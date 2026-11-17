//! Canonical conversation DTOs mirrored mechanically at the FRB boundary.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeReadDemand {
    pub max_items: u32,
    pub max_bytes: u32,
}

#[derive(Debug, Clone)]
pub enum BridgeChatSourceId {
    ForegroundTurn {
        turn_id: String,
    },
    Input {
        input_id: String,
    },
    InboxMessage {
        source_id: String,
        message_id: String,
    },
    BackgroundResult {
        message_id: String,
    },
    Operation {
        operation_id: String,
    },
    Receipt {
        receipt_id: String,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeChatFactPosition {
    pub effect_seq: u64,
    pub suborder: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeChatAtomKind {
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
    Raw,
    Agent,
    Inference,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeChatDeliveryKind {
    Foreground,
    BackgroundHandoff,
    Independent,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeChatActiveStatus {
    Running,
    Waiting,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeChatTerminalOutcome {
    Completed,
    Failed,
    Cancelled,
    Transferred,
}

#[derive(Debug, Clone)]
pub enum BridgeChatAtomLifecycle {
    Active {
        started: Option<BridgeChatFactPosition>,
        status: BridgeChatActiveStatus,
    },
    Terminal {
        started: Option<BridgeChatFactPosition>,
        ended: Option<BridgeChatFactPosition>,
        outcome: BridgeChatTerminalOutcome,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeChatToolIdentity {
    pub call_id: String,
    pub name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeChatContentRole {
    Body,
    ReasoningSummary,
    ToolArguments,
    ToolOutput,
}

#[derive(Debug, Clone)]
pub enum BridgeChatSourceLifecycle {
    Unknown,
    Active,
    Ended { outcome: BridgeChatTerminalOutcome },
}

#[derive(Debug, Clone)]
pub struct BridgeChatSourceState {
    pub source: BridgeChatSourceId,
    pub lifecycle: BridgeChatSourceLifecycle,
    pub started: Option<BridgeChatFactPosition>,
    pub ended: Option<BridgeChatFactPosition>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentPlanHead {
    pub revision: u64,
    pub phase: super::BridgePlanPhase,
    pub document: Option<super::BridgeCurrentContentRef>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadTextChannel {
    User,
    ParentAgent,
    Commentary,
    FinalAnswer,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeContentRange {
    pub offset: u64,
    pub max_bytes: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeContentWindow {
    pub offset: u64,
    pub bytes: Vec<u8>,
    pub generation: String,
    pub available_through: u64,
    pub sealed: bool,
}
