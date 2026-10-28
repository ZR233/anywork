//! Account domain reads and field intents. Each frame retains its original owner's clock.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::{
    AcpAccountSettings, AcpAuthSnapshot, AcpInstallSnapshot, ResourceStamp,
    StudioAccountModelCatalog, StudioAccountSettings,
};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum AccountIdentity {
    Native { account_id: String },
    Acp { account_id: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountCapabilities {
    pub set_default: bool,
    pub edit: bool,
    pub remove: bool,
    pub query_usage: bool,
    pub sync_models: bool,
    pub edit_models: bool,
    pub acp_auth: bool,
}

/// Lightweight settings-only list row. ACP never receives synthetic Native facts.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountSummary {
    pub identity: AccountIdentity,
    pub name: String,
    pub brand_key: Option<String>,
    /// Display-only URL origin; never an editable endpoint or raw configuration fallback.
    pub display_endpoint: Option<String>,
    pub is_default: bool,
    pub billing_kind: Option<crate::BillingKind>,
    pub billing_kind_override: Option<crate::BillingKind>,
    pub credential_ready: Option<bool>,
    pub usage_query_revision: Option<u64>,
    /// ACP connection identity from the authentication owner; absent for Native accounts.
    /// This is not a cross-domain freshness watermark.
    pub acp_connection_revision: Option<u64>,
    pub capabilities: AccountCapabilities,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
pub enum AccountDetail {
    Native(Box<StudioAccountSettings>),
    Acp(AcpAccountSettings),
}

/// Explicit observation demand, not a statistics scope/page/ACK protocol.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum AccountObservationTarget {
    Summaries,
    Detail { identity: AccountIdentity },
    Models { account_id: String },
    Usage,
    AcpAuth,
    AcpInstall,
}

/// Complete replacement for one domain only. Missing detail/catalog means the target was deleted.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum AccountDomainFrame {
    Summaries {
        stamp: ResourceStamp,
        accounts: Vec<AccountSummary>,
    },
    Detail {
        stamp: ResourceStamp,
        identity: AccountIdentity,
        account: Option<AccountDetail>,
    },
    Models {
        stamp: ResourceStamp,
        account_id: String,
        catalog: Option<StudioAccountModelCatalog>,
    },
    Usage {
        stamp: ResourceStamp,
        accounts: Vec<AccountUsageObservation>,
    },
    AcpAuth {
        stamp: ResourceStamp,
        snapshot: AcpAuthSnapshot,
    },
    AcpInstall {
        stamp: ResourceStamp,
        snapshot: AcpInstallSnapshot,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AccountUsagePhase {
    Unchecked,
    Querying,
    Succeeded,
    Unsupported,
    MissingCredential,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AccountUsageFailureCode {
    Configuration,
    Query,
    Cancelled,
    TaskFailed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountUsageFailure {
    pub code: AccountUsageFailureCode,
    pub retryable: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountUsageObservation {
    pub account_id: String,
    pub query_revision: u64,
    pub revision: u64,
    pub phase: AccountUsagePhase,
    pub operation_id: Option<String>,
    pub checked_at: Option<i64>,
    pub failure: Option<AccountUsageFailure>,
    /// Only from this exact query identity, including while querying or after failure.
    pub last_good: Option<AccountUsageSuccess>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountUsageSuccess {
    pub checked_at: i64,
    pub value: AccountUsageValue,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum AccountUsageValue {
    Balance {
        available: bool,
        balances: Vec<AccountMoneyBalance>,
    },
    Subscription {
        level: Option<String>,
        quotas: Vec<AccountQuota>,
    },
}

/// Decimal strings and currencies are provider facts; never summed across currencies.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountMoneyBalance {
    pub currency: String,
    pub total: String,
    pub granted: String,
    pub topped_up: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountQuota {
    pub window: AccountQuotaWindow,
    pub percentage: f64,
    pub used: Option<f64>,
    pub total: Option<f64>,
    pub remaining: Option<f64>,
    pub reset_at: Option<i64>,
    pub details: Vec<AccountQuotaDetail>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
pub enum AccountQuotaWindow {
    FiveHour,
    Weekly,
    McpMonthly,
    Other(String),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountQuotaDetail {
    pub name: String,
    pub used: Option<f64>,
    pub total: Option<f64>,
    pub percentage: Option<f64>,
}

/// Missing fields keep current values; restore uses template defaults (or clears optional fields).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub enum AccountTextPatch {
    #[default]
    Keep,
    Set {
        value: String,
    },
    Restore,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub enum AccountModelsPatch {
    #[default]
    Keep,
    Set {
        models: Vec<super::AccountModelUpdate>,
    },
    Restore,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PatchAccountRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub account_id: String,
    #[serde(default)]
    pub name: AccountTextPatch,
    #[serde(default)]
    pub base_url: AccountTextPatch,
    #[serde(default)]
    pub template_id: AccountTextPatch,
    #[serde(default)]
    pub protocol: AccountTextPatch,
    pub secret: super::AccountSecretUpdate,
    #[serde(default)]
    pub custom_models: AccountModelsPatch,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AccountConnectionMode {
    Http,
    WebSocket,
}

/// Explicit tagged intent: no omitted/null ambiguity and no stale sibling model fields.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    content = "value",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub enum AutoCompactIntent {
    Set(u64),
    Clear,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    content = "value",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub enum ModelConnectionIntent {
    Set(AccountConnectionMode),
    Clear,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SetAccountModelAutoCompactRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub account_id: String,
    pub model_id: String,
    pub limit: AutoCompactIntent,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SetAccountModelConnectionRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub account_id: String,
    pub model_id: String,
    pub connection: ModelConnectionIntent,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SyncAccountModelsRequest {
    pub operation_id: String,
    pub account_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SyncAccountModelsReply {
    /// Duplicate requests return the original operation, rather than claiming a new operation ran.
    pub operation_id: String,
    pub account_id: String,
    pub query_generation: u64,
    pub joined_existing: bool,
}
