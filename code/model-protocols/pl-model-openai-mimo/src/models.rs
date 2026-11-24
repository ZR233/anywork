//! Xiaomi MiMo 内建模型目录（OpenAI-compatible Chat Completions）。

use pl_model_wire::model::capabilities::{
    ModelCapabilities, ModelInputCapability, ModelInputSource, ModelModality,
    PromptCacheModelCapabilities, ReasoningInterleaved, ToolCapabilities,
};
use pl_model_wire::model::family::{ModelFamily, ModelInstanceSpec};
use pl_model_wire::model::info::{
    MaxTokensField, MediaWireFormat, ModelDefinition, ModelRequestProfile, ModelTransportProfile,
    TruncationMode,
};
use pl_model_wire::model::parameter::ModelParameter;
use pl_model_wire::model::pricing::{ModelPricing, TokenPriceTier};
use pl_model_wire::model::{CodexModel, TruncationPolicy};

const MIMO_DEFAULT_MODEL_MODEL_IDS: &[&str] = &["mimo-v2.5-pro", "mimo-v2.5"];

pub fn mimo_default_model_ids() -> &'static [&'static str] {
    MIMO_DEFAULT_MODEL_MODEL_IDS
}

pub fn models() -> Vec<ModelDefinition> {
    let mimo_text = mimo_text_family();
    let mimo_vision = mimo_vision_family();
    vec![
        mimo_text.instantiate(ModelInstanceSpec {
            model_id: "mimo-v2.5-pro",
            display_name: "MiMo V2.5 Pro",
            description: "Xiaomi MiMo flagship model for long-horizon agent work.",
            context_window: 1_000_000,
            max_context_window: 1_000_000,
            max_output_tokens: Some(131_072),
            pricing: ModelPricing::published("CNY", vec![TokenPriceTier::flat(3.0, 6.0, Some(0.025), None)], "https://mimo.mi.com/docs/en-US/price/pay-as-you-go"),
        }),
        mimo_vision.instantiate(ModelInstanceSpec {
            model_id: "mimo-v2.5",
            display_name: "MiMo V2.5",
            description:
                "Xiaomi MiMo full-modal agent model with a one-million-token context window.",
            context_window: 1_000_000,
            max_context_window: 1_000_000,
            max_output_tokens: Some(32_768),
            pricing: ModelPricing::published("CNY", vec![TokenPriceTier::flat(1.0, 2.0, Some(0.02), None)], "https://mimo.mi.com/docs/en-US/price/pay-as-you-go"),
        }),
    ]
}

fn mimo_text_family() -> ModelFamily {
    mimo_family(mimo_text_capabilities(), Vec::new())
}

fn mimo_vision_family() -> ModelFamily {
    mimo_family(
        mimo_vision_capabilities(),
        pl_model_wire::model::image_media_profiles(
            MediaWireFormat::ChatImageUrl,
            pl_model_wire::model::MediaSendOrder::DataUrlOnly,
        ),
    )
}

/// MiMo 共享 family 元数据；视觉变体叠加本地图片输入能力。
fn mimo_family(
    capabilities: ModelCapabilities,
    media: Vec<pl_model_wire::model::ModelMediaInputProfile>,
) -> ModelFamily {
    ModelFamily {
        capabilities,
        base: CodexModel {
            supports_parallel_tool_calls: Some(false),
            truncation_policy: TruncationPolicy {
                mode: TruncationMode::Tokens,
                limit: 10_000,
            },
            ..Default::default()
        },
        parameters: vec![mimo_effort_parameter()],
        transport: ModelTransportProfile::chat_completions_http(),
        request_profile: ModelRequestProfile {
            protocol: pl_model_wire::model::ModelProtocolOptions::ChatCompletions(
                pl_model_wire::model::ChatRequestOptions {
                    max_tokens_field: MaxTokensField::MaxCompletionTokens,
                    ..Default::default()
                },
            ),
            media,
            ..ModelRequestProfile::default()
        },
    }
}

/// MiMo thinking 开关；官方 Chat API 只声明 `thinking.type`。
fn mimo_effort_parameter() -> ModelParameter {
    ModelParameter {
        candidate_display_names: Default::default(),
        default: None,
        name: "effort".to_string(),
        label: Some("Thinking".to_string()),
        candidates: vec!["disabled".to_string(), "enabled".to_string()],
        wire: ["disabled", "enabled"]
            .into_iter()
            .map(|value| {
                (
                    value.to_string(),
                    pl_model_wire::model::wire_set_one("thinking.type", value),
                )
            })
            .collect(),
    }
}

fn mimo_text_capabilities() -> ModelCapabilities {
    mimo_capabilities(vec![ModelInputCapability::text()])
}

fn mimo_vision_capabilities() -> ModelCapabilities {
    mimo_capabilities(vec![
        ModelInputCapability::text(),
        ModelInputCapability::media(ModelModality::Image, vec![ModelInputSource::Local]),
    ])
}

fn mimo_capabilities(input: Vec<ModelInputCapability>) -> ModelCapabilities {
    ModelCapabilities {
        streaming: true,
        temperature: false,
        reasoning: true,
        web_search: false,
        input,
        output: vec![ModelModality::Text],
        tools: ToolCapabilities {
            function_calling: true,
            custom_tools: false,
            freeform_tools: false,
            programmatic_tool_calling: false,
        },
        interleaved: Some(ReasoningInterleaved {
            field: pl_model_wire::model::reasoning_fields::REASONING_CONTENT,
        }),
        prompt_cache: PromptCacheModelCapabilities::default(),
        instruction_snapshot_overrides: false,
        native_context_family: None,
    }
}
