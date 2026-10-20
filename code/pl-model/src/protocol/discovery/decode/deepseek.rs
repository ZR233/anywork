//! DeepSeek 官方 `/models` 名单：`data`/`id`、自有预算、模态、`effort` 与明确能力。
//! `models`/`slug` 等 OpenAI/Codex 专属形态不是合法 DeepSeek 名单。
use super::reasoning::ReasoningDeclaration;
use super::{
    Capabilities, DiscoveryDialect, ModelCatalogQueryError, Record, nullable, required_id,
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
            display_name: self.display_name.or(self.name),
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
            // 未声明的能力保持未知/本账号定义；不从名字或相邻模型推断图片。
            unknown_default_input: None,
            // 有 effort 候选时 DeepSeek 固定 `thinking.type = enabled` base body。
            thinking_base_body: true,
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
