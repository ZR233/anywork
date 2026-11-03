//! 产品智能体成员身份、可复用定义快照与成员目录描述。
//!
//! `AgentId` 是会话内成员身份，不再与 `ThreadId` 在类型层混用：首版迁移复用原
//! Thread ID 字节，但两者语义分开（`ThreadId` 见 [`crate::thread`]）。
//! [`AgentDefinitionSnapshot`] 是可复用定义的不可变快照，不拥有线程、连接或任务，
//! 也不混入模型配置（模型路由归 [`crate::agent::AgentBinding`]）与运行状态。

use serde::{Deserialize, Serialize};

use crate::id::string_id;
use crate::session::SessionId;
use crate::thread::ThreadId;

string_id!(AgentId, "agent id");

/// 可复用智能体定义的不可变快照。
///
/// 定义身份、显示文本、用途与内容修订完整保留；账号、模型、推理强度与指令正文
/// 的冻结归 Profile／binding／指令快照各自的 owner，不在此重复第二份事实。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentDefinitionSnapshot {
    pub definition_id: String,
    pub display_name: String,
    pub description: String,
    pub when_to_use: String,
    /// 定义来源标识（内置声明表或用户 Profile）。
    pub source: String,
    /// 定义内容修订；配置定义更新只影响后续新实例。
    pub revision: String,
    /// 定义正文的内容身份。
    pub content_hash: String,
}

/// 会话成员的执行后端类别。
///
/// 类别在实例创建期固定；`Acp` 分支在 S4 之前没有可执行实现，出现即明确失败，
/// 不提供空实现或假成功。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AgentBackendKind {
    #[default]
    Native,
    Acp,
}

/// 一个会话成员的目录描述。
///
/// 与 [`SessionDescriptor`] 一样是目录 owner 的只读结果；成员关系由
/// `parent_agent_id` 表达（主成员为 `None`），root/child 表达成员关系，
/// Native/ACP（见 [`AgentBackendKind`]）表达执行方式，两者正交。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentDescriptor {
    pub agent_id: AgentId,
    pub session_id: SessionId,
    /// 所属会话内的父成员；主成员为 `None`。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_agent_id: Option<AgentId>,
    /// 成员的默认本地执行上下文；首版一名成员恰有一个默认 Thread。
    pub thread_id: ThreadId,
    /// 成员定义 ID：root 为内置根定义，child 为创建期冻结的 Profile ID。
    ///
    /// 目录冷读只携带该稳定引用，不加载定义正文；完整定义快照由定义 owner 在
    /// 装配或恢复边界提供。
    pub definition_id: String,
    /// 成员显示标题：主成员为会话标题，child 为创建期冻结的任务摘要。
    pub display_title: String,
    pub backend: AgentBackendKind,
    /// 所属会话的工作区引用；child 的实际执行边界另见各自冻结的工作区收据。
    pub workspace_id: String,
}
