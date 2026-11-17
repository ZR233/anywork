//! Final text emitted by the explicit completion tool, decoded from the saved producer receipt.
use super::order;
use crate::{ExecutionItem, ExecutionShape};
use crate::{ThreadContentLifecycle, ThreadTextChannel, ThreadTextItem};
use pl_core::thread::ToolOutcome;

pub(super) fn project_completion(
    thread_id: &str,
    turn_id: &str,
    delivery: &pl_core::thread::ToolDelivery,
    revision: u64,
    at: i64,
) -> Option<ExecutionItem> {
    let summary = completion_summary(delivery)?;
    Some(ExecutionItem::new(
        order::completion_id(&delivery.call_id),
        thread_id.into(),
        turn_id.into(),
        0,
        revision,
        at,
        at,
        ExecutionShape::Text(ThreadTextItem::new(
            ThreadTextChannel::Final,
            summary,
            Vec::new(),
            ThreadContentLifecycle::completed(at),
        )),
    ))
}

fn completion_summary(delivery: &pl_core::thread::ToolDelivery) -> Option<String> {
    committed_finish(delivery).map(|report| report.message)
}

pub(crate) fn committed_finish(
    delivery: &pl_core::thread::ToolDelivery,
) -> Option<pl_tool::finish_turn::SavedFinishTurn> {
    if delivery.tool_id != pl_tool::finish_turn::TOOL_FINISH_TURN
        || !matches!(delivery.outcome, ToolOutcome::Succeeded)
        || delivery.output.control() != pl_core::tool::ToolControl::EndTurn
    {
        return None;
    }
    pl_tool::finish_turn::saved_report(delivery.output.payload())
        .ok()
        .flatten()
}

pub(crate) fn committed_finish_execution(
    item: &ExecutionItem,
) -> anyhow::Result<Option<pl_tool::finish_turn::SavedFinishTurn>> {
    match item.tool() {
        Some(tool) => finish_tool(tool),
        None => Ok(None),
    }
}
fn finish_tool(
    tool: &crate::ThreadToolItem,
) -> anyhow::Result<Option<pl_tool::finish_turn::SavedFinishTurn>> {
    if tool.invocation().name() != pl_tool::finish_turn::TOOL_FINISH_TURN {
        return Ok(None);
    }
    let Some(output) = tool.terminal_output() else {
        return Ok(None);
    };
    for artifact in output.output_artifacts() {
        let Ok(pl_core::context::ContextContent::Opaque { payload }) =
            serde_json::from_value(artifact.clone())
        else {
            continue;
        };
        if payload.format() == "pl.tool.finish-turn" {
            return Ok(pl_tool::finish_turn::saved_report(&payload)?);
        }
    }
    Ok(None)
}
