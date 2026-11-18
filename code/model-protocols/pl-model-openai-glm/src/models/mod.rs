//! Zhipu GLM 内建模型目录：通用 API 走 Chat Completions HTTP（effort 联动 thinking wire），
//! Coding Plan 的 OpenAI Response 协议端点走 Responses HTTP（effort 透传 `reasoning.effort`）。

use pl_model_openai_wire::model::pricing::{ModelPricing, TokenPriceTier};
use std::collections::BTreeMap;

use serde_json::Value;

use pl_model_openai_wire::model::capabilities::{
    ModelCapabilities, ModelInputCapability, ModelInputSource, ModelModality,
    PromptCacheModelCapabilities, ReasoningInterleaved, ToolCapabilities,
};
use pl_model_openai_wire::model::family::{ModelFamily, ModelInstanceSpec};
use pl_model_openai_wire::model::info::{
    MediaWireFormat, ModelInfo, ModelRequestProfile, ModelTransportProfile, TruncationMode,
};
use pl_model_openai_wire::model::parameter::{ModelParameter, ParameterWire, WireAssignment};

const ZHIPU_GLM_DEFAULT_MODEL_MODEL_IDS: &[&str] = &[
    "glm-5.3",
    "glm-5.3-flash",
    "glm-5.2",
    "glm-5",
    "glm-5-turbo",
    "glm-4.7",
    "glm-4.7-flashx",
    "glm-4.7-flash",
];

pub fn zhipu_default_model_ids() -> &'static [&'static str] {
    ZHIPU_GLM_DEFAULT_MODEL_MODEL_IDS
}

const ZHIPU_GLM_RESPONSES_DEFAULT_MODEL_MODEL_IDS: &[&str] = &["glm-5.3", "glm-5.3-flash"];

pub fn zhipu_responses_default_model_ids() -> &'static [&'static str] {
    ZHIPU_GLM_RESPONSES_DEFAULT_MODEL_MODEL_IDS
}

mod glm_4_1v_thinking_flash;
mod glm_4_1v_thinking_flashx;
mod glm_4_5_air;
mod glm_4_5_airx;
mod glm_4_5_flash;
mod glm_4_6;
mod glm_4_6v;
mod glm_4_6v_flash;
mod glm_4_7;
mod glm_4_7_flash;
mod glm_4_7_flashx;
mod glm_4_flash_250414;
mod glm_4_flashx_250414;
mod glm_4_long;
mod glm_4v_flash;
mod glm_5;
mod glm_5_2;
mod glm_5_3;
mod glm_5_3_flash;
mod glm_5_turbo;
mod glm_5v_turbo;

struct Definition {
    id: &'static str,
    name: &'static str,
    description: &'static str,
    context: u64,
    max_output_tokens: Option<u64>,
    tiers: &'static [TokenPriceTier],
}

impl Definition {
    fn instantiate(&self, family: &ModelFamily) -> ModelInfo {
        let pricing = if self.tiers.is_empty() {
            ModelPricing::Unknown
        } else {
            ModelPricing::published(
                "CNY",
                self.tiers.to_vec(),
                "https://open.bigmodel.cn/pricing",
            )
        };
        family.instantiate(ModelInstanceSpec {
            model_id: self.id,
            display_name: self.name,
            description: self.description,
            context_window: self.context,
            max_context_window: self.context,
            max_output_tokens: self.max_output_tokens,
            pricing,
        })
    }
}

const fn context_tiers(short: TokenPriceTier, long: TokenPriceTier) -> [TokenPriceTier; 2] {
    const THRESHOLD: u64 = 32_000;
    [
        TokenPriceTier {
            input_until: Some(THRESHOLD),
            ..short
        },
        TokenPriceTier {
            input_from: THRESHOLD,
            ..long
        },
    ]
}

const fn context_output_tiers(
    short: TokenPriceTier,
    medium: TokenPriceTier,
    long: TokenPriceTier,
) -> [TokenPriceTier; 3] {
    let [short, long] = context_tiers(short, long);
    [
        TokenPriceTier {
            output_until: Some(200),
            ..short
        },
        TokenPriceTier {
            input_until: short.input_until,
            output_from: 200,
            ..medium
        },
        long,
    ]
}

pub fn models() -> Vec<ModelInfo> {
    let zhipu_glm53 = zhipu_glm53_family();
    let zhipu_glm53_flash = zhipu_glm53_flash_family();
    let zhipu_glm52 = zhipu_glm52_family();
    let zhipu_text = zhipu_text_family();
    let zhipu_vision = zhipu_vision_family();
    vec![
        glm_5_3::MODEL.instantiate(&zhipu_glm53),
        glm_5_3_flash::MODEL.instantiate(&zhipu_glm53_flash),
        glm_5_2::MODEL.instantiate(&zhipu_glm52),
        glm_5::MODEL.instantiate(&zhipu_text),
        glm_5_turbo::MODEL.instantiate(&zhipu_text),
        glm_4_7::MODEL.instantiate(&zhipu_text),
        glm_4_7_flashx::MODEL.instantiate(&zhipu_text),
        glm_4_6::MODEL.instantiate(&zhipu_text),
        glm_4_5_air::MODEL.instantiate(&zhipu_text),
        glm_4_5_airx::MODEL.instantiate(&zhipu_text),
        glm_4_long::MODEL.instantiate(&zhipu_text),
        glm_4_flashx_250414::MODEL.instantiate(&zhipu_text),
        glm_4_7_flash::MODEL.instantiate(&zhipu_text),
        glm_4_5_flash::MODEL.instantiate(&zhipu_text),
        glm_4_flash_250414::MODEL.instantiate(&zhipu_text),
        glm_5v_turbo::MODEL.instantiate(&zhipu_vision),
        glm_4_6v::MODEL.instantiate(&zhipu_vision),
        glm_4_1v_thinking_flashx::MODEL.instantiate(&zhipu_vision),
        glm_4_6v_flash::MODEL.instantiate(&zhipu_vision),
        glm_4_1v_thinking_flash::MODEL.instantiate(&zhipu_vision),
        glm_4v_flash::MODEL.instantiate(&zhipu_vision),
    ]
}

// ---- 家族预设 ----

fn zhipu_text_family() -> ModelFamily {
    zhipu_chat_family(
        "zhipu-text",
        zhipu_text_capabilities(),
        zhipu_plain_effort_parameter(),
    )
}

fn zhipu_glm52_family() -> ModelFamily {
    zhipu_chat_family(
        "zhipu-glm52",
        zhipu_text_capabilities(),
        zhipu_glm52_effort_parameter(),
    )
}

fn zhipu_glm53_family() -> ModelFamily {
    let mut family = zhipu_chat_family(
        "zhipu-glm53",
        zhipu_text_capabilities(),
        zhipu_glm53_effort_parameter(),
    );
    if let pl_model_openai_wire::model::ModelProtocolOptions::ChatCompletions(options) =
        &mut family.request_profile.protocol
    {
        options.tool_stream = true;
    }
    family
}

/// GLM-5.3-Flash 与 GLM-5.3 共用 effort wire，但官方归类为原生多模态模型。
fn zhipu_glm53_flash_family() -> ModelFamily {
    let mut family = zhipu_chat_family(
        "zhipu-glm53-flash",
        zhipu_vision_capabilities(),
        zhipu_glm53_effort_parameter(),
    );
    if let pl_model_openai_wire::model::ModelProtocolOptions::ChatCompletions(options) =
        &mut family.request_profile.protocol
    {
        options.tool_stream = true;
    }
    family.request_profile = family.request_profile.with_image_media(
        MediaWireFormat::ChatImageUrl,
        pl_model_openai_wire::model::MediaSendOrder::RemoteUrlFirst,
    );
    family
}

fn zhipu_vision_family() -> ModelFamily {
    let mut family = zhipu_chat_family(
        "zhipu-vision",
        zhipu_vision_capabilities(),
        zhipu_plain_effort_parameter(),
    );
    family.request_profile = family.request_profile.with_image_media(
        MediaWireFormat::ChatImageUrl,
        pl_model_openai_wire::model::MediaSendOrder::RemoteUrlFirst,
    );
    family
}

/// Zhipu Chat 家族共享骨架：Chat Completions HTTP + parallel tool calls base profile。
fn zhipu_chat_family(
    id: &'static str,
    capabilities: ModelCapabilities,
    effort_parameter: ModelParameter,
) -> ModelFamily {
    ModelFamily {
        id,
        capabilities,
        truncation_mode: TruncationMode::Tokens,
        truncation_limit: 10_000,
        parameters: vec![effort_parameter],
        transport: ModelTransportProfile::chat_completions_http(),
        request_profile: chat_parallel_request_profile(),
        base_instructions: String::new(),
    }
}

fn chat_parallel_request_profile() -> ModelRequestProfile {
    ModelRequestProfile {
        protocol: pl_model_openai_wire::model::ModelProtocolOptions::ChatCompletions(
            pl_model_openai_wire::model::ChatRequestOptions {
                parallel_tool_calls: true,
                ..Default::default()
            },
        ),
        ..ModelRequestProfile::default()
    }
}

// ---- effort 参数声明 ----

/// Zhipu 普通模型 effort：候选值按弱到强 none/enabled，映射 `thinking.type` 开关。
fn zhipu_plain_effort_parameter() -> ModelParameter {
    ModelParameter {
        default: None,
        name: "effort".to_string(),
        label: None,
        candidates: vec!["none".to_string(), "enabled".to_string()],
        wire: BTreeMap::from([
            (
                "enabled".to_string(),
                ParameterWire {
                    set: vec![
                        WireAssignment {
                            path: "thinking.type".to_string(),
                            value: Value::String("enabled".to_string()),
                        },
                        WireAssignment {
                            path: "thinking.clear_thinking".to_string(),
                            value: Value::Bool(false),
                        },
                    ],
                    remove: Vec::new(),
                },
            ),
            (
                "none".to_string(),
                ParameterWire {
                    set: vec![WireAssignment {
                        path: "thinking.type".to_string(),
                        value: Value::String("disabled".to_string()),
                    }],
                    remove: Vec::new(),
                },
            ),
        ]),
    }
}

/// GLM-5.2 effort：候选值按弱到强 none/high/max，联动 `reasoning_effort` 与 `thinking`。
fn zhipu_glm52_effort_parameter() -> ModelParameter {
    ModelParameter {
        default: None,
        name: "effort".to_string(),
        label: None,
        candidates: vec!["none".to_string(), "high".to_string(), "max".to_string()],
        wire: BTreeMap::from([
            ("high".to_string(), glm_reasoning_effort_wire("high")),
            ("max".to_string(), glm_reasoning_effort_wire("max")),
            (
                "none".to_string(),
                ParameterWire {
                    set: vec![WireAssignment {
                        path: "thinking.type".to_string(),
                        value: Value::String("disabled".to_string()),
                    }],
                    remove: vec!["reasoning_effort".to_string()],
                },
            ),
        ]),
    }
}

/// GLM-5.3 effort：候选值按弱到强 low/high/max，三档共用「始终思考」wire，仅切换 reasoning_effort。
fn zhipu_glm53_effort_parameter() -> ModelParameter {
    ModelParameter {
        default: None,
        name: "effort".to_string(),
        label: None,
        candidates: vec!["low".to_string(), "high".to_string(), "max".to_string()],
        wire: BTreeMap::from([
            ("high".to_string(), glm_reasoning_effort_wire("high")),
            ("low".to_string(), glm_reasoning_effort_wire("low")),
            ("max".to_string(), glm_reasoning_effort_wire("max")),
        ]),
    }
}

/// GLM-5.2/GLM-5.3 共用 wire：设 reasoning_effort + 开启 thinking。
fn glm_reasoning_effort_wire(effort: &str) -> ParameterWire {
    ParameterWire {
        set: vec![
            WireAssignment {
                path: "reasoning_effort".to_string(),
                value: Value::String(effort.to_string()),
            },
            WireAssignment {
                path: "thinking.type".to_string(),
                value: Value::String("enabled".to_string()),
            },
            WireAssignment {
                path: "thinking.clear_thinking".to_string(),
                value: Value::Bool(false),
            },
        ],
        remove: Vec::new(),
    }
}

// ---- 能力矩阵 ----

fn zhipu_text_capabilities() -> ModelCapabilities {
    zhipu_capabilities(vec![ModelInputCapability::text()])
}

fn zhipu_vision_capabilities() -> ModelCapabilities {
    zhipu_capabilities(vec![
        ModelInputCapability::text(),
        ModelInputCapability::media(
            ModelModality::Image,
            vec![ModelInputSource::Local, ModelInputSource::RemoteUrl],
        ),
    ])
}

fn zhipu_capabilities(input: Vec<ModelInputCapability>) -> ModelCapabilities {
    ModelCapabilities {
        streaming: true,
        temperature: false,
        reasoning: true,
        web_search: false,
        input,
        output: vec![ModelModality::Text],
        tools: ToolCapabilities {
            function_calling: true,
            parallel_tool_calls: true,
            custom_tools: false,
            freeform_tools: false,
            programmatic_tool_calling: false,
        },
        interleaved: Some(ReasoningInterleaved {
            field: pl_model_openai_wire::model::reasoning_fields::REASONING_CONTENT,
        }),
        prompt_cache: PromptCacheModelCapabilities::default(),
        instruction_snapshot_overrides: false,
        native_context_family: None,
    }
}

// ---- Coding Plan Responses 目录 ----

/// Coding Plan 的 OpenAI Response 协议端点当前按官方文档只承载 GLM-5.3 与 GLM-5.3-Flash。
pub fn responses_models() -> Vec<ModelInfo> {
    vec![
        glm_5_3::MODEL.instantiate(&zhipu_responses_text_family()),
        glm_5_3_flash::MODEL.instantiate(&zhipu_responses_flash_family()),
    ]
}

fn zhipu_responses_text_family() -> ModelFamily {
    zhipu_responses_family("zhipu-glm53-responses", zhipu_text_capabilities(), false)
}

fn zhipu_responses_flash_family() -> ModelFamily {
    zhipu_responses_family(
        "zhipu-glm53-flash-responses",
        zhipu_vision_capabilities(),
        true,
    )
}

/// Coding Plan Responses 家族骨架：Responses HTTP + `reasoning.effort` wire。
fn zhipu_responses_family(
    id: &'static str,
    capabilities: ModelCapabilities,
    image: bool,
) -> ModelFamily {
    let mut capabilities = capabilities;
    capabilities.interleaved = None;
    let mut request_profile = ModelRequestProfile::responses();
    if image {
        request_profile = request_profile.with_image_media(
            MediaWireFormat::ResponsesInputImage,
            pl_model_openai_wire::model::MediaSendOrder::RemoteUrlFirst,
        );
    }
    ModelFamily {
        id,
        capabilities,
        truncation_mode: TruncationMode::Tokens,
        truncation_limit: 10_000,
        parameters: vec![pl_model_openai_wire::model::effort_parameter(
            "reasoning.effort",
            &["low", "high", "max"],
            None,
        )],
        transport: ModelTransportProfile::responses_http(),
        request_profile,
        base_instructions: String::new(),
    }
}
