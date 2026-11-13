//! 会话计划的固定状态机、确认决策与模型上下文所需的领域快照。

mod machine;

pub use machine::MAX_FEEDBACK_BYTES;
pub use machine::{
    AgentSessionPlanConfirmationDecision, AgentSessionPlanError, AgentSessionPlanMachine,
    AgentSessionPlanResolveCommand, AgentSessionPlanRestartCommand, AgentSessionPlanSubmitCommand,
    MAX_PLAN_SESSION_STATE_BYTES, available_transitions, validate_plan,
    validate_session_state_size,
};

pub use pl_protocol::{
    AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, AgentSessionPlanAvailableTransition,
    AgentSessionPlanDocument, AgentSessionPlanMutationResponse, AgentSessionPlanOperation,
    AgentSessionPlanPhase, AgentSessionPlanResultCode, AgentSessionPlanSnapshot,
    AgentSessionPlanState, AgentSessionPlanTransitionActor, AgentSessionPlanTransitionError,
    AgentSessionPlanTransitionRecord, PureError, UserInputResolution,
};

mod confirmation;
pub use confirmation::confirmation_decision;
