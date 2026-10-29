//! 唯一的产品元数据编码：头部与不含流式正文的描述，不接受旧 ThreadItem 内存外壳。

use anyhow::Result;
use pl_core::chat::{ChatError, ChatItem};
use pl_protocol::{
    AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, ThreadAgentState, ThreadContentLifecycle,
    ThreadInferenceState, ThreadItem, ThreadItemState, ThreadToolOutput, ThreadToolState,
    ThreadToolUserInput, ThreadToolUserInputState, TimelineAgentDescriptor, TimelineAgentOutcome,
    TimelineAnswerDescriptor, TimelineContentOutcome, TimelineDescriptor,
    TimelineInferenceDescriptor, TimelineInferenceOutcome, TimelineItemHeader,
    TimelinePlanDecision, TimelinePlanDescriptor, TimelineQuestionDescriptor,
    TimelineRawDescriptor, TimelineRawPayloadDescriptor, TimelineTextDescriptor,
    TimelineThinkingDescriptor, TimelineToolDescriptor, TimelineToolInvocation,
    TimelineToolOutputDescriptor, TimelineToolState, TimelineTurnDescriptor, TimelineTurnOutcome,
    TimelineUserInputDescriptor, TimelineUserInputState, TurnState, UserInputAnswer,
    UserInputResolution,
};
use serde::{Deserialize, Serialize};

use crate::plan_tool::{
    TOOL_PLAN_SUBMIT,
    state::{AgentSessionPlanConfirmationDecision, confirmation_decision},
};
use crate::thread_assembler::encode_interaction_key;

pub(crate) const PLAN_DOCUMENT_FIELD: &str = "plan.document";
pub(crate) const PLAN_FEEDBACK_FIELD: &str = "plan.feedback";

/// Frozen Plan facts shared by metadata and the completion field codec.
pub(crate) struct PlanCompletion {
    pub descriptor: TimelinePlanDescriptor,
    pub document: Option<String>,
    pub feedback: Option<String>,
}

/// Extract only facts belonging to this completed interaction, never the current Plan.
pub(crate) fn plan_completion(item: &ThreadItem) -> Result<Option<PlanCompletion>> {
    let ThreadItemState::Tool(tool) = item.state() else {
        return Ok(None);
    };
    if tool.invocation().name() != TOOL_PLAN_SUBMIT {
        return Ok(None);
    }
    let Some(input) = tool.user_input() else {
        return Ok(None);
    };
    if matches!(input.state(), ThreadToolUserInputState::Pending) {
        return Err(nonterminal());
    }
    if !tool.state().is_terminal() {
        return Err(nonterminal());
    }
    let mut questions = input
        .questions()
        .iter()
        .filter(|q| q.id == AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID);
    let question = questions.next();
    if questions.next().is_some() {
        return Err(ChatError::Conflict("duplicate plan confirmation question".into()).into());
    }
    let document = question
        .filter(|q| !q.is_secret)
        .map(|q| q.question.clone());
    let identity = input.plan_document();
    if let (Some(document), Some(identity)) = (&document, identity)
        && pl_core::context::content_hash(document.as_bytes()) != identity.content_hash
    {
        return Err(
            ChatError::Conflict("plan document hash does not match confirmation".into()).into(),
        );
    }
    let (decision, feedback) = match input.state() {
        ThreadToolUserInputState::Cancelled => (TimelinePlanDecision::Cancelled, None),
        ThreadToolUserInputState::Resolved(resolved) => {
            let answers: Vec<_> = resolved
                .answers()
                .iter()
                .filter(|a| a.question_id() == AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID)
                .collect();
            let decision = if question.is_some_and(|q| !q.is_secret)
                && answers.len() == 1
                && !answers[0].is_redacted()
            {
                let answer = answers[0];
                let resolution = UserInputResolution {
                    answers: [(
                        answer.question_id().to_owned(),
                        UserInputAnswer {
                            answers: answer.answers().to_vec(),
                        },
                    )]
                    .into_iter()
                    .collect(),
                };
                confirmation_decision(&resolution).ok()
            } else {
                None
            };
            match decision {
                Some(AgentSessionPlanConfirmationDecision::Approve) => {
                    (TimelinePlanDecision::Approved, None)
                }
                Some(AgentSessionPlanConfirmationDecision::RequestRevision { feedback }) => (
                    TimelinePlanDecision::RevisionRequested,
                    (!feedback.is_empty()).then_some(feedback),
                ),
                None => (TimelinePlanDecision::Resolved, None),
            }
        }
        ThreadToolUserInputState::Pending => unreachable!(),
    };
    Ok(Some(PlanCompletion {
        descriptor: TimelinePlanDescriptor {
            interaction_id: encode_interaction_key(&item.thread_id, input.interaction_id()),
            document_version: identity.and_then(|value| value.version),
            content_hash: identity.map(|value| value.content_hash.clone()),
            decision,
        },
        document,
        feedback,
    }))
}

/// 只在当前进程内使用，不是存储格式；core 将其视为 opaque bytes。
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct TimelineMeta {
    pub id: String,
    pub thread_id: String,
    pub turn_id: Option<String>,
    pub descriptor: TimelineDescriptor,
}

impl TimelineMeta {
    pub(crate) fn from_item(item: &ThreadItem) -> Result<Self> {
        validate_counts(item.state())?;
        Ok(Self {
            id: item.id.clone(),
            thread_id: item.thread_id.clone(),
            turn_id: (!item.turn_id.is_empty()).then(|| item.turn_id.clone()),
            descriptor: match plan_completion(item)? {
                Some(plan) => TimelineDescriptor::Plan(plan.descriptor),
                None => descriptor(item.state(), &item.thread_id)?,
            },
        })
    }

    pub(crate) fn decode(bytes: &[u8]) -> Result<Self, ChatError> {
        // serde 的 typed 解码错误保留为 History source；不回退为旧内存编码或 raw JSON。
        serde_json::from_slice(bytes).map_err(|error| ChatError::History(Box::new(error)))
    }

    pub(crate) fn for_item(item: &ChatItem) -> Result<Self> {
        let meta = Self::decode(&item.meta)?;
        if meta.id != item.item_id || meta.turn_id != item.turn_id {
            return Err(ChatError::Conflict(
                "timeline metadata identity does not match item".into(),
            )
            .into());
        }
        Ok(meta)
    }

    pub(crate) fn header(&self, item: &ChatItem) -> TimelineItemHeader {
        TimelineItemHeader {
            id: self.id.clone(),
            thread_id: self.thread_id.clone(),
            turn_id: self.turn_id.clone(),
            append_seq: item.append_seq,
            source_effect_seq: item.source_effect_seq,
            sealed_at: item.sealed_at,
        }
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
            outcome: content_outcome(text.lifecycle())?,
        }),
        ThreadItemState::Thinking(thinking) => {
            TimelineDescriptor::Thinking(TimelineThinkingDescriptor {
                outcome: content_outcome(thinking.lifecycle())?,
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
                state: tool_state(tool.state())?,
                user_input: tool
                    .user_input()
                    .map(|input| user_input(input, thread_id))
                    .transpose()?,
                wait: tool.wait().cloned().map(Box::new),
            })
        }
        ThreadItemState::Agent(value) => TimelineDescriptor::Agent(TimelineAgentDescriptor {
            identity: value.identity().clone(),
            outcome: match value.state() {
                ThreadAgentState::Succeeded(v) => TimelineAgentOutcome::Succeeded(v.clone()),
                ThreadAgentState::Denied(v) => TimelineAgentOutcome::Denied(v.clone()),
                ThreadAgentState::Cancelled(v) => TimelineAgentOutcome::Cancelled(v.clone()),
                ThreadAgentState::Failed(v) => TimelineAgentOutcome::Failed(v.clone()),
                _ => return Err(nonterminal()),
            },
        }),
        ThreadItemState::Turn(value) => TimelineDescriptor::Turn(TimelineTurnDescriptor {
            input_id: value.input_id().map(str::to_owned),
            outcome: match value.state() {
                TurnState::Completed(v) => TimelineTurnOutcome::Completed(v.clone()),
                TurnState::Failed(v) => TimelineTurnOutcome::Failed(v.clone()),
                TurnState::Cancelled(v) => TimelineTurnOutcome::Cancelled(v.clone()),
                TurnState::BudgetLimited(v) => TimelineTurnOutcome::BudgetLimited(v.clone()),
                _ => return Err(nonterminal()),
            },
        }),
        ThreadItemState::Inference(value) => {
            TimelineDescriptor::Inference(TimelineInferenceDescriptor {
                inference_id: value.inference_id().to_owned(),
                model: value.model().to_owned(),
                outcome: match value.state() {
                    ThreadInferenceState::Completed(v) => {
                        TimelineInferenceOutcome::Completed(v.clone())
                    }
                    ThreadInferenceState::Failed(v) => TimelineInferenceOutcome::Failed(v.clone()),
                    ThreadInferenceState::Cancelled(v) => {
                        TimelineInferenceOutcome::Cancelled(v.clone())
                    }
                    _ => return Err(nonterminal()),
                },
            })
        }
        ThreadItemState::Skill(value) => TimelineDescriptor::Skill(value.clone()),
        ThreadItemState::File(value) => TimelineDescriptor::File(value.clone()),
        ThreadItemState::ContextCompaction(value) => {
            TimelineDescriptor::ContextCompaction(value.clone())
        }
    })
}

fn tool_state(state: &ThreadToolState) -> Result<TimelineToolState> {
    Ok(match state {
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
        _ => return Err(nonterminal()),
    })
}

fn nonterminal() -> anyhow::Error {
    ChatError::Conflict("cannot publish a nonterminal timeline item".into()).into()
}

fn content_outcome(state: &ThreadContentLifecycle) -> Result<TimelineContentOutcome> {
    Ok(match state {
        ThreadContentLifecycle::Completed(v) => TimelineContentOutcome::Completed(v.clone()),
        ThreadContentLifecycle::Failed(v) => TimelineContentOutcome::Failed(v.clone()),
        ThreadContentLifecycle::Cancelled(v) => TimelineContentOutcome::Cancelled(v.clone()),
        ThreadContentLifecycle::Streaming(_) => return Err(nonterminal()),
    })
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
            ThreadToolUserInputState::Pending => return Err(nonterminal()),
            ThreadToolUserInputState::Cancelled => TimelineUserInputState::Cancelled,
            ThreadToolUserInputState::Resolved(resolved) => TimelineUserInputState::Resolved {
                answers: resolved
                    .answers()
                    .iter()
                    .map(|answer| {
                        Ok(TimelineAnswerDescriptor {
                            question_id: answer.question_id().to_owned(),
                            answer_count: if answer.is_redacted()
                                || input
                                    .questions()
                                    .iter()
                                    .any(|q| q.id == answer.question_id() && q.is_secret)
                            {
                                0
                            } else {
                                count(answer.answers().len())?
                            },
                            redacted: answer.is_redacted()
                                || input
                                    .questions()
                                    .iter()
                                    .any(|q| q.id == answer.question_id() && q.is_secret),
                        })
                    })
                    .collect::<Result<_>>()?,
            },
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::{
        InterruptedThreadTool, ResolvedThreadToolUserInput, ThreadPlanDocumentIdentity,
        ThreadToolInvocation, ThreadToolItem, ThreadToolUserInputAnswer, UserQuestion,
    };

    fn plan(state: ThreadToolUserInputState, secret: bool, hash: &str) -> ThreadItem {
        let question = UserQuestion {
            id: AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.into(),
            header: "Plan".into(),
            question: "# Original".into(),
            is_other: true,
            is_secret: secret,
            options: None,
        };
        let input = ThreadToolUserInput::new("interaction".into(), vec![question], state)
            .with_plan_document(ThreadPlanDocumentIdentity {
                version: Some(3),
                content_hash: hash.into(),
            });
        let tool = ThreadToolItem::new(
            ThreadToolInvocation::new("call".into(), TOOL_PLAN_SUBMIT.into(), "{}".into()),
            ThreadToolState::Interrupted(InterruptedThreadTool::new(1, "finished".into())),
        )
        .with_user_input(Some(input));
        ThreadItem::new(
            "id".into(),
            "thread".into(),
            "turn".into(),
            1,
            1,
            1,
            1,
            ThreadItemState::Tool(tool),
        )
    }

    fn resolved(values: &[&str]) -> ThreadToolUserInputState {
        ThreadToolUserInputState::Resolved(ResolvedThreadToolUserInput::new(vec![
            ThreadToolUserInputAnswer::new(
                AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.into(),
                values.iter().map(|value| (*value).to_owned()).collect(),
            ),
        ]))
    }

    #[test]
    fn plan_facts_use_confirmation_and_checked_identity() {
        let hash = pl_core::context::content_hash(b"# Original");
        let item = plan(resolved(&["Revise", "  fix this  "]), false, &hash);
        let result = plan_completion(&item).unwrap().unwrap();
        assert_eq!(result.document.as_deref(), Some("# Original"));
        assert_eq!(result.feedback.as_deref(), Some("fix this"));
        assert_eq!(result.descriptor.document_version, Some(3));
        assert_eq!(
            result.descriptor.content_hash.as_deref(),
            Some(hash.as_str())
        );
        assert_eq!(
            result.descriptor.decision,
            TimelinePlanDecision::RevisionRequested
        );
        let approved = plan_completion(&plan(resolved(&["Approve"]), false, &hash))
            .unwrap()
            .unwrap();
        assert_eq!(approved.descriptor.decision, TimelinePlanDecision::Approved);
        assert!(approved.feedback.is_none());
        assert!(matches!(
            TimelineMeta::from_item(&item).unwrap().descriptor,
            TimelineDescriptor::Plan(_)
        ));
        assert!(plan_completion(&plan(resolved(&["Approve"]), false, "wrong")).is_err());
    }

    #[test]
    fn plan_does_not_guess_or_disclose_sensitive_answers() {
        let hash = pl_core::context::content_hash(b"# Original");
        let unknown = plan_completion(&plan(resolved(&["Approve", "Revise"]), false, &hash))
            .unwrap()
            .unwrap();
        assert_eq!(unknown.descriptor.decision, TimelinePlanDecision::Resolved);
        let secret = plan_completion(&plan(resolved(&["Approve"]), true, &hash))
            .unwrap()
            .unwrap();
        assert_eq!(secret.descriptor.decision, TimelinePlanDecision::Resolved);
        assert!(secret.document.is_none());
        assert!(secret.feedback.is_none());
        let cancelled = plan_completion(&plan(ThreadToolUserInputState::Cancelled, false, &hash))
            .unwrap()
            .unwrap();
        assert_eq!(
            cancelled.descriptor.decision,
            TimelinePlanDecision::Cancelled
        );
        assert!(plan_completion(&plan(ThreadToolUserInputState::Pending, false, &hash)).is_err());
    }
}
