use serde::{Deserialize, Serialize};

use crate::studio::ReadText;
use crate::thread_facets::identity::ReadScopeIdentity;
use crate::{TodoStatus, WorkflowRunLifecycle};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MetricsIdentityReadHeader {
    pub scope: ReadScopeIdentity,
    pub turn_id: ReadText,
    pub attempt_id: Option<ReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContextReadHeader {
    pub scope: ReadScopeIdentity,
    pub frozen_model_id: Option<ReadText>,
    pub prompt_cache_policy: Option<ReadText>,
    pub estimated_cost_count: u64,
    pub estimated_cache_saving_count: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CostReadItem {
    pub index: u64,
    pub currency: ReadText,
    pub amount: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CostPage {
    pub scope: ReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<CostReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ConfigurationReadHeader {
    pub scope: ReadScopeIdentity,
    pub route: Option<ModelRouteReadValue>,
    pub active_skill_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelRouteReadValue {
    pub bot_id: Option<ReadText>,
    pub account_id: ReadText,
    pub model_id: ReadText,
    pub effort: Option<ReadText>,
    pub revision: u64,
    pub available: bool,
    pub unavailable_reason: Option<ReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillNameReadItem {
    pub index: u64,
    pub name: ReadText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillNamePage {
    pub scope: ReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<SkillNameReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct TodoReadHeader {
    pub scope: ReadScopeIdentity,
    pub call_id: Option<ReadText>,
    pub agent_id: Option<ReadText>,
    pub path: Option<ReadText>,
    pub parent_path: Option<ReadText>,
    pub explanation: Option<ReadText>,
    pub item_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct TodoReadItem {
    pub index: u64,
    pub step: ReadText,
    #[schema(value_type = String)]
    pub status: TodoStatus,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct TodoItemPage {
    pub scope: ReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<TodoReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct WorkflowReadHeader {
    pub scope: ReadScopeIdentity,
    pub revision: u64,
    pub current_run: Option<WorkflowRunReadValue>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct WorkflowRunReadValue {
    pub lineage_id: ReadText,
    pub run_id: ReadText,
    pub mode_id: ReadText,
    pub graph_revision: u64,
    pub graph_hash: ReadText,
    #[schema(value_type = String)]
    pub lifecycle: WorkflowRunLifecycle,
    pub current_state_id: ReadText,
    pub started_at: i64,
    pub updated_at: i64,
    pub current_state_title: ReadText,
    pub mode_display_name: ReadText,
    pub mode_deleted: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct PlanDocumentReadHeader {
    pub scope: ReadScopeIdentity,
    pub version: u64,
    pub content_hash: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct PlanDocumentValue {
    pub scope: ReadScopeIdentity,
    pub version: u64,
    pub content_hash: String,
    /// Preserve the stored document, including its original leading and trailing whitespace.
    pub markdown: String,
}
