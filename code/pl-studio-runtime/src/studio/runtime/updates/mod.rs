//! Canonical update products and explicitly started, runtime-owned tasks.
mod feed;
mod material;
mod read;
mod scope;
mod source;
mod task;
pub use feed::StudioUpdatesFeed;
pub use pl_protocol::products::feed::updates::UpdatesFrame;
pub use pl_protocol::products::identity::{
    ProductFeedIdentity, ProductReadOrigin, ProductReadScopeIdentity,
};
pub use pl_protocol::products::read::updates::*;
pub use pl_protocol::products::references::{
    UpdateDetailsReadRef, UpdateErrorReadRef, UpdateOperationReadRef, UpdateSummaryReadRef,
    UpdatesReadRef, UpdatesReadTarget,
};
pub use pl_protocol::products::source::SourceStateErrorRead;
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
pub use read::{
    StudioUpdateDetailsRead, StudioUpdateErrorRead, StudioUpdateOperationRead,
    StudioUpdateSummaryRead, StudioUpdatesRead,
};
pub(in crate::studio::runtime) use source::{UpdatesMaterial, UpdatesSource};
pub use task::StudioUpdateTask;
