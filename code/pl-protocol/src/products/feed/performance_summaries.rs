use serde::{Deserialize, Serialize};
use crate::studio::StudioError;
use crate::products::identity::*;
use crate::products::references::PerformanceSummariesReadRef;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSummariesHeader {
    pub revision: u64,
    pub updated_at: i64,
    pub statistics_pending: bool,
    pub statistics_gap: bool,
    pub read_failed: bool,
    pub reference: PerformanceSummariesReadRef,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSummariesBaseline { pub header: PerformanceSummariesHeader, pub collection: Option<ProductCollectionRef> }
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PerformanceSummariesChange {
    pub header: PerformanceSummariesHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<ProductCollectionRef>,
    pub upserted: Vec<ProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum PerformanceSummariesEvent {
    Baseline { identity: ProductFeedIdentity, stamp: ProductProjectionStamp, value: PerformanceSummariesBaseline },
    Change { stamp: ProductProjectionStamp, base_revision: u64, value: PerformanceSummariesChange },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum PerformanceSummariesFrame {
    Data { delivery_sequence: u64, event: PerformanceSummariesEvent },
    ResyncRequired { identity: ProductFeedIdentity, reason: ProductResyncReason },
    Failure { identity: ProductFeedIdentity, error: StudioError },
    Closed { identity: ProductFeedIdentity, reason: ProductFeedCloseReason },
}
