//! Token-free SIWC values exposed to the desktop client.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BridgeAccountAuthenticationMethod {
    #[default]
    ApiKey,
    ChatGpt,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeChatGptAccountInfo {
    pub issuer: String,
    pub subject: String,
    pub client_id: String,
    pub email: Option<String>,
    pub plan_usage_enabled: bool,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum BridgeAccountAuthenticationIntent {
    #[default]
    Keep,
    ApiKey,
    ChatGpt {
        login_id: String,
        editor_id: String,
    },
}

#[derive(Debug, Clone, Copy)]
pub enum BridgeChatGptLoginPhase {
    Preparing,
    AwaitingBrowser,
    ExchangingCode,
    Succeeded,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, Copy)]
pub enum BridgeChatGptLoginFailureCode {
    Network,
    AuthorizationDenied,
    InvalidCallback,
    InvalidIdentity,
    MissingPlanPermission,
    Expired,
    Storage,
    TaskFailed,
}

#[derive(Debug, Clone)]
pub struct BridgeChatGptLoginFailure {
    pub code: BridgeChatGptLoginFailureCode,
    pub retryable: bool,
}

#[derive(Clone)]
pub struct BridgeChatGptLoginSnapshot {
    pub login_id: String,
    pub editor_id: String,
    pub account_id: String,
    pub revision: u64,
    pub phase: BridgeChatGptLoginPhase,
    pub authorization_url: Option<String>,
    pub expires_at: Option<i64>,
    pub account: Option<BridgeChatGptAccountInfo>,
    pub failure: Option<BridgeChatGptLoginFailure>,
}

#[derive(Debug, Clone)]
pub struct BridgeChatGptLoginCommandReply {
    pub stamp: super::BridgeResourceStamp,
    pub snapshot: BridgeChatGptLoginSnapshot,
}

impl std::fmt::Debug for BridgeChatGptLoginSnapshot {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("BridgeChatGptLoginSnapshot")
            .field("login_id", &self.login_id)
            .field("phase", &self.phase)
            .field("revision", &self.revision)
            .field("authorization_available", &self.authorization_url.is_some())
            .field("failure", &self.failure)
            .finish_non_exhaustive()
    }
}
