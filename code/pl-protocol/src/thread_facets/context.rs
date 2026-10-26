use super::identity::{
    ContextReadRef, FeedClosedReason, MetricsIdentityRef, ResyncReason, ThreadFacetStamp,
    ThreadFeedIdentity,
};
use crate::studio::{ConfigProjectionStamp, StudioError};
use crate::{
    CacheUsageSummary, ModelContextAdjustment, ModelContextUnavailable, PromptPrefixChangedReason,
    ThreadRuntimeUsageState,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContextValue {
    pub usage: Option<ContextUsage>,
    pub live_context: Option<LiveContext>,
    pub current_policy: Option<CurrentContextPolicy>,
    pub details: ContextReadRef,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContextUsage {
    pub has_incomplete_usage: bool,
    pub context_window: Option<u64>,
    pub max_context_window: Option<u64>,
    pub auto_compact_limit: Option<u64>,
    pub latest_context_tokens: u64,
    pub prompt_tokens: u64,
    pub completion_tokens: u64,
    pub cached_prompt_tokens: u64,
    pub cache_write_tokens: u64,
    pub reasoning_tokens: u64,
    pub inference_count: u64,
    pub total_tokens: u64,
    pub cache_usage: CacheUsageSummary,
    pub estimated_cost_count: u64,
    pub estimated_cache_saving_count: u64,
    pub has_unpriced_usage: bool,
    pub prompt_generation: Option<u64>,
    pub prefix_changed_reason: Option<PromptPrefixChangedReason>,
    pub updated_at: i64,
}

/// Context advances only for its own identity/tokens/state, never the metrics observation sequence.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LiveContext {
    pub identity: MetricsIdentityRef,
    pub latest_context_tokens: Option<u64>,
    pub state: ThreadRuntimeUsageState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentContextPolicy {
    pub sources: ConfigProjectionStamp,
    pub mode_revision: u64,
    pub route_revision: u64,
    pub context_window: Option<u64>,
    pub max_context_window: Option<u64>,
    pub input_token_limit: Option<u64>,
    pub auto_compact_limit: Option<u64>,
    pub unavailable: Option<ModelContextUnavailable>,
    pub adjustment: Option<ModelContextAdjustment>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ContextEvent {
    Baseline {
        identity: ThreadFeedIdentity,
        stamp: ThreadFacetStamp,
        value: ContextValue,
    },
    Replace {
        stamp: ThreadFacetStamp,
        value: ContextValue,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ContextFrame {
    Data {
        delivery_sequence: u64,
        event: Box<ContextEvent>,
    },
    ResyncRequired {
        identity: ThreadFeedIdentity,
        reason: ResyncReason,
    },
    Failure {
        identity: ThreadFeedIdentity,
        error: StudioError,
    },
    Closed {
        identity: ThreadFeedIdentity,
        reason: FeedClosedReason,
    },
}
