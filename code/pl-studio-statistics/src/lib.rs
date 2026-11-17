//! Canonical model-performance domain values and the bounded GUI read feed.
//!
//! The statistics owner publishes immutable material. HTTP product consumers retain their
//! existing complete projection, while native GUI consumers use feed identities and scoped pages.

mod feed;
mod models;

pub use feed::{
    StatisticsEffortPage, StatisticsError, StatisticsFeed, StatisticsFeedHeader,
    StatisticsHistoryPage, StatisticsPublisher, StatisticsReadScope, StatisticsSummary,
    StatisticsSummaryPage,
};
pub use models::{
    MetricAvailability, ModelMatchState, StudioModelPerformanceEffortSummary,
    StudioModelPerformanceSample, StudioModelPerformanceSnapshot, StudioModelPerformanceSummary,
    UsageReportStatus,
};
pub use pl_protocol::FirstOutputSource;
