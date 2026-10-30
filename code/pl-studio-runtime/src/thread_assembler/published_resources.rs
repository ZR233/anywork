//! Published workspace cleanup remains owned until the frozen close policy succeeds.
use super::{Registry, State, StudioThreadAssembler, ThreadAssemblyError};
use pl_tool::collaboration::thread::WorkspaceRelease;
use std::sync::{Arc, Weak};

#[cfg(test)]
#[path = "archive_scope_tests.rs"]
mod archive_scope_tests;

/// Admission is sealed only while an operation owns this guard. Durable explicit-close intent
/// belongs to the Studio checkpoint, not a process-long set of every closed identity.
#[must_use = "retain this guard until the sealed operation concludes"]
pub(crate) struct AgentOperationSeal {
    registry: Weak<Registry>,
    ids: Vec<String>,
}

/// One frozen registry closure, not a second preparation/job registry.
pub(crate) struct ArchiveScopeSeal {
    admission: AgentOperationSeal,
    members: Vec<(usize, String)>,
    identities: Vec<(String, Option<String>, String)>,
    private_ids: Vec<String>,
}

impl ArchiveScopeSeal {
    pub(crate) fn thread_ids(&self) -> Vec<String> {
        self.members.iter().map(|(_, id)| id.clone()).collect()
    }
    pub(crate) fn preparation_identities(
        &self,
        workspace_id: &str,
    ) -> Vec<crate::studio::store::thread_preparation::PreparationIdentity> {
        self.identities
            .iter()
            .filter(|(id, _, _)| self.private_ids.contains(id))
            .map(|(thread_id, parent_id, root_id)| {
                crate::studio::store::thread_preparation::PreparationIdentity {
                    thread_id: thread_id.clone(),
                    workspace_id: workspace_id.into(),
                    parent_id: parent_id.clone(),
                    root_id: root_id.clone(),
                }
            })
            .collect()
    }
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
    /// Capture all admitted owners and seal their admission in the same short registry lock.
    /// Cancellation is broadcast outside the lock, before acquiring any operation permit.
    pub(crate) fn seal_archive_scope(
        &self,
        roots: &[String],
    ) -> Result<ArchiveScopeSeal, ThreadAssemblyError> {
        use std::collections::{BTreeMap, BTreeSet};
        let (scope, cancellation) = {
            let mut state = self.0.state();
            let mut parents = BTreeMap::<String, Option<String>>::new();
            let mut observe = |id: &str, parent: Option<&str>| {
                let parent = parent.map(str::to_owned);
                if let Some(previous) = parents.insert(id.to_owned(), parent.clone())
                    && previous != parent
                {
                    return Err(ThreadAssemblyError::Identity(id.to_owned()));
                }
                Ok(())
            };
            for (id, entry) in &state.entries {
                observe(id, entry.parent_id.as_deref())?;
            }
            for (id, entry) in &state.creating {
                observe(id, entry.parent_id.as_deref())?;
            }
            for (id, entry) in &state.preparing_children {
                observe(id, Some(&entry.parent))?;
            }
            for (id, entry) in &state.unpublished_children {
                observe(id, Some(&entry.parent))?;
            }
            let roots = roots.iter().cloned().collect::<BTreeSet<_>>();
            for root in &roots {
                if root.is_empty() || parents.get(root).is_some_and(Option::is_some) {
                    return Err(ThreadAssemblyError::Identity(root.clone()));
                }
            }
            let mut depths = roots
                .iter()
                .map(|id| (id.clone(), 0usize))
                .collect::<BTreeMap<_, _>>();
            loop {
                let mut added = false;
                for (id, parent) in &parents {
                    if depths.contains_key(id) {
                        continue;
                    }
                    if let Some(depth) = parent
                        .as_ref()
                        .and_then(|parent| depths.get(parent))
                        .copied()
                    {
                        depths.insert(id.clone(), depth + 1);
                        added = true;
                    }
                }
                if !added {
                    break;
                }
            }
            let ids = depths.keys().cloned().collect::<Vec<_>>();
            let private_ids = ids
                .iter()
                .filter(|id| {
                    state.creating.contains_key(*id)
                        || state.preparing_children.contains_key(*id)
                        || state.unpublished_children.contains_key(*id)
                })
                .cloned()
                .collect();
            let mut identities = Vec::new();
            for id in &ids {
                let mut root = id;
                while !roots.contains(root) {
                    root = parents
                        .get(root)
                        .and_then(Option::as_ref)
                        .ok_or_else(|| ThreadAssemblyError::Identity(id.clone()))?;
                }
                identities.push((id.clone(), parents.get(id).cloned().flatten(), root.clone()));
            }
            for id in &ids {
                if let Some(pending) = state.unpublished_children.get(id)
                    && *pending
                        .retirement
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        == Some(WorkspaceRelease::Cleanup)
                {
                    return Err(ThreadAssemblyError::Preparing(id.clone()));
                }
            }
            for id in &ids {
                if let Some(pending) = state.unpublished_children.get(id) {
                    *pending
                        .retirement
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner) =
                        Some(WorkspaceRelease::Preserve);
                }
            }
            let cancellation = state
                .creating
                .iter()
                .filter(|(id, _)| depths.contains_key(*id))
                .map(|(_, entry)| entry.cancellation.clone())
                .chain(
                    state
                        .preparing_children
                        .iter()
                        .filter(|(id, _)| depths.contains_key(*id))
                        .map(|(_, entry)| entry.cancellation.clone()),
                )
                .collect::<Vec<_>>();
            let mut members = depths
                .into_iter()
                .map(|(id, depth)| (depth, id))
                .collect::<Vec<_>>();
            members.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| left.1.cmp(&right.1)));
            (
                ArchiveScopeSeal {
                    admission: seal(&self.0, &mut state, ids),
                    members,
                    identities,
                    private_ids,
                },
                cancellation,
            )
        };
        for token in cancellation {
            token.cancel();
        }
        Ok(scope)
    }

    /// Joins admitted permits/preparations, then serially disposes retained unpublished owners.
    /// The caller first interrupts visible work and retains `scope` until directory publication.
    pub(crate) async fn drain_archive_preparations(
        &self,
        scope: &ArchiveScopeSeal,
    ) -> Result<(), ThreadAssemblyError> {
        if !scope
            .admission
            .registry
            .upgrade()
            .is_some_and(|registry| Arc::ptr_eq(&registry, &self.0))
        {
            return Err(ThreadAssemblyError::Identity(
                "archive registry changed".into(),
            ));
        }
        // Never hold a child permit while awaiting its parent's spawn operation: that operation
        // can be waiting for the same child's retained disposal.
        for (_, id) in &scope.members {
            drop(self.agent_operation(id).await);
        }
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let preparing = {
                let state = self.0.state();
                scope.members.iter().any(|(_, id)| {
                    state.creating.contains_key(id) || state.preparing_children.contains_key(id)
                })
            };
            if !preparing {
                break;
            }
            changed.await;
        }
        for (_, id) in &scope.members {
            self.discard_unpublished_child(id).await?;
        }
        Ok(())
    }

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
        disposition: WorkspaceRelease,
    ) -> Result<AgentOperationSeal, ThreadAssemblyError> {
        let mut ids = targets.iter().map(|(_, id)| id).collect::<Vec<_>>();
        ids.sort();
        ids.dedup();
        let close_seal = {
            let mut state = self.0.state();
            if let Some(id) = ids
                .iter()
                .find(|id| state.sealed_agents.contains_key(id.as_str()))
            {
                return Err(ThreadAssemblyError::CloseDisposition((*id).clone()));
            }
            seal(
                &self.0,
                &mut state,
                ids.iter().map(|id| (*id).clone()).collect(),
            )
        };
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
                    entry.ready = false;
                }
            }
        }
        Ok(close_seal)
    }

    /// Caller holds this identity's operation permit and has just successfully flushed its close
    /// intent. An in-memory marker after a failed flush never authorizes publishing a new policy.
    pub(super) fn freeze_agent_close_disposition(
        &self,
        id: &str,
        disposition: WorkspaceRelease,
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
        &self,
        id: &str,
        incarnation: &Arc<()>,
    ) -> Result<(), ThreadAssemblyError> {
        let cleanup = {
            let state = self.0.state();
            if state.unpublished_children.contains_key(id) {
                return Ok(());
            }
            state
                .entries
                .get(id)
                .filter(|entry| {
                    entry.parent_id.is_some() && Arc::ptr_eq(&entry.incarnation, incarnation)
                })
                .map(|entry| entry.cleanup.clone())
        };
        let Some(cleanup) = cleanup else {
            return Ok(());
        };
        let _permit = cleanup.acquire().await;
        let resource = {
            let state = self.0.state();
            state
                .entries
                .get(id)
                .filter(|entry| {
                    !entry.published_resources_closed
                        && Arc::ptr_eq(&entry.incarnation, incarnation)
                })
                .and_then(|entry| {
                    state.child_factory.clone().map(|factory| {
                        let disposition = entry.workspace_disposition.unwrap_or_default();
                        (factory, disposition)
                    })
                })
        };
        if let Some((factory, disposition)) = resource {
            factory.close_published(id, disposition).await?;
            if let Some(entry) = self.0.state().entries.get_mut(id)
                && Arc::ptr_eq(&entry.incarnation, incarnation)
            {
                entry.published_resources_closed = true;
            }
        }
        Ok(())
    }
}
