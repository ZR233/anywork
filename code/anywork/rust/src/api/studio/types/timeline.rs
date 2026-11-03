//! Mechanical display-item DTOs; the Studio projection owns grouping.

use super::{
    BridgeChatAtomContent, BridgeChatAtomKind, BridgeChatDeliveryKind, BridgeChatSourceId,
    BridgeChatTerminalOutcome, BridgePayloadData, BridgeThreadTextChannel,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeTimelineItemKind {
    Text,
    WorkGroup,
    Status,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeTimelineCategory {
    Thinking,
    Read,
    Image,
    Command,
    Search,
    Edit,
    Wait,
    Other,
}

#[derive(Debug, Clone)]
pub struct BridgeTimelineCategoryCount {
    pub category: BridgeTimelineCategory,
    pub count: u32,
}

#[derive(Debug, Clone)]
pub struct BridgeTimelineGroupSummary {
    pub member_count: u32,
    pub active_count: u32,
    pub failed_count: u32,
    pub cancelled_count: u32,
    pub categories: Vec<BridgeTimelineCategoryCount>,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineMembersRef {
    pub database_id: String,
    pub projection_version: u32,
    pub item_id: String,
}

#[derive(Debug, Clone)]
pub struct BridgeTimelineItem {
    pub id: String,
    pub kind: BridgeTimelineItemKind,
    pub source: BridgeChatSourceId,
    pub atom_kind: Option<BridgeChatAtomKind>,
    pub delivery: BridgeChatDeliveryKind,
    pub outcome: Option<BridgeChatTerminalOutcome>,
    pub text_channel: Option<BridgeThreadTextChannel>,
    pub turn_id: Option<String>,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub summary: Option<BridgeTimelineGroupSummary>,
    pub members: Option<BridgeTimelineMembersRef>,
    pub contents: Vec<BridgeChatAtomContent>,
    pub payload: Option<BridgePayloadData>,
    pub content_item_id: Option<String>,
    pub position: Option<u64>,
    pub admission_closed: bool,
}
