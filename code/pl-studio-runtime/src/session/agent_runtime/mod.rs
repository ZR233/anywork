//! Concrete resource branches shared by preparing and published membership.
mod native;
mod resources;

pub(crate) use native::NativeThreadRuntime;
pub(crate) use resources::NativeResources;

#[derive(Debug, Clone)]
pub(crate) enum PreparedResources {
    Native(std::sync::Arc<NativeResources>),
    Acp(std::sync::Arc<crate::studio::runtime::acp_business::AcpResources>),
}

impl PreparedResources {
    pub(crate) fn require_native(
        &self,
    ) -> Result<&std::sync::Arc<NativeResources>, crate::thread_assembler::ThreadAssemblyError>
    {
        self.native().ok_or(
            crate::thread_assembler::ThreadAssemblyError::UnsupportedBackend {
                backend: pl_protocol::AgentBackendKind::Acp,
            },
        )
    }
    pub(crate) fn native(&self) -> Option<&std::sync::Arc<NativeResources>> {
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
