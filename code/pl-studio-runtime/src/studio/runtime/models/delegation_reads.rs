use pl_protocol::products::identity::ProductReadScopeIdentity;
use pl_protocol::products::read::delegation_models::{
    AgentEvaluationRead, AgentEvaluationReadPage, DelegationModelReadHeader,
    ModelSelectionGuideRead, ModelSelectionMeasurementRead, ModelSelectionSourceRead,
    ModelSelectionSourceReadPage,
};
use pl_protocol::studio::StudioError;

use super::super::read_budget::bounded_header;
use super::fields::{
    DelegationText, EvaluationText, ListField, SelectionSourceText, StringList, TextField,
};
use super::material::{ModelReadMaterial, wrong_field};
use super::page_budget::{PageBinding, page};

impl ModelReadMaterial {
    pub(super) fn delegation_header(
        &self,
        scope: ProductReadScopeIdentity,
    ) -> Result<DelegationModelReadHeader, StudioError> {
        let detail = self.delegation()?;
        let qualification = detail.pair.models.model_qualification(
            &detail.target.model.account_id,
            &detail.target.model.model_id,
        )?;
        bounded_header(|inline| {
            let text = |field| self.read(TextField::Delegation(field), inline);
            let guide = detail
                .guide
                .as_ref()
                .map(|guide| -> Result<_, StudioError> {
                    Ok(ModelSelectionGuideRead {
                        summary: text(DelegationText::GuideSummary)?,
                        task_suitability: guide.task_suitability.clone(),
                        limitations: self.list(
                            ListField::Strings(StringList::GuideLimitations),
                            guide.limitations.len(),
                        )?,
                        sources: self.list(ListField::SelectionSources, guide.sources.len())?,
                    })
                })
                .transpose()?;
            Ok(DelegationModelReadHeader {
                scope: scope.clone(),
                target: detail.target.clone(),
                account_name: text(DelegationText::AccountName)?,
                descriptor: self.model_read(detail.path, inline)?,
                available: qualification.is_available(),
                unavailable_reason: qualification
                    .unavailable_reason()
                    .map(|_| text(DelegationText::UnavailableReason))
                    .transpose()?,
                billing_kind: detail.account()?.billing_kind,
                guide,
                performance: detail.performance.clone(),
                evaluations: detail.evaluations.clone(),
                recent_evaluations: self
                    .list(ListField::Evaluations, detail.recent_evaluations.len())?,
            })
        })
    }

    pub(super) fn selection_sources_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<ModelSelectionSourceReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::SelectionSources {
            return Err(wrong_field());
        }
        let guide = self.delegation()?.guide.as_ref().ok_or_else(wrong_field)?;
        let result = page(
            PageBinding::List(list_id),
            guide.sources.len(),
            offset,
            limit,
            |index, inline| self.selection_source_read(index, inline),
        )?;
        Ok(ModelSelectionSourceReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    fn selection_source_read(
        &self,
        index: usize,
        inline: usize,
    ) -> Result<ModelSelectionSourceRead, StudioError> {
        let source = self
            .delegation()?
            .guide
            .as_ref()
            .and_then(|guide| guide.sources.get(index))
            .ok_or_else(wrong_field)?;
        let text = |field| {
            self.read(
                TextField::Delegation(DelegationText::Source(index, field)),
                inline,
            )
        };
        let measurement = source
            .measurement
            .as_ref()
            .map(|value| -> Result<_, StudioError> {
                Ok(ModelSelectionMeasurementRead {
                    model: text(SelectionSourceText::Model)?,
                    effort: value
                        .effort
                        .as_ref()
                        .map(|_| text(SelectionSourceText::Effort))
                        .transpose()?,
                    metric: text(SelectionSourceText::Metric)?,
                    metric_version: value
                        .metric_version
                        .as_ref()
                        .map(|_| text(SelectionSourceText::MetricVersion))
                        .transpose()?,
                    score: value.score,
                })
            })
            .transpose()?;
        Ok(ModelSelectionSourceRead {
            kind: source.kind,
            url: text(SelectionSourceText::Url)?,
            verified_at: source.verified_at,
            measurement,
        })
    }

    pub(super) fn evaluations_page(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<AgentEvaluationReadPage, StudioError> {
        if self.lists.field(list_id)? != ListField::Evaluations {
            return Err(wrong_field());
        }
        let result = page(
            PageBinding::List(list_id),
            self.delegation()?.recent_evaluations.len(),
            offset,
            limit,
            |index, inline| self.evaluation_read(index, inline),
        )?;
        Ok(AgentEvaluationReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    fn evaluation_read(
        &self,
        index: usize,
        inline: usize,
    ) -> Result<AgentEvaluationRead, StudioError> {
        let value = self
            .delegation()?
            .recent_evaluations
            .get(index)
            .ok_or_else(wrong_field)?;
        let text = |field| {
            self.read(
                TextField::Delegation(DelegationText::Evaluation(index, field)),
                inline,
            )
        };
        Ok(AgentEvaluationRead {
            agent_id: text(EvaluationText::Agent)?,
            parent_agent_id: text(EvaluationText::Parent)?,
            account_id: text(EvaluationText::Account)?,
            model_id: text(EvaluationText::Model)?,
            effort: value
                .model
                .effort
                .as_ref()
                .map(|_| text(EvaluationText::Effort))
                .transpose()?,
            profile_id: text(EvaluationText::Profile)?,
            mode: value.mode,
            preference: value.preference,
            turn_id: text(EvaluationText::Turn)?,
            revision: value.revision,
            task_category: value.task_category,
            outcome: value.outcome,
            quality: value.quality,
            instruction_following: value.instruction_following,
            comment: text(EvaluationText::Comment)?,
            created_at: value.created_at,
            updated_at: value.updated_at,
        })
    }
}
