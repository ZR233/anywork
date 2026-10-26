use super::super::identity::*;
use super::super::references::BridgeAccountTemplatesReadRef;
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountTemplatesHeader {
    pub schema_version: u32,
    pub reference: BridgeAccountTemplatesReadRef,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountTemplatesBaseline {
    pub header: BridgeAccountTemplatesHeader,
    pub collection: Option<BridgeProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountTemplatesChange {
    pub header: BridgeAccountTemplatesHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAccountTemplatesEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgeAccountTemplatesBaseline,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgeAccountTemplatesChange,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAccountTemplatesFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeAccountTemplatesEvent,
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
