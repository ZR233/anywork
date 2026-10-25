//! Immutable model-owned provenance and complete normalized responses for history consumers.
use crate::completion::{CompletionPresentationItemKind, CompletionPresentationPartKind};
use crate::{
    completion::CompletionResponse,
    protocol::{ProtocolKind, WireApi},
    runtime::ModelRuntime,
};
use pl_core::context::{ContextContent, OpaquePayload};
use pl_core::model::{
    AggregateChannel, ModelError, ModelFailureKind, ModelProgress, ModelStepOutput,
    ObservedItemKind, ObservedPart, ObservedPartIdentity, ObservedPartKind, ProviderPartIdentity,
};
use pl_protocol::PromptPrefixChangedReason;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// Version of the persisted model failure receipt owned by this crate.
///
/// Version 2 stores the live observation as typed parts whose text is materialized once, at this
/// encoding boundary. Version 1 kept the previous full-text preview shape; it is upgraded to the
/// current structure only at the persistence decode boundary in [`model_failure_receipt`], so a
/// receipt written by an earlier incarnation of this same data version still recovers every byte of
/// partial text it had already received. Version 3 renamed the account binding; version 4 adds
/// explicit no-charge accounting. The live producer only writes the current version.
pub const FAILURE_RECEIPT_VERSION: u32 = 4;

/// Failure receipt before explicit no-charge accounting, with the same field layout.
const LEGACY_FAILURE_RECEIPT_VERSION_V3: u32 = 3;

/// Failure receipt encoding from before the account model-binding field migration.
const LEGACY_FAILURE_RECEIPT_VERSION_V2: u32 = 2;

/// Failure receipt encoding written before the live observation became typed parts.
const LEGACY_FAILURE_RECEIPT_VERSION: u32 = 1;

/// Version of the prepared-request record owned by this crate.
pub const REQUEST_RECEIPT_VERSION: u32 = 2;

/// Prepared-request encoding from before the account model-binding field migration.
const LEGACY_REQUEST_RECEIPT_VERSION: u32 = 1;

/// Format of the version 1 preview payload holding one encoded presentation item.
const PRESENTATION_PREVIEW_FORMAT: &str = "pl.model.presentation-item";

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

/// Vendor protocol spelling stored by the pre-account binding; decoded only to migrate.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "camelCase")]
enum LegacyProtocolKind {
    OpenAi,
    DeepSeek,
    Zhipu,
    MiMo,
    Xai,
    OpenAiCompatible,
}

impl From<LegacyProtocolKind> for ProtocolKind {
    fn from(kind: LegacyProtocolKind) -> Self {
        match kind {
            LegacyProtocolKind::OpenAi => Self::OpenAi,
            LegacyProtocolKind::DeepSeek => Self::DeepSeek,
            LegacyProtocolKind::Zhipu => Self::Zhipu,
            LegacyProtocolKind::MiMo => Self::MiMo,
            LegacyProtocolKind::Xai => Self::Xai,
            LegacyProtocolKind::OpenAiCompatible => Self::OpenAiCompatible,
        }
    }
}

/// Wire API spelling stored by the pre-account binding; decoded only to migrate.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum LegacyWireApi {
    Responses,
    ChatCompletions,
}

impl From<LegacyWireApi> for WireApi {
    fn from(api: LegacyWireApi) -> Self {
        match api {
            LegacyWireApi::Responses => Self::Responses,
            LegacyWireApi::ChatCompletions => Self::ChatCompletions,
        }
    }
}

/// Binding shape written before the account model-binding field migration.
///
/// This is a decode-only migration boundary: the current types carry no serde aliases, and the
/// stored isolation namespace is copied unchanged so an unchanged account keeps the same physical
/// continuation/cache identity.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct LegacyModelCallBinding {
    provider_instance_id: String,
    requested_model: String,
    adapter: LegacyProtocolKind,
    protocol: LegacyWireApi,
    isolation: String,
    purpose: String,
    #[serde(default)]
    context_window: Option<u64>,
    #[serde(default)]
    max_context_window: Option<u64>,
    #[serde(default)]
    auto_compact_limit: Option<u64>,
}

impl LegacyModelCallBinding {
    /// 仅供同一 `thread_model` 层的 producer 载荷迁移使用。
    pub(super) fn migrate(self) -> ModelCallBinding {
        ModelCallBinding {
            account_id: self.provider_instance_id,
            model_id: self.requested_model,
            protocol: self.adapter.into(),
            wire_api: self.protocol.into(),
            isolation: self.isolation,
            purpose: self.purpose,
            context_window: self.context_window,
            max_context_window: self.max_context_window,
            auto_compact_limit: self.auto_compact_limit,
        }
    }
}

/// Complete response receipt written before the account model-binding field migration.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct LegacyModelResponseReceipt {
    binding: LegacyModelCallBinding,
    response: CompletionResponse,
}

impl LegacyModelResponseReceipt {
    pub(super) fn migrate(self) -> ModelResponseReceipt {
        ModelResponseReceipt {
            binding: self.binding.migrate(),
            response: self.response,
        }
    }
}

/// Failure receipt written before the account model-binding field migration.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct FailureReceiptV2 {
    #[serde(default)]
    provider_failure: Option<pl_protocol::ProviderFailure>,
    #[serde(default)]
    message: String,
    binding: LegacyModelCallBinding,
    accounting: crate::completion::InferenceAccounting,
    #[serde(default)]
    model_observation: Option<crate::completion::InferenceModelObservation>,
    #[serde(default)]
    presentation_items: Vec<crate::completion::CompletionPresentationItem>,
    #[serde(default)]
    partial_progress: Option<ModelProgress>,
}

impl FailureReceiptV2 {
    fn migrate(self) -> ModelFailureReceipt {
        ModelFailureReceipt {
            provider_failure: self.provider_failure,
            message: self.message,
            binding: self.binding.migrate(),
            accounting: self.accounting,
            model_observation: self.model_observation,
            presentation_items: self.presentation_items,
            partial_progress: self.partial_progress,
        }
    }
}

/// prompt snapshot shape written before the account diagnostic identity migration.
///
/// `provider` was the endpoint display name and is not an account identity. It is decoded only
/// to preserve the other frozen facts; the stable account ID comes from the receipt's own
/// binding.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyThreadPromptSnapshot {
    scope: String,
    generation: u64,
    #[allow(dead_code)]
    provider: String,
    #[serde(default)]
    provider_hash: String,
    model: String,
    fixed_prefix_hash: String,
    #[serde(default)]
    fixed_prefix_section_hashes: std::collections::BTreeMap<String, String>,
    #[serde(default)]
    request_properties_hash: String,
    tool_schema_hash: String,
    context_hash: String,
    #[serde(default)]
    prompt_cache_policy: String,
    prefix_changed_reason: LegacyPromptPrefixChangedReason,
    updated_at: i64,
}

/// Old prefix-change reasons, including the retired `providerChanged` spelling.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "camelCase")]
enum LegacyPromptPrefixChangedReason {
    Initial,
    PromptScopeChanged,
    ProviderChanged,
    ModelChanged,
    BaseInstructionsChanged,
    GlobalInstructionsChanged,
    ModeRoleChanged,
    SkillCatalogChanged,
    WorkspaceInstructionsChanged,
    RequestPropertiesChanged,
    FixedPrefixChanged,
    ToolSchemaChanged,
    ContextCompacted,
    ContextAppended,
    ContextRecovered,
}

impl From<LegacyPromptPrefixChangedReason> for PromptPrefixChangedReason {
    fn from(reason: LegacyPromptPrefixChangedReason) -> Self {
        use LegacyPromptPrefixChangedReason as Legacy;
        match reason {
            Legacy::Initial => Self::Initial,
            Legacy::PromptScopeChanged => Self::PromptScopeChanged,
            Legacy::ProviderChanged => Self::AccountChanged,
            Legacy::ModelChanged => Self::ModelChanged,
            Legacy::BaseInstructionsChanged => Self::BaseInstructionsChanged,
            Legacy::GlobalInstructionsChanged => Self::GlobalInstructionsChanged,
            Legacy::ModeRoleChanged => Self::ModeRoleChanged,
            Legacy::SkillCatalogChanged => Self::SkillCatalogChanged,
            Legacy::WorkspaceInstructionsChanged => Self::WorkspaceInstructionsChanged,
            Legacy::RequestPropertiesChanged => Self::RequestPropertiesChanged,
            Legacy::FixedPrefixChanged => Self::FixedPrefixChanged,
            Legacy::ToolSchemaChanged => Self::ToolSchemaChanged,
            Legacy::ContextCompacted => Self::ContextCompacted,
            Legacy::ContextAppended => Self::ContextAppended,
            Legacy::ContextRecovered => Self::ContextRecovered,
        }
    }
}

impl LegacyThreadPromptSnapshot {
    /// `account_id` is the frozen binding fact, never the old display name.
    fn migrate(self, account_id: &str) -> pl_protocol::ThreadPromptSnapshot {
        pl_protocol::ThreadPromptSnapshot {
            scope: self.scope,
            generation: self.generation,
            account_id: account_id.to_owned(),
            // Keep the old fingerprint value verbatim; the next current diagnostics pass
            // rotates naturally through `AccountChanged`.
            account_hash: self.provider_hash,
            model_id: self.model,
            fixed_prefix_hash: self.fixed_prefix_hash,
            fixed_prefix_section_hashes: self.fixed_prefix_section_hashes,
            request_properties_hash: self.request_properties_hash,
            tool_schema_hash: self.tool_schema_hash,
            context_hash: self.context_hash,
            prompt_cache_policy: self.prompt_cache_policy,
            prefix_changed_reason: self.prefix_changed_reason.into(),
            updated_at: self.updated_at,
        }
    }
}

/// Prepared-request record written before the account model-binding field migration.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyModelRequestReceipt {
    binding: LegacyModelCallBinding,
    tools: Vec<crate::completion::ToolSpec>,
    tool_choice: String,
    parallel_tool_calls: bool,
    reasoning: Option<crate::completion::ReasoningConfig>,
    temperature: Option<f32>,
    max_tokens: Option<u64>,
    #[serde(default)]
    prompt: Option<LegacyThreadPromptSnapshot>,
}

impl LegacyModelRequestReceipt {
    fn migrate(self) -> ModelRequestReceipt {
        let binding = self.binding.migrate();
        let prompt = self
            .prompt
            .map(|prompt| prompt.migrate(binding.account_id.as_str()));
        ModelRequestReceipt {
            binding,
            tools: self.tools,
            tool_choice: self.tool_choice,
            parallel_tool_calls: self.parallel_tool_calls,
            reasoning: self.reasoning,
            temperature: self.temperature,
            max_tokens: self.max_tokens,
            prompt,
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

/// Reads a producer-owned failure receipt without repricing history using current configuration.
///
/// The current structure is read directly. A receipt written in the version 1 shape is upgraded here,
/// at the only persistence decode boundary, so the partial text already received is preserved rather
/// than dropped as unsupported content. The live path never sees the legacy shape.
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
    let receipt = match payload.version() {
        FAILURE_RECEIPT_VERSION | LEGACY_FAILURE_RECEIPT_VERSION_V3 => {
            serde_json::from_str::<ModelFailureReceipt>(payload.content())
                .map_err(|source| super::failure(ModelFailureKind::UnsupportedContent, source))
        }
        LEGACY_FAILURE_RECEIPT_VERSION_V2 => {
            let legacy: FailureReceiptV2 = serde_json::from_str(payload.content())
                .map_err(|source| super::failure(ModelFailureKind::UnsupportedContent, source))?;
            Ok(legacy.migrate())
        }
        LEGACY_FAILURE_RECEIPT_VERSION => {
            let legacy: FailureReceiptV1 = serde_json::from_str(payload.content())
                .map_err(|source| super::failure(ModelFailureKind::UnsupportedContent, source))?;
            legacy.migrate()
        }
        _ => Err(super::failure(
            ModelFailureKind::UnsupportedContent,
            std::io::Error::other("unsupported model failure receipt"),
        )),
    }?;
    if payload.version() < FAILURE_RECEIPT_VERSION
        && receipt.accounting.pricing == pl_protocol::PricingOutcome::NoCharge
    {
        return Err(super::failure(
            ModelFailureKind::UnsupportedContent,
            std::io::Error::other("no-charge accounting requires model failure receipt version 4"),
        ));
    }
    Ok(Some(receipt))
}

/// Version 1 failure receipt, decoded only to upgrade it into the current structure.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct FailureReceiptV1 {
    #[serde(default)]
    provider_failure: Option<pl_protocol::ProviderFailure>,
    #[serde(default)]
    message: String,
    binding: LegacyModelCallBinding,
    accounting: crate::completion::InferenceAccounting,
    #[serde(default)]
    model_observation: Option<crate::completion::InferenceModelObservation>,
    #[serde(default)]
    presentation_items: Vec<crate::completion::CompletionPresentationItem>,
    #[serde(default)]
    partial_progress: Option<FailureProgressV1>,
}

/// Version 1 live preview: one channel-aggregate text/reasoning body plus encoded item previews.
#[derive(Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct FailureProgressV1 {
    #[serde(default)]
    content: Vec<ContextContent>,
    #[serde(default)]
    reasoning: Option<OpaquePayload>,
    #[serde(default)]
    presentation: Vec<OpaquePayload>,
}

impl FailureReceiptV1 {
    fn migrate(self) -> Result<ModelFailureReceipt, ModelError> {
        let partial_progress = match self.partial_progress {
            Some(progress) => Some(progress.migrate()?),
            None => None,
        };
        Ok(ModelFailureReceipt {
            provider_failure: self.provider_failure,
            message: self.message,
            binding: self.binding.migrate(),
            accounting: self.accounting,
            model_observation: self.model_observation,
            presentation_items: self.presentation_items,
            partial_progress,
        })
    }
}

impl FailureProgressV1 {
    /// Rebuilds the observed text as current typed parts without consulting current configuration.
    fn migrate(self) -> Result<ModelProgress, ModelError> {
        let mut parts = Vec::new();
        // Version 1 replaced the channel aggregate with item previews as soon as an item closed, so
        // the two shapes never coexist and item previews win when present.
        for payload in &self.presentation {
            if payload.format() != PRESENTATION_PREVIEW_FORMAT || payload.version() != 1 {
                continue;
            }
            let item: crate::completion::CompletionPresentationItem =
                serde_json::from_str(payload.content()).map_err(|source| {
                    super::failure(ModelFailureKind::UnsupportedContent, source)
                })?;
            let item_kind = presentation_item_kind(item.kind);
            let item_id: Arc<str> = Arc::from(item.provider_item_id.as_str());
            for part in &item.parts {
                let identity = ObservedPartIdentity::Provider(ProviderPartIdentity {
                    item_id: item_id.clone(),
                    output_index: item.output_index,
                    item_kind,
                    part: presentation_part_kind(part.kind),
                    content_index: part.content_index,
                });
                parts.push(ObservedPart::new(identity).authorized(&part.text));
            }
        }
        if parts.is_empty() {
            let text = self
                .content
                .iter()
                .filter_map(|content| match content {
                    ContextContent::Text { text } => Some(text.as_ref()),
                    ContextContent::Resource { .. } | ContextContent::Opaque { .. } => None,
                })
                .collect::<String>();
            if !text.is_empty() {
                parts.push(
                    ObservedPart::new(ObservedPartIdentity::Aggregate {
                        channel: AggregateChannel::Text,
                    })
                    .authorized(&text),
                );
            }
            if let Some(reasoning) = self
                .reasoning
                .as_ref()
                .filter(|payload| payload.format() == "text/plain")
                .map(OpaquePayload::content)
                .filter(|text| !text.is_empty())
            {
                parts.push(
                    ObservedPart::new(ObservedPartIdentity::Aggregate {
                        channel: AggregateChannel::Reasoning,
                    })
                    .authorized(reasoning),
                );
            }
        }
        Ok(ModelProgress::new(1, parts))
    }
}

fn presentation_item_kind(kind: CompletionPresentationItemKind) -> ObservedItemKind {
    match kind {
        CompletionPresentationItemKind::Text(channel) => {
            ObservedItemKind::Text(text_channel(channel))
        }
        CompletionPresentationItemKind::Reasoning => ObservedItemKind::Reasoning,
    }
}

fn presentation_part_kind(kind: CompletionPresentationPartKind) -> ObservedPartKind {
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
    partial_progress: Option<ModelProgress>,
    error: ModelError,
) -> ModelError {
    let receipt = ModelFailureReceipt {
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
        LEGACY_REQUEST_RECEIPT_VERSION => {
            let legacy: LegacyModelRequestReceipt = serde_json::from_str(payload.content())
                .map_err(|source| {
                    super::failure(pl_core::model::ModelFailureKind::UnsupportedContent, source)
                })?;
            Ok(legacy.migrate())
        }
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
