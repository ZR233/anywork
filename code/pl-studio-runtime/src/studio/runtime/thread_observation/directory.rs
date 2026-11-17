//! Product ancestry and state projections; notifications never replay old child execution.
use super::ObservationServices;
use crate::Thread;
use anyhow::Result;
use pl_core::thread::ThreadSnapshot;

pub(super) async fn publish(
    projector: &ObservationServices,
    thread: Thread,
    observation: Option<&crate::studio::product_event_bus::NativeAgentObservation>,
    snapshot: &ThreadSnapshot,
    summary: Option<String>,
) -> Result<()> {
    let Some(row) = projector.events.patch_thread_runtime(
        observation,
        thread.status,
        thread.updated_at,
        snapshot,
        Some(summary),
    )?
    else {
        return Ok(());
    };
    projector
        .events
        .update_child_interactions(&row.thread_id, snapshot)?;
    Ok(())
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
    thread: &crate::Thread,
    agent: &crate::studio::records::AgentDirectoryRecord,
    snapshot: &ThreadSnapshot,
) -> Result<()> {
    projector.events.publish_cold_agent_scheduling(
        &agent.session_id,
        &agent.agent_id,
        &thread.id,
        snapshot,
    )?;
    projector
        .events
        .update_child_interactions(&thread.id, snapshot)?;
    Ok(())
}
