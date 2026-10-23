use crate::api::studio::types::BridgeError;
use super::super::identity::*;
use super::super::references::BridgePerformanceHistoryReadRef;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceHistoryHeader {
    pub revision: u64,
    pub updated_at: i64,
    pub statistics_pending: bool,
    pub statistics_gap: bool,
    pub read_failed: bool,
    pub reference: BridgePerformanceHistoryReadRef,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceHistoryBaseline { pub header: BridgePerformanceHistoryHeader, pub collection: Option<BridgeProductCollectionRef> }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceHistoryChange {
    pub header: BridgePerformanceHistoryHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgePerformanceHistoryEvent {
    Baseline { identity: BridgeProductFeedIdentity, stamp: BridgeProductProjectionStamp, value: BridgePerformanceHistoryBaseline },
    Change { stamp: BridgeProductProjectionStamp, base_revision: u64, value: BridgePerformanceHistoryChange },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgePerformanceHistoryFrame {
    Data { delivery_sequence: u64, event: BridgePerformanceHistoryEvent },
    ResyncRequired { identity: BridgeProductFeedIdentity, reason: BridgeProductResyncReason },
    Failure { identity: BridgeProductFeedIdentity, error: BridgeError },
    Closed { identity: BridgeProductFeedIdentity, reason: BridgeProductFeedCloseReason },
}
