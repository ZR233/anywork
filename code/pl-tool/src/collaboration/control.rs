//! Trusted collaboration values, independent of Native tool encoding.
use pl_protocol::{AgentId, AgentWorkspaceAssignmentSnapshot, DelegationSettings};

/// Host-assigned call identity; never decoded from model arguments.
#[derive(Debug, Clone)]
pub struct AgentCallContext {
    pub caller: AgentId,
    pub call_id: String,
    pub cancellation: tokio_util::sync::CancellationToken,
}

#[derive(Debug, thiserror::Error)]
pub enum ControlError {
    #[error("agent coordinator is closed")]
    Closed,
    #[error("agent is missing or not published: {0}")]
    Missing(String),
    #[error("target {target} is not a descendant of caller {caller}")]
    Relationship { caller: String, target: String },
    #[error("invalid agent ancestry")]
    Ancestry,
    #[error("agent {0} has no current execution to stop")]
    StaleExecution(String),
    #[error("{0}")]
    Service(#[source] Box<dyn std::error::Error + Send + Sync>),
}

impl ControlError {
    pub fn service(source: impl std::error::Error + Send + Sync + 'static) -> Self {
        Self::Service(Box::new(source))
    }
}

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpawnReceipt {
    pub agent_id: String,
    pub profile_id: String,
    pub model: pl_protocol::studio::NewThreadModelRoute,
    pub delegation: DelegationSettings,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workspace: Option<AgentWorkspaceAssignmentSnapshot>,
    pub message_accepted: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message_sequence: Option<u64>,
}

/// Publication survives a failure to admit the first input.
#[derive(Debug)]
pub struct AgentSpawnResult {
    pub receipt: SpawnReceipt,
    pub message_error: Option<ControlError>,
}

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentSendResult {
    pub target: String,
    pub message_id: String,
    pub sequence: u64,
}

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentInterruptResult {
    pub target: String,
    pub execution_id: String,
    pub interrupted: bool,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentCloseOutcome {
    pub target: String,
    pub agents: Vec<AgentCloseResult>,
    pub error: Option<pl_protocol::StateError>,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentCloseResult {
    pub agent_id: String,
    pub execution_closed: bool,
    pub worktree_cleanup: AgentWorktreeCleanup,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum AgentWorktreeCleanup {
    Pending,
    NotApplicable,
    NotPresent {
        path: String,
        registration_present: bool,
    },
    Removed {
        path: String,
    },
    Failed {
        path: Option<String>,
        error: pl_protocol::StateError,
    },
}

impl AgentWorktreeCleanup {
    pub fn is_terminal(&self) -> bool {
        matches!(
            self,
            Self::NotApplicable | Self::NotPresent { .. } | Self::Removed { .. }
        )
    }
}
