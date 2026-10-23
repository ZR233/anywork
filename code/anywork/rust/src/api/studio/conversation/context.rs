use crate::api::studio::types::{BridgeCacheUsageSummary, BridgeError, BridgeModelContextAdjustment, BridgeModelContextUnavailable, BridgePromptPrefixChangedReason, BridgeThreadRuntimeUsageState};
use super::identity::*;

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeContextValue {
    pub usage: Option<BridgeContextUsage>,
    pub live_context: Option<BridgeLiveContext>,
    pub current_policy: Option<BridgeCurrentContextPolicy>,
    pub details: BridgeContextReadRef,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeContextUsage {
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
    pub cache_usage: BridgeCacheUsageSummary,
    pub estimated_cost_count: u64,
    pub estimated_cache_saving_count: u64,
    pub has_unpriced_usage: bool,
    pub prompt_generation: Option<u64>,
    pub prefix_changed_reason: Option<BridgePromptPrefixChangedReason>,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLiveContext {
    pub identity: BridgeMetricsIdentityRef,
    pub latest_context_tokens: Option<u64>,
    pub state: BridgeThreadRuntimeUsageState,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentContextPolicy {
    pub sources: BridgeConfigProjectionStamp,
    pub mode_revision: u64,
    pub route_revision: u64,
    pub context_window: Option<u64>,
    pub max_context_window: Option<u64>,
    pub input_token_limit: Option<u64>,
    pub auto_compact_limit: Option<u64>,
    pub unavailable: Option<BridgeModelContextUnavailable>,
    pub adjustment: Option<BridgeModelContextAdjustment>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeContextEvent {
    Baseline { identity: BridgeThreadFeedIdentity, stamp: BridgeThreadFacetStamp, value: BridgeContextValue },
    Replace { stamp: BridgeThreadFacetStamp, value: BridgeContextValue },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeContextFrame {
    Data { delivery_sequence: u64, event: BridgeContextEvent },
    ResyncRequired { identity: BridgeThreadFeedIdentity, reason: BridgeResyncReason },
    Failure { identity: BridgeThreadFeedIdentity, error: BridgeError },
    Closed { identity: BridgeThreadFeedIdentity, reason: BridgeFeedClosedReason },
}
