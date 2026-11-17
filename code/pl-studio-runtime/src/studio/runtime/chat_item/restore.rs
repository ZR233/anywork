//! 业务恢复按明确身份读取当前规范原件；不解码旧 history_items 或展示索引。
use super::payload::{TurnOutcome, UserInputState};
use super::{
    TOOL_ARGUMENTS_FIELD, TOOL_OUTPUT_ARTIFACTS_FIELD, TOOL_RESULT_FIELD, payload::*,
    user_input_answer_field, user_input_header_field, user_input_option_description_field,
    user_input_option_label_field, user_input_question_field,
};
use crate::protocol::*;
use crate::ExecutionShape;
use crate::{UserQuestion, UserQuestionOption};
use anyhow::{Context, Result, ensure};
use pl_core::chat::ChatItem;

pub(super) trait BodySource {
    fn body(&self, key: &str) -> Result<String>;
    fn keys(&self) -> impl Iterator<Item = &str>;
    fn contains(&self, key: &str) -> bool {
        self.keys().any(|candidate| candidate == key)
    }
}
impl BodySource for ChatItem {
    fn body(&self, key: &str) -> Result<String> {
        let value = self
            .contents
            .values()
            .find(|content| content.descriptor.key.key == key)
            .with_context(|| {
                format!("canonical content {}:{key} is missing", self.header.item_id)
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

    fn keys(&self) -> impl Iterator<Item = &str> {
        self.contents
            .values()
            .map(|c| c.descriptor.key.key.as_str())
    }
}
impl BodySource for std::collections::BTreeMap<String, String> {
    fn body(&self, key: &str) -> Result<String> {
        self.get(key)
            .cloned()
            .with_context(|| format!("canonical body {key} is missing"))
    }
    fn keys(&self) -> impl Iterator<Item = &str> {
        self.keys().map(String::as_str)
    }
}
fn body(record: &impl BodySource, key: &str) -> Result<String> {
    record.body(key)
}

fn output(record: &impl BodySource, value: ToolOutputDescriptor) -> Result<ThreadToolOutput> {
    let artifacts = if record.contains(TOOL_OUTPUT_ARTIFACTS_FIELD) {
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
    thread_id: &str,
    record: &impl BodySource,
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
            let (owner, interaction) =
                crate::thread_assembler::decode_interaction_key(&input.interaction_id)?;
            ensure!(
                owner == thread_id,
                "canonical interaction belongs to another Thread"
            );
            Ok(ThreadToolUserInput::new(
                interaction.into(),
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

pub(super) fn decode_state(
    record: &impl BodySource,
    atom: &ChatAtom,
    envelope: &serde_json::Value,
    thread_id: &str,
) -> Result<ExecutionShape> {
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
                    .keys()
                    .filter_map(|key| {
                        let index = key.strip_prefix(prefix)?.parse::<u32>().ok()?;
                        Some((index, key.to_owned()))
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
        ItemDescriptor::Tool(value) => ExecutionShape::Tool(tool(thread_id, record, value, data)?),
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
            atom.id
        ),
    })
}
