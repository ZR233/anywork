use serde::{Deserialize, Serialize};

/// 会话目录事实：`catalog.toml` `sessions` 记录的运行期形态。
///
/// 会话级字段（标题、排序时间、归档、工作区与分发设置）在此唯一归属；成员事实见
/// [`AgentDirectoryRecord`]。它由目录 owner 提交，查询侧只读，不构成第二个可写源。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct SessionDirectoryRecord {
    /// 业务会话 ID；由根 Thread 的既有 ID 字节迁移而来，原值不变。
    pub(in crate::studio) session_id: String,
    /// 会话主成员 ID；首版与 `session_id` 同字节，类型与字段语义分开。
    pub(in crate::studio) root_agent_id: String,
    pub(in crate::studio) workspace_id: String,
    /// 会话标题；不被子成员的任务摘要覆盖。
    pub(in crate::studio) title: String,
    pub(in crate::studio) mode: pl_protocol::ThreadModeId,
    pub(in crate::studio) workspace_mode: pl_protocol::ThreadWorkspaceMode,
    pub(in crate::studio) delegation_mode: pl_protocol::DelegationMode,
    pub(in crate::studio) delegation_preference: pl_protocol::DelegationPreference,
    pub(in crate::studio) workspace_path: String,
    pub(in crate::studio) created_at: i64,
    pub(in crate::studio) updated_at: i64,
    /// 服务端最近一次成功受理用户消息的时间；缺失即尚未有已受理用户消息。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(in crate::studio) last_user_message_at: Option<i64>,
    #[serde(default)]
    pub(in crate::studio) archived: bool,
}

impl SessionDirectoryRecord {
    /// 与 `SessionDescriptor::directory_sort_time` 相同的目录排序键。
    pub(in crate::studio) fn directory_sort_time(&self) -> i64 {
        self.last_user_message_at.unwrap_or(self.created_at)
    }
}

/// 成员目录事实：`catalog.toml` `agents` 记录的运行期形态。
///
/// 成员关系（`parent_agent_id`）在此唯一归属；主成员 `parent_agent_id = None`。
/// backend 绑定见 `binding`，完整指令、Profile 正文与执行状态不进入目录。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct AgentDirectoryRecord {
    /// 会话内成员 ID；首版迁移复用原 Thread ID 字节。
    pub(in crate::studio) agent_id: String,
    pub(in crate::studio) session_id: String,
    /// 所属会话内的父成员；主成员为 `None`。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(in crate::studio) parent_agent_id: Option<String>,
    /// 成员的默认本地执行上下文；首版一名成员恰有一个默认 Thread。
    pub(in crate::studio) thread_id: String,
    /// 成员定义 ID：root 为内置根定义，child 为创建期冻结的 Profile ID。
    pub(in crate::studio) role: String,
    /// child 创建期冻结的任务摘要标题；主成员省略（显示标题为会话标题）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(in crate::studio) title: Option<String>,
    pub(in crate::studio) binding: pl_protocol::AgentBinding,
    pub(in crate::studio) status: pl_protocol::ThreadStatus,
    pub(in crate::studio) explicitly_closed: bool,
    pub(in crate::studio) created_at: i64,
    pub(in crate::studio) updated_at: i64,
}

impl AgentDirectoryRecord {
    /// 是否为主成员（会话的 root Agent）。
    pub(in crate::studio) fn is_root_agent(&self) -> bool {
        self.parent_agent_id.is_none()
    }

    /// 与 `CatalogEntry::projected_status` 相同的目录状态投影。
    pub(in crate::studio) fn projected_status(&self) -> pl_protocol::ThreadStatus {
        crate::studio::agent_close::directory_status(self.status, self.explicitly_closed)
    }

    /// Native 冻结模型身份摘要（binding 的只读投影）；ACP 成员没有该事实。
    pub(in crate::studio) fn frozen_model(
        &self,
    ) -> Option<pl_protocol::studio::NewThreadModelRoute> {
        match &self.binding {
            pl_protocol::AgentBinding::Native(config) => config.route.clone(),
            pl_protocol::AgentBinding::Acp(_) => None,
        }
    }
}

/// 从会话与成员目录事实投影 wire 目录行 [`pl_protocol::SessionDirectoryRow`]。
///
/// 目录帧、增量事件与元数据观察共用该投影：行身份是 typed 四元组，会话级事实
/// 随行携带；root/child 判定只读 `parent_agent_id`。
pub(in crate::studio) fn row_projection(
    session: &SessionDirectoryRecord,
    agent: &AgentDirectoryRecord,
) -> pl_protocol::SessionDirectoryRow {
    pl_protocol::SessionDirectoryRow {
        session_id: session.session_id.clone(),
        agent_id: agent.agent_id.clone(),
        parent_agent_id: agent.parent_agent_id.clone(),
        thread_id: agent.thread_id.clone(),
        workspace_id: session.workspace_id.clone(),
        title: agent.title.clone().unwrap_or_else(|| session.title.clone()),
        mode: session.mode.clone(),
        workspace_mode: session.workspace_mode,
        delegation_mode: session.delegation_mode,
        delegation_preference: session.delegation_preference,
        workspace_path: session.workspace_path.clone(),
        role: agent.role.clone(),
        binding: agent.binding.clone(),
        status: agent.projected_status(),
        created_at: agent.created_at,
        updated_at: agent.updated_at,
        last_user_message_at: agent
            .is_root_agent()
            .then_some(session.last_user_message_at)
            .flatten(),
        archived: session.archived,
    }
}

/// 从 wire 目录行反向投影 Native 执行域的 [`pl_protocol::Thread`]。
///
/// 仅用于既有 Native 消费方（归档候选、命令回执）消费目录提交切面：行身份与
/// 目录事实同源，反投影是机械字段映射，不做成员归属推断。
pub(in crate::studio) fn thread_from_row(
    row: &pl_protocol::SessionDirectoryRow,
) -> pl_protocol::Thread {
    pl_protocol::Thread {
        id: row.thread_id.clone(),
        workspace_id: row.workspace_id.clone(),
        title: row.title.clone(),
        mode: row.mode.clone(),
        workspace_mode: row.workspace_mode,
        delegation_mode: row.delegation_mode,
        delegation_preference: row.delegation_preference,
        frozen_model: match &row.binding {
            pl_protocol::AgentBinding::Native(config) => config.route.clone(),
            pl_protocol::AgentBinding::Acp(_) => None,
        },
        workspace_path: row.workspace_path.clone(),
        root_thread_id: row.session_id.clone(),
        parent_thread_id: row.parent_agent_id.clone(),
        role: row.role.clone(),
        agent_path: row.thread_id.clone(),
        status: row.status,
        created_at: row.created_at,
        updated_at: row.updated_at,
        last_user_message_at: row
            .is_root_row()
            .then_some(row.last_user_message_at)
            .flatten(),
        archived: row.archived,
    }
}

/// 从会话与成员目录事实投影 Native 执行域的 [`pl_protocol::Thread`]。
///
/// 投影只服务既有 Native 消费方（费用归集、归档树、装配校验）：`root_thread_id`
/// 携带会话 ID 字节、`parent_thread_id` 携带父成员 ID 字节，与迁移前的值一致；
/// 会话/成员事实的唯一可写源仍是目录 owner。
pub(in crate::studio) fn thread_projection(
    session: &SessionDirectoryRecord,
    agent: &AgentDirectoryRecord,
) -> pl_protocol::Thread {
    let root_agent = agent.is_root_agent();
    pl_protocol::Thread {
        id: agent.thread_id.clone(),
        workspace_id: session.workspace_id.clone(),
        title: agent.title.clone().unwrap_or_else(|| session.title.clone()),
        mode: session.mode.clone(),
        workspace_mode: session.workspace_mode,
        delegation_mode: session.delegation_mode,
        delegation_preference: session.delegation_preference,
        frozen_model: agent.frozen_model(),
        workspace_path: session.workspace_path.clone(),
        root_thread_id: session.session_id.clone(),
        parent_thread_id: agent.parent_agent_id.clone(),
        role: agent.role.clone(),
        agent_path: agent.thread_id.clone(),
        status: agent.projected_status(),
        created_at: agent.created_at,
        updated_at: agent.updated_at,
        last_user_message_at: root_agent.then_some(session.last_user_message_at).flatten(),
        archived: session.archived,
    }
}

/// 测试助手：把 Native `Thread` 拆回会话/成员目录事实（`thread_projection` 的逆）。
///
/// 供旧测试的 `Thread` 惯用法注册目录行：root `Thread` 产生会话 + 主成员记录，
/// child 只产生成员记录（其会话事实由同一测试先注册的父行建立）。
#[cfg(test)]
pub(in crate::studio) fn directory_facts_from_thread(
    thread: &pl_protocol::Thread,
) -> (Option<SessionDirectoryRecord>, AgentDirectoryRecord) {
    let session = thread
        .parent_thread_id
        .is_none()
        .then(|| SessionDirectoryRecord {
            session_id: thread.root_thread_id.clone(),
            root_agent_id: thread.id.clone(),
            workspace_id: thread.workspace_id.clone(),
            title: thread.title.clone(),
            mode: thread.mode.clone(),
            workspace_mode: thread.workspace_mode,
            delegation_mode: thread.delegation_mode,
            delegation_preference: thread.delegation_preference,
            workspace_path: thread.workspace_path.clone(),
            created_at: thread.created_at,
            updated_at: thread.updated_at,
            last_user_message_at: thread.last_user_message_at,
            archived: thread.archived,
        });
    let agent = AgentDirectoryRecord {
        agent_id: thread.id.clone(),
        session_id: thread.root_thread_id.clone(),
        parent_agent_id: thread.parent_thread_id.clone(),
        thread_id: thread.id.clone(),
        role: thread.role.clone(),
        title: thread
            .parent_thread_id
            .is_some()
            .then(|| thread.title.clone()),
        binding: pl_protocol::AgentBinding::Native(pl_protocol::NativeAgentConfig {
            route: thread.frozen_model.clone(),
            system_instructions: None,
        }),
        status: thread.status,
        explicitly_closed: false,
        created_at: thread.created_at,
        updated_at: thread.updated_at,
    };
    (session, agent)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MaterializedAttachment {
    pub attachment_id: String,
    pub modality: pl_protocol::AttachmentModality,
    pub media_type: String,
    pub filename: Option<String>,
    pub data: String,
    pub byte_size: u64,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub initial_remote_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceRecord {
    pub id: String,
    pub kind: pl_protocol::studio::WorkspaceKind,
    pub name: String,
    pub path: String,
    pub ssh_alias: Option<String>,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadRecord {
    pub id: String,
    pub workspace_id: String,
    pub title: String,
    pub mode: pl_protocol::ThreadModeId,
    /// 会话工作区模式：Thread 的 canonical 产品事实，不由 GUI 或目录查询推导。
    pub workspace_mode: pl_protocol::ThreadWorkspaceMode,
    pub delegation_mode: pl_protocol::DelegationMode,
    pub delegation_preference: pl_protocol::DelegationPreference,
    pub frozen_model: Option<pl_protocol::studio::NewThreadModelRoute>,
    /// 会话对外唯一 canonical 工作区地址，创建会话时写定、之后只读。
    pub workspace_path: String,
    pub created_at: i64,
    pub updated_at: i64,
    /// 服务端最近一次成功受理用户消息的时间；缺失表示尚未回填或没有已受理用户消息。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_user_message_at: Option<i64>,
    pub visibility: ThreadVisibility,
    pub parent_thread_id: Option<String>,
    pub root_thread_id: String,
    pub thread_kind: ThreadKind,
    pub agent_path: String,
    pub role: String,
    pub status: pl_protocol::ThreadStatus,
    pub summary: Option<String>,
    pub error: Option<String>,
    pub runtime_updated_at: Option<i64>,
}

impl ThreadRecord {
    /// 从目录事实构造记录（创建命令返回值用）；runtime 派生列取缺省值。
    pub(in crate::studio) fn from_directory_thread(thread: pl_protocol::Thread) -> Self {
        let thread_kind = if thread.parent_thread_id.is_some() {
            ThreadKind::Agent
        } else {
            ThreadKind::Root
        };
        Self {
            thread_kind,
            visibility: if thread.archived {
                ThreadVisibility::Archived
            } else {
                ThreadVisibility::Active
            },
            id: thread.id,
            workspace_id: thread.workspace_id,
            title: thread.title,
            mode: thread.mode,
            workspace_mode: thread.workspace_mode,
            delegation_mode: thread.delegation_mode,
            delegation_preference: thread.delegation_preference,
            frozen_model: thread.frozen_model,
            workspace_path: thread.workspace_path,
            created_at: thread.created_at,
            updated_at: thread.updated_at,
            last_user_message_at: thread.last_user_message_at,
            parent_thread_id: thread.parent_thread_id,
            root_thread_id: thread.root_thread_id,
            agent_path: thread.agent_path,
            role: thread.role,
            status: thread.status,
            summary: None,
            error: None,
            runtime_updated_at: None,
        }
    }
}

impl From<ThreadRecord> for pl_protocol::Thread {
    fn from(value: ThreadRecord) -> Self {
        Self {
            id: value.id,
            workspace_id: value.workspace_id,
            title: value.title,
            mode: value.mode,
            workspace_mode: value.workspace_mode,
            delegation_mode: value.delegation_mode,
            delegation_preference: value.delegation_preference,
            frozen_model: value.frozen_model,
            workspace_path: value.workspace_path,
            root_thread_id: value.root_thread_id,
            parent_thread_id: value.parent_thread_id,
            role: value.role,
            agent_path: value.agent_path,
            status: value.status,
            created_at: value.created_at,
            updated_at: value.updated_at,
            last_user_message_at: value.last_user_message_at,
            archived: value.visibility == ThreadVisibility::Archived,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ThreadKind {
    Root,
    Agent,
}

impl ThreadKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Root => "root",
            Self::Agent => "agent",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ThreadVisibility {
    Active,
    Archived,
}

impl ThreadVisibility {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Active => "active",
            Self::Archived => "archived",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AttachmentRecord {
    pub id: String,
    pub thread_id: String,
    pub modality: pl_protocol::studio::StudioAttachmentModality,
    pub media_type: String,
    pub filename: Option<String>,
    /// POSIX blob reference relative to the owning session, never a host filesystem path.
    /// Read bytes through `StudioStore` so the Thread identity selects the correct session root.
    #[serde(rename = "storagePath")]
    pub blob_relative_path: String,
    pub byte_size: u64,
    pub content_sha256: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub created_at: i64,
}

/// Product directory status; runtime state is projected from the Thread checkpoint.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::studio) struct DirectoryState {
    pub kind: pl_protocol::ThreadStatus,
    pub error: Option<String>,
}
