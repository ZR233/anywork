//! OpenAI-compatible 共同契约（MiMo / 自定义）：`data`/`id` 与两族都公开的
//! 预算、模态、能力、reasoning 声明。Codex 的 `models`/`slug`、xAI 的
//! `context_length`/原生价格字段不属于该契约。
use super::reasoning::ReasoningDeclaration;
use super::{
    Capabilities, DiscoveryDialect, ModelCatalogQueryError, Record, nullable, presentation_name,
    required_id,
};
use crate::model::*;
use serde::Deserialize;

#[derive(Deserialize)]
struct Envelope {
    data: Option<Vec<WireRecord>>,
    /// OpenAI/Codex 的富 envelope 名称；出现在本厂商响应中即歧义，不接受。
    models: Option<serde::de::IgnoredAny>,
    error: Option<serde::de::IgnoredAny>,
    success: Option<bool>,
}

#[derive(Deserialize)]
struct WireRecord {
    id: Option<String>,
    name: Option<String>,
    display_name: Option<String>,
    #[serde(default, deserialize_with = "nullable")]
    description: Option<Option<String>>,
    #[serde(default, deserialize_with = "nullable")]
    context_window: Option<Option<u64>>,
    #[serde(default, deserialize_with = "nullable")]
    max_context_window: Option<Option<u64>>,
    #[serde(default, deserialize_with = "nullable")]
    auto_compact_token_limit: Option<Option<u64>>,
    #[serde(default, deserialize_with = "nullable")]
    max_output_tokens: Option<Option<u64>>,
    #[serde(default, deserialize_with = "nullable")]
    default_temperature: Option<Option<f32>>,
    input_modalities: Option<Vec<ModelModality>>,
    output_modalities: Option<Vec<ModelModality>>,
    #[serde(flatten)]
    reasoning: ReasoningDeclaration,
    binding: Option<ModelBinding>,
    capabilities: Option<Capabilities>,
    supports_parallel_tool_calls: Option<bool>,
    supports_function_calling: Option<bool>,
    supports_temperature: Option<bool>,
    supports_streaming: Option<bool>,
    supports_reasoning: Option<bool>,
}

impl WireRecord {
    fn into_record(self) -> Result<Record, ModelCatalogQueryError> {
        let id = required_id(self.id)?;
        Ok(Record {
            id,
            display_name: presentation_name(self.display_name, self.name),
            description: self.description,
            context_window: self.context_window,
            max_context_window: self.max_context_window,
            auto_compact_token_limit: self.auto_compact_token_limit,
            max_output_tokens: self.max_output_tokens,
            default_temperature: self.default_temperature,
            input_modalities: self.input_modalities,
            output_modalities: self.output_modalities,
            supports_parallel_tool_calls: self.supports_parallel_tool_calls,
            supports_function_calling: self.supports_function_calling,
            supports_temperature: self.supports_temperature,
            supports_streaming: self.supports_streaming,
            supports_reasoning: self.supports_reasoning,
            reasoning: self.reasoning,
            binding: self.binding,
            capabilities: self.capabilities,
            pricing: None,
            unknown_default_input: None,
            thinking_base_body: false,
        })
    }
}

pub(super) fn records(
    bytes: &[u8],
    _dialect: DiscoveryDialect,
) -> Result<Vec<Record>, ModelCatalogQueryError> {
    let envelope: Envelope =
        serde_json::from_slice(bytes).map_err(|_| ModelCatalogQueryError::Protocol)?;
    if envelope.error.is_some() || envelope.success == Some(false) || envelope.models.is_some() {
        return Err(ModelCatalogQueryError::Protocol);
    }
    let records = envelope.data.ok_or(ModelCatalogQueryError::Protocol)?;
    records.into_iter().map(WireRecord::into_record).collect()
}
