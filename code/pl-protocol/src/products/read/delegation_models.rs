//! Exact model details retain the original Configuration/catalog pair and a bounded read window.
use serde::{Deserialize, Serialize};

use super::models::ModelDescriptorRead;
use super::primitives::TypedListRef;
use crate::products::configuration::ConfigurationRoleReadTarget;
use crate::products::identity::ProductReadScopeIdentity;
use crate::products::models::AccountModelKey;
use crate::studio::ReadText;
use crate::{
    AgentEvaluationOutcome, AgentEvaluationSummary, AgentTaskCategory, BillingKind, DelegationMode,
    DelegationPreference, LocalModelPerformanceSummary, ModelSelectionSourceKindDto,
};

/// A requested model within one Rust-issued pair; the target cannot recreate expired material.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationModelReadTarget {
    pub sources: ConfigurationRoleReadTarget,
    pub model: AccountModelKey,
}

/// Every field/list reference belongs to this scope, not to a later catalog or evaluation query.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationModelReadHeader {
    pub scope: ProductReadScopeIdentity,
    pub target: DelegationModelReadTarget,
    pub account_name: ReadText,
    pub descriptor: ModelDescriptorRead,
    pub available: bool,
    pub unavailable_reason: Option<ReadText>,
    pub billing_kind: BillingKind,
    pub guide: Option<ModelSelectionGuideRead>,
    pub performance: LocalModelPerformanceSummary,
    pub evaluations: AgentEvaluationSummary,
    pub recent_evaluations: TypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelSelectionGuideRead {
    pub summary: ReadText,
    pub task_suitability: Vec<AgentTaskCategory>,
    pub limitations: TypedListRef,
    pub sources: TypedListRef,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelSelectionSourceRead {
    pub kind: ModelSelectionSourceKindDto,
    pub url: ReadText,
    pub verified_at: i64,
    pub measurement: Option<ModelSelectionMeasurementRead>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelSelectionMeasurementRead {
    pub model: ReadText,
    pub effort: Option<ReadText>,
    pub metric: ReadText,
    pub metric_version: Option<ReadText>,
    pub score: Option<f64>,
}

/// The evaluation's frozen model identity is retained; current model metadata cannot rewrite it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentEvaluationRead {
    pub agent_id: ReadText,
    pub parent_agent_id: ReadText,
    pub account_id: ReadText,
    pub model_id: ReadText,
    pub effort: Option<ReadText>,
    pub profile_id: ReadText,
    pub mode: DelegationMode,
    pub preference: DelegationPreference,
    pub turn_id: ReadText,
    pub revision: u64,
    pub task_category: AgentTaskCategory,
    pub outcome: AgentEvaluationOutcome,
    pub quality: Option<u8>,
    pub instruction_following: Option<u8>,
    pub comment: ReadText,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelSelectionSourceReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<ModelSelectionSourceRead>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentEvaluationReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<AgentEvaluationRead>,
    pub next_offset: Option<u64>,
}
