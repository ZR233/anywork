use serde::{Deserialize, Serialize};
use crate::studio::{ReadText, StudioError};
use crate::products::identity::*;
use crate::products::references::ThreadDirectoryReadRef;
use crate::products::source::ObservedHeader;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadDirectoryHeader {
    pub source: ObservedHeader,
    pub reference: Option<ThreadDirectoryReadRef>,
    pub directory_revision: Option<u64>,
    pub search_project_revision: Option<u64>,
    pub has_more: Option<bool>,
    pub next_cursor: Option<ReadText>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadDirectoryBaseline { pub header: ThreadDirectoryHeader, pub collection: Option<ProductCollectionRef> }
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadDirectoryChange {
    pub header: ThreadDirectoryHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<ProductCollectionRef>,
    pub upserted: Vec<ProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum ThreadDirectoryEvent {
    Baseline { identity: ProductFeedIdentity, stamp: ProductProjectionStamp, value: ThreadDirectoryBaseline },
    Change { stamp: ProductProjectionStamp, base_revision: u64, value: ThreadDirectoryChange },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum ThreadDirectoryFrame {
    Data { delivery_sequence: u64, event: ThreadDirectoryEvent },
    ResyncRequired { identity: ProductFeedIdentity, reason: ProductResyncReason },
    Failure { identity: ProductFeedIdentity, error: StudioError },
    Closed { identity: ProductFeedIdentity, reason: ProductFeedCloseReason },
}
