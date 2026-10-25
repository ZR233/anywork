use super::super::references::{BridgeConfigurationReadTarget, BridgeModelCatalogReadTarget};
use super::primitives::{BridgeAccountModelKey, BridgeModelSelection};
use crate::api::studio::conversation::identity::BridgeConfigProjectionStamp;
use crate::api::studio::observation::{BridgeReadText, BridgeTypedListRef};
use crate::api::studio::types::{
    BridgeBillingKind, BridgeDelegationSettings, BridgeError, BridgeMcpServerConfiguration,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeConfigurationRoleReadRef {
    pub entry: u64,
    pub revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConfigurationRoleReadTarget {
    pub reference: BridgeConfigurationRoleReadRef,
    pub configuration: BridgeConfigurationReadTarget,
    pub catalog: BridgeModelCatalogReadTarget,
    pub stamp: BridgeConfigProjectionStamp,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConfiguredRoleRoute {
    pub key: String,
    pub account_id: String,
    pub model_id: String,
    pub effort: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeRoleRouteRead {
    Configured {
        route: BridgeConfiguredRoleRoute,
    },
    Missing {
        suggestion: Option<BridgeModelSelection>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeStartRouteIntent {
    pub mode: String,
    pub model: Option<BridgeAccountModelKey>,
    pub effort: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeStartRouteQuery {
    Resolve {
        intent: BridgeStartRouteIntent,
    },
    SelectModel {
        intent: BridgeStartRouteIntent,
        selected: BridgeAccountModelKey,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeStartRouteRead {
    Ready {
        sources: BridgeConfigurationRoleReadTarget,
        query: BridgeStartRouteQuery,
        intent: BridgeStartRouteIntent,
        route: BridgeModelSelection,
        defaults: BridgeDelegationSettings,
    },
    Unavailable {
        sources: BridgeConfigurationRoleReadTarget,
        query: BridgeStartRouteQuery,
        intent: BridgeStartRouteIntent,
        desired: Option<BridgeModelSelection>,
        defaults: BridgeDelegationSettings,
        error: BridgeError,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConfigurationReadHeader {
    pub default_account_id: Option<BridgeReadText>,
    pub accounts: BridgeTypedListRef,
    pub mode_model_routes: BridgeTypedListRef,
    pub roles: BridgeTypedListRef,
    pub permission_mode: BridgeReadText,
    pub instructions: BridgeInstructionsSettingsRead,
    pub skills: BridgeSkillsSettingsRead,
    pub mcp_servers: BridgeTypedListRef,
    pub general: BridgeGeneralSettingsRead,
    pub delegation: BridgeDelegationSettings,
    pub web_search: BridgeWebSearchConfigurationRead,
    pub deepseek_web_search: BridgeDeepSeekSearchConfigurationRead,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountConfigurationRead {
    pub pricing_enabled: bool,
    pub billing_kind: BridgeBillingKind,
    pub billing_kind_override: Option<BridgeBillingKind>,
    pub disabled_models: BridgeTypedListRef,
    pub account_id: BridgeReadText,
    pub template_id: Option<BridgeReadText>,
    pub protocol: BridgeReadText,
    pub name: BridgeReadText,
    pub base_url: BridgeReadText,
    pub has_bearer_token: bool,
    /// 凭据来源环境变量名（非凭据值）；`None` 表示该账号不使用环境变量凭据。
    pub bearer_token_env: Option<BridgeReadText>,
    pub usage_query_revision: u64,
    pub custom_models: BridgeTypedListRef,
    pub model_connection_modes: BridgeTypedListRef,
    pub model_auto_compact_limits: BridgeTypedListRef,
    pub catalog_id: Option<BridgeReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCustomModelConfigurationRead {
    pub input_capabilities: BridgeTypedListRef,
    pub context_window: Option<u64>,
    pub max_output_tokens: Option<u64>,
    pub model_id: BridgeReadText,
    pub display_name: BridgeReadText,
    pub reasoning_efforts: BridgeTypedListRef,
    pub base_instructions: BridgeReadText,
    pub wire_api: BridgeReadText,
    pub supported_connection_modes: BridgeTypedListRef,
    pub default_connection_mode: BridgeReadText,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelConnectionRead {
    pub model_id: BridgeReadText,
    pub connection_mode: BridgeReadText,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelAutoCompactRead {
    pub model_id: BridgeReadText,
    pub override_limit: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModeModelRouteRead {
    pub mode_id: BridgeReadText,
    pub account_id: BridgeReadText,
    pub model_id: BridgeReadText,
    pub effort: BridgeReadText,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRoleModelRouteRead {
    pub key: BridgeReadText,
    pub account_id: BridgeReadText,
    pub model_id: BridgeReadText,
    pub effort: BridgeReadText,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeInstructionsSettingsRead {
    pub base_override: BridgeReadText,
    pub developer: BridgeReadText,
    pub user: BridgeReadText,
    pub project_doc_max_bytes: u64,
    pub project_doc_fallback_filenames: BridgeTypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillsSettingsRead {
    pub enabled: bool,
    pub auto_learn: bool,
    pub system_enabled: bool,
    pub project_dir: BridgeReadText,
    pub user_dir: BridgeReadText,
    pub external_dirs: BridgeTypedListRef,
    pub disabled: BridgeTypedListRef,
    pub auto_learn_min_tool_calls: u32,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMcpConfigurationRead {
    pub id: BridgeReadText,
    pub transport: BridgeReadText,
    pub endpoint: BridgeReadText,
    pub configuration: BridgeMcpServerConfiguration,
    pub source_kind: BridgeReadText,
    pub mutation_policy: BridgeReadText,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeGeneralSettingsRead {
    pub follow_active_turn: bool,
    pub compact_timeline: bool,
    pub sidebar_width: Option<u16>,
    pub pinned_thread_ids: BridgeTypedListRef,
    pub pinned_project_ids: BridgeTypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWebSearchConfigurationRead {
    pub configured_mode: BridgeReadText,
    pub context_size: Option<BridgeReadText>,
    pub allowed_domains: BridgeTypedListRef,
    pub country: Option<BridgeReadText>,
    pub region: Option<BridgeReadText>,
    pub city: Option<BridgeReadText>,
    pub timezone: Option<BridgeReadText>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeDeepSeekSearchConfigurationRead {
    pub configured_enabled: bool,
    pub configured_fetch_enabled: bool,
}
