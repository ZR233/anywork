//! 机器人占用任务 owner：把改变持久身份占用的写入及其本地绑定接续持有到真实终态。
//!
//! 存在理由：SeaORM 的 `DatabaseTransaction::commit` 只有在拿到底层提交结果后才把
//! `open` 置 false（`sea-orm` `database/transaction.rs`），而 SQLx 的 SQLite worker
//! 在 COMMIT 已执行、回执接收端关闭时用 `ignore_next_start_rollback` 忽略析构排队的
//! 回滚（`sqlx-sqlite` `connection/worker.rs`）。因此调用方 future 在等待提交期间被丢弃
//! 时，行可能已经持久存在，而调用方再也不会运行任何后续代码。把占用写入放进由本 owner
//! 持有、不可被调用方取消的任务，提交结果才会被真实观察，并在任务终态请求重建发布。
//!
//! 本集合只持有任务所有权与预算。能力可变性仍由 `owner::snapshot_managed` 从 SQLite
//! 读取，这里不保存任何能力缓存，也不参与业务判断。

use super::owner::BotRuntime;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use std::future::Future;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::{Mutex, OwnedSemaphorePermit, Semaphore, oneshot};
use tokio::task::JoinSet;

/// 同时存在的占用任务上限，覆盖等待登记与执行中的任务。
pub(crate) const OCCUPANCY_TASK_LIMIT: usize = 32;
/// owner 额外冻结文本的并发总预算（UTF-8 字节）。它不是进程内存上限，也不代表任意
/// 合法 FRB/配置请求必然放得下；只限制本 owner 允许同时冻结的材料。
pub(crate) const OCCUPANCY_TEXT_BYTES: usize = 64 * 1024 * 1024;

pub(crate) struct OccupancyTasks {
    tasks: Mutex<JoinSet<()>>,
    slots: Arc<Semaphore>,
    text: Arc<Semaphore>,
    /// 已观察到的任务资源异常事实。取出 `JoinError` 的当刻写入，保留到排空并完成真实
    /// 发布之后才消费；中途取消或后继等待都不能抹掉。
    abnormal: AtomicBool,
}

/// 一个受管任务持有的预算：注册时取得的 permit，加上任务内按需追加的受检文本额度。
/// 只服务本 owner 的计权，不是通用资源框架。
pub(crate) struct OccupancyBudget {
    text: Arc<Semaphore>,
    /// 任务序号 permit：只为生命周期持有，任务终态自动归还。
    _slot: Option<OwnedSemaphorePermit>,
    text_permit: Option<OwnedSemaphorePermit>,
    held: usize,
}

impl OccupancyBudget {
    /// 追加受检文本额度。单操作总量放不下（含溢出）⇒ 不可重试资源错误；
    /// 仅因并发暂满 ⇒ 可重试背压。调用点都在首次持久写之前或写入前已确定的字段上。
    pub(crate) fn reserve_more(&mut self, extra: usize) -> Result<(), FeishuError> {
        if extra == 0 {
            return Ok(());
        }
        let total = self
            .held
            .checked_add(extra)
            .ok_or_else(freeze_budget_error)?;
        if total > OCCUPANCY_TEXT_BYTES {
            return Err(freeze_budget_error());
        }
        let Ok(added) = u32::try_from(extra) else {
            return Err(freeze_budget_error());
        };
        let Ok(permit) = self.text.clone().try_acquire_many_owned(added) else {
            return Err(capacity_error());
        };
        match self.text_permit.take() {
            Some(mut current) => {
                current.merge(permit);
                self.text_permit = Some(current);
            }
            None => self.text_permit = Some(permit),
        }
        self.held = total;
        Ok(())
    }
}

impl OccupancyTasks {
    pub(crate) fn new() -> Self {
        Self {
            tasks: Mutex::new(JoinSet::new()),
            slots: Arc::new(Semaphore::new(OCCUPANCY_TASK_LIMIT)),
            text: Arc::new(Semaphore::new(OCCUPANCY_TEXT_BYTES)),
            abnormal: AtomicBool::new(false),
        }
    }

    /// 在 registry 短锁内登记任务：预算在等锁之前取得，封口在等锁之前快拒、持锁后再核，
    /// 与 [`Self::drain`] 共用同一封口边界。返回的接收端由调用方在锁外等待。
    ///
    /// `text_bytes` 是调用方在首次持久写之前冻结的全部必要文本上界；单项本身放不进
    /// 总预算时属于不可重试的资源错误，不能混同“并发暂满”的可重试背压。
    pub(crate) async fn register<T, F, Fut>(
        &self,
        runtime: &BotRuntime,
        text_bytes: u32,
        work: F,
    ) -> Result<oneshot::Receiver<Result<T, FeishuError>>, FeishuError>
    where
        T: Send + 'static,
        F: FnOnce(OccupancyBudget) -> Fut + Send + 'static,
        Fut: Future<Output = Result<T, FeishuError>> + Send + 'static,
    {
        if runtime.inner.sealed.load(Ordering::SeqCst) != 0 {
            return Err(sealed_error());
        }
        if text_bytes as usize > OCCUPANCY_TEXT_BYTES {
            return Err(freeze_budget_error());
        }
        // 预算覆盖等待登记：permit 随任务终态归还；未登记就返回时由作用域归还。
        let Ok(slot) = self.slots.clone().try_acquire_owned() else {
            return Err(capacity_error());
        };
        let Ok(bytes) = self.text.clone().try_acquire_many_owned(text_bytes) else {
            return Err(capacity_error());
        };
        let (done, result) = oneshot::channel();
        let worker = runtime.clone();
        let mut tasks = self.tasks.lock().await;
        if runtime.inner.sealed.load(Ordering::SeqCst) != 0 {
            return Err(sealed_error());
        }
        reap_finished(&mut tasks, &self.abnormal);
        let text = self.text.clone();
        let held = text_bytes as usize;
        tasks.spawn(async move {
            // permit 是真实绑定：随任务终态归还，调用方离开不影响。
            let budget = OccupancyBudget {
                text,
                _slot: Some(slot),
                text_permit: Some(bytes),
                held,
            };
            // 任务内 guard：正常结束与 panic 展开都会请求一次按真库重建。
            // 它只保证本任务离开时发起重建，不证明数据库 offload 已结束。
            let _publish = PublishOnExit(worker);
            let outcome = work(budget).await;
            // 调用方已离开时发送失败：落盘与发布责任由本任务完成，
            // 既不把“没人等回执”当成功，也不因此丢弃已完成的写入事实。
            let _ = done.send(outcome);
        });
        Ok(result)
    }

    /// 收束所有在途占用任务。集合始终留在 owner 内：把它取出到局部再等待，
    /// 关闭 future 被取消时会连同句柄一起丢失。这里的锁是关闭封口边界，
    /// 持锁期间只有任务收束、没有登记；被取消时 guard 释放锁而句柄仍在 owner 中，
    /// 可由下一次关闭接续。
    pub(crate) async fn drain(&self) {
        let mut tasks = self.tasks.lock().await;
        while let Some(joined) = tasks.join_next().await {
            // 取出当刻即落 owner 持久事实：后续等待其他句柄、发布或取消都抹不掉。
            if joined.is_err() {
                self.abnormal.store(true, Ordering::SeqCst);
                tracing::warn!("a bot occupancy task terminated abnormally");
            }
        }
    }

    /// 排空并完成真实发布之后消费一次异常事实。调用点在发布之后没有额外 await，
    /// 因此不会出现“先抹掉错误再等 I/O”的窗口。
    fn take_abnormal(&self) -> Result<(), FeishuError> {
        if self.abnormal.swap(false, Ordering::SeqCst) {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot occupancy task terminated abnormally",
                true,
                None,
            ));
        }
        Ok(())
    }
}

/// 已终态句柄只在这里回收一次。失败只留安全的固定诊断，
/// 不把 panic 原文或请求内容写进日志与诊断。
fn reap_finished(tasks: &mut JoinSet<()>, abnormal: &AtomicBool) {
    while let Some(joined) = tasks.try_join_next() {
        if joined.is_err() {
            abnormal.store(true, Ordering::SeqCst);
            tracing::warn!("a finished bot occupancy task terminated abnormally");
        }
    }
}

struct PublishOnExit(BotRuntime);

impl Drop for PublishOnExit {
    fn drop(&mut self) {
        self.0.request_publish();
    }
}

fn sealed_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot runtime is sealed",
        true,
        None,
    )
}

/// 暂时没有容量：安全背压，调用方可重试。
fn capacity_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot occupancy budget is full",
        true,
        None,
    )
}

/// 单项无法放入冻结总预算或计权溢出：首次持久写前的资源错误，提示本机调整材料。
pub(crate) fn freeze_budget_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot occupancy freeze budget cannot hold the required input; reduce local material and retry",
        false,
        None,
    )
}

/// 冻结文本计权：按“字段 UTF-8 字节 × 该任务内同时存活的 owned 副本峰值”受检求和。
///
/// 副本峰值由调用方按真实阶段列明：冻结结构本身、操作记录副本、Studio 交回的身份，
/// 以及 `storage` 用 `.clone()/.to_string()` 构造、与原值同时跨 await 存活的 SQL 参数。
/// 这是本 owner 自己的领域计权，不是通用内存框架，也不代表进程总内存上限。
pub(crate) fn counted_text_bytes<'a>(
    fields: impl IntoIterator<Item = (&'a str, usize)>,
) -> Result<usize, FeishuError> {
    counted_extra_bytes(
        0,
        fields
            .into_iter()
            .map(|(field, copies)| (field.len(), copies)),
    )
}

/// 在已有计权上追加派生材料（`(字节, 副本数)`）的受检求和；溢出即视为放不下。
pub(crate) fn counted_extra_bytes(
    base: usize,
    items: impl IntoIterator<Item = (usize, usize)>,
) -> Result<usize, FeishuError> {
    let mut total = base;
    for (bytes, copies) in items {
        let weighted = bytes.checked_mul(copies).ok_or_else(freeze_budget_error)?;
        total = total
            .checked_add(weighted)
            .ok_or_else(freeze_budget_error)?;
    }
    Ok(total)
}

impl BotRuntime {
    /// 提交一个占用任务并等待其业务结果。调用方被取消只是不再等待回执，
    /// 已受理的事务与其本地接续仍由本 owner 完成。
    pub(crate) async fn submit_occupancy<T, F, Fut>(
        &self,
        text_bytes: usize,
        work: F,
    ) -> Result<T, FeishuError>
    where
        T: Send + 'static,
        F: FnOnce(OccupancyBudget) -> Fut + Send + 'static,
        Fut: Future<Output = Result<T, FeishuError>> + Send + 'static,
    {
        if text_bytes > OCCUPANCY_TEXT_BYTES {
            return Err(freeze_budget_error());
        }
        let Ok(text_bytes) = u32::try_from(text_bytes) else {
            return Err(freeze_budget_error());
        };
        let result = self
            .inner
            .occupancy
            .register(self, text_bytes, work)
            .await?;
        result.await.unwrap_or_else(|_| {
            Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot occupancy task ended without a result",
                true,
                None,
            ))
        })
    }

    /// 关闭时先收束占用任务，再经既有 `publish_gate` 做一次真实重建发布，
    /// 最后无额外等待地消费异常事实。不依赖关闭末尾的发布：
    /// 中间关闭步骤失败会提前返回。
    pub(crate) async fn drain_occupancy(&self) -> Result<(), FeishuError> {
        self.inner.occupancy.drain().await;
        self.publish().await;
        self.inner.occupancy.take_abnormal()
    }
}
