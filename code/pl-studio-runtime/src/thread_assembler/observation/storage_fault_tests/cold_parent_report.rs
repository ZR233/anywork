//! Recovery starts with a genuinely cold parent, not a pre-added executable fixture Entry.
use super::*;
use crate::studio::storage_fault_test_support::{close_factory, save_terminal_report};
use crate::thread_assembler::EntryPurpose;
use crate::thread_assembler::close_storage::{AttachmentAckGate, CloseStorage};

/// A fixed, contract-valid terminal report, frozen once for both payload and context. Its Turn
/// matches save_terminal_report; later checkpoints must never rebuild this original evidence.
fn frozen_report_body(
    child: &pl_protocol::Thread,
    sequence: u64,
    evidence: &str,
) -> Result<String> {
    let turn = TurnRecord {
        turn_id: "original-terminal-turn".into(),
        input_id: None,
        state: TurnState::Finished(TurnOutcome::Completed),
        model_steps: 0,
        elapsed_ms: None,
    };
    Ok(serde_json::to_string(&serde_json::json!({
        "childId": child.id,
        "commitSequence": sequence,
        "turn": turn,
        "message": evidence,
        "messages": [],
        "runningTasks": [],
        "pendingInteractions": [],
        "permissions": [],
    }))?)
}

/// Only the environment is synthetic: activation opens the real model session, attaches the real
/// history sink and publishes through the ordinary assembler, not Fixture::add.
struct ReactivationFactory(StudioStore);
impl std::fmt::Debug for ReactivationFactory {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("ReactivationFactory")
    }
}
impl StudioActivationFactory for ReactivationFactory {
    async fn root_delegation(
        &self,
        identity: &ThreadActivation,
    ) -> Result<pl_protocol::DelegationSettings, ThreadAssemblyError> {
        let checkpoint = self
            .0
            .history(&identity.id)
            .await
            .map_err(storage_error)?
            .checkpoint()
            .await
            .map_err(storage_error)?
            .ok_or_else(|| ThreadAssemblyError::Identity(identity.id.clone()))?;
        crate::studio::delegation::saved(&checkpoint.state)
            .map_err(storage_error)?
            .ok_or_else(|| ThreadAssemblyError::Identity(identity.id.clone()))
    }

    async fn prepare(
        &self,
        request: ThreadPreparation,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        let id = request.identity.id;
        let protocol = Fixture::protocol(&id, None);
        let checkpoint = self
            .0
            .history(&id)
            .await
            .map_err(storage_error)?
            .checkpoint()
            .await
            .map_err(storage_error)?;
        let sink = ThreadStorageSink::new(self.0.clone(), protocol, checkpoint.as_ref())
            .await
            .map_err(storage_error)?;
        let model_info = pl_model::model::ModelInfo::compatible("reactivated-model");
        let route = pl_model::config::ResolvedModelRoute {
            pricing_mode: Default::default(),
            role: crate::config::root_agent_route_id(),
            account_id: pl_model::config::AccountId::new("reactivation-account")
                .map_err(storage_error)?,
            endpoint: pl_model::protocol::ProtocolEndpoint::compatible(
                "storage fixture",
                "http://127.0.0.1:0",
            ),
            context: model_info.resolve_context(None),
            model: model_info,
            effort: None,
        };
        let model = pl_model::runtime::ThreadModel::new(
            pl_model::runtime::ModelRuntime::from_route(&route)?,
            None,
        );
        Ok(StudioThreadSpec {
            workspace_usage: None,
            preparation_guard: None,
            context_preparation: None,
            agent_controls: request.agent_controls,
            execution: pl_core::thread::input::InputDriverOptions {
                max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
            },
            id: id.clone(),
            parent_id: None,
            route,
            model_available: true,
            model,
            checkpoint,
            initial_context: Vec::new(),
            initial_runtime_facts: Vec::new(),
            initial_extensions: BTreeMap::new(),
            tools: Vec::new(),
            resources: pl_core::context::ResourceAccess::new(
                crate::resource_store::FileResourceStore::new(
                    self.0.session_resources_dir(&id).map_err(storage_error)?,
                ),
            ),
            capacity: Default::default(),
            cold_store: Some(ColdStoreHandle::new(sink)),
        })
    }
}

async fn save_cold_thread(store: &StudioStore, protocol: &pl_protocol::Thread) -> Result<()> {
    register_test_thread(store, protocol).await?;
    let sink = ThreadStorageSink::new(store.clone(), protocol.clone(), None).await?;
    let projection = spawn_live_projection_for_thread(store.clone(), &protocol.id);
    let channel = store.thread_persistence().history_channel(&protocol.id);
    let thread = ThreadHandle::resume_without_model(protocol.id.clone(), None)?;
    thread.attach_storage(ColdStoreHandle::new(sink)).await?;
    let assignment = pl_protocol::AgentWorkspaceAssignmentSnapshot {
        mode: pl_protocol::AgentWorkspaceMode::Directory,
        project_root: store.paths().home().to_string_lossy().into_owned(),
        root: store.paths().home().to_string_lossy().into_owned(),
        writable_paths: None,
        review_target: None,
        worktree: None,
    };
    thread
        .mutate_extensions(vec![
            pl_core::thread::extensions::ExtensionMutation::Put {
                id: crate::studio::workspace_receipt::EXTENSION.into(),
                expected_revision: None,
                payload: crate::studio::workspace_receipt::to_payload(&assignment)
                    .map_err(anyhow::Error::msg)?,
            },
            pl_core::thread::extensions::ExtensionMutation::Put {
                id: crate::studio::delegation::EXTENSION.into(),
                expected_revision: None,
                payload: crate::studio::delegation::encode(Default::default())?,
            },
        ])
        .await?;
    thread.close().await?;
    channel.stop_and_join().await?;
    projection.await?;
    Ok(())
}

#[derive(Clone, Copy)]
enum RecoveryPath {
    Uninterrupted,
    RetryClose,
    ActivateParent,
}

async fn activate_parent(fixture: &Fixture) -> Result<ThreadHandle> {
    Ok(tokio::time::timeout(
        std::time::Duration::from_secs(10),
        fixture.owner.activate(
            ThreadActivation {
                id: "parent".into(),
                parent_id: None,
            },
            ReactivationFactory(fixture.store.clone()),
        ),
    )
    .await??)
}

#[tokio::test]
async fn cold_parent_close_recovery_releases_receiver_and_preserves_original_ack_after_failure()
-> Result<()> {
    for path in [
        RecoveryPath::Uninterrupted,
        RecoveryPath::RetryClose,
        RecoveryPath::ActivateParent,
    ] {
        let inject_failure = !matches!(path, RecoveryPath::Uninterrupted);
        let mut active = None;
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let parent = Fixture::protocol("parent", None);
        let child = Fixture::protocol("child", Some("parent"));
        // These original storage owners are fully stopped before the new coordinator exists.
        // Never add a parent Entry to the coordinator recovering the saved close.
        save_cold_thread(&store, &parent).await?;
        save_cold_thread(&store, &child).await?;
        let checkpoint = store
            .history("child")
            .await?
            .checkpoint()
            .await?
            .context("saved cold child")?;
        let sequence = checkpoint.history_fence + 1;
        let content = frozen_report_body(
            &child,
            sequence,
            "original terminal body and permission evidence\n\noriginal frozen evidence",
        )?;
        let message = pl_core::thread::inbox::ThreadMessage {
            kind: AgentMessageKind::Report,
            id: crate::studio::agent_close::terminal_report_id("child", sequence),
            source_id: "studio.child:child".into(),
            payload: OpaquePayload::new("pl.studio.turn-report", 1, content.clone())?,
            context: vec![ContextContent::Text {
                text: content.into(),
            }],
        };
        save_terminal_report(&store, &child, message.clone()).await?;
        let resources = close_factory(&store)?;
        let checkpoint = store
            .history("child")
            .await?
            .checkpoint()
            .await?
            .context("terminal child checkpoint")?;
        resources
            .factory
            .begin_child_close(&child, Some(&checkpoint.state), false)
            .await?;
        let fixture = Fixture::new(store.clone())?;
        resources.install(&fixture.owner)?;
        assert!(fixture.owner.0.state().entries.is_empty());
        assert!(
            store
                .history("parent")
                .await?
                .message_identity(&message.id)
                .await?
                .is_none()
        );
        fixture.fail_sync.store(inject_failure, Ordering::SeqCst);
        fixture.fail_drain.store(inject_failure, Ordering::SeqCst);
        let first = tokio::time::timeout(
            std::time::Duration::from_secs(10),
            fixture.owner.resume_agent_closes(),
        )
        .await?;
        let first_receipt = store
            .history("parent")
            .await?
            .message_identity(&message.id)
            .await?
            .context("original report was durably received even when cleanup failed")?;
        assert_eq!(
            first_receipt.digest.as_deref(),
            Some(message.digest().as_str())
        );
        if inject_failure {
            let failure = first.expect_err("both delivery ACK and receiver drain fail");
            let diagnostic = format!("{failure:#}");
            assert!(diagnostic.contains("injected report ACK failure"));
            assert!(diagnostic.contains("injected receiver drain failure"));
            assert!(
                !store
                    .agent_close("child")
                    .await?
                    .context("pending close")?
                    .execution_closed
            );
            assert!(fixture.owner.is_report_receiver("parent"));
            assert!(!fixture.owner.0.state().entries["parent"].ready);
            fixture.fail_sync.store(false, Ordering::SeqCst);
            fixture.fail_drain.store(false, Ordering::SeqCst);
            if matches!(path, RecoveryPath::ActivateParent) {
                // Normal activation itself must release the retained receiver, never return the
                // no-model handle as ready or fail forever with Unpublished.
                active = Some(activate_parent(&fixture).await?);
            }
            tokio::time::timeout(
                std::time::Duration::from_secs(10),
                fixture.owner.resume_agent_closes(),
            )
            .await??;
        } else {
            first?;
        }
        assert_eq!(
            fixture.owner.0.state().entries.contains_key("parent"),
            active.is_some()
        );
        assert!(!fixture.owner.0.state().sealed_agents.contains_key("parent"));
        assert!(store.agent_close("parent").await?.is_none());
        assert!(
            store
                .agent_close("child")
                .await?
                .context("finished close")?
                .execution_closed
        );
        assert_eq!(
            *fixture.closes.lock().unwrap(),
            vec![WorkspaceRelease::Preserve]
        );
        assert_eq!(
            fixture
                .owner
                .acknowledge_parent_reports(&store, &child)
                .await?,
            ParentReportAcknowledgement::Proven
        );
        let receipt = store
            .history("parent")
            .await?
            .message_identity(&message.id)
            .await?
            .context("same durable parent ACK")?;
        assert_eq!(receipt.sequence, first_receipt.sequence);
        assert_eq!(receipt.digest, first_receipt.digest);
        assert_eq!(
            store
                .history("child")
                .await?
                .parent_report(sequence)
                .await?
                .context("unchanged original report")?
                .digest(),
            message.digest()
        );

        let active = match active {
            Some(active) => active,
            None => activate_parent(&fixture).await?,
        };
        assert!(fixture.owner.thread("parent").is_some());
        assert_eq!(
            fixture.owner.0.state().entries["parent"].purpose,
            EntryPurpose::Execution
        );
        let mut followup = message.clone();
        followup.id = "after-recovery".into();
        active.send_message(followup).await?;
        fixture.owner.synchronize_observation("parent").await?;
        assert!(
            store
                .history("parent")
                .await?
                .message_identity("after-recovery")
                .await?
                .is_some()
        );
        assert!(fixture.owner.close_all().await.is_empty());
        fixture.stop_writers().await?;
        resources.shutdown().await?;
    }
    Ok(())
}

struct SavedClose {
    child: pl_protocol::Thread,
    message: pl_core::thread::inbox::ThreadMessage,
    sequence: u64,
}

async fn save_pending_close(
    store: &StudioStore,
    factory: &crate::studio::StudioThreadFactory,
) -> Result<SavedClose> {
    let parent = Fixture::protocol("parent", None);
    let child = Fixture::protocol("child", Some("parent"));
    save_cold_thread(store, &parent).await?;
    save_cold_thread(store, &child).await?;
    let checkpoint = store
        .history("child")
        .await?
        .checkpoint()
        .await?
        .context("cold child checkpoint")?;
    let sequence = checkpoint.history_fence + 1;
    let content = frozen_report_body(
        &child,
        sequence,
        "original body before receiver cancellation or detach\n\noriginal permission evidence",
    )?;
    let message = pl_core::thread::inbox::ThreadMessage {
        kind: AgentMessageKind::Report,
        id: crate::studio::agent_close::terminal_report_id("child", sequence),
        source_id: "studio.child:child".into(),
        payload: OpaquePayload::new("pl.studio.turn-report", 1, content.clone())?,
        context: vec![ContextContent::Text {
            text: content.into(),
        }],
    };
    save_terminal_report(store, &child, message.clone()).await?;
    let checkpoint = store
        .history("child")
        .await?
        .checkpoint()
        .await?
        .context("saved terminal child")?;
    factory
        .begin_child_close(&child, Some(&checkpoint.state), false)
        .await?;
    Ok(SavedClose {
        child,
        message,
        sequence,
    })
}

async fn prove_report_and_reactivate(fixture: &Fixture, saved: &SavedClose) -> Result<()> {
    let store = &fixture.store;
    assert_eq!(
        fixture
            .owner
            .acknowledge_parent_reports(store, &saved.child)
            .await?,
        ParentReportAcknowledgement::Proven
    );
    assert_eq!(
        store
            .history("child")
            .await?
            .parent_report(saved.sequence)
            .await?
            .context("unchanged original body")?
            .digest(),
        saved.message.digest()
    );
    assert_eq!(
        store
            .history("parent")
            .await?
            .message_identity(&saved.message.id)
            .await?
            .context("durable original ID")?
            .digest,
        Some(saved.message.digest())
    );
    assert!(
        store
            .agent_close("child")
            .await?
            .context("completed child close")?
            .execution_closed
    );
    assert!(store.agent_close("parent").await?.is_none());
    assert!(!fixture.owner.0.state().sealed_agents.contains_key("parent"));
    assert!(!fixture.owner.0.state().entries.contains_key("parent"));
    // This inspection cannot create a channel; successful release must not leave a new empty
    // stopping channel behind the original writer that already detached.
    assert!(
        store
            .thread_persistence()
            .retained_history_channel("parent")
            .is_none()
    );
    let active = activate_parent(fixture).await?;
    let current = store
        .thread_persistence()
        .retained_history_channel("parent")
        .context("new active writer")?;
    assert!(!current.is_stopping());
    let mut followup = saved.message.clone();
    followup.id = "after-retained-storage-recovery".into();
    active.send_message(followup.clone()).await?;
    fixture.owner.synchronize_observation("parent").await?;
    assert_eq!(
        store
            .history("parent")
            .await?
            .message_identity(&followup.id)
            .await?
            .context("real followup history write")?
            .digest,
        Some(followup.digest())
    );
    assert!(fixture.owner.close_all().await.is_empty());
    fixture.stop_writers().await
}

#[tokio::test]
async fn detached_receiver_writer_retry_joins_only_the_original_binding() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
    let resources = close_factory(&store)?;
    let saved = save_pending_close(&store, &resources.factory).await?;
    let fixture = Fixture::new(store.clone())?;
    resources.install(&fixture.owner)?;
    assert!(fixture.owner.0.state().entries.is_empty());
    fixture
        .fail_drain_after_writer
        .store(true, Ordering::SeqCst);
    let failed = tokio::time::timeout(
        std::time::Duration::from_secs(10),
        fixture.owner.resume_agent_closes(),
    )
    .await?;
    let error = failed.expect_err("drain fails only after all physical writer workers joined");
    assert!(format!("{error:#}").contains("injected drain failure after writer detach"));
    let binding = fixture
        .owner
        .close_storage_binding("parent")?
        .context("retained exact binding after attachment and close")?;
    assert!(binding.channel.is_stopping());
    assert!(
        store
            .thread_persistence()
            .retained_history_channel("parent")
            .is_none()
    );
    assert!(fixture.owner.is_report_receiver("parent"));
    let first_receipt = store
        .history("parent")
        .await?
        .message_identity(&saved.message.id)
        .await?
        .context("original durable receipt before cleanup retry")?;
    fixture
        .fail_drain_after_writer
        .store(false, Ordering::SeqCst);
    tokio::time::timeout(
        std::time::Duration::from_secs(10),
        fixture.owner.resume_agent_closes(),
    )
    .await??;
    let receipt = store
        .history("parent")
        .await?
        .message_identity(&saved.message.id)
        .await?
        .context("same receipt after exact-binding cleanup")?;
    assert_eq!(receipt.sequence, first_receipt.sequence);
    assert_eq!(receipt.digest, first_receipt.digest);
    assert!(
        store
            .thread_persistence()
            .retained_history_channel("parent")
            .is_none()
    );
    prove_report_and_reactivate(&fixture, &saved).await?;
    resources.shutdown().await
}

#[tokio::test]
async fn cancelled_activation_resumes_the_one_already_effective_attach() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
    let resources = close_factory(&store)?;
    let saved = save_pending_close(&store, &resources.factory).await?;
    let fixture = Fixture::new(store.clone())?;
    resources.install(&fixture.owner)?;
    assert!(fixture.owner.0.state().entries.is_empty());
    // Install only the production cold receiver's retained Pending responsibility. It is not an
    // executable Fixture::add owner; normal activation must settle this very same pending owner.
    {
        let _operation = fixture.owner.agent_operation("parent").await;
        let services = fixture
            .owner
            .0
            .state()
            .agent_services
            .clone()
            .context("close services")?;
        let checkpoint = store
            .history("parent")
            .await?
            .checkpoint()
            .await?
            .context("cold original parent")?;
        services.install_storage_owner(
            &fixture.owner,
            &Fixture::protocol("parent", None),
            checkpoint,
            EntryPurpose::ReportReceiver,
        )?;
    }
    assert!(matches!(
        fixture.owner.0.state().entries["parent"].close_storage,
        Some(CloseStorage::Pending { .. })
    ));
    let (attached, attachment_ack) = tokio::sync::oneshot::channel();
    let (release, released) = tokio::sync::oneshot::channel();
    fixture.owner.0.state().storage_attachment_gate = Some(AttachmentAckGate {
        thread_id: "parent".into(),
        attached,
        release: released,
    });
    let owner = fixture.owner.clone();
    let activating_store = store.clone();
    let activating = tokio::spawn(async move {
        owner
            .activate(
                ThreadActivation {
                    id: "parent".into(),
                    parent_id: None,
                },
                ReactivationFactory(activating_store),
            )
            .await
    });
    tokio::time::timeout(std::time::Duration::from_secs(10), attachment_ack).await??;
    let binding = {
        let state = fixture.owner.0.state();
        let entry = &state.entries["parent"];
        assert!(!entry.ready);
        assert!(entry.thread.snapshot().persistence.attached);
        let Some(CloseStorage::Attaching {
            binding,
            completion,
        }) = &entry.close_storage
        else {
            anyhow::bail!("effective attachment must retain its original shared completion");
        };
        assert!(completion.peek().is_none());
        binding.clone()
    };
    activating.abort();
    assert!(activating.await.unwrap_err().is_cancelled());
    assert!(matches!(
        fixture.owner.0.state().entries["parent"].close_storage,
        Some(CloseStorage::Attaching { .. })
    ));
    release
        .send(())
        .map_err(|_| anyhow::anyhow!("cancelled waiter lost the attachment future"))?;
    // Existing ACK/close recovery re-waits that completion. A second AttachCold would now produce
    // InvalidIdentity from the unchanged core and fail this actual recovery path.
    tokio::time::timeout(
        std::time::Duration::from_secs(10),
        fixture.owner.resume_agent_closes(),
    )
    .await??;
    assert!(binding.channel.is_stopping());
    prove_report_and_reactivate(&fixture, &saved).await?;
    resources.shutdown().await
}
