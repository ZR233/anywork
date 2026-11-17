use crate::api::studio::types::*;

impl From<BridgeDelegationMode> for pl_studio_runtime::DelegationMode {
    fn from(value: BridgeDelegationMode) -> Self {
        match value {
            BridgeDelegationMode::Profile => Self::Profile,
            BridgeDelegationMode::Automatic => Self::Automatic,
        }
    }
}

impl From<pl_studio_runtime::DelegationMode> for BridgeDelegationMode {
    fn from(value: pl_studio_runtime::DelegationMode) -> Self {
        match value {
            pl_studio_runtime::DelegationMode::Profile => Self::Profile,
            pl_studio_runtime::DelegationMode::Automatic => Self::Automatic,
        }
    }
}

impl From<BridgeDelegationPreference> for pl_studio_runtime::DelegationPreference {
    fn from(value: BridgeDelegationPreference) -> Self {
        match value {
            BridgeDelegationPreference::Economy => Self::Economy,
            BridgeDelegationPreference::Balanced => Self::Balanced,
            BridgeDelegationPreference::Fast => Self::Fast,
        }
    }
}

impl From<pl_studio_runtime::DelegationPreference> for BridgeDelegationPreference {
    fn from(value: pl_studio_runtime::DelegationPreference) -> Self {
        match value {
            pl_studio_runtime::DelegationPreference::Economy => Self::Economy,
            pl_studio_runtime::DelegationPreference::Balanced => Self::Balanced,
            pl_studio_runtime::DelegationPreference::Fast => Self::Fast,
        }
    }
}

impl From<BridgeBillingKind> for pl_studio_runtime::BillingKind {
    fn from(value: BridgeBillingKind) -> Self {
        match value {
            BridgeBillingKind::Metered => Self::Metered,
            BridgeBillingKind::Subscription => Self::Subscription,
            BridgeBillingKind::NoCharge => Self::NoCharge,
            BridgeBillingKind::Unknown => Self::Unknown,
        }
    }
}

impl From<pl_studio_runtime::BillingKind> for BridgeBillingKind {
    fn from(value: pl_studio_runtime::BillingKind) -> Self {
        match value {
            pl_studio_runtime::BillingKind::Metered => Self::Metered,
            pl_studio_runtime::BillingKind::Subscription => Self::Subscription,
            pl_studio_runtime::BillingKind::NoCharge => Self::NoCharge,
            pl_studio_runtime::BillingKind::Unknown => Self::Unknown,
        }
    }
}

impl From<pl_studio_runtime::NewThreadModelRoute> for BridgeNewThreadModelRoute {
    fn from(value: pl_studio_runtime::NewThreadModelRoute) -> Self {
        Self {
            account_id: value.account_id,
            model_id: value.model_id,
            effort: value.effort,
        }
    }
}

impl From<BridgeNewThreadModelRoute> for pl_studio_runtime::NewThreadModelRoute {
    fn from(value: BridgeNewThreadModelRoute) -> Self {
        Self {
            account_id: value.account_id,
            model_id: value.model_id,
            effort: value.effort,
        }
    }
}

impl From<BridgeAgentTaskCategory> for pl_studio_runtime::AgentTaskCategory {
    fn from(value: BridgeAgentTaskCategory) -> Self {
        match value {
            BridgeAgentTaskCategory::Reasoning => Self::Reasoning,
            BridgeAgentTaskCategory::Coding => Self::Coding,
            BridgeAgentTaskCategory::Tooling => Self::Tooling,
            BridgeAgentTaskCategory::LongContext => Self::LongContext,
            BridgeAgentTaskCategory::Multimodal => Self::Multimodal,
            BridgeAgentTaskCategory::General => Self::General,
        }
    }
}

impl From<pl_studio_runtime::AgentTaskCategory> for BridgeAgentTaskCategory {
    fn from(value: pl_studio_runtime::AgentTaskCategory) -> Self {
        match value {
            pl_studio_runtime::AgentTaskCategory::Reasoning => Self::Reasoning,
            pl_studio_runtime::AgentTaskCategory::Coding => Self::Coding,
            pl_studio_runtime::AgentTaskCategory::Tooling => Self::Tooling,
            pl_studio_runtime::AgentTaskCategory::LongContext => Self::LongContext,
            pl_studio_runtime::AgentTaskCategory::Multimodal => Self::Multimodal,
            pl_studio_runtime::AgentTaskCategory::General => Self::General,
        }
    }
}

impl From<BridgeDelegationModelCapability> for pl_studio_runtime::DelegationModelCapability {
    fn from(value: BridgeDelegationModelCapability) -> Self {
        match value {
            BridgeDelegationModelCapability::ToolCalling => Self::ToolCalling,
            BridgeDelegationModelCapability::ParallelToolCalls => Self::ParallelToolCalls,
            BridgeDelegationModelCapability::Reasoning => Self::Reasoning,
            BridgeDelegationModelCapability::ImageInput => Self::ImageInput,
            BridgeDelegationModelCapability::AudioInput => Self::AudioInput,
            BridgeDelegationModelCapability::VideoInput => Self::VideoInput,
            BridgeDelegationModelCapability::FileInput => Self::FileInput,
            BridgeDelegationModelCapability::CustomTools => Self::CustomTools,
            BridgeDelegationModelCapability::FreeformTools => Self::FreeformTools,
            BridgeDelegationModelCapability::WebSearch => Self::WebSearch,
            BridgeDelegationModelCapability::Streaming => Self::Streaming,
        }
    }
}

impl From<BridgeListDelegationModelsRequest> for pl_studio_runtime::ListDelegationModelsRequest {
    fn from(value: BridgeListDelegationModelsRequest) -> Self {
        Self {
            capabilities: value.capabilities.into_iter().map(Into::into).collect(),
            account_id: value.account_id,
            billing_kind: value.billing_kind.map(Into::into),
            min_context_window: value.min_context_window,
        }
    }
}

impl From<pl_studio_runtime::DelegationModelList> for BridgeDelegationModelList {
    fn from(value: pl_studio_runtime::DelegationModelList) -> Self {
        Self {
            models: value
                .models
                .into_iter()
                .map(|model| BridgeDelegationModelListItem {
                    account_id: model.account_id,
                    account_name: model.account_name,
                    model_id: model.model_id,
                    display_name: model.display_name,
                    summary: model.summary,
                    task_suitability: model.task_suitability.into_iter().map(Into::into).collect(),
                    context_window: model.context_window,
                    capabilities: model.capabilities.into(),
                    reasoning_efforts: model.reasoning_efforts,
                    billing_kind: model.billing_kind.into(),
                })
                .collect(),
            catalog_revision: value.catalog_revision,
        }
    }
}

impl From<pl_studio_runtime::DelegationModelDetail> for BridgeDelegationModelDetail {
    fn from(value: pl_studio_runtime::DelegationModelDetail) -> Self {
        Self {
            account_id: value.account_id,
            account_name: value.account_name,
            descriptor: value.descriptor.into(),
            available: value.available,
            unavailable_reason: value.unavailable_reason,
            billing_kind: value.billing_kind.into(),
            guide: value.guide.map(|guide| BridgeModelSelectionGuide {
                summary: guide.summary,
                task_suitability: guide.task_suitability.into_iter().map(Into::into).collect(),
                limitations: guide.limitations,
                sources: guide
                    .sources
                    .into_iter()
                    .map(|source| BridgeModelSelectionSource {
                        kind: match source.kind {
                            pl_studio_runtime::ModelSelectionSourceKindDto::Official => {
                                BridgeModelSelectionSourceKind::Official
                            }
                            pl_studio_runtime::ModelSelectionSourceKindDto::Benchmark => {
                                BridgeModelSelectionSourceKind::Benchmark
                            }
                            pl_studio_runtime::ModelSelectionSourceKindDto::Community => {
                                BridgeModelSelectionSourceKind::Community
                            }
                        },
                        url: source.url,
                        verified_at: source.verified_at,
                        measurement: source.measurement.map(|measurement| {
                            BridgeModelSelectionMeasurement {
                                model: measurement.model,
                                effort: measurement.effort,
                                metric: measurement.metric,
                                metric_version: measurement.metric_version,
                                score: measurement.score,
                            }
                        }),
                    })
                    .collect(),
            }),
            performance: value.performance.into(),
            evaluations: value.evaluations.into(),
            recent_evaluations: value
                .recent_evaluations
                .into_iter()
                .map(|evaluation| BridgeAgentEvaluation {
                    agent_id: evaluation.agent_id,
                    parent_agent_id: evaluation.parent_agent_id,
                    model: evaluation.model.into(),
                    profile_id: evaluation.profile_id,
                    mode: evaluation.mode.into(),
                    preference: evaluation.preference.into(),
                    turn_id: evaluation.turn_id,
                    revision: evaluation.revision,
                    task_category: evaluation.task_category.into(),
                    outcome: match evaluation.outcome {
                        pl_studio_runtime::AgentEvaluationOutcome::Passed => {
                            BridgeAgentEvaluationOutcome::Passed
                        }
                        pl_studio_runtime::AgentEvaluationOutcome::Failed => {
                            BridgeAgentEvaluationOutcome::Failed
                        }
                        pl_studio_runtime::AgentEvaluationOutcome::NotRated => {
                            BridgeAgentEvaluationOutcome::NotRated
                        }
                    },
                    quality: evaluation.quality,
                    instruction_following: evaluation.instruction_following,
                    comment: evaluation.comment,
                    created_at: evaluation.created_at,
                    updated_at: evaluation.updated_at,
                })
                .collect(),
        }
    }
}

impl From<pl_studio_runtime::LocalModelPerformanceSummary> for BridgeLocalModelPerformanceSummary {
    fn from(value: pl_studio_runtime::LocalModelPerformanceSummary) -> Self {
        Self {
            sample_count: value.sample_count,
            tokens_per_second: value.tokens_per_second,
            average_ttft_millis: value.average_ttft_millis,
            ttft_sample_count: value.ttft_sample_count,
            updated_at: value.updated_at,
        }
    }
}

impl From<pl_studio_runtime::AgentEvaluationSummary> for BridgeAgentEvaluationSummary {
    fn from(value: pl_studio_runtime::AgentEvaluationSummary) -> Self {
        Self {
            window: value.window,
            rated_samples: value.rated_samples,
            passed: value.passed,
            failed: value.failed,
            not_rated: value.not_rated,
            average_quality: value.average_quality,
            average_instruction_following: value.average_instruction_following,
        }
    }
}
