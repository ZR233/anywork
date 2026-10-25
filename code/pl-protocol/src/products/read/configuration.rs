//! Fixed Configuration fields. All nested collections and long strings remain scope-local.
use serde::{Deserialize, Serialize};

use super::primitives::TypedListRef;
use crate::studio::ReadText;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ConfigurationReadHeader {
    pub default_account_id: Option<ReadText>,
    pub accounts: TypedListRef,
    pub mode_model_routes: TypedListRef,
    pub roles: TypedListRef,
    pub permission_mode: ReadText,
    pub instructions: InstructionsSettingsRead,
    pub skills: SkillsSettingsRead,
    pub mcp_servers: TypedListRef,
    pub general: GeneralSettingsRead,
    pub delegation: crate::DelegationSettings,
    pub web_search: WebSearchConfigurationRead,
    pub deepseek_web_search: DeepSeekSearchConfigurationRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct AccountConfigurationRead {
    pub pricing_enabled: bool,
    pub billing_kind: crate::BillingKind,
    pub billing_kind_override: Option<crate::BillingKind>,
    pub disabled_models: TypedListRef,
    pub account_id: ReadText,
    pub template_id: Option<ReadText>,
    pub protocol: ReadText,
    pub name: ReadText,
    pub base_url: ReadText,
    pub has_bearer_token: bool,
    /// 凭据来源环境变量名（非凭据值）；`None` 表示该账号不使用环境变量凭据。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bearer_token_env: Option<ReadText>,
    pub usage_query_revision: u64,
    pub custom_models: TypedListRef,
    pub model_connection_modes: TypedListRef,
    pub model_auto_compact_limits: TypedListRef,
    pub catalog_id: Option<ReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct CustomModelConfigurationRead {
    pub input_capabilities: TypedListRef,
    pub context_window: Option<u64>,
    pub max_output_tokens: Option<u64>,
    pub model_id: ReadText,
    pub display_name: ReadText,
    pub reasoning_efforts: TypedListRef,
    pub base_instructions: ReadText,
    pub wire_api: ReadText,
    pub supported_connection_modes: TypedListRef,
    pub default_connection_mode: ReadText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelConnectionRead {
    pub model_id: ReadText,
    pub connection_mode: ReadText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelAutoCompactRead {
    pub model_id: ReadText,
    pub override_limit: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModeModelRouteRead {
    pub mode_id: ReadText,
    pub account_id: ReadText,
    pub model_id: ReadText,
    pub effort: ReadText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct RoleModelRouteRead {
    pub key: ReadText,
    pub account_id: ReadText,
    pub model_id: ReadText,
    pub effort: ReadText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct InstructionsSettingsRead {
    pub base_override: ReadText,
    pub developer: ReadText,
    pub user: ReadText,
    pub project_doc_max_bytes: u64,
    pub project_doc_fallback_filenames: TypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct SkillsSettingsRead {
    pub enabled: bool,
    pub auto_learn: bool,
    pub system_enabled: bool,
    pub project_dir: ReadText,
    pub user_dir: ReadText,
    pub external_dirs: TypedListRef,
    pub disabled: TypedListRef,
    pub auto_learn_min_tool_calls: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct McpConfigurationRead {
    pub id: ReadText,
    pub transport: ReadText,
    pub endpoint: ReadText,
    pub configuration: crate::studio::StudioMcpServerConfiguration,
    pub source_kind: ReadText,
    pub mutation_policy: ReadText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct GeneralSettingsRead {
    pub follow_active_turn: bool,
    pub compact_timeline: bool,
    pub sidebar_width: Option<u16>,
    pub pinned_thread_ids: TypedListRef,
    pub pinned_project_ids: TypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct WebSearchConfigurationRead {
    pub configured_mode: ReadText,
    pub context_size: Option<ReadText>,
    pub allowed_domains: TypedListRef,
    pub country: Option<ReadText>,
    pub region: Option<ReadText>,
    pub city: Option<ReadText>,
    pub timezone: Option<ReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct DeepSeekSearchConfigurationRead {
    pub configured_enabled: bool,
    pub configured_fetch_enabled: bool,
}
