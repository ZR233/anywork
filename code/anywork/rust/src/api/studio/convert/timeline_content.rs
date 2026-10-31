//! 完成历史 → FRB 的机械映射；语义和内容裁剪均属于 Runtime。

mod descriptor;

use crate::api::studio::types::*;
use pl_protocol::*;

pub(crate) fn page(value: TimelinePage) -> BridgeTimelinePage {
    BridgeTimelinePage {
        timeline_epoch: value.timeline_epoch,
        items: value.items.into_iter().map(item).collect(),
        before: value.before,
        has_older: value.has_older,
    }
}

pub(crate) fn completion_cursor(value: TimelineCompletionCursor) -> BridgeTimelineCompletionCursor {
    BridgeTimelineCompletionCursor {
        timeline_epoch: value.timeline_epoch,
        append_seq: value.append_seq,
    }
}

pub(crate) fn protocol_completion_cursor(
    value: BridgeTimelineCompletionCursor,
) -> TimelineCompletionCursor {
    TimelineCompletionCursor {
        timeline_epoch: value.timeline_epoch,
        append_seq: value.append_seq,
    }
}

pub(crate) fn baseline(value: TimelineTailBaseline) -> BridgeTimelineBaseline {
    BridgeTimelineBaseline {
        subscription_id: value.subscription_id,
        timeline_epoch: value.timeline_epoch,
        items: value.items.into_iter().map(item).collect(),
        before: value.before,
        has_older: value.has_older,
        completed_cursor: completion_cursor(value.completed_cursor),
    }
}

pub(crate) fn update(value: TimelineTailUpdate) -> BridgeTimelineUpdate {
    match value {
        TimelineTailUpdate::Batch {
            subscription_id,
            timeline_epoch,
            from_seq,
            through_seq,
            items,
        } => BridgeTimelineUpdate::Batch {
            subscription_id,
            timeline_epoch,
            from_seq,
            through_seq,
            items: items.into_iter().map(item).collect(),
        },
        TimelineTailUpdate::Reset { baseline: value } => BridgeTimelineUpdate::Reset {
            baseline: baseline(value),
        },
    }
}

pub(crate) fn detail_query(value: BridgeTimelineDetailQuery) -> TimelineDetailQuery {
    TimelineDetailQuery {
        timeline_epoch: value.timeline_epoch,
        field: protocol_field(value.field),
        continuation: value.continuation,
        max_bytes: value.max_bytes,
    }
}

pub(crate) fn detail_chunk(value: TimelineDetailChunk) -> BridgeTimelineDetailChunk {
    BridgeTimelineDetailChunk {
        timeline_epoch: value.timeline_epoch,
        item_id: value.item_id,
        field: content_field(value.field),
        text: value.text,
        total_bytes: value.total_bytes,
        continuation: value.continuation,
    }
}

fn item(value: TimelineItem) -> BridgeTimelineItem {
    BridgeTimelineItem {
        header: descriptor::header(value.header),
        descriptor: descriptor::descriptor(value.descriptor),
        source: match value.source {
            TimelineItemSource::Content => BridgeTimelineItemSource::Content,
            TimelineItemSource::ModelRecovery { attempt_id, notice } => {
                BridgeTimelineItemSource::ModelRecovery {
                    attempt_id,
                    notice: match notice {
                        TimelineRecoveryNotice::Retry => BridgeTimelineRecoveryNotice::Retry,
                        TimelineRecoveryNotice::Result => BridgeTimelineRecoveryNotice::Result,
                    },
                }
            }
        },
        fields: value
            .fields
            .into_iter()
            .map(|field| BridgeTimelineFieldPreview {
                field: content_field(field.field),
                text: field.text,
                total_bytes: field.total_bytes,
            })
            .collect(),
    }
}

fn content_field(field: ThreadContentField) -> BridgeContentField {
    match field {
        ThreadContentField::Text => BridgeContentField::Text,
        ThreadContentField::ThinkingSummary { chunk_index } => {
            BridgeContentField::ThinkingSummary { chunk_index }
        }
        ThreadContentField::ThinkingContent { chunk_index } => {
            BridgeContentField::ThinkingContent { chunk_index }
        }
        ThreadContentField::ToolArguments => BridgeContentField::ToolArguments,
        ThreadContentField::ToolResult => BridgeContentField::ToolResult,
        ThreadContentField::ToolOutputArtifacts => BridgeContentField::ToolOutputArtifacts,
        ThreadContentField::ToolUserInput {
            question_index,
            part,
        } => BridgeContentField::ToolUserInput {
            question_index,
            part: user_input_part(part),
        },
        ThreadContentField::RawPayload { payload_index } => {
            BridgeContentField::RawPayload { payload_index }
        }
        ThreadContentField::PlanDocument => BridgeContentField::PlanDocument,
        ThreadContentField::PlanFeedback => BridgeContentField::PlanFeedback,
    }
}

fn user_input_part(part: ThreadUserInputFieldPart) -> BridgeThreadUserInputFieldPart {
    match part {
        ThreadUserInputFieldPart::Header => BridgeThreadUserInputFieldPart::Header,
        ThreadUserInputFieldPart::Question => BridgeThreadUserInputFieldPart::Question,
        ThreadUserInputFieldPart::Answer { answer_index } => {
            BridgeThreadUserInputFieldPart::Answer { answer_index }
        }
        ThreadUserInputFieldPart::OptionLabel { option_index } => {
            BridgeThreadUserInputFieldPart::OptionLabel { option_index }
        }
        ThreadUserInputFieldPart::OptionDescription { option_index } => {
            BridgeThreadUserInputFieldPart::OptionDescription { option_index }
        }
    }
}

fn protocol_field(field: BridgeContentField) -> ThreadContentField {
    match field {
        BridgeContentField::Text => ThreadContentField::Text,
        BridgeContentField::ThinkingSummary { chunk_index } => {
            ThreadContentField::ThinkingSummary { chunk_index }
        }
        BridgeContentField::ThinkingContent { chunk_index } => {
            ThreadContentField::ThinkingContent { chunk_index }
        }
        BridgeContentField::ToolArguments => ThreadContentField::ToolArguments,
        BridgeContentField::ToolResult => ThreadContentField::ToolResult,
        BridgeContentField::ToolOutputArtifacts => ThreadContentField::ToolOutputArtifacts,
        BridgeContentField::ToolUserInput {
            question_index,
            part,
        } => ThreadContentField::ToolUserInput {
            question_index,
            part: protocol_part(part),
        },
        BridgeContentField::RawPayload { payload_index } => {
            ThreadContentField::RawPayload { payload_index }
        }
        BridgeContentField::PlanDocument => ThreadContentField::PlanDocument,
        BridgeContentField::PlanFeedback => ThreadContentField::PlanFeedback,
    }
}

fn protocol_part(part: BridgeThreadUserInputFieldPart) -> ThreadUserInputFieldPart {
    match part {
        BridgeThreadUserInputFieldPart::Header => ThreadUserInputFieldPart::Header,
        BridgeThreadUserInputFieldPart::Question => ThreadUserInputFieldPart::Question,
        BridgeThreadUserInputFieldPart::Answer { answer_index } => {
            ThreadUserInputFieldPart::Answer { answer_index }
        }
        BridgeThreadUserInputFieldPart::OptionLabel { option_index } => {
            ThreadUserInputFieldPart::OptionLabel { option_index }
        }
        BridgeThreadUserInputFieldPart::OptionDescription { option_index } => {
            ThreadUserInputFieldPart::OptionDescription { option_index }
        }
    }
}
