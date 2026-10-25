//! One verified pair plus the original bounded guide/evaluation and local-performance window.
use std::sync::Arc;

use anyhow::Result;
use pl_protocol::products::configuration::AccountConfiguration;
use pl_protocol::products::read::delegation_models::DelegationModelReadTarget;
use pl_protocol::studio::StudioError;
use pl_protocol::{
    AgentEvaluation, AgentEvaluationSummary, LocalModelPerformanceSummary, ModelOriginDto,
    ModelSelectionGuideDto,
};

use super::super::StudioRuntime;
use super::fields::{DelegationText, EvaluationText, ModelPath, SelectionSourceText};
use super::material::wrong_field;
use crate::config::ConfigurationPair;

pub(super) struct DelegationMaterial {
    pub(super) pair: Arc<ConfigurationPair>,
    pub(super) target: DelegationModelReadTarget,
    pub(super) path: ModelPath,
    configuration_account: usize,
    pub(super) guide: Option<ModelSelectionGuideDto>,
    pub(super) performance: LocalModelPerformanceSummary,
    pub(super) evaluations: AgentEvaluationSummary,
    pub(super) recent_evaluations: Vec<AgentEvaluation>,
}

impl DelegationMaterial {
    /// Caller has pinned and verified the complete original pair before the first await here.
    /// Local observations form this read's immutable window, not a cross-owner transaction.
    pub(super) async fn capture(
        runtime: &StudioRuntime,
        pair: Arc<ConfigurationPair>,
        target: DelegationModelReadTarget,
    ) -> Result<Self> {
        let key = &target.model;
        let configuration_account = pair
            .configuration
            .value
            .accounts
            .iter()
            .position(|account| account.account_id == key.account_id)
            .ok_or_else(|| StudioError::not_found("Delegation model account"))?;
        let group = pair
            .models
            .value()
            .accounts
            .iter()
            .position(|account| account.account_id == key.account_id)
            .ok_or_else(|| StudioError::not_found("Delegation model account"))?;
        let models = &pair.models.value().accounts[group].effective_models;
        let model = models
            .iter()
            .position(|model| model.model_id == key.model_id)
            .ok_or_else(|| StudioError::not_found("Current account model"))?;
        pair.models
            .model_qualification(&key.account_id, &key.model_id)?;
        // Only the original Bundled account and original non-Manual effective member qualify.
        // This library lookup reads static metadata, never account/current effective_catalog.
        let account = &pair.configuration.value.accounts[configuration_account];
        let mut guide = if models[model].origin == ModelOriginDto::Manual {
            None
        } else {
            account
                .catalog_id
                .as_deref()
                .and_then(|catalog| {
                    pl_model::model::bundled_selection_guide(catalog, &key.model_id)
                })
                .map(pl_model::config::selection_guide_descriptor)
        };
        if let Some(guide) = &mut guide {
            guide.sources.truncate(6);
        }
        let recent_evaluations = runtime
            .store
            .recent_agent_evaluations(&key.account_id, &key.model_id)
            .await?;
        let evaluations =
            crate::studio::store::agent_evaluations::summarize_window(&recent_evaluations)?;
        let performance = match runtime
            .model_performance
            .model_summary(&key.account_id, &key.model_id)
            .await
        {
            Some((updated_at, summary)) if summary.sample_count != 0 => {
                LocalModelPerformanceSummary {
                    sample_count: summary.sample_count,
                    tokens_per_second: Some(summary.tokens_per_second),
                    average_ttft_millis: summary.average_ttft_millis,
                    ttft_sample_count: summary.ttft_sample_count,
                    updated_at: Some(updated_at),
                }
            }
            _ => LocalModelPerformanceSummary::default(),
        };
        Ok(Self {
            pair,
            target,
            path: ModelPath { group, model },
            configuration_account,
            guide,
            performance,
            evaluations,
            recent_evaluations,
        })
    }

    pub(super) fn account(&self) -> Result<&AccountConfiguration, StudioError> {
        self.pair
            .configuration
            .value
            .accounts
            .get(self.configuration_account)
            .ok_or_else(wrong_field)
    }

    pub(super) fn text(&self, field: DelegationText) -> Result<&str, StudioError> {
        let value = match field {
            DelegationText::AccountName => Some(self.account()?.name.as_str()),
            DelegationText::UnavailableReason => self
                .pair
                .models
                .model_qualification(&self.target.model.account_id, &self.target.model.model_id)?
                .unavailable_reason(),
            DelegationText::GuideSummary => self.guide.as_ref().map(|guide| guide.summary.as_str()),
            DelegationText::Source(index, field) => {
                let source = self
                    .guide
                    .as_ref()
                    .and_then(|guide| guide.sources.get(index))
                    .ok_or_else(wrong_field)?;
                match field {
                    SelectionSourceText::Url => Some(source.url.as_str()),
                    SelectionSourceText::Model => source
                        .measurement
                        .as_ref()
                        .map(|value| value.model.as_str()),
                    SelectionSourceText::Effort => source
                        .measurement
                        .as_ref()
                        .and_then(|value| value.effort.as_deref()),
                    SelectionSourceText::Metric => source
                        .measurement
                        .as_ref()
                        .map(|value| value.metric.as_str()),
                    SelectionSourceText::MetricVersion => source
                        .measurement
                        .as_ref()
                        .and_then(|value| value.metric_version.as_deref()),
                }
            }
            DelegationText::Evaluation(index, field) => {
                let value = self.recent_evaluations.get(index).ok_or_else(wrong_field)?;
                match field {
                    EvaluationText::Agent => Some(value.agent_id.as_str()),
                    EvaluationText::Parent => Some(value.parent_agent_id.as_str()),
                    EvaluationText::Account => Some(value.model.account_id.as_str()),
                    EvaluationText::Model => Some(value.model.model_id.as_str()),
                    EvaluationText::Effort => value.model.effort.as_deref(),
                    EvaluationText::Profile => Some(value.profile_id.as_str()),
                    EvaluationText::Turn => Some(value.turn_id.as_str()),
                    EvaluationText::Comment => Some(value.comment.as_str()),
                }
            }
        };
        value.ok_or_else(wrong_field)
    }
}
