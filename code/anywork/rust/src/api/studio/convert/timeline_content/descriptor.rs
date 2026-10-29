//! Product read descriptors → FRB; no body reconstruction or protocol reinterpretation.
use crate::api::studio::convert::thread_stream::{
    attachment, bridge_turn_state, content_lifecycle, token_usage, wait_presentation,
};
use crate::api::studio::types::*;
use pl_protocol::*;

pub(super) fn header(value: TimelineItemHeader) -> BridgeTimelineItemHeader {
    BridgeTimelineItemHeader {
        id: value.id,
        thread_id: value.thread_id,
        turn_id: value.turn_id,
        ordinal: value.ordinal,
        created_at: value.created_at,
        updated_at: value.updated_at,
    }
}

pub(super) fn descriptor(value: TimelineDescriptor) -> BridgeTimelineDescriptor {
    match value {
        TimelineDescriptor::Text(value) => {
            BridgeTimelineDescriptor::Text(BridgeTimelineTextDescriptor {
                channel: match value.channel {
                    ThreadTextChannel::User => BridgeThreadTextChannel::User,
                    ThreadTextChannel::ParentAgent => BridgeThreadTextChannel::ParentAgent,
                    ThreadTextChannel::Commentary => BridgeThreadTextChannel::Commentary,
                    ThreadTextChannel::Final => BridgeThreadTextChannel::Final,
                },
                attachments: value.attachments.iter().map(attachment).collect(),
                lifecycle: content_lifecycle(&value.lifecycle),
            })
        }
        TimelineDescriptor::Thinking(value) => {
            BridgeTimelineDescriptor::Thinking(BridgeTimelineThinkingDescriptor {
                lifecycle: content_lifecycle(&value.lifecycle),
            })
        }
        TimelineDescriptor::Raw(value) => {
            BridgeTimelineDescriptor::Raw(BridgeTimelineRawDescriptor {
                origin: match value.origin {
                    ThreadRawItemOrigin::Stored => BridgeRawItemOrigin::Stored,
                    ThreadRawItemOrigin::RuntimeControl => BridgeRawItemOrigin::RuntimeControl,
                },
                payloads: value
                    .payloads
                    .into_iter()
                    .map(|payload| BridgeTimelineRawPayloadDescriptor {
                        format: payload.format,
                        version: payload.version,
                    })
                    .collect(),
                notice: value.notice,
                recorded_at: value.recorded_at,
            })
        }
        TimelineDescriptor::Tool(value) => {
            BridgeTimelineDescriptor::Tool(Box::new(BridgeTimelineToolDescriptor {
                invocation: BridgeTimelineToolInvocation {
                    tool_call_id: value.invocation.tool_call_id,
                    call_id: value.invocation.call_id,
                    provider_item_id: value.invocation.provider_item_id,
                    name: value.invocation.name,
                    working_directory: value.invocation.working_directory,
                    task_id: value.invocation.task_id,
                },
                state: tool_state(value.state),
                user_input: value.user_input.map(user_input),
                wait: value.wait.map(|wait| Box::new(wait_presentation(*wait))),
            }))
        }
        TimelineDescriptor::Agent(value) => {
            let identity = value.identity();
            BridgeTimelineDescriptor::Agent {
                identity: BridgeThreadAgentIdentity {
                    id: identity.id().to_string(),
                    path: identity.path().to_string(),
                    parent_path: identity.parent_path().map(str::to_string),
                    role: identity.role().to_string(),
                    task: identity.task().to_string(),
                    depth: identity.depth(),
                },
                state: match value.state() {
                    ThreadAgentState::Queued(_) => BridgeThreadAgentState::Queued,
                    ThreadAgentState::Running(_) => BridgeThreadAgentState::Running,
                    ThreadAgentState::Succeeded(state) => BridgeThreadAgentState::Succeeded {
                        completed_at: state.completed_at(),
                        summary: state.summary().to_string(),
                    },
                    ThreadAgentState::Denied(state) => BridgeThreadAgentState::Denied {
                        denied_at: state.denied_at(),
                        reason: state.reason().to_string(),
                    },
                    ThreadAgentState::Cancelled(state) => BridgeThreadAgentState::Cancelled {
                        cancelled_at: state.cancelled_at(),
                        reason: state.reason().to_string(),
                    },
                    ThreadAgentState::Failed(state) => BridgeThreadAgentState::Failed {
                        failed_at: state.failed_at(),
                        error: state.error().to_string(),
                    },
                },
            }
        }
        TimelineDescriptor::Turn(value) => BridgeTimelineDescriptor::Turn {
            state: bridge_turn_state(value.state()),
            input_id: value.input_id().map(str::to_owned),
        },
        TimelineDescriptor::Inference(value) => BridgeTimelineDescriptor::Inference {
            inference_id: value.inference_id().to_string(),
            model: value.model().to_string(),
            state: match value.state() {
                ThreadInferenceState::Running(_) => BridgeThreadInferenceState::Running,
                ThreadInferenceState::Completed(state) => BridgeThreadInferenceState::Completed {
                    completed_at: state.completed_at(),
                    usage: token_usage(state.usage().clone()),
                },
                ThreadInferenceState::Failed(state) => BridgeThreadInferenceState::Failed {
                    failed_at: state.failed_at(),
                    error: state.error().to_string(),
                },
                ThreadInferenceState::Cancelled(state) => BridgeThreadInferenceState::Cancelled {
                    cancelled_at: state.cancelled_at(),
                    reason: state.reason().to_string(),
                },
            },
        },
        TimelineDescriptor::Skill(value) => {
            let activation = value.activation();
            BridgeTimelineDescriptor::Skill {
                name: activation.name.clone(),
                source: activation.source.clone(),
                provider_id: activation.provider_id.clone(),
                resource_base: match &activation.resource_base {
                    pl_protocol::SkillActivationResourceBase::Directory { path } => {
                        BridgeSkillResourceBase::Directory { path: path.clone() }
                    }
                    pl_protocol::SkillActivationResourceBase::Url { url } => {
                        BridgeSkillResourceBase::Url { url: url.clone() }
                    }
                    pl_protocol::SkillActivationResourceBase::Opaque { description } => {
                        BridgeSkillResourceBase::Opaque {
                            description: description.clone(),
                        }
                    }
                },
                cause: match &activation.cause {
                    pl_protocol::SkillActivationCause::Tool { tool_call_id } => {
                        BridgeSkillActivationCause::Tool {
                            tool_call_id: tool_call_id.clone(),
                        }
                    }
                    pl_protocol::SkillActivationCause::UserGesture { invocation_id } => {
                        BridgeSkillActivationCause::UserGesture {
                            invocation_id: invocation_id.clone(),
                        }
                    }
                },
                activated_at: activation.activated_at,
            }
        }
        TimelineDescriptor::File(value) => BridgeTimelineDescriptor::File {
            path: value.path().to_string(),
            media_type: value.media_type().map(str::to_string),
            completed_at: value.completed_at(),
        },
        TimelineDescriptor::ContextCompaction(value) => {
            BridgeTimelineDescriptor::ContextCompaction {
                before_tokens: value.before_tokens(),
                after_tokens: value.after_tokens(),
                compacted_at: value.compacted_at(),
            }
        }
    }
}

fn tool_state(value: TimelineToolState) -> BridgeTimelineToolState {
    match value {
        TimelineToolState::Queued => BridgeTimelineToolState::Queued,
        TimelineToolState::Cancelling => BridgeTimelineToolState::Cancelling,
        TimelineToolState::Started => BridgeTimelineToolState::Started,
        TimelineToolState::Streaming => BridgeTimelineToolState::Streaming,
        TimelineToolState::AwaitingApproval => BridgeTimelineToolState::AwaitingApproval,
        TimelineToolState::Approved => BridgeTimelineToolState::Approved,
        TimelineToolState::Running => BridgeTimelineToolState::Running,
        TimelineToolState::Interrupted {
            interrupted_at,
            reason,
        } => BridgeTimelineToolState::Interrupted {
            interrupted_at,
            reason,
        },
        TimelineToolState::Succeeded {
            completed_at,
            output,
        } => BridgeTimelineToolState::Succeeded {
            completed_at,
            output: tool_output(output),
        },
        TimelineToolState::Failed {
            failed_at,
            failure,
            output,
        } => BridgeTimelineToolState::Failed {
            failed_at,
            failure: BridgeThreadToolFailure {
                kind: match failure.kind() {
                    ThreadToolFailureKind::Execution => BridgeThreadToolFailureKind::Execution,
                    ThreadToolFailureKind::TimedOut => BridgeThreadToolFailureKind::TimedOut,
                    ThreadToolFailureKind::BudgetLimited => {
                        BridgeThreadToolFailureKind::BudgetLimited
                    }
                },
                message: failure.message().to_owned(),
            },
            output: output.map(tool_output),
        },
        TimelineToolState::Denied { denied_at, reason } => {
            BridgeTimelineToolState::Denied { denied_at, reason }
        }
        TimelineToolState::Cancelled {
            cancelled_at,
            reason,
        } => BridgeTimelineToolState::Cancelled {
            cancelled_at,
            reason,
        },
    }
}
fn tool_output(value: TimelineToolOutputDescriptor) -> BridgeTimelineToolOutputDescriptor {
    BridgeTimelineToolOutputDescriptor {
        attachments: value.attachments.iter().map(attachment).collect(),
        exit_code: value.exit_code,
    }
}
fn user_input(value: TimelineUserInputDescriptor) -> BridgeTimelineUserInputDescriptor {
    BridgeTimelineUserInputDescriptor {
        interaction_id: value.interaction_id,
        questions: value
            .questions
            .into_iter()
            .map(|q| BridgeTimelineQuestionDescriptor {
                id: q.id,
                is_other: q.is_other,
                is_secret: q.is_secret,
                option_count: q.option_count,
            })
            .collect(),
        state: match value.state {
            TimelineUserInputState::Pending => BridgeTimelineUserInputState::Pending,
            TimelineUserInputState::Cancelled => BridgeTimelineUserInputState::Cancelled,
            TimelineUserInputState::Resolved { answers } => {
                BridgeTimelineUserInputState::Resolved {
                    answers: answers
                        .into_iter()
                        .map(|a| BridgeTimelineAnswerDescriptor {
                            question_id: a.question_id,
                            answer_count: a.answer_count,
                            redacted: a.redacted,
                        })
                        .collect(),
                }
            }
        },
    }
}
