//! Mechanical FRB types for the independent history and current read ports.

use super::{
    BridgeCacheUsageSummary, BridgeChatAtomKind, BridgeChatAtomLifecycle, BridgeChatContentRole,
    BridgeChatDeliveryKind, BridgeChatSourceId, BridgeChatSourceState, BridgeChatTerminalOutcome,
    BridgeChatToolIdentity, BridgeCurrentPlanHead, BridgeThreadActivityKind,
    BridgeThreadActivityToolState, BridgeThreadNotificationEnvelope, BridgeThreadSnapshot,
    BridgeThreadStatus, BridgeThreadTextChannel, BridgeThreadWaitPresentation, BridgeTurnPhase,
};

pub const BRIDGE_HISTORY_PROTOCOL_VERSION: u32 = 3;
pub const BRIDGE_CURRENT_PROTOCOL_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeHistoryCut {
    pub token: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeHistoryDemand {
    pub max_rows: u32,
    pub max_bytes: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeHistoryEventsQuery {
    AllEvents,
    Entity {
        entity_id: String,
    },
    Turn {
        turn_id: String,
    },
    Source {
        source: BridgeChatSourceId,
    },
    Call {
        call_id: String,
    },
    Originals {
        query_class: String,
        parent_id: Option<String>,
    },
    TextOriginals,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeHistoryTimelineRole {
    Boundary,
    Work,
    Hidden,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeHistoryBusinessRowScope {
    Turn,
    Source,
    Cost,
    Accounting,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeHistoryTurnHead {
    pub turn_id: String,
    pub input_id: Option<String>,
    pub run_id: Option<String>,
    pub state: BridgeHistoryTurnState,
    pub phase: Option<BridgeTurnPhase>,
    pub context_disposition: BridgeHistoryContextDisposition,
    pub queued_at: Option<i64>,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub updated_at: i64,
    pub detail_event_id: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeHistoryTurnState {
    Unknown,
    Queued,
    Running,
    Completed,
    Cancelled,
    Failed,
    BudgetLimited,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeHistoryContextDisposition {
    Active,
    RolledBack,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeHistorySourceHead {
    pub source: BridgeChatSourceId,
    pub lifecycle: BridgeHistorySourceLifecycle,
    pub started_at: Option<i64>,
    pub ended_at: Option<i64>,
    pub observed_at: Option<i64>,
    pub detail_event_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeHistorySourceLifecycle {
    Unknown,
    Active,
    Ended { outcome: BridgeChatTerminalOutcome },
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeHistoryCostHead {
    pub purpose: Option<String>,
    pub currency: String,
    pub cost_delta: Option<f64>,
    pub cost_total: f64,
    pub cache_savings_delta: Option<f64>,
    pub cache_savings_total: Option<f64>,
    pub updated_at: i64,
    pub detail_event_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeHistoryAccountingHead {
    pub prompt_tokens: u64,
    pub completion_tokens: u64,
    pub cached_prompt_tokens: u64,
    pub cache_write_tokens: u64,
    pub reasoning_tokens: u64,
    pub inference_count: u64,
    pub total_tokens: u64,
    pub cache_usage: BridgeCacheUsageSummary,
    pub has_incomplete_usage: bool,
    pub has_unpriced_usage: bool,
    pub updated_at: i64,
    pub detail_event_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeHistoryTimelineEntry {
    pub event: BridgeHistoryEventRecord,
    pub has_folded_after: bool,
    pub tail_folded_ended_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeHistoryTimelinePage {
    pub cut: BridgeHistoryCut,
    pub entries: Vec<BridgeHistoryTimelineEntry>,
    pub has_folded_before_oldest: bool,
    pub next: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeHistoryWorkRangePage {
    pub cut: BridgeHistoryCut,
    pub after_seq: Option<u64>,
    pub before_seq: Option<u64>,
    pub events: Vec<BridgeHistoryEventRecord>,
    pub next: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeHistoryBusinessRowHead {
    Turn(BridgeHistoryTurnHead),
    Source(BridgeHistorySourceHead),
    Cost(BridgeHistoryCostHead),
    Accounting(BridgeHistoryAccountingHead),
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeHistoryBusinessRowEntry {
    pub row_key: String,
    pub anchor_seq: u64,
    pub head_seq: u64,
    pub head: BridgeHistoryBusinessRowHead,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeHistoryBusinessPage {
    pub cut: BridgeHistoryCut,
    pub entries: Vec<BridgeHistoryBusinessRowEntry>,
    pub next: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeHistoryOriginalInfo {
    pub query_class: String,
    pub parent_id: Option<String>,
    pub original_kind: BridgeChatAtomKind,
    pub tool_name: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeHistoryEventBodyRef {
    pub database_id: String,
    pub owner_event_id: String,
    pub body_key: String,
    pub body_id: String,
    pub byte_start: u64,
    pub byte_length: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeHistoryEventRecord {
    pub seq: u64,
    pub event_id: String,
    pub kind: String,
    pub timeline_role: BridgeHistoryTimelineRole,
    pub occurred_at: Option<i64>,
    pub recorded_at: i64,
    pub run_id: Option<String>,
    pub turn_id: Option<String>,
    pub attempt_id: Option<String>,
    pub call_id: Option<String>,
    pub entity_id: Option<String>,
    pub message_id: Option<String>,
    pub tool_name: Option<String>,
    pub source: Option<BridgeChatSourceId>,
    pub original: Option<BridgeHistoryOriginalInfo>,
    pub row_scope: Option<BridgeHistoryBusinessRowScope>,
    pub row_key: Option<String>,
    pub payload_schema: String,
    pub payload_json: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeHistoryEventsPage {
    pub cut: BridgeHistoryCut,
    pub entries: Vec<BridgeHistoryEventRecord>,
    pub next: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeHistoryBodyWindow {
    pub offset: u64,
    pub bytes: Vec<u8>,
    pub total_length: u64,
    pub media_type: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeHistoryBodyRole {
    CanonicalPayload,
    CanonicalMetadata,
    Body,
    ReasoningSummary,
    ToolArguments,
    ToolOutput,
    Attachment,
    WaitPresentation,
    Other { name: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeHistoryBodyEntry {
    pub ordinal: u64,
    pub body_key: String,
    pub role: BridgeHistoryBodyRole,
    pub reference: BridgeHistoryEventBodyRef,
    pub media_type: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeHistoryBodyPage {
    pub owner_event_id: String,
    pub entries: Vec<BridgeHistoryBodyEntry>,
    pub next: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeHistoryAccounting {
    pub head: BridgeHistoryAccountingHead,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeOpenHistoryReader {
    pub reader_id: String,
    pub history_protocol_version: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentRevision {
    pub owner_id: String,
    pub revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentContentRef {
    pub owner_id: String,
    pub domain: String,
    pub entity_id: String,
    pub content_key: String,
    pub generation: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeCurrentStateField {
    Body {
        field: String,
        reference: BridgeCurrentContentRef,
        byte_length: u64,
    },
    Collection {
        field: String,
        reference: BridgeCurrentCollectionRef,
        count: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentCollectionRef {
    pub owner_id: String,
    pub collection: String,
    pub revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeCurrentPayloadData {
    Inline {
        bytes: Vec<u8>,
    },
    Deferred {
        reference: BridgeCurrentContentRef,
        byte_length: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentCollectionEntry {
    pub id: String,
    pub position: i64,
    pub payload: BridgeCurrentPayloadData,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentCollectionPage {
    pub revision: u64,
    pub entries: Vec<BridgeCurrentCollectionEntry>,
    pub continuation: Option<String>,
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
    pub reference: BridgeCurrentContentRef,
}

/// Current atoms carry business identity only. History qualification is never inferred here.
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeCurrentAtom {
    pub id: String,
    pub source: BridgeChatSourceId,
    pub source_state: Option<BridgeChatSourceState>,
    pub source_order: Option<u64>,
    pub kind: BridgeChatAtomKind,
    pub delivery: BridgeChatDeliveryKind,
    pub lifecycle: BridgeChatAtomLifecycle,
    pub turn_id: Option<String>,
    pub attempt_id: Option<String>,
    pub tool: Option<BridgeChatToolIdentity>,
    pub wait: Option<BridgeThreadWaitPresentation>,
    pub text_channel: Option<BridgeThreadTextChannel>,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub content_present: Option<bool>,
    pub contents: Vec<BridgeCurrentAtomContent>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentAtomContent {
    pub role: BridgeChatContentRole,
    pub reference: BridgeCurrentContentRef,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeCurrentProjection {
    pub logical_status: BridgeThreadStatus,
    pub execution_present: bool,
    pub active: Option<BridgeCurrentActivityHead>,
    pub active_turn: Option<BridgeCurrentTurnHead>,
    pub sources: Vec<BridgeChatSourceState>,
    pub atoms: Vec<BridgeCurrentAtom>,
    pub plan: Option<BridgeCurrentPlanHead>,
    pub interactions: Option<BridgeCurrentCollectionRef>,
    pub previews: Vec<BridgeCurrentContentPreview>,
    pub collections: Vec<BridgeCurrentCollectionRef>,
    pub model_recovery: Option<BridgeCurrentModelRecovery>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentModelRecovery {
    pub attempt: u32,
    pub max_attempts: u32,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeCurrentActivityHead {
    pub id: String,
    pub kind: BridgeThreadActivityKind,
    pub summary: String,
    pub thinking_summary: Option<String>,
    pub thinking_seconds: Option<u64>,
    pub tool_count: u32,
    pub background_tool_count: u32,
    pub latest_tool: Option<BridgeCurrentToolHead>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentToolHead {
    pub call_id: String,
    pub name: String,
    pub state: BridgeThreadActivityToolState,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentTurnHead {
    pub id: String,
    pub phase: BridgeTurnPhase,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeCurrentView {
    pub revision: BridgeCurrentRevision,
    pub state: Box<BridgeThreadSnapshot>,
    pub projection: BridgeCurrentProjection,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeCurrentFrame {
    Reset {
        view: Box<BridgeCurrentView>,
    },
    Notification {
        revision: BridgeCurrentRevision,
        notification: Box<BridgeThreadNotificationEnvelope>,
    },
    Projection {
        revision: BridgeCurrentRevision,
        projection: Box<BridgeCurrentProjection>,
    },
}

pub struct BridgeOpenCurrentReader {
    pub reader_id: String,
    pub current_protocol_version: u32,
    pub current_owner_id: String,
}
