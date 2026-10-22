//! 机器人产品 DTO：配置、连接、注册、查询与发送。
//!
//! 字段使用 camelCase、String ID 与 Unix 秒时间戳。配置 CAS 使用各机器人独立
//! `configRevision`，与 `Bots` topic 的领域 revision 分开。设备码、App Secret
//! 与租户 token 不进入本模块。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::{ResourceStamp, StudioCommandReceipt};

/// 飞书中国版自建应用。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotPlatform {
    FeishuChina,
}

/// A bot owns one model selection shared by all of its platform conversations.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotModelRoute {
    pub account_id: String,
    pub model_id: String,
    pub effort: Option<String>,
}

/// 机器人连接生命周期。保存成功不等于已连接。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind", deny_unknown_fields)]
pub enum BotConnectionState {
    Disabled,
    Connecting,
    Connected,
    Reconnecting {
        #[serde(
            rename = "nextAttemptAt",
            default,
            skip_serializing_if = "Option::is_none"
        )]
        next_attempt_at: Option<i64>,
        attempt: u32,
    },
    Failed {
        code: String,
        message: String,
        retryable: bool,
        #[serde(
            rename = "platformCode",
            default,
            skip_serializing_if = "Option::is_none"
        )]
        platform_code: Option<String>,
    },
}

/// App Secret 可用性。`sessionOnly` 表示仅进程 secret lease，未永久保存。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotCredentialAvailability {
    Missing,
    SessionOnly,
    Stored,
    Unavailable,
}

/// 凭据/配置共同提交的公开操作状态。不含 secret、候选材料或内部版本引用。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind", deny_unknown_fields)]
pub enum BotCredentialOperation {
    #[default]
    Idle,
    Preparing {
        #[serde(rename = "operationId")]
        operation_id: String,
    },
    CommitUncertain {
        #[serde(rename = "operationId")]
        operation_id: String,
    },
    CleanupPending {
        #[serde(rename = "operationId")]
        operation_id: String,
        #[serde(rename = "configCommitted")]
        config_committed: bool,
    },
}

/// 扫码注册对外状态。设备码不进入 DTO。
#[derive(Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind", deny_unknown_fields)]
pub enum BotRegistrationStatus {
    Idle,
    Preparing {
        #[serde(rename = "attemptId")]
        attempt_id: String,
    },
    Waiting {
        #[serde(rename = "attemptId")]
        attempt_id: String,
        #[serde(rename = "verificationUrl")]
        verification_url: String,
        #[serde(rename = "expiresAt")]
        expires_at: i64,
        #[serde(rename = "intervalSeconds")]
        interval_seconds: u32,
    },
    SlowDown {
        #[serde(rename = "attemptId")]
        attempt_id: String,
        #[serde(rename = "verificationUrl")]
        verification_url: String,
        #[serde(rename = "expiresAt")]
        expires_at: i64,
        #[serde(rename = "intervalSeconds")]
        interval_seconds: u32,
    },
    Completed {
        #[serde(rename = "attemptId")]
        attempt_id: String,
    },
    Committing {
        #[serde(rename = "attemptId")]
        attempt_id: String,
        #[serde(rename = "botId")]
        bot_id: String,
    },
    Denied {
        #[serde(rename = "attemptId")]
        attempt_id: String,
        message: String,
    },
    Expired {
        #[serde(rename = "attemptId")]
        attempt_id: String,
    },
    Cancelled {
        #[serde(rename = "attemptId")]
        attempt_id: String,
    },
    Failed {
        #[serde(rename = "attemptId")]
        attempt_id: String,
        code: String,
        message: String,
        retryable: bool,
    },
}

impl std::fmt::Debug for BotRegistrationStatus {
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

/// 未知用户形成的有界本地配对请求。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotPairingRequest {
    pub request_id: String,
    pub bot_id: String,
    pub open_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    pub created_at: i64,
}

/// 单机器人配置与运行诊断。不含会话正文。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotSnapshot {
    pub last_activity_at: Option<i64>,
    pub id: String,
    pub name: String,
    pub project_id: String,
    pub app_id: String,
    pub platform: BotPlatform,
    pub enabled: bool,
    pub tools_enabled: bool,
    pub model_route: Option<BotModelRoute>,
    pub workspace_path: String,
    pub config_revision: u64,
    pub trusted_open_ids: Vec<String>,
    pub trusted_chat_ids: Vec<String>,
    pub connection: BotConnectionState,
    pub credential: BotCredentialAvailability,
    #[serde(default)]
    pub credential_operation: BotCredentialOperation,
    pub pairing: Vec<BotPairingRequest>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub diagnostic: Option<BotDiagnostic>,
    pub can_change_project: bool,
    pub can_change_app_id: bool,
    pub created_at: i64,
    pub updated_at: i64,
}

/// 面向 GUI 的可操作诊断。不含固定中文业务文案，也不含 secret。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotDiagnostic {
    pub code: String,
    pub message: String,
    pub retryable: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub platform_code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub guidance: Option<String>,
}

/// `Bots` topic 的 canonical 快照。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotsStateSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub bots: Vec<BotSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub registration: Option<BotRegistrationAttempt>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub pending_credential_operations: Vec<BotPendingCredentialOperation>,
}

/// 尚无确定配置时的凭据/配置操作投影。不把候选加入已配置机器人列表。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotPendingCredentialOperation {
    pub bot_id: String,
    pub credential_operation: BotCredentialOperation,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub diagnostic: Option<BotDiagnostic>,
}

/// 当前扫码注册尝试。与真实 bot 身份分开，不占用 BotSnapshot.id。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotRegistrationAttempt {
    pub attempt_id: String,
    pub name: String,
    pub project_id: String,
    pub status: BotRegistrationStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed_bot_id: Option<String>,
}

/// App Secret 替换语义，沿用 Preserve/Replace/Clear。
#[derive(Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "action", deny_unknown_fields)]
pub enum BotSecretUpdate {
    Preserve,
    Replace { value: String },
    Clear,
}

impl std::fmt::Debug for BotSecretUpdate {
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

/// 保存或更新已有应用。
#[derive(Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SaveBotRequest {
    pub operation_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bot_id: Option<String>,
    pub expected_config_revision: u64,
    pub name: String,
    pub project_id: String,
    pub app_id: String,
    pub secret: BotSecretUpdate,
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub tools_enabled: bool,
    pub model_route: Option<BotModelRoute>,
}

impl std::fmt::Debug for SaveBotRequest {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SaveBotRequest")
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

/// 开始扫码注册。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StartBotRegistrationRequest {
    pub operation_id: String,
    pub name: String,
    pub project_id: String,
}

/// 取消当前扫码注册。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CancelBotRegistrationRequest {
    pub operation_id: String,
    pub attempt_id: String,
}

/// 启停或重试连接。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SetBotEnabledRequest {
    pub operation_id: String,
    pub bot_id: String,
    pub expected_config_revision: u64,
    pub enabled: bool,
}

/// 重试失败连接，不改变 desired enabled。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RetryBotConnectionRequest {
    pub operation_id: String,
    pub bot_id: String,
}

/// 批准或撤销可信用户。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SetBotTrustedUserRequest {
    pub operation_id: String,
    pub bot_id: String,
    pub expected_config_revision: u64,
    pub open_id: String,
    pub trusted: bool,
}

/// 批准或撤销群。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SetBotTrustedChatRequest {
    pub operation_id: String,
    pub bot_id: String,
    pub expected_config_revision: u64,
    pub chat_id: String,
    pub trusted: bool,
}

/// 配置 mutation 的权威回执。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotsCommandReply {
    pub snapshot: BotsStateSnapshot,
    pub receipt: StudioCommandReceipt,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stamp: Option<ResourceStamp>,
}

/// 会话列表来源。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotConversationSource {
    RemoteGroup,
    ObservedDirect,
}

/// 机器人可见会话。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotConversation {
    pub chat_id: String,
    pub kind: BotConversationKind,
    pub source: BotConversationSource,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_observed_at: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thread_binding: Option<BotConversationThreadBinding>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotConversationKind {
    Group,
    Direct,
}

/// 本机会话绑定状态。无绑定时 revision 为 0，且不暴露魔法 Thread ID。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind", deny_unknown_fields)]
pub enum BotConversationThreadState {
    Creating,
    Bound,
    NeedsAttention,
}

/// 机器人/平台会话到本机 Thread 的权威绑定投影。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotConversationThreadBinding {
    pub bot_id: String,
    pub chat_id: String,
    pub project_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thread_id: Option<String>,
    pub revision: u64,
    pub state: BotConversationThreadState,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub diagnostic: Option<BotDiagnostic>,
}

/// 本地显式新建本机会话。不开放给模型工具。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateBotConversationThreadRequest {
    pub operation_id: String,
    pub bot_id: String,
    pub chat_id: String,
    pub expected_config_revision: u64,
    pub expected_binding_revision: u64,
}

/// 显式新建本机会话的权威回执。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotConversationThreadReply {
    pub binding: BotConversationThreadBinding,
    pub receipt: StudioCommandReceipt,
}

/// 会话分页查询。cursor 绑定 bot 与查询身份。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ListBotConversationsRequest {
    pub bot_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cursor: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub limit: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotConversationPage {
    pub bot_id: String,
    pub conversations: Vec<BotConversation>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub next_cursor: Option<String>,
}

/// 历史查询。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadBotMessagesRequest {
    pub bot_id: String,
    pub chat_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start_time: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub end_time: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cursor: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub limit: Option<u32>,
}

/// 已知正文；未支持媒体明确而不伪装附件。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind", deny_unknown_fields)]
pub enum BotMessageBody {
    Text {
        text: String,
    },
    Post {
        text: String,
    },
    Unsupported {
        #[serde(rename = "msgType")]
        msg_type: String,
        notice: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotMessage {
    pub message_id: String,
    pub chat_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sender_open_id: Option<String>,
    pub created_at: i64,
    pub body: BotMessageBody,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotMessagePage {
    pub bot_id: String,
    pub chat_id: String,
    pub messages: Vec<BotMessage>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub next_cursor: Option<String>,
}

/// 发送状态。官方 UUID 去重窗口为一小时，超时未知不自动重发。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotSendStatus {
    Succeeded,
    Partial,
    Rejected,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SendBotMessageRequest {
    pub operation_id: String,
    pub bot_id: String,
    pub chat_id: String,
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotSendSegment {
    pub index: u32,
    pub status: BotSendStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub platform_message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub diagnostic: Option<BotDiagnostic>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotSendResult {
    pub operation_id: String,
    pub bot_id: String,
    pub chat_id: String,
    pub status: BotSendStatus,
    pub segments: Vec<BotSendSegment>,
    pub receipt: StudioCommandReceipt,
}
