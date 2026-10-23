use crate::api::studio::types::BridgeError;
use super::super::identity::*;
use super::super::references::BridgeSkillsReadRef;
use super::super::source::BridgeObservedHeader;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillsHeader {
    pub source: BridgeObservedHeader,
    pub reference: Option<BridgeSkillsReadRef>,
    pub catalog_revision: Option<u64>,
    pub complete: Option<bool>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillsBaseline { pub header: BridgeSkillsHeader, pub collection: Option<BridgeProductCollectionRef> }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillsChange {
    pub header: BridgeSkillsHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeSkillsEvent {
    Baseline { identity: BridgeProductFeedIdentity, stamp: BridgeProductProjectionStamp, value: BridgeSkillsBaseline },
    Change { stamp: BridgeProductProjectionStamp, base_revision: u64, value: BridgeSkillsChange },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeSkillsFrame {
    Data { delivery_sequence: u64, event: BridgeSkillsEvent },
    ResyncRequired { identity: BridgeProductFeedIdentity, reason: BridgeProductResyncReason },
    Failure { identity: BridgeProductFeedIdentity, error: BridgeError },
    Closed { identity: BridgeProductFeedIdentity, reason: BridgeProductFeedCloseReason },
}
