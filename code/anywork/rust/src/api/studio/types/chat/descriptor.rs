//! Mechanical read descriptors; dynamic bodies exist only in identified content fields.
use super::super::{
    BridgeRawItemOrigin, BridgeSkillActivationCause, BridgeSkillResourceBase,
    BridgeThreadAgentIdentity, BridgeThreadAgentState, BridgeThreadAttachment,
    BridgeThreadContentLifecycle, BridgeThreadInferenceState, BridgeThreadTextChannel,
    BridgeThreadToolFailure, BridgeThreadWaitPresentation, BridgeTurnState,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineItemHeader {
    pub id: String,
    pub thread_id: String,
    pub turn_id: String,
    pub ordinal: u64,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeTimelineDescriptor {
    Text(BridgeTimelineTextDescriptor),
    Thinking(BridgeTimelineThinkingDescriptor),
    Tool(Box<BridgeTimelineToolDescriptor>),
    Raw(BridgeTimelineRawDescriptor),
    Agent {
        identity: BridgeThreadAgentIdentity,
        state: BridgeThreadAgentState,
    },
    Turn {
        state: BridgeTurnState,
        input_id: Option<String>,
    },
    Inference {
        inference_id: String,
        model: String,
        state: BridgeThreadInferenceState,
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
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineTextDescriptor {
    pub channel: BridgeThreadTextChannel,
    pub attachments: Vec<BridgeThreadAttachment>,
    pub lifecycle: BridgeThreadContentLifecycle,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineThinkingDescriptor {
    pub lifecycle: BridgeThreadContentLifecycle,
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
    Queued,
    Cancelling,
    Started,
    Streaming,
    AwaitingApproval,
    Approved,
    Running,
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
    Pending,
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
