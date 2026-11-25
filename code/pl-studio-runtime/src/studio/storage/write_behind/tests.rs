use super::*;
use crate::agent::worktree::{
    WorktreeBackend, WorktreeCreateFailure, WorktreeError, WorktreeManager, WorktreeOwnership,
    WorktreeStatus,
};
use crate::studio::worktree::worktree_lease::{
    WorktreeLease, WorktreeLeaseOwner, WorktreeLeaseOwnerKind, WorktreeLeaseState,
};
use anyhow::{Context, Result};
use futures::{FutureExt, future::BoxFuture};
use sea_orm::ConnectionTrait;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

struct LeaseAckGate {
    state: WorktreeLeaseState,
    entered: tokio::sync::oneshot::Sender<()>,
    release: tokio::sync::oneshot::Receiver<()>,
}
struct ControlledPersistence {
    store: StudioStore,
    gate: Mutex<Option<LeaseAckGate>>,
}
impl ControlledPersistence {
    fn writer(store: StudioStore) -> (ThreadWriteBehindWriter, Arc<Self>) {
        let persistence = Arc::new(Self {
            store,
            gate: Mutex::new(None),
        });
        (
            ThreadWriteBehindWriter::with_persistence(persistence.clone()),
            persistence,
        )
    }
}
impl super::super::apply::BatchPersistence for ControlledPersistence {
    fn apply<'a>(
        &'a self,
        batch: &'a super::super::queue::PendingBatch,
    ) -> BoxFuture<'a, Result<(), super::super::worker::BatchError>> {
        Box::pin(async move {
            super::super::apply::apply_batch(&self.store, batch).await?;
            let gate = {
                let mut gate = self.gate.lock().unwrap();
                if gate.as_ref().is_some_and(|gate| batch.entries.iter().any(|entry| {
                    matches!(entry.mutation.as_ref(), super::super::queue::StudioMutation::WorktreeLease(lease) if lease.state == gate.state)
                })) { gate.take() } else { None }
            };
            if let Some(gate) = gate {
                let _ = gate.entered.send(());
                let _ = gate.release.await;
            }
            Ok(())
        })
    }
}

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
        workspace_id: "project".into(),
        ssh_alias: None,
        repository_root: repo.to_string_lossy().into_owned(),
        path: WorktreeManager::allocate_path(repo, "root", &ownership)
            .to_string_lossy()
            .into_owned(),
        base_commit: "a".repeat(40),
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
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    store.database().execute_unprepared("CREATE TRIGGER reject_boundary_lease BEFORE INSERT ON studio_objects WHEN NEW.owner_id='boundary' BEGIN SELECT RAISE(ABORT,'controlled lease admission rejection'); END").await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    for index in 0..super::super::queue::MAX_BATCH_COMMITS - 1 {
        writer.record_worktree_lease(lease(temp.path(), &format!("entry-{index}")));
    }
    let (entered, waiting) = std::sync::mpsc::sync_channel(1);
    let (release, released) = std::sync::mpsc::channel();
    let runtime = tokio::runtime::Handle::current();
    let admitting = writer.clone();
    let critical = lease(temp.path(), "boundary");
    let task = std::thread::spawn(move || {
        let _runtime = runtime.enter();
        admitting.record_mutation(move |ticket| {
            let _ = entered.send(());
            let _ = released.recv();
            queue_worktree_lease(ticket, critical)
        })
    });
    waiting.recv_timeout(std::time::Duration::from_secs(5))?;
    let directory = DirectoryDelta {
        project_removals: vec![crate::studio::store::directory::ProjectRemoval {
            workspace_id: "unused-project".into(),
            session_ids: vec![],
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
        crate::studio::worktree::worktree_lease::load_leases(&store)
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
        crate::studio::worktree::worktree_lease::load_leases(&store)
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
    identity_conflict: bool,
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
            identity_conflict: false,
            replacement_after_remove: AtomicBool::new(false),
            path: lease.path.clone().into(),
            common_dir: Path::new(&lease.repository_root).join(".git"),
            branch: "business".into(),
        }
    }
}

type GitResult<'a, T> = BoxFuture<'a, Result<T, WorktreeError>>;
impl WorktreeBackend for CleanupIo {
    fn worktree_backlink<'a>(&'a self, _: &'a Path, _: &'a str) -> GitResult<'a, String> {
        async {
            let path = self.path.to_string_lossy().replace('\\', "/");
            #[cfg(windows)]
            let path = path.to_ascii_lowercase();
            Ok(if self.identity_conflict {
                format!("{path}/another/.git")
            } else {
                format!("{path}/.git")
            })
        }
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
    fn path_exists<'a>(&'a self, _: &'a Path, _: &'a Path) -> GitResult<'a, bool> {
        async {
            Ok(!self.removed.load(Ordering::Acquire)
                || self.replacement_after_remove.load(Ordering::Acquire))
        }
        .boxed()
    }
    fn create<'a>(
        &'a self,
        _: &'a Path,
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
                ignored_files: vec![],
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
async fn verified_binding_confirmation_requires_exact_lease_and_execution_use() -> Result<()> {
    use crate::studio::worktree::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity};
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let mut expected = lease(temp.path(), "verified-child");
    owner.record_durable(expected.clone()).await?;
    let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, expected.path.clone())?;
    let usage = owner.reserve_workspace(&expected.owner_thread_id, WorkspaceEndpoint::Local)?;
    assert!(
        owner
            .confirm_verified_binding(&expected, &usage)
            .await
            .is_err()
    );
    owner.assign_workspace(&usage, identity.clone())?;
    let foreign_owner = WorktreeLeaseOwner::new(writer.clone());
    let foreign =
        foreign_owner.reserve_workspace(&expected.owner_thread_id, WorkspaceEndpoint::Local)?;
    foreign_owner.assign_workspace(&foreign, identity.clone())?;
    assert!(
        owner
            .confirm_verified_binding(&expected, &foreign)
            .await
            .is_err()
    );
    let wrong_owner = owner.reserve_workspace("another-child", WorkspaceEndpoint::Local)?;
    owner.assign_workspace(&wrong_owner, identity.clone())?;
    assert!(
        owner
            .confirm_verified_binding(&expected, &wrong_owner)
            .await
            .is_err()
    );
    let wrong_path =
        owner.reserve_workspace(&expected.owner_thread_id, WorkspaceEndpoint::Local)?;
    owner.assign_workspace(
        &wrong_path,
        WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            temp.path().to_string_lossy().into_owned(),
        )?,
    )?;
    assert!(
        owner
            .confirm_verified_binding(&expected, &wrong_path)
            .await
            .is_err()
    );
    let cleanup_use = owner.cleanup_resolution(&expected.owner_thread_id, identity.clone())?;
    assert!(
        owner
            .confirm_verified_binding(&expected, &cleanup_use)
            .await
            .is_err()
    );
    let mut changed = expected.clone();
    changed.base_commit = "b".repeat(40);
    assert!(
        owner
            .confirm_verified_binding(&changed, &usage)
            .await
            .is_err()
    );
    for state in [
        WorktreeLeaseState::CleanupRequested,
        WorktreeLeaseState::Cleaned,
    ] {
        let previous = expected.clone();
        expected.transition(state);
        owner.record_durable(expected.clone()).await?;
        assert!(
            owner
                .confirm_verified_binding(&previous, &usage)
                .await
                .is_err()
        );
        assert!(
            owner
                .confirm_verified_binding(&expected, &usage)
                .await
                .is_err()
        );
        assert_eq!(owner.get(&expected.owner_thread_id), Some(expected.clone()));
    }
    expected.transition(WorktreeLeaseState::Preserved);
    owner.record_durable(expected.clone()).await?;
    let active = owner.confirm_verified_binding(&expected, &usage).await?;
    assert_eq!(active.state, WorktreeLeaseState::Active);
    assert_eq!(active.revision, expected.revision + 1);
    assert_eq!(
        owner.confirm_verified_binding(&active, &usage).await?,
        active
    );
    owner.restore_workspace_seal(&active.owner_thread_id, identity)?;
    assert!(
        owner
            .confirm_verified_binding(&active, &usage)
            .await
            .is_err()
    );
    assert_eq!(owner.get(&active.owner_thread_id), Some(active));
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn verified_binding_and_active_reentry_wait_for_the_exact_ack() -> Result<()> {
    use crate::studio::worktree::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity};
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let (writer, persistence) = ControlledPersistence::writer(store.clone());
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let prepared = lease(temp.path(), "ack-child");
    owner.record_durable(prepared.clone()).await?;
    let usage = owner.reserve_workspace(&prepared.owner_thread_id, WorkspaceEndpoint::Local)?;
    owner.assign_workspace(
        &usage,
        WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, prepared.path.clone())?,
    )?;
    let (entered, waiting) = tokio::sync::oneshot::channel();
    let (release, released) = tokio::sync::oneshot::channel();
    *persistence.gate.lock().unwrap() = Some(LeaseAckGate {
        state: WorktreeLeaseState::Active,
        entered,
        release: released,
    });
    let confirming_owner = owner.clone();
    let confirming_usage = usage.clone();
    let confirming = tokio::spawn(async move {
        confirming_owner
            .confirm_verified_binding(&prepared, &confirming_usage)
            .await
    });
    tokio::time::timeout(std::time::Duration::from_secs(5), waiting).await??;
    let active = owner.get("ack-child").context("admitted Active lease")?;
    assert!(!owner.is_durable(&active));
    assert!(!confirming.is_finished());
    let mut reentry = Box::pin(owner.confirm_verified_binding(&active, &usage));
    assert!(futures::poll!(&mut reentry).is_pending());
    // Cancelling one waiter must not lose the admitted write or bypass its original ACK.
    confirming.abort();
    assert!(confirming.await.unwrap_err().is_cancelled());
    assert!(futures::poll!(&mut reentry).is_pending());
    release.send(()).unwrap();
    assert_eq!(reentry.await?, active);
    assert!(owner.is_durable(&active));
    assert_eq!(
        crate::studio::worktree::worktree_lease::load_leases(&store).await?,
        vec![active]
    );
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn hydrated_ssh_worktree_cleanup_uses_only_its_saved_physical_binding() -> Result<()> {
    use crate::studio::worktree::worktree_lease::{
        WorkspaceEndpoint, WorkspaceIdentity, load_leases,
    };
    for has_binding in [true, false] {
        let temp = tempfile::tempdir()?;
        let database = temp.path().join("data/studio.sqlite");
        let store = StudioStore::open(&database).await?;
        let mut active = lease(Path::new("/repository"), "cold-ssh-child");
        active.repository_root = "/repository".into();
        active.path = "/repository/.anywork/worktrees/root/cold-ssh-child".into();
        active.ssh_alias = Some("original-alias".into());
        let identity = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Ssh {
                host: "original.example".into(),
                port: 22,
                username: "fixture".into(),
            },
            active.path.clone(),
        )?;
        if has_binding {
            store
                .bind_workspace_identity(&active.owner_thread_id, &identity)
                .await?;
        }
        let old_writer = ThreadWriteBehindWriter::new(store.clone());
        let old_owner = WorktreeLeaseOwner::new(old_writer.clone());
        old_owner.record_durable(active.clone()).await?;
        active.transition(WorktreeLeaseState::Active);
        old_owner.record_durable(active.clone()).await?;
        old_writer.shutdown().await?;
        drop(old_owner);
        drop(store);

        let store = StudioStore::open(&database).await?;
        let writer = ThreadWriteBehindWriter::new(store.clone());
        let owner = WorktreeLeaseOwner::new(writer.clone());
        owner.restore(&store, load_leases(&store).await?).await?;
        assert_eq!(writer.admitted_ticket(), 0, "restore must not write leases");
        if has_binding {
            let borrower = owner.reserve_workspace("borrower", identity.endpoint.clone())?;
            owner.assign_workspace(&borrower, identity.clone())?;
            assert!(
                owner
                    .begin_workspace_cleanup(&active.owner_thread_id, &identity, None)
                    .is_err(),
                "saved identity must not bypass a live borrower"
            );
            drop(borrower);
            let changed = WorkspaceIdentity::canonical(
                WorkspaceEndpoint::Ssh {
                    host: "replacement.example".into(),
                    port: 22,
                    username: "fixture".into(),
                },
                identity.root.clone(),
            )?;
            assert!(
                owner
                    .begin_workspace_cleanup(&active.owner_thread_id, &changed, None)
                    .is_err(),
                "the same path on a different endpoint is not deletion authority"
            );
            // No execution owner or SSH connection is needed to recover cleanup authority.
            let removal =
                owner.begin_workspace_cleanup(&active.owner_thread_id, &identity, None)?;
            drop(removal);
            owner
                .begin_workspace_cleanup(&active.owner_thread_id, &identity, None)?
                .complete();
        } else {
            assert!(
                owner
                    .begin_workspace_cleanup(&active.owner_thread_id, &identity, None)
                    .is_err(),
                "an old alias without a saved endpoint must remain protected"
            );
        }
        writer.shutdown().await?;
    }
    Ok(())
}

#[tokio::test]
async fn hydrated_active_binding_waits_for_the_current_writer_ack() -> Result<()> {
    check_hydrated_active_binding(false).await
}

#[tokio::test]
async fn hydrated_active_binding_propagates_the_current_writer_failure() -> Result<()> {
    check_hydrated_active_binding(true).await
}

async fn check_hydrated_active_binding(conflict: bool) -> Result<()> {
    use crate::studio::worktree::worktree_lease::{
        WorkspaceEndpoint, WorkspaceIdentity, load_leases,
    };
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let mut active = lease(temp.path(), "hydrated-active");
    active.transition(WorktreeLeaseState::Active);
    // The old writer really saved this Active binding before the new owner hydrates it.
    let old_writer = ThreadWriteBehindWriter::new(store.clone());
    let old_owner = WorktreeLeaseOwner::new(old_writer.clone());
    let mut prepared = active.clone();
    prepared.state = WorktreeLeaseState::Prepared;
    prepared.revision -= 1;
    old_owner.record_durable(prepared).await?;
    old_owner.record_durable(active.clone()).await?;
    old_writer.shutdown().await?;

    let (writer, persistence) = ControlledPersistence::writer(store.clone());
    let owner = WorktreeLeaseOwner::new(writer.clone());
    owner.restore(&store, load_leases(&store).await?).await?;
    assert_eq!(owner.get(&active.owner_thread_id), Some(active.clone()));
    assert_eq!(writer.admitted_ticket(), 0, "hydration must not enqueue");
    let usage = owner.reserve_workspace(&active.owner_thread_id, WorkspaceEndpoint::Local)?;
    owner.assign_workspace(
        &usage,
        WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, active.path.clone())?,
    )?;

    let mut conflicting = active.clone();
    if conflict {
        use sea_orm::{ConnectionTrait, DbBackend, Statement};
        conflicting.base_commit = "b".repeat(40);
        // Inject a competing durable payload at the hydrated revision. The real
        // current writer must report its conflict instead of acknowledging ticket 0.
        let payload = serde_json::to_string(&conflicting)?;
        let changed = store
            .database()
            .execute_raw(Statement::from_sql_and_values(
                DbBackend::Sqlite,
                "UPDATE studio_objects SET payload_json=?,payload_hash=? \
                 WHERE owner_kind='agent' AND owner_id=? AND object_kind='worktreeLease'",
                [
                    payload.clone().into(),
                    pl_core::context::content_hash(payload.as_bytes()).into(),
                    active.owner_thread_id.clone().into(),
                ],
            ))
            .await?;
        assert_eq!(changed.rows_affected(), 1);
    }
    let (entered, waiting) = tokio::sync::oneshot::channel();
    let (release, released) = tokio::sync::oneshot::channel();
    *persistence.gate.lock().unwrap() = Some(LeaseAckGate {
        state: WorktreeLeaseState::Active,
        entered,
        release: released,
    });
    let write = owner.prepare_verified_binding(&active, &usage)?;
    let ticket = writer.admitted_ticket();
    assert!(ticket > 0, "hydrated Active needs a current writer ticket");
    assert!(!owner.is_durable(&active));
    // Reentry reuses the admitted nonzero ticket, without revising or enqueueing again.
    let reentry = owner.prepare_verified_binding(&active, &usage)?;
    assert_eq!(writer.admitted_ticket(), ticket);
    let mut confirming = Box::pin(owner.confirm_prepared_binding(write));
    assert!(futures::poll!(&mut confirming).is_pending());
    if conflict {
        let failure = tokio::time::timeout(std::time::Duration::from_secs(5), confirming)
            .await?
            .unwrap_err();
        assert!(failure.downcast_ref::<crate::PureError>().is_some());
        assert!(
            failure.to_string().contains("revision conflicts"),
            "{failure:#}"
        );
        assert!(!owner.is_durable(&active));
        assert_eq!(load_leases(&store).await?, vec![conflicting]);
        assert!(writer.shutdown().await.is_err());
    } else {
        tokio::time::timeout(std::time::Duration::from_secs(5), waiting).await??;
        assert!(futures::poll!(&mut confirming).is_pending());
        assert!(!owner.is_durable(&active));
        release.send(()).unwrap();
        assert_eq!(confirming.await?, active);
        assert_eq!(owner.confirm_prepared_binding(reentry).await?, active);
        assert!(owner.is_durable(&active));
        assert_eq!(load_leases(&store).await?, vec![active.clone()]);
        writer.shutdown().await?;
    }
    assert_eq!(owner.get(&active.owner_thread_id), Some(active));
    Ok(())
}

#[tokio::test]
async fn verified_binding_rechecks_retirement_after_the_write_ack() -> Result<()> {
    use crate::studio::worktree::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity};
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let (writer, persistence) = ControlledPersistence::writer(store.clone());
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let prepared = lease(temp.path(), "sealed-during-ack");
    owner.record_durable(prepared.clone()).await?;
    let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, prepared.path.clone())?;
    let usage = owner.reserve_workspace(&prepared.owner_thread_id, WorkspaceEndpoint::Local)?;
    owner.assign_workspace(&usage, identity.clone())?;
    let (entered, waiting) = tokio::sync::oneshot::channel();
    let (release, released) = tokio::sync::oneshot::channel();
    *persistence.gate.lock().unwrap() = Some(LeaseAckGate {
        state: WorktreeLeaseState::Active,
        entered,
        release: released,
    });
    let confirming_owner = owner.clone();
    let confirming = tokio::spawn(async move {
        confirming_owner
            .confirm_verified_binding(&prepared, &usage)
            .await
    });
    tokio::time::timeout(std::time::Duration::from_secs(5), waiting).await??;
    let admitted = owner
        .get("sealed-during-ack")
        .context("admitted Active lease")?;
    assert!(!owner.is_durable(&admitted));
    owner.restore_workspace_seal(&admitted.owner_thread_id, identity.clone())?;
    release.send(()).unwrap();
    let failure = confirming.await?.unwrap_err();
    assert!(
        failure.to_string().contains("sealed for retirement"),
        "{failure:#}"
    );
    // The ACK still belongs to its original write; rejecting execution must not
    // erase the durable binding or remove the independent retirement seal.
    assert!(owner.is_durable(&admitted));
    assert_eq!(owner.get(&admitted.owner_thread_id), Some(admitted.clone()));
    let late_usage =
        owner.reserve_workspace(&admitted.owner_thread_id, WorkspaceEndpoint::Local)?;
    assert!(owner.assign_workspace(&late_usage, identity).is_err());
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn verified_binding_propagates_the_writer_failure_without_acknowledging() -> Result<()> {
    use crate::studio::worktree::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity};
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let prepared = lease(temp.path(), "conflicting-durable-binding");
    owner.record_durable(prepared.clone()).await?;
    let usage = owner.reserve_workspace(&prepared.owner_thread_id, WorkspaceEndpoint::Local)?;
    owner.assign_workspace(
        &usage,
        WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, prepared.path.clone())?,
    )?;
    // A conflicting durable revision is a real writer failure, not a test replacement
    // for the confirmation operation or its ACK.
    let mut conflicting = prepared.clone();
    conflicting.transition(WorktreeLeaseState::Active);
    conflicting.base_commit = "b".repeat(40);
    crate::studio::store::object::put_object(
        store.database(),
        &prepared.owner_thread_id,
        &conflicting,
        1,
    )
    .await?;
    let failure = owner
        .confirm_verified_binding(&prepared, &usage)
        .await
        .unwrap_err();
    assert!(failure.downcast_ref::<crate::PureError>().is_some());
    assert!(
        failure.to_string().contains("revision conflicts"),
        "{failure:#}"
    );
    let admitted = owner.get(&prepared.owner_thread_id).unwrap();
    assert!(!owner.is_durable(&admitted));
    assert_eq!(
        crate::studio::worktree::worktree_lease::load_leases(&store).await?,
        vec![conflicting]
    );
    assert!(writer.shutdown().await.is_err());
    Ok(())
}

#[tokio::test]
async fn failed_session_retention_follows_only_the_original_confirmed_binding() -> Result<()> {
    use crate::studio::worktree::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity};
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let mut prepared = lease(temp.path(), "failed-root");
    prepared.owner_kind = WorktreeLeaseOwnerKind::Session;
    prepared.root_thread_id = prepared.owner_thread_id.clone();
    prepared.path = WorktreeManager::allocate_path(
        temp.path(),
        &prepared.root_thread_id,
        &WorktreeOwnership::Session {
            thread_id: prepared.owner_thread_id.clone(),
        },
    )
    .to_string_lossy()
    .into_owned();
    owner.record_durable(prepared.clone()).await?;
    let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, prepared.path.clone())?;
    let usage = owner.reserve_workspace(&prepared.owner_thread_id, WorkspaceEndpoint::Local)?;
    owner.assign_workspace(&usage, identity.clone())?;
    let active = owner.confirm_verified_binding(&prepared, &usage).await?;
    let mut retained = owner.preserve_failed_session_binding(&prepared).await?;
    assert_eq!(retained.state, WorktreeLeaseState::Preserved);
    assert_eq!(retained.revision, active.revision + 1);
    assert!(owner.is_durable(&retained));
    assert_eq!(
        owner.preserve_failed_session_binding(&prepared).await?,
        retained
    );
    let mut other_binding = prepared.clone();
    other_binding.base_commit = "b".repeat(40);
    assert!(
        owner
            .preserve_failed_session_binding(&other_binding)
            .await
            .is_err()
    );
    let mut conflicting_revision = retained.clone();
    conflicting_revision.state = WorktreeLeaseState::Active;
    assert!(
        owner
            .preserve_failed_session_binding(&conflicting_revision)
            .await
            .is_err()
    );
    for state in [
        WorktreeLeaseState::CleanupRequested,
        WorktreeLeaseState::Cleaned,
    ] {
        retained.transition(state);
        owner.record_durable(retained.clone()).await?;
        assert!(
            owner
                .preserve_failed_session_binding(&prepared)
                .await
                .is_err()
        );
        assert_eq!(owner.get(&prepared.owner_thread_id), Some(retained.clone()));
    }
    retained.transition(WorktreeLeaseState::Active);
    owner.record_durable(retained.clone()).await?;
    drop(usage);
    let removing = owner.begin_workspace_cleanup(&prepared.owner_thread_id, &identity, None)?;
    assert!(
        owner
            .preserve_failed_session_binding(&prepared)
            .await
            .is_err()
    );
    drop(removing);
    owner.restore_workspace_seal(&prepared.owner_thread_id, identity)?;
    assert!(
        owner
            .preserve_failed_session_binding(&prepared)
            .await
            .is_err()
    );
    assert_eq!(owner.get(&prepared.owner_thread_id), Some(retained));
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn cleaned_reentry_waits_for_its_completion_commit_and_ack() -> Result<()> {
    use crate::agent::worktree::WorktreeCleanupPolicy;
    use crate::studio::worktree::workspace_preparation::cleanup_workspace;
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let (writer, persistence) = ControlledPersistence::writer(store.clone());
    let leases = WorktreeLeaseOwner::new(writer.clone());
    let unchanged = lease(temp.path(), "already-durable");
    leases.record_durable(unchanged.clone()).await?;
    // A failed identity check or physical postcondition must retain a durable cleanup owner,
    // not publish Cleaned or delete a replacement directory. Branch observations never grant
    // or revoke identity and refs remain outside this deletion boundary.
    for (id, identity_conflict) in [("changed-backlink", true), ("replacement-path", false)] {
        let prepared = lease(temp.path(), id);
        leases.record_durable(prepared.clone()).await?;
        let mut io = CleanupIo::new(&prepared);
        if identity_conflict {
            io.identity_conflict = true;
        } else {
            io.replacement_after_remove.store(true, Ordering::Release);
        }
        let io = Arc::new(io);
        let manager = WorktreeManager::new(temp.path().to_owned(), io.clone());
        assert!(
            cleanup_workspace(
                &store,
                &leases,
                &manager,
                prepared,
                WorktreeCleanupPolicy::Safe
            )
            .await
            .is_err()
        );
        let pending = leases.get(id).context("pending cleanup identity")?;
        assert_eq!(pending.state, WorktreeLeaseState::Preserved);
        assert!(leases.is_durable(&pending));
        assert_eq!(
            io.removals.load(Ordering::Acquire),
            usize::from(!identity_conflict)
        );
        assert!(io.path_exists(temp.path(), &io.path).await?);
    }
    let prepared = lease(temp.path(), "cleanup");
    leases.record_durable(prepared.clone()).await?;
    let io = Arc::new(CleanupIo::new(&prepared));
    let manager = WorktreeManager::new(temp.path().to_owned(), io.clone());
    store.database().execute_unprepared("CREATE TRIGGER reject_cleaned BEFORE UPDATE ON studio_objects WHEN json_extract(NEW.payload_json,'$.state')='cleaned' BEGIN SELECT RAISE(ABORT,'controlled completion rejection'); END").await?;
    assert!(
        cleanup_workspace(
            &store,
            &leases,
            &manager,
            prepared,
            WorktreeCleanupPolicy::Safe
        )
        .await
        .is_err()
    );
    let cleaned = leases.get("cleanup").context("retained cleanup phase")?;
    assert_eq!(cleaned.state, WorktreeLeaseState::Cleaned);
    assert!(!leases.is_durable(&cleaned));
    leases
        .record_durable(unchanged)
        .await
        .context("an unrelated blocked completion cannot invalidate an earlier lease receipt")?;
    assert!(
        cleanup_workspace(
            &store,
            &leases,
            &manager,
            cleaned.clone(),
            WorktreeCleanupPolicy::Safe
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
    cleanup_workspace(
        &store,
        &leases,
        &manager,
        cleaned,
        WorktreeCleanupPolicy::Safe,
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
    *persistence.gate.lock().unwrap() = Some(LeaseAckGate {
        state: WorktreeLeaseState::Cleaned,
        entered,
        release: released,
    });
    let cleanup_leases = leases.clone();
    let cleanup_store = store.clone();
    let cleanup_manager = manager.clone();
    let cleanup = tokio::spawn(async move {
        cleanup_workspace(
            &cleanup_store,
            &cleanup_leases,
            &cleanup_manager,
            next,
            WorktreeCleanupPolicy::Safe,
        )
        .await
    });
    waiting.await?;
    cleanup.abort();
    assert!(cleanup.await.unwrap_err().is_cancelled());
    let mut cleaned = leases
        .get("cancelled-cleanup")
        .context("cancelled completion phase")?;
    // A subsequent logical observation must not bypass the pending receipt.
    cleaned.transition(WorktreeLeaseState::Cleaned);
    let mut pending = Box::pin(leases.record_durable(cleaned.clone()));
    assert!(futures::poll!(&mut pending).is_pending());
    drop(pending); // The queued completion remains owned by the writer.
    let mut retry = Box::pin(cleanup_workspace(
        &store,
        &leases,
        &manager,
        cleaned,
        WorktreeCleanupPolicy::Safe,
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
    cleanup_workspace(
        &store,
        &leases,
        &manager,
        cleaned,
        WorktreeCleanupPolicy::Safe,
    )
    .await?;
    assert_eq!(io.removals.load(Ordering::Acquire), 1);
    assert!(leases.is_durable(&leases.get("cancelled-cleanup").unwrap()));
    io.replacement_after_remove.store(true, Ordering::Release);
    let cleaned = leases
        .get("cancelled-cleanup")
        .context("durable completion")?;
    assert!(
        cleanup_workspace(
            &store,
            &leases,
            &manager,
            cleaned,
            WorktreeCleanupPolicy::Safe
        )
        .await
        .is_err(),
        "a completion retry must not delete a replacement checkout"
    );
    assert!(io.path_exists(temp.path(), &io.path).await?);
    assert_eq!(io.removals.load(Ordering::Acquire), 1);
    writer.shutdown().await?;
    Ok(())
}
