//! Read-only product projections of the single ModelPerformanceOwner.
mod feed;
mod material;
mod read;
mod scope;
mod source;
pub use feed::{
    StudioPerformanceHistoryFeed, StudioPerformanceSummariesFeed, StudioSessionCostsFeed,
};
pub use pl_protocol::products::feed::performance_history::PerformanceHistoryFrame;
pub use pl_protocol::products::feed::performance_summaries::PerformanceSummariesFrame;
pub use pl_protocol::products::feed::session_costs::SessionCostsFrame;
pub use pl_protocol::products::identity::{
    ProductEntityRef, ProductFeedIdentity, ProductReadOrigin, ProductReadScopeIdentity,
};
pub use pl_protocol::products::read::statistics::*;
pub use pl_protocol::products::references::{
    PerformanceEffortIdentityRef, PerformanceHistoryReadRef, PerformanceSampleIdentityRef,
    PerformanceSummariesReadRef, PerformanceSummaryIdentityRef, SessionCostsReadRef,
};
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
pub use read::{
    StudioPerformanceEffortIdentityRead, StudioPerformanceHistoryRead,
    StudioPerformanceSampleIdentityRead, StudioPerformanceSummariesRead,
    StudioPerformanceSummaryIdentityRead, StudioSessionCostsRead,
};
pub(in crate::studio::runtime) use source::StatisticsSource;
