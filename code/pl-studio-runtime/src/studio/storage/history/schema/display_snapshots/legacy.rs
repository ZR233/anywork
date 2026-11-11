//! Frozen schema-19 wire types. Applied 18 -> 19 semantics must not follow the live protocol.
use pl_protocol::{ChatAtom, ChatFactPosition, ChatSourceId, ContentRef, DisplayBlockRef};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio::storage::history::schema) struct WorkSummary {
    pub total: u64,
    pub terminal: u64,
    pub running: u64,
    pub waiting: u64,
    pub failed: u64,
    pub cancelled: u64,
    pub transferred: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub created_at: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub elapsed_ms: Option<u64>,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub duration_ms: Option<u64>,
    pub thinking_summary: Option<String>,
    pub thinking_content: Option<ContentRef>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(in crate::studio::storage::history::schema) enum DisplayBlockBody {
    Work {
        summary: Box<WorkSummary>,
        members: DisplayBlockRef,
    },
    Single {
        atom: Box<ChatAtom>,
        completion_id: Option<String>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::studio::storage::history::schema) struct DisplayHeader {
    pub version: u32,
    pub legacy: bool,
    pub id: String,
    pub source: ChatSourceId,
    pub block_order: u64,
    pub history_pos: Option<u64>,
    pub boundary: Option<ChatFactPosition>,
    pub unfinished: u64,
    pub next_member: u64,
    pub revision: u64,
    pub skip_display: bool,
    pub active_since: Option<i64>,
    pub duration_known: bool,
    pub body: DisplayBlockBody,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio::storage::history::schema) struct DisplayMemberHead {
    pub member_key: String,
    pub member_order: u64,
    pub atom: ChatAtom,
    pub completion_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::studio::storage::history::schema) struct DisplayMemberWrite {
    pub block_id: String,
    pub terminal: bool,
    pub head: DisplayMemberHead,
}
