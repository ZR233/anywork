//! Canonical completion 响应与 trace 上下文。

use crate::completion::CompletionPresentationItem;
use serde::{Deserialize, Serialize};

use crate::completion::InferenceModelObservation;
use crate::completion::tool_call::ToolCall;
use crate::completion::{InferenceTiming, ResponsesContextItem};
use crate::model::InferenceAccounting;
use pl_protocol::PureError;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CompletionResponse {
    /// Versioned runtime receipts for every settled transport attempt of this invocation.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub settlements: Vec<pl_core::context::OpaquePayload>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_id: Option<String>,
    pub content: Option<String>,
    /// Frozen model history, including commentary that is not part of the final-answer view.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub replay: Option<super::AssistantReplay>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reasoning_content: Option<String>,
    #[serde(default)]
    pub tool_calls: Vec<ToolCall>,
    #[serde(default)]
    pub responses_context_items: Vec<ResponsesContextItem>,
    /// Ordered provider output items, or Chat segments decoded from its complete replay.
    /// Chat segment identities are local display identities and never enter model input.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub presentation_items: Vec<CompletionPresentationItem>,
    #[serde(default)]
    pub orchestration: crate::completion::InferenceOrchestrationMetrics,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timing: Option<InferenceTiming>,
    pub accounting: InferenceAccounting,
    /// Whether the most recent usage report was explicitly terminal on the wire.
    #[serde(default)]
    pub usage_is_terminal: bool,
    pub model: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_observation: Option<InferenceModelObservation>,
    /// Display-only recovery facts; abandoned candidates never become response content.
    #[serde(default)]
    pub observation: pl_core::model::ModelObservation,
}

#[derive(Debug, Clone)]
pub struct CompletionTraceContext {
    pub session_id: String,
    pub turn_id: String,
    pub inference_id: String,
}

/// Invocation failure retaining all service-reported usage received before failure.
///
/// `cancelled` carries the implementation's own observation that this invocation was
/// targeted by a runtime interrupt and unwound through its cancellation branch. It is
/// set only at the observation point that produced the failure; it is never inferred
/// from error text, nor from another signal that merely coincides with the failure.
#[derive(Debug, thiserror::Error)]
#[error("{source}")]
pub struct CompletionFailure {
    #[source]
    pub source: Box<PureError>,
    /// A later repair/save error does not replace the original provider failure.
    pub recovery_error: Option<Box<PureError>>,
    pub settlements: Vec<pl_core::context::OpaquePayload>,
    pub accounting: Box<InferenceAccounting>,
    /// Preserves the latest report's terminal fact even when the request failed.
    pub usage_is_terminal: bool,
    pub timing: Option<Box<InferenceTiming>>,
    pub model_observation: Option<Box<InferenceModelObservation>>,
    /// All provider output items received before this invocation failed.
    pub presentation_items: Vec<CompletionPresentationItem>,
    pub partial_progress: Option<Box<pl_core::model::ModelProgress>>,
    pub cancelled: bool,
}

impl CompletionFailure {
    /// Builds a failure that is explicitly **not** the invocation's own cancellation.
    ///
    /// Use this to preserve the observed accounting when folding a secondary cause (for
    /// example a session-close error) into a failure that was already produced elsewhere.
    /// The cancellation fact cannot be forged here: `new(..).is_cancelled()` is always
    /// `false`, and only pl-model's own cancellation branch may produce a cancelled failure.
    pub fn new(source: PureError, accounting: Box<InferenceAccounting>) -> Self {
        Self {
            source: Box::new(source),
            recovery_error: None,
            settlements: Vec::new(),
            accounting,
            usage_is_terminal: false,
            timing: None,
            model_observation: None,
            presentation_items: Vec::new(),
            partial_progress: None,
            cancelled: false,
        }
    }

    /// Whether this invocation itself terminated because it observed a targeting cancellation.
    ///
    /// Provider failures, timeouts and transport errors keep this `false`, even when a
    /// cancellation happens to arrive around the same time.
    pub fn is_cancelled(&self) -> bool {
        self.cancelled
    }

    pub fn model_observation(&self) -> Option<&InferenceModelObservation> {
        self.model_observation.as_deref()
    }

    /// Retains both the original failure and the local reason recovery could not continue.
    pub fn with_recovery_error(mut self, source: PureError) -> Self {
        self.recovery_error = Some(Box::new(source));
        self
    }

    pub fn with_model_observation(mut self, model_observation: InferenceModelObservation) -> Self {
        self.model_observation = Some(Box::new(model_observation));
        self
    }

    pub fn with_optional_model_observation(
        mut self,
        model_observation: Option<InferenceModelObservation>,
    ) -> Self {
        self.model_observation = model_observation.map(Box::new);
        self
    }

    /// Builds the failure produced by the invocation's own cancellation branch.
    ///
    /// Only the code that drove the call and matched its cancellation branch may use this;
    /// a caller outside pl-model cannot fabricate the cancellation fact.
    pub fn cancelled(source: PureError, accounting: Box<InferenceAccounting>) -> Self {
        Self {
            source: Box::new(source),
            recovery_error: None,
            settlements: Vec::new(),
            accounting,
            usage_is_terminal: false,
            timing: None,
            model_observation: None,
            presentation_items: Vec::new(),
            partial_progress: None,
            cancelled: true,
        }
    }
}

impl From<PureError> for CompletionFailure {
    fn from(source: PureError) -> Self {
        Self {
            source: Box::new(source),
            recovery_error: None,
            settlements: Vec::new(),
            accounting: Box::default(),
            usage_is_terminal: false,
            timing: None,
            model_observation: None,
            presentation_items: Vec::new(),
            partial_progress: None,
            cancelled: false,
        }
    }
}

impl std::ops::Deref for CompletionFailure {
    type Target = PureError;
    fn deref(&self) -> &PureError {
        self.source.as_ref()
    }
}
