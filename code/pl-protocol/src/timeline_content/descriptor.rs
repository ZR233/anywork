//! 不含流式正文的产品读取描述；权威正文只通过带身份的字段交付。

use serde::{Deserialize, Serialize};

use crate::{
    ThreadAgentItem, ThreadAttachment, ThreadContentLifecycle, ThreadContextCompactionItem,
    ThreadFileItem, ThreadInferenceItem, ThreadRawItemOrigin, ThreadSkillItem, ThreadTextChannel,
    ThreadToolFailure, ThreadTurnItem, ThreadWaitPresentation,
};

/// 条目的稳定身份、当前轮次关联与权威时间。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineItemHeader {
    pub id: String,
    pub thread_id: String,
    pub turn_id: String,
    pub ordinal: u64,
    pub created_at: i64,
    pub updated_at: i64,
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
    Agent(ThreadAgentItem),
    Turn(ThreadTurnItem),
    Inference(ThreadInferenceItem),
    Skill(ThreadSkillItem),
    File(ThreadFileItem),
    ContextCompaction(ThreadContextCompactionItem),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineTextDescriptor {
    pub channel: ThreadTextChannel,
    pub attachments: Vec<ThreadAttachment>,
    pub lifecycle: ThreadContentLifecycle,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineThinkingDescriptor {
    pub lifecycle: ThreadContentLifecycle,
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
    Pending,
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
