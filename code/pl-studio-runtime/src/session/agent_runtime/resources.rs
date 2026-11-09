//! Resources owned by one Native materialization, including its preparation period.
use std::sync::{Arc, Mutex};

use crate::studio::runtime::{
    rejected_tools::NativeToolCandidates, thread_observation::Observation,
};
use crate::studio::thread_factory::{mcp::ThreadMcpOwner, tool_bindings::ToolBinding};

#[derive(Default)]
pub(crate) struct NativeResources {
    pub(crate) binding: Mutex<Option<ToolBinding>>,
    pub(crate) mcp: Mutex<Option<Arc<ThreadMcpOwner>>>,
    pub(crate) observations: Mutex<Vec<Arc<Observation>>>,
    pub(crate) candidates: NativeToolCandidates,
    #[cfg(test)]
    pub(crate) s2_mcp_close_failure: Mutex<Option<Arc<std::sync::atomic::AtomicBool>>>,
}

impl std::fmt::Debug for NativeResources {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NativeResources").finish_non_exhaustive()
    }
}

impl NativeResources {
    pub(crate) fn cancel_tool_producers(&self) {
        let lifetime = self
            .binding
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .map(|binding| binding.lifetime.clone());
        let mcp = self
            .mcp
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(lifetime) = lifetime {
            lifetime.cancellation.cancel();
        }
        if let Some(mcp) = mcp {
            mcp.cancel_producers();
        }
    }
    pub(crate) fn has_obligations(&self) -> bool {
        self.binding
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .is_some()
            || self
                .mcp
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .is_some()
            || !self
                .observations
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .is_empty()
            || self.candidates.has_obligations()
    }
}
