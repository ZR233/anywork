use serde::{Deserialize, Serialize};

use crate::api::studio::types::BridgeError;

/// One ordered event from the native statistics feed.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeStatisticsFeedEvent {
    Baseline {
        publication: BridgeStatisticsFeedHeader,
    },
    Data {
        publication: BridgeStatisticsFeedHeader,
    },
    Failure {
        error: BridgeError,
    },
    Closed,
}

/// Identity and status of one delivered latest-value publication.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeStatisticsFeedHeader {
    pub owner_epoch: String,
    pub feed_id: String,
    pub delivery_sequence: u64,
    pub publication_revision: u64,
    pub summaries_revision: u64,
    pub history_revision: u64,
    pub summary_count: u64,
    pub history_count: u64,
    pub statistics_pending: bool,
    pub statistics_gap: bool,
    pub read_failed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeStatisticsScopeIdentity {
    pub owner_epoch: String,
    pub feed_id: String,
    pub scope_id: String,
    pub publication_revision: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeStatisticsSummary {
    pub account_id: String,
    pub account_display_name: String,
    pub model_id: String,
    pub sample_count: u64,
    pub completion_tokens: u64,
    pub total_ttft_millis: u64,
    pub ttft_sample_count: u64,
    pub total_response_millis: u64,
    pub tokens_per_second: f64,
    pub average_ttft_millis: Option<f64>,
    pub average_response_millis: f64,
    pub effort_count: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeStatisticsEffortSummary {
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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeStatisticsSample {
    pub completed_at: i64,
    pub account_id: String,
    pub account_display_name: String,
    pub model_id: Option<String>,
    pub sent_model: Option<String>,
    pub reported_model: Option<String>,
    pub model_match_state: BridgeStatisticsModelMatchState,
    pub effort: Option<String>,
    pub completion_tokens: u64,
    pub ttft_millis: Option<u64>,
    pub decode_millis: Option<u64>,
    pub total_response_millis: Option<u64>,
    pub tokens_per_second: Option<f64>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeStatisticsModelMatchState {
    Matched,
    Mismatched,
    Unreported,
    LegacyUnknown,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeStatisticsSummaryPage {
    pub owner_epoch: String,
    pub feed_id: String,
    pub scope_id: String,
    pub publication_revision: u64,
    pub material_revision: u64,
    pub offset: u64,
    pub total_count: u64,
    pub next_offset: Option<u64>,
    pub source_bytes: u64,
    pub items: Vec<BridgeStatisticsSummary>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeStatisticsHistoryPage {
    pub owner_epoch: String,
    pub feed_id: String,
    pub scope_id: String,
    pub publication_revision: u64,
    pub material_revision: u64,
    pub offset: u64,
    pub total_count: u64,
    pub next_offset: Option<u64>,
    pub source_bytes: u64,
    pub items: Vec<BridgeStatisticsSample>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeStatisticsEffortPage {
    pub owner_epoch: String,
    pub feed_id: String,
    pub scope_id: String,
    pub publication_revision: u64,
    pub material_revision: u64,
    pub summary_index: u64,
    pub offset: u64,
    pub total_count: u64,
    pub next_offset: Option<u64>,
    pub source_bytes: u64,
    pub items: Vec<BridgeStatisticsEffortSummary>,
}
