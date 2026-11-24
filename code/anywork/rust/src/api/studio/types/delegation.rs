//! Typed mirrors of delegation settings and on-demand model reference data.

use serde::{Deserialize, Serialize};

use super::BridgeModelDescriptor;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeDelegationMode {
    Profile,
    Automatic,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeDelegationPreference {
    Economy,
    Balanced,
    Fast,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeDelegationSettings {
    pub mode: BridgeDelegationMode,
    pub preference: BridgeDelegationPreference,
}

/// A saved route identity, not a live model-selection recommendation.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeNewThreadModelRoute {
    pub account_id: String,
    pub model_id: String,
    pub effort: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeBillingKind {
    Metered,
    Subscription,
    NoCharge,
    Unknown,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeAgentTaskCategory {
    Reasoning,
    Coding,
    Tooling,
    LongContext,
    Multimodal,
    General,
}

#[derive(Debug, Clone)]
pub struct BridgeGetDelegationModelRequest {
    pub account_id: String,
    pub model_id: String,
}

#[derive(Debug, Clone)]
pub struct BridgeDelegationModelDetail {
    pub account_id: String,
    pub account_name: String,
    pub descriptor: BridgeModelDescriptor,
    pub available: bool,
    pub unavailable_reason: Option<String>,
    pub billing_kind: BridgeBillingKind,
    pub guide: Option<BridgeModelSelectionGuide>,
    pub performance: BridgeLocalModelPerformanceSummary,
    pub evaluations: BridgeAgentEvaluationSummary,
    pub recent_evaluations: Vec<BridgeAgentEvaluation>,
}

#[derive(Debug, Clone)]
pub struct BridgeLocalModelPerformanceSummary {
    pub sample_count: u64,
    pub tokens_per_second: Option<f64>,
    pub average_ttft_millis: Option<f64>,
    pub ttft_sample_count: u64,
    pub updated_at: Option<i64>,
}

#[derive(Debug, Clone)]
pub struct BridgeModelSelectionGuide {
    pub summary: String,
    pub task_suitability: Vec<BridgeAgentTaskCategory>,
    pub limitations: Vec<String>,
    pub sources: Vec<BridgeModelSelectionSource>,
}

#[derive(Debug, Clone)]
pub struct BridgeModelSelectionSource {
    pub kind: BridgeModelSelectionSourceKind,
    pub url: String,
    pub verified_at: i64,
    pub measurement: Option<BridgeModelSelectionMeasurement>,
}

#[derive(Debug, Clone, Copy)]
pub enum BridgeModelSelectionSourceKind {
    Official,
    Benchmark,
    Community,
}

#[derive(Debug, Clone)]
pub struct BridgeModelSelectionMeasurement {
    pub model: String,
    pub effort: Option<String>,
    pub metric: String,
    pub metric_version: Option<String>,
    pub score: Option<f64>,
}

#[derive(Debug, Clone, Copy)]
pub enum BridgeAgentEvaluationOutcome {
    Passed,
    Failed,
    NotRated,
}

#[derive(Debug, Clone)]
pub struct BridgeAgentEvaluation {
    pub agent_id: String,
    pub parent_agent_id: String,
    pub model: BridgeNewThreadModelRoute,
    pub profile_id: String,
    pub mode: BridgeDelegationMode,
    pub preference: BridgeDelegationPreference,
    pub turn_id: String,
    pub revision: u64,
    pub task_category: BridgeAgentTaskCategory,
    pub outcome: BridgeAgentEvaluationOutcome,
    pub quality: Option<u8>,
    pub instruction_following: Option<u8>,
    pub comment: String,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone)]
pub struct BridgeAgentEvaluationSummary {
    pub window: u32,
    pub rated_samples: u32,
    pub passed: u32,
    pub failed: u32,
    pub not_rated: u32,
    pub average_quality: Option<f32>,
    pub average_instruction_following: Option<f32>,
}
