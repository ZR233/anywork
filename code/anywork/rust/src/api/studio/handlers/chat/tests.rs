//! Real Runtime fixture shared by owner tests. Only the final Dart port is substituted.
use anyhow::{Context, Result, ensure};
use pl_model::{
    config::{AccountConfig, AccountId, ModelRouteConfig},
    model::{ModelInfo, ModelTransportProfile},
    protocol::ProtocolEndpoint,
};
use pl_protocol::{
    ThreadNotification, ThreadSubscriptionRequest, ThreadSubscriptionUpdate, ThreadWorkspaceMode,
    TurnState,
    studio::{CreateThreadRequest, NewThreadModelRoute, StudioPromptInput, SubmitPromptRequest},
};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step};
use pl_studio_runtime::{
    ConversationFeed, StudioHostKind, StudioRuntime, StudioRuntimeOptions,
    config::{ConfigPaths, ConfigStore, StudioConfig},
};

pub(super) const MODEL: &str = "bridge-chat-fixture";
const ACCOUNT: &str = "bridge-chat-fixture";
const PROMPT: &str = "conversation read lease";
const INPUT: &str = "input-bridge-chat";
pub(super) const FOLLOWUP: &str = "conversation live range";

pub(super) struct Environment {
    _temp: tempfile::TempDir,
    provider: FixtureServer,
    pub(super) runtime: StudioRuntime,
    pub(super) thread_id: String,
}

impl Environment {
    pub(super) async fn new() -> Result<Self> {
        Self::with_followup(None).await
    }

    pub(super) async fn with_followup(reply: Option<Reply>) -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let project = temp.path().join("project");
        std::fs::create_dir(&project)?;
        // Local workspace mode does not create a repository, commit or worktree.
        let mut script = vec![Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT,
            0,
            Reply::Sse(pl_provider_fixture::responses_text(
                "A completed response for independent demand reads.",
                "bridge-chat-answer",
                MODEL,
            )),
        )];
        if let Some(reply) = reply {
            script.push(Step::prompt(Protocol::ResponsesHttp, FOLLOWUP, 1, reply));
        }
        let provider = FixtureServer::start(script).await?;
        let initialized: Result<StudioRuntime> = async {
            let mut config = StudioConfig::default_config()?;
            config.models.accounts.clear();
            let mut model = ModelInfo::compatible(MODEL);
            model
                .binding
                .set_transport(ModelTransportProfile::responses_http());
            model.capabilities.instruction_snapshot_overrides = true;
            model.base_instructions = "Follow the finite conversation fixture.".into();
            config.models.accounts.insert(
                AccountId::new(ACCOUNT)?,
                AccountConfig::from_explicit_models(
                    ProtocolEndpoint::compatible(ACCOUNT, provider.base_url()),
                    vec![model],
                ),
            );
            let route = ModelRouteConfig {
                account_id: AccountId::new(ACCOUNT)?,
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
            Ok(Box::pin(StudioRuntime::initialize(StudioRuntimeOptions {
                studio_home: Some(home),
                host: StudioHostKind::Test,
                ..StudioRuntimeOptions::desktop()
            }))
            .await?)
        }
        .await;
        let runtime = match initialized {
            Ok(runtime) => runtime,
            Err(error) => {
                let cleanup = provider.finish().await;
                return Err(error.context(format!("provider cleanup: {cleanup:?}")));
            }
        };
        let created: Result<String> = async {
            let project = runtime.open_project(&project).await?;
            let started = Box::pin(runtime.create_thread_command(
                project.id,
                CreateThreadRequest {
                    title: Some("Conversation boundary fixture".into()),
                    input: StudioPromptInput {
                        input_id: INPUT.into(),
                        text: PROMPT.into(),
                        attachment_draft_ids: Vec::new(),
                    },
                    mode: pl_protocol::ThreadModeId::simple().to_string(),
                    route: NewThreadModelRoute {
                        account_id: ACCOUNT.into(),
                        model_id: MODEL.into(),
                        effort: None,
                    },
                    delegation_mode: Some(pl_protocol::DelegationMode::Profile),
                    delegation_preference: None,
                    workspace_mode: ThreadWorkspaceMode::Local,
                },
                None,
            ))
            .await?;
            let id = started.thread.id;
            let mut subscription = runtime
                .subscribe_thread(ThreadSubscriptionRequest {
                    thread_id: id.clone(),
                })
                .await?;
            loop {
                let update = subscription.recv().await?.context("fixture stream ended")?;
                let turn = match update {
                    ThreadSubscriptionUpdate::Snapshot { snapshot } => snapshot.active_turn,
                    ThreadSubscriptionUpdate::Notification { notification } => {
                        match notification.notification {
                            ThreadNotification::TurnCompleted { turn } => Some(turn),
                            _ => None,
                        }
                    }
                };
                if let Some(turn) = turn
                    && turn.input_id.as_deref() == Some(INPUT)
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
            drop(subscription);
            runtime.synchronize_thread_observation(&id).await?;
            Ok(id)
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

    pub(super) async fn feed(&self) -> Result<ConversationFeed> {
        self.runtime
            .open_conversation_feed(
                &self.thread_id,
                pl_protocol::ChatScope::Main,
                pl_protocol::ReadDemand {
                    max_items: 1,
                    max_bytes: 64 * 1024,
                },
            )
            .await
    }

    pub(super) async fn submit_followup(&self) -> Result<()> {
        let snapshot = self.runtime.thread_snapshot(&self.thread_id).await?;
        Box::pin(
            self.runtime.submit_prompt_command(
                self.thread_id.clone(),
                SubmitPromptRequest {
                    input: StudioPromptInput {
                        input_id: "input-bridge-live".into(),
                        text: FOLLOWUP.into(),
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

    pub(super) async fn finish(self, result: Result<()>) -> Result<()> {
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
