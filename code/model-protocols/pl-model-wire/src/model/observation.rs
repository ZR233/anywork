//! Explicit online fields and their durable acquisition order. Inherited defaults are not observations.
use super::ModelDefinition;

pub use pl_model_types::model::{
    ModelMetadataField, ModelObservation, ModelParameterDefaultObservation,
};

/// Copy a provider-neutral field. Parameter wire and media encoders remain route-owned.
pub fn apply_field(
    target: &mut ModelDefinition,
    source: &ModelDefinition,
    field: ModelMetadataField,
) {
    use ModelMetadataField::*;
    match field {
        DisplayName => target.base.display_name = resolve_display_name(source, Some(target)),
        Description => target.base.description.clone_from(&source.base.description),
        ContextWindow => target.base.context_window = source.base.context_window,
        MaxContextWindow => target.base.max_context_window = source.base.max_context_window,
        AutoCompactTokenLimit => {
            target.base.auto_compact_token_limit = source.base.auto_compact_token_limit
        }
        MaxOutputTokens => target.extra.max_output_tokens = source.extra.max_output_tokens,
        DefaultTemperature => target.extra.default_temperature = source.extra.default_temperature,
        Input => target
            .extra
            .capabilities
            .input
            .clone_from(&source.extra.capabilities.input),
        Output => target
            .extra
            .capabilities
            .output
            .clone_from(&source.extra.capabilities.output),
        Streaming => target.extra.capabilities.streaming = source.extra.capabilities.streaming,
        Temperature => {
            target.extra.capabilities.temperature = source.extra.capabilities.temperature
        }
        Reasoning => target.extra.capabilities.reasoning = source.extra.capabilities.reasoning,
        WebSearch => target.extra.capabilities.web_search = source.extra.capabilities.web_search,
        FunctionCalling => {
            target.extra.capabilities.tools.function_calling =
                source.extra.capabilities.tools.function_calling
        }
        ParallelToolCalls => {
            target.base.supports_parallel_tool_calls = source.base.supports_parallel_tool_calls
        }
        CustomTools => {
            target.extra.capabilities.tools.custom_tools =
                source.extra.capabilities.tools.custom_tools
        }
        FreeformTools => {
            target.extra.capabilities.tools.freeform_tools =
                source.extra.capabilities.tools.freeform_tools
        }
        ProgrammaticToolCalling => {
            target.extra.capabilities.tools.programmatic_tool_calling =
                source.extra.capabilities.tools.programmatic_tool_calling
        }
        Interleaved => target
            .extra
            .capabilities
            .interleaved
            .clone_from(&source.extra.capabilities.interleaved),
        PromptCache => target
            .extra
            .capabilities
            .prompt_cache
            .clone_from(&source.extra.capabilities.prompt_cache),
        InstructionSnapshotOverrides => {
            target.extra.capabilities.instruction_snapshot_overrides =
                source.extra.capabilities.instruction_snapshot_overrides
        }
        NativeContextFamily => target
            .extra
            .capabilities
            .native_context_family
            .clone_from(&source.extra.capabilities.native_context_family),
        TruncationPolicy => target
            .base
            .truncation_policy
            .clone_from(&source.base.truncation_policy),
        BaseInstructions => target
            .base
            .model_messages
            .instructions_template
            .clone_from(&source.base.model_messages.instructions_template),
        Parameters => {
            let previous: Vec<_> = target.parameters().collect();
            let mut resolved_parameters: Vec<_> = source
                .parameters()
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
                        let path = match target.extra.binding.transport.protocol {
                            crate::protocol::WireApi::Responses => "reasoning.effort",
                            crate::protocol::WireApi::ChatCompletions => "reasoning_effort",
                            crate::protocol::WireApi::GeminiGenerateContent => {
                                "generationConfig.thinkingConfig.thinkingLevel"
                            }
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
            resolved_parameters.extend(
                previous
                    .into_iter()
                    .filter(|parameter| parameter.name == "service_tier"),
            );
            target.set_parameters(resolved_parameters);
            target
                .base
                .supported_reasoning_levels
                .clone_from(&source.base.supported_reasoning_levels);
        }
        ServiceTiers => {
            target
                .extra
                .parameters
                .retain(|parameter| parameter.name != "service_tier");
            target.extra.parameters.extend(
                source
                    .extra
                    .parameters
                    .iter()
                    .filter(|parameter| parameter.name == "service_tier")
                    .cloned(),
            );
        }
    }
}

/// Resolve a presentation name while distinguishing explicit online names from inherited defaults.
pub fn resolve_display_name(online: &ModelDefinition, local: Option<&ModelDefinition>) -> String {
    observed_display_name(online)
        .or_else(|| local.and_then(readable_display_name))
        .unwrap_or(&online.base.slug)
        .to_owned()
}

fn observed_display_name(model: &ModelDefinition) -> Option<&str> {
    let explicit = model.observation.as_ref().map(|observation| {
        observation
            .fields
            .contains_key(&ModelMetadataField::DisplayName)
    });
    match explicit {
        Some(true) => readable_name(&model.base.display_name),
        Some(false) => None,
        // Observation-less models are legacy or caller-constructed values. Preserve their
        // previous non-ID alias behavior; their default ID cannot prove explicit presence.
        None => (!model.base.display_name.trim().is_empty()
            && model.base.display_name != model.base.slug)
            .then_some(model.base.display_name.as_str()),
    }
}

fn readable_display_name(model: &ModelDefinition) -> Option<&str> {
    readable_name(&model.base.display_name)
}

fn readable_name(name: &str) -> Option<&str> {
    (!name.trim().is_empty()).then_some(name)
}

pub fn apply_parameter_defaults(target: &mut ModelDefinition, source: &ModelDefinition) {
    target
        .base
        .default_reasoning_level
        .clone_from(&source.base.default_reasoning_level);
    for parameter in &mut target.extra.parameters {
        parameter.default = source
            .extra
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
