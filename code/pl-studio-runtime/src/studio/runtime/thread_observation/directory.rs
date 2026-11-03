//! Product ancestry and state projections; notifications never replay old child execution.
use super::ObservationServices;
use anyhow::Result;
use pl_core::thread::{ThreadLifecycle, ThreadSnapshot, TurnState};
use pl_protocol::{AgentState, Thread};

pub(super) async fn publish(
    projector: &ObservationServices,
    thread: Thread,
    snapshot: &ThreadSnapshot,
    summary: Option<String>,
) -> Result<()> {
    let state = agent_state(snapshot)?;
    let execution = execution(snapshot);
    // A row may be stopped exactly when this process owns a current execution for it and the
    // explicit-close intent has not already frozen that member's lifecycle.
    let can_stop = execution.is_some()
        && snapshot.lifecycle == ThreadLifecycle::Open
        && !crate::studio::agent_close::is_explicitly_closed(snapshot)?;
    // A member that owes work nobody has claimed yet was stopped (or interrupted by the previous
    // process) and waits for the main agent to schedule it. A claimed point means an operation
    // already carries it, so the row is not "waiting" any more.
    let awaiting_scheduling = awaiting_scheduling(snapshot)?;
    let Some(row) = projector.events.patch_thread_runtime(
        &thread.id,
        thread.status,
        thread.updated_at,
        snapshot,
    )?
    else {
        return Ok(());
    };
    let entry = crate::StudioAgentDirectoryEntry {
        agent_id: row.agent_id.clone(),
        session_id: row.session_id.clone(),
        parent_agent_id: row.parent_agent_id.clone(),
        thread_id: row.thread_id.clone(),
        role: row.role.clone(),
        delegation_mode: row.delegation_mode,
        delegation_preference: row.delegation_preference,
        frozen_model: match &row.binding {
            pl_protocol::AgentBinding::Native(config) => config.route.clone(),
            pl_protocol::AgentBinding::Acp(_) => None,
        },
        task: row.title.clone(),
        summary,
        state,
        execution,
        can_stop,
        awaiting_scheduling,
        updated_at: row.updated_at,
    };
    projector.events.update_agent_directory(entry).await;
    projector
        .events
        .update_child_interactions(&row.thread_id, snapshot)?;
    Ok(())
}

/// Whether this member owes work nobody has claimed yet (stopped or interrupted, waiting for the
/// main agent).
///
/// One predicate serves the hot directory row and the cold reconciliation, so the two can never
/// drift apart.
pub(super) fn awaiting_scheduling(snapshot: &ThreadSnapshot) -> Result<bool> {
    Ok(snapshot
        .continuation
        .as_ref()
        .is_some_and(|point| point.claim.is_none())
        && snapshot.lifecycle == ThreadLifecycle::Open
        && !crate::studio::agent_close::is_explicitly_closed(snapshot)?)
}

/// Publishes the interruption fact of a **cold** child so the agent list can show
/// "stopped, waiting for the main agent" without activating it.
///
/// Only the facts the saved snapshot really proves are published: no current execution and no stop
/// qualification (this process owns none for that member), and `awaiting_scheduling` derived from the
/// unclaimed continuation point. The business state stays the directory's own cold status, so a
/// crashed Turn is never presented as running here.
pub(super) async fn publish_cold_scheduling_state(
    projector: &ObservationServices,
    thread: &pl_protocol::Thread,
    snapshot: &ThreadSnapshot,
) -> Result<()> {
    let Some((session_record, agent_record)) = (|| {
        let catalog = projector.store.catalog();
        let agent = catalog.agent_by_thread(&thread.id)?;
        let session = catalog.get_session(&agent.session_id)?;
        Some((session, agent))
    })() else {
        return Ok(());
    };
    let awaiting_scheduling = awaiting_scheduling(snapshot)?;
    // Everything except the interruption fact stays the directory's own cold status: a crashed Turn
    // is never presented as running, and no current execution nor stop qualification is invented.
    let state = match agent_record.projected_status() {
        pl_protocol::ThreadStatus::Closed => {
            pl_protocol::AgentState::Closed(pl_protocol::ClosedAgentState::new())
        }
        pl_protocol::ThreadStatus::Closing => {
            pl_protocol::AgentState::Closing(pl_protocol::ClosingAgentState::new())
        }
        _ => pl_protocol::AgentState::idle(),
    };
    let entry = crate::StudioAgentDirectoryEntry {
        agent_id: agent_record.agent_id.clone(),
        session_id: agent_record.session_id.clone(),
        parent_agent_id: agent_record.parent_agent_id.clone(),
        thread_id: agent_record.thread_id.clone(),
        role: agent_record.role.clone(),
        delegation_mode: session_record.delegation_mode,
        delegation_preference: session_record.delegation_preference,
        frozen_model: agent_record.frozen_model(),
        task: agent_record
            .title
            .clone()
            .unwrap_or_else(|| session_record.title.clone()),
        summary: None,
        state,
        execution: None,
        can_stop: false,
        awaiting_scheduling,
        updated_at: thread.updated_at,
    };
    projector.events.update_agent_directory(entry).await;
    projector
        .events
        .update_child_interactions(&thread.id, snapshot)?;
    Ok(())
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
