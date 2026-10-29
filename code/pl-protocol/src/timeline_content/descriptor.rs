//! 不含流式正文的产品读取描述；权威正文只通过带身份的字段交付。

use serde::{Deserialize, Serialize};

use crate::{
    BudgetLimitedTurnState, CancelledThreadAgent, CancelledThreadContent, CancelledThreadInference,
    CancelledTurnState, CompletedThreadContent, CompletedThreadInference, CompletedTurnState,
    DeniedThreadAgent, FailedThreadAgent, FailedThreadContent, FailedThreadInference,
    FailedTurnState, SucceededThreadAgent, ThreadAgentIdentity, ThreadAttachment,
    ThreadContextCompactionItem, ThreadFileItem, ThreadRawItemOrigin, ThreadSkillItem,
    ThreadTextChannel, ThreadToolFailure, ThreadWaitPresentation,
};

/// 条目的稳定身份与发布时已经确定的来源；完成序号独立于执行 ordinal。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineItemHeader {
    pub id: String,
    pub thread_id: String,
    pub turn_id: Option<String>,
    pub append_seq: u64,
    pub source_effect_seq: Option<u64>,
    pub sealed_at: Option<i64>,
}

/// 描述不含字段正文，也不以空正文的持久化值充当读取模型。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub enum TimelineDescriptor {
    Text(TimelineTextDescriptor),
    Thinking(TimelineThinkingDescriptor),
    Tool(TimelineToolDescriptor),
    Raw(TimelineRawDescriptor),
    Agent(TimelineAgentDescriptor),
    Turn(TimelineTurnDescriptor),
    Inference(TimelineInferenceDescriptor),
    Skill(ThreadSkillItem),
    File(ThreadFileItem),
    ContextCompaction(ThreadContextCompactionItem),
    Plan(TimelinePlanDescriptor),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineTextDescriptor {
    pub channel: ThreadTextChannel,
    pub attachments: Vec<ThreadAttachment>,
    pub outcome: TimelineContentOutcome,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineThinkingDescriptor {
    pub outcome: TimelineContentOutcome,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub enum TimelineContentOutcome {
    Completed(CompletedThreadContent),
    Failed(FailedThreadContent),
    Cancelled(CancelledThreadContent),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineAgentDescriptor {
    pub identity: ThreadAgentIdentity,
    pub outcome: TimelineAgentOutcome,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub enum TimelineAgentOutcome {
    Succeeded(SucceededThreadAgent),
    Denied(DeniedThreadAgent),
    Cancelled(CancelledThreadAgent),
    Failed(FailedThreadAgent),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineTurnDescriptor {
    pub input_id: Option<String>,
    pub outcome: TimelineTurnOutcome,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub enum TimelineTurnOutcome {
    Completed(CompletedTurnState),
    Failed(FailedTurnState),
    Cancelled(CancelledTurnState),
    BudgetLimited(BudgetLimitedTurnState),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineInferenceDescriptor {
    pub inference_id: String,
    pub model: String,
    pub outcome: TimelineInferenceOutcome,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub enum TimelineInferenceOutcome {
    Completed(CompletedThreadInference),
    Failed(FailedThreadInference),
    Cancelled(CancelledThreadInference),
}

/// 文档正文与自由反馈在 PlanDocument / PlanFeedback 字段中，遵守统一预览预算。
/// 迁移无法恢复的文档版本与摘要保持未知，不从当前计划补填。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelinePlanDescriptor {
    pub interaction_id: String,
    pub document_version: Option<u64>,
    pub content_hash: Option<String>,
    pub decision: TimelinePlanDecision,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TimelinePlanDecision {
    Approved,
    RevisionRequested,
    Cancelled,
    Resolved,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineRawDescriptor {
    pub origin: ThreadRawItemOrigin,
    pub payloads: Vec<TimelineRawPayloadDescriptor>,
    pub notice: String,
    pub recorded_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineRawPayloadDescriptor {
    pub format: String,
    pub version: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineToolDescriptor {
    pub invocation: TimelineToolInvocation,
    pub state: TimelineToolState,
    pub user_input: Option<TimelineUserInputDescriptor>,
    pub wait: Option<Box<ThreadWaitPresentation>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineToolInvocation {
    pub tool_call_id: String,
    pub call_id: Option<String>,
    pub provider_item_id: Option<String>,
    pub name: String,
    pub working_directory: Option<String>,
    pub task_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum TimelineToolState {
    /// 后台任务已经受理并返回的启动收据，最终结果使用另一个稳定完成身份。
    BackgroundStarted {
        started_at: i64,
    },
    Interrupted {
        interrupted_at: i64,
        reason: String,
    },
    Succeeded {
        completed_at: i64,
        output: TimelineToolOutputDescriptor,
    },
    Failed {
        failed_at: i64,
        failure: ThreadToolFailure,
        output: Option<TimelineToolOutputDescriptor>,
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineToolOutputDescriptor {
    pub attachments: Vec<ThreadAttachment>,
    pub exit_code: Option<i32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineUserInputDescriptor {
    /// 与 PendingInteraction.id 相同的产品 wire 身份；传输与客户端只作不透明值透传、比较。
    /// 核心及可靠历史仍使用本地身份，内部回填须解码并校验已知 Thread 归属。
    pub interaction_id: String,
    pub questions: Vec<TimelineQuestionDescriptor>,
    pub state: TimelineUserInputState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineQuestionDescriptor {
    pub id: String,
    pub is_other: bool,
    pub is_secret: bool,
    /// `None` 与 `Some(0)` 分别保留无选项与空选项列表的原始区别。
    pub option_count: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum TimelineUserInputState {
    Cancelled,
    Resolved {
        answers: Vec<TimelineAnswerDescriptor>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineAnswerDescriptor {
    pub question_id: String,
    pub answer_count: u32,
    pub redacted: bool,
}
