//! Session-scope close guarantees of the real [`SessionTable`]/[`SessionRuntime`] owners.
//!
//! These regressions drive the production session generation API directly: members are real
//! assembled core handles (via `archive_test_spec`) behind explicit typed identities, barriers
//! are the storage flush boundary, and no parallel reimplementation of the close algorithm
//! exists here. Admission assertions only prove the production admission gate
//! (`ensure_agent_admission_open`) and the assembly path stay usable; real model input and
//! spawn/send dispatch keep their coverage in the existing production integration tests.
//! Member-level archive retention proofs live in `thread_assembler/archive_scope_tests.rs`
//! and are not duplicated.
use super::*;
use crate::thread_assembler::{ThreadActivation, archive_test_spec};
use pl_core::thread::cold::{
    ColdStore, ColdStoreError, ColdStoreHandle, StoragePressure, ThreadWrite,
};
use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicUsize, Ordering},
};
use std::time::Duration;

/// Real storage boundary used as the close barrier: `flush` counts, publishes entry, and can
/// block on a gate or fail on demand. `admit` accepts writes so the member close really joins
/// this store, exactly like the deletion fixtures in `thread_service`.
#[derive(Debug, Clone)]
pub(crate) struct ProbeStore {
    pub(crate) flushes: Arc<AtomicUsize>,
    fail: Arc<AtomicBool>,
    pub(crate) gate: Arc<tokio::sync::Semaphore>,
    entered: tokio::sync::watch::Sender<bool>,
}

impl ProbeStore {
    /// `gated` starts the flush barrier closed; the test releases it explicitly.
    pub(crate) fn open(gated: bool) -> (Self, tokio::sync::watch::Receiver<bool>) {
        let (entered, entered_rx) = tokio::sync::watch::channel(false);
        (
            Self {
                flushes: Arc::new(AtomicUsize::new(0)),
                fail: Arc::new(AtomicBool::new(false)),
                gate: Arc::new(tokio::sync::Semaphore::new(if gated {
                    0
                } else {
                    usize::MAX >> 8
                })),
                entered,
            },
            entered_rx,
        )
    }
}

impl ColdStore for ProbeStore {
    fn pressure(&self, _thread_id: &str) -> StoragePressure {
        StoragePressure::default()
    }

    fn admit(&self, _thread_id: &str, _write: ThreadWrite) -> Result<(), ColdStoreError> {
        Ok(())
    }

    async fn flush(&self, _thread_id: &str, _sequence: u64) -> Result<(), ColdStoreError> {
        self.flushes.fetch_add(1, Ordering::SeqCst);
        let _ = self.entered.send(true);
        self.gate
            .acquire()
            .await
            .expect("probe gate stays open for the owning test")
            .forget();
        if self.fail.load(Ordering::SeqCst) {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("probe flush failure")),
            });
        }
        Ok(())
    }
}

/// Explicit typed identity for the owning session: Session, Agent and Thread ids all come from
/// real fixture values and the session's own id, so no fixture assumes a fixed test session.
/// Parentage names the parent member, mirroring the production `AgentThreadIdentity` checks.
fn explicit_activation(session: &str, id: &str, parent: Option<&str>) -> ThreadActivation {
    ThreadActivation {
        agent: pl_protocol::AgentThreadIdentity {
            session_id: pl_protocol::SessionId::new(session).expect("valid fixture session"),
            agent_id: pl_protocol::AgentId::new(id).expect("valid fixture agent"),
            parent_agent_id: parent
                .map(pl_protocol::AgentId::new)
                .transpose()
                .expect("valid fixture parent agent"),
            thread_id: pl_protocol::ThreadId::new(id).expect("valid fixture thread"),
        },
        parent_thread_id: parent
            .map(pl_protocol::ThreadId::new)
            .transpose()
            .expect("valid fixture parent thread"),
        binding: pl_protocol::AgentBinding::Native(pl_protocol::NativeAgentConfig {
            route: None,
            system_instructions: None,
        }),
    }
}

/// Assembles one real member of the owning session generation: explicit identity bound to
/// `session.id()`, optional parent for descendant topologies, optional probe storage. Each
/// session keeps a single root; siblings and later members hang off that root.
pub(crate) async fn member_with_probe(
    session: &SessionRuntime,
    id: &str,
    parent: Option<&str>,
    store: Option<&ProbeStore>,
    root: &std::path::Path,
) -> Result<(), crate::thread_assembler::ThreadAssemblyError> {
    session.install_explicit_activation(explicit_activation(session.id().as_str(), id, parent));
    let mut spec = archive_test_spec(id.to_owned(), parent.map(str::to_owned), root);
    if let Some(store) = store {
        spec.cold_store = Some(ColdStoreHandle::new(store.clone()));
    }
    session.assemble(spec).await.map(drop)
}

#[tokio::test]
async fn closing_one_session_keeps_the_other_generation_open_for_assembly_and_admission() {
    let table = SessionTable::new();
    let a = table
        .materialize(&pl_protocol::SessionId::new("session-a").unwrap())
        .unwrap();
    let b = table
        .materialize(&pl_protocol::SessionId::new("session-b").unwrap())
        .unwrap();
    let (store_a, _) = ProbeStore::open(false);
    let (store_b, _) = ProbeStore::open(false);
    let root_a = tempfile::tempdir().unwrap();
    member_with_probe(&a, "thread-a", None, Some(&store_a), root_a.path())
        .await
        .unwrap();
    let root_b = tempfile::tempdir().unwrap();
    member_with_probe(&b, "thread-b", None, Some(&store_b), root_b.path())
        .await
        .unwrap();

    let report = a.close_session().await;
    assert!(
        report.is_empty(),
        "session-a members close cleanly: {report:?}"
    );
    assert_eq!(a.phase(), SessionPhase::Closed);
    assert!(!a.hosts("thread-a"));
    assert!(a.observed_thread("thread-a").is_none());
    // A closed generation rejects new assembly and its former members fail the admission gate.
    let late = tempfile::tempdir().unwrap();
    assert!(
        a.assemble(archive_test_spec("thread-a-late".into(), None, late.path()))
            .await
            .is_err()
    );
    assert!(a.ensure_agent_admission_open("thread-a").is_err());

    // Session B's generation stays usable: admission gate open, root member still resident,
    // and a descendant member still assembles and closes through the real storage boundary.
    // This proves the generation scope only; real spawn/send stays with production tests.
    assert_eq!(b.phase(), SessionPhase::Open);
    assert!(b.observed_thread("thread-b").is_some());
    assert!(b.ensure_agent_admission_open("thread-b").is_ok());
    let member_b2 = tempfile::tempdir().unwrap();
    member_with_probe(
        &b,
        "thread-b-2",
        Some("thread-b"),
        Some(&store_b),
        member_b2.path(),
    )
    .await
    .unwrap();
    b.close("thread-b-2").await.unwrap();
    assert_eq!(store_b.flushes.load(Ordering::SeqCst), 1);
    assert!(table.holding("thread-b").is_some());
}

#[tokio::test]
async fn cancelled_first_close_waiter_keeps_the_shared_run_for_the_second_join() {
    let session = SessionRuntime::default();
    let (store, mut entered) = ProbeStore::open(true);
    let member = tempfile::tempdir().unwrap();
    member_with_probe(&session, "member", None, Some(&store), member.path())
        .await
        .unwrap();

    // Box::pin owns the waiter future, so dropping it really cancels that waiter instead of
    // merely releasing a borrow of a still-live stack future.
    let mut first = Box::pin(session.close_session());
    assert!(futures::poll!(&mut first).is_pending());
    // Deterministic barrier: the close run has really entered the blocked flush.
    entered
        .wait_for(|entered| *entered)
        .await
        .expect("flush entered");
    drop(first);

    let second = session.close_session();
    store.gate.add_permits(1);
    let report = tokio::time::timeout(Duration::from_secs(5), second)
        .await
        .expect("second waiter joins the same close run");
    assert!(report.is_empty(), "{report:?}");
    assert_eq!(session.phase(), SessionPhase::Closed);
    assert!(session.observed_thread("member").is_none());
    // Exactly one flush proves dropping the first waiter neither cancelled nor restarted the run.
    assert_eq!(store.flushes.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn failed_branch_finishes_siblings_and_retry_releases_them_only_once() {
    let session = SessionRuntime::default();
    let (ok_store, _) = ProbeStore::open(false);
    let (flaky_store, _) = ProbeStore::open(false);
    // One real session tree: a single root with two probe-bound child branches.
    let root_dir = tempfile::tempdir().unwrap();
    member_with_probe(&session, "root", None, None, root_dir.path())
        .await
        .unwrap();
    let ok_dir = tempfile::tempdir().unwrap();
    member_with_probe(&session, "ok", Some("root"), Some(&ok_store), ok_dir.path())
        .await
        .unwrap();
    let flaky_dir = tempfile::tempdir().unwrap();
    member_with_probe(
        &session,
        "flaky",
        Some("root"),
        Some(&flaky_store),
        flaky_dir.path(),
    )
    .await
    .unwrap();

    flaky_store.fail.store(true, Ordering::SeqCst);
    let report = session.close_session().await;
    assert!(
        report.iter().any(|(id, _)| id == "flaky"),
        "the failing branch is reported: {report:?}"
    );
    assert!(
        !report.iter().any(|(id, _)| id == "ok"),
        "the sibling branch really finished: {report:?}"
    );
    assert_eq!(session.phase(), SessionPhase::Closing);
    assert!(session.observed_thread("ok").is_none());
    assert!(session.observed_thread("flaky").is_some());
    assert_eq!(ok_store.flushes.load(Ordering::SeqCst), 1);
    assert_eq!(flaky_store.flushes.load(Ordering::SeqCst), 1);

    flaky_store.fail.store(false, Ordering::SeqCst);
    let retry = tokio::time::timeout(Duration::from_secs(5), session.close_session())
        .await
        .expect("retry completes after the failed run truly ended");
    assert!(retry.is_empty(), "{retry:?}");
    assert_eq!(session.phase(), SessionPhase::Closed);
    assert!(session.observed_thread("flaky").is_none());
    assert!(session.observed_thread("root").is_none());
    // The retry only re-releases the failed member; the finished sibling is not released twice.
    assert_eq!(ok_store.flushes.load(Ordering::SeqCst), 1);
    assert_eq!(flaky_store.flushes.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn deleting_one_descendant_does_not_close_the_session_generation() {
    let session = SessionRuntime::default();
    let (store, _) = ProbeStore::open(false);
    let root_dir = tempfile::tempdir().unwrap();
    member_with_probe(&session, "keeper-root", None, None, root_dir.path())
        .await
        .unwrap();
    let delete_dir = tempfile::tempdir().unwrap();
    member_with_probe(
        &session,
        "delete-me",
        Some("keeper-root"),
        Some(&store),
        delete_dir.path(),
    )
    .await
    .unwrap();
    let survivor_dir = tempfile::tempdir().unwrap();
    member_with_probe(
        &session,
        "survivor",
        Some("keeper-root"),
        Some(&store),
        survivor_dir.path(),
    )
    .await
    .unwrap();

    session
        .close_tree_for_deletion("delete-me", &[])
        .await
        .unwrap();
    assert_eq!(session.phase(), SessionPhase::Open);
    assert!(session.observed_thread("delete-me").is_none());
    assert!(session.observed_thread("survivor").is_some());
    assert!(session.observed_thread("keeper-root").is_some());
    assert!(session.ensure_agent_admission_open("survivor").is_ok());
    // The generation still accepts a new descendant member after a descendant deletion.
    let after_delete_dir = tempfile::tempdir().unwrap();
    member_with_probe(
        &session,
        "after-delete",
        Some("keeper-root"),
        Some(&store),
        after_delete_dir.path(),
    )
    .await
    .unwrap();
    // Deletion is the non-preserving close purpose: it must not produce a preservation flush,
    // matching the durable-deletion contract in thread_service/delete_required_tests.
    assert_eq!(
        store.flushes.load(Ordering::SeqCst),
        0,
        "deleting a descendant must not flush a preservation receipt"
    );
}

#[tokio::test]
async fn foreign_session_identity_is_rejected_by_the_owning_generation() {
    let session = SessionRuntime::open(
        pl_protocol::SessionId::new("session-a").expect("valid fixture session"),
    );
    session.install_explicit_activation(explicit_activation("session-b", "thread-x", None));
    let temp = tempfile::tempdir().unwrap();
    let error = session
        .assemble(archive_test_spec("thread-x".into(), None, temp.path()))
        .await
        .expect_err("activation must match the owning session identity");
    assert!(matches!(
        error,
        crate::thread_assembler::ThreadAssemblyError::Identity(_)
    ));
}
