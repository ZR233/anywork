//! Concrete bot-bound native query owner. Pagination is entirely BotRuntime's frontier.
use pl_studio_runtime::StudioBotConversationsRead;

use super::super::identity::BridgeProductReadScopeIdentity;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use crate::api::studio::convert::runtime::{bridge_conversation_page, protocol_list_conversations};
use crate::api::studio::types::{
    BridgeBotConversationPage, BridgeError, BridgeFeedCloseReport,
    BridgeListBotConversationsRequest,
};

impl ModelsRead for StudioBotConversationsRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        Self::identity(self)
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        Self::ensure_open(self)
    }
    fn request_close(&self) {
        Self::request_close(self);
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        Self::close(self)
    }
}

#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeBotConversationsReadConnection {
    read: ModelsReadHandle<StudioBotConversationsRead>,
    bot_id: String,
}

pub async fn open_bot_conversations(
    bot_id: String,
) -> Result<BridgeBotConversationsReadConnection, BridgeError> {
    let requested = bot_id.clone();
    let read = open_read(move |runtime| runtime.open_bot_conversations(requested)).await?;
    // Check the exact admitted owner, not a later snapshot of another bot.
    if read.query(StudioBotConversationsRead::bot_id)? != bot_id {
        read.request_close();
        return Err(pl_protocol::studio::StudioError::invalid_argument(
            "The native conversation owner belongs to another bot",
        )
        .into());
    }
    Ok(BridgeBotConversationsReadConnection { read, bot_id })
}

impl BridgeBotConversationsReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn bot_id(&self) -> String {
        self.bot_id.clone()
    }
    pub async fn page(
        &self,
        request: BridgeListBotConversationsRequest,
    ) -> Result<BridgeBotConversationPage, BridgeError> {
        let request = protocol_list_conversations(request);
        Ok(bridge_conversation_page(
            self.read.query(move |source| source.page(request))?.await?,
        ))
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}
