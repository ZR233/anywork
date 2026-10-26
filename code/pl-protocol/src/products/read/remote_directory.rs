use crate::studio::ReadText;
use serde::{Deserialize, Serialize};
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RemoteDirectoryReadHeader {
    pub scope_id: String,
    pub path: ReadText,
    pub parent: Option<ReadText>,
    pub next_cursor: Option<ReadText>,
    pub page_entry_count: u64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RemoteDirectoryEntryRead {
    pub name: ReadText,
    pub path: ReadText,
    pub is_directory: bool,
    pub is_symlink: bool,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RemoteDirectoryEntryPage {
    pub scope_id: String,
    pub offset: u64,
    pub items: Vec<RemoteDirectoryEntryRead>,
    pub next_offset: Option<u64>,
}
