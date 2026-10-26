use super::super::configuration_pages::*;
use super::super::configuration_values::*;
use crate::api::studio::types::BridgeError;
use pl_protocol::products::{
    configuration as domain, read::configuration as protocol, read::configuration_pages as pages,
};

impl From<pl_protocol::DelegationSettings> for crate::api::studio::types::BridgeDelegationSettings {
    fn from(value: pl_protocol::DelegationSettings) -> Self {
        Self {
            mode: value.mode.into(),
            preference: value.preference.into(),
        }
    }
}
impl From<pl_protocol::studio::StudioMcpServerConfiguration>
    for crate::api::studio::types::BridgeMcpServerConfiguration
{
    fn from(value: pl_protocol::studio::StudioMcpServerConfiguration) -> Self {
        match value {
            pl_protocol::studio::StudioMcpServerConfiguration::Enabled => Self::Enabled,
            pl_protocol::studio::StudioMcpServerConfiguration::Disabled => Self::Disabled,
            pl_protocol::studio::StudioMcpServerConfiguration::MissingCredential => {
                Self::MissingCredential
            }
        }
    }
}

impl From<domain::ConfigurationRoleReadTarget> for BridgeConfigurationRoleReadTarget {
    fn from(value: domain::ConfigurationRoleReadTarget) -> Self {
        Self {
            reference: BridgeConfigurationRoleReadRef {
                entry: value.reference.entry,
                revision: value.reference.revision,
            },
            configuration: value.configuration.into(),
            catalog: value.catalog.into(),
            stamp: value.stamp.into(),
        }
    }
}
impl From<BridgeConfigurationRoleReadTarget> for domain::ConfigurationRoleReadTarget {
    fn from(value: BridgeConfigurationRoleReadTarget) -> Self {
        Self {
            reference: domain::ConfigurationRoleReadRef {
                entry: value.reference.entry,
                revision: value.reference.revision,
            },
            configuration: pl_protocol::products::references::ConfigurationReadTarget {
                origin: value.configuration.origin.into(),
                reference: value.configuration.reference.into(),
            },
            catalog: pl_protocol::products::references::ModelCatalogReadTarget {
                origin: value.catalog.origin.into(),
                reference: value.catalog.reference.into(),
            },
            stamp: pl_protocol::studio::ConfigProjectionStamp {
                settings_revision: value.stamp.settings_revision,
                model_catalog_revision: value.stamp.model_catalog_revision,
                closing: value.stamp.closing,
            },
        }
    }
}
impl From<domain::RoleRouteRead> for BridgeRoleRouteRead {
    fn from(value: domain::RoleRouteRead) -> Self {
        match value {
            domain::RoleRouteRead::Configured { route } => Self::Configured {
                route: BridgeConfiguredRoleRoute {
                    key: route.key,
                    account_id: route.account_id,
                    model_id: route.model_id,
                    effort: route.effort,
                },
            },
            domain::RoleRouteRead::Missing { suggestion } => Self::Missing {
                suggestion: suggestion.map(Into::into),
            },
        }
    }
}
impl From<domain::StartRouteIntent> for BridgeStartRouteIntent {
    fn from(value: domain::StartRouteIntent) -> Self {
        Self {
            mode: value.mode.to_string(),
            model: value.model.map(Into::into),
            effort: value.effort,
        }
    }
}
impl TryFrom<BridgeStartRouteIntent> for domain::StartRouteIntent {
    type Error = BridgeError;
    fn try_from(value: BridgeStartRouteIntent) -> Result<Self, Self::Error> {
        Ok(Self {
            mode: pl_protocol::ThreadModeId::new(value.mode).map_err(|_| {
                BridgeError::from(pl_protocol::studio::StudioError::invalid_argument(
                    "Invalid Start mode identity",
                ))
            })?,
            model: value
                .model
                .map(|model| pl_protocol::products::models::AccountModelKey {
                    account_id: model.account_id,
                    model_id: model.model_id,
                }),
            effort: value.effort,
        })
    }
}
impl From<domain::StartRouteQuery> for BridgeStartRouteQuery {
    fn from(value: domain::StartRouteQuery) -> Self {
        match value {
            domain::StartRouteQuery::Resolve { intent } => Self::Resolve {
                intent: intent.into(),
            },
            domain::StartRouteQuery::SelectModel { intent, selected } => Self::SelectModel {
                intent: intent.into(),
                selected: selected.into(),
            },
        }
    }
}
impl TryFrom<BridgeStartRouteQuery> for domain::StartRouteQuery {
    type Error = BridgeError;
    fn try_from(value: BridgeStartRouteQuery) -> Result<Self, Self::Error> {
        Ok(match value {
            BridgeStartRouteQuery::Resolve { intent } => Self::Resolve {
                intent: intent.try_into()?,
            },
            BridgeStartRouteQuery::SelectModel { intent, selected } => Self::SelectModel {
                intent: intent.try_into()?,
                selected: pl_protocol::products::models::AccountModelKey {
                    account_id: selected.account_id,
                    model_id: selected.model_id,
                },
            },
        })
    }
}
impl From<domain::StartRouteRead> for BridgeStartRouteRead {
    fn from(value: domain::StartRouteRead) -> Self {
        match value {
            domain::StartRouteRead::Ready {
                sources,
                query,
                intent,
                route,
                defaults,
            } => Self::Ready {
                sources: sources.into(),
                query: query.into(),
                intent: intent.into(),
                route: route.into(),
                defaults: defaults.into(),
            },
            domain::StartRouteRead::Unavailable {
                sources,
                query,
                intent,
                desired,
                defaults,
                error,
            } => Self::Unavailable {
                sources: sources.into(),
                query: query.into(),
                intent: intent.into(),
                desired: desired.map(Into::into),
                defaults: defaults.into(),
                error: error.into(),
            },
        }
    }
}

impl From<protocol::ConfigurationReadHeader> for BridgeConfigurationReadHeader {
    fn from(value: protocol::ConfigurationReadHeader) -> Self {
        Self {
            default_account_id: value.default_account_id.map(Into::into),
            accounts: value.accounts.into(),
            acp_accounts: value.acp_accounts.into(),
            mode_model_routes: value.mode_model_routes.into(),
            roles: value.roles.into(),
            permission_mode: value.permission_mode.into(),
            instructions: value.instructions.into(),
            skills: value.skills.into(),
            mcp_servers: value.mcp_servers.into(),
            general: value.general.into(),
            delegation: value.delegation.into(),
            web_search: value.web_search.into(),
            deepseek_web_search: value.deepseek_web_search.into(),
        }
    }
}
impl From<protocol::AcpAccountConfigurationRead> for BridgeAcpAccountConfigurationRead {
    fn from(value: protocol::AcpAccountConfigurationRead) -> Self {
        Self {
            account_id: value.account_id.into(),
            name: value.name.into(),
            provider: crate::api::studio::convert::acp::bridge_acp_provider(value.provider),
            connection_revision: value.connection_revision,
        }
    }
}
impl From<protocol::AccountConfigurationRead> for BridgeAccountConfigurationRead {
    fn from(value: protocol::AccountConfigurationRead) -> Self {
        Self {
            billing_kind: value.billing_kind.into(),
            billing_kind_override: value.billing_kind_override.map(Into::into),
            disabled_models: value.disabled_models.into(),
            account_id: value.account_id.into(),
            template_id: value.template_id.map(Into::into),
            protocol: value.protocol.into(),
            name: value.name.into(),
            base_url: value.base_url.into(),
            has_bearer_token: value.has_bearer_token,
            bearer_token_env: value.bearer_token_env.map(Into::into),
            usage_query_revision: value.usage_query_revision,
            custom_models: value.custom_models.into(),
            model_connection_modes: value.model_connection_modes.into(),
            model_auto_compact_limits: value.model_auto_compact_limits.into(),
            catalog_id: value.catalog_id.map(Into::into),
        }
    }
}
impl From<protocol::CustomModelConfigurationRead> for BridgeCustomModelConfigurationRead {
    fn from(value: protocol::CustomModelConfigurationRead) -> Self {
        Self {
            input_capabilities: value.input_capabilities.into(),
            context_window: value.context_window,
            max_output_tokens: value.max_output_tokens,
            model_id: value.model_id.into(),
            display_name: value.display_name.into(),
            reasoning_efforts: value.reasoning_efforts.into(),
            base_instructions: value.base_instructions.into(),
            wire_api: value.wire_api.into(),
            supported_connection_modes: value.supported_connection_modes.into(),
            default_connection_mode: value.default_connection_mode.into(),
        }
    }
}
impl From<protocol::ModelConnectionRead> for BridgeModelConnectionRead {
    fn from(value: protocol::ModelConnectionRead) -> Self {
        Self {
            model_id: value.model_id.into(),
            connection_mode: value.connection_mode.into(),
        }
    }
}
impl From<protocol::ModelAutoCompactRead> for BridgeModelAutoCompactRead {
    fn from(value: protocol::ModelAutoCompactRead) -> Self {
        Self {
            model_id: value.model_id.into(),
            override_limit: value.override_limit,
        }
    }
}
impl From<protocol::ModeModelRouteRead> for BridgeModeModelRouteRead {
    fn from(value: protocol::ModeModelRouteRead) -> Self {
        Self {
            mode_id: value.mode_id.into(),
            account_id: value.account_id.into(),
            model_id: value.model_id.into(),
            effort: value.effort.into(),
        }
    }
}
impl From<protocol::RoleModelRouteRead> for BridgeRoleModelRouteRead {
    fn from(value: protocol::RoleModelRouteRead) -> Self {
        Self {
            key: value.key.into(),
            account_id: value.account_id.into(),
            model_id: value.model_id.into(),
            effort: value.effort.into(),
        }
    }
}
impl From<protocol::InstructionsSettingsRead> for BridgeInstructionsSettingsRead {
    fn from(value: protocol::InstructionsSettingsRead) -> Self {
        Self {
            base_override: value.base_override.into(),
            developer: value.developer.into(),
            user: value.user.into(),
            project_doc_max_bytes: value.project_doc_max_bytes,
            project_doc_fallback_filenames: value.project_doc_fallback_filenames.into(),
        }
    }
}
impl From<protocol::SkillsSettingsRead> for BridgeSkillsSettingsRead {
    fn from(value: protocol::SkillsSettingsRead) -> Self {
        Self {
            enabled: value.enabled,
            auto_learn: value.auto_learn,
            system_enabled: value.system_enabled,
            project_dir: value.project_dir.into(),
            user_dir: value.user_dir.into(),
            external_dirs: value.external_dirs.into(),
            disabled: value.disabled.into(),
            auto_learn_min_tool_calls: value.auto_learn_min_tool_calls,
        }
    }
}
impl From<protocol::McpConfigurationRead> for BridgeMcpConfigurationRead {
    fn from(value: protocol::McpConfigurationRead) -> Self {
        Self {
            id: value.id.into(),
            transport: value.transport.into(),
            endpoint: value.endpoint.into(),
            configuration: value.configuration.into(),
            source_kind: value.source_kind.into(),
            mutation_policy: value.mutation_policy.into(),
        }
    }
}
impl From<protocol::GeneralSettingsRead> for BridgeGeneralSettingsRead {
    fn from(value: protocol::GeneralSettingsRead) -> Self {
        Self {
            follow_active_turn: value.follow_active_turn,
            compact_timeline: value.compact_timeline,
            sidebar_width: value.sidebar_width,
            pinned_thread_ids: value.pinned_thread_ids.into(),
            pinned_project_ids: value.pinned_project_ids.into(),
        }
    }
}
impl From<protocol::WebSearchConfigurationRead> for BridgeWebSearchConfigurationRead {
    fn from(value: protocol::WebSearchConfigurationRead) -> Self {
        Self {
            configured_mode: value.configured_mode.into(),
            context_size: value.context_size.map(Into::into),
            allowed_domains: value.allowed_domains.into(),
            country: value.country.map(Into::into),
            region: value.region.map(Into::into),
            city: value.city.map(Into::into),
            timezone: value.timezone.map(Into::into),
        }
    }
}
impl From<protocol::DeepSeekSearchConfigurationRead> for BridgeDeepSeekSearchConfigurationRead {
    fn from(value: protocol::DeepSeekSearchConfigurationRead) -> Self {
        Self {
            configured_enabled: value.configured_enabled,
            configured_fetch_enabled: value.configured_fetch_enabled,
        }
    }
}

impl From<pages::ConfigurationEntryPage> for BridgeConfigurationEntryPage {
    fn from(value: pages::ConfigurationEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}
impl From<pages::ConfigurationEntityRead> for BridgeConfigurationEntityRead {
    fn from(value: pages::ConfigurationEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}

// These concrete pages have identical envelopes, not erased business values or a new codec.
macro_rules! page {
    ($protocol:ident, $bridge:ident) => {
        impl From<pages::$protocol> for $bridge {
            fn from(value: pages::$protocol) -> Self {
                Self {
                    list_id: value.list_id,
                    offset: value.offset,
                    total: value.total,
                    items: value.items.into_iter().map(Into::into).collect(),
                    next_offset: value.next_offset,
                }
            }
        }
    };
}
page!(
    AccountConfigurationReadPage,
    BridgeAccountConfigurationReadPage
);
page!(
    AcpAccountConfigurationReadPage,
    BridgeAcpAccountConfigurationReadPage
);
page!(
    CustomModelConfigurationReadPage,
    BridgeCustomModelConfigurationReadPage
);
page!(ModelConnectionReadPage, BridgeModelConnectionReadPage);
page!(ModelAutoCompactReadPage, BridgeModelAutoCompactReadPage);
page!(ModeModelRouteReadPage, BridgeModeModelRouteReadPage);
page!(RoleModelRouteReadPage, BridgeRoleModelRouteReadPage);
page!(McpConfigurationReadPage, BridgeMcpConfigurationReadPage);
