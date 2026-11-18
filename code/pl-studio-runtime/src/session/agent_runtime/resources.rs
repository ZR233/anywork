//! Resources owned by one Native materialization, including its preparation period.
use pl_core::thread::RuntimeBindingReader;
use std::sync::{Arc, Mutex};

use crate::studio::runtime::{
    rejected_tools::NativeToolCandidates, thread_observation::Observation,
};
use crate::studio::thread_factory::{mcp::ThreadMcpOwner, tool_bindings::ToolBinding};

#[derive(Default)]
pub(crate) struct NativeResources {
    binding: Mutex<ToolBindingSource>,
    pub(crate) mcp: Mutex<Option<Arc<ThreadMcpOwner>>>,
    pub(crate) observations: Mutex<Vec<Arc<Observation>>>,
    pub(crate) candidates: NativeToolCandidates,
    #[cfg(test)]
    pub(crate) s2_mcp_close_failure: Mutex<Option<Arc<std::sync::atomic::AtomicBool>>>,
}

// A physical preparation has no Core owner yet. After the first installation this field
// holds only its read port; refreshes cannot write a second copy of the active binding.
enum ToolBindingSource {
    Preparing(Option<Box<ToolBinding>>),
    Installed(RuntimeBindingReader),
    Closed,
}

impl Default for ToolBindingSource {
    fn default() -> Self {
        Self::Preparing(None)
    }
}

impl std::fmt::Debug for NativeResources {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NativeResources").finish_non_exhaustive()
    }
}

impl NativeResources {
    pub(crate) fn prepare_binding(
        &self,
        binding: ToolBinding,
    ) -> Result<(), pl_core::thread::ThreadError> {
        let mut source = self
            .binding
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let ToolBindingSource::Preparing(slot @ None) = &mut *source else {
            return Err(pl_core::thread::ThreadError::InvalidIdentity);
        };
        *slot = Some(Box::new(binding));
        Ok(())
    }

    pub(crate) fn observe_binding(&self, binding: RuntimeBindingReader) {
        let mut source = self
            .binding
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        debug_assert!(matches!(*source, ToolBindingSource::Preparing(_)));
        *source = ToolBindingSource::Installed(binding);
    }

    pub(crate) fn with_binding<R>(&self, read: impl FnOnce(Option<&ToolBinding>) -> R) -> R {
        let source = self
            .binding
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match &*source {
            ToolBindingSource::Preparing(binding) => read(binding.as_deref()),
            ToolBindingSource::Installed(binding) => binding.with_binding(read),
            ToolBindingSource::Closed => read(None),
        }
    }

    pub(crate) fn binding(&self) -> Option<ToolBinding> {
        self.with_binding(|binding| binding.cloned())
    }

    pub(crate) fn authorization_changed(&self) {
        let source = self
            .binding
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let ToolBindingSource::Installed(binding) = &*source {
            binding.authorization_changed();
        }
    }

    pub(crate) fn release_binding(&self) {
        *self
            .binding
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = ToolBindingSource::Closed;
    }

    pub(crate) fn cancel_tool_producers(&self) {
        let lifetime = self.with_binding(|binding| binding.map(|binding| binding.lifetime.clone()));
        let mcp = self
            .mcp
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(lifetime) = lifetime {
            lifetime.cancel();
        }
        if let Some(mcp) = mcp {
            mcp.cancel_producers();
        }
    }
    pub(crate) fn has_obligations(&self) -> bool {
        self.with_binding(|binding| binding.is_some())
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
