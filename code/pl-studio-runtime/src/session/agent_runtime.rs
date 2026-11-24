//! Concrete resource branches shared by preparing and published membership.
mod resources;

pub(crate) use resources::NativeResources;

use std::sync::Arc;

use pl_core::thread::ThreadHandle;

use crate::studio::WorkspaceUsageLease;
use crate::thread_assembler::{CleanupGate, CloseStorage, EntryPurpose};

#[derive(Debug, Clone)]
pub(crate) enum PreparedResources {
    Native(Arc<NativeResources>),
    Acp(Arc<crate::studio::runtime::acp_business::AcpResources>),
}

impl PreparedResources {
    pub(crate) fn require_native(
        &self,
    ) -> Result<&Arc<NativeResources>, crate::thread_assembler::ThreadAssemblyError> {
        self.native().ok_or(
            crate::thread_assembler::ThreadAssemblyError::UnsupportedBackend {
                backend: crate::AgentBackendKind::Acp,
            },
        )
    }

    pub(crate) fn native(&self) -> Option<&Arc<NativeResources>> {
        match self {
            Self::Native(native) => Some(native),
            Self::Acp(_) => None,
        }
    }

    pub(crate) fn has_obligations(&self) -> bool {
        match self {
            Self::Native(native) => native.has_obligations(),
            Self::Acp(acp) => acp.has_obligations(),
        }
    }

    pub(crate) fn cancel(&self) {
        match self {
            Self::Native(native) => native.cancel_tool_producers(),
            Self::Acp(acp) => acp.cancel(),
        }
    }
}

/// 一个已登记 Native 成员的产品资源。
///
/// 执行状态、工具与检查点仍由 pl-core owner 持有；这里只组合会话关闭、存储交接和
/// 发布资格所需的产品句柄，不复制 core 的 activeTurn。
/// 字段来自原全局 `Entry` 的 Native 资源组合。成员关系不在这里用 Thread id 推断。
#[derive(Debug)]
pub(crate) struct NativeThreadRuntime {
    pub(crate) resources: Arc<NativeResources>,
    pub(crate) purpose: EntryPurpose,
    pub(crate) workspace_usage: Option<WorkspaceUsageLease>,
    pub(crate) close_storage: Option<CloseStorage>,
    pub(crate) published_resources_closed: bool,
    /// Studio 只在显式关闭标记持久后发布 `Some`。普通退役保持 `None`，消费默认 Preserve。
    pub(crate) workspace_disposition: Option<pl_tool::collaboration::thread::WorkspaceRelease>,
    pub(crate) cleanup: Arc<CleanupGate>,
    pub(crate) execution: pl_core::thread::input::InputDriverOptions,
    pub(crate) incarnation: Arc<()>,
    /// 调用方显式给出的父 Thread id，只用于调用者匹配，不是成员树边。
    pub(crate) parent_id: Option<String>,
    pub(crate) ready: bool,
    pub(crate) thread: ThreadHandle,
}
