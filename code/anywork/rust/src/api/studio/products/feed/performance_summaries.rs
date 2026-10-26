use super::super::identity::*;
use super::super::references::BridgePerformanceSummariesReadRef;
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceSummariesHeader {
    pub revision: u64,
    pub updated_at: i64,
    pub statistics_pending: bool,
    pub statistics_gap: bool,
    pub read_failed: bool,
    pub reference: BridgePerformanceSummariesReadRef,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceSummariesBaseline {
    pub header: BridgePerformanceSummariesHeader,
    pub collection: Option<BridgeProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceSummariesChange {
    pub header: BridgePerformanceSummariesHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgePerformanceSummariesEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgePerformanceSummariesBaseline,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgePerformanceSummariesChange,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgePerformanceSummariesFrame {
    Data {
        delivery_sequence: u64,
        event: BridgePerformanceSummariesEvent,
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
