//! 产品会话身份与轻量目录描述。
//!
//! `SessionDescriptor` 是目录 owner 的只读结果：它只描述会话级目录事实（标题、排序
//! 时间、归档、工作区关联），不拥有可变执行状态；成员事实见
//! [`crate::agent::AgentDescriptor`]。首版一名主成员对应一个会话，`SessionId` 由
//! 根 Thread 的既有 ID 字节迁移而来（原值不变），两者类型与字段语义分开。

use serde::{Deserialize, Serialize};

use crate::agent::AgentId;
use crate::id::string_id;

string_id!(SessionId, "session id");

/// 一个产品会话的轻量目录描述。
///
/// 标题、最近用户输入时间与归档是会话级唯一事实：会话列表排序使用
/// `(last_user_message_at ?? created_at, session_id)` 降序，同秒按会话 ID 破平；
/// `updated_at` 保持普通更新语义，不参与排序。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SessionDescriptor {
    pub session_id: SessionId,
    /// 会话主成员；首版与 [`SessionId`] 同字节，但类型与字段语义分开。
    pub root_agent_id: AgentId,
    /// 所属工作区的稳定引用。
    pub workspace_id: String,
    /// 会话标题；不被子成员的任务摘要覆盖。
    pub title: String,
    pub created_at: i64,
    pub updated_at: i64,
    /// 服务端最近一次成功受理用户消息的时间（Unix 秒）；缺失表示尚无已受理输入。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_user_message_at: Option<i64>,
    #[serde(default)]
    pub archived: bool,
}

impl SessionDescriptor {
    /// 会话目录排序键：最近用户消息时间，缺失时回落到创建时间。
    ///
    /// 目录冷分页、搜索与 GUI 会话列表共用同一降序键；同秒由调用方以会话 ID 破平。
    pub fn directory_sort_time(&self) -> i64 {
        self.last_user_message_at.unwrap_or(self.created_at)
    }
}

/// 会话目录行：目录 owner 提交切面的轻量行投影（FRB 与 HTTP 共用）。
///
/// 行身份是 typed 四元组：`session_id`／`agent_id`／`parent_agent_id`／`thread_id`。
/// root/child 判定只读 `parent_agent_id`（主成员为 `None`），不从 ID 前缀或
/// Native 执行快照猜测成员归属。会话级事实（标题、排序时间、归档、工作区与
/// 分发设置）随行携带；`binding` 是成员的封闭后端绑定，child 的冻结模型路由
/// 从中读取，根成员的当前路由仍由既有模型路由观察交付。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SessionDirectoryRow {
    pub session_id: String,
    pub agent_id: String,
    /// 所属会话内的父成员；主成员为 `None`。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_agent_id: Option<String>,
    /// 成员的默认本地执行上下文。
    pub thread_id: String,
    pub workspace_id: String,
    /// 主成员行为会话标题；child 行为创建期冻结的任务摘要。
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<crate::ThreadModeId>,
    pub workspace_mode: crate::ThreadWorkspaceMode,
    pub delegation_mode: crate::DelegationMode,
    pub delegation_preference: crate::DelegationPreference,
    pub workspace_path: String,
    /// 成员定义 ID：root 为内置根定义，child 为冻结 Profile ID。
    pub role: String,
    pub backend: AgentBackend,
    pub created_at: i64,
    pub updated_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_user_message_at: Option<i64>,
    #[serde(default)]
    pub archived: bool,
}

/// 冻结的产品关联；ACP 的实时配置及执行状态不属于目录。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub enum AgentBackend {
    Native {
        config: crate::NativeAgentConfig,
        status: crate::ThreadStatus,
    },
    Acp {
        reference: AcpSessionReference,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpSessionReference {
    pub account_id: String,
    pub acp_session_id: String,
    pub cwd: String,
}

impl SessionDirectoryRow {
    pub fn native_status(&self) -> Option<crate::ThreadStatus> {
        self.backend.native_status()
    }
    /// 是否为主成员行（会话的 root Agent）。
    pub fn is_root_row(&self) -> bool {
        self.parent_agent_id.is_none()
    }

    /// 与 `SessionDescriptor::directory_sort_time` 相同的目录排序键。
    pub fn directory_sort_time(&self) -> i64 {
        self.last_user_message_at.unwrap_or(self.created_at)
    }
}

impl AgentBackend {
    pub fn native_status(&self) -> Option<crate::ThreadStatus> {
        match self {
            Self::Native { status, .. } => Some(*status),
            Self::Acp { .. } => None,
        }
    }

    pub fn binding(&self) -> crate::AgentBinding {
        match self {
            Self::Native { config, .. } => crate::AgentBinding::Native(config.clone()),
            Self::Acp { reference } => crate::AgentBinding::Acp(crate::AcpAgentConfig {
                account_id: reference.account_id.clone(),
            }),
        }
    }
}
