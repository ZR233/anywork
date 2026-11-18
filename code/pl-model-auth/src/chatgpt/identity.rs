//! 已验证的账号身份；不包含凭据。
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

/// Public, validated registration metadata, never a token or a billing guarantee.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatGptAccountInfo {
    pub issuer: String,
    pub subject: String,
    pub client_id: String,
    pub email: Option<String>,
    pub plan_usage_enabled: bool,
    /// Selected Codex workspace from the verified ID token. Older, independent
    /// plan-sharing registrations retain their original resource and credentials.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub codex: Option<CodexAccountInfo>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CodexAccountInfo {
    pub account_id: String,
    pub plan_type: Option<String>,
}
