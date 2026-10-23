use pl_protocol as protocol;
use crate::api::studio::types as bridge;

impl From<protocol::TurnPhase> for bridge::BridgeTurnPhase {
    fn from(value: protocol::TurnPhase) -> Self {
        match value {
            protocol::TurnPhase::Preparing => Self::Preparing,
            protocol::TurnPhase::Thinking => Self::Thinking,
            protocol::TurnPhase::Responding => Self::Responding,
            protocol::TurnPhase::Planning => Self::Planning,
            protocol::TurnPhase::RunningTool => Self::RunningTool,
            protocol::TurnPhase::Persisting => Self::Persisting,
        }
    }
}

impl From<protocol::TurnCompletion> for bridge::BridgeTurnCompletion {
    fn from(value: protocol::TurnCompletion) -> Self {
        match value { protocol::TurnCompletion::Normal => Self::Normal, protocol::TurnCompletion::InteractionRequested => Self::InteractionRequested }
    }
}

impl From<protocol::BudgetLimitSnapshot> for bridge::BridgeTurnBudgetLimit {
    fn from(value: protocol::BudgetLimitSnapshot) -> Self {
        Self { kind: match value.kind {
            protocol::BudgetLimitKind::ModelStep => bridge::BridgeTurnBudgetLimitKind::ModelStep,
            protocol::BudgetLimitKind::ToolCall => bridge::BridgeTurnBudgetLimitKind::ToolCall,
            protocol::BudgetLimitKind::Wait => bridge::BridgeTurnBudgetLimitKind::Wait,
            protocol::BudgetLimitKind::WallClock => bridge::BridgeTurnBudgetLimitKind::WallClock,
            protocol::BudgetLimitKind::AgentCount => bridge::BridgeTurnBudgetLimitKind::AgentCount,
            protocol::BudgetLimitKind::AgentDepth => bridge::BridgeTurnBudgetLimitKind::AgentDepth,
            protocol::BudgetLimitKind::Finalization => bridge::BridgeTurnBudgetLimitKind::Finalization,
        }, usage: bridge::BridgeTurnBudgetUsage { model_steps: value.usage.model_steps,
            tool_calls: value.usage.tool_calls, wait_calls: value.usage.wait_calls, elapsed_ms: value.usage.elapsed_ms } }
    }
}

impl From<protocol::ThreadStatus> for bridge::BridgeThreadStatus {
    fn from(value: protocol::ThreadStatus) -> Self {
        match value {
            protocol::ThreadStatus::Idle => Self::Idle,
            protocol::ThreadStatus::Queued => Self::Queued,
            protocol::ThreadStatus::Running => Self::Running,
            protocol::ThreadStatus::WaitingTool => Self::WaitingTool,
            protocol::ThreadStatus::WaitingInteraction => Self::WaitingInteraction,
            protocol::ThreadStatus::Cancelling => Self::Cancelling,
            protocol::ThreadStatus::Closing => Self::Closing,
            protocol::ThreadStatus::Closed => Self::Closed,
            protocol::ThreadStatus::Faulted => Self::Faulted,
        }
    }
}

impl From<protocol::ThreadActivityKind> for bridge::BridgeThreadActivityKind {
    fn from(value: protocol::ThreadActivityKind) -> Self {
        match value {
            protocol::ThreadActivityKind::Preparing => Self::Preparing,
            protocol::ThreadActivityKind::WaitingApi => Self::WaitingApi,
            protocol::ThreadActivityKind::Thinking => Self::Thinking,
            protocol::ThreadActivityKind::Responding => Self::Responding,
            protocol::ThreadActivityKind::Planning => Self::Planning,
            protocol::ThreadActivityKind::RunningTool => Self::RunningTool,
            protocol::ThreadActivityKind::AwaitingApproval => Self::AwaitingApproval,
            protocol::ThreadActivityKind::AwaitingInput => Self::AwaitingInput,
            protocol::ThreadActivityKind::Stopping => Self::Stopping,
        }
    }
}

impl From<protocol::studio::HistoryFault> for bridge::BridgeHistoryFault {
    fn from(value: protocol::studio::HistoryFault) -> Self {
        match value {
            protocol::studio::HistoryFault::QueueFull => Self::QueueFull,
            protocol::studio::HistoryFault::WriteFailed => Self::WriteFailed,
            protocol::studio::HistoryFault::WriterUnavailable => Self::WriterUnavailable,
            protocol::studio::HistoryFault::NoProgress => Self::NoProgress,
            protocol::studio::HistoryFault::CheckpointFailed => Self::CheckpointFailed,
            protocol::studio::HistoryFault::BlobFailed => Self::BlobFailed,
        }
    }
}

impl From<protocol::studio::ThreadStorageExecution> for bridge::BridgeThreadStorageExecution {
    fn from(value: protocol::studio::ThreadStorageExecution) -> Self {
        match value {
            protocol::studio::ThreadStorageExecution::Running => Self::Running,
            protocol::studio::ThreadStorageExecution::Pausing => Self::Pausing,
            protocol::studio::ThreadStorageExecution::Paused => Self::Paused,
        }
    }
}

impl From<protocol::ThreadRuntimeUsageState> for bridge::BridgeThreadRuntimeUsageState {
    fn from(value: protocol::ThreadRuntimeUsageState) -> Self {
        match value { protocol::ThreadRuntimeUsageState::Live => Self::Live, protocol::ThreadRuntimeUsageState::Authoritative => Self::Authoritative }
    }
}

impl From<protocol::CacheUsageSummary> for bridge::BridgeCacheUsageSummary {
    fn from(value: protocol::CacheUsageSummary) -> Self {
        Self { input_tokens: value.input_tokens, cache_read_tokens: value.cache_read_tokens,
            hit_rate: value.hit_rate, has_incomplete_usage: value.has_incomplete_usage }
    }
}

impl From<protocol::ModelContextUnavailable> for bridge::BridgeModelContextUnavailable {
    fn from(value: protocol::ModelContextUnavailable) -> Self {
        match value {
            protocol::ModelContextUnavailable::WindowUnknown => Self::WindowUnknown,
            protocol::ModelContextUnavailable::InvalidParameters => Self::InvalidParameters,
            protocol::ModelContextUnavailable::InputBudgetExhausted => Self::InputBudgetExhausted,
        }
    }
}

impl From<protocol::ModelContextAdjustment> for bridge::BridgeModelContextAdjustment {
    fn from(value: protocol::ModelContextAdjustment) -> Self {
        match value { protocol::ModelContextAdjustment::SafetyLimit => Self::SafetyLimit }
    }
}

impl From<protocol::PromptPrefixChangedReason> for bridge::BridgePromptPrefixChangedReason {
    fn from(value: protocol::PromptPrefixChangedReason) -> Self {
        match value {
            protocol::PromptPrefixChangedReason::Initial => Self::Initial,
            protocol::PromptPrefixChangedReason::PromptScopeChanged => Self::PromptScopeChanged,
            protocol::PromptPrefixChangedReason::AccountChanged => Self::AccountChanged,
            protocol::PromptPrefixChangedReason::ModelChanged => Self::ModelChanged,
            protocol::PromptPrefixChangedReason::BaseInstructionsChanged => Self::BaseInstructionsChanged,
            protocol::PromptPrefixChangedReason::GlobalInstructionsChanged => Self::GlobalInstructionsChanged,
            protocol::PromptPrefixChangedReason::ModeRoleChanged => Self::ModeRoleChanged,
            protocol::PromptPrefixChangedReason::SkillCatalogChanged => Self::SkillCatalogChanged,
            protocol::PromptPrefixChangedReason::WorkspaceInstructionsChanged => Self::WorkspaceInstructionsChanged,
            protocol::PromptPrefixChangedReason::RequestPropertiesChanged => Self::RequestPropertiesChanged,
            protocol::PromptPrefixChangedReason::FixedPrefixChanged => Self::FixedPrefixChanged,
            protocol::PromptPrefixChangedReason::ToolSchemaChanged => Self::ToolSchemaChanged,
            protocol::PromptPrefixChangedReason::ContextCompacted => Self::ContextCompacted,
            protocol::PromptPrefixChangedReason::ContextAppended => Self::ContextAppended,
            protocol::PromptPrefixChangedReason::ContextRecovered => Self::ContextRecovered,
        }
    }
}

impl From<protocol::AgentSessionPlanPhase> for bridge::BridgePlanPhase {
    fn from(value: protocol::AgentSessionPlanPhase) -> Self {
        match value {
            protocol::AgentSessionPlanPhase::Drafting => Self::Drafting,
            protocol::AgentSessionPlanPhase::AwaitingConfirmation => Self::AwaitingConfirmation,
            protocol::AgentSessionPlanPhase::RevisionRequested => Self::RevisionRequested,
            protocol::AgentSessionPlanPhase::Approved => Self::Approved,
        }
    }
}

impl From<protocol::WorkflowRunLifecycle> for bridge::BridgeWorkflowRunLifecycle {
    fn from(value: protocol::WorkflowRunLifecycle) -> Self {
        match value { protocol::WorkflowRunLifecycle::Active => Self::Active, protocol::WorkflowRunLifecycle::Terminal => Self::Terminal }
    }
}
