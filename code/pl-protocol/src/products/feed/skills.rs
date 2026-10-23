use serde::{Deserialize, Serialize};
use crate::studio::StudioError;
use crate::products::identity::*;
use crate::products::references::SkillsReadRef;
use crate::products::source::ObservedHeader;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillsHeader {
    pub source: ObservedHeader,
    pub reference: Option<SkillsReadRef>,
    pub catalog_revision: Option<u64>,
    pub complete: Option<bool>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillsBaseline { pub header: SkillsHeader, pub collection: Option<ProductCollectionRef> }
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillsChange {
    pub header: SkillsHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<ProductCollectionRef>,
    pub upserted: Vec<ProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum SkillsEvent {
    Baseline { identity: ProductFeedIdentity, stamp: ProductProjectionStamp, value: SkillsBaseline },
    Change { stamp: ProductProjectionStamp, base_revision: u64, value: SkillsChange },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum SkillsFrame {
    Data { delivery_sequence: u64, event: SkillsEvent },
    ResyncRequired { identity: ProductFeedIdentity, reason: ProductResyncReason },
    Failure { identity: ProductFeedIdentity, error: StudioError },
    Closed { identity: ProductFeedIdentity, reason: ProductFeedCloseReason },
}
