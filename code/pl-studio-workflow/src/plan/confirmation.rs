use super::{AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, AgentSessionPlanConfirmationDecision};

/// Interprets the standard plan confirmation answer.
///
/// # Errors
/// Rejects missing answers or answers with no confirmation decision.
pub fn confirmation_decision(
    resolution: &pl_protocol::UserInputResolution,
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
