//! 当前完成 payload 的私有编码结构，不构成第二套公开聊天 DTO。
//!
//! 仅在可靠完成时序列化一次；历史读取透传已冻结的 JSON，不反序列化这些类型。
//! 发布过的旧格式解码独立留在 storage 的迁移边界，不能借用本模块。

use pl_protocol::{
    BudgetLimitedTurnState, CancelledThreadAgent, CancelledThreadContent, CancelledThreadInference,
    CancelledTurnState, CompletedThreadContent, CompletedThreadInference, CompletedTurnState,
    DeniedThreadAgent, FailedThreadAgent, FailedThreadContent, FailedThreadInference,
    FailedTurnState, SucceededThreadAgent, ThreadAgentIdentity, ThreadAttachment,
    ThreadContextCompactionItem, ThreadFileItem, ThreadRawItemOrigin, ThreadSkillItem,
    ThreadTextChannel, ThreadToolFailure, ThreadWaitPresentation,
};
use serde::Serialize;

#[derive(Serialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub(super) enum ItemDescriptor {
    Text(TextDescriptor),
    Thinking(ThinkingDescriptor),
    Tool(ToolDescriptor),
    Raw(RawDescriptor),
    Agent(AgentDescriptor),
    Turn(TurnDescriptor),
    Inference(InferenceDescriptor),
    Skill(ThreadSkillItem),
    File(ThreadFileItem),
    ContextCompaction(ThreadContextCompactionItem),
    Plan(PlanDescriptor),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct TextDescriptor {
    pub channel: ThreadTextChannel,
    pub attachments: Vec<ThreadAttachment>,
    pub outcome: ContentOutcome,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ThinkingDescriptor {
    pub outcome: ContentOutcome,
}

#[derive(Serialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub(super) enum ContentOutcome {
    Completed(CompletedThreadContent),
    Failed(FailedThreadContent),
    Cancelled(CancelledThreadContent),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct AgentDescriptor {
    pub identity: ThreadAgentIdentity,
    pub outcome: AgentOutcome,
}

#[derive(Serialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub(super) enum AgentOutcome {
    Succeeded(SucceededThreadAgent),
    Denied(DeniedThreadAgent),
    Cancelled(CancelledThreadAgent),
    Failed(FailedThreadAgent),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct TurnDescriptor {
    pub input_id: Option<String>,
    pub outcome: TurnOutcome,
}

#[derive(Serialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub(super) enum TurnOutcome {
    Completed(CompletedTurnState),
    Failed(FailedTurnState),
    Cancelled(CancelledTurnState),
    BudgetLimited(BudgetLimitedTurnState),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct InferenceDescriptor {
    pub inference_id: String,
    pub model: String,
    pub outcome: InferenceOutcome,
}

#[derive(Serialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub(super) enum InferenceOutcome {
    Completed(CompletedThreadInference),
    Failed(FailedThreadInference),
    Cancelled(CancelledThreadInference),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct PlanDescriptor {
    pub interaction_id: String,
    pub document_version: Option<u64>,
    pub content_hash: Option<String>,
    pub decision: PlanDecision,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum PlanDecision {
    Approved,
    RevisionRequested,
    Cancelled,
    Resolved,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct RawDescriptor {
    pub origin: ThreadRawItemOrigin,
    pub payloads: Vec<RawPayloadDescriptor>,
    pub notice: String,
    pub recorded_at: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct RawPayloadDescriptor {
    pub format: String,
    pub version: u32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ToolDescriptor {
    pub invocation: ToolInvocation,
    pub state: ToolState,
    pub user_input: Option<UserInputDescriptor>,
    pub wait: Option<Box<ThreadWaitPresentation>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ToolInvocation {
    pub tool_call_id: String,
    pub call_id: Option<String>,
    pub provider_item_id: Option<String>,
    pub name: String,
    pub working_directory: Option<String>,
    pub task_id: Option<String>,
}

#[derive(Serialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(super) enum ToolState {
    Interrupted {
        interrupted_at: i64,
        reason: String,
    },
    Succeeded {
        completed_at: i64,
        output: ToolOutputDescriptor,
    },
    Failed {
        failed_at: i64,
        failure: ThreadToolFailure,
        output: Option<ToolOutputDescriptor>,
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

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ToolOutputDescriptor {
    pub attachments: Vec<ThreadAttachment>,
    pub exit_code: Option<i32>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct UserInputDescriptor {
    pub interaction_id: String,
    pub questions: Vec<QuestionDescriptor>,
    pub state: UserInputState,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct QuestionDescriptor {
    pub id: String,
    pub is_other: bool,
    pub is_secret: bool,
    /// 缺少选项与显式空选项列表保持区别。
    pub option_count: Option<u32>,
}

#[derive(Serialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(super) enum UserInputState {
    Cancelled,
    Resolved { answers: Vec<AnswerDescriptor> },
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct AnswerDescriptor {
    pub question_id: String,
    pub answer_count: u32,
    pub redacted: bool,
}
