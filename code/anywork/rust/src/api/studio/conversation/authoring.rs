use crate::api::studio::types::{BridgeError, BridgePlanPhase, BridgeWorkflowRunLifecycle};
use super::identity::*;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAuthoringBaseline {
    pub todo: Option<BridgeTodoBrief>,
    pub plan: Option<BridgePlanBrief>,
    pub workflow: Option<BridgeWorkflowBrief>,
    pub progress: BridgeThreadCapabilitySupport,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTodoBrief {
    pub reference: BridgeTodoReadRef,
    pub item_count: u64,
    pub has_call_id: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePlanBrief {
    pub revision: u64,
    pub state: BridgePlanPhase,
    pub document: Option<BridgePlanDocumentRef>,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePlanDocumentRef { pub version: u64, pub content_hash: String }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWorkflowBrief {
    pub reference: BridgeWorkflowReadRef,
    pub revision: u64,
    pub has_current_run: bool,
    pub lifecycle: Option<BridgeWorkflowRunLifecycle>,
    pub mode_deleted: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAuthoringChange {
    pub todo: BridgeTodoReplacement,
    pub plan: BridgePlanReplacement,
    pub workflow: BridgeWorkflowReplacement,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTodoReplacement { Unchanged, Replace { value: Option<BridgeTodoBrief> } }
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgePlanReplacement { Unchanged, Replace { value: Option<BridgePlanBrief> } }
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeWorkflowReplacement { Unchanged, Replace { value: Option<BridgeWorkflowBrief> } }

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAuthoringEvent {
    Baseline { identity: BridgeThreadFeedIdentity, stamp: BridgeThreadFacetStamp, value: BridgeAuthoringBaseline },
    Change { stamp: BridgeThreadFacetStamp, base_revision: u64, value: BridgeAuthoringChange },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAuthoringFrame {
    Data { delivery_sequence: u64, event: BridgeAuthoringEvent },
    ResyncRequired { identity: BridgeThreadFeedIdentity, reason: BridgeResyncReason },
    Failure { identity: BridgeThreadFeedIdentity, error: BridgeError },
    Closed { identity: BridgeThreadFeedIdentity, reason: BridgeFeedClosedReason },
}
