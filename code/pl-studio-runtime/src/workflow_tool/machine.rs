use super::{
    CompiledWorkflowDefinition, WorkflowAllowedTransition, WorkflowBinding, WorkflowSessionState,
    WorkflowStateBrief, WorkflowTransitionError, WorkflowTransitionRecord,
};
use crate::PureError;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::fmt::Write as _;

use super::new_run;
use super::output::{
    WorkflowCurrentSnapshot, WorkflowGraphSnapshot, WorkflowHistorySnapshot,
    WorkflowMutationResponse, WorkflowNextSnapshot,
};
use super::state::{
    archive_run, commit_operation_receipt, lifecycle_for_state, operation_receipt, trim_history,
    validate_session_state_size,
};

pub(super) const MAX_REASON_BYTES: usize = 2 * 1024;
pub(super) const MAX_SUMMARY_BYTES: usize = 8 * 1024;
pub(super) const MAX_EVIDENCE_ITEMS: usize = 16;
pub(super) const MAX_EVIDENCE_ITEM_BYTES: usize = 2 * 1024;

#[derive(Debug)]
pub(crate) struct WorkflowOperation {
    pub turn_id: String,
    pub call_id: String,
}

#[derive(Debug, Clone)]
pub(crate) struct WorkflowMachine {
    state: WorkflowSessionState,
    binding: WorkflowBinding,
}

impl WorkflowMachine {
    pub fn new(binding: WorkflowBinding, state: WorkflowSessionState) -> Self {
        Self { binding, state }
    }

    pub fn state(&self) -> &WorkflowSessionState {
        &self.state
    }

    pub fn into_state(self) -> WorkflowSessionState {
        self.state
    }

    pub fn graph(&self) -> &CompiledWorkflowDefinition {
        &self.binding.graph
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

    pub fn current_snapshot(&self) -> WorkflowCurrentSnapshot {
        let state = &self.state;
        let all_states = self.all_states_brief();
        match &state.current_run {
            None => WorkflowCurrentSnapshot::Inactive {
                revision: state.revision,
                mode_id: self.binding.mode_id.clone(),
                current_run: (),
                all_states,
                allowed_transitions: [],
            },
            Some(run) => WorkflowCurrentSnapshot::Run {
                revision: state.revision,
                mode_id: run.mode_id.clone(),
                run_id: run.run_id.clone(),
                lineage_id: run.lineage_id.clone(),
                graph_revision: run.graph_revision,
                graph_hash: run.graph_hash.clone(),
                lifecycle: run.lifecycle,
                current_state_id: run.current_state_id.clone(),
                current_state: self
                    .graph()
                    .state(&run.current_state_id)
                    .cloned()
                    .map(Box::new),
                allowed_transitions: self.allowed_transitions_for_state(&run.current_state_id),
                all_states,
                updated_at: run.updated_at,
            },
        }
    }

    pub fn next_snapshot(&self) -> WorkflowNextSnapshot<'_> {
        let state = &self.state;
        let all_states = self.all_states_brief();
        match &state.current_run {
            None => WorkflowNextSnapshot::Inactive {
                revision: state.revision,
                mode_id: &self.binding.mode_id,
                current_run: (),
                all_states,
                allowed_transitions: [],
                transitions: [],
            },
            Some(run) => WorkflowNextSnapshot::Run {
                revision: state.revision,
                mode_id: &run.mode_id,
                run_id: &run.run_id,
                current_state_id: &run.current_state_id,
                transitions: self.graph().outgoing(&run.current_state_id),
                allowed_transitions: self.allowed_transitions_for_state(&run.current_state_id),
                all_states,
            },
        }
    }

    pub fn graph_snapshot(&self) -> WorkflowGraphSnapshot<'_> {
        WorkflowGraphSnapshot {
            revision: self.state.revision,
            mode_id: &self.binding.mode_id,
            graph_revision: self.binding.graph_revision,
            graph_hash: self.graph().graph_hash(),
            definition: self.graph().definition(),
        }
    }

    pub fn history_snapshot(&self) -> WorkflowHistorySnapshot<'_> {
        let state = &self.state;
        match &state.current_run {
            None => WorkflowHistorySnapshot::Inactive {
                revision: state.revision,
                current_run: (),
            },
            Some(run) => WorkflowHistorySnapshot::Run {
                revision: state.revision,
                mode_id: &run.mode_id,
                run_id: &run.run_id,
                history: &run.history_tail,
                archived_transition_count: run.archived_transition_count,
                archived_transition_digest: &run.archived_transition_digest,
                archived_runs: &state.archived_runs,
                archived_run_count: state.archived_run_count,
                archived_run_digest: &state.archived_run_digest,
            },
        }
    }

    pub fn apply_transition(
        &mut self,
        input: TransitionInput,
        identity: &WorkflowOperation,
        argument_hash: String,
        now_secs: i64,
    ) -> Result<WorkflowMutationResponse, PureError> {
        let operation_id = operation_id(identity);
        if let Some(response) = idempotent_response(self, &operation_id, &argument_hash) {
            return Ok(response);
        }
        if let Some(response) = validate_cas(self, &input.cas()) {
            return Ok(response);
        }
        if let Some(message) = validate_completion(&input.completion) {
            return Ok(self.rejected(
                "invalidCompletion",
                Some(&input.target_state_id),
                message,
                message,
            ));
        }
        let run = self
            .state
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
                self.binding.mode_id,
                format_all_states(&all_states),
                format_allowed_transitions(&allowed),
            );
            return Ok(self.rejected(
                "unknownTargetState",
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
                Some(&input.target_state_id),
                message,
                recovery,
            ));
        }
        let target_id = input.target_state_id.clone();
        let forced = input.force;
        let mut state = self.state.clone();
        let next_revision = state.revision.saturating_add(1);
        let run = state
            .current_run
            .as_mut()
            .expect("validated CAS requires a run");
        let source_state_id = run.current_state_id.clone();
        run.current_state_id = target_id.clone();
        run.lifecycle = lifecycle_for_state(target_kind);
        run.updated_at = now_secs;
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
            transitioned_at: now_secs,
        });
        trim_history(run)?;
        commit_operation_receipt(&mut state, operation_id, argument_hash, next_revision);
        validate_session_state_size(&state)?;
        self.state = state;
        Ok(self.accepted("transitioned", forced))
    }

    pub fn apply_restart(
        &mut self,
        input: RestartInput,
        identity: &WorkflowOperation,
        argument_hash: String,
        now_secs: i64,
    ) -> Result<WorkflowMutationResponse, PureError> {
        let operation_id = operation_id(identity);
        if let Some(response) = idempotent_response(self, &operation_id, &argument_hash) {
            return Ok(response);
        }
        if let Some(response) = validate_cas(self, &input.cas()) {
            return Ok(response);
        }
        if input.reason.trim().is_empty() || input.reason.len() > MAX_REASON_BYTES {
            let msg = "reason must be non-empty and within the documented limit";
            return Ok(self.rejected("invalidReason", None, msg, msg));
        }
        let mut state = self.state.clone();
        let old = state
            .current_run
            .take()
            .expect("validated CAS requires a run");
        let next_revision = state.revision.saturating_add(1);
        archive_run(&mut state, old, "restarted", input.reason.trim(), now_secs)?;
        let seed = format!("{operation_id}:{argument_hash}:{next_revision}");
        state.current_run = Some(new_run(&self.binding, None, &seed, now_secs));
        commit_operation_receipt(&mut state, operation_id, argument_hash, next_revision);
        validate_session_state_size(&state)?;
        self.state = state;
        Ok(self.accepted("restarted", false))
    }

    fn accepted(&self, code: &'static str, forced: bool) -> WorkflowMutationResponse {
        WorkflowMutationResponse::Accepted {
            accepted: true,
            code,
            forced,
            operation_revision: self.state.revision,
            snapshot: self.current_snapshot(),
        }
    }

    fn rejected(
        &self,
        code: &'static str,
        attempted_target_state_id: Option<&str>,
        message: impl Into<String>,
        recovery_action: impl Into<String>,
    ) -> WorkflowMutationResponse {
        let message = message.into();
        let recovery_action = recovery_action.into();
        let current_state_id = self
            .state
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
        WorkflowMutationResponse::Rejected {
            accepted: false,
            code,
            forced: false,
            operation_revision: self.state.revision,
            snapshot: self.current_snapshot(),
            recovery_action: recovery_action.clone(),
            error: Box::new(WorkflowTransitionError {
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

struct WorkflowCas<'a> {
    expected_run_id: &'a str,
    expected_revision: u64,
    expected_state_id: &'a str,
}

fn validate_cas(
    runtime: &WorkflowMachine,
    cas: &WorkflowCas<'_>,
) -> Option<WorkflowMutationResponse> {
    let state = runtime.state();
    let Some(run) = &state.current_run else {
        let msg = "Wait for the root Turn bootstrap before mutating workflow state.";
        return Some(runtime.rejected("workflowNotStarted", None, msg, msg));
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
    } else if run.mode_id != runtime.binding.mode_id
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
    operation_id: &str,
    argument_hash: &str,
) -> Option<WorkflowMutationResponse> {
    operation_receipt(runtime.state(), operation_id).map(|receipt| {
        if receipt.argument_hash == argument_hash {
            runtime.accepted("alreadyApplied", false)
        } else {
            let msg = "Retry with a new tool call identity.";
            runtime.rejected("operationIdentityConflict", None, msg, msg)
        }
    })
}

fn operation_id(identity: &WorkflowOperation) -> String {
    format!("{}/{}", identity.turn_id, identity.call_id)
}

#[cfg(test)]
#[path = "machine_tests.rs"]
mod tests;
