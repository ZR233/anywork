//! Original Mcp product publications, finite delivery and immutable detail capabilities.
mod commands;
mod feed;
mod frames;
mod material;
mod read;
mod scope;
pub(crate) mod source;
mod source_status;

pub use feed::StudioMcpFeed;
pub use pl_protocol::products::feed::mcp::McpFrame;
pub use pl_protocol::products::identity::{
    ProductEntityRef, ProductFeedIdentity, ProductReadOrigin, ProductReadScopeIdentity,
    ProductSourceStatusRef,
};
pub use pl_protocol::products::read::mcp::*;
pub use pl_protocol::products::read::primitives::TextReadPage;
pub use pl_protocol::products::references::{McpReadRef, McpReadTarget};
pub use pl_protocol::products::source::ProductSourceStatusReadHeader;
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
pub use read::StudioMcpRead;
pub use source::McpSnapshot;
pub use source_status::StudioMcpSourceStatusRead;
