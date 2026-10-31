//! Mechanical read descriptors; dynamic bodies exist only in identified content fields.
use super::super::{
    BridgeRawItemOrigin, BridgeSkillActivationCause, BridgeSkillResourceBase,
    BridgeThreadAgentIdentity, BridgeThreadAttachment, BridgeThreadTextChannel,
    BridgeThreadToolFailure, BridgeThreadWaitPresentation, BridgeTokenUsageSnapshot,
    BridgeTurnBudgetLimit, BridgeTurnCancellationCause, BridgeTurnCompletion, BridgeTurnFailureDto,
    BridgeTurnRolloverOutcome,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineItemHeader {
    pub id: String,
    pub thread_id: String,
    pub turn_id: Option<String>,
    pub append_seq: u64,
    pub source_effect_seq: Option<u64>,
    pub sealed_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeTimelineDescriptor {
    Text(BridgeTimelineTextDescriptor),
    Thinking(BridgeTimelineThinkingDescriptor),
    Tool(Box<BridgeTimelineToolDescriptor>),
    Raw(BridgeTimelineRawDescriptor),
    Agent {
        identity: BridgeThreadAgentIdentity,
        outcome: BridgeTimelineAgentOutcome,
    },
    Turn {
        outcome: BridgeTimelineTurnOutcome,
        input_id: Option<String>,
    },
    Inference {
        inference_id: String,
        model: String,
        outcome: BridgeTimelineInferenceOutcome,
    },
    Skill {
        name: String,
        source: String,
        provider_id: String,
        resource_base: BridgeSkillResourceBase,
        cause: BridgeSkillActivationCause,
        activated_at: i64,
    },
    File {
        path: String,
        media_type: Option<String>,
        completed_at: i64,
    },
    ContextCompaction {
        before_tokens: Option<u64>,
        after_tokens: Option<u64>,
        compacted_at: i64,
    },
    Plan {
        interaction_id: String,
        document_version: Option<u64>,
        content_hash: Option<String>,
        decision: BridgeTimelinePlanDecision,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineTextDescriptor {
    pub channel: BridgeThreadTextChannel,
    pub attachments: Vec<BridgeThreadAttachment>,
    pub outcome: BridgeTimelineContentOutcome,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineThinkingDescriptor {
    pub outcome: BridgeTimelineContentOutcome,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTimelineContentOutcome {
    Completed { completed_at: i64 },
    Failed { failed_at: i64, error: String },
    Cancelled { cancelled_at: i64, reason: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTimelineAgentOutcome {
    Succeeded { completed_at: i64, summary: String },
    Denied { denied_at: i64, reason: String },
    Failed { failed_at: i64, error: String },
    Cancelled { cancelled_at: i64, reason: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTimelineInferenceOutcome {
    Completed {
        completed_at: i64,
        usage: BridgeTokenUsageSnapshot,
    },
    Failed {
        failed_at: i64,
        error: String,
    },
    Cancelled {
        cancelled_at: i64,
        reason: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTimelineTurnOutcome {
    Completed {
        started_at: Option<i64>,
        completed_at: i64,
        completion: BridgeTurnCompletion,
    },
    Cancelled {
        started_at: Option<i64>,
        requested_at: i64,
        completed_at: i64,
        cause: BridgeTurnCancellationCause,
    },
    Failed {
        started_at: Option<i64>,
        completed_at: i64,
        failure: BridgeTurnFailureDto,
    },
    BudgetLimited {
        started_at: Option<i64>,
        completed_at: i64,
        limit: BridgeTurnBudgetLimit,
        rollover: BridgeTurnRolloverOutcome,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeTimelinePlanDecision {
    Approved,
    RevisionRequested,
    Cancelled,
    Resolved,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineRawDescriptor {
    pub origin: BridgeRawItemOrigin,
    pub payloads: Vec<BridgeTimelineRawPayloadDescriptor>,
    pub notice: String,
    pub recorded_at: i64,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineRawPayloadDescriptor {
    pub format: String,
    pub version: u32,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeTimelineToolDescriptor {
    pub invocation: BridgeTimelineToolInvocation,
    pub state: BridgeTimelineToolState,
    pub user_input: Option<BridgeTimelineUserInputDescriptor>,
    pub wait: Option<Box<BridgeThreadWaitPresentation>>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineToolInvocation {
    pub tool_call_id: String,
    pub call_id: Option<String>,
    pub provider_item_id: Option<String>,
    pub name: String,
    pub working_directory: Option<String>,
    pub task_id: Option<String>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTimelineToolState {
    BackgroundStarted {
        started_at: i64,
    },
    Interrupted {
        interrupted_at: i64,
        reason: String,
    },
    Succeeded {
        completed_at: i64,
        output: BridgeTimelineToolOutputDescriptor,
    },
    Failed {
        failed_at: i64,
        failure: BridgeThreadToolFailure,
        output: Option<BridgeTimelineToolOutputDescriptor>,
    },
    Denied {
        denied_at: i64,
        reason: String,
    },
    Cancelled {
        cancelled_at: i64,
        reason: String,
    },
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineToolOutputDescriptor {
    pub attachments: Vec<BridgeThreadAttachment>,
    pub exit_code: Option<i32>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineUserInputDescriptor {
    pub interaction_id: String,
    pub questions: Vec<BridgeTimelineQuestionDescriptor>,
    pub state: BridgeTimelineUserInputState,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineQuestionDescriptor {
    pub id: String,
    pub is_other: bool,
    pub is_secret: bool,
    pub option_count: Option<u32>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTimelineUserInputState {
    Cancelled,
    Resolved {
        answers: Vec<BridgeTimelineAnswerDescriptor>,
    },
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineAnswerDescriptor {
    pub question_id: String,
    pub answer_count: u32,
    pub redacted: bool,
}
