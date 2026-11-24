//! Current Plan facts projected for the model by Studio.
use super::PLAN_CONTEXT_SECTION_ID;
use crate::plan_tool::AgentSessionPlanState;
use crate::plan_tool::state::Plan;
use crate::{ContextSectionId, ModelContextSectionSnapshot, PureError};
use pl_core::context::content_hash as canonical_content_hash;

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct ContextPlanDocument<'a> {
    version: u64,
    content_hash: &'a str,
    markdown: &'a str,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct ContextPlan<'a> {
    revision: u64,
    state: pl_tool_plan::PlanState,
    document: Option<ContextPlanDocument<'a>>,
    pending_interaction_id: Option<&'a str>,
    last_revision_feedback: Option<&'a str>,
    allowed_transitions: &'a [pl_tool_plan::PlanTransitionRule],
    all_states: &'a [pl_tool_plan::PlanState],
    constraint: &'static str,
}

/// Derives a complete canonical Plan snapshot for the model; deduplicated per session facts layer.
///
/// # Errors
/// Rejects invalid Plan state or a failed context encoding.
pub fn plan_model_context_section(
    state: &AgentSessionPlanState,
) -> Result<ModelContextSectionSnapshot, PureError> {
    let plan = Plan::from_record(state.plan.clone())
        .map_err(|error| PureError::ConfigError(error.to_string()))?;
    let snapshot = plan.snapshot();
    let document = snapshot
        .document
        .as_ref()
        .map(|document| ContextPlanDocument {
            version: document.revision,
            content_hash: &document.hash,
            markdown: &document.content,
        });
    let content = serde_json::to_string_pretty(&ContextPlan {
        revision: snapshot.revision,
        state: snapshot.state,
        document,
        pending_interaction_id: state.pending_interaction_id.as_deref(),
        last_revision_feedback: snapshot.last_revision_feedback.as_deref(),
        allowed_transitions: &snapshot.allowed_transitions,
        all_states: &snapshot.all_states,
        constraint: "Every agent owns one standalone Plan object independent of workflow. Latest host state overrides outdated summaries. Approval survives compaction and restart. If the workflow is currently in `triage` (or another pre-planning state) and needs planning, call `exec` (`tools.workflow_transition` to `planning`) FIRST before calling `request_user_input` or `plan_transition`. Both `request_user_input` and `plan_transition` are exclusive top-level tools (never batch them with `exec` or other tools). In `planning`, write `content` in ELI5 plain language by default and call `plan_transition(targetState=\"awaitingConfirmation\", force=false)` to trigger user confirmation (never pass `force=true` when requesting confirmation; if currently `approved`, transition to `drafting` first). During `reviewing`, read the latest `studio.plan.document` / `document.markdown` (or call `tools.plan_current({})` via `exec` / top-level `plan_current` if missing) to guide verification and reviewers.",
    })?;
    Ok(ModelContextSectionSnapshot {
        id: ContextSectionId::new(PLAN_CONTEXT_SECTION_ID)
            .map_err(|error| PureError::ConfigError(error.to_string()))?,
        title: "AgentSession Plan State".to_string(),
        content_hash: canonical_content_hash(content.as_bytes()),
        content,
    })
}
