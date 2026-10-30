use crate::api::studio::types::{
    AccountSecretInput, AccountSettingsInput, AccountUsageDto, BridgeAccountSettingsDto,
    BridgeAccountUsageData, BridgeAccountUsageState, BridgeCustomModelSettingsDto,
    BridgeDeepSeekWebSearchSettingsDto, BridgeGeneralSettingsDto, BridgeInstructionsSettingsDto,
    BridgeMcpServerConfiguration, BridgeMcpServerSettingsDto, BridgeModeModelSettingsDto,
    BridgeModelAutoCompactSettingsDto, BridgeModelCatalogAccountDto, BridgeModelCatalogSnapshotDto,
    BridgeModelConnectionSettingsDto, BridgeRoleSettingsDto, BridgeSettingsConfigSnapshotDto,
    BridgeSettingsStateResponse, BridgeSkillsSettingsDto, BridgeStudioSettingsDto,
    BridgeWebSearchSettingsDto, DeepSeekBalanceDto, DeepSeekBalanceInfoDto,
    ZhipuCodingPlanUsageDto, ZhipuQuotaLimitDto, ZhipuToolUsageDetailDto,
};
use pl_studio_runtime::{AccountUsageData, AccountUsageState, ZhipuQuotaWindow};

pub(crate) fn bridge_settings_snapshot(
    snapshot: pl_protocol::studio::SettingsStateResponse,
) -> BridgeSettingsStateResponse {
    BridgeSettingsStateResponse {
        config: bridge_settings_config_snapshot(snapshot.config),
        catalog: bridge_model_catalog_snapshot(snapshot.catalog),
    }
}

pub(crate) fn bridge_settings_config_snapshot(
    snapshot: pl_protocol::studio::SettingsConfigSnapshot,
) -> BridgeSettingsConfigSnapshotDto {
    BridgeSettingsConfigSnapshotDto {
        revision: snapshot.revision,
        updated_at: snapshot.updated_at,
        settings: bridge_settings(snapshot.settings),
    }
}

pub(crate) fn bridge_model_catalog_snapshot(
    snapshot: pl_protocol::studio::ModelCatalogSnapshot,
) -> BridgeModelCatalogSnapshotDto {
    BridgeModelCatalogSnapshotDto {
        revision: snapshot.revision,
        updated_at: snapshot.updated_at,
        accounts: snapshot
            .accounts
            .into_iter()
            .map(|account| BridgeModelCatalogAccountDto {
                account_id: account.account_id,
                effective_models: account
                    .effective_models
                    .into_iter()
                    .map(Into::into)
                    .collect(),
                model_catalog: account.model_catalog.into(),
            })
            .collect(),
    }
}

pub(crate) fn bridge_model_catalog_account(
    account: pl_protocol::studio::StudioAccountModelCatalog,
) -> BridgeModelCatalogAccountDto {
    BridgeModelCatalogAccountDto {
        account_id: account.account_id,
        effective_models: account
            .effective_models
            .into_iter()
            .map(Into::into)
            .collect(),
        model_catalog: account.model_catalog.into(),
    }
}

pub(crate) fn bridge_settings(
    settings: pl_protocol::studio::StudioSettings,
) -> BridgeStudioSettingsDto {
    BridgeStudioSettingsDto {
        default_account_id: settings.default_account_id,
        accounts: settings
            .accounts
            .into_iter()
            .map(bridge_account_settings)
            .collect(),
        acp_accounts: settings
            .acp_accounts
            .into_iter()
            .map(super::acp::bridge_acp_account_settings)
            .collect(),
        mode_model_routes: settings
            .mode_model_routes
            .into_iter()
            .map(|route| BridgeModeModelSettingsDto {
                mode_id: route.mode_id,
                account_id: route.account_id,
                model_id: route.model_id,
                effort: route.effort,
            })
            .collect(),
        roles: settings
            .roles
            .into_iter()
            .map(|role| BridgeRoleSettingsDto {
                key: role.key,
                account_id: role.account_id,
                model_id: role.model_id,
                effort: role.effort,
            })
            .collect(),
        permission_mode: settings.permission_mode,
        instructions: BridgeInstructionsSettingsDto {
            base_override: settings.instructions.base_override,
            developer: settings.instructions.developer,
            user: settings.instructions.user,
            project_doc_max_bytes: settings.instructions.project_doc_max_bytes,
            project_doc_fallback_filenames: settings.instructions.project_doc_fallback_filenames,
        },
        skills: BridgeSkillsSettingsDto {
            enabled: settings.skills.enabled,
            auto_learn: settings.skills.auto_learn,
            system_enabled: settings.skills.system_enabled,
            project_dir: settings.skills.project_dir,
            external_dirs: settings.skills.external_dirs,
            disabled: settings.skills.disabled,
            auto_learn_min_tool_calls: settings.skills.auto_learn_min_tool_calls,
        },
        mcp_servers: settings
            .mcp_servers
            .into_iter()
            .map(|server| BridgeMcpServerSettingsDto {
                id: server.id,
                transport: server.transport,
                endpoint: server.endpoint,
                configuration: match server.configuration {
                    pl_protocol::studio::StudioMcpServerConfiguration::Enabled => {
                        BridgeMcpServerConfiguration::Enabled
                    }
                    pl_protocol::studio::StudioMcpServerConfiguration::Disabled => {
                        BridgeMcpServerConfiguration::Disabled
                    }
                    pl_protocol::studio::StudioMcpServerConfiguration::MissingCredential => {
                        BridgeMcpServerConfiguration::MissingCredential
                    }
                },
                source_kind: server.source_kind,
                mutation_policy: server.mutation_policy,
            })
            .collect(),
        general: BridgeGeneralSettingsDto {
            follow_active_turn: settings.general.follow_active_turn,
            compact_timeline: settings.general.compact_timeline,
            sidebar_width: settings.general.sidebar_width,
            pinned_thread_ids: settings.general.pinned_thread_ids.clone(),
            pinned_project_ids: settings.general.pinned_project_ids.clone(),
        },
        delegation: super::super::types::BridgeDelegationSettings {
            mode: settings.delegation.mode.into(),
            preference: settings.delegation.preference.into(),
        },
        web_search: bridge_web_search_settings(settings.web_search),
        deepseek_web_search: bridge_deepseek_web_search_settings(settings.deepseek_web_search),
    }
}

pub(crate) fn bridge_web_search_settings(
    settings: pl_protocol::studio::StudioWebSearchSettings,
) -> BridgeWebSearchSettingsDto {
    BridgeWebSearchSettingsDto {
        configured_mode: settings.configured_mode,
        effective_mode: settings.effective_mode,
        availability: settings.availability,
        context_size: settings.context_size,
        allowed_domains: settings.allowed_domains,
        country: settings.country,
        region: settings.region,
        city: settings.city,
        timezone: settings.timezone,
        account_id: settings.account_id,
        model_id: settings.model_id,
    }
}

pub(crate) fn bridge_deepseek_web_search_settings(
    settings: pl_protocol::studio::StudioDeepSeekWebSearchSettings,
) -> BridgeDeepSeekWebSearchSettingsDto {
    BridgeDeepSeekWebSearchSettingsDto {
        configured_enabled: settings.configured_enabled,
        effective_enabled: settings.effective_enabled,
        configured_fetch_enabled: settings.configured_fetch_enabled,
        effective_fetch_enabled: settings.effective_fetch_enabled,
        availability: settings.availability,
        account_id: settings.account_id,
    }
}

fn bridge_custom_model_settings(
    model: pl_protocol::studio::StudioCustomModelSettings,
) -> BridgeCustomModelSettingsDto {
    BridgeCustomModelSettingsDto {
        input_capabilities: model
            .input_capabilities
            .into_iter()
            .map(Into::into)
            .collect(),
        context_window: model.context_window,
        max_output_tokens: model.max_output_tokens,
        model_id: model.model_id,
        display_name: model.display_name,
        reasoning_efforts: model.reasoning_efforts,
        base_instructions: model.base_instructions,
        wire_api: model.wire_api,
        supported_connection_modes: model.supported_connection_modes,
        default_connection_mode: model.default_connection_mode,
    }
}

pub(crate) fn account_settings_request(
    operation_id: String,
    expected_revision: u64,
    input: AccountSettingsInput,
) -> pl_protocol::studio::CreateAccountRequest {
    let account = input.account;
    pl_protocol::studio::CreateAccountRequest {
        operation_id,
        expected_revision,
        account: pl_protocol::studio::AccountSettingsUpdate {
            account_id: account.account_id,
            template_id: account.template_id,
            protocol: account.protocol,
            name: account.name,
            base_url: account.base_url,
            secret: match account.secret {
                AccountSecretInput::Preserve => pl_protocol::studio::AccountSecretUpdate::Preserve,
                AccountSecretInput::Replace { value } => {
                    pl_protocol::studio::AccountSecretUpdate::Replace { value }
                }
                AccountSecretInput::Clear => pl_protocol::studio::AccountSecretUpdate::Clear,
            },
            initial_billing_kind: account.initial_billing_kind.map(Into::into),
            custom_models: account
                .custom_models
                .into_iter()
                .map(|model| pl_protocol::studio::AccountModelUpdate {
                    model_id: model.model_id,
                    display_name: model.display_name,
                    wire_api: model.wire_api,
                    context_window: model.context_window,
                    max_output_tokens: model.max_output_tokens,
                })
                .collect(),
            model_connection_modes: account
                .model_connection_modes
                .into_iter()
                .map(|mode| pl_protocol::studio::AccountModelConnectionUpdate {
                    model_id: mode.model_id,
                    connection_mode: mode.connection_mode,
                })
                .collect(),
            model_auto_compact_limits: account
                .model_auto_compact_limits
                .into_iter()
                .map(|limit| pl_protocol::studio::AccountModelAutoCompactUpdate {
                    model_id: limit.model_id,
                    limit: limit.limit,
                })
                .collect(),
        },
    }
}
pub(crate) fn account_usage_dto(record: pl_studio_runtime::AccountUsageRecord) -> AccountUsageDto {
    let state = match record.state() {
        AccountUsageState::Unsupported(_) => BridgeAccountUsageState::Unsupported,
        AccountUsageState::MissingCredential(state) => BridgeAccountUsageState::MissingCredential {
            message: state.message().to_string(),
        },
        AccountUsageState::Failed(state) => BridgeAccountUsageState::Failed {
            error: state.error().into(),
        },
        AccountUsageState::Ready(state) => match state.data() {
            AccountUsageData::DeepSeekBalance(balance) => BridgeAccountUsageState::Ready {
                data: BridgeAccountUsageData::DeepSeekBalance(DeepSeekBalanceDto {
                    is_available: balance.is_available,
                    balances: balance
                        .balances
                        .iter()
                        .map(|item| DeepSeekBalanceInfoDto {
                            currency: item.currency.clone(),
                            total_balance: item.total_balance.clone(),
                            granted_balance: item.granted_balance.clone(),
                            topped_up_balance: item.topped_up_balance.clone(),
                        })
                        .collect(),
                }),
            },
            AccountUsageData::ZhipuCodingPlan(usage) => BridgeAccountUsageState::Ready {
                data: BridgeAccountUsageData::ZhipuCodingPlan(ZhipuCodingPlanUsageDto {
                    level: usage.level.clone(),
                    limits: usage
                        .limits
                        .iter()
                        .map(|limit| {
                            let (window, label) = zhipu_window_labels(&limit.window);
                            ZhipuQuotaLimitDto {
                                window: window.to_string(),
                                label: label.to_string(),
                                percentage: limit.percentage,
                                current_value: limit.current_value,
                                total: limit.total,
                                remaining: limit.remaining,
                                next_reset_at: limit.next_reset_at,
                                usage_details: limit
                                    .usage_details
                                    .iter()
                                    .map(|detail| ZhipuToolUsageDetailDto {
                                        name: detail.name.clone(),
                                        current_value: detail.current_value,
                                        total: detail.total,
                                        percentage: detail.percentage,
                                    })
                                    .collect(),
                            }
                        })
                        .collect(),
                }),
            },
        },
    };
    AccountUsageDto {
        account_id: record.account_id().to_string(),
        revision: record.revision(),
        updated_at: record.updated_at(),
        state,
    }
}

fn zhipu_window_labels(window: &ZhipuQuotaWindow) -> (&'static str, &str) {
    match window {
        ZhipuQuotaWindow::FiveHour => ("fiveHour", "5h"),
        ZhipuQuotaWindow::Weekly => ("weekly", "7d"),
        ZhipuQuotaWindow::McpMonthly => ("mcpMonthly", "MCP"),
        ZhipuQuotaWindow::Other(label) => ("other", label.as_str()),
    }
}

pub(crate) fn bridge_account_settings(
    account: pl_protocol::studio::StudioAccountSettings,
) -> BridgeAccountSettingsDto {
    BridgeAccountSettingsDto {
        billing_kind: account.billing_kind.into(),
        billing_kind_override: account.billing_kind_override.map(Into::into),
        model_enabled_overrides: account.model_enabled_overrides.into_iter().collect(),
        account_id: account.account_id,
        template_id: account.template_id,
        protocol: account.protocol,
        name: account.name,
        base_url: account.base_url,
        has_bearer_token: account.has_bearer_token,
        usage_query_revision: account.usage_query_revision,
        credential_required: account.credential_required,
        capability_source: account.capability_source,
        hosted_web_search: account.hosted_web_search,
        hosted_web_search_dialect: account.hosted_web_search_dialect,
        standalone_web_search: account.standalone_web_search,
        prompt_cache_dialect: account.prompt_cache_dialect,
        responses_programmatic_tool_calling: account.responses_programmatic_tool_calling,
        default_model_id: account.default_model_id,
        custom_models: account
            .custom_models
            .into_iter()
            .map(bridge_custom_model_settings)
            .collect(),
        model_connection_modes: account
            .model_connection_modes
            .into_iter()
            .map(|mode| BridgeModelConnectionSettingsDto {
                model_id: mode.model_id,
                connection_mode: mode.connection_mode,
            })
            .collect(),
        model_auto_compact_limits: account
            .model_auto_compact_limits
            .into_iter()
            .map(|limit| BridgeModelAutoCompactSettingsDto {
                model_id: limit.model_id,
                override_limit: limit.override_limit,
            })
            .collect(),
        catalog_id: account.catalog_id,
    }
}
