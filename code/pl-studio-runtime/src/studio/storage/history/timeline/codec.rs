//! Frozen published v9/v11 conversion codec, copied from cb222f6a. Migration-only.
use crate::{ExecutionItem, ExecutionShape};
// Canonical `ExecutionItem` → typed `ChatItem`/`ChatDraft` 适配。
//
// core 的内容条目是「静态结构 + 若干共享 `ContentBlock` 内容域」。宿主把 canonical 条目的**静态部分**
// （身份、kind、时间戳、附件、工具身份……）编码一次进 `meta`，把**动态正文**按 [`ChatField`] 放进
// `fields`：流式热路径只克隆 `Arc`/共享链，不 JSON、不逐 token 复制全文。
//
// 完成草稿经 `Session::publish_batch` 冻结为不可变完成记录；读取 DTO 直接解码头部与描述并遍历
// 有界字段。完成记录不携带执行 ordinal/revision/时间戳——它们是 Runtime 的内部执行事实，因此这里
// 不存在“从完成记录重建 canonical ExecutionItem”的方向；实时预览的权威重建由 live 投影用自身
// 的运行事实直接完成，不经过完成 meta。
// `static_state` 仅服务投影判等，不是内存 meta 或读取 DTO。

use std::collections::BTreeMap;
use std::sync::Arc;

use super::frozen::{ChatDraft, ChatField};
use anyhow::Result;
use pl_core::chat::PresentationPart;
use pl_core::model::ContentBlock;

use pl_protocol::{
    ThreadThinkingItem, ThreadToolState, ThreadToolUserInput, ThreadToolUserInputState,
    UserQuestion,
};

use self::meta::{
    PLAN_DOCUMENT_FIELD, PLAN_FEEDBACK_FIELD, count, plan_completion, validate_counts,
};

#[path = "record.rs"]
pub(super) mod record;
pub(crate) use record::{decode_record, encode_record};
#[path = "legacy.rs"]
mod legacy;
#[path = "meta.rs"]
pub(super) mod meta;
pub(crate) use legacy::legacy_completion_drafts;
pub(in crate::studio::storage::history) use meta::TimelineMeta;

// Freeze only the acknowledged background handoff, not the still-running final result.

// 工具参数、工具结果与工具开放产物各自的宿主字段域 key（稳定身份，不是内容推断）。
pub(crate) const TOOL_ARGUMENTS_FIELD: &str = "tool.arguments";
pub(crate) const TOOL_RESULT_FIELD: &str = "tool.result";
pub(crate) const TOOL_OUTPUT_ARTIFACTS_FIELD: &str = "tool.output-artifacts";
// 普通问答投影的正文域 key 前缀（见 [`user_input_question_field`] / [`user_input_answer_field`]）。
pub(crate) const TOOL_USER_INPUT_FIELD: &str = "tool.user-input.";
// 原始记录正文域 key 前缀：一段原始 payload 的正文按它在记录里的顺序寻址。
pub(crate) const RAW_PAYLOAD_FIELD: &str = "raw.payload.";

// 把一条 canonical 条目冻结为完成草稿：静态结构进 `meta`，动态正文进 `fields`。
//
// 调用方只在该条目的可靠完成边界构造一次草稿：`sealed_at` 取执行事实的落章时间，`turn_id`
// 为空表示发布时消费 Turn 未知（之后不得回补修改已发布原子）。执行 ordinal/revision 不进入
// 完成记录——它们是 Runtime 的内部执行索引。
pub(crate) fn completion_draft(item: &ExecutionItem, source_effect_seq: u64) -> Result<ChatDraft> {
    let meta = static_meta(item)?;
    let fields = if let Some(plan) = plan_completion(item)? {
        let mut fields = BTreeMap::new();
        if let Some(document) = plan.document {
            fields.insert(
                ChatField::host(PLAN_DOCUMENT_FIELD),
                ContentBlock::from_text(&document),
            );
        }
        if let Some(feedback) = plan.feedback {
            fields.insert(
                ChatField::host(PLAN_FEEDBACK_FIELD),
                ContentBlock::from_text(&feedback),
            );
        }
        fields
    } else {
        content_fields(item.state())?
    };
    let turn_id = (!item.turn_id.is_empty()).then(|| item.turn_id.clone());
    Ok(ChatDraft {
        item_id: item.id.clone(),
        turn_id,
        source_effect_seq: Some(source_effect_seq),
        sealed_at: Some(item.updated_at),
        fields,
        meta,
    })
}

// 仅编码完成身份与独立描述；执行 revision 不进入完成记录。
pub(crate) fn static_meta(item: &ExecutionItem) -> Result<Arc<[u8]>> {
    Ok(Arc::from(serde_json::to_vec(&TimelineMeta::from_item(
        item,
    )?)?))
}

// 动态正文域：只由条目自己的动态事实派生，正文块与生产者共享。
//
// 超出 u32 的位置/数量返回 Overloaded；问答关联缺失明确失败，不静默丢弃答案。
pub(crate) fn content_fields(
    state: &ExecutionShape,
) -> Result<BTreeMap<ChatField, Arc<ContentBlock>>> {
    validate_counts(state)?;
    let mut fields = BTreeMap::new();
    match state {
        ExecutionShape::Text(text) => {
            fields.insert(ChatField::Body, ContentBlock::from_text(text.text()));
        }
        ExecutionShape::Thinking(thinking) => {
            for (index, chunk) in thinking.summary().iter().enumerate() {
                fields.insert(
                    ChatField::Part(PresentationPart::SummaryText(count(index)?)),
                    ContentBlock::from_text(chunk),
                );
            }
            for (index, chunk) in thinking.content().iter().enumerate() {
                fields.insert(
                    ChatField::Part(PresentationPart::ReasoningText(count(index)?)),
                    ContentBlock::from_text(chunk),
                );
            }
        }
        ExecutionShape::Tool(tool) => {
            fields.insert(
                ChatField::host(TOOL_ARGUMENTS_FIELD),
                ContentBlock::from_text(tool.invocation().arguments()),
            );
            if let Some(output) = streamed_output(tool.state()) {
                fields.insert(
                    ChatField::host(TOOL_RESULT_FIELD),
                    ContentBlock::from_text(output),
                );
            }
            // A terminal tool result and its open artifacts are dynamic bodies too: they are user
            // visible, can be large, and must share the same bounded preview instead of staying in
            // the static metadata where no budget could ever reach them.
            if let Some(output) = tool.terminal_output() {
                fields.insert(
                    ChatField::host(TOOL_RESULT_FIELD),
                    ContentBlock::from_text(output.result()),
                );
                if !output.output_artifacts().is_empty() {
                    // Encoding through the value's own `Display` cannot fail; the open payload is
                    // only serialized again at the canonical/detail boundary.
                    let encoded =
                        serde_json::Value::Array(output.output_artifacts().to_vec()).to_string();
                    fields.insert(
                        ChatField::host(TOOL_OUTPUT_ARTIFACTS_FIELD),
                        ContentBlock::from_text(&encoded),
                    );
                }
            }
            // 问答正文同样进内容域：它和其它正文共享同一份有界预览、按身份回源与省略量，不能因为
            // 塞进静态 meta 而绕过预算。问题按原顺序索引，答案按所属问题的位置索引。
            if let Some(user_input) = tool.user_input() {
                for (position, question) in user_input.questions().iter().enumerate() {
                    for (field, text) in user_input_question_fields(position, question) {
                        fields.insert(field, ContentBlock::from_text(text));
                    }
                }
                for answer in user_input.answers() {
                    // validate_counts 已验证关联；正文始终来自公开投影，不回读私有值。
                    if answer.is_redacted()
                        || user_input.questions().iter().any(|question| {
                            question.id == answer.question_id() && question.is_secret
                        })
                    {
                        continue;
                    }
                    let position =
                        question_position(user_input, answer.question_id()).ok_or_else(|| {
                            anyhow::anyhow!("validated timeline answer lost its question")
                        })?;
                    for (index, value) in answer.answers().iter().enumerate() {
                        fields.insert(
                            user_input_answer_field(position, index),
                            ContentBlock::from_text(value),
                        );
                    }
                }
            }
        }
        ExecutionShape::Raw(raw) => {
            // Original producer payloads are shown as正文, so they are one field each instead of a
            // static blob that bypasses every preview budget.
            for (index, payload) in raw.payloads.iter().enumerate() {
                fields.insert(
                    raw_payload_field(index),
                    ContentBlock::from_text(&payload.content),
                );
            }
        }
        _ => {}
    }
    Ok(fields)
}

// 同一条目的**结构 / 终态形状**：动态正文被清空，kind、附件、生命周期与工具状态如实保留。
//
// 仅用于宿主投影的内容版本比较：工具状态转移（Running→Succeeded 等）与执行终态
// （streaming→completed/failed/cancelled）都是载荷变化，必须递增内容版本，否则旧的保存回执
// 会张冠李戴地确认新载荷。读取 DTO 和内存 meta 不消费这里的空正文结构。
//
// 它**不含** `ExecutionItem` 上会随每次投影变化的易变时间戳（`created_at`/`updated_at`），因此同一条目
// 重复投影不会无意义地抬高内容版本；但生命周期自带的 `completed_at`/`failed_at` 属于真实转移，保留。

// 一个问题标题的内容域身份。
pub(crate) fn user_input_header_field(question_index: usize) -> ChatField {
    ChatField::host(format!(
        "{TOOL_USER_INPUT_FIELD}question.{question_index}.header"
    ))
}

// 一个原问题正文的内容域身份：索引是它在原问题顺序里的位置。
pub(crate) fn user_input_question_field(question_index: usize) -> ChatField {
    ChatField::host(format!(
        "{TOOL_USER_INPUT_FIELD}question.{question_index}.body"
    ))
}

// 一个问题选项标签的内容域身份。
pub(crate) fn user_input_option_label_field(
    question_index: usize,
    option_index: usize,
) -> ChatField {
    ChatField::host(format!(
        "{TOOL_USER_INPUT_FIELD}question.{question_index}.option.{option_index}.label"
    ))
}

// 一个问题选项说明的内容域身份。
pub(crate) fn user_input_option_description_field(
    question_index: usize,
    option_index: usize,
) -> ChatField {
    ChatField::host(format!(
        "{TOOL_USER_INPUT_FIELD}question.{question_index}.option.{option_index}.description"
    ))
}

// 一个已接受答案值的内容域身份：问题位置 + 该问题答案列表内的序号。
pub(crate) fn user_input_answer_field(question_index: usize, answer_index: usize) -> ChatField {
    ChatField::host(format!(
        "{TOOL_USER_INPUT_FIELD}answer.{question_index}.{answer_index}"
    ))
}

// 一个问题里所有可展示正文与其内容域身份，按固定顺序列出。
fn user_input_question_fields(
    question_index: usize,
    question: &UserQuestion,
) -> Vec<(ChatField, &str)> {
    let mut fields = vec![
        (
            user_input_header_field(question_index),
            question.header.as_str(),
        ),
        (
            user_input_question_field(question_index),
            question.question.as_str(),
        ),
    ];
    for (option_index, option) in question.options.iter().flatten().enumerate() {
        fields.push((
            user_input_option_label_field(question_index, option_index),
            option.label.as_str(),
        ));
        fields.push((
            user_input_option_description_field(question_index, option_index),
            option.description.as_str(),
        ));
    }
    fields
}

// 一个已作答问题在原问题顺序里的位置。
//
// 回答以 question ID 关联问题，投影边界保证每个回答都指向一个真实问题；结构本身仍按位置寻址，
// 因此一段正文在 `content_fields` 与完成读取两侧落到同一个域上。
fn question_position(user_input: &ThreadToolUserInput, question_id: &str) -> Option<usize> {
    user_input
        .questions()
        .iter()
        .position(|question| question.id == question_id)
}

// 静态结构里的问答：所有正文清空，结构、顺序、ID 与脱敏状态如实保留。

fn streamed_output(state: &ThreadToolState) -> Option<&str> {
    match state {
        ThreadToolState::Running(running) => Some(running.streamed_output()),
        ThreadToolState::Cancelling(cancelling) => Some(cancelling.streamed_output()),
        _ => None,
    }
}

// 原始记录一段正文的内容域身份。
fn raw_payload_field(payload_index: usize) -> ChatField {
    ChatField::host(format!("{RAW_PAYLOAD_FIELD}{payload_index}"))
}

// 只有正文被清空的终态工具输出，其余结构（附件、退出码、失败原因）保持不变。

// 只用于 static_state 的结构判等，保留 task/call 关联；不用于读取或内存 meta 编码。
