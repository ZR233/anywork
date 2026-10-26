use super::super::identity::*;
use super::super::references::BridgeModelCatalogReadRef;
use super::super::source::BridgeObservedHeader;
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelCatalogHeader {
    pub source: BridgeObservedHeader,
    pub catalog_revision: Option<u64>,
    pub updated_at: Option<i64>,
    pub reference: Option<BridgeModelCatalogReadRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelCatalogBaseline {
    pub header: BridgeModelCatalogHeader,
    pub collection: Option<BridgeProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelCatalogChange {
    pub header: BridgeModelCatalogHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeModelCatalogEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgeModelCatalogBaseline,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgeModelCatalogChange,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeModelCatalogFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeModelCatalogEvent,
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
