//! Product identity around the exact official ACP payload types.
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

pub use agent_client_protocol_schema::v1 as acp_schema;
pub use agent_client_protocol_schema::v1::{
    AgentCapabilities, ContentBlock, ListSessionsRequest, ListSessionsResponse, NewSessionResponse,
    PermissionOptionId, PromptResponse, RequestPermissionRequest, SessionConfigId,
    SessionConfigOption, SessionConfigOptionValue, SessionId as AcpSessionId, SessionModeId,
    SessionModeState, SessionNotification, SetSessionConfigOptionResponse,
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(tag = "kind", content = "sessionId", rename_all = "camelCase")]
pub enum AcpOpenIntent {
    New,
    Load(String),
    Resume(String),
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
pub struct AcpCompletedRun {
    pub run: AcpRunId,
    pub completion_sequence: u64,
    #[schema(value_type = Object)]
    pub result: Result<PromptResponse, AcpBusinessFailure>,
    pub summary: String,
    pub truncated: bool,
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
        capabilities: AgentCapabilities,
    },
    Update {
        #[schema(value_type = Object)]
        update: SessionNotification,
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

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpPromptRequest {
    pub target: AcpSessionTarget,
    #[schema(value_type = Vec<serde_json::Value>)]
    pub content: Vec<ContentBlock>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpReplaceRequest {
    pub target: AcpSessionTarget,
    pub run: AcpRunId,
    #[schema(value_type = Vec<serde_json::Value>)]
    pub content: Vec<ContentBlock>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpInterruptRequest {
    pub target: AcpSessionTarget,
    pub run: AcpRunId,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpConfigureRequest {
    pub target: AcpSessionTarget,
    #[schema(value_type = String)]
    pub config_id: SessionConfigId,
    #[schema(value_type = serde_json::Value)]
    pub value: SessionConfigOptionValue,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpSetModeRequest {
    pub target: AcpSessionTarget,
    #[schema(value_type = String)]
    pub mode_id: SessionModeId,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpPermissionAnswerRequest {
    pub target: AcpSessionTarget,
    pub permission_id: AcpPermissionId,
    #[schema(value_type = Option<String>)]
    pub option_id: Option<PermissionOptionId>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpListRequest {
    pub target: AcpSessionTarget,
    #[schema(value_type = Object)]
    pub request: ListSessionsRequest,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initialized_event_preserves_official_agent_capabilities_shape() {
        use acp_schema::{PromptCapabilities, SessionCapabilities, SessionListCapabilities};
        let capabilities = AgentCapabilities::new()
            .load_session(true)
            .prompt_capabilities(
                PromptCapabilities::new()
                    .image(true)
                    .audio(false)
                    .embedded_context(true),
            )
            .session_capabilities(SessionCapabilities::new().list(SessionListCapabilities::new()));
        let official = serde_json::to_value(&capabilities).unwrap();
        let frame = serde_json::to_value(AcpSessionFrame::Event {
            event: Box::new(AcpSessionEvent::Initialized { capabilities }),
        })
        .unwrap();
        assert_eq!(frame["event"]["kind"], "initialized");
        assert_eq!(frame["event"]["capabilities"], official);
        assert_eq!(official["loadSession"], true);
        assert_eq!(official["promptCapabilities"]["embeddedContext"], true);
        assert_eq!(
            official["sessionCapabilities"]["list"],
            serde_json::json!({})
        );
        assert!(official["sessionCapabilities"].get("resume").is_none());
        let decoded: AcpSessionFrame = serde_json::from_value(frame).unwrap();
        assert!(matches!(
            decoded,
            AcpSessionFrame::Event { event }
                if matches!(event.as_ref(), AcpSessionEvent::Initialized { capabilities }
                    if capabilities.session_capabilities.list.is_some()
                        && capabilities.session_capabilities.resume.is_none())
        ));
    }

    #[test]
    fn config_uses_official_typed_values_and_separate_permission_identity() {
        let target = AcpSessionTarget {
            session_id: "product".into(),
            agent_id: "agent".into(),
            thread_id: "context".into(),
            instance: 3,
        };
        let value = serde_json::to_value(AcpConfigureRequest {
            target,
            config_id: "safe".into(),
            value: SessionConfigOptionValue::Boolean { value: false },
        })
        .unwrap();
        assert_eq!(value["configId"], "safe");
        assert_eq!(
            value["value"],
            serde_json::json!({"type":"boolean", "value":false})
        );
        assert!(value.get("optionId").is_none());
        let mut wrong = value;
        wrong["optionId"] = "permission-option".into();
        assert!(serde_json::from_value::<AcpConfigureRequest>(wrong).is_err());
        let event = serde_json::to_value(AcpSessionEvent::ModeSet {
            mode_id: "legacy".into(),
        })
        .unwrap();
        assert_eq!(
            event,
            serde_json::json!({"kind":"modeSet", "modeId":"legacy"})
        );
        let frame = serde_json::to_value(AcpSessionFrame::Event {
            event: Box::new(AcpSessionEvent::ModeSet {
                mode_id: "legacy".into(),
            }),
        })
        .unwrap();
        assert_eq!(
            frame,
            serde_json::json!({
                "kind": "event",
                "event": {"kind": "modeSet", "modeId": "legacy"},
            })
        );
    }
}
