use std::collections::BTreeMap;
use std::sync::LazyLock;

use pl_model_wire::model::{
    BundledModelDefinition, CodexModel, ModelDefinition, ModelDefinitionError, TruncationPolicy,
    capabilities::{
        ModelCapabilities, ModelInputCapability, ModelInputLimits, ModelInputSource, ModelModality,
        ToolCapabilities,
    },
    family::{ModelFamily, ModelInstanceSpec},
    info::{
        GeminiRequestOptions, MediaRepresentation, MediaWireFormat, ModelMediaInputProfile,
        ModelProtocolOptions, ModelRequestProfile, ModelTransportProfile, TruncationMode,
    },
    parameter::{ModelParameter, ParameterWire, WireAssignment},
    pricing::{ModelPricing, TokenPriceTier},
};
use serde_json::Value;

pub const RECOMMENDED_MODEL: &str = "gemini-3.7-flash";

const MAX_INLINE_MEDIA_BYTES: u64 = 15 * 1024 * 1024;
const NATIVE_CONTEXT_FAMILY: &str = "gemini-generate-content";
const PRICING_SOURCE: &str = "https://ai.google.dev/gemini-api/docs/pricing";
const VERIFIED_AT: i64 = 1_763_942_400; // 2025-11-24 / verified baseline

#[derive(Clone, Copy)]
enum ThinkingControl {
    Level(&'static [&'static str], &'static str),
    Budget(&'static [(&'static str, u64)], &'static str),
}

struct Definition {
    id: &'static str,
    name: &'static str,
    description: &'static str,
    context: u64,
    max_output: u64,
    thinking: ThinkingControl,
    pricing: Option<&'static [TokenPriceTier]>,
}

const fn context_tiers(standard: TokenPriceTier, extended: TokenPriceTier) -> [TokenPriceTier; 2] {
    const THRESHOLD: u64 = 200_000;
    [
        TokenPriceTier {
            input_until: Some(THRESHOLD),
            ..standard
        },
        TokenPriceTier {
            input_from: THRESHOLD,
            ..extended
        },
    ]
}

const RATES_3_7_FLASH: [TokenPriceTier; 1] = [TokenPriceTier::flat(0.75, 3.75, None, None)];
const RATES_3_1_PRO: [TokenPriceTier; 2] = context_tiers(
    TokenPriceTier::flat(2.0, 12.0, Some(0.2), None),
    TokenPriceTier::flat(4.0, 18.0, Some(0.4), None),
);
const RATES_2_5_PRO: [TokenPriceTier; 2] = context_tiers(
    TokenPriceTier::flat(1.25, 10.0, Some(0.125), None),
    TokenPriceTier::flat(2.5, 15.0, Some(0.25), None),
);
const RATES_2_5_FLASH: [TokenPriceTier; 1] = [TokenPriceTier::flat(0.30, 2.50, Some(0.03), None)];
const RATES_2_5_FLASH_LITE: [TokenPriceTier; 1] =
    [TokenPriceTier::flat(0.10, 0.40, Some(0.01), None)];

const LEVEL_3_STANDARD: &[&str] = &["low", "medium", "high"];
const BUDGET_2_5_PRO: &[(&str, u64)] = &[("low", 1024), ("medium", 8192), ("high", 24576)];
const BUDGET_2_5_FLASH: &[(&str, u64)] = &[
    ("none", 0),
    ("low", 1024),
    ("medium", 8192),
    ("high", 24576),
];

const MODELS: &[Definition] = &[
    Definition {
        id: RECOMMENDED_MODEL,
        name: "Gemini 3.7 Flash",
        description: "Fast multimodal Gemini reasoning model for coding and agentic tool use.",
        context: 1_048_576,
        max_output: 65_536,
        thinking: ThinkingControl::Level(LEVEL_3_STANDARD, "medium"),
        pricing: Some(&RATES_3_7_FLASH),
    },
    Definition {
        id: "gemini-3-flash-preview",
        name: "Gemini 3 Flash Preview",
        description: "Preview Gemini 3 Flash multimodal reasoning model.",
        context: 1_048_576,
        max_output: 65_536,
        thinking: ThinkingControl::Level(LEVEL_3_STANDARD, "medium"),
        pricing: None,
    },
    Definition {
        id: "gemini-3.1-pro-preview",
        name: "Gemini 3.1 Pro Preview",
        description: "High-capability Gemini 3.1 Pro multimodal reasoning model.",
        context: 1_048_576,
        max_output: 65_536,
        thinking: ThinkingControl::Level(LEVEL_3_STANDARD, "medium"),
        pricing: Some(&RATES_3_1_PRO),
    },
    Definition {
        id: "gemini-2.5-pro",
        name: "Gemini 2.5 Pro",
        description: "Gemini 2.5 Pro reasoning model for complex coding and analysis.",
        context: 1_048_576,
        max_output: 65_536,
        thinking: ThinkingControl::Budget(BUDGET_2_5_PRO, "medium"),
        pricing: Some(&RATES_2_5_PRO),
    },
    Definition {
        id: "gemini-2.5-flash",
        name: "Gemini 2.5 Flash",
        description: "Balanced Gemini 2.5 Flash model with optional thinking budget.",
        context: 1_048_576,
        max_output: 65_536,
        thinking: ThinkingControl::Budget(BUDGET_2_5_FLASH, "medium"),
        pricing: Some(&RATES_2_5_FLASH),
    },
    Definition {
        id: "gemini-2.5-flash-lite",
        name: "Gemini 2.5 Flash-Lite",
        description: "Ultra-low-latency Gemini 2.5 Flash-Lite model.",
        context: 1_048_576,
        max_output: 65_536,
        thinking: ThinkingControl::Budget(BUDGET_2_5_FLASH, "none"),
        pricing: Some(&RATES_2_5_FLASH_LITE),
    },
];

impl Definition {
    fn instantiate(&self, family: &ModelFamily) -> ModelDefinition {
        let pricing = match self.pricing {
            Some(tiers) => {
                ModelPricing::published_at("USD", tiers.to_vec(), PRICING_SOURCE, VERIFIED_AT)
            }
            None => ModelPricing::Unknown,
        };
        let mut model = family.instantiate(ModelInstanceSpec {
            model_id: self.id,
            display_name: self.name,
            description: self.description,
            context_window: self.context,
            max_context_window: self.context,
            max_output_tokens: Some(self.max_output),
            pricing,
        });
        model.set_parameters(vec![thinking_effort_parameter(self.thinking)]);
        model
    }
}

fn thinking_effort_parameter(control: ThinkingControl) -> ModelParameter {
    match control {
        ThinkingControl::Level(candidates, default) => ModelParameter {
            name: "effort".into(),
            label: None,
            default: Some(default.to_owned()),
            candidates: candidates.iter().map(|&c| c.to_owned()).collect(),
            candidate_display_names: Default::default(),
            wire: candidates
                .iter()
                .map(|&c| {
                    (
                        c.to_owned(),
                        ParameterWire {
                            set: vec![WireAssignment {
                                path: "generationConfig.thinkingConfig.thinkingLevel".into(),
                                value: Value::String(c.to_owned()),
                            }],
                            remove: Vec::new(),
                        },
                    )
                })
                .collect(),
        },
        ThinkingControl::Budget(entries, default) => {
            let mut wire = BTreeMap::new();
            let mut candidates = Vec::with_capacity(entries.len());
            for &(name, budget) in entries {
                candidates.push(name.to_owned());
                wire.insert(
                    name.to_owned(),
                    ParameterWire {
                        set: vec![WireAssignment {
                            path: "generationConfig.thinkingConfig.thinkingBudget".into(),
                            value: Value::from(budget),
                        }],
                        remove: Vec::new(),
                    },
                );
            }
            ModelParameter {
                name: "effort".into(),
                label: None,
                default: Some(default.to_owned()),
                candidates,
                candidate_display_names: Default::default(),
                wire,
            }
        }
    }
}

fn family() -> ModelFamily {
    let local_only = vec![ModelInputSource::Local];
    let inline_profile = |modality, wire| ModelMediaInputProfile {
        modality,
        wire,
        first_send: vec![MediaRepresentation::DataUrl],
        replay: vec![MediaRepresentation::DataUrl],
    };
    ModelFamily {
        capabilities: ModelCapabilities {
            streaming: true,
            temperature: true,
            reasoning: true,
            web_search: false,
            input: vec![
                ModelInputCapability::text(),
                ModelInputCapability {
                    modality: ModelModality::Image,
                    sources: local_only.clone(),
                    limits: ModelInputLimits {
                        max_bytes: Some(MAX_INLINE_MEDIA_BYTES),
                        max_total_bytes: Some(MAX_INLINE_MEDIA_BYTES),
                        media_types: vec![
                            "image/jpeg".into(),
                            "image/png".into(),
                            "image/webp".into(),
                            "image/gif".into(),
                        ],
                        ..Default::default()
                    },
                },
                ModelInputCapability {
                    modality: ModelModality::File,
                    sources: local_only,
                    limits: ModelInputLimits {
                        max_bytes: Some(MAX_INLINE_MEDIA_BYTES),
                        max_total_bytes: Some(MAX_INLINE_MEDIA_BYTES),
                        media_types: vec!["application/pdf".into(), "text/plain".into()],
                        ..Default::default()
                    },
                },
            ],
            output: vec![ModelModality::Text],
            tools: ToolCapabilities {
                function_calling: true,
                ..Default::default()
            },
            interleaved: None,
            prompt_cache: Default::default(),
            instruction_snapshot_overrides: false,
            native_context_family: Some(NATIVE_CONTEXT_FAMILY.to_owned()),
        },
        base: CodexModel {
            supports_parallel_tool_calls: Some(true),
            truncation_policy: TruncationPolicy {
                mode: TruncationMode::Tokens,
                limit: 10_000,
            },
            ..Default::default()
        },
        parameters: Vec::new(),
        transport: ModelTransportProfile::gemini_http(),
        request_profile: ModelRequestProfile {
            protocol: ModelProtocolOptions::GeminiGenerateContent(GeminiRequestOptions::default()),
            media: vec![
                inline_profile(ModelModality::Image, MediaWireFormat::GeminiInlineImage),
                inline_profile(ModelModality::File, MediaWireFormat::GeminiInlineFile),
            ],
            ..Default::default()
        },
    }
}

static CATALOG: LazyLock<Result<BundledModelDefinition, ModelDefinitionError>> =
    LazyLock::new(|| {
        let family = family();
        let models = MODELS
            .iter()
            .map(|model| model.instantiate(&family))
            .collect();
        BundledModelDefinition::new(models, RECOMMENDED_MODEL, Some("medium"))
    });

pub fn bundled_definition() -> Result<BundledModelDefinition, ModelDefinitionError> {
    CATALOG.clone()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bundled_models_validate_cleanly() {
        let bundled = bundled_definition().unwrap();
        assert_eq!(bundled.suggested_model, RECOMMENDED_MODEL);
        for model in &bundled.models {
            model.validate().unwrap();
        }
    }
}
