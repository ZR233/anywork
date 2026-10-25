use crate::products::identity::*;
use crate::products::references::PersistenceQueueReadRef;
use crate::studio::StudioError;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PersistenceQueueHeader {
    pub reference: PersistenceQueueReadRef,
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
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PersistenceQueueBaseline {
    pub header: PersistenceQueueHeader,
    pub collection: Option<ProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PersistenceQueueChange {
    pub header: PersistenceQueueHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<ProductCollectionRef>,
    pub upserted: Vec<ProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum PersistenceQueueEvent {
    Baseline {
        identity: ProductFeedIdentity,
        stamp: ProductProjectionStamp,
        value: PersistenceQueueBaseline,
    },
    Change {
        stamp: ProductProjectionStamp,
        base_revision: u64,
        value: PersistenceQueueChange,
    },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum PersistenceQueueFrame {
    Data {
        delivery_sequence: u64,
        event: PersistenceQueueEvent,
    },
    ResyncRequired {
        identity: ProductFeedIdentity,
        reason: ProductResyncReason,
    },
    Failure {
        identity: ProductFeedIdentity,
        error: StudioError,
    },
    Closed {
        identity: ProductFeedIdentity,
        reason: ProductFeedCloseReason,
    },
}
