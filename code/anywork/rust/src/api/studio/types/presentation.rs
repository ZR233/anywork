//! Mechanical FRB projection of the product presentation protocol.

use super::{BridgeChatAtom, BridgeChatFactPosition, BridgeChatPlacement, BridgeChatSourceId};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeDisplayBlockState {
    Open,
    Sealed,
}

#[derive(Debug, Clone)]
pub enum BridgeDisplayContentSource {
    CurrentAtom,
    FrozenObservation {
        captured_at: Option<i64>,
        available: bool,
    },
    CompletedOriginal {
        completion_id: String,
    },
}

#[derive(Debug, Clone)]
pub struct BridgeDisplayRecord {
    pub atom: BridgeChatAtom,
    pub start_fact: Option<BridgeChatFactPosition>,
    pub end_fact: Option<BridgeChatFactPosition>,
    pub content_source: BridgeDisplayContentSource,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeDisplayBlockRef {
    pub database_id: String,
    pub block_id: String,
}

#[derive(Debug, Clone)]
pub struct BridgeWorkTiming {
    pub started_at: i64,
    pub finished_at: Option<i64>,
}

#[derive(Debug, Clone)]
pub enum BridgeDisplayBlockBody {
    Work {
        timing: BridgeWorkTiming,
        members: BridgeDisplayBlockRef,
    },
    Single {
        record: Box<BridgeDisplayRecord>,
        visibility: BridgeSingleVisibility,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeSingleVisibility {
    Content,
    FinalEmptyAfterContent,
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
    pub source: Option<BridgeChatSourceId>,
    pub body: BridgeDisplayBlockBody,
    pub state: BridgeDisplayBlockState,
    pub has_unfinished_members: bool,
    pub thinking_summary: Option<String>,
}

#[derive(Debug, Clone)]
pub struct BridgeLiveDisplayWindow {
    pub revision: u64,
    pub history_through: u64,
    pub execution_present: bool,
    pub current_work_id: Option<String>,
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
    pub record: BridgeDisplayRecord,
}

#[derive(Debug, Clone)]
pub struct BridgeDisplayMemberPage {
    pub block: BridgeDisplayBlockRef,
    pub revision: u64,
    pub sealed: bool,
    pub entries: Vec<BridgeDisplayMemberHead>,
    pub before: Option<u64>,
}
