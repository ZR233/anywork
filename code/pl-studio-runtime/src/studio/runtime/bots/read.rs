//! Real scope/call owners: eight per stable Bots binding, sixty-four runtime-wide calls.
use std::future::Future;
use std::sync::Arc;

use anyhow::Result;
use pl_protocol::products::identity::{ProductReadVersion, ProductResource};

use super::super::read_budget::require_budget;
use super::super::read_scopes::{
    PinnedMaterial, ProductScopeBinding, ReadScopeBudgetKey, ReadScopeOwner,
};
use super::super::{StudioRuntime, read_calls::ReadCalls};
use super::source::BotsStatusMaterial;
use super::{
    BotConversationPage, FeedCloseReport, ListBotConversationsRequest, ProductReadOrigin,
    ProductReadScopeIdentity, ProductSourceStatusReadHeader, ProductSourceStatusRef, StudioError,
    TextChunk,
};

struct BotsScope<M> {
    identity: ProductReadScopeIdentity,
    owner: Arc<ReadScopeOwner>,
    material: Arc<PinnedMaterial<M>>,
    calls: ReadCalls,
}

impl<M: Send + Sync + 'static> BotsScope<M> {
    fn open(
        runtime: &StudioRuntime,
        version: ProductReadVersion,
        binding: &'static str,
        material: M,
    ) -> Result<Self> {
        let origin = runtime.bots_source.origin();
        let identity = ProductReadScopeIdentity {
            scope_id: crate::studio::new_id("bots-read"),
            owner_epoch: origin.owner_epoch.clone(),
            incarnation: origin.incarnation,
            version,
        };
        let group = runtime.read_scopes.group(
            ReadScopeBudgetKey::Product {
                resource: ProductResource::Bots,
                scope: ProductScopeBinding::Named(binding),
            },
            identity.incarnation,
        );
        let (owner, material) = group.open(identity.scope_id.clone(), material)?;
        Ok(Self {
            identity,
            owner,
            material,
            calls: runtime.read_calls.clone(),
        })
    }
    fn request_close(&self) {
        self.owner.request_close();
    }
}

impl<M> Drop for BotsScope<M> {
    fn drop(&mut self) {
        self.owner.request_close();
        self.owner.release_if_joined();
    }
}

pub struct StudioBotsSourceStatusRead {
    scope: BotsScope<Arc<BotsStatusMaterial>>,
}

struct ConversationMaterial {
    bots: crate::bots::BotRuntime,
    bot_id: String,
}
pub struct StudioBotConversationsRead {
    scope: BotsScope<ConversationMaterial>,
    bot_id: String,
}

impl StudioRuntime {
    /// Resolves only actually exposed, still retained status material from this exact source.
    pub fn open_bots_source_status_read(
        &self,
        reference: ProductSourceStatusRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioBotsSourceStatusRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.bots_source.pin_source_status(&origin, reference)?;
            let scope = BotsScope::open(
                &runtime,
                ProductReadVersion::SourceStatus {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                "bots.feed",
                material,
            )?;
            Ok(StudioBotsSourceStatusRead { scope })
        })
    }

    /// Captures only a bot identity and its canonical config revision. `managed`, token/keyring,
    /// network requests and connection startup are deliberately absent from opening.
    pub fn open_bot_conversations(
        &self,
        bot_id: String,
    ) -> impl Future<Output = Result<StudioBotConversationsRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            runtime.bots_source.ensure_open()?;
            let snapshot = runtime.bots.snapshot().await;
            let bot = snapshot
                .bots
                .iter()
                .find(|bot| bot.id == bot_id)
                .ok_or_else(|| StudioError::not_found("bot"))?;
            // Entry identifies this actual native query owner, not a fabricated immutable list.
            let version = ProductReadVersion::Value {
                entry: runtime.observation_ids.next()?,
                revision: bot.config_revision,
            };
            let material = ConversationMaterial {
                bots: runtime.bots.clone(),
                bot_id: bot_id.clone(),
            };
            let scope = BotsScope::open(&runtime, version, "bots.conversations", material)?;
            Ok(StudioBotConversationsRead { scope, bot_id })
        })
    }
}

impl StudioBotsSourceStatusRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity.clone()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.owner.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ProductSourceStatusReadHeader>> + Send + 'static + use<> {
        let material = self.scope.material.clone();
        self.scope.owner.run(&self.scope.calls, async move {
            material.read(|status| {
                require_budget(&status.value)?;
                Ok(status.value.clone())
            })
        })
    }
    /// Canonical Bots source metadata currently has no text fields. Unknown fields stay errors.
    pub fn text(
        &self,
        _field_id: u64,
        _offset: u64,
        _max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope.owner.run(&self.scope.calls, async {
            Err(StudioError::invalid_argument("Bots source status has no text field").into())
        })
    }
    pub fn request_close(&self) {
        self.scope.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
}

impl StudioBotConversationsRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity.clone()
    }
    pub fn bot_id(&self) -> String {
        self.bot_id.clone()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.owner.ensure_open()
    }

    /// Forwards cursor and optional limit unchanged to BotRuntime. The existing query owns
    /// direct/group frontier and token policy; no local sorting, slicing or offset synthesis.
    pub fn page(
        &self,
        request: ListBotConversationsRequest,
    ) -> impl Future<Output = Result<BotConversationPage>> + Send + 'static + use<> {
        let material = self.scope.material.clone();
        self.scope.owner.run(&self.scope.calls, async move {
            let (bots, bot_id) = material.read(|material| {
                if request.bot_id != material.bot_id {
                    return Err(StudioError::invalid_argument(
                        "The conversation request belongs to another bot",
                    ));
                }
                Ok((material.bots.clone(), material.bot_id.clone()))
            })?;
            let page = bots
                .list_conversations(&bot_id, request.cursor.as_deref(), request.limit)
                .await
                .map_err(|error| error.studio_error())?;
            if page.bot_id != bot_id {
                return Err(StudioError::invalid_argument(
                    "The native conversation page belongs to another bot",
                )
                .into());
            }
            require_budget(&page)?;
            Ok(page)
        })
    }
    pub fn request_close(&self) {
        self.scope.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
}
