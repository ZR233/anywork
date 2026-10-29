use serde::{Deserialize, Serialize};

/// Global performance projection retained for the existing HTTP product API.
///
/// GUI readers use the independently versioned feed and immutable read scopes in this module.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StudioModelPerformanceSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    #[serde(default)]
    pub statistics_pending: bool,
    #[serde(default)]
    pub statistics_gap: bool,
    #[serde(default)]
    pub read_failed: bool,
    pub summaries: Vec<StudioModelPerformanceSummary>,
    pub history: Vec<StudioModelPerformanceSample>,
}

/// One `(account_id, model_id)` aggregate; effort is a group-local breakdown.
///
/// Identity comes only from frozen account and configured model identifiers. Display names and
/// provider-reported aliases are diagnostic and do not split an aggregate.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StudioModelPerformanceSummary {
    pub account_id: String,
    pub account_display_name: String,
    pub model_id: String,
    pub sample_count: u64,
    pub completion_tokens: u64,
    /// Total first-token latency over the independent `ttft_sample_count` denominator.
    pub total_ttft_millis: u64,
    pub ttft_sample_count: u64,
    /// Total response latency, including time-to-first-token.
    pub total_response_millis: u64,
    pub tokens_per_second: f64,
    /// Unknown when no first-token measurement exists.
    pub average_ttft_millis: Option<f64>,
    pub average_response_millis: f64,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub effort_breakdowns: Vec<StudioModelPerformanceEffortSummary>,
}

/// An effort breakdown within one account/model aggregate.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StudioModelPerformanceEffortSummary {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    pub sample_count: u64,
    pub completion_tokens: u64,
    pub total_ttft_millis: u64,
    pub ttft_sample_count: u64,
    pub total_response_millis: u64,
    pub tokens_per_second: f64,
    pub average_ttft_millis: Option<f64>,
    pub average_response_millis: f64,
}

/// One successful sample in the retained recent-history window.
///
/// A missing configured model remains unknown; sent and reported identities are frozen
/// diagnostics and are never used to infer or repair the configured model.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StudioModelPerformanceSample {
    pub thread_id: String,
    pub call_id: String,
    pub purpose: Option<String>,
    pub first_output_source: pl_protocol::FirstOutputSource,
    pub usage_status: pl_protocol::UsageReportStatus,
    pub ttft_availability: pl_protocol::MetricAvailability,
    pub throughput_availability: pl_protocol::MetricAvailability,
    pub completed_at: i64,
    pub account_id: String,
    pub account_display_name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sent_model: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reported_model: Option<String>,
    #[serde(default)]
    pub model_match_state: pl_protocol::ModelMatchState,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    pub completion_tokens: Option<u64>,
    pub ttft_millis: Option<u64>,
    pub decode_millis: Option<u64>,
    pub total_response_millis: Option<u64>,
    pub tokens_per_second: Option<f64>,
}
