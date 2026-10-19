//! Explicit online fields and their durable acquisition order. Inherited defaults are not observations.
use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use super::ModelInfo;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ModelMetadataField {
    DisplayName,
    Description,
    ContextWindow,
    MaxContextWindow,
    AutoCompactTokenLimit,
    MaxOutputTokens,
    DefaultTemperature,
    Input,
    Output,
    Streaming,
    Temperature,
    Reasoning,
    WebSearch,
    FunctionCalling,
    ParallelToolCalls,
    CustomTools,
    FreeformTools,
    ProgrammaticToolCalling,
    Parameters,
    Interleaved,
    PromptCache,
    InstructionSnapshotOverrides,
    NativeContextFamily,
    TruncationPolicy,
    BaseInstructions,
}

/// Zero is an uncommitted response field; the host stamps it when accepting the response.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelObservation {
    pub fields: BTreeMap<ModelMetadataField, u64>,
    /// Original budget declarations, before paired budget normalization. A later
    /// field must never promote an inherited/derived companion to an online fact.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub budgets: BTreeMap<ModelMetadataField, Option<u64>>,
    /// Defaults have their own clock: a candidate-only update cannot promote an inherited default.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub parameter_defaults: BTreeMap<String, ModelParameterDefaultObservation>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub price_order: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelParameterDefaultObservation {
    pub value: Option<String>,
    pub order: u64,
}

impl ModelObservation {
    pub fn declare(&mut self, field: ModelMetadataField) {
        self.fields.insert(field, 0);
    }

    pub fn commit(&mut self, order: u64) {
        if self.price_order == Some(0) {
            self.price_order = Some(order);
        }
        for value in self.fields.values_mut() {
            if *value == 0 {
                *value = order;
            }
        }
        for default in self.parameter_defaults.values_mut() {
            if default.order == 0 {
                default.order = order;
            }
        }
    }

    pub fn latest_order(&self) -> u64 {
        self.fields
            .values()
            .copied()
            .chain(self.price_order)
            .chain(
                self.parameter_defaults
                    .values()
                    .map(|default| default.order),
            )
            .max()
            .unwrap_or(0)
    }
}

/// Copy a provider-neutral field. Parameter wire and media encoders remain route-owned.
pub(crate) fn apply_field(target: &mut ModelInfo, source: &ModelInfo, field: ModelMetadataField) {
    use ModelMetadataField::*;
    match field {
        DisplayName => target.display_name.clone_from(&source.display_name),
        Description => target.description.clone_from(&source.description),
        ContextWindow => target.context_window = source.context_window,
        MaxContextWindow => target.max_context_window = source.max_context_window,
        AutoCompactTokenLimit => target.auto_compact_token_limit = source.auto_compact_token_limit,
        MaxOutputTokens => target.max_output_tokens = source.max_output_tokens,
        DefaultTemperature => target.default_temperature = source.default_temperature,
        Input => target
            .capabilities
            .input
            .clone_from(&source.capabilities.input),
        Output => target
            .capabilities
            .output
            .clone_from(&source.capabilities.output),
        Streaming => target.capabilities.streaming = source.capabilities.streaming,
        Temperature => target.capabilities.temperature = source.capabilities.temperature,
        Reasoning => target.capabilities.reasoning = source.capabilities.reasoning,
        WebSearch => target.capabilities.web_search = source.capabilities.web_search,
        FunctionCalling => {
            target.capabilities.tools.function_calling = source.capabilities.tools.function_calling
        }
        ParallelToolCalls => {
            target.capabilities.tools.parallel_tool_calls =
                source.capabilities.tools.parallel_tool_calls
        }
        CustomTools => {
            target.capabilities.tools.custom_tools = source.capabilities.tools.custom_tools
        }
        FreeformTools => {
            target.capabilities.tools.freeform_tools = source.capabilities.tools.freeform_tools
        }
        ProgrammaticToolCalling => {
            target.capabilities.tools.programmatic_tool_calling =
                source.capabilities.tools.programmatic_tool_calling
        }
        Interleaved => target
            .capabilities
            .interleaved
            .clone_from(&source.capabilities.interleaved),
        PromptCache => target
            .capabilities
            .prompt_cache
            .clone_from(&source.capabilities.prompt_cache),
        InstructionSnapshotOverrides => {
            target.capabilities.instruction_snapshot_overrides =
                source.capabilities.instruction_snapshot_overrides
        }
        NativeContextFamily => target
            .capabilities
            .native_context_family
            .clone_from(&source.capabilities.native_context_family),
        TruncationPolicy => target
            .truncation_policy
            .clone_from(&source.truncation_policy),
        BaseInstructions => target
            .base_instructions
            .clone_from(&source.base_instructions),
        Parameters => {
            let previous = std::mem::take(&mut target.parameters);
            target.parameters = source
                .parameters
                .iter()
                .map(|parameter| {
                    let mut resolved = parameter.clone();
                    resolved.default = previous
                        .iter()
                        .find(|old| old.name == parameter.name)
                        .and_then(|old| old.default.clone())
                        .filter(|value| resolved.candidates.contains(value));
                    resolved.wire = previous
                        .iter()
                        .find(|old| old.name == parameter.name)
                        .map(|old| old.wire.clone())
                        .unwrap_or_default();
                    // Protocol-specific effort encoding is an existing boundary contract.
                    if parameter.name == "effort" {
                        let path = match target.binding.transport.protocol {
                            crate::protocol::WireApi::Responses => "reasoning.effort",
                            crate::protocol::WireApi::ChatCompletions => "reasoning_effort",
                        };
                        resolved
                            .wire
                            .retain(|candidate, _| resolved.candidates.contains(candidate));
                        for candidate in &resolved.candidates {
                            resolved.wire.entry(candidate.clone()).or_insert_with(|| {
                                super::ParameterWire {
                                    set: vec![super::WireAssignment {
                                        path: path.into(),
                                        value: serde_json::Value::String(candidate.clone()),
                                    }],
                                    remove: Vec::new(),
                                }
                            });
                        }
                    }
                    resolved
                })
                .collect();
        }
    }
}

pub(crate) fn apply_parameter_defaults(target: &mut ModelInfo, source: &ModelInfo) {
    for parameter in &mut target.parameters {
        parameter.default = source
            .parameters
            .iter()
            .find(|candidate| candidate.name == parameter.name)
            .and_then(|candidate| candidate.default.clone())
            .filter(|value| parameter.candidates.contains(value));
    }
}

pub(crate) const SHARED_FIELDS: &[ModelMetadataField] = &[
    ModelMetadataField::DisplayName,
    ModelMetadataField::Description,
    ModelMetadataField::ContextWindow,
    ModelMetadataField::MaxContextWindow,
    ModelMetadataField::AutoCompactTokenLimit,
    ModelMetadataField::MaxOutputTokens,
    ModelMetadataField::DefaultTemperature,
    ModelMetadataField::Input,
    ModelMetadataField::Output,
    ModelMetadataField::Streaming,
    ModelMetadataField::Temperature,
    ModelMetadataField::Reasoning,
    ModelMetadataField::WebSearch,
    ModelMetadataField::FunctionCalling,
    ModelMetadataField::ParallelToolCalls,
    ModelMetadataField::CustomTools,
    ModelMetadataField::FreeformTools,
    ModelMetadataField::ProgrammaticToolCalling,
    ModelMetadataField::Parameters,
    ModelMetadataField::Interleaved,
    ModelMetadataField::PromptCache,
    ModelMetadataField::InstructionSnapshotOverrides,
    ModelMetadataField::NativeContextFamily,
    ModelMetadataField::TruncationPolicy,
    ModelMetadataField::BaseInstructions,
];
