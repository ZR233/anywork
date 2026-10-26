use super::super::identity::*;
use super::super::references::BridgeProjectDirectoryReadRef;
use super::super::source::BridgeObservedHeader;
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProjectDirectoryHeader {
    pub source: BridgeObservedHeader,
    pub reference: Option<BridgeProjectDirectoryReadRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProjectDirectoryBaseline {
    pub header: BridgeProjectDirectoryHeader,
    pub collection: Option<BridgeProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProjectDirectoryChange {
    pub header: BridgeProjectDirectoryHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeProjectDirectoryEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgeProjectDirectoryBaseline,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgeProjectDirectoryChange,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeProjectDirectoryFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeProjectDirectoryEvent,
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
