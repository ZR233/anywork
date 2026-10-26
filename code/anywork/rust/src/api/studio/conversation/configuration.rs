use super::identity::*;
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConfigurationValue {
    pub details: BridgeThreadConfigurationReadRef,
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
pub enum BridgeThreadConfigurationEvent {
    Baseline {
        identity: BridgeThreadFeedIdentity,
        stamp: BridgeThreadFacetStamp,
        value: BridgeConfigurationValue,
    },
    Replace {
        stamp: BridgeThreadFacetStamp,
        value: BridgeConfigurationValue,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeThreadConfigurationFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeThreadConfigurationEvent,
    },
    ResyncRequired {
        identity: BridgeThreadFeedIdentity,
        reason: BridgeResyncReason,
    },
    Failure {
        identity: BridgeThreadFeedIdentity,
        error: BridgeError,
    },
    Closed {
        identity: BridgeThreadFeedIdentity,
        reason: BridgeFeedClosedReason,
    },
}
