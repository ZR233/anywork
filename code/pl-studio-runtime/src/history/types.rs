use std::sync::Arc;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub use pl_protocol::{
    CacheUsageSummary, ChatAtomKind as HistoryEntityKind, ChatDeliveryKind as HistoryDelivery,
    ChatScope, ChatSourceId as HistorySource, ChatToolIdentity as HistoryToolIdentity,
    SingleVisibility as HistorySingleVisibility, ThreadTextChannel,
};

pub const HISTORY_SCHEMA_VERSION: u32 = 25;
pub const HISTORY_PROTOCOL_VERSION: u32 = 1;
pub const BODY_CHUNK_BYTES: usize = 64 * 1024;
pub const HEAD_MAX_BYTES: usize = 16 * 1024;

#[derive(Debug, thiserror::Error)]
pub enum HistoryError {
    #[error("invalid history event: {0}")]
    InvalidEvent(String),
    #[error("invalid history demand: {0}")]
    InvalidDemand(String),
    #[error("invalid or stale history cursor")]
    InvalidCursor,
    #[error("history identity conflicts: {0}")]
    Conflict(String),
    #[error("history integrity error: {0}")]
    Integrity(String),
    #[error("history object not found: {0}")]
    NotFound(String),
    #[error("history pending capacity reached")]
    Capacity,
    #[error("history owner is closed")]
    Closed,
    #[error(transparent)]
    Database(#[from] sea_orm::DbErr),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Storage(#[from] anyhow::Error),
}

pub type Result<T> = std::result::Result<T, HistoryError>;

macro_rules! event_kinds {
    ($($variant:ident => $name:literal),* $(,)?) => {
        #[derive(Debug, Clone, PartialEq, Eq)]
        pub enum HistoryEventKind { $($variant,)* Other(String) }
        impl HistoryEventKind {
            pub fn as_str(&self) -> &str {
                match self { $(Self::$variant => $name,)* Self::Other(value) => value }
            }
        }
        impl From<String> for HistoryEventKind {
            fn from(value: String) -> Self {
                match value.as_str() { $($name => Self::$variant,)* _ => Self::Other(value) }
            }
        }
    };
}
event_kinds! {
    RunStarted => "run_started", RunEnded => "run_ended",
    TurnStarted => "turn_started", TurnChanged => "turn_changed",
    TurnEnded => "turn_ended", TurnRolledBack => "turn_rolled_back",
    SourceStarted => "source_started", SourceEnded => "source_ended",
    InputAccepted => "input_accepted", InputConsumed => "input_consumed",
    InputDiscarded => "input_discarded", EntityStarted => "entity_started",
    EntityStateChanged => "entity_state_changed", EntityEnded => "entity_ended",
    ContentBecameVisible => "content_became_visible", GroupOpened => "group_opened",
    GroupHeadChanged => "group_head_changed", GroupClosed => "group_closed",
    BoundaryObserved => "boundary_observed", UsageRecorded => "usage_recorded",
    UsageAdjusted => "usage_adjusted", BackgroundDeliveryRecorded => "background_delivery_recorded",
    BusinessChanged => "business_changed", LegacyObserved => "legacy_observed",
}
impl Serialize for HistoryEventKind {
    fn serialize<S: serde::Serializer>(
        &self,
        serializer: S,
    ) -> std::result::Result<S::Ok, S::Error> {
        serializer.serialize_str(self.as_str())
    }
}
impl<'de> Deserialize<'de> for HistoryEventKind {
    fn deserialize<D: serde::Deserializer<'de>>(
        deserializer: D,
    ) -> std::result::Result<Self, D::Error> {
        Ok(String::deserialize(deserializer)?.into())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryEventHeader {
    pub seq: u64,
    pub event_id: String,
    pub kind: HistoryEventKind,
    pub run_id: Option<String>,
    pub attempt_id: Option<String>,
    pub entity_id: Option<String>,
    pub turn_id: Option<String>,
    pub source: Option<HistorySource>,
    pub call_id: Option<String>,
    pub message_id: Option<String>,
    pub group_id: Option<String>,
    pub row_key: Option<String>,
    pub original: Option<HistoryOriginalInfo>,
    pub occurred_at: Option<i64>,
    pub recorded_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryOriginalInfo {
    pub query_class: String,
    pub parent_id: Option<String>,
    pub original_kind: HistoryEntityKind,
    pub tool_name: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
pub enum HistoryRowHead {
    Work(HistoryWorkHead),
    Single(HistoryEntityHead),
    Member(HistoryEntityHead),
    Turn(HistoryTurnHead),
    Source(HistorySourceHead),
    Cost(HistoryCostHead),
    Accounting(HistoryAccountingHead),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryWorkHead {
    pub group_id: String,
    pub run_id: Option<String>,
    pub started_at: Option<i64>,
    pub boundary_at: Option<i64>,
    pub closed: bool,
    pub member_count: u64,
    pub unfinished_count: u64,
    pub execution_present: bool,
    pub summary: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryEntityHead {
    pub entity_id: String,
    pub run_id: Option<String>,
    pub attempt_id: Option<String>,
    pub source: HistorySource,
    pub kind: HistoryEntityKind,
    pub delivery: HistoryDelivery,
    pub state: HistoryEntityState,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub text_channel: Option<ThreadTextChannel>,
    pub tool: Option<HistoryToolIdentity>,
    pub wait: Option<HistoryWaitHead>,
    pub content_present: Option<bool>,
    pub single_visibility: Option<HistorySingleVisibility>,
    pub observation: HistoryObservation,
    pub presentation_contract: Option<String>,
    pub detail_event_id: Option<String>,
    pub input_manifest_event_id: Option<String>,
    pub body_manifest_event_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum HistoryEntityState {
    Unknown,
    KnownActive {
        status: pl_protocol::ChatActiveStatus,
    },
    KnownTerminal {
        outcome: pl_protocol::ChatTerminalOutcome,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum HistoryObservation {
    Original,
    Boundary { captured_at: Option<i64> },
    UnavailableLegacy { captured_at: Option<i64> },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum HistoryWaitHead {
    Inline {
        presentation: pl_protocol::ThreadWaitPresentation,
    },
    Deferred {
        intent: HistoryWaitIntentHead,
        state: pl_protocol::ThreadWaitState,
        messages_ready: Option<bool>,
        presentation: HistoryEventBodyRef,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum HistoryWaitIntentHead {
    Events { target_count: u64, timeout_ms: u64 },
    Timer { duration_ms: u64 },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryTurnHead {
    pub turn_id: String,
    pub input_id: Option<String>,
    pub run_id: Option<String>,
    pub state: HistoryTurnState,
    pub phase: Option<pl_protocol::TurnPhase>,
    pub context_disposition: pl_protocol::ThreadContextDisposition,
    pub queued_at: Option<i64>,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub updated_at: i64,
    pub detail_event_id: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum HistoryTurnState {
    Unknown,
    Queued,
    Running,
    Completed,
    Cancelled,
    Failed,
    BudgetLimited,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistorySourceHead {
    pub source: HistorySource,
    pub lifecycle: pl_protocol::ChatSourceLifecycle,
    pub started_at: Option<i64>,
    pub ended_at: Option<i64>,
    pub observed_at: Option<i64>,
    pub detail_event_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryCostHead {
    pub purpose: Option<String>,
    pub currency: String,
    pub cost_delta: Option<f64>,
    pub cost_total: f64,
    pub cache_savings_delta: Option<f64>,
    pub cache_savings_total: Option<f64>,
    pub updated_at: i64,
    pub detail_event_id: Option<String>,
}
impl HistoryCostHead {
    pub fn row_key(&self) -> Result<String> {
        Ok(format!(
            "cost:{}",
            serde_json::to_string(&(&self.purpose, &self.currency))?
        ))
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryAccountingHead {
    pub prompt_tokens: u64,
    pub completion_tokens: u64,
    pub cached_prompt_tokens: u64,
    pub cache_write_tokens: u64,
    pub reasoning_tokens: u64,
    pub inference_count: u64,
    pub total_tokens: u64,
    pub cache_usage: CacheUsageSummary,
    pub has_incomplete_usage: bool,
    pub has_unpriced_usage: bool,
    pub updated_at: i64,
    pub detail_event_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryCut {
    pub token: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryDemand {
    pub max_rows: u32,
    pub max_bytes: u32,
}
impl Default for HistoryDemand {
    fn default() -> Self {
        Self {
            max_rows: 64,
            max_bytes: 64 * 1024,
        }
    }
}
impl HistoryDemand {
    pub(super) fn validate(self) -> Result<()> {
        if !(1..=512).contains(&self.max_rows) || !(1..=1024 * 1024).contains(&self.max_bytes) {
            return Err(HistoryError::InvalidDemand(
                "rows must be 1..512 and bytes 1..1048576".into(),
            ));
        }
        Ok(())
    }
    pub(super) fn fits(&self, value: &impl Serialize) -> Result<bool> {
        Ok(serde_json::to_vec(value)?.len() <= self.max_bytes as usize)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum HistoryEventsQuery {
    AllEvents,
    Entity { entity_id: String },
    Turn { turn_id: String },
    Source { source: HistorySource },
    Call { call_id: String },
    Message { message_id: String },
    Attempt { run_id: String, attempt_id: String },
    Originals { scope: ChatScope },
    TextOriginals,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryTimelineEntry {
    pub row_key: String,
    pub anchor_seq: u64,
    pub head_seq: u64,
    pub head: HistoryRowHead,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryTimelinePage {
    pub cut: HistoryCut,
    pub entries: Vec<HistoryTimelineEntry>,
    pub next: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryGroupPage {
    pub cut: HistoryCut,
    pub group_id: String,
    pub members: Vec<HistoryTimelineEntry>,
    pub next: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryEventBodyRef {
    pub database_id: String,
    pub owner_event_id: String,
    pub body_key: String,
    pub body_id: String,
    pub byte_start: u64,
    pub byte_length: u64,
}
pub type HistoryPayloadRef = HistoryEventBodyRef;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryBodyWindow {
    pub offset: u64,
    pub bytes: Vec<u8>,
    pub total_length: u64,
    pub media_type: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryEventDetail {
    pub header: HistoryEventHeader,
    pub head: Option<HistoryRowHead>,
    pub payload_ref: Option<HistoryPayloadRef>,
    pub owned_manifest_event_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryEventsPage {
    pub cut: HistoryCut,
    pub entries: Vec<HistoryEventDetail>,
    pub next: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum HistoryBodyRole {
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
impl HistoryBodyRole {
    pub(super) fn as_str(&self) -> &str {
        match self {
            Self::CanonicalPayload => "canonical_payload",
            Self::CanonicalMetadata => "canonical_metadata",
            Self::Body => "body",
            Self::ReasoningSummary => "reasoning_summary",
            Self::ToolArguments => "tool_arguments",
            Self::ToolOutput => "tool_output",
            Self::Attachment => "attachment",
            Self::WaitPresentation => "wait_presentation",
            Self::Other { name } => name,
        }
    }
    pub(super) fn from_string(name: String) -> Self {
        match name.as_str() {
            "canonical_payload" => Self::CanonicalPayload,
            "canonical_metadata" => Self::CanonicalMetadata,
            "body" => Self::Body,
            "reasoning_summary" => Self::ReasoningSummary,
            "tool_arguments" => Self::ToolArguments,
            "tool_output" => Self::ToolOutput,
            "attachment" => Self::Attachment,
            "wait_presentation" => Self::WaitPresentation,
            _ => Self::Other { name },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryBodyEntry {
    pub ordinal: u64,
    pub body_key: String,
    pub role: HistoryBodyRole,
    pub reference: HistoryEventBodyRef,
    pub media_type: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryBodyPage {
    pub owner_event_id: String,
    pub entries: Vec<HistoryBodyEntry>,
    pub next: Option<String>,
}

/// Immutable bytes supplied by the producer. Reuse this object when retrying an event.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HistoryBody {
    pub body_id: String,
    pub body_key: String,
    pub role: HistoryBodyRole,
    pub media_type: Option<String>,
    pub bytes: Arc<[u8]>,
}
impl HistoryBody {
    pub fn new(key: impl Into<String>, role: HistoryBodyRole, bytes: impl Into<Arc<[u8]>>) -> Self {
        Self {
            body_id: uuid::Uuid::new_v4().to_string(),
            body_key: key.into(),
            role,
            media_type: None,
            bytes: bytes.into(),
        }
    }
    pub(super) fn digest(&self) -> Vec<u8> {
        Sha256::digest(&self.bytes).to_vec()
    }
}

/// The owner assigns `header.seq`; callers submit zero. The full semantic batch becomes visible
/// together. Bodies and header references are validated before acceptance.
#[derive(Debug, Clone, PartialEq)]
pub struct HistoryEvent {
    pub header: HistoryEventHeader,
    pub head: Option<HistoryRowHead>,
    pub is_anchor: bool,
    pub payload_body_id: Option<String>,
    pub bodies: Vec<HistoryBody>,
}
impl HistoryEvent {
    pub fn new(event_id: impl Into<String>, kind: HistoryEventKind, recorded_at: i64) -> Self {
        Self {
            header: HistoryEventHeader {
                seq: 0,
                event_id: event_id.into(),
                kind,
                run_id: None,
                attempt_id: None,
                entity_id: None,
                turn_id: None,
                source: None,
                call_id: None,
                message_id: None,
                group_id: None,
                row_key: None,
                original: None,
                occurred_at: None,
                recorded_at,
            },
            head: None,
            is_anchor: false,
            payload_body_id: None,
            bodies: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct HistoryLimits {
    pub pending_events: u32,
    pub pending_bytes: u32,
}
impl Default for HistoryLimits {
    fn default() -> Self {
        Self {
            pending_events: 4096,
            pending_bytes: 64 * 1024 * 1024,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HistoryStatus {
    pub pending_events: usize,
    pub pending_bytes: usize,
    pub write_error: Option<String>,
    pub accepting: bool,
}

pub(super) fn source_key(source: &HistorySource) -> Result<(String, String)> {
    let kind = match source {
        HistorySource::ForegroundTurn { .. } => "foreground_turn",
        HistorySource::Input { .. } => "input",
        HistorySource::InboxMessage { .. } => "inbox_message",
        HistorySource::BackgroundResult { .. } => "background_result",
        HistorySource::Operation { .. } => "operation",
        HistorySource::Receipt { .. } => "receipt",
    };
    Ok((kind.into(), serde_json::to_string(source)?))
}

impl HistoryRowHead {
    pub(super) fn scope(&self) -> &'static str {
        match self {
            Self::Work(_) => "work",
            Self::Single(_) => "single",
            Self::Member(_) => "member",
            Self::Turn(_) => "turn",
            Self::Source(_) => "source",
            Self::Cost(_) => "cost",
            Self::Accounting(_) => "accounting",
        }
    }
}
