use super::super::identity::*;
use super::super::references::BridgeRecoveryReadRef;
use super::super::source::BridgeObservedHeader;
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRecoveryHeader {
    pub source: BridgeObservedHeader,
    pub reference: Option<BridgeRecoveryReadRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRecoveryBaseline {
    pub header: BridgeRecoveryHeader,
    pub collection: Option<BridgeProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRecoveryChange {
    pub header: BridgeRecoveryHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeRecoveryEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgeRecoveryBaseline,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgeRecoveryChange,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeRecoveryFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeRecoveryEvent,
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
