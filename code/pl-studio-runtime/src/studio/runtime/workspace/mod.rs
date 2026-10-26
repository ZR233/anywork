//! Workspace captures the existing directory owners; it never owns a writable directory mirror.
mod capture;
mod feed;
mod frames;
mod material;
mod read;
mod records;
mod scope;
mod source;
mod source_status;

pub use feed::{StudioAgentDirectoryFeed, StudioProjectDirectoryFeed, StudioThreadDirectoryFeed};
pub use pl_protocol::products::feed::agent_directory::AgentDirectoryFrame;
pub use pl_protocol::products::feed::project_directory::ProjectDirectoryFrame;
pub use pl_protocol::products::feed::thread_directory::ThreadDirectoryFrame;
pub use pl_protocol::products::identity::{
    ProductCollectionRef, ProductEntityRef, ProductFeedIdentity, ProductReadOrigin,
    ProductReadScopeIdentity, ProductSourceStatusRef,
};
pub use pl_protocol::products::read::workspace::*;
pub use pl_protocol::products::references::{
    AgentDirectoryReadRef, ProjectDirectoryReadRef, ThreadDirectoryReadRef,
    ThreadDirectoryReadTarget,
};
pub use pl_protocol::products::source::ProductSourceStatusReadHeader;
pub use pl_protocol::studio::{
    FeedCloseReport, StudioError, TextChunk, ThreadDirectoryFilter, ThreadDirectoryQuery,
};
pub use pl_protocol::{
    AgentFaultClassification, AgentWorkspaceDisposition, BudgetLimitSnapshot, DelegationMode,
    DelegationPreference, ThreadStatus, ThreadWorkspaceMode,
};
pub use read::{StudioAgentDirectoryRead, StudioProjectDirectoryRead, StudioThreadDirectoryRead};
pub(crate) use source::WorkspaceProductSource;
pub use source_status::StudioWorkspaceSourceStatusRead;

use pl_protocol::studio::StudioErrorCode;

fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "The original Workspace owner is closing",
        false,
    )
}
fn stale() -> StudioError {
    StudioError::new(
        StudioErrorCode::StaleRevision,
        "The original directory frontier changed; refresh its feed",
        true,
    )
}
fn wrong_field() -> StudioError {
    StudioError::invalid_argument("Unknown field, list or entity in this immutable Workspace read")
}
fn next(value: u64) -> Result<u64, StudioError> {
    value.checked_add(1).ok_or_else(|| {
        StudioError::new(
            StudioErrorCode::Overloaded,
            "Workspace identity space is exhausted",
            false,
        )
    })
}
