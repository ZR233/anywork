//! Native Mode product projection over the original ConfigRuntime/ThreadModeManager.
mod commands;
mod feed;
mod material;
mod read;
mod scope;
mod source;
pub use feed::StudioModeCatalogFeed;
pub use pl_protocol::products::feed::mode_catalog::ModeCatalogFrame;
pub use pl_protocol::products::identity::{
    ProductEntityRef, ProductFeedIdentity, ProductReadOrigin, ProductReadScopeIdentity,
};
pub use pl_protocol::products::read::modes::*;
pub use pl_protocol::products::references::{ModeCatalogReadRef, ModeCatalogReadTarget};
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
pub use pl_protocol::{
    ThreadModeDefinitionSnapshot, ThreadModeDocument, ThreadModeId, ThreadModeValidationResult,
    WorkflowPreviewRequest, WorkflowPreviewSnapshot,
};
pub use read::StudioModeCatalogRead;
pub(in crate::studio::runtime) use source::ModesSource;
