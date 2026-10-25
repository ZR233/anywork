use serde::{Deserialize, Serialize};

use crate::studio::{HistoryFault, ReadText, ThreadStorageExecution};
use crate::thread_facets::execution::InteractionBrief;
use crate::thread_facets::identity::ReadScopeIdentity;
use crate::{
    BudgetLimitSnapshot, ProviderFailureKind, RetryDisposition, ThreadActivityArguments,
    ThreadActivityKind, ThreadActivityToolState, ThreadWaitState, ThreadWaitTargetStatus,
    TurnCompletion, TurnFailureCategory, TurnPhase,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct TurnReadHeader {
    pub scope: ReadScopeIdentity,
    pub input_id: Option<ReadText>,
    pub id: ReadText,
    pub thread_id: ReadText,
    pub revision: u64,
    pub updated_at: i64,
    pub state: TurnReadState,
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
pub enum TurnReadState {
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
        cause: TurnReadCancellationCause,
    },
    Failed {
        started_at: Option<i64>,
        completed_at: i64,
        failure: TurnReadFailure,
    },
    BudgetLimited {
        started_at: Option<i64>,
        completed_at: i64,
        limit: BudgetLimitSnapshot,
        rollover: TurnReadRolloverOutcome,
    },
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
pub enum TurnReadCancellationCause {
    Unspecified,
    UserRequested,
    RuntimeShutdown,
    AgentClosed,
    Interrupted,
    Recovery,
    Coalesced { target_turn_id: ReadText },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum TurnReadRolloverOutcome {
    NotAttempted,
    Succeeded,
    Failed { error: ReadText },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct TurnReadFailure {
    pub category: TurnFailureCategory,
    pub provider_kind: Option<ProviderFailureKind>,
    pub code: Option<ReadText>,
    pub http_status: Option<u16>,
    pub message: ReadText,
    pub retry: RetryDisposition,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct InteractionIndexReadHeader {
    pub scope: ReadScopeIdentity,
    pub total: u64,
    pub pending: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct InteractionBriefPage {
    pub scope: ReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<InteractionBrief>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ActivityReadHeader {
    pub scope: ReadScopeIdentity,
    pub thread_id: ReadText,
    pub identity: ReadText,
    pub turn_id: ReadText,
    pub revision: u64,
    pub input_id: Option<ReadText>,
    pub attempt_id: Option<ReadText>,
    pub kind: ThreadActivityKind,
    pub summary: ReadText,
    pub summary_truncated: bool,
    pub count: u32,
    pub background: u32,
    pub active_count: u64,
    pub latest_started: Option<ActivityToolReadItem>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ActivityToolReadItem {
    pub call_id: ReadText,
    pub task_id: Option<ReadText>,
    pub name: ReadText,
    pub summary: ReadText,
    pub arguments: ThreadActivityArguments,
    pub state: ThreadActivityToolState,
    pub ordinal: Option<u64>,
    pub started_at: Option<i64>,
    pub wait: Option<WaitReadValue>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct IndexedActivityToolReadItem {
    pub index: u64,
    pub call_id: ReadText,
    pub task_id: Option<ReadText>,
    pub name: ReadText,
    pub summary: ReadText,
    pub arguments: ThreadActivityArguments,
    pub state: ThreadActivityToolState,
    pub ordinal: Option<u64>,
    pub started_at: Option<i64>,
    pub wait: Option<WaitReadValue>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct WaitReadValue {
    pub intent: WaitReadIntent,
    pub state: ThreadWaitState,
    pub messages_ready: Option<bool>,
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
pub enum WaitReadIntent {
    Events { target_count: u64, timeout_ms: u64 },
    Timer { duration_ms: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct WaitTargetReadItem {
    pub index: u64,
    pub task_id: ReadText,
    pub tool_name: Option<ReadText>,
    pub summary: Option<ReadText>,
    pub summary_truncated: bool,
    pub status: Option<ThreadWaitTargetStatus>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ActivityToolPage {
    pub scope: ReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<IndexedActivityToolReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct WaitTargetPage {
    pub scope: ReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<WaitTargetReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct StorageReadHeader {
    pub scope: ReadScopeIdentity,
    pub fault: Option<HistoryFault>,
    pub fault_generation: u64,
    pub accepted_sequence: Option<u64>,
    pub durable_sequence: Option<u64>,
    pub execution: ThreadStorageExecution,
    pub pressure_paused: bool,
    pub resume_required: bool,
    pub can_resume: bool,
    pub last_error: Option<ReadText>,
}
