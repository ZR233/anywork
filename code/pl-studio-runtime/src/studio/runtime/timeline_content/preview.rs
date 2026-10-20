//! 产品展示预览：core 条目 → wire 预览值，以及宿主的展示字节预算。
//!
//! 预算是**展示**预算，不是事实预算：可靠待保存内容与活动引用另有其原有上限，预览裁剪既不改写
//! 完整长度、revision、身份与顺序，也不改变 canonical payload 或落盘格式。

use std::collections::BTreeSet;

use anyhow::{Result, anyhow};
use pl_core::chat::{CHAT_ITEM_PREVIEW_BYTES, ChatError, ChatField, ChatItem, ChatLifecycle};
use pl_protocol::{
    AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, TimelineDetailRef, TimelineItem,
    TimelineLifecycle, studio::StudioError, studio::StudioErrorCode,
};

use crate::plan_tool::TOOL_PLAN_SUBMIT;
use crate::studio::runtime::chat_item::{
    TOOL_ARGUMENTS_FIELD, TOOL_RESULT_FIELD, TOOL_USER_INPUT_FIELD, canonical_item, item_shell,
    user_input_option_label_field,
};
use crate::studio::runtime::timeline_content::field::wire_field;

/// 一条条目展示预览的正文总预算。
pub(crate) const PRODUCT_PREVIEW_BYTES: usize = 32 * 1024;
/// 工具参数与工具结果各自的展示预算。
pub(crate) const TOOL_FIELD_PREVIEW_BYTES: usize = 4 * 1024;

/// 宿主展示预算：正文合计 32 KiB，工具参数与结果各最多 4 KiB。
///
/// 这是 [`pl_core::chat::ChatHistory::bounded`] 的产品实现，因此页、订阅基线与实时出帧共用同一份
/// 裁剪规则。结构与正文共用同一条 256 KiB 上限：`meta`、身份、字段声明与详情引用先占用自己那份，
/// 剩下的才是可缩正文，所以空字段、短字段与长宿主 key 都不是免费的。不可再缩减的结构超出上限时
/// 明确报告资源限制，绝不回退成整段大载荷，也不删字段或截身份。
pub(crate) fn bounded(item: &ChatItem) -> Result<ChatItem, ChatError> {
    let structure = item.preview_structure_bytes();
    if structure > CHAT_ITEM_PREVIEW_BYTES {
        return Err(ChatError::Overloaded(format!(
            "static structure of {} exceeds the preview budget",
            item.item_id
        )));
    }
    // 计划确认的权威选项 label 与真正的决定答案先占用真实字节额度：它们是判别事实，不能因为正文剩余
    // 额度变小而被裁成空串或前缀，否则界面会显示“已解决但决定缺失”。自由修改反馈与普通问答答案都是
    // 自由正文，照常参与裁剪（完整文本仍可按身份读详情），不会单独触发硬资源限制。
    let marks = plan_marks(item);
    let keep_whole = |field: &ChatField| marks.contains(field);
    let reserved = item
        .field_previews()
        .filter(|(field, _)| keep_whole(field))
        .fold(0usize, |total, (_, preview)| {
            total.saturating_add(preview.block.len())
        });
    if reserved > PRODUCT_PREVIEW_BYTES
        || structure.saturating_add(reserved) > CHAT_ITEM_PREVIEW_BYTES
    {
        return Err(ChatError::Overloaded(format!(
            "authoritative marks of {} exceed the preview budget",
            item.item_id
        )));
    }
    let body_budget = PRODUCT_PREVIEW_BYTES
        .min(CHAT_ITEM_PREVIEW_BYTES - structure)
        .saturating_sub(reserved);
    if !exceeds_budget(item, body_budget, &keep_whole) {
        return Ok(item.clone());
    }
    let mut preview = item.clone();
    let mut remaining = body_budget;
    for (field, value) in preview.fields.iter_mut() {
        if keep_whole(field) {
            continue;
        }
        let cap = field_cap(field).min(remaining);
        let (block, kept) = pl_core::model::ContentBlock::prefix_at(&value.block, cap);
        value.block = block;
        remaining = remaining.saturating_sub(kept);
    }
    Ok(preview)
}

/// Whether any free field preview would exceed its share of the remaining body budget.
fn exceeds_budget(
    item: &ChatItem,
    body_budget: usize,
    keep_whole: &impl Fn(&ChatField) -> bool,
) -> bool {
    let mut remaining = body_budget;
    for (field, preview) in item.field_previews() {
        if keep_whole(field) {
            continue;
        }
        let cap = field_cap(field).min(remaining);
        if preview.block.len() > cap {
            return true;
        }
        remaining = remaining.saturating_sub(preview.block.len());
    }
    false
}

/// The authoritative decision facts of a Plan confirmation item, as field identities.
///
/// Two things count, both taken from this item's **own content regions**:
///
/// - the plan confirmation question's own option label fields — `Approve`／`Revise` as the plan tool
///   published them. The static shell cannot supply them: it clears every dynamic string, so it only
///   says *where* the question is and how many options it declares;
/// - the recorded answers of that question whose complete value is exactly one of those labels.
///
/// Everything else recorded on the same question (revision feedback, an `is_other` free answer, any
/// ordinary Q&A answer) is free body text: it stays inside the shared preview budget and remains
/// readable in full through its detail entry. Nothing is taken from the current Plan state, a tool's
/// success or a pending interaction, and no product string is re-declared here.
#[derive(Default)]
struct PlanMarks {
    protected: BTreeSet<ChatField>,
}

impl PlanMarks {
    /// Whether this field must be delivered whole: an authoritative label or a real decision answer.
    fn contains(&self, field: &ChatField) -> bool {
        self.protected.contains(field)
    }
}

/// Collects the protected decision facts of one item, decoding the canonical static shell only when the
/// item carries typed Q&A content at all.
///
/// Such an item publishes its question and answers a handful of times, never once per streamed token, so
/// the ordinary text hot path never reaches the decode. The shell is used for structure only — which
/// question is the plan confirmation and how many options it declares — while every label value comes
/// from this item's label fields, so bounding the item again never loses the decision basis. A pending
/// confirmation protects its labels too: the options are the decision the user is asked to make.
fn plan_marks(item: &ChatItem) -> PlanMarks {
    if !item.fields.keys().any(is_user_input_field) {
        return PlanMarks::default();
    }
    let Ok(shell) = item_shell(&item.meta, item.revision) else {
        return PlanMarks::default();
    };
    let Some(tool) = shell.tool() else {
        return PlanMarks::default();
    };
    if tool.invocation().name() != TOOL_PLAN_SUBMIT {
        return PlanMarks::default();
    }
    let Some(user_input) = tool.user_input() else {
        return PlanMarks::default();
    };
    let Some((position, question)) = user_input
        .questions()
        .iter()
        .enumerate()
        .find(|(_, question)| question.id == AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID)
    else {
        return PlanMarks::default();
    };
    let mut protected = BTreeSet::new();
    let mut labels = Vec::new();
    // The shell's `options` list keeps its length with every label cleared, so it says how many label
    // fields exist without providing any of their text.
    for option in 0..question.options.as_ref().map_or(0, Vec::len) {
        let field = user_input_option_label_field(position, option);
        let Some(preview) = item.fields.get(&field) else {
            continue;
        };
        // Only a complete label can prove a decision; a truncated or empty one is never guessed.
        if !preview.is_complete() {
            continue;
        }
        labels.push(preview.block.text());
        protected.insert(field);
    }
    for (field, preview) in item.field_previews() {
        let Some((question, _)) = answer_position(field) else {
            continue;
        };
        if question != position || !preview.is_complete() || labels.is_empty() {
            continue;
        }
        if labels
            .iter()
            .any(|label| label.len() == preview.block.len() && *label == preview.block.text())
        {
            protected.insert(field.clone());
        }
    }
    PlanMarks { protected }
}

/// `(question position, answer index)` of one recorded answer field, if this is one.
fn answer_position(field: &ChatField) -> Option<(usize, usize)> {
    let ChatField::Host(key) = field else {
        return None;
    };
    let answer = key.as_ref().strip_prefix(TOOL_USER_INPUT_FIELD)?;
    let position = answer.strip_prefix("answer.")?;
    let (question, index) = position.split_once('.')?;
    Some((question.parse().ok()?, index.parse().ok()?))
}

/// Whether this field belongs to the typed Q&A / plan-confirmation content domain at all.
///
/// This is the cheap gate in front of the canonical-shell decode: only such an item can carry a plan
/// confirmation, and it publishes its question and answers a handful of times rather than once per
/// streamed token.
fn is_user_input_field(field: &ChatField) -> bool {
    let ChatField::Host(key) = field else {
        return false;
    };
    key.as_ref().starts_with(TOOL_USER_INPUT_FIELD)
}

/// 一个字段的展示上限：工具参数与结果各自 4 KiB，其余字段共享剩余总预算。
fn field_cap(field: &ChatField) -> usize {
    match field {
        ChatField::Host(key)
            if key.as_ref() == TOOL_ARGUMENTS_FIELD || key.as_ref() == TOOL_RESULT_FIELD =>
        {
            TOOL_FIELD_PREVIEW_BYTES
        }
        _ => PRODUCT_PREVIEW_BYTES,
    }
}

/// 一条 core 条目 → wire 预览值（含逐字段详情引用）。
pub(crate) fn timeline_item(item: &ChatItem) -> Result<TimelineItem> {
    let mut details = Vec::new();
    for (field, preview) in item.field_previews() {
        let Some(field) = wire_field(field) else {
            return Err(anyhow!(StudioError::new(
                StudioErrorCode::Protocol,
                "timeline item carries a content field this product cannot address",
                false,
            )));
        };
        details.push(TimelineDetailRef {
            field,
            revision: item.revision,
            total_bytes: preview.total_bytes,
            preview_bytes: preview.block.len() as u64,
        });
    }
    Ok(TimelineItem {
        source: crate::studio::thread_projection::order::timeline_source(&item.item_id),
        preview: canonical_item(item)?,
        saved: item.saved,
        lifecycle: match item.lifecycle {
            ChatLifecycle::Streaming => TimelineLifecycle::Streaming,
            ChatLifecycle::Terminal => TimelineLifecycle::Terminal,
        },
        omitted_bytes: item.omitted_bytes(),
        details,
    })
}
