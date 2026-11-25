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

/// 单次 inference 实际观测到的模型输出与传输计数。
///
/// 工具在模型调用结束后才执行，其并发与耗时不属于这份不可变回执。
/// 未采集项保持缺失；历史回执中已编码的可选值保留原样，避免改变原计量的幂等载荷。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InferenceOrchestrationMetrics {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_schema_estimated_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_result_estimated_tokens: Option<u64>,
    #[serde(default)]
    pub tool_calls: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parallel_candidates: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub actual_parallel_calls: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_batch_elapsed_millis: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_execution_millis: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_critical_path_millis: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_cache_hits: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duplicate_suppressed: Option<u64>,
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

    pub fn parallel_saved_millis(&self) -> Option<u64> {
        self.tool_execution_millis
            .zip(self.tool_batch_elapsed_millis)
            .map(|(execution, elapsed)| execution.saturating_sub(elapsed))
    }

    pub fn merge(&mut self, other: &Self) {
        self.tool_schema_estimated_tokens = self
            .tool_schema_estimated_tokens
            .zip(other.tool_schema_estimated_tokens)
            .map(|(left, right)| left.saturating_add(right));
        self.tool_result_estimated_tokens = self
            .tool_result_estimated_tokens
            .zip(other.tool_result_estimated_tokens)
            .map(|(left, right)| left.saturating_add(right));
        self.tool_calls = self.tool_calls.saturating_add(other.tool_calls);
        self.parallel_candidates = self
            .parallel_candidates
            .zip(other.parallel_candidates)
            .map(|(left, right)| left.saturating_add(right));
        self.actual_parallel_calls = self
            .actual_parallel_calls
            .zip(other.actual_parallel_calls)
            .map(|(left, right)| left.saturating_add(right));
        self.tool_batch_elapsed_millis = self
            .tool_batch_elapsed_millis
            .zip(other.tool_batch_elapsed_millis)
            .map(|(left, right)| left.saturating_add(right));
        self.tool_execution_millis = self
            .tool_execution_millis
            .zip(other.tool_execution_millis)
            .map(|(left, right)| left.saturating_add(right));
        self.tool_critical_path_millis = self
            .tool_critical_path_millis
            .zip(other.tool_critical_path_millis)
            .map(|(left, right)| left.saturating_add(right));
        self.tool_cache_hits = self
            .tool_cache_hits
            .zip(other.tool_cache_hits)
            .map(|(left, right)| left.saturating_add(right));
        self.duplicate_suppressed = self
            .duplicate_suppressed
            .zip(other.duplicate_suppressed)
            .map(|(left, right)| left.saturating_add(right));
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

/// The terminal result of a real model transport attempt.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum InferenceAttemptOutcome {
    Succeeded,
    Failed,
    Cancelled,
}

/// Provenance of one network attempt within the original logical request.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InferenceAttemptMetadata {
    pub logical_request_id: String,
    pub core_attempt_id: String,
    pub generation: u32,
    pub stage: pl_protocol::ProviderFailureStage,
    pub outcome: InferenceAttemptOutcome,
    /// Whether the latest received usage sample was explicitly terminal.
    /// Missing token dimensions still remain unknown in the accounting report.
    pub usage_is_terminal: bool,
}

/// SQLite 中以 `inference_id` 幂等保存的单次计费记录。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct InferenceBillingRecord {
    pub inference_id: String,
    /// Old aggregate receipts have no evidence from which to reconstruct sub-attempts.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attempt: Option<InferenceAttemptMetadata>,
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
    /// Frozen request grouping key: `standard`, `notApplicable`, or `tier:<exact id>`.
    /// Absence means the prepared request did not record this fact.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub requested_service_tier: Option<String>,
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
