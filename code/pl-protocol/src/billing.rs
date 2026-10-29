use serde::{Deserialize, Serialize};

use crate::{PromptPrefixChangedReason, TokenUsageSnapshot};

/// 一次成功 inference 的单调时钟耗时事实。
///
/// 三者以产生成功结果的 transport attempt 发送为起点；失败尝试、退避和工具执行不混入。
/// `response_millis` 到归一化终止事件到达为止，不包含其后的消费、展示与保存开销，也是输出
/// 吞吐的分母。`ttft_millis` 是首次非空内容观测；完整工具项也可提供边界，来源单独保留。
/// `decode_millis` 只是 `response - ttft` 的诊断值，不作为吞吐分母。
///
/// 旧口径的序列化只带 `totalMillis`；该字段不属于当前契约，解码后 `response_millis` 为 0，
/// 因此旧样本不会被当作可用速度重新读出。
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InferenceTiming {
    pub first_output_source: FirstOutputSource,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ttft_millis: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub decode_millis: Option<u64>,
    #[serde(default)]
    pub response_millis: u64,
}

/// 客户端首次内容观测，不代表供应商生成首 token 的时间。
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum FirstOutputSource {
    #[default]
    Unobserved,
    Incremental,
    CompletedToolInput,
    LegacyUnknown,
}

impl InferenceTiming {
    /// 已知总响应为正、可选首字边界一致时才可与输出词元组成吞吐样本。
    ///
    /// 首字未知不阻止输出吞吐：它只让首字延迟和首字后诊断耗时保持未知。
    pub fn has_throughput_sample(self) -> bool {
        self.response_millis > 0 && self.first_output_boundary_consistent()
    }

    /// 首字边界只能整组存在或整组未知，且存在时必须落在总响应之内。
    fn first_output_boundary_consistent(self) -> bool {
        match (self.ttft_millis, self.decode_millis) {
            (None, None) => true,
            (Some(ttft_millis), Some(decode_millis)) => {
                ttft_millis <= self.response_millis
                    && decode_millis == self.response_millis - ttft_millis
            }
            (Some(_), None) | (None, Some(_)) => false,
        }
    }
}

/// 模型调用发生时使用的价格快照。
///
/// 历史账单只能使用该快照重建，不能按当前 catalog 价格重新计算。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ModelPricingSnapshot {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub currency: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_per_mtok: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_per_mtok: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_read_per_mtok: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_write_per_mtok: Option<f64>,
}

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

impl InferenceTokenUsage {
    pub fn public_snapshot(&self) -> TokenUsageSnapshot {
        let normalized = self;
        TokenUsageSnapshot {
            prompt_tokens: normalized.prompt_tokens,
            completion_tokens: normalized.completion_tokens,
            cached_prompt_tokens: normalized.cached_prompt_tokens,
            cache_write_tokens: normalized.cache_write_tokens,
            cache_miss_tokens: normalized
                .prompt_tokens
                .saturating_sub(normalized.cached_prompt_tokens),
            reasoning_tokens: normalized.reasoning_tokens,
            inference_count: 1,
            total_tokens: normalized.total_tokens,
        }
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

impl InferenceModelObservation {
    pub fn match_state(&self) -> ModelMatchState {
        match self.reported_model.as_deref() {
            Some(reported) if reported == self.sent_model => ModelMatchState::Matched,
            Some(_) => ModelMatchState::Mismatched,
            None => ModelMatchState::Unreported,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ModelMatchState {
    Matched,
    Mismatched,
    Unreported,
    #[default]
    LegacyUnknown,
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
    pub accounting: crate::InferenceAccounting,
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
