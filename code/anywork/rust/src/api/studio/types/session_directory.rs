//! 会话目录行的 FRB 镜像：typed 身份四元组 + 目录事实。
//!
//! 行身份是 `session_id`/`agent_id`/`parent_agent_id`/`thread_id`；root/child 判定
//! 只读 `parent_agent_id`（主成员为 `None`），不从 ID 前缀或 Native 快照猜测。
//! `binding` 是成员的封闭后端绑定，child 的冻结模型路由从中读取。

use serde::{Deserialize, Serialize};

use super::{
    BridgeDelegationMode, BridgeDelegationPreference, BridgeNewThreadModelRoute, BridgeThreadStatus,
};

/// 成员后端绑定的 FRB 镜像；与 `pl_protocol::AgentBinding` 的 tagged 形状一致。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum BridgeAgentBinding {
    Native {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        route: Option<BridgeNewThreadModelRoute>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        system_instructions: Option<String>,
    },
    Acp {
        account_id: String,
        connection_revision: u64,
    },
}

impl From<pl_protocol::AgentBinding> for BridgeAgentBinding {
    fn from(binding: pl_protocol::AgentBinding) -> Self {
        match binding {
            pl_protocol::AgentBinding::Native(config) => Self::Native {
                route: config.route.map(Into::into),
                system_instructions: config.system_instructions,
            },
            pl_protocol::AgentBinding::Acp(config) => Self::Acp {
                account_id: config.account_id,
                connection_revision: config.connection_revision,
            },
        }
    }
}

impl From<BridgeAgentBinding> for pl_protocol::AgentBinding {
    fn from(binding: BridgeAgentBinding) -> Self {
        match binding {
            BridgeAgentBinding::Native {
                route,
                system_instructions,
            } => Self::Native(pl_protocol::NativeAgentConfig {
                route: route.map(Into::into),
                system_instructions,
            }),
            BridgeAgentBinding::Acp {
                account_id,
                connection_revision,
            } => Self::Acp(pl_protocol::AcpAgentConfig {
                account_id,
                connection_revision,
            }),
        }
    }
}

/// 会话目录行的 FRB 镜像（目录 owner 提交切面的轻量行投影）。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeSessionDirectoryRow {
    pub session_id: String,
    pub agent_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_agent_id: Option<String>,
    pub thread_id: String,
    pub workspace_id: String,
    pub title: String,
    /// 完整 Thread Mode ID，例如 `mode.simple` 或 `mode.release`。
    pub mode: String,
    pub delegation_mode: BridgeDelegationMode,
    pub delegation_preference: BridgeDelegationPreference,
    /// Canonical 会话工作区模式：`local` 或 `worktree`。
    pub workspace_mode: String,
    /// Canonical 会话工作区地址。
    pub workspace_path: String,
    /// 成员定义 ID：root 为内置根定义，child 为冻结 Profile ID。
    pub role: String,
    pub binding: BridgeAgentBinding,
    pub status: BridgeThreadStatus,
    pub created_at: i64,
    pub updated_at: i64,
    pub last_user_message_at: Option<i64>,
    pub archived: bool,
}

impl BridgeSessionDirectoryRow {
    pub fn is_root_row(&self) -> bool {
        self.parent_agent_id.is_none()
    }
}
