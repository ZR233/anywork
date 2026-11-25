//! Session-scope close guarantees of the real [`SessionTable`]/[`SessionRuntime`] owners.
//!
//! These regressions drive the production session generation API directly: members are real
//! assembled core handles (via `archive_test_spec`) behind explicit typed identities, and no
//! parallel reimplementation of the close algorithm exists here. Admission assertions only
//! prove the production admission gate
//! (`ensure_agent_admission_open`) and the assembly path stay usable; real model input and
//! spawn/send dispatch keep their coverage in the existing production integration tests.
//! Member-level archive retention proofs live in `thread_assembler/archive_scope_tests.rs`
//! and are not duplicated.
use super::*;
use crate::thread_assembler::{ThreadActivation, archive_test_spec};

/// Explicit typed identity for the owning session: Session, Agent and Thread ids all come from
/// real fixture values and the session's own id, so no fixture assumes a fixed test session.
/// Parentage names the parent member, mirroring the production `AgentThreadIdentity` checks.
fn explicit_activation(session: &str, id: &str, parent: Option<&str>) -> ThreadActivation {
    ThreadActivation {
        agent: crate::AgentThreadIdentity {
            session_id: crate::SessionId::new(session).expect("valid fixture session"),
            agent_id: crate::AgentId::new(id).expect("valid fixture agent"),
            parent_agent_id: parent
                .map(crate::AgentId::new)
                .transpose()
                .expect("valid fixture parent agent"),
            thread_id: crate::ThreadId::new(id).expect("valid fixture thread"),
        },
        parent_thread_id: parent
            .map(crate::ThreadId::new)
            .transpose()
            .expect("valid fixture parent thread"),
        binding: crate::AgentBinding::Native(crate::NativeAgentConfig {
            route: None,
            system_instructions: None,
        }),
    }
}

/// Assembles one real member of the owning session generation: explicit identity bound to
/// `session.id()`, optional parent for descendant topologies. Each
/// session keeps a single root; siblings and later members hang off that root.
pub(crate) async fn member(
    session: &SessionRuntime,
    id: &str,
    parent: Option<&str>,
    root: &std::path::Path,
) -> Result<(), crate::thread_assembler::ThreadAssemblyError> {
    session.install_explicit_activation(explicit_activation(session.id().as_str(), id, parent));
    let spec = archive_test_spec(id.to_owned(), parent.map(str::to_owned), root);
    session.assemble(spec).await.map(drop)
}

#[tokio::test]
async fn closing_one_session_keeps_the_other_generation_open_for_assembly_and_admission() {
    let table = SessionTable::new();
    let a = table
        .materialize(&crate::SessionId::new("session-a").unwrap())
        .unwrap();
    let b = table
        .materialize(&crate::SessionId::new("session-b").unwrap())
        .unwrap();
    let root_a = tempfile::tempdir().unwrap();
    member(&a, "thread-a", None, root_a.path()).await.unwrap();
    let root_b = tempfile::tempdir().unwrap();
    member(&b, "thread-b", None, root_b.path()).await.unwrap();

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
    member(&b, "thread-b-2", Some("thread-b"), member_b2.path())
        .await
        .unwrap();
    b.close("thread-b-2").await.unwrap();
    assert!(table.holding("thread-b").is_some());
}

#[tokio::test]
async fn deleting_one_descendant_does_not_close_the_session_generation() {
    let session = SessionRuntime::default();
    let root_dir = tempfile::tempdir().unwrap();
    member(&session, "keeper-root", None, root_dir.path())
        .await
        .unwrap();
    let delete_dir = tempfile::tempdir().unwrap();
    member(
        &session,
        "delete-me",
        Some("keeper-root"),
        delete_dir.path(),
    )
    .await
    .unwrap();
    let survivor_dir = tempfile::tempdir().unwrap();
    member(
        &session,
        "survivor",
        Some("keeper-root"),
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
    member(
        &session,
        "after-delete",
        Some("keeper-root"),
        after_delete_dir.path(),
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn foreign_session_identity_is_rejected_by_the_owning_generation() {
    let session =
        SessionRuntime::open(crate::SessionId::new("session-a").expect("valid fixture session"));
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
