use crate::products::identity::*;
use crate::products::references::ModeCatalogReadRef;
use crate::studio::StudioError;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModeCatalogHeader {
    pub revision: u64,
    pub reference: ModeCatalogReadRef,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModeCatalogBaseline {
    pub header: ModeCatalogHeader,
    pub collection: Option<ProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModeCatalogChange {
    pub header: ModeCatalogHeader,
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
pub enum ModeCatalogEvent {
    Baseline {
        identity: ProductFeedIdentity,
        stamp: ProductProjectionStamp,
        value: ModeCatalogBaseline,
    },
    Change {
        stamp: ProductProjectionStamp,
        base_revision: u64,
        value: ModeCatalogChange,
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
pub enum ModeCatalogFrame {
    Data {
        delivery_sequence: u64,
        event: ModeCatalogEvent,
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
