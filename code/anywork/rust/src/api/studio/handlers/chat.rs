//! Independent content/state observations sharing bounded delivery and retained native joins.
mod close_failures;
mod content_watch;
mod owner;
mod producer;

pub mod timeline;

use std::sync::Arc;

use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::chat;
use crate::api::studio::types::{
    BridgeChatBatch, BridgeChatScope, BridgeCompletedEntry, BridgeContentManifestPage,
    BridgeContentRange, BridgeContentRef, BridgeContentWindow, BridgeConversationFrame,
    BridgeCurrentCollectionPage, BridgeCurrentCollectionRef, BridgeError, BridgeReadDemand,
    BridgeThreadBusinessRefs,
};
use crate::frb_generated::StreamSink;

pub(crate) use owner::ConversationOwner;
use owner::closed;

/// Opaque owner of one captured native feed. Dropping this facade requests cancellation; the opening
/// registry retains the real owner until close confirms every task, query and native observation.
pub struct BridgeConversationFeed {
    inner: Arc<ConversationOwner>,
}

/// State-only observation. It owns no content reader and does not activate execution.
pub struct BridgeConversationStateFeed {
    inner: Arc<ConversationOwner>,
}

pub async fn open_conversation_state_feed(
    thread_id: String,
) -> Result<BridgeConversationStateFeed, BridgeError> {
    let bridge = active_bridge().await?;
    let cancel = bridge.shutdown.child_token();
    let feed = tokio::select! {
        biased;
        () = cancel.cancelled() => return Err(closed()),
        feed = bridge.studio.open_conversation_state_feed(&thread_id) => feed?,
    };
    let inner = Arc::new(ConversationOwner::new_state(feed, cancel));
    let opening = inner.cancel.clone().drop_guard();
    bridge
        .subscriptions
        .register_conversation(&inner, &bridge.shutdown)?;
    drop(opening.disarm());
    Ok(BridgeConversationStateFeed { inner })
}

impl BridgeConversationStateFeed {
    #[flutter_rust_bridge::frb(sync)]
    pub fn thread_id(&self) -> String {
        self.inner.thread_id.clone()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn subscription_id(&self) -> String {
        self.inner.subscription_id.clone()
    }

    pub async fn events(
        &self,
        sink: StreamSink<BridgeConversationFrame>,
    ) -> Result<(), BridgeError> {
        self.inner.start(sink).await
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn acknowledge(
        &self,
        subscription_id: String,
        delivery_sequence: u64,
    ) -> Result<(), BridgeError> {
        self.inner.acknowledge(&subscription_id, delivery_sequence)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.inner.request_close();
    }

    pub async fn close(&self) -> Result<(), BridgeError> {
        self.inner.close().await
    }
}

impl Drop for BridgeConversationStateFeed {
    fn drop(&mut self) {
        self.inner.request_close();
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
    let cancel = bridge.shutdown.child_token();
    let feed = tokio::select! {
        biased;
        () = cancel.cancelled() => return Err(closed()),
        feed = bridge.studio.open_conversation_feed(
            &thread_id,
            chat::scope(scope),
            chat::demand(demand),
        ) => feed?,
    };
    let inner = Arc::new(ConversationOwner::new(feed, cancel));
    let opening = inner.cancel.clone().drop_guard();
    // Register the owner and its cancellation-driven lifecycle task in one synchronous publication
    // boundary. The opening guard cancels any installed responsibility if publication fails.
    bridge
        .subscriptions
        .register_conversation(&inner, &bridge.shutdown)?;
    drop(opening.disarm());
    Ok(BridgeConversationFeed { inner })
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

    pub async fn page_current(
        &self,
        reference: BridgeCurrentCollectionRef,
        continuation: Option<String>,
        demand: BridgeReadDemand,
    ) -> Result<BridgeCurrentCollectionPage, BridgeError> {
        self.inner.ensure_read_open()?;
        let page = self
            .inner
            .content()?
            .reader
            .page_current(
                &chat::protocol_collection_ref(reference),
                continuation.as_deref(),
                chat::demand(demand),
            )
            .await?;
        self.inner.ensure_read_open()?;
        Ok(chat::collection_page(page))
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
        self.inner.request_close();
    }

    /// Joins retained work and closes native capabilities. Cancelled close waits can be repeated;
    /// failed closes retain the original owner and diagnostic in the opening registry.
    pub async fn close(&self) -> Result<(), BridgeError> {
        self.inner.close().await
    }
}

impl Drop for BridgeConversationFeed {
    fn drop(&mut self) {
        self.inner.request_close();
    }
}

#[cfg(test)]
mod tests {
    //! Real Runtime fixture shared by owner tests. Only the final Dart port is substituted.
    use anyhow::{Context, Result, ensure};
    use pl_model::{
        config::{AccountConfig, AccountId, ModelRouteConfig},
        model::{ModelInfo, ModelTransportProfile},
        protocol::ProtocolEndpoint,
    };
    use pl_protocol::{
        ThreadNotification, ThreadSubscriptionUpdate, ThreadWorkspaceMode, TurnState,
        studio::{
            CreateThreadRequest, NewThreadModelRoute, StudioPromptInput, SubmitPromptRequest,
        },
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
                let mut subscription = runtime.open_conversation_state_feed(&id).await?;
                loop {
                    let update = subscription.recv().await?.context("fixture stream ended")?;
                    let turn = match update {
                        ThreadSubscriptionUpdate::Snapshot {
                            completed_history_version,
                            snapshot,
                        } => {
                            ensure!(
                                completed_history_version == pl_protocol::COMPLETED_HISTORY_VERSION,
                                "snapshot advertised an unsupported completed-history version"
                            );
                            snapshot.active_turn
                        }
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
                subscription.close().await?;
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
}
