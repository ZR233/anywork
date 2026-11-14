//! 执行事实在可靠完成或观察封存边界编码为规范 JSON 与显式内容所有权。

use anyhow::{Result, ensure};
use pl_core::{
    chat::{
        ChatContent, ChatContentKey, ChatContents, ChatDraft, ChatKey, ContentData,
        ContentDescriptor, PresentationPart,
    },
    model::ContentBlock,
};
use pl_protocol::{
    ContentOwner, ContentRef, ContentTarget, ResolvedThreadToolUserInput, ThreadItem,
    ThreadItemState, ThreadRawItem, ThreadRawPayload, ThreadTextItem, ThreadThinkingItem,
    ThreadToolInvocation, ThreadToolItem, ThreadToolState, ThreadToolUserInput,
    ThreadToolUserInputAnswer, ThreadToolUserInputState, UserQuestion,
};
use std::{collections::BTreeMap, sync::Arc};

mod accepted;
mod atom;
pub(in crate::studio) use accepted::{accepted_inbox_draft, accepted_input_draft};
mod read_hint;
pub(in crate::studio) use read_hint::{native_read_class_v1, native_read_hint_v1};
mod descriptor;
mod payload;
pub(crate) use atom::atom;
use descriptor::{
    PLAN_DOCUMENT_FIELD, PLAN_FEEDBACK_FIELD, count, plan_completion, validate_counts,
};

/// 仅用于执行投影的正文位置比较；不进入 Core、存储记录或产品 DTO。
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum BodyKey {
    Body,
    Part(PresentationPart),
    Host(String),
}
impl BodyKey {
    pub(crate) fn host(key: impl Into<String>) -> Self {
        Self::Host(key.into())
    }
    pub(crate) fn as_key(&self) -> String {
        match self {
            Self::Body => "body".into(),
            Self::Host(key) => key.clone(),
            Self::Part(PresentationPart::OutputText(index)) => format!("part.outputText.{index}"),
            Self::Part(PresentationPart::ReasoningText(index)) => {
                format!("part.reasoningText.{index}")
            }
            Self::Part(PresentationPart::SummaryText(index)) => format!("part.summaryText.{index}"),
        }
    }
}

pub(crate) const TOOL_ARGUMENTS_FIELD: &str = "tool.arguments";
pub(crate) const TOOL_RESULT_FIELD: &str = "tool.result";
pub(crate) const TOOL_OUTPUT_ARTIFACTS_FIELD: &str = "tool.output-artifacts";
pub(crate) const TOOL_USER_INPUT_FIELD: &str = "tool.user-input.";
pub(crate) const RAW_PAYLOAD_FIELD: &str = "raw.payload.";
const INLINE_BODY_BYTES: usize = 4096;

/// Only canonical member body roles belong to the small provenance header. Structured details
/// (questions, raw payload fields, attachments) keep their existing manifest/collection owners.
pub(crate) fn atom_content_role(key: &BodyKey) -> Option<pl_protocol::ChatContentRole> {
    use pl_protocol::ChatContentRole as Role;
    match key {
        BodyKey::Body
        | BodyKey::Part(PresentationPart::OutputText(_) | PresentationPart::ReasoningText(_)) => {
            Some(Role::Body)
        }
        BodyKey::Part(PresentationPart::SummaryText(_)) => Some(Role::ReasoningSummary),
        BodyKey::Host(key) if key == TOOL_ARGUMENTS_FIELD => Some(Role::ToolArguments),
        BodyKey::Host(key) if key == TOOL_RESULT_FIELD => Some(Role::ToolOutput),
        BodyKey::Host(key) if key == PLAN_DOCUMENT_FIELD || key == PLAN_FEEDBACK_FIELD => {
            Some(Role::Body)
        }
        BodyKey::Host(_) => None,
    }
}

pub(crate) fn atom_content_role_by_key(key: &str) -> Option<pl_protocol::ChatContentRole> {
    let parsed = if key == "body" {
        BodyKey::Body
    } else if key.starts_with("part.outputText.") {
        BodyKey::Part(PresentationPart::OutputText(0))
    } else if key.starts_with("part.reasoningText.") {
        BodyKey::Part(PresentationPart::ReasoningText(0))
    } else if key.starts_with("part.summaryText.") {
        BodyKey::Part(PresentationPart::SummaryText(0))
    } else {
        BodyKey::Host(key.to_owned())
    };
    atom_content_role(&parsed)
}

/// 一次完成只编码一次。后续查询不再通过当前 renderer 解码历史。
#[cfg(test)]
pub(crate) fn completion_draft(
    item: &ThreadItem,
    source_effect_seq: u64,
    database_id: &str,
) -> Result<ChatDraft> {
    completion_draft_reusing(item, source_effect_seq, database_id, &ChatContents::new())
}

pub(crate) fn completion_draft_reusing(
    item: &ThreadItem,
    source_effect_seq: u64,
    database_id: &str,
    previous: &ChatContents,
) -> Result<ChatDraft> {
    ensure!(
        item.is_terminal(),
        "cannot publish a nonterminal timeline item"
    );
    let descriptor = descriptor::item_descriptor(item)?;
    let mut bodies = if let Some(plan) = plan_completion(item)? {
        let mut bodies = BTreeMap::new();
        if let Some(document) = plan.document {
            bodies.insert(
                BodyKey::host(PLAN_DOCUMENT_FIELD),
                ContentBlock::from_text(&document),
            );
        }
        if let Some(feedback) = plan.feedback {
            bodies.insert(
                BodyKey::host(PLAN_FEEDBACK_FIELD),
                ContentBlock::from_text(&feedback),
            );
        }
        bodies
    } else {
        content_fields(item.state())?
    };
    freeze(
        item,
        CompletionStamp {
            id: &item.id,
            source_effect_seq,
            sealed_at: item.updated_at,
        },
        database_id,
        serde_json::to_value(descriptor)?,
        &mut bodies,
        previous,
        None,
    )
}

pub(crate) fn background_started_draft(
    item: &ThreadItem,
    task_id: &str,
    receipt: &str,
    source_effect_seq: u64,
    started_at: i64,
    database_id: &str,
) -> Result<ChatDraft> {
    let ThreadItemState::Tool(tool) = item.state() else {
        anyhow::bail!("background acknowledgement has no tool invocation");
    };
    let invocation = tool.invocation();
    let id = crate::studio::thread_projection::order::tool_background_started_id(
        invocation.tool_call_id(),
    );
    let value = serde_json::json!({"kind":"tool", "data":{
        "invocation": { "toolCallId": invocation.tool_call_id(), "callId": invocation.call_id(),
            "providerItemId": invocation.provider_item_id(), "name": invocation.name(),
            "workingDirectory": invocation.working_directory(), "taskId": task_id,
            "presentationContract":invocation.presentation_contract() },
        "state": { "kind":"backgroundStarted", "startedAt": started_at },
        "userInput": null, "wait": null
    }});
    let mut bodies = BTreeMap::from([
        (
            BodyKey::host(TOOL_ARGUMENTS_FIELD),
            ContentBlock::from_text(invocation.arguments()),
        ),
        (
            BodyKey::host(TOOL_RESULT_FIELD),
            ContentBlock::from_text(receipt),
        ),
    ]);
    freeze(
        item,
        CompletionStamp {
            id: &id,
            source_effect_seq,
            sealed_at: started_at,
        },
        database_id,
        value,
        &mut bodies,
        &ChatContents::new(),
        None,
    )
}

struct CompletionStamp<'a> {
    id: &'a str,
    source_effect_seq: u64,
    sealed_at: i64,
}

pub(in crate::studio) struct ObservationStamp<'a> {
    pub thread_id: &'a str,
    pub database_id: &'a str,
    pub owner: &'a ContentOwner,
    pub boundary: pl_protocol::ChatFactPosition,
    pub captured_at: i64,
}

pub(in crate::studio) fn validate_observation(
    state: &ThreadItemState,
    atom: &pl_protocol::ChatAtom,
    thread_id: &str,
) -> Result<()> {
    ensure!(
        matches!(
            atom.lifecycle,
            pl_protocol::ChatAtomLifecycle::Active { .. }
        ) && atom.completion_item_id.is_none()
            && atom.finished_at.is_none(),
        "observation is not an active execution cut"
    );
    serde_json::to_value(descriptor::observation_descriptor(state, thread_id)?)?;
    Ok(())
}

pub(in crate::studio) fn observation_payload(
    state: &ThreadItemState,
    atom: &pl_protocol::ChatAtom,
    contents: &[Arc<ChatContent>],
    stamp: ObservationStamp<'_>,
) -> Result<Vec<u8>> {
    validate_observation(state, atom, stamp.thread_id)?;
    ensure!(
        !stamp.database_id.is_empty(),
        "observation requires its database identity"
    );
    ensure!(
        matches!(stamp.owner, ContentOwner::DisplayObservation { block_id, member_key }
            if !block_id.is_empty() && !member_key.is_empty()),
        "observation requires its assigned display namespace"
    );
    let owner_key = crate::studio::conversation_identity::content_owner_key(stamp.owner)?;
    let mut bodies = Vec::with_capacity(atom.contents.len());
    for body in &atom.contents {
        let ContentTarget::Body { owner, key } = &body.reference.target else {
            anyhow::bail!("observation body has no display owner");
        };
        ensure!(
            owner == stamp.owner && body.reference.database_id == stamp.database_id,
            "observation body escaped its display namespace"
        );
        let content = contents
            .iter()
            .find(|content| {
                content.descriptor.key.owner == owner_key && content.descriptor.key.key == *key
            })
            .ok_or_else(|| anyhow::anyhow!("observation lost its owned content"))?;
        // Observations always expose their sealed namespace, even for short bodies.
        bodies.push(body_envelope(
            content,
            stamp.database_id,
            stamp.owner,
            false,
        )?);
    }
    let descriptor =
        serde_json::to_value(descriptor::observation_descriptor(state, stamp.thread_id)?)?;
    let mut envelope = payload_envelope(state, descriptor, bodies, stamp.boundary.effect_seq)?;
    envelope["capturedAt"] = stamp.captured_at.into();
    if let Some(turn_id) = &atom.turn_id {
        envelope["turnId"] = turn_id.clone().into();
    }
    Ok(serde_json::to_vec(&envelope)?)
}

fn body_envelope(
    content: &ChatContent,
    database_id: &str,
    owner: &ContentOwner,
    allow_inline: bool,
) -> Result<serde_json::Value> {
    let mut body = serde_json::json!({
        "key":content.descriptor.key.key, "byteLength":content.descriptor.byte_length
    });
    if allow_inline && content.data.len() <= INLINE_BODY_BYTES {
        body["inline"] =
            serde_json::to_value(content.data.range(0, content.data.len())?.as_bytes())?;
    } else {
        body["reference"] = serde_json::to_value(ContentRef {
            database_id: database_id.into(),
            target: ContentTarget::Body {
                owner: owner.clone(),
                key: content.descriptor.key.key.clone(),
            },
        })?;
    }
    Ok(body)
}

fn payload_envelope(
    state: &ThreadItemState,
    descriptor: serde_json::Value,
    bodies: Vec<serde_json::Value>,
    source_effect_seq: u64,
) -> Result<serde_json::Value> {
    let kind = descriptor
        .get("kind")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("descriptor has no kind"))?;
    let mut data = descriptor
        .get("data")
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("descriptor has no data"))?;
    if let ThreadItemState::Tool(tool) = state
        && let Some(invocation) = data
            .get_mut("invocation")
            .and_then(serde_json::Value::as_object_mut)
    {
        invocation.insert(
            "presentationContract".into(),
            serde_json::to_value(tool.invocation().presentation_contract())?,
        );
    }
    Ok(serde_json::json!({"contract":"anywork.chat/1", "type":kind,
        "data":data, "sourceEffectSeq":source_effect_seq, "bodies":bodies}))
}

fn freeze(
    item: &ThreadItem,
    stamp: CompletionStamp<'_>,
    database_id: &str,
    descriptor: serde_json::Value,
    bodies: &mut BTreeMap<BodyKey, Arc<ContentBlock>>,
    previous: &ChatContents,
    metadata: Option<pl_protocol::ChatAtom>,
) -> Result<ChatDraft> {
    let CompletionStamp {
        id,
        source_effect_seq,
        sealed_at,
    } = stamp;
    ensure!(
        !database_id.is_empty(),
        "completion requires its database identity"
    );
    let parent_id = (!item.turn_id.is_empty())
        .then(|| ChatKey::new("turn", &item.turn_id))
        .transpose()?;
    let owner = ContentOwner::Item {
        item_id: id.to_owned(),
    };
    let owner_key = crate::studio::conversation_identity::content_owner_key(&owner)?;
    let mut contents = ChatContents::new();
    let mut body_envelopes = Vec::with_capacity(bodies.len());
    for (position, block) in bodies.iter() {
        let key = position.as_key();
        let byte_length = block.len() as u64;
        // Index once at ownership handoff. Large bodies never flatten to encode the envelope.
        let content_key = ChatContentKey {
            owner: owner_key.clone(),
            key: key.clone(),
        };
        let old = previous.get(&content_key);
        let mut generation = old.map_or(1, |content| content.descriptor.generation);
        let mut body_block = block.clone();
        let shared = old.filter(|content| {
            matches!(&content.data, ContentData::Text(text) if ContentBlock::text_eq(text.block(), block))
        });
        if let Some(old) = old.filter(|_| shared.is_none()) {
            let candidate = ContentData::text(block.clone());
            let old_bytes = old.data.len();
            let prefix_matches = old_bytes <= block.len()
                && (0..old_bytes).step_by(4096).all(|offset| {
                    old.data
                        .range(offset as u64, 4096.min(old_bytes - offset))
                        .ok()
                        .zip(
                            candidate
                                .range(offset as u64, 4096.min(old_bytes - offset))
                                .ok(),
                        )
                        .is_some_and(|(left, right)| left.as_bytes() == right.as_bytes())
                });
            if prefix_matches {
                if let ContentData::Text(text) = &old.data
                    && let Some(suffix) = block.suffix_since(old_bytes)
                {
                    body_block = ContentBlock::append(text.block(), &suffix);
                }
            } else {
                generation = generation
                    .checked_add(1)
                    .ok_or_else(|| anyhow::anyhow!("content generation exhausted"))?;
            }
        }
        let content = shared.cloned().unwrap_or_else(|| {
            Arc::new(ChatContent {
                descriptor: ContentDescriptor {
                    key: content_key,
                    byte_length,
                    generation,
                    media_type: Some("text/plain; charset=utf-8".into()),
                },
                data: ContentData::text(body_block),
            })
        });
        let body = body_envelope(&content, database_id, &owner, true)?;
        contents.insert(content.descriptor.key.clone(), content);
        body_envelopes.push(body);
    }
    let mut envelope =
        payload_envelope(item.state(), descriptor, body_envelopes, source_effect_seq)?;
    envelope["sealedAt"] = sealed_at.into();
    if !item.turn_id.is_empty() {
        envelope["turnId"] = item.turn_id.clone().into();
    }
    let kind = envelope["type"]
        .as_str()
        .expect("payload kind was validated");
    let mut atom = metadata.unwrap_or_else(|| atom(item));
    if let ThreadItemState::Text(text) = item.state() {
        atom.content_present = Some(
            bodies.iter().any(|(key, block)| {
                atom_content_role(key) == Some(pl_protocol::ChatContentRole::Body)
                    && !block.is_empty()
            }) || !text.attachments().is_empty(),
        );
    }
    // Frozen completions (including background handoff receipts) carry the original
    // typed tool payload, never a duplicate of the active wait presentation.
    atom.wait = None;
    if kind == "plan" {
        atom.kind = pl_protocol::ChatAtomKind::Plan;
    }
    atom.completion_item_id = Some(id.into());
    if id != item.id {
        atom.delivery = pl_protocol::ChatDeliveryKind::BackgroundHandoff;
        atom.lifecycle = pl_protocol::ChatAtomLifecycle::Terminal {
            started: None,
            ended: None,
            outcome: pl_protocol::ChatTerminalOutcome::Transferred,
        };
    }
    atom.contents = bodies
        .keys()
        .filter_map(|key| {
            Some(pl_protocol::ChatAtomContent {
                role: atom_content_role(key)?,
                reference: ContentRef {
                    database_id: database_id.into(),
                    target: ContentTarget::Body {
                        owner: owner.clone(),
                        key: key.as_key(),
                    },
                },
            })
        })
        .collect();
    Ok(ChatDraft {
        item_id: id.into(),
        query_class: "conversation".into(),
        read_hint: native_read_hint_v1("conversation", &atom),
        parent_id,
        metadata: serde_json::to_vec(&atom)?.into(),
        payload: Arc::from(serde_json::to_vec(&envelope)?),
        contents: Arc::new(contents),
    })
}

/// 动态正文域：只由条目自己的动态事实派生，正文块与生产者共享。
///
/// 超出 u32 的位置/数量返回 Overloaded；问答关联缺失明确失败，不静默丢弃答案。
pub(crate) fn content_fields(
    state: &ThreadItemState,
) -> Result<BTreeMap<BodyKey, Arc<ContentBlock>>> {
    validate_counts(state)?;
    let mut fields = BTreeMap::new();
    match state {
        ThreadItemState::Text(text) => {
            fields.insert(BodyKey::Body, ContentBlock::from_text(text.text()));
        }
        ThreadItemState::Thinking(thinking) => {
            for (index, chunk) in thinking.summary().iter().enumerate() {
                fields.insert(
                    BodyKey::Part(PresentationPart::SummaryText(count(index)?)),
                    ContentBlock::from_text(chunk),
                );
            }
            for (index, chunk) in thinking.content().iter().enumerate() {
                fields.insert(
                    BodyKey::Part(PresentationPart::ReasoningText(count(index)?)),
                    ContentBlock::from_text(chunk),
                );
            }
        }
        ThreadItemState::Tool(tool) => {
            fields.insert(
                BodyKey::host(TOOL_ARGUMENTS_FIELD),
                ContentBlock::from_text(tool.invocation().arguments()),
            );
            if let Some(output) = streamed_output(tool.state()) {
                fields.insert(
                    BodyKey::host(TOOL_RESULT_FIELD),
                    ContentBlock::from_text(output),
                );
            }
            // A terminal tool result and its open artifacts are dynamic bodies too: they are user
            // visible, can be large, and must share the same bounded preview instead of staying in
            // the static metadata where no budget could ever reach them.
            if let Some(output) = tool.terminal_output() {
                fields.insert(
                    BodyKey::host(TOOL_RESULT_FIELD),
                    ContentBlock::from_text(output.result()),
                );
                if !output.output_artifacts().is_empty() {
                    // Encoding through the value's own `Display` cannot fail; the open payload is
                    // only serialized again at the canonical/detail boundary.
                    let encoded =
                        serde_json::Value::Array(output.output_artifacts().to_vec()).to_string();
                    fields.insert(
                        BodyKey::host(TOOL_OUTPUT_ARTIFACTS_FIELD),
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
        ThreadItemState::Raw(raw) => {
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

/// 同一条目的**结构 / 终态形状**：动态正文被清空，kind、附件、生命周期与工具状态如实保留。
///
/// 仅用于宿主投影的内容版本比较：工具状态转移（Running→Succeeded 等）与执行终态
/// （streaming→completed/failed/cancelled）都是载荷变化，必须递增内容版本，否则旧的保存回执
/// 会张冠李戴地确认新载荷。读取 DTO 和内存 meta 不消费这里的空正文结构。
///
/// 它**不含** `ThreadItem` 上会随每次投影变化的易变时间戳（`created_at`/`updated_at`），因此同一条目
/// 重复投影不会无意义地抬高内容版本；但生命周期自带的 `completed_at`/`failed_at` 属于真实转移，保留。
pub(crate) fn static_state(state: &ThreadItemState) -> ThreadItemState {
    match state {
        ThreadItemState::Text(text) => ThreadItemState::Text(ThreadTextItem::new(
            text.channel(),
            String::new(),
            text.attachments().to_vec(),
            text.lifecycle().clone(),
        )),
        ThreadItemState::Thinking(thinking) => ThreadItemState::Thinking(ThreadThinkingItem::new(
            Vec::new(),
            Vec::new(),
            thinking.lifecycle().clone(),
        )),
        ThreadItemState::Tool(tool) => ThreadItemState::Tool(
            ThreadToolItem::new(
                clear_arguments(tool.invocation()),
                clear_terminal_output(&clear_streamed_output(tool.state())),
            )
            .with_user_input(tool.user_input().map(clear_user_input))
            .with_wait(tool.wait().cloned()),
        ),
        ThreadItemState::Raw(raw) => ThreadItemState::Raw(ThreadRawItem {
            origin: raw.origin,
            payloads: raw
                .payloads
                .iter()
                .map(|payload| ThreadRawPayload {
                    format: payload.format.clone(),
                    version: payload.version,
                    content: String::new(),
                })
                .collect(),
            notice: raw.notice.clone(),
            recorded_at: raw.recorded_at,
        }),
        other => other.clone(),
    }
}

/// 一个问题标题的内容域身份。
pub(crate) fn user_input_header_field(question_index: usize) -> BodyKey {
    BodyKey::host(format!(
        "{TOOL_USER_INPUT_FIELD}question.{question_index}.header"
    ))
}

/// 一个原问题正文的内容域身份：索引是它在原问题顺序里的位置。
pub(crate) fn user_input_question_field(question_index: usize) -> BodyKey {
    BodyKey::host(format!(
        "{TOOL_USER_INPUT_FIELD}question.{question_index}.body"
    ))
}

/// 一个问题选项标签的内容域身份。
pub(crate) fn user_input_option_label_field(question_index: usize, option_index: usize) -> BodyKey {
    BodyKey::host(format!(
        "{TOOL_USER_INPUT_FIELD}question.{question_index}.option.{option_index}.label"
    ))
}

/// 一个问题选项说明的内容域身份。
pub(crate) fn user_input_option_description_field(
    question_index: usize,
    option_index: usize,
) -> BodyKey {
    BodyKey::host(format!(
        "{TOOL_USER_INPUT_FIELD}question.{question_index}.option.{option_index}.description"
    ))
}

/// 一个已接受答案值的内容域身份：问题位置 + 该问题答案列表内的序号。
pub(crate) fn user_input_answer_field(question_index: usize, answer_index: usize) -> BodyKey {
    BodyKey::host(format!(
        "{TOOL_USER_INPUT_FIELD}answer.{question_index}.{answer_index}"
    ))
}

/// 一个问题里所有可展示正文与其内容域身份，按固定顺序列出。
fn user_input_question_fields(
    question_index: usize,
    question: &UserQuestion,
) -> Vec<(BodyKey, &str)> {
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

/// 一个已作答问题在原问题顺序里的位置。
///
/// 回答以 question ID 关联问题，投影边界保证每个回答都指向一个真实问题；结构本身仍按位置寻址，
/// 因此一段正文在 `content_fields` 与完成读取两侧落到同一个域上。
fn question_position(user_input: &ThreadToolUserInput, question_id: &str) -> Option<usize> {
    user_input
        .questions()
        .iter()
        .position(|question| question.id == question_id)
}

/// 静态结构里的问答：所有正文清空，结构、顺序、ID 与脱敏状态如实保留。
fn clear_user_input(user_input: &ThreadToolUserInput) -> ThreadToolUserInput {
    let cleared = ThreadToolUserInput::new(
        user_input.interaction_id().to_owned(),
        user_input
            .questions()
            .iter()
            .map(|question| UserQuestion {
                header: String::new(),
                question: String::new(),
                options: question.options.as_ref().map(|options| {
                    options
                        .iter()
                        .map(|_| pl_protocol::UserQuestionOption {
                            label: String::new(),
                            description: String::new(),
                        })
                        .collect()
                }),
                ..question.clone()
            })
            .collect(),
        match user_input.state() {
            ThreadToolUserInputState::Pending => ThreadToolUserInputState::Pending,
            ThreadToolUserInputState::Cancelled => ThreadToolUserInputState::Cancelled,
            ThreadToolUserInputState::Resolved(resolved) => {
                ThreadToolUserInputState::Resolved(ResolvedThreadToolUserInput::new(
                    resolved
                        .answers()
                        .iter()
                        .map(|answer| {
                            if answer.is_redacted() {
                                ThreadToolUserInputAnswer::redacted(answer.question_id().to_owned())
                            } else {
                                ThreadToolUserInputAnswer::new(
                                    answer.question_id().to_owned(),
                                    vec![String::new(); answer.answers().len()],
                                )
                            }
                        })
                        .collect(),
                ))
            }
        },
    );
    match user_input.plan_document() {
        Some(identity) => cleared.with_plan_document(identity.clone()),
        None => cleared,
    }
}

fn streamed_output(state: &ThreadToolState) -> Option<&str> {
    match state {
        ThreadToolState::Running(running) => Some(running.streamed_output()),
        ThreadToolState::Cancelling(cancelling) => Some(cancelling.streamed_output()),
        _ => None,
    }
}

/// 原始记录一段正文的内容域身份。
fn raw_payload_field(payload_index: usize) -> BodyKey {
    BodyKey::host(format!("{RAW_PAYLOAD_FIELD}{payload_index}"))
}

/// 只有正文被清空的终态工具输出，其余结构（附件、退出码、失败原因）保持不变。
fn clear_terminal_output(state: &ThreadToolState) -> ThreadToolState {
    match state {
        ThreadToolState::Succeeded(succeeded) => {
            ThreadToolState::Succeeded(pl_protocol::SucceededThreadTool::new(
                succeeded.completed_at(),
                cleared_output(succeeded.output()),
            ))
        }
        ThreadToolState::Failed(failed) => {
            ThreadToolState::Failed(pl_protocol::FailedThreadTool::new(
                failed.failed_at(),
                failed.failure().clone(),
                failed.output().map(cleared_output),
            ))
        }
        other => other.clone(),
    }
}

fn cleared_output(output: &pl_protocol::ThreadToolOutput) -> pl_protocol::ThreadToolOutput {
    pl_protocol::ThreadToolOutput::new(
        String::new(),
        output.attachments().to_vec(),
        Vec::new(),
        output.exit_code(),
    )
}

fn clear_streamed_output(state: &ThreadToolState) -> ThreadToolState {
    match state {
        ThreadToolState::Running(_) => {
            ThreadToolState::Running(pl_protocol::RunningThreadTool::new(String::new()))
        }
        ThreadToolState::Cancelling(_) => {
            ThreadToolState::Cancelling(pl_protocol::CancellingThreadTool::new(String::new()))
        }
        other => other.clone(),
    }
}

/// 只用于 static_state 的结构判等，保留 task/call 关联；不用于读取或内存 meta 编码。
fn clear_arguments(invocation: &ThreadToolInvocation) -> ThreadToolInvocation {
    let rebuilt = ThreadToolInvocation::new(
        invocation.tool_call_id().to_owned(),
        invocation.name().to_owned(),
        String::new(),
    )
    .with_provider_identity(
        invocation.call_id().map(str::to_owned),
        invocation.provider_item_id().map(str::to_owned),
    )
    .with_working_directory(invocation.working_directory().map(str::to_owned))
    .with_presentation_contract(invocation.presentation_contract().map(str::to_owned));
    match invocation.task_id() {
        Some(task_id) => rebuilt.with_task_id(task_id.to_owned()),
        None => rebuilt,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::{ThreadContentLifecycle, ThreadTextChannel};

    #[test]
    fn completion_rejects_active_text_thinking_and_tool_with_shared_observation_codec() {
        use pl_protocol::*;
        for state in [
            ThreadItemState::Text(ThreadTextItem::new(
                ThreadTextChannel::Final,
                "active".into(),
                vec![],
                ThreadContentLifecycle::streaming(),
            )),
            ThreadItemState::Thinking(ThreadThinkingItem::new(
                vec![],
                vec![],
                ThreadContentLifecycle::streaming(),
            )),
            ThreadItemState::Tool(ThreadToolItem::new(
                ThreadToolInvocation::new("call".into(), "exec".into(), "{}".into()),
                ThreadToolState::Running(RunningThreadTool::new(String::new())),
            )),
        ] {
            let item = ThreadItem::new(
                "active".into(),
                "thread".into(),
                "turn".into(),
                1,
                1,
                10,
                11,
                state,
            );
            assert!(completion_draft(&item, 1, "database").is_err());
        }
    }

    #[test]
    fn observation_tool_descriptors_keep_all_nonterminal_phases_without_completion() -> Result<()> {
        use pl_protocol::*;
        for (kind, state) in [
            ("queued", ThreadToolState::Queued(QueuedThreadTool)),
            ("started", ThreadToolState::Started(StartedThreadTool)),
            ("streaming", ThreadToolState::Streaming(StreamingThreadTool)),
            (
                "awaitingApproval",
                ThreadToolState::AwaitingApproval(AwaitingApprovalThreadTool),
            ),
            ("approved", ThreadToolState::Approved(ApprovedThreadTool)),
            (
                "running",
                ThreadToolState::Running(RunningThreadTool::new(String::new())),
            ),
        ] {
            let state = ThreadItemState::Tool(ThreadToolItem::new(
                ThreadToolInvocation::new("call".into(), "exec".into(), String::new()),
                state,
            ));
            let encoded =
                serde_json::to_value(descriptor::observation_descriptor(&state, "thread")?)?;
            assert_eq!(encoded["data"]["state"]["kind"], kind);
            let item = ThreadItem::new(
                "active".into(),
                "thread".into(),
                "turn".into(),
                1,
                1,
                10,
                11,
                state,
            );
            assert!(completion_draft(&item, 1, "database").is_err());
        }
        Ok(())
    }

    #[test]
    fn active_wait_is_typed_without_payload_and_completion_keeps_only_original_wait() -> Result<()>
    {
        use pl_protocol::*;
        let waiting = ThreadWaitPresentation::new(
            ThreadWaitIntent::Events {
                targets: vec![ThreadWaitTarget::new(
                    "task:timer".into(),
                    None,
                    None,
                    Some(ThreadWaitTargetStatus::Running),
                )],
                timeout_ms: 30_000,
            },
            ThreadWaitState::Waiting,
            None,
        );
        let tool_item = |state, wait| {
            ThreadItem::new(
                "tool:4:call".into(),
                "thread".into(),
                "turn".into(),
                7,
                1,
                10,
                11,
                ThreadItemState::Tool(
                    ThreadToolItem::new(
                        ThreadToolInvocation::new("call".into(), "wait".into(), "{}".into()),
                        state,
                    )
                    .with_wait(wait),
                ),
            )
        };
        let active = tool_item(
            ThreadToolState::Running(RunningThreadTool::new(String::new())),
            Some(waiting.clone()),
        );
        let live = atom(&active);
        assert_eq!(live.id, active.id);
        assert_eq!(live.tool.as_ref().unwrap().call_id, "call");
        assert_eq!(live.wait, Some(waiting.clone()));
        assert!(matches!(live.lifecycle, ChatAtomLifecycle::Active { .. }));
        assert!(live.payload.is_none());
        assert!(live.contents.is_empty());
        assert_eq!(
            serde_json::from_slice::<ChatAtom>(&serde_json::to_vec(&live)?)?,
            live
        );
        // Tool names and generic running state do not manufacture typed Waiting.
        assert!(
            atom(&tool_item(
                ThreadToolState::Running(RunningThreadTool::new(String::new())),
                None,
            ))
            .wait
            .is_none()
        );
        assert!(atom(&text("not-a-tool", String::new())).wait.is_none());

        let handoff = background_started_draft(&active, "task", "accepted", 3, 12, "database")?;
        let handoff_atom: ChatAtom = serde_json::from_slice(&handoff.metadata)?;
        assert!(handoff_atom.wait.is_none());
        assert!(
            serde_json::from_slice::<serde_json::Value>(&handoff.metadata)?
                .get("wait")
                .is_none()
        );

        let ready = ThreadWaitPresentation::new(
            waiting.intent().clone(),
            ThreadWaitState::Ready,
            Some(true),
        );
        let terminal = tool_item(
            ThreadToolState::Succeeded(SucceededThreadTool::new(
                12,
                ThreadToolOutput::new("ready".into(), Vec::new(), Vec::new(), None),
            )),
            Some(ready.clone()),
        );
        assert!(atom(&terminal).wait.is_none());
        let draft = completion_draft(&terminal, 4, "database")?;
        let metadata: serde_json::Value = serde_json::from_slice(&draft.metadata)?;
        assert!(metadata.get("wait").is_none());
        let decoded: ChatAtom = serde_json::from_value(metadata)?;
        assert!(
            decoded.wait.is_none(),
            "old metadata without wait must decode"
        );
        let payload: serde_json::Value = serde_json::from_slice(&draft.payload)?;
        assert_eq!(payload["data"]["wait"], serde_json::to_value(ready)?);
        Ok(())
    }

    #[test]
    fn interaction_calls_enter_status_before_user_input_and_keep_identity_through_resolution()
    -> Result<()> {
        use pl_protocol::*;

        for (name, kind, question_id) in [
            ("request_user_input", ChatAtomKind::Interaction, "question"),
            (
                crate::plan_tool::TOOL_PLAN_SUBMIT,
                ChatAtomKind::Plan,
                AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID,
            ),
        ] {
            let input = |state| {
                ThreadToolUserInput::new(
                    "interaction".into(),
                    vec![UserQuestion {
                        id: question_id.into(),
                        header: "Confirmation".into(),
                        question: "Continue with this proposal?".into(),
                        is_other: true,
                        is_secret: false,
                        options: None,
                    }],
                    state,
                )
            };
            let tool_item = |state, user_input| {
                ThreadItem::new(
                    "tool:4:call".into(),
                    "thread".into(),
                    "turn".into(),
                    7,
                    1,
                    10,
                    11,
                    ThreadItemState::Tool(
                        ThreadToolItem::new(
                            ThreadToolInvocation::new("call".into(), name.into(), "{}".into()),
                            state,
                        )
                        .with_user_input(user_input),
                    ),
                )
            };
            for (resolution, terminal_state, outcome) in [
                (
                    ThreadToolUserInputState::Resolved(ResolvedThreadToolUserInput::new(vec![
                        ThreadToolUserInputAnswer::new(question_id.into(), vec!["Approve".into()]),
                    ])),
                    ThreadToolState::Succeeded(SucceededThreadTool::new(
                        12,
                        ThreadToolOutput::new("answered".into(), Vec::new(), Vec::new(), None),
                    )),
                    ChatTerminalOutcome::Completed,
                ),
                (
                    ThreadToolUserInputState::Cancelled,
                    ThreadToolState::Interrupted(InterruptedThreadTool::new(
                        12,
                        "cancelled".into(),
                    )),
                    ChatTerminalOutcome::Cancelled,
                ),
            ] {
                let initial = tool_item(
                    ThreadToolState::Running(RunningThreadTool::new(String::new())),
                    None,
                );
                assert!(initial.tool().unwrap().user_input().is_none());
                assert!(initial.tool().unwrap().wait().is_none());
                let first_atom = atom(&initial);
                assert!(first_atom.payload.is_none());
                assert!(first_atom.contents.is_empty());
                assert!(first_atom.completion_item_id.is_none());
                assert!(first_atom.completion_seq.is_none());

                let pending = tool_item(
                    ThreadToolState::Running(RunningThreadTool::new(String::new())),
                    Some(input(ThreadToolUserInputState::Pending)),
                );
                let decided = tool_item(
                    ThreadToolState::Running(RunningThreadTool::new(String::new())),
                    Some(input(resolution.clone())),
                );
                let terminal = tool_item(terminal_state, Some(input(resolution)));
                for (item, expected_outcome) in [
                    (initial, None),
                    (pending, None),
                    (decided, None),
                    (terminal, Some(outcome)),
                ] {
                    let projected_atom = if expected_outcome.is_some() {
                        serde_json::from_slice::<ChatAtom>(
                            &completion_draft(&item, 4, "database")?.metadata,
                        )?
                    } else {
                        atom(&item)
                    };
                    assert_eq!(projected_atom.id, first_atom.id);
                    assert_eq!(projected_atom.source, first_atom.source);
                    assert_eq!(projected_atom.tool, first_atom.tool);
                    assert_eq!(projected_atom.kind, kind);
                    assert!(projected_atom.wait.is_none());
                    match expected_outcome {
                        None => assert!(matches!(
                            projected_atom.lifecycle,
                            ChatAtomLifecycle::Active {
                                status: ChatActiveStatus::Running,
                                ..
                            }
                        )),
                        Some(expected) => assert!(matches!(
                            projected_atom.lifecycle,
                            ChatAtomLifecycle::Terminal { outcome, .. } if outcome == expected
                        )),
                    }
                    if expected_outcome.is_some() {
                        let class = native_read_class_v1("conversation", &projected_atom);
                        assert_eq!(class.hint, pl_core::chat::ChatReadHint::Single);
                        assert_eq!(class.main_presentation, MainPresentation::Single);
                    }
                }
            }
        }
        Ok(())
    }

    fn text(id: &str, body: String) -> ThreadItem {
        ThreadItem::new(
            id.into(),
            "thread".into(),
            "turn:a:b".into(),
            1,
            1,
            10,
            11,
            ThreadItemState::Text(ThreadTextItem::new(
                ThreadTextChannel::Final,
                body,
                Vec::new(),
                ThreadContentLifecycle::completed(11),
            )),
        )
    }

    #[test]
    fn completion_freezes_opaque_payload_and_explicit_large_body_without_embedding_full_text()
    -> Result<()> {
        let body = "汉📖".repeat(4000);
        let item = text("text", body.clone());
        let draft = completion_draft(&item, 7, "database")?;
        let envelope: serde_json::Value = serde_json::from_slice(&draft.payload)?;
        assert_eq!(envelope["contract"], "anywork.chat/1");
        assert_eq!(envelope["type"], "text");
        assert_eq!(envelope["sourceEffectSeq"], 7);
        assert_eq!(envelope["sealedAt"], 11);
        assert_eq!(envelope["turnId"], "turn:a:b");
        assert_eq!(envelope["bodies"][0]["byteLength"], body.len() as u64);
        assert!(envelope["bodies"][0].get("inline").is_none());
        assert_eq!(draft.query_class, "conversation");
        let atom: pl_protocol::ChatAtom = serde_json::from_slice(&draft.metadata)?;
        assert_eq!(atom.id, item.id);
        assert_eq!(atom.completion_item_id.as_deref(), Some(item.id.as_str()));
        assert_eq!(atom.completion_seq, None);
        assert_eq!(atom.source_state, None);
        assert!(
            serde_json::from_slice::<serde_json::Value>(&draft.metadata)?
                .get("sourceState")
                .is_none()
        );
        assert_eq!(atom.payload, None);
        assert_eq!(
            atom.source,
            pl_protocol::ChatSourceId::ForegroundTurn {
                turn_id: "turn:a:b".into()
            }
        );
        assert_eq!(atom.contents.len(), 1);
        assert_eq!(draft.parent_id, Some(ChatKey::new("turn", "turn:a:b")?));
        assert!(draft.payload.len() < 2048);
        let reference: ContentRef =
            serde_json::from_value(envelope["bodies"][0]["reference"].clone())?;
        assert_eq!(
            reference,
            ContentRef {
                database_id: "database".into(),
                target: ContentTarget::Body {
                    owner: ContentOwner::Item {
                        item_id: "text".into()
                    },
                    key: "body".into()
                },
            }
        );
        let key = ChatContentKey {
            owner: crate::studio::conversation_identity::content_owner_key(&ContentOwner::Item {
                item_id: "text".into(),
            })?,
            key: "body".into(),
        };
        let content = &draft.contents[&key];
        assert_eq!(content.descriptor.byte_length, body.len() as u64);
        assert_eq!(
            content.data.range((body.len() - 7) as u64, 7)?.as_bytes(),
            "汉📖".as_bytes()
        );
        assert_eq!(completion_draft(&item, 7, "database")?, draft);
        Ok(())
    }

    #[test]
    fn background_handoff_keeps_member_identity_and_the_distinct_receipt_content_owner()
    -> Result<()> {
        let item = ThreadItem::new(
            "tool:4:call".into(),
            "thread".into(),
            "turn".into(),
            7,
            1,
            10,
            11,
            ThreadItemState::Tool(ThreadToolItem::new(
                ThreadToolInvocation::new("call".into(), "arbitrary".into(), "{}".into()),
                ThreadToolState::Running(pl_protocol::RunningThreadTool::new(String::new())),
            )),
        );
        let draft = background_started_draft(&item, "task", "accepted", 3, 12, "database")?;
        let atom: pl_protocol::ChatAtom = serde_json::from_slice(&draft.metadata)?;
        assert_eq!(atom.id, item.id);
        assert_ne!(draft.item_id, atom.id);
        assert_eq!(
            atom.completion_item_id.as_deref(),
            Some(draft.item_id.as_str())
        );
        assert_eq!(
            atom.delivery,
            pl_protocol::ChatDeliveryKind::BackgroundHandoff
        );
        assert_eq!(atom.source_state, None);
        assert!(
            serde_json::from_slice::<serde_json::Value>(&draft.metadata)?
                .get("sourceState")
                .is_none()
        );
        assert!(matches!(
            atom.lifecycle,
            pl_protocol::ChatAtomLifecycle::Terminal {
                outcome: pl_protocol::ChatTerminalOutcome::Transferred,
                ..
            }
        ));
        for content in &atom.contents {
            assert!(matches!(&content.reference.target, ContentTarget::Body {
            owner: ContentOwner::Item { item_id }, ..
        } if item_id == &draft.item_id));
        }
        assert_eq!(atom.contents.len(), 2);
        Ok(())
    }

    #[test]
    fn short_body_boundary_is_exact_and_retains_the_manifest() -> Result<()> {
        for len in [0, 4096, 4097] {
            let draft = completion_draft(&text("short", "x".repeat(len)), 3, "database")?;
            let envelope: serde_json::Value = serde_json::from_slice(&draft.payload)?;
            let body = &envelope["bodies"][0];
            assert_eq!(body.get("inline").is_some(), len <= 4096);
            assert_eq!(body.get("reference").is_some(), len > 4096);
            assert_eq!(draft.contents.len(), 1);
            if len <= 4096 {
                assert_eq!(
                    serde_json::from_value::<Vec<u8>>(body["inline"].clone())?,
                    vec![b'x'; len]
                );
            }
        }
        assert!(completion_draft(&text("missing-db", "body".into()), 1, "").is_err());
        Ok(())
    }

    #[test]
    fn tool_contract_is_frozen_from_the_real_invocation_not_its_name() -> Result<()> {
        for contract in [None, Some("opaque-tool@7")] {
            let invocation =
                ThreadToolInvocation::new("call".into(), "same-name".into(), "{}".into())
                    .with_presentation_contract(contract.map(str::to_owned));
            let item = ThreadItem::new(
                "tool".into(),
                "thread".into(),
                "turn".into(),
                1,
                1,
                10,
                11,
                ThreadItemState::Tool(ThreadToolItem::new(
                    invocation,
                    ThreadToolState::Succeeded(pl_protocol::SucceededThreadTool::new(
                        11,
                        pl_protocol::ThreadToolOutput::new(
                            "result".into(),
                            Vec::new(),
                            Vec::new(),
                            None,
                        ),
                    )),
                )),
            );
            let draft = completion_draft(&item, 3, "database")?;
            assert_eq!(draft.query_class, "conversation");
            let envelope: serde_json::Value = serde_json::from_slice(&draft.payload)?;
            assert_eq!(
                envelope["data"]["invocation"]["presentationContract"],
                serde_json::to_value(contract)?
            );
            assert_eq!(draft.contents.len(), 2);
            let ThreadItemState::Tool(shape) = static_state(item.state()) else {
                panic!("tool shape");
            };
            assert_eq!(shape.invocation().presentation_contract(), contract);
        }
        Ok(())
    }

    #[test]
    fn frozen_text_presence_uses_owned_blocks_not_the_static_shell_or_payload_json() -> Result<()> {
        use anyhow::Context;
        use pl_protocol::{AttachmentModality, ChatAtom, ThreadAttachment};
        for (body, expected) in [("accepted", true), ("", false), (" \n\t", true)] {
            let original = text("presence", body.into());
            let shell = original.clone().with_state(static_state(original.state()));
            assert!(shell.text().context("text")?.text().is_empty());
            assert_eq!(
                atom(&shell).content_present,
                None,
                "a stripped shell claimed emptiness"
            );
            let mut blocks = BTreeMap::from([(BodyKey::Body, ContentBlock::from_text(body))]);
            let draft = freeze(
                &shell,
                CompletionStamp {
                    id: &shell.id,
                    source_effect_seq: 1,
                    sealed_at: 11,
                },
                "database",
                serde_json::to_value(descriptor::item_descriptor(&shell)?)?,
                &mut blocks,
                &ChatContents::new(),
                None,
            )?;
            let metadata: ChatAtom = serde_json::from_slice(&draft.metadata)?;
            assert_eq!(metadata.content_present, Some(expected));
        }
        let image = ThreadAttachment {
            id: "image".into(),
            modality: AttachmentModality::Image,
            media_type: "image/png".into(),
            filename: None,
            width: None,
            height: None,
            byte_size: 1,
        };
        let item = text("image-only", String::new()).with_state(ThreadItemState::Text(
            ThreadTextItem::new(
                ThreadTextChannel::Final,
                String::new(),
                vec![image],
                ThreadContentLifecycle::completed(11),
            ),
        ));
        let metadata: ChatAtom =
            serde_json::from_slice(&completion_draft(&item, 1, "database")?.metadata)?;
        assert_eq!(metadata.content_present, Some(true));
        Ok(())
    }
}
