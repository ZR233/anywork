//! Typed attachment and wait leaves retained by the state domain.

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
