use super::{ModelCapabilities, ModelParameter, observation::ModelObservation};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModelMetadata<Binding = ()> {
    pub model_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub observation: Option<ModelObservation>,
    pub display_name: String,
    pub description: Option<String>,

    pub context_window: Option<u64>,
    pub max_context_window: Option<u64>,
    pub auto_compact_token_limit: Option<u64>,

    pub default_temperature: Option<f32>,
    pub max_output_tokens: Option<u64>,
    pub pricing: super::pricing::ModelPricing,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub parameters: Vec<ModelParameter>,

    /// 模型使用的 API 协议、可用连接方式及默认连接方式。
    pub binding: Binding,

    #[serde(default)]
    pub capabilities: ModelCapabilities,

    #[serde(default)]
    pub truncation_policy: TruncationPolicy,

    #[serde(default)]
    pub base_instructions: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TruncationPolicy {
    pub mode: TruncationMode,
    pub limit: u64,
}

impl Default for TruncationPolicy {
    fn default() -> Self {
        Self {
            mode: TruncationMode::Bytes,
            limit: 10_000,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TruncationMode {
    Bytes,
    Tokens,
}
