use crate::products::identity::*;
use crate::products::references::McpReadRef;
use crate::products::source::ObservedHeader;
use crate::studio::StudioError;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct McpHeader {
    pub source: ObservedHeader,
    pub reference: Option<McpReadRef>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct McpBaseline {
    pub header: McpHeader,
    pub collection: Option<ProductCollectionRef>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct McpChange {
    pub header: McpHeader,
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
pub enum McpEvent {
    Baseline {
        identity: ProductFeedIdentity,
        stamp: ProductProjectionStamp,
        value: McpBaseline,
    },
    Change {
        stamp: ProductProjectionStamp,
        base_revision: u64,
        value: McpChange,
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
pub enum McpFrame {
    Data {
        delivery_sequence: u64,
        event: McpEvent,
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
