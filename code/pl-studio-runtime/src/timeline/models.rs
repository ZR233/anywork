//! Unified domain DTOs for Native timeline patches, live status state machine, and session metadata.

use serde::{Deserialize, Serialize};

use pl_core::thread::UsageSummary;

use crate::{
    ThreadActivity, ThreadModelRouteSnapshot, ThreadRuntimeSnapshot, ThreadRuntimeUsage,
    ThreadStorageState, Turn, mode::ThreadModeId,
};

pub type TimelineItemId = String;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BodyRef {
    pub database_id: String,
    pub body_id: String,
    pub owner_event_id: String,
    pub body_key: String,
    pub role: String,
    pub byte_length: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub media_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub inline_text: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BodyWindow {
    pub offset: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bytes_base64: Option<String>,
    pub total_bytes: u64,
    pub eof: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum WorkGroupStatus {
    Active,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum TimelineItem {
    UserMessage {
        id: TimelineItemId,
        seq: u64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        turn_id: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        input_id: Option<String>,
        channel: String,
        text: String,
        attachments: Vec<serde_json::Value>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        occurred_at_ms: Option<i64>,
    },
    AssistantText {
        id: TimelineItemId,
        seq: u64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        turn_id: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        attempt_id: Option<String>,
        channel: String,
        text: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        body_ref: Option<BodyRef>,
        is_final_turn_delivery: bool,
        outcome: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        model_recovery: Option<Box<crate::ModelRecoveryNotice>>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        occurred_at_ms: Option<i64>,
    },
    WorkGroup {
        id: TimelineItemId,
        first_seq: u64,
        last_seq: u64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        after_boundary_seq: Option<u64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        before_boundary_seq: Option<u64>,
        member_count: u32,
        summary: String,
        status: WorkGroupStatus,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        started_at_ms: Option<i64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        finished_at_ms: Option<i64>,
    },
    Compaction {
        id: TimelineItemId,
        seq: u64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        turn_id: Option<String>,
        summary: String,
        outcome: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        tokens_before: Option<u64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        tokens_after: Option<u64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        occurred_at_ms: Option<i64>,
    },
    PlanResolution {
        id: TimelineItemId,
        seq: u64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        turn_id: Option<String>,
        decision: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        document: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        document_ref: Option<BodyRef>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        feedback: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        occurred_at_ms: Option<i64>,
    },
    ConnectionNotice {
        id: TimelineItemId,
        seq: u64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        turn_id: Option<String>,
        scope: String,
        state: String,
        transport: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        fallback_transport: Option<String>,
        attempt: u32,
        max_attempts: u32,
        recoverable: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        reason: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        duration_ms: Option<u64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        occurred_at_ms: Option<i64>,
    },
    TurnOutcome {
        id: TimelineItemId,
        seq: u64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        turn_id: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        input_id: Option<String>,
        outcome: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        turn_failure: Option<Box<crate::TurnFailure>>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        occurred_at_ms: Option<i64>,
    },
    StandaloneTool {
        id: TimelineItemId,
        seq: u64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        turn_id: Option<String>,
        call_id: String,
        tool_name: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        presentation_contract: Option<String>,
        state: String,
        summary: String,
        payload_json: String,
        bodies: Vec<BodyRef>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        occurred_at_ms: Option<i64>,
    },
    Fallback {
        id: TimelineItemId,
        seq: u64,
        event_id: String,
        event_kind: String,
        reason: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        raw_preview: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        occurred_at_ms: Option<i64>,
    },
}

impl TimelineItem {
    #[must_use]
    pub fn id(&self) -> &str {
        match self {
            Self::UserMessage { id, .. }
            | Self::AssistantText { id, .. }
            | Self::WorkGroup { id, .. }
            | Self::Compaction { id, .. }
            | Self::PlanResolution { id, .. }
            | Self::ConnectionNotice { id, .. }
            | Self::TurnOutcome { id, .. }
            | Self::StandaloneTool { id, .. }
            | Self::Fallback { id, .. } => id,
        }
    }

    #[must_use]
    pub fn seq(&self) -> u64 {
        match self {
            Self::WorkGroup { last_seq, .. } => *last_seq,
            Self::UserMessage { seq, .. }
            | Self::AssistantText { seq, .. }
            | Self::Compaction { seq, .. }
            | Self::PlanResolution { seq, .. }
            | Self::ConnectionNotice { seq, .. }
            | Self::TurnOutcome { seq, .. }
            | Self::StandaloneTool { seq, .. }
            | Self::Fallback { seq, .. } => *seq,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum WorkGroupMember {
    Reasoning {
        id: String,
        seq: u64,
        text: String,
        summary: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        body_ref: Option<BodyRef>,
        outcome: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        started_at_ms: Option<i64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        finished_at_ms: Option<i64>,
    },
    ToolCall {
        id: String,
        seq: u64,
        call_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        turn_id: Option<String>,
        tool_name: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        presentation_contract: Option<String>,
        status: String,
        summary: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        arguments: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        result_preview: Option<String>,
        payload_json: String,
        bodies: Vec<BodyRef>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        wait_json: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        started_at_ms: Option<i64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        finished_at_ms: Option<i64>,
    },
    Agent {
        id: String,
        seq: u64,
        agent_id: String,
        name: String,
        status: String,
        summary: String,
        payload_json: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        started_at_ms: Option<i64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        finished_at_ms: Option<i64>,
    },
    FileChange {
        id: String,
        seq: u64,
        summary: String,
        payload_json: String,
        bodies: Vec<BodyRef>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        occurred_at_ms: Option<i64>,
    },
    Skill {
        id: String,
        seq: u64,
        name: String,
        summary: String,
        payload_json: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        occurred_at_ms: Option<i64>,
    },
    Fallback {
        id: String,
        seq: u64,
        event_id: String,
        event_kind: String,
        reason: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        occurred_at_ms: Option<i64>,
    },
}

impl WorkGroupMember {
    #[must_use]
    pub fn id(&self) -> &str {
        match self {
            Self::Reasoning { id, .. }
            | Self::ToolCall { id, .. }
            | Self::Agent { id, .. }
            | Self::FileChange { id, .. }
            | Self::Skill { id, .. }
            | Self::Fallback { id, .. } => id,
        }
    }

    #[must_use]
    pub fn seq(&self) -> u64 {
        match self {
            Self::Reasoning { seq, .. }
            | Self::ToolCall { seq, .. }
            | Self::Agent { seq, .. }
            | Self::FileChange { seq, .. }
            | Self::Skill { seq, .. }
            | Self::Fallback { seq, .. } => *seq,
        }
    }
}

#[allow(clippy::large_enum_variant)]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum TimelinePatch {
    Reset {
        items: Vec<TimelineItem>,
        has_more_older: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        older_cursor: Option<String>,
        revision: u64,
    },
    PrependOlder {
        items: Vec<TimelineItem>,
        has_more_older: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        older_cursor: Option<String>,
    },
    Append {
        items: Vec<TimelineItem>,
    },
    Update {
        item: TimelineItem,
    },
    Remove {
        item_id: TimelineItemId,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LiveAttention {
    pub id: String,
    pub kind: String,
    pub summary: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub call_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "phase",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum LiveStatusPhase {
    Idle,
    Working {
        items: Vec<WorkGroupMember>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        reasoning_preview: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        started_at_ms: Option<i64>,
    },
    StreamingText {
        attempt_id: String,
        item_id: String,
        text: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        started_at_ms: Option<i64>,
    },
    Compacting {
        manual: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        started_at_ms: Option<i64>,
    },
    Reconnecting {
        attempt_id: String,
        message: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        retry_after_ms: Option<u64>,
        attempt: u32,
        #[serde(default)]
        max_attempts: u32,
    },
    Stopping {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        started_at_ms: Option<i64>,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LiveStatusSnapshot {
    pub revision: u64,
    pub phase: LiveStatusPhase,
    pub attentions: Vec<LiveAttention>,
    pub suppressed_by_interaction: bool,
}

impl Default for LiveStatusSnapshot {
    fn default() -> Self {
        Self {
            revision: 0,
            phase: LiveStatusPhase::Idle,
            attentions: Vec::new(),
            suppressed_by_interaction: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionMetaSnapshot {
    pub thread_id: String,
    pub status: crate::ThreadStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_thread_id: Option<String>,
    pub root_thread_id: String,
    pub owner_epoch: String,
    pub revision: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub active_turn: Option<Turn>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_turn: Option<Turn>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub activity: Option<ThreadActivity>,
    pub usage: UsageSummary,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context_metrics: Option<ThreadRuntimeUsage>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_route: Option<ThreadModelRouteSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub runtime: Option<ThreadRuntimeSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub storage_state: Option<ThreadStorageState>,
    #[serde(default)]
    pub interactions: Vec<crate::InteractionRequest>,
    pub pending_interaction_count: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub plan: Option<crate::plan_tool::AgentSessionPlanRuntimeSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<ThreadModeId>,
    pub execution_present: bool,
}

#[allow(clippy::large_enum_variant)]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ConversationEvent {
    Timeline(TimelinePatch),
    LiveStatus(LiveStatusSnapshot),
    SessionMeta(SessionMetaSnapshot),
    InputPresented {
        input_id: String,
        item_id: TimelineItemId,
    },
    ResyncRequired {
        reason: String,
    },
}
