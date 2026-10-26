//! Published workspace cleanup remains owned until the frozen close policy succeeds.
use super::{Registry, State, StudioThreadAssembler, ThreadAssemblyError};
use pl_tool::collaboration::thread::AgentWorkspaceDisposition;
use std::sync::{Arc, Weak};

/// Admission is sealed only while an operation owns this guard. Durable explicit-close intent
/// belongs to the Studio checkpoint, not a process-long set of every closed identity.
#[must_use = "retain this guard until the sealed operation concludes"]
pub(crate) struct AgentOperationSeal {
    registry: Weak<Registry>,
    ids: Vec<String>,
}

impl Drop for AgentOperationSeal {
    fn drop(&mut self) {
        let Some(registry) = self.registry.upgrade() else {
            return;
        };
        let mut state = registry.state();
        for id in &self.ids {
            if let Some(count) = state.sealed_agents.get_mut(id) {
                *count -= 1;
                if *count == 0 {
                    state.sealed_agents.remove(id);
                }
            }
        }
    }
}

fn seal(registry: &Arc<Registry>, state: &mut State, ids: Vec<String>) -> AgentOperationSeal {
    for id in &ids {
        *state.sealed_agents.entry(id.clone()).or_default() += 1;
    }
    AgentOperationSeal {
        registry: Arc::downgrade(registry),
        ids,
    }
}

impl StudioThreadAssembler {
    /// Caller owns this identity's operation permit. Tree operations seal roots before children.
    pub(crate) fn seal_agent_operation(&self, id: &str) -> AgentOperationSeal {
        seal(&self.0, &mut self.0.state(), vec![id.to_owned()])
    }

    pub(crate) async fn seal_agent_operations(&self, ids: &[String]) -> AgentOperationSeal {
        let mut ids = ids.to_vec();
        ids.sort();
        ids.dedup();
        let mut permits = Vec::with_capacity(ids.len());
        for id in &ids {
            permits.push(self.agent_operation(id).await);
        }
        seal(&self.0, &mut self.0.state(), ids)
    }

    pub(super) async fn seal_agent_close(
        &self,
        targets: &[(usize, String)],
        disposition: AgentWorkspaceDisposition,
    ) -> Result<AgentOperationSeal, ThreadAssemblyError> {
        let mut ids = targets.iter().map(|(_, id)| id).collect::<Vec<_>>();
        ids.sort();
        ids.dedup();
        let mut permits = Vec::new();
        for id in &ids {
            permits.push(self.agent_operation(id).await);
        }
        let mut state = self.0.state();
        for (_, id) in targets {
            if let Some(entry) = state.entries.get(id)
                && entry
                    .workspace_disposition
                    .is_some_and(|current| current != disposition)
            {
                return Err(ThreadAssemblyError::CloseDisposition(id.clone()));
            }
        }
        let standalone = state.agent_services.is_none();
        for (_, id) in targets {
            if let Some(entry) = state.entries.get_mut(id) {
                // Standalone assemblers have no Studio persistence contract. Studio seals only
                // admission here: publishing Cleanup before a successful flush would let ordinary
                // shutdown consume an uncommitted request after the owned close fails.
                if standalone {
                    if entry.workspace_disposition != Some(disposition) {
                        entry.published_resources_closed = false;
                    }
                    entry.workspace_disposition = Some(disposition);
                }
                entry.ready = false;
            }
        }
        Ok(seal(
            &self.0,
            &mut state,
            ids.into_iter().cloned().collect(),
        ))
    }

    /// Caller holds this identity's operation permit and has just successfully flushed its close
    /// intent. An in-memory marker after a failed flush never authorizes publishing a new policy.
    pub(super) fn freeze_agent_close_disposition(
        &self,
        id: &str,
        disposition: AgentWorkspaceDisposition,
    ) -> Result<(), ThreadAssemblyError> {
        let mut state = self.0.state();
        let entry = state
            .entries
            .get_mut(id)
            .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
        if let Some(current) = entry.workspace_disposition {
            if current != disposition {
                return Err(ThreadAssemblyError::CloseDisposition(id.to_owned()));
            }
        } else {
            // A previous default Preserve is not an explicit policy; first durable Cleanup must
            // still run even if that ordinary resource retirement had already completed.
            entry.published_resources_closed = false;
            entry.workspace_disposition = Some(disposition);
        }
        Ok(())
    }

    pub(super) async fn close_published_resources(
        registry: Weak<Registry>,
        id: String,
        owner: super::close_failure::EntryCloseOwner,
    ) -> Result<(), ThreadAssemblyError> {
        if !owner.published || owner.disposition.is_none() {
            return Ok(());
        }
        let cleanup = owner
            .cleanup
            .upgrade()
            .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
        // The drive owns the original cleanup permit outside its retained phase future.
        // Do not keep that gate or the registry alive through the future stored in that gate.
        let completed = {
            let registry = registry
                .upgrade()
                .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
            let state = registry.state();
            let entry = state
                .entries
                .get(&id)
                .filter(|entry| {
                    Arc::ptr_eq(&entry.incarnation, &owner.incarnation)
                        && entry.thread.same_instance(&owner.thread)
                        && Arc::ptr_eq(&entry.cleanup, &cleanup)
                        && entry.workspace_disposition == owner.disposition
                })
                .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
            if state.unpublished_children.contains_key(&id) {
                return Err(ThreadAssemblyError::Identity(id.to_owned()));
            }
            entry.published_resources_closed
        };
        drop(cleanup);
        if completed {
            return Ok(());
        }
        if let (Some(factory), Some(disposition)) = (owner.factory, owner.disposition) {
            factory
                .close_published(&id, disposition)
                .await?;
        }
        let registry = registry
            .upgrade()
            .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
        let cleanup = owner
            .cleanup
            .upgrade()
            .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
        let mut state = registry.state();
        let entry = state
            .entries
            .get_mut(&id)
            .filter(|entry| {
                Arc::ptr_eq(&entry.incarnation, &owner.incarnation)
                    && entry.thread.same_instance(&owner.thread)
                    && Arc::ptr_eq(&entry.cleanup, &cleanup)
                    && entry.workspace_disposition == owner.disposition
            })
            .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
        entry.published_resources_closed = true;
        Ok(())
    }
}
