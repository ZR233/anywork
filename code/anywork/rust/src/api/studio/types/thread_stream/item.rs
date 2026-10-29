//! Non-streaming typed leaves shared by conversation read descriptors and thread status.

use super::BridgeTokenUsageSnapshot;

/// Why one raw record exists; the payload list cannot tell the two apart.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeRawItemOrigin {
    Stored,
    RuntimeControl,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeSkillResourceBase {
    Directory { path: String },
    Url { url: String },
    Opaque { description: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeSkillActivationCause {
    Tool { tool_call_id: String },
    UserGesture { invocation_id: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadTextChannel {
    User,
    Commentary,
    Final,
    ParentAgent,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeThreadContentLifecycle {
    Streaming,
    Completed { completed_at: i64 },
    Failed { failed_at: i64, error: String },
    Cancelled { cancelled_at: i64, reason: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadAttachment {
    pub id: String,
    pub modality: crate::api::studio::types::BridgeAttachmentModality,
    pub media_type: String,
    pub filename: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub byte_size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadToolFailure {
    pub kind: BridgeThreadToolFailureKind,
    pub message: String,
}

/// Shared typed wait/sleep presentation mirrored from the protocol DTO.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadWaitPresentation {
    pub intent: BridgeThreadWaitIntent,
    pub state: BridgeThreadWaitState,
    pub messages_ready: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeThreadWaitIntent {
    Events {
        targets: Vec<BridgeThreadWaitTarget>,
        timeout_ms: u64,
    },
    Timer {
        duration_ms: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadWaitTarget {
    pub task_id: String,
    pub tool_name: Option<String>,
    pub summary: Option<String>,
    pub summary_truncated: bool,
    pub status: Option<BridgeThreadWaitTargetStatus>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadWaitTargetStatus {
    Running,
    Succeeded,
    Failed,
    Cancelled,
    Interrupted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadWaitState {
    Waiting,
    Ready,
    TimedOut,
    Elapsed,
    Cancelled,
    Failed,
    Interrupted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadToolFailureKind {
    Execution,
    TimedOut,
    BudgetLimited,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadAgentIdentity {
    pub id: String,
    pub path: String,
    pub parent_path: Option<String>,
    pub role: String,
    pub task: String,
    pub depth: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeThreadAgentState {
    Queued,
    Running,
    Succeeded { completed_at: i64, summary: String },
    Denied { denied_at: i64, reason: String },
    Cancelled { cancelled_at: i64, reason: String },
    Failed { failed_at: i64, error: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeThreadInferenceState {
    Running,
    Completed {
        completed_at: i64,
        usage: BridgeTokenUsageSnapshot,
    },
    Failed {
        failed_at: i64,
        error: String,
    },
    Cancelled {
        cancelled_at: i64,
        reason: String,
    },
}
