//! Explicit, pure upgrade boundary for model-owned persisted payloads.
//! Normal request reconstruction and receipt readers never call this module.
use super::receipt::{
    FAILURE_RECEIPT_VERSION, ModelCallBinding, ModelFailureReceipt, ModelRequestReceipt,
    ModelResponseReceipt, REQUEST_RECEIPT_VERSION, presentation_item_kind, presentation_part_kind,
};
use crate::{
    completion::CompletionResponse,
    protocol::{ProtocolKind, WireApi},
};
use pl_core::{
    context::ContextContent,
    model::{
        AggregateChannel, ModelFailureKind, ModelProgress, ObservedPart, ObservedPartIdentity,
        ProviderPartIdentity,
    },
};
pub use pl_core::{context::OpaquePayload, model::ModelError};
use pl_protocol::PromptPrefixChangedReason;
use serde::Deserialize;
use std::sync::Arc;
const LEGACY_FAILURE_RECEIPT_VERSION_V3: u32 = 3;
const LEGACY_FAILURE_RECEIPT_VERSION_V2: u32 = 2;
const LEGACY_FAILURE_RECEIPT_VERSION: u32 = 1;
const PRESENTATION_PREVIEW_FORMAT: &str = "pl.model.presentation-item";

/// Validates current model payloads and upgrades historical v2 producer encodings.
///
/// Returns `None` for unrelated formats and already-current, validated payloads. This function
/// has no storage or configuration access. Unknown fields and numeric representations survive
/// outer-object upgrades; embedded provider and tool strings are never parsed or rewritten.
///
/// # Errors
/// Rejects recognized payloads with unsupported versions, conflicting fields or invalid content.
pub fn migrate_payload(payload: &OpaquePayload) -> Result<Option<OpaquePayload>, ModelError> {
    let current = match payload.format() {
        "pl.model.compaction" => {
            match payload.version() {
                2 | 3 => {
                    let value: RawObject = parse(payload.content())?;
                    if payload.version() == 2 {
                        migrate_call_binding(field(&value, "binding")?.get())?;
                    }
                }
                super::compaction::NATIVE_CHECKPOINT_VERSION => {
                    let checkpoint: super::compaction::NativeCheckpoint = parse(payload.content())?;
                    if !matches!(checkpoint.item, crate::completion::ModelContextItem::Compaction { encrypted_content } if !encrypted_content.trim().is_empty())
                    {
                        return Err(invalid("compaction record contains no native checkpoint"));
                    }
                }
                _ => return Err(invalid("unsupported native compaction checkpoint")),
            }
            super::compaction::NATIVE_CHECKPOINT_VERSION
        }
        "pl.model.assistant" => {
            decode_frame_legacy(payload)?;
            FRAME_VERSION
        }
        "pl.model.failure" => {
            decode_failure(payload)?;
            FAILURE_RECEIPT_VERSION
        }
        "pl.model.prepared-request" => {
            match payload.version() {
                1 => {
                    let legacy: LegacyModelRequestReceipt = parse(payload.content())?;
                    legacy.migrate();
                }
                REQUEST_RECEIPT_VERSION => {
                    super::receipt::model_request_receipt(payload)?;
                }
                _ => return Err(invalid("unsupported prepared model request record")),
            }
            REQUEST_RECEIPT_VERSION
        }
        _ => return Ok(None),
    };
    if payload.version() == current {
        return Ok(None);
    }
    let mut value: RawObject = parse(payload.content())?;
    match payload.format() {
        "pl.model.compaction" => {
            if payload.version() == 2 {
                migrate_binding_field(&mut value)?;
            }
            migrate_timing(&mut value)?;
        }
        "pl.model.assistant" if payload.version() == 2 => {
            edit(&mut value, "receipt", migrate_binding_field)?;
        }
        "pl.model.failure" => {
            if payload.version() <= 2 {
                migrate_binding_field(&mut value)?;
            }
            if payload.version() == 1
                && let Some(progress) = decode_failure(payload)?.partial_progress
            {
                // Old opaque previews remain inert extension material; only current parts are read.
                let encoded: RawObject =
                    parse(&serde_json::to_string(&progress).map_err(json_error)?)?;
                edit(&mut value, "partialProgress", |object| {
                    for (key, field) in encoded {
                        put(object, &key, field)?;
                    }
                    Ok(())
                })?;
            }
        }
        "pl.model.prepared-request" => {
            migrate_binding_field(&mut value)?;
            if value.get("prompt").is_some_and(|raw| raw.get() != "null") {
                let binding: RawObject = parse(field(&value, "binding")?.get())?;
                let account_id = field(&binding, "accountId")?.to_owned();
                edit(&mut value, "prompt", |prompt| {
                    prompt.remove("provider");
                    put(prompt, "accountId", account_id)?;
                    rename(prompt, "providerHash", "accountHash")?;
                    rename(prompt, "model", "modelId")?;
                    if prompt
                        .get("prefixChangedReason")
                        .map(|raw| parse::<String>(raw.get()))
                        .transpose()?
                        .as_deref()
                        == Some("providerChanged")
                    {
                        prompt.insert(
                            "prefixChangedReason".into(),
                            serde_json::value::to_raw_value("accountChanged")
                                .map_err(json_error)?,
                        );
                    }
                    Ok(())
                })?;
            }
        }
        _ => {}
    }
    match payload.format() {
        "pl.model.assistant" => {
            edit(&mut value, "receipt", |receipt| {
                edit(receipt, "response", migrate_timing)
            })?;
        }
        "pl.model.failure" => migrate_timing(&mut value)?,
        _ => {}
    }
    let migrated = OpaquePayload::new(
        payload.format(),
        current,
        serde_json::to_string(&value).map_err(json_error)?,
    )
    .map_err(|error| failure(ModelFailureKind::UnsupportedContent, error))?;
    // The new bytes must pass the current decoder before the storage owner can commit them.
    migrate_payload(&migrated)?;
    Ok(Some(migrated))
}

fn parse<T: serde::de::DeserializeOwned>(content: &str) -> Result<T, ModelError> {
    serde_json::from_str(content).map_err(json_error)
}

/// Upgrade only the producer-owned timing object, never provider raw strings or absent timing.
fn migrate_timing(object: &mut RawObject) -> Result<(), ModelError> {
    if object
        .get("timing")
        .is_some_and(|timing| timing.get() != "null")
    {
        edit(object, "timing", |timing| {
            put(
                timing,
                "firstOutputSource",
                serde_json::value::to_raw_value(&pl_protocol::FirstOutputSource::LegacyUnknown)
                    .map_err(json_error)?,
            )
        })?;
    }
    Ok(())
}

fn legacy_timing_content(payload: &OpaquePayload, assistant: bool) -> Result<String, ModelError> {
    let mut object: RawObject = parse(payload.content())?;
    if assistant {
        edit(&mut object, "receipt", |receipt| {
            edit(receipt, "response", migrate_timing)
        })?;
    } else {
        migrate_timing(&mut object)?;
    }
    serde_json::to_string(&object).map_err(json_error)
}
fn json_error(source: serde_json::Error) -> ModelError {
    failure(ModelFailureKind::UnsupportedContent, source)
}
type RawObject = std::collections::BTreeMap<String, Box<serde_json::value::RawValue>>;
fn field<'a>(
    object: &'a RawObject,
    key: &str,
) -> Result<&'a serde_json::value::RawValue, ModelError> {
    object
        .get(key)
        .map(Box::as_ref)
        .ok_or_else(|| invalid("missing producer payload field"))
}
fn edit(
    object: &mut RawObject,
    key: &str,
    change: impl FnOnce(&mut RawObject) -> Result<(), ModelError>,
) -> Result<(), ModelError> {
    let mut nested = parse(field(object, key)?.get())?;
    change(&mut nested)?;
    object.insert(
        key.into(),
        serde_json::value::to_raw_value(&nested).map_err(json_error)?,
    );
    Ok(())
}
fn put(
    object: &mut RawObject,
    key: &str,
    value: Box<serde_json::value::RawValue>,
) -> Result<(), ModelError> {
    // Renamed identity fields are strings, so compare decoded values rather than whitespace.
    if let Some(existing) = object.get(key)
        && parse::<serde_json::Value>(existing.get())? != parse::<serde_json::Value>(value.get())?
    {
        return Err(invalid("conflicting producer payload fields"));
    }
    object.insert(key.into(), value);
    Ok(())
}
fn rename(object: &mut RawObject, old: &str, new: &str) -> Result<(), ModelError> {
    if let Some(value) = object.remove(old) {
        put(object, new, value)?;
    }
    Ok(())
}
/// Upgrades the historical account binding embedded in a host-owned producer receipt.
/// Unknown fields are retained; callers own the enclosing receipt's version and transaction.
///
/// # Errors
/// Rejects invalid historical bindings and conflicting old/current fields.
pub fn migrate_call_binding(content: &str) -> Result<String, ModelError> {
    let legacy: LegacyModelCallBinding = parse(content)?;
    let current = legacy.migrate();
    let mut object = parse(content)?;
    rename(&mut object, "providerInstanceId", "accountId")?;
    rename(&mut object, "requestedModel", "modelId")?;
    rename(&mut object, "protocol", "wireApi")?;
    object.remove("adapter");
    put(
        &mut object,
        "protocol",
        serde_json::value::to_raw_value(&current.protocol).map_err(json_error)?,
    )?;
    serde_json::to_string(&object).map_err(json_error)
}
fn migrate_binding_field(object: &mut RawObject) -> Result<(), ModelError> {
    let migrated = migrate_call_binding(field(object, "binding")?.get())?;
    object.insert(
        "binding".into(),
        serde_json::value::RawValue::from_string(migrated).map_err(json_error)?,
    );
    Ok(())
}
/// Vendor protocol spelling stored by the pre-account binding; decoded only to migrate.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "camelCase")]
enum LegacyProtocolKind {
    #[serde(alias = "open_ai")]
    OpenAi,
    #[serde(alias = "deep_seek")]
    DeepSeek,
    Zhipu,
    #[serde(alias = "mi_mo")]
    MiMo,
    Xai,
    #[serde(alias = "open_ai_compatible")]
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
            timing: None,
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
            timing: None,
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

fn decode_failure(payload: &OpaquePayload) -> Result<ModelFailureReceipt, ModelError> {
    let content = if payload.version() < FAILURE_RECEIPT_VERSION {
        legacy_timing_content(payload, false)?
    } else {
        payload.content().to_owned()
    };
    let receipt = match payload.version() {
        FAILURE_RECEIPT_VERSION | 4 | LEGACY_FAILURE_RECEIPT_VERSION_V3 => {
            serde_json::from_str::<ModelFailureReceipt>(&content)
                .map_err(|source| super::failure(ModelFailureKind::UnsupportedContent, source))
        }
        LEGACY_FAILURE_RECEIPT_VERSION_V2 => {
            let legacy: FailureReceiptV2 = serde_json::from_str(&content)
                .map_err(|source| super::failure(ModelFailureKind::UnsupportedContent, source))?;
            Ok(legacy.migrate())
        }
        LEGACY_FAILURE_RECEIPT_VERSION => {
            let legacy: FailureReceiptV1 = serde_json::from_str(&content)
                .map_err(|source| super::failure(ModelFailureKind::UnsupportedContent, source))?;
            legacy.migrate()
        }
        _ => Err(super::failure(
            ModelFailureKind::UnsupportedContent,
            std::io::Error::other("unsupported model failure receipt"),
        )),
    }?;
    if payload.version() < 4 && receipt.accounting.pricing == pl_protocol::PricingOutcome::NoCharge
    {
        return Err(super::failure(
            ModelFailureKind::UnsupportedContent,
            std::io::Error::other("no-charge accounting requires model failure receipt version 4"),
        ));
    }
    Ok(receipt)
}

use super::{
    codec::{AssistantFrame, FRAME_VERSION},
    failure,
};
use pl_core::model::ModelToolCall;
const LEGACY_FRAME_VERSION_V3: u32 = 3;
const LEGACY_FRAME_VERSION_V2: u32 = 2;
fn invalid(message: &'static str) -> ModelError {
    failure(
        ModelFailureKind::UnsupportedContent,
        std::io::Error::other(message),
    )
}
/// Assistant frame written before the account model-binding field migration.
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyAssistantFrameV2 {
    receipt: LegacyModelResponseReceipt,
    bindings: Vec<ModelToolCall>,
    #[serde(default)]
    compatibility_family: Option<String>,
}

/// Decode a producer-owned frame only at this explicit version boundary.
///
/// Current types carry no serde aliases. The legacy shape keeps the stored isolation namespace,
/// tool bindings, frozen response and opaque vendor output unchanged while converting the
/// binding field names.
fn decode_frame_legacy(payload: &OpaquePayload) -> Result<AssistantFrame, ModelError> {
    let unsupported = || invalid("unsupported or repeated model response receipt");
    let content = if payload.version() < FRAME_VERSION {
        legacy_timing_content(payload, true)?
    } else {
        payload.content().to_owned()
    };
    let frame = match payload.version() {
        FRAME_VERSION | 4 | LEGACY_FRAME_VERSION_V3 => {
            serde_json::from_str::<AssistantFrame>(&content)
                .map_err(|source| failure(ModelFailureKind::UnsupportedContent, source))
        }
        LEGACY_FRAME_VERSION_V2 => {
            let legacy: LegacyAssistantFrameV2 = serde_json::from_str(&content)
                .map_err(|source| failure(ModelFailureKind::UnsupportedContent, source))?;
            Ok(AssistantFrame {
                receipt: legacy.receipt.migrate(),
                bindings: legacy.bindings,
                compatibility_family: legacy.compatibility_family,
            })
        }
        _ => Err(unsupported()),
    }?;
    // v3 has the same field layout, but its Disabled outcome remains historical "not estimated".
    // A new no-charge declaration must never be smuggled into an older producer version.
    if payload.version() < 4
        && frame.receipt.response.accounting.pricing == pl_protocol::PricingOutcome::NoCharge
    {
        return Err(invalid(
            "no-charge accounting requires model response receipt version 4",
        ));
    }
    Ok(frame)
}
