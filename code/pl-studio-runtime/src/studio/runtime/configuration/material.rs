use pl_protocol::products::configuration::ConfigurationValue;
use pl_protocol::products::read::configuration::*;
use pl_protocol::products::read::primitives::TypedListRef;
use pl_protocol::studio::{ReadText, StudioError, TextChunk};
use std::sync::Arc;

use super::super::read_budget::{FieldTable, bounded_header, count, text_chunk};
use super::fields::*;
use crate::config::ConfigurationMaterial;

pub(super) struct ConfigurationReadMaterial {
    pub(super) source: Arc<ConfigurationMaterial>,
    texts: FieldTable<TextField>,
    pub(super) lists: FieldTable<ListField>,
}

impl ConfigurationReadMaterial {
    pub(super) fn new(source: Arc<ConfigurationMaterial>) -> Self {
        Self {
            source,
            texts: FieldTable::default(),
            lists: FieldTable::default(),
        }
    }

    pub(super) fn value(&self) -> &ConfigurationValue {
        &self.source.value
    }

    pub(super) fn header(&self) -> Result<ConfigurationReadHeader, StudioError> {
        bounded_header(|inline| {
            let value = self.value();
            let text = |field| self.read(TextField::Root(field), inline);
            let strings = |kind| self.string_list(kind);
            Ok(ConfigurationReadHeader {
                default_account_id: value
                    .default_account_id
                    .as_ref()
                    .map(|_| text(RootText::DefaultAccount))
                    .transpose()?,
                accounts: self.list(ListField::Accounts, value.accounts.len())?,
                mode_model_routes: self.list(ListField::Modes, value.mode_model_routes.len())?,
                roles: self.list(ListField::Roles, value.roles.len())?,
                permission_mode: text(RootText::Permission)?,
                instructions: InstructionsSettingsRead {
                    base_override: text(RootText::BaseInstruction)?,
                    developer: text(RootText::Developer)?,
                    user: text(RootText::User)?,
                    project_doc_max_bytes: value.instructions.project_doc_max_bytes,
                    project_doc_fallback_filenames: strings(StringList::ProjectDocs)?,
                },
                skills: SkillsSettingsRead {
                    enabled: value.skills.enabled,
                    auto_learn: value.skills.auto_learn,
                    system_enabled: value.skills.system_enabled,
                    project_dir: text(RootText::SkillsProject)?,
                    user_dir: text(RootText::SkillsUser)?,
                    external_dirs: strings(StringList::SkillsExternal)?,
                    disabled: strings(StringList::SkillsDisabled)?,
                    auto_learn_min_tool_calls: value.skills.auto_learn_min_tool_calls,
                },
                mcp_servers: self.list(ListField::Mcp, value.mcp_servers.len())?,
                general: GeneralSettingsRead {
                    follow_active_turn: value.general.follow_active_turn,
                    compact_timeline: value.general.compact_timeline,
                    sidebar_width: value.general.sidebar_width,
                    pinned_thread_ids: strings(StringList::PinnedThreads)?,
                    pinned_project_ids: strings(StringList::PinnedProjects)?,
                },
                delegation: value.delegation,
                web_search: WebSearchConfigurationRead {
                    configured_mode: text(RootText::SearchMode)?,
                    context_size: value
                        .web_search
                        .context_size
                        .as_ref()
                        .map(|_| text(RootText::SearchContext))
                        .transpose()?,
                    allowed_domains: strings(StringList::SearchDomains)?,
                    country: value
                        .web_search
                        .country
                        .as_ref()
                        .map(|_| text(RootText::Country))
                        .transpose()?,
                    region: value
                        .web_search
                        .region
                        .as_ref()
                        .map(|_| text(RootText::Region))
                        .transpose()?,
                    city: value
                        .web_search
                        .city
                        .as_ref()
                        .map(|_| text(RootText::City))
                        .transpose()?,
                    timezone: value
                        .web_search
                        .timezone
                        .as_ref()
                        .map(|_| text(RootText::Timezone))
                        .transpose()?,
                },
                deepseek_web_search: DeepSeekSearchConfigurationRead {
                    configured_enabled: value.deepseek_web_search.configured_enabled,
                    configured_fetch_enabled: value.deepseek_web_search.configured_fetch_enabled,
                },
            })
        })
    }

    pub(super) fn account(
        &self,
        index: usize,
    ) -> Result<&pl_protocol::products::configuration::AccountConfiguration, StudioError> {
        self.value().accounts.get(index).ok_or_else(wrong_field)
    }

    pub(super) fn model(
        &self,
        path: ModelPath,
    ) -> Result<&pl_protocol::studio::StudioCustomModelSettings, StudioError> {
        self.account(path.account)?
            .custom_models
            .get(path.model)
            .ok_or_else(wrong_field)
    }

    pub(super) fn strings(&self, field: StringList) -> Result<&[String], StudioError> {
        let value = self.value();
        Ok(match field {
            StringList::ProjectDocs => &value.instructions.project_doc_fallback_filenames,
            StringList::SkillsExternal => &value.skills.external_dirs,
            StringList::SkillsDisabled => &value.skills.disabled,
            StringList::PinnedThreads => &value.general.pinned_thread_ids,
            StringList::PinnedProjects => &value.general.pinned_project_ids,
            StringList::SearchDomains => &value.web_search.allowed_domains,
            StringList::DisabledModels(index) => &self.account(index)?.disabled_models,
            StringList::Efforts(path) => &self.model(path)?.reasoning_efforts,
            StringList::Connections(path) => &self.model(path)?.supported_connection_modes,
            StringList::MediaTypes(path, index) => {
                &self
                    .model(path)?
                    .input_capabilities
                    .get(index)
                    .ok_or_else(wrong_field)?
                    .media_types
            }
        })
    }

    pub(super) fn list(&self, field: ListField, total: usize) -> Result<TypedListRef, StudioError> {
        Ok(TypedListRef {
            list_id: self.lists.register(field)?,
            total: count(total)?,
        })
    }

    pub(super) fn string_list(&self, field: StringList) -> Result<TypedListRef, StudioError> {
        self.list(ListField::Strings(field), self.strings(field)?.len())
    }

    pub(super) fn read(&self, field: TextField, inline: usize) -> Result<ReadText, StudioError> {
        self.texts.read(field, self.text_source(field)?, inline)
    }

    pub(super) fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<TextChunk, StudioError> {
        text_chunk(
            field_id,
            self.text_source(self.texts.field(field_id)?)?,
            offset,
            max_bytes,
        )
    }

    fn text_source(&self, field: TextField) -> Result<&str, StudioError> {
        let value = self.value();
        let text = match field {
            TextField::Root(field) => match field {
                RootText::DefaultAccount => value.default_account_id.as_deref(),
                RootText::Permission => Some(value.permission_mode.as_str()),
                RootText::BaseInstruction => Some(value.instructions.base_override.as_str()),
                RootText::Developer => Some(value.instructions.developer.as_str()),
                RootText::User => Some(value.instructions.user.as_str()),
                RootText::SkillsProject => Some(value.skills.project_dir.as_str()),
                RootText::SkillsUser => Some(value.skills.user_dir.as_str()),
                RootText::SearchMode => Some(value.web_search.configured_mode.as_str()),
                RootText::SearchContext => value.web_search.context_size.as_deref(),
                RootText::Country => value.web_search.country.as_deref(),
                RootText::Region => value.web_search.region.as_deref(),
                RootText::City => value.web_search.city.as_deref(),
                RootText::Timezone => value.web_search.timezone.as_deref(),
            },
            TextField::Account(index, field) => {
                let account = self.account(index)?;
                match field {
                    AccountText::Id => Some(account.account_id.as_str()),
                    AccountText::Template => account.template_id.as_deref(),
                    AccountText::Protocol => Some(account.protocol.as_str()),
                    AccountText::Name => Some(account.name.as_str()),
                    AccountText::BaseUrl => Some(account.base_url.as_str()),
                    AccountText::Catalog => account.catalog_id.as_deref(),
                    AccountText::BearerTokenEnv => account.bearer_token_env.as_deref(),
                }
            }
            TextField::Model(path, field) => {
                let model = self.model(path)?;
                Some(
                    match field {
                        ModelText::Id => &model.model_id,
                        ModelText::Name => &model.display_name,
                        ModelText::BaseInstructions => &model.base_instructions,
                        ModelText::WireApi => &model.wire_api,
                        ModelText::DefaultConnection => &model.default_connection_mode,
                    }
                    .as_str(),
                )
            }
            TextField::Connection(account, index, mode) => self
                .account(account)?
                .model_connection_modes
                .get(index)
                .map(|value| {
                    if mode {
                        value.connection_mode.as_str()
                    } else {
                        value.model_id.as_str()
                    }
                }),
            TextField::AutoCompact(account, index) => self
                .account(account)?
                .model_auto_compact_limits
                .get(index)
                .map(|value| value.model_id.as_str()),
            TextField::Mode(index, field) => {
                value.mode_model_routes.get(index).map(|route| match field {
                    RouteText::Key => route.mode_id.as_str(),
                    RouteText::Account => route.account_id.as_str(),
                    RouteText::Model => route.model_id.as_str(),
                    RouteText::Effort => route.effort.as_str(),
                })
            }
            TextField::Role(index, field) => value.roles.get(index).map(|route| match field {
                RouteText::Key => route.key.as_str(),
                RouteText::Account => route.account_id.as_str(),
                RouteText::Model => route.model_id.as_str(),
                RouteText::Effort => route.effort.as_str(),
            }),
            TextField::Mcp(index, field) => {
                value.mcp_servers.get(index).map(|server| match field {
                    McpText::Id => server.id.as_str(),
                    McpText::Transport => server.transport.as_str(),
                    McpText::Endpoint => server.endpoint.as_str(),
                    McpText::Source => server.source_kind.as_str(),
                    McpText::MutationPolicy => server.mutation_policy.as_str(),
                })
            }
            TextField::String(list, index) => self.strings(list)?.get(index).map(String::as_str),
        };
        text.ok_or_else(wrong_field)
    }
}

pub(super) fn wrong_field() -> StudioError {
    StudioError::invalid_argument(
        "This field, member or typed list does not belong to the original Configuration scope",
    )
}
