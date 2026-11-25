use crate::thread_assembler::test_support::*;
use crate::thread_assembler::*;
use anyhow::Context as _;
use pl_core::thread::{ThreadError, ThreadHandle};
// Recovery starts with a genuinely cold parent, not a pre-added executable fixture Entry.

use crate::test_support::storage::{close_factory, save_terminal_report};
use crate::thread_assembler::EntryPurpose;
use crate::thread_assembler::close_storage::{
    CloseStorage, NativeStorageAttachment, StorageAttachment,
};
use crate::thread_assembler::observation::ParentReportAcknowledgement;

#[derive(Debug)]
struct PausedAttachment {
    epoch: pl_core::thread::current::RuntimeEpoch,
    gate: Mutex<
        Option<(
            tokio::sync::oneshot::Sender<()>,
            tokio::sync::oneshot::Receiver<()>,
        )>,
    >,
}
impl StorageAttachment for PausedAttachment {
    fn attach(
        &self,
        thread: ThreadHandle,
        storage: ThreadStorageSink,
        current: Option<Arc<crate::studio::conversation_store::ConversationStore>>,
    ) -> futures::future::BoxFuture<'static, Result<(), Arc<ThreadError>>> {
        let gate = if thread.runtime_epoch() == self.epoch {
            self.gate.lock().unwrap().take()
        } else {
            None
        };
        Box::pin(async move {
            NativeStorageAttachment
                .attach(thread, storage, current)
                .await?;
            if let Some((attached, release)) = gate {
                let _ = attached.send(());
                let _ = release.await;
            }
            Ok(())
        })
    }
}

/// A fixed, contract-valid terminal report, frozen once for both payload and context. Its Turn
/// matches save_terminal_report; later checkpoints must never rebuild this original evidence.
fn frozen_report_body(child: &crate::Thread, sequence: u64, evidence: &str) -> Result<String> {
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
    async fn prepare_root(
        &self,
        identity: &ThreadActivation,
    ) -> Result<
        (
            crate::DelegationSettings,
            Option<pl_core::thread::current::ThreadCurrent>,
        ),
        ThreadAssemblyError,
    > {
        let paths = self
            .0
            .registered_session_paths(identity.id())
            .map_err(storage_error)?;
        let current = self
            .0
            .state_for(paths.workspace_id(), identity.id())
            .map_err(storage_error)?
            .load_current()
            .await
            .map_err(storage_error)?
            .ok_or_else(|| ThreadAssemblyError::Identity(identity.id().to_owned()))?;
        let delegation = crate::studio::delegation::saved(&current.state.to_paused_snapshot())
            .map_err(storage_error)?
            .ok_or_else(|| ThreadAssemblyError::Identity(identity.id().to_owned()))?;
        Ok((delegation, Some(current)))
    }

    async fn prepare(
        &self,
        request: ThreadPreparation,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        let id = request.identity.id().to_owned();
        let protocol = Fixture::protocol(&id, None);
        let current = request.root_current;
        let sink = ThreadStorageSink::new(self.0.clone(), protocol)
            .await
            .map_err(storage_error)?;
        let model_info = pl_model::model::ModelDefinition::compatible("reactivated-model");
        let route = pl_model::config::ResolvedModelRoute {
            pricing_mode: Default::default(),
            role: crate::config::root_agent_route_id(),
            account_id: pl_model::config::AccountId::new("reactivation-account")
                .map_err(storage_error)?,
            endpoint: pl_model::protocol::providers::openai::compatible_endpoint(
                "storage fixture",
                "http://127.0.0.1:0",
            ),
            context: model_info
                .resolve_context(None, pl_model::model::AutoCompactDefaultPolicy::Bundled),
            model: model_info,
            effort: None,
            service_tier: None,
        };
        let model =
            pl_model::runtime::ThreadModel::new(pl_model::runtime::from_route(&route)?, None);
        Ok(StudioThreadSpec {
            workspace_usage: None,
            preparation_guard: None,
            agent_controls: request.agent_controls,
            execution: pl_core::thread::input::InputDriverOptions {
                max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
            },
            id: id.clone(),
            parent_id: None,
            model: Some(pl_core::thread::RuntimeModel::new(
                route.model.base.slug.clone(),
                pl_core::model::ModelFactory::new(model),
                None,
            )),
            route,
            current,
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
            history_sink: Some(sink),
        })
    }
}

async fn save_cold_thread(store: &StudioStore, protocol: &crate::Thread) -> Result<()> {
    register_test_thread(store, protocol).await?;
    let sink = ThreadStorageSink::new(store.clone(), protocol.clone()).await?;
    let projection = spawn_live_projection_for_thread(store.clone(), &protocol.id);
    let channel = store.thread_persistence().history_channel(&protocol.id);
    let thread = ThreadHandle::start_current(protocol.id.clone(), None)?;
    thread.attach_history(HistorySinkHandle::new(sink)).await?;
    let epoch = thread.runtime_epoch();
    let mut current_store = store.state_for(&protocol.workspace_id, &protocol.id)?;
    current_store
        .attach_current(
            store.thread_persistence().clone(),
            None,
            epoch,
            crate::studio::storage::current_writer::CurrentSource::from_thread(thread.clone()),
        )
        .await?;
    let assignment = crate::AgentWorkspaceAssignmentSnapshot {
        mode: crate::AgentWorkspaceMode::Directory,
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
    current_store
        .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
        .await?;
    let through = channel.handoff_ticket();
    channel.await_handoff_durable(&protocol.id, through).await?;
    channel.stop_and_join().await?;
    projection.await?;
    Ok(())
}

/// Seed the explicit Current obligation left before recipient admission. History's
/// immutable report alone does not authorize recovery to infer or re-send a delivery.
async fn save_pending_report(
    store: &StudioStore,
    parent: &crate::Thread,
    message: &pl_core::thread::inbox::ThreadMessage,
) -> Result<()> {
    let mut state = store.state_for(&parent.workspace_id, &parent.id)?;
    let saved = state
        .load_current()
        .await?
        .context("saved parent Current")?;
    let owner = ThreadHandle::restore_current(saved, None)?;
    let epoch = owner.runtime_epoch();
    state
        .attach_current(
            store.thread_persistence().clone(),
            None,
            epoch,
            crate::studio::storage::current_writer::CurrentSource::from_thread(owner.clone()),
        )
        .await?;
    let pending =
        crate::studio::session_runtime::pending_delivery::PendingNativeDelivery::from_terminal_message(
            message.clone(),
            false,
        )?;
    owner
        .mutate_extensions(vec![pl_core::thread::extensions::ExtensionMutation::Put {
            id: pending.extension_id(),
            expected_revision: None,
            payload: pending.encode()?,
        }])
        .await?;
    state
        .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
        .await
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
            fixture.activation("parent", None),
            ReactivationFactory(fixture.store.clone()),
        ),
    )
    .await??)
}

#[tokio::test]
async fn closing_execution_accepts_only_the_original_storage_report_without_resuming() -> Result<()>
{
    for global_close in [false, true] {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let saved = save_pending_close(&store).await?;
        let resources = crate::test_support::storage::close_factory(&store)?;
        let fixture = Fixture::new(store.clone())?;
        resources.install(&fixture.owner)?;
        let active = activate_parent(&fixture).await?;
        let before = active.snapshot();
        fixture
            .owner
            .0
            .state()
            .members
            .entries
            .get_mut("parent")
            .unwrap()
            .native_mut()
            .unwrap()
            .ready = false;
        let services = fixture
            .owner
            .0
            .state()
            .agent_services
            .clone()
            .context("real report services")?;
        let error = services
            .redeliver_parent_report(&fixture.owner, "parent", saved.message.clone())
            .await
            .unwrap_err();
        assert!(matches!(
            error.downcast_ref::<ThreadAssemblyError>(),
            Some(ThreadAssemblyError::Unpublished(_))
        ));
        assert!(
            current_message_identity(&store, "parent", &saved.message.id)
                .await?
                .is_none()
        );
        let seal = if global_close {
            fixture.owner.0.state().close.closing = true;
            None
        } else {
            Some(fixture.owner.seal_agent_operation("parent"))
        };
        fixture.owner.admit_thread_close("parent")?;
        services
            .redeliver_parent_report(&fixture.owner, "parent", saved.message.clone())
            .await?;
        let SavedMessageIdentity {
            sequence: receipt_sequence,
            digest: receipt_digest,
        } = current_message_identity(&store, "parent", &saved.message.id)
            .await?
            .context("original report durable receipt")?;
        assert_eq!(receipt_digest, saved.message.digest());
        services
            .redeliver_parent_report(&fixture.owner, "parent", saved.message.clone())
            .await?;
        let SavedMessageIdentity {
            sequence: repeated_sequence,
            digest: repeated_digest,
        } = current_message_identity(&store, "parent", &saved.message.id)
            .await?
            .context("idempotent original report receipt")?;
        assert_eq!(repeated_sequence, receipt_sequence);
        assert_eq!(repeated_digest, receipt_digest);
        {
            let state = fixture.owner.0.state();
            let entry = &state.members.entries["parent"];
            assert_eq!(entry.native().unwrap().purpose, EntryPurpose::Execution);
            assert!(!entry.native().unwrap().ready);
            assert!(entry.native().unwrap().thread.same_instance(&active));
        }
        let after = active.snapshot();
        assert_eq!(after.execution_sequence, before.execution_sequence);
        assert!(before.attempts.is_empty() && after.attempts.is_empty());
        assert_eq!(after.execution, before.execution);
        assert_eq!(
            after
                .inbox
                .iter()
                .filter(|entry| entry.message.id == saved.message.id)
                .count(),
            1
        );
        drop(seal);
        assert!(fixture.owner.close_session().await.is_empty());
        fixture.stop_writers().await?;
        resources.shutdown().await?;
    }
    Ok(())
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
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let parent = Fixture::protocol("parent", None);
        let child = Fixture::protocol("child", Some("parent"));
        // These original storage owners are fully stopped before the new coordinator exists.
        // Never add a parent Entry to the coordinator recovering the saved close.
        save_cold_thread(&store, &parent).await?;
        save_cold_thread(&store, &child).await?;
        let sequence = 1;
        let content = frozen_report_body(
            &child,
            sequence,
            "original terminal body and permission evidence\n\noriginal frozen evidence",
        )?;
        let message = pl_core::thread::inbox::ThreadMessage {
            kind: AgentMessageKind::Report,
            id: crate::studio::agent_close::terminal_report_id("child", sequence),
            source_id: "studio.child:child".into(),
            payload: OpaquePayload::new("pl.studio.turn-report", 3, content.clone())?,
            context: vec![ContextContent::Text {
                text: content.into(),
            }],
        };
        save_terminal_report(&store, &child, message.clone()).await?;
        save_pending_report(&store, &parent, &message).await?;
        let resources = close_factory(&store)?;
        let current = store
            .state_for("project-test", "child")?
            .load_current()
            .await?
            .context("terminal child current")?;
        let current_snapshot = current.state.to_paused_snapshot();
        resources
            .factory
            .begin_child_close(&child, Some(&current_snapshot), false)
            .await?;
        let fixture = Fixture::new(store.clone())?;
        resources.install(&fixture.owner)?;
        assert!(fixture.owner.0.state().members.entries.is_empty());
        assert!(
            current_message_identity(&store, "parent", &message.id)
                .await?
                .is_none()
        );
        fixture.fail_drain.store(inject_failure, Ordering::SeqCst);
        let first = tokio::time::timeout(
            std::time::Duration::from_secs(10),
            fixture.owner.resume_agent_closes(),
        )
        .await?;
        let SavedMessageIdentity {
            sequence: first_sequence,
            digest: first_digest,
        } = current_message_identity(&store, "parent", &message.id)
            .await?
            .context("original report was durably received even when cleanup failed")?;
        assert_eq!(first_digest, message.digest());
        if inject_failure {
            let failure =
                first.expect_err("receiver drain fails after the real Current delivery ACK");
            let diagnostic = format!("{failure:#}");
            assert!(diagnostic.contains("injected receiver drain failure"));
            assert!(
                !store
                    .agent_close("child")
                    .await?
                    .context("pending close")?
                    .execution_closed
            );
            assert!(
                fixture
                    .owner
                    .0
                    .state()
                    .members
                    .entries
                    .get("parent")
                    .is_some_and(|entry| {
                        entry
                            .native()
                            .is_ok_and(|native| native.purpose == EntryPurpose::ReportReceiver)
                    })
            );
            assert!(
                !fixture.owner.0.state().members.entries["parent"]
                    .native()
                    .unwrap()
                    .ready
            );
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
            fixture
                .owner
                .0
                .state()
                .members
                .entries
                .contains_key("parent"),
            active.is_some()
        );
        assert!(
            !fixture
                .owner
                .0
                .state()
                .close
                .sealed_agents
                .contains_key("parent")
        );
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
            vec![("child".into(), WorkspaceRelease::Preserve)]
        );
        assert_eq!(
            fixture.owner.acknowledge_parent_reports(&child).await?,
            ParentReportAcknowledgement::Absent
        );
        let SavedMessageIdentity {
            sequence: receipt_sequence,
            digest: receipt_digest,
        } = current_message_identity(&store, "parent", &message.id)
            .await?
            .context("same durable parent ACK")?;
        assert_eq!(receipt_sequence, first_sequence);
        assert_eq!(receipt_digest, first_digest);
        assert_eq!(
            history_parent_report(&store.history("child").await?, "child", sequence)
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
            fixture.owner.0.state().members.entries["parent"]
                .native()
                .unwrap()
                .purpose,
            EntryPurpose::Execution
        );
        let mut followup = message.clone();
        followup.id = "after-recovery".into();
        active.send_message(followup).await?;
        fixture.owner.synchronize_observation("parent").await?;
        store
            .conversation_store("parent")
            .await?
            .flush_current(active.runtime_epoch())
            .await?;
        assert!(
            current_message_identity(&store, "parent", "after-recovery")
                .await?
                .is_some()
        );
        assert!(fixture.owner.close_session().await.is_empty());
        fixture.stop_writers().await?;
        resources.shutdown().await?;
    }
    Ok(())
}

struct SavedClose {
    child: crate::Thread,
    message: pl_core::thread::inbox::ThreadMessage,
    sequence: u64,
}

async fn save_pending_close(store: &StudioStore) -> Result<SavedClose> {
    let parent = Fixture::protocol("parent", None);
    let child = Fixture::protocol("child", Some("parent"));
    save_cold_thread(store, &parent).await?;
    save_cold_thread(store, &child).await?;
    let sequence = 1;
    let content = frozen_report_body(
        &child,
        sequence,
        "original body before receiver cancellation or detach\n\noriginal permission evidence",
    )?;
    let message = pl_core::thread::inbox::ThreadMessage {
        kind: AgentMessageKind::Report,
        id: crate::studio::agent_close::terminal_report_id("child", sequence),
        source_id: "studio.child:child".into(),
        payload: OpaquePayload::new("pl.studio.turn-report", 3, content.clone())?,
        context: vec![ContextContent::Text {
            text: content.into(),
        }],
    };
    save_terminal_report(store, &child, message.clone()).await?;
    save_pending_report(store, &parent, &message).await?;
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
            .acknowledge_parent_reports(&saved.child)
            .await?,
        ParentReportAcknowledgement::Absent
    );
    let child_history = store.history("child").await?;
    assert_eq!(
        history_parent_report(&child_history, "child", saved.sequence)
            .await?
            .context("unchanged original body")?
            .digest(),
        saved.message.digest()
    );
    let SavedMessageIdentity { digest, .. } =
        current_message_identity(store, "parent", &saved.message.id)
            .await?
            .context("durable original ID")?;
    assert_eq!(digest, saved.message.digest());
    assert!(
        store
            .agent_close("child")
            .await?
            .context("completed child close")?
            .execution_closed
    );
    assert!(store.agent_close("parent").await?.is_none());
    assert!(
        !fixture
            .owner
            .0
            .state()
            .close
            .sealed_agents
            .contains_key("parent")
    );
    assert!(
        !fixture
            .owner
            .0
            .state()
            .members
            .entries
            .contains_key("parent")
    );
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
    store
        .conversation_store("parent")
        .await?
        .flush_current(active.runtime_epoch())
        .await?;
    let SavedMessageIdentity { digest, .. } =
        current_message_identity(store, "parent", &followup.id)
            .await?
            .context("real followup history write")?;
    assert_eq!(digest, followup.digest());
    assert!(fixture.owner.close_session().await.is_empty());
    fixture.stop_writers().await
}

#[tokio::test]
async fn detached_receiver_writer_retry_joins_only_the_original_binding() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let saved = save_pending_close(&store).await?;
    let resources = close_factory(&store)?;
    let current = store
        .state_for("project-test", "child")?
        .load_current()
        .await?
        .context("saved terminal child")?;
    let current_snapshot = current.state.to_paused_snapshot();
    resources
        .factory
        .begin_child_close(&saved.child, Some(&current_snapshot), false)
        .await?;
    let fixture = Fixture::new(store.clone())?;
    resources.install(&fixture.owner)?;
    assert!(fixture.owner.0.state().members.entries.is_empty());
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
    if let Some(retained) = store
        .thread_persistence()
        .retained_history_channel("parent")
    {
        assert!(
            Arc::ptr_eq(&retained, &binding.channel),
            "cleanup changed writer ownership"
        );
    }
    assert!(
        fixture
            .owner
            .0
            .state()
            .members
            .entries
            .get("parent")
            .is_some_and(|entry| entry
                .native()
                .is_ok_and(|native| native.purpose == EntryPurpose::ReportReceiver))
    );
    let SavedMessageIdentity {
        sequence: first_sequence,
        digest: first_digest,
    } = current_message_identity(&store, "parent", &saved.message.id)
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
    let SavedMessageIdentity {
        sequence: receipt_sequence,
        digest: receipt_digest,
    } = current_message_identity(&store, "parent", &saved.message.id)
        .await?
        .context("same receipt after exact-binding cleanup")?;
    assert_eq!(receipt_sequence, first_sequence);
    assert_eq!(receipt_digest, first_digest);
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
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let saved = save_pending_close(&store).await?;
    let resources = close_factory(&store)?;
    let current = store
        .state_for("project-test", "child")?
        .load_current()
        .await?
        .context("saved terminal child")?;
    let current_snapshot = current.state.to_paused_snapshot();
    resources
        .factory
        .begin_child_close(&saved.child, Some(&current_snapshot), false)
        .await?;
    let fixture = Fixture::new(store.clone())?;
    resources.install(&fixture.owner)?;
    assert!(fixture.owner.0.state().members.entries.is_empty());
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
        let current = store
            .state_for("project-test", "parent")?
            .load_current()
            .await?
            .context("cold original parent")?;
        services.install_storage_owner(
            &fixture.owner,
            &Fixture::protocol("parent", None),
            current,
            EntryPurpose::ReportReceiver,
        )?;
    }
    assert!(matches!(
        fixture.owner.0.state().members.entries["parent"]
            .native()
            .unwrap()
            .close_storage,
        Some(CloseStorage::Pending { .. })
    ));
    let (attached, attachment_ack) = tokio::sync::oneshot::channel();
    let (release, released) = tokio::sync::oneshot::channel();
    let epoch = fixture
        .owner
        .observed_thread("parent")
        .context("retained parent Core")?
        .runtime_epoch();
    fixture.owner.0.state().close.attachment = Arc::new(PausedAttachment {
        epoch,
        gate: Mutex::new(Some((attached, released))),
    });
    let owner = fixture.owner.clone();
    let activation = fixture.activation("parent", None);
    let activating_store = store.clone();
    let activating = tokio::spawn(async move {
        owner
            .activate(activation, ReactivationFactory(activating_store))
            .await
    });
    tokio::time::timeout(std::time::Duration::from_secs(10), attachment_ack).await??;
    let binding = {
        let state = fixture.owner.0.state();
        let entry = &state.members.entries["parent"];
        assert!(!entry.native().unwrap().ready);
        assert!(
            entry
                .native()
                .unwrap()
                .thread
                .snapshot()
                .persistence
                .attached
        );
        let Some(CloseStorage::Attaching {
            binding,
            completion,
        }) = &entry.native().unwrap().close_storage
        else {
            anyhow::bail!("effective attachment must retain its original shared completion");
        };
        assert!(completion.peek().is_none());
        binding.clone()
    };
    activating.abort();
    assert!(activating.await.unwrap_err().is_cancelled());
    assert!(matches!(
        fixture.owner.0.state().members.entries["parent"]
            .native()
            .unwrap()
            .close_storage,
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
