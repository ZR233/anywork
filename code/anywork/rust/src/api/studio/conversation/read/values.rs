use super::super::identity::BridgeReadScopeIdentity;
use crate::api::studio::observation::BridgeReadText;
use crate::api::studio::types::{BridgeTodoStatus, BridgeWorkflowRunLifecycle};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMetricsIdentityReadHeader {
    pub scope: BridgeReadScopeIdentity,
    pub turn_id: BridgeReadText,
    pub attempt_id: Option<BridgeReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeContextReadHeader {
    pub scope: BridgeReadScopeIdentity,
    pub frozen_model_id: Option<BridgeReadText>,
    pub prompt_cache_policy: Option<BridgeReadText>,
    pub estimated_cost_count: u64,
    pub estimated_cache_saving_count: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeCostReadItem {
    pub index: u64,
    pub currency: BridgeReadText,
    pub amount: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeCostPage {
    pub scope: BridgeReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeCostReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadConfigurationReadHeader {
    pub scope: BridgeReadScopeIdentity,
    pub route: Option<BridgeModelRouteReadValue>,
    pub active_skill_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelRouteReadValue {
    pub bot_id: Option<BridgeReadText>,
    pub account_id: BridgeReadText,
    pub model_id: BridgeReadText,
    pub effort: Option<BridgeReadText>,
    pub revision: u64,
    pub available: bool,
    pub unavailable_reason: Option<BridgeReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillNameReadItem {
    pub index: u64,
    pub name: BridgeReadText,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillNamePage {
    pub scope: BridgeReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeSkillNameReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTodoReadHeader {
    pub scope: BridgeReadScopeIdentity,
    pub call_id: Option<BridgeReadText>,
    pub agent_id: Option<BridgeReadText>,
    pub path: Option<BridgeReadText>,
    pub parent_path: Option<BridgeReadText>,
    pub explanation: Option<BridgeReadText>,
    pub item_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTodoReadItem {
    pub index: u64,
    pub step: BridgeReadText,
    pub status: BridgeTodoStatus,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTodoItemPage {
    pub scope: BridgeReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeTodoReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWorkflowReadHeader {
    pub scope: BridgeReadScopeIdentity,
    pub revision: u64,
    pub current_run: Option<BridgeWorkflowRunReadValue>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWorkflowRunReadValue {
    pub lineage_id: BridgeReadText,
    pub run_id: BridgeReadText,
    pub mode_id: BridgeReadText,
    pub graph_revision: u64,
    pub graph_hash: BridgeReadText,
    pub lifecycle: BridgeWorkflowRunLifecycle,
    pub current_state_id: BridgeReadText,
    pub started_at: i64,
    pub updated_at: i64,
    pub current_state_title: BridgeReadText,
    pub mode_display_name: BridgeReadText,
    pub mode_deleted: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePlanDocumentReadHeader {
    pub scope: BridgeReadScopeIdentity,
    pub version: u64,
    pub content_hash: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePlanDocumentValue {
    pub scope: BridgeReadScopeIdentity,
    pub version: u64,
    pub content_hash: String,
    pub markdown: String,
}
