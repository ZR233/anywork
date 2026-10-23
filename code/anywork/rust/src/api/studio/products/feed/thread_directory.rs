use crate::api::studio::observation::BridgeReadText;
use crate::api::studio::types::BridgeError;
use super::super::identity::*;
use super::super::references::BridgeThreadDirectoryReadRef;
use super::super::source::BridgeObservedHeader;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadDirectoryHeader {
    pub source: BridgeObservedHeader,
    pub reference: Option<BridgeThreadDirectoryReadRef>,
    pub directory_revision: Option<u64>,
    pub search_project_revision: Option<u64>,
    pub has_more: Option<bool>,
    pub next_cursor: Option<BridgeReadText>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadDirectoryBaseline { pub header: BridgeThreadDirectoryHeader, pub collection: Option<BridgeProductCollectionRef> }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadDirectoryChange {
    pub header: BridgeThreadDirectoryHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeThreadDirectoryEvent {
    Baseline { identity: BridgeProductFeedIdentity, stamp: BridgeProductProjectionStamp, value: BridgeThreadDirectoryBaseline },
    Change { stamp: BridgeProductProjectionStamp, base_revision: u64, value: BridgeThreadDirectoryChange },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeThreadDirectoryFrame {
    Data { delivery_sequence: u64, event: BridgeThreadDirectoryEvent },
    ResyncRequired { identity: BridgeProductFeedIdentity, reason: BridgeProductResyncReason },
    Failure { identity: BridgeProductFeedIdentity, error: BridgeError },
    Closed { identity: BridgeProductFeedIdentity, reason: BridgeProductFeedCloseReason },
}
