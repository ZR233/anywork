use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

/// The Codex /models entry. Additional provider fields retain their native JSON structure.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct CodexModel {
    pub slug: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub supported_reasoning_levels: Option<Vec<ReasoningLevel>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_reasoning_level: Option<String>,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub display_name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context_window: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_context_window: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auto_compact_token_limit: Option<u64>,
    #[serde(default, skip_serializing_if = "is_default")]
    pub model_messages: ModelMessages,
    #[serde(default, skip_serializing_if = "is_default")]
    pub truncation_policy: TruncationPolicy,
    #[serde(flatten)]
    pub fields: Map<String, Value>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ModelMessages {
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub instructions_template: String,
    #[serde(flatten)]
    pub fields: Map<String, Value>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ReasoningLevel {
    pub effort: String,
    #[serde(flatten)]
    pub fields: Map<String, Value>,
}

fn is_default<T: Default + PartialEq>(value: &T) -> bool {
    *value == T::default()
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
