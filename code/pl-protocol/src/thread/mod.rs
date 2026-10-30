pub mod mode;

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::{
    InteractionRequest, McpHealthSnapshot, RuntimeCostAmount, ThreadItem, ThreadModeId,
    TodoListSnapshot, Turn,
};

pub const THREAD_SCHEMA_VERSION: u32 = 15;

/// Timeline 游标 token 的版本号。
///
/// 读取水位、数据库身份或 ordinal 语义发生变化时递增；客户端持有的旧版本游标会被
/// 明确拒绝并要求回到数据库重新读取，而不是回落到猜测位置。
pub const TIMELINE_CURSOR_VERSION: u32 = 1;

/// Timeline 游标的 opaque 前缀；item identity 不会以它开头，因此解码是确定性的。
const TIMELINE_CURSOR_PREFIX: &str = "tlc1.";

/// 会话级工作区模式：Project 根目录，或从 Project Git 仓库 `HEAD` 派生的独立 checkout。
///
/// 它是 Thread 的 canonical 产品事实，在创建会话时确定；与 Profile 的
/// [`crate::AgentWorkspaceMode`] 是两条语义轴：本模式决定会话工作区在哪里，
/// Profile 模式决定 child 相对会话工作区的隔离方式。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ThreadWorkspaceMode {
    /// 使用 Project 根目录（默认）。
    #[default]
    Local,
    /// 从 Project 的 Git 仓库 `HEAD` 派生独立 worktree 并在其中工作。
    Worktree,
}

impl ThreadWorkspaceMode {
    /// Canonical 稳定标签，也是 `threads.workspace_mode` 的持久化值。
    pub const fn label(self) -> &'static str {
        match self {
            Self::Local => "local",
            Self::Worktree => "worktree",
        }
    }

    /// 解析 canonical 标签；未知标签明确失败，不默认为 `local`。
    pub fn from_label(label: &str) -> Result<Self, crate::UnknownLabelError> {
        match label {
            "local" => Ok(Self::Local),
            "worktree" => Ok(Self::Worktree),
            other => Err(crate::UnknownLabelError::new("ThreadWorkspaceMode", other)),
        }
    }
}

/// 一个 agent 独占的对话和执行队列。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Thread {
    pub id: String,
    pub workspace_id: String,
    pub title: String,
    pub mode: ThreadModeId,
    /// 会话工作区模式；缺失的旧编码按默认 `local` 解码。
    #[serde(default)]
    pub workspace_mode: ThreadWorkspaceMode,
    /// 创建时确定的子智能体分发模式；缺失的旧编码按固定 Profile 解码。
    #[serde(default)]
    pub delegation_mode: crate::DelegationMode,
    /// 创建时确定的自动选模偏好；固定模式保留但不生效。
    #[serde(default)]
    pub delegation_preference: crate::DelegationPreference,
    /// child 创建时冻结的最终模型身份摘要。
    ///
    /// 值只取创建时冻结的绑定，供智能体列表直接展示；root 或无法证明的历史条目保持
    /// `None`，不从当前 Profile、默认设置或别名补造。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub frozen_model: Option<crate::studio::NewThreadModelRoute>,
    /// 会话对外唯一 canonical 工作区地址；缺失的旧编码按空串解码。
    #[serde(default)]
    pub workspace_path: String,
    pub root_thread_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_thread_id: Option<String>,
    pub role: String,
    pub agent_path: String,
    pub status: ThreadStatus,
    pub created_at: i64,
    pub updated_at: i64,
    /// 服务端最近一次成功受理用户消息的时间（Unix 秒）。
    ///
    /// 仅由用户输入的成功受理推进：已接受的排队输入计入，拒绝的输入、代理通知、
    /// 系统注入、工具结果及恢复重放均不计入。缺失表示尚无已受理的用户消息（例如
    /// 旧目录迁移后的未回填会话），列表排序按 `created_at` 回落；`updated_at` 保持
    /// 普通更新语义，不能替代该字段排序。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_user_message_at: Option<i64>,
    #[serde(default)]
    pub archived: bool,
}

impl Thread {
    pub fn placeholder(id: impl Into<String>) -> Self {
        let id = id.into();
        Self {
            workspace_id: String::new(),
            title: String::new(),
            mode: ThreadModeId::simple(),
            workspace_mode: ThreadWorkspaceMode::Local,
            delegation_mode: Default::default(),
            delegation_preference: Default::default(),
            frozen_model: None,
            workspace_path: String::new(),
            root_thread_id: id.clone(),
            parent_thread_id: None,
            role: String::new(),
            agent_path: String::new(),
            status: ThreadStatus::Idle,
            created_at: 0,
            updated_at: 0,
            last_user_message_at: None,
            archived: false,
            id,
        }
    }

    /// 会话目录排序键：最近用户消息时间，缺失时回落到创建时间。
    ///
    /// 目录冷分页、搜索与 GUI 会话列表共用同一降序键；同秒由调用方以 ID 破平。
    pub fn directory_sort_time(&self) -> i64 {
        self.last_user_message_at.unwrap_or(self.created_at)
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ThreadStatus {
    Idle,
    Queued,
    Running,
    WaitingTool,
    WaitingInteraction,
    Cancelling,
    Closing,
    Closed,
    Faulted,
}

/// Timeline 记录是否仍属于后续模型的有效上下文。
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ThreadContextDisposition {
    #[default]
    Active,
    RolledBack,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadSnapshot {
    pub schema_version: u32,
    pub revision: u64,
    pub thread: Thread,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub active_turn: Option<Turn>,
    #[serde(default)]
    pub interactions: Vec<InteractionRequest>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub runtime: Option<ThreadRuntimeSnapshot>,
    /// 当前执行活动的权威小摘要；`None` 表示当前没有活动。
    ///
    /// 它是独立于 Timeline 内容的 typed 投影：内容只决定有哪些历史条目，活动只描述当前
    /// 在做什么。完整正文不在快照里，按活动身份按需读取。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub activity: Option<crate::ThreadActivity>,
    /// Thread 的存储状态；`None` 表示该投影没有可报告的存储事实（不是“健康”）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub storage: Option<crate::ThreadStorageState>,
}

impl ThreadSnapshot {
    pub fn empty(thread_id: impl Into<String>) -> Self {
        Self {
            schema_version: THREAD_SCHEMA_VERSION,
            revision: 0,
            thread: Thread::placeholder(thread_id),
            active_turn: None,
            interactions: Vec::new(),
            runtime: None,
            activity: None,
            storage: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadRuntimeSnapshot {
    pub thread_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_route: Option<ThreadModelRouteSnapshot>,
    pub usage: ThreadRuntimeUsage,
    /// Best-effort usage for the currently running attempt. Durable totals remain in `usage`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub live_usage: Option<ThreadRuntimeLiveUsage>,
    #[serde(default)]
    pub turn_completion_tokens: u64,
    /// 与 `turn_completion_tokens` 成对的总响应耗时；缺失计时保持 0 且不参与速度汇总。
    #[serde(default)]
    pub turn_response_millis: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub todo: Option<TodoListSnapshot>,
    #[serde(default)]
    pub active_skills: Vec<String>,
    #[serde(default)]
    pub active_mcp_servers: Vec<String>,
    #[serde(default)]
    pub active_lsp_servers: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub progress: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mcp_health: Option<McpHealthSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workflow: Option<crate::WorkflowRuntimeSnapshot>,
    /// 派生自 canonical `studio.plan` Thread 扩展，仅供 GUI 只读展示。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub plan: Option<crate::AgentSessionPlanRuntimeSnapshot>,
    /// 该会话当前拥有的执行身份与阶段；`None` 表示没有当前执行。
    ///
    /// 停止命令的目标来自这里，而不是 `activeTurn` 的可空投影：准备、等待保存、等待准入与
    /// 清理阶段同样有身份，轮次编号只是它在进入轮次后补充的事实。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub execution: Option<crate::AgentExecution>,
    /// 该会话当前仍然欠着的继续点；`None` 表示没有可继续的工作。
    ///
    /// 继续命令的 `expectedContinuationId` 只能来自这里：它是执行事实的投影，客户端不能猜、
    /// 不能本地生成。`claimed` 为真表示已有操作认领该点（继续已受理、可能仍在准备）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation: Option<crate::ContinuationView>,
    pub updated_at: i64,
}

/// Whether a runtime usage observation is still a preview or a terminal fact.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ThreadRuntimeUsageState {
    Live,
    Authoritative,
}

/// Typed, non-durable usage observation for one running model attempt.
///
/// A missing counter is explicitly represented by `None`; it is not a zero estimate. The sequence
/// is monotonic within the stable `(turn_id, attempt_id)` identity and lets consumers reject stale
/// observations after best-effort coalescing.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadRuntimeLiveUsage {
    pub turn_id: String,
    pub attempt_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completion_tokens: Option<u64>,
    /// 本次 attempt 起点的单调总响应耗时；透明重试换代时从头重新计时。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_millis: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_context_tokens: Option<u64>,
    pub state: ThreadRuntimeUsageState,
    pub observation_sequence: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadModelRouteSnapshot {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bot_id: Option<String>,
    pub account_id: String,
    pub model_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    pub revision: u64,
    pub available: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unavailable_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadRuntimeUsage {
    pub diagnostics: crate::ThreadUsageDiagnostics,
    #[serde(default)]
    pub has_incomplete_usage: bool,
    pub model_id: String,
    /// Effective context window of the newest request binding; `None` stays unknown.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context_window: Option<u64>,
    /// Capacity the bound model itself declares; never inferred from `context_window`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_context_window: Option<u64>,
    /// Finally resolved automatic compaction threshold of the newest request binding.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auto_compact_limit: Option<u64>,
    pub latest_context_tokens: u64,
    pub prompt_tokens: u64,
    pub completion_tokens: u64,
    pub cached_prompt_tokens: u64,
    #[serde(default)]
    pub cache_write_tokens: u64,
    #[serde(default)]
    pub reasoning_tokens: u64,
    #[serde(default)]
    pub inference_count: u64,
    pub total_tokens: u64,
    #[serde(default)]
    pub cache_usage: CacheUsageSummary,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub estimated_costs: Vec<RuntimeCostAmount>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub estimated_cache_savings: Vec<RuntimeCostAmount>,
    #[serde(default)]
    pub has_unpriced_usage: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt_generation: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt_cache_policy: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prefix_changed_reason: Option<crate::PromptPrefixChangedReason>,
    pub updated_at: i64,
}

/// 由已报告输入样本累计出的 prompt cache 有效用量。
///
/// 只有 input 与 cache read 同时报告、且 cache read（连同可选的 cache
/// write）不超过 input 的样本才计入累计；缺失或矛盾的样本只置
/// `has_incomplete_usage`，不改变累计值。命中率分母是累计 input，因为它
/// 已经包含 cache read，未知不等于真实零命中。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CacheUsageSummary {
    pub sample_count: u64,
    pub legacy_sample_count_unknown: bool,
    /// 计入累计的有效样本 input 总量，已包含 cache read。
    #[serde(default)]
    pub input_tokens: u64,
    /// 计入累计的有效样本 cache read 总量。
    #[serde(default)]
    pub cache_read_tokens: u64,
    /// `cache_read_tokens / input_tokens`；累计 input 为零时为 `None`。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hit_rate: Option<f64>,
    /// 是否存在被排除在累计之外的缺失或矛盾样本。
    #[serde(default)]
    pub has_incomplete_usage: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "type"
)]
pub enum ThreadNotification {
    TurnStarted {
        turn: Turn,
    },
    TurnUpdated {
        turn: Turn,
    },
    TurnCompleted {
        turn: Turn,
    },
    InteractionChanged {
        interaction: Box<InteractionRequest>,
    },
    ThreadRuntimeUpdated {
        runtime: Box<ThreadRuntimeSnapshot>,
    },
    /// 当前执行活动变化；`None` 表示当前没有活动（Turn 已结束或尚未开始）。
    ///
    /// 帧只在活动实际变化时发出，并只携带小型 typed 摘要与身份；完整正文按活动身份按需读取。
    ActivityChanged {
        activity: Option<Box<crate::ThreadActivity>>,
    },
    /// Thread 存储状态变化；`None` 表示当前没有可报告的存储事实（未知，不是“健康”）。
    ///
    /// 帧只在存储状态实际变化时发出，携带 typed 故障类别、代数、水位与恢复阶段——故障类别来自
    /// 协调器的 typed 值，绝不从错误文本推断。快照首帧已带权威存储状态，后续帧只在它变化时补发，
    /// 因此正文更新不会额外走一遍状态流。
    StorageChanged {
        storage: Option<Box<crate::ThreadStorageState>>,
    },
    Lagged {
        dropped: u64,
    },
}

/// 一条实时增量通知的封套。
///
/// `epoch` 是生产端一次连续广播生命周期的标识：重订阅、owner 重建或数据库重同步后
/// 递增，客户端据此丢弃旧生命周期的迟到帧。`base_revision` 是本通知之前的状态水位，
/// `revision` 是应用本通知之后的状态水位；`base_revision != 上一条 revision`（或两帧间
/// `revision` 出现跳变）即表示缺口，客户端必须重同步而不是继续拼接增量。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadNotificationEnvelope {
    pub thread_id: String,
    pub epoch: u64,
    pub base_revision: u64,
    pub revision: u64,
    pub emitted_at: i64,
    pub notification: ThreadNotification,
}

impl ThreadNotificationEnvelope {
    /// 用生产端水位构造通知；`emitted_at` 由调用方的时钟提供。
    pub fn new(
        thread_id: impl Into<String>,
        epoch: u64,
        base_revision: u64,
        revision: u64,
        emitted_at: i64,
        notification: ThreadNotification,
    ) -> Self {
        Self {
            thread_id: thread_id.into(),
            epoch,
            base_revision,
            revision,
            emitted_at,
            notification,
        }
    }

    /// 本通知是否可由客户端接在上一条 `revision` 之后拼接。
    ///
    /// 同 epoch 且 `base_revision` 恰好等于客户端已知水位才连续；否则是缺口。
    pub fn continues_from(&self, epoch: u64, last_revision: u64) -> bool {
        self.epoch == epoch && self.base_revision == last_revision
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "type"
)]
pub enum ThreadSubscriptionUpdate {
    Snapshot {
        snapshot: Box<ThreadSnapshot>,
    },
    Notification {
        notification: Box<ThreadNotificationEnvelope>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadSubscriptionRequest {
    pub thread_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadTurnPage {
    pub turns: Vec<ThreadTurnHistory>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub next_cursor: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadTurnHistory {
    pub turn: Turn,
    pub items: Vec<ThreadItem>,
    #[serde(default)]
    pub context_disposition: ThreadContextDisposition,
}

/// 版本化、自校验的 Timeline 游标。
///
/// Turn 历史沿用这套 durable 游标：它绑定 Thread 身份、history 数据库身份、条目 ordinal、
/// 条目 identity 与读取时的 applied write sequence。Timeline 正文本身改用
/// [`crate::timeline_content::TimelinePageCursor`]，后者只表达严格 `(ordinal, identity)` 边界，
/// 不要求该条目已落盘。
///
/// 游标绑定 Thread 身份、history 数据库身份、条目 ordinal、条目 identity 与读取时的
/// applied write sequence。任何一项在当前数据库上不成立（Thread 不符、数据库被重建、
/// 水位回退）都必须拒绝，避免把游标当成"附近某条"的猜测位置。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineCursor {
    pub version: u32,
    pub thread_id: String,
    pub database_id: String,
    pub ordinal: u64,
    pub item_id: String,
    pub applied_write_sequence: u64,
}

impl TimelineCursor {
    /// 构造当前版本游标。
    pub fn new(
        thread_id: impl Into<String>,
        database_id: impl Into<String>,
        ordinal: u64,
        item_id: impl Into<String>,
        applied_write_sequence: u64,
    ) -> Self {
        Self {
            version: TIMELINE_CURSOR_VERSION,
            thread_id: thread_id.into(),
            database_id: database_id.into(),
            ordinal,
            item_id: item_id.into(),
            applied_write_sequence,
        }
    }

    /// 编码为可跨 wire 传输的 opaque token。
    ///
    /// # Panics
    /// 仅在内部 JSON 编码失败时 panic；字段均为可序列化的原始类型。
    pub fn encode(&self) -> String {
        let payload = serde_json::to_string(self).expect("timeline cursor is serializable");
        format!("{TIMELINE_CURSOR_PREFIX}{payload}")
    }

    /// 解析 opaque token；非游标输入（例如原始 item identity）返回 `None`。
    pub fn decode(token: &str) -> Option<Self> {
        let payload = token.strip_prefix(TIMELINE_CURSOR_PREFIX)?;
        let cursor: Self = serde_json::from_str(payload).ok()?;
        (cursor.version == TIMELINE_CURSOR_VERSION).then_some(cursor)
    }
}

/// Turn metadata is independent of whether its admission item is in this page.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TimelineTurn {
    pub turn: Turn,
    pub last_item_id: String,
    pub context_disposition: ThreadContextDisposition,
}

crate::impl_labeled_enum!(
    ThreadStatus,
    "ThreadStatus",
    [
        ThreadStatus::Idle => "idle",
        ThreadStatus::Queued => "queued",
        ThreadStatus::Running => "running",
        ThreadStatus::WaitingTool => "waitingTool",
        ThreadStatus::WaitingInteraction => "waitingInteraction",
        ThreadStatus::Cancelling => "cancelling",
        ThreadStatus::Closing => "closing",
        ThreadStatus::Closed => "closed",
        ThreadStatus::Faulted => "faulted",
    ]
);
