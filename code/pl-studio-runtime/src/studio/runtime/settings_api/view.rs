//! Settings 只读投影：从 StudioConfig 派生 secret-free 的 snapshot 视图与展示标签。

use anyhow::{Context, Result};
use pl_model::model::ModelInfo;
use pl_model::protocol::{ConnectionMode, WireApi};
use pl_protocol::WebSearchContextSize;
use pl_protocol::search::WebSearchMode;
use pl_protocol::studio::{
    ModelCatalogSnapshot, SettingsConfigSnapshot, SettingsStateResponse, StudioAccountModelCatalog,
    StudioAccountSettings, StudioCustomModelSettings, StudioDeepSeekWebSearchSettings,
    StudioGeneralSettings, StudioInstructionsSettings, StudioMcpServerSettings,
    StudioModeModelSettings, StudioModelAutoCompactSettings, StudioModelConnectionSettings,
    StudioRoleSettings, StudioSettings, StudioSkillsSettings, StudioWebSearchSettings,
};

use crate::{ConfigRuntimeSnapshot, ModelCatalogRuntimeSnapshot};
use pl_model::config::{AccountCapabilitySelection, AccountModelCatalogConfig};
use pl_tool::search::{WebSearchAvailability, WebSearchDeepSeekOptions};

pub(crate) fn settings_config_snapshot(
    state: &ConfigRuntimeSnapshot,
    acp_accounts: Vec<pl_protocol::studio::AcpAccountSettings>,
) -> Result<SettingsConfigSnapshot> {
    Ok(SettingsConfigSnapshot {
        revision: state.revision,
        updated_at: state.updated_at,
        settings: settings_view(state, acp_accounts)?,
    })
}

pub(crate) fn model_catalog_snapshot(
    state: &ConfigRuntimeSnapshot,
    catalog: &ModelCatalogRuntimeSnapshot,
) -> Result<ModelCatalogSnapshot> {
    let accounts = state
        .config
        .models
        .accounts
        .iter()
        .map(|(id, account)| {
            let status = match catalog.catalogs.get(id).cloned() {
                Some(status) => status,
                None => pl_protocol::studio::StudioModelCatalogStatus {
                    query_generation: 0,
                    operation_id: None,
                    supported: account.discovery_profile()?.is_some(),
                    source: pl_protocol::studio::StudioModelCatalogSource::Default,
                    probing: false,
                    last_success_at: None,
                    checked_at: None,
                    error: None,
                    cache_warning: None,
                },
            };
            Ok(StudioAccountModelCatalog {
                account_id: id.to_string(),
                effective_models: account
                    .effective_catalog(None)?
                    .iter()
                    .map(pl_model::config::model_descriptor)
                    .collect(),
                model_catalog: status,
            })
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(ModelCatalogSnapshot {
        revision: catalog.revision,
        updated_at: catalog.updated_at,
        accounts,
    })
}

pub(crate) fn settings_state_response(
    state: &ConfigRuntimeSnapshot,
    catalog: &ModelCatalogRuntimeSnapshot,
    acp_accounts: Vec<pl_protocol::studio::AcpAccountSettings>,
) -> Result<SettingsStateResponse> {
    Ok(SettingsStateResponse {
        config: settings_config_snapshot(state, acp_accounts)?,
        catalog: model_catalog_snapshot(state, catalog)?,
    })
}

fn settings_view(
    state: &ConfigRuntimeSnapshot,
    acp_accounts: Vec<pl_protocol::studio::AcpAccountSettings>,
) -> Result<StudioSettings> {
    let config = state.canonical_config();
    let accounts = config
        .models
        .accounts
        .iter()
        .map(|(id, account)| account_settings(state, id, account))
        .collect::<Result<Vec<_>>>()?;
    let mode_model_routes = config
        .mode_model_routes
        .iter()
        .map(|(mode, route)| StudioModeModelSettings {
            mode_id: mode.to_string(),
            account_id: route.account_id.to_string(),
            model_id: route.model_id.clone(),
            effort: route
                .effort
                .as_ref()
                .map(|effort| effort.as_str().to_string())
                .unwrap_or_default(),
        })
        .collect();
    let roles = crate::config::system_agent_profiles(config)?
        .into_iter()
        .map(|profile| StudioRoleSettings {
            key: profile.profile_id,
            account_id: profile.account_id,
            model_id: profile.model_id,
            effort: profile.effort.unwrap_or_default(),
        })
        .collect();
    let mcp_servers = crate::config::effective_mcp_servers(config)
        .into_values()
        .map(|server| StudioMcpServerSettings {
            id: server.id,
            transport: server.config.transport.as_str().to_string(),
            endpoint: server.config.endpoint_summary(),
            configuration: match server.status_kind {
                pl_tool::mcp::config::McpServerStatusKind::Enabled => {
                    pl_protocol::studio::StudioMcpServerConfiguration::Enabled
                }
                pl_tool::mcp::config::McpServerStatusKind::Disabled => {
                    pl_protocol::studio::StudioMcpServerConfiguration::Disabled
                }
                pl_tool::mcp::config::McpServerStatusKind::MissingCredential => {
                    pl_protocol::studio::StudioMcpServerConfiguration::MissingCredential
                }
            },
            source_kind: server.source_kind.as_str().to_string(),
            mutation_policy: server.mutation_policy.as_str().to_string(),
        })
        .collect();
    let (web_search, deepseek_web_search) = search_settings(config)?;
    Ok(StudioSettings {
        delegation: config.delegation,
        default_account_id: config
            .mode_model_routes
            .get(&pl_protocol::ThreadModeId::simple())
            .map(|route| route.account_id.to_string()),
        accounts,
        acp_accounts,
        mode_model_routes,
        roles,
        permission_mode: config.runtime.permission_mode.label().to_string(),
        instructions: StudioInstructionsSettings {
            base_override: config.instructions.base_override.clone(),
            developer: config.instructions.developer.clone(),
            user: config.instructions.user.clone(),
            project_doc_max_bytes: config.instructions.project_doc_max_bytes as u64,
            project_doc_fallback_filenames: config
                .instructions
                .project_doc_fallback_filenames
                .clone(),
        },
        skills: StudioSkillsSettings {
            enabled: config.skills.enabled,
            auto_learn: config.skills.auto_learn,
            system_enabled: config.skills.system.enabled,
            project_dir: config.skills.project_dir.clone(),
            external_dirs: config.skills.external_dirs.clone(),
            disabled: config.skills.disabled.clone(),
            auto_learn_min_tool_calls: config.skills.auto_learn_min_tool_calls,
        },
        mcp_servers,
        general: StudioGeneralSettings {
            language: config.ui.language,
            follow_active_turn: config.ui.follow_active_turn,
            compact_timeline: config.ui.compact_timeline,
            sidebar_width: config.ui.sidebar_width,
            pinned_thread_ids: config.ui.pinned_thread_ids.clone(),
            pinned_project_ids: config.ui.pinned_project_ids.clone(),
        },
        web_search,
        deepseek_web_search,
    })
}

fn custom_model_settings(model: &ModelInfo) -> StudioCustomModelSettings {
    let reasoning_efforts = model
        .parameters
        .iter()
        .find(|parameter| parameter.name == "effort")
        .map(|parameter| parameter.candidates.as_slice())
        .unwrap_or_default();
    StudioCustomModelSettings {
        input_capabilities: model.capabilities.input.iter().map(Into::into).collect(),
        context_window: model.context_window,
        max_output_tokens: model.max_output_tokens,
        model_id: model.model_id.clone(),
        display_name: model.display_name.clone(),
        reasoning_efforts: reasoning_efforts.to_vec(),
        base_instructions: model.base_instructions.clone(),
        wire_api: match model.binding.transport.protocol {
            WireApi::Responses => "responses",
            WireApi::ChatCompletions => "chat_completions",
        }
        .to_string(),
        supported_connection_modes: model
            .binding
            .transport
            .supported_connection_modes
            .iter()
            .copied()
            .map(connection_mode_label)
            .map(str::to_string)
            .collect(),
        default_connection_mode: connection_mode_label(
            model.binding.transport.default_connection_mode,
        )
        .to_string(),
    }
}

fn search_settings(
    config: &crate::StudioConfig,
) -> Result<(StudioWebSearchSettings, StudioDeepSeekWebSearchSettings)> {
    // Search service availability is independent of any session/executor model; the shared
    // pl-tool service planner is the single source of truth used by Thread consumption too.
    let services = pl_tool::search::plan_web_search_services(
        &config.models,
        &config.web_search,
        &WebSearchDeepSeekOptions {
            enabled: config.deepseek_web_search.enabled,
            fetch_enabled: config.deepseek_web_search.fetch_enabled,
        },
    )?;
    let openai = services.openai.resolution;
    let deepseek = services.deepseek.resolution;
    let deepseek_available = deepseek.availability == WebSearchAvailability::Available;
    let location = config.web_search.location.as_ref();
    Ok((
        StudioWebSearchSettings {
            configured_mode: web_search_mode_label(openai.configured_mode).to_string(),
            effective_mode: web_search_mode_label(openai.effective_mode).to_string(),
            availability: web_search_availability_label(openai.availability).to_string(),
            context_size: config
                .web_search
                .context_size
                .map(|size| match size {
                    WebSearchContextSize::Low => "low",
                    WebSearchContextSize::Medium => "medium",
                    WebSearchContextSize::High => "high",
                })
                .map(str::to_string),
            allowed_domains: config.web_search.allowed_domains.clone(),
            country: location.and_then(|location| location.country.clone()),
            region: location.and_then(|location| location.region.clone()),
            city: location.and_then(|location| location.city.clone()),
            timezone: location.and_then(|location| location.timezone.clone()),
            account_id: openai.account_id.map(|account| account.to_string()),
            model_id: openai.model_id,
        },
        StudioDeepSeekWebSearchSettings {
            configured_enabled: config.deepseek_web_search.enabled,
            effective_enabled: config.deepseek_web_search.enabled && deepseek_available,
            configured_fetch_enabled: config.deepseek_web_search.fetch_enabled,
            effective_fetch_enabled: config.deepseek_web_search.fetch_enabled && deepseek_available,
            availability: web_search_availability_label(deepseek.availability).to_string(),
            account_id: deepseek.account_id.map(|account| account.to_string()),
        },
    ))
}

fn web_search_availability_label(availability: WebSearchAvailability) -> &'static str {
    match availability {
        WebSearchAvailability::Available => "available",
        WebSearchAvailability::Disabled => "disabled",
        WebSearchAvailability::MissingCredential => "missingCredential",
        WebSearchAvailability::AccountUnsupported => "accountUnsupported",
        WebSearchAvailability::ModelUnsupported => "modelUnsupported",
    }
}

pub(super) fn normalized_optional(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

pub(super) fn normalized_string_list(values: Vec<String>) -> Vec<String> {
    let mut values = values
        .into_iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();
    values.sort();
    values.dedup();
    values
}

fn web_search_mode_label(mode: WebSearchMode) -> &'static str {
    match mode {
        WebSearchMode::Disabled => "disabled",
        WebSearchMode::Cached => "cached",
        WebSearchMode::Indexed => "indexed",
        WebSearchMode::Live => "live",
    }
}

fn connection_mode_label(mode: ConnectionMode) -> &'static str {
    match mode {
        ConnectionMode::WebSocket => "web_socket",
        ConnectionMode::Http => "http",
    }
}

/// Projects only this account; list and usage observations never expand every model.
pub(crate) fn account_settings(
    state: &ConfigRuntimeSnapshot,
    id: &pl_model::config::AccountId,
    account: &pl_model::config::AccountConfig,
) -> Result<StudioAccountSettings> {
    let config = state.canonical_config();
    let models = account
        .effective_catalog(None)?
        .into_iter()
        .map(|entry| entry.model)
        .collect::<Vec<_>>();
    let default_model_id = config
        .models
        .routes
        .values()
        .find(|route| route.account_id == *id)
        .map(|route| route.model_id.clone())
        .or_else(|| models.first().map(|model| model.model_id.clone()))
        .unwrap_or_default();
    let service_capabilities = account.service_capabilities()?;
    let catalog_id = match &account.catalog {
        AccountModelCatalogConfig::Bundled { catalog, .. } => Some(catalog.to_string()),
        AccountModelCatalogConfig::Explicit { .. } => None,
    };
    Ok(StudioAccountSettings {
        billing_kind: account.billing_kind()?,
        billing_kind_override: account.billing_kind,
        model_enabled_overrides: account.model_enabled_overrides().clone(),
        account_id: id.to_string(),
        template_id: account.template_id().map(ToString::to_string),
        protocol: account.protocol.as_str().to_string(),
        name: account.name.clone(),
        base_url: account.base_url.clone(),
        has_bearer_token: account.resolved_bearer_token().is_some(),
        usage_query_revision: state
            .usage_query_revision(id)
            .context("account usage query identity is missing")?,
        credential_required: account.protocol != pl_model::protocol::ProtocolKind::OpenAiCompatible,
        capability_source: match &account.capabilities {
            AccountCapabilitySelection::TemplateDefaults => "template_defaults",
            AccountCapabilitySelection::Explicit(_) => "explicit",
        }
        .to_string(),
        hosted_web_search: service_capabilities.web_search.hosted_responses,
        hosted_web_search_dialect: service_capabilities
            .web_search
            .hosted_dialect
            .as_str()
            .to_string(),
        standalone_web_search: service_capabilities
            .web_search
            .standalone
            .map(|dialect| dialect.as_str().to_string()),
        prompt_cache_dialect: service_capabilities
            .prompt_cache
            .dialect
            .as_str()
            .to_string(),
        responses_programmatic_tool_calling: service_capabilities
            .responses_tools
            .programmatic_tool_calling,
        default_model_id,
        custom_models: account
            .editable_models()
            .iter()
            .map(custom_model_settings)
            .collect(),
        model_connection_modes: account
            .connection_overrides()
            .iter()
            .map(|(model_id, mode)| StudioModelConnectionSettings {
                model_id: model_id.clone(),
                connection_mode: connection_mode_label(*mode).to_string(),
            })
            .collect(),
        model_auto_compact_limits: account
            .auto_compact_overrides()
            .iter()
            .map(|(model_id, limit)| StudioModelAutoCompactSettings {
                model_id: model_id.clone(),
                override_limit: Some(*limit),
            })
            .collect(),
        catalog_id,
    })
}
