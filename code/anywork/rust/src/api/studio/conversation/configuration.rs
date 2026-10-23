use crate::api::studio::types::BridgeError;
use super::identity::*;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConfigurationValue {
    pub details: BridgeConfigurationReadRef,
    pub sources: BridgeConfigProjectionStamp,
    pub mode_revision: u64,
    pub mode_binding_revision: Option<u64>,
    pub model_route: Option<BridgeModelRouteBrief>,
    pub active_skill_count: u64,
    pub active_mcp: BridgeThreadCapabilitySupport,
    pub active_lsp: BridgeThreadCapabilitySupport,
    pub mcp_health: BridgeThreadCapabilitySupport,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelRouteBrief {
    pub revision: u64,
    pub available: bool,
    pub has_unavailable_reason: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeConfigurationEvent {
    Baseline { identity: BridgeThreadFeedIdentity, stamp: BridgeThreadFacetStamp, value: BridgeConfigurationValue },
    Replace { stamp: BridgeThreadFacetStamp, value: BridgeConfigurationValue },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeConfigurationFrame {
    Data { delivery_sequence: u64, event: BridgeConfigurationEvent },
    ResyncRequired { identity: BridgeThreadFeedIdentity, reason: BridgeResyncReason },
    Failure { identity: BridgeThreadFeedIdentity, error: BridgeError },
    Closed { identity: BridgeThreadFeedIdentity, reason: BridgeFeedClosedReason },
}
