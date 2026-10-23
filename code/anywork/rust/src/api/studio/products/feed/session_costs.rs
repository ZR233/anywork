use crate::api::studio::types::BridgeError;
use super::super::identity::*;
use super::super::references::BridgeSessionCostsReadRef;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSessionCostsHeader {
    pub revision: u64,
    pub updated_at: i64,
    pub statistics_pending: bool,
    pub statistics_gap: bool,
    pub read_failed: bool,
    pub has_cost: bool,
    pub has_unpriced_usage: Option<bool>,
    pub reference: BridgeSessionCostsReadRef,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeSessionCostsEvent {
    Baseline { identity: BridgeProductFeedIdentity, stamp: BridgeProductProjectionStamp, value: BridgeSessionCostsHeader },
    Replace { stamp: BridgeProductProjectionStamp, base_revision: u64, value: BridgeSessionCostsHeader },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeSessionCostsFrame {
    Data { delivery_sequence: u64, event: BridgeSessionCostsEvent },
    ResyncRequired { identity: BridgeProductFeedIdentity, reason: BridgeProductResyncReason },
    Failure { identity: BridgeProductFeedIdentity, error: BridgeError },
    Closed { identity: BridgeProductFeedIdentity, reason: BridgeProductFeedCloseReason },
}
