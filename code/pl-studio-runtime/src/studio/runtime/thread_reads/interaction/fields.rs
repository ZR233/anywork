use pl_protocol::studio::{ReadText, StudioError};
use pl_protocol::{
    InteractionContent, InteractionContinuationMessage, InteractionPurpose, ToolApprovalState,
    UserInputState,
};

use super::super::super::read_budget::protocol;
use super::InteractionMaterial;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum Field {
    InteractionId,
    ThreadId,
    TurnId,
    ItemId,
    ToolId,
    AgentPath,
    PurposeOperation,
    ArgumentHash,
    PlanHash,
    ContinuationQuestion,
    ApprovalName,
    ApprovalArguments,
    WorkingDirectory,
    ParentAgentId,
    StateOperation,
    StateReason,
    QuestionId(usize),
    QuestionHeader(usize),
    QuestionText(usize),
    OptionLabel(usize, usize),
    OptionDescription(usize, usize),
    AnswerKey(usize),
    AnswerValue(usize, usize),
}

impl InteractionMaterial {
    pub(super) fn read(&self, field: Field, inline: usize) -> Result<ReadText, StudioError> {
        self.fields.read(field, self.source_text(field)?, inline)
    }

    pub(super) fn source_text(&self, field: Field) -> Result<&str, StudioError> {
        let source = &self.source;
        let value = match field {
            Field::InteractionId => Some(source.interaction_id.as_str()),
            Field::ThreadId => Some(source.scope.thread_id.as_str()),
            Field::TurnId => Some(source.scope.turn_id.as_str()),
            Field::ItemId => source.scope.item_id.as_deref(),
            Field::ToolId => source.scope.tool_id.as_deref(),
            Field::AgentPath => source.scope.agent_path.as_deref(),
            Field::PurposeOperation | Field::ArgumentHash | Field::PlanHash => match &source
                .scope
                .purpose
            {
                InteractionPurpose::General => None,
                InteractionPurpose::AgentSessionPlanConfirmation(purpose) => Some(match field {
                    Field::PurposeOperation => purpose.operation_id.as_str(),
                    Field::ArgumentHash => purpose.argument_hash.as_str(),
                    Field::PlanHash => purpose.plan_hash.as_str(),
                    _ => return Err(protocol("Incompatible interaction purpose field")),
                }),
            },
            Field::ContinuationQuestion => {
                source
                    .continuation
                    .as_ref()
                    .and_then(|continuation| match &continuation.message {
                        InteractionContinuationMessage::Question { question_id } => {
                            Some(question_id.as_str())
                        }
                        InteractionContinuationMessage::Resolution => None,
                    })
            }
            Field::ApprovalName | Field::WorkingDirectory | Field::ParentAgentId => {
                match &source.content {
                    InteractionContent::ToolApproval(approval) => match field {
                        Field::ApprovalName => Some(approval.request().name.as_str()),
                        Field::WorkingDirectory => approval.request().working_directory.as_deref(),
                        Field::ParentAgentId => approval.request().parent_agent_id.as_deref(),
                        _ => return Err(protocol("Incompatible approval field")),
                    },
                    InteractionContent::UserInput(_) => None,
                }
            }
            Field::ApprovalArguments => self.argument_json.as_deref(),
            Field::StateOperation => Some(match &source.content {
                InteractionContent::UserInput(value) => match value.state() {
                    UserInputState::Pending(value) => value.operation_id(),
                    UserInputState::Resolved(value) => value.operation_id(),
                    UserInputState::Cancelled(value) => value.operation_id(),
                    UserInputState::Expired(value) => value.operation_id(),
                },
                InteractionContent::ToolApproval(value) => match value.state() {
                    ToolApprovalState::Pending(value) => value.operation_id(),
                    ToolApprovalState::Resolved(value) => value.operation_id(),
                    ToolApprovalState::Cancelled(value) => value.operation_id(),
                    ToolApprovalState::Expired(value) => value.operation_id(),
                },
            }),
            Field::StateReason => match &source.content {
                InteractionContent::UserInput(value) => match value.state() {
                    UserInputState::Cancelled(value) => Some(value.reason()),
                    UserInputState::Pending(_)
                    | UserInputState::Resolved(_)
                    | UserInputState::Expired(_) => None,
                },
                InteractionContent::ToolApproval(value) => match value.state() {
                    ToolApprovalState::Resolved(value) => value.reason(),
                    ToolApprovalState::Cancelled(value) => Some(value.reason()),
                    ToolApprovalState::Pending(_) | ToolApprovalState::Expired(_) => None,
                },
            },
            Field::QuestionId(index) => self
                .questions_source()?
                .get(index)
                .map(|value| value.id.as_str()),
            Field::QuestionHeader(index) => self
                .questions_source()?
                .get(index)
                .map(|value| value.header.as_str()),
            Field::QuestionText(index) => self
                .questions_source()?
                .get(index)
                .map(|value| value.question.as_str()),
            Field::OptionLabel(question, option) => self
                .questions_source()?
                .get(question)
                .and_then(|question| question.options.as_ref())
                .and_then(|options| options.get(option))
                .map(|value| value.label.as_str()),
            Field::OptionDescription(question, option) => self
                .questions_source()?
                .get(question)
                .and_then(|question| question.options.as_ref())
                .and_then(|options| options.get(option))
                .map(|value| value.description.as_str()),
            Field::AnswerKey(index) => Some(self.answer(index)?.0),
            Field::AnswerValue(entry, index) => {
                self.answer(entry)?.1.answers.get(index).map(String::as_str)
            }
        };
        value.ok_or_else(|| protocol("Text field does not address the pinned interaction schema"))
    }
}
