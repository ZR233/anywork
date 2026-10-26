//! Typed FRB projection of canonical Thread Item state machines.

use super::{BridgeTokenUsageSnapshot, BridgeTurnState};

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeThreadItem {
    pub id: String,
    pub thread_id: String,
    pub turn_id: String,
    pub ordinal: u64,
    pub revision: u64,
    pub created_at: i64,
    pub updated_at: i64,
    pub state: BridgeThreadItemState,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeThreadItemState {
    Raw {
        origin: BridgeRawItemOrigin,
        payloads: Vec<BridgeRawPayload>,
        notice: String,
        recorded_at: i64,
    },
    Text {
        channel: BridgeThreadTextChannel,
        text: String,
        attachments: Vec<BridgeThreadAttachment>,
        lifecycle: BridgeThreadContentLifecycle,
    },
    Thinking {
        summary: Vec<String>,
        content: Vec<String>,
        lifecycle: BridgeThreadContentLifecycle,
    },
    Tool {
        invocation: BridgeThreadToolInvocation,
        state: BridgeThreadToolState,
        /// Typed ordinary Q&A history the call asked for, when it asked one.
        user_input: Option<BridgeThreadUserInput>,
        /// Typed wait/sleep presentation when this call is a wait or sleep.
        wait: Option<Box<BridgeThreadWaitPresentation>>,
    },
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
pub struct BridgeRawPayload {
    pub format: String,
    pub version: u32,
    pub content: String,
}

/// Why one raw record exists; the payload list cannot tell the two apart.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeRawItemOrigin {
    Stored,
    RuntimeControl,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeSkillResourceBase {
    Directory { path: String },
    Url { url: String },
    Opaque { description: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeSkillActivationCause {
    Tool { tool_call_id: String },
    UserGesture { invocation_id: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadTextChannel {
    User,
    Commentary,
    Final,
    ParentAgent,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeThreadContentLifecycle {
    Streaming,
    Completed { completed_at: i64 },
    Failed { failed_at: i64, error: String },
    Cancelled { cancelled_at: i64, reason: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadAttachment {
    pub id: String,
    pub modality: crate::api::studio::types::BridgeAttachmentModality,
    pub media_type: String,
    pub filename: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub byte_size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadToolInvocation {
    pub task_id: Option<String>,
    pub tool_call_id: String,
    pub call_id: Option<String>,
    pub provider_item_id: Option<String>,
    pub name: String,
    pub arguments: String,
    pub working_directory: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeThreadToolState {
    Queued,
    Cancelling {
        streamed_output: String,
    },
    Interrupted {
        interrupted_at: i64,
        reason: String,
    },
    Started,
    Streaming,
    AwaitingApproval,
    Approved,
    Running {
        streamed_output: String,
    },
    Succeeded {
        completed_at: i64,
        output: BridgeThreadToolOutput,
    },
    Failed {
        failed_at: i64,
        failure: BridgeThreadToolFailure,
        output: Option<BridgeThreadToolOutput>,
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

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeThreadToolOutput {
    pub result: String,
    pub attachments: Vec<BridgeThreadAttachment>,
    pub output_artifacts_json: Vec<String>,
    pub exit_code: Option<i32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadToolFailure {
    pub kind: BridgeThreadToolFailureKind,
    pub message: String,
}

/// Shared typed wait/sleep presentation mirrored from the protocol DTO.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadWaitPresentation {
    pub intent: BridgeThreadWaitIntent,
    pub state: BridgeThreadWaitState,
    pub messages_ready: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeThreadWaitIntent {
    Events {
        targets: Vec<BridgeThreadWaitTarget>,
        timeout_ms: u64,
    },
    Timer {
        duration_ms: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadWaitTarget {
    pub task_id: String,
    pub tool_name: Option<String>,
    pub summary: Option<String>,
    pub summary_truncated: bool,
    pub status: Option<BridgeThreadWaitTargetStatus>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadWaitTargetStatus {
    Running,
    Succeeded,
    Failed,
    Cancelled,
    Interrupted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadWaitState {
    Waiting,
    Ready,
    TimedOut,
    Elapsed,
    Cancelled,
    Failed,
    Interrupted,
}

/// 一条普通问答的只读历史投影：问题、权威状态与已接受的回答。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadUserInput {
    pub interaction_id: String,
    pub questions: Vec<BridgeThreadUserInputQuestion>,
    pub state: BridgeThreadUserInputState,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadUserInputQuestion {
    pub id: String,
    pub header: String,
    pub question: String,
    pub is_other: bool,
    pub is_secret: bool,
    pub options: Vec<BridgeThreadUserInputOption>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadUserInputOption {
    pub label: String,
    pub description: String,
}

/// 只有 `resolved` 表示用户已回答；待回答与已取消各自是独立事实。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeThreadUserInputState {
    Pending,
    Resolved {
        /// 按原问题顺序排列的已接受回答。
        answers: Vec<BridgeThreadUserInputAnswer>,
    },
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadUserInputAnswer {
    pub question_id: String,
    /// 已接受的答案值；`redacted` 为真时这里必然为空。
    pub answers: Vec<String>,
    /// 敏感回答只公开“已回答/已隐藏”的状态，原值不在公开投影内。
    pub redacted: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadToolFailureKind {
    Execution,
    TimedOut,
    BudgetLimited,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadAgentIdentity {
    pub id: String,
    pub path: String,
    pub parent_path: Option<String>,
    pub role: String,
    pub task: String,
    pub depth: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeThreadAgentState {
    Queued,
    Running,
    Succeeded { completed_at: i64, summary: String },
    Denied { denied_at: i64, reason: String },
    Cancelled { cancelled_at: i64, reason: String },
    Failed { failed_at: i64, error: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeThreadInferenceState {
    Running,
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
