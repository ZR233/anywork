//! Published workspace cleanup remains owned until the frozen close policy succeeds.
use super::{Registry, State, StudioThreadAssembler, ThreadAssemblyError};
use pl_tool::collaboration::thread::AgentWorkspaceDisposition;
use std::sync::{Arc, Weak};

/// One immutable Studio directory confirmation, bound to the Entry that accepted its close.
#[derive(Debug)]
pub(super) struct DirectoryProjection {
    factory: crate::studio::StudioThreadFactory,
    record: pl_protocol::Thread,
}

impl DirectoryProjection {
    pub(super) fn new(
        factory: crate::studio::StudioThreadFactory,
        record: pl_protocol::Thread,
    ) -> Self {
        Self { factory, record }
    }

    fn same_record(&self, other: &Self) -> bool {
        let left = &self.record;
        let right = &other.record;
        left.id == right.id
            && left.project_id == right.project_id
            && left.root_thread_id == right.root_thread_id
            && left.parent_thread_id == right.parent_thread_id
            && left.agent_path == right.agent_path
            && left.created_at == right.created_at
            && left.workspace_mode == right.workspace_mode
            && left.workspace_path == right.workspace_path
    }

    pub(super) async fn project(
        self: &Arc<Self>,
        thread: &pl_core::thread::ThreadHandle,
    ) -> Result<(), ThreadAssemblyError> {
        let result = async {
            let snapshot = thread.snapshot();
            if snapshot.lifecycle != pl_core::thread::ThreadLifecycle::Closed {
                return Err(ThreadAssemblyError::Identity(self.record.id.clone()));
            }
            self.factory
                .project_child_close(&self.record, &snapshot)
                .await
        }
        .await;
        result.map_err(|cause| ThreadAssemblyError::Resource {
            operation: "confirm original child directory closure",
            source: Box::new(DirectoryProjectionFailure {
                projection: self.clone(),
                cause: Arc::new(cause),
            }),
        })
    }
}

#[derive(Debug, thiserror::Error)]
#[error("the original child directory confirmation remains unresolved")]
pub(super) struct DirectoryProjectionFailure {
    pub(super) projection: Arc<DirectoryProjection>,
    #[source]
    cause: Arc<ThreadAssemblyError>,
}

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
        let cleanups = {
            let state = self.0.state();
            ids.iter()
                .filter_map(|id| state.entries.get(*id).map(|entry| entry.cleanup.clone()))
                .collect::<Vec<_>>()
        };
        let mut cleanup_permits = Vec::with_capacity(cleanups.len());
        for cleanup in cleanups {
            cleanup_permits.push(cleanup.acquire().await);
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
    pub(super) async fn freeze_agent_close_disposition(
        &self,
        id: &str,
        thread: &pl_core::thread::ThreadHandle,
        disposition: AgentWorkspaceDisposition,
        projection: DirectoryProjection,
    ) -> Result<(), ThreadAssemblyError> {
        let (incarnation, cleanup) = self
            .0
            .state()
            .entries
            .get(id)
            .filter(|entry| entry.thread.same_instance(thread))
            .map(|entry| (entry.incarnation.clone(), entry.cleanup.clone()))
            .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
        let _cleanup = cleanup.acquire().await;
        let mut state = self.0.state();
        let entry = state
            .entries
            .get_mut(id)
            .filter(|entry| {
                Arc::ptr_eq(&entry.incarnation, &incarnation)
                    && entry.thread.same_instance(thread)
                    && Arc::ptr_eq(&entry.cleanup, &cleanup)
            })
            .ok_or_else(|| ThreadAssemblyError::Identity(id.to_owned()))?;
        if projection.record.id != id || projection.record.parent_thread_id != entry.parent_id {
            return Err(ThreadAssemblyError::Identity(id.to_owned()));
        }
        if entry
            .directory_projection
            .as_ref()
            .is_some_and(|current| !current.same_record(&projection))
        {
            return Err(ThreadAssemblyError::Identity(id.to_owned()));
        }
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
        if entry.directory_projection.is_none() {
            entry.directory_projection = Some(Arc::new(projection));
            entry.directory_projected = false;
        }
        Ok(())
    }

    pub(super) async fn close_published_resources(
        registry: Weak<Registry>,
        id: String,
        owner: super::close_failure::EntryCloseOwner,
        disposition: Option<AgentWorkspaceDisposition>,
    ) -> Result<(), ThreadAssemblyError> {
        if !owner.published || disposition.is_none() {
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
                    owner.matches_entry(entry) && entry.workspace_disposition == disposition
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
        if let (Some(factory), Some(disposition)) = (owner.factory, disposition) {
            factory.close_published(&id, disposition).await?;
        }
        Ok(())
    }
}
