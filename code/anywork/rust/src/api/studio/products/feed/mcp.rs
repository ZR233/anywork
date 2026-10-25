use super::super::identity::*;
use super::super::references::BridgeMcpReadRef;
use super::super::source::BridgeObservedHeader;
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMcpHeader {
    pub source: BridgeObservedHeader,
    pub reference: Option<BridgeMcpReadRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMcpBaseline {
    pub header: BridgeMcpHeader,
    pub collection: Option<BridgeProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMcpChange {
    pub header: BridgeMcpHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeMcpEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgeMcpBaseline,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgeMcpChange,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeMcpFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeMcpEvent,
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
