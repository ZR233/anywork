//! Studio 无密钥 canonical Settings 快照。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

/// Secret-free canonical configuration snapshot.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SettingsConfigSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub settings: StudioSettings,
}

/// One account's model directory observation. It is owned by the catalog clock and
/// is deliberately absent from [`StudioAccountSettings`].
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioAccountModelCatalog {
    pub account_id: String,
    pub effective_models: Vec<crate::ModelDescriptor>,
    pub model_catalog: StudioModelCatalogStatus,
}

/// Canonical model directory snapshot. Catalog refreshes never rewrite the
/// configuration snapshot or its revision.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelCatalogSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub accounts: Vec<StudioAccountModelCatalog>,
}

/// Direct response for a configuration command. The two resources are
/// returned together for convenience, while each retains its own clock.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SettingsStateResponse {
    pub config: SettingsConfigSnapshot,
    pub catalog: ModelCatalogSnapshot,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioSettings {
    pub default_account_id: Option<String>,
    pub accounts: Vec<StudioAccountSettings>,
    pub mode_model_routes: Vec<StudioModeModelSettings>,
    pub roles: Vec<StudioRoleSettings>,
    pub permission_mode: String,
    pub instructions: StudioInstructionsSettings,
    pub skills: StudioSkillsSettings,
    pub mcp_servers: Vec<StudioMcpServerSettings>,
    pub general: StudioGeneralSettings,
    pub web_search: StudioWebSearchSettings,
    pub deepseek_web_search: StudioDeepSeekWebSearchSettings,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioAccountSettings {
    pub pricing_enabled: bool,
    pub account_id: String,
    /// 可选的内置账号模板引用；完全自定义账号为 `None`。
    pub template_id: Option<String>,
    /// 明确的厂商协议适配选择。
    pub protocol: String,
    pub name: String,
    pub base_url: String,
    pub has_bearer_token: bool,
    /// Owner-local, non-secret identity of this instance's usage query inputs.
    pub usage_query_revision: u64,
    pub credential_required: bool,
    pub capability_source: String,
    pub hosted_web_search: bool,
    pub hosted_web_search_dialect: String,
    pub standalone_web_search: Option<String>,
    pub prompt_cache_dialect: String,
    pub responses_programmatic_tool_calling: bool,
    /// 目录或创建路由的默认模型投影；不是账号 runtime 的第二份模型选择。
    pub default_model_id: String,
    pub custom_models: Vec<StudioCustomModelSettings>,
    pub model_connection_modes: Vec<StudioModelConnectionSettings>,
    pub model_auto_compact_limits: Vec<StudioModelAutoCompactSettings>,
    pub catalog_id: Option<String>,
}

/// One account instance's derived directory observation, never desired configuration.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioModelCatalogStatus {
    pub supported: bool,
    pub source: StudioModelCatalogSource,
    pub probing: bool,
    pub last_success_at: Option<i64>,
    pub checked_at: Option<i64>,
    pub error: Option<StudioModelCatalogError>,
    pub cache_warning: Option<StudioModelCatalogCacheWarning>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum StudioModelCatalogSource {
    Default,
    Cached,
    Online,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum StudioModelCatalogError {
    Unsupported,
    Configuration,
    Timeout,
    Transport {
        #[serde(rename = "httpStatus")]
        http_status: Option<u16>,
    },
    Http {
        status: u16,
    },
    TooLarge,
    Protocol,
    CacheIdentity,
    UnexpectedNotModified,
    CacheWrite,
    Closing,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum StudioModelCatalogCacheWarning {
    Read,
    Schema,
    Identity,
    Declaration,
}

/// 删除手动模型的配置命令。只接受 `additional_models` 或 Explicit 目录中的 model_id。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RemoveAccountModelRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub account_id: String,
    pub model_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioCustomModelSettings {
    pub input_capabilities: Vec<crate::ModelInputCapabilityDto>,
    pub context_window: Option<u64>,
    pub max_output_tokens: Option<u64>,
    pub model_id: String,
    pub display_name: String,
    pub reasoning_efforts: Vec<String>,
    pub base_instructions: String,
    pub wire_api: String,
    pub supported_connection_modes: Vec<String>,
    pub default_connection_mode: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioModelConnectionSettings {
    pub model_id: String,
    pub connection_mode: String,
}

/// Persisted account override intent; resolved policy belongs to the effective catalog.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioModelAutoCompactSettings {
    pub model_id: String,
    pub override_limit: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioRoleSettings {
    pub key: String,
    pub account_id: String,
    pub model_id: String,
    pub effort: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioModeModelSettings {
    pub mode_id: String,
    pub account_id: String,
    pub model_id: String,
    pub effort: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioInstructionsSettings {
    pub base_override: String,
    pub developer: String,
    pub user: String,
    pub project_doc_max_bytes: u64,
    pub project_doc_fallback_filenames: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioSkillsSettings {
    pub enabled: bool,
    pub auto_learn: bool,
    pub system_enabled: bool,
    pub project_dir: String,
    pub user_dir: String,
    pub external_dirs: Vec<String>,
    pub disabled: Vec<String>,
    pub auto_learn_min_tool_calls: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioMcpServerSettings {
    pub id: String,
    pub transport: String,
    pub endpoint: String,
    pub configuration: StudioMcpServerConfiguration,
    pub source_kind: String,
    pub mutation_policy: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum StudioMcpServerConfiguration {
    Enabled,
    Disabled,
    MissingCredential,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioGeneralSettings {
    pub follow_active_turn: bool,
    pub compact_timeline: bool,
    #[serde(default)]
    pub sidebar_width: Option<u16>,
    #[serde(default)]
    pub pinned_thread_ids: Vec<String>,
    #[serde(default)]
    pub pinned_project_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioWebSearchSettings {
    pub configured_mode: String,
    pub effective_mode: String,
    pub availability: String,
    pub context_size: Option<String>,
    pub allowed_domains: Vec<String>,
    pub country: Option<String>,
    pub region: Option<String>,
    pub city: Option<String>,
    pub timezone: Option<String>,
    pub account_id: Option<String>,
    pub model_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioDeepSeekWebSearchSettings {
    pub configured_enabled: bool,
    pub effective_enabled: bool,
    pub configured_fetch_enabled: bool,
    pub effective_fetch_enabled: bool,
    pub availability: String,
    pub account_id: Option<String>,
}
