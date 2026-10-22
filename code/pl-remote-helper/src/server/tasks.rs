//! 连接拥有的阻塞任务边界。
//!
//! 所有不可取消的阻塞阶段（目录遍历/创建/删除/重命名/复制、上传暂存与原子发布、文件 sync）
//! 都提交到这里：唯一监督任务用 `JoinSet` 真实 join 每个任务，任务结束立即从集合移除；调用方
//! 取消只会丢失去结果的权利，系统调用仍由本 owner 等到真实终态。连接结束封准入后必须等监督
//! 任务返回，才允许宣称清理完成；任务的 `JoinError`（panic）与任务自报的清理失败都归档为
//! helper 层面失败，并通过持久的 [`BlockingTasks::failed`] 通知让连接 owner **主动**结束连接：
//! 归档不是留到未来 shutdown 才读的缓存，否则 publish panic 会带着未清理的暂存区把连接留在
//! 健康态。
//!
//! # 受理预算（为什么这里是无界通道）
//!
//! 递交通道只承载「已经存在的调用者要让 owner 代持一次阻塞调用」，不是业务载荷队列：
//! 每个 `run()` 调用者持有恰好一次在途递交（提交后立刻 await 结果），递交者数量由连接的
//! 物理预算决定——最多 [`crate::remote_transport::OPERATION_STREAMS`] 个操作任务，加上每个
//! 已登记进程自己的 job（进程同样占一条操作流），因此队列长度是「并发操作数」的线性上界，
//! 与文件/目录大小无关；文件正文、目录条目和记录字节都不进入这里（job 不承载文件正文，
//! 只携带路径、[`cap_std::fs::Dir`] 能力等操作状态）。
//! 收束语义：`close_and_wait` 先 `jobs.close()` 封闭**新工作**，再排空并 join 已受理的工作；
//! 已经受理的递交永远由 owner 裁决到真实终态，不会因为封闭而被拒绝或静默丢弃。
//!
//! # 析构清理（兜底通道）
//!
//! 正常的上传失败（非法 offset、超长正文、记录损坏、写错误、提前 EOF、长度不符、sync 失败）
//! 由 `write_file` 在**返回前显式 `await` 暂存清理**，操作流一直持到删除真实结束，因此健康期
//! 不会留下「已部分写盘的暂存目录 + 删除闭包」的历史。
//!
//! [`BlockingTasks::retire`] 只是整条连接被 abort、或结果接收者已被取消时的兜底：那些 `Drop`
//! 可能发生在 tokio 工作线程，所以只做 O(1) 登记、不做任何 IO、不 detach 任务。收尾时监督任务
//! 在 join 完所有工作后统一执行这些兜底清理（阻塞池 + 真实 join + 失败归档）；登记在封闭之后
//! 仍然受理，不会被 `jobs.close()` 遗失，且清理闭包不再递交新 job，因此不会递归产生无界工作。

use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use pl_protocol::remote::{RemoteError, RemoteErrorCode};
use tokio::sync::{mpsc, oneshot, watch};
use tokio::task::{JoinHandle, JoinSet};

use super::path::remote_error;

type Job = Pin<Box<dyn Future<Output = ()> + Send + 'static>>;

/// 必须在阻塞上下文执行的一次性清理（通常是删除资源）；只由 [`BlockingTasks::retire`] 登记。
type Cleanup = Box<dyn FnOnce() -> Result<(), RemoteError> + Send + 'static>;

/// 连接级阻塞任务 owner；克隆只共享登记状态。
#[derive(Clone)]
pub(super) struct BlockingTasks {
    inner: Arc<Inner>,
}

struct Inner {
    submit: mpsc::UnboundedSender<Job>,
    closing: watch::Sender<bool>,
    retired: Arc<Mutex<Vec<Cleanup>>>,
    supervisor: Mutex<Option<JoinHandle<Result<(), RemoteError>>>>,
    /// 第一个 helper 层面失败（panic/清理失败）；持久值，owner 可随时观察。
    failure: watch::Sender<Option<RemoteError>>,
}

impl BlockingTasks {
    /// 由连接创建；监督任务随 owner 一起启动，独占全部阻塞任务的 join。
    pub(super) fn new() -> Self {
        let (submit, incoming) = mpsc::unbounded_channel();
        let (closing, closed) = watch::channel(false);
        let (failure, _) = watch::channel(None);
        let retired = Arc::new(Mutex::new(Vec::new()));
        // guard 在 spawn 之前构造并移入任务体：任务被 panic/取消时它会发布失败通知。
        let guard = SupervisorGuard::new(failure.clone(), SUPERVISOR_FAILED);
        let supervisor = tokio::spawn(supervise(incoming, closed, Arc::clone(&retired), guard));
        Self {
            inner: Arc::new(Inner {
                submit,
                closing,
                retired,
                supervisor: Mutex::new(Some(supervisor)),
                failure,
            }),
        }
    }

    /// 提交一个阻塞调用并等待结果。
    ///
    /// 调用方被取消时任务仍在册，由连接终态等待它真实退出；因此取消不会让已开始的系统调用
    /// 逃出清理责任，也不会在无人观察时“偷偷完成一半”。
    pub(super) async fn run<T, F>(&self, work: F) -> Result<T, RemoteError>
    where
        F: FnOnce() -> Result<T, RemoteError> + Send + 'static,
        T: Send + 'static,
    {
        let (sender, outcome) = oneshot::channel();
        let reporter = self.clone();
        let job: Job = Box::pin(async move {
            let result = tokio::task::spawn_blocking(work).await;
            // 调用方可能已经取消（等待者消失）：任务自身的异常结束必须由 owner 归档，
            // 不能只靠回传结果，否则 panic 会被一次成功的连接收尾掩盖。
            if let Err(error) = &result {
                reporter.report_failure(abnormal(error));
            }
            let _ = sender.send(result);
        });
        // 交接与关闭互斥：要么本任务进入监督任务可排空的队列，要么立即得到关闭错误，
        // 不存在“已受理却无人执行”的中间状态。
        self.inner.submit.send(job).map_err(|_| closing())?;
        match outcome.await {
            Ok(Ok(result)) => result,
            // 阻塞任务 panic 或被 runtime 取消：结果未知，必须作为失败上报。
            Ok(Err(error)) => Err(abnormal(&error)),
            Err(_) => Err(remote_error(
                RemoteErrorCode::Io,
                "blocking filesystem task lost its result",
            )),
        }
    }

    /// 记录一次无法随返回值交回的 helper 层面失败（任务 panic、兜底清理失败）。
    ///
    /// 写入持久的 watch 值（保留第一条），等待中的连接 owner 会立即被唤醒并结束连接；普通业务
    /// 错误不经过这里，仍是操作级 `RemoteError`。
    pub(super) fn report_failure(&self, error: RemoteError) {
        publish_failure(&self.inner.failure, error);
    }

    /// 等待第一次 helper 层面失败；owner 用它主动结束连接并走统一收尾。
    ///
    /// 值持久保留，因此「先失败、后开始等待」也不会错过；连接正常时该 future 永不完成。
    pub(super) async fn failed(&self) -> RemoteError {
        let mut failures = self.inner.failure.subscribe();
        loop {
            let observed = failures.borrow_and_update().as_ref().cloned();
            if let Some(error) = observed {
                return error;
            }
            if failures.changed().await.is_err() {
                // owner 已释放：不会再有新的失败可观察，连接本身会在别处结束。
                std::future::pending::<()>().await;
            }
        }
    }

    /// 兜底移交一次只能在阻塞上下文执行的清理（正常失败路径已在返回前显式清理）。
    ///
    /// 只有整条连接被 abort、或结果接收者已被取消时才会走到这里，因此这里只登记、不做任何
    /// IO：调用点可能位于 tokio 工作线程，同步删除目录会阻塞运行时。登记在封闭之后仍然受理，
    /// 由连接收尾的最终 drain 在阻塞池里执行并 join。
    pub(super) fn retire(&self, cleanup: Cleanup) {
        self.retired().push(cleanup);
    }

    /// 封准入并等待全部在册阻塞任务真实结束，返回归档的失败。
    ///
    /// 等待包含两部分真实终态：已受理的工作任务，以及它们（和已被取消的调用方）析构时移交的
    /// 阻塞清理。调用方必须在所有提交者（操作任务、进程 job）都结束后再调用，因此之后不会再有
    /// 新的工作递交；清理登记仍然受理，避免「结果接收者被取消后才 drop」的资源逃出责任。
    pub(super) async fn close_and_wait(&self) -> Result<(), RemoteError> {
        self.inner.closing.send_replace(true);
        let supervisor = self
            .inner
            .supervisor
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .take();
        let supervised = match supervisor {
            Some(supervisor) => match supervisor.await {
                Ok(result) => result,
                Err(error) => Err(remote_error(
                    RemoteErrorCode::Io,
                    format!("blocking task supervisor ended abnormally: {error}"),
                )),
            },
            // 已经等待过一次真实终态。
            None => Ok(()),
        };
        let recorded = self.inner.failure.borrow().as_ref().cloned();
        match (supervised, recorded) {
            (Err(error), _) => Err(error),
            (Ok(()), Some(error)) => Err(error),
            (Ok(()), None) => Ok(()),
        }
    }

    fn retired(&self) -> MutexGuard<'_, Vec<Cleanup>> {
        self.inner
            .retired
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
    }
}

/// 唯一 job owner：持续 join 已受理的工作，并在关闭后 drain 到全部真实结束。
async fn supervise(
    mut jobs: mpsc::UnboundedReceiver<Job>,
    mut closing: watch::Receiver<bool>,
    retired: Arc<Mutex<Vec<Cleanup>>>,
    guard: SupervisorGuard,
) -> Result<(), RemoteError> {
    let mut running = JoinSet::new();
    let mut failure = None;
    loop {
        tokio::select! {
            biased;
            _ = closing.wait_for(|closing| *closing) => {
                // 先封闭队列再排空：之后提交会立即得到关闭错误，已受理的必须执行并 join 到
                // 真实终态。
                jobs.close();
                while let Ok(job) = jobs.try_recv() {
                    running.spawn(job);
                }
                break;
            }
            // 先回收已完成的在册任务，再接收新工作：连续就绪的业务输入不能饿死 join，
            // 否则已结束任务的条目（及其捕获的资源）会无限堆积。已完成集合本身有限，
            // 不接收新工作就不会无限产生。
            Some(result) = running.join_next(), if !running.is_empty() => {
                observe(result, &mut failure);
            }
            job = jobs.recv() => match job {
                Some(job) => {
                    running.spawn(job);
                }
                None => break,
            },
        }
    }
    // 队列为空不等于阻塞调用已结束：必须 join 到每个在册工作真实返回。
    while let Some(result) = running.join_next().await {
        observe(result, &mut failure);
    }
    // 全部工作结束后执行兜底退役清理（正常失败已在操作内显式清理）。清理本身不再递交新
    // 工作，因此这个 drain 只会被「登记过的兜底」推进；迟到的登记在下一轮取到。
    let mut cleanups: Vec<JoinHandle<Result<(), RemoteError>>> = Vec::new();
    loop {
        let batch = take_retired(&retired);
        if batch.is_empty() && cleanups.is_empty() {
            break;
        }
        for cleanup in batch {
            cleanups.push(tokio::task::spawn_blocking(cleanup));
        }
        for handle in cleanups.drain(..) {
            match handle.await {
                Ok(Ok(())) => {}
                Ok(Err(error)) => {
                    failure.get_or_insert(error);
                }
                Err(error) => {
                    failure.get_or_insert(abnormal(&error));
                }
            }
        }
    }
    // 走到这里说明本任务按设计收完了全部工作与兜底清理：撤销「未正常结束」通知责任，
    // 真实终态由 `close_and_wait` 观察 `JoinHandle` 结果。
    guard.disarm();
    match failure {
        Some(error) => Err(error),
        None => Ok(()),
    }
}

fn observe(result: Result<(), tokio::task::JoinError>, failure: &mut Option<RemoteError>) {
    if let Err(error) = result {
        failure.get_or_insert_with(|| abnormal(&error));
    }
}

/// 监督任务未正常结束时的失败文案（`process` 的 supervisor 复用同名 guard）。
pub(super) const SUPERVISOR_FAILED: &str = "blocking task supervisor ended without finishing";

/// 写入持久失败通知（保留第一条），等待中的连接 owner 会立即被唤醒并主动收尾。
pub(super) fn publish_failure(failure: &watch::Sender<Option<RemoteError>>, error: RemoteError) {
    let _ = failure.send_if_modified(|slot| {
        if slot.is_some() {
            return false;
        }
        *slot = Some(error);
        true
    });
}

/// 监督任务自身的终态守卫。
///
/// 在 spawn **之前**构造并移入任务体：任务正常结束（含预期关闭与 owner 触发的收束）必须
/// [`SupervisorGuard::disarm`]；否则（panic、被取消、被 abort）`Drop` 会发布「supervisor 未
/// 正常结束」，让连接 owner 主动收尾，而不是等到未来的 shutdown 才发现没人回收。守卫只发
/// 通知，**不伪造任何 join 结果**：真实终态仍由各 owner 观察自己的 `JoinHandle`。
pub(super) struct SupervisorGuard {
    failure: watch::Sender<Option<RemoteError>>,
    message: &'static str,
    armed: bool,
}

impl SupervisorGuard {
    pub(super) fn new(failure: watch::Sender<Option<RemoteError>>, message: &'static str) -> Self {
        Self {
            failure,
            message,
            armed: true,
        }
    }

    /// 监督任务按设计结束：撤销通知责任。
    pub(super) fn disarm(mut self) {
        self.armed = false;
    }
}

impl Drop for SupervisorGuard {
    fn drop(&mut self) {
        if !self.armed {
            return;
        }
        publish_failure(
            &self.failure,
            remote_error(RemoteErrorCode::Io, self.message),
        );
    }
}

fn take_retired(retired: &Mutex<Vec<Cleanup>>) -> Vec<Cleanup> {
    std::mem::take(&mut *retired.lock().unwrap_or_else(PoisonError::into_inner))
}

fn abnormal(error: &tokio::task::JoinError) -> RemoteError {
    remote_error(
        RemoteErrorCode::Io,
        format!("blocking filesystem task ended abnormally: {error}"),
    )
}

fn closing() -> RemoteError {
    remote_error(
        RemoteErrorCode::RemoteDisconnected,
        "remote helper is closing",
    )
}
