//! 业务恢复按明确身份读取当前规范原件；不解码旧 history_items 或展示索引。
use super::payload::{TurnOutcome, UserInputState};
use super::{
    TOOL_ARGUMENTS_FIELD, TOOL_OUTPUT_ARTIFACTS_FIELD, TOOL_RESULT_FIELD, payload::*,
    user_input_answer_field, user_input_header_field, user_input_option_description_field,
    user_input_option_label_field, user_input_question_field,
};
use crate::{ExecutionItem, ExecutionShape};
use anyhow::{Context, Result, ensure};
use pl_core::chat::ChatItem;
use pl_protocol::*;

fn body(record: &ChatItem, key: &str) -> Result<String> {
    let value = record
        .contents
        .values()
        .find(|content| content.descriptor.key.key == key)
        .with_context(|| {
            format!(
                "canonical content {}:{key} is missing",
                record.header.item_id
            )
        })?;
    let mut bytes = Vec::with_capacity(value.data.len());
    let mut offset = 0;
    while offset < value.data.len() {
        let window = value.data.range(offset as u64, 32 * 1024)?;
        ensure!(
            !window.as_bytes().is_empty(),
            "canonical content read did not advance"
        );
        bytes.extend_from_slice(window.as_bytes());
        offset += window.as_bytes().len();
    }
    Ok(String::from_utf8(bytes)?)
}

fn output(record: &ChatItem, value: ToolOutputDescriptor) -> Result<ThreadToolOutput> {
    let artifacts = if record
        .contents
        .values()
        .any(|c| c.descriptor.key.key == TOOL_OUTPUT_ARTIFACTS_FIELD)
    {
        serde_json::from_str(&body(record, TOOL_OUTPUT_ARTIFACTS_FIELD)?)?
    } else {
        Vec::new()
    };
    Ok(ThreadToolOutput::new(
        body(record, TOOL_RESULT_FIELD)?,
        value.attachments,
        artifacts,
        value.exit_code,
    ))
}

fn tool(
    record: &ChatItem,
    value: ToolDescriptor,
    data: &serde_json::Value,
) -> Result<ThreadToolItem> {
    let call = value.invocation;
    let mut invocation = ThreadToolInvocation::new(
        call.tool_call_id,
        call.name,
        body(record, TOOL_ARGUMENTS_FIELD)?,
    )
    .with_provider_identity(call.call_id, call.provider_item_id)
    .with_working_directory(call.working_directory)
    .with_presentation_contract(
        data.pointer("/invocation/presentationContract")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned),
    );
    if let Some(task) = call.task_id {
        invocation = invocation.with_task_id(task);
    }
    let state = match value.state {
        ToolState::Succeeded {
            completed_at,
            output: value,
        } => ThreadToolState::Succeeded(SucceededThreadTool::new(
            completed_at,
            output(record, value)?,
        )),
        ToolState::Failed {
            failed_at,
            failure,
            output: value,
        } => ThreadToolState::Failed(FailedThreadTool::new(
            failed_at,
            failure,
            value.map(|v| output(record, v)).transpose()?,
        )),
        ToolState::Interrupted {
            interrupted_at,
            reason,
        } => ThreadToolState::Interrupted(InterruptedThreadTool::new(interrupted_at, reason)),
        ToolState::Denied { denied_at, reason } => {
            ThreadToolState::Denied(DeniedThreadTool::new(denied_at, reason))
        }
        ToolState::Cancelled {
            cancelled_at,
            reason,
        } => ThreadToolState::Cancelled(CancelledThreadTool::new(cancelled_at, reason)),
        _ => anyhow::bail!("completed tool has a nonterminal descriptor"),
    };
    let user_input = value
        .user_input
        .map(|input| -> Result<ThreadToolUserInput> {
            let mut questions = Vec::with_capacity(input.questions.len());
            for (position, question) in input.questions.into_iter().enumerate() {
                let text = body(record, &user_input_question_field(position).as_key())?;
                let header = body(record, &user_input_header_field(position).as_key())?;
                let options = question
                    .option_count
                    .map(|count| {
                        (0..count)
                            .map(|index| -> Result<UserQuestionOption> {
                                Ok(UserQuestionOption {
                                    label: body(
                                        record,
                                        &user_input_option_label_field(position, index as usize)
                                            .as_key(),
                                    )?,
                                    description: body(
                                        record,
                                        &user_input_option_description_field(
                                            position,
                                            index as usize,
                                        )
                                        .as_key(),
                                    )?,
                                })
                            })
                            .collect::<Result<Vec<_>>>()
                    })
                    .transpose()?;
                questions.push(UserQuestion {
                    id: question.id,
                    header,
                    question: text,
                    options,
                    is_other: question.is_other,
                    is_secret: question.is_secret,
                });
            }
            let state = match input.state {
                UserInputState::Cancelled => ThreadToolUserInputState::Cancelled,
                UserInputState::Resolved { answers } => {
                    let mut restored = Vec::with_capacity(answers.len());
                    for answer in answers {
                        let position = questions
                            .iter()
                            .position(|question| question.id == answer.question_id)
                            .context("canonical answer has no question")?;
                        let values = if answer.redacted {
                            Vec::new()
                        } else {
                            (0..answer.answer_count)
                                .map(|index| {
                                    body(
                                        record,
                                        &user_input_answer_field(position, index as usize).as_key(),
                                    )
                                })
                                .collect::<Result<Vec<_>>>()?
                        };
                        restored.push(if answer.redacted {
                            ThreadToolUserInputAnswer::redacted(answer.question_id)
                        } else {
                            ThreadToolUserInputAnswer::new(answer.question_id, values)
                        });
                    }
                    ThreadToolUserInputState::Resolved(ResolvedThreadToolUserInput::new(restored))
                }
            };
            Ok(ThreadToolUserInput::new(
                input.interaction_id,
                questions,
                state,
            ))
        })
        .transpose()?;
    Ok(ThreadToolItem::new(invocation, state)
        .with_user_input(user_input)
        .with_wait(value.wait.map(|v| *v)))
}

fn content_outcome(value: ContentOutcome) -> ThreadContentLifecycle {
    match value {
        ContentOutcome::Streaming(value) => ThreadContentLifecycle::Streaming(value),
        ContentOutcome::Completed(value) => ThreadContentLifecycle::Completed(value),
        ContentOutcome::Failed(value) => ThreadContentLifecycle::Failed(value),
        ContentOutcome::Cancelled(value) => ThreadContentLifecycle::Cancelled(value),
    }
}

pub(in crate::studio) fn execution_state(record: &ChatItem) -> Result<ExecutionShape> {
    let atom: ChatAtom = serde_json::from_slice(&record.header.metadata)?;
    ensure!(
        atom.completion_item_id.as_deref() == Some(record.header.item_id.as_str())
            && matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }),
        "canonical execution envelope identity conflict"
    );
    let envelope: serde_json::Value = serde_json::from_slice(&record.payload)?;
    ensure!(
        envelope["contract"] == "anywork.chat/1",
        "unsupported canonical execution payload contract"
    );
    let data = &envelope["data"];
    let descriptor: ItemDescriptor =
        serde_json::from_value(serde_json::json!({"kind": envelope["type"], "data":data}))?;
    Ok(match descriptor {
        ItemDescriptor::Text(value) => ExecutionShape::Text(ThreadTextItem::new(
            value.channel,
            body(record, "body")?,
            value.attachments,
            content_outcome(value.outcome),
        )),
        ItemDescriptor::Thinking(value) => {
            let parts = |prefix: &str| -> Result<Vec<String>> {
                let mut keys = record
                    .contents
                    .values()
                    .filter_map(|c| {
                        let index = c
                            .descriptor
                            .key
                            .key
                            .strip_prefix(prefix)?
                            .parse::<u32>()
                            .ok()?;
                        Some((index, c.descriptor.key.key.clone()))
                    })
                    .collect::<Vec<_>>();
                keys.sort_by_key(|(index, _)| *index);
                keys.into_iter()
                    .map(|(_, key)| body(record, &key))
                    .collect()
            };
            ExecutionShape::Thinking(ThreadThinkingItem::new(
                parts("part.reasoningText.")?,
                parts("part.summaryText.")?,
                content_outcome(value.outcome),
            ))
        }
        ItemDescriptor::Tool(value) => ExecutionShape::Tool(tool(record, value, data)?),
        ItemDescriptor::Turn(value) => {
            let state = match value.outcome {
                TurnOutcome::Queued(value) => TurnState::Queued(value),
                TurnOutcome::Running(value) => TurnState::Running(value),
                TurnOutcome::Completed(value) => TurnState::Completed(value),
                TurnOutcome::Failed(value) => TurnState::Failed(value),
                TurnOutcome::Cancelled(value) => TurnState::Cancelled(value),
                TurnOutcome::BudgetLimited(value) => TurnState::BudgetLimited(value),
            };
            ExecutionShape::Turn(ThreadTurnItem::new(state).with_input_id(value.input_id))
        }
        _ => anyhow::bail!(
            "canonical record {} has no execution restoration consumer",
            record.header.item_id
        ),
    })
}

pub(in crate::studio) fn execution_item(
    record: &ChatItem,
    thread_id: &str,
    placement: Option<(u64, u64)>,
) -> Result<ExecutionItem> {
    let atom: ChatAtom = serde_json::from_slice(&record.header.metadata)?;
    let envelope: serde_json::Value = serde_json::from_slice(&record.payload)?;
    let state = execution_state(record)?;
    let ordinal = placement
        .map(|value| value.0)
        .or(atom.source_order)
        .context("canonical execution order is unknown")?;
    let revision = envelope["sourceEffectSeq"]
        .as_u64()
        .or(placement.map(|value| value.1))
        .context("canonical completion effect is unknown")?;
    // 已发布旧原件可能没有统一时间字段；typed 正文自身的终态时间仍是原始证据。
    let terminal = match &state {
        ExecutionShape::Text(value) => value.lifecycle().terminal_at(),
        ExecutionShape::Thinking(value) => value.lifecycle().terminal_at(),
        ExecutionShape::Tool(value) => value.state().terminal_at(),
        _ => None,
    };
    let updated = atom
        .finished_at
        .or(terminal)
        .context("canonical completion time is unknown")?;
    // 这里只是局部转换值的创建时间；不补写或宣称 lifecycle 的未知开始时间。
    let created = atom.started_at.unwrap_or(updated);
    Ok(ExecutionItem::new(
        atom.id,
        thread_id.into(),
        atom.turn_id.unwrap_or_default(),
        ordinal,
        revision,
        created,
        updated,
        state,
    ))
}
