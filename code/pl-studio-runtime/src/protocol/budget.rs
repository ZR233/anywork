use serde::{Deserialize, Serialize};

/// Kind of runtime budget that stopped a turn or agent.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BudgetLimitKind {
    ModelStep,
    ToolCall,
    Wait,
    WallClock,
    AgentCount,
    AgentDepth,
    Finalization,
}

impl BudgetLimitKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::ModelStep => "modelStep",
            Self::ToolCall => "toolCall",
            Self::Wait => "wait",
            Self::WallClock => "wallClock",
            Self::AgentCount => "agentCount",
            Self::AgentDepth => "agentDepth",
            Self::Finalization => "finalization",
        }
    }
}

/// Snapshot of consumed turn budgets.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BudgetUsage {
    pub model_steps: u32,
    pub tool_calls: u32,
    pub wait_calls: u32,
    pub elapsed_ms: u64,
}

/// 一次 budget 终止的类型化用量快照。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BudgetLimitSnapshot {
    pub kind: BudgetLimitKind,
    pub usage: BudgetUsage,
}

/// Token usage snapshot shared by product projection and internal trace mapping.
///
/// Independent of [`pl_model::completion::InferenceTokenUsage`] to keep this product projection DTO
/// decoupled from the model-layer accounting type.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TokenUsageSnapshot {
    pub prompt_tokens: u64,
    pub completion_tokens: u64,
    pub cached_prompt_tokens: u64,
    #[serde(default)]
    pub cache_write_tokens: u64,
    #[serde(default)]
    pub cache_miss_tokens: u64,
    #[serde(default)]
    pub reasoning_tokens: u64,
    #[serde(default)]
    pub inference_count: u64,
    pub total_tokens: u64,
}
