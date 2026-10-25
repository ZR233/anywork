use super::super::execution::BridgeInteractionBrief;
use super::super::identity::BridgeReadScopeIdentity;
use crate::api::studio::observation::BridgeReadText;
use crate::api::studio::types::{
    BridgeHistoryFault, BridgeProviderFailureKind, BridgeRetryDisposition,
    BridgeThreadActivityArguments, BridgeThreadActivityKind, BridgeThreadActivityToolState,
    BridgeThreadStorageExecution, BridgeThreadWaitState, BridgeThreadWaitTargetStatus,
    BridgeTurnBudgetLimit, BridgeTurnCompletion, BridgeTurnFailureCategory, BridgeTurnPhase,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTurnReadHeader {
    pub scope: BridgeReadScopeIdentity,
    pub input_id: Option<BridgeReadText>,
    pub id: BridgeReadText,
    pub thread_id: BridgeReadText,
    pub revision: u64,
    pub updated_at: i64,
    pub state: BridgeTurnReadState,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTurnReadState {
    Queued {
        queued_at: i64,
    },
    Running {
        started_at: i64,
        phase: BridgeTurnPhase,
    },
    Completed {
        started_at: Option<i64>,
        completed_at: i64,
        completion: BridgeTurnCompletion,
    },
    Cancelled {
        started_at: Option<i64>,
        requested_at: i64,
        completed_at: i64,
        cause: BridgeTurnReadCancellationCause,
    },
    Failed {
        started_at: Option<i64>,
        completed_at: i64,
        failure: BridgeTurnReadFailure,
    },
    BudgetLimited {
        started_at: Option<i64>,
        completed_at: i64,
        limit: BridgeTurnBudgetLimit,
        rollover: BridgeTurnReadRolloverOutcome,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTurnReadCancellationCause {
    Unspecified,
    UserRequested,
    RuntimeShutdown,
    AgentClosed,
    Interrupted,
    Recovery,
    Coalesced { target_turn_id: BridgeReadText },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTurnReadRolloverOutcome {
    NotAttempted,
    Succeeded,
    Failed { error: BridgeReadText },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTurnReadFailure {
    pub category: BridgeTurnFailureCategory,
    pub provider_kind: Option<BridgeProviderFailureKind>,
    pub code: Option<BridgeReadText>,
    pub http_status: Option<u16>,
    pub message: BridgeReadText,
    pub retry: BridgeRetryDisposition,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeInteractionIndexReadHeader {
    pub scope: BridgeReadScopeIdentity,
    pub total: u64,
    pub pending: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeInteractionBriefPage {
    pub scope: BridgeReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeInteractionBrief>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeActivityReadHeader {
    pub scope: BridgeReadScopeIdentity,
    pub thread_id: BridgeReadText,
    pub identity: BridgeReadText,
    pub turn_id: BridgeReadText,
    pub revision: u64,
    pub input_id: Option<BridgeReadText>,
    pub attempt_id: Option<BridgeReadText>,
    pub kind: BridgeThreadActivityKind,
    pub summary: BridgeReadText,
    pub summary_truncated: bool,
    pub count: u32,
    pub background: u32,
    pub active_count: u64,
    pub latest_started: Option<BridgeActivityToolReadItem>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeActivityToolReadItem {
    pub call_id: BridgeReadText,
    pub task_id: Option<BridgeReadText>,
    pub name: BridgeReadText,
    pub summary: BridgeReadText,
    pub arguments: BridgeThreadActivityArguments,
    pub state: BridgeThreadActivityToolState,
    pub ordinal: Option<u64>,
    pub started_at: Option<i64>,
    pub wait: Option<BridgeWaitReadValue>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeIndexedActivityToolReadItem {
    pub index: u64,
    pub call_id: BridgeReadText,
    pub task_id: Option<BridgeReadText>,
    pub name: BridgeReadText,
    pub summary: BridgeReadText,
    pub arguments: BridgeThreadActivityArguments,
    pub state: BridgeThreadActivityToolState,
    pub ordinal: Option<u64>,
    pub started_at: Option<i64>,
    pub wait: Option<BridgeWaitReadValue>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWaitReadValue {
    pub intent: BridgeWaitReadIntent,
    pub state: BridgeThreadWaitState,
    pub messages_ready: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeWaitReadIntent {
    Events { target_count: u64, timeout_ms: u64 },
    Timer { duration_ms: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWaitTargetReadItem {
    pub index: u64,
    pub task_id: BridgeReadText,
    pub tool_name: Option<BridgeReadText>,
    pub summary: Option<BridgeReadText>,
    pub summary_truncated: bool,
    pub status: Option<BridgeThreadWaitTargetStatus>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeActivityToolPage {
    pub scope: BridgeReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeIndexedActivityToolReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWaitTargetPage {
    pub scope: BridgeReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeWaitTargetReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeStorageReadHeader {
    pub scope: BridgeReadScopeIdentity,
    pub fault: Option<BridgeHistoryFault>,
    pub fault_generation: u64,
    pub accepted_sequence: Option<u64>,
    pub durable_sequence: Option<u64>,
    pub execution: BridgeThreadStorageExecution,
    pub pressure_paused: bool,
    pub resume_required: bool,
    pub can_resume: bool,
    pub last_error: Option<BridgeReadText>,
}
