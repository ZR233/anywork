use super::super::identity::*;
use super::super::references::BridgeAgentProfilesReadRef;
use super::super::source::BridgeObservedHeader;
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentProfilesHeader {
    pub source: BridgeObservedHeader,
    pub profiles_revision: Option<u64>,
    pub reference: Option<BridgeAgentProfilesReadRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentProfilesBaseline {
    pub header: BridgeAgentProfilesHeader,
    pub collection: Option<BridgeProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentProfilesChange {
    pub header: BridgeAgentProfilesHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAgentProfilesEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgeAgentProfilesBaseline,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgeAgentProfilesChange,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAgentProfilesFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeAgentProfilesEvent,
    },
    ResyncRequired {
        identity: BridgeProductFeedIdentity,
        reason: BridgeProductResyncReason,
    },
    Failure {
        identity: BridgeProductFeedIdentity,
        error: BridgeError,
    },
    Closed {
        identity: BridgeProductFeedIdentity,
        reason: BridgeProductFeedCloseReason,
    },
}
