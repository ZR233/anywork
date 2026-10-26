use super::super::identity::*;
use super::super::references::BridgePersistenceQueueReadRef;
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePersistenceQueueHeader {
    pub reference: BridgePersistenceQueueReadRef,
    pub revision: u64,
    pub updated_at: i64,
    pub statistics_gap: bool,
    pub pending_operations: u64,
    pub pending_bytes: u64,
    pub in_flight_bytes: u64,
    pub oldest_pending_age_millis: Option<u64>,
    pub pressure_paused: bool,
    pub has_last_error: bool,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePersistenceQueueBaseline {
    pub header: BridgePersistenceQueueHeader,
    pub collection: Option<BridgeProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePersistenceQueueChange {
    pub header: BridgePersistenceQueueHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgePersistenceQueueEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgePersistenceQueueBaseline,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgePersistenceQueueChange,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgePersistenceQueueFrame {
    Data {
        delivery_sequence: u64,
        event: BridgePersistenceQueueEvent,
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
