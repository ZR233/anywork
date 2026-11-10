//! 会话内一个已物化成员：目录身份、冻结 binding 与具体 Native 运行时。
use pl_protocol::{AgentBinding, AgentThreadIdentity};

use super::agent_runtime::NativeThreadRuntime;

/// 一个已物化成员。冷成员不构造本对象。
#[derive(Debug)]
pub(crate) struct AgentInstance {
    pub(crate) identity: AgentThreadIdentity,
    pub(crate) binding: AgentBinding,
    pub(crate) runtime: AgentRuntime,
}

#[derive(Debug)]
pub(crate) enum AgentRuntime {
    Native(Box<NativeThreadRuntime>),
    Acp(std::sync::Arc<crate::studio::runtime::acp_business::AcpResources>),
}

impl AgentInstance {
    pub(crate) fn native(
        &self,
    ) -> Result<&NativeThreadRuntime, crate::thread_assembler::ThreadAssemblyError> {
        match &self.runtime {
            AgentRuntime::Native(native) => Ok(native),
            AgentRuntime::Acp(_) => Err(
                crate::thread_assembler::ThreadAssemblyError::UnsupportedBackend {
                    backend: pl_protocol::AgentBackendKind::Acp,
                },
            ),
        }
    }

    pub(crate) fn native_mut(
        &mut self,
    ) -> Result<&mut NativeThreadRuntime, crate::thread_assembler::ThreadAssemblyError> {
        match &mut self.runtime {
            AgentRuntime::Native(native) => Ok(native),
            AgentRuntime::Acp(_) => Err(
                crate::thread_assembler::ThreadAssemblyError::UnsupportedBackend {
                    backend: pl_protocol::AgentBackendKind::Acp,
                },
            ),
        }
    }

    pub(crate) fn cancel(&self) {
        match &self.runtime {
            AgentRuntime::Native(native) => {
                native.thread.request_shutdown();
            }
            AgentRuntime::Acp(acp) => acp.cancel(),
        }
    }
}
