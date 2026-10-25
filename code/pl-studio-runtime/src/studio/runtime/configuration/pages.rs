use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::configuration::*;
use pl_protocol::products::read::configuration_pages::*;
use pl_protocol::products::read::model_pages::{
    ModelInputCapabilityReadPage, ModelInputSourceReadPage,
};
use pl_protocol::products::read::models::{ModelInputCapabilityRead, ModelInputSourceReadItem};
use pl_protocol::products::read::primitives::{TextReadItem, TextReadPage};
use pl_protocol::studio::{StudioError, StudioErrorCode};

use super::super::models::page_budget::{PageBinding, page};
use super::super::read_budget::bounded_header;
use super::fields::*;
use super::material::{ConfigurationReadMaterial, wrong_field};

impl ConfigurationReadMaterial {
    pub(super) fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<ConfigurationEntryPage, StudioError> {
        let collection = self.source.collection;
        let result = page(
            PageBinding::Collection(collection),
            self.source.entities.len(),
            offset,
            limit,
            |index, _| Ok(self.source.entities[index]),
        )?;
        Ok(ConfigurationEntryPage {
            collection,
            offset,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn lookup_account(
        &self,
        account_id: &str,
    ) -> Result<Option<ProductEntityRef>, StudioError> {
        Ok(self
            .value()
            .accounts
            .iter()
            .position(|account| account.account_id == account_id)
            .map(|index| self.source.entities[index]))
    }

    pub(super) fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> Result<ConfigurationEntityRead, StudioError> {
        let index = self
            .source
            .entities
            .iter()
            .position(|entity| entity.entry == reference.entry)
            .ok_or_else(|| StudioError::not_found("Configuration account member"))?;
        if self.source.entities[index] != reference {
            return Err(StudioError::new(
                StudioErrorCode::Superseded,
                "Account revision does not belong to the original immutable Configuration scope",
                false,
            ));
        }
        bounded_header(|inline| {
            Ok(ConfigurationEntityRead {
                reference,
                value: self.account_read(index, inline)?,
            })
        })
    }

    pub(super) fn accounts(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<AccountConfigurationReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Accounts {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.value().accounts.len(),
            offset,
            limit,
            |index, inline| self.account_read(index, inline),
        )?;
        Ok(AccountConfigurationReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    fn account_read(
        &self,
        index: usize,
        inline: usize,
    ) -> Result<AccountConfigurationRead, StudioError> {
        let value = self.account(index)?;
        let text = |field| self.read(TextField::Account(index, field), inline);
        Ok(AccountConfigurationRead {
            pricing_enabled: value.pricing_enabled,
            billing_kind: value.billing_kind,
            billing_kind_override: value.billing_kind_override,
            disabled_models: self.string_list(StringList::DisabledModels(index))?,
            account_id: text(AccountText::Id)?,
            template_id: value
                .template_id
                .as_ref()
                .map(|_| text(AccountText::Template))
                .transpose()?,
            protocol: text(AccountText::Protocol)?,
            name: text(AccountText::Name)?,
            base_url: text(AccountText::BaseUrl)?,
            has_bearer_token: value.has_bearer_token,
            bearer_token_env: value
                .bearer_token_env
                .as_ref()
                .map(|_| text(AccountText::BearerTokenEnv))
                .transpose()?,
            usage_query_revision: value.usage_query_revision,
            custom_models: self.list(ListField::CustomModels(index), value.custom_models.len())?,
            model_connection_modes: self.list(
                ListField::Connections(index),
                value.model_connection_modes.len(),
            )?,
            model_auto_compact_limits: self.list(
                ListField::AutoCompact(index),
                value.model_auto_compact_limits.len(),
            )?,
            catalog_id: value
                .catalog_id
                .as_ref()
                .map(|_| text(AccountText::Catalog))
                .transpose()?,
        })
    }

    pub(super) fn custom_models(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<CustomModelConfigurationReadPage, StudioError> {
        let ListField::CustomModels(account) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let result = page(
            PageBinding::List(list_id),
            self.account(account)?.custom_models.len(),
            offset,
            limit,
            |model, inline| {
                let path = ModelPath { account, model };
                let value = self.model(path)?;
                let text = |field| self.read(TextField::Model(path, field), inline);
                Ok(CustomModelConfigurationRead {
                    input_capabilities: self
                        .list(ListField::Inputs(path), value.input_capabilities.len())?,
                    context_window: value.context_window,
                    max_output_tokens: value.max_output_tokens,
                    model_id: text(ModelText::Id)?,
                    display_name: text(ModelText::Name)?,
                    reasoning_efforts: self.string_list(StringList::Efforts(path))?,
                    base_instructions: text(ModelText::BaseInstructions)?,
                    wire_api: text(ModelText::WireApi)?,
                    supported_connection_modes: self.string_list(StringList::Connections(path))?,
                    default_connection_mode: text(ModelText::DefaultConnection)?,
                })
            },
        )?;
        Ok(CustomModelConfigurationReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn model_connections(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModelConnectionReadPage, StudioError> {
        let ListField::Connections(account) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let result = page(
            PageBinding::List(list_id),
            self.account(account)?.model_connection_modes.len(),
            offset,
            limit,
            |index, inline| {
                Ok(ModelConnectionRead {
                    model_id: self.read(TextField::Connection(account, index, false), inline)?,
                    connection_mode: self
                        .read(TextField::Connection(account, index, true), inline)?,
                })
            },
        )?;
        Ok(ModelConnectionReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn auto_compact_overrides(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModelAutoCompactReadPage, StudioError> {
        let ListField::AutoCompact(account) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let result = page(
            PageBinding::List(list_id),
            self.account(account)?.model_auto_compact_limits.len(),
            offset,
            limit,
            |index, inline| {
                Ok(ModelAutoCompactRead {
                    model_id: self.read(TextField::AutoCompact(account, index), inline)?,
                    override_limit: self.account(account)?.model_auto_compact_limits[index]
                        .override_limit,
                })
            },
        )?;
        Ok(ModelAutoCompactReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn mode_routes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModeModelRouteReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Modes {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.value().mode_model_routes.len(),
            offset,
            limit,
            |index, inline| {
                let text = |field| self.read(TextField::Mode(index, field), inline);
                Ok(ModeModelRouteRead {
                    mode_id: text(RouteText::Key)?,
                    account_id: text(RouteText::Account)?,
                    model_id: text(RouteText::Model)?,
                    effort: text(RouteText::Effort)?,
                })
            },
        )?;
        Ok(ModeModelRouteReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn role_routes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<RoleModelRouteReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Roles {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.value().roles.len(),
            offset,
            limit,
            |index, inline| {
                let text = |field| self.read(TextField::Role(index, field), inline);
                Ok(RoleModelRouteRead {
                    key: text(RouteText::Key)?,
                    account_id: text(RouteText::Account)?,
                    model_id: text(RouteText::Model)?,
                    effort: text(RouteText::Effort)?,
                })
            },
        )?;
        Ok(RoleModelRouteReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn mcp_configs(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<McpConfigurationReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Mcp {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.value().mcp_servers.len(),
            offset,
            limit,
            |index, inline| {
                let text = |field| self.read(TextField::Mcp(index, field), inline);
                Ok(McpConfigurationRead {
                    id: text(McpText::Id)?,
                    transport: text(McpText::Transport)?,
                    endpoint: text(McpText::Endpoint)?,
                    configuration: self.value().mcp_servers[index].configuration,
                    source_kind: text(McpText::Source)?,
                    mutation_policy: text(McpText::MutationPolicy)?,
                })
            },
        )?;
        Ok(McpConfigurationReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn strings_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<TextReadPage, StudioError> {
        let ListField::Strings(field) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let result = page(
            PageBinding::List(list_id),
            self.strings(field)?.len(),
            offset,
            limit,
            |index, inline| {
                Ok(TextReadItem {
                    value: self.read(TextField::String(field, index), inline)?,
                })
            },
        )?;
        Ok(TextReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn input_capabilities(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModelInputCapabilityReadPage, StudioError> {
        let ListField::Inputs(path) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let result = page(
            PageBinding::List(list_id),
            self.model(path)?.input_capabilities.len(),
            offset,
            limit,
            |index, _| {
                let input = &self.model(path)?.input_capabilities[index];
                Ok(ModelInputCapabilityRead {
                    modality: input.modality,
                    sources: self
                        .list(ListField::InputSources(path, index), input.sources.len())?,
                    max_count: input.max_count,
                    max_bytes: input.max_bytes,
                    max_total_bytes: input.max_total_bytes,
                    max_width: input.max_width,
                    max_height: input.max_height,
                    media_types: self.string_list(StringList::MediaTypes(path, index))?,
                })
            },
        )?;
        Ok(ModelInputCapabilityReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(super) fn input_sources(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModelInputSourceReadPage, StudioError> {
        let ListField::InputSources(path, index) = self.lists.field(list_id)? else {
            return Err(wrong_field());
        };
        let input = self
            .model(path)?
            .input_capabilities
            .get(index)
            .ok_or_else(wrong_field)?;
        let result = page(
            PageBinding::List(list_id),
            input.sources.len(),
            offset,
            limit,
            |index, _| {
                Ok(ModelInputSourceReadItem {
                    value: input.sources[index],
                })
            },
        )?;
        Ok(ModelInputSourceReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
}
