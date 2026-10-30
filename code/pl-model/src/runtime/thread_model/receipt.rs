//! Immutable model-owned provenance and complete normalized responses for history consumers.
use crate::completion::{CompletionPresentationItemKind, CompletionPresentationPartKind};
use crate::{
    completion::CompletionResponse,
    protocol::{ProtocolKind, WireApi},
    runtime::ModelRuntime,
};
use pl_core::model::{
    ModelError, ModelFailureKind, ModelProgress, ModelStepOutput, ObservedItemKind,
    ObservedPartKind,
};
use serde::{Deserialize, Serialize};

/// Current version of the persisted model failure receipt.
pub const FAILURE_RECEIPT_VERSION: u32 = 5;

/// Version of the prepared-request record owned by this crate.
pub const REQUEST_RECEIPT_VERSION: u32 = 2;

/// Non-secret binding facts selected before execution; diagnostic purpose is not a permission.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelCallBinding {
    pub account_id: String,
    pub model_id: String,
    pub protocol: ProtocolKind,
    pub wire_api: WireApi,
    pub isolation: String,
    pub purpose: String,
    /// Context capacity frozen with the bound model before execution; `None` stays unknown.
    ///
    /// Receipts saved before this field existed decode as unknown rather than reading a
    /// current model catalog, and an absent value never falls back to output limits or usage.
    #[serde(default)]
    pub context_window: Option<u64>,
    /// Capacity the bound model itself declares; `None` stays unknown.
    ///
    /// An effective window narrowed by configuration says nothing about the model's own maximum, so
    /// this field is never filled from `context_window`.
    #[serde(default)]
    pub max_context_window: Option<u64>,
    /// Finally resolved automatic compaction threshold of the bound route; `None` stays unknown.
    ///
    /// Requests prepared before this field existed, and auxiliary calls without the owning Thread's
    /// compaction policy, decode as unknown instead of a threshold recomputed from today's settings.
    #[serde(default)]
    pub auto_compact_limit: Option<u64>,
}

impl ModelCallBinding {
    /// Stable provenance for the selected account, vendor protocol, wire API and model.
    pub fn route_identity(&self) -> String {
        crate::runtime::derive_prompt_cache_key(
            &self.isolation,
            &format!("{}:{:?}", self.account_id, self.protocol),
            &self.model_id,
            self.wire_api,
        )
    }

    /// 同一来源绑定可直接重放；跨模型必须携带产生时和目标共同声明的兼容族。
    pub(super) fn native_context_compatible(
        &self,
        target: &Self,
        source_family: Option<&str>,
        target_family: Option<&str>,
    ) -> bool {
        let same_origin = self.account_id == target.account_id
            && self.isolation == target.isolation
            && self.protocol == target.protocol
            && self.wire_api == target.wire_api;
        same_origin
            && (self.model_id == target.model_id
                || source_family
                    .filter(|family| !family.is_empty())
                    .is_some_and(|family| Some(family) == target_family))
    }

    pub(super) fn capture(runtime: &ModelRuntime, purpose: &str) -> Self {
        Self {
            account_id: runtime.account_id().to_owned(),
            model_id: runtime.model().model_id.clone(),
            protocol: runtime.endpoint().protocol,
            wire_api: runtime.model().binding.transport.protocol,
            isolation: crate::runtime::binding_cache_namespace(
                runtime.account_id(),
                runtime.endpoint(),
            ),
            purpose: purpose.to_owned(),
            context_window: runtime.context().context_window,
            max_context_window: runtime.model().max_context_window,
            auto_compact_limit: runtime.context().auto_compact_limit,
        }
    }
}

/// Preserves all normalized response fields, including identifiers, pricing, timing and retries.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelResponseReceipt {
    pub binding: ModelCallBinding,
    pub response: CompletionResponse,
}

/// Complete accounting already observed by the adapter before an invocation failed.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelFailureReceipt {
    pub timing: Option<pl_protocol::InferenceTiming>,
    #[serde(default)]
    pub provider_failure: Option<pl_protocol::ProviderFailure>,
    #[serde(default)]
    pub message: String,
    pub binding: ModelCallBinding,
    pub accounting: crate::completion::InferenceAccounting,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_observation: Option<crate::completion::InferenceModelObservation>,
    /// Full provider output retained independently of the bounded live preview.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub presentation_items: Vec<crate::completion::CompletionPresentationItem>,
    /// Live observation observed before the failure, with its text materialized for this encoding.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub partial_progress: Option<ModelProgress>,
}

/// Reads only the current producer-owned failure receipt, without repricing history.
///
/// # Errors
/// Rejects unsupported receipt encodings; original error details remain available to raw history views.
pub fn model_failure_receipt(
    error: &ModelError,
) -> Result<Option<ModelFailureReceipt>, ModelError> {
    let Some(payload) = &error.details else {
        return Ok(None);
    };
    if payload.format() != "pl.model.failure" {
        return Err(super::failure(
            ModelFailureKind::UnsupportedContent,
            std::io::Error::other("unsupported model failure receipt"),
        ));
    }
    if payload.version() != FAILURE_RECEIPT_VERSION {
        return Err(super::failure(
            ModelFailureKind::UnsupportedContent,
            std::io::Error::other("unsupported model failure receipt"),
        ));
    }
    let receipt = serde_json::from_str(payload.content())
        .map_err(|source| super::failure(ModelFailureKind::UnsupportedContent, source))?;
    Ok(Some(receipt))
}

pub(super) fn presentation_item_kind(kind: CompletionPresentationItemKind) -> ObservedItemKind {
    match kind {
        CompletionPresentationItemKind::Text(channel) => {
            ObservedItemKind::Text(text_channel(channel))
        }
        CompletionPresentationItemKind::Reasoning => ObservedItemKind::Reasoning,
    }
}

pub(super) fn presentation_part_kind(kind: CompletionPresentationPartKind) -> ObservedPartKind {
    match kind {
        CompletionPresentationPartKind::OutputText => ObservedPartKind::OutputText,
        CompletionPresentationPartKind::ReasoningText => ObservedPartKind::ReasoningText,
        CompletionPresentationPartKind::SummaryText => ObservedPartKind::SummaryText,
    }
}

fn text_channel(channel: pl_protocol::trace::TraceTextChannel) -> pl_core::model::ModelTextChannel {
    match channel {
        pl_protocol::trace::TraceTextChannel::User => pl_core::model::ModelTextChannel::User,
        pl_protocol::trace::TraceTextChannel::Commentary => {
            pl_core::model::ModelTextChannel::Commentary
        }
        pl_protocol::trace::TraceTextChannel::Final => pl_core::model::ModelTextChannel::Final,
    }
}

pub(super) fn failure_error(
    binding: ModelCallBinding,
    failure: crate::completion::CompletionFailure,
    partial_progress: Option<ModelProgress>,
) -> ModelError {
    // Only a typed provider code may trigger capacity recovery; arbitrary HTTP 400s and
    // diagnostic wording remain ordinary failures. Invocation cancellation takes precedence.
    let kind = if failure.is_cancelled() {
        pl_core::model::ModelFailureKind::Cancelled
    } else if failure
        .source
        .provider_failure_ref()
        .is_some_and(|failure| failure.code.as_deref() == Some("context_length_exceeded"))
    {
        pl_core::model::ModelFailureKind::ContextLimit
    } else {
        pl_core::model::ModelFailureKind::Unavailable
    };
    let usage = super::usage(&failure.accounting.usage);
    let model_observation = failure.model_observation().cloned();
    let mut failure = failure;
    let receipt = ModelFailureReceipt {
        timing: failure.timing,
        provider_failure: failure.source.provider_failure_ref().cloned(),
        message: failure.source.to_string(),
        binding,
        accounting: (*failure.accounting).clone(),
        model_observation,
        presentation_items: std::mem::take(&mut failure.presentation_items),
        partial_progress: failure
            .partial_progress
            .take()
            .map(|progress| *progress)
            .or(partial_progress),
    };
    let details = failure_details(&receipt);
    ModelError {
        kind,
        details: Some(Box::new(details)),
        usage: Box::new(usage),
        source: Some(Box::new(failure)),
    }
}

pub(super) fn postprocess_failure_error(
    binding: ModelCallBinding,
    accounting: crate::completion::InferenceAccounting,
    model_observation: Option<crate::completion::InferenceModelObservation>,
    timing: Option<pl_protocol::InferenceTiming>,
    partial_progress: Option<ModelProgress>,
    error: ModelError,
) -> ModelError {
    let receipt = ModelFailureReceipt {
        timing,
        provider_failure: None,
        message: error.to_string(),
        binding,
        accounting,
        model_observation,
        presentation_items: Vec::new(),
        partial_progress,
    };
    let details = failure_details(&receipt);
    ModelError {
        kind: error.kind,
        details: Some(Box::new(details)),
        usage: error.usage.clone(),
        source: Some(Box::new(error)),
    }
}

fn failure_details(receipt: &ModelFailureReceipt) -> pl_core::context::OpaquePayload {
    match serde_json::to_string(receipt) {
        Ok(content) => pl_core::context::OpaquePayload::new(
            "pl.model.failure",
            FAILURE_RECEIPT_VERSION,
            content,
        )
        .expect("static format and version are valid"),
        Err(encoding) => pl_core::context::OpaquePayload::new(
            "pl.model.failure-diagnostic",
            1,
            format!(
                "Failure receipt could not be encoded: {encoding}\nObserved receipt: {receipt:?}"
            ),
        )
        .expect("static format and version are valid"),
    }
}

/// Frozen normalized request metadata, including provider-hosted declarations absent from core's registry.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelRequestReceipt {
    pub binding: ModelCallBinding,
    pub tools: Vec<crate::completion::ToolSpec>,
    pub tool_choice: String,
    pub parallel_tool_calls: bool,
    pub reasoning: Option<crate::completion::ReasoningConfig>,
    pub temperature: Option<f32>,
    pub max_tokens: Option<u64>,
    /// Hashes of the normalized request; independent of the stable account cache hint.
    #[serde(default)]
    pub prompt: Option<crate::runtime::ThreadPromptSnapshot>,
}

/// Reads the model-owned record saved at admission, including attempts that failed before any response.
///
/// # Errors
/// Rejects unsupported record formats and malformed payloads without consulting current configuration.
pub fn model_request_receipt(
    payload: &pl_core::context::OpaquePayload,
) -> Result<ModelRequestReceipt, ModelError> {
    if payload.format() != "pl.model.prepared-request" {
        return Err(super::failure(
            pl_core::model::ModelFailureKind::UnsupportedContent,
            std::io::Error::other("unsupported prepared model request record"),
        ));
    }
    match payload.version() {
        REQUEST_RECEIPT_VERSION => serde_json::from_str(payload.content()).map_err(|source| {
            super::failure(pl_core::model::ModelFailureKind::UnsupportedContent, source)
        }),
        _ => Err(super::failure(
            pl_core::model::ModelFailureKind::UnsupportedContent,
            std::io::Error::other("unsupported prepared model request record"),
        )),
    }
}

/// Decodes model output provenance without constructing a provider, tool or physical session.
/// Returns None for outputs from another model implementation with no recognized receipt.
///
/// # Errors
/// Rejects unsupported receipt versions, duplicate frames and inconsistent call associations.
pub fn model_response_receipt(
    output: &ModelStepOutput,
) -> Result<Option<ModelResponseReceipt>, ModelError> {
    super::codec::receipt(output)
}

pub(super) fn request_metadata(
    binding: &ModelCallBinding,
    request: &crate::completion::CompletionRequest,
    prompt: Option<&crate::runtime::ThreadPromptSnapshot>,
) -> Result<pl_core::context::OpaquePayload, ModelError> {
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct RequestMetadata<'a> {
        binding: &'a ModelCallBinding,
        tools: &'a [crate::completion::ToolSpec],
        tool_choice: &'a str,
        parallel_tool_calls: bool,
        reasoning: &'a Option<crate::completion::ReasoningConfig>,
        temperature: Option<f32>,
        max_tokens: Option<u64>,
        prompt: Option<&'a crate::runtime::ThreadPromptSnapshot>,
    }
    let content = serde_json::to_string(&RequestMetadata {
        binding,
        tools: &request.tools,
        tool_choice: &request.tool_choice,
        parallel_tool_calls: request.parallel_tool_calls,
        reasoning: &request.reasoning,
        temperature: request.temperature,
        max_tokens: request.max_tokens,
        prompt,
    })
    .map_err(|source| {
        super::failure(pl_core::model::ModelFailureKind::UnsupportedContent, source)
    })?;
    pl_core::context::OpaquePayload::new(
        "pl.model.prepared-request",
        REQUEST_RECEIPT_VERSION,
        content,
    )
    .map_err(|source| super::failure(pl_core::model::ModelFailureKind::UnsupportedContent, source))
}
