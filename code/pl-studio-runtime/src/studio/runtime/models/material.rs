use std::sync::Arc;

use pl_protocol::products::identity::{ProductCollectionRef, ProductEntityRef};
use pl_protocol::products::models::ModelsValue;
use pl_protocol::products::read::primitives::TypedListRef;
use pl_protocol::studio::{ReadText, StudioError, TextChunk};
use pl_protocol::{AccountCatalogSnapshot, ModelDescriptor};

use super::super::read_budget::{FieldTable, count, text_chunk};
use super::delegation_material::DelegationMaterial;
use super::fields::{
    AccountText, DescriptorText, ListField, ModelPath, SearchText, StringList, TemplateText,
    TextField,
};
use super::templates_source::TemplatesMaterial;

pub(super) enum ModelRoot {
    Catalog(Arc<crate::config::ModelCatalogMaterial>),
    Templates(Arc<TemplatesMaterial>),
}

pub(super) struct ModelReadMaterial {
    pub(super) root: ModelRoot,
    delegation: Option<Box<DelegationMaterial>>,
    pub(super) texts: FieldTable<TextField>,
    pub(super) lists: FieldTable<ListField>,
}

impl ModelReadMaterial {
    pub(super) fn new(root: ModelRoot) -> Self {
        Self {
            root,
            delegation: None,
            texts: FieldTable::default(),
            lists: FieldTable::default(),
        }
    }

    pub(super) fn for_delegation(detail: DelegationMaterial) -> Self {
        let mut material = Self::new(ModelRoot::Catalog(detail.pair.models.clone()));
        material.delegation = Some(Box::new(detail));
        material
    }

    pub(super) fn delegation(&self) -> Result<&DelegationMaterial, StudioError> {
        self.delegation.as_deref().ok_or_else(wrong_field)
    }

    pub(super) fn catalog(&self) -> Result<&ModelsValue, StudioError> {
        match &self.root {
            ModelRoot::Catalog(material) => Ok(material.value()),
            ModelRoot::Templates(_) => Err(wrong_field()),
        }
    }

    pub(super) fn templates(&self) -> Result<&AccountCatalogSnapshot, StudioError> {
        match &self.root {
            ModelRoot::Templates(material) => Ok(&material.value),
            ModelRoot::Catalog(_) => Err(wrong_field()),
        }
    }

    pub(super) fn collection(&self) -> ProductCollectionRef {
        match &self.root {
            ModelRoot::Catalog(material) => material.collection,
            ModelRoot::Templates(material) => material.collection,
        }
    }

    pub(super) fn entities(&self) -> &[ProductEntityRef] {
        match &self.root {
            ModelRoot::Catalog(material) => &material.entities,
            ModelRoot::Templates(material) => &material.entities,
        }
    }

    pub(super) fn model_group(&self, group: usize) -> Result<&[ModelDescriptor], StudioError> {
        match &self.root {
            ModelRoot::Catalog(material) => material
                .value()
                .accounts
                .get(group)
                .map(|account| account.effective_models.as_slice()),
            ModelRoot::Templates(material) => material
                .value
                .model_catalogs
                .values()
                .nth(group)
                .map(|catalog| catalog.models.as_slice()),
        }
        .ok_or_else(wrong_field)
    }

    pub(super) fn model(&self, path: ModelPath) -> Result<&ModelDescriptor, StudioError> {
        self.model_group(path.group)?
            .get(path.model)
            .ok_or_else(wrong_field)
    }

    pub(super) fn strings_source(&self, list: StringList) -> Result<&[String], StudioError> {
        match list {
            StringList::Candidates(path) => self
                .model(path)?
                .reasoning
                .as_ref()
                .map(|value| value.candidates.as_slice()),
            StringList::MediaTypes(path, index) => self
                .model(path)?
                .capabilities
                .input
                .get(index)
                .map(|value| value.media_types.as_slice()),
            StringList::GuideLimitations => self
                .delegation()?
                .guide
                .as_ref()
                .map(|guide| guide.limitations.as_slice()),
        }
        .ok_or_else(wrong_field)
    }

    pub(super) fn list(&self, key: ListField, total: usize) -> Result<TypedListRef, StudioError> {
        Ok(TypedListRef {
            list_id: self.lists.register(key)?,
            total: count(total)?,
        })
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
        let field = self.texts.field(field_id)?;
        text_chunk(field_id, self.text_source(field)?, offset, max_bytes)
    }

    fn text_source(&self, field: TextField) -> Result<&str, StudioError> {
        let value = match field {
            TextField::Delegation(field) => return self.delegation()?.text(field),
            TextField::Account(index, field) => {
                let account = self
                    .catalog()?
                    .accounts
                    .get(index)
                    .ok_or_else(wrong_field)?;
                match field {
                    AccountText::Id => Some(account.account_id.as_str()),
                    AccountText::CapabilitySource => Some(account.capability_source.as_str()),
                    AccountText::HostedDialect => Some(account.hosted_web_search_dialect.as_str()),
                    AccountText::Standalone => account.standalone_web_search.as_deref(),
                    AccountText::PromptCache => Some(account.prompt_cache_dialect.as_str()),
                    AccountText::DefaultModel => Some(account.default_model_id.as_str()),
                }
            }
            TextField::Search(field) => {
                let catalog = self.catalog()?;
                match field {
                    SearchText::Mode => Some(catalog.web_search.effective_mode.as_str()),
                    SearchText::Availability => Some(catalog.web_search.availability.as_str()),
                    SearchText::Account => catalog.web_search.account_id.as_deref(),
                    SearchText::Model => catalog.web_search.model_id.as_deref(),
                    SearchText::DeepSeekAvailability => {
                        Some(catalog.deepseek_web_search.availability.as_str())
                    }
                    SearchText::DeepSeekAccount => {
                        catalog.deepseek_web_search.account_id.as_deref()
                    }
                }
            }
            TextField::Template(index, field) => {
                let template = self
                    .templates()?
                    .templates
                    .get(index)
                    .ok_or_else(wrong_field)?;
                match field {
                    TemplateText::Id => Some(template.id.as_str()),
                    TemplateText::DisplayName => Some(template.display_name.as_str()),
                    TemplateText::Description => template.description.as_deref(),
                    TemplateText::BaseUrl => Some(template.base_url.as_str()),
                    TemplateText::CredentialLabel => Some(template.credential.label.as_str()),
                    TemplateText::CredentialEnv => template.credential.env_var.as_deref(),
                    TemplateText::CatalogId => Some(template.model_catalog_id.as_str()),
                    TemplateText::Protocol => Some(template.protocol.as_str()),
                    TemplateText::SuggestedModel => Some(template.suggested_model_id.as_str()),
                    TemplateText::Icon => template.icon_key.as_deref(),
                    TemplateText::HostedDialect => Some(
                        template
                            .service_capabilities
                            .web_search
                            .hosted_dialect
                            .as_str(),
                    ),
                    TemplateText::Standalone => template
                        .service_capabilities
                        .web_search
                        .standalone
                        .as_deref(),
                    TemplateText::PromptCache => {
                        Some(template.service_capabilities.prompt_cache_dialect.as_str())
                    }
                }
            }
            TextField::TemplateRevision => Some(self.templates()?.revision.as_str()),
            TextField::CatalogKey(index) => self
                .templates()?
                .model_catalogs
                .keys()
                .nth(index)
                .map(String::as_str),
            TextField::CatalogId(index) => self
                .templates()?
                .model_catalogs
                .values()
                .nth(index)
                .map(|value| value.id.as_str()),
            TextField::Model(path, field) => {
                let model = self.model(path)?;
                match field {
                    DescriptorText::Id => Some(model.model_id.as_str()),
                    DescriptorText::DisplayName => Some(model.display_name.as_str()),
                    DescriptorText::Description => model.description.as_deref(),
                    DescriptorText::Protocol => Some(model.transport.protocol.as_str()),
                    DescriptorText::DefaultConnection => {
                        Some(model.transport.default_connection_mode.as_str())
                    }
                    DescriptorText::NativeContext => {
                        model.capabilities.native_context_family.as_deref()
                    }
                    DescriptorText::ReasoningParameter => model
                        .reasoning
                        .as_ref()
                        .map(|value| value.parameter.as_str()),
                    DescriptorText::ReasoningLabel => {
                        model.reasoning.as_ref().map(|value| value.label.as_str())
                    }
                    DescriptorText::ReasoningDefault => model
                        .reasoning
                        .as_ref()
                        .and_then(|value| value.default.as_deref()),
                    DescriptorText::PricingCurrency => {
                        model.pricing.as_ref().map(|value| value.currency.as_str())
                    }
                    DescriptorText::PricingSource => {
                        model.pricing.as_ref().map(|value| value.source.as_str())
                    }
                }
            }
            TextField::ConnectionId(path, index) => self
                .model(path)?
                .transport
                .connection_modes
                .get(index)
                .map(|value| value.id.as_str()),
            TextField::ConnectionName(path, index) => self
                .model(path)?
                .transport
                .connection_modes
                .get(index)
                .map(|value| value.display_name.as_str()),
            TextField::TierLabel(path, index) => self
                .model(path)?
                .pricing
                .as_ref()
                .and_then(|value| value.tiers.get(index))
                .map(|value| value.label.as_str()),
            TextField::String(list, index) => {
                self.strings_source(list)?.get(index).map(String::as_str)
            }
        };
        value.ok_or_else(wrong_field)
    }
}

pub(super) fn wrong_field() -> StudioError {
    StudioError::invalid_argument(
        "The field or list does not belong to this immutable Models read scope",
    )
}
