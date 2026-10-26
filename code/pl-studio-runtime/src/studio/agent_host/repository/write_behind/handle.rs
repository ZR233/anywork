//! write-behind 队列与后台 writer task 的共享状态及对外句柄。

use std::collections::VecDeque;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

use futures::FutureExt;
use tokio::sync::{Notify, oneshot, watch};

use crate::studio::store::directory::DirectoryDelta;
use crate::studio::{PersistenceState, PersistenceStateSnapshot, StudioStore};

use super::failure::{
    WriteBehindCause, WriteBehindFlushFailure, WriteBehindFlushFailureKind,
    WriteBehindRetryFailure, WriteBehindRetryFailureKind, WriteBehindShutdownFailure,
    WriteBehindShutdownIssue, WriteBehindTaskState,
};
use super::queue::{QueuedMutation, queue_directory, queue_worktree_lease, try_coalesce_directory};
use super::state::{WriterHealth, update_healthy_state};
use super::task::{ShutdownObservation, SupervisorLifecycle, SupervisorTask};

pub(super) struct WriterShared {
    pub(super) identity: Arc<()>,
    pub(super) store: StudioStore,
    pub(super) queue: Mutex<VecDeque<QueuedMutation>>,
    /// 已从 queue 取出、但尚未 durable 的 typed mutation 副本。
    ///
    /// worker panic 时 supervisor 把它原序放回 queue；热状态从不依赖 worker
    /// 局部变量保存唯一一份待写事实。
    pub(super) inflight: Mutex<VecDeque<QueuedMutation>>,
    /// 入队方唤醒 writer。
    pub(super) work_notify: Notify,
    /// 单调受理 ticket；每次入队 `fetch_add(1)`。
    pub(super) admitted_ticket: AtomicU64,
    /// 已 durable 的最高连续 ticket；只在批次成功提交后前进。
    pub(super) durable_ticket: watch::Sender<u64>,
    /// 任一 owner 的耐久修订推进时发布，供精确屏障等待。
    pub(super) durable_progress: watch::Sender<u64>,
    pub(super) state: watch::Sender<WriterHealth>,
    pub(super) retry_notify: Notify,
    pub(super) stopping: AtomicBool,
    /// 正在等待固定 ticket 的显式 flush 请求数。
    ///
    /// 大于 0 时 writer 跳过空闲批量去抖、立即取批落库；等待方在开始等待前先自增再唤醒
    /// writer，返回或取消时由 guard 自减，因此没有任何人等待时后台写入仍按
    /// `FLUSH_INTERVAL` 合并。
    pub(super) flush_waiters: AtomicUsize,
}

/// 一次显式固定 ticket 等待的登记。
///
/// drop 时撤销请求：等待方返回或整个 future 被取消（例如观察 worker 被 abort）后，
/// writer 立刻恢复空闲去抖，不会因为遗留计数而永久按“有人等待”处理后台写入。
struct PendingFlushRequest<'a> {
    shared: &'a WriterShared,
}

impl Drop for PendingFlushRequest<'_> {
    fn drop(&mut self) {
        self.shared.flush_waiters.fetch_sub(1, Ordering::AcqRel);
    }
}

/// write-behind 队列与后台 writer task 的共享句柄。
///
/// task 惰性首启于 enqueue 或具名显式恢复；flush 只观察原任务与固定 ticket。
/// `shutdown` 排空队列并等待 task 退出。clone 共享同一队列与 task。
#[derive(Clone)]
pub(in crate::studio) struct ThreadWriteBehindWriter {
    shared: Arc<WriterShared>,
    lifecycle: Arc<Mutex<SupervisorLifecycle>>,
    pending_commits: Arc<AtomicUsize>,
}

struct WriterObservation {
    health: WriterHealth,
    task: Option<Arc<SupervisorTask>>,
    executor: WriteBehindTaskState,
    completion: Option<Result<(), Arc<WriteBehindCause>>>,
    progress_error: Option<Arc<WriteBehindCause>>,
}

impl WriterObservation {
    fn owns_health(&self) -> bool {
        self.health.task.as_ref().is_none_or(|identity| {
            self.task
                .as_ref()
                .is_some_and(|task| Arc::ptr_eq(identity, &task.identity))
        })
    }
}

enum RetryDecision {
    Changed,
    Notify,
    Start(oneshot::Sender<()>),
    Done,
    Failed(WriteBehindRetryFailure),
}

impl ThreadWriteBehindWriter {
    pub(in crate::studio) fn new(store: StudioStore) -> Self {
        let (durable_ticket, _) = watch::channel(0u64);
        let (durable_progress, _) = watch::channel(0u64);
        let (state, _) = watch::channel(WriterHealth::default());
        Self {
            shared: Arc::new(WriterShared {
                identity: Arc::new(()),
                store,
                queue: Mutex::new(VecDeque::new()),
                inflight: Mutex::new(VecDeque::new()),
                work_notify: Notify::new(),
                admitted_ticket: AtomicU64::new(0),
                durable_ticket,
                durable_progress,
                state,
                retry_notify: Notify::new(),
                stopping: AtomicBool::new(false),
                flush_waiters: AtomicUsize::new(0),
            }),
            lifecycle: Arc::new(Mutex::new(SupervisorLifecycle::default())),
            pending_commits: Arc::new(AtomicUsize::new(0)),
        }
    }

    /// 当前尚未落库的 pending commit 数。
    pub(in crate::studio) fn pending_commit_count(&self) -> usize {
        self.pending_commits.load(Ordering::Acquire)
    }

    /// 当前已受理的最高 ticket；`flush_through` 的目标上界。
    pub(in crate::studio) fn admitted_ticket(&self) -> u64 {
        self.shared.admitted_ticket.load(Ordering::Acquire)
    }

    /// 已 durable 的最高连续 ticket；诊断用的真实保存水位。
    pub(in crate::studio) fn saved_watermark(&self) -> u64 {
        *self.shared.durable_ticket.borrow()
    }

    #[allow(dead_code)] // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
    pub(in crate::studio) fn state_snapshot(&self) -> PersistenceStateSnapshot {
        self.shared.state.borrow().snapshot.clone()
    }

    pub(in crate::studio) fn subscribe_state(&self) -> watch::Receiver<WriterHealth> {
        self.shared.state.subscribe()
    }

    /// Requests original-queue recovery. An ended supervisor is really joined first; only a
    /// successful stop with retained facts can be replaced. Cancellation leaves that same join.
    pub(in crate::studio) async fn retry_now(&self) -> Result<(), WriteBehindRetryFailure> {
        loop {
            let (task, stopping) = {
                let state = self
                    .lifecycle
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if state.shutdown_observers != 0 {
                    return Err(WriteBehindRetryFailure {
                        kind: WriteBehindRetryFailureKind::ShutdownInProgress,
                        cause: None,
                        owner: self.shared.identity.clone(),
                        task: state.task.as_ref().map(|task| task.identity.clone()),
                    });
                }
                (state.task.clone(), state.stopping_through.is_some())
            };
            let completion = match &task {
                Some(task) if stopping => Some(task.join().await),
                Some(task) => task.join().now_or_never(),
                None => None,
            };
            match self.retry_decision(task.as_ref(), completion) {
                RetryDecision::Changed => continue,
                RetryDecision::Failed(error) => return Err(error),
                RetryDecision::Done => return Ok(()),
                RetryDecision::Start(start) => {
                    let _ = start.send(());
                }
                RetryDecision::Notify => {}
            }
            self.shared.retry_notify.notify_one();
            self.shared.work_notify.notify_one();
            return Ok(());
        }
    }

    /// 登记已提交目录事实；不检查保存健康或队列容量。
    pub(in crate::studio) fn record_directory(&self, delta: DirectoryDelta) {
        if delta.is_empty() {
            return;
        }
        self.ensure_task();
        let mut queue = self.lock_queue_shared();
        if try_coalesce_directory(&mut queue, &delta) {
            drop(queue);
            self.shared.work_notify.notify_one();
            // Merging reuses the queued entry's ticket, so the flush target does not grow here.
            return;
        }
        let ticket = self.next_ticket();
        queue.push_back(queue_directory(ticket, delta));
        self.record_visible_commit();
        drop(queue);
        update_healthy_state(&self.shared, self.pending_commit_count());
        self.shared.work_notify.notify_one();
    }

    pub(in crate::studio) fn record_worktree_lease(
        &self,
        lease: crate::studio::agent_host::worktree_lease::WorktreeLease,
    ) {
        self.ensure_task();
        let mut queue = self.lock_queue_shared();
        let ticket = self.next_ticket();
        queue.push_back(queue_worktree_lease(ticket, lease));
        self.record_visible_commit();
        drop(queue);
        update_healthy_state(&self.shared, self.pending_commit_count());
        self.shared.work_notify.notify_one();
    }

    /// 等待当前已受理的全部 pending commit 完成落库。
    pub(in crate::studio) async fn flush(&self) -> Result<(), WriteBehindFlushFailure> {
        self.flush_through(self.admitted_ticket()).await
    }

    /// Both running and stopping waits keep this exact fence. Real completion is an independent
    /// wake source: neither an empty slot nor a finished flag stands in for joining a supervisor.
    pub(in crate::studio) async fn flush_through(
        &self,
        target: u64,
    ) -> Result<(), WriteBehindFlushFailure> {
        let original = self
            .lifecycle
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task
            .clone();
        self.observe_flush_through(target, original).await
    }

    /// Re-observes only the producer captured by this failure. Qualification is rechecked while
    /// retaining that task under its original lifecycle lock, not transferred to a newer slot.
    pub(in crate::studio) async fn reobserve_original_flush(
        &self,
        failure: &WriteBehindFlushFailure,
    ) -> Result<(), WriteBehindFlushFailure> {
        if !Arc::ptr_eq(&failure.owner, &self.shared.identity) {
            return Err(failure.clone());
        }
        if self.saved_watermark() >= failure.through {
            return Ok(());
        }
        let original = {
            let state = self
                .lifecycle
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            self.reobservable_task(failure, &state)
        };
        match original {
            Some(task) => {
                self.observe_flush_through(failure.through, Some(task))
                    .await
            }
            None if self.saved_watermark() >= failure.through => Ok(()),
            None => Err(failure.clone()),
        }
    }

    async fn observe_flush_through(
        &self,
        target: u64,
        original: Option<Arc<SupervisorTask>>,
    ) -> Result<(), WriteBehindFlushFailure> {
        let mut progress = self.shared.durable_ticket.subscribe();
        let mut health = self.shared.state.subscribe();
        let mut request = None;
        loop {
            // In every phase, a later fault cannot negate an already satisfied original fence.
            if target == 0 || *progress.borrow_and_update() >= target {
                return Ok(());
            }
            let snapshot = health.borrow_and_update().clone();
            let observed = self.observe(snapshot, original.as_ref());
            let kind = if matches!(&observed.completion, Some(Err(_))) {
                Some(WriteBehindFlushFailureKind::SupervisorFailed)
            } else if observed.owns_health()
                && matches!(
                    &observed.health.snapshot.state,
                    PersistenceState::Blocked(_)
                )
            {
                Some(WriteBehindFlushFailureKind::Blocked)
            } else if observed.executor == WriteBehindTaskState::Joined {
                Some(if self.pending_commit_count() == 0 {
                    WriteBehindFlushFailureKind::StoppedBeforeTicket
                } else {
                    WriteBehindFlushFailureKind::StoppingUnsaved
                })
            } else if observed.task.is_none() {
                Some(if observed.executor == WriteBehindTaskState::Stopping {
                    WriteBehindFlushFailureKind::StoppingUnsaved
                } else {
                    WriteBehindFlushFailureKind::NotRunning
                })
            } else {
                None
            };
            if let Some(kind) = kind {
                // The producer can publish durability while the independent health/join is read.
                if *self.shared.durable_ticket.borrow() >= target {
                    return Ok(());
                }
                return Err(self.flush_failure(target, kind, &observed));
            }
            if observed.executor == WriteBehindTaskState::Running && request.is_none() {
                request = Some(self.request_flush());
            }
            let Some(task) = observed.task.clone() else {
                return Err(self.flush_failure(
                    target,
                    WriteBehindFlushFailureKind::NotRunning,
                    &observed,
                ));
            };
            tokio::select! {
                changed = progress.changed() => {
                    if let Err(error) = changed {
                        if *self.shared.durable_ticket.borrow() >= target { return Ok(()); }
                        let snapshot = health.borrow().clone();
                        let mut observed = self.observe(snapshot, original.as_ref());
                        observed.progress_error = Some(Arc::new(WriteBehindCause::ProgressClosed(Arc::new(error))));
                        return Err(self.flush_failure(target, WriteBehindFlushFailureKind::DurabilityClosed, &observed));
                    }
                }
                changed = health.changed() => {
                    if let Err(error) = changed {
                        if *self.shared.durable_ticket.borrow() >= target { return Ok(()); }
                        let snapshot = health.borrow().clone();
                        let mut observed = self.observe(snapshot, original.as_ref());
                        observed.progress_error = Some(Arc::new(WriteBehindCause::ProgressClosed(Arc::new(error))));
                        return Err(self.flush_failure(target, WriteBehindFlushFailureKind::HealthClosed, &observed));
                    }
                }
                _ = task.join() => {}
            }
        }
    }

    /// Pure permission to re-observe this producer's still-owed fixed fence, not a recovery action.
    pub(in crate::studio) fn can_reobserve_original_flush(
        &self,
        failure: &WriteBehindFlushFailure,
    ) -> bool {
        let state = self
            .lifecycle
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.reobservable_task(failure, &state).is_some()
    }

    fn reobservable_task(
        &self,
        failure: &WriteBehindFlushFailure,
        state: &SupervisorLifecycle,
    ) -> Option<Arc<SupervisorTask>> {
        if failure.kind != WriteBehindFlushFailureKind::Blocked
            || failure.executor != WriteBehindTaskState::Running
            || !Arc::ptr_eq(&failure.owner, &self.shared.identity)
            || failure.through <= self.saved_watermark()
        {
            return None;
        }
        let task = state.task.as_ref()?;
        if state.stopping_through.is_some()
            || task.is_finished()
            || task.observed_result().is_some()
            || !failure
                .task
                .as_ref()
                .is_some_and(|id| Arc::ptr_eq(id, &task.identity))
        {
            return None;
        }
        // Same order as the original worker handoff. No IO, notifications or callbacks here.
        let inflight = self
            .shared
            .inflight
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let queue = self.lock_queue_shared();
        inflight
            .iter()
            .chain(queue.iter())
            .any(|entry| entry.ticket() == failure.through)
            .then(|| task.clone())
    }

    /// 登记一次显式固定 ticket 等待，并唤醒 writer 处理已受理批次。
    ///
    /// 必须先自增计数再唤醒：writer 每次循环都重新读取该计数，因此“请求 → 立即取批”
    /// 不受读取压力与进入等待之间的竞态影响；`PendingFlushRequest` 在等待结束时撤销。
    fn request_flush(&self) -> PendingFlushRequest<'_> {
        self.shared.flush_waiters.fetch_add(1, Ordering::AcqRel);
        self.shared.work_notify.notify_one();
        PendingFlushRequest {
            shared: &self.shared,
        }
    }

    /// Repeated/cancelled callers observe the same retained supervisor. Explicit recovery cannot
    /// replace it while any shutdown observation still constructs its original result.
    pub(in crate::studio) async fn shutdown(&self) -> Result<(), WriteBehindShutdownFailure> {
        let observation = ShutdownObservation::register(&self.lifecycle, self.admitted_ticket());
        self.shared.stopping.store(true, Ordering::Release);
        self.shared.work_notify.notify_one();
        self.shared.retry_notify.notify_one();
        let completion = match &observation.task {
            Some(task) => Some(task.join().await),
            None => None,
        };
        let health = self.shared.state.borrow().clone();
        let mut issues = Vec::new();
        if let Some(cause) = health.blocked_cause() {
            issues.push(WriteBehindShutdownIssue::Blocked(cause));
        } else if matches!(&health.snapshot.state, PersistenceState::Degraded(_))
            && let Some(cause) = &health.cause
        {
            issues.push(WriteBehindShutdownIssue::Degraded(cause.clone()));
        }
        if let Some(Err(error)) = completion {
            issues.push(WriteBehindShutdownIssue::Supervisor(error));
        }
        let pending = self.pending_commit_count();
        if pending != 0 {
            issues.push(WriteBehindShutdownIssue::Unsaved { pending });
        }
        let durable = self.saved_watermark();
        if durable < observation.through {
            issues.push(WriteBehindShutdownIssue::FenceNotDurable {
                through: observation.through,
                durable,
            });
        }
        if issues.is_empty() {
            return Ok(());
        }
        let cause = issues.iter().find_map(|issue| match issue {
            WriteBehindShutdownIssue::Supervisor(error)
            | WriteBehindShutdownIssue::Blocked(error)
            | WriteBehindShutdownIssue::Degraded(error) => Some(error.clone()),
            WriteBehindShutdownIssue::Unsaved { .. }
            | WriteBehindShutdownIssue::FenceNotDurable { .. } => None,
        });
        Err(WriteBehindShutdownFailure {
            through: observation.through,
            health,
            issues,
            cause,
            owner: self.shared.identity.clone(),
            task: observation.task.as_ref().map(|task| task.identity.clone()),
        })
    }

    fn observe(
        &self,
        health: WriterHealth,
        original: Option<&Arc<SupervisorTask>>,
    ) -> WriterObservation {
        let stopping = {
            let state = self
                .lifecycle
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.stopping_through.is_some()
        };
        let task = original.cloned();
        // Poll only the retained real join; never infer an outcome from a finished flag.
        let completion = task.as_ref().and_then(|task| task.join().now_or_never());
        let executor = if completion.is_some() {
            WriteBehindTaskState::Joined
        } else if stopping {
            WriteBehindTaskState::Stopping
        } else if task.is_some() {
            WriteBehindTaskState::Running
        } else {
            WriteBehindTaskState::NotStarted
        };
        WriterObservation {
            health,
            task,
            executor,
            completion,
            progress_error: None,
        }
    }

    fn flush_failure(
        &self,
        through: u64,
        kind: WriteBehindFlushFailureKind,
        observed: &WriterObservation,
    ) -> WriteBehindFlushFailure {
        let cause = observed
            .progress_error
            .clone()
            .or_else(|| {
                observed
                    .completion
                    .as_ref()
                    .and_then(|result| result.as_ref().err())
                    .cloned()
            })
            .or_else(|| {
                if observed.owns_health() {
                    observed
                        .health
                        .blocked_cause()
                        .or_else(|| observed.health.cause.clone())
                } else {
                    None
                }
            });
        // A blocked cause and its producer ID are from one canonical watch capture, not a
        // possibly newer task. The lifecycle fact is independently retained as such.
        let task = if kind == WriteBehindFlushFailureKind::Blocked {
            observed.health.task.clone()
        } else {
            observed.task.as_ref().map(|task| task.identity.clone())
        };
        WriteBehindFlushFailure {
            through,
            kind,
            executor: observed.executor,
            health: observed.owns_health().then(|| observed.health.clone()),
            completion: observed.completion.clone(),
            cause,
            owner: self.shared.identity.clone(),
            task,
        }
    }

    fn retry_decision(
        &self,
        original: Option<&Arc<SupervisorTask>>,
        completion: Option<Result<(), Arc<WriteBehindCause>>>,
    ) -> RetryDecision {
        let mut state = self
            .lifecycle
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let same = match (&state.task, original) {
            (Some(current), Some(original)) => Arc::ptr_eq(current, original),
            (None, None) => true,
            _ => false,
        };
        if !same {
            return RetryDecision::Changed;
        }
        if state.shutdown_observers != 0 {
            return RetryDecision::Failed(WriteBehindRetryFailure {
                kind: WriteBehindRetryFailureKind::ShutdownInProgress,
                cause: None,
                owner: self.shared.identity.clone(),
                task: state.task.as_ref().map(|task| task.identity.clone()),
            });
        }
        if let Some(Err(error)) = &completion {
            return RetryDecision::Failed(WriteBehindRetryFailure {
                kind: WriteBehindRetryFailureKind::SupervisorFailed,
                cause: Some(error.clone()),
                owner: self.shared.identity.clone(),
                task: state.task.as_ref().map(|task| task.identity.clone()),
            });
        }
        if original.is_some() && completion.is_none() {
            return if state.stopping_through.is_some() {
                RetryDecision::Changed
            } else {
                RetryDecision::Notify
            };
        }
        // No slot was taken by shutdown: None is exclusively the never-started state. A prior
        // task reaches this branch only after its actual successful join above.
        let inflight = self
            .shared
            .inflight
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let queue = self.lock_queue_shared();
        if self.pending_commit_count() == 0 && queue.is_empty() && inflight.is_empty() {
            return RetryDecision::Done;
        }
        if !inflight.is_empty() || queue.is_empty() {
            return RetryDecision::Failed(WriteBehindRetryFailure {
                kind: WriteBehindRetryFailureKind::QueueNotRetained,
                cause: None,
                owner: self.shared.identity.clone(),
                task: state.task.as_ref().map(|task| task.identity.clone()),
            });
        }
        state.stopping_through = None;
        self.shared.stopping.store(false, Ordering::Release);
        RetryDecision::Start(self.prepare_task(&mut state))
    }

    fn lock_queue_shared(&self) -> std::sync::MutexGuard<'_, VecDeque<QueuedMutation>> {
        self.shared
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }

    fn next_ticket(&self) -> u64 {
        self.shared
            .admitted_ticket
            .fetch_add(1, Ordering::AcqRel)
            .wrapping_add(1)
    }

    fn ensure_task(&self) {
        let start = {
            let mut state = self
                .lifecycle
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.task.is_none() && state.stopping_through.is_none() {
                Some(self.prepare_task(&mut state))
            } else {
                None
            }
        };
        if let Some(start) = start {
            let _ = start.send(());
        }
    }

    fn prepare_task(&self, state: &mut SupervisorLifecycle) -> oneshot::Sender<()> {
        let (task, start) =
            SupervisorTask::prepare(self.shared.clone(), self.pending_commits.clone());
        state.task = Some(task);
        start
    }

    /// 必须在持有队列锁、且 commit 已经入队后调用。这样 writer 只有在计数
    /// 更新后才能观察并取走该 commit，避免从零计数递减下溢。
    fn record_visible_commit(&self) {
        self.pending_commits.fetch_add(1, Ordering::AcqRel);
    }
}
