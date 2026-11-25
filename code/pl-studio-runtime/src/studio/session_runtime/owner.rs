//! Saved agent identities, explicit cold activation and read-only history/Profile queries.
pub(crate) mod query;
#[cfg(test)]
use super::host_agent_tools::query::{Kind, QueryTool};
use super::*;
use crate::AgentSessionPage;
use anyhow::{Context, Result, bail};
#[cfg(test)]
use pl_agent_tool::{Tool, ToolDefinition};
#[cfg(test)]
use pl_core::tool::opaque::CallContext;
use query::*;
use serde::Serialize;
use tokio_util::sync::CancellationToken;

/// Publishes (or refreshes) the Recovery diagnosis of a member whose workspace could not be used.
///
/// The runtime owns the single Recovery registry; the assembler only reports the failure, so an
/// internal scheduling activation fails exactly like an explicit activation would.
pub(crate) type WorkspaceRecoveryPublisher = std::sync::Arc<
    dyn Fn(crate::Thread, anyhow::Error) -> futures::future::BoxFuture<'static, ()> + Send + Sync,
>;

#[derive(Clone)]
pub(crate) struct StudioSessionOwner {
    pub(crate) factory: crate::studio::StudioThreadFactory,
    pub(crate) config: crate::config::ConfigRuntime,
    pub(crate) store: crate::studio::StudioStore,
    pub(crate) events: crate::studio::ProductEventBus,
    pub(crate) performance: crate::studio::ModelPerformanceOwner,
    pub(crate) recovery: crate::studio::StudioRecoveryRegistry,
    pub(crate) workspace_recovery: Option<WorkspaceRecoveryPublisher>,
    pub(crate) acp_business: Option<crate::studio::runtime::acp_business::AcpBusinessOwner>,
}
impl std::fmt::Debug for StudioSessionOwner {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("StudioSessionOwner")
    }
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Profiles<'a> {
    delegation_mode: crate::DelegationMode,
    profiles: Vec<crate::AgentProfile>,
    diagnostics: &'a [crate::config::AgentProfileDiagnostic],
}

#[derive(Debug, thiserror::Error)]
#[error("Agent service failed: {0}")]
pub(crate) struct ServiceError(#[source] pub(crate) anyhow::Error);

impl super::agents::AgentHost {
    pub(crate) fn query_services(
        &self,
        context: &pl_tool::collaboration::control::AgentCallContext,
        model: bool,
    ) -> Result<Arc<StudioSessionOwner>, pl_tool::collaboration::control::ControlError> {
        use pl_tool::collaboration::control::ControlError;
        self.caller(context)?;
        if self.identity.parent_agent_id.is_some() {
            return Err(ControlError::service(std::io::Error::other(
                "delegation tools are root-only",
            )));
        }
        if model && self.delegation().mode != crate::DelegationMode::Automatic {
            return Err(ControlError::service(std::io::Error::other(
                "model queries require automatic delegation",
            )));
        }
        self.owner()?
            .0
            .state()
            .agent_services
            .clone()
            .ok_or(ControlError::Closed)
    }

    pub(crate) async fn list_agent_profiles(
        &self,
        context: pl_tool::collaboration::control::AgentCallContext,
    ) -> Result<serde_json::Value, pl_tool::collaboration::control::ControlError> {
        self.query_services(&context, false)?;
        let delegation_mode = self.delegation().mode;
        let mut profiles = self.catalog.profiles.clone();
        if delegation_mode == crate::DelegationMode::Automatic {
            for profile in &mut profiles {
                if let crate::AgentBinding::Native(native) = &mut profile.binding {
                    // A role's unused fixed route must not masquerade as the automatic choice.
                    native.route = None;
                }
            }
        }
        serde_json::to_value(Profiles {
            delegation_mode,
            profiles,
            diagnostics: &self.catalog.diagnostics,
        })
        .map_err(pl_tool::collaboration::control::ControlError::service)
    }

    pub(crate) async fn list_delegation_models(
        &self,
        context: pl_tool::collaboration::control::AgentCallContext,
        request: crate::ListDelegationModelsRequest,
    ) -> Result<crate::DelegationModelList, pl_tool::collaboration::control::ControlError> {
        self.query_services(&context, true)?
            .delegation_models()
            .list_delegation_models(request)
            .await
            .map_err(|error| {
                pl_tool::collaboration::control::ControlError::service(ServiceError(error))
            })
    }

    pub(crate) async fn get_delegation_models(
        &self,
        context: pl_tool::collaboration::control::AgentCallContext,
        request: crate::GetDelegationModelsRequest,
    ) -> Result<crate::DelegationModelDetails, pl_tool::collaboration::control::ControlError> {
        self.query_services(&context, true)?
            .delegation_models()
            .get_delegation_models(request)
            .await
            .map_err(|error| {
                pl_tool::collaboration::control::ControlError::service(ServiceError(error))
            })
    }
}

impl StudioSessionOwner {
    pub(crate) fn identity(&self, thread: &str) -> Result<crate::AgentThreadIdentity> {
        self.events
            .agent_execution_identity(thread)
            .map(|(identity, _, _)| identity)
            .context("agent directory identity is missing")
    }

    pub(crate) fn direct_child(&self, caller: &str, target: &str) -> Result<bool> {
        let caller = self.identity(caller)?;
        let target = self.identity(target)?;
        Ok(caller.session_id == target.session_id
            && target.parent_agent_id.as_ref() == Some(&caller.agent_id))
    }

    fn delegation_models(&self) -> super::delegation_models::DelegationModels {
        super::delegation_models::DelegationModels {
            config: self.config.clone(),
            store: self.store.clone(),
            performance: self.performance.clone(),
        }
    }

    pub(crate) async fn saved_agents(
        &self,
        caller: &str,
        loaded: &std::collections::BTreeSet<String>,
    ) -> Result<Vec<serde_json::Value>> {
        let caller_identity = self.identity(caller)?;
        let mut rows = Vec::new();
        // 冷成员查询只消费已保存的目录摘要，不逐个激活成员或读取 Current。
        // 摘要只有 durable status，因此这里只投影 lifecycle，不虚构 Turn/Task 运行态计数。
        for (member, closed) in self.factory.directory_rows_for_root(caller).await? {
            if loaded.contains(&member.agent_id) {
                continue;
            }
            if member.session_id != caller_identity.session_id.as_str() {
                continue;
            }
            let mut row = match member.backend {
                crate::AgentBackend::Native { config, status } => {
                    let mut row = super::agents::agent_row(
                        &member.agent_id,
                        member.parent_agent_id.as_deref(),
                        &directory_snapshot(status),
                    )?;
                    row["frozenModel"] = serde_json::to_value(config.route)?;
                    row
                }
                crate::AgentBackend::Acp { .. } => serde_json::json!({
                    "id":member.agent_id, "parentId":member.parent_agent_id,
                    "backend":"acp", "lifecycle":{"kind":if closed {"closed"} else {"cold"}},
                }),
            };
            row["delegationMode"] = serde_json::to_value(member.delegation_mode)?;
            row["delegationPreference"] = serde_json::to_value(member.delegation_preference)?;
            rows.push(row);
        }
        Ok(rows)
    }

    pub(crate) async fn activate_child(
        &self,
        owner: &SessionRuntime,
        caller: &str,
        target: &str,
    ) -> Result<()> {
        // Typed directory/backend admission precedes Native ancestry, workspace, checkpoint and
        // Recovery work. The same resolved activation is consumed by the assembler below.
        let activation = self.factory.activation(target)?;
        self.authorize(caller, target).await?;
        let record = self.record(target).await?;
        self.recovery.ensure_thread_read_access(&record)?;
        let live = owner
            .observed_thread(target)
            .map(|thread| thread.snapshot());
        let resources = self
            .factory
            .verify_execution_workspace(
                &record,
                live.as_ref(),
                crate::studio::thread_factory::ExecutionWorkspaceCheck::Prepare,
            )
            .await;
        self.events.emit_recovery_state(
            self.recovery
                .apply_execution_workspace_check(&record, resources.as_ref().err()),
        );
        resources?;
        self.recovery.ensure_thread_execution_access(&record)?;
        anyhow::ensure!(
            self.direct_child(caller, target)? && !record.archived,
            "only an active direct child can be resumed"
        );
        let activated = owner.activate(activation, self.factory.clone()).await;
        if let Err(error) = activated {
            // An internal scheduling activation is the same product fact as an explicit one, so its
            // failure publishes the member's Recovery diagnosis instead of only returning an error;
            // a missing workspace is never silently rebuilt on this path.
            if let Some(publish) = self.workspace_recovery.clone() {
                let failure = anyhow::Error::from(error);
                // The publisher only observes the failure; the error itself is returned to the
                // caller unchanged by message and cause.
                let reported = anyhow::anyhow!("{failure:#}");
                publish(record.clone(), reported).await;
                return Err(failure);
            }
            return Err(error.into());
        }
        Ok(())
    }

    pub(crate) async fn record(&self, id: &str) -> Result<crate::Thread> {
        // CatalogStore is the directory owner already loaded in RAM. There is no SQL/file read
        // and no fallback through a second product mirror during unpublished preparation.
        self.store
            .read_thread(id)
            .await?
            .map(crate::Thread::from)
            .context("agent product association is missing")
    }
    pub(crate) async fn authorize(
        &self,
        caller: &str,
        target: &str,
    ) -> Result<Vec<crate::AgentId>> {
        let caller = self.identity(caller)?;
        let mut member = self.identity(target)?;
        let mut path = Vec::new();
        loop {
            anyhow::ensure!(
                member.session_id == caller.session_id,
                "agent query target belongs to another tree"
            );
            if path.contains(&member.agent_id) {
                bail!("cyclic agent ancestry");
            }
            path.push(member.agent_id.clone());
            let Some(parent) = member.parent_agent_id else {
                break;
            };
            member = self
                .events
                .member_identity(&caller.session_id, &parent)
                .context("agent parent directory identity is missing")?;
        }
        anyhow::ensure!(
            path.contains(&caller.agent_id),
            "agent query target is not the caller or its descendant"
        );
        path.reverse();
        Ok(path)
    }
}
impl crate::thread_assembler::SessionAssignment {
    pub(crate) fn services(
        config: crate::config::ConfigRuntime,
        store: crate::studio::StudioStore,
        events: crate::studio::ProductEventBus,
        factory: crate::studio::StudioThreadFactory,
        performance: crate::studio::ModelPerformanceOwner,
        recovery: crate::studio::StudioRecoveryRegistry,
        acp_business: crate::studio::runtime::acp_business::AcpBusinessOwner,
    ) -> Self {
        let child_factory = children::ChildFactory::new(children::ConfiguredChildFactory::new(
            config.clone(),
            factory.clone(),
        ));
        Self(AssignmentKind::Installation {
            services: Some(Arc::new(StudioSessionOwner {
                factory,
                config,
                store,
                events,
                performance,
                recovery,

                workspace_recovery: None,
                acp_business: Some(acp_business),
            })),
            child_factory,
        })
    }
}

impl SessionRuntime {
    #[cfg(test)]
    pub(crate) fn set_agent_services(
        &self,
        config: crate::config::ConfigRuntime,
        store: crate::studio::StudioStore,
        events: crate::studio::ProductEventBus,
        factory: crate::studio::StudioThreadFactory,
        performance: crate::studio::ModelPerformanceOwner,
        recovery: crate::studio::StudioRecoveryRegistry,
    ) -> Result<(), ThreadAssemblyError> {
        let mut state = self.0.state();
        if state.close.closing
            || !state.members.entries.is_empty()
            || !state.activation.creating.is_empty()
            || state.agent_services.is_some()
        {
            return Err(ThreadAssemblyError::Closed);
        }
        state.agent_services = Some(Arc::new(StudioSessionOwner {
            factory,
            config,
            store,
            events,
            performance,
            recovery,

            workspace_recovery: None,
            acp_business: None,
        }));
        Ok(())
    }

    pub(crate) fn agent_profiles_snapshot(
        &self,
    ) -> Result<crate::config::AgentProfilesSnapshot, ThreadAssemblyError> {
        let services =
            self.0
                .state()
                .agent_services
                .clone()
                .ok_or_else(|| ThreadAssemblyError::Resource {
                    operation: "read Agent Profile catalog",
                    source: Box::new(std::io::Error::other(
                        "Agent Profile service is not configured",
                    )),
                })?;
        Ok(services.config.agent_profiles_snapshot()?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::StudioStore;
    use crate::test_support::storage::{
        ThreadStorageSink, close_factory, spawn_live_projection_for_thread,
    };
    use crate::thread_assembler::ThreadActivation;
    use base64::Engine as _;
    use pl_core::{
        context::{ContextContent, OpaquePayload},
        model::{
            DynModelSession, Model, ModelError, ModelFactory, ModelRequest, ModelSession,
            ModelStepOutput, PreparedModelCall,
        },
        thread::TurnInput,
    };
    use sea_orm::{Database, SqliteTransactionMode, TransactionOptions, TransactionTrait};
    use std::{
        sync::{Arc, Mutex},
        time::Duration,
    };

    fn context(caller: &str, cancellation: CancellationToken) -> CallContext {
        CallContext {
            thread_id: caller.into(),
            turn_id: "query".into(),
            call_id: "read-saved".into(),
            grant: Default::default(),
            context: Default::default(),
            history_fence: 0,
            model_projection: None,
            tasks: None,
            cancellation,
            extensions: Arc::new(Default::default()),
            catalog: Arc::from([]),
            extension_sequence: 0,
        }
    }

    fn tool(owner: &SessionRuntime) -> Result<QueryTool> {
        let (identity, resources) = {
            let state = owner.0.state();
            let entry = state
                .members
                .entries
                .get("root")
                .context("root is not assembled")?;
            (entry.identity.clone(), entry.native()?.resources.clone())
        };
        let host = owner.native_agent_host(
            &identity,
            &resources,
            &owner.agent_profiles_snapshot()?,
            Default::default(),
        )?;
        Ok(QueryTool {
            definition: ToolDefinition::json(
                "read_agent_session",
                "Read saved history",
                pl_agent_tool::typed::input_schema_for::<SessionInput>(),
            )?,
            host: Arc::new(host),
            kind: Kind::Session,
        })
    }

    fn input(value: serde_json::Value) -> OpaquePayload {
        OpaquePayload::new("application/json", 1, value.to_string()).unwrap()
    }

    async fn query(tool: &QueryTool, value: serde_json::Value) -> Result<AgentSessionPage> {
        let result = tokio::time::timeout(
            Duration::from_secs(5),
            tool.execute(input(value), context("root", CancellationToken::new())),
        )
        .await??;
        Ok(serde_json::from_str(result.payload().content())?)
    }

    fn record(id: &str, parent: Option<&str>, path: &std::path::Path) -> crate::Thread {
        let mut record = crate::Thread::placeholder(id);
        record.workspace_id = "query-project".into();
        record.root_thread_id = "root".into();
        record.parent_thread_id = parent.map(str::to_owned);
        record.workspace_path = path.to_string_lossy().into_owned();
        record
    }

    async fn persist_test_thread(store: &StudioStore, thread: &crate::Thread) -> Result<()> {
        crate::test_support::storage::register_test_thread(store, thread).await
    }

    struct SavedThenBlocked(Arc<Mutex<Option<tokio::sync::oneshot::Sender<()>>>>);
    struct Session {
        first: bool,
        entered: Arc<Mutex<Option<tokio::sync::oneshot::Sender<()>>>>,
    }
    impl Model for SavedThenBlocked {
        async fn open_session(&self) -> Result<DynModelSession, ModelError> {
            Ok(DynModelSession::new(Session {
                first: true,
                entered: self.0.clone(),
            }))
        }
    }
    impl ModelSession for Session {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            let first = std::mem::replace(&mut self.first, false);
            let entered = self.entered.clone();
            let (capture, mut captures) = pl_core::model::CurrentCaptureHandle::channel();
            Ok(PreparedModelCall::new_with_current(async move {
                let accepted = OpaquePayload::text("saved answer");
                if !first {
                    if let Some(entered) = entered.lock().unwrap().take() {
                        let _ = entered.send(());
                    }
                    loop {
                        tokio::select! {
                            () = request.cancellation.cancelled() => break,
                            capture = captures.recv() => {
                                let Some(capture) = capture else { break; };
                                let _ = capture.reply.send(Ok(accepted.clone()));
                            }
                        }
                    }
                }
                pl_core::model::ModelCallExit {
                    result: Ok(ModelStepOutput {
                        turn_action: Default::default(),
                        attempt_id: request.attempt_id,
                        base_context_revision: request.context.revision,
                        content: vec![ContextContent::Text {
                            text: Arc::from("saved answer"),
                        }],
                        tool_calls: vec![],
                        private_context: None,
                        usage: Default::default(),
                    }),
                    current: Some(accepted),
                }
            })
            .with_current_capture(capture))
        }
        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    fn turn(id: &str, cancellation: CancellationToken) -> TurnInput {
        TurnInput {
            turn_id: id.into(),
            attempt_prefix: format!("attempt-{id}"),
            content: vec![ContextContent::Text {
                text: Arc::from("question"),
            }],
            max_model_steps: pl_core::thread::ModelStepLimit::Limited(1.try_into().unwrap()),
            cancellation,
        }
    }

    async fn wait_history_projection(store: &StudioStore, id: &str) -> Result<()> {
        let channel = store.thread_persistence().history_channel(id);
        let mut status = channel.subscribe();
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                {
                    let current = status.borrow_and_update();
                    if let Some(error) = &current.error {
                        anyhow::bail!("history projection failed: {error}");
                    }
                    if current.queued_records == 0 {
                        return Ok::<_, anyhow::Error>(());
                    }
                }
                status
                    .changed()
                    .await
                    .context("history projection status closed")?;
            }
        })
        .await
        .context("history projection did not settle")??;
        Ok(())
    }

    #[tokio::test]
    async fn read_agent_session_returns_saved_page_while_model_and_writer_are_blocked() -> Result<()>
    {
        let dir = tempfile::tempdir()?;
        let store = StudioStore::open(dir.path().join("data/studio.sqlite")).await?;
        let record = record("root", None, dir.path());
        persist_test_thread(&store, &record).await?;
        let fixture = close_factory(&store)?;
        let owner = SessionRuntime::open(crate::SessionId::new("root")?);
        fixture.install(&owner)?;
        let sink = ThreadStorageSink::new(store.clone(), record).await?;
        let projection = spawn_live_projection_for_thread(store.clone(), "root");
        let mut spec = super::super::agents::archive_tests::spec("root".into(), None, dir.path());
        spec.initial_extensions.insert(
            crate::studio::delegation::EXTENSION.into(),
            crate::studio::delegation::encode(Default::default())?,
        );
        spec.history_sink = Some(sink);
        let mut activation = ThreadActivation::native_test("root", None);
        activation.agent.session_id = owner.id().clone();
        owner.install_explicit_activation(activation);
        let root = owner.assemble(spec).await?;
        wait_history_projection(&store, "root").await?;
        let (entered_tx, entered) = tokio::sync::oneshot::channel();
        root.replace_model(ModelFactory::new(SavedThenBlocked(Arc::new(Mutex::new(
            Some(entered_tx),
        )))))
        .await?;
        root.run_turn(turn("saved", CancellationToken::new()))
            .await?;
        root.flush().await?;
        wait_history_projection(&store, "root").await?;
        let tool = tool(&owner)?;
        let before = query(&tool, serde_json::json!({"target":"root", "detail":"full"})).await?;
        assert!(
            !before.items.is_empty(),
            "the original writer must have saved real execution history"
        );
        let path = store.registered_session_paths("root")?.history_database();
        let options = crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::ReadWrite,
            |options| options,
        )
        .await?;
        let blocker = Database::connect(options).await?;
        let cancellation = CancellationToken::new();
        let running = root.run_turn(turn("blocked", cancellation.clone()));
        let read = async {
            entered.await?;
            let locked = blocker
                .begin_with_options(TransactionOptions {
                    sqlite_transaction_mode: Some(SqliteTransactionMode::Immediate),
                    ..Default::default()
                })
                .await?;
            let reader = store.open_history_reader("root").await?;
            let saved = reader
                .events_window(
                    crate::history::HistoryEventsQuery::Originals {
                        scope: crate::ChatScope {
                            query_class: crate::ChatClassFilter::All {},
                            parent_id: None,
                        },
                    },
                    None,
                    None,
                    false,
                    crate::history::HistoryDemand {
                        max_rows: 20,
                        max_bytes: 64 * 1024,
                    },
                )
                .await?;
            tokio::time::timeout(
                Duration::from_secs(5),
                root.queue_runtime_facts(vec![pl_core::thread::RuntimeFact {
                    source_id: "query-pending-save".into(),
                    content: vec![ContextContent::Text {
                        text: Arc::from("blocked behind the writer transaction"),
                    }],
                }]),
            )
            .await
            .context("running owner must admit the pending runtime fact")??;
            let page = query(&tool, serde_json::json!({"target":"root", "detail":"full"})).await;
            let page = page?;
            assert!(page.history_through_seq >= saved.0);
            assert!(page.items.starts_with(&saved.1));
            assert!(page.history_through_seq >= before.history_through_seq);
            let first = query(
                &tool,
                serde_json::json!({"target":"root", "detail":"full", "limit":1}),
            )
            .await?;
            assert_eq!(first.items, page.items[..1]);
            assert!(
                first.has_more,
                "the real execution supplies multiple entries"
            );
            let next = query(
                &tool,
                serde_json::json!({
                    "target":"root", "detail":"full", "limit":1,
                    "cursor":first.next_cursor.context("continuation")?,
                }),
            )
            .await?;
            assert_eq!(next.history_through_seq, first.history_through_seq);
            assert_eq!(next.items, page.items[1..2]);
            assert!(
                query(&tool, serde_json::json!({"target":"root", "limit":0}),)
                    .await
                    .is_err()
            );
            assert_eq!(
                owner.0.state().members.entries.len(),
                1,
                "reading must not activate another execution"
            );
            locked.rollback().await?;
            cancellation.cancel();
            Ok::<_, anyhow::Error>(())
        };
        let (execution, read) = tokio::time::timeout(Duration::from_secs(15), async {
            tokio::join!(running, read)
        })
        .await?;
        read?;
        assert!(
            matches!(execution, Err(pl_core::thread::ThreadError::Cancelled)),
            "the deliberately cancelled model must finish through the typed cancellation path"
        );
        // This fixture owns its projection task instead of installing the product observer's
        // drain hook. Stop the producer, then drain every admitted fact before joining its writer.
        root.close().await?;
        wait_history_projection(&store, "root").await?;
        let closed = owner.close_session().await;
        assert!(closed.is_empty(), "{closed:?}");
        projection.await?;
        blocker.close().await?;
        fixture.shutdown().await?;
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn read_agent_session_preserves_cold_empty_errors_permissions_and_cursor_binding()
    -> Result<()> {
        let dir = tempfile::tempdir()?;
        let store = StudioStore::open(dir.path().join("data/studio.sqlite")).await?;
        for (id, parent) in [
            ("root", None),
            ("cold", Some("root")),
            ("sibling", Some("root")),
        ] {
            persist_test_thread(&store, &record(id, parent, dir.path())).await?;
        }
        let fixture = close_factory(&store)?;
        let owner = SessionRuntime::open(crate::SessionId::new("root")?);
        fixture.install(&owner)?;
        // A cold reader consumes an existing independent History owner. Creating this empty
        // History object does not activate a Current owner or synthesize any session facts.
        store.history("cold").await?.close().await?;
        store.history("sibling").await?.close().await?;
        let mut spec = super::super::agents::archive_tests::spec("root".into(), None, dir.path());
        spec.initial_extensions.insert(
            crate::studio::delegation::EXTENSION.into(),
            crate::studio::delegation::encode(Default::default())?,
        );
        let mut activation = ThreadActivation::native_test("root", None);
        activation.agent.session_id = owner.id().clone();
        owner.install_explicit_activation(activation);
        owner.assemble(spec).await?;
        let tool = tool(&owner)?;
        let page = query(&tool, serde_json::json!({"target":"cold"})).await?;
        assert_eq!(
            (page.history_through_seq, page.items.len(), page.has_more),
            (0, 0, false)
        );
        let path = store.registered_session_paths("cold")?.history_database();
        assert!(
            store
                .state_for("query-project", "cold")?
                .load_current()
                .await?
                .is_none(),
            "an empty History cannot synthesize Current execution facts"
        );
        assert!(owner.thread("cold").is_none());
        let services = owner.0.state().agent_services.clone().unwrap();
        assert!(services.authorize("cold", "sibling").await.is_err());
        assert!(services.authorize("cold", "root").await.is_err());
        let cursor = Cursor {
            database_id: None,
            version: 4,
            target: "cold".into(),
            through: 0,
            order: Order::Descending,
            detail: Detail::Text,
            anchor: 1,
        };
        let cursor =
            base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(serde_json::to_vec(&cursor)?);
        for value in [
            serde_json::json!({"target":"sibling", "cursor":cursor}),
            serde_json::json!({"target":"cold", "cursor":cursor, "order":"ascending"}),
            serde_json::json!({"target":"cold", "cursor":cursor, "detail":"full"}),
            serde_json::json!({"target":"cold", "limit":0}),
            serde_json::json!({"target":"missing"}),
        ] {
            assert!(query(&tool, value).await.is_err());
        }
        let cancellation = CancellationToken::new();
        cancellation.cancel();
        let error = tool
            .execute(
                input(serde_json::json!({"target":"sibling"})),
                context("root", cancellation),
            )
            .await
            .expect_err("cancelled original request");
        assert!(matches!(
            error.source.downcast_ref::<pl_core::thread::ThreadError>(),
            Some(pl_core::thread::ThreadError::Cancelled)
        ));
        let page = query(&tool, serde_json::json!({"target":"sibling"})).await?;
        assert!(page.items.is_empty());
        // Real storage damage remains an error at the tool boundary.
        tokio::fs::create_dir_all(path.parent().unwrap()).await?;
        tokio::fs::write(&path, b"invalid SQLite database").await?;
        let error = query(&tool, serde_json::json!({"target":"cold"}))
            .await
            .expect_err("real storage errors must survive the tool boundary");
        assert!(
            error.chain().any(|source| matches!(
                source.downcast_ref::<crate::history::HistoryError>(),
                Some(crate::history::HistoryError::Database(_))
            )),
            "{error:#}"
        );
        assert!(owner.thread("cold").is_none());
        assert!(owner.thread("sibling").is_none());
        assert!(owner.close_session().await.is_empty());
        fixture.shutdown().await?;
        store.close().await?;
        Ok(())
    }
}
