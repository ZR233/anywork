use futures::{
    FutureExt,
    future::{BoxFuture, Shared},
};
use pl_protocol::studio::{
    CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, FeedCloseReport, StudioError,
    StudioErrorCode, StudioShutdownIssue,
};
use std::sync::Arc;

pub(super) type Completion = Shared<BoxFuture<'static, Result<(), Arc<tokio::task::JoinError>>>>;
pub(super) fn retain(task: tokio::task::JoinHandle<()>) -> Completion {
    async move { task.await.map_err(Arc::new) }.boxed().shared()
}
pub(super) fn succeeded(task: &Completion) -> bool {
    matches!(task.clone().now_or_never(), Some(Ok(())))
}
pub(super) fn issue(code: &str, message: &str, recovery: CleanupRecovery) -> FeedCloseIssue {
    FeedCloseIssue {
        diagnostic: StudioShutdownIssue {
            stage: "modelsHttp".into(),
            code: code.into(),
            message: message.into(),
            retryable: recovery != CleanupRecovery::Terminal,
            correlation_id: StudioError::internal().correlation_id,
        },
        recovery,
    }
}
pub(super) fn failure(error: StudioError) -> FeedCloseIssue {
    FeedCloseIssue {
        diagnostic: StudioShutdownIssue {
            stage: "modelsHttp".into(),
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
        "The original Models HTTP owner is closing",
        false,
    )
}
pub(super) fn wrong() -> StudioError {
    StudioError::invalid_argument(
        "This original Models HTTP handle has a different named capability",
    )
}
pub(super) fn missing() -> StudioError {
    StudioError::not_found("Models HTTP handle")
}
