//! Deferred, exact AgentDirectory values. Writers record only coalesced inverse member changes.
//!
//! A queued or dequeued publication owns its version until materialization ends. Live versions
//! are bounded by the broadcast buffers, in-flight receivers and the current publication,
//! not the number of mutations.
//! Each reverse map stores only differences from that version: returning to its original value
//! removes an entry, including a member created and then deleted after the version. Its size is
//! bounded by that version's member count plus the current member count.
//!
//! Lock order: directory index -> topic registry -> live-version registry. Recording releases
//! the live-version registry before taking individual reverse maps or dropping upgraded leases.
//! Drop only takes the live-version registry; send/eviction never holds that registry's lock.

use super::*;
use std::collections::btree_map::Entry;

#[derive(Default)]
pub(in crate::studio::product_event_bus) struct AgentDirectoryHistory {
    versions: Mutex<BTreeMap<u64, Weak<DeferredAgentDirectory>>>,
}

pub(in crate::studio::product_event_bus) struct DeferredAgentDirectory {
    revision: u64,
    updated_at: i64,
    index: Arc<Mutex<ThreadDirectoryIndex>>,
    history: Arc<AgentDirectoryHistory>,
    reverse: Mutex<BTreeMap<String, Option<StudioAgentDirectoryEntry>>>,
}

impl AgentDirectoryHistory {
    /// The caller owns the index through mutation, inverse recording and publication.
    pub(super) fn record(&self, changes: &AgentDirectoryChanges) {
        // Keep upgraded leases outside the registry lock: the last lease's Drop takes it too.
        let versions = self
            .versions
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .values()
            .filter_map(Weak::upgrade)
            .collect::<Vec<_>>();
        let after = changes
            .upserted
            .iter()
            .map(|entry| (entry.agent_id.as_str(), Some(entry)))
            .chain(changes.removed.iter().map(|id| (id.as_str(), None)))
            .collect::<BTreeMap<_, _>>();
        for version in &versions {
            let mut reverse = version
                .reverse
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            for (id, previous) in &changes.previous {
                let current = *after
                    .get(id.as_str())
                    .expect("changed member has a current value");
                match reverse.entry(id.clone()) {
                    Entry::Vacant(entry) => {
                        entry.insert(previous.clone());
                    }
                    Entry::Occupied(entry) if entry.get().as_ref() == current => {
                        entry.remove();
                    }
                    Entry::Occupied(_) => {}
                }
            }
        }
        tracing::trace!(
            patched_versions = versions.len(),
            patched_members = changes.previous.len(),
            "retain inverse agent directory changes"
        );
    }

    pub(in crate::studio::product_event_bus) fn capture(
        self: &Arc<Self>,
        index: Arc<Mutex<ThreadDirectoryIndex>>,
        revision: u64,
        updated_at: i64,
    ) -> Arc<DeferredAgentDirectory> {
        let version = Arc::new(DeferredAgentDirectory {
            revision,
            updated_at,
            index,
            history: self.clone(),
            reverse: Mutex::default(),
        });
        self.versions
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(revision, Arc::downgrade(&version));
        version
    }
}

impl DeferredAgentDirectory {
    pub(in crate::studio::product_event_bus) fn materialize(&self) -> StudioAgentDirectoryState {
        let index = self
            .index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let reverse = self
            .reverse
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut agents = index
            .agent_directory_entries()
            .into_iter()
            .map(|entry| (entry.agent_id.clone(), entry))
            .collect::<BTreeMap<_, _>>();
        for (id, previous) in reverse.iter() {
            match previous {
                Some(entry) => {
                    agents.insert(id.clone(), entry.clone());
                }
                None => {
                    agents.remove(id);
                }
            }
        }
        StudioAgentDirectoryState {
            state: crate::ObservedResource::ready(
                self.revision,
                self.updated_at,
                StudioAgentDirectoryData {
                    agents: agents.into_values().collect(),
                },
            ),
        }
    }
}

impl Drop for DeferredAgentDirectory {
    fn drop(&mut self) {
        self.history
            .versions
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .remove(&self.revision);
    }
}

#[cfg(test)]
mod tests;
