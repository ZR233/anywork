//! Per-agent Plan state machine validation, confirmation interpretation, and options.

pub use pl_tool_plan::{Plan, PlanValidationError};

use crate::plan_tool::{AgentSessionPlanState, PlanActor, PlanState};
use crate::{AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, MessagePresentation, PureError};

pub const MAX_PLAN_SESSION_STATE_BYTES: usize = 128 * 1024;

/// Confirmation decision produced when resolving a pending Plan confirmation dialog.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AgentSessionPlanConfirmationDecision {
    Approve,
    RequestRevision { feedback: String },
}

/// Per-agent options controlling confirmation dialog emission.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AgentSessionPlanOptions {
    submitted_plan_presentation: MessagePresentation,
    allow_confirmation_interaction: bool,
}

impl Default for AgentSessionPlanOptions {
    fn default() -> Self {
        Self {
            submitted_plan_presentation: MessagePresentation::Hidden,
            allow_confirmation_interaction: false,
        }
    }
}

impl AgentSessionPlanOptions {
    #[must_use]
    pub const fn with_submitted_plan_presentation(
        mut self,
        presentation: MessagePresentation,
    ) -> Self {
        self.submitted_plan_presentation = presentation;
        self
    }

    #[must_use]
    pub const fn submitted_plan_presentation(&self) -> MessagePresentation {
        self.submitted_plan_presentation
    }

    #[must_use]
    pub const fn with_confirmation_interaction(mut self, enabled: bool) -> Self {
        self.allow_confirmation_interaction = enabled;
        self
    }

    #[must_use]
    pub const fn allow_confirmation_interaction(&self) -> bool {
        self.allow_confirmation_interaction
    }
}

/// Validates domain invariants and persisted byte limit of a `Studio` Plan state wrapper.
///
/// Note: Child agents, ACP agents, and non-interactive sessions can validly enter
/// `PlanState::AwaitingConfirmation` without a pending Native GUI `InteractionRequest`
/// (`pending_interaction_id == None`). Only non-`AwaitingConfirmation` states must never
/// retain a stale `pending_interaction_id`.
pub fn validate_session_state_size(state: &AgentSessionPlanState) -> Result<(), PureError> {
    Plan::from_record(state.plan.clone())
        .map_err(|error| PureError::ConfigError(error.to_string()))?;
    if state.plan.state != PlanState::AwaitingConfirmation && state.pending_interaction_id.is_some()
    {
        return Err(PureError::ConfigError(
            "non-awaiting Plan state cannot retain a pendingInteractionId".into(),
        ));
    }
    let bytes = serde_json::to_vec(state)?.len();
    if bytes > MAX_PLAN_SESSION_STATE_BYTES {
        return Err(PureError::ConfigError(format!(
            "AgentSession Plan state exceeds {MAX_PLAN_SESSION_STATE_BYTES} bytes"
        )));
    }
    Ok(())
}

/// Interprets the standard plan confirmation answer from GUI / Bot Interaction resolution.
///
/// # Errors
/// Rejects missing answers or answers with no confirmation decision.
pub fn confirmation_decision(
    resolution: &crate::UserInputResolution,
) -> Result<AgentSessionPlanConfirmationDecision, String> {
    let answer = resolution
        .answers
        .get(AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID)
        .ok_or_else(|| {
            format!(
                "Plan confirmation answer `{AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID}` is missing"
            )
        })?;
    let approved = answer.answers.iter().any(|value| value == "Approve");
    let revision = answer.answers.iter().any(|value| value == "Revise");
    if approved && revision {
        return Err("Plan confirmation cannot select both Approve and Revise".to_string());
    }
    if approved {
        return Ok(AgentSessionPlanConfirmationDecision::Approve);
    }
    let feedback = answer
        .answers
        .iter()
        .filter(|value| value.as_str() != "Revise")
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>()
        .join("\n");
    if revision || !feedback.is_empty() {
        return Ok(AgentSessionPlanConfirmationDecision::RequestRevision { feedback });
    }
    Err("Plan confirmation must select Approve, Revise, or provide revision feedback".to_string())
}

pub(crate) fn user_resolution_command(
    decision: AgentSessionPlanConfirmationDecision,
    expected_revision: u64,
    operation_id: String,
    argument_hash: String,
    now_secs: i64,
) -> pl_tool_plan::PlanTransitionCommand {
    let (target_state, reason, feedback) = match decision {
        AgentSessionPlanConfirmationDecision::Approve => (
            PlanState::Approved,
            Some("User approved the current Plan.".to_string()),
            None,
        ),
        AgentSessionPlanConfirmationDecision::RequestRevision { feedback } => {
            let trimmed = feedback.trim().to_string();
            let reason = if trimmed.is_empty() {
                "User requested a revised Plan.".to_string()
            } else {
                format!("User requested a revised Plan: {trimmed}")
            };
            (
                PlanState::RevisionRequested,
                Some(reason),
                (!trimmed.is_empty()).then_some(trimmed),
            )
        }
    };
    pl_tool_plan::PlanTransitionCommand {
        target_state,
        content: None,
        feedback,
        reason,
        force: false,
        expected_revision: Some(expected_revision),
        idempotency_key: Some(operation_id),
        argument_hash: Some(argument_hash),
        actor: PlanActor::User,
        timestamp_ms: now_secs.saturating_mul(1000),
    }
}
