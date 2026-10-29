//! Product read descriptors → FRB; no body reconstruction or protocol reinterpretation.
use crate::api::studio::convert::thread_stream::{
    attachment, bridge_turn_failure, token_usage, turn_budget_limit, turn_cancellation_cause,
    turn_rollover, wait_presentation,
};
use crate::api::studio::types::*;
use pl_protocol::*;

pub(super) fn header(value: TimelineItemHeader) -> BridgeTimelineItemHeader {
    BridgeTimelineItemHeader {
        id: value.id,
        thread_id: value.thread_id,
        turn_id: value.turn_id,
        append_seq: value.append_seq,
        source_effect_seq: value.source_effect_seq,
        sealed_at: value.sealed_at,
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
                outcome: content_outcome(value.outcome),
            })
        }
        TimelineDescriptor::Thinking(value) => {
            BridgeTimelineDescriptor::Thinking(BridgeTimelineThinkingDescriptor {
                outcome: content_outcome(value.outcome),
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
            let identity = &value.identity;
            BridgeTimelineDescriptor::Agent {
                identity: BridgeThreadAgentIdentity {
                    id: identity.id().to_string(),
                    path: identity.path().to_string(),
                    parent_path: identity.parent_path().map(str::to_string),
                    role: identity.role().to_string(),
                    task: identity.task().to_string(),
                    depth: identity.depth(),
                },
                outcome: match value.outcome {
                    TimelineAgentOutcome::Succeeded(state) => {
                        BridgeTimelineAgentOutcome::Succeeded {
                            completed_at: state.completed_at(),
                            summary: state.summary().to_string(),
                        }
                    }
                    TimelineAgentOutcome::Denied(state) => BridgeTimelineAgentOutcome::Denied {
                        denied_at: state.denied_at(),
                        reason: state.reason().to_string(),
                    },
                    TimelineAgentOutcome::Cancelled(state) => {
                        BridgeTimelineAgentOutcome::Cancelled {
                            cancelled_at: state.cancelled_at(),
                            reason: state.reason().to_string(),
                        }
                    }
                    TimelineAgentOutcome::Failed(state) => BridgeTimelineAgentOutcome::Failed {
                        failed_at: state.failed_at(),
                        error: state.error().to_string(),
                    },
                },
            }
        }
        TimelineDescriptor::Turn(value) => BridgeTimelineDescriptor::Turn {
            outcome: turn_outcome(value.outcome),
            input_id: value.input_id,
        },
        TimelineDescriptor::Inference(value) => BridgeTimelineDescriptor::Inference {
            inference_id: value.inference_id,
            model: value.model,
            outcome: match value.outcome {
                TimelineInferenceOutcome::Completed(state) => {
                    BridgeTimelineInferenceOutcome::Completed {
                        completed_at: state.completed_at(),
                        usage: token_usage(state.usage().clone()),
                    }
                }
                TimelineInferenceOutcome::Failed(state) => BridgeTimelineInferenceOutcome::Failed {
                    failed_at: state.failed_at(),
                    error: state.error().to_string(),
                },
                TimelineInferenceOutcome::Cancelled(state) => {
                    BridgeTimelineInferenceOutcome::Cancelled {
                        cancelled_at: state.cancelled_at(),
                        reason: state.reason().to_string(),
                    }
                }
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
        TimelineDescriptor::Plan(value) => BridgeTimelineDescriptor::Plan {
            interaction_id: value.interaction_id,
            document_version: value.document_version,
            content_hash: value.content_hash,
            decision: match value.decision {
                TimelinePlanDecision::Approved => BridgeTimelinePlanDecision::Approved,
                TimelinePlanDecision::RevisionRequested => {
                    BridgeTimelinePlanDecision::RevisionRequested
                }
                TimelinePlanDecision::Cancelled => BridgeTimelinePlanDecision::Cancelled,
                TimelinePlanDecision::Resolved => BridgeTimelinePlanDecision::Resolved,
            },
        },
    }
}

fn tool_state(value: TimelineToolState) -> BridgeTimelineToolState {
    match value {
        TimelineToolState::BackgroundStarted { started_at } => {
            BridgeTimelineToolState::BackgroundStarted { started_at }
        }
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

fn content_outcome(value: TimelineContentOutcome) -> BridgeTimelineContentOutcome {
    match value {
        TimelineContentOutcome::Completed(state) => BridgeTimelineContentOutcome::Completed {
            completed_at: state.completed_at(),
        },
        TimelineContentOutcome::Failed(state) => BridgeTimelineContentOutcome::Failed {
            failed_at: state.failed_at(),
            error: state.error().to_owned(),
        },
        TimelineContentOutcome::Cancelled(state) => BridgeTimelineContentOutcome::Cancelled {
            cancelled_at: state.cancelled_at(),
            reason: state.reason().to_owned(),
        },
    }
}

fn turn_outcome(value: TimelineTurnOutcome) -> BridgeTimelineTurnOutcome {
    match value {
        TimelineTurnOutcome::Completed(state) => BridgeTimelineTurnOutcome::Completed {
            started_at: state.started_at(),
            completed_at: state.completed_at(),
            completion: match state.completion() {
                TurnCompletion::Normal => BridgeTurnCompletion::Normal,
                TurnCompletion::InteractionRequested => BridgeTurnCompletion::InteractionRequested,
            },
        },
        TimelineTurnOutcome::Cancelled(state) => BridgeTimelineTurnOutcome::Cancelled {
            started_at: state.started_at(),
            requested_at: state.requested_at(),
            completed_at: state.completed_at(),
            cause: turn_cancellation_cause(state.cause().clone()),
        },
        TimelineTurnOutcome::Failed(state) => BridgeTimelineTurnOutcome::Failed {
            started_at: state.started_at(),
            completed_at: state.completed_at(),
            failure: bridge_turn_failure(state.failure().clone()),
        },
        TimelineTurnOutcome::BudgetLimited(state) => BridgeTimelineTurnOutcome::BudgetLimited {
            started_at: state.started_at(),
            completed_at: state.completed_at(),
            limit: turn_budget_limit(*state.limit()),
            rollover: turn_rollover(state.rollover().clone()),
        },
    }
}
