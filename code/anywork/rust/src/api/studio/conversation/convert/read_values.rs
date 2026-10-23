use pl_protocol::thread_facets::read::values as protocol;
use super::super::read::values as bridge;

impl From<protocol::MetricsIdentityReadHeader> for bridge::BridgeMetricsIdentityReadHeader {
    fn from(value: protocol::MetricsIdentityReadHeader) -> Self {
        Self { scope: value.scope.into(), turn_id: value.turn_id.into(), attempt_id: value.attempt_id.map(Into::into) }
    }
}

impl From<protocol::ContextReadHeader> for bridge::BridgeContextReadHeader {
    fn from(value: protocol::ContextReadHeader) -> Self {
        Self { scope: value.scope.into(), frozen_model_id: value.frozen_model_id.map(Into::into),
            prompt_cache_policy: value.prompt_cache_policy.map(Into::into), estimated_cost_count: value.estimated_cost_count,
            estimated_cache_saving_count: value.estimated_cache_saving_count }
    }
}

impl From<protocol::CostReadItem> for bridge::BridgeCostReadItem {
    fn from(value: protocol::CostReadItem) -> Self {
        Self { index: value.index, currency: value.currency.into(), amount: value.amount }
    }
}

impl From<protocol::CostPage> for bridge::BridgeCostPage {
    fn from(value: protocol::CostPage) -> Self {
        Self { scope: value.scope.into(), offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::ModelRouteReadValue> for bridge::BridgeModelRouteReadValue {
    fn from(value: protocol::ModelRouteReadValue) -> Self {
        Self { account_id: value.account_id.into(), model_id: value.model_id.into(), effort: value.effort.map(Into::into),
            revision: value.revision, available: value.available, unavailable_reason: value.unavailable_reason.map(Into::into) }
    }
}

impl From<protocol::ConfigurationReadHeader> for bridge::BridgeConfigurationReadHeader {
    fn from(value: protocol::ConfigurationReadHeader) -> Self {
        Self { scope: value.scope.into(), route: value.route.map(Into::into), active_skill_count: value.active_skill_count }
    }
}

impl From<protocol::SkillNameReadItem> for bridge::BridgeSkillNameReadItem {
    fn from(value: protocol::SkillNameReadItem) -> Self { Self { index: value.index, name: value.name.into() } }
}

impl From<protocol::SkillNamePage> for bridge::BridgeSkillNamePage {
    fn from(value: protocol::SkillNamePage) -> Self {
        Self { scope: value.scope.into(), offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::TodoReadHeader> for bridge::BridgeTodoReadHeader {
    fn from(value: protocol::TodoReadHeader) -> Self {
        Self { scope: value.scope.into(), call_id: value.call_id.map(Into::into), agent_id: value.agent_id.map(Into::into),
            path: value.path.map(Into::into), parent_path: value.parent_path.map(Into::into),
            explanation: value.explanation.map(Into::into), item_count: value.item_count }
    }
}

impl From<protocol::TodoReadItem> for bridge::BridgeTodoReadItem {
    fn from(value: protocol::TodoReadItem) -> Self {
        Self { index: value.index, step: value.step.into(), status: value.status.into() }
    }
}

impl From<protocol::TodoItemPage> for bridge::BridgeTodoItemPage {
    fn from(value: protocol::TodoItemPage) -> Self {
        Self { scope: value.scope.into(), offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::WorkflowRunReadValue> for bridge::BridgeWorkflowRunReadValue {
    fn from(value: protocol::WorkflowRunReadValue) -> Self {
        Self { lineage_id: value.lineage_id.into(), run_id: value.run_id.into(), mode_id: value.mode_id.into(),
            graph_revision: value.graph_revision, graph_hash: value.graph_hash.into(), lifecycle: value.lifecycle.into(),
            current_state_id: value.current_state_id.into(), started_at: value.started_at, updated_at: value.updated_at,
            current_state_title: value.current_state_title.into(), mode_display_name: value.mode_display_name.into(), mode_deleted: value.mode_deleted }
    }
}

impl From<protocol::WorkflowReadHeader> for bridge::BridgeWorkflowReadHeader {
    fn from(value: protocol::WorkflowReadHeader) -> Self {
        Self { scope: value.scope.into(), revision: value.revision, current_run: value.current_run.map(Into::into) }
    }
}

impl From<protocol::PlanDocumentReadHeader> for bridge::BridgePlanDocumentReadHeader {
    fn from(value: protocol::PlanDocumentReadHeader) -> Self {
        Self { scope: value.scope.into(), version: value.version, content_hash: value.content_hash }
    }
}

impl From<protocol::PlanDocumentValue> for bridge::BridgePlanDocumentValue {
    fn from(value: protocol::PlanDocumentValue) -> Self {
        Self { scope: value.scope.into(), version: value.version, content_hash: value.content_hash, markdown: value.markdown }
    }
}
