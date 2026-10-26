//! 机器人产品 FRB DTO。字段与 `pl_protocol::studio::bots` 对齐；Secret 与验证链接
//! 的调试表示脱敏。FRB 2.x wire 按位置传递，不依赖 serde 字段重命名。

use serde::{Deserialize, Serialize};

use super::command::{BridgeResourceStamp, BridgeStudioCommandReceipt};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BridgeBotPlatform {
    FeishuChina,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum BridgeBotConnectionState {
    Disabled,
    Connecting,
    Connected,
    Reconnecting {
        next_attempt_at: Option<i64>,
        attempt: u32,
    },
    Failed {
        code: String,
        message: String,
        retryable: bool,
        platform_code: Option<String>,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BridgeBotCredentialAvailability {
    Missing,
    SessionOnly,
    Stored,
    Unavailable,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum BridgeBotCredentialOperation {
    Idle,
    Preparing {
        operation_id: String,
    },
    CommitUncertain {
        operation_id: String,
    },
    CleanupPending {
        operation_id: String,
        config_committed: bool,
    },
}

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum BridgeBotRegistrationStatus {
    Idle,
    Preparing {
        attempt_id: String,
    },
    Waiting {
        attempt_id: String,
        verification_url: String,
        expires_at: i64,
        interval_seconds: u32,
    },
    SlowDown {
        attempt_id: String,
        verification_url: String,
        expires_at: i64,
        interval_seconds: u32,
    },
    Completed {
        attempt_id: String,
    },
    Committing {
        attempt_id: String,
        bot_id: String,
    },
    Denied {
        attempt_id: String,
        message: String,
    },
    Expired {
        attempt_id: String,
    },
    Cancelled {
        attempt_id: String,
    },
    Failed {
        attempt_id: String,
        code: String,
        message: String,
        retryable: bool,
    },
}

impl std::fmt::Debug for BridgeBotRegistrationStatus {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Idle => formatter.write_str("Idle"),
            Self::Preparing { attempt_id } => formatter
                .debug_struct("Preparing")
                .field("attempt_id", attempt_id)
                .finish(),
            Self::Waiting {
                attempt_id,
                expires_at,
                interval_seconds,
                ..
            } => formatter
                .debug_struct("Waiting")
                .field("attempt_id", attempt_id)
                .field("verification_url", &"<redacted>")
                .field("expires_at", expires_at)
                .field("interval_seconds", interval_seconds)
                .finish(),
            Self::SlowDown {
                attempt_id,
                expires_at,
                interval_seconds,
                ..
            } => formatter
                .debug_struct("SlowDown")
                .field("attempt_id", attempt_id)
                .field("verification_url", &"<redacted>")
                .field("expires_at", expires_at)
                .field("interval_seconds", interval_seconds)
                .finish(),
            Self::Completed { attempt_id } => formatter
                .debug_struct("Completed")
                .field("attempt_id", attempt_id)
                .finish(),
            Self::Committing { attempt_id, bot_id } => formatter
                .debug_struct("Committing")
                .field("attempt_id", attempt_id)
                .field("bot_id", bot_id)
                .finish(),
            Self::Denied {
                attempt_id,
                message,
            } => formatter
                .debug_struct("Denied")
                .field("attempt_id", attempt_id)
                .field("message", message)
                .finish(),
            Self::Expired { attempt_id } => formatter
                .debug_struct("Expired")
                .field("attempt_id", attempt_id)
                .finish(),
            Self::Cancelled { attempt_id } => formatter
                .debug_struct("Cancelled")
                .field("attempt_id", attempt_id)
                .finish(),
            Self::Failed {
                attempt_id,
                code,
                message,
                retryable,
            } => formatter
                .debug_struct("Failed")
                .field("attempt_id", attempt_id)
                .field("code", code)
                .field("message", message)
                .field("retryable", retryable)
                .finish(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeBotPairingRequest {
    pub request_id: String,
    pub bot_id: String,
    pub open_id: String,
    pub display_name: Option<String>,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeBotDiagnostic {
    pub code: String,
    pub message: String,
    pub retryable: bool,
    pub platform_code: Option<String>,
    pub guidance: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeBotSnapshot {
    pub last_activity_at: Option<i64>,
    pub id: String,
    pub name: String,
    pub project_id: String,
    pub app_id: String,
    pub platform: BridgeBotPlatform,
    pub enabled: bool,
    pub tools_enabled: bool,
    pub model_route: Option<BridgeBotModelRoute>,
    pub workspace_path: String,
    pub config_revision: u64,
    pub trusted_open_ids: Vec<String>,
    pub trusted_chat_ids: Vec<String>,
    pub connection: BridgeBotConnectionState,
    pub credential: BridgeBotCredentialAvailability,
    pub credential_operation: BridgeBotCredentialOperation,
    pub pairing: Vec<BridgeBotPairingRequest>,
    pub diagnostic: Option<BridgeBotDiagnostic>,
    pub can_change_project: bool,
    pub can_change_app_id: bool,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeBotsStateSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub bots: Vec<BridgeBotSnapshot>,
    pub registration: Option<BridgeBotRegistrationAttempt>,
    pub pending_credential_operations: Vec<BridgeBotPendingCredentialOperation>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeBotPendingCredentialOperation {
    pub bot_id: String,
    pub credential_operation: BridgeBotCredentialOperation,
    pub diagnostic: Option<BridgeBotDiagnostic>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeBotRegistrationAttempt {
    pub attempt_id: String,
    pub name: String,
    pub project_id: String,
    pub status: BridgeBotRegistrationStatus,
    pub completed_bot_id: Option<String>,
}

#[derive(Clone, PartialEq, Eq)]
pub enum BridgeBotSecretUpdate {
    Preserve,
    Replace { value: String },
    Clear,
}

impl std::fmt::Debug for BridgeBotSecretUpdate {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Preserve => formatter.write_str("Preserve"),
            Self::Replace { .. } => formatter
                .debug_struct("Replace")
                .field("value", &"<redacted>")
                .finish(),
            Self::Clear => formatter.write_str("Clear"),
        }
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct BridgeSaveBotRequest {
    pub operation_id: String,
    pub bot_id: Option<String>,
    pub expected_config_revision: u64,
    pub name: String,
    pub project_id: String,
    pub app_id: String,
    pub secret: BridgeBotSecretUpdate,
    pub enabled: bool,
    pub tools_enabled: bool,
    pub model_route: Option<BridgeBotModelRoute>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeBotModelRoute {
    pub account_id: String,
    pub model_id: String,
    pub effort: Option<String>,
}

impl std::fmt::Debug for BridgeSaveBotRequest {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("BridgeSaveBotRequest")
            .field("operation_id", &self.operation_id)
            .field("bot_id", &self.bot_id)
            .field("expected_config_revision", &self.expected_config_revision)
            .field("name", &self.name)
            .field("project_id", &self.project_id)
            .field("app_id", &self.app_id)
            .field("secret", &self.secret)
            .field("enabled", &self.enabled)
            .field("tools_enabled", &self.tools_enabled)
            .finish()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeStartBotRegistrationRequest {
    pub operation_id: String,
    pub name: String,
    pub project_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCancelBotRegistrationRequest {
    pub operation_id: String,
    pub attempt_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSetBotEnabledRequest {
    pub operation_id: String,
    pub bot_id: String,
    pub expected_config_revision: u64,
    pub enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRetryBotConnectionRequest {
    pub operation_id: String,
    pub bot_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSetBotTrustedUserRequest {
    pub operation_id: String,
    pub bot_id: String,
    pub expected_config_revision: u64,
    pub open_id: String,
    pub trusted: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSetBotTrustedChatRequest {
    pub operation_id: String,
    pub bot_id: String,
    pub expected_config_revision: u64,
    pub chat_id: String,
    pub trusted: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotsCommandReply {
    pub bot: Option<BridgeBotSnapshot>,
    pub registration: Option<BridgeBotRegistrationAttempt>,
    pub receipt: BridgeStudioCommandReceipt,
    pub stamp: Option<BridgeResourceStamp>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotConversationSource {
    RemoteGroup,
    ObservedDirect,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotConversationKind {
    Group,
    Direct,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotConversationThreadState {
    Creating,
    Bound,
    NeedsAttention,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotConversationThreadBinding {
    pub bot_id: String,
    pub chat_id: String,
    pub project_id: String,
    pub thread_id: Option<String>,
    pub revision: u64,
    pub state: BridgeBotConversationThreadState,
    pub diagnostic: Option<BridgeBotDiagnostic>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotConversation {
    pub chat_id: String,
    pub kind: BridgeBotConversationKind,
    pub source: BridgeBotConversationSource,
    pub name: Option<String>,
    pub last_observed_at: Option<i64>,
    pub thread_binding: Option<BridgeBotConversationThreadBinding>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCreateBotConversationThreadRequest {
    pub operation_id: String,
    pub bot_id: String,
    pub chat_id: String,
    pub expected_config_revision: u64,
    pub expected_binding_revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotConversationThreadReply {
    pub binding: BridgeBotConversationThreadBinding,
    pub receipt: BridgeStudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeListBotConversationsRequest {
    pub bot_id: String,
    pub cursor: Option<String>,
    pub limit: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotConversationPage {
    pub bot_id: String,
    pub conversations: Vec<BridgeBotConversation>,
    pub next_cursor: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeReadBotMessagesRequest {
    pub bot_id: String,
    pub chat_id: String,
    pub start_time: Option<i64>,
    pub end_time: Option<i64>,
    pub cursor: Option<String>,
    pub limit: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotMessageBody {
    Text { text: String },
    Post { text: String },
    Unsupported { msg_type: String, notice: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotMessage {
    pub message_id: String,
    pub chat_id: String,
    pub sender_open_id: Option<String>,
    pub created_at: i64,
    pub body: BridgeBotMessageBody,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotMessagePage {
    pub bot_id: String,
    pub chat_id: String,
    pub messages: Vec<BridgeBotMessage>,
    pub next_cursor: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotSendStatus {
    Succeeded,
    Partial,
    Rejected,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSendBotMessageRequest {
    pub operation_id: String,
    pub bot_id: String,
    pub chat_id: String,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotSendSegment {
    pub index: u32,
    pub status: BridgeBotSendStatus,
    pub platform_message_id: Option<String>,
    pub diagnostic: Option<BridgeBotDiagnostic>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotSendResult {
    pub operation_id: String,
    pub bot_id: String,
    pub chat_id: String,
    pub status: BridgeBotSendStatus,
    pub segments: Vec<BridgeBotSendSegment>,
    pub receipt: BridgeStudioCommandReceipt,
}
