//! OpenAI Models API (`data`/`id`) and the currently deployed Codex rich `models`/`slug`
//! declaration. Codex-only defaults belong to this boundary only.
use crate::discovery::reasoning::ReasoningDeclaration;
use crate::discovery::{Capabilities, ModelCatalogQueryError, Record, nullable, presentation_name};
use crate::model::*;
use serde::Deserialize;

#[derive(Deserialize)]
struct Envelope {
    data: Option<Vec<serde_json::Value>>,
    models: Option<Vec<serde_json::Value>>,
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
    input_modalities: Option<Vec<String>>,
    output_modalities: Option<Vec<String>>,
    #[serde(flatten)]
    reasoning: ReasoningDeclaration,
    #[serde(flatten)]
    service_tiers: crate::service_tiers::ServiceTierDeclaration,
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

    fn into_record(self) -> Result<Record, ModelCatalogQueryError> {
        let id = self.identifier()?;
        Ok(Record {
            codex: None,
            id,
            display_name: presentation_name(self.display_name, self.name),
            description: self.description,
            context_window: self.context_window,
            max_context_window: self.max_context_window,
            auto_compact_token_limit: self.auto_compact_token_limit,
            max_output_tokens: self.max_output_tokens,
            default_temperature: self.default_temperature,
            input_modalities: self.input_modalities.map(known_modalities),
            output_modalities: self.output_modalities.map(known_modalities),
            supports_parallel_tool_calls: self.supports_parallel_tool_calls,
            supports_function_calling: self.supports_function_calling,
            supports_temperature: self.supports_temperature,
            supports_streaming: self.supports_streaming,
            supports_reasoning: self.supports_reasoning,
            reasoning: self.reasoning,
            service_tiers: self.service_tiers,
            binding: self.binding,
            capabilities: self.capabilities,
            pricing: None,
            thinking_base_body: false,
        })
    }
}

pub fn records(bytes: &[u8]) -> Result<Vec<Record>, ModelCatalogQueryError> {
    with_standard_records(bytes, standard_record)
}

pub fn openai_records(bytes: &[u8]) -> Result<Vec<Record>, ModelCatalogQueryError> {
    with_standard_records(bytes, rich_record)
}

/// All compatible protocols accept the same Codex envelope. A protocol can specialize
/// how it reads a standard Models API entry without replacing envelope validation.
pub fn with_standard_records(
    bytes: &[u8],
    standard: impl Fn(serde_json::Value) -> Result<Record, ModelCatalogQueryError>,
) -> Result<Vec<Record>, ModelCatalogQueryError> {
    let envelope: Envelope =
        serde_json::from_slice(bytes).map_err(|_| ModelCatalogQueryError::Protocol)?;
    if envelope.error.is_some() || envelope.success == Some(false) {
        return Err(ModelCatalogQueryError::Protocol);
    }
    match (envelope.data, envelope.models) {
        (Some(records), None) => records.into_iter().map(standard).collect(),
        (None, Some(records)) => records.into_iter().map(rich_record).collect(),
        _ => Err(ModelCatalogQueryError::Protocol),
    }
}

pub fn standard_record(value: serde_json::Value) -> Result<Record, ModelCatalogQueryError> {
    if value.get("id").and_then(|id| id.as_str()).is_none() {
        return Err(ModelCatalogQueryError::Protocol);
    }
    rich_record(value)
}

pub fn rich_record(value: serde_json::Value) -> Result<Record, ModelCatalogQueryError> {
    let mut declarations = value.clone();
    // Some Codex-compatible catalogs publish a display default alongside an empty effort list.
    // The default is retained in the base, but no selectable wire parameter exists.
    if declarations
        .get("supported_reasoning_levels")
        .and_then(|v| v.as_array())
        .is_some_and(Vec::is_empty)
        && let Some(object) = declarations.as_object_mut()
    {
        object.remove("default_reasoning_level");
    }
    let mut normalized = serde_json::from_value::<WireRecord>(declarations)
        .map_err(|_| ModelCatalogQueryError::Protocol)?
        .into_record()?;
    let web_search = value
        .get("supports_web_search")
        .and_then(|v| v.as_bool())
        .or_else(|| {
            value
                .get("web_search_tool_type")
                .and_then(|v| v.as_str())
                .filter(|v| matches!(*v, "text" | "text_and_image"))
                .map(|_| true)
        });
    if let Some(supported) = web_search {
        normalized
            .capabilities
            .get_or_insert_with(Default::default)
            .web_search
            .get_or_insert(supported);
    }
    if normalized.supports_parallel_tool_calls == Some(true)
        && normalized.supports_function_calling.is_none()
        && normalized
            .capabilities
            .as_ref()
            .and_then(|c| c.tools.as_ref())
            .and_then(|t| t.function_calling)
            .is_none()
    {
        normalized.supports_function_calling = Some(true);
    }
    normalized.codex = Some(codex_base(value, &normalized.id)?);
    Ok(normalized)
}

pub fn codex_base(
    mut value: serde_json::Value,
    id: &str,
) -> Result<CodexModel, ModelCatalogQueryError> {
    let object = value
        .as_object_mut()
        .ok_or(ModelCatalogQueryError::Protocol)?;
    object.insert("slug".into(), id.into());
    for key in [
        "id",
        "model_id",
        "modelId",
        "binding",
        "capabilities",
        "pricing",
        "parameters",
        "max_output_tokens",
        "default_temperature",
    ] {
        object.remove(key);
    }
    for key in ["model_messages", "display_name", "truncation_policy"] {
        if object.get(key).is_some_and(serde_json::Value::is_null) {
            object.remove(key);
        }
    }
    if let Some(messages) = object
        .get_mut("model_messages")
        .and_then(|v| v.as_object_mut())
        && messages
            .get("instructions_template")
            .is_some_and(|v| v.is_null())
    {
        messages.remove("instructions_template");
    }
    serde_json::from_value(value).map_err(|_| ModelCatalogQueryError::Protocol)
}

fn known_modalities(names: Vec<String>) -> Vec<ModelModality> {
    names
        .into_iter()
        .filter_map(|name| serde_json::from_value(name.into()).ok())
        .collect()
}
