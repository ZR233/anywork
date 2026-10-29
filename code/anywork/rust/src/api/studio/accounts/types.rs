use crate::api::studio::types::{
    AccountModelInput, AccountSecretInput, BridgeAccountSettingsDto, BridgeAcpAccountSettings,
    BridgeAcpAuthSnapshot, BridgeAcpInstallSnapshot, BridgeBillingKind,
    BridgeModelCatalogAccountDto, BridgeResourceStamp,
};

#[derive(Debug, Clone)]
pub enum BridgeAccountIdentity {
    Native { account_id: String },
    Acp { account_id: String },
}

#[derive(Debug, Clone)]
pub enum BridgeAccountObservationTarget {
    Summaries,
    Detail { identity: BridgeAccountIdentity },
    Models { account_id: String },
    Usage,
    AcpAuth,
    AcpInstall,
}

#[derive(Debug, Clone)]
pub struct BridgeAccountCapabilities {
    pub set_default: bool,
    pub edit: bool,
    pub remove: bool,
    pub query_usage: bool,
    pub sync_models: bool,
    pub edit_models: bool,
    pub acp_auth: bool,
}

#[derive(Debug, Clone)]
pub struct BridgeAccountSummary {
    pub identity: BridgeAccountIdentity,
    pub name: String,
    pub brand_key: Option<String>,
    pub display_endpoint: Option<String>,
    pub is_default: bool,
    pub billing_kind: Option<BridgeBillingKind>,
    pub billing_kind_override: Option<BridgeBillingKind>,
    pub credential_ready: Option<bool>,
    pub usage_query_revision: Option<u64>,
    /// ACP authentication-owner identity; not a settings/catalog observation watermark.
    pub acp_connection_revision: Option<u64>,
    pub capabilities: BridgeAccountCapabilities,
}

#[derive(Debug, Clone)]
pub enum BridgeAccountDetail {
    Native(Box<BridgeAccountSettingsDto>),
    Acp(BridgeAcpAccountSettings),
}

#[derive(Debug, Clone)]
pub enum BridgeAccountDomainFrame {
    Summaries {
        stamp: BridgeResourceStamp,
        accounts: Vec<BridgeAccountSummary>,
    },
    Detail {
        stamp: BridgeResourceStamp,
        identity: BridgeAccountIdentity,
        account: Option<BridgeAccountDetail>,
    },
    Models {
        stamp: BridgeResourceStamp,
        account_id: String,
        catalog: Option<BridgeModelCatalogAccountDto>,
    },
    Usage {
        stamp: BridgeResourceStamp,
        accounts: Vec<BridgeAccountUsageObservation>,
    },
    AcpAuth {
        stamp: BridgeResourceStamp,
        snapshot: BridgeAcpAuthSnapshot,
    },
    AcpInstall {
        stamp: BridgeResourceStamp,
        snapshot: BridgeAcpInstallSnapshot,
    },
}

#[derive(Debug, Clone, Copy)]
pub enum BridgeAccountUsagePhase {
    Unchecked,
    Querying,
    Succeeded,
    Unsupported,
    MissingCredential,
    Failed,
}

#[derive(Debug, Clone, Copy)]
pub enum BridgeAccountUsageFailureCode {
    Configuration,
    Query,
    Cancelled,
    TaskFailed,
}

#[derive(Debug, Clone)]
pub struct BridgeAccountUsageFailure {
    pub code: BridgeAccountUsageFailureCode,
    pub retryable: bool,
}

#[derive(Debug, Clone)]
pub struct BridgeAccountUsageObservation {
    pub account_id: String,
    pub query_revision: u64,
    pub revision: u64,
    pub phase: BridgeAccountUsagePhase,
    pub operation_id: Option<String>,
    pub checked_at: Option<i64>,
    pub failure: Option<BridgeAccountUsageFailure>,
    pub last_good: Option<BridgeAccountUsageSuccess>,
}

#[derive(Debug, Clone)]
pub struct BridgeAccountUsageSuccess {
    pub checked_at: i64,
    pub value: BridgeAccountUsageValue,
}

#[derive(Debug, Clone)]
pub enum BridgeAccountUsageValue {
    Balance {
        available: bool,
        balances: Vec<BridgeAccountMoneyBalance>,
    },
    Subscription {
        level: Option<String>,
        quotas: Vec<BridgeAccountQuota>,
    },
}

#[derive(Debug, Clone)]
pub struct BridgeAccountMoneyBalance {
    pub currency: String,
    pub total: String,
    pub granted: String,
    pub topped_up: String,
}

#[derive(Debug, Clone)]
pub struct BridgeAccountQuota {
    pub window: BridgeAccountQuotaWindow,
    pub percentage: f64,
    pub used: Option<f64>,
    pub total: Option<f64>,
    pub remaining: Option<f64>,
    pub reset_at: Option<i64>,
    pub details: Vec<BridgeAccountQuotaDetail>,
}

#[derive(Debug, Clone)]
pub enum BridgeAccountQuotaWindow {
    FiveHour,
    Weekly,
    McpMonthly,
    Other(String),
}

#[derive(Debug, Clone)]
pub struct BridgeAccountQuotaDetail {
    pub name: String,
    pub used: Option<f64>,
    pub total: Option<f64>,
    pub percentage: Option<f64>,
}

#[derive(Debug, Clone)]
pub enum BridgeAccountTextPatch {
    Keep,
    Set { value: String },
    Restore,
}

#[derive(Debug, Clone)]
pub enum BridgeAccountModelsPatch {
    Keep,
    Set { models: Vec<AccountModelInput> },
    Restore,
}

#[derive(Debug, Clone)]
pub struct BridgePatchAccountInput {
    pub name: BridgeAccountTextPatch,
    pub base_url: BridgeAccountTextPatch,
    pub template_id: BridgeAccountTextPatch,
    pub protocol: BridgeAccountTextPatch,
    pub secret: AccountSecretInput,
    pub custom_models: BridgeAccountModelsPatch,
}

#[derive(Debug, Clone, Copy)]
pub enum BridgeAutoCompactIntent {
    Set { limit: u64 },
    Clear,
}

#[derive(Debug, Clone, Copy)]
pub enum BridgeAccountConnectionMode {
    Http,
    WebSocket,
}

#[derive(Debug, Clone, Copy)]
pub enum BridgeModelConnectionIntent {
    Set { mode: BridgeAccountConnectionMode },
    Clear,
}

#[derive(Debug, Clone)]
pub struct BridgeSyncAccountModelsReply {
    pub operation_id: String,
    pub account_id: String,
    pub query_generation: u64,
    pub joined_existing: bool,
}
