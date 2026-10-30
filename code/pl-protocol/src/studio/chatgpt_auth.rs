//! Native OpenAI authentication. OAuth credentials never cross this boundary.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AccountAuthenticationMethod {
    #[default]
    ApiKey,
    ChatGpt,
}

/// Public, validated registration metadata, never a token or a billing guarantee.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatGptAccountInfo {
    pub issuer: String,
    pub subject: String,
    pub client_id: String,
    pub email: Option<String>,
    pub plan_usage_enabled: bool,
}

/// Authentication changes participate in the same account settings transaction.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum AccountAuthenticationIntent {
    #[default]
    Keep,
    ApiKey,
    ChatGpt {
        login_id: String,
        editor_id: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StartChatGptLoginRequest {
    /// Stable idempotency identity allocated before dispatch.
    pub login_id: String,
    pub editor_id: String,
    /// The editor allocates the stable account ID before creating an account.
    pub account_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CancelChatGptLoginRequest {
    pub login_id: String,
    pub editor_id: String,
    pub account_id: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ChatGptLoginPhase {
    Preparing,
    AwaitingBrowser,
    ExchangingCode,
    Succeeded,
    Cancelled,
    Failed,
}

impl ChatGptLoginPhase {
    pub fn is_terminal(self) -> bool {
        matches!(self, Self::Succeeded | Self::Cancelled | Self::Failed)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ChatGptLoginFailureCode {
    Network,
    AuthorizationDenied,
    InvalidCallback,
    InvalidIdentity,
    MissingPlanPermission,
    Expired,
    Storage,
    TaskFailed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatGptLoginFailure {
    pub code: ChatGptLoginFailureCode,
    pub retryable: bool,
}

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatGptLoginSnapshot {
    pub login_id: String,
    pub editor_id: String,
    pub account_id: String,
    pub revision: u64,
    pub phase: ChatGptLoginPhase,
    /// Only present while waiting. Must not contain id_token_hint or any token.
    pub authorization_url: Option<String>,
    pub expires_at: Option<i64>,
    pub account: Option<ChatGptAccountInfo>,
    pub failure: Option<ChatGptLoginFailure>,
}

/// Command and observation deliveries use the same owner clock.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatGptLoginCommandReply {
    pub stamp: super::ResourceStamp,
    pub snapshot: ChatGptLoginSnapshot,
}

impl std::fmt::Debug for ChatGptLoginSnapshot {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ChatGptLoginSnapshot")
            .field("login_id", &self.login_id)
            .field("phase", &self.phase)
            .field("revision", &self.revision)
            .field("authorization_available", &self.authorization_url.is_some())
            .field("failure", &self.failure)
            .finish_non_exhaustive()
    }
}
