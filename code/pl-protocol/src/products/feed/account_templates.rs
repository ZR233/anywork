use serde::{Deserialize, Serialize};
use crate::studio::StudioError;
use crate::products::identity::*;
use crate::products::references::AccountTemplatesReadRef;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct AccountTemplatesHeader { pub schema_version: u32, pub reference: AccountTemplatesReadRef }
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct AccountTemplatesBaseline { pub header: AccountTemplatesHeader, pub collection: Option<ProductCollectionRef> }
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct AccountTemplatesChange {
    pub header: AccountTemplatesHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<ProductCollectionRef>,
    pub upserted: Vec<ProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub enum AccountTemplatesEvent {
    Baseline { identity: ProductFeedIdentity, stamp: ProductProjectionStamp, value: AccountTemplatesBaseline },
    Change { stamp: ProductProjectionStamp, base_revision: u64, value: AccountTemplatesChange },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub enum AccountTemplatesFrame {
    Data { delivery_sequence: u64, event: AccountTemplatesEvent },
    ResyncRequired { identity: ProductFeedIdentity, reason: ProductResyncReason },
    Failure { identity: ProductFeedIdentity, error: StudioError },
    Closed { identity: ProductFeedIdentity, reason: ProductFeedCloseReason },
}
