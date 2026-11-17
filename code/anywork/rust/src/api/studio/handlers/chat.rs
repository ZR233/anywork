//! Independent content/state observations sharing bounded delivery and retained native joins.
mod content_watch;
mod owner;
mod producer;

pub mod timeline;

use std::sync::Arc;

use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::chat;
use crate::api::studio::subscription::{
    error::{close_error, open_error},
    factory::BridgeObservationFactory,
};
use crate::api::studio::types::{
    BridgeChatBatch, BridgeChatScope, BridgeCompletedEntry, BridgeContentManifestPage,
    BridgeContentRange, BridgeContentRef, BridgeContentWindow, BridgeConversationFrame,
    BridgeCurrentCollectionPage, BridgeCurrentCollectionRef, BridgeError, BridgeReadDemand,
    BridgeThreadBusinessRefs,
};
use crate::frb_generated::StreamSink;
use pl_lifecycle::{Managed, ManagedResource};

pub(crate) use owner::ConversationOwner;
use owner::closed;

/// Opaque owner of one captured native feed. Dropping this facade requests cancellation; the opening
/// scope retains the real owner until close confirms every task, query and native observation.
pub struct BridgeConversationFeed {
    inner: Arc<ConversationOwner>,
    managed: Managed<ConversationResource>,
    #[cfg(test)]
    test_scope: Option<pl_lifecycle::ScopeOwner<BridgeError>>,
}

struct ConversationResource(Arc<ConversationOwner>);

impl ManagedResource for ConversationResource {
    type Error = BridgeError;

    fn request_close(&self) {
        self.0.request_close();
    }

    async fn close(&self) -> Result<(), BridgeError> {
        self.0.close().await
    }
}

impl BridgeConversationFeed {
    fn from_managed(managed: Managed<ConversationResource>) -> Self {
        Self {
            inner: Arc::clone(&managed.get().0),
            managed,
            #[cfg(test)]
            test_scope: None,
        }
    }

    #[cfg(test)]
    async fn from_test_owner(inner: Arc<ConversationOwner>) -> Self {
        let (managed, scope) = test_managed_conversation(inner).await;
        let mut facade = Self::from_managed(managed);
        facade.test_scope = Some(scope);
        facade
    }
}

#[cfg(test)]
async fn test_managed_conversation(
    inner: Arc<ConversationOwner>,
) -> (
    Managed<ConversationResource>,
    pl_lifecycle::ScopeOwner<BridgeError>,
) {
    let scope = pl_lifecycle::ScopeOwner::new("test", tokio::runtime::Handle::current());
    let managed = scope
        .handle()
        .open("conversation", move |_| async move {
            Ok(ConversationResource(inner))
        })
        .await
        .unwrap();
    (managed, scope)
}

impl BridgeObservationFactory {
    pub(crate) async fn open_conversation(
        &self,
        thread_id: String,
        scope: BridgeChatScope,
        demand: BridgeReadDemand,
    ) -> Result<BridgeConversationFeed, BridgeError> {
        let source = self.source.clone();
        let managed = self
            .scope
            .open("conversations", move |cancel| async move {
                let feed = source
                    .open_conversation_feed(&thread_id, chat::scope(scope), chat::demand(demand))
                    .await?;
                Ok(ConversationResource(Arc::new(ConversationOwner::new(
                    feed, cancel,
                ))))
            })
            .await
            .map_err(open_error)?;
        Ok(BridgeConversationFeed::from_managed(managed))
    }
}

/// Opens exactly one native content feed, without a second tail or a rebuilt baseline.
/// Cancellation before publication drops the native feed through its own RAII boundary.
pub async fn open_conversation_feed(
    thread_id: String,
    scope: BridgeChatScope,
    demand: BridgeReadDemand,
) -> Result<BridgeConversationFeed, BridgeError> {
    let bridge = active_bridge().await?;
    bridge
        .observation_factory
        .open_conversation(thread_id, scope, demand)
        .await
}

impl BridgeConversationFeed {
    /// Registers one bounded range observation on this facade's original read lease.
    pub async fn open_content_watch(
        &self,
        reference: BridgeContentRef,
        range: BridgeContentRange,
    ) -> Result<String, BridgeError> {
        self.inner.ensure_read_open()?;
        self.inner
            .content()?
            .watches
            .open(
                &self.inner.content()?.reader,
                &self.inner.cancel,
                chat::protocol_content_ref(reference),
                chat::range(range),
            )
            .await
    }

    /// Pulls at most one window. Overlapping reads of the same watch are rejected, not queued.
    pub async fn next_content_window(
        &self,
        watch_id: String,
    ) -> Result<Option<BridgeContentWindow>, BridgeError> {
        self.inner.content()?.watches.next(&watch_id).await
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close_content_watch(&self, watch_id: String) -> Result<(), BridgeError> {
        self.inner.content()?.watches.request_close(&watch_id)
    }

    /// Cancels first, then joins the retained native watch before releasing its identity/capacity.
    pub async fn close_content_watch(&self, watch_id: String) -> Result<(), BridgeError> {
        self.inner.content()?.watches.close(&watch_id).await
    }

    /// Queries share the original read lease, never the producer's native receive/credit mutex.
    pub async fn load_older(
        &self,
        before: String,
        demand: BridgeReadDemand,
    ) -> Result<BridgeChatBatch, BridgeError> {
        self.inner.ensure_read_open()?;
        let batch = self
            .inner
            .content()?
            .reader
            .load_older(&before, chat::demand(demand))
            .await?;
        self.inner.ensure_read_open()?;
        let batch = chat::batch(batch);
        if tracing::enabled!(target: "conversation_work", tracing::Level::DEBUG) {
            use crate::frb_generated::SseEncode as _;
            let mut serializer = flutter_rust_bridge::for_generated::SseSerializer::new();
            batch.clone().sse_encode(&mut serializer);
            tracing::debug!(
                target: "conversation_work",
                thread_id = %self.inner.thread_id,
                trace_id = %self.inner.subscription_id,
                // A normal success uses the same SSE action byte as StreamSink::add.
                frb_encoded_bytes = serializer.cursor.get_ref().len() + 1,
                "FRB page returned"
            );
        }
        Ok(batch)
    }

    /// Reads one immutable completion through this feed's original independent read lease.
    pub async fn read_completed(
        &self,
        record_id: String,
        demand: BridgeReadDemand,
    ) -> Result<BridgeCompletedEntry, BridgeError> {
        self.inner.ensure_read_open()?;
        let entry = self
            .inner
            .content()?
            .reader
            .read_completed(&record_id, chat::demand(demand))
            .await?;
        self.inner.ensure_read_open()?;
        Ok(chat::completed(entry))
    }

    /// Reads business-resource references from the existing independent read lease.
    pub async fn read_business_refs(&self) -> Result<BridgeThreadBusinessRefs, BridgeError> {
        self.inner.ensure_read_open()?;
        let references = self.inner.content()?.reader.read_business_refs().await?;
        self.inner.ensure_read_open()?;
        Ok(chat::business_refs(references))
    }

    pub async fn list_contents(
        &self,
        item_id: String,
        continuation: Option<String>,
        demand: BridgeReadDemand,
    ) -> Result<BridgeContentManifestPage, BridgeError> {
        self.inner.ensure_read_open()?;
        let page = self
            .inner
            .content()?
            .reader
            .list_contents(&item_id, continuation.as_deref(), chat::demand(demand))
            .await?;
        self.inner.ensure_read_open()?;
        Ok(chat::manifest(page))
    }

    pub async fn read_content(
        &self,
        reference: BridgeContentRef,
        range: BridgeContentRange,
    ) -> Result<BridgeContentWindow, BridgeError> {
        self.inner.ensure_read_open()?;
        let window = self
            .inner
            .content()?
            .reader
            .read_content(&chat::protocol_content_ref(reference), chat::range(range))
            .await?;
        self.inner.ensure_read_open()?;
        Ok(chat::window(window))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn thread_id(&self) -> String {
        self.inner.thread_id.clone()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn subscription_id(&self) -> String {
        self.inner.subscription_id.clone()
    }

    /// Installs the sole producer and sink atomically with respect to close. A second consumer is a
    /// Conflict; a sealed handle always returns Cancelled first. Producer exit drops the sink.
    pub async fn events(
        &self,
        sink: StreamSink<BridgeConversationFrame>,
    ) -> Result<(), BridgeError> {
        self.inner.start(sink).await
    }

    /// Acknowledges the sent contiguous prefix. Wrong identity and future sequences are rejected;
    /// repeated old prefixes are idempotent. Closing takes precedence over argument checks.
    #[flutter_rust_bridge::frb(sync)]
    pub fn acknowledge(
        &self,
        subscription_id: String,
        delivery_sequence: u64,
    ) -> Result<(), BridgeError> {
        self.inner.acknowledge(&subscription_id, delivery_sequence)
    }

    /// Seals admission and wakes credit and receive waits without issuing business cancellation.
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.managed.request_close();
    }

    /// Joins retained work and closes native capabilities. Cancelled close waits can be repeated;
    /// failed closes retain the original owner and diagnostic in the observation scope.
    pub async fn close(&self) -> Result<(), BridgeError> {
        self.managed.retry_close().await.map_err(close_error)
    }
}

#[cfg(test)]
pub(crate) mod tests {
    //! Real Runtime fixture shared by owner tests. Only the final Dart port is substituted.
    use anyhow::{Context, Result, ensure};
    use pl_model::{
        config::{AccountConfig, AccountId, ModelRouteConfig},
        model::{ModelInfo, ModelTransportProfile},
        protocol::ProtocolEndpoint,
    };
    use pl_protocol::{
        ThreadNotification, ThreadWorkspaceMode, TurnState,
        studio::{
            CreateThreadRequest, NewThreadModelRoute, StudioPromptInput, SubmitPromptRequest,
        },
    };
    use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step};
    use pl_studio_runtime::{
        ConversationFeed, StudioHostKind, StudioRuntime, StudioRuntimeOptions,
        config::{ConfigPaths, ConfigStore, StudioConfig},
    };

    pub(crate) const MODEL: &str = "bridge-chat-fixture";
    const ACCOUNT: &str = "bridge-chat-fixture";
    const PROMPT: &str = "conversation read lease";
    const INPUT: &str = "input-bridge-chat";
    pub(super) const FOLLOWUP: &str = "conversation live range";

    pub(crate) struct Environment {
        _temp: tempfile::TempDir,
        provider: FixtureServer,
        pub(crate) runtime: StudioRuntime,
        pub(crate) thread_id: String,
    }

    impl Environment {
        pub(crate) async fn new() -> Result<Self> {
            Self::with_followup(None).await
        }

        pub(crate) async fn with_followup(reply: Option<Reply>) -> Result<Self> {
            Self::with_model_followup(reply, Self::model_info()).await
        }

        /// Same real Runtime chain as [`Environment::with_followup`], with fixture-only model metadata
        /// sized for the 128k-reference-token streaming output test. No production budget changes.
        pub(super) async fn with_output_limit_followup(reply: Option<Reply>) -> Result<Self> {
            let mut model = Self::model_info();
            model.context_window = Some(1_050_000);
            model.max_context_window = Some(1_050_000);
            model.max_output_tokens = Some(128_000);
            Self::with_model_followup(reply, model).await
        }

        async fn with_model_followup(reply: Option<Reply>, model: ModelInfo) -> Result<Self> {
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
                let demand = pl_protocol::ReadDemand {
                    max_items: 16,
                    max_bytes: 64 * 1024,
                };
                let current = runtime
                    .open_current_reader(&id, pl_protocol::CURRENT_PROTOCOL_VERSION, demand)
                    .await?;
                let baseline = current.snapshot(demand).await?;
                let mut subscription = current.watch(Some(baseline.revision), demand).await?;
                loop {
                    let update = subscription.next().await?.context("fixture stream ended")?;
                    let turn = match update {
                        pl_protocol::CurrentFrame::Reset { view } => view.state.active_turn,
                        pl_protocol::CurrentFrame::Notification { notification, .. } => {
                            match notification.notification {
                                ThreadNotification::TurnCompleted { turn } => Some(turn),
                                _ => None,
                            }
                        }
                        pl_protocol::CurrentFrame::Projection { .. } => None,
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
                subscription.request_close();
                subscription.close().await?;
                current.request_close();
                current.close().await?;
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

        fn model_info() -> ModelInfo {
            let mut model = ModelInfo::compatible(MODEL);
            model
                .binding
                .set_transport(ModelTransportProfile::responses_http());
            model.capabilities.instruction_snapshot_overrides = true;
            model.base_instructions = "Follow the finite conversation fixture.".into();
            model
        }

        pub(super) async fn feed(&self) -> Result<ConversationFeed> {
            self.runtime
                .open_conversation_feed(
                    &self.thread_id,
                    pl_protocol::ChatScope::conversation(None),
                    pl_protocol::ReadDemand {
                        max_items: 1,
                        max_bytes: 64 * 1024,
                    },
                )
                .await
        }

        pub(crate) async fn submit_followup(&self) -> Result<()> {
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

        pub(crate) fn home_path(&self) -> std::path::PathBuf {
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
}
