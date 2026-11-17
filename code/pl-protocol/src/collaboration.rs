//! 工具前端与产品宿主共同依赖的智能体协作、工作区边界、模型路由与基础状态错误契约。

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::{AgentId, SessionId, ThreadId};

/// 可跨宿主与工具边界传递的结构化领域错误。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct StateError {
    pub code: String,
    pub message: String,
    pub retryable: bool,
}

/// 会话成员的执行后端类别。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AgentBackendKind {
    #[default]
    Native,
    Acp,
}

/// 目录 owner 已解析的成员与默认执行上下文对应关系。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentThreadIdentity {
    pub session_id: SessionId,
    pub agent_id: AgentId,
    pub parent_agent_id: Option<AgentId>,
    pub thread_id: ThreadId,
}

/// 子 Agent 使用的工作区执行模式。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AgentWorkspaceMode {
    /// 不增加 Profile 级路径限制；宿主权限模式仍然生效。
    Unrestricted,
    /// 与父 Agent 共享项目目录，并可由 spawn 参数限制内置文件工具的写入目录。
    #[default]
    Directory,
    /// 在独立 Git worktree 中执行。
    Worktree,
    /// 工作区在 spawn 时采用被审代理的冻结工作区收据。
    Review,
}

impl AgentWorkspaceMode {
    pub const fn label(self) -> &'static str {
        match self {
            Self::Unrestricted => "unrestricted",
            Self::Directory => "directory",
            Self::Worktree => "worktree",
            Self::Review => "review",
        }
    }
}

/// Worktree 模式在 spawn 时冻结的 Git 资源收据。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentWorktreeSnapshot {
    pub repository_root: String,
    pub path: String,
    pub base_commit: String,
}

/// `review` 模式在 spawn 时冻结的被审代理身份。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentReviewTargetSnapshot {
    pub agent_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub feedback: Option<AgentReviewFeedback>,
    /// Absent on migrated receipts: old history never grants a new review baseline.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub baseline: Option<AgentReviewBaseline>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub enum AgentReviewFeedback {
    ToExecutor,
}

/// Host-proven delivery and admission watermarks, not model-authored disk version evidence.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentReviewBaseline {
    pub turn_id: String,
    pub input_id: Option<String>,
    pub terminal_sequence: u64,
    pub commit_sequence: u64,
    pub input_ordinal: u64,
    pub message_sequence: u64,
    pub consumed_messages: u64,
    pub wake_messages_through: u64,
    pub execution_sequence: u64,
    pub continuation_id: Option<String>,
}

/// 子 Agent 在创建时冻结的有效工作区边界。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentWorkspaceAssignmentSnapshot {
    pub mode: AgentWorkspaceMode,
    pub project_root: String,
    pub root: String,
    /// `None` 表示整个项目可写，空数组表示项目内只读。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub writable_paths: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub worktree: Option<AgentWorktreeSnapshot>,
    /// `review` 模式采用的工作区所属被审代理；其余模式为 `None`。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub review_target: Option<AgentReviewTargetSnapshot>,
}

/// 完整模型选择：账号、模型与可选 effort。
///
/// 同一份定义服务新建会话草稿与附件准入的 route、child 派发时的模型选择输入，以及目录/
/// 运行时投影的冻结模型身份摘要。它只描述「选了哪个模型」，不携带权限、工作区或 Profile。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NewThreadModelRoute {
    pub account_id: String,
    pub model_id: String,
    pub effort: Option<String>,
}

/// 根会话的子智能体分发模式。
///
/// 与 Thread Mode、工作区模式独立；创建后只读，主代理模型不受其影响。
#[derive(
    Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum DelegationMode {
    /// 使用 Profile 配置的固定路由（默认）。
    #[default]
    Profile,
    /// 派发时由主代理显式选择账号模型。
    Automatic,
}

/// 自动选模偏好；只通过主代理提示词表达，不是宿主排序算法。
#[derive(
    Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum DelegationPreference {
    Economy,
    #[default]
    Balanced,
    Fast,
}

/// 新会话默认分发选择；已有会话不回读该默认值。
#[derive(
    Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq, JsonSchema, ToSchema,
)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DelegationSettings {
    #[serde(default)]
    pub mode: DelegationMode,
    /// 固定模式中保留但不生效。
    #[serde(default)]
    pub preference: DelegationPreference,
}

crate::impl_labeled_enum!(
    DelegationMode,
    "DelegationMode",
    [
        DelegationMode::Profile => "profile",
        DelegationMode::Automatic => "automatic",
    ]
);

crate::impl_labeled_enum!(
    DelegationPreference,
    "DelegationPreference",
    [
        DelegationPreference::Economy => "economy",
        DelegationPreference::Balanced => "balanced",
        DelegationPreference::Fast => "fast",
    ]
);
