//! 会话运行时所有权。
//!
//! 应用持有活动 [`SessionTable`]。每个 [`SessionRuntime`] 是一个会话代次，内部
//! [`crate::thread_assembler::Registry`] 是该代次的成员登记，不是应用级成员表。
//! 代次只沿 Open → Closing → Closed 前进；失败留在 Closing，旧对象不能 reopen。
mod agent;
mod agent_runtime;
#[cfg(test)]
pub(crate) mod session_close_tests;
mod table;

pub(crate) use agent::{AgentInstance, AgentRuntime};
pub(crate) use agent_runtime::NativeResources;
pub(crate) use agent_runtime::NativeThreadRuntime;
pub(crate) use agent_runtime::PreparedResources;
pub(crate) use table::SessionTable;
pub(crate) use table::WeakSessionTable;

use std::sync::Arc;

use crate::thread_assembler::Registry;

/// 一个会话代次的执行、准备与关闭 owner。
///
/// 成员 `close` 仍按 id 收束单个成员。会话收束是 [`Self::close_session`]：它与成员
/// 方法同名会冲突，因此用这个名字承载 design 中的 `Session::close`。
#[derive(Debug, Clone)]
pub struct SessionRuntime(pub(crate) Arc<Registry>);

impl SessionRuntime {
    /// 创建一个 Open 代次。安装服务与观察由 [`SessionTable`] 的 installer 完成。
    pub(crate) fn open(id: pl_protocol::SessionId) -> Self {
        Self(Arc::new(Registry::open(id)))
    }

    pub(crate) fn id(&self) -> &pl_protocol::SessionId {
        &self.0.session_id
    }

    pub(crate) fn phase(&self) -> SessionPhase {
        self.0.phase()
    }
}

#[cfg(test)]
impl Default for SessionRuntime {
    fn default() -> Self {
        Self::open(pl_protocol::SessionId::new("test-session").expect("valid test session"))
    }
}

/// 会话代次。单向前进，失败停在 Closing。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SessionPhase {
    Open,
    Closing,
    Closed,
}
