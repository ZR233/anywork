use super::InferenceTiming;
use serde::{Deserialize, Serialize};

use crate::PromptPrefixChangedReason;
use crate::model::InferenceAccounting;

/// 单次模型调用的 provider 原始 token 分类。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InferenceTokenUsage {
    pub prompt_tokens: u64,
    pub cached_prompt_tokens: u64,
    #[serde(default)]
    pub cache_write_tokens: u64,
    pub completion_tokens: u64,
    pub reasoning_tokens: u64,
    pub total_tokens: u64,
}

/// 单次 inference 及其直接工具批次的脱敏编排收益指标。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InferenceOrchestrationMetrics {
    #[serde(default)]
    pub tool_schema_estimated_tokens: u64,
    #[serde(default)]
    pub tool_result_estimated_tokens: u64,
    #[serde(default)]
    pub tool_calls: u64,
    #[serde(default)]
    pub parallel_candidates: u64,
    #[serde(default)]
    pub actual_parallel_calls: u64,
    #[serde(default)]
    pub tool_batch_elapsed_millis: u64,
    #[serde(default)]
    pub tool_execution_millis: u64,
    #[serde(default)]
    pub tool_critical_path_millis: u64,
    #[serde(default)]
    pub tool_cache_hits: u64,
    #[serde(default)]
    pub duplicate_suppressed: u64,
    #[serde(default)]
    pub program_count: u64,
    #[serde(default)]
    pub program_tool_calls: u64,
    #[serde(default)]
    pub transport_attempts: u64,
    #[serde(default)]
    pub continuation_attempts: u64,
    #[serde(default)]
    pub continuation_used: u64,
    #[serde(default)]
    pub continuation_invalid: u64,
    #[serde(default)]
    pub http_fallbacks: u64,
}

impl InferenceOrchestrationMetrics {
    pub fn is_empty(&self) -> bool {
        self == &Self::default()
    }

    pub fn parallel_saved_millis(&self) -> u64 {
        self.tool_execution_millis
            .saturating_sub(self.tool_batch_elapsed_millis)
    }

    pub fn merge(&mut self, other: &Self) {
        self.tool_schema_estimated_tokens = self
            .tool_schema_estimated_tokens
            .saturating_add(other.tool_schema_estimated_tokens);
        self.tool_result_estimated_tokens = self
            .tool_result_estimated_tokens
            .saturating_add(other.tool_result_estimated_tokens);
        self.tool_calls = self.tool_calls.saturating_add(other.tool_calls);
        self.parallel_candidates = self
            .parallel_candidates
            .saturating_add(other.parallel_candidates);
        self.actual_parallel_calls = self
            .actual_parallel_calls
            .saturating_add(other.actual_parallel_calls);
        self.tool_batch_elapsed_millis = self
            .tool_batch_elapsed_millis
            .saturating_add(other.tool_batch_elapsed_millis);
        self.tool_execution_millis = self
            .tool_execution_millis
            .saturating_add(other.tool_execution_millis);
        self.tool_critical_path_millis = self
            .tool_critical_path_millis
            .saturating_add(other.tool_critical_path_millis);
        self.tool_cache_hits = self.tool_cache_hits.saturating_add(other.tool_cache_hits);
        self.duplicate_suppressed = self
            .duplicate_suppressed
            .saturating_add(other.duplicate_suppressed);
        self.program_count = self.program_count.saturating_add(other.program_count);
        self.program_tool_calls = self
            .program_tool_calls
            .saturating_add(other.program_tool_calls);
        self.transport_attempts = self
            .transport_attempts
            .saturating_add(other.transport_attempts);
        self.continuation_attempts = self
            .continuation_attempts
            .saturating_add(other.continuation_attempts);
        self.continuation_used = self
            .continuation_used
            .saturating_add(other.continuation_used);
        self.continuation_invalid = self
            .continuation_invalid
            .saturating_add(other.continuation_invalid);
        self.http_fallbacks = self.http_fallbacks.saturating_add(other.http_fallbacks);
    }
}

/// 一次推理从目录选择到 wire 请求和厂商响应的冻结模型身份。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InferenceModelObservation {
    pub configured_model: String,
    pub sent_model: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reported_model: Option<String>,
}

/// SQLite 中以 `inference_id` 幂等保存的单次计费记录。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct InferenceBillingRecord {
    pub inference_id: String,
    /// Producer-defined usage purpose; absent when historical provenance is unknown.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub purpose: Option<String>,
    /// 冻结的稳定账号身份；旧记录无法确定账号时为空。
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub account_id: String,
    /// 仅用于展示，不参与统计归组。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub account_display_name: Option<String>,
    /// 冻结的目录配置 model_id；旧记录缺少该事实时保持 `None`，不用发送模型冒充。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_observation: Option<InferenceModelObservation>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context_window: Option<u64>,
    pub accounting: InferenceAccounting,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt_generation: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt_cache_policy: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prefix_changed_reason: Option<PromptPrefixChangedReason>,
    #[serde(
        default,
        skip_serializing_if = "InferenceOrchestrationMetrics::is_empty"
    )]
    pub orchestration: InferenceOrchestrationMetrics,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timing: Option<InferenceTiming>,
    pub recorded_at: i64,
}
