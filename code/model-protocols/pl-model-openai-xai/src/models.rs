use std::sync::LazyLock;

use pl_model_openai_wire::model::{
    BundledModelDefinition, MediaSendOrder, ModelDefinition, ModelDefinitionError,
    capabilities::{
        ModelCapabilities, ModelInputCapability, ModelInputLimits, ModelInputSource, ModelModality,
        ToolCapabilities,
    },
    effort_parameter,
    family::{ModelFamily, ModelInstanceSpec},
    info::{MediaWireFormat, ModelRequestProfile, ModelTransportProfile, TruncationMode},
    pricing::{ModelPricing, TokenPriceTier},
};

const RECOMMENDED_MODEL: &str = "grok-4.7";
const COMMON_EFFORTS: &[&str] = &["low", "medium", "high", "xhigh"];
const COMMON_RATES: [TokenPriceTier; 2] = context_tiers(
    TokenPriceTier::flat(2.0, 6.0, Some(0.5), None),
    TokenPriceTier::flat(4.0, 12.0, Some(1.0), None),
);

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

struct Definition {
    id: &'static str,
    name: &'static str,
    description: &'static str,
    context: u64,
    efforts: &'static [&'static str],
    rates: [TokenPriceTier; 2],
}

const MODELS: &[Definition] = &[
    Definition {
        id: RECOMMENDED_MODEL,
        name: "Grok 4.7",
        description: "xAI flagship model for coding, agentic tool calling and knowledge work.",
        context: 500_000,
        efforts: COMMON_EFFORTS,
        rates: COMMON_RATES,
    },
    Definition {
        id: "grok-4.6",
        name: "Grok 4.6",
        description: "xAI coding and agentic model with the same context and rates as Grok 4.7.",
        context: 500_000,
        efforts: COMMON_EFFORTS,
        rates: COMMON_RATES,
    },
    Definition {
        id: "grok-4.5",
        name: "Grok 4.5",
        description: "xAI coding and engineering model. xhigh effort is treated as high by the provider.",
        context: 500_000,
        efforts: &["low", "medium", "high"],
        rates: context_tiers(
            TokenPriceTier::flat(2.0, 6.0, Some(0.3), None),
            TokenPriceTier::flat(4.0, 12.0, Some(0.6), None),
        ),
    },
    Definition {
        id: "grok-4.3",
        name: "Grok 4.3",
        description: "xAI long-context model with configurable reasoning, including none.",
        context: 1_000_000,
        efforts: &["none", "low", "medium", "high", "xhigh"],
        rates: context_tiers(
            TokenPriceTier::flat(1.25, 2.5, Some(0.2), None),
            TokenPriceTier::flat(2.5, 5.0, Some(0.4), None),
        ),
    },
    Definition {
        id: "grok-build-0.1",
        name: "Grok Build 0.1",
        description: "xAI fast model for agentic coding workflows.",
        context: 256_000,
        efforts: &[],
        rates: context_tiers(
            TokenPriceTier::flat(1.0, 2.0, Some(0.2), None),
            TokenPriceTier::flat(2.0, 4.0, Some(0.4), None),
        ),
    },
];

impl Definition {
    fn instantiate(&self, family: &ModelFamily) -> ModelDefinition {
        let mut model = family.instantiate(ModelInstanceSpec {
            model_id: self.id,
            display_name: self.name,
            description: self.description,
            context_window: self.context,
            max_context_window: self.context,
            max_output_tokens: None,
            pricing: ModelPricing::Rates {
                currency: "USD".into(),
                tiers: self.rates.to_vec(),
                weekly_adjustment: None,
                source: "https://docs.x.ai/developers/pricing".into(),
                verified_at: 1_760_227_200,
            },
        });
        if !self.efforts.is_empty() {
            model.extra.capabilities.reasoning = true;
            model.set_parameters(vec![effort_parameter(
                "reasoning.effort",
                self.efforts,
                None,
            )]);
        }
        model
    }
}

fn family() -> ModelFamily {
    ModelFamily {
        id: "grok-responses",
        capabilities: ModelCapabilities {
            temperature: false,
            input: vec![
                ModelInputCapability::text(),
                ModelInputCapability {
                    modality: ModelModality::Image,
                    sources: vec![ModelInputSource::Local, ModelInputSource::RemoteUrl],
                    limits: ModelInputLimits {
                        max_bytes: Some(20 * 1024 * 1024),
                        media_types: vec!["image/jpeg".into(), "image/png".into()],
                        ..Default::default()
                    },
                },
            ],
            tools: ToolCapabilities {
                function_calling: true,
                parallel_tool_calls: true,
                ..Default::default()
            },
            ..ModelCapabilities::text_only()
        },
        truncation_mode: TruncationMode::Tokens,
        truncation_limit: 10_000,
        parameters: Vec::new(),
        transport: ModelTransportProfile::responses_http(),
        request_profile: ModelRequestProfile::responses().with_image_media(
            MediaWireFormat::ResponsesInputImage,
            MediaSendOrder::RemoteUrlFirst,
        ),
        base_instructions: String::new(),
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
