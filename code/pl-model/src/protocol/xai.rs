//! Native xAI access. Completion uses the same lifecycle and accounting as routed calls.
use crate::completion::{CompletionFailure, CompletionRequest, CompletionResponse};
use crate::runtime::{InvocationRunner, ModelInvocationContext};

/// Concrete xAI client, obtained from the resolved runtime's provider enum.
#[derive(Debug, Clone)]
pub struct XaiClient<'a> {
    pub(crate) runner: &'a InvocationRunner,
}

impl XaiClient<'_> {
    /// Executes a request with shared cancellation, retries and final accounting.
    ///
    /// # Errors
    /// Returns a typed failure retaining any usage reported before the failure.
    pub async fn complete(
        &self,
        request: CompletionRequest,
        context: ModelInvocationContext,
    ) -> Result<CompletionResponse, CompletionFailure> {
        self.runner.complete(request, context).await
    }
}
