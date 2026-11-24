//! 当前 Mode 和轻量 run 的模型上下文投影。

use crate::workflow_tool::{WorkflowRunLifecycle, WorkflowSessionState};
use crate::{ContextSectionId, ModelContextSectionSnapshot};
use serde::Serialize;

use super::RegisteredThreadMode;
use super::WORKFLOW_CONTEXT_SECTION_ID;
use pl_core::context::content_hash as canonical_content_hash;

pub fn workflow_model_context_section(
    state: &WorkflowSessionState,
    mode: &RegisteredThreadMode,
) -> Option<ModelContextSectionSnapshot> {
    let run = state.current_run.as_ref()?;
    let graph = mode.workflow()?;
    if run.mode_id != mode.descriptor().id || run.graph_hash != graph.graph_hash() {
        return None;
    }
    let current = graph.state(&run.current_state_id)?;
    let outgoing = graph
        .outgoing(&run.current_state_id)
        .into_iter()
        .map(|transition| WorkflowTransitionProjection {
            target_state_id: &transition.target_state_id,
            guard: &transition.guard,
        })
        .collect();
    let projection = WorkflowContextProjection {
        run_id: &run.run_id,
        revision: state.revision,
        mode_id: run.mode_id.as_str(),
        graph_revision: run.graph_revision,
        graph_hash: &run.graph_hash,
        lifecycle: run.lifecycle,
        current_state: current,
        allowed_transitions: outgoing,
        latest_completion_summary: run
            .history_tail
            .last()
            .map(|record| record.summary.as_str()),
        constraint: match run.lifecycle {
            WorkflowRunLifecycle::Active => {
                "Follow the current state instructions. Always advance the workflow stage first via `exec` (`tools.workflow_transition`) BEFORE calling `request_user_input` or `plan_transition` (never call those suspending tools while still in `triage` or before moving to `planning`). Both `request_user_input` and `plan_transition` are exclusive top-level tools—never batch them with `exec` or other tools. In `planning`, clarify any conflict with existing design via `request_user_input` first, then submit an ELI5 Markdown plan using `plan_transition(targetState=\"awaitingConfirmation\", force=false)` (transition `approved -> drafting` first if re-planning). In `reviewing`, read the latest Plan (`studio.plan.document` / `pl.plan`, or call `tools.plan_current({})` inside `exec` / top-level `plan_current` per tool declarations) and instruct reviewers based on it. Use the projected runId, revision, state id and allowed transitions to call `tools.workflow_transition` after the completion criteria are satisfied (set force=true only when an intentional out-of-path jump is needed). Query only if this projection is missing or a compare-and-swap conflict occurs. Compaction and restart do not reset the current stage."
            }
            WorkflowRunLifecycle::Terminal => {
                "The workflow is terminal. Do not transition it unless overriding with workflow_transition(force=true) or starting an explicit new attempt with workflow_restart."
            }
        },
    };
    let content = serde_json::to_string_pretty(&projection).ok()?;
    Some(ModelContextSectionSnapshot {
        id: ContextSectionId::new(WORKFLOW_CONTEXT_SECTION_ID)
            .expect("built-in workflow context id must be valid"),
        title: "Thread Mode Workflow".to_string(),
        content_hash: canonical_content_hash(content.as_bytes()),
        content,
    })
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct WorkflowContextProjection<'a> {
    run_id: &'a str,
    revision: u64,
    mode_id: &'a str,
    graph_revision: u64,
    graph_hash: &'a str,
    lifecycle: WorkflowRunLifecycle,
    current_state: &'a crate::workflow_tool::WorkflowState,
    allowed_transitions: Vec<WorkflowTransitionProjection<'a>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    latest_completion_summary: Option<&'a str>,
    constraint: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct WorkflowTransitionProjection<'a> {
    target_state_id: &'a str,
    guard: &'a str,
}
