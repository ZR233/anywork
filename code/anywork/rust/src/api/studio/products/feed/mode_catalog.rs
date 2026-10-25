use super::super::identity::*;
use super::super::references::BridgeModeCatalogReadRef;
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModeCatalogHeader {
    pub revision: u64,
    pub reference: BridgeModeCatalogReadRef,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModeCatalogBaseline {
    pub header: BridgeModeCatalogHeader,
    pub collection: Option<BridgeProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModeCatalogChange {
    pub header: BridgeModeCatalogHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeModeCatalogEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgeModeCatalogBaseline,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgeModeCatalogChange,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeModeCatalogFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeModeCatalogEvent,
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
