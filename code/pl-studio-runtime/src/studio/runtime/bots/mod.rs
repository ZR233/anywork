//! Bots-only native publication and read owners. BotRuntime remains the business fact owner.
mod feed;
mod read;
mod source;

pub use feed::StudioBotsFeed;
pub use read::{StudioBotConversationsRead, StudioBotsSourceStatusRead};
pub(in crate::studio::runtime) use source::BotsSource;

pub use pl_protocol::products::identity::{
    ProductFeedIdentity, ProductReadOrigin, ProductReadScopeIdentity, ProductSourceStatusRef,
};
pub use pl_protocol::products::read::bots::{
    BotConversationPage, BotsEvent, BotsFrame, BotsHeader, BotsStateSnapshot,
    ListBotConversationsRequest,
};
pub use pl_protocol::products::source::ProductSourceStatusReadHeader;
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
