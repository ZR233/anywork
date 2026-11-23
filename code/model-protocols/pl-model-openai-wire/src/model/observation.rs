//! Explicit online fields and their durable acquisition order. Inherited defaults are not observations.
use super::ModelInfo;

pub use pl_model_types::model::{
    ModelMetadataField, ModelObservation, ModelParameterDefaultObservation,
};

/// Copy a provider-neutral field. Parameter wire and media encoders remain route-owned.
pub fn apply_field(target: &mut ModelInfo, source: &ModelInfo, field: ModelMetadataField) {
    use ModelMetadataField::*;
    match field {
        DisplayName => target.display_name = resolve_display_name(source, Some(target)),
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
                .filter(|parameter| parameter.name != "service_tier")
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
            target.parameters.extend(
                previous
                    .into_iter()
                    .filter(|parameter| parameter.name == "service_tier"),
            );
        }
        ServiceTiers => {
            target
                .parameters
                .retain(|parameter| parameter.name != "service_tier");
            target.parameters.extend(
                source
                    .parameters
                    .iter()
                    .filter(|parameter| parameter.name == "service_tier")
                    .cloned(),
            );
        }
    }
}

/// Resolve a presentation name while distinguishing explicit online names from inherited defaults.
pub fn resolve_display_name(online: &ModelInfo, local: Option<&ModelInfo>) -> String {
    observed_display_name(online)
        .or_else(|| local.and_then(readable_display_name))
        .unwrap_or(&online.model_id)
        .to_owned()
}

fn observed_display_name(model: &ModelInfo) -> Option<&str> {
    let explicit = model.observation.as_ref().map(|observation| {
        observation
            .fields
            .contains_key(&ModelMetadataField::DisplayName)
    });
    match explicit {
        Some(true) => readable_name(&model.display_name),
        Some(false) => None,
        // Observation-less models are legacy or caller-constructed values. Preserve their
        // previous non-ID alias behavior; their default ID cannot prove explicit presence.
        None => (!model.display_name.trim().is_empty() && model.display_name != model.model_id)
            .then_some(model.display_name.as_str()),
    }
}

fn readable_display_name(model: &ModelInfo) -> Option<&str> {
    readable_name(&model.display_name)
}

fn readable_name(name: &str) -> Option<&str> {
    (!name.trim().is_empty()).then_some(name)
}

pub fn apply_parameter_defaults(target: &mut ModelInfo, source: &ModelInfo) {
    for parameter in &mut target.parameters {
        parameter.default = source
            .parameters
            .iter()
            .find(|candidate| candidate.name == parameter.name)
            .and_then(|candidate| candidate.default.clone())
            .filter(|value| parameter.candidates.contains(value));
    }
}

pub const SHARED_FIELDS: &[ModelMetadataField] = &[
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
    ModelMetadataField::ServiceTiers,
    ModelMetadataField::Interleaved,
    ModelMetadataField::PromptCache,
    ModelMetadataField::InstructionSnapshotOverrides,
    ModelMetadataField::NativeContextFamily,
    ModelMetadataField::TruncationPolicy,
    ModelMetadataField::BaseInstructions,
];
