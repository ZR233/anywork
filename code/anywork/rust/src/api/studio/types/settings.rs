use serde::{Deserialize, Serialize};

use super::{
    BridgeBillingKind, BridgeDelegationMode, BridgeDelegationPreference, BridgeDelegationSettings,
};
// ── Input types ──

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountSettingsInput {
    /// A single account edit.  Default account, mode routes and role routes
    /// have their own commands and are intentionally absent from this input.
    pub account: AccountInput,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoveAccountInput {
    #[serde(default)]
    pub replacement_account_id: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountInput {
    pub account_id: String,
    #[serde(default)]
    pub template_id: Option<String>,
    pub protocol: String,
    pub name: String,
    pub base_url: String,
    pub secret: AccountSecretInput,
    /// Initial override for account creation only; existing accounts use the narrow command.
    pub initial_billing_kind: Option<BridgeBillingKind>,
    pub custom_models: Vec<AccountModelInput>,
    pub model_connection_modes: Vec<AccountModelConnectionInput>,
    pub model_auto_compact_limits: Vec<AccountModelAutoCompactInput>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountModelInput {
    pub model_id: String,
    pub display_name: String,
    pub wire_api: String,
    pub context_window: Option<u64>,
    pub max_output_tokens: Option<u64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountModelConnectionInput {
    pub model_id: String,
    pub connection_mode: String,
}

/// 某模型上下文压缩阈值用户覆盖的输入项；`limit` 必须为正整数 tokens。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountModelAutoCompactInput {
    pub model_id: String,
    pub limit: u64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", tag = "scope")]
pub enum McpResetInput {
    Server { server_id: String },
    All,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", tag = "scope")]
pub enum LspScopeInput {
    Server {
        project_id: String,
        server_id: String,
    },
    Workspace {
        project_id: String,
    },
    All,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", tag = "action")]
pub enum AccountSecretInput {
    Preserve,
    Replace { value: String },
    Clear,
}

/// One settings field/resource mutation.  The bridge accepts exactly one
/// typed intent per call; the runtime fills all sibling values from its
/// canonical configuration.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum SettingsFieldInput {
    InstructionBaseOverride {
        value: String,
    },
    InstructionDeveloper {
        value: String,
    },
    InstructionUser {
        value: String,
    },
    ProjectDocMaxBytes {
        value: u64,
    },
    ProjectDocFallbackFilenames {
        value: Vec<String>,
    },
    SkillsEnabled {
        value: bool,
    },
    SkillsAutoLearn {
        value: bool,
    },
    SkillsSystemEnabled {
        value: bool,
    },
    SkillsProjectDir {
        value: String,
    },
    SkillsUserDir {
        value: String,
    },
    SkillsExternalDirs {
        value: Vec<String>,
    },
    SkillsDisabled {
        value: Vec<String>,
    },
    SkillsAutoLearnMinToolCalls {
        value: u32,
    },
    McpServerEnabled {
        id: String,
        value: bool,
    },
    McpServerTransport {
        id: String,
        transport: String,
    },
    McpServerEndpoint {
        id: String,
        endpoint: String,
    },
    GeneralFollowActiveTurn {
        value: bool,
    },
    GeneralCompactTimeline {
        value: bool,
    },
    GeneralSidebarWidth {
        value: Option<u16>,
    },
    GeneralPinnedThreadIds {
        value: Vec<String>,
    },
    GeneralPinnedProjectIds {
        value: Vec<String>,
    },
    WebSearchMode {
        value: String,
    },
    WebSearchContextSize {
        value: Option<String>,
    },
    WebSearchAllowedDomains {
        value: Vec<String>,
    },
    WebSearchCountry {
        value: Option<String>,
    },
    WebSearchRegion {
        value: Option<String>,
    },
    WebSearchCity {
        value: Option<String>,
    },
    WebSearchTimezone {
        value: Option<String>,
    },
    DeepSeekWebSearchEnabled {
        value: bool,
    },
    DeepSeekWebFetchEnabled {
        value: bool,
    },
    ModeModel {
        mode_id: String,
        account_id: String,
        model_id: String,
    },
    ModeReasoningEffort {
        mode_id: String,
        effort: Option<String>,
    },
    RoleModel {
        role: String,
        account_id: String,
        model_id: String,
    },
    RoleReasoningEffort {
        role: String,
        effort: Option<String>,
    },
    DelegationMode {
        value: BridgeDelegationMode,
    },
    DelegationPreference {
        value: BridgeDelegationPreference,
    },
}

impl From<SettingsFieldInput> for pl_protocol::studio::SettingsFieldUpdate {
    fn from(value: SettingsFieldInput) -> Self {
        use pl_protocol::studio::SettingsFieldUpdate as Update;
        match value {
            SettingsFieldInput::InstructionBaseOverride { value } => {
                Update::InstructionBaseOverride { value }
            }
            SettingsFieldInput::InstructionDeveloper { value } => {
                Update::InstructionDeveloper { value }
            }
            SettingsFieldInput::InstructionUser { value } => Update::InstructionUser { value },
            SettingsFieldInput::ProjectDocMaxBytes { value } => {
                Update::ProjectDocMaxBytes { value }
            }
            SettingsFieldInput::ProjectDocFallbackFilenames { value } => {
                Update::ProjectDocFallbackFilenames { value }
            }
            SettingsFieldInput::SkillsEnabled { value } => Update::SkillsEnabled { value },
            SettingsFieldInput::SkillsAutoLearn { value } => Update::SkillsAutoLearn { value },
            SettingsFieldInput::SkillsSystemEnabled { value } => {
                Update::SkillsSystemEnabled { value }
            }
            SettingsFieldInput::SkillsProjectDir { value } => Update::SkillsProjectDir { value },
            SettingsFieldInput::SkillsUserDir { value } => Update::SkillsUserDir { value },
            SettingsFieldInput::SkillsExternalDirs { value } => {
                Update::SkillsExternalDirs { value }
            }
            SettingsFieldInput::SkillsDisabled { value } => Update::SkillsDisabled { value },
            SettingsFieldInput::SkillsAutoLearnMinToolCalls { value } => {
                Update::SkillsAutoLearnMinToolCalls { value }
            }
            SettingsFieldInput::McpServerEnabled { id, value } => {
                Update::McpServerEnabled { id, value }
            }
            SettingsFieldInput::McpServerTransport { id, transport } => {
                Update::McpServerTransport { id, transport }
            }
            SettingsFieldInput::McpServerEndpoint { id, endpoint } => {
                Update::McpServerEndpoint { id, endpoint }
            }
            SettingsFieldInput::GeneralFollowActiveTurn { value } => {
                Update::GeneralFollowActiveTurn { value }
            }
            SettingsFieldInput::GeneralCompactTimeline { value } => {
                Update::GeneralCompactTimeline { value }
            }
            SettingsFieldInput::GeneralSidebarWidth { value } => {
                Update::GeneralSidebarWidth { value }
            }
            SettingsFieldInput::GeneralPinnedThreadIds { value } => {
                Update::GeneralPinnedThreadIds { value }
            }
            SettingsFieldInput::GeneralPinnedProjectIds { value } => {
                Update::GeneralPinnedProjectIds { value }
            }
            SettingsFieldInput::WebSearchMode { value } => Update::WebSearchMode { value },
            SettingsFieldInput::WebSearchContextSize { value } => {
                Update::WebSearchContextSize { value }
            }
            SettingsFieldInput::WebSearchAllowedDomains { value } => {
                Update::WebSearchAllowedDomains { value }
            }
            SettingsFieldInput::WebSearchCountry { value } => Update::WebSearchCountry { value },
            SettingsFieldInput::WebSearchRegion { value } => Update::WebSearchRegion { value },
            SettingsFieldInput::WebSearchCity { value } => Update::WebSearchCity { value },
            SettingsFieldInput::WebSearchTimezone { value } => Update::WebSearchTimezone { value },
            SettingsFieldInput::DeepSeekWebSearchEnabled { value } => {
                Update::DeepSeekWebSearchEnabled { value }
            }
            SettingsFieldInput::DeepSeekWebFetchEnabled { value } => {
                Update::DeepSeekWebFetchEnabled { value }
            }
            SettingsFieldInput::ModeModel {
                mode_id,
                account_id,
                model_id,
            } => Update::ModeModel {
                mode_id,
                account_id,
                model_id,
            },
            SettingsFieldInput::ModeReasoningEffort { mode_id, effort } => {
                Update::ModeReasoningEffort { mode_id, effort }
            }
            SettingsFieldInput::RoleModel {
                role,
                account_id,
                model_id,
            } => Update::RoleModel {
                role,
                account_id,
                model_id,
            },
            SettingsFieldInput::RoleReasoningEffort { role, effort } => {
                Update::RoleReasoningEffort { role, effort }
            }
            SettingsFieldInput::DelegationMode { value } => Update::DelegationMode {
                value: value.into(),
            },
            SettingsFieldInput::DelegationPreference { value } => Update::DelegationPreference {
                value: value.into(),
            },
        }
    }
}

/// Web 搜索配置、有效状态和自动 OpenAI backend 的 canonical bridge 快照。
#[derive(Debug, Clone, serde::Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeWebSearchSettingsDto {
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

/// DeepSeek 原生 Web 搜索的 canonical bridge 快照。
#[derive(Debug, Clone, serde::Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeDeepSeekWebSearchSettingsDto {
    pub configured_enabled: bool,
    pub effective_enabled: bool,
    pub configured_fetch_enabled: bool,
    pub effective_fetch_enabled: bool,
    pub availability: String,
    pub account_id: Option<String>,
}

/// Studio 配置与本地界面设置的 canonical typed 快照。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeStudioSettingsDto {
    pub default_account_id: Option<String>,
    pub accounts: Vec<BridgeAccountSettingsDto>,
    /// ACP 接入的 desired 配置；与 Native `accounts` 是两套语义。
    pub acp_accounts: Vec<super::BridgeAcpAccountSettings>,
    pub mode_model_routes: Vec<BridgeModeModelSettingsDto>,
    pub roles: Vec<BridgeRoleSettingsDto>,
    pub permission_mode: String,
    pub instructions: BridgeInstructionsSettingsDto,
    pub skills: BridgeSkillsSettingsDto,
    pub mcp_servers: Vec<BridgeMcpServerSettingsDto>,
    pub general: BridgeGeneralSettingsDto,
    pub delegation: BridgeDelegationSettings,
    pub web_search: BridgeWebSearchSettingsDto,
    pub deepseek_web_search: BridgeDeepSeekWebSearchSettingsDto,
}

/// Thread Mode 到默认 account/model/effort 的 canonical 路由。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModeModelSettingsDto {
    pub mode_id: String,
    pub account_id: String,
    pub model_id: String,
    pub effort: String,
}

/// 不含 secret 的 Account canonical 设置视图。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeAccountSettingsDto {
    pub billing_kind: BridgeBillingKind,
    pub billing_kind_override: Option<BridgeBillingKind>,
    pub disabled_models: Vec<String>,
    pub account_id: String,
    /// 可选的内置账号模板引用；完全自定义账号为 `None`。
    pub template_id: Option<String>,
    /// 明确的厂商协议适配选择。
    pub protocol: String,
    pub name: String,
    pub base_url: String,
    pub has_bearer_token: bool,
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
    pub custom_models: Vec<BridgeCustomModelSettingsDto>,
    pub model_connection_modes: Vec<BridgeModelConnectionSettingsDto>,
    pub model_auto_compact_limits: Vec<BridgeModelAutoCompactSettingsDto>,
    pub catalog_id: Option<String>,
}

/// A account's observed model directory. This belongs to the catalog clock,
/// not to the account configuration snapshot.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelCatalogAccountDto {
    pub account_id: String,
    pub effective_models: Vec<BridgeModelDescriptor>,
    pub model_catalog: BridgeModelCatalogStatusDto,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelCatalogStatusDto {
    pub supported: bool,
    pub source: BridgeModelCatalogSource,
    pub probing: bool,
    pub last_success_at: Option<i64>,
    pub checked_at: Option<i64>,
    pub error: Option<BridgeModelCatalogError>,
    pub cache_warning: Option<BridgeModelCatalogCacheWarning>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeModelCatalogSource {
    Default,
    Cached,
    Online,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum BridgeModelCatalogError {
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

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeModelCatalogCacheWarning {
    Read,
    Schema,
    Identity,
    Declaration,
}

/// Effective catalog membership origin. Names match `ModelOriginDto`.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeModelOrigin {
    Bundled,
    Online,
    Manual,
}

impl From<pl_protocol::ModelOriginDto> for BridgeModelOrigin {
    fn from(origin: pl_protocol::ModelOriginDto) -> Self {
        match origin {
            pl_protocol::ModelOriginDto::Bundled => Self::Bundled,
            pl_protocol::ModelOriginDto::Online => Self::Online,
            pl_protocol::ModelOriginDto::Manual => Self::Manual,
        }
    }
}

impl From<pl_protocol::studio::StudioModelCatalogStatus> for BridgeModelCatalogStatusDto {
    fn from(status: pl_protocol::studio::StudioModelCatalogStatus) -> Self {
        use pl_protocol::studio::{
            StudioModelCatalogCacheWarning as Warning, StudioModelCatalogError as Error,
            StudioModelCatalogSource as Source,
        };
        Self {
            supported: status.supported,
            source: match status.source {
                Source::Default => BridgeModelCatalogSource::Default,
                Source::Cached => BridgeModelCatalogSource::Cached,
                Source::Online => BridgeModelCatalogSource::Online,
            },
            probing: status.probing,
            last_success_at: status.last_success_at,
            checked_at: status.checked_at,
            error: status.error.map(|error| match error {
                Error::Unsupported => BridgeModelCatalogError::Unsupported,
                Error::Configuration => BridgeModelCatalogError::Configuration,
                Error::Timeout => BridgeModelCatalogError::Timeout,
                Error::Transport { http_status } => {
                    BridgeModelCatalogError::Transport { http_status }
                }
                Error::Http { status } => BridgeModelCatalogError::Http { status },
                Error::TooLarge => BridgeModelCatalogError::TooLarge,
                Error::Protocol => BridgeModelCatalogError::Protocol,
                Error::CacheIdentity => BridgeModelCatalogError::CacheIdentity,
                Error::UnexpectedNotModified => BridgeModelCatalogError::UnexpectedNotModified,
                Error::CacheWrite => BridgeModelCatalogError::CacheWrite,
                Error::Closing => BridgeModelCatalogError::Closing,
            }),
            cache_warning: status.cache_warning.map(|warning| match warning {
                Warning::Read => BridgeModelCatalogCacheWarning::Read,
                Warning::Schema => BridgeModelCatalogCacheWarning::Schema,
                Warning::Identity => BridgeModelCatalogCacheWarning::Identity,
                Warning::Declaration => BridgeModelCatalogCacheWarning::Declaration,
            }),
        }
    }
}

/// Account 配置中由用户定义的模型，不复制内置 catalog 元数据。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeCustomModelSettingsDto {
    pub input_capabilities: Vec<BridgeModelInputCapability>,
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

/// Account 实例对 canonical catalog 模型的连接方式覆盖。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelConnectionSettingsDto {
    pub model_id: String,
    pub connection_mode: String,
}

/// account 实例中某模型上下文压缩阈值的三层 canonical 视图。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelAutoCompactSettingsDto {
    pub model_id: String,
    pub override_limit: Option<u64>,
}

/// 角色到 account/model/effort 的 canonical 路由。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeRoleSettingsDto {
    pub key: String,
    pub account_id: String,
    pub model_id: String,
    pub effort: String,
}

/// Instructions 页的 canonical 设置。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeInstructionsSettingsDto {
    pub base_override: String,
    pub developer: String,
    pub user: String,
    pub project_doc_max_bytes: u64,
    pub project_doc_fallback_filenames: Vec<String>,
}

/// Skills 页的 canonical 设置。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeSkillsSettingsDto {
    pub enabled: bool,
    pub auto_learn: bool,
    pub system_enabled: bool,
    pub project_dir: String,
    pub user_dir: String,
    pub external_dirs: Vec<String>,
    pub disabled: Vec<String>,
    pub auto_learn_min_tool_calls: u32,
}

/// MCP 设置页的 canonical server 视图。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeMcpServerSettingsDto {
    pub id: String,
    pub transport: String,
    pub endpoint: String,
    pub configuration: BridgeMcpServerConfiguration,
    pub source_kind: String,
    pub mutation_policy: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeMcpServerConfiguration {
    Enabled,
    Disabled,
    MissingCredential,
}

/// Flutter 本地通用设置的 typed 快照。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeGeneralSettingsDto {
    pub follow_active_turn: bool,
    pub compact_timeline: bool,
    #[serde(default)]
    pub sidebar_width: Option<u16>,
    #[serde(default)]
    pub pinned_thread_ids: Vec<String>,
    #[serde(default)]
    pub pinned_project_ids: Vec<String>,
}

impl Default for BridgeGeneralSettingsDto {
    fn default() -> Self {
        Self {
            follow_active_turn: true,
            compact_timeline: false,
            sidebar_width: None,
            pinned_thread_ids: Vec::new(),
            pinned_project_ids: Vec::new(),
        }
    }
}

// ── Account catalog output ──

#[derive(Debug, Clone)]
pub struct BridgeAccountCatalogSnapshot {
    pub schema_version: u32,
    pub revision: String,
    pub templates: Vec<BridgeAccountTemplateDescriptor>,
    pub model_catalogs: Vec<BridgeModelCatalogDescriptor>,
}

#[derive(Debug, Clone)]
pub struct BridgeAccountTemplateDescriptor {
    pub id: String,
    pub display_name: String,
    pub description: Option<String>,
    pub base_url: String,
    pub credential_label: String,
    pub credential_env: Option<String>,
    pub model_catalog_id: String,
    /// 模板默认的厂商协议；与 ProtocolKind 的 wire 值一致。
    pub protocol: String,
    pub suggested_model_id: String,
    pub icon_key: Option<String>,
    pub service_capabilities: BridgeServiceCapabilitiesDescriptor,
}

#[derive(Debug, Clone)]
pub struct BridgeServiceCapabilitiesDescriptor {
    pub web_search: BridgeWebSearchServiceCapabilitiesDescriptor,
    pub prompt_cache_dialect: String,
    pub responses_programmatic_tool_calling: bool,
}

#[derive(Debug, Clone)]
pub struct BridgeWebSearchServiceCapabilitiesDescriptor {
    pub hosted_responses: bool,
    pub hosted_dialect: String,
    pub standalone: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelTransportDescriptor {
    pub protocol: String,
    pub connection_modes: Vec<BridgeConnectionModeDescriptor>,
    pub default_connection_mode: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeConnectionModeDescriptor {
    pub id: String,
    pub display_name: String,
}

#[derive(Debug, Clone)]
pub struct BridgeModelCatalogDescriptor {
    pub id: String,
    pub models: Vec<BridgeModelDescriptor>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelDescriptor {
    pub model_id: String,
    pub enabled: bool,
    pub type_support: Vec<BridgeModelTypeSupport>,
    pub origin: BridgeModelOrigin,
    pub display_name: String,
    pub description: Option<String>,
    pub context_window: Option<u64>,
    pub max_context_window: Option<u64>,
    pub context: BridgeModelContextResolution,
    pub max_output_tokens: Option<u64>,
    pub transport: BridgeModelTransportDescriptor,
    pub capabilities: BridgeModelCapabilities,
    pub reasoning: Option<BridgeModelReasoningDescriptor>,
    pub pricing: Option<BridgeModelPricing>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelContextResolution {
    pub unavailable: Option<BridgeModelContextUnavailable>,
    pub context_window: Option<u64>,
    pub input_token_limit: Option<u64>,
    pub auto_compact_limit: Option<u64>,
    pub adjustment: Option<BridgeModelContextAdjustment>,
}
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeModelContextUnavailable {
    WindowUnknown,
    InvalidParameters,
    InputBudgetExhausted,
}
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeModelContextAdjustment {
    SafetyLimit,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeModelType {
    Text,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeModelTypeExclusion {
    TextInputUnsupported,
    TextOutputUnsupported,
    ContextWindowUnknown,
    ContextParametersInvalid,
    InputBudgetExhausted,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelTypeSupport {
    pub model_type: BridgeModelType,
    pub exclusions: Vec<BridgeModelTypeExclusion>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelCapabilities {
    pub input: Vec<BridgeModelInputCapability>,
    pub output: Vec<BridgeModelModality>,
    pub streaming: bool,
    pub temperature: bool,
    pub reasoning: bool,
    pub web_search: bool,
    pub function_calling: bool,
    pub parallel_tool_calls: bool,
    pub custom_tools: bool,
    pub freeform_tools: bool,
    pub instruction_snapshot_overrides: bool,
    pub native_context_family: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeModelModality {
    Text,
    Image,
    Audio,
    Video,
    File,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeModelInputSource {
    Local,
    RemoteUrl,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelInputCapability {
    pub modality: BridgeModelModality,
    pub sources: Vec<BridgeModelInputSource>,
    pub max_count: Option<u32>,
    pub max_bytes: Option<u64>,
    pub max_total_bytes: Option<u64>,
    pub max_width: Option<u32>,
    pub max_height: Option<u32>,
    pub media_types: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelReasoningDescriptor {
    pub parameter: String,
    pub label: String,
    pub default_candidate: Option<String>,
    pub candidates: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelPricing {
    pub currency: String,
    pub tiers: Vec<BridgeModelPriceTier>,
    pub source: String,
    pub verified_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeModelPriceTier {
    pub label: String,
    pub input_per_mtok: f64,
    pub output_per_mtok: f64,
    pub cache_read_per_mtok: Option<f64>,
    pub cache_write_per_mtok: Option<f64>,
}

impl From<pl_protocol::AccountCatalogSnapshot> for BridgeAccountCatalogSnapshot {
    fn from(snapshot: pl_protocol::AccountCatalogSnapshot) -> Self {
        Self {
            schema_version: snapshot.schema_version,
            revision: snapshot.revision,
            templates: snapshot
                .templates
                .into_iter()
                .map(|preset| BridgeAccountTemplateDescriptor {
                    id: preset.id,
                    display_name: preset.display_name,
                    description: preset.description,
                    base_url: preset.base_url,
                    credential_label: preset.credential.label,
                    credential_env: preset.credential.env_var,
                    model_catalog_id: preset.model_catalog_id,
                    protocol: preset.protocol,
                    suggested_model_id: preset.suggested_model_id,
                    icon_key: preset.icon_key,
                    service_capabilities: BridgeServiceCapabilitiesDescriptor {
                        web_search: BridgeWebSearchServiceCapabilitiesDescriptor {
                            hosted_responses: preset
                                .service_capabilities
                                .web_search
                                .hosted_responses,
                            hosted_dialect: preset.service_capabilities.web_search.hosted_dialect,
                            standalone: preset.service_capabilities.web_search.standalone,
                        },
                        prompt_cache_dialect: preset.service_capabilities.prompt_cache_dialect,
                        responses_programmatic_tool_calling: preset
                            .service_capabilities
                            .responses_programmatic_tool_calling,
                    },
                })
                .collect(),
            model_catalogs: snapshot
                .model_catalogs
                .into_values()
                .map(|catalog| BridgeModelCatalogDescriptor {
                    id: catalog.id,
                    models: catalog
                        .models
                        .into_iter()
                        .map(BridgeModelDescriptor::from)
                        .collect(),
                })
                .collect(),
        }
    }
}

impl From<pl_protocol::ModelDescriptor> for BridgeModelDescriptor {
    fn from(model: pl_protocol::ModelDescriptor) -> Self {
        Self {
            model_id: model.model_id,
            enabled: model.enabled,
            type_support: model
                .type_support
                .into_iter()
                .map(|support| BridgeModelTypeSupport {
                    model_type: match support.model_type {
                        pl_protocol::ModelType::Text => BridgeModelType::Text,
                    },
                    exclusions: support
                        .exclusions
                        .into_iter()
                        .map(|reason| match reason {
                            pl_protocol::ModelTypeExclusion::TextInputUnsupported => {
                                BridgeModelTypeExclusion::TextInputUnsupported
                            }
                            pl_protocol::ModelTypeExclusion::TextOutputUnsupported => {
                                BridgeModelTypeExclusion::TextOutputUnsupported
                            }
                            pl_protocol::ModelTypeExclusion::ContextParametersInvalid => {
                                BridgeModelTypeExclusion::ContextParametersInvalid
                            }
                            pl_protocol::ModelTypeExclusion::InputBudgetExhausted => {
                                BridgeModelTypeExclusion::InputBudgetExhausted
                            }
                            pl_protocol::ModelTypeExclusion::ContextWindowUnknown => {
                                BridgeModelTypeExclusion::ContextWindowUnknown
                            }
                        })
                        .collect(),
                })
                .collect(),
            origin: model.origin.into(),
            display_name: model.display_name,
            description: model.description,
            context_window: model.context_window,
            max_context_window: model.max_context_window,
            context: BridgeModelContextResolution {
                unavailable: model.context.unavailable.map(|reason| match reason {
                    pl_protocol::ModelContextUnavailable::WindowUnknown => {
                        BridgeModelContextUnavailable::WindowUnknown
                    }
                    pl_protocol::ModelContextUnavailable::InvalidParameters => {
                        BridgeModelContextUnavailable::InvalidParameters
                    }
                    pl_protocol::ModelContextUnavailable::InputBudgetExhausted => {
                        BridgeModelContextUnavailable::InputBudgetExhausted
                    }
                }),
                context_window: model.context.context_window,
                input_token_limit: model.context.input_token_limit,
                auto_compact_limit: model.context.auto_compact_limit,
                adjustment: model.context.adjustment.map(|reason| match reason {
                    pl_protocol::ModelContextAdjustment::SafetyLimit => {
                        BridgeModelContextAdjustment::SafetyLimit
                    }
                }),
            },
            max_output_tokens: model.max_output_tokens,
            transport: BridgeModelTransportDescriptor {
                protocol: model.transport.protocol,
                connection_modes: model
                    .transport
                    .connection_modes
                    .into_iter()
                    .map(|mode| BridgeConnectionModeDescriptor {
                        id: mode.id,
                        display_name: mode.display_name,
                    })
                    .collect(),
                default_connection_mode: model.transport.default_connection_mode,
            },
            capabilities: model.capabilities.into(),
            reasoning: model
                .reasoning
                .map(|reasoning| BridgeModelReasoningDescriptor {
                    parameter: reasoning.parameter,
                    label: reasoning.label,
                    default_candidate: reasoning.default,
                    candidates: reasoning.candidates,
                }),
            pricing: model.pricing.map(Into::into),
        }
    }
}

impl From<pl_protocol::ModelCapabilitiesDto> for BridgeModelCapabilities {
    fn from(value: pl_protocol::ModelCapabilitiesDto) -> Self {
        Self {
            input: value.input.into_iter().map(Into::into).collect(),
            output: value.output.into_iter().map(bridge_modality).collect(),
            streaming: value.streaming,
            temperature: value.temperature,
            reasoning: value.reasoning,
            web_search: value.web_search,
            function_calling: value.function_calling,
            parallel_tool_calls: value.parallel_tool_calls,
            custom_tools: value.custom_tools,
            freeform_tools: value.freeform_tools,
            instruction_snapshot_overrides: value.instruction_snapshot_overrides,
            native_context_family: value.native_context_family,
        }
    }
}

impl From<pl_protocol::ModelPricingDto> for BridgeModelPricing {
    fn from(value: pl_protocol::ModelPricingDto) -> Self {
        Self {
            currency: value.currency,
            source: value.source,
            verified_at: value.verified_at,
            tiers: value
                .tiers
                .into_iter()
                .map(|tier| BridgeModelPriceTier {
                    label: tier.label,
                    input_per_mtok: tier.input_per_mtok,
                    output_per_mtok: tier.output_per_mtok,
                    cache_read_per_mtok: tier.cache_read_per_mtok,
                    cache_write_per_mtok: tier.cache_write_per_mtok,
                })
                .collect(),
        }
    }
}

fn bridge_modality(modality: pl_protocol::ModelModalityDto) -> BridgeModelModality {
    match modality {
        pl_protocol::ModelModalityDto::Text => BridgeModelModality::Text,
        pl_protocol::ModelModalityDto::Image => BridgeModelModality::Image,
        pl_protocol::ModelModalityDto::Audio => BridgeModelModality::Audio,
        pl_protocol::ModelModalityDto::Video => BridgeModelModality::Video,
        pl_protocol::ModelModalityDto::File => BridgeModelModality::File,
    }
}

fn bridge_input_source(source: pl_protocol::ModelInputSourceDto) -> BridgeModelInputSource {
    match source {
        pl_protocol::ModelInputSourceDto::Local => BridgeModelInputSource::Local,
        pl_protocol::ModelInputSourceDto::RemoteUrl => BridgeModelInputSource::RemoteUrl,
    }
}

impl From<pl_protocol::ModelInputCapabilityDto> for BridgeModelInputCapability {
    fn from(capability: pl_protocol::ModelInputCapabilityDto) -> Self {
        Self {
            modality: bridge_modality(capability.modality),
            sources: capability
                .sources
                .into_iter()
                .map(bridge_input_source)
                .collect(),
            max_count: capability.max_count,
            max_bytes: capability.max_bytes,
            max_total_bytes: capability.max_total_bytes,
            max_width: capability.max_width,
            max_height: capability.max_height,
            media_types: capability.media_types,
        }
    }
}
