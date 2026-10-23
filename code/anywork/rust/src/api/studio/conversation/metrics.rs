use crate::api::studio::types::{BridgeError, BridgeThreadRuntimeUsageState};
use super::identity::*;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMetricsValue {
    pub live: Option<BridgeLiveTurnMetrics>,
    pub authoritative: Option<BridgeAuthoritativeTurnMetrics>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLiveTurnMetrics {
    pub identity: BridgeMetricsIdentityRef,
    pub completion_tokens: Option<u64>,
    pub response_millis: Option<u64>,
    pub state: BridgeThreadRuntimeUsageState,
    pub observation_sequence: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAuthoritativeTurnMetrics {
    pub identity: BridgeMetricsIdentityRef,
    pub completion_tokens: u64,
    pub response_millis: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeMetricsEvent {
    Baseline { identity: BridgeThreadFeedIdentity, stamp: BridgeThreadFacetStamp, value: BridgeMetricsValue },
    Replace { stamp: BridgeThreadFacetStamp, value: BridgeMetricsValue },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeMetricsFrame {
    Data { delivery_sequence: u64, event: BridgeMetricsEvent },
    ResyncRequired { identity: BridgeThreadFeedIdentity, reason: BridgeResyncReason },
    Failure { identity: BridgeThreadFeedIdentity, error: BridgeError },
    Closed { identity: BridgeThreadFeedIdentity, reason: BridgeFeedClosedReason },
}
