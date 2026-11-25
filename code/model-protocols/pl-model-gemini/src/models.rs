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

pub const RECOMMENDED_MODEL: &str = "gemini-4-hydrogen";

const MAX_INLINE_MEDIA_BYTES: u64 = 15 * 1024 * 1024;
const NATIVE_CONTEXT_FAMILY: &str = "gemini-generate-content";
const PRICING_SOURCE: &str = "https://ai.google.dev/gemini-api/docs/pricing";
const VERIFIED_AT: i64 = 1_795_564_800; // 2026-11-25 UTC
const UNIFIED_CONTEXT_WINDOW: u64 = 1_048_576;
const STREAMING_MAX_OUTPUT: u64 = 65_536;
// Matches Google Antigravity's 512K automatic compaction ceiling for Gemini 4 models,
// leaving headroom within the unified 1M input/thinking/output context pool while still
// allowing per-account overrides up to 90% (943,718 tokens).
const DEFAULT_AUTO_COMPACT_TOKEN_LIMIT: u64 = 512_000;

struct Definition {
    id: &'static str,
    name: &'static str,
    description: &'static str,
    context: u64,
    max_output: u64,
    auto_compact_token_limit: u64,
    thinking_levels: &'static [&'static str],
    default_thinking_level: &'static str,
    pricing: TokenPriceTier,
}

const LEVEL_STANDARD: &[&str] = &["low", "medium", "high"];
const LEVEL_EXTENDED: &[&str] = &["low", "medium", "high", "xhigh"];

const MODELS: &[Definition] = &[
    Definition {
        id: RECOMMENDED_MODEL,
        name: "Gemini 4 Hydrogen",
        description: "Fast, cost-efficient Gemini 4 multimodal reasoning model for everyday coding and agentic workflows.",
        context: UNIFIED_CONTEXT_WINDOW,
        max_output: STREAMING_MAX_OUTPUT,
        auto_compact_token_limit: DEFAULT_AUTO_COMPACT_TOKEN_LIMIT,
        thinking_levels: LEVEL_EXTENDED,
        default_thinking_level: "high",
        pricing: TokenPriceTier::flat(1.50, 7.50, Some(0.075), None),
    },
    Definition {
        id: "gemini-4-neon",
        name: "Gemini 4 Neon",
        description: "Frontier-level Gemini 4 model balancing deep reasoning with fast end-to-end completion for complex coding and knowledge work.",
        context: UNIFIED_CONTEXT_WINDOW,
        max_output: STREAMING_MAX_OUTPUT,
        auto_compact_token_limit: DEFAULT_AUTO_COMPACT_TOKEN_LIMIT,
        thinking_levels: LEVEL_EXTENDED,
        default_thinking_level: "high",
        pricing: TokenPriceTier::flat(3.00, 15.00, Some(0.15), None),
    },
    Definition {
        id: "gemini-4-argon",
        name: "Gemini 4 Argon",
        description: "Efficient Gemini 4 frontier reasoning model with faster responses and lower token spend per turn than Carbon.",
        context: UNIFIED_CONTEXT_WINDOW,
        // Streaming single-hop default limit is 65,536 (live /models metadata reports 32,768 for non-streaming hops).
        max_output: STREAMING_MAX_OUTPUT,
        auto_compact_token_limit: DEFAULT_AUTO_COMPACT_TOKEN_LIMIT,
        thinking_levels: LEVEL_STANDARD,
        default_thinking_level: "medium",
        // Published introductory rate through 2026-11-30; standard rate starts 2026-12-01.
        pricing: TokenPriceTier::flat(2.00, 10.00, Some(0.10), None),
    },
    Definition {
        id: "gemini-4-carbon",
        name: "Gemini 4 Carbon",
        description: "Strongest Gemini 4 reasoning model for complex software engineering, multimodal knowledge work, scientific reasoning, and cybersecurity defense.",
        context: UNIFIED_CONTEXT_WINDOW,
        // Streaming single-hop default limit is 65,536 (live /models metadata reports 32,768 for non-streaming hops).
        max_output: STREAMING_MAX_OUTPUT,
        auto_compact_token_limit: DEFAULT_AUTO_COMPACT_TOKEN_LIMIT,
        thinking_levels: LEVEL_STANDARD,
        default_thinking_level: "medium",
        // Published introductory rate through 2026-11-30; standard rate starts 2026-12-01.
        pricing: TokenPriceTier::flat(2.00, 10.00, Some(0.10), None),
    },
];

impl Definition {
    fn instantiate(&self, family: &ModelFamily) -> ModelDefinition {
        let pricing = ModelPricing::published_at(
            "USD",
            vec![self.pricing.clone()],
            PRICING_SOURCE,
            VERIFIED_AT,
        );
        let mut model = family.instantiate(ModelInstanceSpec {
            model_id: self.id,
            display_name: self.name,
            description: self.description,
            context_window: self.context,
            max_context_window: self.context,
            max_output_tokens: Some(self.max_output),
            pricing,
        });
        model.base.auto_compact_token_limit = Some(self.auto_compact_token_limit);
        model.set_parameters(vec![thinking_effort_parameter(
            self.thinking_levels,
            self.default_thinking_level,
        )]);
        model
    }
}

fn thinking_effort_parameter(candidates: &[&str], default: &str) -> ModelParameter {
    ModelParameter {
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
            temperature: false,
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
        BundledModelDefinition::new(models, RECOMMENDED_MODEL, Some("high"))
    });

pub fn bundled_definition() -> Result<BundledModelDefinition, ModelDefinitionError> {
    CATALOG.clone()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bundled_models_validate_cleanly_with_gemini_4_inventory_and_pricing() {
        let bundled = bundled_definition().unwrap();
        assert_eq!(bundled.suggested_model, "gemini-4-hydrogen");
        assert_eq!(bundled.suggested_effort.as_deref(), Some("high"));

        let slugs: Vec<&str> = bundled
            .models
            .iter()
            .map(|model| model.base.slug.as_str())
            .collect();
        assert_eq!(
            slugs,
            [
                "gemini-4-hydrogen",
                "gemini-4-neon",
                "gemini-4-argon",
                "gemini-4-carbon",
            ]
        );

        let expected = [
            (
                "gemini-4-hydrogen",
                &["low", "medium", "high", "xhigh"][..],
                "high",
                1.50,
                7.50,
                0.075,
            ),
            (
                "gemini-4-neon",
                &["low", "medium", "high", "xhigh"][..],
                "high",
                3.00,
                15.00,
                0.15,
            ),
            (
                "gemini-4-argon",
                &["low", "medium", "high"][..],
                "medium",
                2.00,
                10.00,
                0.10,
            ),
            (
                "gemini-4-carbon",
                &["low", "medium", "high"][..],
                "medium",
                2.00,
                10.00,
                0.10,
            ),
        ];

        for (model, (slug, efforts, default_effort, input, output, cache_read)) in
            bundled.models.iter().zip(expected)
        {
            model.validate().unwrap();
            assert_eq!(model.base.slug, slug);
            assert_eq!(model.base.context_window, Some(UNIFIED_CONTEXT_WINDOW));
            assert_eq!(model.base.max_context_window, Some(UNIFIED_CONTEXT_WINDOW));
            assert_eq!(model.extra.max_output_tokens, Some(STREAMING_MAX_OUTPUT));
            assert_eq!(
                model.base.auto_compact_token_limit,
                Some(DEFAULT_AUTO_COMPACT_TOKEN_LIMIT)
            );
            assert_eq!(
                model
                    .resolve_context(
                        None,
                        pl_model_wire::model::AutoCompactDefaultPolicy::Bundled
                    )
                    .auto_compact_limit,
                Some(DEFAULT_AUTO_COMPACT_TOKEN_LIMIT)
            );
            assert_eq!(model.max_auto_compact_override(), Some(943_718));
            assert_eq!(
                model
                    .resolve_context(
                        Some(700_000),
                        pl_model_wire::model::AutoCompactDefaultPolicy::Bundled
                    )
                    .auto_compact_limit,
                Some(700_000)
            );

            let effort_param = model.effort_parameter().expect("effort parameter");
            assert_eq!(effort_param.default.as_deref(), Some(default_effort));
            assert_eq!(effort_param.candidates, efforts);
            for candidate in efforts {
                let wire = effort_param
                    .wire_for(candidate)
                    .expect("wire entry for effort candidate");
                assert_eq!(
                    wire.set,
                    vec![WireAssignment {
                        path: "generationConfig.thinkingConfig.thinkingLevel".into(),
                        value: Value::String((*candidate).to_owned()),
                    }]
                );
                assert!(wire.remove.is_empty());
            }

            let ModelPricing::Rates {
                currency,
                tiers,
                weekly_adjustment,
                source,
                verified_at,
            } = &model.extra.pricing
            else {
                panic!("expected published USD pricing for {slug}");
            };
            assert_eq!(currency, "USD");
            assert!(weekly_adjustment.is_none());
            assert_eq!(source, PRICING_SOURCE);
            assert_eq!(*verified_at, VERIFIED_AT);
            assert_eq!(tiers.len(), 1);
            let tier = &tiers[0];
            assert_eq!(tier.input_from, 0);
            assert_eq!(tier.input_until, None);
            assert_eq!(tier.output_from, 0);
            assert_eq!(tier.output_until, None);
            assert_eq!(tier.input_per_mtok, input);
            assert_eq!(tier.output_per_mtok, output);
            assert_eq!(tier.cache_read_per_mtok, Some(cache_read));
            assert_eq!(tier.cache_write_per_mtok, None);
        }
    }
}
