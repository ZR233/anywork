//! Original Lsp product publications, finite delivery and immutable detail capabilities.
mod commands;
mod feed;
mod frames;
mod material;
mod read;
mod scope;
pub(crate) mod source;
mod source_status;

pub use feed::StudioLspFeed;
pub use pl_protocol::products::feed::lsp::LspFrame;
pub use pl_protocol::products::identity::{
    ProductEntityRef, ProductFeedIdentity, ProductReadOrigin, ProductReadScopeIdentity,
    ProductSourceStatusRef,
};
pub use pl_protocol::products::read::lsp::*;
pub use pl_protocol::products::read::primitives::TextReadPage;
pub use pl_protocol::products::references::{LspReadRef, LspReadTarget};
pub use pl_protocol::products::source::ProductSourceStatusReadHeader;
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
pub use read::StudioLspRead;
pub use source::LspSnapshot;
pub use source_status::StudioLspSourceStatusRead;
