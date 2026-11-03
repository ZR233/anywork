//! anywork 产品配置。
//!
//! `pl-model` 定义可 serde 的模型路由值对象；本模块组合 Studio 的运行时、
//! instructions、skills、MCP 与 UI 配置，并独占文件格式、schema 版本和默认角色。

pub mod acp;
mod agent_profile;
mod instruction;
mod profiles_resource;
pub use instruction::{DEFAULT_PROJECT_DOC_MAX_BYTES, InstructionsConfig};
mod bot_credentials;
mod chatgpt;
mod credential;
pub(crate) mod credential_commit;
mod document_migration;
mod execution;
pub mod mcp;
pub mod mcp_document;
pub mod mcp_resource;
pub use execution::RuntimeConfig;
pub(crate) mod model_catalog;
mod runtime;
pub(crate) use runtime::CatalogChange;
mod schema_migration;
mod store;

use std::collections::{BTreeMap, BTreeSet};

use crate::{PureError, Result};
use pl_protocol::{ThreadModeId, search::WebSearchConfig};

use pl_tool::skill::SkillsConfig;

use pl_model::config::{AccountConfig, AgentModelConfig};
use serde::{Deserialize, Serialize};

pub use agent_profile::{
    AgentProfileCatalog, AgentProfileDiagnostic, UserAgentProfile, is_system_profile_id,
    resolve_profile_route, save_user_agent_profile, system_profile_ids,
};
pub(crate) use agent_profile::{
    effective_system_profile_route, system_agent_profile, system_agent_profiles,
    validate_user_agent_profile_id,
};
pub use mcp::{
    BuiltinMcpServerState as StudioBuiltinMcpServerState, build_builtin_effective_config,
    builtin_mcp_server_ids, is_builtin_mcp_server_id, zhipu_coding_plan_token,
};
pub use mcp_document::{
    ALL_BUILTIN_IDS, MCP_DOCUMENT_SCHEMA_VERSION, McpFileSpecV1, McpFileV1,
    validate_server_config_strict,
};
pub use mcp_resource::{
    McpCatalogResource, McpDocumentError, ResolvedThreadMcpServer, ScopedEffectiveMcpServer,
    ScopedMcpScan, canonical_document_ref, canonical_mcp_filename, document_revision,
    ensure_default_host_builtins_if_fresh, resolve_document_path,
    resolve_scoped_servers_for_thread, resolve_stdio_cwd, scan_scope_catalog, scope_dir,
};
pub use pl_tool::mcp::config::EffectiveMcpServerConfig;
pub use pl_tool::mcp::config::McpServerConfig as StudioMcpServerEntry;
pub use pl_tool::mcp::config::McpServerMutationPolicy;
pub use pl_tool::mcp::config::McpServerSourceKind;
pub use pl_tool::mcp::config::McpServerStatusKind;
pub use pl_tool::mcp::config::McpServerTransport;
pub use pl_tool::mcp::config::validate_mcp_identifier;
pub use profiles_resource::{AgentProfilesResource, AgentProfilesSnapshot};

pub use acp::{AcpAccountConfig, AcpConfig, AcpProvider};
pub(crate) use bot_credentials::{
    BotCredentialCapability, BotCredentialRef, BotCredentialRefKind, BotProtectedPayload,
    BotSecretVersion, SelectedBotCredential, try_decode_current_payload,
};
#[cfg(test)]
pub(crate) use credential::memory_faults;
pub(crate) use credential::{
    BotCredentialIoError, BotCredentialIoKind, BotProtectedPersist, BotProtectedRead,
};
pub use pl_model::config::{AccountId, AgentRoleId, ModelRouteConfig, ReasoningEffort};
pub(crate) use runtime::ModeDefinitionCommandOutcome;
pub(crate) use runtime::SettingsCommitObserver;
pub use runtime::{
    ConfigRuntime, ConfigRuntimeError, ConfigRuntimeSnapshot, ModelCatalogRuntimeSnapshot,
    ResolvedAgentProfile,
};
pub use store::{ConfigPaths, ConfigStore};

pub const STUDIO_CONFIG_SCHEMA_VERSION: u32 = 31;
pub const STUDIO_CONFIG_DIR_NAME: &str = ".anywork";
pub const STUDIO_CONFIG_FILE_NAME: &str = "config.toml";

const DEFAULT_ACCOUNT_ID: &str = "deepseek";
/// Historical root route identity; unlike Agent declarations it is not a child Profile.
pub(crate) const ROOT_AGENT_ROUTE_KEY: &str = "planner";

pub(crate) fn root_agent_route_id() -> AgentRoleId {
    AgentRoleId::new(ROOT_AGENT_ROUTE_KEY).expect("reserved root Agent route id must be valid")
}

pub use pl_protocol::WebSearchContextSize;
pub use pl_protocol::search::{WebSearchLocation, WebSearchMode};

/// Studio 自有的 LSP 自定义 server 配置段（`[lsp.servers.<id>]`）。
///
/// 声明在 catalog 之外启动的命令式语言服务器；与内置 catalog 合并时冲突 fail-loud。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudioLspConfig {
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub servers: BTreeMap<String, pl_lsp::catalog::LspUserServerConfig>,
}

impl StudioLspConfig {
    fn is_default(&self) -> bool {
        self.servers.is_empty()
    }
}

/// Studio UI 本地偏好，由 [`ConfigRuntime`] 与其余 desired settings 一起持有。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudioUiConfig {
    #[serde(default)]
    pub language: pl_protocol::studio::StudioUiLanguage,
    #[serde(default = "default_true")]
    pub follow_active_turn: bool,
    #[serde(default)]
    pub compact_timeline: bool,
    #[serde(default)]
    pub sidebar_width: Option<u16>,
    #[serde(default)]
    pub pinned_thread_ids: Vec<String>,
    #[serde(default)]
    pub pinned_project_ids: Vec<String>,
}

impl Default for StudioUiConfig {
    fn default() -> Self {
        Self {
            language: pl_protocol::studio::StudioUiLanguage::System,
            follow_active_turn: true,
            compact_timeline: false,
            sidebar_width: None,
            pinned_thread_ids: Vec::new(),
            pinned_project_ids: Vec::new(),
        }
    }
}

impl StudioUiConfig {
    fn is_default(&self) -> bool {
        self == &Self::default()
    }
}

const fn default_true() -> bool {
    true
}

/// DeepSeek Search & Fetch 的两个独立产品开关。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DeepSeekWebSearchConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_true")]
    pub fetch_enabled: bool,
}

impl Default for DeepSeekWebSearchConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            fetch_enabled: true,
        }
    }
}

/// anywork 的完整配置文档。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StudioConfig {
    pub schema_version: u32,
    pub models: AgentModelConfig,
    #[serde(default)]
    pub delegation: pl_protocol::DelegationSettings,
    #[serde(default)]
    pub mode_model_routes: BTreeMap<ThreadModeId, ModelRouteConfig>,
    /// Rust 内置 Agent 只能在这里禁用；其余字段不可覆盖，也不存在删除语义。
    #[serde(default, skip_serializing_if = "BTreeSet::is_empty")]
    pub disabled_system_agents: BTreeSet<String>,
    #[serde(default)]
    pub web_search: WebSearchConfig,
    #[serde(default)]
    pub deepseek_web_search: DeepSeekWebSearchConfig,
    #[serde(default, skip_serializing_if = "RuntimeConfig::is_empty")]
    pub runtime: RuntimeConfig,
    #[serde(default, skip_serializing_if = "InstructionsConfig::is_default")]
    pub instructions: InstructionsConfig,
    #[serde(default, skip_serializing_if = "SkillsConfig::is_default")]
    pub skills: SkillsConfig,
    #[serde(default, skip_serializing_if = "StudioLspConfig::is_default")]
    pub lsp: StudioLspConfig,
    #[serde(default, skip_serializing_if = "StudioUiConfig::is_default")]
    pub ui: StudioUiConfig,
    /// ACP 接入的 desired 配置；与 `models.accounts` 是两套语义，互不进入对方的候选。
    #[serde(default, skip_serializing_if = "acp::AcpConfig::is_empty")]
    pub acp: acp::AcpConfig,
}

impl StudioConfig {
    pub fn default_config() -> Result<Self> {
        let definition = pl_model::model::bundled_model_definition(DEFAULT_ACCOUNT_ID)?;
        let account_id =
            AccountId::new(DEFAULT_ACCOUNT_ID).expect("Studio 内置 account id 必须有效");
        let account = AccountConfig::deepseek_template();
        let route = ModelRouteConfig {
            account_id: account_id.clone(),
            model_id: definition.suggested_model,
            effort: definition.suggested_effort.map(ReasoningEffort::new),
        };
        Ok(Self {
            schema_version: STUDIO_CONFIG_SCHEMA_VERSION,
            delegation: pl_protocol::DelegationSettings::default(),
            models: AgentModelConfig {
                accounts: BTreeMap::from([(account_id, account)]),
                routes: BTreeMap::new(),
            },
            mode_model_routes: BTreeMap::from([
                (ThreadModeId::simple(), route.clone()),
                (ThreadModeId::task(), route),
            ]),
            disabled_system_agents: BTreeSet::new(),
            web_search: WebSearchConfig::default(),
            deepseek_web_search: DeepSeekWebSearchConfig::default(),
            runtime: RuntimeConfig::default(),
            instructions: InstructionsConfig::default(),
            skills: SkillsConfig::default(),
            lsp: StudioLspConfig::default(),
            ui: StudioUiConfig::default(),
            acp: acp::AcpConfig::default(),
        })
    }

    pub fn validate(&self) -> Result<()> {
        self.validate_declarations()?;
        self.models.validate()?;
        for route in self.mode_model_routes.values() {
            self.models.resolve_route(root_agent_route_id(), route)?;
        }
        Ok(())
    }

    /// Validates desired integrity while retaining externally unavailable selections.
    pub fn validate_declarations(&self) -> Result<()> {
        if self.schema_version != STUDIO_CONFIG_SCHEMA_VERSION {
            return Err(PureError::ConfigError(format!(
                "unsupported Studio config schema version: {}",
                self.schema_version
            )));
        }
        self.models.validate_declarations()?;
        let system_profile_ids = agent_profile::system_profile_ids()?;
        if let Some(profile_id) = self
            .disabled_system_agents
            .iter()
            .find(|profile_id| !system_profile_ids.contains(*profile_id))
        {
            return Err(PureError::ConfigError(format!(
                "disabled_system_agents contains unknown system Agent `{profile_id}`"
            )));
        }
        for (role, route) in &self.models.routes {
            if !system_profile_ids.contains(role.as_str()) {
                return Err(PureError::ConfigError(format!(
                    "models.routes contains unsupported child role: {role}"
                )));
            }
            self.models.route_availability(route)?;
        }
        if !self.mode_model_routes.contains_key(&ThreadModeId::simple())
            || !self.mode_model_routes.contains_key(&ThreadModeId::task())
        {
            return Err(PureError::ConfigError(
                "mode_model_routes must define mode.simple and mode.task".to_string(),
            ));
        }
        for route in self.mode_model_routes.values() {
            self.models.route_availability(route)?;
        }
        pl_tool::skill::validate_skills_config(&self.skills)?;
        validate_lsp_servers(&self.lsp.servers)?;
        acp::validate_acp_config(&self.acp)?;
        Ok(())
    }

    pub fn mode_model_route(&self, mode: &ThreadModeId) -> Result<&ModelRouteConfig> {
        self.mode_model_routes
            .get(mode)
            .or_else(|| self.mode_model_routes.get(&ThreadModeId::simple()))
            .ok_or_else(|| {
                PureError::ConfigError("missing model route for mode.simple".to_string())
            })
    }

    pub fn resolve_mode_model_route(
        &self,
        mode: &ThreadModeId,
    ) -> Result<pl_model::config::ResolvedModelRoute> {
        self.models
            .resolve_route(root_agent_route_id(), self.mode_model_route(mode)?)
    }
}

/// 校验自定义 LSP server 与内置 catalog 的合并结果；冲突 fail-loud。
fn validate_lsp_servers(
    servers: &BTreeMap<String, pl_lsp::catalog::LspUserServerConfig>,
) -> Result<()> {
    pl_lsp::catalog::LspServerCatalog::with_user_servers(servers)
        .map(|_| ())
        .map_err(|error| {
            PureError::ConfigError(format!("invalid [lsp.servers] configuration: {error}"))
        })
}
