//! Mechanical mapping only; the SDK owns current-state staging and validation.

use pl_protocol::{ActivityContentFrame, ActivityTextOperation, ActivityTextRegion};

use crate::api::studio::types::{
    BridgeActivityContentFrame, BridgeActivityPartMetadata, BridgeActivityTextOperation,
    BridgeActivityTextRegion, BridgeActivityToolMetadata, BridgeActivityToolOutputMetadata,
};

fn region(value: ActivityTextRegion) -> BridgeActivityTextRegion {
    match value {
        ActivityTextRegion::Reasoning { item_id } => {
            BridgeActivityTextRegion::Reasoning { item_id }
        }
        ActivityTextRegion::Response { item_id } => BridgeActivityTextRegion::Response { item_id },
        ActivityTextRegion::ToolArguments { call_id } => {
            BridgeActivityTextRegion::ToolArguments { call_id }
        }
        ActivityTextRegion::ToolOutput { call_id, part_id } => {
            BridgeActivityTextRegion::ToolOutput { call_id, part_id }
        }
    }
}

fn part(value: pl_protocol::ActivityPartMetadata) -> BridgeActivityPartMetadata {
    BridgeActivityPartMetadata {
        item_id: value.item_id,
        complete: value.complete,
        total_bytes: value.total_bytes,
    }
}

fn operation(value: ActivityTextOperation) -> BridgeActivityTextOperation {
    match value {
        ActivityTextOperation::Append {
            region: target,
            text,
        } => BridgeActivityTextOperation::Append {
            region: region(target),
            text,
        },
        ActivityTextOperation::Replace {
            region: target,
            text,
        } => BridgeActivityTextOperation::Replace {
            region: region(target),
            text,
        },
        ActivityTextOperation::Remove { region: target } => BridgeActivityTextOperation::Remove {
            region: region(target),
        },
    }
}

pub(crate) fn activity_content(value: ActivityContentFrame) -> BridgeActivityContentFrame {
    match value {
        ActivityContentFrame::Begin {
            generation,
            base_revision,
            revision,
            activity,
            reasoning,
            response,
            tools,
            total_bytes,
        } => BridgeActivityContentFrame::Begin {
            generation,
            base_revision,
            revision,
            activity: activity.map(|value| Box::new(super::activity::activity(*value))),
            reasoning: reasoning.into_iter().map(part).collect(),
            response: response.into_iter().map(part).collect(),
            tools: tools
                .into_iter()
                .map(|tool| BridgeActivityToolMetadata {
                    call_id: tool.call_id,
                    task_id: tool.task_id,
                    name: tool.name,
                    state: super::activity::tool_state(tool.state),
                    started_at: tool.started_at,
                    source_order: tool.source_order,
                    arguments_bytes: tool.arguments_bytes,
                    output_bytes: tool.output_bytes,
                    output_parts: tool
                        .output_parts
                        .into_iter()
                        .map(|part| BridgeActivityToolOutputMetadata {
                            part_id: part.part_id,
                            total_bytes: part.total_bytes,
                        })
                        .collect(),
                    wait: tool.wait.map(super::wait_presentation),
                })
                .collect(),
            total_bytes,
        },
        ActivityContentFrame::Text {
            generation,
            revision,
            operations,
        } => BridgeActivityContentFrame::Text {
            generation,
            revision,
            operations: operations.into_iter().map(operation).collect(),
        },
        ActivityContentFrame::Commit {
            generation,
            revision,
        } => BridgeActivityContentFrame::Commit {
            generation,
            revision,
        },
    }
}
