//! Native member activity derived from the original Thread snapshot.
use anyhow::Result;
use pl_core::thread::{ThreadLifecycle, ThreadSnapshot, TurnState};
use pl_protocol::AgentState;

/// Whether this member owes work nobody has claimed yet (stopped or interrupted, waiting for the
/// main agent).
///
/// One predicate serves the hot directory row and the cold reconciliation, so the two can never
/// drift apart.
pub(in crate::studio) fn awaiting_scheduling(snapshot: &ThreadSnapshot) -> Result<bool> {
    Ok(snapshot
        .continuation
        .as_ref()
        .is_some_and(|point| point.claim.is_none())
        && snapshot.lifecycle == ThreadLifecycle::Open
        && !crate::studio::agent_close::is_explicitly_closed(snapshot)?)
}

pub(in crate::studio) fn native_activity(
    snapshot: &ThreadSnapshot,
) -> Result<crate::StudioAgentActivity> {
    let execution = execution(snapshot);
    let can_stop = execution.is_some()
        && snapshot.lifecycle == ThreadLifecycle::Open
        && !crate::studio::agent_close::is_explicitly_closed(snapshot)?;
    Ok(crate::StudioAgentActivity::Native {
        state: agent_state(snapshot)?,
        execution,
        can_stop,
        awaiting_scheduling: awaiting_scheduling(snapshot)?,
    })
}

/// The current execution of this Thread, in the product's typed vocabulary.
///
/// Preparation, storage and admission phases are part of the identity, so a member that has not
/// created a Turn yet still publishes what a stop would target.
fn execution(snapshot: &ThreadSnapshot) -> Option<pl_protocol::AgentExecution> {
    snapshot.execution.as_ref().map(|execution| {
        pl_protocol::AgentExecution::new(
            execution.id.clone(),
            match execution.phase {
                pl_core::thread::ExecutionPhase::Preparing => {
                    pl_protocol::AgentExecutionPhase::Preparing
                }
                pl_core::thread::ExecutionPhase::AwaitingStorage => {
                    pl_protocol::AgentExecutionPhase::AwaitingStorage
                }
                pl_core::thread::ExecutionPhase::AwaitingAdmission => {
                    pl_protocol::AgentExecutionPhase::AwaitingAdmission
                }
                pl_core::thread::ExecutionPhase::Running => {
                    pl_protocol::AgentExecutionPhase::Running
                }
                pl_core::thread::ExecutionPhase::Stopping => {
                    pl_protocol::AgentExecutionPhase::Stopping
                }
            },
            execution.turn_id.clone(),
        )
    })
}

fn agent_state(snapshot: &ThreadSnapshot) -> Result<AgentState> {
    if crate::studio::agent_close::is_explicitly_closed(snapshot)?
        && snapshot.lifecycle == ThreadLifecycle::Open
    {
        return Ok(AgentState::Closing(pl_protocol::ClosingAgentState::new()));
    }
    match snapshot.lifecycle {
        ThreadLifecycle::Closed => {
            return Ok(AgentState::Closed(pl_protocol::ClosedAgentState::new()));
        }
        ThreadLifecycle::Closing => {
            return Ok(AgentState::Closing(pl_protocol::ClosingAgentState::new()));
        }
        ThreadLifecycle::Open => {}
    }
    if let Some(interaction) = snapshot.interactions.values().find(|interaction| {
        interaction.state == pl_core::thread::interactions::InteractionState::Pending
    }) {
        return Ok(AgentState::WaitingInteraction(
            pl_protocol::WaitingInteractionAgentState::new(
                pl_protocol::TurnId::new(interaction.request.turn_id.clone())?,
                interaction.request.id.clone(),
            ),
        ));
    }
    if let Some(permission) = snapshot.permissions.values().find(|permission| {
        permission.state == pl_core::thread::permissions::PermissionState::Pending
    }) {
        return Ok(AgentState::WaitingInteraction(
            pl_protocol::WaitingInteractionAgentState::new(
                pl_protocol::TurnId::new(permission.turn_id.clone())?,
                permission.id.clone(),
            ),
        ));
    }
    if let Some(turn) = snapshot
        .turns
        .iter()
        .rev()
        .find(|turn| turn.state == TurnState::Running)
    {
        return Ok(AgentState::Running(pl_protocol::RunningAgentState::new(
            pl_protocol::TurnId::new(turn.turn_id.clone())?,
        )));
    }
    // Accepted inputs have no Turn identity until execution starts; do not fabricate a queued Turn.
    Ok(AgentState::idle())
}
