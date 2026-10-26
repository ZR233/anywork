use super::super::identity::*;
use super::super::references::BridgeConfigurationReadRef;
use super::super::source::BridgeObservedHeader;
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConfigurationHeader {
    pub source: BridgeObservedHeader,
    pub configuration_revision: Option<u64>,
    pub updated_at: Option<i64>,
    pub reference: Option<BridgeConfigurationReadRef>,
    pub role_read:
        Option<super::super::read::configuration_values::BridgeConfigurationRoleReadTarget>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConfigurationBaseline {
    pub header: BridgeConfigurationHeader,
    pub collection: Option<BridgeProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConfigurationChange {
    pub header: BridgeConfigurationHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<BridgeProductCollectionRef>,
    pub upserted: Vec<BridgeProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeConfigurationEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgeConfigurationBaseline,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgeConfigurationChange,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeConfigurationFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeConfigurationEvent,
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
