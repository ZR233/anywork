//! A user's sparse edit. Bundled and observed data only enter the resolved ModelDefinition.
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};

use crate::{
    Result,
    model::{ModelDefinition, ModelTransportProfile},
    protocol::WireApi,
};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AccountModelOverride {
    pub base: ModelBaseOverride,
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub extra: Map<String, Value>,
}

/// Only the identity is required in a declaration. All remaining keys, including
/// nested keys, mean that the user explicitly chose that value.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ModelBaseOverride {
    pub slug: String,
    #[serde(flatten)]
    pub fields: Map<String, Value>,
}

impl From<ModelDefinition> for AccountModelOverride {
    fn from(model: ModelDefinition) -> Self {
        Self {
            base: serde_json::from_value(json!(model.base))
                .expect("CodexModel serializes as an object with slug"),
            extra: serde_json::from_value(json!(model.extra))
                .expect("ModelExtras serializes as an object"),
        }
    }
}

impl AccountModelOverride {
    /// Apply exactly the declared keys, including false, empty arrays and values equal to
    /// the protocol defaults. Serializing this edit always preserves its original field set.
    pub fn apply(&self, model: &mut ModelDefinition) -> Result<()> {
        if !self.base.fields.is_empty() {
            let mut base = serde_json::to_value(&model.base)?;
            if self.base.fields.contains_key("truncation_policy") {
                base["truncation_policy"] = serde_json::to_value(&model.base.truncation_policy)?;
            }
            merge(&mut base, &Value::Object(self.base.fields.clone()));
            model.base = serde_json::from_value(base)?;
            if self.base.fields.contains_key("max_context_window")
                && !self.base.fields.contains_key("context_window")
                && let (Some(window), Some(maximum)) =
                    (model.base.context_window, model.base.max_context_window)
            {
                model.base.context_window = Some(window.min(maximum));
            }
        }
        if let Some(protocol) = self
            .extra
            .get("binding")
            .and_then(|b| b.pointer("/transport/protocol"))
        {
            let protocol: WireApi = serde_json::from_value(protocol.clone())?;
            if protocol != model.extra.binding.transport.protocol {
                let transport = match protocol {
                    WireApi::Responses => ModelTransportProfile::responses_http(),
                    WireApi::ChatCompletions => ModelTransportProfile::chat_completions_http(),
                };
                model.extra.binding.set_transport(transport);
            }
        }
        if !self.base.fields.is_empty() {
            let mut record = pl_model_openai_wire::generic_catalog::rich_record(json!(self.base))
                .map_err(|_| {
                crate::PureError::ConfigError(format!(
                    "invalid Codex model declaration: {}",
                    self.base.slug
                ))
            })?;
            if self.base.fields.contains_key("supported_reasoning_levels")
                && record.supports_reasoning.is_none()
            {
                record.supports_reasoning = Some(!model.supported_efforts().is_empty());
            }
            pl_model_openai_wire::discovery::apply_capabilities(
                &mut record,
                model,
                pl_model_openai_wire::discovery::DiscoveryPolicy::COMPATIBLE,
                false,
            );
        }
        if self.extra.is_empty() {
            return Ok(());
        }
        let mut effective = serde_json::to_value(&model.extra)?;
        // These structures have callable protocol defaults even when the entire group is omitted.
        if self.extra.contains_key("capabilities") {
            effective["capabilities"] = serde_json::to_value(&model.extra.capabilities)?;
        }
        if self.extra.contains_key("binding") {
            effective["binding"] = serde_json::to_value(&model.extra.binding)?;
        }
        merge(&mut effective, &Value::Object(self.extra.clone()));
        let mut extra: crate::model::ModelExtras = serde_json::from_value(effective)?;
        if self.extra.contains_key("parameters") {
            // Preserve online service tiers when editing other model parameters.
            extra
                .parameters
                .retain(|parameter| parameter.name != "service_tier");
            extra.parameters.extend(
                model
                    .extra
                    .parameters
                    .iter()
                    .filter(|p| p.name == "service_tier")
                    .cloned(),
            );
        }
        model.extra = extra;
        Ok(())
    }
}

fn merge(target: &mut Value, changes: &Value) {
    match (target, changes) {
        (Value::Object(target), Value::Object(changes)) => {
            for (key, change) in changes {
                merge(target.entry(key).or_insert(Value::Null), change);
            }
        }
        (target, replacement) => target.clone_from(replacement),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn partial_capability_edit_preserves_inherited_values_and_only_serializes_user_keys() {
        let document = json!({"base":{"slug":"example","truncation_policy":{"mode":"bytes","limit":10000}},"extra":{"capabilities":{"streaming":false}}});
        let edit: AccountModelOverride = serde_json::from_value(document.clone()).unwrap();
        let mut model = ModelDefinition::compatible("example");
        model.base.truncation_policy.limit = 25_000;
        model.extra.capabilities.reasoning = true;
        model.extra.max_output_tokens = Some(1024);
        edit.apply(&mut model).unwrap();
        assert!(!model.extra.capabilities.streaming);
        assert!(model.extra.capabilities.reasoning);
        assert_eq!(model.base.truncation_policy.limit, 10_000);
        assert_eq!(model.extra.max_output_tokens, Some(1024));
        assert_eq!(serde_json::to_value(edit).unwrap(), document);
    }
    #[test]
    fn codex_capabilities_in_a_manual_declaration_drive_the_same_responses_wire() {
        let edit: AccountModelOverride = serde_json::from_value(json!({"base":{
            "slug":"example","input_modalities":["text","file"],"supports_parallel_tool_calls":true,
            "web_search_tool_type":"text", "supported_reasoning_levels":[{"effort":"future"}]
        },"extra":{"binding":{"transport":{"protocol":"responses"}}}}))
        .unwrap();
        let mut model = ModelDefinition::compatible("example");
        edit.apply(&mut model).unwrap();
        model.validate().unwrap();
        assert!(
            model.extra.capabilities.tools.function_calling
                && model.base.supports_parallel_tool_calls == Some(true)
        );
        assert!(model.extra.capabilities.supports_web_search());
        assert_eq!(model.supported_efforts(), ["future"]);
        assert!(
            model
                .extra
                .binding
                .request
                .media
                .iter()
                .any(|p| p.wire == crate::model::MediaWireFormat::ResponsesInputFile)
        );
    }
}
