use serde::{Deserialize, Serialize};

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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
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

/// Agent Profile 在子会话创建时冻结的可执行快照。
///
/// `profile_id` 同时作为运行时角色标识；account/model/effort 与系统指令不再
/// 随磁盘配置变化，保证已启动 Agent 的行为可复现。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentProfileSnapshot {
    pub profile_id: String,
    pub display_name: String,
    pub description: String,
    pub when_to_use: String,
    pub system_instructions: String,
    pub account_id: String,
    pub model_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    pub source: String,
    pub revision: String,
    pub content_hash: String,
    #[serde(default)]
    pub system: bool,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub workspace_mode: AgentWorkspaceMode,
}

const fn default_true() -> bool {
    true
}
