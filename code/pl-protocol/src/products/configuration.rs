//! Configuration-only values and the native-issued compatible configuration/catalog credential.
use serde::{Deserialize, Serialize};

use super::models::{AccountModelKey, ModelSelection};
use super::references::{ConfigurationReadTarget, ModelCatalogReadTarget};
use crate::studio::{ConfigProjectionStamp, StudioError};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ConfigurationRoleReadRef {
    pub entry: u64,
    pub revision: u64,
}

/// All four fields are verified against the original immutable pair, not merely echoed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ConfigurationRoleReadTarget {
    pub reference: ConfigurationRoleReadRef,
    pub configuration: ConfigurationReadTarget,
    pub catalog: ModelCatalogReadTarget,
    pub stamp: ConfigProjectionStamp,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ConfigurationValue {
    pub default_account_id: Option<String>,
    pub accounts: Vec<AccountConfiguration>,
    pub mode_model_routes: Vec<crate::studio::StudioModeModelSettings>,
    pub roles: Vec<crate::studio::StudioRoleSettings>,
    pub permission_mode: String,
    pub instructions: crate::studio::StudioInstructionsSettings,
    pub skills: crate::studio::StudioSkillsSettings,
    pub mcp_servers: Vec<crate::studio::StudioMcpServerSettings>,
    pub general: crate::studio::StudioGeneralSettings,
    pub delegation: crate::DelegationSettings,
    pub web_search: WebSearchConfiguration,
    pub deepseek_web_search: DeepSeekSearchConfiguration,
}

/// Only credential presence survives capture. Effective Models and search policy are not here.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct AccountConfiguration {
    pub pricing_enabled: bool,
    pub billing_kind: crate::BillingKind,
    pub billing_kind_override: Option<crate::BillingKind>,
    pub disabled_models: Vec<String>,
    pub account_id: String,
    pub template_id: Option<String>,
    pub protocol: String,
    pub name: String,
    pub base_url: String,
    pub has_bearer_token: bool,
    /// 凭据来源环境变量名（非凭据值）；`None` 表示该账号不使用环境变量凭据。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bearer_token_env: Option<String>,
    pub usage_query_revision: u64,
    pub custom_models: Vec<crate::studio::StudioCustomModelSettings>,
    pub model_connection_modes: Vec<crate::studio::StudioModelConnectionSettings>,
    pub model_auto_compact_limits: Vec<crate::studio::StudioModelAutoCompactSettings>,
    pub catalog_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct WebSearchConfiguration {
    pub configured_mode: String,
    pub context_size: Option<String>,
    pub allowed_domains: Vec<String>,
    pub country: Option<String>,
    pub region: Option<String>,
    pub city: Option<String>,
    pub timezone: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct DeepSeekSearchConfiguration {
    pub configured_enabled: bool,
    pub configured_fetch_enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum RoleRouteRead {
    Configured {
        route: crate::studio::StudioRoleSettings,
    },
    Missing {
        suggestion: Option<ModelSelection>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct StartRouteIntent {
    #[schema(value_type = String)]
    pub mode: crate::ThreadModeId,
    pub model: Option<AccountModelKey>,
    pub effort: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum StartRouteQuery {
    Resolve {
        intent: StartRouteIntent,
    },
    SelectModel {
        intent: StartRouteIntent,
        selected: AccountModelKey,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum StartRouteRead {
    Ready {
        sources: ConfigurationRoleReadTarget,
        query: StartRouteQuery,
        intent: StartRouteIntent,
        route: ModelSelection,
        defaults: crate::DelegationSettings,
    },
    Unavailable {
        sources: ConfigurationRoleReadTarget,
        query: StartRouteQuery,
        intent: StartRouteIntent,
        desired: Option<ModelSelection>,
        defaults: crate::DelegationSettings,
        error: StudioError,
    },
}
