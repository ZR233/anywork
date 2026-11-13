use super::*;
use pl_agent_tool::{Tool, ToolDefinition, ToolHandle};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    model::{
        DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput, ModelToolCall,
        PreparedModelCall,
    },
    thread::{
        ModelStepLimit, ThreadEffectBatch, ThreadHandle, ThreadSnapshot, TurnInput, TurnOutcome,
        TurnRecord, TurnState,
        cold::ColdStoreHandle,
        input::{InputChange, InputRecord, InputState, ThreadInput},
        task::TaskStatus,
    },
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use sea_orm::{ConnectionTrait, Database};
use tokio::sync::{Notify, mpsc};
use tokio_util::sync::CancellationToken;

#[derive(Debug)]
struct ConcurrentModel(Arc<AtomicUsize>);

impl ModelSession for ConcurrentModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        self.0.fetch_add(1, Ordering::Relaxed);
        Ok(PreparedModelCall::new(async move {
            Ok(ModelStepOutput {
                turn_action: Default::default(),
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: vec![ContextContent::Text {
                    text: Arc::from("running both tools"),
                }],
                tool_calls: ["first", "second"]
                    .into_iter()
                    .map(|id| ModelToolCall {
                        rejection: None,
                        presentation_contract: None,
                        call_id: id.to_owned(),
                        tool_id: id.to_owned(),
                        arguments: OpaquePayload::text(id),
                    })
                    .collect(),
                private_context: None,
                usage: Default::default(),
            })
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[derive(Debug)]
struct ConcurrentTool {
    definition: ToolDefinition,
    started: mpsc::UnboundedSender<String>,
    release: Arc<Notify>,
    executions: Arc<Mutex<Vec<String>>>,
}

impl Tool for ConcurrentTool {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.executions
            .lock()
            .unwrap()
            .push(context.call_id.clone());
        self.started.send(context.call_id).unwrap();
        self.release.notified().await;
        Ok(ToolOutput::new(
            input.clone(),
            vec![ContextContent::Text {
                text: Arc::from(input.content()),
            }],
        ))
    }
}

pub(crate) fn ticket(thread_id: &str, sequence: u64) -> ThreadWrite {
    let state = ThreadSnapshot {
        commit_sequence: sequence,
        ..Default::default()
    };
    ThreadWrite {
        effect: Arc::new(ThreadEffectBatch {
            thread_id: thread_id.to_owned(),
            sequence,
            committed_at: 1,
            ..Default::default()
        }),
        checkpoint: ThreadCheckpoint::capture_transfer(thread_id.to_owned(), sequence, state),
        output_claim: None,
    }
}

fn ticket_referencing_attachment(
    thread_id: &str,
    attachment: &crate::studio::AttachmentRecord,
) -> Result<ThreadWrite> {
    let mut write = ticket(thread_id, 1);
    let input = InputRecord {
        continuation: None,
        accepted_sequence: 1,
        delivery: Default::default(),
        input: ThreadInput {
            purpose: pl_core::thread::input::InputPurpose::Message,
            id: "attached-input".to_owned(),
            payload: OpaquePayload::new(
                "pl.studio.prompt",
                1,
                serde_json::json!({
                    "text": "attached",
                    "presentation": "visible",
                    "attachments": [attachment],
                })
                .to_string(),
            )?,
            context: Vec::new(),
        },
        ordinal: 1,
        revision: 1,
        state: InputState::Pending,
    };
    write.checkpoint.state.inputs = Arc::from([input.clone()]);
    Arc::make_mut(&mut write.effect).inputs = Arc::from([InputChange::Accepted(input)]);
    Ok(write)
}

pub(super) fn test_thread(thread_id: &str) -> pl_protocol::Thread {
    let mut thread = pl_protocol::Thread::placeholder(thread_id);
    thread.workspace_id = "project-test".into();
    thread.agent_path = thread_id.to_owned();
    thread.root_thread_id = thread_id.to_owned();
    thread
}

pub(crate) async fn register_test_thread(
    store: &StudioStore,
    thread: &pl_protocol::Thread,
) -> Result<()> {
    let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
        crate::studio::store::directory::ProjectDirectoryRecord {
            id: thread.workspace_id.clone(),
            kind: pl_protocol::studio::WorkspaceKind::Project,
            name: "Test".into(),
            path: "/tmp/project-test".into(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        },
    );
    let (session, agent) = crate::studio::records::directory_facts_from_thread(thread);
    if let Some(session) = session {
        delta.session_upserts = vec![session];
    }
    delta.agent_upserts = vec![agent];
    store.persist_directory_summaries(&delta).await
}

impl crate::studio::ProductEventBus {
    pub(crate) async fn commit_test_thread(&self, thread: &pl_protocol::Thread) -> Result<()> {
        let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
            crate::studio::store::directory::ProjectDirectoryRecord {
                id: thread.workspace_id.clone(),
                kind: pl_protocol::studio::WorkspaceKind::Project,
                name: "Test".into(),
                path: thread.workspace_path.clone(),
                ssh_alias: None,
                created_at: 1,
                updated_at: 1,
                last_opened_at: None,
                closed: false,
            },
        );
        let (session, agent) = crate::studio::records::directory_facts_from_thread(thread);
        delta.session_upserts.extend(session);
        delta.agent_upserts.push(agent);
        self.commit_directory(delta).await?;
        Ok(())
    }
}

async fn sink(thread_id: &str) -> Result<(tempfile::TempDir, StudioStore, ThreadStorageSink)> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let thread = test_thread(thread_id);
    register_test_thread(&store, &thread).await?;
    let sink = ThreadStorageSink::new(store.clone(), thread, None).await?;
    spawn_live_projection(&sink);
    Ok((temp, store, sink))
}

#[tokio::test]
async fn late_reliable_summary_publishes_without_another_billing() -> Result<()> {
    use crate::studio::agent_host::ThreadWriteBehindWriter;
    use crate::studio::runtime::ModelPerformanceOwner;
    use crate::studio::thread_projection::AuxiliaryBillingReceipt;
    use pl_core::thread::extensions::{ExtensionChange, ExtensionRecord};
    use pl_protocol::{
        FirstOutputSource, InferenceAccounting, InferenceBillingRecord, InferenceTiming,
        PricingOutcome, RuntimeCostAmount, UsageReport,
    };

    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let thread = test_thread("late-summary");
    register_test_thread(&store, &thread).await?;
    let sink = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
    let product_writer = ThreadWriteBehindWriter::new(store.clone());
    let events = crate::studio::ProductEventBus::new(store.clone(), product_writer.clone());
    let mut cost_events = events.subscribe_topic(&crate::StudioProductTopic::SessionCosts {
        root_thread_id: thread.root_thread_id.clone(),
    });
    let owner = ModelPerformanceOwner::new(store.clone(), events, "late-summary-owner".into());
    owner.initialize_projection().await;
    let feed = owner.subscribe_statistics();
    let initial = feed.next().await?.context("missing initial statistics")?;
    feed.acknowledge(initial.delivery_sequence)?;

    let billing = InferenceBillingRecord {
        inference_id: "title-call".into(),
        purpose: Some("title".into()),
        account_id: "account".into(),
        account_display_name: Some("Account".into()),
        model_id: Some("model".into()),
        model_observation: None,
        effort: None,
        context_window: None,
        accounting: InferenceAccounting {
            usage: UsageReport {
                input_tokens: Some(10),
                output_tokens: Some(2),
                cache_read_tokens: Some(0),
                total_tokens: Some(12),
                ..Default::default()
            },
            pricing: PricingOutcome::Estimated {
                cost: RuntimeCostAmount {
                    currency: "USD".into(),
                    amount: 1.25,
                },
                cache_savings: None,
            },
            ..Default::default()
        },
        prompt_generation: None,
        prompt_cache_policy: None,
        prefix_changed_reason: None,
        orchestration: Default::default(),
        timing: Some(InferenceTiming {
            first_output_source: FirstOutputSource::CompletedToolInput,
            ttft_millis: Some(100),
            decode_millis: Some(0),
            response_millis: 100,
        }),
        recorded_at: crate::studio::unix_seconds(),
    };
    let extension = ExtensionRecord {
        revision: 1,
        payload: AuxiliaryBillingReceipt {
            billing: billing.clone(),
            succeeded: true,
        }
        .into_payload()?,
    };
    let mut write = ticket(&thread.id, 1);
    Arc::make_mut(&mut write.effect).extensions = vec![ExtensionChange::Put {
        id: "studio.auxiliary-billing.title".into(),
        record: extension.clone(),
    }]
    .into();
    write.checkpoint.state.extension_sequence = 1;
    write
        .checkpoint
        .state
        .extensions
        .insert("studio.auxiliary-billing.title".into(), extension);

    // Block the actual ordered history writer, not a replacement saver or artificial delay.
    let history_gate = sink.0.channel.step_lock.lock().await;
    sink.admit(&thread.id, write.clone())?;
    let mut live = live_projection(&sink).await?;
    let (_, mut prepared) = live
        .prepare(&thread, &write.effect, &write.checkpoint.state, false)
        .await?;
    live.publish_prepared(&sink.0.chat, &mut prepared).await?;
    assert!(sink.0.channel.prepare(prepared.clone()));
    for fact in prepared.accounting.facts.iter() {
        owner.record_auxiliary_inference(
            &thread.root_thread_id,
            &thread.id,
            &fact.record,
            fact.status,
        )?;
    }
    let billing_publication = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let header = feed.next().await?.context("statistics feed closed")?;
            feed.acknowledge(header.delivery_sequence)?;
            if owner.snapshot().await.history.len() == 1 {
                break Ok::<_, anyhow::Error>(header);
            }
        }
    })
    .await
    .context("Billing performance publication timed out")??;
    assert_eq!(store.history(&thread.id).await?.watermark().await?, 0);
    assert!(
        owner
            .session_costs_snapshot(&thread.id)
            .await
            .cost
            .is_none()
    );
    let before_costs = owner.snapshot().await;
    assert_eq!(
        billing_publication.history_count,
        before_costs.history.len() as u64
    );
    assert_eq!(before_costs.history[0].completion_tokens, Some(2));
    assert_eq!(
        before_costs.history[0].first_output_source,
        FirstOutputSource::CompletedToolInput
    );
    assert_eq!(before_costs.history[0].decode_millis, Some(0));

    drop(history_gate);
    tokio::time::timeout(Duration::from_secs(5), sink.flush(&thread.id, 1)).await??;
    // A late cost-only Summary must publish its scoped fact, not manufacture a global
    // performance revision solely to wake this test. Observe the actual consumer topic.
    let costs_publication = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if let crate::StudioProductEventKind::SessionCostsChanged(state) =
                cost_events.recv().await?.kind
                && state
                    .cost
                    .as_ref()
                    .and_then(|cost| cost.estimated_costs.first())
                    .is_some_and(|cost| cost.amount == 1.25)
            {
                break Ok::<_, anyhow::Error>(state);
            }
        }
    })
    .await
    .context("late Summary scoped cost publication timed out")??;
    assert_eq!(costs_publication.root_thread_id, thread.root_thread_id);
    assert!(!costs_publication.read_failed);
    assert_eq!(
        owner.session_costs_snapshot(&thread.id).await,
        costs_publication
    );
    let after_costs = owner.snapshot().await;
    assert!(
        Arc::ptr_eq(&after_costs.history, &before_costs.history),
        "cost-only publication must retain the frozen history material"
    );
    assert!(
        Arc::ptr_eq(&after_costs.summaries, &before_costs.summaries),
        "cost-only publication must retain the frozen summary material"
    );
    assert_eq!(after_costs.history, before_costs.history);
    assert_eq!(
        store
            .history(&thread.id)
            .await?
            .checkpoint()
            .await?
            .unwrap()
            .state
            .usage_summary
            .totals
            .inference_count,
        1
    );

    // Repeating the same reliable fact and billing does not add another contribution.
    let admitted = store.calls().admitted_ticket();
    sink.admit(&thread.id, write)?;
    owner.record_auxiliary_inference(
        &thread.root_thread_id,
        &thread.id,
        &billing,
        super::super::calls::CallStatus::Committed,
    )?;
    assert_eq!(store.calls().admitted_ticket(), admitted);
    sink.0.channel.stop_and_join().await?;
    feed.close().await?;
    owner.close().await?;
    product_writer.shutdown().await?;
    store.close().await?;
    Ok(())
}

pub(crate) struct CloseFactoryFixture {
    pub(crate) factory: crate::studio::StudioThreadFactory,
    pub(in crate::studio) writer: crate::studio::agent_host::ThreadWriteBehindWriter,
    pub(crate) config: crate::config::ConfigRuntime,
    pub(crate) events: crate::studio::ProductEventBus,
    store: StudioStore,
    worktrees: crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner,
}
impl CloseFactoryFixture {
    pub(crate) async fn unpublished_workspace(
        &self,
        id: &str,
        root: &std::path::Path,
    ) -> Result<crate::thread_assembler::WorkspacePreparationOwner> {
        use crate::studio::agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity};
        let usage = self
            .worktrees
            .reserve_workspace(id, WorkspaceEndpoint::Local)?;
        let identity = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            dunce::canonicalize(root)?.to_string_lossy().into_owned(),
        )?;
        self.worktrees.assign_workspace(&usage, identity.clone())?;
        self.store.bind_workspace_identity(id, &identity).await?;
        self.worktrees.preserve_workspace_resources(id, identity);
        let files = root.join(pl_tool::workspace::SessionFiles::new(id).root());
        tokio::fs::create_dir_all(files.join("scratch")).await?;
        tokio::fs::write(files.join("scratch/prepared"), b"unpublished owned file").await?;
        let preparation = crate::thread_assembler::WorkspacePreparationOwner::default();
        preparation.retain(&usage);
        Ok(preparation)
    }
    pub(crate) fn workspace_is_busy(&self, id: &str) -> bool {
        self.worktrees.ensure_thread_workspace_idle(id).is_err()
    }
    pub(crate) fn install(&self, owner: &crate::thread_assembler::SessionRuntime) -> Result<()> {
        let performance = crate::studio::ModelPerformanceOwner::new(
            self.store.clone(),
            self.events.clone(),
            "close-fault-fixture".into(),
        );
        owner.set_agent_services(
            self.config.clone(),
            self.store.clone(),
            self.events.clone(),
            self.factory.clone(),
            performance,
            crate::studio::StudioRecoveryRegistry::new(),
        )?;
        Ok(())
    }
    pub(crate) async fn shutdown(&self) -> Result<()> {
        self.writer.shutdown().await?;
        Ok(())
    }
}

pub(crate) fn close_factory(store: &StudioStore) -> Result<CloseFactoryFixture> {
    use crate::studio::thread_factory::{StudioThreadFactory, StudioThreadServices};
    let writer = crate::studio::agent_host::ThreadWriteBehindWriter::new(store.clone());
    let events = crate::studio::ProductEventBus::new(store.clone(), writer.clone());
    let config = crate::config::ConfigRuntime::initialize(crate::config::ConfigStore::new(
        crate::config::ConfigPaths::from_config_dir(
            store.paths().home().join("isolated-test-config"),
        ),
    ))?;
    let source = crate::worker_assets::RemoteHelperSource::External;
    let bots = crate::bots::BotRuntime::new(store.paths().clone(), config.clone(), events.clone())?;
    let worktrees =
        crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner::new(writer.clone());
    let factory = StudioThreadFactory::new(StudioThreadServices {
        store: store.clone(),
        worktrees: worktrees.clone(),
        recovery: crate::studio::StudioRecoveryRegistry::new(),
        product_events: events.clone(),
        config_runtime: config.clone(),
        mcp_connector: pl_tool::mcp::McpConnector::default(),
        lsp_runtime: pl_lsp::runtime::LspRuntimeRegistry::new(),
        local_executor: pl_remote_helper::Executor::local()?,
        skills: crate::studio::runtime::SkillCatalogRuntime::new(
            events.clone(),
            store.paths().home().join("isolated-test-skills"),
            pl_remote_helper::Executor::local()?,
        ),
        thread_modes: config.thread_mode_manager(),
        ssh_manager: Arc::new(crate::worker_assets::ssh_manager(&source)),
        helper_source: source,
        bots,
    });
    Ok(CloseFactoryFixture {
        factory,
        writer,
        config,
        events,
        store: store.clone(),
        worktrees,
    })
}

#[tokio::test]
async fn close_intent_preserves_inherited_and_actual_assignment_for_subdirectory_projects()
-> Result<()> {
    use crate::agent::worktree::{WorktreeManager, WorktreeOwnership};
    use crate::studio::agent_host::worktree_lease::{
        WorkspaceEndpoint, WorkspaceIdentity, WorktreeLease, WorktreeLeaseOwnerKind,
        WorktreeLeaseState,
    };
    use pl_protocol::{
        AgentWorkspaceAssignmentSnapshot, AgentWorkspaceMode, AgentWorktreeSnapshot,
    };
    async fn register(
        store: &StudioStore,
        thread: &pl_protocol::Thread,
        project_root: &std::path::Path,
    ) -> Result<()> {
        let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
            crate::studio::store::directory::ProjectDirectoryRecord {
                id: thread.workspace_id.clone(),
                kind: pl_protocol::studio::WorkspaceKind::Project,
                name: "Subdirectory Project".into(),
                path: project_root.to_string_lossy().into_owned(),
                ssh_alias: None,
                created_at: 1,
                updated_at: 1,
                last_opened_at: None,
                closed: false,
            },
        );
        let (session, agent) = crate::studio::records::directory_facts_from_thread(thread);
        if let Some(session) = session {
            delta.session_upserts.push(session);
        }
        delta.agent_upserts.push(agent);
        store.persist_directory_summaries(&delta).await
    }
    let temp = tempfile::tempdir()?;
    let repository = temp.path().join("repository");
    let project_root = repository.join("subdirectory");
    tokio::fs::create_dir_all(&project_root).await?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let mut root = test_thread("root-local");
    root.workspace_path = project_root.to_string_lossy().into_owned();
    register(&store, &root, &project_root).await?;
    let mut root_worktree = test_thread("root-worktree");
    root_worktree.workspace_mode = pl_protocol::ThreadWorkspaceMode::Worktree;
    let root_site = WorktreeManager::allocate_path(
        &repository,
        &root_worktree.id,
        &WorktreeOwnership::Session {
            thread_id: root_worktree.id.clone(),
        },
    );
    root_worktree.workspace_path = root_site.to_string_lossy().into_owned();
    register(&store, &root_worktree, &project_root).await?;
    let child_site = WorktreeManager::allocate_path(
        &repository,
        &root.id,
        &WorktreeOwnership::Child {
            child_id: "worktree-owner".into(),
        },
    );
    let child_receipt = AgentWorktreeSnapshot {
        repository_root: repository.to_string_lossy().into_owned(),
        path: child_site.to_string_lossy().into_owned(),
        base_commit: "a".repeat(40),
    };
    let mut cases = Vec::new();
    for (id, parent, mode, assigned, receipt, reviewed) in [
        (
            "worktree-owner",
            &root,
            AgentWorkspaceMode::Worktree,
            &child_site,
            Some(child_receipt.clone()),
            None,
        ),
        (
            "review-owner",
            &root,
            AgentWorkspaceMode::Review,
            &child_site,
            Some(child_receipt.clone()),
            Some(pl_protocol::AgentReviewTargetSnapshot {
                baseline: None,
                feedback: None,
                agent_id: "worktree-owner".into(),
            }),
        ),
        (
            "directory-owner",
            &root,
            AgentWorkspaceMode::Directory,
            &project_root,
            None,
            None,
        ),
        (
            "session-directory-owner",
            &root_worktree,
            AgentWorkspaceMode::Directory,
            &root_site,
            None,
            None,
        ),
    ] {
        tokio::fs::create_dir_all(assigned).await?;
        let mut thread = test_thread(id);
        thread.parent_thread_id = Some(parent.id.clone());
        thread.root_thread_id = parent.id.clone();
        thread.workspace_path = parent.workspace_path.clone();
        thread.workspace_mode = parent.workspace_mode;
        register(&store, &thread, &project_root).await?;
        let assignment = AgentWorkspaceAssignmentSnapshot {
            mode,
            project_root: project_root.to_string_lossy().into_owned(),
            root: assigned.to_string_lossy().into_owned(),
            writable_paths: None,
            worktree: receipt,
            review_target: reviewed,
        };
        cases.push((thread, assignment));
    }
    store
        .persist_directory_summaries(
            &crate::studio::store::directory::DirectoryDelta::upsert_project(
                crate::studio::store::directory::ProjectDirectoryRecord {
                    id: "project-test".into(),
                    kind: pl_protocol::studio::WorkspaceKind::Project,
                    name: "Subdirectory Project".into(),
                    path: project_root.to_string_lossy().into_owned(),
                    ssh_alias: None,
                    created_at: 1,
                    updated_at: 1,
                    last_opened_at: None,
                    closed: false,
                },
            ),
        )
        .await?;
    let project = store.read_project("project-test").await?.unwrap();
    let fixture = close_factory(&store)?;
    for (owner, kind, root_id, path) in [
        (
            "worktree-owner",
            WorktreeLeaseOwnerKind::Child,
            root.id.as_str(),
            child_site.clone(),
        ),
        (
            root_worktree.id.as_str(),
            WorktreeLeaseOwnerKind::Session,
            root_worktree.id.as_str(),
            root_site.clone(),
        ),
    ] {
        let mut lease = WorktreeLease {
            revision: 1,
            state: WorktreeLeaseState::Prepared,
            owner_kind: kind,
            owner_thread_id: owner.into(),
            root_thread_id: root_id.into(),
            workspace_id: "project-test".into(),
            ssh_alias: None,
            repository_root: repository.to_string_lossy().into_owned(),
            path: path.to_string_lossy().into_owned(),
            base_commit: "a".repeat(40),
        };
        fixture.worktrees.record_durable(lease.clone()).await?;
        lease.transition(WorktreeLeaseState::Active);
        fixture.worktrees.record_durable(lease).await?;
    }
    for (thread, assignment) in cases {
        let catalog = store.catalog();
        let registered_agent = catalog
            .get_agent(&thread.id)
            .expect("registered projection agent");
        let registered_session = catalog
            .get_session(&registered_agent.session_id)
            .expect("registered projection session");
        store
            .prepare_session_manifest(&registered_session, &registered_agent, |id| {
                catalog.get_agent(id)
            })
            .await?;
        let execution = std::path::Path::new(&assignment.root)
            .join(pl_tool::workspace::SessionFiles::new(&thread.id).root());
        tokio::fs::create_dir_all(&execution).await?;
        tokio::fs::write(execution.join("owned"), b"exact owner").await?;
        let identity =
            WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, assignment.root.clone())?;
        store.bind_workspace_identity(&thread.id, &identity).await?;
        let core = pl_core::thread::ThreadHandle::resume_without_model(thread.id.clone(), None)?;
        core.mutate_extensions(vec![
            pl_core::thread::extensions::ExtensionMutation::Put {
                id: crate::studio::workspace_receipt::EXTENSION.into(),
                expected_revision: None,
                payload: crate::studio::workspace_receipt::to_payload(&assignment)
                    .map_err(anyhow::Error::msg)?,
            },
            pl_core::thread::extensions::ExtensionMutation::Put {
                id: "studio.project".into(),
                expected_revision: None,
                payload: pl_core::context::OpaquePayload::new(
                    "pl.studio.project",
                    1,
                    serde_json::to_string(&project)?,
                )?,
            },
        ])
        .await?;
        let close = fixture
            .factory
            .begin_child_close(&thread, Some(&core.snapshot()), false)
            .await?;
        if assignment.mode == AgentWorkspaceMode::Worktree {
            let owned = close.worktree.as_ref().context("actual owned worktree")?;
            assert_eq!(owned.lease.path, assignment.root);
            assert_eq!(owned.identity, identity);
            assert_ne!(thread.workspace_path, owned.lease.path);
        } else {
            assert!(
                close.worktree.is_none(),
                "directory/review must not acquire deletion ownership"
            );
        }
        assert_eq!(
            tokio::fs::read(execution.join("owned")).await?,
            b"exact owner"
        );
        let repeated = fixture
            .factory
            .begin_child_close(&thread, None, false)
            .await?;
        assert_eq!(close, repeated);
        core.close().await?;
    }
    fixture.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn unknown_old_close_candidates_preserve_source_and_refuse_new_delete_authority() -> Result<()>
{
    use sea_orm::{ConnectionTrait, DatabaseBackend, Statement};
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let parent = test_thread("legacy-parent");
    register_test_thread(&store, &parent).await?;
    let mut child = test_thread("legacy-child");
    child.parent_thread_id = Some(parent.id.clone());
    child.root_thread_id = parent.id.clone();
    child.workspace_path = parent.workspace_path.clone();
    register_test_thread(&store, &child).await?;
    let source = store
        .registered_session_paths(&child.id)?
        .root()
        .join("retained-evidence");
    tokio::fs::create_dir_all(source.parent().unwrap()).await?;
    tokio::fs::write(&source, b"original history and attachments").await?;
    let payload = r#"{"unknownOriginalCloseFacts":true}"#;
    let hash = pl_core::context::content_hash(payload.as_bytes());
    store.database().execute_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
            "INSERT INTO studio_objects(owner_kind,owner_id,object_kind,schema_version,revision,payload_json,payload_hash,updated_at) VALUES ('thread',?,'agentRetirement',99,1,?,?,1)",
            [child.id.clone().into(), payload.to_owned().into(), hash.clone().into()])).await?;
    let fixture = close_factory(&store)?;
    assert!(
        store
            .ensure_agent_execution_allowed(&child.id)
            .await
            .is_err()
    );
    assert!(
        fixture
            .factory
            .begin_child_close(&child, None, true)
            .await
            .is_err()
    );
    assert!(store.agent_close(&child.id).await?.is_none());
    let row = store.database().query_one_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
            "SELECT schema_version,payload_json,payload_hash FROM studio_objects WHERE owner_id=? AND object_kind='agentRetirement'",
            [child.id.into()])).await?.context("preserved unknown object")?;
    assert_eq!(row.try_get::<i64>("", "schema_version")?, 99);
    assert_eq!(row.try_get::<String>("", "payload_json")?, payload);
    assert_eq!(row.try_get::<String>("", "payload_hash")?, hash);
    assert_eq!(
        tokio::fs::read(source).await?,
        b"original history and attachments"
    );
    fixture.shutdown().await?;
    Ok(())
}

/// Replaces the former whole-resource retirement case with the actual close/storage contract:
/// save ACKs, live borrowers, content protection, retained history/refs and replacement safety.
#[tokio::test]
async fn close_worktree_preserves_original_history_refs_and_terminal_replacements() -> Result<()> {
    use crate::agent::worktree::{
        ExecutorWorktreeBackend, WorktreeCreateSpec, WorktreeManager, WorktreeOwnership,
    };
    use crate::studio::agent_host::worktree_lease::{
        WorkspaceEndpoint, WorkspaceIdentity, WorktreeLease, WorktreeLeaseOwnerKind,
        WorktreeLeaseState,
    };
    use pl_core::context::ResourceReader;
    use pl_core::thread::{ThreadHandle, cold::ColdStoreHandle, extensions::ExtensionMutation};
    use pl_tool::collaboration::control::AgentWorktreeCleanup;

    async fn git(root: &std::path::Path, args: &[&str]) -> Result<String> {
        let output = tokio::process::Command::new("git")
            .args(args)
            .current_dir(root)
            .output()
            .await?;
        anyhow::ensure!(
            output.status.success(),
            "git {args:?}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        Ok(String::from_utf8(output.stdout)?.trim().to_owned())
    }
    let temp = tempfile::tempdir()?;
    let repository = temp.path().join("repository");
    tokio::fs::create_dir_all(&repository).await?;
    git(&repository, &["init", "--quiet"]).await?;
    git(&repository, &["config", "user.name", "Close fixture"]).await?;
    git(
        &repository,
        &["config", "user.email", "close@example.invalid"],
    )
    .await?;
    tokio::fs::write(repository.join(".gitignore"), b".anywork/\n").await?;
    tokio::fs::write(repository.join("tracked"), b"committed").await?;
    git(&repository, &["add", ".gitignore", "tracked"]).await?;
    git(
        &repository,
        &["commit", "--quiet", "-m", "fixture baseline"],
    )
    .await?;
    let repository = dunce::canonicalize(repository)?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let mut parent = test_thread("close-parent");
    parent.workspace_path = repository.to_string_lossy().into_owned();
    register_test_thread(&store, &parent).await?;
    let mut child = test_thread("close-owned-child");
    child.parent_thread_id = Some(parent.id.clone());
    child.root_thread_id = parent.id.clone();
    child.workspace_path = parent.workspace_path.clone();
    register_test_thread(&store, &child).await?;
    let fixture = close_factory(&store)?;
    let manager = WorktreeManager::new(
        repository.clone(),
        Arc::new(ExecutorWorktreeBackend::new(
            pl_remote_helper::Executor::local()?,
        )),
    );
    let ownership = WorktreeOwnership::Child {
        child_id: child.id.clone(),
    };
    let head = manager.resolve_head(&repository).await?;
    let mut lease = WorktreeLease {
        revision: 1,
        state: WorktreeLeaseState::Prepared,
        owner_kind: WorktreeLeaseOwnerKind::Child,
        owner_thread_id: child.id.clone(),
        root_thread_id: parent.id.clone(),
        workspace_id: child.workspace_id.clone(),
        ssh_alias: None,
        repository_root: parent.workspace_path.clone(),
        path: WorktreeManager::allocate_path(&repository, &parent.id, &ownership)
            .to_string_lossy()
            .into_owned(),
        base_commit: head.clone(),
    };
    fixture.worktrees.record_durable(lease.clone()).await?;
    let handle = manager
        .create(WorktreeCreateSpec {
            repo_root: repository.clone(),
            root_thread_id: parent.id.clone(),
            ownership,
            base_commit: head,
        })
        .await?;
    lease.transition(WorktreeLeaseState::Active);
    fixture.worktrees.record_durable(lease.clone()).await?;
    let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, lease.path.clone())?;
    store.bind_workspace_identity(&child.id, &identity).await?;
    store
        .bind_workspace_identity(
            &parent.id,
            &WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, parent.workspace_path.clone())?,
        )
        .await?;
    let assignment = pl_protocol::AgentWorkspaceAssignmentSnapshot {
        mode: pl_protocol::AgentWorkspaceMode::Worktree,
        project_root: parent.workspace_path.clone(),
        root: lease.path.clone(),
        writable_paths: None,
        review_target: None,
        worktree: Some(pl_protocol::AgentWorktreeSnapshot {
            repository_root: lease.repository_root.clone(),
            path: lease.path.clone(),
            base_commit: lease.base_commit.clone(),
        }),
    };
    let core = ThreadHandle::resume_without_model(child.id.clone(), None)?;
    let sink = ThreadStorageSink::new(store.clone(), child.clone(), None).await?;
    spawn_live_projection(&sink);
    core.attach_storage(ColdStoreHandle::new(sink)).await?;
    core.mutate_extensions(vec![ExtensionMutation::Put {
        id: crate::studio::workspace_receipt::EXTENSION.into(),
        expected_revision: None,
        payload: crate::studio::workspace_receipt::to_payload(&assignment)
            .map_err(anyhow::Error::msg)?,
    }])
    .await?;
    let resources =
        crate::resource_store::FileResourceStore::new(store.session_resources_dir(&child.id)?);
    let reference = resources
        .retain_bytes(
            Arc::from(&b"reliable original attachment"[..]),
            "text/plain",
        )
        .await?;
    let independent_files =
        repository.join(pl_tool::workspace::SessionFiles::new(&parent.id).root());
    tokio::fs::create_dir_all(&independent_files).await?;
    tokio::fs::write(
        independent_files.join("retained"),
        b"independent session files",
    )
    .await?;
    let borrower = fixture
        .worktrees
        .reserve_workspace("active-reviewer", WorkspaceEndpoint::Local)?;
    fixture
        .worktrees
        .assign_workspace(&borrower, identity.clone())?;
    fixture
        .factory
        .begin_child_close(&child, Some(&core.snapshot()), false)
        .await?;
    crate::studio::agent_close::commit(&core).await?;
    core.close().await?;
    store
        .thread_persistence()
        .history_channel(&child.id)
        .stop_and_join()
        .await?;
    let history = store.history(&child.id).await?;
    let saved = serde_json::to_vec(&history.checkpoint().await?)?;
    fixture.factory.finish_child_execution(&child).await?;
    let (blocked, error) = fixture
        .factory
        .finish_child_worktree_cleanup(&child)
        .await?;
    assert!(blocked.execution_closed);
    assert!(
        error
            .context("active borrower must block")?
            .message
            .contains("active-reviewer")
    );
    assert!(matches!(
        blocked.worktree_cleanup,
        AgentWorktreeCleanup::Failed { .. }
    ));
    drop(borrower);
    tokio::fs::write(handle.path.join("tracked"), b"uncommitted child work").await?;
    let (dirty, error) = fixture
        .factory
        .finish_child_worktree_cleanup(&child)
        .await?;
    assert!(error.is_some());
    assert!(matches!(
        dirty.worktree_cleanup,
        AgentWorktreeCleanup::Failed { .. }
    ));
    assert!(tokio::fs::try_exists(&handle.path).await?);
    git(&handle.path, &["add", "tracked"]).await?;
    git(
        &handle.path,
        &["commit", "--quiet", "-m", "undelivered child work"],
    )
    .await?;
    let before_refusal_head = git(&handle.path, &["rev-parse", "HEAD"]).await?;
    // Detached creation owns no branch. An independently created business ref must survive
    // close even when the child checks it out after its ownership was frozen.
    let retained_branch = "retained-business";
    git(&handle.path, &["switch", "-c", retained_branch]).await?;
    let (_, error) = fixture
        .factory
        .finish_child_worktree_cleanup(&child)
        .await?;
    assert!(
        error
            .context("undelivered HEAD must block default close")?
            .message
            .contains("not contained")
    );
    assert!(
        store.agent_close(&child.id).await?.unwrap().git.is_none(),
        "content refusal must precede the destructive grant, preserving a force retry"
    );
    fixture
        .factory
        .begin_child_close(&child, None, true)
        .await?;
    git(&repository, &["worktree", "lock", &lease.path]).await?;
    let (_, error) = fixture
        .factory
        .finish_child_worktree_cleanup(&child)
        .await?;
    assert!(
        error
            .context("Git lock must still block force")?
            .message
            .contains("locked")
    );
    assert!(
        !store
            .agent_close(&child.id)
            .await?
            .unwrap()
            .git
            .unwrap()
            .removal_started,
        "a confirmed Git refusal plus the original remaining site permits a fresh attempt"
    );
    // A previous attempt's expected HEAD is content authorization, not permanent identity.
    tokio::fs::write(
        handle.path.join("tracked"),
        b"advanced after confirmed refusal",
    )
    .await?;
    git(&handle.path, &["add", "tracked"]).await?;
    git(
        &handle.path,
        &["commit", "--quiet", "-m", "advance after refused removal"],
    )
    .await?;
    let retained_head = git(&handle.path, &["rev-parse", "HEAD"]).await?;
    assert_ne!(retained_head, before_refusal_head);
    git(&repository, &["worktree", "unlock", &lease.path]).await?;
    let (removed, error) = fixture
        .factory
        .finish_child_worktree_cleanup(&child)
        .await?;
    assert!(error.is_none(), "{error:?}");
    assert_eq!(
        removed.worktree_cleanup,
        AgentWorktreeCleanup::Removed {
            path: lease.path.clone()
        }
    );
    assert!(!tokio::fs::try_exists(&handle.path).await?);
    assert_eq!(
        git(&repository, &["rev-parse", retained_branch]).await?,
        retained_head
    );
    assert_eq!(serde_json::to_vec(&history.checkpoint().await?)?, saved);
    assert_eq!(
        &*resources.read(reference, Default::default()).await?,
        b"reliable original attachment"
    );
    assert_eq!(
        tokio::fs::read(independent_files.join("retained")).await?,
        b"independent session files"
    );
    git(
        &repository,
        &["worktree", "add", &lease.path, retained_branch],
    )
    .await?;
    let (repeated, error) = fixture
        .factory
        .finish_child_worktree_cleanup(&child)
        .await?;
    assert!(
        error.is_some(),
        "a terminal grant must not delete a replacement"
    );
    assert_eq!(repeated.worktree_cleanup, removed.worktree_cleanup);
    assert!(tokio::fs::try_exists(&handle.path).await?);
    fixture
        .factory
        .restore_workspace_admission(
            crate::studio::agent_host::worktree_lease::load_leases(&store).await?,
        )
        .await?;
    assert!(tokio::fs::try_exists(&handle.path).await?);
    assert!(
        store
            .ensure_agent_execution_allowed(&child.id)
            .await
            .is_err()
    );
    assert!(history.checkpoint().await?.is_some());
    // A fresh process hydrates the top-level lease after it reads the close record. The old
    // preserved ownership must not resurrect a physical borrow once this result is terminal.
    let restarted = close_factory(&store)?;
    restarted
        .factory
        .restore_workspace_admission(
            crate::studio::agent_host::worktree_lease::load_leases(&store).await?,
        )
        .await?;
    let container = WorkspaceIdentity::canonical(
        WorkspaceEndpoint::Local,
        repository.to_string_lossy().into_owned(),
    )?;
    let seal = restarted.worktrees.try_seal_workspace(
        "new-container-owner",
        container.clone(),
        &std::collections::BTreeSet::new(),
    )?;
    restarted
        .worktrees
        .release_workspace_seal("new-container-owner", &container)?;
    drop(seal);
    assert!(
        store
            .ensure_agent_execution_allowed(&child.id)
            .await
            .is_err()
    );
    restarted.shutdown().await?;
    fixture.shutdown().await?;
    Ok(())
}

/// Physical binding persistence and live admission share exact identities. The domain seal's
/// producer still owns the grant ACK proof; this component does not execute a full close/Git.
#[tokio::test]
async fn saved_workspace_identity_keeps_preparers_and_pending_cleanup_until_release() -> Result<()>
{
    use crate::studio::agent_host::{
        ThreadWriteBehindWriter,
        worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity, WorktreeLeaseOwner},
    };
    use std::collections::BTreeSet;
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let root = temp.path().join("repository");
    let workspace = root.join(".anywork/worktrees/root-a/child-w");
    tokio::fs::create_dir_all(&workspace).await?;
    let canonical = dunce::canonicalize(&workspace)?;
    let identity = WorkspaceIdentity::canonical(
        WorkspaceEndpoint::Local,
        canonical.to_string_lossy().into_owned(),
    )?;
    store.bind_workspace_identity("child-w", &identity).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let owner = WorktreeLeaseOwner::new(writer.clone());
    let preparing = owner.reserve_workspace("root-b-preparer", WorkspaceEndpoint::Local)?;
    let foreign_owner = WorktreeLeaseOwner::new(writer.clone());
    let foreign = foreign_owner.reserve_workspace("foreign-preparer", WorkspaceEndpoint::Local)?;
    assert!(
        owner.assign_workspace(&foreign, identity.clone()).is_err(),
        "equal serials from different runtime owners must not alias"
    );
    drop(foreign);
    let closing = BTreeSet::from(["child-w".into(), "review-r".into()]);
    assert!(
        owner
            .try_seal_workspace("child-w", identity.clone(), &closing)
            .err()
            .unwrap()
            .to_string()
            .contains("root-b-preparer")
    );
    // An assigned ancestor root does not borrow every worktree below its pool forever.
    owner.assign_workspace(
        &preparing,
        WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            dunce::canonicalize(&root)?.to_string_lossy().into_owned(),
        )?,
    )?;
    let external = owner.reserve_workspace("other-project-root", WorkspaceEndpoint::Local)?;
    owner.assign_workspace(&external, identity.clone())?;
    assert!(
        owner
            .try_seal_workspace("child-w", identity.clone(), &closing)
            .err()
            .unwrap()
            .to_string()
            .contains("other-project-root")
    );
    drop(external);
    let binding = owner.reserve_workspace("review-r", WorkspaceEndpoint::Local)?;
    owner.assign_workspace(&binding, identity.clone())?;
    let observer_owner = binding.clone();
    owner.preserve_workspace_resources("review-r", identity.clone());
    let seal = owner.try_seal_workspace("child-w", identity.clone(), &closing)?;
    seal.durable()?;
    drop(binding); // Forgetting the binding does not join the actual observer owner.
    assert!(owner.ensure_thread_workspace_idle("review-r").is_err());
    assert!(owner.begin_workspace_removal("child-w", &identity).is_err());
    drop(observer_owner);
    owner.ensure_thread_workspace_idle("review-r")?;
    // A real failed cleanup obligation still blocks independently of active runtime tokens.
    assert!(
        owner
            .begin_workspace_removal("child-w", &identity)
            .err()
            .unwrap()
            .to_string()
            .contains("review-r")
    );
    owner.release_workspace_resources("review-r", &identity)?;
    // The physical seal is distinct from the agent execution seal and ends at a reliable
    // terminal result; retained SessionFiles alone must not keep a stopped review active.
    let removal = owner.begin_workspace_removal("child-w", &identity)?;
    assert!(
        owner
            .reserve_workspace("new-preparer", WorkspaceEndpoint::Local)
            .is_err()
    );
    drop(removal);
    drop(seal);
    let rejected = owner.reserve_workspace("late-borrower", WorkspaceEndpoint::Local)?;
    assert!(owner.assign_workspace(&rejected, identity.clone()).is_err());
    drop(rejected);
    let reopened = StudioStore::open(store.paths().database()).await?;
    let frozen = reopened.workspace_identity("child-w").await?.unwrap();
    assert_eq!(frozen, identity);
    assert!(
        reopened
            .bind_workspace_identity(
                "child-w",
                &WorkspaceIdentity::canonical(
                    WorkspaceEndpoint::Local,
                    dunce::canonicalize(&root)?.to_string_lossy().into_owned()
                )?
            )
            .await
            .is_err()
    );
    // Alias and credential spelling do not split one endpoint/path into two physical sites.
    let first = pl_tool::remote::SshServerProfile {
        alias: "one".into(),
        host_name: "host.example".into(),
        port: 22,
        username: "user".into(),
        identity_file: Some("key-one".into()),
    };
    let second = pl_tool::remote::SshServerProfile {
        alias: "two".into(),
        identity_file: Some("key-two".into()),
        ..first.clone()
    };
    let ssh_a = WorkspaceIdentity::canonical(
        WorkspaceEndpoint::from_profile(Some(&first)),
        "/repo/.anywork/worktrees/root-a/remote-w".into(),
    )?;
    let ssh_b = WorkspaceIdentity::canonical(
        WorkspaceEndpoint::from_profile(Some(&second)),
        ssh_a.root.clone(),
    )?;
    let remote_borrower = owner.reserve_workspace("remote-root-b", ssh_b.endpoint.clone())?;
    owner.assign_workspace(&remote_borrower, ssh_b.clone())?;
    assert!(
        owner
            .try_seal_workspace("remote-w", ssh_a.clone(), &BTreeSet::new())
            .err()
            .unwrap()
            .to_string()
            .contains("remote-root-b")
    );
    drop(remote_borrower);
    let pending = owner.try_seal_workspace("remote-w", ssh_a.clone(), &BTreeSet::new())?;
    drop(pending); // Losing the waiting handle cannot adjudicate an unconfirmed product write.
    let late = owner.reserve_workspace("remote-late", ssh_b.endpoint.clone())?;
    assert!(owner.assign_workspace(&late, ssh_b.clone()).is_err());
    // This fixture sent no grant and started no removal, so explicitly release its known seal.
    owner.release_workspace_seal("remote-w", &ssh_a)?;
    owner.assign_workspace(&late, ssh_b)?;
    // Ordinary archive/failed preparation holds a reversible removal, not a permanent seal.
    let independent = WorkspaceIdentity::canonical(
        WorkspaceEndpoint::Local,
        root.join("independent").to_string_lossy().into_owned(),
    )?;
    let temporary = owner.reserve_workspace("ordinary-preparer", WorkspaceEndpoint::Local)?;
    owner.assign_workspace(&temporary, independent.clone())?;
    let still_owned = temporary.clone();
    assert!(
        owner
            .begin_workspace_cleanup("ordinary-preparer", &independent, Some(&temporary))
            .is_err()
    );
    drop(still_owned);
    let cleanup =
        owner.begin_workspace_cleanup("ordinary-preparer", &independent, Some(&temporary))?;
    assert!(
        owner
            .reserve_workspace("during-cleanup", WorkspaceEndpoint::Local)
            .is_err()
    );
    drop(cleanup);
    owner.assign_workspace(&temporary, independent.clone())?;
    let cleanup =
        owner.begin_workspace_cleanup("ordinary-preparer", &independent, Some(&temporary))?;
    cleanup.complete();
    drop(temporary);
    let restored = owner.reserve_workspace("ordinary-restored", WorkspaceEndpoint::Local)?;
    owner.assign_workspace(&restored, independent)?;
    writer.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn cancelled_sink_initialization_releases_its_claim_before_worker_registration() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let thread = test_thread("cancelled-sink-initialization");
    register_test_thread(&store, &thread).await?;
    let channel = store.thread_persistence().history_channel(&thread.id);
    let (entered, waiting) = tokio::sync::oneshot::channel();
    let (_release, released) = tokio::sync::oneshot::channel();
    *channel.initialization_gate.lock().unwrap() = Some((entered, released));
    let opening_store = store.clone();
    let opening_thread = thread.clone();
    let opening =
        tokio::spawn(
            async move { ThreadStorageSink::new(opening_store, opening_thread, None).await },
        );
    waiting.await?;
    opening.abort();
    assert!(opening.await.unwrap_err().is_cancelled());
    channel.stop_and_join().await?;
    let replacement = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
    assert!(!Arc::ptr_eq(&channel, &replacement.0.channel));
    assert!(Arc::ptr_eq(
        &replacement.0.channel,
        &store.thread_persistence().history_channel(&thread.id)
    ));
    replacement.0.channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_replacement_claim_cannot_lose_its_channel_to_predecessor_release() -> Result<()> {
    for retain_pending in [false, true] {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let thread = test_thread("overlapping-channel-release");
        register_test_thread(&store, &thread).await?;
        let previous = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let previous_channel = previous.0.channel.clone();
        let write_gate = if retain_pending {
            Some(previous_channel.step_lock.lock().await)
        } else {
            None
        };
        if retain_pending {
            previous.admit(&thread.id, ticket(&thread.id, 1))?;
        }
        let wake = previous.0.changed.clone();
        let (waiting, release) = store.thread_persistence().arm_release_gate();
        let stopped_writer = if retain_pending {
            let writer = previous_channel
                .workers
                .lock()
                .await
                .pop()
                .context("registered predecessor writer")?;
            writer.abort();
            Some(writer)
        } else {
            None
        };
        drop(previous);
        wake.notify_one();
        tokio::time::timeout(Duration::from_secs(5), waiting).await??;
        drop(write_gate);
        let replacement = tokio::time::timeout(
            Duration::from_secs(5),
            ThreadStorageSink::new(store.clone(), thread.clone(), None),
        )
        .await;
        release.send(())?;
        if let Some(writer) = stopped_writer {
            assert!(writer.await.unwrap_err().is_cancelled());
        }
        let replacement = replacement??;
        if !retain_pending {
            previous_channel.stop_and_join().await?;
        }
        assert!(
            Arc::ptr_eq(
                &replacement.0.channel,
                &store.thread_persistence().history_channel(&thread.id)
            ),
            "predecessor release must not remove the new incarnation's channel"
        );
        assert!(
            replacement.0.channel.subscribe().borrow().fault.is_none(),
            "a predecessor cannot publish WriterUnavailable after its successor initialized"
        );
        spawn_live_projection(&replacement);
        if !retain_pending {
            replacement.admit(&thread.id, ticket(&thread.id, 1))?;
        }
        tokio::time::timeout(Duration::from_secs(5), replacement.flush(&thread.id, 1)).await??;
        assert_eq!(store.history(&thread.id).await?.watermark().await?, 1);
        replacement.0.channel.stop_and_join().await?;
    }
    Ok(())
}

#[tokio::test]
async fn a_cancelled_replacement_cannot_acknowledge_its_predecessors_pending_facts() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let thread = test_thread("cancelled-queue-adoption");
    register_test_thread(&store, &thread).await?;
    let previous = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
    let channel = previous.0.channel.clone();
    let write_gate = channel.step_lock.lock().await;
    previous.admit(&thread.id, ticket(&thread.id, 1))?;
    let mut previous_flush = Box::pin(previous.flush(&thread.id, 1));
    assert!(futures::poll!(previous_flush.as_mut()).is_pending());
    let (entered, waiting) = tokio::sync::oneshot::channel();
    let (_release, released) = tokio::sync::oneshot::channel();
    *channel.initialization_gate.lock().unwrap() = Some((entered, released));
    let opening_store = store.clone();
    let opening_thread = thread.clone();
    let opening =
        tokio::spawn(
            async move { ThreadStorageSink::new(opening_store, opening_thread, None).await },
        );
    waiting.await?;
    let writer = channel
        .workers
        .lock()
        .await
        .pop()
        .context("registered writer")?;
    writer.abort();
    assert!(writer.await.unwrap_err().is_cancelled());
    opening.abort();
    assert!(opening.await.unwrap_err().is_cancelled());
    assert!(
        store.thread_persistence().snapshot().pending_commits > 0,
        "an initializer cannot acknowledge queue adoption merely by claiming its identity"
    );
    assert!(store.thread_persistence().wait_for_drain().await.is_err());
    assert_eq!(store.history(&thread.id).await?.watermark().await?, 0);
    assert!(
        matches!(
            futures::poll!(previous_flush.as_mut()),
            std::task::Poll::Ready(Err(_))
        ),
        "the old sink's pending flush must receive the unavailable-writer failure"
    );
    drop(previous_flush);
    let unavailable = channel.subscribe().borrow().clone();
    assert_eq!(
        unavailable.fault,
        Some(pl_protocol::studio::HistoryFault::WriterUnavailable)
    );
    assert!(unavailable.error.is_some());
    assert_eq!(unavailable.committed_sequence, 0);
    assert_eq!(unavailable.queued_records, 1);
    drop(write_gate);
    drop(previous);

    let replacement = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
    assert!(Arc::ptr_eq(&channel, &replacement.0.channel));
    spawn_live_projection(&replacement);
    tokio::time::timeout(
        Duration::from_secs(5),
        store
            .thread_persistence()
            .retry_history(&thread.id, unavailable.fault_generation),
    )
    .await??;
    tokio::time::timeout(Duration::from_secs(5), replacement.flush(&thread.id, 1)).await??;
    assert_eq!(store.history(&thread.id).await?.watermark().await?, 1);
    let recovered = channel.subscribe().borrow().clone();
    assert_eq!(recovered.committed_sequence, 1);
    assert_eq!(recovered.queued_records, 0);
    assert!(recovered.fault.is_none());
    assert!(recovered.error.is_none());
    assert_eq!(
        replacement.pressure(&thread.id).recovered_generation,
        Some(unavailable.fault_generation)
    );
    store.thread_persistence().wait_for_drain().await?;
    replacement.0.channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn stopped_writer_joins_survive_cancelled_waiters_and_history_reopens() -> Result<()> {
    let id = "retirement-writer-join";
    let (_temp, store, sink) = sink(id).await?;
    let channel = sink.0.channel.clone();
    let write_gate = channel.step_lock.lock().await;
    sink.admit(id, ticket(id, 1))?;
    assert!(channel.stop_and_join().await.is_err());
    assert!(
        !channel.stopping.is_cancelled(),
        "pending facts must keep their writer"
    );
    drop(write_gate);
    tokio::time::timeout(Duration::from_secs(5), sink.flush(id, 1)).await??;
    let history = store.history(id).await?;
    let saved = history.checkpoint().await?.context("durable checkpoint")?;
    let (release, released) = tokio::sync::oneshot::channel();
    channel.workers.lock().await.push(tokio::spawn(async move {
        let _ = released.await;
    }));
    let waiter_channel = channel.clone();
    let waiter = tokio::spawn(async move { waiter_channel.stop_and_join().await });
    channel.stopping.cancelled().await;
    waiter.abort();
    assert!(waiter.await.unwrap_err().is_cancelled());
    assert!(
        !channel.workers.lock().await.is_empty(),
        "cancelled waits cannot lose join ownership"
    );
    release
        .send(())
        .map_err(|_| anyhow::anyhow!("controlled worker lost its owner"))?;
    tokio::time::timeout(Duration::from_secs(5), channel.stop_and_join()).await??;
    assert!(channel.workers.lock().await.is_empty());
    channel.stop_and_join().await?;
    assert!(
        sink.admit(id, ticket(id, 2)).is_err(),
        "old sinks cannot resume writing"
    );
    assert_eq!(history.watermark().await?, saved.history_fence);
    let reopened = ThreadStorageSink::new(store.clone(), test_thread(id), Some(&saved)).await?;
    spawn_live_projection(&reopened);
    assert!(!Arc::ptr_eq(&channel, &reopened.0.channel));
    reopened.admit(id, ticket(id, 2))?;
    tokio::time::timeout(Duration::from_secs(5), reopened.flush(id, 2)).await??;
    assert_eq!(history.watermark().await?, 2);
    reopened.0.channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn review_exception_cas_is_atomic_and_budget_survives_writer_replacement() -> Result<()> {
    use crate::thread_assembler::{
        agent_review::{ReviewDeliverySource, ReviewForward, ReviewForwardReason},
        review_delivery::ReviewDeliveryException,
    };
    use pl_core::thread::extensions::ExtensionMutation;
    let id = "review-cas-history";
    let (_temp, store, sink) = sink(id).await?;
    let thread = ThreadHandle::resume_without_model(id.into(), None)?;
    thread
        .attach_storage(ColdStoreHandle::new(sink.clone()))
        .await?;
    thread
        .mutate_extensions(vec![ExtensionMutation::Put {
            id: "fixture-original-source".into(),
            expected_revision: None,
            payload: OpaquePayload::text("original durable source"),
        }])
        .await?;
    tokio::time::timeout(Duration::from_secs(5), thread.flush()).await??;
    let history = store.history(id).await?;
    let terminal = history.watermark().await?;
    let body_budget = 256 * 1024;
    let retained = store
        .thread_persistence()
        .retain_review_delivery(id, body_budget)?;
    let fact = ReviewDeliveryException::from_forward(
        id,
        "saved-turn",
        None,
        terminal,
        "executor",
        ReviewDeliverySource::Reconciliation,
        &ReviewForward::Unconfirmed {
            message_id: crate::thread_assembler::agent_review::review_message_id(
                id,
                "saved-turn",
                terminal,
            ),
            reason: ReviewForwardReason::RecoveryRequiresScheduling,
        },
    )
    .context("exception fixture")?
    .into_fact()?;
    let path = store
        .session_paths("project-test", id)?
        .root()
        .join("history.sqlite");
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?;
    db.execute_unprepared("CREATE TRIGGER reject_review_cas BEFORE INSERT ON history_fact_receipts WHEN NEW.kind='reviewDeliveryException' BEGIN SELECT RAISE(ABORT,'controlled review CAS failure'); END").await?;
    let mut status = sink.0.channel.subscribe();
    let records = thread
        .mutate_extensions(vec![ExtensionMutation::Put {
            id: fact.extension_id(),
            expected_revision: None,
            payload: fact.encode()?,
        }])
        .await?;
    tokio::time::timeout(Duration::from_secs(5), async {
        while status.borrow_and_update().fault.is_none() {
            status.changed().await?;
        }
        Ok::<_, tokio::sync::watch::error::RecvError>(())
    })
    .await??;
    assert!(
        history
            .review_delivery_exception(&fact.message.id)
            .await?
            .is_none()
    );
    assert_eq!(history.watermark().await?, terminal);
    assert!(
        !history
            .checkpoint()
            .await?
            .unwrap()
            .state
            .extensions
            .contains_key(&fact.extension_id())
    );
    assert!(thread.flush().await.is_err());
    let failed = status.borrow().clone();
    db.execute_unprepared("DROP TRIGGER reject_review_cas")
        .await?;
    tokio::time::timeout(
        Duration::from_secs(5),
        store
            .thread_persistence()
            .retry_history(id, failed.fault_generation),
    )
    .await??;
    tokio::time::timeout(Duration::from_secs(5), thread.flush()).await??;
    assert_eq!(
        history
            .review_delivery_exception(&fact.message.id)
            .await?
            .unwrap()
            .message
            .digest(),
        fact.message.digest()
    );
    assert!(
        history
            .checkpoint()
            .await?
            .unwrap()
            .state
            .extensions
            .contains_key(&fact.extension_id())
    );
    thread
        .mutate_extensions(vec![ExtensionMutation::Delete {
            id: fact.extension_id(),
            expected_revision: records[&fact.extension_id()].revision,
        }])
        .await?;
    thread.close().await?;
    sink.0.channel.stop_and_join().await?;
    let checkpoint = history
        .checkpoint()
        .await?
        .context("closed CAS source checkpoint")?;
    assert!(
        !checkpoint
            .state
            .extensions
            .contains_key(&fact.extension_id())
    );
    let reopened =
        ThreadStorageSink::new(store.clone(), test_thread(id), Some(&checkpoint)).await?;
    spawn_live_projection(&reopened);
    assert!(!Arc::ptr_eq(&sink.0.channel, &reopened.0.channel));
    assert!(sink.0.channel.shares_delivery_budget(&reopened.0.channel));
    assert!(reopened.pressure(id).thread_bytes >= body_budget);
    let before = reopened.0.channel.process_bytes.load(Ordering::Acquire);
    assert!(
        store
            .thread_persistence()
            .retain_review_delivery(id, MAX_HISTORY_THREAD_BYTES)
            .is_err()
    );
    assert_eq!(
        reopened.0.channel.process_bytes.load(Ordering::Acquire),
        before
    );
    drop(retained);
    assert!(!reopened.0.channel.has_delivery_bytes());
    let resumed = ThreadHandle::resume_without_model(id.into(), Some(checkpoint))?;
    resumed
        .attach_storage(ColdStoreHandle::new(reopened.clone()))
        .await?;
    resumed.close().await?;
    reopened.0.channel.stop_and_join().await?;
    assert_eq!(
        history
            .review_delivery_exception(&fact.message.id)
            .await?
            .unwrap()
            .message
            .digest(),
        fact.message.digest()
    );
    assert!(
        store
            .thread_persistence()
            .retained_history_channel(id)
            .is_none()
    );
    Ok(())
}

#[tokio::test]
async fn worker_join_failure_remains_a_failure_after_retry() -> Result<()> {
    let (_temp, _store, sink) = sink("retirement-worker-failure").await?;
    let channel = sink.0.channel.clone();
    channel.workers.lock().await.push(tokio::spawn(async {
        panic!("controlled storage worker failure");
    }));
    assert!(channel.stop_and_join().await.is_err());
    assert!(channel.workers.lock().await.is_empty());
    assert!(
        channel.stop_and_join().await.is_err(),
        "retry cannot erase an observed worker failure"
    );
    Ok(())
}

#[tokio::test]
async fn explicit_close_intent_is_atomic_retryable_and_survives_owner_shutdown() -> Result<()> {
    use pl_core::thread::extensions::ExtensionMutation;
    let id = "close-intent-storage";
    let (_temp, store, sink) = sink(id).await?;
    let thread = ThreadHandle::resume_without_model(id.into(), None)?;
    thread
        .attach_storage(ColdStoreHandle::new(sink.clone()))
        .await?;
    let route = pl_model::config::ModelRouteConfig {
        account_id: pl_model::config::AccountId::new("frozen-account")?,
        model_id: "frozen-model".into(),
        effort: None,
    };
    thread
        .mutate_extensions(vec![ExtensionMutation::Put {
            id: crate::studio::model_route::MODEL_ROUTE_EXTENSION.into(),
            expected_revision: None,
            payload: crate::studio::model_route::encode(&route)?,
        }])
        .await?;
    thread.flush().await?;
    let history = store.history(id).await?;
    let before = history.checkpoint().await?.context("saved baseline")?;
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &store.session_paths("project-test", id)?.history_database(),
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?;
    db.execute_unprepared(
        "CREATE TRIGGER reject_close_intent BEFORE UPDATE ON session_checkpoint
            BEGIN SELECT RAISE(ABORT, 'controlled close intent rejection'); END",
    )
    .await?;
    let rejected = tokio::time::timeout(
        Duration::from_secs(5),
        crate::studio::agent_close::commit(&thread),
    )
    .await?;
    assert!(
        rejected.is_err(),
        "a rejected checkpoint cannot acknowledge explicit closure"
    );
    let unchanged = history.checkpoint().await?.context("retained checkpoint")?;
    assert_eq!(
        serde_json::to_vec(&unchanged)?,
        serde_json::to_vec(&before)?
    );
    assert_eq!(history.watermark().await?, before.history_fence);
    assert!(!crate::studio::agent_close::is_explicitly_closed(
        &unchanged.state
    )?);
    let generation = sink.0.channel.subscribe().borrow().fault_generation;
    db.execute_unprepared("DROP TRIGGER reject_close_intent")
        .await?;
    store
        .thread_persistence()
        .retry_history(id, generation)
        .await?;
    crate::studio::agent_close::commit(&thread).await?;
    thread.close().await?;
    let saved = history.checkpoint().await?.context("closed checkpoint")?;
    assert_eq!(
        saved.state.lifecycle,
        pl_core::thread::ThreadLifecycle::Closed
    );
    assert!(crate::studio::agent_close::is_explicitly_closed(
        &saved.state
    )?);
    assert_eq!(
        saved.state.extensions[crate::studio::model_route::MODEL_ROUTE_EXTENSION],
        before.state.extensions[crate::studio::model_route::MODEL_ROUTE_EXTENSION]
    );
    assert_eq!(saved.history_fence, history.watermark().await?);
    drop(history);
    let reloaded = crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(
        &store,
        &test_thread(id),
    )
    .await?
    .context("reopened canonical checkpoint")?;
    assert!(crate::studio::agent_close::is_explicitly_closed(
        &reloaded.state
    )?);
    assert_eq!(reloaded.history_fence, saved.history_fence);
    assert_eq!(
        reloaded.state.extensions[crate::studio::agent_close::EXTENSION],
        saved.state.extensions[crate::studio::agent_close::EXTENSION]
    );
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn a_reopened_studio_sink_accepts_a_thread_with_durable_history() -> Result<()> {
    let id = "reopened-durable-thread";
    let temp = tempfile::tempdir()?;
    // Native paths remain literal, including URI-looking characters and deep data roots.
    let database = temp
        .path()
        .join("存储 %2F #")
        .join("nested".repeat(16))
        .join("data/studio.sqlite");
    let store = StudioStore::open(&database).await?;
    let thread = test_thread(id);
    register_test_thread(&store, &thread).await?;
    let original = ThreadStorageSink::new(store.clone(), thread, None).await?;
    spawn_live_projection(&original);
    let write = ticket(id, 1);
    let checkpoint = write.checkpoint.clone();
    original.admit(id, write)?;
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 1),
        original.flush(id, 1),
        || channel_facts(&original),
    )
    .await??;
    drop(original);
    drop(store);

    let reopened_store = StudioStore::open(&database).await?;
    assert!(
        ThreadStorageSink::new(reopened_store.clone(), test_thread(id), None,)
            .await
            .is_err(),
        "history ahead of the checkpoint must not silently skip effects"
    );
    let reopened =
        ThreadStorageSink::new(reopened_store, test_thread(id), Some(&checkpoint)).await?;
    spawn_live_projection(&reopened);
    let resumed = ThreadHandle::resume_without_model(id.into(), Some(checkpoint))?;
    resumed
        .attach_storage(ColdStoreHandle::new(reopened.clone()))
        .await?;
    assert_eq!(reopened.pressure(id).durable_sequence, 1);
    await_durable(
        Duration::from_secs(5),
        "reopened durable barrier",
        resumed.flush(),
        || String::from("the reopened owner never reached its durable ticket"),
    )
    .await??;
    resumed.close().await?;
    let saved = reopened
        .0
        .store
        .history(id)
        .await?
        .checkpoint()
        .await?
        .context("owner shutdown checkpoint")?;
    assert_eq!(
        saved.state.lifecycle,
        pl_core::thread::ThreadLifecycle::Closed
    );
    assert!(
        !crate::studio::agent_close::is_explicitly_closed(&saved.state)?,
        "ordinary shutdown must not seal future execution"
    );
    let restored = ThreadHandle::resume_without_model(id.into(), Some(saved))?;
    assert_eq!(
        restored.snapshot().lifecycle,
        pl_core::thread::ThreadLifecycle::Open
    );
    assert!(!crate::studio::agent_close::is_explicitly_closed(
        &restored.snapshot()
    )?);
    restored.close().await?;
    Ok(())
}

/// The projection an observation worker would own: empty until the test hands it the admitted
/// facts, which it folds and hands back to the reliable channel exactly like the production owner.
pub(super) async fn live_projection(
    sink: &ThreadStorageSink,
) -> Result<crate::studio::thread_projection::LiveProjection> {
    let mut projection = crate::studio::thread_projection::LiveProjection::new();
    projection.bind_execution_history(
        sink.0.channel.order_index(),
        sink.0.store.history(&sink.0.thread.id).await?,
    )?;
    Ok(projection)
}

#[test]
fn execution_index_retires_sources_and_charges_pending_until_real_confirmation() -> Result<()> {
    let process = Arc::new(AtomicU64::new(0));
    let index = Arc::new(RuntimeOrderIndex::new(process.clone(), 30));
    let observed = index.reserve_observed("attempt-one", "observed")?;
    assert_eq!(observed, 31);
    let reserved_bytes = index.retained_bytes();
    assert!(reserved_bytes > "observed".len() as u64);
    assert_eq!(process.load(Ordering::Acquire), reserved_bytes);
    index.retain::<()>(&Default::default(), Vec::new());
    let active_bytes = index.retained_bytes();
    assert!(active_bytes > 0 && active_bytes < reserved_bytes);
    assert_eq!(
        index.assigned("observed"),
        Some(observed),
        "an older checkpoint cannot retire a source the projection has not reached"
    );
    index.finish_source("attempt-one");
    let identities = BTreeMap::from([("observed".to_owned(), 5_u64)]);
    index.retain(&identities, Vec::new());
    assert!(
        index.retained_bytes() > 0 && index.retained_bytes() < active_bytes,
        "retained facts own the identity after source and change keys are released"
    );
    assert_eq!(index.assigned("observed"), Some(observed));
    index.retain::<()>(&Default::default(), vec!["observed".into()]);
    assert_eq!(
        index.retained_bytes(),
        0,
        "unmaterialized retired source needs no save"
    );
    let order = index.reserve_observed("attempt-two", "completed")?;
    assert_eq!(
        order, 32,
        "retiring a source cannot rewind the scalar ceiling"
    );
    let item = pl_protocol::ThreadItem::new(
        "completed".into(),
        "thread".into(),
        "turn".into(),
        order,
        9,
        10,
        20,
        pl_protocol::ThreadItemState::Raw(pl_protocol::ThreadRawItem::stored(
            Vec::new(),
            "done",
            20,
        )),
    );
    index.materialize(&item, 7)?;
    index.mark_completion("completed", true);
    index.finish_source("attempt-two");
    index.retain::<()>(&Default::default(), Vec::new());
    assert!(index.pending("completed"));
    assert!(index.is_sealed("completed"));
    assert!(index.is_terminal("completed"));
    index.confirm_saved(6);
    assert!(
        index.retained_bytes() > 0,
        "an earlier save cannot release this pending fact"
    );
    index.confirm_saved(7);
    assert_eq!(index.retained_bytes(), 0);
    assert_eq!(process.load(Ordering::Acquire), 0);
    assert!(!index.is_sealed("completed"));
    assert!(!index.is_terminal("completed"));
    assert_eq!(index.assign("next")?, 33);
    drop(index);
    assert_eq!(process.load(Ordering::Acquire), 0);
    Ok(())
}

#[test]
fn execution_index_budget_rejects_without_allocating_or_rewinding() -> Result<()> {
    let process = Arc::new(AtomicU64::new(0));
    let index = RuntimeOrderIndex::new(process.clone(), 10);
    index
        .other_thread_bytes
        .store(MAX_HISTORY_THREAD_BYTES, Ordering::Release);
    let rejected = index.reserve_observed("attempt", "rejected").unwrap_err();
    assert!(rejected.is::<ExecutionIndexBudgetFull>());
    assert_eq!(index.assigned("rejected"), None);
    assert_eq!(process.load(Ordering::Acquire), 0);
    index.other_thread_bytes.store(0, Ordering::Release);
    assert_eq!(index.reserve_observed("attempt", "accepted")?, 11);
    index.finish_source("attempt");
    index.retain::<()>(&Default::default(), Vec::new());
    assert_eq!(process.load(Ordering::Acquire), 0);
    Ok(())
}

#[test]
fn execution_index_materialize_budget_rejection_leaves_no_partial_identity_or_stamp() -> Result<()>
{
    let process = Arc::new(AtomicU64::new(0));
    let index = RuntimeOrderIndex::new(process.clone(), 40);
    let id = "materialize-budget";
    let probe = RuntimeOrderIndex::new(Arc::new(AtomicU64::new(0)), 40);
    probe.assign(id)?;
    let placement_bytes = probe.retained_bytes();
    let item = pl_protocol::ThreadItem::new(
        id.into(),
        "thread".into(),
        "original-turn".into(),
        41,
        9,
        10,
        20,
        pl_protocol::ThreadItemState::Raw(pl_protocol::ThreadRawItem::stored(
            Vec::new(),
            "completed",
            20,
        )),
    );
    // There is room for placement alone, but not its stamp. Both must be funded before
    // insertion; rejecting the stamp must not leave an unowned retained=true entry.
    index.other_thread_bytes.store(
        MAX_HISTORY_THREAD_BYTES - placement_bytes,
        Ordering::Release,
    );
    let error = index.materialize(&item, 7).unwrap_err();
    assert!(error.is::<ExecutionIndexBudgetFull>());
    assert_eq!(index.assigned(id), None);
    assert_eq!(index.inner.lock().unwrap().ceiling, 40);
    assert_eq!(index.retained_bytes(), 0);
    assert_eq!(process.load(Ordering::Acquire), 0);

    index.other_thread_bytes.store(0, Ordering::Release);
    index.materialize(&item, 7)?;
    index.retain::<()>(&Default::default(), Vec::new());
    let pending = index.pending_placement(id, "thread").unwrap();
    let resident_bytes = index.retained_bytes();
    let mut growing = item.clone();
    growing.turn_id.push_str("-additional-stamp-bytes");
    growing.revision += 1;
    index
        .other_thread_bytes
        .store(MAX_HISTORY_THREAD_BYTES - resident_bytes, Ordering::Release);
    let error = index.materialize(&growing, 8).unwrap_err();
    assert!(error.is::<ExecutionIndexBudgetFull>());
    assert_eq!(index.pending_placement(id, "thread"), Some(pending));
    assert_eq!(index.inner.lock().unwrap().assigned[id].effect, Some(7));
    assert_eq!(index.retained_bytes(), resident_bytes);
    assert_eq!(process.load(Ordering::Acquire), resident_bytes);
    index.confirm_saved(7);
    assert_eq!(index.retained_bytes(), 0);
    assert_eq!(process.load(Ordering::Acquire), 0);
    // A committed database prefix can precede its local acknowledgement.
    // Replacing that pending key must charge only the actual replacement.
    index.other_thread_bytes.store(0, Ordering::Release);
    index.materialize(&item, 9)?;
    index.retain::<()>(&Default::default(), Vec::new());
    index.seed(item.ordinal, 9);
    index.materialize(&item, 10)?;
    index.retain::<()>(&Default::default(), Vec::new());
    index.confirm_saved(10);
    assert!(index.inner.lock().unwrap().assigned.is_empty());
    assert_eq!(index.retained_bytes(), 0);
    assert_eq!(process.load(Ordering::Acquire), 0);
    Ok(())
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn execution_index_materialize_and_real_save_confirmation_are_atomic() -> Result<()> {
    for materialize_first in [true, false] {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let id = if materialize_first {
            "materialize-first"
        } else {
            "confirmation-first"
        };
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let lease = sink.0.channel.step_lock.lock().await;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection(&sink).await?;
        let old_write = visible_input_ticket(id, 1, "racing-identity")?;
        let old_prepared =
            drive_live_projection(&mut projection, &chat, &sink, id, old_write.clone()).await?;
        drive_live_projection(&mut projection, &chat, &sink, id, ticket(id, 2)).await?;
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: projection.retained_bytes(),
                pending: None,
            })?;
        let index = sink.0.channel.order_index();
        {
            let state = index.inner.lock().unwrap();
            let entry = &state.assigned["racing-identity"];
            assert!(!entry.retained);
            assert_eq!(entry.effect, Some(1));
            assert_eq!(state.durable, 0);
        }
        // This is the old placement a later reliable fact captured through live.resolve.
        let old_placement = index.pending_placement("racing-identity", id).unwrap();
        let mut next_item = old_prepared.items[0].clone();
        next_item.ordinal = old_placement.ordinal;
        next_item.created_at = old_placement.created_at;
        next_item.revision = old_placement.revision + 1;
        next_item.updated_at += 1;

        if materialize_first {
            let (entered, materialize_entered) = tokio::sync::oneshot::channel();
            let (release, materialize_release) = std::sync::mpsc::channel();
            *index.materialize_gate.lock().unwrap() = Some(MaterializeGate {
                entered,
                release: materialize_release,
            });
            let materializing = tokio::task::spawn_blocking({
                let index = index.clone();
                let item = next_item.clone();
                move || index.materialize(&item, 3)
            });
            tokio::time::timeout(Duration::from_secs(5), materialize_entered).await??;
            assert!(
                matches!(
                    index.inner.try_lock(),
                    Err(std::sync::TryLockError::WouldBlock)
                ),
                "allocation and stamp/effect update must stay in one critical section"
            );
            let (entered, confirmation_entered) = tokio::sync::oneshot::channel();
            *index.confirm_saved_entered.lock().unwrap() = Some(entered);
            let saving = tokio::task::spawn_blocking({
                let inner = sink.0.clone();
                let write = old_write.clone();
                let prepared = old_prepared.clone();
                move || {
                    tokio::runtime::Handle::current().block_on(persist_effect(
                        &inner,
                        1,
                        &write,
                        &prepared,
                        encoded_bytes(&write.effect),
                    ))
                }
            });
            tokio::time::timeout(Duration::from_secs(5), confirmation_entered).await??;
            assert_eq!(
                store.history(id).await?.watermark().await?,
                1,
                "the real transaction committed before it tried to reclaim the old identity"
            );
            assert!(
                !saving.is_finished(),
                "confirmation must wait for the materialization lock"
            );
            release.send(())?;
            tokio::time::timeout(Duration::from_secs(5), materializing).await???;
            tokio::time::timeout(Duration::from_secs(5), saving).await???;
        } else {
            persist_effect(
                &sink.0,
                1,
                &old_write,
                &old_prepared,
                encoded_bytes(&old_write.effect),
            )
            .await?;
            assert_eq!(index.assigned("racing-identity"), None);
            assert_eq!(index.retained_bytes(), 0);
            // Confirmation won the lock before this call. Recreate the captured placement,
            // never allocate a different ordinal for this later reliable fact.
            index.materialize(&next_item, 3)?;
        }
        let pending = index.pending_placement("racing-identity", id).unwrap();
        assert_eq!(pending.ordinal, old_placement.ordinal);
        assert_eq!(pending.revision, next_item.revision);
        assert_eq!(pending.created_at, old_placement.created_at);
        assert_eq!(pending.updated_at, next_item.updated_at);
        assert_eq!(
            index.inner.lock().unwrap().assigned["racing-identity"].effect,
            Some(3)
        );
        assert!(index.pending("racing-identity"));
        assert_eq!(chat.durable_seq(), 1);
        let mut next_write = visible_input_ticket(id, 3, "racing-identity")?;
        let input = Arc::make_mut(&mut next_write.checkpoint.state.inputs)
            .first_mut()
            .unwrap();
        input.accepted_sequence = 1;
        input.ordinal = 1;
        Arc::make_mut(&mut next_write.effect).inputs = Arc::from([InputChange::Transition {
            id: input.input.id.clone(),
            revision: input.revision,
            state: input.state.clone(),
        }]);
        let next_current = projection
            .prepare_committed(
                &sink.0.thread,
                &next_write.effect,
                &next_write.checkpoint.state,
            )
            .await?;
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: projection.retained_bytes(),
                pending: None,
            })?;
        // The later fact has also left the live window; only its new unsaved obligation
        // must keep the reconstructed identity resident until the writer reaches it.
        index.retain::<()>(&Default::default(), vec!["racing-identity".into()]);
        let mut next_prepared = old_prepared.clone();
        next_prepared.sequence = 3;
        next_prepared.current = next_current.current.clone();
        next_prepared.current_state = next_current.current_state.clone();
        next_prepared.accounting = Arc::new(
            crate::studio::thread_projection::PreparedAccounting::prepare(&next_write.effect)?,
        );
        next_prepared.items = vec![next_item.clone()];
        next_prepared.completions = Arc::from([]);
        sink.admit(id, next_write)?;
        assert!(sink.0.channel.prepare(Arc::new(next_prepared)));
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: projection.retained_bytes(),
                pending: None,
            })?;
        let mut effects_released = sink.0.channel.effects_released.subscribe();
        drop(lease);
        tokio::time::timeout(Duration::from_secs(5), async {
            sink.flush(id, 3).await?;
            // The durable report precedes process-budget decharge. Observe the same
            // writer's real release before checking that its retained bytes are zero.
            effects_released
                .wait_for(|sequence| *sequence >= 3)
                .await
                .context("writer release observation closed before the saved target")?;
            Ok::<_, anyhow::Error>(())
        })
        .await??;
        let history = store.history(id).await?;
        let saved = history.item("racing-identity").await?.unwrap();
        assert_eq!(saved.ordinal, old_placement.ordinal);
        assert_eq!(saved.revision, next_item.revision);
        assert_eq!(saved.created_at, old_placement.created_at);
        assert_eq!(history.watermark().await?, 3);
        assert_eq!(index.retained_bytes(), 0);
        // Saving releases the writer/index, not the still-live current projection owner.
        assert_eq!(sink.pressure(id).thread_bytes, projection.retained_bytes());
        drop(projection);
        sink.0.channel.release_projection_retention();
        assert_eq!(sink.pressure(id).thread_bytes, 0);
        assert_eq!(sink.0.channel.process_bytes.load(Ordering::Acquire), 0);
        sink.0.channel.stop_and_join().await?;
    }
    Ok(())
}

#[test]
fn execution_index_channel_replacement_carries_only_live_or_pending_obligations() -> Result<()> {
    let process = Arc::new(AtomicU64::new(0));
    let (capacity, mut capacity_changes) = tokio::sync::watch::channel(0_u64);
    let channel = HistoryChannel::with_capacity(process.clone(), capacity.clone());
    let producer = channel.order_index();
    assert_eq!(producer.reserve_observed("running", "part")?, 1);
    let replacement = channel.next_storage_channel();
    assert!(Arc::ptr_eq(&producer, &replacement.order_index()));
    assert_eq!(replacement.order_index.assign("next")?, 2);
    let weak = Arc::downgrade(&producer);
    drop(producer);
    drop(channel);
    drop(replacement);
    assert!(
        weak.upgrade().is_none(),
        "no registry may keep the last owner alive"
    );
    assert_eq!(process.load(Ordering::Acquire), 0);
    assert!(capacity_changes.has_changed()?);
    capacity_changes.borrow_and_update();
    let closed = HistoryChannel::new(process.clone());
    let finished_projection = closed.order_index();
    assert_eq!(finished_projection.assign("finished-scope")?, 1);
    let weak = Arc::downgrade(&closed.order_index);
    let reopened = closed.next_storage_channel();
    assert!(!Arc::ptr_eq(&closed.order_index, &reopened.order_index));
    assert_eq!(reopened.order_index.retained_bytes(), 0);
    assert_eq!(reopened.order_index.assign("new-scope")?, 2);
    drop(closed);
    drop(finished_projection);
    assert!(weak.upgrade().is_none());
    drop(reopened);
    assert_eq!(process.load(Ordering::Acquire), 0);
    Ok(())
}

#[tokio::test]
async fn execution_index_many_completed_scopes_return_the_reliable_budget_to_baseline() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "index-bounded";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let mut projection = live_projection(&sink).await?;
    let chat = store.chat_session(id).await?;
    let index = sink.0.channel.order_index();
    for sequence in 1..=20 {
        // Mirror LiveOwner::observe_storage using only the writer's real durable watermark.
        projection.confirm_sources(store.history(id).await?.watermark().await?);
        let mut write = ticket(id, sequence);
        let mut records = Vec::new();
        for part in 0..80 {
            let input =
                visible_input_ticket(id, sequence, &format!("turn-{sequence}-part-{part}"))?;
            let mut record = input.checkpoint.state.inputs[0].clone();
            record.state = InputState::Consumed {
                turn_id: format!("turn-{sequence}"),
                attempt_id: format!("attempt-{sequence}"),
            };
            records.push(record);
        }
        let turn = turn_record(
            &format!("turn-{sequence}"),
            &records[0].input.id,
            TurnState::Finished(TurnOutcome::Completed),
        );
        write.checkpoint.state.turns = Arc::from([turn.clone()]);
        Arc::make_mut(&mut write.effect).turn = Some(turn);
        write.checkpoint.state.inputs = records.clone().into();
        Arc::make_mut(&mut write.effect).inputs = records
            .into_iter()
            .map(InputChange::Accepted)
            .collect::<Vec<_>>()
            .into();
        drive_live_projection(&mut projection, &chat, &sink, id, write).await?;
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: projection.retained_bytes(),
                pending: None,
            })?;
        sink.flush(id, sequence).await?;
        // Durable display heads/members are owned by SQLite now. As LiveOwner does
        // on storage acknowledgement, retire that exact prefix before measuring
        // the next resident scope; a writer flush alone does not notify this fixture.
        let before_confirm = projection.retained_bytes();
        projection.confirm_sources(store.history(id).await?.watermark().await?);
        assert!(
            projection.retained_bytes() < before_confirm,
            "the durable display prefix must release its retained members"
        );
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: projection.retained_bytes(),
                pending: None,
            })?;
        assert!(index.inner.lock().unwrap().assigned.len() <= 81);
        assert!(index.retained_bytes() < 32 * 1024);
        assert!(
            sink.pressure(id).thread_bytes < 128 * 1024,
            "scope {sequence}: projection={}, thread={}",
            projection.retained_bytes(),
            sink.pressure(id).thread_bytes
        );
    }
    drive_live_projection(&mut projection, &chat, &sink, id, ticket(id, 21)).await?;
    sink.0
        .channel
        .set_projection_retention(ProjectionRetention {
            resident_bytes: projection.retained_bytes(),
            pending: None,
        })?;
    sink.flush(id, 21).await?;
    assert_eq!(index.retained_bytes(), 0);
    assert_eq!(sink.pressure(id).thread_bytes, projection.retained_bytes());
    drop(projection);
    sink.0.channel.release_projection_retention();
    assert_eq!(sink.pressure(id).thread_bytes, 0);
    assert_eq!(sink.0.channel.process_bytes.load(Ordering::Acquire), 0);
    assert_eq!(chat.head_seq(), 1620);
    sink.0.channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn execution_index_late_reliable_input_restores_placement_without_resealing() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "index-late";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let chat = store.chat_session(id).await?;
    let mut projection = live_projection(&sink).await?;
    let mut accepted = visible_input_ticket(id, 1, "late-input")?;
    let input = Arc::make_mut(&mut accepted.checkpoint.state.inputs)
        .first_mut()
        .unwrap();
    input.state = InputState::Pending;
    Arc::make_mut(&mut accepted.effect).inputs = Arc::from([InputChange::Accepted(input.clone())]);
    let first = drive_live_projection(&mut projection, &chat, &sink, id, accepted).await?;
    sink.flush(id, 1).await?;
    let history = store.history(id).await?;
    let original = pl_core::chat::ChatHistory::item(&history, "late-input")
        .await?
        .unwrap();
    assert_eq!(original.header.parent_id, None);
    let checkpoint = history.checkpoint().await?.unwrap();
    sink.0.channel.stop_and_join().await?;
    drop(projection);
    drop(sink);
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), Some(&checkpoint)).await?;
    let mut projection = live_projection(&sink).await?;
    assert_eq!(sink.0.channel.order_index.retained_bytes(), 0);
    let mut late = visible_input_ticket(id, 2, "late-input")?;
    let input = Arc::make_mut(&mut late.checkpoint.state.inputs)
        .first_mut()
        .unwrap();
    input.state = InputState::Consumed {
        turn_id: "later-turn".into(),
        attempt_id: "later-attempt".into(),
    };
    input.accepted_sequence = 1;
    input.ordinal = 1;
    Arc::make_mut(&mut late.effect).inputs = Arc::from([InputChange::Transition {
        id: input.input.id.clone(),
        revision: input.revision,
        state: input.state.clone(),
    }]);
    let prepared = drive_live_projection(&mut projection, &chat, &sink, id, late).await?;
    assert!(
        prepared.completions.is_empty(),
        "a later execution binding cannot reseal completion"
    );
    assert_eq!(prepared.items[0].ordinal, first.items[0].ordinal);
    assert_eq!(prepared.items[0].created_at, first.items[0].created_at);
    assert!(prepared.items[0].revision > first.items[0].revision);
    sink.flush(id, 2).await?;
    assert_eq!(chat.head_seq(), 1);
    assert_eq!(
        pl_core::chat::ChatHistory::item(&history, "late-input").await?,
        Some(original)
    );
    sink.0.channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn stall_clock_belongs_to_the_writable_prefix_and_survives_later_admissions() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "writable-stall-clock";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let chat = store.chat_session(id).await?;
    let mut projection = live_projection(&sink).await?;
    let lease = sink.0.channel.step_lock.lock().await;
    let first = visible_input_ticket(id, 1, "first")?;
    sink.admit(id, first.clone())?;
    assert_eq!(
        lock_progress(&sink.0).stage,
        Some(HistoryStage::ProjectionPrepare)
    );
    sink.0.channel.detect_stall();
    assert!(sink.0.channel.subscribe().borrow().fault.is_none());
    let mut prepared = projection
        .prepare_committed(&sink.0.thread, &first.effect, &first.checkpoint.state)
        .await?;
    projection.publish_prepared(&chat, &mut prepared).await?;
    assert!(sink.0.channel.prepare(prepared));
    assert!(lock_progress(&sink.0).last_progress_at.unwrap().elapsed() < NO_PROGRESS_WINDOW);
    let stalled_at = Instant::now() - NO_PROGRESS_WINDOW;
    lock_progress(&sink.0).last_progress_at = Some(stalled_at);
    let second = visible_input_ticket(id, 2, "second")?;
    sink.admit(id, second.clone())?;
    assert_eq!(lock_progress(&sink.0).last_progress_at, Some(stalled_at));
    let mut prepared = projection
        .prepare_committed(&sink.0.thread, &second.effect, &second.checkpoint.state)
        .await?;
    projection.publish_prepared(&chat, &mut prepared).await?;
    assert!(sink.0.channel.prepare(prepared));
    assert_eq!(
        lock_progress(&sink.0).stage,
        Some(HistoryStage::WriterQueue)
    );
    assert_eq!(lock_progress(&sink.0).last_progress_at, Some(stalled_at));
    let retained = sink.pressure(id).thread_bytes;
    sink.0.channel.detect_stall();
    let failed = sink.0.channel.subscribe().borrow().clone();
    assert_eq!(
        failed.fault,
        Some(pl_protocol::studio::HistoryFault::NoProgress)
    );
    assert_eq!(lock_progress(&sink.0).prepared_through(), 2);
    assert_eq!(sink.pressure(id).thread_bytes, retained);
    assert!(sink.flush(id, 2).await.is_err());
    sink.0.channel.detect_stall();
    assert_eq!(
        sink.0.channel.subscribe().borrow().fault_generation,
        failed.fault_generation
    );
    drop(lease);
    store
        .thread_persistence()
        .retry_history(id, failed.fault_generation)
        .await?;
    sink.flush(id, 2).await?;
    assert_eq!(store.history(id).await?.watermark().await?, 2);
    assert!(lock_progress(&sink.0).last_progress_at.is_none());
    sink.0.channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn execution_index_retired_pending_survives_a_rejected_writer_transaction() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "index-failed";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let chat = store.chat_session(id).await?;
    let mut projection = live_projection(&sink).await?;
    drive_live_projection(&mut projection, &chat, &sink, id, ticket(id, 1)).await?;
    sink.flush(id, 1).await?;
    let lease = sink.0.channel.step_lock.lock().await;
    let write = visible_input_ticket(id, 2, "pending-retired")?;
    let prepared = drive_live_projection(&mut projection, &chat, &sink, id, write.clone()).await?;
    drive_live_projection(&mut projection, &chat, &sink, id, ticket(id, 3)).await?;
    sink.0
        .channel
        .set_projection_retention(ProjectionRetention {
            resident_bytes: projection.retained_bytes(),
            pending: None,
        })?;
    let index = sink.0.channel.order_index();
    assert!(index.pending("pending-retired"));
    let path = store
        .session_paths("project-test", id)?
        .root()
        .join("history.sqlite");
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?;
    db.execute_unprepared(
        "CREATE TRIGGER reject_index_save BEFORE UPDATE OF applied_write_seq ON history_meta
             BEGIN SELECT RAISE(ABORT, 'controlled index save rejection'); END",
    )
    .await?;
    assert!(
        persist_effect(&sink.0, 2, &write, &prepared, encoded_bytes(&write.effect))
            .await
            .is_err()
    );
    let charged = index.retained_bytes();
    assert!(charged > 0);
    assert_eq!(chat.durable_seq(), 0);
    assert_eq!(sink.0.channel.subscribe().borrow().queued_records, 2);
    assert!(sink.pressure(id).thread_bytes >= charged);
    assert!(index.pending("pending-retired"));
    assert!(index.is_sealed("pending-retired"));
    db.execute_unprepared("DROP TRIGGER reject_index_save")
        .await?;
    persist_effect(&sink.0, 2, &write, &prepared, encoded_bytes(&write.effect)).await?;
    assert_eq!(index.retained_bytes(), 0);
    assert_eq!(chat.durable_seq(), 1);
    drop(lease);
    sink.flush(id, 3).await?;
    assert_eq!(sink.pressure(id).thread_bytes, projection.retained_bytes());
    drop(projection);
    sink.0.channel.release_projection_retention();
    assert_eq!(sink.pressure(id).thread_bytes, 0);
    sink.0.channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn execution_index_writer_replacement_and_cold_reopen_preserve_the_right_ceiling()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let database = temp.path().join("data/studio.sqlite");
    let id = "index-reopened";
    let store = StudioStore::open(&database).await?;
    register_test_thread(&store, &test_thread(id)).await?;
    let original = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let mut projection = live_projection(&original).await?;
    let chat = store.chat_session(id).await?;
    let first = drive_live_projection(
        &mut projection,
        &chat,
        &original,
        id,
        visible_input_ticket(id, 1, "durable-execution")?,
    )
    .await?;
    original.flush(id, 1).await?;
    let checkpoint = store.history(id).await?.checkpoint().await?.unwrap();
    let index = original.0.channel.order_index();
    let weak = Arc::downgrade(&index);
    let reserved = index.reserve_observed("still-running", "unmaterialized-part")?;
    assert!(reserved > first.items[0].ordinal);
    let replacement =
        ThreadStorageSink::new(store.clone(), test_thread(id), Some(&checkpoint)).await?;
    assert!(Arc::ptr_eq(&index, &replacement.0.channel.order_index()));
    assert_eq!(
        replacement
            .0
            .channel
            .order_index
            .assign("replacement-next")?,
        reserved + 1
    );
    replacement.0.channel.stop_and_join().await?;
    drop(projection);
    drop(index);
    drop(first);
    drop(original);
    drop(replacement);
    drop(chat);
    drop(store);
    assert!(
        weak.upgrade().is_none(),
        "closed owners cannot leave a process registry behind"
    );
    let reopened_store = StudioStore::open(&database).await?;
    let reopened =
        ThreadStorageSink::new(reopened_store, test_thread(id), Some(&checkpoint)).await?;
    let reopened_index = reopened.0.channel.order_index();
    assert_eq!(reopened_index.retained_bytes(), 0);
    assert_eq!(
        reopened_index.assign("cold-next")?,
        2,
        "cold reopen derives its ceiling from durable execution rows, not abandoned reservations"
    );
    reopened.0.channel.stop_and_join().await?;
    Ok(())
}

/// Takes the admitted facts over exactly as the Thread's live projection owner does.
///
/// The Studio runtime installs that owner during Thread assembly, and the history writer refuses
/// to save a fact no projection holds. These tests exercise the writer on its own, so they drive
/// the same production projection against the same reliable admission channel: one projection per
/// commit, published shape unchanged, only the caller differs.
pub(crate) fn spawn_live_projection(sink: &ThreadStorageSink) {
    drop(spawn_projection(
        sink.0.store.clone(),
        sink.0.thread.clone(),
    ));
}

/// Drives the real projection for an assembler-installed sink without downcasting its erased
/// ColdStoreHandle or retaining that writer incarnation after its core/observer have ended.
pub(crate) fn spawn_live_projection_for_thread(
    store: StudioStore,
    id: &str,
) -> tokio::task::JoinHandle<()> {
    let catalog = store.catalog();
    let agent = catalog.get_agent(id).expect("registered projection agent");
    let session = catalog
        .get_session(&agent.session_id)
        .expect("registered projection session");
    let thread = crate::studio::records::thread_projection(&session, &agent, |id| {
        catalog.get_agent(id).map(|agent| agent.thread_id)
    })
    .expect("Native projection");
    spawn_projection(store, thread)
}

fn spawn_projection(
    store: StudioStore,
    thread: pl_protocol::Thread,
) -> tokio::task::JoinHandle<()> {
    let channel = store.thread_persistence().history_channel(&thread.id);
    let chat = store
        .thread_persistence()
        .chat_session(&thread.id)
        .expect("initialized writer Session");
    tokio::spawn(async move {
        let mut projection = crate::studio::thread_projection::LiveProjection::new();
        projection
            .bind_execution_history(
                channel.order_index(),
                store
                    .history(&thread.id)
                    .await
                    .expect("initialized execution history"),
            )
            .expect("one projection binding");
        let mut failed = std::collections::BTreeSet::new();
        // Wake on the channel's own status watch, never on the channel's `Notify`: the history
        // writer is the one task that waits on that `Notify`, and a second waiter would consume
        // the single wakeup permit a recovery notification hands out.
        let mut updates = channel.subscribe();
        loop {
            if channel.stopping.is_cancelled() {
                return;
            }
            if let Some(write) = channel.next_unprojected() {
                let sequence = write.effect.sequence;
                if failed.contains(&sequence) {
                    tokio::time::sleep(Duration::from_millis(5)).await;
                    continue;
                }
                // A reliable-output repair can name an identity this bounded window released; the
                // production observation owner reads that committed body back and folds it in, so
                // the harness drives the same step instead of skipping a fact the writer must save.
                if !write.effect.delivery_repairs.is_empty() {
                    let seeded = match store.history(&thread.id).await {
                        Ok(history) => crate::studio::thread_projection::seed_repaired_targets(
                            &mut projection,
                            &history,
                            &write.effect,
                        )
                        .await
                        .map_err(|error| error.to_string()),
                        Err(error) => Err(error.to_string()),
                    };
                    if let Err(error) = seeded {
                        failed.insert(sequence);
                        channel.fail_projection(sequence, error);
                        continue;
                    }
                }
                let published = async {
                    let mut prepared = projection
                        .prepare_committed(&thread, &write.effect, &write.checkpoint.state)
                        .await?;
                    projection.publish_prepared(&chat, &mut prepared).await?;
                    Ok::<_, crate::studio::thread_projection::ProjectionError>(prepared)
                }
                .await;
                match published {
                    Ok(prepared) => {
                        channel.prepare(prepared);
                    }
                    // The writer never projects, so failing here is what the running Studio sees
                    // from its observation worker: the fact is reported and the barrier fails
                    // closed with the projection's own reason.
                    Err(error) => {
                        failed.insert(sequence);
                        channel.fail_projection(sequence, error.to_string());
                    }
                }
                continue;
            }
            tokio::select! {
                changed = updates.changed() => if changed.is_err() { return; },
                () = channel.stopping.cancelled() => return,
            }
        }
    })
}

/// Save the original terminal report in the same real effect/checkpoint transaction as Studio.
/// No parent owner is needed; recovery must later prove its independently missing receipt.
pub(crate) async fn save_terminal_report(
    store: &StudioStore,
    thread: &pl_protocol::Thread,
    message: pl_core::thread::inbox::ThreadMessage,
) -> Result<()> {
    let checkpoint = store.history(&thread.id).await?.checkpoint().await?;
    let sink = ThreadStorageSink::new(store.clone(), thread.clone(), checkpoint.as_ref()).await?;
    let sequence = checkpoint
        .as_ref()
        .map_or(1, |checkpoint| checkpoint.history_fence + 1);
    let mut terminal = ticket(&thread.id, sequence);
    if let Some(checkpoint) = checkpoint {
        terminal.checkpoint.state = checkpoint.state;
        terminal.checkpoint.state.commit_sequence = sequence;
    }
    let turn = TurnRecord {
        turn_id: "original-terminal-turn".into(),
        input_id: None,
        state: TurnState::Finished(TurnOutcome::Completed),
        model_steps: 0,
        elapsed_ms: None,
    };
    terminal.checkpoint.state.lifecycle = pl_core::thread::ThreadLifecycle::Closed;
    terminal.checkpoint.state.turns = Arc::from([turn.clone()]);
    Arc::make_mut(&mut terminal.effect).turn = Some(turn);
    let mut projection = live_projection(&sink).await?;
    let mut prepared = projection
        .prepare_committed(thread, &terminal.effect, &terminal.checkpoint.state)
        .await?;
    projection
        .publish_prepared(&sink.0.chat, &mut prepared)
        .await?;
    Arc::get_mut(&mut prepared)
        .context("new prepared effect unexpectedly shared")?
        .parent_report = Some(Arc::new(message));
    sink.admit(&thread.id, terminal)?;
    sink.0.channel.prepare(prepared);
    sink.flush(&thread.id, sequence).await?;
    sink.0.channel.stop_and_join().await
}

/// One ticket whose effect commits a visible prompt item, i.e. the shortest effect that projects
/// a durable body the writer must confirm.
pub(super) fn visible_input_ticket(
    thread_id: &str,
    sequence: u64,
    input_id: &str,
) -> Result<ThreadWrite> {
    let mut write = ticket(thread_id, sequence);
    let input = InputRecord {
        continuation: None,
        accepted_sequence: sequence,
        delivery: Default::default(),
        input: ThreadInput {
            purpose: pl_core::thread::input::InputPurpose::Message,
            id: input_id.to_owned(),
            payload: OpaquePayload::new(
                "pl.studio.prompt",
                1,
                serde_json::json!({"text":"hello","presentation":"visible","attachments":[]})
                    .to_string(),
            )?,
            context: vec![ContextContent::Text {
                text: "hello".into(),
            }],
        },
        ordinal: sequence,
        revision: sequence,
        state: InputState::Consumed {
            turn_id: "visible-turn".into(),
            attempt_id: "attempt".into(),
        },
    };
    write.checkpoint.state.inputs = Arc::from([input.clone()]);
    Arc::make_mut(&mut write.effect).inputs = Arc::from([InputChange::Accepted(input)]);
    Ok(write)
}

/// A commit the Thread's projection owner has not handed over is never written.
///
/// This is what makes "the owner released this effect from its window" imply "the projection
/// published it": the durable watermark cannot move past a fact no projection took over, so a
/// released commit is always one the product already has. The sink below is built without the
/// test projection, so nothing takes the fact over until the test hands it in itself.
#[tokio::test]
async fn a_commit_without_a_projection_handoff_is_never_saved() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    register_test_thread(&store, &test_thread("no-handoff")).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread("no-handoff"), None).await?;
    let calls_before = store.calls().metrics();
    let materials_before = store.calls().subscribe_materials().borrow().clone();
    let write = ticket("no-handoff", 1);
    sink.admit("no-handoff", write.clone())?;
    assert!(
        tokio::time::timeout(Duration::from_millis(200), sink.flush("no-handoff", 1))
            .await
            .is_err(),
        "an unprojected commit must not reach a durable barrier"
    );
    let unprojected = sink.0.channel.subscribe().borrow().clone();
    assert_eq!(unprojected.committed_sequence, 0);
    assert_eq!(unprojected.queued_records, 1);
    assert_eq!(store.history("no-handoff").await?.watermark().await?, 0);

    let chat = store.chat_session("no-handoff").await?;
    let mut projection = live_projection(&sink).await?;
    let mut prepared = projection
        .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
        .await?;
    projection.publish_prepared(&chat, &mut prepared).await?;
    sink.0.channel.prepare(prepared);
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 1),
        sink.flush("no-handoff", 1),
        || channel_facts(&sink),
    )
    .await??;
    assert_eq!(store.history("no-handoff").await?.watermark().await?, 1);
    assert_eq!(store.calls().metrics(), calls_before);
    assert_eq!(
        *store.calls().subscribe_materials().borrow(),
        materials_before
    );
    Ok(())
}

#[tokio::test]
async fn hidden_consumed_input_keeps_turn_history_complete_after_body_pruning() -> Result<()> {
    let (_temp, store, sink) = sink("hidden-input").await?;
    let input_id = "interaction:confirmed:continuation";
    let turn_id = "turn-after-confirmation";
    let mut accepted = ticket("hidden-input", 1);
    let input = InputRecord {
        continuation: None,
        accepted_sequence: 1,
        delivery: Default::default(),
        input: ThreadInput {
            purpose: pl_core::thread::input::InputPurpose::Message,
            id: input_id.into(),
            payload: OpaquePayload::new(
                "pl.studio.interaction-continuation",
                1,
                serde_json::json!({"interactionId":"confirmed","presentation":"hidden"})
                    .to_string(),
            )?,
            context: vec![ContextContent::Text {
                text: "answer".into(),
            }],
        },
        ordinal: 1,
        revision: 2,
        state: InputState::Consumed {
            turn_id: turn_id.into(),
            attempt_id: "attempt-1".into(),
        },
    };
    accepted.checkpoint.state.inputs = Arc::from([input.clone()]);
    Arc::make_mut(&mut accepted.effect).inputs = Arc::from([InputChange::Accepted(input)]);
    sink.admit("hidden-input", accepted)?;
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 1),
        sink.flush("hidden-input", 1),
        || channel_facts(&sink),
    )
    .await??;
    let history = store.history("hidden-input").await?;
    assert!(history.existing_items([input_id.into()]).await?.is_empty());
    assert!(history.input_identity(input_id).await?.is_some());

    let mut later = ticket("hidden-input", 2);
    let turn = TurnRecord {
        elapsed_ms: None,
        input_id: Some(input_id.into()),
        turn_id: turn_id.into(),
        state: TurnState::Running,
        model_steps: 0,
    };
    later.checkpoint.state.turns = Arc::from([turn.clone()]);
    Arc::make_mut(&mut later.effect).turn = Some(turn);
    sink.admit("hidden-input", later)?;
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 2),
        sink.flush("hidden-input", 2),
        || channel_facts(&sink),
    )
    .await??;
    assert_eq!(history.watermark().await?, 2);
    assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
    Ok(())
}

#[tokio::test]
async fn missing_visible_input_item_still_blocks_history() -> Result<()> {
    // A Thread re-activated after its durable timeline lost a visible input body. The projection
    // that installs now has never folded that input — it is a fresh owner, exactly like a Thread
    // whose earlier incarnation committed the input — so the effect that still references it must
    // fail closed instead of committing a timeline with a hole.
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    register_test_thread(&store, &test_thread("missing-visible")).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread("missing-visible"), None).await?;
    let mut accepted = ticket("missing-visible", 1);
    let input = InputRecord {
        continuation: None,
        accepted_sequence: 1,
        delivery: Default::default(),
        input: ThreadInput {
            purpose: pl_core::thread::input::InputPurpose::Message,
            id: "visible-input".into(),
            payload: OpaquePayload::new(
                "pl.studio.prompt",
                1,
                serde_json::json!({"text":"hello","presentation":"visible","attachments":[]})
                    .to_string(),
            )?,
            context: vec![ContextContent::Text {
                text: "hello".into(),
            }],
        },
        ordinal: 1,
        revision: 2,
        state: InputState::Consumed {
            turn_id: "visible-turn".into(),
            attempt_id: "attempt".into(),
        },
    };
    accepted.checkpoint.state.inputs = Arc::from([input.clone()]);
    Arc::make_mut(&mut accepted.effect).inputs = Arc::from([InputChange::Accepted(input)]);
    // The incarnation that committed the input projects and hands it over normally.
    let chat = store.chat_session("missing-visible").await?;
    sink.admit("missing-visible", accepted.clone())?;
    let mut owner = live_projection(&sink).await?;
    let mut prepared = owner
        .prepare_committed(&sink.0.thread, &accepted.effect, &accepted.checkpoint.state)
        .await?;
    owner.publish_prepared(&chat, &mut prepared).await?;
    sink.0.channel.prepare(prepared);
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 1),
        sink.flush("missing-visible", 1),
        || channel_facts(&sink),
    )
    .await??;
    let history = store.history("missing-visible").await?;
    let path = store
        .session_paths("project-test", "missing-visible")?
        .root()
        .join("history.sqlite");
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?;
    db.execute_unprepared("DELETE FROM history_items WHERE item_id='visible-input'")
        .await?;

    // The owner this Thread gets on re-activation never folded the input, and the durable row
    // the projection would resolve it from is gone.
    spawn_live_projection(&sink);
    let mut later = ticket("missing-visible", 2);
    let turn = TurnRecord {
        elapsed_ms: None,
        input_id: Some("visible-input".into()),
        turn_id: "visible-turn".into(),
        state: TurnState::Running,
        model_steps: 0,
    };
    later.checkpoint.state.turns = Arc::from([turn.clone()]);
    Arc::make_mut(&mut later.effect).turn = Some(turn);
    sink.admit("missing-visible", later)?;
    let error = await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 2),
        sink.flush("missing-visible", 2),
        || channel_facts(&sink),
    )
    .await
    .context("a torn projection must fail the durable barrier instead of hanging")?
    .expect_err("a visible input without its item must fail closed");
    assert!(
        error
            .to_string()
            .contains("missing the committed input item")
    );
    assert_eq!(history.watermark().await?, 1);
    Ok(())
}

#[tokio::test]
async fn unconsumed_input_survives_failed_preparation_and_a_new_turn() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "unconsumed-retry";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let chat = store.chat_session(id).await?;
    let mut projection = live_projection(&sink).await?;
    let mut input = consumed_visible_input("pending-input", "second-turn", 1)?;
    input.state = InputState::Pending;
    let mut accepted = ticket(id, 1);
    accepted.checkpoint.state.inputs = Arc::from([input.clone()]);
    Arc::make_mut(&mut accepted.effect).inputs = Arc::from([InputChange::Accepted(input.clone())]);
    drive_live_projection(&mut projection, &chat, &sink, id, accepted).await?;
    // Both runs publish a Turn before model preparation consumes anything. The first one
    // failed preparation, so the same pending identity legitimately enters the second run.
    for (sequence, turn_id, turn_state) in [
        (2, "first-turn", TurnState::Running),
        (
            3,
            "first-turn",
            TurnState::Failed {
                description: "model preparation rejected media".into(),
                model_failure: None,
            },
        ),
        (4, "second-turn", TurnState::Running),
    ] {
        let mut turn = turn_record(turn_id, "pending-input", turn_state);
        if sequence == 3 {
            turn.elapsed_ms = Some(1);
        }
        let mut write = ticket(id, sequence);
        write.checkpoint.state.inputs = Arc::from([input.clone()]);
        write.checkpoint.state.turns = Arc::from([turn.clone()]);
        Arc::make_mut(&mut write.effect).turn = Some(turn);
        drive_live_projection(&mut projection, &chat, &sink, id, write).await?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", sequence),
            sink.flush(id, sequence),
            || channel_facts(&sink),
        )
        .await??;
        let saved = store
            .history(id)
            .await?
            .existing_items(["pending-input".into()])
            .await?;
        assert!(saved["pending-input"].turn_id.is_empty());
    }
    input.state = InputState::Consumed {
        turn_id: "second-turn".into(),
        attempt_id: "attempt".into(),
    };
    input.revision += 1;
    let mut consumed = ticket(id, 5);
    consumed.checkpoint.state.inputs = Arc::from([input.clone()]);
    Arc::make_mut(&mut consumed.effect).inputs = Arc::from([InputChange::Transition {
        id: input.input.id.clone(),
        revision: input.revision,
        state: input.state.clone(),
    }]);
    drive_live_projection(&mut projection, &chat, &sink, id, consumed).await?;
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 5),
        sink.flush(id, 5),
        || channel_facts(&sink),
    )
    .await??;
    let history = store.history(id).await?;
    let saved = history.existing_items(["pending-input".into()]).await?;
    assert_eq!(saved["pending-input"].turn_id, "second-turn");
    assert_eq!(history.watermark().await?, 5);
    assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
    Ok(())
}

/// One visible, already-consumed input record owned by `turn_id`.
///
/// This is exactly what core's consuming commit leaves behind: the input is `Consumed`, so it has
/// a visible timeline item whose `turn_id` is the Turn it opened.
fn consumed_visible_input(id: &str, turn_id: &str, sequence: u64) -> Result<InputRecord> {
    Ok(InputRecord {
        continuation: None,
        accepted_sequence: sequence,
        delivery: Default::default(),
        input: ThreadInput {
            purpose: pl_core::thread::input::InputPurpose::Message,
            id: id.to_owned(),
            payload: OpaquePayload::new(
                "pl.studio.prompt",
                1,
                serde_json::json!({"text":"hello","presentation":"visible","attachments":[]})
                    .to_string(),
            )?,
            context: vec![ContextContent::Text {
                text: "hello".into(),
            }],
        },
        ordinal: sequence,
        revision: sequence,
        state: InputState::Consumed {
            turn_id: turn_id.to_owned(),
            attempt_id: "attempt".to_owned(),
        },
    })
}

/// One Turn record naming `input_id` as the input that opened it.
fn turn_record(turn_id: &str, input_id: &str, state: TurnState) -> TurnRecord {
    TurnRecord {
        elapsed_ms: None,
        input_id: Some(input_id.to_owned()),
        turn_id: turn_id.to_owned(),
        state,
        model_steps: 0,
    }
}

/// One provider output item with a single text part, as a model receipt reports it.
///
/// The multi-item stress response is exactly a long list of these: one stable identity per
/// provider item, all delivered inside one model step.
fn provider_presentation_part(index: usize) -> pl_model::completion::CompletionPresentationItem {
    use pl_model::completion::{
        CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
        CompletionPresentationPartKind,
    };
    CompletionPresentationItem {
        provider_item_id: format!("stress-item-{index}"),
        output_index: Some(index as u32),
        kind: CompletionPresentationItemKind::Text(pl_protocol::trace::TraceTextChannel::Final),
        parts: vec![CompletionPresentationPart {
            content_index: 0,
            provider_part_id: Some(format!("stress-part-{index}")),
            kind: CompletionPresentationPartKind::OutputText,
            text: format!("chunk-{index}"),
        }],
    }
}

/// The snapshot attempt and the matching effect update for one committed step of `parts` parts.
///
/// The receipt is the model crate's own `pl.model.assistant` frame — the same payload a real
/// adapter writes — so the projection itemizes it through its public receipt reader instead of a
/// test-only shape.
fn committed_parts_attempt(
    turn_id: &str,
    attempt_id: &str,
    parts: usize,
) -> Result<(
    pl_core::thread::RequestAttempt,
    pl_core::thread::journal::AttemptUpdate,
)> {
    committed_presentation_attempt(
        turn_id,
        attempt_id,
        (0..parts).map(provider_presentation_part).collect(),
    )
}

fn committed_presentation_attempt(
    turn_id: &str,
    attempt_id: &str,
    presentation_items: Vec<pl_model::completion::CompletionPresentationItem>,
) -> Result<(
    pl_core::thread::RequestAttempt,
    pl_core::thread::journal::AttemptUpdate,
)> {
    let receipt = pl_model::runtime::ModelResponseReceipt {
        binding: pl_model::runtime::ModelCallBinding {
            account_id: "fixture".into(),
            model_id: "fixture-model".into(),
            protocol: pl_model::protocol::ProtocolKind::OpenAiCompatible,
            wire_api: pl_model::protocol::WireApi::ChatCompletions,
            isolation: "test".into(),
            purpose: "test".into(),
            context_window: None,
            max_context_window: None,
            auto_compact_limit: None,
        },
        response: pl_model::completion::CompletionResponse {
            replay: None,
            response_id: None,
            content: None,
            reasoning_content: None,
            tool_calls: Vec::new(),
            responses_context_items: Vec::new(),
            presentation_items,
            orchestration: Default::default(),
            timing: None,
            accounting: Default::default(),
            model: "fixture-model".into(),
            model_observation: None,
            observation: Default::default(),
        },
    };
    // The durable assistant frame is exactly this pair of receipt and tool bindings.
    #[derive(serde::Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Frame<'a> {
        receipt: &'a pl_model::runtime::ModelResponseReceipt,
        bindings: Vec<ModelToolCall>,
    }
    let frame = OpaquePayload::new(
        "pl.model.assistant",
        // 与 pl-model 当前 `pl.model.assistant` 帧版本一致（该常量不对外重导出）。
        5,
        serde_json::to_string(&Frame {
            receipt: &receipt,
            bindings: Vec::new(),
        })?,
    )?;
    let output = ModelStepOutput {
        turn_action: Default::default(),
        attempt_id: attempt_id.to_owned(),
        base_context_revision: 0,
        content: vec![ContextContent::Opaque { payload: frame }],
        tool_calls: Vec::new(),
        private_context: None,
        usage: Default::default(),
    };
    let tools: Arc<[pl_core::model::ModelToolDeclaration]> =
        Arc::from(Vec::<pl_core::model::ModelToolDeclaration>::new());
    let attempt = pl_core::thread::RequestAttempt::new(
        turn_id.to_owned(),
        attempt_id.to_owned(),
        0,
        pl_core::thread::AttemptStatus::Committed,
    );
    let update = pl_core::thread::journal::AttemptUpdate {
        request_metadata: None,
        usage_binding: None,
        tool_projection: None,
        turn_id: turn_id.to_owned(),
        attempt_id: attempt_id.to_owned(),
        retry_of: None,
        input_revision: 0,
        tools,
        outcome: pl_core::thread::AttemptOutcome::Committed(output),
        input_estimate: None,
    };
    Ok((attempt, update))
}

/// Hands one admitted fact to the production live projection and to the writer, exactly as the
/// Thread's observation worker does: admit, take the owed fact over, project it, hand the batch
/// back. The writer saves only what this owner handed over, so a `flush` afterwards is the same
/// durable barrier the product uses.
async fn drive_live_projection(
    projection: &mut crate::studio::thread_projection::LiveProjection,
    chat: &pl_core::chat::Session,
    sink: &ThreadStorageSink,
    thread_id: &str,
    write: ThreadWrite,
) -> Result<crate::studio::thread_projection::PreparedEffect> {
    sink.admit(thread_id, write)?;
    let write = sink
        .0
        .channel
        .next_unprojected()
        .context("the admitted fact is owed a projection")?;
    let (_, mut prepared) = projection
        .prepare(&sink.0.thread, &write.effect, &write.checkpoint.state, true)
        .await?;
    assert!(prepared.completion_drafts.is_some());
    assert!(!sink.0.channel.prepare(prepared.clone()));
    projection.publish_prepared(chat, &mut prepared).await?;
    assert!(prepared.completion_drafts.is_none());
    assert!(sink.0.channel.prepare(prepared.clone()));
    Ok((*prepared).clone())
}

/// A delayed Running acknowledgement must not retire provider observations published after
/// its batch was prepared. The writer step lock fixes the interleaving without timing sleeps.
#[tokio::test]
async fn running_save_ack_preserves_later_failed_and_current_observations() -> Result<()> {
    use pl_core::{
        chat::{PresentationPart, presentation_item_id},
        model::{
            ActiveModelProgress, ModelProgressSender, ModelTextChannel, ObservedItemKind,
            ObservedPart, ObservedPartIdentity, ObservedPartKind, ProviderPartIdentity,
        },
        thread::{AttemptOutcome, AttemptStatus},
    };

    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "running-save-ack";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let chat = store.chat_session(id).await?;
    let mut projection = live_projection(&sink).await?;
    let (mut attempt, mut update) = committed_parts_attempt("turn", "attempt", 0)?;
    attempt.status = AttemptStatus::Running;
    update.outcome = AttemptOutcome::Running;
    let mut write = ticket(id, 1);
    write.checkpoint.state.attempts = Arc::from([attempt]);
    Arc::make_mut(&mut write.effect).attempt = Some(update);
    let mut state = write.checkpoint.state.clone();

    let locked = sink.0.channel.step_lock.lock().await;
    drive_live_projection(&mut projection, &chat, &sink, id, write).await?;
    let sender = ModelProgressSender::detached(1024);
    let part = |text: &str| {
        ObservedPart::new(ObservedPartIdentity::Provider(ProviderPartIdentity {
            item_id: Arc::from("same-provider-id"),
            output_index: Some(0),
            item_kind: ObservedItemKind::Text(ModelTextChannel::Final),
            part: ObservedPartKind::OutputText,
            content_index: 0,
        }))
        .authorized(text)
    };
    sender.edit_parts(|parts| parts.push(part("failed body")));
    sender.begin_recovery(5, Arc::from("connection interrupted"))?;
    sender.edit_parts(|parts| parts.push(part("current body")));
    state.model_progress = Some(ActiveModelProgress {
        attempt_id: "attempt".into(),
        progress: sender.latest(),
    });
    projection.stream(&chat, &sink.0.thread, &state, 1).await?;
    let failed_id = presentation_item_id(
        "attempt",
        0,
        "same-provider-id",
        Some(PresentationPart::OutputText(0)),
    );
    let current_id = presentation_item_id(
        "attempt",
        1,
        "same-provider-id",
        Some(PresentationPart::OutputText(0)),
    );
    // The two observations are facts of this Runtime projection owner now: the completion
    // session never saw them, and their bodies stay the shared blocks `stream` stored.
    let failed_body = preview_body(&projection, &failed_id);
    let current_body = preview_body(&projection, &current_id);
    drop(locked);
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 1),
        sink.flush(id, 1),
        || channel_facts(&sink),
    )
    .await??;

    // No further provider update is needed to keep either identity live after the save ack:
    // the delayed Running write owns neither observation, so both previews remain this owner's
    // resident facts with their bodies unchanged.
    assert_eq!(
        preview_body(&projection, &failed_id),
        failed_body,
        "the delayed Running acknowledgement must not retire the failed observation"
    );
    assert_eq!(
        preview_body(&projection, &current_id),
        current_body,
        "the delayed Running acknowledgement must not retire the current observation"
    );
    assert!(
        store
            .history(id)
            .await?
            .existing_items([failed_id.clone(), current_id.clone()])
            .await?
            .is_empty(),
        "Running saved only its prepared start facts, not these later observations"
    );
    let mut stale = state.clone();
    stale.model_progress.as_mut().unwrap().attempt_id = "retired-before-current".into();
    projection.stream(&chat, &sink.0.thread, &stale, 1).await?;
    assert_eq!(
        preview_body(&projection, &current_id),
        current_body,
        "an unrelated retired source cannot erase the current source's preview"
    );
    Arc::make_mut(&mut state.attempts)[0].status = AttemptStatus::Cancelled;
    projection.stream(&chat, &sink.0.thread, &state, 1).await?;
    assert!(projection.preview_fields(&failed_id).is_none());
    assert!(projection.preview_fields(&current_id).is_none());
    projection.stream(&chat, &sink.0.thread, &state, 1).await?;
    assert!(
        projection.preview_fields(&current_id).is_none(),
        "a delayed frame from an ended attempt cannot recreate its preview"
    );
    Ok(())
}

/// The body text one preview currently holds, straight from the projection's shared blocks.
fn preview_body(projection: &crate::studio::thread_projection::LiveProjection, id: &str) -> String {
    let fields = projection
        .preview_fields(id)
        .expect("the observation stays a resident preview of this owner");
    fields
        .values()
        .map(|block| block.text())
        .collect::<Vec<_>>()
        .join("")
}

#[tokio::test]
async fn parent_message_keeps_identity_until_consumed_and_saved() -> Result<()> {
    use pl_core::thread::inbox::{InboxRecord, ThreadMessage};

    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let parent = test_thread("parent");
    register_test_thread(&store, &parent).await?;
    let id = "child-message";
    let mut thread = test_thread(id);
    thread.root_thread_id = parent.id.clone();
    thread.parent_thread_id = Some(parent.id.clone());
    register_test_thread(&store, &thread).await?;
    let sink = ThreadStorageSink::new(store.clone(), thread, None).await?;
    let chat = store.chat_session(id).await?;
    let mut projection = live_projection(&sink).await?;
    let record = InboxRecord {
        sequence: 1,
        message: ThreadMessage {
            kind: pl_core::context::AgentMessageKind::Report,
            id: "initial:spawn".into(),
            source_id: "agent:parent".into(),
            payload: OpaquePayload::text("implement the assigned task"),
            context: Vec::new(),
        },
    };
    let item_id = crate::studio::thread_projection::order::message_id(&record.message.id);
    let mut accepted = ticket(id, 1);
    accepted.checkpoint.state.inbox = Arc::from([record.clone()]);
    Arc::make_mut(&mut accepted.effect).inbox = Arc::from([record.clone()]);
    sink.admit(id, accepted.clone())?;
    let (_, mut accepted_batch) = projection
        .prepare(
            &sink.0.thread,
            &accepted.effect,
            &accepted.checkpoint.state,
            true,
        )
        .await?;
    projection
        .publish_prepared(&chat, &mut accepted_batch)
        .await?;
    assert!(sink.0.channel.prepare(accepted_batch.clone()));
    let original = accepted_batch
        .items
        .iter()
        .find(|item| item.id == item_id)
        .context("accepted parent message")?
        .clone();
    // Lost publication acknowledgement reuses the frozen handoff; it cannot fold the
    // same journal effect again or allocate a new identity/content version.
    let mut repeat = accepted_batch.clone();
    projection.publish_prepared(&chat, &mut repeat).await?;
    assert!(Arc::ptr_eq(&accepted_batch, &repeat));
    assert_eq!(
        repeat
            .items
            .iter()
            .find(|item| item.id == item_id)
            .context("the re-observation still projects the identity")?
            .revision,
        original.revision
    );

    let (attempt, update) = committed_parts_attempt("child-turn", "child-attempt", 1)?;
    let mut consumed = ticket(id, 2);
    consumed.checkpoint.state.consumed_messages = 1;
    consumed.checkpoint.state.inbox = Arc::from([record]);
    consumed.checkpoint.state.attempts = Arc::from([attempt]);
    Arc::make_mut(&mut consumed.effect).attempt = Some(update);
    Arc::make_mut(&mut consumed.effect).consumed_messages = Some(1);
    drive_live_projection(&mut projection, &chat, &sink, id, consumed).await?;
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 2),
        sink.flush(id, 2),
        || channel_facts(&sink),
    )
    .await??;
    let history = store.history(id).await?;
    let saved = history.existing_items([item_id.clone()]).await?;
    let item = saved.get(&item_id).context("saved parent message")?;
    assert_eq!(item.ordinal, original.ordinal);
    assert_eq!(item.turn_id, "child-turn");
    assert!(item.revision > original.revision);
    assert!(
        matches!(item.state(), pl_protocol::ThreadItemState::Text(text)
            if text.channel() == pl_protocol::ThreadTextChannel::ParentAgent
                && text.text() == "implement the assigned task")
    );
    assert_eq!(history.watermark().await?, 2);
    assert_eq!(sink.0.channel.subscribe().borrow().fault, None);

    // A saved but unconsumed follow-up has no Turn. Reinstall the projection from its
    // durable identity before consuming it, as activation does for an idle child.
    let mut followup = ticket(id, 3);
    followup.checkpoint.state.consumed_messages = 1;
    let mut record = accepted.checkpoint.state.inbox[0].clone();
    record.sequence = 2;
    record.message.id = "followup".into();
    followup.checkpoint.state.inbox = Arc::from([record.clone()]);
    Arc::make_mut(&mut followup.effect).inbox = Arc::from([record.clone()]);
    drive_live_projection(&mut projection, &chat, &sink, id, followup).await?;
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 3),
        sink.flush(id, 3),
        || channel_facts(&sink),
    )
    .await??;
    let followup_id = crate::studio::thread_projection::order::message_id(&record.message.id);
    let saved = history.existing_items([followup_id.clone()]).await?;
    let original = saved[&followup_id].clone();
    projection = live_projection(&sink).await?;
    projection.seed(saved.into_values().collect(), Default::default());
    let (attempt, update) = committed_parts_attempt("next-turn", "next-attempt", 1)?;
    let mut consumed = ticket(id, 4);
    consumed.checkpoint.state.consumed_messages = 2;
    consumed.checkpoint.state.inbox = Arc::from([record]);
    consumed.checkpoint.state.attempts = Arc::from([attempt]);
    Arc::make_mut(&mut consumed.effect).attempt = Some(update);
    Arc::make_mut(&mut consumed.effect).consumed_messages = Some(2);
    drive_live_projection(&mut projection, &chat, &sink, id, consumed).await?;
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 4),
        sink.flush(id, 4),
        || channel_facts(&sink),
    )
    .await??;
    let saved = history.existing_items([followup_id.clone()]).await?;
    assert_eq!(saved[&followup_id].ordinal, original.ordinal);
    assert_eq!(saved[&followup_id].turn_id, "next-turn");
    assert!(saved[&followup_id].revision > original.revision);
    assert_eq!(history.watermark().await?, 4);
    Ok(())
}

/// A live Turn survives a retained window smaller than the response it produced.
///
/// The live projection is a bounded observation owner: it releases a Turn's oldest facts by
/// ordinal once that Turn commits more identities than `LIVE_ITEM_WINDOW`. A Turn's own input is
/// the identity core keeps referencing from *every* later effect of that Turn — above all its
/// terminal one, whose checkpoint has already pruned the consumed body and carries only the
/// minimal `turns[].input_id` — while it is also the oldest fact the Turn ever created. Numbering
/// the window purely by ordinal therefore evicted exactly that identity, the terminal effect then
/// resolved the pruned input as a hole and the durable barrier failed closed with
/// `MissingDurableInput`: the multi-item stress fault. The window must bound only *optional*
/// retained history; the minimal identity a live Turn still references is not optional.
///
/// Keeping an identity without keeping its content version is not enough: the Turn's own item is
/// re-projected by the same later effects, so a window that released it made the re-projection
/// restart at revision 1, and the durable row rejected the new payload as a revision conflict.
/// Identity and version have to survive together.
///
/// This drives the production `advance` path over the same reliable handoff the observation
/// worker uses, with no GUI subscriber: the projection publishes into the shared session and
/// hands the batch to the writer exactly like the owner. The pressure is a real provider receipt
/// with more presentation parts than the window holds, not a fabricated per-Turn input queue.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn execution_index_delivery_admission_releases_registry_before_channel_accounting()
-> Result<()> {
    for cold in [false, true] {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let id = if cold {
            "cold-pin-lock-order"
        } else {
            "review-pin-lock-order"
        };
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let (entered, entering) = std::sync::mpsc::channel();
        *sink.0.channel.delivery_admission_entered.lock().unwrap() = Some(entered);
        tokio::task::block_in_place(|| -> Result<()> {
            // The writer already owns progress. Admission reaches accounting only after it
            // pinned the actual registry source; it must not still own the registry here.
            let progress = lock_progress(&sink.0);
            let admission = std::thread::spawn({
                let coordinator = store.thread_persistence().clone();
                let channel = sink.0.channel.clone();
                move || -> Result<Box<dyn std::any::Any + Send>> {
                    if cold {
                        Ok(Box::new(
                            coordinator.retain_terminal_material(id, &channel, 1024, None)?,
                        ))
                    } else {
                        Ok(Box::new(coordinator.retain_review_delivery(id, 1024)?))
                    }
                }
            });
            entering.recv_timeout(Duration::from_secs(5))?;
            assert_eq!(
                sink.0.channel.delivery_admissions.load(Ordering::Acquire),
                1
            );
            let (probed, probe) = std::sync::mpsc::channel();
            let registry = std::thread::spawn({
                let coordinator = store.thread_persistence().clone();
                move || {
                    let channel = coordinator.history_channel(id);
                    let _ = probed.send(channel);
                }
            });
            let registry_source = probe.recv_timeout(Duration::from_secs(5));
            if registry_source.is_ok() {
                // This is the real progress -> registry writer report, while delivery's
                // accounting is blocked on the progress lock above.
                report(&sink.0, &progress);
            }
            // Also release the blocked participants before reporting a regression failure.
            drop(progress);
            let retained = admission
                .join()
                .map_err(|_| anyhow::anyhow!("delivery admission panicked"))??;
            registry
                .join()
                .map_err(|_| anyhow::anyhow!("registry probe panicked"))?;
            let source = registry_source?;
            assert!(Arc::ptr_eq(&source, &sink.0.channel));
            assert_eq!(
                sink.0.channel.delivery_admissions.load(Ordering::Acquire),
                0
            );
            assert_eq!(sink.0.channel.retained_delivery_bytes(), 1024);
            drop(retained);
            assert_eq!(sink.0.channel.retained_delivery_bytes(), 0);
            Ok(())
        })?;
        sink.0.channel.stop_and_join().await?;
    }
    Ok(())
}

#[tokio::test]
async fn execution_index_unchanged_projection_reports_stay_quiet_but_retry_and_handoff_wake()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "projection-watch";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let channel = &sink.0.channel;
    let lease = channel.step_lock.lock().await;
    let mut status = channel.subscribe();
    let mut pressure = channel.pressure_changed.subscribe();
    let mut capacity = store.thread_persistence().subscribe_delivery_capacity();
    let steady = ProjectionRetention {
        resident_bytes: 256,
        pending: None,
    };
    channel.set_projection_retention(steady)?;
    assert!(status.has_changed()? && pressure.has_changed()?);
    status.borrow_and_update();
    pressure.borrow_and_update();
    capacity.borrow_and_update();
    for _ in 0..8 {
        channel.set_projection_retention(steady)?;
        assert!(!status.has_changed()?);
        assert!(!pressure.has_changed()?);
        assert!(!capacity.has_changed()?);
    }
    let full = ProjectionRetention {
        resident_bytes: MAX_HISTORY_THREAD_BYTES + 1,
        pending: None,
    };
    assert!(channel.set_projection_retention(full).is_err());
    status.borrow_and_update();
    pressure.borrow_and_update();
    for _ in 0..8 {
        assert!(channel.set_projection_retention(full).is_err());
        assert!(!status.has_changed()?);
        assert!(!pressure.has_changed()?);
    }
    channel.release_projection_retention();
    assert!(status.has_changed()? && pressure.has_changed()? && capacity.has_changed()?);
    status.borrow_and_update();
    pressure.borrow_and_update();
    let write = ticket(id, 1);
    sink.admit(id, write.clone())?;
    let mut projection = live_projection(&sink).await?;
    let mut prepared = projection
        .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
        .await?;
    projection
        .publish_prepared(&sink.0.chat, &mut prepared)
        .await?;
    assert!(prepared.items.is_empty() && prepared.completions.is_empty());
    // The real handoff also retains current metadata. Isolate the accounting charge without
    // changing the batch submitted below, so omitting accounting still fails this assertion.
    let mut accounting_only = prepared.as_ref().clone();
    accounting_only.current_state = None;
    assert_eq!(
        accounting_only.retained_bytes(),
        accounting_only.accounting.retained_bytes()
                + serde_json::to_vec(accounting_only.current.projection())?.len() as u64
                + std::mem::size_of::<std::sync::OnceLock<u64>>() as u64
                + 3 * std::mem::size_of::<usize>() as u64
                + serde_json::to_vec(accounting_only.current.source_changes.as_ref())?.len() as u64
                + accounting_only.current.operation_bytes()
                + serde_json::to_vec(accounting_only.current.atom_facts.as_ref())?.len() as u64
                + accounting_only.display.as_ref().context("frozen display handoff")?.retained_bytes
                // Publication consumed the effect-local member updates, but their empty
                // Arc collection remains part of PreparedEffect's retained shell.
                + serde_json::to_vec(&[] as &[pl_protocol::ChatAtom])?.len() as u64
                // Empty first-content evidence and observation plans are also retained.
                + 2 * b"[]".len() as u64,
        "content-empty handoffs still own their accounting and persisted current material"
    );
    assert!(
        prepared.retained_bytes() > accounting_only.retained_bytes(),
        "the original handoff also keeps its current metadata charged"
    );
    status.borrow_and_update();
    assert!(channel.prepare(prepared.clone()));
    assert!(
        status.has_changed()?,
        "a new content-empty handoff must wake the observer"
    );
    status.borrow_and_update();
    assert!(channel.prepare(prepared));
    assert!(
        !status.has_changed()?,
        "repeating the same handoff is not a new event"
    );
    channel.fail_projection(1, "controlled projection report failure".into());
    let generation = status.borrow_and_update().fault_generation;
    pressure.borrow_and_update();
    channel.fail_projection(1, "controlled projection report failure".into());
    assert!(!status.has_changed()? && !pressure.has_changed()?);
    channel.retry(generation)?;
    assert!(status.has_changed()? && pressure.has_changed()?);
    drop(lease);
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let snapshot = status.borrow_and_update().clone();
            if snapshot.committed_sequence == 1 && snapshot.error.is_none() {
                break Ok::<_, anyhow::Error>(());
            }
            status.changed().await?;
        }
    })
    .await??;
    channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn execution_index_multi_item_effect_rejection_keeps_projection_and_stamps_atomic()
-> Result<()> {
    assert_empty_multi_item_prepare_is_atomic(false).await
}

#[tokio::test]
async fn execution_index_empty_prepare_rejects_unfunded_stamp_without_reserving_shells()
-> Result<()> {
    assert_empty_multi_item_prepare_is_atomic(true).await
}

async fn assert_empty_multi_item_prepare_is_atomic(stamp_shortfall: bool) -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "batch-projection-budget";
    let attempt_id = "batch-attempt";
    let turn_id = "batch-turn";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let chat = store.chat_session(id).await?;
    let mut projection = live_projection(&sink).await?;
    let empty_projection_bytes = projection.retained_bytes();
    let (attempt, update) = committed_parts_attempt(turn_id, attempt_id, 2)?;
    let mut write = ticket(id, 1);
    write.checkpoint.state.attempts = Arc::from([attempt]);
    Arc::make_mut(&mut write.effect).attempt = Some(update);
    sink.admit(id, write)?;
    let owed = sink.0.channel.next_unprojected().unwrap();
    let candidates = crate::studio::thread_projection::project_effect_items(
        &sink.0.thread,
        &owed.checkpoint.state,
        &owed.effect,
        &Default::default(),
        &Default::default(),
        &Default::default(),
    )?
    .items;
    let ids = candidates
        .iter()
        .map(|item| item.id.clone())
        .collect::<Vec<_>>();
    assert_eq!(ids.len(), 3);
    let index = sink.0.channel.order_index();
    let probe = RuntimeOrderIndex::new(Arc::new(AtomicU64::new(0)), 0);
    // This separate, disposable index measures the established shell charge only. The
    // production index below remains empty until its one actual prepare call.
    probe.assign(&ids[0])?;
    let first_shell = probe.retained_bytes();
    for identity in &ids[1..] {
        probe.assign(identity)?;
    }
    let shells = probe.retained_bytes();
    let stamps = candidates
        .iter()
        .map(|item| item.turn_id.len() as u64)
        .sum::<u64>();
    assert!(stamps > 1);
    let available = if stamp_shortfall {
        shells + stamps - 1
    } else {
        first_shell
    };
    if stamp_shortfall {
        assert!(
            available >= shells,
            "every shell fits before testing the final stamp"
        );
        assert!(
            available < shells + stamps,
            "the complete stamp delta does not fit"
        );
    }
    let queued = sink.pressure(id).thread_bytes;
    sink.0
        .channel
        .set_projection_retention(ProjectionRetention {
            resident_bytes: MAX_HISTORY_THREAD_BYTES - queued - available,
            pending: None,
        })?;
    let process = sink.0.channel.process_bytes.load(Ordering::Acquire);
    let thread_bytes = sink.pressure(id).thread_bytes;
    let index_bytes = index.retained_bytes();
    let index_state = {
        let state = index.inner.lock().unwrap();
        (
            state.ceiling,
            state.durable,
            state.resident_blocked,
            state.assigned.len(),
        )
    };
    let projection_bytes = projection.retained_bytes();
    let completion_head = chat.head_seq();
    assert_eq!(index_bytes, 0);
    assert_eq!(index_state, (0, 0, false, 0));
    assert_eq!(
        projection_bytes, empty_projection_bytes,
        "read-only candidate lookup must not mutate the hydrated empty projection"
    );
    assert_eq!(completion_head, 0);
    let failure = projection
        .prepare(&sink.0.thread, &owed.effect, &owed.checkpoint.state, true)
        .await
        .err()
        .context("the empty-index prepare must reject the insufficient batch budget")?;
    assert!(failure.to_string().contains("budget"), "{failure}");
    assert_eq!(index.retained_bytes(), index_bytes);
    {
        let state = index.inner.lock().unwrap();
        assert_eq!(
            (
                state.ceiling,
                state.durable,
                state.resident_blocked,
                state.assigned.len()
            ),
            index_state
        );
    }
    assert_eq!(
        sink.0.channel.process_bytes.load(Ordering::Acquire),
        process
    );
    assert_eq!(sink.pressure(id).thread_bytes, thread_bytes);
    assert_eq!(projection.retained_bytes(), projection_bytes);
    assert!(projection.turn_result(turn_id).is_none());
    assert_eq!(chat.head_seq(), completion_head);
    assert!(Arc::ptr_eq(
        &sink.0.channel.next_unprojected().unwrap(),
        &owed
    ));

    // Restore headroom and retry the same owed write, without any separate identity
    // reservation. Nothing from the rejected prepare may consume an ordinal or revision.
    sink.0.channel.release_projection_retention();
    let (_, mut prepared) = projection
        .prepare(&sink.0.thread, &owed.effect, &owed.checkpoint.state, true)
        .await?;
    assert!(prepared.completion_drafts.is_some());
    assert!(prepared.completions.is_empty());
    assert_eq!(chat.head_seq(), 0);
    assert!(!sink.0.channel.prepare(prepared.clone()));
    projection.publish_prepared(&chat, &mut prepared).await?;
    assert_eq!(prepared.items.len(), 3);
    assert!(
        prepared
            .items
            .iter()
            .all(|item| item.revision == 1 && item.ordinal > 0)
    );
    let actual_ids = prepared
        .items
        .iter()
        .map(|item| item.id.clone())
        .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(actual_ids, ids.iter().cloned().collect());
    let ordinals = prepared
        .items
        .iter()
        .map(|item| item.ordinal)
        .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(ordinals, [1, 2, 3].into_iter().collect());
    assert_eq!(index.inner.lock().unwrap().ceiling, 3);
    // The third execution identity is inference accounting, not a conversation completion.
    assert_eq!(prepared.completions.len(), 2);
    assert!(prepared.completions.iter().all(|record| {
        prepared.items.iter().any(|item| {
            item.id == record.header.item_id
                && !matches!(item.state(), pl_protocol::ThreadItemState::Inference(_))
        })
    }));
    for (offset, completion) in prepared.completions.iter().enumerate() {
        assert_eq!(completion.header.append_seq, offset as u64 + 1);
    }
    let published = prepared.clone();
    projection.publish_prepared(&chat, &mut prepared).await?;
    assert!(Arc::ptr_eq(&published, &prepared));
    assert_eq!(
        chat.head_seq(),
        2,
        "publication retry cannot append duplicate identities"
    );
    assert!(sink.0.channel.prepare(prepared));
    sink.flush(id, 1).await?;
    assert_eq!(chat.head_seq(), 2);
    assert_eq!(
        store
            .history(id)
            .await?
            .items_for_turn(turn_id)
            .await?
            .len(),
        3
    );
    sink.0.channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn execution_index_channel_resident_commits_serialize_provider_allocation() -> Result<()> {
    // Admission, direct preparation, and transfer of an already charged pending batch.
    for mode in 0..3 {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let id = format!("resident-commit-{mode}");
        register_test_thread(&store, &test_thread(&id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(&id), None).await?;
        let chat = store.chat_session(&id).await?;
        let mut projection = live_projection(&sink).await?;
        let write = visible_input_ticket(&id, 1, "input")?;
        let lease = sink.0.channel.step_lock.lock().await;
        let prepared = if mode == 0 {
            let probe = RuntimeOrderIndex::new(Arc::new(AtomicU64::new(0)), 0);
            probe.reserve_boundaries(&write.effect, 0)?;
            let resident_bytes = MAX_HISTORY_THREAD_BYTES
                - encoded_bytes(&write.effect)
                - PENDING_AGE_METADATA_BYTES
                - probe.retained_bytes();
            sink.0
                .channel
                .set_projection_retention(ProjectionRetention {
                    resident_bytes,
                    pending: None,
                })?;
            None
        } else {
            sink.admit(&id, write.clone())?;
            let mut prepared = projection
                .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
                .await?;
            projection.publish_prepared(&chat, &mut prepared).await?;
            let bytes = prepared.retained_bytes();
            sink.0
                .channel
                .set_projection_retention(ProjectionRetention {
                    resident_bytes: MAX_HISTORY_THREAD_BYTES
                        - sink.pressure(&id).thread_bytes
                        - bytes,
                    pending: (mode == 2).then_some(PendingProjectionRetention {
                        sequence: 1,
                        prepared_bytes: bytes,
                    }),
                })?;
            Some(prepared)
        };
        let (entered, entered_rx) = tokio::sync::oneshot::channel();
        let (release, release_rx) = std::sync::mpsc::channel();
        *sink.0.channel.resident_gate.lock().unwrap() = Some(MaterializeGate {
            entered,
            release: release_rx,
        });
        let mutation = {
            let sink = sink.clone();
            let write = write.clone();
            let prepared = prepared.clone();
            let id = id.clone();
            tokio::task::spawn_blocking(move || -> Result<()> {
                if let Some(prepared) = prepared {
                    ensure!(
                        sink.0.channel.prepare(prepared),
                        "prepared handoff rejected"
                    );
                } else {
                    sink.admit(&id, write)?;
                }
                Ok(())
            })
        };
        tokio::time::timeout(
            crate::runtime_test_support::integration_test_deadline()?,
            entered_rx,
        )
        .await??;
        let (attempting, attempted) = tokio::sync::oneshot::channel();
        let provider = {
            let sink = sink.clone();
            let id = id.clone();
            tokio::task::spawn_blocking(move || {
                let _ = attempting.send(());
                sink.reserve_observed_item(&id, "provider-attempt", "provider-part")
            })
        };
        attempted.await?;
        assert!(
            sink.0.channel.order_index.inner.try_lock().is_err(),
            "the resident mutation must exclude identity allocation until its commit"
        );
        release.send(())?;
        mutation.await??;
        assert!(provider.await?.is_err());
        assert_eq!(sink.pressure(&id).thread_bytes, MAX_HISTORY_THREAD_BYTES);
        assert_eq!(sink.0.channel.order_index.assigned("provider-part"), None);
        {
            let progress = lock_progress(&sink.0);
            assert_eq!(progress.effects.len(), 1);
            assert_eq!(progress.projection_pending, None);
            assert_eq!(progress.effects[0].sequence, 1);
            if let Some(prepared) = &prepared {
                assert!(Arc::ptr_eq(
                    progress.effects[0].prepared.as_ref().unwrap(),
                    prepared
                ));
            } else {
                assert!(progress.effects[0].prepared.is_none());
            }
        }
        // Rejecting the optional provider reservation leaves the original fact fully owed.
        sink.0.channel.release_projection_retention();
        if prepared.is_none() {
            drive_live_projection(&mut projection, &chat, &sink, &id, write).await?;
        }
        drop(lease);
        let generation = sink.0.channel.subscribe().borrow().fault_generation;
        store
            .thread_persistence()
            .retry_history(&id, generation)
            .await?;
        sink.flush(&id, 1).await?;
        assert_eq!(store.history(&id).await?.watermark().await?, 1);
        sink.0.channel.stop_and_join().await?;
    }
    Ok(())
}

#[tokio::test]
async fn execution_index_terminal_transfer_rejection_retains_source_and_releases_capacity()
-> Result<()> {
    use pl_core::thread::inbox::ThreadMessage;
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "terminal-transfer-budget";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let chat = store.chat_session(id).await?;
    let mut projection = live_projection(&sink).await?;
    let write = visible_input_ticket(id, 1, "input")?;
    sink.admit(id, write.clone())?;
    let mut prepared = projection
        .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
        .await?;
    projection.publish_prepared(&chat, &mut prepared).await?;
    Arc::get_mut(&mut prepared).unwrap().parent_report = Some(Arc::new(ThreadMessage {
        kind: pl_core::context::AgentMessageKind::Report,
        id: "terminal-report".into(),
        source_id: "agent:worker".into(),
        payload: OpaquePayload::text("the original completed report"),
        context: Vec::new(),
    }));
    let source = PendingProjectionRetention {
        sequence: 1,
        prepared_bytes: prepared.retained_bytes(),
    };
    let report_bytes = prepared.parent_report_retained_bytes();
    let material_bytes = report_bytes + 1024;
    let resident =
        MAX_HISTORY_THREAD_BYTES - sink.pressure(id).thread_bytes - source.prepared_bytes;
    let mut before = ProjectionRetention {
        resident_bytes: resident,
        pending: Some(source),
    };
    sink.0.channel.set_projection_retention(before)?;
    let transfer = |before: ProjectionRetention| ProjectionTransfer {
        source,
        after: ProjectionRetention {
            resident_bytes: before.resident_bytes,
            pending: Some(PendingProjectionRetention {
                sequence: 1,
                prepared_bytes: source.prepared_bytes - report_bytes,
            }),
        },
    };
    let process_before = sink.0.channel.process_bytes.load(Ordering::Acquire);
    assert!(
        store
            .thread_persistence()
            .retain_terminal_material(id, &sink.0.channel, material_bytes, Some(transfer(before)))
            .is_err()
    );
    assert_eq!(sink.pressure(id).thread_bytes, MAX_HISTORY_THREAD_BYTES);
    assert_eq!(
        sink.0.channel.process_bytes.load(Ordering::Acquire),
        process_before
    );
    assert_eq!(sink.0.channel.retained_delivery_bytes(), 0);
    assert_eq!(lock_progress(&sink.0).projection_pending, Some(source));
    assert!(prepared.parent_report.is_some());
    assert!(
        sink.0
            .channel
            .order_index
            .reserve_observed("attempt", "blocked-part")
            .is_err()
    );
    assert_eq!(sink.0.channel.order_index.assigned("blocked-part"), None);

    before.resident_bytes -= material_bytes;
    sink.0.channel.set_projection_retention(before)?;
    sink.0
        .channel
        .process_bytes
        .store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
    assert!(
        store
            .thread_persistence()
            .retain_terminal_material(id, &sink.0.channel, material_bytes, Some(transfer(before)))
            .is_err()
    );
    assert_eq!(
        sink.0.channel.process_bytes.load(Ordering::Acquire),
        MAX_HISTORY_PROCESS_BYTES
    );
    assert_eq!(lock_progress(&sink.0).projection_pending, Some(source));
    assert_eq!(sink.0.channel.retained_delivery_bytes(), 0);
    sink.0
        .channel
        .process_bytes
        .store(process_before, Ordering::Release);
    let retained = store.thread_persistence().retain_terminal_material(
        id,
        &sink.0.channel,
        material_bytes,
        Some(transfer(before)),
    )?;
    Arc::get_mut(&mut prepared).unwrap().parent_report = None;
    assert_eq!(
        lock_progress(&sink.0).projection_pending,
        transfer(before).after.pending
    );
    assert_eq!(sink.0.channel.retained_delivery_bytes(), material_bytes);
    assert!(sink.pressure(id).thread_bytes <= MAX_HISTORY_THREAD_BYTES);
    // The real managed guard releases through the coordinator callback, not a report write.
    drop(retained);
    assert_eq!(sink.0.channel.retained_delivery_bytes(), 0);
    sink.0
        .channel
        .order_index
        .reserve_observed("attempt", "released-part")?;
    assert!(sink.0.channel.prepare(prepared));
    sink.0.channel.release_projection_retention();
    sink.flush(id, 1).await?;
    sink.0.channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn execution_index_cold_terminal_material_uses_new_admission_and_managed_release()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "cold-material-budget";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let channel = &sink.0.channel;
    let process_before = channel.process_bytes.load(Ordering::Acquire);
    channel.set_projection_retention(ProjectionRetention {
        resident_bytes: MAX_HISTORY_THREAD_BYTES - 512,
        pending: None,
    })?;
    assert!(
        store
            .thread_persistence()
            .retain_terminal_material(id, channel, 1024, None)
            .is_err()
    );
    assert_eq!(channel.retained_delivery_bytes(), 0);
    assert_eq!(
        channel.process_bytes.load(Ordering::Acquire),
        process_before
    );
    assert_eq!(
        sink.pressure(id).thread_bytes,
        MAX_HISTORY_THREAD_BYTES - 512
    );
    {
        let progress = lock_progress(&sink.0);
        assert_eq!(progress.projection_pending, None);
        assert!(progress.effects.is_empty());
    }
    channel.set_projection_retention(ProjectionRetention {
        resident_bytes: MAX_HISTORY_THREAD_BYTES - 1024,
        pending: None,
    })?;
    let material = store
        .thread_persistence()
        .retain_terminal_material(id, channel, 1024, None)?;
    assert_eq!(channel.retained_delivery_bytes(), 1024);
    assert_eq!(
        channel.process_bytes.load(Ordering::Acquire),
        process_before + 1024
    );
    assert_eq!(sink.pressure(id).thread_bytes, MAX_HISTORY_THREAD_BYTES);
    assert!(
        channel
            .order_index
            .reserve_observed("attempt", "part")
            .is_err()
    );
    assert_eq!(channel.order_index.assigned("part"), None);
    drop(material);
    assert_eq!(channel.retained_delivery_bytes(), 0);
    assert_eq!(
        channel.process_bytes.load(Ordering::Acquire),
        process_before
    );
    channel.order_index.reserve_observed("attempt", "part")?;
    channel.release_projection_retention();
    channel.stop_and_join().await?;
    Ok(())
}

#[test]
fn execution_index_admission_boundaries_reject_atomically_and_stay_charged() -> Result<()> {
    let process = Arc::new(AtomicU64::new(0));
    let index = RuntimeOrderIndex::new(process.clone(), 0);
    let mut write = visible_input_ticket("boundary-budget", 1, "input")?;
    Arc::make_mut(&mut write.effect).turn = Some(turn_record("turn", "input", TurnState::Running));
    assert!(
        index
            .reserve_boundaries(&write.effect, MAX_HISTORY_THREAD_BYTES - 1)
            .is_err()
    );
    assert_eq!(index.retained_bytes(), 0);
    assert_eq!(process.load(Ordering::Acquire), 0);
    assert!(index.inner.lock().unwrap().assigned.is_empty());
    assert_eq!(index.inner.lock().unwrap().ceiling, 0);
    process.store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
    assert!(index.reserve_boundaries(&write.effect, 0).is_err());
    assert_eq!(index.retained_bytes(), 0);
    assert_eq!(process.load(Ordering::Acquire), MAX_HISTORY_PROCESS_BYTES);
    assert!(index.inner.lock().unwrap().assigned.is_empty());
    assert_eq!(index.inner.lock().unwrap().ceiling, 0);
    process.store(0, Ordering::Release);
    index.reserve_boundaries(&write.effect, 0)?;
    let bytes = index.retained_bytes();
    assert!(bytes > 0);
    assert_eq!(process.load(Ordering::Acquire), bytes);
    // Processing an older checkpoint cannot retire an admitted but unprojected boundary.
    index.retain::<()>(&Default::default(), Vec::new());
    assert!(index.retained_bytes() > 0 && index.retained_bytes() < bytes);
    assert_eq!(index.inner.lock().unwrap().assigned.len(), 2);
    index.confirm_saved(1);
    assert_eq!(index.retained_bytes(), 0);
    assert_eq!(process.load(Ordering::Acquire), 0);
    assert_eq!(index.assign("next")?, 3);
    Ok(())
}

#[tokio::test]
async fn execution_index_running_turn_recovers_its_boundary_before_cold_admission() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "turn-cold-boundary";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let chat = store.chat_session(id).await?;
    let mut projection = live_projection(&sink).await?;
    let mut opening = visible_input_ticket(id, 1, "input")?;
    let running = turn_record("visible-turn", "input", TurnState::Running);
    opening.checkpoint.state.turns = Arc::from([running.clone()]);
    Arc::make_mut(&mut opening.effect).turn = Some(running.clone());
    let original = drive_live_projection(&mut projection, &chat, &sink, id, opening).await?;
    sink.flush(id, 1).await?;
    let turn_id = crate::studio::thread_projection::order::turn_id("visible-turn");
    let original_turn = original
        .items
        .iter()
        .find(|item| item.id == turn_id)
        .unwrap();
    let history = store.history(id).await?;
    let source_ids = [pl_protocol::ChatSourceId::ForegroundTurn {
        turn_id: "visible-turn".into(),
    }];
    let original_source = history
        .conversation_sources(&source_ids, 1)
        .await?
        .pop()
        .context("saved running source")?;
    assert_eq!(
        original_source.started,
        Some(pl_protocol::ChatFactPosition {
            effect_seq: 1,
            suborder: 0,
        })
    );
    assert!(original_source.ended.is_none());
    let checkpoint = history.checkpoint().await?.context("running checkpoint")?;
    sink.0.channel.stop_and_join().await?;
    drop(projection);
    drop(sink);
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), Some(&checkpoint)).await?;
    assert_eq!(
        sink.0.channel.order_index.assigned(&turn_id),
        Some(original_turn.ordinal)
    );
    let mut projection = live_projection(&sink).await?;
    let mut update = ticket(id, 2);
    projection.bind_conversation_identity(
        history
            .conversation_database_id()
            .await?
            .context("database")?,
    )?;
    projection
        .restore_current(&chat, &sink.0.thread, &checkpoint.state)
        .await?;
    update.checkpoint.state.turns = Arc::from([running.clone()]);
    Arc::make_mut(&mut update.effect).turn = Some(running);
    let prepared = drive_live_projection(&mut projection, &chat, &sink, id, update).await?;
    assert_eq!(prepared.items[0].ordinal, original_turn.ordinal);
    sink.flush(id, 2).await?;
    assert_eq!(
        history.item(&turn_id).await?.unwrap().ordinal,
        original_turn.ordinal
    );
    assert_eq!(
        history.conversation_sources(&source_ids, 2).await?,
        vec![original_source],
        "cold activation must retain the original source start, not start the Turn again"
    );
    sink.0.channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn execution_index_turn_start_precedes_provider_reservations_before_projection() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let id = "turn-start-order";
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let chat = store.chat_session(id).await?;
    let mut projection = live_projection(&sink).await?;
    let turn_id = "turn";
    let input_id = "input";
    let attempt_id = "attempt";
    let input = consumed_visible_input(input_id, turn_id, 1)?;
    let running = turn_record(turn_id, input_id, TurnState::Running);
    let mut opening = ticket(id, 1);
    opening.checkpoint.state.inputs = Arc::from([input.clone()]);
    opening.checkpoint.state.turns = Arc::from([running.clone()]);
    Arc::make_mut(&mut opening.effect).inputs = Arc::from([InputChange::Accepted(input)]);
    Arc::make_mut(&mut opening.effect).turn = Some(running.clone());
    // Core can already produce observations while the one projection owner still owes the
    // admitted Turn start. Its provider reservation must not precede that Turn's first item.
    sink.admit(id, opening.clone())?;
    let part_id = crate::studio::thread_projection::order::presentation_id(
        attempt_id,
        0,
        "stress-item-0",
        Some(crate::studio::thread_projection::order::PresentationPart::OutputText(0)),
    );
    sink.reserve_observed_item(id, attempt_id, &part_id)?;
    let opening_batch = drive_live_projection(&mut projection, &chat, &sink, id, opening).await?;
    sink.flush(id, 1).await?;
    let first = opening_batch
        .items
        .iter()
        .map(|item| item.ordinal)
        .min()
        .unwrap();
    let (attempt, update) = committed_parts_attempt(turn_id, attempt_id, 1)?;
    let mut step = ticket(id, 2);
    step.checkpoint.state.turns = Arc::from([running]);
    step.checkpoint.state.attempts = Arc::from([attempt]);
    Arc::make_mut(&mut step.effect).attempt = Some(update);
    let batch = drive_live_projection(&mut projection, &chat, &sink, id, step).await?;
    sink.flush(id, 2).await?;
    assert!(
        batch
            .items
            .iter()
            .find(|item| item.id == part_id)
            .unwrap()
            .ordinal
            > first
    );
    let finished = turn_record(
        turn_id,
        input_id,
        TurnState::Finished(TurnOutcome::Completed),
    );
    let mut terminal = ticket(id, 3);
    terminal.checkpoint.state.turns = Arc::from([finished.clone()]);
    Arc::make_mut(&mut terminal.effect).turn = Some(finished);
    drive_live_projection(&mut projection, &chat, &sink, id, terminal).await?;
    sink.flush(id, 3).await?;
    // The next checkpoint releases the finished source and its actual references. Real save
    // confirmation must allow the entire index to retire without losing the durable boundary.
    drive_live_projection(&mut projection, &chat, &sink, id, ticket(id, 4)).await?;
    sink.flush(id, 4).await?;
    assert_eq!(sink.0.channel.order_index.retained_bytes(), 0);
    let head = chat.head_seq();
    let mut late = ticket(id, 5);
    let mut input = consumed_visible_input(input_id, turn_id, 1)?;
    input.revision = 5;
    late.checkpoint.state.inputs = Arc::from([input.clone()]);
    Arc::make_mut(&mut late.effect).inputs = Arc::from([InputChange::Transition {
        id: input_id.into(),
        revision: input.revision,
        state: input.state,
    }]);
    let late_batch = drive_live_projection(&mut projection, &chat, &sink, id, late).await?;
    assert_eq!(late_batch.items[0].ordinal, first);
    assert!(late_batch.completions.is_empty());
    sink.flush(id, 5).await?;
    assert_eq!(chat.head_seq(), head);
    let history = store.history(id).await?;
    assert_eq!(history.items_for_turn(turn_id).await?[0].ordinal, first);
    let checkpoint = history.checkpoint().await?.context("saved late fact")?;
    drop(projection);
    // Run the actual Core close, whose Closing/Closed commits are additional reliable facts,
    // with the same channel/writer and one replacement projection owner.
    let observer = spawn_projection(store.clone(), test_thread(id));
    let core = ThreadHandle::resume_without_model(id.into(), Some(checkpoint))?;
    core.attach_storage(ColdStoreHandle::new(sink.clone()))
        .await?;
    tokio::time::timeout(Duration::from_secs(10), core.close()).await??;
    let closed = history.checkpoint().await?.context("saved Core close")?;
    assert_eq!(
        closed.state.lifecycle,
        pl_core::thread::ThreadLifecycle::Closed
    );
    assert!(closed.history_fence > 5);
    assert_eq!(history.watermark().await?, closed.history_fence);
    assert_eq!(history.items_for_turn(turn_id).await?[0].ordinal, first);
    assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
    sink.0.channel.stop_and_join().await?;
    tokio::time::timeout(Duration::from_secs(5), observer).await??;
    Ok(())
}

#[tokio::test]
async fn a_live_turn_input_survives_a_window_smaller_than_its_parts() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    register_test_thread(&store, &test_thread("window-input")).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread("window-input"), None).await?;
    let thread_id = "window-input";
    let turn_id = "long-turn";
    let attempt_id = "long-attempt";
    let input_id = "input-under-the-window";
    let chat = store.chat_session(thread_id).await?;
    let mut projection = live_projection(&sink).await?;

    // Commit 1: the Turn's own opening input. Every later commit's checkpoint has pruned the
    // consumed body from `state.inputs` and keeps only the minimal `turns[].input_id`.
    let input = consumed_visible_input(input_id, turn_id, 1)?;
    let mut opening = ticket(thread_id, 1);
    opening.checkpoint.state.inputs = Arc::from([input.clone()]);
    opening.checkpoint.state.turns =
        Arc::from([turn_record(turn_id, input_id, TurnState::Running)]);
    Arc::make_mut(&mut opening.effect).inputs = Arc::from([InputChange::Accepted(input)]);
    Arc::make_mut(&mut opening.effect).turn =
        Some(turn_record(turn_id, input_id, TurnState::Running));
    drive_live_projection(&mut projection, &chat, &sink, thread_id, opening).await?;

    // Commit 2: one model step whose receipt itemizes more provider parts than the window holds.
    // That pushes the Turn's own oldest facts out of the ordinal window.
    let parts = crate::studio::thread_projection::LIVE_ITEM_WINDOW + 8;
    let (attempt, update) = committed_parts_attempt(turn_id, attempt_id, parts)?;
    let mut step = ticket(thread_id, 2);
    step.checkpoint.state.turns = Arc::from([turn_record(turn_id, input_id, TurnState::Running)]);
    step.checkpoint.state.attempts = Arc::from([attempt.clone()]);
    Arc::make_mut(&mut step.effect).attempt = Some(update);
    drive_live_projection(&mut projection, &chat, &sink, thread_id, step).await?;

    // Commit 3: the Turn's terminal effect. Its checkpoint names the input without carrying its
    // body, and it re-projects the Turn item, so both the input identity and the Turn's content
    // version have to resolve from the projection's own memory.
    let finished = || {
        turn_record(
            turn_id,
            input_id,
            TurnState::Finished(TurnOutcome::Completed),
        )
    };
    let mut terminal = ticket(thread_id, 3);
    terminal.checkpoint.state.turns = Arc::from([finished()]);
    terminal.checkpoint.state.attempts = Arc::from([attempt]);
    Arc::make_mut(&mut terminal.effect).turn = Some(finished());
    drive_live_projection(&mut projection, &chat, &sink, thread_id, terminal).await?;

    // Every fact is handed over, so the durable barrier reaches the terminal commit with no
    // fault, and the rows a long Turn produced are complete instead of a hole or a revision
    // conflict.
    await_durable(
        Duration::from_secs(30),
        &format!("commit {}", 3),
        sink.flush(thread_id, 3),
        || channel_facts(&sink),
    )
    .await??;
    let history = store.history(thread_id).await?;
    assert_eq!(history.watermark().await?, 3);
    assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
    assert!(history.input_identity(input_id).await?.is_some());
    let turn_item_id = crate::studio::thread_projection::order::turn_id(turn_id);
    let last_part_id = crate::studio::thread_projection::order::presentation_id(
        attempt_id,
        0,
        &format!("stress-item-{}", parts - 1),
        Some(crate::studio::thread_projection::order::PresentationPart::OutputText(0)),
    );
    let mut rows = history
        .existing_items([
            input_id.to_owned(),
            turn_item_id.clone(),
            last_part_id.clone(),
        ])
        .await?;
    let input_row = rows
        .remove(input_id)
        .expect("the live Turn's consumed input stays a complete durable row");
    match input_row.state() {
        pl_protocol::ThreadItemState::Text(text) => assert_eq!(text.text(), "hello"),
        other => panic!("the input row keeps its visible body, got {other:?}"),
    }
    let turn_row = rows
        .remove(&turn_item_id)
        .expect("the Turn row is re-projected onto its own content version");
    match turn_row.state() {
        pl_protocol::ThreadItemState::Turn(turn) => {
            assert!(matches!(turn.state(), pl_protocol::TurnState::Completed(_)))
        }
        other => panic!("the Turn row keeps its Turn state, got {other:?}"),
    }
    let part_row = rows
        .remove(&last_part_id)
        .expect("the receipt's provider parts are durable rows");
    match part_row.state() {
        pl_protocol::ThreadItemState::Text(text) => {
            assert_eq!(text.text(), format!("chunk-{}", parts - 1).as_str())
        }
        other => panic!("the provider part keeps its text, got {other:?}"),
    }
    Ok(())
}

#[tokio::test]
async fn a_cold_owner_seeds_the_same_terminal_turn_the_live_projection_publishes() -> Result<()> {
    // A Thread re-activated after its last Turn finished has no live frame left for that fact:
    // the authoritative snapshot carries only the active Turn and `turnCompleted` is broadcast
    // once. The owner therefore seeds its retained last-Turn fact from durable history on the
    // install path. This drives that cold read over real committed rows and proves it agrees with
    // the live projection the frame would have used — same identity, same revision, same state —
    // while a Turn that is still running (or not yet durable) is never reported as finished.
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    register_test_thread(&store, &test_thread("cold-turn")).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread("cold-turn"), None).await?;
    let thread_id = "cold-turn";
    let turn_id = "terminal-turn";
    let input_id = "cold-input";
    let chat = store.chat_session(thread_id).await?;
    let mut projection = live_projection(&sink).await?;

    // A Thread whose history was never written reads as "no finished Turn" instead of creating a
    // database, so this cold read can never make the live path wait on the writer.
    assert!(
        store
            .history_for("project-test", "never-written")
            .await?
            .newest_terminal_turn()
            .await?
            .is_none()
    );

    // Commit 1: the Turn opens and is durable, but it is still running — the cold seed must not
    // mistake the newest Turn row for a finished one.
    let input = consumed_visible_input(input_id, turn_id, 1)?;
    let mut opening = ticket(thread_id, 1);
    opening.checkpoint.state.inputs = Arc::from([input.clone()]);
    opening.checkpoint.state.turns =
        Arc::from([turn_record(turn_id, input_id, TurnState::Running)]);
    Arc::make_mut(&mut opening.effect).inputs = Arc::from([InputChange::Accepted(input)]);
    Arc::make_mut(&mut opening.effect).turn =
        Some(turn_record(turn_id, input_id, TurnState::Running));
    drive_live_projection(&mut projection, &chat, &sink, thread_id, opening).await?;
    await_durable(
        Duration::from_secs(30),
        &format!("commit {}", 1),
        sink.flush(thread_id, 1),
        || channel_facts(&sink),
    )
    .await??;
    assert!(
        store
            .history(thread_id)
            .await?
            .newest_terminal_turn()
            .await?
            .is_none()
    );
    let history = store.history(thread_id).await?;
    let admitted = history.latest_turn_at(1).await?.context("admitted Turn")?;
    assert_eq!(admitted.id, turn_id);
    assert!(!admitted.state.is_terminal());
    assert!(history.latest_turn_at(0).await.is_err());
    assert!(history.latest_turn_at(2).await.is_err());

    // Intervening commits advance the execution clock without changing the Turn item.
    // A terminal frame must outrank running frames even when its item content version is small.
    for sequence in 2..=10 {
        let mut intermediate = ticket(thread_id, sequence);
        intermediate.checkpoint.state.turns =
            Arc::from([turn_record(turn_id, input_id, TurnState::Running)]);
        drive_live_projection(&mut projection, &chat, &sink, thread_id, intermediate).await?;
    }
    // Commit 11: the Turn finishes. The live projection of that same effect is the fact the frame
    // carried; the durable row the writer commits has to recover the identical Turn.
    let finished = || {
        turn_record(
            turn_id,
            input_id,
            TurnState::Finished(TurnOutcome::Completed),
        )
    };
    let mut terminal = ticket(thread_id, 11);
    terminal.checkpoint.state.turns = Arc::from([finished()]);
    Arc::make_mut(&mut terminal.effect).turn = Some(finished());
    let prepared =
        drive_live_projection(&mut projection, &chat, &sink, thread_id, terminal).await?;
    let live = crate::studio::thread_projection::prepared_terminal_turn(&prepared)
        .context("the live projection must carry the finished Turn")?;
    await_durable(
        Duration::from_secs(30),
        &format!("commit {}", 11),
        sink.flush(thread_id, 11),
        || channel_facts(&sink),
    )
    .await??;

    let cold = store
        .history(thread_id)
        .await?
        .newest_terminal_turn()
        .await?
        .context("the durable history must carry the finished Turn")?;
    assert_eq!(
        live.revision, 11,
        "terminal frame must use the execution clock"
    );
    assert_eq!(cold.id, live.id);
    assert_eq!(cold.revision, live.revision);
    assert_eq!(cold.state, live.state);
    let saved = history.checkpoint().await?.context("durable checkpoint")?;
    assert!(saved.state.turns.is_empty(), "terminal Turns must retire");
    assert_eq!(
        history.latest_turn_at(saved.history_fence).await?,
        Some(live.clone())
    );

    // A later running admission must outrank the saved terminal. Evaluation cannot use the
    // terminal-only seed as a shortcut, even while that older terminal remains readable.
    let next_id = "newer-running-turn";
    let next_input = consumed_visible_input("newer-input", next_id, 12)?;
    let mut next = ticket(thread_id, 12);
    next.checkpoint.state.inputs = Arc::from([next_input.clone()]);
    next.checkpoint.state.turns =
        Arc::from([turn_record(next_id, "newer-input", TurnState::Running)]);
    Arc::make_mut(&mut next.effect).inputs = Arc::from([InputChange::Accepted(next_input)]);
    Arc::make_mut(&mut next.effect).turn =
        Some(turn_record(next_id, "newer-input", TurnState::Running));
    drive_live_projection(&mut projection, &chat, &sink, thread_id, next).await?;
    await_durable(
        Duration::from_secs(30),
        &format!("commit {}", 12),
        sink.flush(thread_id, 12),
        || channel_facts(&sink),
    )
    .await??;
    let latest = history.latest_turn_at(12).await?.context("latest Turn")?;
    assert_eq!(latest.id, next_id);
    assert!(!latest.state.is_terminal());
    assert_eq!(history.newest_terminal_turn().await?, Some(cold));
    assert!(history.latest_turn_at(11).await.is_err());
    Ok(())
}

#[tokio::test]
async fn retained_budget_counts_the_bodies_the_live_projection_holds() {
    // A running Turn retains tool arguments, terminal results, attachment metadata and opaque
    // payloads. Charging only text and reasoning would leave the largest resident bodies outside
    // the Thread's reliable budget, so the estimate has to cover every category payload.
    let arguments = "a".repeat(4096);
    let result = "r".repeat(8192);
    let artifact = "z".repeat(2048);
    let raw_content = "p".repeat(1024);
    let failure = "f".repeat(256);
    let attachment = pl_protocol::ThreadAttachment {
        id: "artifact-attachment".to_owned(),
        modality: pl_protocol::AttachmentModality::File,
        media_type: "application/octet-stream".to_owned(),
        filename: Some("artifact.bin".to_owned()),
        width: None,
        height: None,
        byte_size: 64 * 1024 * 1024,
    };
    let tool = pl_protocol::ThreadItem::new(
        "tool-item".to_owned(),
        "retained-budget".to_owned(),
        "turn".to_owned(),
        1,
        1,
        1,
        1,
        pl_protocol::ThreadItemState::Tool(pl_protocol::ThreadToolItem::new(
            pl_protocol::ThreadToolInvocation::new(
                "call".to_owned(),
                "shell".to_owned(),
                arguments.clone(),
            ),
            pl_protocol::ThreadToolState::Succeeded(pl_protocol::SucceededThreadTool::new(
                1,
                pl_protocol::ThreadToolOutput::new(
                    result.clone(),
                    vec![attachment.clone()],
                    vec![serde_json::json!({"stdout": artifact.clone()})],
                    Some(0),
                ),
            )),
        )),
    );
    let raw = pl_protocol::ThreadItem::new(
        "raw-item".to_owned(),
        "retained-budget".to_owned(),
        "turn".to_owned(),
        2,
        1,
        1,
        1,
        pl_protocol::ThreadItemState::Raw(pl_protocol::ThreadRawItem::stored(
            vec![pl_protocol::ThreadRawPayload {
                format: "pl.model.receipt".to_owned(),
                version: 1,
                content: raw_content.clone(),
            }],
            String::new(),
            1,
        )),
    );
    let failed_text = pl_protocol::ThreadItem::new(
        "failed-text".to_owned(),
        "retained-budget".to_owned(),
        "turn".to_owned(),
        3,
        1,
        1,
        1,
        pl_protocol::ThreadItemState::Text(pl_protocol::ThreadTextItem::new(
            pl_protocol::ThreadTextChannel::Commentary,
            "visible".to_owned(),
            vec![attachment],
            pl_protocol::ThreadContentLifecycle::failed(1, failure.clone()),
        )),
    );
    let bytes = crate::studio::thread_projection::retained_bytes(&[tool, raw, failed_text]);
    let bodies =
        (arguments.len() + result.len() + artifact.len() + raw_content.len() + failure.len())
            as u64;
    assert!(
        bytes >= bodies,
        "retained budget {bytes} must cover the {bodies} resident body bytes"
    );
}

#[tokio::test]
async fn projection_gauge_is_part_of_the_thread_budget() -> Result<()> {
    let (_temp, _store, sink) = sink("projection-budget").await?;
    // The projection owner keeps a Turn's retained bodies and its report accumulator resident
    // after their batch became durable. The Thread's budget therefore reads the owner's absolute
    // gauge, and releasing the owner's tables releases the budget with them.
    sink.0
        .channel
        .set_projection_retention(ProjectionRetention {
            resident_bytes: 8192,
            pending: None,
        })?;
    assert_eq!(sink.pressure("projection-budget").thread_bytes, 8192);
    assert_eq!(sink.0.channel.subscribe().borrow().queued_bytes, 8192);
    sink.0
        .channel
        .set_projection_retention(ProjectionRetention::default())?;
    assert_eq!(sink.pressure("projection-budget").thread_bytes, 0);
    assert_eq!(sink.0.channel.subscribe().borrow().queued_bytes, 0);
    Ok(())
}

#[tokio::test]
async fn operation_output_reservation_returns_to_baseline_across_rounds() -> Result<()> {
    // Idle operations must not spend their hypothetical maximum output. More than sixteen
    // parallel tools with tiny output must run without exhausting the 256 MiB process budget.
    let (_temp, _store, sink) = sink("operation-budget").await?;
    let channel = &sink.0.channel;
    let baseline = channel.process_bytes.load(Ordering::Acquire);
    for index in 0..32 {
        assert_eq!(
            channel.reserve_operation_output(&format!("idle-{index}"), 16 * 1024 * 1024),
            Some(16 * 1024 * 1024)
        );
    }
    assert_eq!(channel.process_bytes.load(Ordering::Acquire), baseline);
    for index in 0..32 {
        channel.release_operation_output(&format!("idle-{index}"));
    }
    for round in 0..4_u64 {
        let operation = format!("task:call-{round}");
        let granted = channel
            .reserve_operation_output(&operation, 4096)
            .expect("the empty budget funds the reservation");
        assert_eq!(granted, 4096);
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            baseline,
            "a ceiling without produced bytes consumes no resident budget"
        );
        channel.charge_operation_output(&operation, 1024)?;
        channel.charge_operation_output(&operation, 1024)?;
        assert!(channel.charge_operation_output(&operation, 4097).is_err());
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            baseline + 1024
        );
        channel.release_operation_output(&operation);
        channel.release_operation_output(&operation);
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            baseline,
            "a finished call releases all accepted bytes"
        );
    }
    Ok(())
}

/// The whole reserve/complete/refuse/recover cycle of parallel in-flight operations.
///
/// Four Threads reserve the process budget down to its last byte, which is exactly the state
/// where charging an admitted fact *next to* the reservation that produced it would need space
/// that does not exist: every result would be refused, no result could be handed over, and the
/// reservations would be held forever waiting for the queue they themselves block. The rule under
/// test is the transfer instead — the bytes a reservation covers become the fact's own charge, so
/// a fully reserved process still hands its facts over — together with the boundaries that stay
/// real: an uncovered fact is refused with typed backpressure instead of being admitted over budget,
/// the refused fact is handed over unchanged once its Thread's ceiling comes back, and the
/// process gauge returns to the baseline once everything is durable.
#[tokio::test]
async fn parallel_reservations_transfer_into_their_facts_without_deadlock() -> Result<()> {
    // No test projection here: nothing takes the admitted facts over until the test hands them
    // in itself, so the durable watermark cannot drain the queue while the reservations are
    // still charged and every step below is deterministic.
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let operations = (0..4)
        .map(|index| format!("task:parallel-{index}"))
        .collect::<Vec<_>>();
    let mut sinks = Vec::new();
    // Each Thread first admits its input identity, then charges output up to its own limit.
    // This funds both the existing boundaries and the output instead of placing the entire
    // process allowance on one Thread or inventing uncharged identities at the full limit.
    for (index, operation) in operations.iter().enumerate() {
        let id = format!("output-transfer-{index}");
        register_test_thread(&store, &test_thread(&id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(&id), None).await?;
        sink.admit(
            &id,
            visible_input_ticket(&id, 1, &format!("input-{index}"))?,
        )?;
        let reservation = MAX_HISTORY_THREAD_BYTES - sink.pressure(&id).thread_bytes;
        let granted = sink
            .0
            .channel
            .reserve_operation_output(operation, reservation)
            .expect("the Thread can register its remaining allowance");
        assert_eq!(granted, reservation);
        sink.0
            .channel
            .charge_operation_output(operation, reservation)?;
        assert_eq!(sink.pressure(&id).thread_bytes, MAX_HISTORY_THREAD_BYTES);
        sinks.push(sink);
    }
    let sink = &sinks[0];
    let channel = &sink.0.channel;
    let process_bytes = channel.process_bytes.clone();
    let baseline = 0;
    assert_eq!(
        channel.process_bytes.load(Ordering::Acquire),
        MAX_HISTORY_PROCESS_BYTES,
        "the reservations alone fill the process budget"
    );
    assert!(
        channel
            .reserve_operation_output("task:one-too-many", MAX_HISTORY_THREAD_BYTES)
            .is_none(),
        "a call that the reliable budget cannot fund is backpressure, never a silent grant"
    );

    // Every call returns: its result is admitted while the process budget is still full, which
    // only works because the reservation it was made under is transferred onto the fact.
    for (index, operation) in operations.iter().enumerate() {
        let sink = &sinks[index];
        let mut write = visible_input_ticket(&sink.0.thread.id, 2, &format!("input-{index}"))?;
        let input = Arc::make_mut(&mut write.checkpoint.state.inputs)
            .first_mut()
            .unwrap();
        input.accepted_sequence = 1;
        input.ordinal = 1;
        Arc::make_mut(&mut write.effect).inputs = Arc::from([InputChange::Transition {
            id: input.input.id.clone(),
            revision: input.revision,
            state: input.state.clone(),
        }]);
        write.output_claim = Some(operation.clone());
        sink.admit(&sink.0.thread.id, write)
            .expect("the reservation funds the fact it was made for");
    }
    assert_eq!(
        channel.process_bytes.load(Ordering::Acquire),
        MAX_HISTORY_PROCESS_BYTES,
        "transferring a reservation onto a fact adds no second charge for the same output"
    );

    // The next continuous fact has no reservation and is refused while there is no headroom and
    // no projection can free any: typed backpressure, nothing dropped, ticket untouched.
    let uncovered = visible_input_ticket(&sink.0.thread.id, 3, "input-uncovered")?;
    let error = sink
        .admit(&sink.0.thread.id, uncovered.clone())
        .expect_err("an unfunded fact cannot be admitted into a full budget");
    assert!(
        error
            .source
            .is::<pl_core::thread::cold::StorageAdmissionBackpressure>()
    );
    let refused = channel.subscribe().borrow().clone();
    assert!(refused.fault.is_none() && refused.error.is_none());
    // Overlapping owners must not invent a fault from the same shared capacity refusal.
    let overlapping = ThreadStorageSink::new(store.clone(), sink.0.thread.clone(), None).await?;

    // Recovery: the first call ends, so its remaining ceiling comes back and the very same
    // ticket is admitted unchanged; the rest of the calls end too.
    channel.release_operation_output(&operations[0]);
    sink.admit(&sink.0.thread.id, uncovered)?;
    for (sink, operation) in sinks.iter().zip(&operations).skip(1) {
        sink.0.channel.release_operation_output(operation);
    }

    // The Thread's own projection owner hands the admitted facts over in admission order, which
    // is what lets the writer save them; every fact becomes durable without a fault retry.
    for (index, sink) in sinks.iter().enumerate() {
        let mut projection = live_projection(sink).await?;
        while let Some(write) = sink.0.channel.next_unprojected() {
            let mut prepared = projection
                .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
                .await?;
            projection
                .publish_prepared(&sink.0.chat, &mut prepared)
                .await?;
            assert!(sink.0.channel.prepare(prepared));
        }
        // A real subsequent checkpoint releases the last input reference. Its pending
        // identity charge still survives until the writer confirms the actual transaction.
        let target = if index == 0 { 4 } else { 3 };
        drive_live_projection(
            &mut projection,
            &sink.0.chat,
            sink,
            &sink.0.thread.id,
            ticket(&sink.0.thread.id, target),
        )
        .await?;
    }
    // The original writer drains every fact without an explicit fault-recovery request.
    let mut drained = channel.subscribe();
    await_durable(
        Duration::from_secs(10),
        "parallel reservations durable after backpressure",
        async {
            loop {
                let status = drained.borrow_and_update().clone();
                if status.committed_sequence == 4 && status.queued_records == 0 {
                    break;
                }
                drained.changed().await?;
            }
            Ok::<(), anyhow::Error>(())
        },
        || channel_facts(sink),
    )
    .await??;
    assert!(lock_progress(&sink.0).fault.is_none());
    assert_eq!(lock_progress(&sink.0).fault_generation, 0);
    assert!(
        store.thread_persistence().snapshot().error.is_none(),
        "all live writer reports stay healthy after ordinary backpressure"
    );
    for (index, sink) in sinks.iter().enumerate() {
        let target = if index == 0 { 4 } else { 3 };
        sink.flush(&sink.0.thread.id, target).await?;
        assert_eq!(
            store.history(&sink.0.thread.id).await?.watermark().await?,
            target
        );
        let drained = sink.0.channel.subscribe().borrow().clone();
        assert!(drained.error.is_none() && drained.fault.is_none());
        sink.0.channel.stop_and_join().await?;
    }
    assert_eq!(
        process_bytes.load(Ordering::Acquire),
        baseline,
        "once every fact is durable and every call ended, the process gauge is back to baseline"
    );
    drop(overlapping);
    Ok(())
}

#[derive(Clone, Default)]
struct AdmissionRefusals(Arc<Mutex<Vec<BTreeMap<String, String>>>>);

#[derive(Default)]
struct AdmissionFields(BTreeMap<String, String>);

impl tracing::field::Visit for AdmissionFields {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        self.0.insert(field.name().to_owned(), format!("{value:?}"));
    }
}

impl tracing::Subscriber for AdmissionRefusals {
    fn enabled(&self, metadata: &tracing::Metadata<'_>) -> bool {
        metadata.target() == "conversation_work"
    }
    fn new_span(&self, _: &tracing::span::Attributes<'_>) -> tracing::span::Id {
        tracing::span::Id::from_u64(1)
    }
    fn record(&self, _: &tracing::span::Id, _: &tracing::span::Record<'_>) {}
    fn record_follows_from(&self, _: &tracing::span::Id, _: &tracing::span::Id) {}
    fn event(&self, event: &tracing::Event<'_>) {
        let mut fields = AdmissionFields::default();
        event.record(&mut fields);
        if fields.0.contains_key("rejection_kind") {
            self.0.lock().unwrap().push(fields.0);
        }
    }
    fn enter(&self, _: &tracing::span::Id) {}
    fn exit(&self, _: &tracing::span::Id) {}
}

impl AdmissionRefusals {
    fn matching_events(&self, kind: &str, thread: &str, sequence: u64) -> BTreeMap<String, String> {
        let events = self.0.lock().unwrap();
        let event = events.first().expect("refusal diagnostic").clone();
        assert!(events.iter().all(|next| next == &event));
        assert_eq!(event["operation"], "\"history_admission\"");
        assert_eq!(event["rejection_kind"], format!("{kind:?}"));
        assert_eq!(event["thread_id"], format!("{thread:?}"));
        assert_eq!(event["write_seq"], sequence.to_string());
        assert!(!format!("{event:?}").contains("SYNTHETIC-PRIVATE-CHECKPOINT"));
        eprintln!("HISTORY_ADMISSION_REFUSAL {event:?}");
        event
    }
}

#[tokio::test]
async fn queue_pressure_keeps_the_original_ticket_until_retry_and_commit() -> Result<()> {
    for kind in ["thread_bytes", "process_budget"] {
        let id = format!("queue-pressure-{kind}");
        let (_temp, store, sink) = sink(&id).await?;
        let channel = &sink.0.channel;
        for sequence in 1..=2 {
            let writer = channel.step_lock.lock().await;
            let mut write = ticket(&id, sequence);
            write.checkpoint.state.persistence.error =
                Some("SYNTHETIC-PRIVATE-CHECKPOINT".to_owned());
            let baseline = channel.process_bytes.load(Ordering::Acquire);
            let index_baseline = channel.order_index.retained_bytes();
            // Supply only occupied-budget environment, never replace the production classifier.
            // Both limits are full in the Thread case to pin the original short-circuit priority.
            if kind == "thread_bytes" {
                channel
                    .order_index
                    .bytes
                    .store(MAX_HISTORY_THREAD_BYTES, Ordering::Release);
            }
            channel
                .process_bytes
                .store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
            let capture = AdmissionRefusals::default();
            tracing::subscriber::with_default(capture.clone(), || {
                for _ in 0..3 {
                    let error = sink.admit(&id, write.clone()).unwrap_err();
                    assert!(
                        error
                            .source
                            .is::<pl_core::thread::cold::StorageAdmissionBackpressure>()
                    );
                    assert_eq!(channel.subscribe().borrow().fault_generation, 0);
                }
            });
            assert_eq!(capture.0.lock().unwrap().len(), 3);
            let event = capture.matching_events(kind, &id, sequence);
            assert_eq!(event["fault_generation"], "0");
            assert_eq!(event["queued_effects"], "0");
            assert_eq!(
                event["queued_thread_bytes"],
                if kind == "thread_bytes" {
                    MAX_HISTORY_THREAD_BYTES
                } else {
                    index_baseline
                }
                .to_string()
            );
            assert_eq!(
                event["process_bytes_observed"],
                MAX_HISTORY_PROCESS_BYTES.to_string()
            );
            let increment = encoded_bytes(&write.effect) + PENDING_AGE_METADATA_BYTES;
            assert_eq!(event["thread_bytes_increment"], increment.to_string());
            assert_eq!(event["process_bytes_increment"], increment.to_string());
            assert_eq!(
                channel.process_bytes.load(Ordering::Acquire),
                MAX_HISTORY_PROCESS_BYTES
            );
            let fault = channel.subscribe().borrow().clone();
            assert!(fault.fault.is_none() && fault.error.is_none());
            assert_eq!(fault.admitted_sequence, sequence - 1);
            assert_eq!(fault.queued_records, 0);
            channel
                .order_index
                .bytes
                .store(index_baseline, Ordering::Release);
            channel.process_bytes.store(baseline, Ordering::Release);
            sink.admit(&id, write)?;
            let flush = sink.flush(&id, sequence);
            tokio::pin!(flush);
            assert!(futures::poll!(&mut flush).is_pending());
            drop(writer);
            tokio::time::timeout(Duration::from_secs(5), flush).await??;
            assert_eq!(store.history(&id).await?.watermark().await?, sequence);
            let recovered = channel.subscribe().borrow().clone();
            assert_eq!(recovered.queued_records, 0);
            assert_eq!(recovered.fault, None);
            assert_eq!(channel.process_bytes.load(Ordering::Acquire), baseline);
        }
        channel.stop_and_join().await?;
    }
    Ok(())
}

#[tokio::test]
async fn admission_requires_the_continuous_tail_but_keeps_replay_semantics() -> Result<()> {
    let id = "continuous-admission";
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let channel = &sink.0.channel;
    let writer = channel.step_lock.lock().await;
    let first = ticket(id, 1);
    sink.admit(id, first.clone())?;
    sink.admit(id, first.clone())?;
    assert_eq!(channel.subscribe().borrow().queued_records, 1);

    let third = ticket(id, 3);
    sink.admit(id, third.clone())
        .expect_err("a new record cannot cross an unsaved sequence gap");
    let fault = channel.subscribe().borrow().clone();
    assert_eq!(
        fault.fault,
        Some(pl_protocol::studio::HistoryFault::WriteFailed)
    );
    assert_eq!(fault.queued_records, 1);

    sink.admit(id, ticket(id, 2))?;
    sink.admit(id, third)?;
    let mut projection = live_projection(&sink).await?;
    while let Some(write) = channel.next_unprojected() {
        let mut prepared = projection
            .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        projection
            .publish_prepared(&sink.0.chat, &mut prepared)
            .await?;
        assert!(channel.prepare(prepared));
    }
    drop(writer);
    store
        .thread_persistence()
        .retry_history(id, fault.fault_generation)
        .await?;
    sink.flush(id, 3).await?;
    assert_eq!(store.history(id).await?.watermark().await?, 3);
    sink.admit(id, first)?;
    assert_eq!(channel.subscribe().borrow().queued_records, 0);
    channel.stop_and_join().await
}

#[tokio::test]
async fn record_capacity_refuses_only_the_next_continuous_ticket_and_drains() -> Result<()> {
    let id = "record-capacity";
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    register_test_thread(&store, &test_thread(id)).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let channel = &sink.0.channel;
    let writer = channel.step_lock.lock().await;
    let mut projection = live_projection(&sink).await?;
    for sequence in 1..=MAX_HISTORY_BATCHES as u64 {
        let write = ticket(id, sequence);
        sink.admit(id, write.clone())?;
        let mut prepared = projection
            .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        projection
            .publish_prepared(&sink.0.chat, &mut prepared)
            .await?;
        assert!(channel.prepare(prepared));
    }
    let refused = ticket(id, MAX_HISTORY_BATCHES as u64 + 1);
    let before = sink.pressure(id);
    let queued_before = {
        let progress = lock_progress(&sink.0);
        progress.effect_bytes + progress.queue_metadata_bytes + channel.order_index.retained_bytes()
    };
    let capture = AdmissionRefusals::default();
    tracing::subscriber::with_default(capture.clone(), || {
        for _ in 0..3 {
            let error = sink
                .admit(id, refused.clone())
                .expect_err("the first ticket beyond the real record limit must be refused");
            assert!(
                error
                    .source
                    .is::<pl_core::thread::cold::StorageAdmissionBackpressure>()
            );
            assert_eq!(channel.subscribe().borrow().fault_generation, 0);
        }
    });
    assert_eq!(capture.0.lock().unwrap().len(), 3);
    let event = capture.matching_events("slot", id, refused.effect.sequence);
    assert_eq!(event["queued_effects"], MAX_HISTORY_BATCHES.to_string());
    assert_eq!(event["queued_thread_bytes"], queued_before.to_string());
    assert_eq!(
        event["process_bytes_observed"],
        before.store_bytes.to_string()
    );
    let increment = encoded_bytes(&refused.effect) + PENDING_AGE_METADATA_BYTES;
    assert_eq!(event["thread_bytes_increment"], increment.to_string());
    assert_eq!(event["process_bytes_increment"], increment.to_string());
    assert_eq!(sink.pressure(id).thread_bytes, before.thread_bytes);
    assert_eq!(sink.pressure(id).store_bytes, before.store_bytes);
    let full = channel.subscribe().borrow().clone();
    assert!(full.fault.is_none() && full.error.is_none());
    assert_eq!(full.queued_records, MAX_HISTORY_BATCHES as u64);
    assert!(
        channel.next_unprojected().is_none(),
        "capacity refusal must not append or duplicate the original ticket"
    );
    drop(writer);

    let mut capacity = channel.subscribe();
    tokio::time::timeout(Duration::from_secs(10), async {
        while capacity.borrow_and_update().queued_records >= MAX_HISTORY_BATCHES as u64 {
            capacity.changed().await?;
        }
        Ok::<_, tokio::sync::watch::error::RecvError>(())
    })
    .await??;
    sink.admit(id, refused.clone())?;
    let write = channel
        .next_unprojected()
        .context("the exact refused ticket becomes the next continuous handoff")?;
    assert_eq!(write.effect.sequence, refused.effect.sequence);
    let mut prepared = projection
        .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
        .await?;
    projection
        .publish_prepared(&sink.0.chat, &mut prepared)
        .await?;
    assert!(channel.prepare(prepared));
    sink.flush(id, refused.effect.sequence).await?;
    assert_eq!(
        store.history(id).await?.watermark().await?,
        refused.effect.sequence
    );
    assert_eq!(channel.subscribe().borrow().queued_records, 0);
    channel.stop_and_join().await
}

#[test]
fn pending_age_index_tracks_the_oldest_timestamp_without_sequence_order() {
    let mut progress = Progress::default();
    progress.admit_saved_at(80);
    progress.admit_saved_at(10);
    progress.admit_saved_at(50);
    assert_eq!(progress.pending_saved_at.first_key_value(), Some((&10, &1)));
    assert_eq!(
        progress.queue_metadata_bytes,
        3 * PENDING_AGE_METADATA_BYTES
    );
    progress.release_saved_at(10);
    assert_eq!(progress.pending_saved_at.first_key_value(), Some((&50, &1)));
    progress.release_saved_at(80);
    progress.release_saved_at(50);
    assert!(progress.pending_saved_at.is_empty());
    assert_eq!(progress.queue_metadata_bytes, 0);
}

#[tokio::test]
async fn sqlite_rejection_retains_the_real_writer_queue_until_recovery() -> Result<()> {
    let (_temp, store, sink) = sink("sqlite-rejection").await?;
    sink.admit("sqlite-rejection", ticket("sqlite-rejection", 1))?;
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 1),
        sink.flush("sqlite-rejection", 1),
        || channel_facts(&sink),
    )
    .await??;
    let path = store
        .session_paths("project-test", "sqlite-rejection")?
        .root()
        .join("history.sqlite");
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?;
    db.execute_unprepared(
        "CREATE TRIGGER reject_history BEFORE UPDATE OF applied_write_seq ON history_meta \
             BEGIN SELECT RAISE(ABORT, 'controlled writer rejection'); END",
    )
    .await?;
    let mut status = sink.0.channel.subscribe();
    sink.admit("sqlite-rejection", ticket("sqlite-rejection", 2))?;
    tokio::time::timeout(Duration::from_secs(5), async {
        while status.borrow_and_update().fault.is_none() {
            status.changed().await?;
        }
        Ok::<_, tokio::sync::watch::error::RecvError>(())
    })
    .await??;
    let failed = status.borrow().clone();
    assert_eq!(
        failed.fault,
        Some(pl_protocol::studio::HistoryFault::WriteFailed)
    );
    assert_eq!(failed.queued_records, 1);
    assert_eq!(
        store.history("sqlite-rejection").await?.watermark().await?,
        1
    );
    assert!(sink.flush("sqlite-rejection", 2).await.is_err());
    db.execute_unprepared("DROP TRIGGER reject_history").await?;
    tokio::time::timeout(
        Duration::from_secs(5),
        store
            .thread_persistence()
            .retry_history("sqlite-rejection", failed.fault_generation),
    )
    .await??;
    assert_eq!(
        store.history("sqlite-rejection").await?.watermark().await?,
        2
    );
    let recovered = sink.0.channel.subscribe().borrow().clone();
    assert_eq!(recovered.queued_records, 0);
    assert_eq!(recovered.fault, None);
    Ok(())
}

#[tokio::test]
async fn execution_index_durable_background_ack_replayed_with_other_drafts_after_reclamation()
-> Result<()> {
    use pl_core::{
        context::{ContextRecord, ContextSnapshot, ContextSource},
        thread::{
            journal::ContextChange,
            task::{TaskAcknowledgement, TaskRecord},
        },
    };
    for cold_projection in [false, true] {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let id = if cold_projection {
            "ack-cold-replay"
        } else {
            "ack-reclaimed-replay"
        };
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let chat = store.chat_session(id).await?;
        let history = store.history(id).await?;
        let index = sink.0.channel.order_index();
        let mut projection = live_projection(&sink).await?;
        let call_id = "background-call";
        let tool_id = "background-tool";
        let turn_id = "background-turn";
        let receipt_id = "task-receipt";
        let task = TaskRecord {
            id: format!("task:{call_id}"),
            call_id: call_id.into(),
            tool_id: tool_id.into(),
            turn_id: turn_id.into(),
            revision: 2,
            status: TaskStatus::Running,
            cancel_requested: false,
            started_sequence: Some(1),
            acknowledgement: Some(TaskAcknowledgement {
                record_id: receipt_id.into(),
                context_revision: 1,
            }),
        };
        let context = ContextSnapshot {
            revision: 1,
            records: Arc::from([
                ContextRecord {
                    id: "assistant-call".into(),
                    turn_id: Some(turn_id.into()),
                    source: ContextSource::Assistant,
                    content: vec![],
                    tool_calls: vec![ModelToolCall {
                        rejection: None,
                        presentation_contract: None,
                        call_id: call_id.into(),
                        tool_id: tool_id.into(),
                        arguments: OpaquePayload::text("background arguments"),
                    }],
                },
                ContextRecord {
                    id: receipt_id.into(),
                    turn_id: Some(turn_id.into()),
                    source: ContextSource::ToolResult {
                        call_id: call_id.into(),
                        tool_id: tool_id.into(),
                    },
                    content: vec![ContextContent::Text {
                        text: Arc::from(format!(
                            "Task {} is running. Its result will be delivered when execution finishes.",
                            task.id
                        )),
                    }],
                    tool_calls: vec![],
                },
            ]),
        };
        assert!(context.pending_calls()?.is_empty());
        let mut initial = ticket(id, 1);
        initial.checkpoint.state.context = context.clone();
        initial.checkpoint.state.tasks = BTreeMap::from([(task.id.clone(), task.clone())]);
        Arc::make_mut(&mut initial.effect).context = Some(ContextChange::Replace(context.clone()));
        Arc::make_mut(&mut initial.effect).tasks = Arc::from([task.clone()]);
        let first =
            drive_live_projection(&mut projection, &chat, &sink, id, initial.clone()).await?;
        sink.flush(id, 1).await?;
        let ack_id = crate::studio::thread_projection::order::tool_background_started_id(call_id);
        let tool_item_id = crate::studio::thread_projection::order::tool_id(call_id);
        let original_ack = pl_core::chat::ChatHistory::item(&history, &ack_id)
            .await?
            .context("the matching context fact must really save its background ACK")?;
        assert_eq!(first.completions.len(), 1);
        assert_eq!(original_ack.header.append_seq, 1);
        assert_eq!(chat.durable_seq(), 1);
        let payload: serde_json::Value = serde_json::from_slice(&original_ack.payload)?;
        assert_eq!(payload["type"], "tool");
        assert_eq!(payload["data"]["state"]["kind"], "backgroundStarted");
        assert_eq!(
            index.assigned(&ack_id),
            None,
            "the real writer confirmation must retire the ACK index entry"
        );
        assert!(!index.is_sealed(&ack_id));
        let original_tool = history
            .item(&tool_item_id)
            .await?
            .context("saved running tool")?;
        if cold_projection {
            drop(projection);
            sink.0.channel.release_projection_retention();
            projection = live_projection(&sink).await?;
            assert_eq!(
                projection.retained_bytes(),
                crate::studio::thread_projection::LiveProjection::new().retained_bytes()
            );
        }
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: projection.retained_bytes(),
                pending: None,
            })?;
        let ceiling = index.inner.lock().unwrap().ceiling;
        let before_head = chat.head_seq();
        let mut replay = visible_input_ticket(id, 2, "after-ack-a")?;
        let mut inputs = vec![
            replay.checkpoint.state.inputs[0].clone(),
            visible_input_ticket(id, 2, "after-ack-b")?
                .checkpoint
                .state
                .inputs[0]
                .clone(),
        ];
        for (offset, input) in inputs.iter_mut().enumerate() {
            input.state = InputState::Pending;
            input.ordinal += offset as u64;
        }
        replay.checkpoint.state.inputs = inputs.clone().into();
        replay.checkpoint.state.context = context.clone();
        replay.checkpoint.state.tasks = initial.checkpoint.state.tasks.clone();
        let effect = Arc::make_mut(&mut replay.effect);
        effect.inputs = inputs
            .into_iter()
            .map(InputChange::Accepted)
            .collect::<Vec<_>>()
            .into();
        effect.tasks = Arc::from([task.clone()]);
        effect.context = Some(ContextChange::Replace(context.clone()));
        // This is the same acknowledged task and its exact ToolResult context, together
        // with two new completed inputs. No marker or ACK shell is manually installed.
        assert_eq!(
            effect.tasks[0].acknowledgement,
            initial.effect.tasks[0].acknowledgement
        );
        assert!(matches!(&effect.context,
                Some(ContextChange::Replace(replayed)) if replayed == &context));
        let lease = sink.0.channel.step_lock.lock().await;
        sink.admit(id, replay)?;
        assert_eq!(index.inner.lock().unwrap().ceiling, ceiling + 2);
        assert_eq!(index.assigned(&ack_id), None);
        let owed = sink
            .0
            .channel
            .next_unprojected()
            .context("replayed ACK fact is owed")?;
        let before_index = index.retained_bytes();
        let before_process = sink.0.channel.process_bytes.load(Ordering::Acquire);
        let before_thread = sink.pressure(id).thread_bytes;
        let before_projection = projection.retained_bytes();
        let (_, mut prepared) = projection
            .prepare(&sink.0.thread, &owed.effect, &owed.checkpoint.state, false)
            .await?;
        let new_ids = ["after-ack-a".to_owned(), "after-ack-b".to_owned()]
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>();
        let drafts = prepared
            .completion_drafts
            .as_ref()
            .context("publication still owed")?;
        assert_eq!(
            drafts.len(),
            2,
            "a saved ACK must be excluded even without a resident marker"
        );
        assert_eq!(
            drafts
                .iter()
                .map(|draft| draft.item_id.clone())
                .collect::<std::collections::BTreeSet<_>>(),
            new_ids
        );
        assert_eq!(index.assigned(&ack_id), None);
        assert_eq!(index.inner.lock().unwrap().ceiling, ceiling + 2);
        let after_index = index.retained_bytes();
        assert_eq!(
            sink.0.channel.process_bytes.load(Ordering::Acquire),
            before_process - before_index + after_index
        );
        assert!(prepared.items.iter().all(|item| item.ordinal > 0));
        let tool = prepared
            .items
            .iter()
            .find(|item| item.id == tool_item_id)
            .unwrap();
        assert_eq!(tool.ordinal, original_tool.ordinal);
        assert_eq!(tool.revision, original_tool.revision);
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: projection.retained_bytes(),
                pending: Some(PendingProjectionRetention {
                    sequence: prepared.sequence,
                    prepared_bytes: prepared.retained_bytes(),
                }),
            })?;
        assert_eq!(
            sink.pressure(id).thread_bytes,
            before_thread - before_projection - before_index
                + after_index
                + projection.retained_bytes()
                + prepared.retained_bytes()
        );
        projection.publish_prepared(&chat, &mut prepared).await?;
        assert_eq!(prepared.completions.len(), 2);
        assert_eq!(
            prepared
                .completions
                .iter()
                .map(|item| item.header.item_id.clone())
                .collect::<std::collections::BTreeSet<_>>(),
            new_ids
        );
        for (offset, item) in prepared.completions.iter().enumerate() {
            assert_eq!(item.header.append_seq, before_head + offset as u64 + 1);
            assert_ne!(item.header.item_id, ack_id);
        }
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: projection.retained_bytes(),
                pending: Some(PendingProjectionRetention {
                    sequence: prepared.sequence,
                    prepared_bytes: prepared.retained_bytes(),
                }),
            })?;
        assert!(sink.0.channel.prepare(prepared));
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: projection.retained_bytes(),
                pending: None,
            })?;
        drop(lease);
        sink.flush(id, 2).await?;
        assert_eq!(chat.head_seq(), before_head + 2);
        assert_eq!(chat.durable_seq(), before_head + 2);
        assert_eq!(history.watermark().await?, 2);
        assert_eq!(
            pl_core::chat::ChatHistory::item(&history, &ack_id).await?,
            Some(original_ack)
        );
        assert_eq!(index.assigned(&ack_id), None);
        assert_eq!(index.inner.lock().unwrap().ceiling, ceiling + 2);
        sink.0.channel.release_projection_retention();
        sink.0.channel.stop_and_join().await?;
    }
    Ok(())
}

#[tokio::test]
async fn concurrent_tool_results_survive_a_real_writer_failure_without_reexecution() -> Result<()> {
    let (_temp, store, sink) = sink("concurrent-results").await?;
    let requests = Arc::new(AtomicUsize::new(0));
    let thread = ThreadHandle::start(
        "concurrent-results".into(),
        DynModelSession::new(ConcurrentModel(requests.clone())),
    )?;
    let (started, mut starts) = mpsc::unbounded_channel();
    let executions = Arc::new(Mutex::new(Vec::new()));
    let releases: Vec<_> = (0..2).map(|_| Arc::new(Notify::new())).collect();
    thread
        .register_tools(
            ["first", "second"]
                .into_iter()
                .zip(releases.iter())
                .map(|(id, release)| {
                    Ok(
                        Registration::prepare(
                            id.into(),
                            OpaquePayload::text(format!("Tool {id}")),
                        )?
                        .attach(ToolHandle::new(ConcurrentTool {
                            definition: ToolDefinition::text(id, format!("Tool {id}"))?,
                            started: started.clone(),
                            release: release.clone(),
                            executions: executions.clone(),
                        })),
                    )
                })
                .collect::<Result<Vec<_>>>()?,
        )
        .await?;
    thread
        .attach_storage(ColdStoreHandle::new(sink.clone()))
        .await?;
    let turn = TurnInput {
        turn_id: "both-running".into(),
        attempt_prefix: "both-running".into(),
        content: vec![ContextContent::Text {
            text: Arc::from("start"),
        }],
        max_model_steps: ModelStepLimit::Limited(1.try_into()?),
        cancellation: CancellationToken::new(),
    };
    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(turn).await }
    });
    tokio::time::timeout(Duration::from_secs(10), async {
        let mut started = [starts.recv().await, starts.recv().await];
        started.sort();
        assert_eq!(started, [Some("first".into()), Some("second".into())]);
    })
    .await?;
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(5), runner)
            .await???
            .outcome,
        TurnOutcome::StepLimit
    );
    thread.flush().await?;
    let baseline = store
        .history("concurrent-results")
        .await?
        .watermark()
        .await?;
    let chat = store.chat_session("concurrent-results").await?;
    let started_head = chat.head_seq();
    let history = store.history("concurrent-results").await?;
    for call_id in ["first", "second"] {
        let receipt_id =
            crate::studio::thread_projection::order::tool_background_started_id(call_id);
        let receipt = pl_core::chat::ChatHistory::item(&history, &receipt_id)
            .await?
            .context("acknowledged background call must publish its own completion")?;
        let payload: serde_json::Value = serde_json::from_slice(&receipt.payload)?;
        assert_eq!(payload["type"], "tool");
        assert_eq!(payload["data"]["state"]["kind"], "backgroundStarted");
        assert_eq!(
            payload["data"]["invocation"]["taskId"],
            format!("task:{call_id}")
        );
        assert!(
            pl_core::chat::ChatHistory::item(
                &history,
                &crate::studio::thread_projection::order::tool_id(call_id),
            )
            .await?
            .is_none(),
            "a running background result is not a completion"
        );
    }
    let path = store
        .session_paths("project-test", "concurrent-results")?
        .root()
        .join("history.sqlite");
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?;
    db.execute_unprepared(
        "CREATE TRIGGER reject_history BEFORE UPDATE OF applied_write_seq ON history_meta \
             BEGIN SELECT RAISE(ABORT, 'controlled concurrent rejection'); END",
    )
    .await?;

    for release in &releases {
        release.notify_one();
    }
    let mut snapshots = thread.subscribe();
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let snapshot = snapshots.next().await.unwrap();
            if snapshot.terminal_tasks.len()
                + snapshot
                    .tasks
                    .values()
                    .filter(|task| task.status != TaskStatus::Running)
                    .count()
                == 2
            {
                break;
            }
        }
    })
    .await?;
    let mut status = sink.0.channel.subscribe();
    tokio::time::timeout(Duration::from_secs(5), async {
        while status.borrow_and_update().fault.is_none() {
            status.changed().await?;
        }
        Ok::<_, tokio::sync::watch::error::RecvError>(())
    })
    .await??;
    let failed = status.borrow().clone();
    assert_eq!(
        failed.fault,
        Some(pl_protocol::studio::HistoryFault::WriteFailed)
    );
    assert!(failed.queued_records >= 2);
    assert_eq!(
        store
            .history("concurrent-results")
            .await?
            .watermark()
            .await?,
        baseline
    );
    assert_eq!(requests.load(Ordering::Relaxed), 1);
    assert_eq!(*executions.lock().unwrap(), ["first", "second"]);

    db.execute_unprepared("DROP TRIGGER reject_history").await?;
    tokio::time::timeout(
        Duration::from_secs(5),
        store
            .thread_persistence()
            .retry_history("concurrent-results", failed.fault_generation),
    )
    .await??;
    thread.flush().await?;
    let history = store.history("concurrent-results").await?;
    assert_eq!(
        history.watermark().await?,
        thread.snapshot().commit_sequence
    );
    for id in ["first", "second"] {
        let fact = history.tool_task(&format!("task:{id}")).await?.unwrap();
        assert_eq!(fact.task.call_id, id);
        assert_eq!(fact.delivery.unwrap().call_id, id);
        let completion = pl_core::chat::ChatHistory::item(
            &history,
            &crate::studio::thread_projection::order::tool_id(id),
        )
        .await?
        .context("finished background call must publish its separate final result")?;
        assert!(completion.header.append_seq > started_head);
    }
    assert_eq!(requests.load(Ordering::Relaxed), 1);
    assert_eq!(executions.lock().unwrap().len(), 2);
    thread.close().await?;
    Ok(())
}

#[tokio::test]
async fn committed_batch_is_replayed_after_ack_is_lost() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    register_test_thread(&store, &test_thread("lost-ack")).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread("lost-ack"), None).await?;
    // The Thread's projection owner hands the batch over before the writer may write it. The test
    // drives that one write directly, under the step lock, so it can lose the acknowledgement while
    // the queue entry stays — exactly the retry the writer has to make idempotent.
    let write = visible_input_ticket("lost-ack", 1, "replayed-completion")?;
    let bytes = encoded_bytes(&write.effect);
    let chat = store.chat_session("lost-ack").await?;
    let mut projection = live_projection(&sink).await?;
    let mut prepared = projection
        .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
        .await?;
    projection.publish_prepared(&chat, &mut prepared).await?;
    let locked = sink.0.channel.step_lock.lock().await;
    sink.admit("lost-ack", write.clone())?;
    assert!(sink.0.channel.prepare(prepared.clone()));
    assert!(sink.0.channel.prepare(prepared.clone()));
    assert!(
        !sink.0.channel.prepare(Arc::new((*prepared).clone())),
        "a second preparation must not replace the frozen queued batch"
    );
    persist_effect(&sink.0, 1, &write, &prepared, bytes).await?;
    assert_eq!(
        lock_progress(&sink.0).effect_bytes,
        bytes,
        "a committed but unacknowledged queue entry still owns its effect bytes"
    );
    assert_eq!(chat.durable_seq(), 1);
    assert_eq!(store.history("lost-ack").await?.watermark().await?, 1);
    assert_eq!(
        pl_core::chat::ChatHistory::publication_seed(&store.history("lost-ack").await?)
            .await?
            .head_seq,
        1,
        "retry must not append a second completion"
    );
    assert_eq!(sink.0.channel.subscribe().borrow().queued_records, 1);
    sink.0.channel.mark_unavailable(|| true);
    let unavailable = sink.0.channel.subscribe().borrow().clone();
    assert_eq!(
        unavailable.fault,
        Some(pl_protocol::studio::HistoryFault::WriterUnavailable)
    );
    assert!(sink.flush("lost-ack", 1).await.is_err());
    drop(locked);
    tokio::time::timeout(
        Duration::from_secs(5),
        store
            .thread_persistence()
            .retry_history("lost-ack", unavailable.fault_generation),
    )
    .await??;
    assert_eq!(store.history("lost-ack").await?.watermark().await?, 1);
    let status = sink.0.channel.subscribe().borrow().clone();
    assert_eq!(status.queued_records, 0);
    assert_eq!(status.fault, None);
    assert_eq!(lock_progress(&sink.0).effect_bytes, 0);
    let mut persistence = store.thread_persistence().subscribe();
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let row = store
                .thread_persistence()
                .queue_snapshot()
                .threads
                .into_iter()
                .find(|row| row.thread_id == "lost-ack")
                .context("missing live Thread persistence row")?;
            if row.history_admitted_sequence == Some(1) && row.history_durable_sequence == Some(1) {
                break Ok::<_, anyhow::Error>(());
            }
            persistence.changed().await?;
        }
    })
    .await??;
    Ok(())
}

#[tokio::test]
async fn completion_confirmation_does_not_acknowledge_a_later_published_batch() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    register_test_thread(&store, &test_thread("completion-prefix")).await?;
    let sink =
        ThreadStorageSink::new(store.clone(), test_thread("completion-prefix"), None).await?;
    let chat = store.chat_session("completion-prefix").await?;
    let lease = sink.0.channel.step_lock.lock().await;
    let mut projection = live_projection(&sink).await?;
    let mut batches = Vec::new();
    for (sequence, input_id) in [(1, "first-completion"), (2, "later-completion")] {
        let write = visible_input_ticket("completion-prefix", sequence, input_id)?;
        let mut prepared = projection
            .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        projection.publish_prepared(&chat, &mut prepared).await?;
        sink.admit("completion-prefix", write.clone())?;
        assert!(sink.0.channel.prepare(prepared.clone()));
        batches.push((write, prepared));
    }
    assert_eq!(chat.head_seq(), 2);
    assert_eq!(chat.durable_seq(), 0);
    persist_effect(
        &sink.0,
        1,
        &batches[0].0,
        &batches[0].1,
        encoded_bytes(&batches[0].0.effect),
    )
    .await?;
    assert_eq!(
        chat.durable_seq(),
        1,
        "the Session head is not a save receipt"
    );
    let history = store.history("completion-prefix").await?;
    assert!(
        pl_core::chat::ChatHistory::item(&history, "later-completion")
            .await?
            .is_none()
    );
    let visible = chat
        .page(
            pl_core::chat::ChatPageRequest::latest(
                pl_core::chat::ChatQuery::new("conversation", None),
                pl_core::chat::ReadDemand::new(10, 1024 * 1024),
            ),
            &super::batch_tests::Budget,
        )
        .await?;
    assert_eq!(
        visible
            .items
            .iter()
            .map(|item| item.header.item_id.as_str())
            .collect::<Vec<_>>(),
        ["first-completion", "later-completion"],
        "a later published completion stays queryable while only the first is durable"
    );
    drop(lease);
    sink.flush("completion-prefix", 2).await?;
    assert_eq!(chat.durable_seq(), 2);
    Ok(())
}

/// A rejected commit rolls back the effect's history, its latest context and its checkpoint
/// together, so the writer never advances the history watermark to a revision whose checkpoint
/// the very same transaction failed to store — the atomicity the old split write could not give.
#[tokio::test]
async fn a_rejected_atomic_commit_never_advances_history_without_its_checkpoint() -> Result<()> {
    let (_temp, store, sink) = sink("atomic-failure").await?;
    // Commit one effect first so the history database exists, then reject the second one's whole
    // transaction from the watermark update that every atomic commit performs.
    sink.admit("atomic-failure", ticket("atomic-failure", 1))?;
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 1),
        sink.flush("atomic-failure", 1),
        || channel_facts(&sink),
    )
    .await??;
    let path = store
        .session_paths("project-test", "atomic-failure")?
        .root()
        .join("history.sqlite");
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?;
    db.execute_unprepared(
        "CREATE TRIGGER reject_watermark BEFORE UPDATE OF applied_write_seq ON history_meta \
             BEGIN SELECT RAISE(ABORT, 'controlled atomic rejection'); END",
    )
    .await?;
    let mut status = sink.0.channel.subscribe();
    let chat = store.chat_session("atomic-failure").await?;
    sink.admit(
        "atomic-failure",
        visible_input_ticket("atomic-failure", 2, "pending-completion")?,
    )?;
    tokio::time::timeout(Duration::from_secs(5), async {
        while status.borrow_and_update().fault.is_none() {
            status.changed().await?;
        }
        Ok::<_, tokio::sync::watch::error::RecvError>(())
    })
    .await??;
    let failed = status.borrow().clone();
    assert_eq!(
        failed.fault,
        Some(pl_protocol::studio::HistoryFault::WriteFailed)
    );
    // Nothing of the rejected revision is durable: the watermark stays on the previously
    // committed effect and the effect is retained in order for retry.
    assert_eq!(failed.committed_sequence, 1);
    assert_eq!(failed.queued_records, 1);
    assert_eq!(store.history("atomic-failure").await?.watermark().await?, 1);
    assert_eq!(chat.head_seq(), 1);
    assert_eq!(chat.durable_seq(), 0);
    assert!(
        pl_core::chat::ChatHistory::item(
            &store.history("atomic-failure").await?,
            "pending-completion",
        )
        .await?
        .is_none(),
        "rejected transaction must roll back timeline_records too"
    );
    let pending_budget = sink.0.channel.subscribe().borrow().queued_bytes;
    assert!(
        pending_budget > 0,
        "pending completion stays in the reliable budget"
    );
    assert!(sink.flush("atomic-failure", 2).await.is_err());
    db.execute_unprepared("DROP TRIGGER reject_watermark")
        .await?;
    tokio::time::timeout(
        Duration::from_secs(5),
        store
            .thread_persistence()
            .retry_history("atomic-failure", failed.fault_generation),
    )
    .await??;
    assert_eq!(store.history("atomic-failure").await?.watermark().await?, 2);
    assert_eq!(chat.durable_seq(), 1);
    assert!(
        pl_core::chat::ChatHistory::item(
            &store.history("atomic-failure").await?,
            "pending-completion",
        )
        .await?
        .is_some()
    );
    assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
    Ok(())
}

#[tokio::test]
async fn missing_blob_blocks_checkpoint_until_the_same_attachment_is_durable() -> Result<()> {
    use pl_core::context::ResourceReader as _;
    use sha2::Digest as _;

    let (temp, store, sink) = sink("blob-fence").await?;
    let session = store.session_paths("project-test", "blob-fence")?;
    let source = temp.path().join("attachment-draft");
    let bytes = b"restored";
    tokio::fs::write(&source, bytes).await?;
    let draft = crate::studio::store::attachment::AttachmentDraftObject {
        draft_id: "draft-1".to_owned(),
        modality: pl_protocol::studio::StudioAttachmentModality::File,
        media_type: "text/plain".to_owned(),
        filename: "attachment.txt".to_owned(),
        storage_path: source,
        byte_size: bytes.len() as u64,
        content_sha256: hex::encode(sha2::Sha256::digest(bytes)),
        width: None,
        height: None,
        initial_remote_url: None,
    };
    let attachment = store
        .promote_attachment_drafts("blob-fence", &[draft])
        .await?
        .pop()
        .context("promoted attachment is missing")?;
    let reference = store.retain_attachment_resource(&attachment).await?;
    let blob = session.root().join(&attachment.blob_relative_path);
    assert_eq!(
        blob,
        session.resources_dir().join(&attachment.content_sha256),
        "attachment and tool references share the same retained object"
    );
    tokio::fs::remove_file(&blob).await?;
    let resources = crate::resource_store::FileResourceStore::new(session.resources_dir());
    match resources
        .read(
            reference.clone(),
            tokio_util::sync::CancellationToken::new(),
        )
        .await
        .expect_err("removing the shared CAS object makes both references unavailable")
    {
        pl_core::context::ResourceReadError::Unavailable { source } => assert!(matches!(
            source.downcast_ref::<crate::resource_store::ResourceStoreError>(),
            Some(crate::resource_store::ResourceStoreError::Io { source, .. })
                if source.kind() == std::io::ErrorKind::NotFound
        )),
        other => {
            anyhow::bail!("missing shared bytes produced the wrong resource failure: {other}")
        }
    }
    store.record_attachments(vec![attachment.clone()]).await?;
    let mut status = sink.0.channel.subscribe();
    sink.admit(
        "blob-fence",
        ticket_referencing_attachment("blob-fence", &attachment)?,
    )?;
    tokio::time::timeout(Duration::from_secs(5), async {
        while status.borrow_and_update().fault.is_none() {
            status.changed().await?;
        }
        Ok::<_, tokio::sync::watch::error::RecvError>(())
    })
    .await??;
    let failed = status.borrow().clone();
    assert_eq!(
        failed.fault,
        Some(pl_protocol::studio::HistoryFault::BlobFailed)
    );
    // The blob fence runs before the atomic commit, so the missing blob blocks both the effect's
    // history and its checkpoint: the watermark stays untouched until the blob is durable.
    assert_eq!(failed.committed_sequence, 0);
    assert_eq!(failed.queued_records, 1);
    assert!(sink.flush("blob-fence", 1).await.is_err());
    tokio::fs::create_dir_all(blob.parent().expect("blob has a parent")).await?;
    tokio::fs::write(&blob, bytes).await?;
    tokio::time::timeout(
        Duration::from_secs(5),
        store
            .thread_persistence()
            .retry_history("blob-fence", failed.fault_generation),
    )
    .await??;
    assert_eq!(store.history("blob-fence").await?.watermark().await?, 1);
    assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
    assert_eq!(
        resources
            .read(reference, tokio_util::sync::CancellationToken::new())
            .await?
            .as_ref(),
        bytes,
        "restoring the same CAS object repairs tool reads as well as the attachment fence"
    );
    Ok(())
}

#[tokio::test]
async fn closing_the_chat_and_sink_does_not_release_pending_history() -> Result<()> {
    let (_temp, store, sink) = sink("closed-view").await?;
    sink.admit("closed-view", ticket("closed-view", 1))?;
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 1),
        sink.flush("closed-view", 1),
        || channel_facts(&sink),
    )
    .await??;
    let chat = store.chat_session("closed-view").await?;
    let path = store
        .session_paths("project-test", "closed-view")?
        .root()
        .join("history.sqlite");
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?;
    db.execute_unprepared(
        "CREATE TRIGGER reject_history BEFORE UPDATE OF applied_write_seq ON history_meta \
             BEGIN SELECT RAISE(ABORT, 'controlled closed-view rejection'); END",
    )
    .await?;
    let channel = store.thread_persistence().history_channel("closed-view");
    let mut updates = channel.subscribe();
    sink.admit("closed-view", ticket("closed-view", 2))?;
    tokio::time::timeout(Duration::from_secs(5), async {
        while updates.borrow_and_update().fault.is_none() {
            updates.changed().await?;
        }
        Ok::<_, tokio::sync::watch::error::RecvError>(())
    })
    .await??;
    let generation = updates.borrow().fault_generation;
    drop(chat);
    drop(sink);
    assert_eq!(channel.subscribe().borrow().queued_records, 1);
    assert_eq!(store.history("closed-view").await?.watermark().await?, 1);
    db.execute_unprepared("DROP TRIGGER reject_history").await?;
    tokio::time::timeout(
        Duration::from_secs(5),
        store
            .thread_persistence()
            .retry_history("closed-view", generation),
    )
    .await??;
    assert_eq!(store.history("closed-view").await?.watermark().await?, 2);
    assert_eq!(channel.subscribe().borrow().queued_records, 0);
    Ok(())
}

#[tokio::test]
async fn stopped_statistics_consumer_never_blocks_history_or_checkpoint() -> Result<()> {
    let (temp, store, sink) = sink("statistics-gap").await?;
    let calls_before = store.calls().metrics();
    let materials_before = store.calls().subscribe_materials().borrow().clone();
    store.calls().stop_best_effort();
    sink.admit("statistics-gap", ticket("statistics-gap", 1))?;
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 1),
        sink.flush("statistics-gap", 1),
        || channel_facts(&sink),
    )
    .await??;
    assert_eq!(store.history("statistics-gap").await?.watermark().await?, 1);
    assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
    assert_eq!(store.calls().metrics(), calls_before);
    assert_eq!(
        *store.calls().subscribe_materials().borrow(),
        materials_before
    );
    assert!(!store.thread_persistence().queue_snapshot().statistics_gap);

    // A real committed absolute Summary still has a handoff obligation. The history owner
    // keeps its bounded retries through shutdown, without a per-Thread calls observer.
    let accounting = store
        .history("statistics-gap")
        .await?
        .accounting()
        .await?
        .context("committed accounting")?;
    submit_accounting(&sink.0, accounting);
    assert!(lock_progress(&sink.0).pending_accounting.is_some());
    tokio::time::timeout(Duration::from_secs(5), sink.0.channel.stop_and_join()).await??;
    assert!(lock_progress(&sink.0).pending_accounting.is_none());
    assert!(store.calls().statistics_gap());
    assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
    store.thread_persistence().report_calls(store.calls());
    assert!(store.thread_persistence().queue_snapshot().statistics_gap);
    // Later material-free work cannot erase a real rejection.
    store
        .calls()
        .record_effect(&ticket("statistics-gap", 2).effect);
    assert!(store.calls().statistics_gap());
    drop(sink);
    store.close().await?;
    let reopened = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let history = reopened.history("statistics-gap").await?;
    assert_eq!(history.watermark().await?, 1);
    assert_eq!(
        history
            .checkpoint()
            .await?
            .context("checkpoint")?
            .history_fence,
        1
    );
    reopened.close().await?;
    Ok(())
}

#[tokio::test]
async fn crashed_statistics_consumer_does_not_block_history_and_restarts() -> Result<()> {
    let (_temp, store, sink) = sink("statistics-crash").await?;
    let calls = store.calls();
    let summary = |revision| super::super::calls::SessionUsageProjection {
        root_thread_id: "statistics-crash".into(),
        thread_id: "statistics-crash".into(),
        revision,
        has_unpriced_usage: false,
        purpose_costs: vec![],
    };
    calls.panic_on_next_mutation();
    calls.replace_session_usage(summary(1))?;
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if calls
                .last_error()
                .is_some_and(|message| message.contains("terminated unexpectedly"))
            {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .context("call writer did not report the injected worker exit")?;
    assert!(calls.statistics_gap());
    let dropped_ticket = calls.admitted_ticket();
    calls.replace_session_usage(summary(2))?;
    let resumed_ticket = calls.admitted_ticket();
    assert!(resumed_ticket > dropped_ticket);

    sink.admit("statistics-crash", ticket("statistics-crash", 1))?;
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 1),
        sink.flush("statistics-crash", 1),
        || channel_facts(&sink),
    )
    .await
    .context("history flush stalled after the call writer exit")??;
    assert_eq!(
        store.history("statistics-crash").await?.watermark().await?,
        1
    );
    assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if calls.processed_ticket() >= resumed_ticket {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .context("call writer did not advance the resumed ticket")?;
    assert!(calls.statistics_gap());
    Ok(())
}

#[tokio::test]
async fn recovery_rechecks_new_faults_and_stop_after_the_channel_clears() -> Result<()> {
    for stopping in [false, true] {
        let id = if stopping {
            "recovery-stop"
        } else {
            "recovery-new-generation"
        };
        let (_temp, store, sink) = sink(id).await?;
        let channel = &sink.0.channel;
        // Recovery generations belong to real faults, not temporary capacity pressure.
        assert!(sink.admit(id, ticket("wrong-owner", 1)).is_err());
        let first = ticket(id, 1);
        let failed = channel.subscribe().borrow().clone();
        let generation = failed.fault_generation;
        sink.admit(id, first)?;
        let (entered, release) = store.thread_persistence().pause_retry_before_reports();
        let coordinator = store.thread_persistence().clone();
        let recovery = tokio::spawn(async move { coordinator.retry_history(id, generation).await });
        tokio::time::timeout(Duration::from_secs(5), entered).await??;
        if stopping {
            // Keep this owner's pre-commit report visible while its observer is
            // being cancelled. The worker's final report must discharge it.
            store.thread_persistence().report(
                id,
                sink.0.owner,
                ThreadPersistenceReport {
                    pending: Some(PendingSequenceRange { first: 1, last: 1 }),
                    pending_checkpoint: false,
                    error: failed.error,
                    metrics: ThreadPersistenceMetrics {
                        fault_generation: generation,
                        fault: failed.fault,
                        state_dirty_revision: 1,
                        history_admitted_sequence: 1,
                        pending_operations: 1,
                        ..Default::default()
                    },
                },
                Some(store.calls()),
            );
            channel.stop_and_join().await?;
        } else {
            assert!(sink.admit(id, ticket("wrong-owner", 2)).is_err());
        }
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("recovery check lost its owner"))?;
        let error = tokio::time::timeout(Duration::from_secs(5), recovery)
            .await??
            .expect_err("a changed recovery boundary must not return success");
        if stopping {
            assert!(error.to_string().contains("stopping"));
        } else {
            assert!(error.to_string().contains("generation changed"));
            let next = channel.subscribe().borrow().fault_generation;
            assert!(next > generation);
            sink.admit(id, ticket(id, 2))?;
            tokio::time::timeout(
                Duration::from_secs(5),
                store.thread_persistence().retry_history(id, next),
            )
            .await??;
            channel.stop_and_join().await?;
        }
        assert!(store.thread_persistence().snapshot().error.is_none());
    }
    Ok(())
}

#[tokio::test]
async fn empty_queue_retry_does_not_clear_a_ticket_contract_failure() -> Result<()> {
    for durable in [0, 1] {
        let (_temp, store, sink) = sink("ticket-contract").await?;
        if durable != 0 {
            sink.admit("ticket-contract", ticket("ticket-contract", durable))?;
            sink.flush("ticket-contract", durable).await?;
        }
        assert!(
            sink.admit("ticket-contract", ticket("another-thread", durable + 1))
                .is_err()
        );
        let failed = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(
            failed.fault,
            Some(pl_protocol::studio::HistoryFault::WriteFailed)
        );
        assert_eq!(failed.queued_records, 0);
        sink.0.channel.retry(failed.fault_generation)?;
        // Exercise the worker after the retry, with equal old watermarks but no
        // successful write that could repair the rejected ticket's contract.
        assert!(matches!(step(&sink.0).await?, Step::Idle));
        let pressure = sink.pressure("ticket-contract");
        assert!(pressure.error.is_some());
        assert_eq!(
            pressure.fault,
            Some(pl_core::thread::cold::StorageFaultKind::WriteFailed)
        );
        assert_eq!(pressure.recovered_generation, None);
        assert_eq!(
            store.history("ticket-contract").await?.watermark().await?,
            durable
        );
    }
    Ok(())
}

#[tokio::test]
async fn stale_fault_generation_cannot_resume_a_new_ticket_failure() -> Result<()> {
    let (_temp, store, sink) = sink("fault-generation").await?;
    for sequence in [1, 2] {
        let write = ticket("fault-generation", sequence);
        assert!(
            sink.admit("fault-generation", ticket("wrong-owner", sequence))
                .is_err()
        );
        let failed = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(failed.fault_generation, sequence);
        if sequence == 2 {
            assert!(sink.0.channel.retry(1).is_err());
            assert_eq!(sink.0.channel.subscribe().borrow().fault_generation, 2);
        }
        sink.admit("fault-generation", write)?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("fault-generation", sequence),
        )
        .await??;
    }
    assert_eq!(
        store.history("fault-generation").await?.watermark().await?,
        2
    );
    Ok(())
}

/// The continue entry the UI reads is exactly the Thread owner's readiness, with nothing else
/// able to light it.
///
/// The writer reports watermarks and the typed fault generation, but no readiness of its own:
/// the owner can still owe a newer fault while a writer has long since written an older retry, so
/// the projection takes the owner's single verdict — byte for byte — instead of combining
/// anything a writer reports. `resume_required` stays a separate fact: readiness never releases
/// the latch by itself.
#[test]
fn can_resume_is_exactly_the_owners_readiness() {
    use crate::studio::thread_projection::storage_state;

    let mut owner = ThreadSnapshot::default();
    owner.persistence.resume_required = true;
    owner.persistence.fault_generation = 2;

    // A writer that is already past this generation's fault — it reports the same generation with
    // no error and fully admitted watermarks — still cannot offer a continue the owner refuses.
    let writer = pl_protocol::ThreadPersistenceSnapshot {
        fault_generation: 2,
        history_admitted_sequence: Some(9),
        history_durable_sequence: Some(9),
        last_error: None,
        ..pl_protocol::ThreadPersistenceSnapshot::default()
    };
    let storage = storage_state(&owner, &writer);
    assert!(storage.resume_required);
    assert!(
        !storage.can_resume,
        "only the owner's own generation-matched readiness may enable the continue"
    );
    assert_eq!(
        storage.accepted_sequence,
        Some(9),
        "the writer's own watermarks still reach the UI as facts"
    );

    // The owner's verified readiness is the fact, whatever else the writer reports.
    owner.persistence.resume_ready = true;
    assert!(storage_state(&owner, &writer).can_resume);
}

/// One `(identity, content version)` pair is one canonical payload, even when the same fact is
/// projected a second time.
///
/// The projection owner folds an admitted fact once, but the same effect can legitimately reach
/// the projection again — a commit the owner's snapshot already carried, a durable step retried
/// after a real writer failure, or a re-subscription. Every pass must deliver the *same bytes*
/// for a `(item_id, revision)` pair: a pass that restamped the projection clock would hand the
/// durable writer two different payloads under one version, which the store's own revision fence
/// rejects as a real save fault instead of the idempotent rewrite it is. This pins that a repeat
/// projection reuses the version, placement and timestamps of the payload it already delivered.
#[tokio::test]
async fn reprojecting_an_unchanged_effect_keeps_one_canonical_payload() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    register_test_thread(&store, &test_thread("stable-payload")).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread("stable-payload"), None).await?;
    let chat = store.chat_session("stable-payload").await?;
    // The commit sequence is deliberately far above the item's own content version, so a sequence
    // leaking into the version shows up as a value change instead of a coincidence.
    let write = visible_input_ticket("stable-payload", 9, "stable-input")?;
    let mut projection = live_projection(&sink).await?;
    let mut first = projection
        .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
        .await?;
    projection.publish_prepared(&chat, &mut first).await?;
    let mut second = first.clone();
    projection.publish_prepared(&chat, &mut second).await?;
    assert!(Arc::ptr_eq(&first, &second));
    assert!(Arc::ptr_eq(&first.completions, &second.completions));
    assert!(Arc::ptr_eq(
        first.display.as_ref().context("original display")?,
        second.display.as_ref().context("replayed display")?,
    ));
    assert_eq!(
        first.items[0].revision, 1,
        "a first delivery takes the projection's own content version, not the commit sequence"
    );
    assert_eq!(
        serde_json::to_vec(&first.items)?,
        serde_json::to_vec(&second.items)?,
        "redelivery of the frozen effect is byte-identical, so one version never names two payloads"
    );
    Ok(())
}

/// The durable row carries the item's own **content version**, never the effect sequence that
/// committed it, and a cold read of the same history file observes the same value.
///
/// A save receipt is a fact about one exact `(identity, content version)` pair. Substituting the
/// commit sequence for the version would let an acknowledgement vouch for a payload the store
/// never wrote, so both ends are pinned here: the shared session confirms exactly the revision
/// the projection published, and a separate history handle — the cold path, which decodes the
/// durable row itself instead of reading live projection state — returns that same revision.
#[tokio::test]
async fn the_durable_row_keeps_the_items_own_content_version_across_a_cold_read() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    register_test_thread(&store, &test_thread("revision-fence")).await?;
    let sink = ThreadStorageSink::new(store.clone(), test_thread("revision-fence"), None).await?;
    let chat = store.chat_session("revision-fence").await?;
    // The commit sequence is deliberately far above the item's first content version: the
    // projection decides the content version, and the writer has to store that exact value.
    let write = visible_input_ticket("revision-fence", 9, "revision-input")?;
    // No test projection task here: the test hands the one fact over itself, exactly like the
    // Thread's observation worker, so the publish/hand-off/confirm order is deterministic.
    let mut projection = live_projection(&sink).await?;
    // Advance through real, contiguous empty commits; a large write sequence cannot be
    // invented independently of the checkpoint's history fence.
    for sequence in 1..9 {
        let seed = ticket("revision-fence", sequence);
        let mut prepared = projection
            .prepare_committed(&sink.0.thread, &seed.effect, &seed.checkpoint.state)
            .await?;
        projection.publish_prepared(&chat, &mut prepared).await?;
        sink.admit("revision-fence", seed)?;
        sink.0.channel.prepare(prepared);
    }
    let mut prepared = projection
        .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
        .await?;
    projection.publish_prepared(&chat, &mut prepared).await?;
    // The completion records were published atomically before this handoff: the accepted input
    // is complete at acceptance, so the frozen batch carries it and nothing republishes per
    // item.
    sink.admit("revision-fence", write)?;
    sink.0.channel.prepare(prepared.clone());
    await_durable(
        Duration::from_secs(5),
        &format!("commit {}", 9),
        sink.flush("revision-fence", 9),
        || channel_facts(&sink),
    )
    .await??;

    // The real allocation entry point is pinned, not just "different from the commit sequence":
    // a fresh projection's first delivery of a new identity is that identity's content version 1.
    let published = prepared
        .items
        .iter()
        .find(|item| item.id == "revision-input")
        .context("the accepted input is part of the prepared batch")?;
    assert_eq!(
        published.revision, 1,
        "a first delivery takes the projection's own content version, not the commit sequence"
    );
    assert_ne!(
        published.revision, 9,
        "a content version is the item's own fact, never the commit sequence"
    );
    assert_eq!(prepared.completions.len(), 1);
    assert_eq!(prepared.completions[0].header.item_id, "revision-input");

    let path = store
        .session_paths("project-test", "revision-fence")?
        .root()
        .join("history.sqlite");
    let cold = crate::studio::storage::history::HistoryStore::open(&path, "revision-fence").await?;
    let durable = cold.items_for_turn("visible-turn").await?;
    assert_eq!(durable.len(), 1);
    assert_eq!(durable[0].id, "revision-input");
    assert_eq!(
        durable[0].revision, published.revision,
        "the persisted row carries the same content version the projection allocated"
    );
    Ok(())
}

/// Archive retry for an already complete capture, using the real content-addressed store.
#[derive(Debug)]
struct CaptureArchiveObligation {
    archive: crate::resource_store::FileResourceStore,
    capture_file: std::path::PathBuf,
    call_id: String,
    committed_len: u64,
    pending: Vec<u8>,
    retries: Arc<AtomicUsize>,
}

impl pl_core::thread::cold::OutputRetryObligation for CaptureArchiveObligation {
    fn identity(&self) -> String {
        self.capture_file.display().to_string()
    }
    fn retry(&self) -> pl_core::thread::cold::OutputRetryFuture<'_> {
        Box::pin(async move {
            self.retries.fetch_add(1, Ordering::SeqCst);
            let reference = self
                .archive
                .retain_command_capture(&self.capture_file)
                .await
                .map_err(|error| pl_core::thread::cold::ColdStoreError {
                    source: Box::new(error),
                })?;
            Ok(pl_core::thread::cold::OutputRetryOutcome::StoredWithRepair(
                pl_core::thread::cold::OutputRepair {
                    call_id: self.call_id.clone(),
                    reference,
                },
            ))
        })
    }
    fn received_bytes(&self) -> u64 {
        self.committed_len.saturating_add(self.pending.len() as u64)
    }
    fn location(&self) -> String {
        self.capture_file.display().to_string()
    }
    fn kind(&self) -> pl_core::thread::cold::StorageFaultKind {
        pl_core::thread::cold::StorageFaultKind::WriteFailed
    }
}

/// A completed capture whose desktop archive failed, retaining the confirmed source.
#[derive(Debug)]
struct FailedArchiveTool {
    definition: ToolDefinition,
    archive: crate::resource_store::FileResourceStore,
    capture_file: std::path::PathBuf,
    committed_len: u64,
    pending: Vec<u8>,
    retries: Arc<AtomicUsize>,
    created: Arc<Mutex<Vec<Arc<CaptureArchiveObligation>>>>,
}

impl Tool for FailedArchiveTool {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let obligation = Arc::new(CaptureArchiveObligation {
            archive: self.archive.clone(),
            capture_file: self.capture_file.clone(),
            call_id: context.call_id.clone(),
            committed_len: self.committed_len,
            pending: self.pending.clone(),
            retries: self.retries.clone(),
        });
        self.created.lock().unwrap().push(obligation.clone());
        let source = pl_core::thread::cold::ColdStoreError {
            source: Box::new(std::io::Error::other("capture archive failed")),
        };
        let fault = pl_core::thread::cold::OutputStorageFault::new(
            pl_core::thread::cold::StorageFaultKind::WriteFailed,
            Arc::new(source),
        )
        .with_obligation(obligation);
        Err(ToolError::new(fault).with_output(ToolOutput::new(
            input.clone(),
            vec![ContextContent::Text {
                text: Arc::from("accepted so far"),
            }],
        )))
    }
}

#[derive(Debug)]
struct CaptureModel;

impl ModelSession for CaptureModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        Ok(PreparedModelCall::new(async move {
            Ok(ModelStepOutput {
                turn_action: Default::default(),
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: vec![ContextContent::Text {
                    text: Arc::from("calling capture"),
                }],
                tool_calls: vec![ModelToolCall {
                    rejection: None,
                    presentation_contract: None,
                    call_id: "capture-1".to_owned(),
                    tool_id: "capture".to_owned(),
                    arguments: OpaquePayload::text("capture"),
                }],
                private_context: None,
                usage: Default::default(),
            })
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

/// The owner facts one stuck wait is diagnosed from, so a timeout names a stage instead of a bare
/// deadline and a real owner bug is not masked by a longer one.
fn stage_facts(snapshot: &ThreadSnapshot) -> String {
    format!(
        "fault={:?} generation={} phase={:?} obligations={} resume_required={} resume_ready={} \
             commit={} durable={}",
        snapshot.persistence.fault,
        snapshot.persistence.fault_generation,
        snapshot.persistence.execution_phase,
        snapshot.persistence.output_obligations.len(),
        snapshot.persistence.resume_required,
        snapshot.persistence.resume_ready,
        snapshot.commit_sequence,
        snapshot.persistence.durable_sequence,
    )
}

/// A best-effort snapshot of the reliable channel taken when one durable barrier expires.
///
/// It reports the watermarks, the queue, the published fault and the oldest effect no projection
/// has taken over yet, so an expired budget is accompanied by the facts the wait was measured
/// against instead of only `deadline has elapsed`. The values are read from live state and may
/// already reflect concurrent progress: they are not an atomic snapshot of one instant, and
/// `unprojected` names only the earliest effect that is unprepared at the moment of the read.
/// Neither its presence nor its absence decides on its own whether a stall came from scheduling,
/// IO, a lock or a logic defect — those fields are evidence for a later judgement, not a verdict.
fn channel_facts(sink: &ThreadStorageSink) -> String {
    let channel = &sink.0.channel;
    let facts = {
        let status = channel.subscribe();
        let status = status.borrow();
        format!(
            "durable={} admitted={} queued={} ({} bytes) fault={:?} generation={} error={:?}",
            status.committed_sequence,
            status.admitted_sequence,
            status.queued_records,
            status.queued_bytes,
            status.fault,
            status.fault_generation,
            status.error,
        )
    };
    let unprojected = channel
        .next_unprojected()
        .map(|write| write.effect.sequence);
    format!("{facts} unprojected={unprojected:?}")
}

/// Awaits the supplied future under the caller's timeout budget.
///
/// On expiry, appends the caller-provided diagnostic text without inferring a cause.
async fn await_durable<T>(
    budget: Duration,
    stage: &str,
    future: impl std::future::Future<Output = T>,
    describe: impl FnOnce() -> String,
) -> Result<T> {
    match tokio::time::timeout(budget, future).await {
        Ok(value) => Ok(value),
        Err(_) => anyhow::bail!("`{stage}` did not land: {}", describe()),
    }
}

/// Waits until the authoritative snapshot satisfies `predicate`, tagging `stage` on timeout.
///
/// The subscription yields the current snapshot first, so a boundary that already landed is observed
/// without waiting for an unrelated new frame — the exact shape of the earlier hang — and the timeout
/// reports the stage and the last owner facts so the production cause is located, not hidden.
async fn await_stage(
    thread: &ThreadHandle,
    stage: &str,
    predicate: impl Fn(&ThreadSnapshot) -> bool,
) -> Result<ThreadSnapshot> {
    let mut snapshots = thread.subscribe();
    let reached = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let snapshot = snapshots.next().await.expect("thread stays observable");
            if predicate(&snapshot) {
                return snapshot;
            }
        }
    })
    .await;
    reached.map_err(|_| {
        anyhow::anyhow!(
            "stage `{stage}` was not reached: {}",
            stage_facts(&thread.snapshot())
        )
    })
}

/// The reference a repaired capture stored reaches the durable tool result, not just memory.
///
/// A retry archives the same confirmed bytes and attaches its durable reference exactly once.
#[tokio::test]
async fn a_confirmed_capture_archive_retry_reaches_the_durable_tool_result() -> Result<()> {
    use pl_core::context::ResourceReader;
    use pl_core::thread::cold::OutputRetryObligation as _;

    let (temp, store, sink) = sink("archive-repair").await?;
    let resources_root = temp.path().join("resources");
    std::fs::create_dir_all(&resources_root)?;
    let archive = crate::resource_store::FileResourceStore::new(resources_root);

    let capture_file = temp.path().join("capture.fragment");
    let committed = b"accepted line one\n".to_vec();
    let pending = b"accepted line two".to_vec();
    let mut expected = committed.clone();
    expected.extend_from_slice(&pending);
    std::fs::write(&capture_file, &expected)?;

    let retries = Arc::new(AtomicUsize::new(0));
    let created: Arc<Mutex<Vec<Arc<CaptureArchiveObligation>>>> = Arc::new(Mutex::new(Vec::new()));
    let thread = ThreadHandle::start("archive-repair".into(), DynModelSession::new(CaptureModel))?;
    thread
        .register_tools(vec![
            Registration::prepare("capture".into(), OpaquePayload::text("Tool capture"))?.attach(
                ToolHandle::new(FailedArchiveTool {
                    definition: ToolDefinition::text("capture", "Tool capture")?,
                    archive: archive.clone(),
                    capture_file: capture_file.clone(),
                    committed_len: committed.len() as u64,
                    pending: pending.clone(),
                    retries: retries.clone(),
                    created: created.clone(),
                }),
            ),
        ])
        .await?;
    thread
        .attach_storage(ColdStoreHandle::new(sink.clone()))
        .await?;

    let runner = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .run_turn(TurnInput {
                    turn_id: "capture-turn".into(),
                    attempt_prefix: "capture".into(),
                    content: vec![ContextContent::Text {
                        text: Arc::from("run capture"),
                    }],
                    max_model_steps: ModelStepLimit::Limited(
                        std::num::NonZeroU32::new(1).expect("positive model step limit"),
                    ),
                    cancellation: CancellationToken::new(),
                })
                .await
        }
    });
    let faulted = await_stage(&thread, "typed storage fault latch", |snapshot| {
        snapshot.persistence.resume_required
    })
    .await?;
    assert_eq!(
        faulted.persistence.fault,
        Some(pl_core::thread::cold::StorageFaultKind::WriteFailed)
    );
    let generation = faulted.persistence.fault_generation;
    assert_eq!(
        faulted.persistence.output_obligations.len(),
        1,
        "the failed capture owes exactly one archive obligation"
    );
    assert!(
        !faulted.persistence.resume_ready,
        "a failed archive must not offer a continue before its bytes are stored"
    );

    // The requirement is that the owed obligation blocks continuation, not that the Turn reaches
    // one particular phase: with a one-step limit the Turn may simply end after the fault, and no
    // later phase frame is guaranteed to be published. Stopping the driver and refusing the
    // explicit continue while the obligation is still owed proves the real boundary.
    drop(runner);
    assert!(
        !thread.snapshot().persistence.output_obligations.is_empty(),
        "the failed capture is still owed before the retry: {}",
        stage_facts(&thread.snapshot())
    );
    assert!(
        thread.resume_storage(generation).await.is_err(),
        "the pause stays closed until the archive obligation is re-stored"
    );

    thread.retry_output_storage().await?;
    thread.flush().await?;
    assert_eq!(
        retries.load(Ordering::SeqCst),
        1,
        "the real repair and archive run exactly once for the failed capture"
    );

    let history = store.history("archive-repair").await?;
    let fact = history
        .tool_task("task:capture-1")
        .await?
        .context("the committed tool task is durable")?;
    let delivery = fact.delivery.context("the committed delivery is durable")?;
    let reference = delivery
        .delivered_context
        .iter()
        .find_map(|content| match content {
            ContextContent::Resource { reference } => Some(reference.clone()),
            _ => None,
        })
        .context("the repaired reference is recorded on the committed delivery")?;
    assert!(
        reference.id().starts_with("pl.studio.resource:"),
        "the delivery records the real content-addressed archive reference"
    );
    let stored_bytes =
        ResourceReader::read(&archive, reference.clone(), CancellationToken::new()).await?;
    assert_eq!(
        stored_bytes.as_ref(),
        expected.as_slice(),
        "the archive stores the accepted bytes verbatim, once, without the partial write"
    );
    let items = history.items_for_turn("capture-turn").await?;
    let output = items
        .iter()
        .find_map(|item| match item.state() {
            pl_protocol::ThreadItemState::Tool(tool) => tool.terminal_output(),
            _ => None,
        })
        .context("the repaired call keeps its durable terminal result")?;
    let referenced = serde_json::to_value(&reference)?;
    assert_eq!(
        output
            .output_artifacts()
            .iter()
            .filter(|artifact| *artifact == &referenced)
            .count(),
        1,
        "the durable item carries the repaired reference exactly once"
    );

    // Off-window stage: the bounded live window is not a save authority. A window that never saw
    // the commit — no GUI open, a slow reader, or a rolled-over window — must still project the
    // repair from the already-committed body, so the canonical item and its content version come
    // from the single projection owner and the durable row is a pure confirmation. A second,
    // already-committed tool identity with no reference yet is written through the writer's own
    // durable commit path, then repaired by a fresh window that has to read it back.
    // The durable identity the single projection owner derives from the call id, kept identical to
    // `order::tool_id` so the owner's own history lookup finds exactly this committed row.
    // This is a separate cold fixture, not an out-of-band mutation of the live writer's
    // database: its artificial sequence must not invalidate the live recovery checkpoint.
    let history = crate::studio::storage::history::HistoryStore::open(
        &temp.path().join("off-window.sqlite"),
        "archive-repair",
    )
    .await?;
    history.prepare_model_access().await?;
    let fixture_db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &temp.path().join("off-window.sqlite"),
            crate::studio::paths::SqliteFileMode::ReadOnly,
            |options| options,
        )
        .await?,
    )
    .await?;
    let database_id: String = fixture_db
        .query_one_raw(sea_orm::Statement::from_string(
            sea_orm::DatabaseBackend::Sqlite,
            "SELECT database_id FROM history_meta WHERE id=1",
        ))
        .await?
        .context("off-window history identity")?
        .try_get("", "database_id")?;
    let off_write = ticket("archive-repair", 1_000_000);
    let mut current_owner = crate::studio::thread_projection::LiveProjection::new();
    let current_channel = HistoryChannel::new(Arc::new(AtomicU64::new(0)));
    current_owner.bind_execution_history(current_channel.order_index(), history.clone())?;
    let frozen_current = current_owner
        .prepare_committed(
            &test_thread("archive-repair"),
            &off_write.effect,
            &off_write.checkpoint.state,
        )
        .await?;
    let off_window_id = format!("tool:{}:capture-2", "capture-2".len());
    let off_window_item = pl_protocol::ThreadItem::new(
        off_window_id.clone(),
        "archive-repair".to_owned(),
        "capture-turn".to_owned(),
        41,
        1,
        1,
        1,
        pl_protocol::ThreadItemState::Tool(pl_protocol::ThreadToolItem::new(
            pl_protocol::ThreadToolInvocation::new(
                "capture-2".to_owned(),
                "capture".to_owned(),
                "{}".to_owned(),
            ),
            pl_protocol::ThreadToolState::Succeeded(pl_protocol::SucceededThreadTool::new(
                1,
                pl_protocol::ThreadToolOutput::new(
                    "accepted so far".to_owned(),
                    Vec::new(),
                    Vec::new(),
                    None,
                ),
            )),
        )),
    );
    let cold_chat = pl_core::chat::Session::new(
        history.clone(),
        pl_core::chat::TimelineEpoch::new("off-window-repair")?,
    );
    let original_completion = cold_chat
        .publish_batch(vec![crate::studio::runtime::chat_item::completion_draft(
            &off_window_item,
            1_000_000,
            &database_id,
        )?])
        .await?;
    history
        .commit_effect(
            1_000_000,
            EffectCommit {
                items: std::slice::from_ref(&off_window_item),
                completions: &original_completion,
                current: &frozen_current.current,
                rolled_back_turns: &Default::default(),
                identities: &[],
                messages: &[],
                receipts: &[],
                tasks: &[],
                deliveries: &[],
                delivery_repairs: &[],
                attempt: None,
            },
        )
        .await?;
    cold_chat.confirm_durable(original_completion.last().unwrap().header.append_seq)?;
    let repair_only = ThreadEffectBatch {
        thread_id: "archive-repair".to_owned(),
        sequence: 1_000_001,
        committed_at: 1,
        delivery_repairs: Arc::from([pl_core::thread::cold::OutputRepair {
            call_id: "capture-2".to_owned(),
            reference: reference.clone(),
        }]),
        ..Default::default()
    };
    let off_window_channel = HistoryChannel::new(Arc::new(AtomicU64::new(0)));
    off_window_channel.order_index.seed(
        history.latest_execution_ordinal().await?,
        history.watermark().await?,
    );
    let mut off_window = crate::studio::thread_projection::LiveProjection::new();
    off_window.bind_execution_history(off_window_channel.order_index(), history.clone())?;
    crate::studio::thread_projection::seed_repaired_targets(
        &mut off_window,
        &history,
        &repair_only,
    )
    .await?;
    assert!(
        off_window.holds_terminal_tool(&off_window_id),
        "the off-window repair reads the committed body back before projecting it"
    );
    let chat = cold_chat;
    let mut packaged = off_window
        .prepare_committed(
            &test_thread("archive-repair"),
            &repair_only,
            &ThreadSnapshot::default(),
        )
        .await?;
    off_window.publish_prepared(&chat, &mut packaged).await?;
    assert!(
        packaged.completions.is_empty(),
        "a repaired execution result cannot reseal its changed payload into completion history"
    );
    assert_eq!(
        pl_core::chat::ChatHistory::item(&history, &off_window_id).await?,
        Some((*original_completion[0]).clone())
    );
    let repackaged = packaged
        .items
        .iter()
        .find(|item| item.id == off_window_id)
        .context("the off-window repair is projected at its original identity")?;
    assert_eq!(
        repackaged.ordinal, off_window_item.ordinal,
        "the supplement keeps the committed position instead of taking a new one"
    );
    assert_eq!(
        repackaged.revision,
        off_window_item.revision + 1,
        "the single projection owner assigns the content version; the writer never invents one"
    );
    let repackaged_output = match repackaged.state() {
        pl_protocol::ThreadItemState::Tool(tool) => tool.terminal_output(),
        _ => None,
    }
    .context("the off-window supplement keeps the terminal tool result")?;
    assert_eq!(
        repackaged_output
            .output_artifacts()
            .iter()
            .filter(|artifact| *artifact == &referenced)
            .count(),
        1,
        "the off-window projection appends the reference exactly once"
    );

    // The caller can only continue once the obligation and its repair really landed.
    thread.resume_storage(generation).await?;
    assert!(!thread.snapshot().persistence.resume_required);

    // A repeated retry reproduces the same bytes and the same reference instead of appending twice.
    let obligation = created
        .lock()
        .unwrap()
        .first()
        .cloned()
        .expect("the tool created its obligation");
    let again = obligation.retry().await?;
    let pl_core::thread::cold::OutputRetryOutcome::StoredWithRepair(repaired) = again else {
        anyhow::bail!("the repeated retry must name the same repaired reference");
    };
    assert_eq!(repaired.reference, reference);
    assert_eq!(
        std::fs::read(&capture_file)?,
        expected,
        "repeating archive retention preserves the confirmed source bytes"
    );
    assert_eq!(retries.load(Ordering::SeqCst), 2);
    thread.close().await?;
    Ok(())
}
