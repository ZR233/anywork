use std::sync::LazyLock;

use pl_model_wire::model::{
    BundledModelDefinition, MediaSendOrder, ModelDefinitionError,
    capabilities::{
        ModelCapabilities, ModelInputCapability, ModelInputLimits, ModelInputSource, ModelModality,
        ReasoningInterleaved, ToolCapabilities,
    },
    effort_parameter,
    family::{ModelFamily, ModelInstanceSpec},
    info::{MediaWireFormat, ModelRequestProfile, ModelTransportProfile, TruncationMode},
    pricing::{DailyPriceWindow, ModelPricing, TokenPriceTier, WeeklyPriceAdjustment},
    reasoning_fields::REASONING_CONTENT,
};
use pl_model_wire::model::{CodexModel, TruncationPolicy};
use serde_json::{Map, Value};

const FLASH: &str = "deepseek-flash";
const CONTEXT: u64 = 1_000_000;
const MAX_OUTPUT_TOKENS: Option<u64> = Some(384_000);

fn pricing(rate: TokenPriceTier) -> ModelPricing {
    ModelPricing::Rates {
        currency: "CNY".into(),
        tiers: vec![rate],
        weekly_adjustment: Some(WeeklyPriceAdjustment {
            utc_offset_minutes: 8 * 60,
            weekdays: vec![1, 2, 3, 4, 5],
            windows: vec![
                DailyPriceWindow {
                    start_minute: 9 * 60,
                    end_minute: 12 * 60,
                },
                DailyPriceWindow {
                    start_minute: 14 * 60,
                    end_minute: 18 * 60,
                },
            ],
            multiplier: 2.0,
        }),
        source: "https://api-docs.deepseek.com/zh-cn/quick_start/pricing/".into(),
        verified_at: 1_789_084_800,
    }
}

fn text_family() -> ModelFamily {
    let mut request_profile = ModelRequestProfile::responses();
    request_profile.body.insert(
        "thinking".into(),
        Value::Object(Map::from_iter([(
            "type".into(),
            Value::String("enabled".into()),
        )])),
    );
    ModelFamily {
        capabilities: ModelCapabilities {
            temperature: false,
            reasoning: true,
            interleaved: Some(ReasoningInterleaved {
                field: REASONING_CONTENT,
            }),
            instruction_snapshot_overrides: true,
            tools: ToolCapabilities {
                function_calling: true,
                ..Default::default()
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
        parameters: vec![effort_parameter(
            "reasoning_effort",
            &["low", "high", "max"],
            None,
        )],
        transport: ModelTransportProfile::responses_http(),
        request_profile,
    }
    .with_responses_files(
        &["text/plain", "application/pdf"],
        MediaSendOrder::ProviderFileFirst,
    )
}

fn image_family(mut family: ModelFamily) -> ModelFamily {
    const MAX_IMAGE_BYTES: u64 = 32 * 1024 * 1024;
    family.capabilities.input.push(ModelInputCapability {
        modality: ModelModality::Image,
        sources: vec![ModelInputSource::Local, ModelInputSource::RemoteUrl],
        limits: ModelInputLimits {
            max_count: Some(600),
            max_bytes: Some(MAX_IMAGE_BYTES),
            max_total_bytes: Some(MAX_IMAGE_BYTES),
            max_width: Some(4096),
            max_height: Some(4096),
            media_types: ["image/jpeg", "image/png", "image/gif", "image/webp"]
                .map(str::to_owned)
                .to_vec(),
        },
    });
    family
        .request_profile
        .media
        .extend(pl_model_wire::model::image_media_profiles(
            MediaWireFormat::ResponsesInputImage,
            MediaSendOrder::ProviderFileFirst,
        ));
    family
}

static CATALOG: LazyLock<Result<BundledModelDefinition, ModelDefinitionError>> =
    LazyLock::new(|| {
        let text = text_family();
        let flash = image_family(text.clone()).instantiate(ModelInstanceSpec {
            model_id: FLASH,
            display_name: "DeepSeek V4.1 Flash",
            description: "DeepSeek fast multimodal reasoning model with thinking mode.",
            context_window: CONTEXT,
            max_context_window: CONTEXT,
            max_output_tokens: MAX_OUTPUT_TOKENS,
            pricing: pricing(TokenPriceTier::flat(1.0, 4.0, Some(0.02), None)),
        });
        let pro = text.instantiate(ModelInstanceSpec {
            model_id: "deepseek-v4-pro",
            display_name: "DeepSeek V4 Pro",
            description: "DeepSeek flagship reasoning model with thinking mode.",
            context_window: CONTEXT,
            max_context_window: CONTEXT,
            max_output_tokens: MAX_OUTPUT_TOKENS,
            pricing: pricing(TokenPriceTier::flat(4.5, 13.5, Some(0.15), None)),
        });
        BundledModelDefinition::new(vec![flash, pro], FLASH, Some("high"))
    });

pub fn bundled_definition() -> Result<BundledModelDefinition, ModelDefinitionError> {
    CATALOG.clone()
}
