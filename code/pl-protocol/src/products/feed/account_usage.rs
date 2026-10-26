use crate::products::identity::*;
use crate::products::references::AccountUsageReadRef;
use crate::products::source::ObservedHeader;
use crate::studio::StudioError;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountUsageHeader {
    pub source: ObservedHeader,
    pub reference: Option<AccountUsageReadRef>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountUsageBaseline {
    pub header: AccountUsageHeader,
    pub collection: Option<ProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountUsageChange {
    pub header: AccountUsageHeader,
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
pub enum AccountUsageEvent {
    Baseline {
        identity: ProductFeedIdentity,
        stamp: ProductProjectionStamp,
        value: AccountUsageBaseline,
    },
    Change {
        stamp: ProductProjectionStamp,
        base_revision: u64,
        value: AccountUsageChange,
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
pub enum AccountUsageFrame {
    Data {
        delivery_sequence: u64,
        event: AccountUsageEvent,
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
