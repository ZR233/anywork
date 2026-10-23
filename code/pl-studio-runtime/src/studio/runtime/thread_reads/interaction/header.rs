use pl_protocol::studio::StudioError;
use pl_protocol::thread_facets::read::interaction::{InteractionReadContent, InteractionReadContinuation,
    InteractionReadHeader, InteractionReadPurpose, InteractionReadState};
use pl_protocol::{InteractionContent, InteractionContinuationMessage, InteractionPurpose,
    ToolApprovalState, UserInputState};

use super::InteractionMaterial;
use super::fields::Field;
use super::super::super::read_budget::{bounded_header, count};

impl InteractionMaterial {
    pub(in super::super) fn header(&self) -> Result<InteractionReadHeader, StudioError> {
        bounded_header(|inline| {
            let source = &self.source;
            let optional = |present: bool, field: Field| {
                present.then(|| self.read(field, inline)).transpose()
            };
            let purpose = match &source.scope.purpose {
                InteractionPurpose::General => InteractionReadPurpose::General,
                InteractionPurpose::AgentSessionPlanConfirmation(value) => InteractionReadPurpose::PlanConfirmation {
                    expected_revision: value.expected_revision,
                    operation_id: self.read(Field::PurposeOperation, inline)?,
                    argument_hash: self.read(Field::ArgumentHash, inline)?,
                    plan_hash: self.read(Field::PlanHash, inline)?,
                },
            };
            let continuation = source.continuation.as_ref().map(|value| {
                Ok::<_, StudioError>(match &value.message {
                    InteractionContinuationMessage::Resolution => InteractionReadContinuation::Resolution {
                        presentation: value.presentation,
                    },
                    InteractionContinuationMessage::Question { .. } => InteractionReadContinuation::Question {
                        question_id: self.read(Field::ContinuationQuestion, inline)?, presentation: value.presentation,
                    },
                })
            }).transpose()?;
            let content = match &source.content {
                InteractionContent::UserInput(value) => InteractionReadContent::UserInput {
                    question_count: count(value.questions().len())?,
                },
                InteractionContent::ToolApproval(value) => InteractionReadContent::ToolApproval {
                    name: self.read(Field::ApprovalName, inline)?,
                    arguments: self.read(Field::ApprovalArguments, inline)?,
                    working_directory: optional(value.request().working_directory.is_some(), Field::WorkingDirectory)?,
                    parent_agent_id: optional(value.request().parent_agent_id.is_some(), Field::ParentAgentId)?,
                },
            };
            let operation_id = self.read(Field::StateOperation, inline)?;
            let state = match &source.content {
                InteractionContent::UserInput(value) => match value.state() {
                    UserInputState::Pending(_) => InteractionReadState::Pending { operation_id },
                    UserInputState::Resolved(value) => InteractionReadState::UserInputResolved {
                        operation_id, resolved_at: value.resolved_at(), answer_entry_count: count(value.answers().len())?,
                    },
                    UserInputState::Cancelled(value) => InteractionReadState::Cancelled {
                        operation_id, cancelled_at: value.cancelled_at(), reason: self.read(Field::StateReason, inline)?,
                    },
                    UserInputState::Expired(value) => InteractionReadState::Expired {
                        operation_id, expired_at: value.expired_at(),
                    },
                },
                InteractionContent::ToolApproval(value) => match value.state() {
                    ToolApprovalState::Pending(_) => InteractionReadState::Pending { operation_id },
                    ToolApprovalState::Resolved(value) => InteractionReadState::ApprovalResolved {
                        operation_id, resolved_at: value.resolved_at(), decision: value.decision(),
                        reason: optional(value.reason().is_some(), Field::StateReason)?,
                    },
                    ToolApprovalState::Cancelled(value) => InteractionReadState::Cancelled {
                        operation_id, cancelled_at: value.cancelled_at(), reason: self.read(Field::StateReason, inline)?,
                    },
                    ToolApprovalState::Expired(value) => InteractionReadState::Expired {
                        operation_id, expired_at: value.expired_at(),
                    },
                },
            };
            Ok(InteractionReadHeader {
                scope: self.scope.clone(), interaction_id: self.read(Field::InteractionId, inline)?,
                thread_id: self.read(Field::ThreadId, inline)?, turn_id: self.read(Field::TurnId, inline)?,
                item_id: optional(source.scope.item_id.is_some(), Field::ItemId)?,
                tool_id: optional(source.scope.tool_id.is_some(), Field::ToolId)?,
                agent_path: optional(source.scope.agent_path.is_some(), Field::AgentPath)?,
                revision: source.revision, purpose, continuation, created_at: source.created_at,
                updated_at: source.updated_at, content, state,
            })
        })
    }
}
