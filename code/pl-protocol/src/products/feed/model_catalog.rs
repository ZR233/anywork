use serde::{Deserialize, Serialize};
use crate::studio::StudioError;
use crate::products::identity::*;
use crate::products::references::ModelCatalogReadRef;
use crate::products::source::ObservedHeader;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelCatalogHeader {
    pub source: ObservedHeader,
    pub catalog_revision: Option<u64>,
    pub updated_at: Option<i64>,
    pub reference: Option<ModelCatalogReadRef>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelCatalogBaseline { pub header: ModelCatalogHeader, pub collection: Option<ProductCollectionRef> }
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelCatalogChange {
    pub header: ModelCatalogHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<ProductCollectionRef>,
    pub upserted: Vec<ProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum ModelCatalogEvent {
    Baseline { identity: ProductFeedIdentity, stamp: ProductProjectionStamp, value: ModelCatalogBaseline },
    Change { stamp: ProductProjectionStamp, base_revision: u64, value: ModelCatalogChange },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum ModelCatalogFrame {
    Data { delivery_sequence: u64, event: ModelCatalogEvent },
    ResyncRequired { identity: ProductFeedIdentity, reason: ProductResyncReason },
    Failure { identity: ProductFeedIdentity, error: StudioError },
    Closed { identity: ProductFeedIdentity, reason: ProductFeedCloseReason },
}
