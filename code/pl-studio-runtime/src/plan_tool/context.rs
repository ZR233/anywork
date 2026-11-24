//! Current Plan facts projected for the model by Studio.
use super::PLAN_CONTEXT_SECTION_ID;
use crate::plan_tool::AgentSessionPlanState;
use crate::plan_tool::state::Plan;
use crate::{ContextSectionId, ModelContextSectionSnapshot, PureError};
use pl_core::context::content_hash as canonical_content_hash;

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
    let document = snapshot.document.as_ref().map(|document| {
        serde_json::json!({
            "version": document.revision,
            "contentHash": document.hash,
            "markdown": document.content,
        })
    });
    let content = serde_json::to_string_pretty(&serde_json::json!({
        "revision": snapshot.revision,
        "state": snapshot.state,
        "document": document,
        "pendingInteractionId": state.pending_interaction_id,
        "lastRevisionFeedback": snapshot.last_revision_feedback,
        "allowedTransitions": snapshot.allowed_transitions,
        "allStates": snapshot.all_states,
        "constraint": "Every agent owns one standalone Plan object independent of workflow. Latest host state overrides outdated summaries. Approval survives compaction and restart. Use plan_transition to switch Plan state when planning or confirmation is needed (pass force=true only for intentional out-of-path overrides).",
    }))?;
    Ok(ModelContextSectionSnapshot {
        id: ContextSectionId::new(PLAN_CONTEXT_SECTION_ID)
            .map_err(|error| PureError::ConfigError(error.to_string()))?,
        title: "AgentSession Plan State".to_string(),
        content_hash: canonical_content_hash(content.as_bytes()),
        content,
    })
}
