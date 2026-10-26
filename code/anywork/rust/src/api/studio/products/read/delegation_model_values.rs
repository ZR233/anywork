//! Read-only values for the exact native Configuration/catalog pair, never whole detail text.
use super::super::identity::BridgeProductReadScopeIdentity;
use super::configuration_values::BridgeConfigurationRoleReadTarget;
use super::model_values::BridgeModelDescriptorRead;
use super::primitives::BridgeAccountModelKey;
use crate::api::studio::observation::{BridgeReadText, BridgeTypedListRef};
use crate::api::studio::types::{
    BridgeAgentEvaluationOutcome, BridgeAgentEvaluationSummary, BridgeAgentTaskCategory,
    BridgeBillingKind, BridgeDelegationMode, BridgeDelegationPreference,
    BridgeLocalModelPerformanceSummary, BridgeModelSelectionSourceKind,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeDelegationModelReadTarget {
    pub sources: BridgeConfigurationRoleReadTarget,
    pub model: BridgeAccountModelKey,
}
#[derive(Debug, Clone)]
pub struct BridgeDelegationModelReadHeader {
    pub scope: BridgeProductReadScopeIdentity,
    pub target: BridgeDelegationModelReadTarget,
    pub account_name: BridgeReadText,
    pub descriptor: BridgeModelDescriptorRead,
    pub available: bool,
    pub unavailable_reason: Option<BridgeReadText>,
    pub billing_kind: BridgeBillingKind,
    pub guide: Option<BridgeModelSelectionGuideRead>,
    pub performance: BridgeLocalModelPerformanceSummary,
    pub evaluations: BridgeAgentEvaluationSummary,
    pub recent_evaluations: BridgeTypedListRef,
}
#[derive(Debug, Clone)]
pub struct BridgeModelSelectionGuideRead {
    pub summary: BridgeReadText,
    pub task_suitability: Vec<BridgeAgentTaskCategory>,
    pub limitations: BridgeTypedListRef,
    pub sources: BridgeTypedListRef,
}
#[derive(Debug, Clone)]
pub struct BridgeModelSelectionSourceRead {
    pub kind: BridgeModelSelectionSourceKind,
    pub url: BridgeReadText,
    pub verified_at: i64,
    pub measurement: Option<BridgeModelSelectionMeasurementRead>,
}
#[derive(Debug, Clone)]
pub struct BridgeModelSelectionMeasurementRead {
    pub model: BridgeReadText,
    pub effort: Option<BridgeReadText>,
    pub metric: BridgeReadText,
    pub metric_version: Option<BridgeReadText>,
    pub score: Option<f64>,
}
#[derive(Debug, Clone)]
pub struct BridgeAgentEvaluationRead {
    pub agent_id: BridgeReadText,
    pub parent_agent_id: BridgeReadText,
    pub account_id: BridgeReadText,
    pub model_id: BridgeReadText,
    pub effort: Option<BridgeReadText>,
    pub profile_id: BridgeReadText,
    pub mode: BridgeDelegationMode,
    pub preference: BridgeDelegationPreference,
    pub turn_id: BridgeReadText,
    pub revision: u64,
    pub task_category: BridgeAgentTaskCategory,
    pub outcome: BridgeAgentEvaluationOutcome,
    pub quality: Option<u8>,
    pub instruction_following: Option<u8>,
    pub comment: BridgeReadText,
    pub created_at: i64,
    pub updated_at: i64,
}
#[derive(Debug, Clone)]
pub struct BridgeModelSelectionSourceReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeModelSelectionSourceRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone)]
pub struct BridgeAgentEvaluationReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeAgentEvaluationRead>,
    pub next_offset: Option<u64>,
}
