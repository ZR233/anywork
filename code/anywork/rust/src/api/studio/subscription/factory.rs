//! 生命周期受应用观察作用域约束的类型化工厂。

use pl_lifecycle::ScopeHandle;
use pl_studio_runtime::StudioRuntime;

use crate::api::studio::types::BridgeError;

pub(crate) struct BridgeObservationFactory {
    pub(crate) source: StudioRuntime,
    pub(crate) scope: ScopeHandle<BridgeError>,
}

impl BridgeObservationFactory {
    pub(crate) fn new(source: StudioRuntime, scope: ScopeHandle<BridgeError>) -> Self {
        Self { source, scope }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::time::Duration;

    use anyhow::{Context, Result, ensure};
    use futures::poll;
    use pl_lifecycle::ScopeOwner;

    use crate::api::studio::{
        accounts::types::BridgeAccountObservationTarget,
        directory::types::{
            BridgeThreadDirectoryFilter, BridgeThreadDirectoryQuery, BridgeThreadDirectoryWindow,
        },
        types::{BridgeErrorCode, BridgeProductTopic, BridgeReadDemand},
    };

    const MODEL: &str = "bridge-chat-fixture";
    const ACCOUNT: &str = "bridge-chat-fixture";
    const INITIAL_PROMPT: &str = "conversation read lease";
    const INITIAL_INPUT: &str = "input-bridge-chat";
    const FOLLOWUP_PROMPT: &str = "conversation live range";

    /// Isolated real Runtime assembled through public product commands and the existing provider
    /// fixture. `BridgeObservationFactory` itself is the only substituted connection point.
    pub(crate) struct Environment {
        _temp: tempfile::TempDir,
        provider: pl_provider_fixture::FixtureServer,
        pub(crate) runtime: pl_studio_runtime::StudioRuntime,
        pub(crate) thread_id: String,
    }

    impl Environment {
        pub(crate) async fn new() -> Result<Self> {
            Self::with_followup(None).await
        }

        async fn with_followup(reply: Option<pl_provider_fixture::Reply>) -> Result<Self> {
            use pl_model::{
                config::{AccountConfig, AccountId, ModelRouteConfig},
                model::{ModelInfo, ModelTransportProfile},
                protocol::ProtocolEndpoint,
            };
            use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step};
            use pl_studio_runtime::{
                CURRENT_PROTOCOL_VERSION, CreateThreadRequest, CurrentFrame, DelegationMode,
                NewThreadModelRoute, ReadDemand, StudioHostKind, StudioPromptInput, StudioRuntime,
                StudioRuntimeOptions, ThreadNotification, ThreadWorkspaceMode, TurnState,
                config::{ConfigPaths, ConfigStore, StudioConfig},
                mode::ThreadModeId,
            };

            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let project = temp.path().join("project");
            std::fs::create_dir(&project)?;
            let mut script = vec![Step::prompt(
                Protocol::ResponsesHttp,
                INITIAL_PROMPT,
                0,
                Reply::Sse(pl_provider_fixture::responses_text(
                    "A completed response for independent demand reads.",
                    "bridge-chat-answer",
                    MODEL,
                )),
            )];
            if let Some(reply) = reply {
                script.push(Step::prompt(
                    Protocol::ResponsesHttp,
                    FOLLOWUP_PROMPT,
                    1,
                    reply,
                ));
            }
            let provider = FixtureServer::start(script).await?;

            let initialized: Result<pl_studio_runtime::StudioRuntime> = async {
                let mut model = ModelInfo::compatible(MODEL);
                model
                    .binding
                    .set_transport(ModelTransportProfile::responses_http());
                model.capabilities.instruction_snapshot_overrides = true;
                model.base_instructions = "Follow the finite conversation fixture.".into();
                let account_id = AccountId::new(ACCOUNT)?;
                let mut config = StudioConfig::default_config()?;
                config.models.accounts.clear();
                config.models.accounts.insert(
                    account_id.clone(),
                    AccountConfig::from_explicit_models(
                        ProtocolEndpoint::compatible(ACCOUNT, provider.base_url()),
                        vec![model],
                    ),
                );
                let route = ModelRouteConfig {
                    account_id: account_id.clone(),
                    model_id: MODEL.into(),
                    effort: None,
                };
                for selected in config
                    .models
                    .routes
                    .values_mut()
                    .chain(config.mode_model_routes.values_mut())
                {
                    *selected = route.clone();
                }
                ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
                Box::pin(StudioRuntime::initialize(StudioRuntimeOptions {
                    studio_home: Some(home),
                    host: StudioHostKind::Test,
                    ..StudioRuntimeOptions::desktop()
                }))
                .await
            }
            .await;
            let runtime = match initialized {
                Ok(runtime) => runtime,
                Err(error) => {
                    let provider = provider.finish().await;
                    return Err(error.context(format!("provider cleanup: {provider:?}")));
                }
            };

            let created: Result<String> = async {
                let project = runtime.open_project(&project).await?;
                let started = Box::pin(runtime.create_thread_command(
                    project.id,
                    CreateThreadRequest {
                        title: Some("Conversation boundary fixture".into()),
                        input: StudioPromptInput {
                            input_id: INITIAL_INPUT.into(),
                            text: INITIAL_PROMPT.into(),
                            attachment_draft_ids: Vec::new(),
                        },
                        mode: ThreadModeId::simple().label().into(),
                        route: NewThreadModelRoute {
                            account_id: ACCOUNT.into(),
                            model_id: MODEL.into(),
                            effort: None,
                        },
                        delegation_mode: Some(DelegationMode::Profile),
                        delegation_preference: None,
                        workspace_mode: ThreadWorkspaceMode::Local,
                    },
                    None,
                ))
                .await?;
                let thread_id = started.thread.id;
                let demand = ReadDemand {
                    max_items: 16,
                    max_bytes: 64 * 1024,
                };
                let current = runtime
                    .open_current_reader(&thread_id, CURRENT_PROTOCOL_VERSION, demand)
                    .await?;
                let baseline = current.snapshot(demand).await?;
                let mut watch = current.watch(Some(baseline.revision), demand).await?;
                loop {
                    let update = watch
                        .next()
                        .await?
                        .context("fixture Current stream ended")?;
                    let turn = match update {
                        CurrentFrame::Reset { view } => view.state.active_turn,
                        CurrentFrame::Notification { notification, .. } => {
                            match notification.notification {
                                ThreadNotification::TurnCompleted { turn } => Some(turn),
                                _ => None,
                            }
                        }
                        CurrentFrame::Projection { .. } => None,
                    };
                    if let Some(turn) = turn
                        && turn.input_id.as_deref() == Some(INITIAL_INPUT)
                        && turn.state.is_terminal()
                    {
                        ensure!(
                            matches!(turn.state, TurnState::Completed(_)),
                            "fixture failed: {:?}",
                            turn.state
                        );
                        break;
                    }
                }
                watch.request_close();
                watch.close().await?;
                current.request_close();
                current.close().await?;
                runtime.synchronize_thread_observation(&thread_id).await?;
                Ok(thread_id)
            }
            .await;

            match created {
                Ok(thread_id) => Ok(Self {
                    _temp: temp,
                    provider,
                    runtime,
                    thread_id,
                }),
                Err(error) => {
                    let shutdown = runtime.shutdown_runtime().await;
                    let provider = provider.finish().await;
                    Err(error.context(format!(
                        "cleanup: runtime={shutdown:?}; provider={provider:?}"
                    )))
                }
            }
        }

        async fn submit_followup(&self) -> Result<()> {
            use pl_studio_runtime::{StudioPromptInput, SubmitPromptRequest};

            let snapshot = self.runtime.thread_snapshot(&self.thread_id).await?;
            Box::pin(
                self.runtime.submit_prompt_command(
                    self.thread_id.clone(),
                    SubmitPromptRequest {
                        input: StudioPromptInput {
                            input_id: "input-bridge-live".into(),
                            text: FOLLOWUP_PROMPT.into(),
                            attachment_draft_ids: Vec::new(),
                        },
                        expected_model_route_revision: snapshot
                            .model_route
                            .as_ref()
                            .context("fixture model route")?
                            .revision,
                    },
                ),
            )
            .await?;
            Ok(())
        }

        fn home_path(&self) -> std::path::PathBuf {
            self._temp.path().join("home")
        }

        pub(crate) async fn finish(self, result: Result<()>) -> Result<()> {
            let shutdown = self.runtime.shutdown_runtime().await;
            let provider = self.provider.finish().await;
            drop(self.runtime);
            let cleanup = self._temp.close();
            result.context(format!(
                "cleanup: runtime={:?}; provider={:?}; isolated files={cleanup:?}",
                shutdown.as_ref().map(|_| ()),
                provider.as_ref().map(|_| ())
            ))?;
            shutdown?;
            provider?;
            cleanup?;
            Ok(())
        }
    }

    #[tokio::test]
    async fn real_factories_share_shutdown_without_stopping_business_runtime() -> Result<()> {
        let env = Environment::new().await?;
        let result = async {
            let scope = ScopeOwner::new("bridge", tokio::runtime::Handle::current());
            let factory = BridgeObservationFactory::new(env.runtime.clone(), scope.handle());
            let account = factory
                .open_account(BridgeAccountObservationTarget::Summaries)
                .await?;
            let directory = factory
                .open_threads(
                    BridgeThreadDirectoryQuery {
                        workspace_id: None,
                        search: None,
                        archived: false,
                        filter: BridgeThreadDirectoryFilter::All,
                        thread_ids: None,
                        excluded_thread_ids: Vec::new(),
                    },
                    BridgeThreadDirectoryWindow {
                        before: None,
                        limit: 20,
                    },
                )
                .await?;
            let metadata = factory.open_thread(env.thread_id.clone()).await?;
            let statistics = factory.open_statistics().await?;
            let product = factory
                .open_product_topic(BridgeProductTopic::Updater)
                .await?;
            let demand = BridgeReadDemand {
                max_items: 2,
                max_bytes: 64 * 1024,
            };
            let current = factory
                .open_current(
                    env.thread_id.clone(),
                    pl_studio_runtime::CURRENT_PROTOCOL_VERSION,
                    demand,
                )
                .await?;
            let history = factory
                .open_history(
                    env.thread_id.clone(),
                    pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION,
                )
                .await?;

            ensure!(account.next().await?.is_some());
            ensure!(directory.next().await?.is_some());
            ensure!(metadata.next().await?.is_some());
            let mut account_next = Box::pin(account.next());
            let mut directory_next = Box::pin(directory.next());
            ensure!(poll!(account_next.as_mut()).is_pending());
            ensure!(poll!(directory_next.as_mut()).is_pending());
            ensure!(account.next().await.unwrap_err().code == BridgeErrorCode::Busy);
            ensure!(directory.next().await.unwrap_err().code == BridgeErrorCode::Busy);

            scope.request_close();
            let rejected = match factory
                .open_account(BridgeAccountObservationTarget::Summaries)
                .await
            {
                Err(error) => error,
                Ok(_) => anyhow::bail!("a closed scope accepted another account observation"),
            };
            ensure!(rejected.code == BridgeErrorCode::RuntimeStopped);
            ensure!(account_next.await?.is_none());
            ensure!(directory_next.await?.is_none());
            let report = scope
                .close(tokio::time::Instant::now() + Duration::from_secs(10))
                .await;
            ensure!(report.is_clean(), "scope did not close: {report:?}");
            account.close().await?;
            directory.close().await?;
            metadata.close().await?;
            statistics.close().await?;
            product.cancel().await?;
            current.close().await?;
            history.close().await?;
            ensure!(
                env.runtime.runtime_snapshot().await?.state.kind()
                    == pl_studio_runtime::StudioRuntimeStateKind::Ready
            );
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn closing_bridge_observations_keeps_admitted_execution_and_persistence() -> Result<()> {
        use pl_provider_fixture::{ReplyStage, responses_text_chunks};
        use pl_studio_runtime::{ReadDemand, ThreadNotification, TurnState};
        use pl_studio_runtime::{StudioHostKind, StudioRuntime, StudioRuntimeOptions};

        let stage = ReplyStage::new();
        let frames = responses_text_chunks(
            &["execution continues after observation closes"],
            "bridge-observation-close",
            MODEL,
        );
        let reply = stage.gated(frames[..3].to_vec(), frames[3..].to_vec());
        let mut env = Environment::with_followup(Some(reply)).await?;
        let result = tokio::time::timeout(Duration::from_secs(30), async {
            let scope = ScopeOwner::new("bridge", tokio::runtime::Handle::current());
            let factory = BridgeObservationFactory::new(env.runtime.clone(), scope.handle());
            let topic = factory
                .open_product_topic(BridgeProductTopic::Updater)
                .await?;
            let bridge_state = factory
                .open_current(
                    env.thread_id.clone(),
                    pl_studio_runtime::CURRENT_PROTOCOL_VERSION,
                    BridgeReadDemand {
                        max_items: 16,
                        max_bytes: 64 * 1024,
                    },
                )
                .await?;
            // 独立状态读取只用于核对原业务执行，不属于待关闭的桥接作用域。
            let demand = ReadDemand {
                max_items: 16,
                max_bytes: 64 * 1024,
            };
            let state = env
                .runtime
                .open_current_reader(
                    &env.thread_id,
                    pl_studio_runtime::CURRENT_PROTOCOL_VERSION,
                    demand,
                )
                .await?;
            let baseline = state.snapshot(demand).await?;
            let mut state = state.watch(Some(baseline.revision), demand).await?;
            env.submit_followup().await?;
            stage.wait_reached().await;
            let before = env.runtime.thread_snapshot(&env.thread_id).await?;
            let active = before.active_turn.context("admitted turn")?;
            ensure!(active.input_id.as_deref() == Some("input-bridge-live"));
            ensure!(!active.state.is_terminal());

            scope.request_close();
            let report = scope
                .close(tokio::time::Instant::now() + Duration::from_secs(10))
                .await;
            ensure!(report.is_clean(), "bridge scope did not close: {report:?}");
            topic.cancel().await?;
            bridge_state.close().await?;
            let after = env.runtime.thread_snapshot(&env.thread_id).await?;
            let still_running = after.active_turn.context("original turn remains active")?;
            ensure!(still_running.id == active.id && !still_running.state.is_terminal());

            let title = "观察关闭后仍可保存";
            env.runtime
                .rename_thread(
                    "observer-close-rename".into(),
                    env.thread_id.clone(),
                    title.into(),
                )
                .await?;
            stage.release();
            let completed_id = loop {
                let update = state.next().await?.context("Current watch ended")?;
                let turn = match update {
                    pl_studio_runtime::CurrentFrame::Reset { view } => view.state.active_turn,
                    pl_studio_runtime::CurrentFrame::Notification { notification, .. } => {
                        match notification.notification {
                            ThreadNotification::TurnCompleted { turn } => Some(turn),
                            _ => None,
                        }
                    }
                    pl_studio_runtime::CurrentFrame::Projection { .. } => None,
                };
                if let Some(turn) = turn
                    && turn.id == active.id
                    && turn.state.is_terminal()
                {
                    ensure!(matches!(turn.state, TurnState::Completed(_)));
                    break turn.id;
                }
            };
            state.request_close();
            state.close().await?;
            env.runtime
                .synchronize_thread_observation(&env.thread_id)
                .await?;
            drop(factory);
            env.runtime.shutdown_runtime().await?;
            env.runtime = StudioRuntime::initialize(StudioRuntimeOptions {
                studio_home: Some(env.home_path()),
                host: StudioHostKind::Test,
                ..StudioRuntimeOptions::desktop()
            })
            .await?;
            ensure!(env.runtime.read_thread(&env.thread_id).await?.title == title);
            let history = env
                .runtime
                .open_history_reader(
                    &env.thread_id,
                    pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION,
                )
                .await?;
            let page = history
                .turns_page(
                    None,
                    None,
                    pl_studio_runtime::history::HistoryDemand {
                        max_rows: 100,
                        max_bytes: 256 * 1024,
                    },
                )
                .await?;
            ensure!(
                page.entries.iter().any(|entry| {
                    matches!(
                        &entry.head,
                        pl_studio_runtime::history::HistoryRowHead::Turn(turn)
                            if turn.turn_id == completed_id
                    )
                }),
                "completed turn was not recovered from durable history"
            );
            history.request_close();
            history.close().await?;
            Ok(())
        })
        .await
        .context("bridge observation lifecycle exceeded its test budget")
        .and_then(|result| result);
        stage.release();
        env.finish(result).await
    }
}
