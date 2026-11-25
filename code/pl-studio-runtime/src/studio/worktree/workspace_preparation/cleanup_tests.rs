use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use futures::{FutureExt, future::BoxFuture};
use sea_orm::ConnectionTrait;

use super::super::worktree_lease::{load_leases, test_support::prepared_child_lease};
use super::*;
use crate::agent::worktree::{WorktreeCreateFailure, WorktreeStatus};
use crate::studio::{
    StudioStore,
    storage::write_behind::{
        ThreadWriteBehindWriter,
        test_support::{wait_for_durable_ticket, writer_with_lease_ack_gate},
    },
};

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
async fn invalid_physical_cleanup_keeps_the_lease_and_checkout() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let leases = WorktreeLeaseOwner::new(writer.clone());
    // A failed identity check or physical postcondition must retain a durable cleanup owner,
    // not publish Cleaned or delete a replacement directory. Branch observations never grant
    // or revoke identity and refs remain outside this deletion boundary.
    for (id, identity_conflict) in [("changed-backlink", true), ("replacement-path", false)] {
        let prepared = prepared_child_lease(temp.path(), id);
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
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn rejected_cleanup_completion_keeps_its_receipt_and_does_not_remove_twice() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let leases = WorktreeLeaseOwner::new(writer.clone());
    let unchanged = prepared_child_lease(temp.path(), "already-durable");
    leases.record_durable(unchanged.clone()).await?;
    let prepared = prepared_child_lease(temp.path(), "cleanup");
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
    wait_for_durable_ticket(&writer, writer.admitted_ticket()).await?;
    cleanup_workspace(
        &store,
        &leases,
        &manager,
        cleaned,
        WorktreeCleanupPolicy::Safe,
    )
    .await?;
    assert_eq!(io.removals.load(Ordering::Acquire), 1);

    assert!(leases.is_durable(&leases.get("cleanup").context("saved completion")?));
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn cancelled_cleanup_reentry_waits_for_its_completion_ack() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let (writer, lease_acks) = writer_with_lease_ack_gate(store.clone());
    let leases = WorktreeLeaseOwner::new(writer.clone());
    let next = prepared_child_lease(temp.path(), "cancelled-cleanup");
    leases.record_durable(next.clone()).await?;
    let io = Arc::new(CleanupIo::new(&next));
    let manager = WorktreeManager::new(temp.path().to_owned(), io.clone());
    let (waiting, release) = lease_acks.arm(&next.owner_thread_id, WorktreeLeaseState::Cleaned);
    let cleanup_leases = leases.clone();
    let cleanup_store = store.clone();
    let cleanup_manager = manager.clone();
    let mut cleanup = tokio::spawn(async move {
        cleanup_workspace(
            &cleanup_store,
            &cleanup_leases,
            &cleanup_manager,
            next,
            WorktreeCleanupPolicy::Safe,
        )
        .await
    });
    tokio::select! {
        committed = waiting => committed.context("writer dropped the cleanup commit gate")?,
        early = &mut cleanup => anyhow::bail!("cleanup returned before its ACK gate: {early:?}"),
    }
    cleanup.abort();
    assert!(cleanup.await.unwrap_err().is_cancelled());
    let mut cleaned = leases
        .get("cancelled-cleanup")
        .context("cancelled completion phase")?;
    assert_eq!(load_leases(&store).await?, vec![cleaned.clone()]);
    assert!(!leases.is_durable(&cleaned));
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
    let completion_ticket = writer.admitted_ticket();
    release
        .send(())
        .map_err(|_| anyhow::anyhow!("completion writer lost its owner"))?;
    writer.flush_through(completion_ticket).await?;
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
