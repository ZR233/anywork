//! 唯一的产品元数据编码：头部与不含流式正文的描述，不接受旧 ThreadItem 内存外壳。

use anyhow::Result;
use pl_core::chat::{ChatError, ChatItem};
use pl_protocol::{
    ThreadItem, ThreadItemState, ThreadToolOutput, ThreadToolState, ThreadToolUserInput,
    ThreadToolUserInputState, TimelineAnswerDescriptor, TimelineDescriptor, TimelineItemHeader,
    TimelineQuestionDescriptor, TimelineRawDescriptor, TimelineRawPayloadDescriptor,
    TimelineTextDescriptor, TimelineThinkingDescriptor, TimelineToolDescriptor,
    TimelineToolInvocation, TimelineToolOutputDescriptor, TimelineToolState,
    TimelineUserInputDescriptor, TimelineUserInputState,
};
use serde::{Deserialize, Serialize};

use crate::thread_assembler::encode_interaction_key;

/// 只在当前进程内使用，不是存储格式；core 将其视为 opaque bytes。
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct TimelineMeta {
    pub header: TimelineItemHeader,
    pub descriptor: TimelineDescriptor,
}

impl TimelineMeta {
    pub(crate) fn from_item(item: &ThreadItem) -> Result<Self> {
        validate_counts(item.state())?;
        Ok(Self {
            header: TimelineItemHeader {
                id: item.id.clone(),
                thread_id: item.thread_id.clone(),
                turn_id: item.turn_id.clone(),
                ordinal: item.ordinal,
                created_at: item.created_at,
                updated_at: item.updated_at,
            },
            descriptor: descriptor(item.state(), &item.thread_id)?,
        })
    }

    pub(crate) fn decode(bytes: &[u8]) -> Result<Self, ChatError> {
        // serde 的 typed 解码错误保留为 History source；不回退为旧内存编码或 raw JSON。
        serde_json::from_slice(bytes).map_err(|error| ChatError::History(Box::new(error)))
    }

    pub(crate) fn for_item(item: &ChatItem) -> Result<Self> {
        let meta = Self::decode(&item.meta)?;
        if meta.header.id != item.item_id
            || meta.header.ordinal != item.order
            || meta.header.turn_id != item.turn_id
        {
            return Err(ChatError::Conflict(
                "timeline metadata identity does not match item".into(),
            )
            .into());
        }
        Ok(meta)
    }
}

pub(crate) fn count(value: usize) -> Result<u32> {
    u32::try_from(value)
        .map_err(|_| ChatError::Overloaded("timeline field count exceeds u32".into()).into())
}

/// 所有带位置的字段都必须能由 wire 的 u32 无损寻址。
/// 同时验证问答关联，避免一个未关联答案在拆分时被静默丢弃。
pub(crate) fn validate_counts(state: &ThreadItemState) -> Result<()> {
    match state {
        ThreadItemState::Thinking(thinking) => {
            count(thinking.summary().len())?;
            count(thinking.content().len())?;
        }
        ThreadItemState::Raw(raw) => {
            count(raw.payloads.len())?;
        }
        ThreadItemState::Tool(tool) => {
            if let Some(input) = tool.user_input() {
                count(input.questions().len())?;
                for question in input.questions() {
                    if let Some(options) = &question.options {
                        count(options.len())?;
                    }
                }
                for answer in input.answers() {
                    count(answer.answers().len())?;
                    if !input
                        .questions()
                        .iter()
                        .any(|question| question.id == answer.question_id())
                    {
                        return Err(ChatError::Conflict(
                            "timeline answer has no matching question".into(),
                        )
                        .into());
                    }
                }
            }
        }
        _ => {}
    }
    Ok(())
}

fn descriptor(state: &ThreadItemState, thread_id: &str) -> Result<TimelineDescriptor> {
    Ok(match state {
        ThreadItemState::Text(text) => TimelineDescriptor::Text(TimelineTextDescriptor {
            channel: text.channel(),
            attachments: text.attachments().to_vec(),
            lifecycle: text.lifecycle().clone(),
        }),
        ThreadItemState::Thinking(thinking) => {
            TimelineDescriptor::Thinking(TimelineThinkingDescriptor {
                lifecycle: thinking.lifecycle().clone(),
            })
        }
        ThreadItemState::Raw(raw) => TimelineDescriptor::Raw(TimelineRawDescriptor {
            origin: raw.origin,
            payloads: raw
                .payloads
                .iter()
                .map(|payload| TimelineRawPayloadDescriptor {
                    format: payload.format.clone(),
                    version: payload.version,
                })
                .collect(),
            notice: raw.notice.clone(),
            recorded_at: raw.recorded_at,
        }),
        ThreadItemState::Tool(tool) => {
            let invocation = tool.invocation();
            TimelineDescriptor::Tool(TimelineToolDescriptor {
                invocation: TimelineToolInvocation {
                    tool_call_id: invocation.tool_call_id().to_owned(),
                    call_id: invocation.call_id().map(str::to_owned),
                    provider_item_id: invocation.provider_item_id().map(str::to_owned),
                    name: invocation.name().to_owned(),
                    working_directory: invocation.working_directory().map(str::to_owned),
                    task_id: invocation.task_id().map(str::to_owned),
                },
                state: tool_state(tool.state()),
                user_input: tool
                    .user_input()
                    .map(|input| user_input(input, thread_id))
                    .transpose()?,
                wait: tool.wait().cloned().map(Box::new),
            })
        }
        ThreadItemState::Agent(value) => TimelineDescriptor::Agent(value.clone()),
        ThreadItemState::Turn(value) => TimelineDescriptor::Turn(value.clone()),
        ThreadItemState::Inference(value) => TimelineDescriptor::Inference(value.clone()),
        ThreadItemState::Skill(value) => TimelineDescriptor::Skill(value.clone()),
        ThreadItemState::File(value) => TimelineDescriptor::File(value.clone()),
        ThreadItemState::ContextCompaction(value) => {
            TimelineDescriptor::ContextCompaction(value.clone())
        }
    })
}

fn tool_state(state: &ThreadToolState) -> TimelineToolState {
    match state {
        ThreadToolState::Queued(_) => TimelineToolState::Queued,
        ThreadToolState::Cancelling(_) => TimelineToolState::Cancelling,
        ThreadToolState::Started(_) => TimelineToolState::Started,
        ThreadToolState::Streaming(_) => TimelineToolState::Streaming,
        ThreadToolState::AwaitingApproval(_) => TimelineToolState::AwaitingApproval,
        ThreadToolState::Approved(_) => TimelineToolState::Approved,
        ThreadToolState::Running(_) => TimelineToolState::Running,
        ThreadToolState::Interrupted(value) => TimelineToolState::Interrupted {
            interrupted_at: value.interrupted_at(),
            reason: value.reason().to_owned(),
        },
        ThreadToolState::Succeeded(value) => TimelineToolState::Succeeded {
            completed_at: value.completed_at(),
            output: output(value.output()),
        },
        ThreadToolState::Failed(value) => TimelineToolState::Failed {
            failed_at: value.failed_at(),
            failure: value.failure().clone(),
            output: value.output().map(output),
        },
        ThreadToolState::Denied(value) => TimelineToolState::Denied {
            denied_at: value.denied_at(),
            reason: value.reason().to_owned(),
        },
        ThreadToolState::Cancelled(value) => TimelineToolState::Cancelled {
            cancelled_at: value.cancelled_at(),
            reason: value.reason().to_owned(),
        },
    }
}

fn output(value: &ThreadToolOutput) -> TimelineToolOutputDescriptor {
    TimelineToolOutputDescriptor {
        attachments: value.attachments().to_vec(),
        exit_code: value.exit_code(),
    }
}

fn user_input(input: &ThreadToolUserInput, thread_id: &str) -> Result<TimelineUserInputDescriptor> {
    Ok(TimelineUserInputDescriptor {
        interaction_id: encode_interaction_key(thread_id, input.interaction_id()),
        questions: input
            .questions()
            .iter()
            .map(|question| {
                Ok(TimelineQuestionDescriptor {
                    id: question.id.clone(),
                    is_other: question.is_other,
                    is_secret: question.is_secret,
                    option_count: question
                        .options
                        .as_ref()
                        .map(|options| count(options.len()))
                        .transpose()?,
                })
            })
            .collect::<Result<_>>()?,
        state: match input.state() {
            ThreadToolUserInputState::Pending => TimelineUserInputState::Pending,
            ThreadToolUserInputState::Cancelled => TimelineUserInputState::Cancelled,
            ThreadToolUserInputState::Resolved(resolved) => TimelineUserInputState::Resolved {
                answers: resolved
                    .answers()
                    .iter()
                    .map(|answer| {
                        Ok(TimelineAnswerDescriptor {
                            question_id: answer.question_id().to_owned(),
                            answer_count: count(answer.answers().len())?,
                            redacted: answer.is_redacted(),
                        })
                    })
                    .collect::<Result<_>>()?,
            },
        },
    })
}
