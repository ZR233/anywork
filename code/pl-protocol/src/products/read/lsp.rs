//! Typed immutable Lsp detail schema. IDs belong only to their original read scope.
use super::primitives::TypedListRef;
use crate::products::identity::{ProductCollectionRef, ProductEntityRef};
use crate::products::source::SourceStateErrorRead;
use crate::studio::ReadText;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LspReadHeader {
    pub lsp_servers: TypedListRef,
    pub active_lsp_servers: TypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum LspActivityRead {
    Idle,
    Busy {
        title: Option<ReadText>,
        message: Option<ReadText>,
        percentage: Option<u32>,
    },
    Indexing {
        title: Option<ReadText>,
        message: Option<ReadText>,
        percentage: Option<u32>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum LspServerStateRead {
    Checking {
        message: ReadText,
    },
    Disabled {
        message: ReadText,
    },
    Unavailable {
        checked_at: i64,
        error: SourceStateErrorRead,
    },
    Available {
        checked_at: i64,
        diagnostic_count: u64,
        activity: LspActivityRead,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LspServerRead {
    pub id: ReadText,
    pub display_name: ReadText,
    pub extensions: TypedListRef,
    pub language_ids: TypedListRef,
    pub state: LspServerStateRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LspEntityRead {
    pub reference: ProductEntityRef,
    pub value: LspServerRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LspEntryPage {
    pub collection: ProductCollectionRef,
    pub offset: u64,
    pub items: Vec<ProductEntityRef>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LspServerReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<LspServerRead>,
    pub next_offset: Option<u64>,
}
