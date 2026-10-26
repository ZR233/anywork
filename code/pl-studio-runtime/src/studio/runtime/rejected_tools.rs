//! Owns failed candidate closures across refresh retries and cancelled shutdown waiters.
//!
//! 一份 rejected 资源或一次 retire/reconfigure 交接只登记一次，并由本 owner 独占：
//!
//! - 被取消的 waiter 把在途交接（[`Resources::Retiring`]）或原始 rejected 批次
//!   （[`Resources::Rejected`]）留在登记项上，`retry`/停机继续 join 同一次交接，迟到的
//!   `RejectedTools` 结果仍被收编，绝不重放 core 操作；
//! - [`TransferFailure::Product`] 表示 core 已交接且产品义务已完成或已转交，不得重放 core；
//!   它的诊断与“工具批次自身失败”必须可区分（见 [`RejectedCloseSource`]）。

use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_core::{
    thread::{IdleReconfiguration, ThreadError, ThreadHandle, ThreadSnapshot},
    tool::opaque::{Registration, RejectedTools, ToolError},
};
use std::sync::{
    Arc, Mutex, Weak,
    atomic::{AtomicBool, Ordering},
};

#[derive(Clone, Default)]
pub(super) struct RejectedToolOwners {
    entries: Arc<Mutex<Vec<Arc<Entry>>>>,
    stop: Arc<Mutex<tokio_util::sync::CancellationToken>>,
}

struct Entry {
    thread: ThreadHandle,
    /// 交接的操作身份；诊断必须能说明是哪一次 retire/reconfigure 失败。
    operation: Option<String>,
    gate: tokio::sync::Mutex<()>,
    resources: Mutex<Option<Resources>>,
    /// 最近一次真实失败的原始见证；重试授予按“是否仍是同一次失败”判定。
    failure: Mutex<Option<RejectedCloseSource>>,
    /// 每个批次唯一的共享收束句柄；只持有 `Weak` 回边。
    wait: Mutex<Option<RejectedWait>>,
    completed: AtomicBool,
    /// 资源槽已空且没有可续用的等待：不得据此伪报完成。
    resources_missing: AtomicBool,
}

/// 本 owner 独占的一份可重试资源。
enum Resources {
    /// 原始 rejected 批次：只由 `retry_close` 收束。
    Rejected(Box<RejectedTools>),
    /// 已 spawn 的 core→产品交接。被取消的 waiter 仍把句柄留在登记项上，可继续 join。
    Retiring(tokio::task::JoinHandle<Result<(), TransferFailure>>),
}

#[derive(Debug)]
enum TransferFailure {
    Core(ThreadError),
    // The product has already transferred any remaining persistence/recovery obligation to its
    // existing owners before returning this resource-free error. Core must not be replayed.
    Product(anyhow::Error),
}

struct Lease {
    entry: Weak<Entry>,
    resources: Option<Resources>,
}
impl Drop for Lease {
    fn drop(&mut self) {
        if let Some(resources) = self.resources.take()
            && let Some(entry) = self.entry.upgrade()
        {
            let retired = entry
                .resources
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .replace(resources);
            drop(retired);
        }
    }
}

/// 一次收束失败的来源。
///
/// 工具批次自身的失败（[`Self::Tool`]）与 core/产品交接失败（[`Self::Transfer`]）在诊断上必须
/// 可区分：交接失败绝不报成工具失败，产品未完成也绝不报成已回收。
#[derive(Debug, Clone)]
pub(in crate::studio::runtime) enum RejectedCloseSource {
    /// 原始 `RejectedTools::retry_close` 的失败，即工具执行事实。
    Tool(Arc<ToolError>),
    /// retire/reconfigure 交接失败：core 拒绝、产品未完成或交接任务本身未收束。
    Transfer(Arc<TransferDiagnostic>),
}

impl RejectedCloseSource {
    /// 是否仍是同一次失败见证：重试授予只按身份，不按本轮新观察到的失败。
    fn same_occurrence(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Tool(left), Self::Tool(right)) => Arc::ptr_eq(left, right),
            (Self::Transfer(left), Self::Transfer(right)) => Arc::ptr_eq(left, right),
            // A tool-batch failure and a handoff failure are never the same occurrence.
            (Self::Tool(_), Self::Transfer(_)) | (Self::Transfer(_), Self::Tool(_)) => false,
        }
    }

    /// The exact witness this source keeps in the std source chain.
    ///
    /// A tool failure stays `Arc<ToolError>` so the existing `ToolRefresh` retry grant
    /// (`error.chain().any(|source| source.is::<Arc<ToolError>>())`) keeps matching only real
    /// tool-batch failures. A transfer failure is `Arc<TransferDiagnostic>`, which never matches
    /// that grant: core/product handoff failures are not tool `close` failures.
    fn as_error(&self) -> &(dyn std::error::Error + 'static) {
        match self {
            Self::Tool(error) => error as &(dyn std::error::Error + 'static),
            Self::Transfer(error) => error as &(dyn std::error::Error + 'static),
        }
    }
}

/// retire/reconfigure 交接的类型化诊断。
///
/// 文本按来源区分三种失败：core 拒绝交接（含原始注册拒绝）、产品完成失败（core 已生效且不得
/// 重放）、交接任务未收束。三者都不代表工具 `close` 本身失败。
#[derive(Debug)]
pub(in crate::studio::runtime) struct TransferDiagnostic {
    message: String,
}

impl TransferDiagnostic {
    fn core_rejected(operation: Option<&str>, cleanup: String, rejection: Option<String>) -> Self {
        Self {
            message: format!(
                "tool candidate retirement was rejected by core ({cleanup}); operation: {operation:?}; original refusal: {rejection:?}"
            ),
        }
    }

    fn core(operation: Option<&str>, error: &ThreadError) -> Self {
        Self {
            message: format!(
                "tool candidate transfer failed in core ({error}); operation: {operation:?}"
            ),
        }
    }

    fn product(operation: Option<&str>, error: &anyhow::Error) -> Self {
        Self {
            message: format!(
                "product completion failed after the completed core handoff ({error:#}); core must not be replayed; operation: {operation:?}"
            ),
        }
    }

    fn task(operation: Option<&str>, error: &tokio::task::JoinError) -> Self {
        Self {
            message: format!(
                "tool candidate transfer task did not settle ({error}); operation: {operation:?}"
            ),
        }
    }
}

impl std::fmt::Display for TransferDiagnostic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for TransferDiagnostic {}

type RejectedWait = Shared<BoxFuture<'static, Result<(), RejectedCloseSource>>>;

#[derive(Debug, Clone)]
pub(in crate::studio::runtime) struct RejectedToolCloseIssue {
    pub(in crate::studio::runtime) batch: usize,
    pub(in crate::studio::runtime) source: Option<RejectedCloseSource>,
    #[allow(dead_code)] // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
    pub(in crate::studio::runtime) resources_missing: bool,
}

/// A failed close retains the exact batches, not a later lookup by Thread ID.
#[derive(Clone)]
pub(crate) struct RejectedToolsCloseFailure {
    owner: RejectedToolOwners,
    entries: Vec<Arc<Entry>>,
    pub(in crate::studio::runtime) issues: Vec<RejectedToolCloseIssue>,
}
impl std::fmt::Debug for RejectedToolsCloseFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RejectedToolsCloseFailure")
            .field("issues", &self.issues)
            .finish_non_exhaustive()
    }
}
impl std::fmt::Display for RejectedToolsCloseFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("original rejected tool batches still require cleanup")
    }
}
impl std::error::Error for RejectedToolsCloseFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.issues
            .iter()
            .find_map(|issue| issue.source.as_ref().map(|source| source.as_error() as _))
    }
}

// Keep the existing anyhow return/boxed consumers. Its std source chain includes the concrete
// witness even when anyhow's boxed adapter is not directly downcastable to that witness.
#[derive(Debug, thiserror::Error)]
#[error("rejected tool candidate cleanup failed: {0}")]
struct CleanupFailure(#[source] RejectedToolsCloseFailure);

impl RejectedToolsCloseFailure {
    pub(crate) fn matches_thread(&self, thread: &ThreadHandle) -> bool {
        !self.entries.is_empty()
            && self
                .entries
                .iter()
                .all(|entry| entry.thread.same_instance(thread))
    }

    pub(crate) fn original_is_complete(&self) -> bool {
        self.entries
            .iter()
            .all(|entry| entry.completed.load(Ordering::Acquire))
    }

    /// Pure capability of these original batches. An empty resource slot belongs to its retained
    /// accepted wait, never evidence that the batch completed.
    pub(crate) fn can_resume_original(&self) -> bool {
        self.entries.iter().any(|entry| {
            !entry.completed.load(Ordering::Acquire)
                && !entry.resources_missing.load(Ordering::Acquire)
        })
    }

    pub(crate) async fn resume_original(&self) -> Result<(), Self> {
        if !self.can_resume_original() && !self.original_is_complete() {
            return Err(self.clone());
        }
        self.owner
            .close_entries(self.entries.clone(), Some(self))
            .await
    }
}

/// 一次收束驱动的归属判定：决定失败之后资源是否还能被下一次尝试取回。
enum Settled {
    /// 全部收束：资源已被消费，可以从 owner 列表移除。
    Closed,
    /// 失败但资源仍可续用：失败只借用资源、不消费它，因此下一次 `retry`/停机必须仍能取回。
    ///
    /// `handback` 为 `Some` 表示 core 明确把原始批次交还，用它替换当前资源；`None` 表示原样保留
    /// lease 中仍在的同一份资源。
    Retained {
        source: RejectedCloseSource,
        handback: Option<Resources>,
    },
    /// 失败且资源已释放或不可续用（core 已消费资源、产品义务已完成、交接任务已结束）。
    /// 终态：不再重试，也绝不重放 core。
    Terminal { source: RejectedCloseSource },
}

/// Drives one owned resource set to its real outcome without ever taking ownership of it.
///
/// Awaiting through the borrow (instead of moving the resources into this future) is what lets a
/// cancelled waiter put the same in-flight handoff back on its entry. The returned [`Settled`]
/// states explicitly whether the resources stay retrievable afterwards:
///
/// - `RejectedTools::retry_close` is a **borrowing** call whose contract keeps every unfinished
///   owner in the batch (see `pl_core::tool::opaque`). A failed close therefore reports
///   [`Settled::Retained`] without a handback, and the exact same batch stays on the entry, so
///   `can_resume_original()` and `thread_assembler::close_failure` keep granting the original
///   recovery contract instead of dropping owners that still owe a close.
/// - A core-rejected retirement hands the batch back, so it is `Retained` with that batch.
/// - Core/product failures and a failed join are `Terminal`: the transfer consumed the resources,
///   the product already owns its obligations, and a finished `JoinHandle` must never be polled
///   again.
async fn drive(resources: &mut Resources, operation: Option<&str>) -> Settled {
    match resources {
        Resources::Rejected(batch) => match batch.retry_close().await {
            Ok(()) => Settled::Closed,
            // The unfinished owners are still inside `batch`: retain it as-is for the next attempt.
            Err(error) => Settled::Retained {
                source: RejectedCloseSource::Tool(error),
                handback: None,
            },
        },
        Resources::Retiring(task) => match task.await {
            Ok(Ok(())) => Settled::Closed,
            Ok(Err(TransferFailure::Core(ThreadError::RejectedTools(batch)))) => {
                // Core released the handoff and handed the exact original batch back: retain it so
                // the next attempt closes it instead of leaking the owners.
                let cleanup = batch.to_string();
                let rejection = batch.rejection().map(ToString::to_string);
                Settled::Retained {
                    source: RejectedCloseSource::Transfer(Arc::new(
                        TransferDiagnostic::core_rejected(operation, cleanup, rejection),
                    )),
                    handback: Some(Resources::Rejected(batch)),
                }
            }
            Ok(Err(TransferFailure::Core(error))) => Settled::Terminal {
                source: RejectedCloseSource::Transfer(Arc::new(TransferDiagnostic::core(
                    operation, &error,
                ))),
            },
            Ok(Err(TransferFailure::Product(error))) => Settled::Terminal {
                source: RejectedCloseSource::Transfer(Arc::new(TransferDiagnostic::product(
                    operation, &error,
                ))),
            },
            // The owning task ended without a usable outcome: nothing is left to close, and the
            // already-observed handle must not be polled again.
            Err(join) => Settled::Terminal {
                source: RejectedCloseSource::Transfer(Arc::new(TransferDiagnostic::task(
                    operation, &join,
                ))),
            },
        },
    }
}

/// The caller-facing text of one transfer outcome, kept independent of the close bookkeeping.
fn transfer_diagnostic(operation: &str, error: &TransferFailure) -> anyhow::Error {
    match error {
        TransferFailure::Core(ThreadError::RejectedTools(resources)) => anyhow::anyhow!(
            "tool candidate retirement was rejected by core ({resources}); operation: {operation}; original refusal: {:?}",
            resources.rejection().map(ToString::to_string)
        ),
        TransferFailure::Core(error) => {
            anyhow::anyhow!(
                "tool candidate transfer failed in core ({error}); operation: {operation}"
            )
        }
        TransferFailure::Product(error) => anyhow::anyhow!(
            "product completion failed after the completed core handoff ({error:#}); core must not be replayed; operation: {operation}"
        ),
    }
}

impl RejectedToolOwners {
    pub(super) fn start(&self) -> tokio_util::sync::CancellationToken {
        let token = tokio_util::sync::CancellationToken::new();
        *self
            .stop
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = token.clone();
        token
    }
    pub(super) fn stop(&self) {
        self.stop
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .cancel();
    }
    pub(super) fn retain(&self, thread: ThreadHandle, resources: Box<RejectedTools>) {
        self.insert(thread, Resources::Rejected(resources), None);
    }

    /// Owns retirement before its first await. Cancelling the waiter leaves the exact in-flight
    /// transfer registered for retry/shutdown, including a late RejectedTools result.
    pub(super) async fn retire(
        &self,
        thread: ThreadHandle,
        tools: Vec<Registration>,
        operation: String,
    ) -> anyhow::Result<()> {
        let owner = thread.clone();
        self.transfer(thread, operation, async move {
            owner
                .retire_tools(tools)
                .await
                .map_err(TransferFailure::Core)
        })
        .await
    }

    /// Owns both the core handoff and the mandatory product continuation. The continuation must
    /// transfer any unfinished persistence/recovery obligation before returning an error.
    pub(super) async fn reconfigure<T, F, C>(
        &self,
        thread: ThreadHandle,
        update: IdleReconfiguration,
        operation: String,
        complete: F,
    ) -> anyhow::Result<T>
    where
        T: Send + 'static,
        F: FnOnce(ThreadSnapshot) -> C + Send + 'static,
        C: std::future::Future<Output = anyhow::Result<T>> + Send + 'static,
    {
        let owner = thread.clone();
        self.transfer(thread, operation, async move {
            let snapshot = owner
                .reconfigure(update)
                .await
                .map_err(TransferFailure::Core)?;
            complete(snapshot).await.map_err(TransferFailure::Product)
        })
        .await
    }

    async fn transfer<T: Send + 'static>(
        &self,
        thread: ThreadHandle,
        operation: String,
        transfer: impl std::future::Future<Output = Result<T, TransferFailure>> + Send + 'static,
    ) -> anyhow::Result<T> {
        let (completed, result) = tokio::sync::oneshot::channel();
        let transfer_operation = operation.clone();
        let task = tokio::spawn(async move {
            match transfer.await {
                Ok(value) => {
                    // All product obligations are complete (or durably transferred) before this
                    // response. Losing its receiver never discards a post-commit continuation.
                    let _ = completed.send(Ok(value));
                    Ok(())
                }
                Err(error) => {
                    // Another retry waiter can settle the task first. Keep the original outcome
                    // available independently, but leave its resource box in this owned task.
                    let _ = completed.send(Err(transfer_diagnostic(&transfer_operation, &error)));
                    Err(error)
                }
            }
        });
        let entry = self.insert(thread, Resources::Retiring(task), Some(operation));
        // The same close primitive serves retry, shutdown and this handoff: a cancelled waiter
        // keeps the in-flight transfer registered instead of detaching it.
        let settlement = self
            .close_entries(vec![entry], None)
            .await
            .map_err(|failure| anyhow::Error::new(CleanupFailure(failure)));
        match (result.await, settlement) {
            (Ok(Ok(value)), Ok(())) => Ok(value),
            (_, Err(error)) | (Ok(Err(error)), Ok(())) => Err(error),
            (Err(error), Ok(())) => Err(error.into()),
        }
    }

    fn insert(
        &self,
        thread: ThreadHandle,
        resources: Resources,
        operation: Option<String>,
    ) -> Arc<Entry> {
        let entry = Arc::new(Entry {
            thread,
            operation,
            gate: Default::default(),
            resources: Mutex::new(Some(resources)),
            failure: Mutex::new(None),
            wait: Mutex::new(None),
            completed: AtomicBool::new(false),
            resources_missing: AtomicBool::new(false),
        });
        self.entries
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(entry.clone());
        entry
    }

    pub(super) async fn retry(&self, thread: Option<&ThreadHandle>) -> anyhow::Result<()> {
        let entries = self
            .entries
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .iter()
            .filter(|entry| thread.is_none_or(|thread| thread.same_instance(&entry.thread)))
            .cloned()
            .collect();
        self.close_entries(entries, None)
            .await
            .map_err(|failure| anyhow::Error::new(CleanupFailure(failure)))
    }

    fn close_batch(&self, entry: &Arc<Entry>, resources: Resources) -> RejectedWait {
        let operation = entry.operation.clone();
        let entry = Arc::downgrade(entry);
        let owner = Arc::downgrade(&self.entries);
        async move {
            // Only weak back-edges live in the future stored by this Entry. A timeout in tool
            // refresh drops its waiter, not the original accepted tool close, its resources or an
            // in-flight transfer: `Lease::drop` returns exactly what the batch did not consume.
            let mut lease = Lease {
                entry: entry.clone(),
                resources: Some(resources),
            };
            let settled = {
                let resources = lease.resources.as_mut().expect("original batch lease");
                drive(resources, operation.as_deref()).await
            };
            match settled {
                Settled::Closed => {
                    lease.resources = None;
                    if let Some(entry) = entry.upgrade() {
                        entry.completed.store(true, Ordering::Release);
                        let retired = entry
                            .failure
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .take();
                        drop(retired);
                        drop_owner_entry(&owner, &entry);
                    }
                    Ok(())
                }
                Settled::Retained { source, handback } => {
                    // The failed attempt borrowed the resources and consumed nothing, so the exact
                    // same batch (or exactly the batch core handed back) stays on the entry: the
                    // next `retry`/shutdown closes the very same unfinished owners instead of a
                    // reset, a re-created batch or a lost resource slot.
                    if let Some(handback) = handback {
                        lease.resources = Some(handback);
                    }
                    if let Some(entry) = entry.upgrade() {
                        let retired = entry
                            .failure
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .replace(source.clone());
                        drop(retired);
                    }
                    Err(source)
                }
                Settled::Terminal { source } => {
                    // Core/product handoffs already released their resources and a finished join
                    // must never be polled again: the entry is terminal, so the resource slot is
                    // emptied and the entry leaves the owner list without a fake completion.
                    lease.resources = None;
                    if let Some(entry) = entry.upgrade() {
                        entry.resources_missing.store(true, Ordering::Release);
                        let retired = entry
                            .failure
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .replace(source.clone());
                        drop(retired);
                        drop_owner_entry(&owner, &entry);
                    }
                    Err(source)
                }
            }
        }
        .boxed()
        .shared()
    }

    async fn close_entries(
        &self,
        entries: Vec<Arc<Entry>>,
        previous: Option<&RejectedToolsCloseFailure>,
    ) -> Result<(), RejectedToolsCloseFailure> {
        // Capture every raw failure before waiting for any gate. A concurrent cleanup may finish
        // or fail while we wait; a newly observed failure is not this call's retry grant.
        let grants: Vec<_> = entries
            .iter()
            .enumerate()
            .map(|(batch, entry)| match previous {
                Some(previous) => previous
                    .issues
                    .iter()
                    .find(|issue| issue.batch == batch)
                    .and_then(|issue| issue.source.clone()),
                None => entry
                    .failure
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .clone(),
            })
            .collect();
        let outcomes = futures::future::join_all(entries.iter().zip(grants).enumerate().map(
            |(batch, (entry, original))| async move {
                let _permit = entry.gate.lock().await;
                if entry.completed.load(Ordering::Acquire) {
                    return None;
                }
                if entry.resources_missing.load(Ordering::Acquire) {
                    return Some(RejectedToolCloseIssue {
                        batch,
                        source: entry
                            .failure
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .clone(),
                        resources_missing: true,
                    });
                }
                let current = entry
                    .failure
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .clone();
                let same_failure = match (&original, &current) {
                    (None, None) => true,
                    (Some(original), Some(current)) => original.same_occurrence(current),
                    _ => false,
                };
                if !same_failure {
                    return Some(RejectedToolCloseIssue {
                        batch,
                        source: current,
                        resources_missing: false,
                    });
                }
                let existing = entry
                    .wait
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .clone();
                let (wait, retired) = if let Some(wait) = existing
                    && !matches!(wait.peek(), Some(Err(_)))
                {
                    (wait, None)
                } else {
                    let resources = entry
                        .resources
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .take();
                    let Some(resources) = resources else {
                        entry.resources_missing.store(true, Ordering::Release);
                        return Some(RejectedToolCloseIssue {
                            batch,
                            source: current,
                            resources_missing: true,
                        });
                    };
                    let wait = self.close_batch(entry, resources);
                    let retired = entry
                        .wait
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .replace(wait.clone());
                    (wait, retired)
                };
                drop(retired);
                wait.await.err().map(|source| RejectedToolCloseIssue {
                    batch,
                    source: Some(source),
                    resources_missing: false,
                })
            },
        ))
        .await;
        let issues: Vec<_> = outcomes.into_iter().flatten().collect();
        if issues.is_empty() {
            Ok(())
        } else {
            Err(RejectedToolsCloseFailure {
                owner: self.clone(),
                entries,
                issues,
            })
        }
    }
}

/// Removes one settled or terminal entry from the owner list without touching other batches.
fn drop_owner_entry(owner: &Weak<Mutex<Vec<Arc<Entry>>>>, entry: &Arc<Entry>) {
    let retired = owner.upgrade().and_then(|owner| {
        let mut all = owner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        all.iter()
            .position(|current| Arc::ptr_eq(current, entry))
            .map(|index| all.remove(index))
    });
    drop(retired);
}
