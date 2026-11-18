//! Invocation admission, cancellation and final observation handoff.
mod attempt;
mod connection;
mod prepare;
mod recovery;
mod timing;

use super::{ModelInvocationContext, ModelRuntime};
use crate::completion::stream::CompletionEventStream;
use crate::completion::{CompletionFailure, CompletionRequest, CompletionResponse};
use pl_protocol::PureError;
use std::time::Duration;

struct OpenedCompletionStream {
    events: CompletionEventStream,
    sent_model: String,
    idle_timeout: Option<Duration>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum OpenAiTransport {
    ResponsesWebSocket,
    Http,
}

impl OpenAiTransport {
    fn label(self) -> &'static str {
        match self {
            Self::ResponsesWebSocket => "WebSocket",
            Self::Http => "HTTP",
        }
    }

    fn trace_label(self) -> &'static str {
        match self {
            Self::ResponsesWebSocket => "ws",
            Self::Http => "http",
        }
    }
}

impl std::fmt::Debug for ModelRuntime {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ModelRuntime")
            .field("account", &self.account_id)
            .field("model", &self.model.model_id)
            .field("transport", &self.model.binding.transport)
            .field("pricing_mode", &self.pricing_mode)
            .finish_non_exhaustive()
    }
}

impl ModelRuntime {
    pub(super) fn resolve_base_url(&self) -> String {
        self.endpoint.base_url.trim_end_matches('/').to_owned()
    }

    /// Executes a canonical request with session admission, bounded recovery and final accounting.
    ///
    /// # Errors
    /// Returns a typed failure retaining accepted output, usage and cancellation facts.
    pub async fn complete(
        &self,
        request: CompletionRequest,
        mut context: ModelInvocationContext,
    ) -> std::result::Result<CompletionResponse, CompletionFailure> {
        let progress = context
            .progress
            .get_or_insert_with(|| {
                pl_core::model::ModelProgressSender::detached(
                    crate::completion::stream::MAX_COMPLETION_OUTPUT_BYTES as u64,
                )
            })
            .clone();
        // A Thread-owned channel is initialized with its stable turn/attempt live marker. Do not
        // replace it with a default snapshot here: doing so would erase the identity before the
        // first provider event and make a reused invocation look like an unowned observation.
        let caller_cancellation = context.cancellation.take().unwrap_or_default();
        let closing = context.session.closing_token();
        // Propagate caller cancellation synchronously, including when it happens inside an
        // invocation poll (for example while charging a member before sending it). Waiting for
        // the outer select to be polled again would let that same poll send after cancellation.
        // Session close may cancel this child without cancelling the caller's parent token.
        let cancellation = caller_cancellation.child_token();
        context.cancellation = Some(cancellation.clone());
        let current_link = context.current.clone();
        let mut current = current_link.as_ref().and_then(|link| link.take_producer());
        if current_link.is_some() && current.is_none() {
            return Err(CompletionFailure::new(
                PureError::Protocol("current invocation endpoint was already consumed".into()),
                Box::default(),
            ));
        }
        let mut result = {
            let invocation = self.complete_inner(request, context, current.as_mut());
            tokio::pin!(invocation);
            // Cancellation is cooperative: await the same invocation so its partial
            // accounting and transport guards finish before releasing admission.
            tokio::select! {
                biased;
                _ = closing.cancelled() => {
                    cancellation.cancel();
                    invocation.await
                }
                result = &mut invocation => result,
            }
        };
        if let Some(current) = current.as_mut() {
            match current.finish(result.as_ref().err().map(ToString::to_string)) {
                Ok(payload) => current_link
                    .as_ref()
                    .expect("current invocation")
                    .handoff(payload),
                Err(error) if result.is_ok() => {
                    let accounting = result
                        .as_ref()
                        .expect("successful result")
                        .accounting
                        .clone();
                    result = Err(CompletionFailure::new(
                        PureError::Protocol(error.to_string()),
                        Box::new(accounting),
                    ));
                }
                Err(_) => {} // Core rejects an exit without a complete final current payload.
            }
        }
        match &mut result {
            Ok(response) => {
                progress.finish_recovery(pl_core::model::ModelRecoveryPhase::Recovered);
                response.observation = progress.latest().observation().clone();
            }
            Err(error) => {
                let phase = if error.is_cancelled() {
                    pl_core::model::ModelRecoveryPhase::Cancelled
                } else if progress
                    .latest()
                    .observation()
                    .recovery
                    .is_some_and(|status| {
                        status.phase == pl_core::model::ModelRecoveryPhase::Exhausted
                    })
                {
                    pl_core::model::ModelRecoveryPhase::Exhausted
                } else {
                    pl_core::model::ModelRecoveryPhase::Failed
                };
                progress.finish_recovery(phase);
                let latest = progress.latest();
                error.partial_progress = (!latest.is_empty()).then_some(Box::new(latest));
            }
        }
        result
    }
}

#[cfg(test)]
#[path = "invocation/cache_tests.rs"]
mod cache_tests;

#[cfg(test)]
#[path = "invocation/chatgpt_tests.rs"]
mod chatgpt_tests;
