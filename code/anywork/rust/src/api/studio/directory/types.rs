use crate::api::studio::types::{BridgeResourceStamp, BridgeSessionDirectoryRow};

#[derive(Debug, Clone)]
pub enum BridgeThreadDirectoryFilter {
    All,
    Running,
    Attention,
}

#[derive(Debug, Clone)]
pub struct BridgeThreadDirectoryQuery {
    pub workspace_id: Option<String>,
    pub search: Option<String>,
    pub archived: bool,
    pub filter: BridgeThreadDirectoryFilter,
    pub thread_ids: Option<Vec<String>>,
    pub excluded_thread_ids: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct BridgeThreadDirectoryWindow {
    pub before: Option<String>,
    pub limit: u32,
}

#[derive(Debug, Clone)]
pub struct BridgeThreadDirectoryFrame {
    pub query: BridgeThreadDirectoryQuery,
    pub window: BridgeThreadDirectoryWindow,
    pub stamp: BridgeResourceStamp,
    pub rows: Vec<BridgeSessionDirectoryRow>,
    pub next_cursor: Option<String>,
}

#[derive(Debug, Clone)]
pub struct BridgeThreadMetadataFrame {
    pub thread_id: String,
    pub stamp: BridgeResourceStamp,
    pub row: Option<BridgeSessionDirectoryRow>,
}
