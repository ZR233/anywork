//! Independent append-only atomic History query and hybrid body protocol (Schema 26 / v2).
pub use crate::{
    CacheUsageSummary, ChatAtomKind as HistoryEntityKind, ChatDeliveryKind as HistoryDelivery,
    ChatScope, ChatSourceId as HistorySource, ChatToolIdentity as HistoryToolIdentity,
    ThreadTextChannel,
};
use serde::{Deserialize, Serialize};

pub const HISTORY_SCHEMA_VERSION: u32 = 26;
pub const HISTORY_PROTOCOL_VERSION: u32 = 2;
pub const INLINE_BODY_MAX_BYTES: usize = 16 * 1024;
pub const INLINE_EVENT_MAX_BYTES: usize = 16 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum HistorySingleVisibility {
    Content,
    FinalEmptyAfterContent,
}

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
    RunStarted => "run_started",
    RunEnded => "run_ended",
    TurnStarted => "turn_started",
    TurnChanged => "turn_changed",
    TurnEnded => "turn_ended",
    TurnRolledBack => "turn_rolled_back",
    SourceStarted => "source_started",
    SourceEnded => "source_ended",
    UsageRecorded => "usage_recorded",
    UsageAdjusted => "usage_adjusted",
    ParentReportRecorded => "parent_report_recorded",
    ReviewDeliveryRecorded => "review_delivery_recorded",
    RetainedResourceRecorded => "retained_resource_recorded",
    BackgroundDeliveryRecorded => "background_delivery_recorded",
    BusinessChanged => "business_changed",
    InputAccepted => "input_accepted",
    InputConsumed => "input_consumed",
    InputDiscarded => "input_discarded",
    TextCompleted => "text_completed",
    PlanResolved => "plan_resolved",
    TurnReceiptRecorded => "turn_receipt_recorded",
    InboxMessageReceived => "inbox_message_received",
    ToolCalled => "tool_called",
    ToolWaitingApproval => "tool_waiting_approval",
    ToolBackgrounded => "tool_backgrounded",
    ToolCancelRequested => "tool_cancel_requested",
    ToolCompleted => "tool_completed",
    ReasoningStarted => "reasoning_started",
    ReasoningCompleted => "reasoning_completed",
    CompactionStarted => "compaction_started",
    CompactionCompleted => "compaction_completed",
    AgentSpawned => "agent_spawned",
    AgentCompleted => "agent_completed",
    ItemRecorded => "item_recorded",
    LegacyObserved => "legacy_observed",
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum HistoryTimelineRole {
    Divider,
    Work,
    Hidden,
}

impl HistoryTimelineRole {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Divider => "divider",
            Self::Work => "work",
            Self::Hidden => "hidden",
        }
    }

    pub fn from_db(value: &str) -> Option<Self> {
        match value {
            "divider" => Some(Self::Divider),
            "work" => Some(Self::Work),
            "hidden" => Some(Self::Hidden),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum HistoryBusinessRowScope {
    Turn,
    Source,
    Cost,
    Accounting,
}

impl HistoryBusinessRowScope {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Turn => "turn",
            Self::Source => "source",
            Self::Cost => "cost",
            Self::Accounting => "accounting",
        }
    }

    pub fn from_db(value: &str) -> Option<Self> {
        match value {
            "turn" => Some(Self::Turn),
            "source" => Some(Self::Source),
            "cost" => Some(Self::Cost),
            "accounting" => Some(Self::Accounting),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryOriginalInfo {
    pub query_class: String,
    pub parent_id: Option<String>,
    pub original_kind: HistoryEntityKind,
    pub tool_name: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum HistoryEntityState {
    Unknown,
    KnownActive { status: crate::ChatActiveStatus },
    KnownTerminal { outcome: crate::ChatTerminalOutcome },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum HistoryWaitHead {
    Inline {
        presentation: crate::ThreadWaitPresentation,
    },
    Deferred {
        intent: HistoryWaitIntentHead,
        state: crate::ThreadWaitState,
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
#[serde(rename_all = "camelCase")]
pub struct HistoryEventMeta {
    pub entity_id: String,
    pub entity_kind: HistoryEntityKind,
    pub delivery: HistoryDelivery,
    pub state: HistoryEntityState,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub text_channel: Option<ThreadTextChannel>,
    pub single_visibility: Option<HistorySingleVisibility>,
    pub presentation_contract: Option<String>,
    pub source_order: Option<u64>,
    pub content_present: Option<bool>,
    pub wait: Option<HistoryWaitHead>,
    pub tool: Option<HistoryToolIdentity>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryBodyManifestEntry {
    pub key: String,
    pub role: String,
    pub byte_length: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub media_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub inline_text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reference: Option<HistoryEventBodyRef>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryEventRecord {
    pub seq: u64,
    pub event_id: String,
    pub kind: HistoryEventKind,
    pub timeline_role: HistoryTimelineRole,
    pub occurred_at: Option<i64>,
    pub recorded_at: i64,
    pub run_id: Option<String>,
    pub turn_id: Option<String>,
    pub attempt_id: Option<String>,
    pub call_id: Option<String>,
    pub entity_id: Option<String>,
    pub message_id: Option<String>,
    pub tool_name: Option<String>,
    pub source: Option<HistorySource>,
    pub original: Option<HistoryOriginalInfo>,
    pub row_scope: Option<HistoryBusinessRowScope>,
    pub row_key: Option<String>,
    pub payload_schema: String,
    pub payload_json: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryWorkRange {
    pub range_id: String,
    pub after_seq: Option<u64>,
    pub before_seq: Option<u64>,
    pub first_seq: u64,
    pub last_seq: u64,
    pub started_at: Option<i64>,
    pub ended_at: Option<i64>,
    pub run_id: Option<String>,
    pub event_count: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
#[allow(clippy::large_enum_variant)]
pub enum HistoryTimelineItem {
    Divider(HistoryEventRecord),
    WorkRange(HistoryWorkRange),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryTimelinePage {
    pub cut: HistoryCut,
    pub items: Vec<HistoryTimelineItem>,
    pub next: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryWorkRangePage {
    pub cut: HistoryCut,
    pub after_seq: Option<u64>,
    pub before_seq: Option<u64>,
    pub events: Vec<HistoryEventRecord>,
    pub next: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryTurnHead {
    pub turn_id: String,
    pub input_id: Option<String>,
    pub run_id: Option<String>,
    pub state: HistoryTurnState,
    pub phase: Option<crate::TurnPhase>,
    pub context_disposition: crate::ThreadContextDisposition,
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
#[serde(rename_all = "camelCase")]
pub struct HistorySourceHead {
    pub source: HistorySource,
    pub lifecycle: crate::ChatSourceLifecycle,
    pub started_at: Option<i64>,
    pub ended_at: Option<i64>,
    pub observed_at: Option<i64>,
    pub detail_event_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
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
    pub fn row_key(&self) -> serde_json::Result<String> {
        Ok(format!(
            "cost:{}",
            serde_json::to_string(&(&self.purpose, &self.currency))?
        ))
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
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

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
pub enum HistoryBusinessRowHead {
    Turn(HistoryTurnHead),
    Source(HistorySourceHead),
    Cost(HistoryCostHead),
    Accounting(HistoryAccountingHead),
}

impl HistoryBusinessRowHead {
    pub fn scope(&self) -> HistoryBusinessRowScope {
        match self {
            Self::Turn(_) => HistoryBusinessRowScope::Turn,
            Self::Source(_) => HistoryBusinessRowScope::Source,
            Self::Cost(_) => HistoryBusinessRowScope::Cost,
            Self::Accounting(_) => HistoryBusinessRowScope::Accounting,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryBusinessRowEntry {
    pub row_key: String,
    pub anchor_seq: u64,
    pub head_seq: u64,
    pub head: HistoryBusinessRowHead,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryBusinessPage {
    pub cut: HistoryCut,
    pub entries: Vec<HistoryBusinessRowEntry>,
    pub next: Option<String>,
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
            max_bytes: 128 * 1024,
        }
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HistoryBodyWindow {
    pub offset: u64,
    pub bytes: Vec<u8>,
    pub total_length: u64,
    pub media_type: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryEventsPage {
    pub cut: HistoryCut,
    pub entries: Vec<HistoryEventRecord>,
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
    pub fn as_str(&self) -> &str {
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

    pub fn from_string(name: String) -> Self {
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
