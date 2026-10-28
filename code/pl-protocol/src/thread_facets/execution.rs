use super::identity::{
    ActivityReadRef, FeedClosedReason, InteractionIndexRef, InteractionReadRef, ResyncReason,
    StorageReadRef, ThreadFacetStamp, ThreadFeedIdentity, TurnReadRef,
};
use crate::studio::{HistoryFault, StudioError, ThreadStorageExecution};
use crate::{
    BudgetLimitSnapshot, InteractionKind, InteractionStatus, ProviderFailureKind, RetryDisposition,
    ThreadActivityKind, ThreadStatus, TurnCompletion, TurnFailureCategory, TurnPhase,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct TurnBrief {
    pub reference: TurnReadRef,
    pub revision: u64,
    pub updated_at: i64,
    pub state: TurnBriefState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum TurnBriefState {
    Queued {
        queued_at: i64,
    },
    Running {
        started_at: i64,
        phase: TurnPhase,
    },
    Completed {
        started_at: Option<i64>,
        completed_at: i64,
        completion: TurnCompletion,
    },
    Cancelled {
        started_at: Option<i64>,
        requested_at: i64,
        completed_at: i64,
        cause: TurnCancellationKind,
    },
    Failed {
        started_at: Option<i64>,
        completed_at: i64,
        category: TurnFailureCategory,
        provider_kind: Option<ProviderFailureKind>,
        http_status: Option<u16>,
        retry: RetryDisposition,
    },
    BudgetLimited {
        started_at: Option<i64>,
        completed_at: i64,
        limit: BudgetLimitSnapshot,
        rollover: TurnRolloverKind,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[derive(utoipa::ToSchema)]
pub enum TurnCancellationKind {
    Unspecified,
    UserRequested,
    RuntimeShutdown,
    AgentClosed,
    Interrupted,
    Recovery,
    Coalesced,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[derive(utoipa::ToSchema)]
pub enum TurnRolloverKind {
    NotAttempted,
    Succeeded,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct InteractionBrief {
    pub reference: InteractionReadRef,
    pub revision: u64,
    pub kind: InteractionKind,
    pub status: InteractionStatus,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct InteractionIndexHeader {
    pub reference: InteractionIndexRef,
    pub total: u64,
    pub pending: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct InteractionDelta {
    pub base_index_revision: u64,
    pub index: InteractionIndexHeader,
    pub upserted: Vec<InteractionBrief>,
    pub removed_entries: Vec<u64>,
    pub terminal_facts: Vec<InteractionBrief>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ActivityBrief {
    pub reference: ActivityReadRef,
    pub revision: u64,
    pub kind: ThreadActivityKind,
    pub tool_count: u32,
    pub background_count: u32,
    pub active_count: u64,
    pub has_latest_started: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct StorageBrief {
    pub reference: StorageReadRef,
    pub fault: Option<HistoryFault>,
    pub fault_generation: u64,
    pub accepted_sequence: Option<u64>,
    pub durable_sequence: Option<u64>,
    pub execution: ThreadStorageExecution,
    pub pressure_paused: bool,
    pub resume_required: bool,
    pub can_resume: bool,
    pub has_last_error: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ExecutionBaseline {
    pub status: ThreadStatus,
    pub execution: Option<crate::AgentExecution>,
    pub continuation: Option<crate::ContinuationView>,
    pub active_turn: Option<TurnBrief>,
    pub recent_terminal_turn: Option<TurnBrief>,
    pub interactions: InteractionIndexHeader,
    pub activity: Option<ActivityBrief>,
    pub storage: Option<StorageBrief>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ExecutionChange {
    pub status: Option<ThreadStatus>,
    pub execution: ExecutionReplacement,
    pub continuation: ContinuationReplacement,
    pub turns: Option<TurnsReplacement>,
    pub interactions: Option<InteractionDelta>,
    pub activity: ActivityReplacement,
    pub storage: StorageReplacement,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct TurnsReplacement {
    pub active_turn: Option<TurnBrief>,
    pub recent_terminal_turn: Option<TurnBrief>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub enum ExecutionReplacement {
    Unchanged,
    Replace {
        value: Option<crate::AgentExecution>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub enum ContinuationReplacement {
    Unchanged,
    Replace {
        value: Option<crate::ContinuationView>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum ActivityReplacement {
    Unchanged,
    Replace { value: Option<ActivityBrief> },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum StorageReplacement {
    Unchanged,
    Replace { value: Option<StorageBrief> },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum ExecutionEvent {
    Baseline {
        identity: ThreadFeedIdentity,
        stamp: ThreadFacetStamp,
        value: ExecutionBaseline,
    },
    Change {
        stamp: ThreadFacetStamp,
        base_revision: u64,
        value: ExecutionChange,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum ExecutionFrame {
    Data {
        delivery_sequence: u64,
        event: Box<ExecutionEvent>,
    },
    ResyncRequired {
        identity: ThreadFeedIdentity,
        reason: ResyncReason,
    },
    Failure {
        identity: ThreadFeedIdentity,
        error: StudioError,
    },
    Closed {
        identity: ThreadFeedIdentity,
        reason: FeedClosedReason,
    },
}
