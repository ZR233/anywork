use futures::{
    FutureExt,
    future::{BoxFuture, Shared},
};
use pl_protocol::studio::{
    CleanupRecovery, FeedCloseIssue, StudioError, StudioErrorCode, StudioShutdownIssue,
};
use std::sync::Arc;
use tokio::task::{JoinError, JoinHandle};

pub(super) type Completion = Shared<BoxFuture<'static, Result<(), Arc<JoinError>>>>;
pub(super) fn retain(task: JoinHandle<()>) -> Completion {
    async move { task.await.map_err(Arc::new) }.boxed().shared()
}
pub(super) fn succeeded(task: &Completion) -> bool {
    matches!(task.clone().now_or_never(), Some(Ok(())))
}
pub(super) fn finished(task: &Completion) -> bool {
    task.clone().now_or_never().is_some()
}
pub(super) fn failed(task: &Completion) -> bool {
    matches!(task.clone().now_or_never(), Some(Err(_)))
}
pub(super) fn issue(code: &str, message: &str, recovery: CleanupRecovery) -> FeedCloseIssue {
    FeedCloseIssue {
        diagnostic: StudioShutdownIssue {
            stage: "configurationHttp".into(),
            code: code.into(),
            message: message.into(),
            retryable: recovery != CleanupRecovery::Terminal,
            correlation_id: StudioError::internal().correlation_id,
        },
        recovery,
    }
}
pub(super) fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "The original Configuration HTTP owner is closing",
        false,
    )
}
pub(super) fn not_found() -> StudioError {
    StudioError::not_found("Original Configuration HTTP handle")
}
pub(super) fn delivery_error() -> StudioError {
    StudioError::new(
        StudioErrorCode::Unavailable,
        "Configuration HTTP stream sink is unavailable",
        false,
    )
}
