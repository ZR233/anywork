//! Mechanical FRB projection of the product presentation protocol.

use super::{BridgeChatAtom, BridgeChatPlacement, BridgeContentRef};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeDisplayBlockRef {
    pub database_id: String,
    pub block_id: String,
}

#[derive(Debug, Clone)]
pub struct BridgeWorkSummary {
    pub total: u64,
    pub terminal: u64,
    pub running: u64,
    pub waiting: u64,
    pub failed: u64,
    pub cancelled: u64,
    pub transferred: u64,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub duration_ms: Option<u64>,
    pub thinking_summary: Option<String>,
    pub thinking_content: Option<BridgeContentRef>,
}

#[derive(Debug, Clone)]
pub enum BridgeDisplayBlockBody {
    Work {
        summary: Box<BridgeWorkSummary>,
        members: BridgeDisplayBlockRef,
    },
    Single {
        atom: Box<BridgeChatAtom>,
        completion_id: Option<String>,
    },
}

#[derive(Debug, Clone)]
pub struct BridgeDisplayBlock {
    pub id: String,
    pub history_pos: u64,
    pub body: BridgeDisplayBlockBody,
}

#[derive(Debug, Clone)]
pub struct BridgeLiveDisplayBlock {
    pub id: String,
    pub block_order: u64,
    pub body: BridgeDisplayBlockBody,
    pub closing: bool,
}

#[derive(Debug, Clone)]
pub struct BridgeLiveDisplayWindow {
    pub revision: u64,
    pub history_through: u64,
    pub execution_present: bool,
    pub blocks: Vec<BridgeLiveDisplayBlock>,
    pub older: Option<String>,
}

#[derive(Debug, Clone)]
pub struct BridgeTimelineBatch {
    pub presentation_version: u32,
    pub placement: BridgeChatPlacement,
    pub blocks: Vec<BridgeDisplayBlock>,
    pub before: Option<String>,
    pub from_pos: Option<u64>,
    pub through_pos: u64,
    pub live: Option<BridgeLiveDisplayWindow>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeDisplayMemberWindow {
    Latest,
    Before { member_order: u64 },
}

#[derive(Debug, Clone)]
pub struct BridgeDisplayMemberHead {
    pub member_key: String,
    pub member_order: u64,
    pub atom: BridgeChatAtom,
    pub completion_id: Option<String>,
}

#[derive(Debug, Clone)]
pub struct BridgeDisplayMemberPage {
    pub block: BridgeDisplayBlockRef,
    pub revision: u64,
    pub sealed: bool,
    pub entries: Vec<BridgeDisplayMemberHead>,
    pub before: Option<u64>,
}
