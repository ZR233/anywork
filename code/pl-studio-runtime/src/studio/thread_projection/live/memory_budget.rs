//! Length-based placement charges and independently owned event allocations.
use crate::{
    ExecutionItem, ExecutionShape, InteractionContent, InteractionContinuationMessage,
    InteractionPurpose, InteractionRequest, SkillActivationCause, SkillActivationResourceBase,
    ThreadAgentItem, ThreadAgentState, ThreadAttachment, ThreadContentLifecycle,
    ThreadInferenceItem, ThreadInferenceState, ThreadSkillItem, ThreadToolItem, ThreadToolOutput,
    ThreadToolState, ToolApprovalState, TurnCancellationCause, TurnRolloverOutcome,
    UserInputAnswer, UserInputState, UserQuestion, UserQuestionOption,
};

pub(super) trait RetainedBytes {
    fn retained_bytes(&self) -> u64;
}

impl RetainedBytes for ExecutionItem {
    fn retained_bytes(&self) -> u64 {
        charged_item_bytes(self)
    }
}

/// Fixed per-identity charge of the retained-size estimate.
///
/// The estimate sums every variable-length body of an item, so this constant only covers the
/// identity, ordinals and payload shells around them. It never serializes an item.
pub(in crate::studio::thread_projection) const RETAINED_ITEM_OVERHEAD: u64 = 512;

/// Fixed per-entry charge of one map or set node whose key is measured separately.
///
/// Placement metadata (`Fact`) and the report accumulator are keyed collections; the key strings
/// themselves are summed by the estimator, and this constant covers the node and ordering overhead
/// around them.
pub(in crate::studio::thread_projection) const RETAINED_ENTRY_OVERHEAD: u64 = 64;

/// Resident bytes one retained item holds, its fixed identity overhead included.
fn charged_item_bytes(item: &ExecutionItem) -> u64 {
    item_body_bytes(item).saturating_add(RETAINED_ITEM_OVERHEAD)
}

/// Sums every resident body of one item's category payload.
pub(in crate::studio::thread_projection) fn item_body_bytes(item: &ExecutionItem) -> u64 {
    state_body_bytes(item.state())
}

pub(in crate::studio::thread_projection) fn state_body_bytes(state: &ExecutionShape) -> u64 {
    match state {
        ExecutionShape::Raw(raw) => raw
            .payloads
            .iter()
            .fold(0_u64, |total, payload| {
                total.saturating_add(payload.content.len() as u64)
            })
            .saturating_add(raw.notice.len() as u64),
        ExecutionShape::Text(text) => (text.text().len() as u64)
            .saturating_add(attachments_bytes(text.attachments()))
            .saturating_add(lifecycle_bytes(text.lifecycle())),
        ExecutionShape::Thinking(thinking) => thinking
            .summary()
            .iter()
            .chain(thinking.content())
            .fold(0_u64, |total, chunk| {
                total.saturating_add(chunk.len() as u64)
            })
            .saturating_add(lifecycle_bytes(thinking.lifecycle())),
        ExecutionShape::Tool(tool) => tool_bytes(tool),
        ExecutionShape::Agent(agent) => agent_bytes(agent),
        ExecutionShape::Turn(turn) => optional_bytes(turn.input_id()),
        ExecutionShape::Inference(inference) => inference_bytes(inference),
        ExecutionShape::Skill(skill) => skill_bytes(skill),
        ExecutionShape::File(file) => {
            (file.path().len() as u64).saturating_add(optional_bytes(file.media_type()))
        }
        ExecutionShape::ContextCompaction(_) => 0,
    }
}

pub(in crate::studio::thread_projection) fn optional_bytes(value: Option<&str>) -> u64 {
    value.map_or(0, |text| text.len() as u64)
}

/// Diagnostic bodies a text or reasoning lifecycle can carry beyond its content.
fn lifecycle_bytes(lifecycle: &ThreadContentLifecycle) -> u64 {
    optional_bytes(lifecycle.failure())
        .saturating_add(optional_bytes(lifecycle.cancellation_reason()))
}

/// Metadata of one attachment list; the referenced blobs are not resident.
fn attachments_bytes(attachments: &[ThreadAttachment]) -> u64 {
    attachments.iter().fold(0_u64, |total, attachment| {
        total
            .saturating_add(attachment.id.len() as u64)
            .saturating_add(attachment.media_type.len() as u64)
            .saturating_add(optional_bytes(attachment.filename.as_deref()))
            .saturating_add(RETAINED_ENTRY_OVERHEAD)
    })
}

/// Arguments and state bodies of one tool item.
pub(in crate::studio::thread_projection) fn tool_bytes(tool: &ThreadToolItem) -> u64 {
    let invocation = tool.invocation();
    let mut bytes = 0_u64;
    for text in [
        invocation.tool_call_id(),
        invocation.name(),
        invocation.arguments(),
    ] {
        bytes = bytes.saturating_add(text.len() as u64);
    }
    for text in [
        invocation.call_id(),
        invocation.provider_item_id(),
        invocation.working_directory(),
        invocation.task_id(),
    ] {
        bytes = bytes.saturating_add(optional_bytes(text));
    }
    match tool.state() {
        ThreadToolState::Queued(_)
        | ThreadToolState::Started(_)
        | ThreadToolState::Streaming(_)
        | ThreadToolState::AwaitingApproval(_)
        | ThreadToolState::Approved(_) => {}
        ThreadToolState::Cancelling(state) => {
            bytes = bytes.saturating_add(state.streamed_output().len() as u64);
        }
        ThreadToolState::Interrupted(state) => {
            bytes = bytes.saturating_add(state.reason().len() as u64);
        }
        ThreadToolState::Running(state) => {
            bytes = bytes.saturating_add(state.streamed_output().len() as u64);
        }
        ThreadToolState::Succeeded(state) => {
            bytes = bytes.saturating_add(tool_output_bytes(state.output()));
        }
        ThreadToolState::Failed(state) => {
            bytes = bytes
                .saturating_add(state.failure().message().len() as u64)
                .saturating_add(state.output().map_or(0, tool_output_bytes));
        }
        ThreadToolState::Denied(state) => {
            bytes = bytes.saturating_add(state.reason().len() as u64);
        }
        ThreadToolState::Cancelled(state) => {
            bytes = bytes.saturating_add(state.reason().len() as u64);
        }
    }
    if let Some(user_input) = tool.user_input() {
        bytes = bytes.saturating_add(user_input_bytes(user_input));
    }
    if let Some(wait) = tool.wait() {
        bytes = bytes.saturating_add(wait_bytes(wait));
    }
    bytes
}

fn wait_bytes(wait: &crate::ThreadWaitPresentation) -> u64 {
    match wait.intent() {
        crate::ThreadWaitIntent::Events { targets, .. } => {
            targets
                .iter()
                .fold(RETAINED_ENTRY_OVERHEAD, |total, target| {
                    total
                        .saturating_add(target.task_id().len() as u64)
                        .saturating_add(optional_bytes(target.tool_name()))
                        .saturating_add(optional_bytes(target.summary()))
                        .saturating_add(RETAINED_ENTRY_OVERHEAD)
                })
        }
        crate::ThreadWaitIntent::Timer { .. } => RETAINED_ENTRY_OVERHEAD,
    }
}

/// Placement scores visible payload lengths. Feed events own their allocations and charge
/// visible capacities and initialized value shells.
#[derive(Clone, Copy)]
enum Charge {
    Placement,
    FeedAllocation,
}

impl Charge {
    fn string(self, value: &String) -> u64 {
        match self {
            Self::Placement => value.len() as u64,
            Self::FeedAllocation => value.capacity() as u64,
        }
    }
}

fn user_questions_bytes(questions: &[UserQuestion], charge: Charge) -> u64 {
    let shell = match charge {
        Charge::Placement => RETAINED_ENTRY_OVERHEAD,
        Charge::FeedAllocation => std::mem::size_of::<UserQuestion>() as u64,
    };
    let mut bytes = shell.saturating_mul(questions.len() as u64);
    for question in questions {
        if matches!(charge, Charge::FeedAllocation) {
            bytes = bytes.saturating_add(charge.string(&question.id));
        }
        bytes = bytes
            .saturating_add(charge.string(&question.header))
            .saturating_add(charge.string(&question.question));
        if let Some(options) = &question.options {
            let option_shells = match charge {
                Charge::Placement => RETAINED_ENTRY_OVERHEAD.saturating_mul(options.len() as u64),
                Charge::FeedAllocation => (std::mem::size_of::<UserQuestionOption>() as u64)
                    .saturating_mul(options.capacity() as u64),
            };
            bytes = bytes.saturating_add(option_shells);
            for option in options {
                bytes = bytes
                    .saturating_add(charge.string(&option.label))
                    .saturating_add(charge.string(&option.description));
            }
        }
    }
    bytes
}

/// Questions and accepted answers of one user-input history projection.
///
/// The question bodies and the answer values are resident here and in the content fields the window
/// delivers, so the residency estimate charges every one of them exactly once per item.
fn user_input_bytes(user_input: &crate::ThreadToolUserInput) -> u64 {
    let questions = user_questions_bytes(user_input.questions(), Charge::Placement).saturating_add(
        user_input.plan_document().map_or(0, |identity| {
            (identity.content_hash.len() as u64).saturating_add(RETAINED_ENTRY_OVERHEAD)
        }),
    );
    user_input
        .answers()
        .iter()
        .fold(questions, |total, answer| {
            answer.answers().iter().fold(
                total.saturating_add(answer.question_id().len() as u64),
                |total, value| {
                    total
                        .saturating_add(value.len() as u64)
                        .saturating_add(RETAINED_ENTRY_OVERHEAD)
                },
            )
        })
}

/// Result, attachment metadata and opaque artifacts of one terminal tool output.
fn tool_output_bytes(output: &ThreadToolOutput) -> u64 {
    (output.result().len() as u64)
        .saturating_add(attachments_bytes(output.attachments()))
        .saturating_add(
            output
                .output_artifacts()
                .iter()
                .fold(0_u64, |total, artifact| {
                    total.saturating_add(json_bytes(artifact, Charge::Placement))
                }),
        )
}

/// Walk the initialized values once. Feed allocations additionally include vector capacity
/// and one logical shell per visible map entry.
fn json_bytes(value: &serde_json::Value, charge: Charge) -> u64 {
    use serde_json::Value;

    match value {
        Value::Null | Value::Bool(_) => match charge {
            Charge::Placement => 8,
            Charge::FeedAllocation => 0,
        },
        Value::Number(_) => match charge {
            Charge::Placement => 16,
            Charge::FeedAllocation => 0,
        },
        Value::String(text) => charge.string(text),
        Value::Array(values) => {
            let shell = match charge {
                Charge::Placement => 0,
                Charge::FeedAllocation => {
                    (std::mem::size_of::<Value>() as u64).saturating_mul(values.capacity() as u64)
                }
            };
            values.iter().fold(shell, |total, value| {
                total.saturating_add(json_bytes(value, charge))
            })
        }
        Value::Object(entries) => {
            let entry_shell = match charge {
                Charge::Placement => 0,
                Charge::FeedAllocation => (std::mem::size_of::<String>() as u64)
                    .saturating_add(std::mem::size_of::<Value>() as u64),
            };
            entries.iter().fold(0_u64, |total, (key, value)| {
                total
                    .saturating_add(entry_shell)
                    .saturating_add(charge.string(key))
                    .saturating_add(json_bytes(value, charge))
            })
        }
    }
}

/// Identity and state bodies of one agent item.
fn agent_bytes(agent: &ThreadAgentItem) -> u64 {
    let identity = agent.identity();
    let mut bytes = 0_u64;
    for text in [
        identity.id(),
        identity.path(),
        identity.role(),
        identity.task(),
    ] {
        bytes = bytes.saturating_add(text.len() as u64);
    }
    match agent.state() {
        ThreadAgentState::Queued(_) | ThreadAgentState::Running(_) => {}
        ThreadAgentState::Succeeded(state) => {
            bytes = bytes.saturating_add(state.summary().len() as u64);
        }
        ThreadAgentState::Denied(state) => {
            bytes = bytes.saturating_add(state.reason().len() as u64);
        }
        ThreadAgentState::Cancelled(state) => {
            bytes = bytes.saturating_add(state.reason().len() as u64);
        }
        ThreadAgentState::Failed(state) => {
            bytes = bytes.saturating_add(state.error().len() as u64);
        }
    }
    bytes
}

/// Identity and diagnostic bodies of one inference item.
fn inference_bytes(inference: &ThreadInferenceItem) -> u64 {
    let mut bytes =
        (inference.inference_id().len() as u64).saturating_add(inference.model().len() as u64);
    match inference.state() {
        ThreadInferenceState::Running(_) | ThreadInferenceState::Completed(_) => {}
        ThreadInferenceState::Failed(state) => {
            bytes = bytes.saturating_add(state.error().len() as u64);
        }
        ThreadInferenceState::Cancelled(state) => {
            bytes = bytes.saturating_add(state.reason().len() as u64);
        }
    }
    bytes
}

/// Bodies of one Skill activation item.
fn skill_bytes(skill: &ThreadSkillItem) -> u64 {
    let activation = skill.activation();
    let mut bytes = 0_u64;
    for text in [
        activation.name.as_str(),
        activation.source.as_str(),
        activation.provider_id.as_str(),
        activation.turn_id.as_str(),
    ] {
        bytes = bytes.saturating_add(text.len() as u64);
    }
    bytes = bytes.saturating_add(match &activation.cause {
        SkillActivationCause::Tool { tool_call_id } => tool_call_id.len() as u64,
        SkillActivationCause::UserGesture { invocation_id } => invocation_id.len() as u64,
    });
    bytes.saturating_add(match &activation.resource_base {
        SkillActivationResourceBase::Directory { path } => path.len() as u64,
        SkillActivationResourceBase::Url { url } => url.len() as u64,
        SkillActivationResourceBase::Opaque { description } => description.len() as u64,
    })
}

/// Variable-length diagnostics one Turn lifecycle state holds beyond its inline scalars.
///
/// The state's scalar shell is already part of `Turn`'s inline layout, so only owned strings are
/// charged: a failed Turn's structured failure, a coalesced cancellation's target identity and a
/// budget rollover's error. Every other variant carries only timestamps and copied discriminants.
pub(in crate::studio::thread_projection) fn turn_state_bytes(state: &crate::TurnState) -> u64 {
    match state {
        crate::TurnState::Queued(_) | crate::TurnState::Running(_) => 0,
        crate::TurnState::Completed(_) => 0,
        crate::TurnState::Cancelled(state) => match state.cause() {
            TurnCancellationCause::Coalesced { target_turn_id } => target_turn_id.len() as u64,
            TurnCancellationCause::Unspecified
            | TurnCancellationCause::UserRequested
            | TurnCancellationCause::RuntimeShutdown
            | TurnCancellationCause::AgentClosed
            | TurnCancellationCause::Interrupted
            | TurnCancellationCause::Recovery => 0,
        },
        crate::TurnState::Failed(state) => {
            let failure = state.failure();
            optional_bytes(failure.code.as_deref()).saturating_add(failure.message.len() as u64)
        }
        crate::TurnState::BudgetLimited(state) => match state.rollover() {
            TurnRolloverOutcome::Failed { error } => error.len() as u64,
            TurnRolloverOutcome::NotAttempted | TurnRolloverOutcome::Succeeded => 0,
        },
    }
}

/// Variable-length bodies one interaction aggregate holds beyond its inline shells.
///
/// The interaction is boxed inside [`LiveEvent`], so its heap shell is charged separately by
/// [`LiveEvent::retained_bytes`]; this walks only the owned strings, the question and answer bodies
/// and the opaque approval arguments.
pub(in crate::studio::thread_projection) fn interaction_request_bytes(
    interaction: &InteractionRequest,
) -> u64 {
    let scope = &interaction.scope;
    let mut bytes = (interaction.interaction_id.len() as u64)
        .saturating_add(scope.thread_id.len() as u64)
        .saturating_add(scope.turn_id.len() as u64)
        .saturating_add(optional_bytes(scope.item_id.as_deref()))
        .saturating_add(optional_bytes(scope.tool_id.as_deref()))
        .saturating_add(optional_bytes(scope.agent_path.as_deref()))
        .saturating_add(interaction_purpose_bytes(&scope.purpose))
        .saturating_add(interaction_content_bytes(&interaction.content));
    if let Some(continuation) = &interaction.continuation {
        bytes = bytes.saturating_add(match &continuation.message {
            InteractionContinuationMessage::Resolution => 0,
            InteractionContinuationMessage::Question { question_id } => question_id.len() as u64,
        });
    }
    bytes
}

/// Owned identity strings one interaction purpose carries; the general purpose carries none.
fn interaction_purpose_bytes(purpose: &InteractionPurpose) -> u64 {
    match purpose {
        InteractionPurpose::General => 0,
        InteractionPurpose::AgentSessionPlanConfirmation(purpose) => (purpose.operation_id.len()
            as u64)
            .saturating_add(purpose.argument_hash.len() as u64)
            .saturating_add(purpose.plan_hash.len() as u64),
    }
}

fn interaction_content_bytes(content: &InteractionContent) -> u64 {
    match content {
        InteractionContent::UserInput(user_input) => {
            user_questions_bytes(user_input.questions(), Charge::FeedAllocation)
                .saturating_add(user_input_state_bytes(user_input.state()))
        }
        InteractionContent::ToolApproval(tool_approval) => {
            let request = tool_approval.request();
            (request.name.len() as u64)
                .saturating_add(json_bytes(&request.arguments, Charge::FeedAllocation))
                .saturating_add(optional_bytes(request.working_directory.as_deref()))
                .saturating_add(optional_bytes(request.parent_agent_id.as_deref()))
                .saturating_add(tool_approval_state_bytes(tool_approval.state()))
        }
    }
}

/// Operation identities, accepted answers and cancellation reasons of one user-input interaction.
///
/// Event-path estimate: every public `String` charges its visible capacity, the
/// resolved answer map pays one logical entry shell per visible `(key, value)`
/// pair (the private hash node stays uncharged), and each answer's `Vec` pays
/// its capacity in `String` shells plus the strings' own dynamic bodies. Inline
/// stack shells already sit inside the entry shell and are never re-charged.
fn user_input_state_bytes(state: &UserInputState) -> u64 {
    match state {
        UserInputState::Pending(state) => state.operation_id().len() as u64,
        UserInputState::Resolved(state) => {
            let entry_shell = (std::mem::size_of::<String>() as u64)
                .saturating_add(std::mem::size_of::<UserInputAnswer>() as u64);
            let mut bytes = state.operation_id().len() as u64;
            for (question_id, answer) in state.answers() {
                bytes = bytes
                    .saturating_add(entry_shell)
                    .saturating_add(question_id.capacity() as u64)
                    .saturating_add(
                        (std::mem::size_of::<String>() as u64)
                            .saturating_mul(answer.answers.capacity() as u64),
                    );
                for value in &answer.answers {
                    bytes = bytes.saturating_add(value.capacity() as u64);
                }
            }
            bytes
        }
        UserInputState::Cancelled(state) => {
            (state.operation_id().len() as u64).saturating_add(state.reason().len() as u64)
        }
        UserInputState::Expired(state) => state.operation_id().len() as u64,
    }
}

/// Operation identities and decision reasons of one tool-approval interaction.
fn tool_approval_state_bytes(state: &ToolApprovalState) -> u64 {
    match state {
        ToolApprovalState::Pending(state) => state.operation_id().len() as u64,
        ToolApprovalState::Resolved(state) => {
            (state.operation_id().len() as u64).saturating_add(optional_bytes(state.reason()))
        }
        ToolApprovalState::Cancelled(state) => {
            (state.operation_id().len() as u64).saturating_add(state.reason().len() as u64)
        }
        ToolApprovalState::Expired(state) => state.operation_id().len() as u64,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn placement_ignores_question_spare_capacity_and_identity_while_feed_charges_both() {
        let mut id = String::with_capacity(40);
        id.push_str("choice");
        let mut options = Vec::with_capacity(4);
        options.push(UserQuestionOption {
            label: "Yes".into(),
            description: "Proceed".into(),
        });
        let feed_bytes = std::mem::size_of::<UserQuestion>()
            + id.capacity()
            + options.capacity() * std::mem::size_of::<UserQuestionOption>()
            + options[0].label.capacity()
            + options[0].description.capacity();
        let question = UserQuestion {
            id,
            header: String::new(),
            question: String::new(),
            is_other: false,
            is_secret: false,
            options: Some(options),
        };
        assert_eq!(
            user_questions_bytes(std::slice::from_ref(&question), Charge::Placement),
            2 * RETAINED_ENTRY_OVERHEAD + 10,
        );
        assert_eq!(
            user_questions_bytes(&[question], Charge::FeedAllocation),
            feed_bytes as u64,
        );
    }

    #[test]
    fn nested_json_preserves_scalar_placement_and_array_allocation_costs() {
        let mut text = String::with_capacity(40);
        text.push_str("value");
        let mut values = Vec::with_capacity(8);
        values.extend([Value::Bool(true), Value::Number(2.into())]);
        let allocation = values.capacity() * std::mem::size_of::<Value>() + text.capacity();
        values.push(Value::String(text));
        let value = Value::Array(values);
        assert_eq!(json_bytes(&value, Charge::Placement), 8 + 16 + 5);
        assert_eq!(
            json_bytes(&value, Charge::FeedAllocation),
            allocation as u64
        );
    }
}
