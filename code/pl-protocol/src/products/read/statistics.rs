//! Direct views of the native performance projection; identity is separate from counters.
use super::primitives::TypedListRef;
use crate::ModelMatchState;
use crate::products::identity::{ProductCollectionRef, ProductEntityRef};
use crate::products::references::{
    PerformanceEffortIdentityRef, PerformanceSampleIdentityRef, PerformanceSummaryIdentityRef,
};
use crate::studio::ReadText;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceCounters {
    pub sample_count: u64,
    pub completion_tokens: u64,
    pub total_ttft_millis: u64,
    pub ttft_sample_count: u64,
    pub total_response_millis: u64,
    pub tokens_per_second: f64,
    pub average_ttft_millis: Option<f64>,
    pub average_response_millis: f64,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSampleCounters {
    pub completed_at: i64,
    pub completion_tokens: u64,
    pub ttft_millis: Option<u64>,
    pub decode_millis: Option<u64>,
    pub total_response_millis: Option<u64>,
    pub tokens_per_second: Option<f64>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSummariesReadHeader {
    pub summaries: TypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceHistoryReadHeader {
    pub samples: TypedListRef,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSummaryRead {
    pub identity: PerformanceSummaryIdentityRef,
    pub counters: PerformanceCounters,
    pub effort_breakdowns: TypedListRef,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceEffortRead {
    pub identity: PerformanceEffortIdentityRef,
    pub counters: PerformanceCounters,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSampleRead {
    pub identity: PerformanceSampleIdentityRef,
    pub counters: PerformanceSampleCounters,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSummaryIdentityRead {
    pub account_id: ReadText,
    pub account_display_name: ReadText,
    pub model_id: ReadText,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceEffortIdentityRead {
    pub effort: Option<ReadText>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSampleIdentityRead {
    pub account_id: ReadText,
    pub account_display_name: ReadText,
    pub model_id: Option<ReadText>,
    pub sent_model: Option<ReadText>,
    pub reported_model: Option<ReadText>,
    pub model_match_state: ModelMatchState,
    pub effort: Option<ReadText>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SessionCostsReadHeader {
    pub cost: Option<SessionCostRead>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SessionCostRead {
    pub root_thread_id: ReadText,
    pub purpose_costs: TypedListRef,
    pub estimated_costs: TypedListRef,
    pub has_unpriced_usage: bool,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PurposeCostRead {
    pub purpose: Option<ReadText>,
    pub estimated_costs: TypedListRef,
    pub has_unpriced_usage: bool,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RuntimeCostRead {
    pub currency: ReadText,
    pub amount: f64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSummariesEntryPage {
    pub collection: ProductCollectionRef,
    pub offset: u64,
    pub items: Vec<ProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSummariesEntityRead {
    pub reference: ProductEntityRef,
    pub value: PerformanceSummaryRead,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceHistoryEntryPage {
    pub collection: ProductCollectionRef,
    pub offset: u64,
    pub items: Vec<ProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceHistoryEntityRead {
    pub reference: ProductEntityRef,
    pub value: PerformanceSampleRead,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSummaryReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<PerformanceSummaryRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceEffortReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<PerformanceEffortRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSampleReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<PerformanceSampleRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PurposeCostReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<PurposeCostRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RuntimeCostReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<RuntimeCostRead>,
    pub next_offset: Option<u64>,
}
