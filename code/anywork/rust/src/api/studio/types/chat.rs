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

/// A mechanical FRB boundary for the canonical pl-protocol ChatBatch.
#[derive(Debug, Clone)]
pub struct BridgeChatBatch {
    pub placement: BridgeChatPlacement,
    pub entries: Vec<BridgeChatEntry>,
    pub before: Option<String>,
    pub current: Option<BridgeCurrentProjection>,
}

#[derive(Debug, Clone)]
pub enum BridgeChatEntry {
    Atom(Box<BridgeChatAtom>),
    Source(BridgeChatSourceState),
}

#[derive(Debug, Clone)]
pub struct BridgeChatAtom {
    pub id: String,
    pub completion_item_id: Option<String>,
    pub completion_seq: Option<u64>,
    pub source: BridgeChatSourceId,
    pub source_state: Option<BridgeChatSourceState>,
    pub source_order: Option<u64>,
    pub kind: BridgeChatAtomKind,
    pub delivery: BridgeChatDeliveryKind,
    pub lifecycle: BridgeChatAtomLifecycle,
    pub turn_id: Option<String>,
    pub attempt_id: Option<String>,
    pub tool: Option<BridgeChatToolIdentity>,
    pub wait: Option<super::BridgeThreadWaitPresentation>,
    pub text_channel: Option<BridgeThreadTextChannel>,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub contents: Vec<BridgeChatAtomContent>,
    pub payload: Option<BridgePayloadData>,
}

#[derive(Debug, Clone)]
pub enum BridgeChatSourceId {
    ForegroundTurn { turn_id: String },
    Input { input_id: String },
    BackgroundResult { message_id: String },
    Operation { operation_id: String },
    Receipt { receipt_id: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeChatFactPosition {
    pub effect_seq: u64,
    pub suborder: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeChatAtomKind {
    Input,
    Text,
    Reasoning,
    ToolCall,
    FileChange,
    Skill,
    Interaction,
    Plan,
    Compaction,
    TurnReceipt,
    Receipt,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeChatDeliveryKind {
    Foreground,
    BackgroundHandoff,
    Independent,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeChatActiveStatus {
    Running,
    Waiting,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeChatTerminalOutcome {
    Completed,
    Failed,
    Cancelled,
    Transferred,
}

#[derive(Debug, Clone)]
pub enum BridgeChatAtomLifecycle {
    Active {
        started: Option<BridgeChatFactPosition>,
        status: BridgeChatActiveStatus,
    },
    Terminal {
        started: Option<BridgeChatFactPosition>,
        ended: Option<BridgeChatFactPosition>,
        outcome: BridgeChatTerminalOutcome,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeChatToolIdentity {
    pub call_id: String,
    pub name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeChatContentRole {
    Body,
    ReasoningSummary,
    ToolArguments,
    ToolOutput,
}

#[derive(Debug, Clone)]
pub struct BridgeChatAtomContent {
    pub role: BridgeChatContentRole,
    pub reference: BridgeContentRef,
}

#[derive(Debug, Clone)]
pub enum BridgeChatSourceLifecycle {
    Unknown,
    Active,
    Ended { outcome: BridgeChatTerminalOutcome },
}

#[derive(Debug, Clone)]
pub struct BridgeChatSourceState {
    pub source: BridgeChatSourceId,
    pub lifecycle: BridgeChatSourceLifecycle,
    pub started: Option<BridgeChatFactPosition>,
    pub ended: Option<BridgeChatFactPosition>,
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
    pub sources: Vec<BridgeChatSourceState>,
    pub atoms: Vec<BridgeChatAtom>,
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
