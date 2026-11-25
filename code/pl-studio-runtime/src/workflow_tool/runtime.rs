//! Workflow run creation and reconciliation with a frozen graph.
use std::sync::Arc;

use super::state::{archive_run, lifecycle_for_state, validate_session_state_size};
use super::{CompiledWorkflowDefinition, WorkflowRun, WorkflowRunLifecycle, WorkflowSessionState};
use crate::PureError;
use crate::thread_mode_id::ThreadModeId;

/// The validated graph and identities needed to run it independently of the mode registry.
#[derive(Debug, Clone)]
pub(crate) struct WorkflowBinding {
    pub(crate) mode_id: ThreadModeId,
    pub(crate) graph_revision: u64,
    pub(crate) graph: Arc<CompiledWorkflowDefinition>,
}

/// 在 root Turn 第一次 provider 请求前，把持久状态与冻结 Mode 快照对齐。
pub(crate) fn reconcile_workflow_for_turn(
    existing: Option<WorkflowSessionState>,
    mode_id: &ThreadModeId,
    binding: Option<WorkflowBinding>,
    identity_seed: &str,
    now: i64,
) -> Result<Option<WorkflowSessionState>, PureError> {
    let mut state = existing.unwrap_or_default();
    let Some(binding) = binding else {
        if let Some(run) = state.current_run.take() {
            let outcome = if &run.mode_id == mode_id {
                "modeUpdated"
            } else {
                "modeChanged"
            };
            archive_run(
                &mut state,
                run,
                outcome,
                "Selected Mode has no workflow",
                now,
            )?;
            state.revision = state.revision.saturating_add(1);
        }
        validate_session_state_size(&state)?;
        return if is_empty_state(&state) {
            Ok(None)
        } else {
            Ok(Some(state))
        };
    };

    let replacement = match state.current_run.as_ref() {
        None => Some((None, "started")),
        Some(run) if run.mode_id != binding.mode_id => Some((None, "modeChanged")),
        Some(run) if run.graph_hash != binding.graph.graph_hash() => {
            Some((Some(run.lineage_id.clone()), "modeUpdated"))
        }
        Some(run) if run.lifecycle == WorkflowRunLifecycle::Terminal => {
            Some((None, "terminalRestart"))
        }
        Some(_) => None,
    };
    if let Some((replacement_lineage, reason)) = replacement {
        if let Some(run) = state.current_run.take() {
            archive_run(&mut state, run, reason, "Started replacement run", now)?;
        }
        let revision = state.revision.saturating_add(1);
        let seed = format!("{identity_seed}:{reason}:{revision}");
        state.current_run = Some(new_run(&binding, replacement_lineage, &seed, now));
        state.revision = revision;
    }
    validate_session_state_size(&state)?;
    Ok(Some(state))
}
/// Creates an initial run from an already validated, frozen mode graph.
pub(crate) fn new_run(
    binding: &WorkflowBinding,
    lineage_id: Option<String>,
    identity_seed: &str,
    now: i64,
) -> WorkflowRun {
    let initial = binding.graph.initial_state();
    WorkflowRun {
        lineage_id: lineage_id.unwrap_or_else(|| generated_id("lineage", identity_seed)),
        run_id: generated_id("run", identity_seed),
        mode_id: binding.mode_id.clone(),
        graph_revision: binding.graph_revision,
        graph_hash: binding.graph.graph_hash().to_string(),
        lifecycle: lifecycle_for_state(initial.kind),
        current_state_id: initial.id.clone(),
        started_at: now,
        updated_at: now,
        history_tail: Vec::new(),
        archived_transition_count: 0,
        archived_transition_digest: String::new(),
    }
}

fn generated_id(prefix: &str, seed: &str) -> String {
    let hash = crate::canonical_content_hash(seed.as_bytes());
    format!("{prefix}-{}", workflow_id_suffix(&hash))
}

fn workflow_id_suffix(content_hash: &str) -> &str {
    // Persisted run and lineage IDs use the first 24 hexadecimal digits of SHA-256.
    const HEX_DIGITS: usize = 24;
    &content_hash
        .strip_prefix("sha256:")
        .expect("canonical content hash is prefixed SHA-256")[..HEX_DIGITS]
}

fn is_empty_state(state: &WorkflowSessionState) -> bool {
    state.revision == 0
        && state.current_run.is_none()
        && state.archived_runs.is_empty()
        && state.archived_run_count == 0
        && state.operation_receipts.is_empty()
}
