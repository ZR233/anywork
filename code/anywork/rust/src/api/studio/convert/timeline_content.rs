//! Timeline 内容 → FRB DTO 的机械映射。
//!
//! 内容映射的唯一实现是 runtime 的 `pl_studio_runtime::timeline_content`（HTTP 与 FRB 共用）。这个
//! 模块只把已交付的 typed 结果逐字段转成 FRB 可生成类型：不复制差量逻辑、不持有第二份内容索引，也不
//! 自己重建基线。

use pl_protocol::{
    ThreadContentField, ThreadUserInputFieldPart, TimelineChange, TimelineDetailChunk,
    TimelineDetailQuery, TimelineDetailRef, TimelineFieldChange, TimelineFieldUpdate, TimelineItem,
    TimelineItemSource, TimelineLifecycle, TimelinePage, TimelinePageQuery, TimelinePriority,
    TimelineRecoveryNotice, TimelineResyncReason, TimelineTailBaseline, TimelineTailUpdate,
};

use crate::api::studio::convert::thread_stream::bridge_chat_thread_item;
use crate::api::studio::types::{
    BridgeContentField, BridgeError, BridgeThreadUserInputFieldPart, BridgeTimelineBaseline,
    BridgeTimelineChange, BridgeTimelineDetailChunk, BridgeTimelineDetailQuery,
    BridgeTimelineDetailRef, BridgeTimelineFieldChange, BridgeTimelineFieldUpdate,
    BridgeTimelineItem, BridgeTimelineItemSource, BridgeTimelineLifecycle, BridgeTimelinePage,
    BridgeTimelinePriority, BridgeTimelineRecoveryNotice, BridgeTimelineResyncReason,
    BridgeTimelineUpdate,
};

/// Counts standard JSON bytes of a product Timeline payload without retaining the encoding.
pub(crate) fn encoded_payload_bytes(value: &impl serde::Serialize) -> Result<u64, BridgeError> {
    struct Counter(u64);
    impl std::io::Write for Counter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            self.0 = self.0.saturating_add(bytes.len() as u64);
            Ok(bytes.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    let mut counter = Counter(0);
    serde_json::to_writer(&mut counter, value).map_err(BridgeError::from)?;
    Ok(counter.0)
}

pub(crate) fn page(value: TimelinePage) -> Result<BridgeTimelinePage, BridgeError> {
    Ok(BridgeTimelinePage {
        items: value
            .items
            .into_iter()
            .map(item)
            .collect::<Result<_, _>>()?,
        before: value.before,
        has_older: value.has_older,
    })
}

/// FRB 页请求 → 共享页查询。
pub(crate) fn page_query(before: Option<String>, limit: Option<u32>) -> TimelinePageQuery {
    TimelinePageQuery { before, limit }
}

pub(crate) fn baseline(value: TimelineTailBaseline) -> Result<BridgeTimelineBaseline, BridgeError> {
    Ok(BridgeTimelineBaseline {
        subscription_id: value.subscription_id,
        version: value.version,
        items: value
            .items
            .into_iter()
            .map(item)
            .collect::<Result<_, _>>()?,
        before: value.before,
        has_older: value.has_older,
    })
}

pub(crate) fn update(value: TimelineTailUpdate) -> Result<BridgeTimelineUpdate, BridgeError> {
    Ok(match value {
        TimelineTailUpdate::Patch {
            subscription_id,
            from,
            to,
            changes,
            priority,
        } => BridgeTimelineUpdate::Patch {
            subscription_id,
            from,
            to,
            changes: changes.into_iter().map(change).collect::<Result<_, _>>()?,
            priority: priority_dto(priority),
        },
        TimelineTailUpdate::Resync {
            subscription_id,
            reason,
            baseline: value,
        } => BridgeTimelineUpdate::Resync {
            subscription_id,
            reason: resync_reason(reason),
            baseline: baseline(value)?,
        },
    })
}

pub(crate) fn detail_query(value: BridgeTimelineDetailQuery) -> TimelineDetailQuery {
    TimelineDetailQuery {
        field: protocol_field(value.field),
        revision: value.revision,
        continuation: value.continuation,
        max_bytes: value.max_bytes,
    }
}

pub(crate) fn detail_chunk(
    value: TimelineDetailChunk,
) -> Result<BridgeTimelineDetailChunk, BridgeError> {
    Ok(BridgeTimelineDetailChunk {
        item_id: value.item_id,
        field: content_field(value.field),
        revision: value.revision,
        text: value.text,
        total_bytes: value.total_bytes,
        continuation: value.continuation,
    })
}

fn item(value: TimelineItem) -> Result<BridgeTimelineItem, BridgeError> {
    Ok(BridgeTimelineItem {
        item: bridge_chat_thread_item(value.preview)?,
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
        saved: value.saved,
        lifecycle: lifecycle_dto(value.lifecycle),
        omitted_bytes: value.omitted_bytes,
        details: value.details.into_iter().map(detail_ref).collect(),
    })
}

fn detail_ref(value: TimelineDetailRef) -> BridgeTimelineDetailRef {
    BridgeTimelineDetailRef {
        field: content_field(value.field),
        revision: value.revision,
        total_bytes: value.total_bytes,
        preview_bytes: value.preview_bytes,
    }
}

fn change(value: TimelineChange) -> Result<BridgeTimelineChange, BridgeError> {
    Ok(match value {
        TimelineChange::Add { item: value } => BridgeTimelineChange::Add {
            item: Box::new(item(*value)?),
        },
        TimelineChange::Remove { item_id } => BridgeTimelineChange::Remove { item_id },
        TimelineChange::UpdateItem {
            item_id,
            expected_revision,
            revision,
            omitted_bytes,
            saved,
            lifecycle,
            item_shell,
            fields,
        } => BridgeTimelineChange::UpdateItem {
            item_id,
            expected_revision,
            revision,
            omitted_bytes,
            saved,
            lifecycle: lifecycle_dto(lifecycle),
            item_shell: item_shell
                .map(|shell| bridge_chat_thread_item(*shell).map(Box::new))
                .transpose()?,
            fields: fields.into_iter().map(field_update).collect(),
        },
    })
}

fn field_update(value: TimelineFieldUpdate) -> BridgeTimelineFieldUpdate {
    BridgeTimelineFieldUpdate {
        field: content_field(value.field),
        change: field_change(value.change),
        total_bytes: value.total_bytes,
        preview_bytes: value.preview_bytes,
    }
}

fn field_change(value: TimelineFieldChange) -> BridgeTimelineFieldChange {
    match value {
        TimelineFieldChange::Unchanged => BridgeTimelineFieldChange::Unchanged,
        TimelineFieldChange::Append { text } => BridgeTimelineFieldChange::Append { text },
        TimelineFieldChange::Replace { text } => BridgeTimelineFieldChange::Replace { text },
        TimelineFieldChange::Remove => BridgeTimelineFieldChange::Remove,
    }
}

fn lifecycle_dto(value: TimelineLifecycle) -> BridgeTimelineLifecycle {
    match value {
        TimelineLifecycle::Streaming => BridgeTimelineLifecycle::Streaming,
        TimelineLifecycle::Terminal => BridgeTimelineLifecycle::Terminal,
    }
}

fn priority_dto(value: TimelinePriority) -> BridgeTimelinePriority {
    match value {
        TimelinePriority::Immediate => BridgeTimelinePriority::Immediate,
        TimelinePriority::Coalesced => BridgeTimelinePriority::Coalesced,
    }
}

fn resync_reason(value: TimelineResyncReason) -> BridgeTimelineResyncReason {
    match value {
        TimelineResyncReason::Lagging => BridgeTimelineResyncReason::Lagging,
        TimelineResyncReason::Unavailable => BridgeTimelineResyncReason::Unavailable,
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

/// FRB 字段身份 → 共享字段身份（读详情时的请求方向）。
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
