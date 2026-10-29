//! core 字段身份 ↔ 产品字段身份的**唯一**映射，以及两种不透明游标的边界转换。
//!
//! 映射只由字段身份决定，不从内容字符串推断。真实产品字段之外的身份不下沉成“猜一个标签”，而是
//! 明确失败或让调用方按权威重同步收束。

use anyhow::{Result, anyhow};
use pl_core::chat::{ChatCursor, ChatDetailCursor, ChatField, PresentationPart, TimelineEpoch};
use pl_protocol::{
    ThreadContentField, ThreadUserInputFieldPart, TimelineDetailCursor, TimelineDetailQuery,
    TimelinePageCursor, studio::StudioError, studio::StudioErrorCode,
};

use super::meta::{PLAN_DOCUMENT_FIELD, PLAN_FEEDBACK_FIELD};
use crate::studio::runtime::chat_item::{
    RAW_PAYLOAD_FIELD, TOOL_ARGUMENTS_FIELD, TOOL_OUTPUT_ARTIFACTS_FIELD, TOOL_RESULT_FIELD,
    TOOL_USER_INPUT_FIELD,
};

/// core 字段身份 → 产品字段身份；未知宿主字段返回 `None`。
pub(crate) fn wire_field(field: &ChatField) -> Option<ThreadContentField> {
    match field {
        ChatField::Body => Some(ThreadContentField::Text),
        ChatField::Part(PresentationPart::OutputText(_)) => Some(ThreadContentField::Text),
        ChatField::Part(PresentationPart::ReasoningText(index)) => {
            Some(ThreadContentField::ThinkingContent {
                chunk_index: *index,
            })
        }
        ChatField::Part(PresentationPart::SummaryText(index)) => {
            Some(ThreadContentField::ThinkingSummary {
                chunk_index: *index,
            })
        }
        ChatField::Host(key) if key.as_ref() == TOOL_ARGUMENTS_FIELD => {
            Some(ThreadContentField::ToolArguments)
        }
        ChatField::Host(key) if key.as_ref() == TOOL_RESULT_FIELD => {
            Some(ThreadContentField::ToolResult)
        }
        ChatField::Host(key) if key.as_ref() == TOOL_OUTPUT_ARTIFACTS_FIELD => {
            Some(ThreadContentField::ToolOutputArtifacts)
        }
        ChatField::Host(key) if key.as_ref() == PLAN_DOCUMENT_FIELD => {
            Some(ThreadContentField::PlanDocument)
        }
        ChatField::Host(key) if key.as_ref() == PLAN_FEEDBACK_FIELD => {
            Some(ThreadContentField::PlanFeedback)
        }
        ChatField::Host(key) => {
            if let Some(payload_index) = key.as_ref().strip_prefix(RAW_PAYLOAD_FIELD) {
                return payload_index
                    .parse()
                    .ok()
                    .map(|payload_index| ThreadContentField::RawPayload { payload_index });
            }
            user_input_field(key)
        }
    }
}

/// 产品字段身份 → core 字段身份。
pub(crate) fn core_field(field: ThreadContentField) -> ChatField {
    match field {
        ThreadContentField::Text => ChatField::Body,
        ThreadContentField::ThinkingSummary { chunk_index } => {
            ChatField::Part(PresentationPart::SummaryText(chunk_index))
        }
        ThreadContentField::ThinkingContent { chunk_index } => {
            ChatField::Part(PresentationPart::ReasoningText(chunk_index))
        }
        ThreadContentField::ToolArguments => ChatField::host(TOOL_ARGUMENTS_FIELD),
        ThreadContentField::ToolResult => ChatField::host(TOOL_RESULT_FIELD),
        ThreadContentField::ToolOutputArtifacts => ChatField::host(TOOL_OUTPUT_ARTIFACTS_FIELD),
        ThreadContentField::PlanDocument => ChatField::host(PLAN_DOCUMENT_FIELD),
        ThreadContentField::PlanFeedback => ChatField::host(PLAN_FEEDBACK_FIELD),
        ThreadContentField::ToolUserInput {
            question_index,
            part,
        } => {
            let question_index = question_index as usize;
            match part {
                ThreadUserInputFieldPart::Header => {
                    crate::studio::runtime::chat_item::user_input_header_field(question_index)
                }
                ThreadUserInputFieldPart::Question => {
                    crate::studio::runtime::chat_item::user_input_question_field(question_index)
                }
                ThreadUserInputFieldPart::Answer { answer_index } => {
                    crate::studio::runtime::chat_item::user_input_answer_field(
                        question_index,
                        answer_index as usize,
                    )
                }
                ThreadUserInputFieldPart::OptionLabel { option_index } => {
                    crate::studio::runtime::chat_item::user_input_option_label_field(
                        question_index,
                        option_index as usize,
                    )
                }
                ThreadUserInputFieldPart::OptionDescription { option_index } => {
                    crate::studio::runtime::chat_item::user_input_option_description_field(
                        question_index,
                        option_index as usize,
                    )
                }
            }
        }
        ThreadContentField::RawPayload { payload_index } => {
            ChatField::host(format!("{RAW_PAYLOAD_FIELD}{payload_index}"))
        }
    }
}

/// 普通问答正文域的 wire 身份：问题位置 + 该问题内的具体正文（标题/问题/选项/答案）。
fn user_input_field(key: &str) -> Option<ThreadContentField> {
    let rest = key.strip_prefix(TOOL_USER_INPUT_FIELD)?;
    let mut segments = rest.split('.');
    let scope = segments.next()?;
    let question_index: u32 = segments.next()?.parse().ok()?;
    let part = if scope == "answer" {
        ThreadUserInputFieldPart::Answer {
            answer_index: segments.next()?.parse().ok()?,
        }
    } else if scope == "question" {
        match segments.next()? {
            "header" => ThreadUserInputFieldPart::Header,
            "body" => ThreadUserInputFieldPart::Question,
            "option" => {
                let option_index = segments.next()?.parse().ok()?;
                match segments.next()? {
                    "label" => ThreadUserInputFieldPart::OptionLabel { option_index },
                    "description" => ThreadUserInputFieldPart::OptionDescription { option_index },
                    _ => return None,
                }
            }
            _ => return None,
        }
    } else {
        return None;
    };
    // 多出的段落说明这个 key 不是本模块产生的身份。
    segments
        .next()
        .is_none()
        .then_some(ThreadContentField::ToolUserInput {
            question_index,
            part,
        })
}

/// 上一页的不透明边界 token → 严格 keyset 边界；跨 Thread 或版本不符即拒绝。
pub(crate) fn page_cursor(thread_id: &str, token: &str) -> Result<ChatCursor> {
    let cursor = TimelinePageCursor::decode(token)
        .ok_or_else(|| invalid_argument("timeline page cursor is not a supported token"))?;
    if cursor.thread_id != thread_id {
        return Err(invalid_argument(
            "timeline page cursor belongs to another Thread",
        ));
    }
    Ok(ChatCursor::new(
        TimelineEpoch::new(cursor.timeline_epoch)?,
        cursor.append_seq,
        cursor.item_id,
    ))
}

/// 严格 keyset 边界 → Thread 绑定的不透明 token。
pub(crate) fn encode_page_cursor(thread_id: &str, cursor: &ChatCursor) -> String {
    TimelinePageCursor {
        thread_id: thread_id.to_owned(),
        timeline_epoch: cursor.epoch.as_str().to_owned(),
        append_seq: cursor.append_seq,
        item_id: cursor.item_id.clone(),
    }
    .encode()
}

/// 详情 continuation token → 字段内 continuation，逐项校验它与本次请求同属一个上下文。
///
/// token 绑定 Thread、item、字段身份、revision 与字节偏移；任何一项与当前请求不符都明确拒绝，绝不把
/// 一段偏移套到另一个字段、条目、版本或 Thread 上。
pub(crate) fn detail_cursor(
    thread_id: &str,
    item_id: &str,
    query: &TimelineDetailQuery,
    token: &str,
) -> Result<ChatDetailCursor> {
    let cursor = TimelineDetailCursor::decode(token)
        .ok_or_else(|| invalid_argument("timeline detail continuation is not a supported token"))?;
    if cursor.thread_id != thread_id {
        return Err(invalid_argument(
            "timeline detail continuation belongs to another Thread",
        ));
    }
    if cursor.item_id != item_id {
        return Err(invalid_argument(
            "timeline detail continuation belongs to another item",
        ));
    }
    if cursor.field != query.field.token_label() {
        return Err(invalid_argument(
            "timeline detail continuation belongs to another content field",
        ));
    }
    if cursor.timeline_epoch != query.timeline_epoch {
        return Err(invalid_argument(
            "timeline detail continuation binds another epoch",
        ));
    }
    Ok(ChatDetailCursor::new(
        item_id,
        core_field(query.field),
        cursor.offset,
    ))
}

/// 字段内 continuation → 绑定同一上下文的 wire token。
pub(crate) fn encode_detail_cursor(
    thread_id: &str,
    item_id: &str,
    query: &TimelineDetailQuery,
    offset: u64,
) -> String {
    TimelineDetailCursor {
        thread_id: thread_id.to_owned(),
        item_id: item_id.to_owned(),
        field: query.field.token_label(),
        timeline_epoch: query.timeline_epoch.clone(),
        offset,
    }
    .encode()
}

fn invalid_argument(reason: &str) -> anyhow::Error {
    anyhow!(StudioError::new(
        StudioErrorCode::InvalidArgument,
        reason.to_owned(),
        false,
    ))
}
