use super::*;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::{
        ThreadEffectBatch, ThreadSnapshot, TurnOutcome, TurnRecord, TurnState,
        current::RuntimeEpoch,
        history_sink::HistorySink,
        input::{InputChange, InputRecord, InputState, ThreadInput},
    },
};

pub(crate) fn ticket(thread_id: &str, sequence: u64) -> Arc<HistoryExport> {
    Arc::new(HistoryExport {
        effect: Arc::new(ThreadEffectBatch {
            thread_id: thread_id.to_owned(),
            sequence,
            committed_at: 1,
            ..Default::default()
        }),
        state: ThreadSnapshot {
            commit_sequence: sequence,
            ..Default::default()
        },
        output_claim: None,
    })
}

pub(super) fn test_thread(thread_id: &str) -> crate::Thread {
    let mut thread = crate::Thread::placeholder(thread_id);
    thread.workspace_id = "project-test".into();
    thread.agent_path = thread_id.to_owned();
    thread.root_thread_id = thread_id.to_owned();
    thread
}

pub(crate) async fn register_test_thread(
    store: &StudioStore,
    thread: &crate::Thread,
) -> Result<()> {
    let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
        crate::studio::store::directory::ProjectDirectoryRecord {
            id: thread.workspace_id.clone(),
            kind: crate::WorkspaceKind::Project,
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

pub(crate) struct CloseFactoryFixture {
    pub(crate) factory: crate::studio::StudioThreadFactory,
    pub(in crate::studio) writer: crate::studio::storage::write_behind::ThreadWriteBehindWriter,
    pub(crate) config: crate::config::ConfigRuntime,
    pub(crate) events: crate::studio::ProductEventBus,
    store: StudioStore,
    worktrees: crate::studio::worktree::worktree_lease::WorktreeLeaseOwner,
}

impl CloseFactoryFixture {
    pub(crate) async fn unpublished_workspace(
        &self,
        id: &str,
        root: &std::path::Path,
    ) -> Result<crate::thread_assembler::WorkspacePreparationOwner> {
        use crate::studio::worktree::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity};
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
    let writer = crate::studio::storage::write_behind::ThreadWriteBehindWriter::new(store.clone());
    let events = crate::studio::ProductEventBus::new(store.clone(), writer.clone());
    let config = crate::config::ConfigRuntime::initialize(crate::config::ConfigStore::new(
        crate::config::ConfigPaths::from_config_dir(
            store.paths().home().join("isolated-test-config"),
        ),
    ))?;
    let source = crate::worker_assets::RemoteHelperSource::External;
    let bots = crate::bots::BotRuntime::new(store.paths().clone(), config.clone(), events.clone())?;
    let worktrees =
        crate::studio::worktree::worktree_lease::WorktreeLeaseOwner::new(writer.clone());
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
            Default::default(),
        ),
        thread_modes: config.thread_mode_manager(),
        ssh_manager: Arc::new(crate::worker_assets::ssh_manager(&source)),
        bots,
        run_export: None,
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

fn spawn_projection(store: StudioStore, thread: crate::Thread) -> tokio::task::JoinHandle<()> {
    let channel = store.thread_persistence().history_channel(&thread.id);
    tokio::spawn(async move {
        let mut projection = crate::studio::thread_projection::LiveProjection::new();
        projection
            .bind_execution(
                channel.order_index(),
                RuntimeEpoch::new(),
                store
                    .history(&thread.id)
                    .await
                    .expect("history owner")
                    .database_id()
                    .to_owned(),
            )
            .expect("one projection binding");
        let mut failed = std::collections::BTreeSet::new();
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
                match projection.prepare_committed(&thread, &write.effect, &write.state) {
                    Ok(prepared) => {
                        if let Err(error) = channel.accept_prepared(Some(&write), prepared) {
                            failed.insert(sequence);
                            channel.fail_projection(
                                sequence,
                                format!("fixture History handoff failed: {error:#}"),
                            );
                        }
                    }
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

async fn saved_current(
    store: &StudioStore,
    thread: &crate::Thread,
) -> Result<Option<pl_core::thread::current::ThreadCurrent>> {
    let paths = store.registered_session_paths(&thread.id)?;
    store
        .state_for(paths.workspace_id(), &thread.id)?
        .load_current()
        .await
}

pub(super) async fn live_projection(
    sink: &ThreadStorageSink,
) -> Result<crate::studio::thread_projection::LiveProjection> {
    let current = saved_current(&sink.0.store, &sink.0.thread).await?;
    let epoch = match current {
        Some(current) => current.saved_runtime_epoch,
        None => RuntimeEpoch::new(),
    };
    let mut projection = crate::studio::thread_projection::LiveProjection::new();
    projection.bind_execution(
        sink.0.channel.order_index(),
        epoch,
        sink.0
            .store
            .history(&sink.0.thread.id)
            .await?
            .database_id()
            .to_owned(),
    )?;
    Ok(projection)
}

pub(crate) async fn save_terminal_report(
    store: &StudioStore,
    thread: &crate::Thread,
    message: pl_core::thread::inbox::ThreadMessage,
) -> Result<()> {
    let saved = saved_current(store, thread).await?;
    // This is a new History producer incarnation. Its handoff sequence starts at one;
    // an independent Current revision cannot seed History admission or durability.
    let sequence = 1;
    let mut snapshot = saved
        .as_ref()
        .map_or_else(ThreadSnapshot::default, |current| {
            current.state.to_paused_snapshot()
        });
    snapshot.commit_sequence = sequence;
    let turn = TurnRecord {
        turn_id: "original-terminal-turn".into(),
        input_id: None,
        state: TurnState::Finished(TurnOutcome::Completed),
        model_steps: 0,
        elapsed_ms: None,
    };
    snapshot.lifecycle = pl_core::thread::ThreadLifecycle::Closed;
    snapshot.turns = Arc::from([turn.clone()]);
    let terminal = Arc::new(HistoryExport {
        effect: Arc::new(ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence,
            committed_at: 1,
            turn: Some(turn),
            ..Default::default()
        }),
        state: snapshot,
        output_claim: None,
    });
    let sink = ThreadStorageSink::new(store.clone(), thread.clone()).await?;
    let mut projection = crate::studio::thread_projection::LiveProjection::new();
    projection.bind_execution(
        sink.0.channel.order_index(),
        RuntimeEpoch::new(),
        store.history(&thread.id).await?.database_id().to_owned(),
    )?;
    let prepared = projection.prepare_committed(thread, &terminal.effect, &terminal.state)?;
    let mut handed = (*prepared).clone();
    handed.parent_report = Some(Arc::new(message));
    let handed = Arc::new(handed);
    sink.admit(&thread.id, terminal)?;
    sink.0.channel.accept_prepared(None, handed)?;
    sink.0
        .channel
        .await_handoff_durable(&thread.id, sequence)
        .await?;
    sink.0.channel.stop_and_join().await
}

pub(crate) fn visible_input_ticket(
    thread_id: &str,
    sequence: u64,
    input_id: &str,
) -> Result<Arc<HistoryExport>> {
    let mut write = (*ticket(thread_id, sequence)).clone();
    let input = InputRecord {
        accepted_sequence: sequence,
        input: ThreadInput {
            purpose: pl_core::thread::input::InputPurpose::Message,
            id: input_id.to_owned(),
            payload: OpaquePayload::new(
                "pl.studio.prompt",
                1,
                serde_json::json!({
                    "text": "hello",
                    "presentation": "visible",
                    "attachments": [],
                })
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
    write.state.inputs = Arc::from([input.clone()]);
    Arc::make_mut(&mut write.effect).inputs = Arc::from([InputChange::Accepted(input)]);
    Ok(Arc::new(write))
}

pub(super) struct Fixture {
    _temp: tempfile::TempDir,
    pub(super) store: StudioStore,
    pub(super) sink: ThreadStorageSink,
    pub(super) projection: crate::studio::thread_projection::LiveProjection,
}

impl Fixture {
    pub(super) async fn new(id: &str) -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id)).await?;
        let projection = live_projection(&sink).await?;
        Ok(Self {
            _temp: temp,
            store,
            sink,
            projection,
        })
    }

    pub(super) async fn handoff(
        &mut self,
        write: &Arc<HistoryExport>,
    ) -> Result<Arc<PreparedEffect>> {
        let id = self.sink.0.thread.id.clone();
        self.sink.admit(&id, write.clone())?;
        let prepared =
            self.projection
                .prepare_committed(&self.sink.0.thread, &write.effect, &write.state)?;
        ensure!(
            self.sink.0.channel.prepare(prepared.clone()),
            "handoff refused"
        );
        Ok(prepared)
    }

    pub(super) fn select(&self, now: Instant) -> batch::Selection {
        batch::select(&mut lock_progress(&self.sink.0), now, 0, false)
    }

    pub(super) async fn finish(&self, sequence: u64) -> Result<()> {
        self.sink
            .0
            .channel
            .await_handoff_durable(&self.sink.0.thread.id, sequence)
            .await?;
        self.sink.0.channel.stop_and_join().await
    }
}

pub(super) fn ready(selection: batch::Selection) -> Vec<batch::Effect> {
    match selection {
        batch::Selection::Ready(effects) => effects,
        _ => panic!("expected a frozen prepared prefix"),
    }
}
