//! OpenAI Models API (`data`/`id`) and the currently deployed Codex rich `models`/`slug`
//! declaration. Codex-only defaults belong to this boundary only.
use super::reasoning::ReasoningDeclaration;
use super::{
    Capabilities, DiscoveryDialect, ModelCatalogQueryError, Record, nullable, presentation_name,
};
use crate::model::*;
use serde::Deserialize;

#[derive(Deserialize)]
struct Envelope {
    data: Option<Vec<WireRecord>>,
    models: Option<Vec<WireRecord>>,
    error: Option<serde::de::IgnoredAny>,
    success: Option<bool>,
}

#[derive(Deserialize)]
struct WireRecord {
    id: Option<String>,
    #[serde(rename = "modelId", alias = "model_id")]
    model_id: Option<String>,
    slug: Option<String>,
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
    fn identifier(&self) -> Result<String, ModelCatalogQueryError> {
        if let (Some(a), Some(b)) = (&self.model_id, &self.id)
            && a != b
        {
            return Err(ModelCatalogQueryError::Protocol);
        }
        let wire_id = self.model_id.as_deref().or(self.id.as_deref());
        let id = match (wire_id, self.slug.as_deref()) {
            (Some(id), None) | (None, Some(id)) => id,
            (Some(id), Some(slug)) if id == slug => id,
            _ => return Err(ModelCatalogQueryError::Protocol),
        };
        if id.trim().is_empty() {
            return Err(ModelCatalogQueryError::Protocol);
        }
        Ok(id.to_owned())
    }

    fn into_record(self, dialect: DiscoveryDialect) -> Result<Record, ModelCatalogQueryError> {
        let id = self.identifier()?;
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
            unknown_default_input: Some(dialect.unknown_input_modalities()),
            thinking_base_body: false,
        })
    }
}

pub(super) fn records(
    bytes: &[u8],
    dialect: DiscoveryDialect,
) -> Result<Vec<Record>, ModelCatalogQueryError> {
    let envelope: Envelope =
        serde_json::from_slice(bytes).map_err(|_| ModelCatalogQueryError::Protocol)?;
    if envelope.error.is_some() || envelope.success == Some(false) {
        return Err(ModelCatalogQueryError::Protocol);
    }
    let records = match (envelope.data, envelope.models) {
        (Some(records), None) | (None, Some(records)) => records,
        _ => return Err(ModelCatalogQueryError::Protocol),
    };
    records
        .into_iter()
        .map(|record| record.into_record(dialect))
        .collect()
}
