//! Archive admission at real binding confirmation and restricted review feedback consumers.
use crate::thread_assembler::{
    StudioActivationFactory, StudioThreadAssembler, StudioThreadSpec, ThreadActivation,
    ThreadAssemblyError, ThreadPreparation, archive_test_spec as spec,
};
use crate::{
    studio::{
        StudioStore,
        agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
        storage_fault_test_support::{
            ThreadStorageSink, close_factory, save_terminal_report,
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
use anyhow::Context;
use pl_core::{
    context::OpaquePayload,
    thread::{ThreadHandle, cold::ColdStoreHandle, inbox::ThreadMessage},
};

#[tokio::test]
async fn archive_seal_rejects_late_factory_binding_confirmation() -> anyhow::Result<()> {
    check_sealed_factory_binding(true).await
}

#[tokio::test]
async fn archive_registry_seal_rejects_factory_binding_before_scope_commit() -> anyhow::Result<()> {
    check_sealed_factory_binding(false).await
}

/// Captures the real preparation issued by activate_owned; no test-created admission or
/// fallback owner substitutes for the registry identity being exercised below.
type PreparationHandoff = (ThreadPreparation, tokio::sync::oneshot::Sender<()>);

#[derive(Debug)]
struct CapturedPreparation {
    entered: std::sync::Mutex<Option<tokio::sync::oneshot::Sender<PreparationHandoff>>>,
}

impl StudioActivationFactory for CapturedPreparation {
    async fn root_delegation(
        &self,
        _: &ThreadActivation,
    ) -> Result<pl_protocol::DelegationSettings, ThreadAssemblyError> {
        Ok(Default::default())
    }

    async fn prepare(
        &self,
        request: ThreadPreparation,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        let (release, waiting) = tokio::sync::oneshot::channel();
        let entered = self
            .entered
            .lock()
            .unwrap()
            .take()
            .ok_or(ThreadAssemblyError::Closed)?;
        entered
            .send((request, release))
            .map_err(|_| ThreadAssemblyError::Closed)?;
        // Dropping the test's sender also releases this owner on an early test error.
        let _ = waiting.await;
        Err(ThreadAssemblyError::Closed)
    }
}

async fn check_sealed_factory_binding(durable: bool) -> anyhow::Result<()> {
    use crate::{
        agent::worktree::{WorktreeManager, WorktreeOwnership},
        studio::agent_host::worktree_lease::{
            WorktreeLease, WorktreeLeaseOwnerKind, WorktreeLeaseState,
        },
    };
    let temp = tempfile::tempdir()?;
    let root = dunce::canonicalize(temp.path())?;
    let store = StudioStore::open(root.join("home/data/studio.sqlite")).await?;
    let physical = close_factory(&store)?;
    let factory = &physical.factory;
    let owner = StudioThreadAssembler::default();
    physical.install(&owner)?;
    let mut protocol = pl_protocol::Thread::placeholder("root");
    protocol.workspace_id = "review-workspace".into();
    protocol.root_thread_id = "root".into();
    protocol.workspace_path = root.to_string_lossy().into_owned();
    register(&store, &protocol, &protocol.workspace_path).await?;
    let path = WorktreeManager::allocate_path(
        &root,
        "root",
        &WorktreeOwnership::Session {
            thread_id: "root".into(),
        },
    );
    let mut lease = WorktreeLease {
        revision: 1,
        state: WorktreeLeaseState::Prepared,
        owner_kind: WorktreeLeaseOwnerKind::Session,
        owner_thread_id: "root".into(),
        root_thread_id: "root".into(),
        workspace_id: protocol.workspace_id.clone(),
        ssh_alias: None,
        repository_root: protocol.workspace_path.clone(),
        path: path.to_string_lossy().into_owned(),
        base_commit: "a".repeat(40),
    };
    let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, lease.path.clone())?;
    let usage = factory
        .services
        .worktrees
        .reserve_workspace("root", WorkspaceEndpoint::Local)?;
    factory
        .services
        .worktrees
        .assign_workspace(&usage, identity.clone())?;
    factory
        .services
        .worktrees
        .record_durable(lease.clone())
        .await?;
    let (entered, waiting) = tokio::sync::oneshot::channel();
    let activating = owner.clone();
    let activation = tokio::spawn(async move {
        activating
            .activate(
                ThreadActivation {
                    id: "root".into(),
                    parent_id: None,
                },
                CapturedPreparation {
                    entered: std::sync::Mutex::new(Some(entered)),
                },
            )
            .await
    });
    let (preparation, release) =
        tokio::time::timeout(std::time::Duration::from_secs(5), waiting).await??;
    preparation.workspace_owner.retain(&usage);
    // Establish a valid binding through the real factory boundary before sealing it.
    factory
        .confirm_worktree_binding(&lease, &usage, &preparation.workspace_owner)
        .await?;
    lease = factory.services.worktrees.get("root").unwrap();
    lease.transition(WorktreeLeaseState::Preserved);
    factory
        .services
        .worktrees
        .record_durable(lease.clone())
        .await?;
    let scope = if durable {
        let paths = store.registered_session_paths("root")?;
        store
            .save_thread_archive(&ThreadArchiveOperation {
                scope: ArchiveScope::Thread("root".into()),
                revision: 1,
                members: vec![ArchiveMember {
                    parent_id: None,
                    thread_id: "root".into(),
                    workspace_id: protocol.workspace_id.clone(),
                    root_id: "root".into(),
                    host_session: paths.root().into(),
                    host_temp: paths.temp_dir(),
                    execution: identity,
                    host_cleaned: false,
                    execution_cleaned: false,
                }],
                private_members: Vec::new(),
                phase: ArchivePhase::Sealed,
            })
            .await?;
        None
    } else {
        let scope = owner.seal_archive_scope(&["root".into()])?;
        assert_eq!(scope.thread_ids(), vec!["root".to_owned()]);
        assert!(
            !preparation.cancellation.is_cancelled(),
            "the volatile seal must win before durable commit and cancellation"
        );
        assert!(store.thread_archives().await?.is_empty());
        store
            .ensure_archive_execution_allowed(&protocol.workspace_id, Some("root"))
            .await?;
        Some(scope)
    };
    let failure = tokio::time::timeout(
        std::time::Duration::from_secs(5),
        factory.confirm_worktree_binding(&lease, &usage, &preparation.workspace_owner),
    )
    .await?
    .unwrap_err();
    if durable {
        assert!(
            failure
                .to_string()
                .contains("archive cleanup must be retried"),
            "{failure:#}"
        );
    } else {
        assert!(
            matches!(
                failure.downcast_ref::<ThreadAssemblyError>(),
                Some(ThreadAssemblyError::Closed)
            ),
            "{failure:#}"
        );
    }
    assert_eq!(factory.services.worktrees.get("root"), Some(lease.clone()));
    assert_eq!(
        crate::studio::agent_host::worktree_lease::load_leases(&store).await?,
        vec![lease]
    );
    assert!(owner.thread("root").is_none(), "no owner may be published");
    drop(preparation);
    drop(release);
    // Coalesced activation preserves the original failure under its public typed wrapper.
    let activation_result = activation.await?;
    assert!(
        matches!(
            &activation_result,
            Err(ThreadAssemblyError::ActivationFailed(source))
                if matches!(source.as_ref(), ThreadAssemblyError::Closed)
        ),
        "{activation_result:?}"
    );
    drop(scope);
    physical.shutdown().await?;
    Ok(())
}

async fn register(
    store: &StudioStore,
    protocol: &pl_protocol::Thread,
    root: &str,
) -> anyhow::Result<()> {
    let mut delta = DirectoryDelta::upsert_project(ProjectDirectoryRecord {
        id: protocol.workspace_id.clone(),
        kind: pl_protocol::studio::WorkspaceKind::Project,
        name: "Review fixture".into(),
        path: root.into(),
        ssh_alias: None,
        created_at: 1,
        updated_at: 1,
        last_opened_at: None,
        closed: false,
    });
    delta.thread_upserts.push(protocol.clone());
    store.persist_directory_summaries(&delta).await
}

async fn restore_delivery(
    owner: &StudioThreadAssembler,
    store: &StudioStore,
    id: &str,
    assignment: &pl_protocol::AgentWorkspaceAssignmentSnapshot,
) -> anyhow::Result<(ThreadHandle, tokio::task::JoinHandle<()>, String)> {
    let mut protocol = pl_protocol::Thread::placeholder(id);
    protocol.workspace_id = "review-workspace".into();
    protocol.parent_thread_id = Some("root".into());
    protocol.root_thread_id = "root".into();
    protocol.workspace_path = assignment.root.clone();
    register(store, &protocol, &assignment.project_root).await?;
    let turn = pl_core::thread::TurnRecord {
        turn_id: "original-terminal-turn".into(),
        input_id: None,
        state: pl_core::thread::TurnState::Finished(pl_core::thread::TurnOutcome::Completed),
        model_steps: 0,
        elapsed_ms: None,
    };
    let review = (assignment.mode == pl_protocol::AgentWorkspaceMode::Review).then(|| {
        serde_json::json!({
            "target": assignment.review_target,
            "disposition": pl_tool::finish_turn::ReviewDisposition::NeedsChanges,
            "reason": null,
        })
    });
    let body = serde_json::to_string(&serde_json::json!({
        "childId": id,
        "commitSequence": 1,
        "turn": turn,
        "turnId": "original-terminal-turn",
        "inputId": null,
        "review": review,
        "message": "immutable original review evidence",
        "messages": [],
        "runningTasks": [],
        "pendingInteractions": [],
        "permissions": [],
    }))?;
    save_terminal_report(
        store,
        &protocol,
        ThreadMessage {
            id: crate::studio::agent_close::terminal_report_id(id, 1),
            kind: pl_core::context::AgentMessageKind::Report,
            source_id: format!("studio.child:{id}"),
            payload: OpaquePayload::new("pl.studio.turn-report", 3, body.clone())?,
            context: vec![pl_core::context::ContextContent::Text {
                text: body.clone().into(),
            }],
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
    Ok((thread, projection, body))
}

#[tokio::test]
async fn archive_sealed_review_feedback_remains_rejected_after_volatile_seal_drops()
-> anyhow::Result<()> {
    let temp = tempfile::tempdir()?;
    let root = dunce::canonicalize(temp.path())?
        .to_string_lossy()
        .into_owned();
    let database = temp.path().join("home/data/studio.sqlite");
    let store = StudioStore::open(&database).await.with_context(|| {
        format!(
            "open current review fixture product database {}",
            database.display()
        )
    })?;
    let physical = close_factory(&store)?;
    let owner = StudioThreadAssembler::default();
    physical.install(&owner)?;
    let mut protocol = pl_protocol::Thread::placeholder("root");
    protocol.workspace_id = "review-workspace".into();
    protocol.root_thread_id = "root".into();
    protocol.workspace_path = root.clone();
    register(&store, &protocol, &root).await?;
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
    let (target, target_projection, _) =
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
    let (_, reviewer_projection, original_body) =
        restore_delivery(&owner, &store, "reviewer", &review_assignment).await?;
    let binding = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, root)?;
    for id in ["root", "target", "reviewer"] {
        store.bind_workspace_identity(id, &binding).await?;
    }
    // Prove this is an otherwise valid physical/frozen target, not a rejection by a bad fixture.
    drop(
        physical
            .factory
            .verify_review_workspace("target", &assignment)
            .await?,
    );
    let seal = owner.seal_archive_scope(&["root".into()])?;
    let mut members = Vec::new();
    for id in seal.thread_ids() {
        let paths = store.registered_session_paths(&id)?;
        members.push(ArchiveMember {
            parent_id: (id != "root").then(|| "root".into()),
            thread_id: id,
            workspace_id: "review-workspace".into(),
            root_id: "root".into(),
            host_session: paths.root().into(),
            host_temp: paths.temp_dir(),
            execution: binding.clone(),
            host_cleaned: false,
            execution_cleaned: false,
        });
    }
    assert_eq!(members.len(), 3, "freeze the whole admitted registry scope");
    store
        .save_thread_archive(&ThreadArchiveOperation {
            scope: ArchiveScope::Thread("root".into()),
            revision: 1,
            members,
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
            body: &original_body,
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
    assert_eq!(
        store
            .history("reviewer")
            .await?
            .parent_report(1)
            .await?
            .unwrap()
            .payload
            .content(),
        original_body
    );
    owner.close_tree("root").await?;
    target_projection.await?;
    reviewer_projection.await?;
    physical.shutdown().await?;
    Ok(())
}
