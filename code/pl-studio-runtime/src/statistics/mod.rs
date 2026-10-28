//! Canonical model-performance values and product statistics APIs.
//!
//! Desktop and HTTP consumers use these same product-domain feeds and bounded reads. Their
//! private runtime implementation owns one projection; no transport-specific publisher mirrors it.

pub use crate::studio::statistics::{
    FeedCloseReport, PerformanceCounters, PerformanceEffortIdentityRead,
    PerformanceEffortIdentityRef, PerformanceEffortRead, PerformanceEffortReadPage,
    PerformanceHistoryEntityRead, PerformanceHistoryEntryPage, PerformanceHistoryFrame,
    PerformanceHistoryReadHeader, PerformanceHistoryReadRef, PerformanceSampleCounters,
    PerformanceSampleIdentityRead, PerformanceSampleIdentityRef, PerformanceSampleRead,
    PerformanceSampleReadPage, PerformanceSummariesEntityRead, PerformanceSummariesEntryPage,
    PerformanceSummariesFrame, PerformanceSummariesReadHeader, PerformanceSummariesReadRef,
    PerformanceSummaryIdentityRead, PerformanceSummaryIdentityRef, PerformanceSummaryRead,
    PerformanceSummaryReadPage, ProductEntityRef, ProductFeedIdentity, ProductReadOrigin,
    ProductReadScopeIdentity, PurposeCostRead, PurposeCostReadPage, RuntimeCostRead,
    RuntimeCostReadPage, SessionCostRead, SessionCostsFrame, SessionCostsReadHeader,
    SessionCostsReadRef, StudioError, StudioPerformanceEffortIdentityRead,
    StudioPerformanceHistoryFeed, StudioPerformanceHistoryRead,
    StudioPerformanceSampleIdentityRead, StudioPerformanceSummariesFeed,
    StudioPerformanceSummariesRead, StudioPerformanceSummaryIdentityRead, StudioSessionCostsFeed,
    StudioSessionCostsRead, TextChunk,
};

mod models;
pub use models::{
    StudioModelPerformanceEffortSummary, StudioModelPerformanceSample,
    StudioModelPerformanceSnapshot, StudioModelPerformanceSummary,
};
