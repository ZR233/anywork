//! 可靠保存与必要权威边界的反向映射；读取 DTO 不经过这里。

use anyhow::Result;
use pl_core::chat::{ChatError, ChatField, ChatItem, PresentationPart};
use pl_protocol::{
    ApprovedThreadTool, AwaitingApprovalThreadTool, CancelledThreadTool, CancellingThreadTool,
    DeniedThreadTool, FailedThreadTool, InterruptedThreadTool, QueuedThreadTool,
    ResolvedThreadToolUserInput, RunningThreadTool, StartedThreadTool, StreamingThreadTool,
    SucceededThreadTool, ThreadItemState, ThreadRawItem, ThreadRawPayload, ThreadTextItem,
    ThreadThinkingItem, ThreadToolInvocation, ThreadToolItem, ThreadToolOutput, ThreadToolState,
    ThreadToolUserInput, ThreadToolUserInputAnswer, ThreadToolUserInputState, TimelineDescriptor,
    TimelineToolDescriptor, TimelineToolOutputDescriptor, TimelineToolState,
    TimelineUserInputDescriptor, TimelineUserInputState, UserQuestion, UserQuestionOption,
};

use super::super::chat_item::{
    RAW_PAYLOAD_FIELD, TOOL_ARGUMENTS_FIELD, TOOL_OUTPUT_ARTIFACTS_FIELD, TOOL_RESULT_FIELD,
    user_input_answer_field, user_input_header_field, user_input_option_description_field,
    user_input_option_label_field, user_input_question_field,
};
use crate::thread_assembler::decode_interaction_key;

pub(crate) fn state(
    descriptor: &TimelineDescriptor,
    item: &ChatItem,
    expected_thread_id: &str,
) -> Result<ThreadItemState> {
    if item
        .field_previews()
        .any(|(_, preview)| !preview.is_complete())
    {
        return Err(invalid(
            "canonical reconstruction requires complete content fields",
        ));
    }
    Ok(match descriptor {
        TimelineDescriptor::Text(text) => ThreadItemState::Text(ThreadTextItem::new(
            text.channel,
            text_body(item)?,
            text.attachments.clone(),
            text.lifecycle.clone(),
        )),
        TimelineDescriptor::Thinking(thinking) => {
            ThreadItemState::Thinking(ThreadThinkingItem::new(
                chunks(item, true)?,
                chunks(item, false)?,
                thinking.lifecycle.clone(),
            ))
        }
        TimelineDescriptor::Raw(raw) => ThreadItemState::Raw(ThreadRawItem {
            origin: raw.origin,
            payloads: raw
                .payloads
                .iter()
                .enumerate()
                .map(|(index, payload)| {
                    Ok(ThreadRawPayload {
                        format: payload.format.clone(),
                        version: payload.version,
                        content: text(
                            item,
                            &ChatField::host(format!("{RAW_PAYLOAD_FIELD}{index}")),
                        )?,
                    })
                })
                .collect::<Result<_>>()?,
            notice: raw.notice.clone(),
            recorded_at: raw.recorded_at,
        }),
        TimelineDescriptor::Tool(tool) => {
            ThreadItemState::Tool(restore_tool(tool, item, expected_thread_id)?)
        }
        TimelineDescriptor::Agent(value) => ThreadItemState::Agent(value.clone()),
        TimelineDescriptor::Turn(value) => ThreadItemState::Turn(value.clone()),
        TimelineDescriptor::Inference(value) => ThreadItemState::Inference(value.clone()),
        TimelineDescriptor::Skill(value) => ThreadItemState::Skill(value.clone()),
        TimelineDescriptor::File(value) => ThreadItemState::File(value.clone()),
        TimelineDescriptor::ContextCompaction(value) => {
            ThreadItemState::ContextCompaction(value.clone())
        }
    })
}

fn restore_tool(
    tool: &TimelineToolDescriptor,
    item: &ChatItem,
    expected_thread_id: &str,
) -> Result<ThreadToolItem> {
    let invocation = &tool.invocation;
    let mut restored = ThreadToolInvocation::new(
        invocation.tool_call_id.clone(),
        invocation.name.clone(),
        text(item, &ChatField::host(TOOL_ARGUMENTS_FIELD))?,
    )
    .with_provider_identity(
        invocation.call_id.clone(),
        invocation.provider_item_id.clone(),
    )
    .with_working_directory(invocation.working_directory.clone());
    if let Some(task_id) = &invocation.task_id {
        restored = restored.with_task_id(task_id.clone());
    }
    let state = match &tool.state {
        TimelineToolState::Queued => ThreadToolState::Queued(QueuedThreadTool),
        TimelineToolState::Cancelling => ThreadToolState::Cancelling(CancellingThreadTool::new(
            text(item, &ChatField::host(TOOL_RESULT_FIELD))?,
        )),
        TimelineToolState::Started => ThreadToolState::Started(StartedThreadTool),
        TimelineToolState::Streaming => ThreadToolState::Streaming(StreamingThreadTool),
        TimelineToolState::AwaitingApproval => {
            ThreadToolState::AwaitingApproval(AwaitingApprovalThreadTool)
        }
        TimelineToolState::Approved => ThreadToolState::Approved(ApprovedThreadTool),
        TimelineToolState::Running => ThreadToolState::Running(RunningThreadTool::new(text(
            item,
            &ChatField::host(TOOL_RESULT_FIELD),
        )?)),
        TimelineToolState::Interrupted {
            interrupted_at,
            reason,
        } => ThreadToolState::Interrupted(InterruptedThreadTool::new(
            *interrupted_at,
            reason.clone(),
        )),
        TimelineToolState::Succeeded {
            completed_at,
            output,
        } => ThreadToolState::Succeeded(SucceededThreadTool::new(
            *completed_at,
            restore_output(output, item)?,
        )),
        TimelineToolState::Failed {
            failed_at,
            failure,
            output,
        } => ThreadToolState::Failed(FailedThreadTool::new(
            *failed_at,
            failure.clone(),
            output
                .as_ref()
                .map(|output| restore_output(output, item))
                .transpose()?,
        )),
        TimelineToolState::Denied { denied_at, reason } => {
            ThreadToolState::Denied(DeniedThreadTool::new(*denied_at, reason.clone()))
        }
        TimelineToolState::Cancelled {
            cancelled_at,
            reason,
        } => ThreadToolState::Cancelled(CancelledThreadTool::new(*cancelled_at, reason.clone())),
    };
    Ok(ThreadToolItem::new(restored, state)
        .with_user_input(
            tool.user_input
                .as_ref()
                .map(|input| restore_input(input, item, expected_thread_id))
                .transpose()?,
        )
        .with_wait(tool.wait.as_deref().cloned()))
}

fn restore_output(
    output: &TimelineToolOutputDescriptor,
    item: &ChatItem,
) -> Result<ThreadToolOutput> {
    let artifacts = item
        .field(&ChatField::host(TOOL_OUTPUT_ARTIFACTS_FIELD))
        .map(|block| {
            serde_json::from_str(&block.text()).map_err(|error| ChatError::History(Box::new(error)))
        })
        .transpose()?
        .unwrap_or_default();
    Ok(ThreadToolOutput::new(
        text(item, &ChatField::host(TOOL_RESULT_FIELD))?,
        output.attachments.clone(),
        artifacts,
        output.exit_code,
    ))
}

fn restore_input(
    input: &TimelineUserInputDescriptor,
    item: &ChatItem,
    expected_thread_id: &str,
) -> Result<ThreadToolUserInput> {
    let (thread_id, local_id) = decode_interaction_key(&input.interaction_id)
        .map_err(|_| invalid("timeline user-input interaction identity is malformed"))?;
    if thread_id != expected_thread_id {
        return Err(invalid(
            "timeline user-input interaction belongs to another Thread",
        ));
    }
    let questions = input
        .questions
        .iter()
        .enumerate()
        .map(|(position, question)| {
            Ok(UserQuestion {
                id: question.id.clone(),
                is_other: question.is_other,
                is_secret: question.is_secret,
                header: text(item, &user_input_header_field(position))?,
                question: text(item, &user_input_question_field(position))?,
                options: question
                    .option_count
                    .map(|count| {
                        (0..count)
                            .map(|option| {
                                Ok(UserQuestionOption {
                                    label: text(
                                        item,
                                        &user_input_option_label_field(position, option as usize),
                                    )?,
                                    description: text(
                                        item,
                                        &user_input_option_description_field(
                                            position,
                                            option as usize,
                                        ),
                                    )?,
                                })
                            })
                            .collect::<Result<_>>()
                    })
                    .transpose()?,
            })
        })
        .collect::<Result<_>>()?;
    let state = match &input.state {
        TimelineUserInputState::Pending => ThreadToolUserInputState::Pending,
        TimelineUserInputState::Cancelled => ThreadToolUserInputState::Cancelled,
        TimelineUserInputState::Resolved { answers } => {
            ThreadToolUserInputState::Resolved(ResolvedThreadToolUserInput::new(
                answers
                    .iter()
                    .map(|answer| {
                        // 脱敏标记直接还原，绝不尝试回读敏感字段或私有 receipt。
                        if answer.redacted {
                            return Ok(ThreadToolUserInputAnswer::redacted(
                                answer.question_id.clone(),
                            ));
                        }
                        let position = input
                            .questions
                            .iter()
                            .position(|question| question.id == answer.question_id)
                            .ok_or_else(|| invalid("timeline answer has no matching question"))?;
                        Ok(ThreadToolUserInputAnswer::new(
                            answer.question_id.clone(),
                            (0..answer.answer_count)
                                .map(|index| {
                                    text(item, &user_input_answer_field(position, index as usize))
                                })
                                .collect::<Result<_>>()?,
                        ))
                    })
                    .collect::<Result<_>>()?,
            ))
        }
    };
    Ok(ThreadToolUserInput::new(
        local_id.to_owned(),
        questions,
        state,
    ))
}

fn text(item: &ChatItem, field: &ChatField) -> Result<String> {
    item.field(field)
        .map(|block| block.text())
        .ok_or_else(|| invalid("canonical content field is missing"))
}

fn text_body(item: &ChatItem) -> Result<String> {
    if item.field(&ChatField::Body).is_some() {
        return text(item, &ChatField::Body);
    }
    // 活动 provider 的单段文本使用自己的 Part 身份，必要权威边界保留该段原文。
    let mut parts = item
        .field_previews()
        .filter_map(|(field, preview)| match field {
            ChatField::Part(PresentationPart::OutputText(_)) => Some(preview.block.text()),
            _ => None,
        });
    let body = parts
        .next()
        .ok_or_else(|| invalid("canonical text field is missing"))?;
    if parts.next().is_some() {
        return Err(invalid("canonical text item has multiple primary fields"));
    }
    Ok(body)
}

fn chunks(item: &ChatItem, summary: bool) -> Result<Vec<String>> {
    let indexed: Vec<_> = item
        .field_previews()
        .filter_map(|(field, preview)| match (summary, field) {
            (true, ChatField::Part(PresentationPart::SummaryText(index)))
            | (false, ChatField::Part(PresentationPart::ReasoningText(index))) => {
                Some((*index as usize, preview))
            }
            _ => None,
        })
        .collect();
    let len = indexed
        .iter()
        .map(|(index, _)| *index)
        .max()
        .map(|index| {
            index
                .checked_add(1)
                .ok_or_else(|| ChatError::Overloaded("thinking chunk index exceeds usize".into()))
        })
        .transpose()?
        .unwrap_or(0);
    // 可靠回填不套用展示预算；按 provider 段位置补空，无法分配时明确失败而不截断原结构。
    let mut chunks = Vec::new();
    chunks.try_reserve_exact(len).map_err(|_| {
        ChatError::Overloaded("thinking chunk structure cannot be allocated".into())
    })?;
    chunks.resize_with(len, String::new);
    for (index, preview) in indexed {
        chunks[index] = preview.block.text();
    }
    Ok(chunks)
}

fn invalid(message: &str) -> anyhow::Error {
    ChatError::History(Box::new(std::io::Error::new(
        std::io::ErrorKind::InvalidData,
        message,
    )))
    .into()
}
