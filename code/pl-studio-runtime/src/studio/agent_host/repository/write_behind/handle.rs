//! write-behind 队列与后台 writer task 的共享状态及对外句柄。

use std::collections::VecDeque;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

use tokio::sync::{Notify, watch};
use tokio::task::JoinHandle;

use crate::PureError;
use crate::studio::store::directory::DirectoryDelta;
use crate::studio::{PersistenceState, PersistenceStateSnapshot, StudioStore};

use super::super::store_error;
use super::queue::{QueuedMutation, queue_directory, queue_worktree_lease, try_coalesce_directory};
use super::state::update_healthy_state;
use super::worker::supervise_writer;

pub(super) struct WriterShared {
    #[cfg(test)]
    pub(super) lease_ticket_gate: Mutex<
        Option<(
            std::sync::mpsc::SyncSender<()>,
            std::sync::mpsc::Receiver<()>,
        )>,
    >,
    #[cfg(test)]
    pub(super) cleaned_ack_gate: Mutex<
        Option<(
            tokio::sync::oneshot::Sender<()>,
            tokio::sync::oneshot::Receiver<()>,
        )>,
    >,
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
    pub(super) state: watch::Sender<PersistenceStateSnapshot>,
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
/// task 惰性启动：第一次 enqueue/flush 时创建；`shutdown` 排空队列并等待
/// task 退出。clone 共享同一队列与 task。
#[derive(Clone)]
pub(in crate::studio) struct ThreadWriteBehindWriter {
    shared: Arc<WriterShared>,
    task: Arc<Mutex<Option<JoinHandle<()>>>>,
    pending_commits: Arc<AtomicUsize>,
}

impl ThreadWriteBehindWriter {
    pub(in crate::studio) fn new(store: StudioStore) -> Self {
        let (durable_ticket, _) = watch::channel(0u64);
        let (durable_progress, _) = watch::channel(0u64);
        let (state, _) = watch::channel(PersistenceStateSnapshot::default());
        Self {
            shared: Arc::new(WriterShared {
                #[cfg(test)]
                lease_ticket_gate: Mutex::new(None),
                #[cfg(test)]
                cleaned_ack_gate: Mutex::new(None),
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
            task: Arc::new(Mutex::new(None)),
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

    pub(in crate::studio) fn state_snapshot(&self) -> PersistenceStateSnapshot {
        self.shared.state.borrow().clone()
    }

    pub(in crate::studio) fn subscribe_state(&self) -> watch::Receiver<PersistenceStateSnapshot> {
        self.shared.state.subscribe()
    }

    /// 跳过当前退避等待并立即重试队首批次；不丢弃任何待落库事实。
    pub(in crate::studio) fn retry_now(&self) {
        if self.pending_commit_count() > 0 && self.task_is_none() {
            self.shared.stopping.store(false, Ordering::Release);
        }
        self.ensure_task();
        self.shared.retry_notify.notify_one();
        self.shared.work_notify.notify_one();
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
    ) -> u64 {
        self.ensure_task();
        let mut queue = self.lock_queue_shared();
        let ticket = self.next_ticket();
        #[cfg(test)]
        {
            let gate = self.shared.lease_ticket_gate.lock().unwrap().take();
            if let Some((entered, release)) = gate {
                let _ = entered.send(());
                let _ = release.recv();
            }
        }
        queue.push_back(queue_worktree_lease(ticket, lease));
        self.record_visible_commit();
        drop(queue);
        update_healthy_state(&self.shared, self.pending_commit_count());
        self.shared.work_notify.notify_one();
        ticket
    }

    /// 持久化已进入 Blocked 时，flush 立即返回诊断；瞬时故障则继续等待自动恢复。
    fn blocked_result(&self) -> Result<(), PureError> {
        match &self.state_snapshot().state {
            PersistenceState::Blocked(state) => Err(store_error(format!(
                "write-behind writer blocked: {}",
                state.error.message
            ))),
            PersistenceState::Ready(_)
            | PersistenceState::Flushing(_)
            | PersistenceState::Degraded(_)
            | PersistenceState::Recovering(_) => Ok(()),
        }
    }

    /// 等待当前已受理的全部 pending commit 完成落库。
    pub(in crate::studio) async fn flush(&self) -> Result<(), PureError> {
        self.flush_through(self.admitted_ticket()).await
    }

    /// 只等待调用时固定的目标 ticket 变为 durable，不等待整个系统空闲。
    pub(in crate::studio) async fn flush_through(&self, target: u64) -> Result<(), PureError> {
        if target == 0 || *self.shared.durable_ticket.borrow() >= target {
            return Ok(());
        }
        self.blocked_result()?;
        if self.shared.stopping.load(Ordering::Acquire) {
            return self.await_stopping_drain(target).await;
        }
        if self.task_is_none() {
            return Err(store_error(format!(
                "write-behind writer is not running for ticket {target}"
            )));
        }
        // 显式固定 ticket 等待：登记请求并唤醒 writer，让它跳过空闲批量去抖立即取批。
        let _request = self.request_flush();
        // Durability alone cannot end this wait: a terminal `Blocked` health transition keeps the
        // durable sequence unchanged, so the waiter has to observe health as well. Health is
        // subscribed before the first check, so a `Blocked` published before that check is reported
        // by `blocked_result()` and one published after it wakes `health.changed()`; either way the
        // fixed ticket wait returns the real diagnostic instead of waiting for progress that a
        // blocked ticket can never make. Transient `Degraded`/`Recovering` states stay non-fatal.
        let mut progress = self.shared.durable_ticket.subscribe();
        let mut health = self.shared.state.subscribe();
        loop {
            if *progress.borrow_and_update() >= target {
                return Ok(());
            }
            self.blocked_result()?;
            if self.shared.stopping.load(Ordering::Acquire) {
                return self.await_stopping_drain(target).await;
            }
            if self.task_is_none() {
                return Err(store_error(format!(
                    "write-behind writer stopped before ticket {target}"
                )));
            }
            tokio::select! {
                changed = progress.changed() => {
                    changed.map_err(|_| store_error("write-behind durability channel closed"))?;
                }
                changed = health.changed() => {
                    changed.map_err(|_| store_error("write-behind health channel closed"))?;
                }
            }
        }
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

    /// 尝试排空并停止；保存失败返回错误并保留事实。
    pub(in crate::studio) async fn shutdown(&self) -> Result<(), PureError> {
        self.shared.stopping.store(true, Ordering::Release);
        self.shared.work_notify.notify_one();
        self.shared.retry_notify.notify_one();
        let task = self.task.lock().expect("writer task lock").take();
        if let Some(task) = task {
            task.await
                .map_err(|error| store_error(format!("write-behind supervisor failed: {error}")))?;
        }
        self.blocked_result()?;
        if self.pending_commit_count() != 0 {
            return Err(store_error(format!(
                "write-behind writer stopped with {} pending commits",
                self.pending_commit_count()
            )));
        }
        Ok(())
    }

    async fn await_stopping_drain(&self, target: u64) -> Result<(), PureError> {
        let mut progress = self.shared.state.subscribe();
        let mut durability = self.shared.durable_ticket.subscribe();
        loop {
            self.blocked_result()?;
            if *durability.borrow_and_update() >= target {
                return Ok(());
            }
            if self.pending_commit_count() == 0 {
                return Err(store_error(format!(
                    "write-behind writer stopped before ticket {target}"
                )));
            }
            if self.task_is_none() {
                return Err(store_error(
                    "write-behind writer is stopping with unsaved facts",
                ));
            }
            tokio::select! {
                changed = progress.changed() => {
                    changed.map_err(|_| store_error("write-behind shutdown progress channel closed"))?;
                }
                changed = durability.changed() => {
                    changed.map_err(|_| store_error("write-behind shutdown durability channel closed"))?;
                }
            }
        }
    }

    fn lock_queue_shared(&self) -> std::sync::MutexGuard<'_, VecDeque<QueuedMutation>> {
        self.shared
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }

    fn task_is_none(&self) -> bool {
        self.task.lock().expect("writer task lock").is_none()
    }

    fn next_ticket(&self) -> u64 {
        self.shared
            .admitted_ticket
            .fetch_add(1, Ordering::AcqRel)
            .wrapping_add(1)
    }

    fn ensure_task(&self) {
        let mut task = self.task.lock().expect("writer task lock");
        if task.as_ref().is_none_or(JoinHandle::is_finished) {
            if self.shared.stopping.load(Ordering::Acquire) {
                return;
            }
            let shared = self.shared.clone();
            let pending = self.pending_commits.clone();
            *task = Some(tokio::spawn(supervise_writer(shared, pending)));
        }
    }

    /// 必须在持有队列锁、且 commit 已经入队后调用。这样 writer 只有在计数
    /// 更新后才能观察并取走该 commit，避免从零计数递减下溢。
    fn record_visible_commit(&self) {
        self.pending_commits.fetch_add(1, Ordering::AcqRel);
    }
}

#[cfg(test)]
mod storage_fault_tests {
    use super::*;
    use crate::agent::worktree::{
        WorktreeBackend, WorktreeCreateFailure, WorktreeError, WorktreeManager, WorktreeOwnership,
        WorktreeStatus,
    };
    use crate::studio::agent_host::worktree_lease::{
        WorktreeLease, WorktreeLeaseOwner, WorktreeLeaseOwnerKind, WorktreeLeaseState,
    };
    use anyhow::{Context, Result};
    use futures::{FutureExt, future::BoxFuture};
    use sea_orm::ConnectionTrait;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::AtomicBool;

    fn lease(repo: &Path, id: &str) -> WorktreeLease {
        let ownership = WorktreeOwnership::Child {
            child_id: id.into(),
        };
        WorktreeLease {
            revision: 1,
            state: WorktreeLeaseState::Prepared,
            owner_kind: WorktreeLeaseOwnerKind::Child,
            owner_thread_id: id.into(),
            root_thread_id: "root".into(),
            project_id: "project".into(),
            ssh_alias: None,
            repository_root: repo.to_string_lossy().into_owned(),
            path: WorktreeManager::allocate_path(repo, "root", &ownership)
                .to_string_lossy()
                .into_owned(),
            branch: WorktreeManager::branch_for(&ownership),
            base_commit: "a".repeat(40),
            restore_authorized_at: None,
        }
    }

    async fn settled(writer: &ThreadWriteBehindWriter, target: u64) -> Result<()> {
        let _request = writer.request_flush();
        let mut updates = writer.subscribe_state();
        tokio::time::timeout(std::time::Duration::from_secs(5), async {
            while writer.saved_watermark() < target {
                updates.changed().await.context("writer state closed")?;
            }
            Ok::<_, anyhow::Error>(())
        })
        .await??;
        Ok(())
    }

    #[tokio::test]
    async fn lease_ticket_admission_is_fifo_across_the_batch_boundary() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        store.database().execute_unprepared("CREATE TRIGGER reject_boundary_lease BEFORE INSERT ON studio_objects WHEN NEW.owner_id='boundary' BEGIN SELECT RAISE(ABORT,'controlled lease admission rejection'); END").await?;
        let writer = ThreadWriteBehindWriter::new(store.clone());
        for index in 0..super::super::queue::MAX_BATCH_COMMITS - 1 {
            writer.record_worktree_lease(lease(temp.path(), &format!("entry-{index}")));
        }
        let (entered, waiting) = std::sync::mpsc::sync_channel(1);
        let (release, released) = std::sync::mpsc::channel();
        *writer.shared.lease_ticket_gate.lock().unwrap() = Some((entered, released));
        let runtime = tokio::runtime::Handle::current();
        let admitting = writer.clone();
        let critical = lease(temp.path(), "boundary");
        let task = std::thread::spawn(move || {
            let _runtime = runtime.enter();
            admitting.record_worktree_lease(critical)
        });
        waiting.recv_timeout(std::time::Duration::from_secs(5))?;
        let directory = DirectoryDelta {
            project_removals: vec![crate::studio::store::directory::ProjectRemoval {
                project_id: "unused-project".into(),
                thread_ids: vec![],
                closed_at: 1,
            }],
            ..Default::default()
        };
        // The former allocation-before-lock implementation permits precisely the bad 65-before-64
        // interleaving here. The corrected implementation holds this lock through admission.
        let admission_holds_queue = writer.shared.queue.try_lock().is_err();
        if !admission_holds_queue {
            writer.record_directory(directory.clone());
        }
        release.send(())?;
        let ticket = task
            .join()
            .map_err(|_| anyhow::anyhow!("admission thread failed"))?;
        if admission_holds_queue {
            writer.record_directory(directory);
        }
        assert!(
            admission_holds_queue,
            "ticket assignment and enqueue must share the queue lock"
        );
        assert_eq!(ticket, 64);
        assert_eq!(writer.admitted_ticket(), 65);
        assert_eq!(writer.pending_commit_count(), 65);
        assert_eq!(
            writer
                .shared
                .queue
                .lock()
                .unwrap()
                .iter()
                .map(|entry| entry.ticket())
                .collect::<Vec<_>>(),
            (1..=65).collect::<Vec<_>>()
        );
        let blocked = tokio::time::timeout(
            std::time::Duration::from_secs(5),
            writer.flush_through(ticket),
        )
        .await?;
        assert!(
            blocked.is_err(),
            "a later directory ticket must never confirm the rejected lease"
        );
        assert!(writer.saved_watermark() < ticket);
        assert!(
            crate::studio::agent_host::worktree_lease::load_leases(&store)
                .await?
                .is_empty()
        );
        store
            .database()
            .execute_unprepared("DROP TRIGGER reject_boundary_lease")
            .await?;
        writer.retry_now();
        settled(&writer, 65).await?;
        assert_eq!(writer.pending_commit_count(), 0);
        assert!(
            crate::studio::agent_host::worktree_lease::load_leases(&store)
                .await?
                .iter()
                .any(|lease| lease.owner_thread_id == "boundary")
        );
        writer.shutdown().await?;
        Ok(())
    }

    #[derive(Debug)]
    struct CleanupIo {
        removed: AtomicBool,
        removals: AtomicUsize,
        branch_removed: AtomicBool,
        replacement_after_remove: AtomicBool,
        path: PathBuf,
        common_dir: PathBuf,
        branch: String,
    }

    impl CleanupIo {
        fn new(lease: &WorktreeLease) -> Self {
            Self {
                removed: AtomicBool::new(false),
                removals: AtomicUsize::new(0),
                branch_removed: AtomicBool::new(false),
                replacement_after_remove: AtomicBool::new(false),
                path: lease.path.clone().into(),
                common_dir: Path::new(&lease.repository_root).join(".git"),
                branch: lease.branch.clone(),
            }
        }
    }

    type GitResult<'a, T> = BoxFuture<'a, Result<T, WorktreeError>>;
    impl WorktreeBackend for CleanupIo {
        fn delete_branch_at<'a>(
            &'a self,
            _: &'a Path,
            branch: &'a str,
            expected_head: &'a str,
        ) -> GitResult<'a, ()> {
            async move {
                if branch != self.branch || expected_head != "a".repeat(40) {
                    return Err(WorktreeError::InvalidResource(
                        "reference CAS mismatch".into(),
                    ));
                }
                self.branch_removed.store(true, Ordering::Release);
                Ok(())
            }
            .boxed()
        }
        fn branch_head<'a>(&'a self, _: &'a Path, _: &'a str) -> GitResult<'a, Option<String>> {
            async { Ok((!self.branch_removed.load(Ordering::Acquire)).then(|| "a".repeat(40))) }
                .boxed()
        }
        fn is_ancestor<'a>(&'a self, _: &'a Path, _: &'a str, _: &'a str) -> GitResult<'a, bool> {
            async { Ok(true) }.boxed()
        }
        fn resolve_repo_root<'a>(&'a self, path: &'a Path) -> GitResult<'a, PathBuf> {
            async move { Ok(path.to_owned()) }.boxed()
        }
        fn create_parent<'a>(&'a self, _: &'a Path, _: &'a Path) -> GitResult<'a, ()> {
            async { Ok(()) }.boxed()
        }
        fn path_exists<'a>(&'a self, _: &'a Path) -> GitResult<'a, bool> {
            async {
                Ok(!self.removed.load(Ordering::Acquire)
                    || self.replacement_after_remove.load(Ordering::Acquire))
            }
            .boxed()
        }
        fn create<'a>(
            &'a self,
            _: &'a Path,
            _: &'a str,
            _: &'a Path,
            _: &'a str,
        ) -> BoxFuture<'a, Result<(), WorktreeCreateFailure>> {
            async {
                Err(WorktreeCreateFailure::no_side_effects(
                    WorktreeError::InvalidResource("not a create fixture".into()),
                ))
            }
            .boxed()
        }
        fn resolve_head<'a>(&'a self, _: &'a Path) -> GitResult<'a, String> {
            async { Ok("a".repeat(40)) }.boxed()
        }
        fn status<'a>(&'a self, _: &'a Path) -> GitResult<'a, WorktreeStatus> {
            async {
                Ok(WorktreeStatus {
                    head: "a".repeat(40),
                    branch: Some(self.branch.clone()),
                    changed_files: vec![],
                })
            }
            .boxed()
        }
        fn remove<'a>(&'a self, _: &'a Path, _: &'a Path, _: bool) -> GitResult<'a, ()> {
            async {
                self.removals.fetch_add(1, Ordering::AcqRel);
                self.removed.store(true, Ordering::Release);
                Ok(())
            }
            .boxed()
        }
        fn worktree_list<'a>(&'a self, _: &'a Path) -> GitResult<'a, String> {
            async {
                Ok(if self.removed.load(Ordering::Acquire) {
                    String::new()
                } else {
                    format!(
                        "worktree {}\nHEAD {}\nbranch refs/heads/{}\n\n",
                        self.path.display(),
                        "a".repeat(40),
                        self.branch
                    )
                })
            }
            .boxed()
        }
        fn git_common_dir<'a>(&'a self, _: &'a Path) -> GitResult<'a, String> {
            async { Ok(self.common_dir.to_string_lossy().into_owned()) }.boxed()
        }
    }

    #[tokio::test]
    async fn cleaned_reentry_waits_for_its_completion_commit_and_ack() -> Result<()> {
        use crate::studio::agent_host::workspace_preparation::close_workspace;
        use pl_tool::collaboration::thread::WorkspaceRelease;
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let writer = ThreadWriteBehindWriter::new(store.clone());
        let leases = WorktreeLeaseOwner::new(writer.clone());
        let unchanged = lease(temp.path(), "already-durable");
        leases.record_durable(unchanged.clone()).await?;
        // A failed identity check or physical postcondition must retain a durable cleanup owner,
        // not publish Cleaned or delete either a replacement directory or its surviving branch.
        for (id, changed_branch) in [("changed-branch", true), ("replacement-path", false)] {
            let prepared = lease(temp.path(), id);
            leases.record_durable(prepared.clone()).await?;
            let mut io = CleanupIo::new(&prepared);
            if changed_branch {
                io.branch = "user-owned-branch".into();
            } else {
                io.replacement_after_remove.store(true, Ordering::Release);
            }
            let io = Arc::new(io);
            let manager = WorktreeManager::new(temp.path().to_owned(), io.clone());
            assert!(
                close_workspace(
                    &store,
                    &leases,
                    &manager,
                    prepared,
                    WorkspaceRelease::Cleanup
                )
                .await
                .is_err()
            );
            let pending = leases.get(id).context("pending cleanup identity")?;
            assert_eq!(pending.state, WorktreeLeaseState::Preserved);
            assert!(leases.is_durable(&pending));
            assert_eq!(
                io.removals.load(Ordering::Acquire),
                usize::from(!changed_branch)
            );
            assert!(!io.branch_removed.load(Ordering::Acquire));
            assert!(io.path_exists(&io.path).await?);
        }
        let prepared = lease(temp.path(), "cleanup");
        leases.record_durable(prepared.clone()).await?;
        let io = Arc::new(CleanupIo::new(&prepared));
        let manager = WorktreeManager::new(temp.path().to_owned(), io.clone());
        store.database().execute_unprepared("CREATE TRIGGER reject_cleaned BEFORE UPDATE ON studio_objects WHEN json_extract(NEW.payload_json,'$.state')='cleaned' BEGIN SELECT RAISE(ABORT,'controlled completion rejection'); END").await?;
        assert!(
            close_workspace(
                &store,
                &leases,
                &manager,
                prepared,
                WorkspaceRelease::Cleanup
            )
            .await
            .is_err()
        );
        let cleaned = leases.get("cleanup").context("retained cleanup phase")?;
        assert_eq!(cleaned.state, WorktreeLeaseState::Cleaned);
        assert!(!leases.is_durable(&cleaned));
        leases.record_durable(unchanged).await.context(
            "an unrelated blocked completion cannot invalidate an earlier lease receipt",
        )?;
        assert!(
            close_workspace(
                &store,
                &leases,
                &manager,
                cleaned.clone(),
                WorkspaceRelease::Cleanup
            )
            .await
            .is_err(),
            "a hot Cleaned label is not a durable completion receipt"
        );
        assert_eq!(io.removals.load(Ordering::Acquire), 1);
        store
            .database()
            .execute_unprepared("DROP TRIGGER reject_cleaned")
            .await?;
        writer.retry_now();
        settled(&writer, writer.admitted_ticket()).await?;
        close_workspace(
            &store,
            &leases,
            &manager,
            cleaned,
            WorkspaceRelease::Cleanup,
        )
        .await?;
        assert_eq!(io.removals.load(Ordering::Acquire), 1);

        // A separate physical cleanup commits, but its ACK is deliberately held back.
        let next = lease(temp.path(), "cancelled-cleanup");
        leases.record_durable(next.clone()).await?;
        let io = Arc::new(CleanupIo::new(&next));
        let manager = WorktreeManager::new(temp.path().to_owned(), io.clone());
        let (entered, waiting) = tokio::sync::oneshot::channel();
        let (release, released) = tokio::sync::oneshot::channel();
        *writer.shared.cleaned_ack_gate.lock().unwrap() = Some((entered, released));
        let cleanup_leases = leases.clone();
        let cleanup_store = store.clone();
        let cleanup_manager = manager.clone();
        let cleanup = tokio::spawn(async move {
            close_workspace(
                &cleanup_store,
                &cleanup_leases,
                &cleanup_manager,
                next,
                WorkspaceRelease::Cleanup,
            )
            .await
        });
        waiting.await?;
        cleanup.abort();
        assert!(cleanup.await.unwrap_err().is_cancelled());
        let mut cleaned = leases
            .get("cancelled-cleanup")
            .context("cancelled completion phase")?;
        // Also exercise consume_restore: its new revision must not bypass the pending receipt.
        cleaned.grant_restore(1);
        leases.record(cleaned.clone())?;
        let mut retry = Box::pin(close_workspace(
            &store,
            &leases,
            &manager,
            cleaned,
            WorkspaceRelease::Cleanup,
        ));
        assert!(
            futures::poll!(retry.as_mut()).is_pending(),
            "completion reentry must wait for writer ACK"
        );
        drop(retry);
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("completion writer lost its owner"))?;
        settled(&writer, writer.admitted_ticket()).await?;
        let cleaned = leases
            .get("cancelled-cleanup")
            .context("completion phase after ACK")?;
        close_workspace(
            &store,
            &leases,
            &manager,
            cleaned,
            WorkspaceRelease::Cleanup,
        )
        .await?;
        assert_eq!(io.removals.load(Ordering::Acquire), 1);
        assert!(leases.is_durable(&leases.get("cancelled-cleanup").unwrap()));
        io.branch_removed.store(false, Ordering::Release);
        let cleaned = leases
            .get("cancelled-cleanup")
            .context("durable completion")?;
        assert!(
            close_workspace(
                &store,
                &leases,
                &manager,
                cleaned,
                WorkspaceRelease::Cleanup
            )
            .await
            .is_err(),
            "a completion retry must not delete a replacement branch"
        );
        assert!(!io.branch_removed.load(Ordering::Acquire));
        assert_eq!(io.removals.load(Ordering::Acquire), 1);
        writer.shutdown().await?;
        Ok(())
    }
}
