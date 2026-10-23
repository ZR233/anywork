use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::models::ModelSelection;
use pl_protocol::products::read::model_pages::ModelCatalogEntityRead;
use pl_protocol::products::read::models::*;
use pl_protocol::studio::{StudioError, StudioErrorCode};

use super::super::read_budget::bounded_header;
use super::fields::{AccountText, ListField, SearchText, TextField};
use super::material::{ModelReadMaterial, ModelRoot, wrong_field};

impl ModelReadMaterial {
    pub(super) fn catalog_header(&self) -> Result<ModelCatalogReadHeader, StudioError> {
        bounded_header(|inline| {
            let catalog = self.catalog()?;
            let text = |field| self.read(TextField::Search(field), inline);
            Ok(ModelCatalogReadHeader {
                accounts: self.list(ListField::Accounts, catalog.accounts.len())?,
                web_search: EffectiveWebSearchRead { effective_mode: text(SearchText::Mode)?,
                    availability: text(SearchText::Availability)?,
                    account_id: catalog.web_search.account_id.as_ref().map(|_| text(SearchText::Account)).transpose()?,
                    model_id: catalog.web_search.model_id.as_ref().map(|_| text(SearchText::Model)).transpose()? },
                deepseek_web_search: EffectiveDeepSeekSearchRead {
                    effective_enabled: catalog.deepseek_web_search.effective_enabled,
                    effective_fetch_enabled: catalog.deepseek_web_search.effective_fetch_enabled,
                    availability: text(SearchText::DeepSeekAvailability)?,
                    account_id: catalog.deepseek_web_search.account_id.as_ref().map(|_| text(SearchText::DeepSeekAccount)).transpose()? },
            })
        })
    }

    pub(super) fn account_read(&self, index: usize, inline: usize) -> Result<AccountCatalogEntryRead, StudioError> {
        let account = self.catalog()?.accounts.get(index).ok_or_else(wrong_field)?;
        let text = |field| self.read(TextField::Account(index, field), inline);
        let status = &account.model_catalog;
        Ok(AccountCatalogEntryRead {
            account_id: text(AccountText::Id)?, credential_required: account.credential_required,
            capability_source: text(AccountText::CapabilitySource)?, hosted_web_search: account.hosted_web_search,
            hosted_web_search_dialect: text(AccountText::HostedDialect)?,
            standalone_web_search: account.standalone_web_search.as_ref().map(|_| text(AccountText::Standalone)).transpose()?,
            prompt_cache_dialect: text(AccountText::PromptCache)?,
            responses_programmatic_tool_calling: account.responses_programmatic_tool_calling,
            default_model_id: text(AccountText::DefaultModel)?,
            effective_models: self.list(ListField::Models(index), account.effective_models.len())?,
            model_catalog: ModelCatalogStatusRead { supported: status.supported, source: status.source,
                probing: status.probing, last_success_at: status.last_success_at, checked_at: status.checked_at,
                error: status.error.clone(), cache_warning: status.cache_warning },
        })
    }

    pub(super) fn lookup_account(&self, account_id: &str) -> Result<Option<ProductEntityRef>, StudioError> {
        let index = self.catalog()?.accounts.iter().position(|account| account.account_id == account_id);
        index.map(|index| self.entities().get(index).copied().ok_or_else(wrong_field)).transpose()
    }

    pub(super) fn catalog_entity(&self, reference: ProductEntityRef) -> Result<ModelCatalogEntityRead, StudioError> {
        self.catalog()?;
        let index = self.entity_index(reference)?;
        bounded_header(|inline| Ok(ModelCatalogEntityRead { reference, value: self.account_read(index, inline)? }))
    }

    pub(super) fn effort(&self, account_id: &str, model_id: &str, candidate: Option<&str>)
        -> Result<Option<String>, StudioError> {
        match &self.root { ModelRoot::Catalog(material) => material.effort_after_model_selection(account_id, model_id, candidate),
            ModelRoot::Templates(_) => Err(wrong_field()) }
    }

    pub(super) fn first_text_model(&self) -> Result<Option<ModelSelection>, StudioError> {
        match &self.root { ModelRoot::Catalog(material) => material.first_text_model(),
            ModelRoot::Templates(_) => Err(wrong_field()) }
    }

    pub(super) fn entity_index(&self, reference: ProductEntityRef) -> Result<usize, StudioError> {
        let index = self.entities().iter().position(|entry| entry.entry == reference.entry)
            .ok_or_else(|| StudioError::not_found("Models scope member"))?;
        if self.entities()[index] != reference {
            return Err(StudioError::new(StudioErrorCode::Superseded,
                "The entity revision does not belong to this immutable Models scope", false));
        }
        Ok(index)
    }
}
