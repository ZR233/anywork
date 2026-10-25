use super::super::authoring as bridge;
use pl_protocol::thread_facets::authoring as protocol;

impl From<protocol::TodoBrief> for bridge::BridgeTodoBrief {
    fn from(value: protocol::TodoBrief) -> Self {
        Self {
            reference: value.reference.into(),
            item_count: value.item_count,
            has_call_id: value.has_call_id,
        }
    }
}

impl From<protocol::PlanDocumentRef> for bridge::BridgePlanDocumentRef {
    fn from(value: protocol::PlanDocumentRef) -> Self {
        Self {
            version: value.version,
            content_hash: value.content_hash,
        }
    }
}

impl From<bridge::BridgePlanDocumentRef> for protocol::PlanDocumentRef {
    fn from(value: bridge::BridgePlanDocumentRef) -> Self {
        Self {
            version: value.version,
            content_hash: value.content_hash,
        }
    }
}

impl From<protocol::PlanBrief> for bridge::BridgePlanBrief {
    fn from(value: protocol::PlanBrief) -> Self {
        Self {
            revision: value.revision,
            state: value.state.into(),
            document: value.document.map(Into::into),
            updated_at: value.updated_at,
        }
    }
}

impl From<protocol::WorkflowBrief> for bridge::BridgeWorkflowBrief {
    fn from(value: protocol::WorkflowBrief) -> Self {
        Self {
            reference: value.reference.into(),
            revision: value.revision,
            has_current_run: value.has_current_run,
            lifecycle: value.lifecycle.map(Into::into),
            mode_deleted: value.mode_deleted,
        }
    }
}

impl From<protocol::AuthoringBaseline> for bridge::BridgeAuthoringBaseline {
    fn from(value: protocol::AuthoringBaseline) -> Self {
        Self {
            todo: value.todo.map(Into::into),
            plan: value.plan.map(Into::into),
            workflow: value.workflow.map(Into::into),
            progress: value.progress.into(),
        }
    }
}

impl From<protocol::TodoReplacement> for bridge::BridgeTodoReplacement {
    fn from(value: protocol::TodoReplacement) -> Self {
        match value {
            protocol::TodoReplacement::Unchanged => Self::Unchanged,
            protocol::TodoReplacement::Replace { value } => Self::Replace {
                value: value.map(Into::into),
            },
        }
    }
}

impl From<protocol::PlanReplacement> for bridge::BridgePlanReplacement {
    fn from(value: protocol::PlanReplacement) -> Self {
        match value {
            protocol::PlanReplacement::Unchanged => Self::Unchanged,
            protocol::PlanReplacement::Replace { value } => Self::Replace {
                value: value.map(Into::into),
            },
        }
    }
}

impl From<protocol::WorkflowReplacement> for bridge::BridgeWorkflowReplacement {
    fn from(value: protocol::WorkflowReplacement) -> Self {
        match value {
            protocol::WorkflowReplacement::Unchanged => Self::Unchanged,
            protocol::WorkflowReplacement::Replace { value } => Self::Replace {
                value: value.map(Into::into),
            },
        }
    }
}

impl From<protocol::AuthoringChange> for bridge::BridgeAuthoringChange {
    fn from(value: protocol::AuthoringChange) -> Self {
        Self {
            todo: value.todo.into(),
            plan: value.plan.into(),
            workflow: value.workflow.into(),
        }
    }
}

impl From<protocol::AuthoringEvent> for bridge::BridgeAuthoringEvent {
    fn from(value: protocol::AuthoringEvent) -> Self {
        match value {
            protocol::AuthoringEvent::Baseline {
                identity,
                stamp,
                value,
            } => Self::Baseline {
                identity: identity.into(),
                stamp: stamp.into(),
                value: value.into(),
            },
            protocol::AuthoringEvent::Change {
                stamp,
                base_revision,
                value,
            } => Self::Change {
                stamp: stamp.into(),
                base_revision,
                value: value.into(),
            },
        }
    }
}

impl From<protocol::AuthoringFrame> for bridge::BridgeAuthoringFrame {
    fn from(value: protocol::AuthoringFrame) -> Self {
        match value {
            protocol::AuthoringFrame::Data {
                delivery_sequence,
                event,
            } => Self::Data {
                delivery_sequence,
                event: event.into(),
            },
            protocol::AuthoringFrame::ResyncRequired { identity, reason } => Self::ResyncRequired {
                identity: identity.into(),
                reason: reason.into(),
            },
            protocol::AuthoringFrame::Failure { identity, error } => Self::Failure {
                identity: identity.into(),
                error: error.into(),
            },
            protocol::AuthoringFrame::Closed { identity, reason } => Self::Closed {
                identity: identity.into(),
                reason: reason.into(),
            },
        }
    }
}
