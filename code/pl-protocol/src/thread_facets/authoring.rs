use serde::{Deserialize, Serialize};
use crate::{AgentSessionPlanPhase, WorkflowRunLifecycle};
use crate::studio::StudioError;
use super::identity::{TodoReadRef, WorkflowReadRef, ThreadCapabilitySupport, ThreadFeedIdentity, ThreadFacetStamp, ResyncReason, FeedClosedReason};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AuthoringBaseline {
    pub todo: Option<TodoBrief>,
    pub plan: Option<PlanBrief>,
    pub workflow: Option<WorkflowBrief>,
    pub progress: ThreadCapabilitySupport,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TodoBrief {
    pub reference: TodoReadRef,
    pub item_count: u64,
    pub has_call_id: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PlanBrief {
    pub revision: u64,
    pub state: AgentSessionPlanPhase,
    pub document: Option<PlanDocumentRef>,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PlanDocumentRef { pub version: u64, pub content_hash: String }

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowBrief {
    pub reference: WorkflowReadRef,
    pub revision: u64,
    pub has_current_run: bool,
    pub lifecycle: Option<WorkflowRunLifecycle>,
    pub mode_deleted: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AuthoringChange {
    pub todo: TodoReplacement,
    pub plan: PlanReplacement,
    pub workflow: WorkflowReplacement,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", deny_unknown_fields)]
pub enum TodoReplacement { Unchanged, Replace { value: Option<TodoBrief> } }
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", deny_unknown_fields)]
pub enum PlanReplacement { Unchanged, Replace { value: Option<PlanBrief> } }
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", deny_unknown_fields)]
pub enum WorkflowReplacement { Unchanged, Replace { value: Option<WorkflowBrief> } }

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum AuthoringEvent {
    Baseline { identity: ThreadFeedIdentity, stamp: ThreadFacetStamp, value: AuthoringBaseline },
    Change { stamp: ThreadFacetStamp, base_revision: u64, value: AuthoringChange },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum AuthoringFrame {
    Data { delivery_sequence: u64, event: AuthoringEvent },
    ResyncRequired { identity: ThreadFeedIdentity, reason: ResyncReason },
    Failure { identity: ThreadFeedIdentity, error: StudioError },
    Closed { identity: ThreadFeedIdentity, reason: FeedClosedReason },
}
