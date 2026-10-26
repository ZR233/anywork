//! Producer-specific observation failures, separate from actual background task completion.
use std::sync::Arc;

use super::super::background_task::BackgroundTaskFailure;
use super::{Progress, close::CloseRequest, fences::HistoryFenceFailure};
use crate::studio::agent_host::{WriteBehindFlushFailure, WriteBehindRetryFailure};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::studio::runtime) enum RetryPoint {
    Projection,
    SubscriptionEnded,
    FinalWriteBehind,
}

#[derive(Debug, Clone)]
pub(in crate::studio::runtime) enum ProgressFailure {
    Retry {
        point: RetryPoint,
        cause: Arc<anyhow::Error>,
    },
    FinalWriteBehind(WriteBehindFlushFailure),
    // The existing catch discards the payload. This marker does not invent a recovered panic.
    ProjectionPanicked,
}

impl ProgressFailure {
    pub(super) fn retry_point(&self) -> Option<RetryPoint> {
        match self {
            Self::Retry { point, .. } => Some(*point),
            Self::FinalWriteBehind(_) => Some(RetryPoint::FinalWriteBehind),
            Self::ProjectionPanicked => None,
        }
    }
}

impl std::fmt::Display for ProgressFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Retry { point, cause } => write!(f, "observation {point:?} failed: {cause:#}"),
            Self::FinalWriteBehind(cause) => write!(f, "final observation fence failed: {cause}"),
            Self::ProjectionPanicked => f.write_str("Thread product projection panicked"),
        }
    }
}
impl std::error::Error for ProgressFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Retry { cause, .. } => Some(cause.as_ref().as_ref()),
            Self::FinalWriteBehind(cause) => Some(cause),
            Self::ProjectionPanicked => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ObservationPendingStep {
    Projection,
    History,
    WriteBehind,
    FinalState,
    Completion,
    Scopes,
}

#[derive(Debug, Clone)]
#[allow(dead_code)] // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
pub(crate) struct ObservationCloseIssue {
    pub(crate) thread_id: String,
    pub(crate) target: u64,
    pub(in crate::studio::runtime) progress: Progress,
    pub(in crate::studio::runtime) completion: Option<Result<(), Arc<BackgroundTaskFailure>>>,
    pub(in crate::studio::runtime) progress_closed:
        Option<Arc<tokio::sync::watch::error::RecvError>>,
    pub(in crate::studio::runtime) ended_before_final_state: bool,
    pub(in crate::studio::runtime) projection_failed: bool,
    pub(in crate::studio::runtime) history: Option<HistoryFenceFailure>,
    pub(crate) pending: Vec<ObservationPendingStep>,
}

/// An immutable capture of this request's exact owners/fences. The request is not stored back in
/// any Observation, so retaining it for continuation cannot form an owner/failure strong cycle.
#[derive(Clone)]
pub(crate) struct ObservationCloseFailure {
    pub(super) request: Arc<CloseRequest>,
    pub(crate) observations: Vec<ObservationCloseIssue>,
    pub(in crate::studio::runtime) write_behind: Vec<WriteBehindFlushFailure>,
    pub(crate) scope_issues: Vec<pl_protocol::studio::FeedCloseIssue>,
    pub(super) global_scope_issues: Vec<pl_protocol::studio::FeedCloseIssue>,
    pub(in crate::studio::runtime) retry_request: Option<WriteBehindRetryFailure>,
}

impl std::fmt::Debug for ObservationCloseFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ObservationCloseFailure")
            .field("observations", &self.observations)
            .field("write_behind", &self.write_behind)
            .field("scope_issues", &self.scope_issues)
            .field("retry_request", &self.retry_request)
            .finish_non_exhaustive()
    }
}
impl std::fmt::Display for ObservationCloseFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("original Thread observation responsibilities remain unresolved")
    }
}
impl std::error::Error for ObservationCloseFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        if let Some(error) = &self.retry_request {
            return Some(error);
        }
        for issue in &self.observations {
            if let Some(error) = &issue.progress.error {
                return Some(error.as_ref());
            }
            if let Some(Err(error)) = &issue.completion {
                return Some(error.as_ref());
            }
            if let Some(error) = &issue.history {
                return Some(error);
            }
            if let Some(error) = &issue.progress_closed {
                return Some(error.as_ref());
            }
        }
        self.write_behind.first().map(|error| error as _)
    }
}
