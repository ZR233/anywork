//! Lightweight atomic facts and actual source lifecycle, never presentation groups.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::{ContentRef, PayloadData};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ChatSourceId {
    ForegroundTurn { turn_id: String },
    Input { input_id: String },
    BackgroundResult { message_id: String },
    Operation { operation_id: String },
    Receipt { receipt_id: String },
}

/// Canonical effect and its stable intra-effect position, not transport delivery order.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatFactPosition {
    pub effect_seq: u64,
    pub suborder: u32,
}

/// Domain kind. Tool UI categories, work-group boundaries and titles belong to Flutter.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ChatAtomKind {
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ChatDeliveryKind {
    Foreground,
    BackgroundHandoff,
    Independent,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ChatActiveStatus {
    Running,
    Waiting,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ChatTerminalOutcome {
    Completed,
    Failed,
    Cancelled,
    /// The foreground obligation ended, not the background task.
    Transferred,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ChatAtomLifecycle {
    Active {
        /// Unknown for attributable legacy previews without recorded start evidence.
        started: Option<ChatFactPosition>,
        status: ChatActiveStatus,
    },
    Terminal {
        started: Option<ChatFactPosition>,
        /// Missing historical evidence stays unknown; never substitute read/paint time.
        ended: Option<ChatFactPosition>,
        outcome: ChatTerminalOutcome,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatToolIdentity {
    pub call_id: String,
    pub name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ChatContentRole {
    Body,
    ReasoningSummary,
    ToolArguments,
    ToolOutput,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatAtomContent {
    pub role: ChatContentRole,
    pub reference: ContentRef,
}

/// Usable without decoding a potentially large or Deferred payload.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatAtom {
    /// Stable member/part identity, including the active-to-completed handoff.
    pub id: String,
    /// The original frozen completion may be a distinct background-started receipt.
    pub completion_item_id: Option<String>,
    /// Actual completion publication order; absent before completion.
    pub completion_seq: Option<u64>,
    pub source: ChatSourceId,
    /// Actual source state at this read cut, not frozen into completion metadata.
    /// Reliable source changes are delivered independently as `ChatEntry::Source`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_state: Option<ChatSourceState>,
    /// Stable actual source position, not a dense UI index. Legacy absence stays unknown.
    pub source_order: Option<u64>,
    pub kind: ChatAtomKind,
    pub delivery: ChatDeliveryKind,
    pub lifecycle: ChatAtomLifecycle,
    pub turn_id: Option<String>,
    pub attempt_id: Option<String>,
    pub tool: Option<ChatToolIdentity>,
    /// Existing typed tool facts while active; never a completion payload or group state.
    /// Terminal atoms retain the original wait facts in their frozen payload instead.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wait: Option<crate::ThreadWaitPresentation>,
    pub text_channel: Option<crate::ThreadTextChannel>,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub contents: Vec<ChatAtomContent>,
    /// Absent for an active fact. Frozen payload ownership stays with the original item.
    pub payload: Option<PayloadData>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ChatSourceLifecycle {
    Unknown,
    Active,
    Ended { outcome: ChatTerminalOutcome },
}

/// Actual Turn/input/background/operation state at the read cut. It contains no
/// member frontier, closed-through position, group range or presentation-ready flag.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatSourceState {
    pub source: ChatSourceId,
    pub lifecycle: ChatSourceLifecycle,
    pub started: Option<ChatFactPosition>,
    pub ended: Option<ChatFactPosition>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
pub enum ChatEntry {
    /// Keep lifecycle-only entries small without changing the serialized envelope.
    Atom(Box<ChatAtom>),
    /// A reliable lifecycle event, not an extra row of per-page source evidence.
    Source(ChatSourceState),
}
