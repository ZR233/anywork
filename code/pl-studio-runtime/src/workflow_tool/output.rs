use super::{
    WorkflowAllowedTransition, WorkflowDefinition, WorkflowRunArchive, WorkflowRunLifecycle,
    WorkflowState, WorkflowStateBrief, WorkflowTransition, WorkflowTransitionError,
    WorkflowTransitionRecord,
};
use crate::thread_mode_id::ThreadModeId;
use schemars::JsonSchema;
use serde::Serialize;

#[derive(Debug, Serialize, JsonSchema)]
#[serde(untagged, rename_all_fields = "camelCase", deny_unknown_fields)]
pub(crate) enum WorkflowCurrentSnapshot {
    Inactive {
        revision: u64,
        mode_id: ThreadModeId,
        current_run: (),
        all_states: Vec<WorkflowStateBrief>,
        allowed_transitions: [WorkflowAllowedTransition; 0],
    },
    Run {
        revision: u64,
        mode_id: ThreadModeId,
        run_id: String,
        lineage_id: String,
        graph_revision: u64,
        graph_hash: String,
        lifecycle: WorkflowRunLifecycle,
        current_state_id: String,
        current_state: Option<Box<WorkflowState>>,
        allowed_transitions: Vec<WorkflowAllowedTransition>,
        all_states: Vec<WorkflowStateBrief>,
        updated_at: i64,
    },
}

#[derive(Serialize, JsonSchema)]
#[serde(untagged, rename_all_fields = "camelCase", deny_unknown_fields)]
pub(crate) enum WorkflowNextSnapshot<'a> {
    Inactive {
        revision: u64,
        mode_id: &'a ThreadModeId,
        current_run: (),
        all_states: Vec<WorkflowStateBrief>,
        allowed_transitions: [WorkflowAllowedTransition; 0],
        transitions: [WorkflowTransition; 0],
    },
    Run {
        revision: u64,
        mode_id: &'a ThreadModeId,
        run_id: &'a str,
        current_state_id: &'a str,
        transitions: Vec<&'a WorkflowTransition>,
        allowed_transitions: Vec<WorkflowAllowedTransition>,
        all_states: Vec<WorkflowStateBrief>,
    },
}

#[derive(Serialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct WorkflowGraphSnapshot<'a> {
    pub(super) revision: u64,
    pub(super) mode_id: &'a ThreadModeId,
    pub(super) graph_revision: u64,
    pub(super) graph_hash: &'a str,
    pub(super) definition: &'a WorkflowDefinition,
}

#[derive(Serialize, JsonSchema)]
#[serde(untagged, rename_all_fields = "camelCase", deny_unknown_fields)]
pub(crate) enum WorkflowHistorySnapshot<'a> {
    Inactive {
        revision: u64,
        current_run: (),
    },
    Run {
        revision: u64,
        mode_id: &'a ThreadModeId,
        run_id: &'a str,
        history: &'a [WorkflowTransitionRecord],
        archived_transition_count: u64,
        archived_transition_digest: &'a str,
        archived_runs: &'a [WorkflowRunArchive],
        archived_run_count: u64,
        archived_run_digest: &'a str,
    },
}

#[derive(Debug, Serialize, JsonSchema)]
#[serde(untagged, rename_all_fields = "camelCase", deny_unknown_fields)]
pub(crate) enum WorkflowMutationResponse {
    Accepted {
        #[schemars(extend("const" = true))]
        accepted: bool,
        code: &'static str,
        forced: bool,
        operation_revision: u64,
        snapshot: WorkflowCurrentSnapshot,
    },
    Rejected {
        #[schemars(extend("const" = false))]
        accepted: bool,
        code: &'static str,
        #[schemars(extend("const" = false))]
        forced: bool,
        operation_revision: u64,
        snapshot: WorkflowCurrentSnapshot,
        recovery_action: String,
        error: Box<WorkflowTransitionError>,
    },
}

#[cfg(test)]
impl WorkflowMutationResponse {
    pub(crate) fn accepted(&self) -> bool {
        matches!(self, Self::Accepted { .. })
    }
}
