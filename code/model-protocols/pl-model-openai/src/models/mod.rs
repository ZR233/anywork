use std::sync::LazyLock;

use pl_model_wire::model::{
    BundledModelDefinition, CodexModel, ModelDefinition, ModelDefinitionError, TruncationPolicy,
    capabilities::{
        ModelCapabilities, ModelInputCapability, ModelInputLimits, ModelInputSource, ModelModality,
        ToolCapabilities,
    },
    effort_parameter,
    family::{ModelFamily, ModelInstanceSpec},
    info::{
        MediaRepresentation, MediaWireFormat, ModelMediaInputProfile, ModelProtocolOptions,
        ModelRequestProfile, ModelTransportProfile, ResponsesRequestOptions, TruncationMode,
    },
    pricing::{ModelPricing, TokenPriceTier},
};

mod gpt_5_6_luna;
mod gpt_5_6_sol;
mod gpt_5_6_terra;
mod gpt_6_1_sol;
mod gpt_6_1_terra;
mod gpt_6_2_astra;
mod gpt_6_2_sol;
mod gpt_6_astra;
mod gpt_6_luna;
mod gpt_6_sol;

const EXTENDED_CONTEXT: u64 = 1_050_000;
const STANDARD_CONTEXT: u64 = 272_000;
const COMMON_EFFORTS: &[&str] = &["low", "medium", "high", "xhigh", "max"];
const OPTIONAL_EFFORTS: &[&str] = &["none", "low", "medium", "high", "xhigh", "max"];
const PRICING_SOURCE: &str = "https://developers.openai.com/api/docs/pricing";
const SOL_TIERS: [TokenPriceTier; 2] = context_tiers(
    TokenPriceTier::flat(2.0, 10.0, Some(0.1), Some(2.5)),
    TokenPriceTier::flat(4.0, 15.0, Some(0.2), Some(5.0)),
);

const fn context_tiers(standard: TokenPriceTier, extended: TokenPriceTier) -> [TokenPriceTier; 2] {
    let threshold = STANDARD_CONTEXT + 1;
    [
        TokenPriceTier {
            input_until: Some(threshold),
            ..standard
        },
        TokenPriceTier {
            input_from: threshold,
            ..extended
        },
    ]
}

struct Definition {
    id: &'static str,
    name: &'static str,
    description: &'static str,
    context: u64,
    max_output_tokens: Option<u64>,
    auto_compact_token_limit: Option<u64>,
    efforts: &'static [&'static str],
    default_effort: Option<&'static str>,
    cache_write_tokens: bool,
    tiers: [TokenPriceTier; 2],
    pricing_source: &'static str,
    verified_at: i64,
}

impl Definition {
    fn instantiate(&self, family: &ModelFamily) -> ModelDefinition {
        let mut model = family.instantiate(ModelInstanceSpec {
            model_id: self.id,
            display_name: self.name,
            description: self.description,
            context_window: self.context,
            max_context_window: self.context,
            max_output_tokens: self.max_output_tokens,
            pricing: ModelPricing::Rates {
                currency: "USD".into(),
                tiers: self.tiers.to_vec(),
                weekly_adjustment: None,
                source: self.pricing_source.into(),
                verified_at: self.verified_at,
            },
        });
        model.base.auto_compact_token_limit = self.auto_compact_token_limit;
        model.extra.capabilities.prompt_cache.cache_write_tokens = self.cache_write_tokens;
        model.set_parameters(vec![effort_parameter(
            "reasoning.effort",
            self.efforts,
            self.default_effort,
        )]);
        model
    }
}

fn family() -> ModelFamily {
    let sources = vec![ModelInputSource::Local, ModelInputSource::RemoteUrl];
    let media = |modality, wire| ModelMediaInputProfile {
        modality,
        wire,
        first_send: vec![MediaRepresentation::RemoteUrl, MediaRepresentation::DataUrl],
        replay: vec![MediaRepresentation::DataUrl],
    };
    ModelFamily {
        capabilities: ModelCapabilities {
            temperature: false,
            reasoning: true,
            web_search: true,
            input: vec![
                ModelInputCapability::text(),
                ModelInputCapability::media(ModelModality::Image, sources.clone()),
                ModelInputCapability {
                    modality: ModelModality::File,
                    sources,
                    limits: ModelInputLimits {
                        max_bytes: Some(50_000_000),
                        max_total_bytes: Some(50_000_000),
                        media_types: vec!["application/pdf".into(), "text/plain".into()],
                        ..Default::default()
                    },
                },
            ],
            tools: ToolCapabilities {
                function_calling: true,
                custom_tools: true,
                freeform_tools: true,
                programmatic_tool_calling: true,
            },
            ..ModelCapabilities::text_only()
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
        transport: ModelTransportProfile::responses_websocket(),
        request_profile: ModelRequestProfile {
            protocol: ModelProtocolOptions::Responses(ResponsesRequestOptions {
                programmatic_tool_calling: true,
                ..Default::default()
            }),
            media: vec![
                media(ModelModality::Image, MediaWireFormat::ResponsesInputImage),
                media(ModelModality::File, MediaWireFormat::ResponsesInputFile),
            ],
            ..Default::default()
        },
    }
}

static CATALOG: LazyLock<Result<BundledModelDefinition, ModelDefinitionError>> =
    LazyLock::new(|| {
        let family = family();
        let models = [
            gpt_6_2_astra::MODEL,
            gpt_6_2_sol::MODEL,
            gpt_6_astra::MODEL,
            gpt_6_1_sol::MODEL,
            gpt_6_sol::MODEL,
            gpt_6_1_terra::MODEL,
            gpt_6_luna::MODEL,
            gpt_5_6_sol::MODEL,
            gpt_5_6_terra::MODEL,
            gpt_5_6_luna::MODEL,
        ]
        .iter()
        .map(|model| model.instantiate(&family))
        .collect();
        BundledModelDefinition::new(models, gpt_6_2_sol::MODEL.id, Some("medium"))
    });

pub fn bundled_definition() -> Result<BundledModelDefinition, ModelDefinitionError> {
    CATALOG.clone()
}
