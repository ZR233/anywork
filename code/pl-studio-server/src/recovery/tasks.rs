// Reuse the retained JoinHandle completion already used by the Templates transport.
pub(super) use crate::templates::{Completion, failed, finished, retain, succeeded};

use pl_protocol::studio::{
    CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, FeedCloseReport, StudioError,
    StudioErrorCode, StudioShutdownIssue,
};

pub(super) fn issue(code: &str, message: &str, recovery: CleanupRecovery) -> FeedCloseIssue {
    FeedCloseIssue {
        diagnostic: StudioShutdownIssue {
            stage: "recoveryHttp".into(),
            code: code.into(),
            message: message.into(),
            retryable: recovery != CleanupRecovery::Terminal,
            correlation_id: StudioError::internal().correlation_id,
        },
        recovery,
    }
}

pub(super) fn delivery_failure(error: StudioError) -> FeedCloseIssue {
    FeedCloseIssue {
        diagnostic: StudioShutdownIssue {
            stage: "recoveryHttp".into(),
            code: "deliveryFailed".into(),
            message: error.message,
            retryable: error.retryable,
            correlation_id: error.correlation_id,
        },
        recovery: CleanupRecovery::Terminal,
    }
}

pub(super) fn report(id: String, issues: Vec<FeedCloseIssue>) -> FeedCloseReport {
    FeedCloseReport {
        feed_id: id,
        outcome: if issues.is_empty() {
            FeedCloseOutcome::Clean
        } else {
            FeedCloseOutcome::Unresolved { issues }
        },
    }
}

pub(super) fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "The original Recovery HTTP owner is closing",
        false,
    )
}

pub(super) fn not_found() -> StudioError {
    StudioError::not_found("Original Recovery HTTP handle")
}

pub(super) fn wrong_scope() -> StudioError {
    StudioError::invalid_argument(
        "This named query is not supported by the original Recovery scope kind",
    )
}
