//! Durable archive admission at the actual restricted review feedback consumer.
use crate::thread_assembler::{StudioThreadAssembler, archive_test_spec as spec};
use crate::{
    studio::{
        StudioStore,
        agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
        storage_fault_test_support::{
            ThreadStorageSink, close_factory, register_test_thread, save_terminal_report,
            spawn_live_projection_for_thread,
        },
        store::{
            directory::{DirectoryDelta, ProjectDirectoryRecord},
            thread_archive::{ArchiveMember, ArchivePhase, ArchiveScope, ThreadArchiveOperation},
        },
    },
    thread_assembler::agent_review::{
        ReviewDeliverySource, ReviewFeedbackDelivery, ReviewForward, ReviewForwardReason,
    },
};
use pl_core::{
    context::OpaquePayload,
    thread::{ThreadHandle, cold::ColdStoreHandle, inbox::ThreadMessage},
};

async fn restore_delivery(
    owner: &StudioThreadAssembler,
    store: &StudioStore,
    id: &str,
    assignment: &pl_protocol::AgentWorkspaceAssignmentSnapshot,
) -> anyhow::Result<(ThreadHandle, tokio::task::JoinHandle<()>)> {
    let mut protocol = pl_protocol::Thread::placeholder(id);
    protocol.workspace_id = "review-workspace".into();
    protocol.parent_thread_id = Some("root".into());
    protocol.root_thread_id = "root".into();
    protocol.workspace_path = assignment.root.clone();
    register_test_thread(store, &protocol).await?;
    save_terminal_report(
        store,
        &protocol,
        ThreadMessage {
            id: crate::studio::agent_close::terminal_report_id(id, 1),
            kind: pl_core::context::AgentMessageKind::Report,
            source_id: format!("agent:{id}"),
            payload: OpaquePayload::text("immutable original review evidence"),
            context: Vec::new(),
        },
    )
    .await?;
    let checkpoint = store.history(id).await?.checkpoint().await?;
    let sink = ThreadStorageSink::new(store.clone(), protocol, checkpoint.as_ref()).await?;
    let projection = spawn_live_projection_for_thread(store.clone(), id);
    let mut prepared = spec(
        id.into(),
        Some("root".into()),
        std::path::Path::new(&assignment.root),
    );
    let payload = prepared
        .initial_extensions
        .get_mut(crate::studio::model_route::AGENT_PROFILE_EXTENSION)
        .unwrap();
    let mut profile: pl_protocol::AgentProfileSnapshot = serde_json::from_str(payload.content())?;
    profile.workspace_mode = assignment.mode;
    *payload = crate::studio::model_route::encode_profile(&profile)?;
    prepared.initial_extensions.insert(
        crate::studio::workspace_receipt::EXTENSION.into(),
        crate::studio::workspace_receipt::to_payload(assignment).map_err(anyhow::Error::msg)?,
    );
    prepared.checkpoint = checkpoint;
    prepared.cold_store = Some(ColdStoreHandle::new(sink));
    let thread = owner.assemble(prepared).await?;
    thread.flush().await?;
    Ok((thread, projection))
}

#[tokio::test]
async fn archive_sealed_review_feedback_remains_rejected_after_volatile_seal_drops()
-> anyhow::Result<()> {
    let temp = tempfile::tempdir()?;
    let root = dunce::canonicalize(temp.path())?
        .to_string_lossy()
        .into_owned();
    let store = StudioStore::open(temp.path().join("home/studio.sqlite")).await?;
    let physical = close_factory(&store)?;
    let owner = StudioThreadAssembler::default();
    physical.install(&owner)?;
    let mut protocol = pl_protocol::Thread::placeholder("root");
    protocol.workspace_id = "review-workspace".into();
    protocol.root_thread_id = "root".into();
    register_test_thread(&store, &protocol).await?;
    owner
        .assemble(spec("root".into(), None, temp.path()))
        .await?;
    let assignment = pl_protocol::AgentWorkspaceAssignmentSnapshot {
        mode: pl_protocol::AgentWorkspaceMode::Directory,
        project_root: root.clone(),
        root: root.clone(),
        writable_paths: None,
        review_target: None,
        worktree: None,
    };
    let (target, target_projection) =
        restore_delivery(&owner, &store, "target", &assignment).await?;
    let snapshot = target.snapshot();
    let turn = store
        .history("target")
        .await?
        .latest_turn_at(snapshot.commit_sequence)
        .await?
        .unwrap();
    let baseline = pl_protocol::AgentReviewBaseline {
        turn_id: turn.id,
        input_id: turn.input_id,
        terminal_sequence: turn.revision,
        commit_sequence: snapshot.commit_sequence,
        input_ordinal: snapshot.input_ordinal,
        message_sequence: snapshot.inbox_sequence,
        consumed_messages: snapshot.consumed_messages,
        wake_messages_through: snapshot.wake_messages_through,
        execution_sequence: snapshot.execution_sequence,
        continuation_id: snapshot.continuation.as_ref().map(|point| point.id.clone()),
    };
    let mut review_assignment = assignment.clone();
    review_assignment.mode = pl_protocol::AgentWorkspaceMode::Review;
    review_assignment.review_target = Some(pl_protocol::AgentReviewTargetSnapshot {
        agent_id: "target".into(),
        feedback: Some(pl_protocol::AgentReviewFeedback::ToExecutor),
        baseline: Some(baseline),
    });
    let (_, reviewer_projection) =
        restore_delivery(&owner, &store, "reviewer", &review_assignment).await?;
    store
        .persist_directory_summaries(&DirectoryDelta::upsert_project(ProjectDirectoryRecord {
            id: "review-workspace".into(),
            kind: pl_protocol::studio::WorkspaceKind::Project,
            name: "Review fixture".into(),
            path: root.clone(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        }))
        .await?;
    let binding = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, root)?;
    store.bind_workspace_identity("target", &binding).await?;
    // Prove this is an otherwise valid physical/frozen target, not a rejection by a bad fixture.
    drop(
        physical
            .factory
            .verify_review_workspace("target", &assignment)
            .await?,
    );
    let paths = store.registered_session_paths("target")?;
    let seal = owner.seal_archive_scope(&["target".into()])?;
    store
        .save_thread_archive(&ThreadArchiveOperation {
            scope: ArchiveScope::Thread("target".into()),
            revision: 1,
            members: vec![ArchiveMember {
                thread_id: "target".into(),
                workspace_id: "review-workspace".into(),
                parent_id: Some("root".into()),
                root_id: "root".into(),
                host_session: paths.root().into(),
                host_temp: paths.temp_dir(),
                execution: binding,
                host_cleaned: false,
                execution_cleaned: false,
            }],
            private_members: Vec::new(),
            phase: ArchivePhase::Sealed,
        })
        .await?;
    drop(seal); // The archive failed before retirement; volatile RAII no longer blocks the consumer.
    owner.ensure_agent_admission_open("target")?;
    owner.ensure_agent_admission_open("reviewer")?;
    let before = target.snapshot();
    let outcome = owner
        .forward_review(ReviewFeedbackDelivery {
            reviewer: "reviewer",
            turn_id: "original-terminal-turn",
            terminal_sequence: 1,
            assignment: &review_assignment,
            body: "immutable original review evidence",
            source: ReviewDeliverySource::LiveTerminal,
            revocation: None,
        })
        .await;
    match outcome {
        ReviewForward::Rejected {
            reason: ReviewForwardReason::WorkspaceCheckRejected(error),
            ..
        } => {
            assert!(
                format!("{error:?}").contains("archive cleanup must be retried"),
                "must reach the durable archive gate, not another fixture error: {error:?}"
            );
        }
        other => panic!("real review forwarding bypassed durable archive admission: {other:?}"),
    }
    let after = target.snapshot();
    assert_eq!(before.commit_sequence, after.commit_sequence);
    assert_eq!(before.turns, after.turns);
    assert_eq!(before.inputs, after.inputs);
    assert_eq!(before.inbox_sequence, after.inbox_sequence);
    assert!(after.tasks.is_empty());
    assert_eq!(
        store
            .history("reviewer")
            .await?
            .terminal_report_sequences(0)
            .await?,
        vec![1]
    );
    owner.close_tree("root").await?;
    target_projection.await?;
    reviewer_projection.await?;
    physical.shutdown().await?;
    Ok(())
}
