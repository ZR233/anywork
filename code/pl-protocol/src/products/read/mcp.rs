//! Typed immutable Mcp detail schema. IDs belong only to their original read scope.
use super::primitives::TypedListRef;
use crate::products::identity::{ProductCollectionRef, ProductEntityRef};
use crate::products::source::SourceStateErrorRead;
use crate::studio::ReadText;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct McpHealthRead {
    pub mcp_servers: TypedListRef,
    pub active_mcp_servers: TypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct McpReadHeader {
    pub desired_config_fingerprint: ReadText,
    pub applied_config_fingerprint: ReadText,
    pub health: McpHealthRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum McpServerStateRead {
    Disabled {
        message: ReadText,
    },
    MissingCredential {
        message: ReadText,
    },
    Checking {
        message: ReadText,
    },
    Available {
        checked_at: i64,
        tool_count: u64,
    },
    Unavailable {
        checked_at: i64,
        error: SourceStateErrorRead,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct McpServerRead {
    pub id: ReadText,
    pub transport: ReadText,
    pub endpoint: ReadText,
    pub source_kind: ReadText,
    pub mutation_policy: ReadText,
    pub state: McpServerStateRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct McpEntityRead {
    pub reference: ProductEntityRef,
    pub value: McpServerRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct McpEntryPage {
    pub collection: ProductCollectionRef,
    pub offset: u64,
    pub items: Vec<ProductEntityRef>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct McpServerReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<McpServerRead>,
    pub next_offset: Option<u64>,
}
