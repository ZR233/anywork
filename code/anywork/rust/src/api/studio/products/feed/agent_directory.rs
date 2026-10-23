use crate::api::studio::types::BridgeError;
use super::super::identity::*;
use super::super::references::BridgeAgentDirectoryReadRef;
use super::super::source::BridgeObservedHeader;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentDirectoryHeader { pub source: BridgeObservedHeader, pub reference: Option<BridgeAgentDirectoryReadRef> }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentDirectoryBaseline { pub header: BridgeAgentDirectoryHeader, pub collection: Option<BridgeProductCollectionRef> }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentDirectoryChange {
    pub header: BridgeAgentDirectoryHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAgentDirectoryEvent {
    Baseline { identity: BridgeProductFeedIdentity, stamp: BridgeProductProjectionStamp, value: BridgeAgentDirectoryBaseline },
    Change { stamp: BridgeProductProjectionStamp, base_revision: u64, value: BridgeAgentDirectoryChange },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAgentDirectoryFrame {
    Data { delivery_sequence: u64, event: BridgeAgentDirectoryEvent },
    ResyncRequired { identity: BridgeProductFeedIdentity, reason: BridgeProductResyncReason },
    Failure { identity: BridgeProductFeedIdentity, error: BridgeError },
    Closed { identity: BridgeProductFeedIdentity, reason: BridgeProductFeedCloseReason },
}
