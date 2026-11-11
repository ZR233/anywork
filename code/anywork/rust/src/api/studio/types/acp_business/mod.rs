//! Explicit FRB mirrors of the locked official ACP v1 data, never Native timeline values.
pub mod content;
pub mod notification;
pub use content::*;
pub use notification::*;

use super::{BridgeAcpAuthMethod, BridgeError};
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpJsonValue {
    Null,
    Bool {
        value: bool,
    },
    Number {
        value: BridgeAcpJsonNumber,
    },
    String {
        value: String,
    },
    Array {
        values: Vec<BridgeAcpJsonValue>,
    },
    Object {
        fields: HashMap<String, BridgeAcpJsonValue>,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpJsonNumber {
    Signed { value: i64 },
    Unsigned { value: u64 },
    Float { value: f64 },
}
pub type BridgeAcpMeta = HashMap<String, BridgeAcpJsonValue>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAcpConfigId {
    pub value: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAcpConfigValueId {
    pub value: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAcpModeId {
    pub value: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAcpPermissionOptionId {
    pub value: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAcpRemoteSessionId {
    pub value: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAcpSessionTarget {
    pub session_id: String,
    pub agent_id: String,
    pub thread_id: String,
    pub instance: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeAcpRunId {
    pub instance: u64,
    pub sequence: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeAcpPermissionId {
    pub instance: u64,
    pub sequence: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeAcpBusinessFailureKind {
    Busy,
    Stale,
    NotReady,
    Closed,
    Unsupported,
    UnsupportedVersion,
    ServerVersionMismatch,
    InvalidOption,
    Rpc,
    InstallRequired,
    InstallationInvalid,
    UnsupportedPlatform,
    MissingExecutable,
    InvalidWorkingDirectory,
    InvalidDefinition,
    Io,
    Cancelled,
    Preparation,
    Publication,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpBusinessFailure {
    pub kind: BridgeAcpBusinessFailureKind,
    pub rpc_code: Option<i32>,
    pub message: String,
    pub rpc_data: Option<BridgeAcpJsonValue>,
    pub auth_methods: Vec<BridgeAcpAuthMethod>,
}
#[derive(Debug, Clone, thiserror::Error)]
pub enum BridgeAcpBusinessError {
    #[error("{0}")]
    Runtime(BridgeError),
    #[error("ACP business failure")]
    Business(Box<BridgeAcpBusinessFailure>),
    #[error("Unsupported official ACP value: {type_name}")]
    Unsupported { type_name: String },
}
impl From<BridgeError> for BridgeAcpBusinessError {
    fn from(value: BridgeError) -> Self {
        Self::Runtime(value)
    }
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpOpenIntent {
    New,
    Load {
        session_id: BridgeAcpRemoteSessionId,
    },
    Resume {
        session_id: BridgeAcpRemoteSessionId,
    },
}
#[derive(Debug, Clone)]
pub struct BridgeOpenAcpSessionRequest {
    pub account_id: String,
    pub expected_connection_revision: u64,
    pub workspace_id: String,
    pub thread_id: Option<String>,
    pub intent: BridgeAcpOpenIntent,
}
#[derive(Debug, Clone)]
pub struct BridgeAcpPromptRequest {
    pub target: BridgeAcpSessionTarget,
    pub content: Vec<BridgeAcpContentBlock>,
}
#[derive(Debug, Clone)]
pub struct BridgeAcpReplaceRequest {
    pub target: BridgeAcpSessionTarget,
    pub run: BridgeAcpRunId,
    pub content: Vec<BridgeAcpContentBlock>,
}
#[derive(Debug, Clone)]
pub struct BridgeAcpInterruptRequest {
    pub target: BridgeAcpSessionTarget,
    pub run: BridgeAcpRunId,
}
#[derive(Debug, Clone)]
pub struct BridgeAcpConfigureRequest {
    pub target: BridgeAcpSessionTarget,
    pub config_id: BridgeAcpConfigId,
    pub value: BridgeAcpConfigValue,
}
#[derive(Debug, Clone)]
pub struct BridgeAcpSetModeRequest {
    pub target: BridgeAcpSessionTarget,
    pub mode_id: BridgeAcpModeId,
}
#[derive(Debug, Clone)]
pub struct BridgeAcpPermissionAnswerRequest {
    pub target: BridgeAcpSessionTarget,
    pub permission_id: BridgeAcpPermissionId,
    pub option_id: Option<BridgeAcpPermissionOptionId>,
}
#[derive(Debug, Clone)]
pub struct BridgeAcpListRequest {
    pub target: BridgeAcpSessionTarget,
    pub cwd: Option<String>,
    pub cursor: Option<String>,
    pub meta: Option<BridgeAcpMeta>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpConfigValue {
    Boolean { value: bool },
    ValueId { value: BridgeAcpConfigValueId },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpConfigCategory {
    Mode,
    Model,
    ModelConfig,
    ThoughtLevel,
    Other { value: String },
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpConfigOption {
    pub id: BridgeAcpConfigId,
    pub name: String,
    pub description: Option<String>,
    pub category: Option<BridgeAcpConfigCategory>,
    pub kind: BridgeAcpConfigKind,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpConfigKind {
    Select {
        current_value: BridgeAcpConfigValueId,
        options: BridgeAcpSelectOptions,
    },
    Boolean {
        current_value: bool,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpSelectOptions {
    Ungrouped { options: Vec<BridgeAcpSelectOption> },
    Grouped { groups: Vec<BridgeAcpSelectGroup> },
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpSelectOption {
    pub value: BridgeAcpConfigValueId,
    pub name: String,
    pub description: Option<String>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpSelectGroup {
    pub group: String,
    pub name: String,
    pub options: Vec<BridgeAcpSelectOption>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpModeState {
    pub current_mode_id: BridgeAcpModeId,
    pub available_modes: Vec<BridgeAcpMode>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpMode {
    pub id: BridgeAcpModeId,
    pub name: String,
    pub description: Option<String>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpNewSessionResponse {
    pub session_id: BridgeAcpRemoteSessionId,
    pub modes: Option<BridgeAcpModeState>,
    pub config_options: Option<Vec<BridgeAcpConfigOption>>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpListResponse {
    pub sessions: Vec<BridgeAcpSessionInfo>,
    pub next_cursor: Option<String>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpSessionInfo {
    pub session_id: BridgeAcpRemoteSessionId,
    pub cwd: String,
    pub additional_directories: Vec<String>,
    pub title: Option<String>,
    pub updated_at: Option<String>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeAcpStopReason {
    EndTurn,
    MaxTokens,
    MaxTurnRequests,
    Refusal,
    Cancelled,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpPromptResponse {
    pub stop_reason: BridgeAcpStopReason,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpPromptResult {
    Succeeded { response: BridgeAcpPromptResponse },
    Failed { failure: BridgeAcpBusinessFailure },
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpCompletedRun {
    pub run: BridgeAcpRunId,
    pub completion_sequence: u64,
    pub result: BridgeAcpPromptResult,
    pub summary: String,
    pub truncated: bool,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeAcpObservationGap {
    WindowExceeded,
    Disconnected,
    Encoding,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpSettlement {
    Succeeded,
    Failed { failure: BridgeAcpBusinessFailure },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpSessionFrame {
    Accepted {
        target: BridgeAcpSessionTarget,
        has_observation: bool,
    },
    Settled {
        result: BridgeAcpSettlement,
    },
    Event {
        event: Box<BridgeAcpSessionEvent>,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpAgentCapabilities {
    pub image: bool,
    pub audio: bool,
    pub embedded_context: bool,
    pub load_session: bool,
    pub list_sessions: bool,
    pub resume_session: bool,
    pub close_session: bool,
    pub mcp_http: bool,
    pub mcp_sse: bool,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpSessionEvent {
    Initialized {
        capabilities: BridgeAcpAgentCapabilities,
    },
    Update {
        update: BridgeAcpSessionNotification,
    },
    Ready {
        response: BridgeAcpNewSessionResponse,
    },
    Failed {
        failure: BridgeAcpBusinessFailure,
    },
    Permission {
        id: BridgeAcpPermissionId,
        request: BridgeAcpPermissionRequest,
    },
    Configured {
        config_options: Vec<BridgeAcpConfigOption>,
        meta: Option<BridgeAcpMeta>,
    },
    ModeSet {
        mode_id: BridgeAcpModeId,
    },
    Completed {
        completed: BridgeAcpCompletedRun,
    },
    Gap {
        gap: BridgeAcpObservationGap,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpBusinessSnapshot {
    pub target: BridgeAcpSessionTarget,
    pub acp_session_id: Option<BridgeAcpRemoteSessionId>,
    pub ready: bool,
    pub closing: bool,
    pub config_pending: bool,
    pub config_options: Option<Vec<BridgeAcpConfigOption>>,
    pub modes: Option<BridgeAcpModeState>,
    pub active_run: Option<BridgeAcpRunId>,
    pub last_completed: Option<BridgeAcpCompletedRun>,
    pub observation_gap: Option<BridgeAcpObservationGap>,
    pub auth_methods: Vec<BridgeAcpAuthMethod>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpBusinessClose {
    pub local_complete: bool,
    pub sdk_finished: bool,
    pub cleanup_timed_out: bool,
    pub remote_close_error: Option<BridgeAcpBusinessFailure>,
    pub sdk_error: Option<BridgeAcpBusinessFailure>,
    pub worker_error: Option<String>,
    pub driver_error: Option<String>,
    pub unfinished_prompt: Option<BridgeAcpRunId>,
    pub unfinished_controls: bool,
    pub last_completed: Option<BridgeAcpCompletedRun>,
    pub owner_failures: Vec<BridgeAcpMemberCloseFailure>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpMemberCloseFailure {
    pub thread_id: String,
    pub message: String,
}
