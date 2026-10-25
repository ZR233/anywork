use std::sync::Arc;

use anyhow::{Context, Result};
use pl_model::config::AccountCapabilitySelection;
use pl_protocol::products::identity::{ProductCollectionRef, ProductEntityRef};
use pl_protocol::products::models::{
    AccountCatalogEntry, EffectiveDeepSeekSearch, EffectiveWebSearch, ModelSelection, ModelsValue,
};
use pl_protocol::products::references::ModelCatalogReadRef;
use pl_protocol::search::WebSearchMode;
use pl_protocol::studio::StudioError;
use pl_tool::search::{WebSearchAvailability, WebSearchDeepSeekOptions};

use super::ModelExecutionQualification;
use super::qualification::AccountModelQualifications;
use super::selection::ModelSelectionMaterial;
use crate::{ConfigRuntimeSnapshot, ModelCatalogRuntimeSnapshot};

/// Only Models fields, validated suggestions and original execution qualifications survive capture.
/// Full desired settings, credentials, runtime handles and routes are not stored here.
pub(crate) struct CapturedModels {
    pub(crate) value: ModelsValue,
    selection: ModelSelectionMaterial,
    qualifications: Vec<AccountModelQualifications>,
}

impl CapturedModels {
    pub(super) fn same_business(&self, other: &Self) -> bool {
        self.value == other.value
            && self.selection.same_policy(&other.selection)
            && self.qualifications == other.qualifications
    }

    pub(super) fn same_account(&self, index: usize, other: &Self, other_index: usize) -> bool {
        self.value.accounts.get(index) == other.value.accounts.get(other_index)
            && self
                .selection
                .same_account_policy(index, &other.selection, other_index)
            && match (
                self.qualifications.get(index),
                other.qualifications.get(other_index),
            ) {
                (Some(left), Some(right)) => left == right,
                _ => false,
            }
    }

    pub(crate) fn capture(
        snapshot: &ConfigRuntimeSnapshot,
        catalog: &ModelCatalogRuntimeSnapshot,
    ) -> Result<Self> {
        let desired = snapshot.canonical_config();
        let mut accounts = Vec::with_capacity(snapshot.config.models.accounts.len());
        let mut qualifications = Vec::with_capacity(snapshot.config.models.accounts.len());
        for (id, account) in &snapshot.config.models.accounts {
            let configured = desired
                .models
                .accounts
                .get(id)
                .context("Models account has no canonical configuration")?;
            let capabilities = configured.service_capabilities()?;
            let default_model_id = match desired
                .models
                .routes
                .values()
                .find(|route| route.account_id == *id)
            {
                Some(route) => route.model_id.clone(),
                None => configured
                    .effective_catalog(None)?
                    .first()
                    .map(|entry| entry.model.model_id.clone())
                    .unwrap_or_default(),
            };
            let effective_models = account.effective_catalog(None)?;
            qualifications.push(AccountModelQualifications::capture(
                &snapshot.config,
                id,
                &effective_models,
            ));
            accounts.push(AccountCatalogEntry {
                account_id: id.to_string(),
                credential_required: configured.protocol
                    != pl_model::protocol::ProtocolKind::OpenAiCompatible,
                capability_source: match &configured.capabilities {
                    AccountCapabilitySelection::TemplateDefaults => "template_defaults",
                    AccountCapabilitySelection::Explicit(_) => "explicit",
                }
                .to_owned(),
                hosted_web_search: capabilities.web_search.hosted_responses,
                hosted_web_search_dialect: capabilities
                    .web_search
                    .hosted_dialect
                    .as_str()
                    .to_owned(),
                standalone_web_search: capabilities
                    .web_search
                    .standalone
                    .map(|dialect| dialect.as_str().to_owned()),
                prompt_cache_dialect: capabilities.prompt_cache.dialect.as_str().to_owned(),
                responses_programmatic_tool_calling: capabilities
                    .responses_tools
                    .programmatic_tool_calling,
                default_model_id,
                effective_models: effective_models
                    .iter()
                    .map(pl_model::config::model_descriptor)
                    .collect(),
                model_catalog: catalog
                    .catalogs
                    .get(id)
                    .cloned()
                    .context("Models account observation is unavailable")?,
            });
        }
        // This is the same deterministic service planner used by the existing Settings view;
        // it resolves typed declarations/credentials, not a client request or network discovery.
        let services = pl_tool::search::plan_web_search_services(
            &snapshot.config.models,
            &snapshot.config.web_search,
            &WebSearchDeepSeekOptions {
                enabled: snapshot.config.deepseek_web_search.enabled,
                fetch_enabled: snapshot.config.deepseek_web_search.fetch_enabled,
            },
        )?;
        let openai = services.openai.resolution;
        let deepseek = services.deepseek.resolution;
        let available = deepseek.availability == WebSearchAvailability::Available;
        Ok(Self {
            value: ModelsValue {
                accounts,
                web_search: EffectiveWebSearch {
                    effective_mode: mode_label(openai.effective_mode).to_owned(),
                    availability: availability_label(openai.availability).to_owned(),
                    account_id: openai.account_id.map(|id| id.to_string()),
                    model_id: openai.model_id,
                },
                deepseek_web_search: EffectiveDeepSeekSearch {
                    effective_enabled: snapshot.config.deepseek_web_search.enabled && available,
                    effective_fetch_enabled: snapshot.config.deepseek_web_search.fetch_enabled
                        && available,
                    availability: availability_label(deepseek.availability).to_owned(),
                    account_id: deepseek.account_id.map(|id| id.to_string()),
                },
            },
            selection: ModelSelectionMaterial::capture(snapshot)?,
            qualifications,
        })
    }
}

/// One registered immutable business version. Its IDs belong to the original Models projection.
pub(crate) struct ModelCatalogMaterial {
    pub(crate) reference: ModelCatalogReadRef,
    pub(crate) collection: ProductCollectionRef,
    pub(crate) entities: Vec<ProductEntityRef>,
    pub(crate) fields: Arc<CapturedModels>,
}

impl ModelCatalogMaterial {
    pub(crate) fn value(&self) -> &ModelsValue {
        &self.fields.value
    }

    /// Borrows qualification from this exact captured catalog, without resolving current config.
    /// Missing original account/model members return the same typed NotFound as exact detail.
    pub(crate) fn model_qualification(
        &self,
        account_id: &str,
        model_id: &str,
    ) -> Result<&ModelExecutionQualification, StudioError> {
        self.fields
            .qualifications
            .iter()
            .find(|account| account.account_id() == account_id)
            .ok_or_else(|| StudioError::not_found("Delegation model account"))?
            .model(model_id)
    }

    pub(crate) fn effort_after_model_selection(
        &self,
        account_id: &str,
        model_id: &str,
        candidate: Option<&str>,
    ) -> Result<Option<String>, StudioError> {
        self.fields
            .selection
            .effort_after_model_selection(account_id, model_id, candidate)
    }
    pub(crate) fn first_text_model(&self) -> Result<Option<ModelSelection>, StudioError> {
        self.fields.selection.first_text_model()
    }
}

fn mode_label(mode: WebSearchMode) -> &'static str {
    match mode {
        WebSearchMode::Disabled => "disabled",
        WebSearchMode::Cached => "cached",
        WebSearchMode::Indexed => "indexed",
        WebSearchMode::Live => "live",
    }
}

fn availability_label(value: WebSearchAvailability) -> &'static str {
    match value {
        WebSearchAvailability::Available => "available",
        WebSearchAvailability::Disabled => "disabled",
        WebSearchAvailability::MissingCredential => "missingCredential",
        WebSearchAvailability::AccountUnsupported => "accountUnsupported",
        WebSearchAvailability::ModelUnsupported => "modelUnsupported",
    }
}
