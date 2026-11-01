//! Canonical conversation DTOs mirrored mechanically at the FRB boundary.

use super::{BridgeError, BridgeThreadSubscriptionUpdate};

#[derive(Debug, Clone)]
pub struct BridgeConversationFrame {
    pub thread_id: String,
    pub subscription_id: String,
    pub delivery_sequence: u64,
    pub event: BridgeConversationEvent,
}

#[derive(Debug, Clone)]
pub enum BridgeConversationEvent {
    State {
        update: Box<BridgeThreadSubscriptionUpdate>,
    },
    Chat {
        batch: Box<BridgeChatBatch>,
    },
    Failure {
        error: BridgeError,
    },
    Closed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeReadDemand {
    pub max_items: u32,
    pub max_bytes: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeChatScope {
    Main,
    Children { parent_id: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeChatPlacement {
    Set,
    Prepend,
    Append,
}

#[derive(Debug, Clone)]
pub enum BridgePayloadData {
    Inline {
        bytes: Vec<u8>,
    },
    Deferred {
        reference: BridgeContentRef,
        byte_length: u64,
    },
}

#[derive(Debug, Clone)]
pub struct BridgeChatMessage {
    pub id: String,
    pub payload: BridgePayloadData,
}

/// A mechanical FRB boundary for the canonical pl-protocol ChatBatch.
#[derive(Debug, Clone)]
pub struct BridgeChatBatch {
    pub placement: BridgeChatPlacement,
    pub messages: Vec<BridgeChatMessage>,
    pub before: Option<String>,
    pub current: Option<BridgeCurrentProjection>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeContentRef {
    pub database_id: String,
    pub target: BridgeContentTarget,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeContentTarget {
    ItemPayload {
        item_id: String,
    },
    Body {
        owner: BridgeContentOwner,
        key: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeContentOwner {
    Item {
        item_id: String,
    },
    Current {
        domain: String,
        id: String,
        revision: u64,
    },
}

#[derive(Debug, Clone)]
pub struct BridgeCurrentProjection {
    pub source_effect_seq: u64,
    pub logical_status: super::BridgeThreadStatus,
    pub execution_present: bool,
    pub active: Option<BridgeCurrentActivityHead>,
    pub active_turn: Option<BridgeCurrentTurnHead>,
    pub plan: Option<BridgeCurrentPlanHead>,
    pub interactions: Option<BridgeCurrentCollectionRef>,
    pub previews: Vec<BridgeCurrentContentPreview>,
    pub collections: Vec<BridgeCurrentCollectionRef>,
}

#[derive(Debug, Clone)]
pub struct BridgeCurrentActivityHead {
    pub id: String,
    pub kind: super::BridgeThreadActivityKind,
    pub summary: String,
    pub thinking_summary: Option<String>,
    pub thinking_seconds: Option<u64>,
    pub tool_count: u32,
    pub background_tool_count: u32,
    pub latest_tool: Option<BridgeCurrentToolHead>,
}

#[derive(Debug, Clone)]
pub struct BridgeCurrentToolHead {
    pub call_id: String,
    pub name: String,
    pub state: super::BridgeThreadActivityToolState,
}

#[derive(Debug, Clone)]
pub struct BridgeCurrentTurnHead {
    pub id: String,
    pub phase: super::BridgeTurnPhase,
    pub children_parent_id: Option<String>,
}

#[derive(Debug, Clone)]
pub struct BridgeCurrentPlanHead {
    pub revision: u64,
    pub phase: super::BridgePlanPhase,
    pub document: Option<BridgeContentRef>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentCollectionRef {
    pub database_id: String,
    pub collection: String,
    pub revision: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeCurrentContentRole {
    Reasoning,
    Response,
    ToolArguments,
    ToolOutput,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentContentPreview {
    pub id: String,
    pub role: BridgeCurrentContentRole,
    pub text_channel: Option<BridgeThreadTextChannel>,
    pub text: String,
    pub reference: BridgeContentRef,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadTextChannel {
    User,
    ParentAgent,
    Commentary,
    FinalAnswer,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeContentRange {
    pub offset: u64,
    pub max_bytes: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeContentWindow {
    pub offset: u64,
    pub bytes: Vec<u8>,
    pub generation: String,
    pub available_through: u64,
    pub sealed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeContentManifestEntry {
    pub key: String,
    pub payload: Vec<u8>,
    pub reference: BridgeContentRef,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeContentManifestPage {
    pub entries: Vec<BridgeContentManifestEntry>,
    pub continuation: Option<String>,
}

#[derive(Debug, Clone)]
pub struct BridgeCurrentCollectionEntry {
    pub id: String,
    pub position: i64,
    pub payload: BridgePayloadData,
}

#[derive(Debug, Clone)]
pub struct BridgeCurrentCollectionPage {
    pub revision: u64,
    pub entries: Vec<BridgeCurrentCollectionEntry>,
    pub continuation: Option<String>,
}
