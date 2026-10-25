//! Read-only candidate projections over the config, performance and evaluation owners.
use super::{StudioThreadAssembler, agent_services::AgentServices};
use crate::studio::delegation::resolve_catalog_selection;
use anyhow::{Context, Result};
use pl_model::{config::AccountId, model::ModelType};
use pl_protocol::{
    DelegationModelCapability as Capability, DelegationModelCursor, DelegationModelDetail,
    DelegationModelKey, DelegationModelList, DelegationModelListItem, GetDelegationModelRequest,
    ListDelegationModelsRequest, LocalModelPerformanceSummary, ModelCapabilitiesDto,
    ModelModalityDto,
};

impl AgentServices {
    pub(super) async fn list_delegation_models(
        &self,
        request: ListDelegationModelsRequest,
    ) -> Result<DelegationModelList> {
        let limit = usize::from(request.page_limit().map_err(|error| {
            pl_protocol::studio::StudioError::invalid_argument(error.to_string())
        })?);
        let filter = request.filter();
        let (snapshot, catalog) = self.config.read_with_catalog()?;
        let cursor = request
            .cursor
            .as_deref()
            .map(|value| {
                DelegationModelCursor::decode(value).ok_or_else(|| {
                    pl_protocol::studio::StudioError::invalid_argument(
                        "invalid delegation model cursor",
                    )
                })
            })
            .transpose()?;
        if let Some(cursor) = &cursor
            && (cursor.filter != filter || cursor.catalog_watermark != catalog.revision)
        {
            return Err(stale_cursor(catalog.revision));
        }
        let mut candidates = Vec::new();
        for (account_id, account) in &snapshot.config.models.accounts {
            if filter
                .account_id
                .as_deref()
                .is_some_and(|id| id != account_id.as_str())
            {
                continue;
            }
            let billing = account.billing_kind()?;
            if filter.billing_kind.is_some_and(|kind| kind != billing) {
                continue;
            }
            // This is the model owner's only base qualification, not an automatic whitelist.
            for entry in account.selectable_catalog(Some(ModelType::Text))? {
                if resolve_catalog_selection(&snapshot.config, account_id, &entry).is_err() {
                    continue;
                }
                if filter.min_context_window.is_some_and(|minimum| {
                    entry
                        .model
                        .context_window
                        .is_none_or(|value| value < minimum)
                }) {
                    continue;
                }
                let descriptor = pl_model::config::model_descriptor(&entry);
                if !filter
                    .capabilities
                    .iter()
                    .all(|capability| supports(&descriptor.capabilities, *capability))
                {
                    continue;
                }
                candidates.push((
                    DelegationModelKey {
                        account_id: account_id.to_string(),
                        model_id: entry.model.model_id.clone(),
                    },
                    entry,
                ));
            }
        }
        candidates.sort_by(|left, right| left.0.cmp(&right.0));
        if let Some(cursor) = &cursor {
            if !candidates.iter().any(|(key, _)| key == &cursor.after) {
                return Err(stale_cursor(catalog.revision));
            }
            candidates.retain(|(key, _)| key > &cursor.after);
        }
        let more = candidates.len() > limit;
        candidates.truncate(limit);
        let next_cursor = more.then(|| {
            DelegationModelCursor::new(
                filter,
                catalog.revision,
                candidates
                    .last()
                    .expect("nonempty page before continuation")
                    .0
                    .clone(),
            )
            .encode()
        });
        let mut models = Vec::with_capacity(candidates.len());
        for (key, entry) in candidates {
            let account = snapshot
                .config
                .models
                .accounts
                .get(&AccountId::new(key.account_id.clone())?)
                .context("candidate account missing")?;
            let guide = account.model_selection_guide(&key.model_id)?;
            let descriptor = pl_model::config::model_descriptor(&entry);
            models.push(DelegationModelListItem {
                account_id: key.account_id.clone(),
                account_name: account.name.clone(),
                model_id: key.model_id.clone(),
                display_name: descriptor.display_name,
                summary: guide
                    .map(|value| value.summary)
                    .or(entry.model.description.as_deref())
                    .map(|value| value.chars().take(240).collect()),
                task_suitability: guide
                    .map(|value| value.task_suitability.to_vec())
                    .unwrap_or_default(),
                context_window: descriptor.context_window,
                capabilities: descriptor.capabilities,
                reasoning_efforts: entry.model.supported_efforts(),
                pricing: descriptor.pricing,
                billing_kind: account.billing_kind()?,
                performance: performance_summary(&self.performance, &key).await,
                evaluations: self
                    .store
                    .agent_evaluation_summary(&key.account_id, &key.model_id)
                    .await?,
            });
        }
        Ok(DelegationModelList {
            models,
            next_cursor,
            catalog_revision: catalog.revision,
        })
    }

    pub(super) async fn get_delegation_model(
        &self,
        request: GetDelegationModelRequest,
    ) -> Result<DelegationModelDetail> {
        let snapshot = self.config.read()?;
        let account_id = AccountId::new(request.account_id.clone())?;
        let account = snapshot
            .config
            .models
            .accounts
            .get(&account_id)
            .ok_or_else(|| {
                pl_protocol::studio::StudioError::not_found("Delegation model account")
            })?;
        let entry = account
            .effective_catalog(None)?
            .into_iter()
            .find(|entry| entry.model.model_id == request.model_id)
            .ok_or_else(|| pl_protocol::studio::StudioError::not_found("Current account model"))?;
        let availability = resolve_catalog_selection(&snapshot.config, &account_id, &entry);
        let key = DelegationModelKey {
            account_id: request.account_id,
            model_id: request.model_id,
        };
        let mut guide = account
            .model_selection_guide(&key.model_id)?
            .map(pl_model::config::selection_guide_descriptor);
        if let Some(guide) = &mut guide {
            guide.sources.truncate(6);
        }
        let recent_evaluations = self
            .store
            .recent_agent_evaluations(&key.account_id, &key.model_id)
            .await?;
        let evaluations =
            crate::studio::store::agent_evaluations::summarize_window(&recent_evaluations)?;
        Ok(DelegationModelDetail {
            account_id: key.account_id.clone(),
            account_name: account.name.clone(),
            descriptor: pl_model::config::model_descriptor(&entry),
            available: availability.is_ok(),
            unavailable_reason: availability.err().map(|error| error.to_string()),
            billing_kind: account.billing_kind()?,
            guide,
            performance: performance_summary(&self.performance, &key).await,
            evaluations,
            recent_evaluations,
        })
    }
}

fn stale_cursor(revision: u64) -> anyhow::Error {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::StaleRevision,
        "Delegation model cursor is stale or belongs to another query; restart the query",
        true,
    )
    .with_details(pl_protocol::studio::StudioErrorDetails::CatalogRevision { revision })
    .into()
}

fn supports(model: &ModelCapabilitiesDto, capability: Capability) -> bool {
    let modality = match capability {
        Capability::ImageInput => Some(ModelModalityDto::Image),
        Capability::AudioInput => Some(ModelModalityDto::Audio),
        Capability::VideoInput => Some(ModelModalityDto::Video),
        Capability::FileInput => Some(ModelModalityDto::File),
        _ => None,
    };
    if let Some(modality) = modality {
        return model.input.iter().any(|input| input.modality == modality);
    }
    match capability {
        Capability::ToolCalling => model.function_calling,
        Capability::ParallelToolCalls => model.parallel_tool_calls,
        Capability::Reasoning => model.reasoning,
        Capability::CustomTools => model.custom_tools,
        Capability::FreeformTools => model.freeform_tools,
        Capability::WebSearch => model.web_search,
        Capability::Streaming => model.streaming,
        Capability::ImageInput
        | Capability::AudioInput
        | Capability::VideoInput
        | Capability::FileInput => false,
    }
}

async fn performance_summary(
    owner: &crate::studio::ModelPerformanceOwner,
    key: &DelegationModelKey,
) -> LocalModelPerformanceSummary {
    let Some((updated_at, summary)) = owner.model_summary(&key.account_id, &key.model_id).await
    else {
        return Default::default();
    };
    if summary.sample_count == 0 {
        return Default::default();
    }
    LocalModelPerformanceSummary {
        sample_count: summary.sample_count,
        tokens_per_second: Some(summary.tokens_per_second),
        average_ttft_millis: summary.average_ttft_millis,
        ttft_sample_count: summary.ttft_sample_count,
        updated_at: Some(updated_at),
    }
}

impl StudioThreadAssembler {
    pub(crate) async fn list_delegation_models(
        &self,
        request: ListDelegationModelsRequest,
    ) -> Result<DelegationModelList> {
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .context("delegation services are unavailable")?;
        services.list_delegation_models(request).await
    }
    pub(crate) async fn get_delegation_model(
        &self,
        request: GetDelegationModelRequest,
    ) -> Result<DelegationModelDetail> {
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .context("delegation services are unavailable")?;
        services.get_delegation_model(request).await
    }
}
