use anyhow::{Context, Result};
use pl_model::config::AccountModelCatalogConfig;
use pl_model::model::ModelInfo;
use pl_model::protocol::{ConnectionMode, WireApi};
use pl_protocol::products::configuration::{
    AccountConfiguration, ConfigurationValue, DeepSeekSearchConfiguration, WebSearchConfiguration,
};
use pl_protocol::studio::{
    AcpAccountSettings, StudioCustomModelSettings, StudioError, StudioErrorCode,
    StudioGeneralSettings, StudioInstructionsSettings, StudioMcpServerConfiguration,
    StudioMcpServerSettings, StudioModeModelSettings, StudioModelAutoCompactSettings,
    StudioModelConnectionSettings, StudioRoleSettings, StudioSkillsSettings,
};
use std::sync::Arc;

use crate::ConfigRuntimeSnapshot;

/// Read canonical desired fields directly. No Settings serialization, credentials or live handles
/// cross this boundary; only the credential-presence decision is retained.
pub(super) fn capture(
    snapshot: &ConfigRuntimeSnapshot,
    acp_accounts: std::result::Result<Arc<[AcpAccountSettings]>, Arc<StudioError>>,
) -> Result<ConfigurationValue> {
    let config = snapshot.canonical_config();
    let acp_accounts = acp_accounts.map_err(|error| anyhow::Error::new(error.as_ref().clone()))?;
    // 目录捕获值必须与同一 Settings 版本的接入集合逐项一致；不一致是协议失败，不能补齐。
    if acp_accounts.len() != config.acp.accounts.len()
        || acp_accounts
            .iter()
            .zip(config.acp.accounts.keys())
            .any(|(row, account_id)| &row.account_id != account_id)
    {
        return Err(anyhow::Error::new(StudioError::new(
            StudioErrorCode::Protocol,
            "ACP directory projection does not cover the committed Settings accounts",
            false,
        )));
    }
    let accounts = config
        .models
        .accounts
        .iter()
        .map(|(id, account)| {
            Ok(AccountConfiguration {
                billing_kind: account.billing_kind()?,
                billing_kind_override: account.billing_kind,
                disabled_models: account.disabled_models().iter().cloned().collect(),
                account_id: id.to_string(),
                template_id: account.template_id().map(ToString::to_string),
                protocol: account.protocol.as_str().to_owned(),
                name: account.name.clone(),
                base_url: account.base_url.clone(),
                has_bearer_token: account.resolved_bearer_token().is_some(),
                bearer_token_env: account.bearer_token_env.clone(),
                usage_query_revision: snapshot
                    .usage_query_revision(id)
                    .context("Configuration account usage identity is missing")?,
                custom_models: account.editable_models().iter().map(custom_model).collect(),
                model_connection_modes: account
                    .connection_overrides()
                    .iter()
                    .map(|(model_id, mode)| StudioModelConnectionSettings {
                        model_id: model_id.clone(),
                        connection_mode: connection(*mode).to_owned(),
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
                catalog_id: match &account.catalog {
                    AccountModelCatalogConfig::Bundled { catalog, .. } => Some(catalog.to_string()),
                    AccountModelCatalogConfig::Explicit { .. } => None,
                },
            })
        })
        .collect::<Result<Vec<_>>>()?;
    let location = config.web_search.location.as_ref();
    Ok(ConfigurationValue {
        default_account_id: config
            .mode_model_routes
            .get(&pl_protocol::ThreadModeId::simple())
            .map(|route| route.account_id.to_string()),
        accounts,
        acp_accounts: acp_accounts.to_vec(),
        mode_model_routes: config
            .mode_model_routes
            .iter()
            .map(|(mode, route)| StudioModeModelSettings {
                mode_id: mode.to_string(),
                account_id: route.account_id.to_string(),
                model_id: route.model_id.clone(),
                effort: route
                    .effort
                    .as_ref()
                    .map(|effort| effort.as_str().to_owned())
                    .unwrap_or_default(),
            })
            .collect(),
        // Missing role keys are meaningful; do not fabricate one row per well-known child role.
        roles: config
            .models
            .routes
            .iter()
            .map(|(role, route)| StudioRoleSettings {
                key: role.to_string(),
                account_id: route.account_id.to_string(),
                model_id: route.model_id.clone(),
                effort: route
                    .effort
                    .as_ref()
                    .map(|effort| effort.as_str().to_owned())
                    .unwrap_or_default(),
            })
            .collect(),
        permission_mode: config.runtime.permission_mode.label().to_owned(),
        instructions: StudioInstructionsSettings {
            base_override: config.instructions.base_override.clone(),
            developer: config.instructions.developer.clone(),
            user: config.instructions.user.clone(),
            project_doc_max_bytes: u64::try_from(config.instructions.project_doc_max_bytes)?,
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
            user_dir: config.skills.user_dir.clone(),
            external_dirs: config.skills.external_dirs.clone(),
            disabled: config.skills.disabled.clone(),
            auto_learn_min_tool_calls: config.skills.auto_learn_min_tool_calls,
        },
        mcp_servers: crate::config::effective_mcp_servers(config)
            .into_values()
            .map(|server| StudioMcpServerSettings {
                id: server.id,
                transport: server.config.transport.as_str().to_owned(),
                endpoint: server.config.endpoint_summary(),
                configuration: match server.status_kind {
                    pl_tool::mcp::config::McpServerStatusKind::Enabled => {
                        StudioMcpServerConfiguration::Enabled
                    }
                    pl_tool::mcp::config::McpServerStatusKind::Disabled => {
                        StudioMcpServerConfiguration::Disabled
                    }
                    pl_tool::mcp::config::McpServerStatusKind::MissingCredential => {
                        StudioMcpServerConfiguration::MissingCredential
                    }
                },
                source_kind: server.source_kind.as_str().to_owned(),
                mutation_policy: server.mutation_policy.as_str().to_owned(),
            })
            .collect(),
        general: StudioGeneralSettings {
            follow_active_turn: config.ui.follow_active_turn,
            compact_timeline: config.ui.compact_timeline,
            sidebar_width: config.ui.sidebar_width,
            pinned_thread_ids: config.ui.pinned_thread_ids.clone(),
            pinned_project_ids: config.ui.pinned_project_ids.clone(),
        },
        delegation: config.delegation,
        web_search: WebSearchConfiguration {
            configured_mode: match config.web_search.mode {
                pl_protocol::search::WebSearchMode::Disabled => "disabled",
                pl_protocol::search::WebSearchMode::Cached => "cached",
                pl_protocol::search::WebSearchMode::Indexed => "indexed",
                pl_protocol::search::WebSearchMode::Live => "live",
            }
            .to_owned(),
            context_size: config.web_search.context_size.map(|size| {
                match size {
                    pl_protocol::WebSearchContextSize::Low => "low",
                    pl_protocol::WebSearchContextSize::Medium => "medium",
                    pl_protocol::WebSearchContextSize::High => "high",
                }
                .to_owned()
            }),
            allowed_domains: config.web_search.allowed_domains.clone(),
            country: location.and_then(|location| location.country.clone()),
            region: location.and_then(|location| location.region.clone()),
            city: location.and_then(|location| location.city.clone()),
            timezone: location.and_then(|location| location.timezone.clone()),
        },
        deepseek_web_search: DeepSeekSearchConfiguration {
            configured_enabled: config.deepseek_web_search.enabled,
            configured_fetch_enabled: config.deepseek_web_search.fetch_enabled,
        },
    })
}

fn custom_model(model: &ModelInfo) -> StudioCustomModelSettings {
    StudioCustomModelSettings {
        input_capabilities: model.capabilities.input.iter().map(Into::into).collect(),
        context_window: model.context_window,
        max_output_tokens: model.max_output_tokens,
        model_id: model.model_id.clone(),
        display_name: model.display_name.clone(),
        reasoning_efforts: model
            .parameters
            .iter()
            .find(|parameter| parameter.name == "effort")
            .map(|parameter| parameter.candidates.clone())
            .unwrap_or_default(),
        base_instructions: model.base_instructions.clone(),
        wire_api: match model.binding.transport.protocol {
            WireApi::Responses => "responses",
            WireApi::ChatCompletions => "chat_completions",
        }
        .to_owned(),
        supported_connection_modes: model
            .binding
            .transport
            .supported_connection_modes
            .iter()
            .map(|mode| connection(*mode).to_owned())
            .collect(),
        default_connection_mode: connection(model.binding.transport.default_connection_mode)
            .to_owned(),
    }
}

fn connection(mode: ConnectionMode) -> &'static str {
    match mode {
        ConnectionMode::WebSocket => "web_socket",
        ConnectionMode::Http => "http",
    }
}
