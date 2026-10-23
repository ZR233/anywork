use pl_protocol as protocol;
use crate::api::studio::types as bridge;
use super::super::read::interaction::BridgeInteractionPresentation;

impl From<protocol::MessagePresentation> for BridgeInteractionPresentation {
    fn from(value: protocol::MessagePresentation) -> Self {
        match value { protocol::MessagePresentation::Visible => Self::Visible, protocol::MessagePresentation::Hidden => Self::Hidden }
    }
}

impl From<protocol::ToolApprovalResolution> for bridge::BridgeToolApprovalResolution {
    fn from(value: protocol::ToolApprovalResolution) -> Self {
        match value { protocol::ToolApprovalResolution::Approved => Self::Approved, protocol::ToolApprovalResolution::Denied => Self::Denied }
    }
}

impl From<protocol::TodoStatus> for bridge::BridgeTodoStatus {
    fn from(value: protocol::TodoStatus) -> Self {
        match value { protocol::TodoStatus::Pending => Self::Pending, protocol::TodoStatus::InProgress => Self::InProgress,
            protocol::TodoStatus::Completed => Self::Completed }
    }
}

impl From<protocol::ThreadActivityArguments> for bridge::BridgeThreadActivityArguments {
    fn from(value: protocol::ThreadActivityArguments) -> Self {
        match value {
            protocol::ThreadActivityArguments::CommandLine => Self::CommandLine,
            protocol::ThreadActivityArguments::Opaque => Self::Opaque,
            protocol::ThreadActivityArguments::Streaming => Self::Streaming,
            protocol::ThreadActivityArguments::Unavailable => Self::Unavailable,
        }
    }
}

impl From<protocol::ThreadActivityToolState> for bridge::BridgeThreadActivityToolState {
    fn from(value: protocol::ThreadActivityToolState) -> Self {
        match value {
            protocol::ThreadActivityToolState::Running => Self::Running,
            protocol::ThreadActivityToolState::AwaitingApproval => Self::AwaitingApproval,
            protocol::ThreadActivityToolState::Cancelling => Self::Cancelling,
            protocol::ThreadActivityToolState::Finished => Self::Finished,
        }
    }
}

impl From<protocol::ThreadWaitState> for bridge::BridgeThreadWaitState {
    fn from(value: protocol::ThreadWaitState) -> Self {
        match value {
            protocol::ThreadWaitState::Waiting => Self::Waiting,
            protocol::ThreadWaitState::Ready => Self::Ready,
            protocol::ThreadWaitState::TimedOut => Self::TimedOut,
            protocol::ThreadWaitState::Elapsed => Self::Elapsed,
            protocol::ThreadWaitState::Cancelled => Self::Cancelled,
            protocol::ThreadWaitState::Failed => Self::Failed,
            protocol::ThreadWaitState::Interrupted => Self::Interrupted,
        }
    }
}

impl From<protocol::ThreadWaitTargetStatus> for bridge::BridgeThreadWaitTargetStatus {
    fn from(value: protocol::ThreadWaitTargetStatus) -> Self {
        match value {
            protocol::ThreadWaitTargetStatus::Running => Self::Running,
            protocol::ThreadWaitTargetStatus::Succeeded => Self::Succeeded,
            protocol::ThreadWaitTargetStatus::Failed => Self::Failed,
            protocol::ThreadWaitTargetStatus::Cancelled => Self::Cancelled,
            protocol::ThreadWaitTargetStatus::Interrupted => Self::Interrupted,
        }
    }
}
