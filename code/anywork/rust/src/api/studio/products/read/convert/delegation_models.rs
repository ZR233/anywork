//! Mechanical moves only; no recapture, qualification policy or text materialization.
use super::super::delegation_model_values::*;
use crate::api::studio::types::{BridgeAgentEvaluationOutcome, BridgeModelSelectionSourceKind};
use pl_protocol::products::read::delegation_models as protocol;

impl From<BridgeDelegationModelReadTarget> for protocol::DelegationModelReadTarget {
    fn from(value: BridgeDelegationModelReadTarget) -> Self {
        Self {
            sources: value.sources.into(),
            model: pl_protocol::products::models::AccountModelKey {
                account_id: value.model.account_id,
                model_id: value.model.model_id,
            },
        }
    }
}
impl From<protocol::DelegationModelReadTarget> for BridgeDelegationModelReadTarget {
    fn from(value: protocol::DelegationModelReadTarget) -> Self {
        Self {
            sources: value.sources.into(),
            model: value.model.into(),
        }
    }
}
impl From<protocol::DelegationModelReadHeader> for BridgeDelegationModelReadHeader {
    fn from(value: protocol::DelegationModelReadHeader) -> Self {
        Self {
            scope: value.scope.into(),
            target: value.target.into(),
            account_name: value.account_name.into(),
            descriptor: value.descriptor.into(),
            available: value.available,
            unavailable_reason: value.unavailable_reason.map(Into::into),
            billing_kind: value.billing_kind.into(),
            guide: value.guide.map(Into::into),
            performance: value.performance.into(),
            evaluations: value.evaluations.into(),
            recent_evaluations: value.recent_evaluations.into(),
        }
    }
}
impl From<protocol::ModelSelectionGuideRead> for BridgeModelSelectionGuideRead {
    fn from(value: protocol::ModelSelectionGuideRead) -> Self {
        Self {
            summary: value.summary.into(),
            task_suitability: value.task_suitability.into_iter().map(Into::into).collect(),
            limitations: value.limitations.into(),
            sources: value.sources.into(),
        }
    }
}
impl From<protocol::ModelSelectionSourceRead> for BridgeModelSelectionSourceRead {
    fn from(value: protocol::ModelSelectionSourceRead) -> Self {
        Self {
            kind: match value.kind {
                pl_protocol::ModelSelectionSourceKindDto::Official => {
                    BridgeModelSelectionSourceKind::Official
                }
                pl_protocol::ModelSelectionSourceKindDto::Benchmark => {
                    BridgeModelSelectionSourceKind::Benchmark
                }
                pl_protocol::ModelSelectionSourceKindDto::Community => {
                    BridgeModelSelectionSourceKind::Community
                }
            },
            url: value.url.into(),
            verified_at: value.verified_at,
            measurement: value.measurement.map(Into::into),
        }
    }
}
impl From<protocol::ModelSelectionMeasurementRead> for BridgeModelSelectionMeasurementRead {
    fn from(value: protocol::ModelSelectionMeasurementRead) -> Self {
        Self {
            model: value.model.into(),
            effort: value.effort.map(Into::into),
            metric: value.metric.into(),
            metric_version: value.metric_version.map(Into::into),
            score: value.score,
        }
    }
}
impl From<protocol::AgentEvaluationRead> for BridgeAgentEvaluationRead {
    fn from(value: protocol::AgentEvaluationRead) -> Self {
        Self {
            agent_id: value.agent_id.into(),
            parent_agent_id: value.parent_agent_id.into(),
            account_id: value.account_id.into(),
            model_id: value.model_id.into(),
            effort: value.effort.map(Into::into),
            profile_id: value.profile_id.into(),
            mode: value.mode.into(),
            preference: value.preference.into(),
            turn_id: value.turn_id.into(),
            revision: value.revision,
            task_category: value.task_category.into(),
            outcome: match value.outcome {
                pl_protocol::AgentEvaluationOutcome::Passed => BridgeAgentEvaluationOutcome::Passed,
                pl_protocol::AgentEvaluationOutcome::Failed => BridgeAgentEvaluationOutcome::Failed,
                pl_protocol::AgentEvaluationOutcome::NotRated => {
                    BridgeAgentEvaluationOutcome::NotRated
                }
            },
            quality: value.quality,
            instruction_following: value.instruction_following,
            comment: value.comment.into(),
            created_at: value.created_at,
            updated_at: value.updated_at,
        }
    }
}
impl From<protocol::ModelSelectionSourceReadPage> for BridgeModelSelectionSourceReadPage {
    fn from(value: protocol::ModelSelectionSourceReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}
impl From<protocol::AgentEvaluationReadPage> for BridgeAgentEvaluationReadPage {
    fn from(value: protocol::AgentEvaluationReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}
