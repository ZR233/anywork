//! Original Skills product publications, finite delivery and immutable detail capabilities.
mod commands;
mod feed;
mod frames;
mod material;
mod read;
mod scope;
mod source_status;
pub use commands::SkillsDiscovery;
pub(crate) mod source;
pub(crate) mod sources;
pub use feed::StudioSkillsFeed;
pub use pl_protocol::products::feed::skills::SkillsFrame;
pub use pl_protocol::products::identity::{
    ProductEntityRef, ProductFeedIdentity, ProductReadOrigin, ProductReadScopeIdentity,
    ProductSourceStatusRef,
};
pub use pl_protocol::products::read::primitives::TextReadPage;
pub use pl_protocol::products::read::skills::*;
pub use pl_protocol::products::references::{SkillsReadRef, SkillsReadTarget};
pub use pl_protocol::products::source::ProductSourceStatusReadHeader;
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
pub use read::StudioSkillsRead;
pub use source::SkillsSnapshot;
pub use source_status::StudioSkillsSourceStatusRead;
