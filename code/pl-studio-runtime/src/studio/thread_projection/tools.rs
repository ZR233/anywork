//! Tool timeline facts keep delivered text and producer-owned machine metadata separate.
use super::{ProjectionError, content::text_content};
use crate::{ExecutionItem, ExecutionShape};
use pl_core::context::ResourceReference;
use pl_core::thread::{
    ThreadSnapshot, ToolDelivery, ToolOutcome, permissions::PermissionState, task::TaskStatus,
};
use pl_protocol::{
    FailedThreadTool, SucceededThreadTool, ThreadToolInvocation, ThreadToolItem, ThreadToolOutput,
    ThreadToolState,
};

#[allow(clippy::too_many_arguments)]
pub(in crate::studio) fn project_tool_call(
    thread_id: &str,
    snapshot: &ThreadSnapshot,
    turn_id: &str,
    call: &pl_core::model::ModelToolCall,
    ordinal: u64,
    created_at: i64,
    revision: u64,
    updated_at: i64,
) -> Result<Vec<ExecutionItem>, ProjectionError> {
    let id = call.call_id.as_str();
    let invocation = ThreadToolInvocation::new(
        id.into(),
        call.tool_id.clone(),
        call.arguments.content().into(),
    )
    .with_provider_identity(Some(id.into()), None)
    .with_presentation_contract(
        call.presentation_contract
            .as_ref()
            .map(|contract| contract.as_str().to_owned()),
    );
    project_invocation(
        thread_id, snapshot, turn_id, invocation, ordinal, created_at, revision, updated_at,
    )
}

pub(super) fn project_saved_tool_call(
    thread_id: &str,
    snapshot: &ThreadSnapshot,
    saved: &ExecutionItem,
    revision: u64,
    updated_at: i64,
) -> Result<Vec<ExecutionItem>, ProjectionError> {
    let ExecutionShape::Tool(tool) = saved.state() else {
        return Err(ProjectionError::DuplicateCall(saved.id.clone()));
    };
    let invocation = tool.invocation().clone();
    let id = invocation.tool_call_id();
    if saved.id != super::order::tool_id(id) || saved.thread_id != thread_id {
        return Err(ProjectionError::DuplicateCall(id.into()));
    }
    project_invocation(
        thread_id,
        snapshot,
        &saved.turn_id,
        invocation,
        saved.ordinal,
        saved.created_at,
        revision,
        updated_at,
    )
}

/// Supplements one already-projected terminal tool result with durable resource references.
///
/// A reliable-output repair lands *after* its result was committed, so the delivery that carried the
/// original projection has already left resident state and cannot describe the terminal result from
/// the current snapshot. The canonical terminal item is therefore the authority for everything but
/// the repaired references: this keeps its invocation, result text, attachments, exit code, order and
/// identity, and only appends the references the retried archive stored. The result is never
/// re-executed, never re-delivered and never moved; an already-projected reference is not duplicated.
///
/// # Errors
/// Rejects an identity that is not a committed terminal tool result, so a supplement can never turn
/// a running or unrelated item into a repaired one.
pub(in crate::studio) fn project_repaired_tool_call(
    thread_id: &str,
    saved: &ExecutionItem,
    references: &[ResourceReference],
    updated_at: i64,
) -> Result<Vec<ExecutionItem>, ProjectionError> {
    let ExecutionShape::Tool(tool) = saved.state() else {
        return Err(ProjectionError::DuplicateCall(saved.id.clone()));
    };
    if saved.thread_id != thread_id {
        return Err(ProjectionError::DuplicateCall(saved.id.clone()));
    }
    let state = match tool.state() {
        ThreadToolState::Succeeded(succeeded) => {
            ThreadToolState::Succeeded(SucceededThreadTool::new(
                succeeded.completed_at(),
                supplement_output(succeeded.output(), references)?,
            ))
        }
        ThreadToolState::Failed(failed) => {
            let Some(output) = failed.output() else {
                return Err(ProjectionError::DuplicateCall(saved.id.clone()));
            };
            ThreadToolState::Failed(FailedThreadTool::new(
                failed.failed_at(),
                failed.failure().clone(),
                Some(supplement_output(output, references)?),
            ))
        }
        _ => return Err(ProjectionError::DuplicateCall(saved.id.clone())),
    };
    Ok(vec![ExecutionItem::new(
        saved.id.clone(),
        saved.thread_id.clone(),
        saved.turn_id.clone(),
        saved.ordinal,
        saved.revision,
        saved.created_at,
        updated_at,
        ExecutionShape::Tool(
            ThreadToolItem::new(tool.invocation().clone(), state)
                .with_user_input(tool.user_input().cloned())
                .with_wait(tool.wait().cloned()),
        ),
    )])
}

/// Appends the repaired durable references to one projected tool output, never duplicating one.
fn supplement_output(
    output: &ThreadToolOutput,
    references: &[ResourceReference],
) -> Result<ThreadToolOutput, ProjectionError> {
    let mut artifacts = output.output_artifacts().to_vec();
    for reference in references {
        let artifact = serde_json::to_value(reference)?;
        if !artifacts.contains(&artifact) {
            artifacts.push(artifact);
        }
    }
    Ok(ThreadToolOutput::new(
        output.result().to_owned(),
        output.attachments().to_vec(),
        artifacts,
        output.exit_code(),
    ))
}

#[allow(clippy::too_many_arguments)]
fn project_invocation(
    thread_id: &str,
    snapshot: &ThreadSnapshot,
    turn_id: &str,
    mut invocation: ThreadToolInvocation,
    ordinal: u64,
    created_at: i64,
    revision: u64,
    updated_at: i64,
) -> Result<Vec<ExecutionItem>, ProjectionError> {
    let mut items = Vec::new();
    let id = invocation.tool_call_id().to_owned();
    let task = snapshot.tasks.values().find(|task| task.call_id == id);
    let delivery = snapshot
        .deliveries
        .iter()
        .find(|delivery| delivery.call_id == id);
    let state = if let Some(delivery) = delivery {
        if delivery.tool_id != invocation.name() {
            return Err(ProjectionError::DuplicateCall(id));
        }
        terminal(delivery, updated_at)?
    } else if let Some(task) = task {
        if task.status != TaskStatus::Running {
            return Err(ProjectionError::MissingToolResult(id));
        }
        let progress = snapshot
            .tool_progress
            .get(&task.id)
            // The canonical item carries the completed preview as text; the live window shares its
            // block and is materialized only here, at the projection boundary that has to encode it.
            .map_or_else(String::new, |progress| progress.content().text());
        if task.cancel_requested {
            ThreadToolState::Cancelling(pl_protocol::CancellingThreadTool::new(progress))
        } else if snapshot.permissions.values().any(|permission| {
            permission.call_id == id && permission.state == PermissionState::Pending
        }) {
            ThreadToolState::AwaitingApproval(pl_protocol::AwaitingApprovalThreadTool)
        } else {
            ThreadToolState::Running(pl_protocol::RunningThreadTool::new(progress))
        }
    } else {
        ThreadToolState::Queued(pl_protocol::QueuedThreadTool)
    };
    if let Some(delivery) = delivery
        && delivery.tool_id == "skill_view"
        && matches!(delivery.outcome, ToolOutcome::Succeeded)
        && let Ok(Some(mut activation)) = pl_tool::skill::saved_skill_activation(
            delivery.output.payload(),
            turn_id.into(),
            pl_protocol::SkillActivationCause::Tool {
                tool_call_id: id.clone(),
            },
        )
    {
        activation.activated_at = updated_at;
        items.push(ExecutionItem::new(
            super::order::skill_id(&id),
            thread_id.into(),
            turn_id.into(),
            revision,
            revision,
            updated_at,
            updated_at,
            ExecutionShape::Skill(pl_protocol::ThreadSkillItem::new(activation)),
        ));
    }
    if let Some(task) = task {
        invocation = invocation.with_task_id(task.id.clone());
    }
    let wait = super::wait::project_wait(
        Some(snapshot),
        invocation.name(),
        invocation.arguments(),
        &state,
    );
    items.push(ExecutionItem::new(
        super::order::tool_id(&id),
        thread_id.into(),
        turn_id.into(),
        ordinal,
        revision,
        created_at,
        updated_at,
        ExecutionShape::Tool(ThreadToolItem::new(invocation, state).with_wait(wait)),
    ));
    Ok(items)
}

pub(super) fn delivery_context(delivery: &ToolDelivery) -> &[pl_core::context::ContextContent] {
    match delivery.target {
        pl_core::thread::ToolDeliveryTarget::Nested { .. } => delivery.output.context(),
        _ => &delivery.delivered_context,
    }
}

fn terminal(delivery: &ToolDelivery, at: i64) -> Result<ThreadToolState, ProjectionError> {
    let mut resources = Vec::new();
    let task_query_payload = (delivery.tool_id == "get_tool_task"
        && delivery.output.payload().format() == "pl.tool.task")
        .then_some(delivery.output.payload());
    for content in delivery_context(delivery) {
        match content {
            pl_core::context::ContextContent::Text { .. } => {}
            pl_core::context::ContextContent::Resource { reference } => {
                resources.push(serde_json::to_value(reference)?)
            }
            pl_core::context::ContextContent::Opaque { payload } => {
                // The same query payload receives its explicit machine envelope
                // below. Retain every other opaque context without duplicating it.
                if task_query_payload != Some(payload) {
                    resources.push(serde_json::to_value(payload)?);
                }
            }
        }
    }
    if pl_tool::file_display::saved_file_display_receipt(delivery.output.payload())
        .map_err(ProjectionError::ToolMedia)?
        .is_some()
    {
        // Display metadata is a public artifact, not model input. Keep the standard
        // ContextContent shape here without modifying the actual delivered context.
        resources.push(serde_json::to_value(
            pl_core::context::ContextContent::Opaque {
                payload: delivery.output.payload().clone(),
            },
        )?);
    }
    if let Some(payload) = task_query_payload {
        // A query may itself finish in the background. Its delivered text then
        // includes a task notice, but the original versioned page is unchanged.
        // Preserve that producer value as metadata without altering model input.
        let artifact = serde_json::to_value(pl_core::context::ContextContent::Opaque {
            payload: payload.clone(),
        })?;
        if !resources.contains(&artifact) {
            resources.push(artifact);
        }
    }
    let output = ThreadToolOutput::new(
        text_content(delivery_context(delivery)),
        super::delivery_attachments(delivery)?,
        resources,
        command_exit_code(delivery),
    );
    Ok(match &delivery.outcome {
        ToolOutcome::Succeeded => {
            ThreadToolState::Succeeded(pl_protocol::SucceededThreadTool::new(at, output))
        }
        ToolOutcome::Failed(error) => ThreadToolState::Failed(pl_protocol::FailedThreadTool::new(
            at,
            pl_protocol::ThreadToolFailure::new(
                pl_protocol::ThreadToolFailureKind::Execution,
                error.to_string(),
            ),
            Some(output),
        )),
        ToolOutcome::Cancelled => {
            ThreadToolState::Cancelled(pl_protocol::CancelledThreadTool::new(
                at,
                "Tool execution was cancelled; observed facts remain in the journal.".into(),
            ))
        }
        ToolOutcome::Interrupted => {
            ThreadToolState::Interrupted(pl_protocol::InterruptedThreadTool::new(
                at,
                "Tool execution was interrupted; no side effect was replayed.".into(),
            ))
        }
    })
}

// Decode only the producer-owned versioned command receipt. The core outcome remains
// authoritative even when a process receipt reports a different exit status.
fn command_exit_code(delivery: &ToolDelivery) -> Option<i32> {
    let payload = delivery.output.payload();
    if !matches!(
        delivery.tool_id.as_str(),
        "exec" | "exec_command" | "write_stdin"
    ) || payload.format() != "pl.tool.exec"
        || !matches!(payload.version(), 1 | 2)
    {
        return None;
    }
    if payload.version() == 2 {
        #[derive(serde::Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct CommandReceipt {
            exit_code: Option<i32>,
        }
        return serde_json::from_str::<CommandReceipt>(payload.content())
            .ok()?
            .exit_code;
    }
    #[derive(serde::Deserialize)]
    struct CommandReceipt {
        state: pl_tool::command::CommandProcessLifecycle,
    }
    serde_json::from_str::<CommandReceipt>(payload.content())
        .ok()?
        .state
        .exit_code()
}

#[cfg(test)]
mod task_query_payload_tests {
    use super::*;
    use pl_core::context::{ContextContent, OpaquePayload};
    use pl_core::tool::ToolOutput;
    use serde_json::json;
    use std::sync::Arc;

    fn text(value: &str) -> ContextContent {
        ContextContent::Text {
            text: Arc::from(value),
        }
    }

    fn query_payload(version: u32) -> OpaquePayload {
        OpaquePayload::new(
            "pl.tool.task",
            version,
            json!({
                "task": {
                    "id": "task:original", "callId": "call:original", "toolId": "exec",
                    "turnId": "turn:control", "revision": 2, "status": "succeeded"
                },
                "result": {
                    "format": "pl.tool.exec", "version": 2, "content": "{\"exitCode\":0}",
                    "nextCursor": null, "totalBytes": 14
                }
            })
            .to_string(),
        )
        .unwrap()
    }

    fn delivery(tool: &str, payload: OpaquePayload, context: Vec<ContextContent>) -> ToolDelivery {
        ToolDelivery {
            target: Default::default(),
            call_id: "call:query".into(),
            tool_id: tool.into(),
            output: ToolOutput::new(payload, context.clone()),
            delivered_context: context,
            outcome: ToolOutcome::Succeeded,
        }
    }

    #[test]
    fn query_payload_survives_inline_background_and_existing_opaque_context() {
        let payload = query_payload(1);
        let opaque = ContextContent::Opaque {
            payload: payload.clone(),
        };
        for context in [
            vec![text("a JSON-looking display is not the payload")],
            vec![
                text("Task task:query for tool get_tool_task finished: Succeeded."),
                text("arbitrary delivered presentation"),
            ],
            vec![opaque.clone(), text("same producer value")],
        ] {
            let original = context.clone();
            let delivery = delivery("get_tool_task", payload.clone(), context);
            let state = terminal(&delivery, 42).unwrap();
            let ThreadToolState::Succeeded(done) = state else {
                panic!("query projection did not retain its successful outcome");
            };
            let output = done.output();
            assert_eq!(output.result(), text_content(&original));
            assert_eq!(
                output.output_artifacts(),
                &[serde_json::to_value(&opaque).unwrap()]
            );
            assert_eq!(delivery.delivered_context, original);
            assert_eq!(delivery.output.payload(), &payload);
        }
    }

    #[test]
    fn task_payload_requires_its_original_query_tool_identity() {
        for (tool, payload) in [
            ("exec", query_payload(1)),
            (
                "get_tool_task",
                OpaquePayload::text("not a task query payload"),
            ),
        ] {
            let state = terminal(&delivery(tool, payload, Vec::new()), 42).unwrap();
            let ThreadToolState::Succeeded(done) = state else {
                panic!("projection changed the execution outcome");
            };
            assert!(done.output().output_artifacts().is_empty());
        }
    }

    #[test]
    fn opaque_query_metadata_preserves_unknown_versions_without_decoding() {
        let payload = query_payload(99);
        let state = terminal(&delivery("get_tool_task", payload.clone(), Vec::new()), 42).unwrap();
        let ThreadToolState::Succeeded(done) = state else {
            panic!("projection changed the execution outcome");
        };
        let artifact: ContextContent =
            serde_json::from_value(done.output().output_artifacts()[0].clone()).unwrap();
        assert_eq!(artifact, ContextContent::Opaque { payload });
    }
}
