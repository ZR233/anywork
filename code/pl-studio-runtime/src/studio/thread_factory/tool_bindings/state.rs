//! One map owns preparing, abandoned and published lifetimes; only Ready exposes a workspace.
use super::{ThreadToolLifetime, ToolBinding};
use crate::thread_assembler::ThreadAssemblyError;
use std::{collections::BTreeMap, sync::Arc};

enum BindingState {
    Preparing(Arc<ThreadToolLifetime>),
    Abandoned(Arc<ThreadToolLifetime>),
    Ready(Box<ToolBinding>),
}
impl BindingState {
    fn lifetime(&self) -> &Arc<ThreadToolLifetime> {
        match self {
            Self::Preparing(owner) | Self::Abandoned(owner) => owner,
            Self::Ready(binding) => &binding.lifetime,
        }
    }
}

#[derive(Default)]
pub(in crate::studio::thread_factory) struct ToolBindings {
    closing: bool,
    entries: BTreeMap<String, BindingState>,
}
impl ToolBindings {
    pub fn get(&self, id: &str) -> Option<&ToolBinding> {
        match self.entries.get(id)? {
            BindingState::Ready(binding) => Some(binding.as_ref()),
            BindingState::Preparing(_) | BindingState::Abandoned(_) => None,
        }
    }
    pub fn get_mut(&mut self, id: &str) -> Option<&mut ToolBinding> {
        match self.entries.get_mut(id)? {
            BindingState::Ready(binding) => Some(binding.as_mut()),
            BindingState::Preparing(_) | BindingState::Abandoned(_) => None,
        }
    }
    pub fn values_mut(&mut self) -> impl Iterator<Item = &mut ToolBinding> {
        self.entries.values_mut().filter_map(|entry| match entry {
            BindingState::Ready(binding) => Some(binding.as_mut()),
            BindingState::Preparing(_) | BindingState::Abandoned(_) => None,
        })
    }
    pub fn lifetime(&self, id: &str) -> Option<Arc<ThreadToolLifetime>> {
        self.entries.get(id).map(|entry| entry.lifetime().clone())
    }
    pub fn pending(&self) -> Vec<(String, Arc<ThreadToolLifetime>)> {
        self.entries
            .iter()
            .filter_map(|(id, entry)| match entry {
                BindingState::Ready(_) => None,
                BindingState::Preparing(_) | BindingState::Abandoned(_) => {
                    Some((id.clone(), entry.lifetime().clone()))
                }
            })
            .collect()
    }
    pub fn reserve(
        &mut self,
        id: &str,
        lifetime: Arc<ThreadToolLifetime>,
    ) -> Result<(), ThreadAssemblyError> {
        if self.closing {
            return Err(ThreadAssemblyError::Closed);
        }
        if self.entries.contains_key(id) {
            return Err(ThreadAssemblyError::Identity(id.into()));
        }
        self.entries
            .insert(id.into(), BindingState::Preparing(lifetime));
        Ok(())
    }
    pub fn publish(&mut self, id: &str, binding: ToolBinding) -> Result<(), ThreadAssemblyError> {
        if self.closing || binding.lifetime.cancellation.is_cancelled() {
            return Err(ThreadAssemblyError::Closed);
        }
        let Some(BindingState::Preparing(previous)) = self.entries.get(id) else {
            return Err(ThreadAssemblyError::Closed);
        };
        if !Arc::ptr_eq(previous, &binding.lifetime) {
            return Err(ThreadAssemblyError::Closed);
        }
        self.entries
            .insert(id.into(), BindingState::Ready(Box::new(binding)));
        Ok(())
    }
    pub fn abandon(&mut self, id: &str, expected: &Arc<ThreadToolLifetime>) {
        if self
            .entries
            .get(id)
            .is_some_and(|entry| Arc::ptr_eq(entry.lifetime(), expected))
        {
            expected.cancellation.cancel();
            self.entries
                .insert(id.into(), BindingState::Abandoned(expected.clone()));
        }
    }
    pub fn remove_drained(
        &mut self,
        id: &str,
        expected: &Arc<ThreadToolLifetime>,
    ) -> Result<(), ThreadAssemblyError> {
        if self
            .entries
            .get(id)
            .is_some_and(|entry| !Arc::ptr_eq(entry.lifetime(), expected))
        {
            return Err(ThreadAssemblyError::Identity(
                "Thread lifetime changed during file-operation drain".into(),
            ));
        }
        self.entries.remove(id);
        Ok(())
    }
    pub fn seal(&mut self) {
        self.closing = true;
        for entry in self.entries.values() {
            entry.lifetime().cancellation.cancel();
        }
    }
}
