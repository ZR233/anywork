use pl_protocol::MessagePresentation;

/// AgentSession Plan 注册选项；不包含或暴露 session-local Arc handle。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AgentSessionPlanOptions {
    submitted_plan_presentation: MessagePresentation,
}

impl Default for AgentSessionPlanOptions {
    fn default() -> Self {
        Self {
            submitted_plan_presentation: MessagePresentation::Hidden,
        }
    }
}

impl AgentSessionPlanOptions {
    /// 预设 Plan confirmation 决议后完整 Plan 用户消息的 GUI presentation。
    pub const fn with_submitted_plan_presentation(
        mut self,
        presentation: MessagePresentation,
    ) -> Self {
        self.submitted_plan_presentation = presentation;
        self
    }

    pub const fn submitted_plan_presentation(&self) -> MessagePresentation {
        self.submitted_plan_presentation
    }
}
