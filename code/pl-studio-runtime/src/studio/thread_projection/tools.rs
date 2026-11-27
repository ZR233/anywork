//! Tool timeline facts keep delivered text and producer-owned machine metadata separate.
use super::{ProjectionError, content::text_content};
use crate::{ExecutionItem, ExecutionShape};
use crate::{
    FailedThreadTool, SucceededThreadTool, ThreadToolInvocation, ThreadToolItem, ThreadToolOutput,
    ThreadToolState,
};
use pl_core::context::ResourceReference;
use pl_core::thread::{
    ThreadSnapshot, ToolDelivery, ToolOutcome, permissions::PermissionState, task::TaskStatus,
};

pub(in crate::studio) fn project_tool_call(
    snapshot: &ThreadSnapshot,
    call: &pl_core::model::ModelToolCall,
    stamp: crate::ItemStamp<'_>,
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
    project_invocation(snapshot, invocation, stamp)
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
        snapshot,
        invocation,
        crate::ItemStamp {
            thread_id: std::borrow::Cow::Borrowed(thread_id),
            turn_id: std::borrow::Cow::Borrowed(saved.turn_id.as_str()),
            ordinal: saved.ordinal,
            created_at: saved.created_at,
            revision,
            updated_at,
        },
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
        crate::ItemStamp {
            thread_id: std::borrow::Cow::Owned(saved.thread_id.clone()),
            turn_id: std::borrow::Cow::Owned(saved.turn_id.clone()),
            ordinal: saved.ordinal,
            revision: saved.revision,
            created_at: saved.created_at,
            updated_at,
        },
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

fn project_invocation(
    snapshot: &ThreadSnapshot,
    mut invocation: ThreadToolInvocation,
    stamp: crate::ItemStamp<'_>,
) -> Result<Vec<ExecutionItem>, ProjectionError> {
    let thread_id = stamp.thread_id.as_ref();
    let turn_id = stamp.turn_id.as_ref();
    let ordinal = stamp.ordinal;
    let created_at = stamp.created_at;
    let revision = stamp.revision;
    let updated_at = stamp.updated_at;
    let mut items = Vec::new();
    let id = invocation.tool_call_id().to_owned();
    let task = snapshot
        .tasks
        .values()
        .chain(snapshot.terminal_tasks.iter())
        .find(|task| task.call_id == id);
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
        match task.status {
            TaskStatus::Interrupted => {
                ThreadToolState::Interrupted(crate::InterruptedThreadTool::new(
                    updated_at,
                    "Tool execution was interrupted; no side effect was replayed.".into(),
                ))
            }
            TaskStatus::Cancelled => ThreadToolState::Cancelled(crate::CancelledThreadTool::new(
                updated_at,
                "Tool execution was cancelled; observed facts remain in the journal.".into(),
            )),
            TaskStatus::Succeeded => {
                // Answer consumption retires the delivery while the terminal Task can remain.
                // Its paired result already belongs to this same Current context.
                let output = completed_interaction_output(snapshot, &id, invocation.name())
                    .ok_or_else(|| ProjectionError::MissingToolResult(id.clone()))?;
                ThreadToolState::Succeeded(crate::SucceededThreadTool::new(updated_at, output))
            }
            TaskStatus::Failed => return Err(ProjectionError::MissingToolResult(id)),
            TaskStatus::Running => {
                let progress = snapshot
                    .tool_progress
                    .get(&task.id)
                    // The canonical item carries the completed preview as text; the live window shares its
                    // block and is materialized only here, at the projection boundary that has to encode it.
                    .map_or_else(String::new, |progress| progress.content().text());
                if task.cancel_requested {
                    ThreadToolState::Cancelling(crate::CancellingThreadTool::new(progress))
                } else if snapshot.permissions.values().any(|permission| {
                    permission.call_id == id && permission.state == PermissionState::Pending
                }) {
                    ThreadToolState::AwaitingApproval(crate::AwaitingApprovalThreadTool)
                } else {
                    ThreadToolState::Running(crate::RunningThreadTool::new(progress))
                }
            }
        }
    } else if let Some(output) = completed_interaction_output(snapshot, &id, invocation.name()) {
        ThreadToolState::Succeeded(crate::SucceededThreadTool::new(updated_at, output))
    } else {
        ThreadToolState::Queued(crate::QueuedThreadTool)
    };
    if let Some(delivery) = delivery
        && delivery.tool_id == "skill_view"
        && matches!(delivery.outcome, ToolOutcome::Succeeded)
        && let Ok(Some(mut activation)) = pl_tool::skill::saved_skill_activation(
            delivery.output.data(),
            turn_id.into(),
            crate::SkillActivationCause::Tool {
                tool_call_id: id.clone(),
            },
        )
    {
        activation.activated_at = updated_at;
        items.push(ExecutionItem::new(
            super::order::skill_id(&id),
            crate::ItemStamp {
                thread_id: std::borrow::Cow::Owned(thread_id.into()),
                turn_id: std::borrow::Cow::Owned(turn_id.into()),
                ordinal: revision,
                revision,
                created_at: updated_at,
                updated_at,
            },
            ExecutionShape::Skill(crate::ThreadSkillItem::new(activation)),
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
        crate::ItemStamp {
            thread_id: std::borrow::Cow::Owned(thread_id.into()),
            turn_id: std::borrow::Cow::Owned(turn_id.into()),
            ordinal,
            revision,
            created_at,
            updated_at,
        },
        ExecutionShape::Tool(ThreadToolItem::new(invocation, state).with_wait(wait)),
    ));
    Ok(items)
}

fn completed_interaction_output(
    snapshot: &ThreadSnapshot,
    call_id: &str,
    tool_id: &str,
) -> Option<ThreadToolOutput> {
    // Core admits a tool-produced interaction with its successful result. Consuming its answer
    // prunes the interaction but retains Core's terminal context alongside the paired result.
    let interaction_id = pl_core::tool::opaque::tool_interaction_id(call_id);
    let admitted = snapshot.interactions.contains_key(&interaction_id)
        || snapshot.context.records.iter().any(|record| {
            matches!(&record.source, pl_core::context::ContextSource::Runtime { source_id }
                if source_id.strip_prefix("interaction:") == Some(interaction_id.as_str()))
        });
    if !admitted {
        return None;
    }
    let result = snapshot.context.records.iter().find(|record| {
        matches!(&record.source, pl_core::context::ContextSource::ToolResult {
            call_id: known_call, tool_id: known_tool,
        } if known_call == call_id && known_tool == tool_id)
    })?;
    Some(ThreadToolOutput::new(
        text_content(&result.content),
        Vec::new(),
        Vec::new(),
        None,
    ))
}

pub(super) fn delivery_context(delivery: &ToolDelivery) -> &[pl_core::context::ContextContent] {
    match delivery.target {
        pl_core::thread::ToolDeliveryTarget::Nested { .. } => delivery.output.content(),
        _ => &delivery.delivered_context,
    }
}

fn terminal(delivery: &ToolDelivery, at: i64) -> Result<ThreadToolState, ProjectionError> {
    let mut resources = Vec::new();
    for content in delivery_context(delivery) {
        match content {
            pl_core::context::ContextContent::Text { .. } => {}
            pl_core::context::ContextContent::Resource { reference } => {
                resources.push(serde_json::to_value(reference)?)
            }
            pl_core::context::ContextContent::Media { .. }
            | pl_core::context::ContextContent::Opaque { .. } => {
                resources.push(serde_json::to_value(content)?);
            }
        }
    }
    if let Some(receipt) =
        pl_tool::file_display::saved_file_display_receipt(delivery.output.details())
            .map_err(ProjectionError::ToolMedia)?
    {
        // Product metadata stays separate from the model's frozen content.
        resources.push(serde_json::json!({"fileDisplay": receipt}));
    }
    for reference in pl_tool::exec::saved_command_resources(delivery.output.details())
        .map_err(ProjectionError::ToolMedia)?
    {
        let artifact = serde_json::to_value(reference)?;
        if !resources.contains(&artifact) {
            resources.push(artifact);
        }
    }
    if delivery.tool_id == "get_tool_task"
        && let Some(data) = delivery.output.data()
    {
        // The task-query page remains inspectable even if foreground delivery
        // was replaced by a background notice. Its data is author-supplied.
        resources.push(serde_json::json!({"toolData": data}));
    }
    let output = ThreadToolOutput::new(
        text_content(delivery_context(delivery)),
        super::delivery_attachments(delivery)?,
        resources,
        command_exit_code(delivery),
    );
    Ok(match &delivery.outcome {
        ToolOutcome::Succeeded => {
            ThreadToolState::Succeeded(crate::SucceededThreadTool::new(at, output))
        }
        ToolOutcome::Failed(error) => ThreadToolState::Failed(crate::FailedThreadTool::new(
            at,
            crate::ThreadToolFailure::new(
                crate::ThreadToolFailureKind::Execution,
                error.to_string(),
            ),
            Some(output),
        )),
        ToolOutcome::Cancelled => ThreadToolState::Cancelled(crate::CancelledThreadTool::new(
            at,
            "Tool execution was cancelled; observed facts remain in the journal.".into(),
        )),
        ToolOutcome::Interrupted => {
            ThreadToolState::Interrupted(crate::InterruptedThreadTool::new(
                at,
                "Tool execution was interrupted; no side effect was replayed.".into(),
            ))
        }
    })
}

// The author supplies process details; the core outcome remains authoritative.
fn command_exit_code(delivery: &ToolDelivery) -> Option<i32> {
    pl_tool::exec::saved_command_exit_code(delivery.output.details())
}

#[cfg(test)]
mod interaction_current_tests {
    use super::*;
    use anyhow::{Context, Result};
    use pl_core::context::{ContextContent, ContextRecord, ContextSource, OpaquePayload};

    #[test]
    fn consumed_interaction_keeps_only_its_proven_completed_result() -> Result<()> {
        let call = pl_core::model::ModelToolCall {
            call_id: "call".into(),
            tool_id: "request_user_input".into(),
            arguments: OpaquePayload::new("application/json", 1, "{}")?,
            presentation_contract: None,
            rejection: None,
        };
        for (source, expected) in [
            ("interaction:tool-interaction:call", Some("accepted")),
            ("interaction:tool-interaction:other", None),
        ] {
            let mut snapshot = ThreadSnapshot::default();
            snapshot.context.records = [
                ContextRecord {
                    tool_data: Default::default(),
                    id: "call".into(),
                    turn_id: Some("turn".into()),
                    source: ContextSource::Assistant,
                    content: vec![],
                    tool_calls: vec![call.clone()],
                },
                ContextRecord {
                    tool_data: Default::default(),
                    id: "result".into(),
                    turn_id: Some("turn".into()),
                    source: ContextSource::ToolResult {
                        call_id: "call".into(),
                        tool_id: "request_user_input".into(),
                    },
                    content: vec![ContextContent::Text {
                        text: "accepted".into(),
                    }],
                    tool_calls: vec![],
                },
                ContextRecord {
                    tool_data: Default::default(),
                    id: "answer".into(),
                    turn_id: Some("turn".into()),
                    source: ContextSource::Runtime {
                        source_id: source.into(),
                    },
                    content: vec![],
                    tool_calls: vec![],
                },
            ]
            .into();
            let items = project_tool_call(
                &snapshot,
                &call,
                crate::ItemStamp {
                    thread_id: std::borrow::Cow::Borrowed("thread"),
                    turn_id: std::borrow::Cow::Borrowed("turn"),
                    ordinal: 1,
                    created_at: 1,
                    revision: 1,
                    updated_at: 1,
                },
            )?;
            let tool = items[0].tool().context("projected interaction tool")?;
            assert_eq!(
                tool.terminal_output().map(|output| output.result()),
                expected,
                "{source}"
            );
        }
        Ok(())
    }
}

#[cfg(test)]
mod task_query_data_tests {
    use super::*;
    use pl_agent_tool::{ToolData, ToolResult};
    use pl_core::context::ContextContent;
    use pl_core::tool::ToolOutput;
    use serde_json::json;

    fn text(value: &str) -> ContextContent {
        ContextContent::Text { text: value.into() }
    }

    fn delivery(data: ToolData, content: Vec<ContextContent>) -> ToolDelivery {
        ToolDelivery {
            target: Default::default(),
            call_id: "call:query".into(),
            tool_id: "get_tool_task".into(),
            output: ToolOutput::new(ToolResult::new(data, content.clone())),
            delivered_context: content,
            outcome: ToolOutcome::Succeeded,
            cancellation_cause: None,
        }
    }

    #[test]
    fn query_data_is_independent_of_inline_and_background_presentation() {
        let data = json!({"task":{"id":"task:original","status":"succeeded"},
            "result":{"content":"original UTF-8 正文", "nextCursor":null}});
        for content in [
            vec![text("{\"display\":\"not the program result\"}")],
            vec![
                text("Task task:query finished."),
                text("background summary"),
            ],
        ] {
            let delivery = delivery(ToolData::Value(data.clone()), content.clone());
            let ThreadToolState::Succeeded(done) = terminal(&delivery, 42).unwrap() else {
                panic!("projection changed the execution outcome");
            };
            assert_eq!(done.output().result(), text_content(&content));
            assert_eq!(
                done.output().output_artifacts(),
                &[json!({"toolData": data})]
            );
            assert_eq!(delivery.delivered_context, content);
            assert_eq!(delivery.output.data(), Some(&data));
        }
    }

    #[test]
    fn missing_program_value_is_not_inferred_from_json_looking_text() {
        let content = vec![text("{\"taskId\":\"pretend\"}")];
        let delivery = delivery(ToolData::Absent, content.clone());
        let ThreadToolState::Succeeded(done) = terminal(&delivery, 42).unwrap() else {
            panic!("projection changed the execution outcome");
        };
        assert!(done.output().output_artifacts().is_empty());
        assert_eq!(done.output().result(), text_content(&content));
    }
}

#[cfg(test)]
mod file_display_wire_tests {
    use super::*;
    use pl_agent_tool::{ToolData, ToolResult};
    use pl_core::{context::ContextContent, tool::ToolOutput};

    #[test]
    fn file_display_rust_fixture_survives_product_projection() {
        // Shared with the Dart consumer; generated by FileDisplayReceipt's production Serialize.
        let artifacts: Vec<serde_json::Value> = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../anywork/test/fixtures/file_display_rust.json"
        )))
        .unwrap();
        assert_eq!(artifacts.len(), 1);
        let content = vec![ContextContent::Text {
            text: "original model presentation".into(),
        }];
        let delivery = ToolDelivery {
            target: Default::default(),
            call_id: "call:file-display-fixture".into(),
            tool_id: "show_files".into(),
            output: ToolOutput::new(
                ToolResult::new(ToolData::Absent, content.clone())
                    .with_details(artifacts[0].clone()),
            ),
            delivered_context: content,
            outcome: ToolOutcome::Succeeded,
            cancellation_cause: None,
        };
        let ThreadToolState::Succeeded(done) = terminal(&delivery, 42).unwrap() else {
            panic!("projection changed the execution outcome");
        };
        assert_eq!(done.output().output_artifacts(), artifacts);
        assert_eq!(done.output().result(), "original model presentation");
    }
}
