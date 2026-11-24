use std::fmt::Write as _;
use std::sync::Arc;

use crate::PureError;
use crate::workflow_tool::{
    WorkflowAllowedTransition, WorkflowDefinition, WorkflowRunArchive, WorkflowRunLifecycle,
    WorkflowSessionState, WorkflowState, WorkflowStateBrief, WorkflowTransition,
    WorkflowTransitionError, WorkflowTransitionRecord,
};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::mode::new_run;
use crate::mode::state::{
    archive_run, commit_operation_receipt, lifecycle_for_state, operation_receipt, trim_history,
};
use crate::mode::{RegisteredThreadMode, ThreadModeId};

pub(super) const MAX_REASON_BYTES: usize = 2 * 1024;
pub(super) const MAX_SUMMARY_BYTES: usize = 8 * 1024;
pub(super) const MAX_EVIDENCE_ITEMS: usize = 16;
pub(super) const MAX_EVIDENCE_ITEM_BYTES: usize = 2 * 1024;

#[derive(Debug)]
pub(crate) struct WorkflowOperation {
    pub turn_id: String,
    pub call_id: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct WorkflowQuery<'a> {
    revision: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    mode_id: Option<&'a ThreadModeId>,
    #[serde(flatten)]
    body: WorkflowQueryBody<'a>,
}

#[derive(Serialize)]
#[serde(untagged, rename_all_fields = "camelCase")]
enum WorkflowQueryBody<'a> {
    Inactive {
        current_run: Option<()>,
        #[serde(skip_serializing_if = "Option::is_none")]
        all_states: Option<Vec<WorkflowStateBrief>>,
        #[serde(skip_serializing_if = "Option::is_none")]
        allowed_transitions: Option<&'a [WorkflowAllowedTransition]>,
        #[serde(skip_serializing_if = "Option::is_none")]
        transitions: Option<&'a [WorkflowTransition]>,
    },
    Current {
        run_id: &'a str,
        lineage_id: &'a str,
        graph_revision: u64,
        graph_hash: &'a str,
        lifecycle: WorkflowRunLifecycle,
        current_state_id: &'a str,
        current_state: Option<&'a WorkflowState>,
        allowed_transitions: Vec<WorkflowAllowedTransition>,
        all_states: Vec<WorkflowStateBrief>,
        updated_at: i64,
    },
    Next {
        run_id: &'a str,
        current_state_id: &'a str,
        transitions: Vec<&'a WorkflowTransition>,
        allowed_transitions: Vec<WorkflowAllowedTransition>,
        all_states: Vec<WorkflowStateBrief>,
    },
    Graph {
        graph_revision: u64,
        graph_hash: &'a str,
        definition: &'a WorkflowDefinition,
    },
    History {
        run_id: &'a str,
        history: &'a [WorkflowTransitionRecord],
        archived_transition_count: u64,
        archived_transition_digest: &'a str,
        archived_runs: &'a [WorkflowRunArchive],
        archived_run_count: u64,
        archived_run_digest: &'a str,
    },
}

impl WorkflowQuery<'_> {
    fn into_json(self) -> serde_json::Value {
        serde_json::to_value(self).expect("workflow query contains only serializable product facts")
    }
}

#[derive(Debug, Clone)]
pub(crate) struct WorkflowMachine {
    state: WorkflowSessionState,
    pub mode: Arc<RegisteredThreadMode>,
}

impl WorkflowMachine {
    pub fn new(mode: Arc<RegisteredThreadMode>, state: WorkflowSessionState) -> Self {
        Self { mode, state }
    }

    pub fn state(&self) -> WorkflowSessionState {
        self.state.clone()
    }

    pub fn graph(&self) -> &crate::mode::CompiledWorkflowDefinition {
        self.mode
            .workflow()
            .expect("workflow tools require a registered graph")
    }

    pub fn all_states_brief(&self) -> Vec<WorkflowStateBrief> {
        self.graph()
            .definition()
            .states
            .iter()
            .map(|state| WorkflowStateBrief {
                id: state.id.clone(),
                title: state.title.clone(),
                kind: state.kind,
            })
            .collect()
    }

    pub fn allowed_transitions_for_state(&self, state_id: &str) -> Vec<WorkflowAllowedTransition> {
        let graph = self.graph();
        graph
            .outgoing(state_id)
            .into_iter()
            .filter_map(|edge| {
                let target = graph.state(&edge.target_state_id)?;
                Some(WorkflowAllowedTransition {
                    target_state_id: edge.target_state_id.clone(),
                    target_state_title: target.title.clone(),
                    target_kind: target.kind,
                    guard: edge.guard.clone(),
                })
            })
            .collect()
    }

    pub fn current_snapshot(&self, state: &WorkflowSessionState) -> serde_json::Value {
        let all_states = self.all_states_brief();
        let (mode_id, body) = match &state.current_run {
            None => (
                &self.mode.descriptor().id,
                WorkflowQueryBody::Inactive {
                    current_run: None,
                    all_states: Some(all_states),
                    allowed_transitions: Some(&[]),
                    transitions: None,
                },
            ),
            Some(run) => (
                &run.mode_id,
                WorkflowQueryBody::Current {
                    run_id: &run.run_id,
                    lineage_id: &run.lineage_id,
                    graph_revision: run.graph_revision,
                    graph_hash: &run.graph_hash,
                    lifecycle: run.lifecycle,
                    current_state_id: &run.current_state_id,
                    current_state: self.graph().state(&run.current_state_id),
                    allowed_transitions: self.allowed_transitions_for_state(&run.current_state_id),
                    all_states,
                    updated_at: run.updated_at,
                },
            ),
        };
        WorkflowQuery {
            revision: state.revision,
            mode_id: Some(mode_id),
            body,
        }
        .into_json()
    }

    pub fn next_snapshot(&self, state: &WorkflowSessionState) -> serde_json::Value {
        let all_states = self.all_states_brief();
        let (mode_id, body) = match &state.current_run {
            None => (
                &self.mode.descriptor().id,
                WorkflowQueryBody::Inactive {
                    current_run: None,
                    all_states: Some(all_states),
                    allowed_transitions: Some(&[]),
                    transitions: Some(&[]),
                },
            ),
            Some(run) => (
                &run.mode_id,
                WorkflowQueryBody::Next {
                    run_id: &run.run_id,
                    current_state_id: &run.current_state_id,
                    transitions: self.graph().outgoing(&run.current_state_id),
                    allowed_transitions: self.allowed_transitions_for_state(&run.current_state_id),
                    all_states,
                },
            ),
        };
        WorkflowQuery {
            revision: state.revision,
            mode_id: Some(mode_id),
            body,
        }
        .into_json()
    }

    pub fn graph_snapshot(&self, state: &WorkflowSessionState) -> serde_json::Value {
        WorkflowQuery {
            revision: state.revision,
            mode_id: Some(&self.mode.descriptor().id),
            body: WorkflowQueryBody::Graph {
                graph_revision: self.mode.graph_revision(),
                graph_hash: self.graph().graph_hash(),
                definition: self.graph().definition(),
            },
        }
        .into_json()
    }

    pub fn history_snapshot(&self, state: &WorkflowSessionState) -> serde_json::Value {
        let (mode_id, body) = match &state.current_run {
            None => (
                None,
                WorkflowQueryBody::Inactive {
                    current_run: None,
                    all_states: None,
                    allowed_transitions: None,
                    transitions: None,
                },
            ),
            Some(run) => (
                Some(&run.mode_id),
                WorkflowQueryBody::History {
                    run_id: &run.run_id,
                    history: &run.history_tail,
                    archived_transition_count: run.archived_transition_count,
                    archived_transition_digest: &run.archived_transition_digest,
                    archived_runs: &state.archived_runs,
                    archived_run_count: state.archived_run_count,
                    archived_run_digest: &state.archived_run_digest,
                },
            ),
        };
        WorkflowQuery {
            revision: state.revision,
            mode_id,
            body,
        }
        .into_json()
    }

    pub fn apply_transition(
        &mut self,
        input: TransitionInput,
        identity: &WorkflowOperation,
        argument_hash: String,
    ) -> Result<WorkflowMutationResponse, PureError> {
        let mut state = self.state.clone();
        let operation_id = operation_id(identity);
        if let Some(response) = idempotent_response(self, &state, &operation_id, &argument_hash) {
            return Ok(response);
        }
        if let Some(response) = validate_cas(self, &state, &input.cas()) {
            return Ok(response);
        }
        if let Some(message) = validate_completion(&input.completion) {
            return Ok(self.rejected(
                "invalidCompletion",
                &state,
                Some(&input.target_state_id),
                message,
                message,
            ));
        }
        let run = state
            .current_run
            .as_ref()
            .expect("validated CAS requires a run");
        let current_state_id = run.current_state_id.clone();
        let Some(target_state) = self.graph().state(&input.target_state_id) else {
            let all_states = self.all_states_brief();
            let allowed = self.allowed_transitions_for_state(&current_state_id);
            let message = format!(
                "Unknown workflow targetStateId `{}` from `{}`. Valid states in `{}`: [{}]. Allowed direct transitions: [{}].",
                input.target_state_id,
                current_state_id,
                self.mode.descriptor().id,
                format_all_states(&all_states),
                format_allowed_transitions(&allowed),
            );
            return Ok(self.rejected(
                "unknownTargetState",
                &state,
                Some(&input.target_state_id),
                message,
                format!(
                    "Select a valid targetStateId from: [{}].",
                    all_states
                        .iter()
                        .map(|s| s.id.as_str())
                        .collect::<Vec<_>>()
                        .join(", ")
                ),
            ));
        };
        let target_kind = target_state.kind;
        let target_title = target_state.title.clone();
        let direct_edge = self
            .graph()
            .transition(&current_state_id, &input.target_state_id);
        if direct_edge.is_none() && !input.force {
            let current_title = self
                .graph()
                .state(&current_state_id)
                .map_or("", |s| s.title.as_str());
            let allowed = self.allowed_transitions_for_state(&current_state_id);
            let all_states = self.all_states_brief();
            let allowed_ids = allowed
                .iter()
                .map(|t| t.target_state_id.as_str())
                .collect::<Vec<_>>()
                .join(", ");
            let message = format!(
                "Cannot transition workflow from `{current_state_id}` ({current_title}) to `{}` ({target_title}) without force=true. Allowed next states from `{current_state_id}`: [{}]. All workflow states: [{}]. Pass force=true only when an out-of-path jump is intentionally needed.",
                input.target_state_id,
                format_allowed_transitions(&allowed),
                format_all_states(&all_states),
            );
            let recovery = if allowed.is_empty() {
                "Current state is terminal (no direct outgoing transitions). Pass force=true to jump explicitly to any valid state, or call workflow_restart to begin a new run."
                    .to_string()
            } else {
                format!(
                    "Choose an allowed direct targetStateId [{allowed_ids}], or pass force=true to override transition rules."
                )
            };
            return Ok(self.rejected(
                "transitionNotAllowed",
                &state,
                Some(&input.target_state_id),
                message,
                recovery,
            ));
        }
        let target_id = input.target_state_id.clone();
        let forced = input.force;
        let next_revision = state.revision.saturating_add(1);
        let now = crate::studio::unix_seconds();
        let run = state
            .current_run
            .as_mut()
            .expect("validated CAS requires a run");
        let source_state_id = run.current_state_id.clone();
        run.current_state_id = target_id.clone();
        run.lifecycle = lifecycle_for_state(target_kind);
        run.updated_at = now;
        run.history_tail.push(WorkflowTransitionRecord {
            revision: next_revision,
            source_state_id,
            target_state_id: target_id,
            forced,
            reason: input.completion.reason.trim().to_string(),
            summary: input.completion.summary.trim().to_string(),
            evidence: input
                .completion
                .evidence
                .into_iter()
                .map(|item| item.trim().to_string())
                .collect(),
            turn_id: identity.turn_id.clone(),
            call_id: identity.call_id.clone(),
            transitioned_at: now,
        });
        trim_history(run)?;
        commit_operation_receipt(&mut state, operation_id, argument_hash, next_revision);
        crate::mode::state::validate_session_state_size(&state)?;
        self.state = state.clone();
        Ok(self.accepted("transitioned", forced, &state))
    }

    pub fn apply_restart(
        &mut self,
        input: RestartInput,
        identity: &WorkflowOperation,
        argument_hash: String,
    ) -> Result<WorkflowMutationResponse, PureError> {
        let mut state = self.state.clone();
        let operation_id = operation_id(identity);
        if let Some(response) = idempotent_response(self, &state, &operation_id, &argument_hash) {
            return Ok(response);
        }
        if let Some(response) = validate_cas(self, &state, &input.cas()) {
            return Ok(response);
        }
        if input.reason.trim().is_empty() || input.reason.len() > MAX_REASON_BYTES {
            let msg = "reason must be non-empty and within the documented limit";
            return Ok(self.rejected("invalidReason", &state, None, msg, msg));
        }
        let old = state
            .current_run
            .take()
            .expect("validated CAS requires a run");
        let next_revision = state.revision.saturating_add(1);
        let now = crate::studio::unix_seconds();
        archive_run(&mut state, old, "restarted", input.reason.trim(), now)?;
        let seed = format!("{operation_id}:{argument_hash}:{next_revision}");
        state.current_run = Some(new_run(&self.mode, self.graph(), None, &seed, now));
        commit_operation_receipt(&mut state, operation_id, argument_hash, next_revision);
        crate::mode::state::validate_session_state_size(&state)?;
        self.state = state.clone();
        Ok(self.accepted("restarted", false, &state))
    }

    fn accepted(
        &self,
        code: &'static str,
        forced: bool,
        state: &WorkflowSessionState,
    ) -> WorkflowMutationResponse {
        WorkflowMutationResponse {
            accepted: true,
            code,
            forced,
            operation_revision: state.revision,
            snapshot: self.current_snapshot(state),
            recovery_action: None,
            error: None,
        }
    }

    fn rejected(
        &self,
        code: &'static str,
        state: &WorkflowSessionState,
        attempted_target_state_id: Option<&str>,
        message: impl Into<String>,
        recovery_action: impl Into<String>,
    ) -> WorkflowMutationResponse {
        let message = message.into();
        let recovery_action = recovery_action.into();
        let current_state_id = state
            .current_run
            .as_ref()
            .map(|run| run.current_state_id.clone());
        let current_state_title = current_state_id
            .as_deref()
            .and_then(|id| self.graph().state(id))
            .map(|state| state.title.clone());
        let allowed_transitions = current_state_id
            .as_deref()
            .map(|id| self.allowed_transitions_for_state(id))
            .unwrap_or_default();
        let all_states = self.all_states_brief();
        WorkflowMutationResponse {
            accepted: false,
            code,
            forced: false,
            operation_revision: state.revision,
            snapshot: self.current_snapshot(state),
            recovery_action: Some(recovery_action.clone()),
            error: Some(WorkflowTransitionError {
                code: code.to_string(),
                message,
                current_state_id,
                current_state_title,
                attempted_target_state_id: attempted_target_state_id.map(str::to_string),
                allowed_transitions,
                all_states,
                recovery_action,
            }),
        }
    }
}

fn format_allowed_transitions(allowed: &[WorkflowAllowedTransition]) -> String {
    if allowed.is_empty() {
        return "none".to_string();
    }
    let mut out = String::new();
    for (idx, item) in allowed.iter().enumerate() {
        if idx > 0 {
            out.push_str(", ");
        }
        let _ = write!(
            out,
            "{} ({}): {}",
            item.target_state_id, item.target_state_title, item.guard
        );
    }
    out
}

fn format_all_states(states: &[WorkflowStateBrief]) -> String {
    let mut out = String::new();
    for (idx, state) in states.iter().enumerate() {
        if idx > 0 {
            out.push_str(", ");
        }
        let _ = write!(out, "{} ({})", state.id, state.title);
    }
    out
}

#[derive(Debug, Default, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct EmptyInput {}

#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TransitionInput {
    /// Current run returned by `workflow_current`.
    pub expected_run_id: String,
    /// Current workflow revision returned by `workflow_current`.
    pub expected_revision: u64,
    /// Current state returned by `workflow_current`.
    pub expected_state_id: String,
    /// Target state ID (must be an outgoing edge from `workflow_next` unless `force` is true).
    pub target_state_id: String,
    /// Bypass workflow edge and terminal-state rules to jump to any valid state ID in the graph (default: false). Use only when intentionally overriding normal flow.
    #[serde(default)]
    pub force: bool,
    /// Exactly three keys: reason explains why the selected guard holds; summary describes the phase outcome; evidence is an array of supporting records.
    pub completion: CompletionInput,
}

impl TransitionInput {
    fn cas(&self) -> WorkflowCas<'_> {
        WorkflowCas {
            expected_run_id: &self.expected_run_id,
            expected_revision: self.expected_revision,
            expected_state_id: &self.expected_state_id,
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[schemars(inline)]
pub struct CompletionInput {
    /// Why the current state's criteria and selected edge guard are satisfied.
    pub reason: String,
    /// Concise result produced while completing the current state.
    pub summary: String,
    /// Concrete checks, receipts, or artifacts supporting the declaration.
    #[serde(default)]
    pub evidence: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RestartInput {
    pub expected_run_id: String,
    pub expected_revision: u64,
    pub expected_state_id: String,
    pub reason: String,
}

impl RestartInput {
    fn cas(&self) -> WorkflowCas<'_> {
        WorkflowCas {
            expected_run_id: &self.expected_run_id,
            expected_revision: self.expected_revision,
            expected_state_id: &self.expected_state_id,
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct WorkflowMutationResponse {
    pub accepted: bool,
    pub code: &'static str,
    pub forced: bool,
    pub operation_revision: u64,
    pub snapshot: serde_json::Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recovery_action: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<WorkflowTransitionError>,
}

struct WorkflowCas<'a> {
    expected_run_id: &'a str,
    expected_revision: u64,
    expected_state_id: &'a str,
}

fn validate_cas(
    runtime: &WorkflowMachine,
    state: &WorkflowSessionState,
    cas: &WorkflowCas<'_>,
) -> Option<WorkflowMutationResponse> {
    let Some(run) = &state.current_run else {
        let msg = "Wait for the root Turn bootstrap before mutating workflow state.";
        return Some(runtime.rejected("workflowNotStarted", state, None, msg, msg));
    };
    let mismatch = if run.run_id != cas.expected_run_id {
        Some((
            "runMismatch",
            format!(
                "expectedRunId `{}` does not match active run `{}`.",
                cas.expected_run_id, run.run_id
            ),
        ))
    } else if state.revision != cas.expected_revision {
        Some((
            "staleRevision",
            format!(
                "expectedRevision {} does not match current revision {}.",
                cas.expected_revision, state.revision
            ),
        ))
    } else if run.current_state_id != cas.expected_state_id {
        Some((
            "stateMismatch",
            format!(
                "expectedStateId `{}` does not match current state `{}`.",
                cas.expected_state_id, run.current_state_id
            ),
        ))
    } else if run.mode_id != runtime.mode.descriptor().id
        || run.graph_hash != runtime.graph().graph_hash()
    {
        Some((
            "modeSnapshotMismatch",
            "active run mode or graph hash differs from frozen Mode snapshot.".to_string(),
        ))
    } else {
        None
    };
    mismatch.map(|(code, msg)| {
        runtime.rejected(
            code,
            state,
            None,
            msg,
            "Call workflow_current and retry with its canonical runId, revision, and currentStateId.",
        )
    })
}

fn validate_completion(completion: &CompletionInput) -> Option<&'static str> {
    if completion.reason.trim().is_empty() || completion.reason.len() > MAX_REASON_BYTES {
        return Some("reason must be non-empty and within the documented limit");
    }
    if completion.summary.trim().is_empty() || completion.summary.len() > MAX_SUMMARY_BYTES {
        return Some("completion summary must be non-empty and within the documented limit");
    }
    if completion.evidence.len() > MAX_EVIDENCE_ITEMS
        || completion
            .evidence
            .iter()
            .any(|item| item.trim().is_empty() || item.len() > MAX_EVIDENCE_ITEM_BYTES)
    {
        return Some("completion evidence is empty, too large, or contains too many items");
    }
    None
}

fn idempotent_response(
    runtime: &WorkflowMachine,
    state: &WorkflowSessionState,
    operation_id: &str,
    argument_hash: &str,
) -> Option<WorkflowMutationResponse> {
    operation_receipt(state, operation_id).map(|receipt| {
        if receipt.argument_hash == argument_hash {
            runtime.accepted("alreadyApplied", false, state)
        } else {
            let msg = "Retry with a new tool call identity.";
            runtime.rejected("operationIdentityConflict", state, None, msg, msg)
        }
    })
}

fn operation_id(identity: &WorkflowOperation) -> String {
    format!("{}/{}", identity.turn_id, identity.call_id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mode::ThreadModeManager;
    use crate::studio::thread::register_builtins;
    use crate::workflow_tool::WorkflowRunLifecycle;

    fn auto_machine() -> WorkflowMachine {
        let manager = ThreadModeManager::default();
        let catalog = register_builtins(&manager).expect("builtin auto mode");
        let mode = catalog
            .mode(&crate::mode::ThreadModeId::auto())
            .expect("mode.auto registered")
            .clone();
        let compiled = mode.workflow().expect("mode.auto has workflow");
        let run = new_run(&mode, compiled, None, "test-seed", 100);
        let state = WorkflowSessionState {
            revision: 1,
            current_run: Some(run),
            archived_runs: Vec::new(),
            archived_run_count: 0,
            archived_run_digest: String::new(),
            operation_receipts: Vec::new(),
        };
        WorkflowMachine::new(mode, state)
    }

    fn completion(reason: &str) -> CompletionInput {
        CompletionInput {
            reason: reason.into(),
            summary: "stage summary".into(),
            evidence: vec!["unit test evidence".into()],
        }
    }

    #[test]
    fn non_forced_unknown_target_and_disallowed_transition_return_rich_hints() {
        let mut machine = auto_machine();
        let state = machine.state();
        let run = state.current_run.as_ref().unwrap();
        let err_unknown = machine
            .apply_transition(
                TransitionInput {
                    expected_run_id: run.run_id.clone(),
                    expected_revision: state.revision,
                    expected_state_id: "triage".into(),
                    target_state_id: "nonexistent".into(),
                    force: false,
                    completion: completion("invalid target"),
                },
                &WorkflowOperation {
                    turn_id: "t1".into(),
                    call_id: "c1".into(),
                },
                "h1".into(),
            )
            .unwrap();
        assert!(!err_unknown.accepted);
        assert_eq!(err_unknown.code, "unknownTargetState");
        let error = err_unknown.error.expect("structured error");
        assert!(error.all_states.iter().any(|s| s.id == "simple"));
        assert!(error.all_states.iter().any(|s| s.id == "planning"));
        assert!(!error.allowed_transitions.is_empty());

        let err_disallowed = machine
            .apply_transition(
                TransitionInput {
                    expected_run_id: run.run_id.clone(),
                    expected_revision: state.revision,
                    expected_state_id: "triage".into(),
                    target_state_id: "completed".into(),
                    force: false,
                    completion: completion("skip directly"),
                },
                &WorkflowOperation {
                    turn_id: "t1".into(),
                    call_id: "c2".into(),
                },
                "h2".into(),
            )
            .unwrap();
        assert!(!err_disallowed.accepted);
        assert_eq!(err_disallowed.code, "transitionNotAllowed");
        assert!(
            err_disallowed
                .recovery_action
                .as_deref()
                .unwrap_or_default()
                .contains("force=true")
        );
        let error = err_disallowed.error.expect("structured error");
        assert_eq!(error.current_state_id.as_deref(), Some("triage"));
        assert_eq!(
            error.attempted_target_state_id.as_deref(),
            Some("completed")
        );
        assert!(
            error
                .allowed_transitions
                .iter()
                .any(|edge| edge.target_state_id == "simple" && !edge.guard.is_empty())
        );
        assert!(
            error
                .allowed_transitions
                .iter()
                .any(|edge| edge.target_state_id == "planning" && !edge.guard.is_empty())
        );
    }

    #[test]
    fn forced_transition_jumps_anywhere_including_out_of_final_state() {
        let mut machine = auto_machine();
        let run_id = machine.state().current_run.unwrap().run_id;
        // Forced jump directly from `triage` to terminal `completed`.
        let jump_final = machine
            .apply_transition(
                TransitionInput {
                    expected_run_id: run_id.clone(),
                    expected_revision: 1,
                    expected_state_id: "triage".into(),
                    target_state_id: "completed".into(),
                    force: true,
                    completion: completion("force complete"),
                },
                &WorkflowOperation {
                    turn_id: "t1".into(),
                    call_id: "c1".into(),
                },
                "h1".into(),
            )
            .unwrap();
        assert!(jump_final.accepted);
        assert!(jump_final.forced);
        assert_eq!(
            machine.state().current_run.as_ref().unwrap().lifecycle,
            WorkflowRunLifecycle::Terminal
        );

        // Forced jump out of terminal `completed` back into `planning`.
        let jump_back = machine
            .apply_transition(
                TransitionInput {
                    expected_run_id: run_id,
                    expected_revision: machine.state().revision,
                    expected_state_id: "completed".into(),
                    target_state_id: "planning".into(),
                    force: true,
                    completion: completion("reopen into planning"),
                },
                &WorkflowOperation {
                    turn_id: "t2".into(),
                    call_id: "c2".into(),
                },
                "h2".into(),
            )
            .unwrap();
        assert!(jump_back.accepted);
        assert!(jump_back.forced);
        let run = machine.state().current_run.unwrap();
        assert_eq!(run.current_state_id, "planning");
        assert_eq!(run.lifecycle, WorkflowRunLifecycle::Active);
        assert!(run.history_tail.iter().all(|rec| rec.forced));
    }
}
