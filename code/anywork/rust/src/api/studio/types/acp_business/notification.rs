use super::*;

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpSessionNotification {
    pub session_id: BridgeAcpRemoteSessionId,
    pub update: BridgeAcpSessionUpdate,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpContentChunk {
    pub content: BridgeAcpContentBlock,
    pub message_id: Option<String>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpSessionUpdate {
    UserMessageChunk {
        chunk: BridgeAcpContentChunk,
    },
    AgentMessageChunk {
        chunk: BridgeAcpContentChunk,
    },
    AgentThoughtChunk {
        chunk: BridgeAcpContentChunk,
    },
    ToolCall {
        call: BridgeAcpToolCall,
    },
    ToolCallUpdate {
        update: BridgeAcpToolCallUpdate,
    },
    Plan {
        entries: Vec<BridgeAcpPlanEntry>,
        meta: Option<BridgeAcpMeta>,
    },
    AvailableCommands {
        commands: Vec<BridgeAcpAvailableCommand>,
        meta: Option<BridgeAcpMeta>,
    },
    CurrentMode {
        mode_id: BridgeAcpModeId,
        meta: Option<BridgeAcpMeta>,
    },
    ConfigOptions {
        config_options: Vec<BridgeAcpConfigOption>,
        meta: Option<BridgeAcpMeta>,
    },
    SessionInfo {
        title: BridgeAcpStringField,
        updated_at: BridgeAcpStringField,
        meta: Option<BridgeAcpMeta>,
    },
    Usage {
        used: u64,
        size: u64,
        cost: Option<BridgeAcpCost>,
        meta: Option<BridgeAcpMeta>,
    },
    Notice {
        severity: BridgeAcpNoticeSeverity,
        title: String,
        description: Option<String>,
        meta: Option<BridgeAcpMeta>,
    },
    Compaction {
        compaction_id: String,
        status: BridgeAcpCompactionStatus,
        summary: BridgeAcpContentField,
        error: BridgeAcpStringField,
        meta: BridgeAcpMetaField,
    },
    CompactionSummary {
        compaction_id: String,
        content: BridgeAcpContentBlock,
        meta: Option<BridgeAcpMeta>,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpStringField {
    Undefined,
    Null,
    Value { value: String },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpContentField {
    Undefined,
    Null,
    Value { value: Vec<BridgeAcpContentBlock> },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpMetaField {
    Undefined,
    Null,
    Value { value: BridgeAcpMeta },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpNoticeSeverity {
    Info,
    Warning,
    Error,
    Other { value: String },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpCompactionStatus {
    InProgress,
    Completed,
    Failed,
    Cancelled,
    Other { value: String },
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpCost {
    pub amount: f64,
    pub currency: String,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpToolCall {
    pub tool_call_id: String,
    pub title: String,
    pub name: Option<String>,
    pub kind: BridgeAcpToolKind,
    pub status: BridgeAcpToolStatus,
    pub content: Vec<BridgeAcpToolContent>,
    pub locations: Vec<BridgeAcpToolLocation>,
    pub raw_input: Option<BridgeAcpJsonValue>,
    pub raw_output: Option<BridgeAcpJsonValue>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpToolCallUpdate {
    pub tool_call_id: String,
    pub kind: Option<BridgeAcpToolKind>,
    pub status: Option<BridgeAcpToolStatus>,
    pub title: Option<String>,
    pub name: Option<String>,
    pub content: Option<Vec<BridgeAcpToolContent>>,
    pub locations: Option<Vec<BridgeAcpToolLocation>>,
    pub raw_input: Option<BridgeAcpJsonValue>,
    pub raw_output: Option<BridgeAcpJsonValue>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeAcpToolKind {
    Read,
    Edit,
    Delete,
    Move,
    Search,
    Execute,
    Think,
    Fetch,
    SwitchMode,
    Other,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeAcpToolStatus {
    Pending,
    InProgress,
    Completed,
    Failed,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpToolContent {
    Content {
        content: Box<BridgeAcpContentBlock>,
        meta: Option<BridgeAcpMeta>,
    },
    Diff {
        path: String,
        old_text: Option<String>,
        new_text: String,
        meta: Option<BridgeAcpMeta>,
    },
    Terminal {
        terminal_id: String,
        meta: Option<BridgeAcpMeta>,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpToolLocation {
    pub path: String,
    pub line: Option<u32>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpPlanEntry {
    pub content: String,
    pub priority: BridgeAcpPlanPriority,
    pub status: BridgeAcpPlanStatus,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeAcpPlanPriority {
    High,
    Medium,
    Low,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeAcpPlanStatus {
    Pending,
    InProgress,
    Completed,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpAvailableCommand {
    pub name: String,
    pub description: String,
    pub input: Option<BridgeAcpCommandInput>,
    pub meta: Option<BridgeAcpMeta>,
}
/// The locked stable schema has only Unstructured command input. Its concrete
/// payload is a struct at the FRB boundary; unknown future official variants
/// are rejected by the converter rather than represented by invented variants.
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpCommandInput {
    pub hint: String,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpPermissionRequest {
    pub session_id: BridgeAcpRemoteSessionId,
    pub tool_call: BridgeAcpToolCallUpdate,
    pub options: Vec<BridgeAcpPermissionOption>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpPermissionOption {
    pub option_id: BridgeAcpPermissionOptionId,
    pub name: String,
    pub kind: BridgeAcpPermissionKind,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeAcpPermissionKind {
    AllowOnce,
    AllowAlways,
    RejectOnce,
    RejectAlways,
}
