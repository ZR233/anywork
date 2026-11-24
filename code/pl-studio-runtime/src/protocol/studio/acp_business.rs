//! Product identity around the exact official ACP payload types.
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

pub use pl_acp::session::schema as acp_schema;
pub use pl_acp::session::schema::{
    AgentCapabilities, ListSessionsRequest, ListSessionsResponse, NewSessionResponse,
    PermissionOptionId, PromptResponse, RequestPermissionRequest, SessionConfigId,
    SessionConfigOption, SessionConfigOptionValue, SessionId as AcpSessionId, SessionModeId,
    SessionModeState, SessionNotification, SetSessionConfigOptionResponse,
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum AcpOpenIntent {
    New,
    /// A real protocol session whose product association is published on first submission.
    Draft {
        workspace_mode: crate::ThreadWorkspaceMode,
        delegation_mode: Option<crate::DelegationMode>,
        delegation_preference: Option<crate::DelegationPreference>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        #[schema(value_type = Option<String>)]
        mode: Option<crate::mode::ThreadModeId>,
    },
    Load {
        session_id: String,
    },
    Resume {
        session_id: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OpenAcpSessionRequest {
    pub account_id: String,
    pub expected_connection_revision: u64,
    pub workspace_id: String,
    /// Existing product member to reopen. New product membership omits this field.
    pub thread_id: Option<String>,
    pub intent: AcpOpenIntent,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpSessionTarget {
    pub session_id: String,
    pub agent_id: String,
    pub thread_id: String,
    /// Studio materialization generation; not an SDK run/permission instance.
    pub instance: u64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
/// Exact SDK qualification returned by prompt/replace, never derived from the target.
pub struct AcpRunId {
    pub instance: u64,
    pub sequence: u64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpPermissionId {
    pub instance: u64,
    pub sequence: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AcpBusinessFailureKind {
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

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpBusinessFailure {
    pub kind: AcpBusinessFailureKind,
    pub rpc_code: Option<i32>,
    pub message: String,
    pub rpc_data: Option<Box<serde_json::Value>>,
    pub auth_methods: Vec<super::AcpAuthMethod>,
}

impl std::fmt::Display for AcpBusinessFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "ACP {:?}", self.kind)
    }
}
impl std::error::Error for AcpBusinessFailure {}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AcpObservationGap {
    WindowExceeded,
    Disconnected,
    Encoding,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpTextPerformance {
    pub estimated_output_tokens: u64,
    pub response_millis: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpUsageSnapshot {
    pub used: u64,
    pub size: u64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpCostSnapshot {
    pub amount: f64,
    pub currency: String,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpTextPerformanceSnapshot {
    pub estimated_output_tokens: u64,
    pub response_millis: u64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpServerInfoSnapshot {
    pub name: String,
    pub version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpConfigItemSnapshot {
    pub id: String,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    pub value_id: String,
    pub value_label: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpSessionInfoSnapshot {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub usage: Option<AcpUsageSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cost: Option<AcpCostSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text_performance: Option<AcpTextPerformanceSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_stop_reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub server_info: Option<AcpServerInfoSnapshot>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub active_config: Vec<AcpConfigItemSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed_turns: Option<u64>,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpWorkflowStateSnapshot {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[schema(value_type = Option<String>)]
    pub mode_id: Option<crate::mode::ThreadModeId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode_display_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[schema(value_type = Option<Object>)]
    pub run: Option<crate::workflow_tool::WorkflowRuntimeRunSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[schema(value_type = Option<Object>)]
    pub graph: Option<crate::workflow_tool::WorkflowRuntimeGraphSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[schema(value_type = Option<Object>)]
    pub plan: Option<crate::plan_tool::AgentSessionPlanRuntimeSnapshot>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpCompletedRun {
    pub run: AcpRunId,
    pub completion_sequence: u64,
    #[schema(value_type = Object)]
    pub result: Result<PromptResponse, AcpBusinessFailure>,
    pub summary: String,
    pub truncated: bool,
    pub text_performance: Option<AcpTextPerformance>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum AcpSessionEvent {
    Initialized {
        #[schema(value_type = Object)]
        capabilities: Box<AgentCapabilities>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        server_info: Option<AcpServerInfoSnapshot>,
    },
    Update {
        #[schema(value_type = Object)]
        update: SessionNotification,
        text_performance: Option<AcpTextPerformance>,
    },
    Ready {
        #[schema(value_type = Object)]
        response: NewSessionResponse,
    },
    Failed {
        error: AcpBusinessFailure,
    },
    Permission {
        id: AcpPermissionId,
        #[schema(value_type = Object)]
        request: RequestPermissionRequest,
    },
    Configured {
        #[schema(value_type = Object)]
        response: SetSessionConfigOptionResponse,
    },
    ModeSet {
        #[schema(value_type = String)]
        mode_id: SessionModeId,
    },
    Completed {
        completed: AcpCompletedRun,
    },
    WorkflowStateUpdated {
        state: Box<AcpWorkflowStateSnapshot>,
    },
    Gap {
        gap: AcpObservationGap,
    },
}

/// Thin transport framing around one admitted open, its owner result and original observation.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum AcpSessionFrame {
    Accepted {
        target: AcpSessionTarget,
        has_observation: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        info_snapshot: Option<Box<AcpSessionInfoSnapshot>>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        workflow_state: Option<Box<AcpWorkflowStateSnapshot>>,
    },
    Settled {
        #[schema(value_type = Object)]
        result: Result<(), AcpBusinessFailure>,
    },
    Event {
        event: Box<AcpSessionEvent>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpBusinessSnapshot {
    pub target: AcpSessionTarget,
    pub acp_session_id: Option<String>,
    pub ready: bool,
    pub closing: bool,
    pub config_pending: bool,
    #[schema(value_type = Option<Vec<serde_json::Value>>)]
    pub config_options: Option<Vec<SessionConfigOption>>,
    #[schema(value_type = Option<serde_json::Value>)]
    pub modes: Option<SessionModeState>,
    pub active_run: Option<AcpRunId>,
    pub last_completed: Option<AcpCompletedRun>,
    pub observation_gap: Option<AcpObservationGap>,
    pub auth_methods: Vec<super::AcpAuthMethod>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub info_snapshot: Option<AcpSessionInfoSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workflow_state: Option<AcpWorkflowStateSnapshot>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpBusinessClose {
    pub local_complete: bool,
    pub sdk_finished: bool,
    pub cleanup_timed_out: bool,
    pub remote_close_error: Option<AcpBusinessFailure>,
    pub sdk_error: Option<AcpBusinessFailure>,
    pub worker_error: Option<String>,
    pub driver_error: Option<String>,
    pub unfinished_prompt: Option<AcpRunId>,
    pub unfinished_controls: bool,
    pub last_completed: Option<AcpCompletedRun>,
    pub owner_failures: Vec<AcpMemberCloseFailure>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpMemberCloseFailure {
    pub thread_id: String,
    pub message: String,
}
