use super::identity::*;
use crate::api::studio::types::{
    BridgeError, BridgeHistoryFault, BridgeProviderFailureKind, BridgeRetryDisposition,
    BridgeThreadActivityKind, BridgeThreadStatus, BridgeThreadStorageExecution,
    BridgeTurnBudgetLimit, BridgeTurnCompletion, BridgeTurnFailureCategory, BridgeTurnPhase,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTurnBrief {
    pub reference: BridgeTurnReadRef,
    pub revision: u64,
    pub updated_at: i64,
    pub state: BridgeTurnBriefState,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTurnBriefState {
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
        cause: BridgeTurnCancellationKind,
    },
    Failed {
        started_at: Option<i64>,
        completed_at: i64,
        category: BridgeTurnFailureCategory,
        provider_kind: Option<BridgeProviderFailureKind>,
        http_status: Option<u16>,
        retry: BridgeRetryDisposition,
    },
    BudgetLimited {
        started_at: Option<i64>,
        completed_at: i64,
        limit: BridgeTurnBudgetLimit,
        rollover: BridgeTurnRolloverKind,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeTurnCancellationKind {
    Unspecified,
    UserRequested,
    RuntimeShutdown,
    AgentClosed,
    Interrupted,
    Recovery,
    Coalesced,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeTurnRolloverKind {
    NotAttempted,
    Succeeded,
    Failed,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeInteractionKind {
    UserInput,
    ToolApproval,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeInteractionStatus {
    Pending,
    Resolved,
    Cancelled,
    Expired,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeInteractionBrief {
    pub reference: BridgeInteractionReadRef,
    pub revision: u64,
    pub kind: BridgeInteractionKind,
    pub status: BridgeInteractionStatus,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeInteractionIndexHeader {
    pub reference: BridgeInteractionIndexRef,
    pub total: u64,
    pub pending: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeInteractionDelta {
    pub base_index_revision: u64,
    pub index: BridgeInteractionIndexHeader,
    pub upserted: Vec<BridgeInteractionBrief>,
    pub removed_entries: Vec<u64>,
    pub terminal_facts: Vec<BridgeInteractionBrief>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeActivityBrief {
    pub reference: BridgeActivityReadRef,
    pub revision: u64,
    pub kind: BridgeThreadActivityKind,
    pub tool_count: u32,
    pub background_count: u32,
    pub active_count: u64,
    pub has_latest_started: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeStorageBrief {
    pub reference: BridgeStorageReadRef,
    pub fault: Option<BridgeHistoryFault>,
    pub fault_generation: u64,
    pub accepted_sequence: Option<u64>,
    pub durable_sequence: Option<u64>,
    pub execution: BridgeThreadStorageExecution,
    pub pressure_paused: bool,
    pub resume_required: bool,
    pub can_resume: bool,
    pub has_last_error: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeExecutionBaseline {
    pub status: BridgeThreadStatus,
    pub execution: Option<crate::api::studio::types::BridgeAgentExecution>,
    pub continuation: Option<crate::api::studio::types::BridgeContinuationView>,
    pub active_turn: Option<BridgeTurnBrief>,
    pub recent_terminal_turn: Option<BridgeTurnBrief>,
    pub interactions: BridgeInteractionIndexHeader,
    pub activity: Option<BridgeActivityBrief>,
    pub storage: Option<BridgeStorageBrief>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeExecutionChange {
    pub status: Option<BridgeThreadStatus>,
    pub execution: BridgeExecutionReplacement,
    pub continuation: BridgeContinuationReplacement,
    pub turns: Option<BridgeTurnsReplacement>,
    pub interactions: Option<BridgeInteractionDelta>,
    pub activity: BridgeActivityReplacement,
    pub storage: BridgeStorageReplacement,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTurnsReplacement {
    pub active_turn: Option<BridgeTurnBrief>,
    pub recent_terminal_turn: Option<BridgeTurnBrief>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeExecutionReplacement {
    Unchanged,
    Replace {
        value: Option<crate::api::studio::types::BridgeAgentExecution>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeContinuationReplacement {
    Unchanged,
    Replace {
        value: Option<crate::api::studio::types::BridgeContinuationView>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeActivityReplacement {
    Unchanged,
    Replace { value: Option<BridgeActivityBrief> },
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeStorageReplacement {
    Unchanged,
    Replace { value: Option<BridgeStorageBrief> },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeExecutionEvent {
    Baseline {
        identity: BridgeThreadFeedIdentity,
        stamp: BridgeThreadFacetStamp,
        value: BridgeExecutionBaseline,
    },
    Change {
        stamp: BridgeThreadFacetStamp,
        base_revision: u64,
        value: BridgeExecutionChange,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeExecutionFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeExecutionEvent,
    },
    ResyncRequired {
        identity: BridgeThreadFeedIdentity,
        reason: BridgeResyncReason,
    },
    Failure {
        identity: BridgeThreadFeedIdentity,
        error: BridgeError,
    },
    Closed {
        identity: BridgeThreadFeedIdentity,
        reason: BridgeFeedClosedReason,
    },
}
