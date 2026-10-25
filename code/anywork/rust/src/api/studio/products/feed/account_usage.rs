use super::super::identity::*;
use super::super::references::BridgeAccountUsageReadRef;
use super::super::source::BridgeObservedHeader;
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountUsageHeader {
    pub source: BridgeObservedHeader,
    pub reference: Option<BridgeAccountUsageReadRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountUsageBaseline {
    pub header: BridgeAccountUsageHeader,
    pub collection: Option<BridgeProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountUsageChange {
    pub header: BridgeAccountUsageHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAccountUsageEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgeAccountUsageBaseline,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgeAccountUsageChange,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAccountUsageFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeAccountUsageEvent,
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
