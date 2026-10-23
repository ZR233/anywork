use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::model_pages::AccountTemplatesEntityRead;
use pl_protocol::products::read::templates::*;
use pl_protocol::studio::StudioError;

use super::super::read_budget::bounded_header;
use super::fields::{ListField, TemplateText, TextField};
use super::material::{ModelReadMaterial, wrong_field};

impl ModelReadMaterial {
    pub(super) fn templates_header(&self) -> Result<AccountTemplatesReadHeader, StudioError> {
        bounded_header(|inline| {
            let source = self.templates()?;
            Ok(AccountTemplatesReadHeader { schema_version: source.schema_version,
                revision: self.read(TextField::TemplateRevision, inline)?,
                templates: self.list(ListField::Templates, source.templates.len())?,
                model_catalogs: self.list(ListField::Catalogs, source.model_catalogs.len())? })
        })
    }

    pub(super) fn template_read(&self, index: usize, inline: usize) -> Result<AccountTemplateRead, StudioError> {
        let source = self.templates()?.templates.get(index).ok_or_else(wrong_field)?;
        let text = |field| self.read(TextField::Template(index, field), inline);
        Ok(AccountTemplateRead { pricing_enabled: source.pricing_enabled, id: text(TemplateText::Id)?,
            display_name: text(TemplateText::DisplayName)?,
            description: source.description.as_ref().map(|_| text(TemplateText::Description)).transpose()?,
            base_url: text(TemplateText::BaseUrl)?,
            credential: CredentialDescriptorRead { label: text(TemplateText::CredentialLabel)?,
                env_var: source.credential.env_var.as_ref().map(|_| text(TemplateText::CredentialEnv)).transpose()? },
            model_catalog_id: text(TemplateText::CatalogId)?, protocol: text(TemplateText::Protocol)?,
            suggested_model_id: text(TemplateText::SuggestedModel)?,
            icon_key: source.icon_key.as_ref().map(|_| text(TemplateText::Icon)).transpose()?,
            service_capabilities: AccountServiceCapabilitiesRead {
                web_search: WebSearchServiceCapabilitiesRead { hosted_responses: source.service_capabilities.web_search.hosted_responses,
                    hosted_dialect: text(TemplateText::HostedDialect)?,
                    standalone: source.service_capabilities.web_search.standalone.as_ref().map(|_| text(TemplateText::Standalone)).transpose()? },
                prompt_cache_dialect: text(TemplateText::PromptCache)?,
                responses_programmatic_tool_calling: source.service_capabilities.responses_programmatic_tool_calling },
        })
    }

    pub(super) fn named_catalog_read(&self, index: usize, inline: usize) -> Result<NamedModelCatalogReadItem, StudioError> {
        let source = self.templates()?.model_catalogs.values().nth(index).ok_or_else(wrong_field)?;
        Ok(NamedModelCatalogReadItem { key: self.read(TextField::CatalogKey(index), inline)?,
            value: NamedModelCatalogRead { id: self.read(TextField::CatalogId(index), inline)?,
                models: self.list(ListField::Models(index), source.models.len())? } })
    }

    pub(super) fn lookup_template(&self, template_id: &str) -> Result<Option<ProductEntityRef>, StudioError> {
        let index = self.templates()?.templates.iter().position(|value| value.id == template_id);
        index.map(|index| self.entities().get(index).copied().ok_or_else(wrong_field)).transpose()
    }

    pub(super) fn template_entity(&self, reference: ProductEntityRef) -> Result<AccountTemplatesEntityRead, StudioError> {
        self.templates()?;
        let index = self.entity_index(reference)?;
        bounded_header(|inline| Ok(AccountTemplatesEntityRead { reference, value: self.template_read(index, inline)? }))
    }
}
