use pl_protocol::thread_facets::read::interaction as protocol;
use super::super::read::interaction as bridge;

impl From<protocol::InteractionReadPurpose> for bridge::BridgeInteractionReadPurpose {
    fn from(value: protocol::InteractionReadPurpose) -> Self {
        match value {
            protocol::InteractionReadPurpose::General => Self::General,
            protocol::InteractionReadPurpose::PlanConfirmation { expected_revision, operation_id, argument_hash, plan_hash } =>
                Self::PlanConfirmation { expected_revision, operation_id: operation_id.into(),
                    argument_hash: argument_hash.into(), plan_hash: plan_hash.into() },
        }
    }
}

impl From<protocol::InteractionReadContinuation> for bridge::BridgeInteractionReadContinuation {
    fn from(value: protocol::InteractionReadContinuation) -> Self {
        match value {
            protocol::InteractionReadContinuation::Resolution { presentation } => Self::Resolution { presentation: presentation.into() },
            protocol::InteractionReadContinuation::Question { question_id, presentation } => Self::Question {
                question_id: question_id.into(), presentation: presentation.into(),
            },
        }
    }
}

impl From<protocol::InteractionReadContent> for bridge::BridgeInteractionReadContent {
    fn from(value: protocol::InteractionReadContent) -> Self {
        match value {
            protocol::InteractionReadContent::UserInput { question_count } => Self::UserInput { question_count },
            protocol::InteractionReadContent::ToolApproval { name, arguments, working_directory, parent_agent_id } => Self::ToolApproval {
                name: name.into(), arguments: arguments.into(), working_directory: working_directory.map(Into::into),
                parent_agent_id: parent_agent_id.map(Into::into),
            },
        }
    }
}

impl From<protocol::InteractionReadState> for bridge::BridgeInteractionReadState {
    fn from(value: protocol::InteractionReadState) -> Self {
        match value {
            protocol::InteractionReadState::Pending { operation_id } => Self::Pending { operation_id: operation_id.into() },
            protocol::InteractionReadState::UserInputResolved { operation_id, resolved_at, answer_entry_count } => Self::UserInputResolved {
                operation_id: operation_id.into(), resolved_at, answer_entry_count,
            },
            protocol::InteractionReadState::ApprovalResolved { operation_id, resolved_at, decision, reason } => Self::ApprovalResolved {
                operation_id: operation_id.into(), resolved_at, decision: decision.into(), reason: reason.map(Into::into),
            },
            protocol::InteractionReadState::Cancelled { operation_id, cancelled_at, reason } => Self::Cancelled {
                operation_id: operation_id.into(), cancelled_at, reason: reason.into(),
            },
            protocol::InteractionReadState::Expired { operation_id, expired_at } => Self::Expired { operation_id: operation_id.into(), expired_at },
        }
    }
}

impl From<protocol::InteractionReadHeader> for bridge::BridgeInteractionReadHeader {
    fn from(value: protocol::InteractionReadHeader) -> Self {
        Self { scope: value.scope.into(), interaction_id: value.interaction_id.into(), thread_id: value.thread_id.into(),
            turn_id: value.turn_id.into(), item_id: value.item_id.map(Into::into), tool_id: value.tool_id.map(Into::into),
            agent_path: value.agent_path.map(Into::into), revision: value.revision, purpose: value.purpose.into(),
            continuation: value.continuation.map(Into::into), created_at: value.created_at, updated_at: value.updated_at,
            content: value.content.into(), state: value.state.into() }
    }
}

impl From<protocol::QuestionReadItem> for bridge::BridgeQuestionReadItem {
    fn from(value: protocol::QuestionReadItem) -> Self {
        Self { index: value.index, id: value.id.into(), header: value.header.into(), question: value.question.into(),
            is_other: value.is_other, is_secret: value.is_secret, options_count: value.options_count }
    }
}

impl From<protocol::OptionReadItem> for bridge::BridgeOptionReadItem {
    fn from(value: protocol::OptionReadItem) -> Self {
        Self { index: value.index, label: value.label.into(), description: value.description.into() }
    }
}

impl From<protocol::AnswerEntryReadItem> for bridge::BridgeAnswerEntryReadItem {
    fn from(value: protocol::AnswerEntryReadItem) -> Self {
        Self { index: value.index, question_id: value.question_id.into(), answer_count: value.answer_count }
    }
}

impl From<protocol::AnswerValueReadItem> for bridge::BridgeAnswerValueReadItem {
    fn from(value: protocol::AnswerValueReadItem) -> Self { Self { index: value.index, value: value.value.into() } }
}

impl From<protocol::QuestionPage> for bridge::BridgeQuestionPage {
    fn from(value: protocol::QuestionPage) -> Self {
        Self { scope: value.scope.into(), offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::OptionPage> for bridge::BridgeOptionPage {
    fn from(value: protocol::OptionPage) -> Self {
        Self { scope: value.scope.into(), offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::AnswerEntryPage> for bridge::BridgeAnswerEntryPage {
    fn from(value: protocol::AnswerEntryPage) -> Self {
        Self { scope: value.scope.into(), offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::AnswerValuePage> for bridge::BridgeAnswerValuePage {
    fn from(value: protocol::AnswerValuePage) -> Self {
        Self { scope: value.scope.into(), offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}
