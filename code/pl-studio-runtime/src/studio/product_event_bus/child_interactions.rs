//! Root-scoped pending child interaction projection.

use anyhow::Result;
use pl_core::thread::{ThreadLifecycle, ThreadSnapshot};
use pl_protocol::{ChildInteractionSummary, ObservedResource, Thread};

use crate::{StudioChildInteractionsState, StudioProductEventEnvelope, StudioProductEventKind};

use super::{
    ChildInteractionsHost, ChildInteractionsMember, ChildInteractionsProjection, ProductEventBus,
};

impl ProductEventBus {
    /// Reads the already-published projection for one root. This never initializes or refreshes it.
    pub fn read_child_interactions_state(
        &self,
        host_thread_id: &str,
    ) -> StudioChildInteractionsState {
        let projection = self
            .child_interactions
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let state = match projection.hosts.get(host_thread_id) {
            Some(host) => ObservedResource::ready(host.revision, host.updated_at, flatten(host)),
            None => ObservedResource::uninitialized(0),
        };
        StudioChildInteractionsState {
            host_thread_id: host_thread_id.to_owned(),
            state,
        }
    }

    /// Initializes directory membership without emitting a collection event.
    ///
    /// Root preparation calls this before observation/reconciliation. Existing revisions and child
    /// sequence watermarks are retained across warm-up and restore.
    pub(super) fn prepare_child_interaction_directory(&self, entries: &[Thread]) {
        let mut projection = self
            .child_interactions
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        prepare_entries(&mut projection, entries);
    }

    /// Applies directory removals to the projection and emits only hosts whose visible collection
    /// really changed.
    pub(super) fn remove_child_interaction_directory(&self, removed: &[String]) {
        let changed = {
            let mut projection = self
                .child_interactions
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            remove_entries(&mut projection, removed)
        };
        for state in changed {
            self.emit(StudioProductEventKind::ChildInteractionsChanged(state));
        }
    }

    /// Applies one authoritative hot or cold child snapshot.
    ///
    /// Projection happens before locking. The critical section only verifies current directory
    /// ownership, compares the original Thread commit sequence and replaces one child's summaries.
    pub(in crate::studio) fn update_child_interactions(
        &self,
        thread: &Thread,
        snapshot: &ThreadSnapshot,
    ) -> Result<Option<StudioProductEventEnvelope>> {
        let summaries = if snapshot.lifecycle == ThreadLifecycle::Open {
            crate::thread_assembler::project_pending_child_interactions(&thread.id, snapshot)?
        } else {
            Vec::new()
        };
        let current = self.store.catalog().get(&thread.id);
        let eligible = current.as_ref().is_some_and(|record| {
            !record.archived
                && record.parent_thread_id.as_deref() == Some(record.root_thread_id.as_str())
        });
        let changed = {
            let mut projection = self
                .child_interactions
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            update_member(
                &mut projection,
                thread,
                snapshot.commit_sequence,
                summaries,
                eligible,
            )
        };
        Ok(changed.map(|state| self.emit(StudioProductEventKind::ChildInteractionsChanged(state))))
    }
}

fn prepare_entries(projection: &mut ChildInteractionsProjection, entries: &[Thread]) {
    for thread in entries {
        if thread.parent_thread_id.is_none() && !thread.archived {
            initialize_host(projection, &thread.id);
        }
        let direct_host = thread
            .parent_thread_id
            .as_deref()
            .filter(|parent| *parent == thread.root_thread_id)
            .filter(|_| !thread.archived);
        if let Some(host_thread_id) = direct_host {
            initialize_host(projection, host_thread_id);
            let member = projection
                .members
                .entry(thread.id.clone())
                .or_insert_with(|| ChildInteractionsMember {
                    host_thread_id: host_thread_id.to_owned(),
                    commit_sequence: None,
                    active: true,
                });
            member.host_thread_id = host_thread_id.to_owned();
            member.active = true;
        }
    }
}

fn remove_entries(
    projection: &mut ChildInteractionsProjection,
    removed: &[String],
) -> Vec<StudioChildInteractionsState> {
    let mut changed_hosts = std::collections::BTreeSet::new();
    for id in removed {
        if projection.hosts.contains_key(id) {
            let member_ids = projection
                .members
                .iter()
                .filter(|(_, member)| member.host_thread_id == *id)
                .map(|(member_id, _)| member_id.clone())
                .collect::<Vec<_>>();
            for member_id in member_ids {
                if let Some(member) = projection.members.get_mut(&member_id) {
                    member.active = false;
                }
            }
            if projection
                .hosts
                .get_mut(id)
                .is_some_and(|host| !std::mem::take(&mut host.children).is_empty())
            {
                changed_hosts.insert(id.clone());
            }
        }
        if let Some(member) = projection.members.get_mut(id) {
            member.active = false;
            let host_thread_id = member.host_thread_id.clone();
            if projection
                .hosts
                .get_mut(&host_thread_id)
                .is_some_and(|host| host.children.remove(id).is_some())
            {
                changed_hosts.insert(host_thread_id);
            }
        }
    }
    changed_hosts
        .into_iter()
        .map(|host_thread_id| changed_state(projection, &host_thread_id))
        .collect()
}

fn update_member(
    projection: &mut ChildInteractionsProjection,
    thread: &Thread,
    commit_sequence: u64,
    summaries: Vec<ChildInteractionSummary>,
    eligible: bool,
) -> Option<StudioChildInteractionsState> {
    let host_thread_id = thread.parent_thread_id.as_deref()?;
    if host_thread_id != thread.root_thread_id {
        return None;
    }
    initialize_host(projection, host_thread_id);
    let member = projection
        .members
        .entry(thread.id.clone())
        .or_insert_with(|| ChildInteractionsMember {
            host_thread_id: host_thread_id.to_owned(),
            commit_sequence: None,
            active: eligible,
        });
    if !eligible
        || !member.active
        || member.host_thread_id != host_thread_id
        || member
            .commit_sequence
            .is_some_and(|applied| commit_sequence <= applied)
    {
        return None;
    }
    member.commit_sequence = Some(commit_sequence);
    let host = projection
        .hosts
        .get_mut(host_thread_id)
        .expect("child interaction host initialized");
    let changed = if summaries.is_empty() {
        host.children.remove(&thread.id).is_some()
    } else if host.children.get(&thread.id) == Some(&summaries) {
        false
    } else {
        host.children.insert(thread.id.clone(), summaries);
        true
    };
    changed.then(|| changed_state(projection, host_thread_id))
}

fn initialize_host(projection: &mut ChildInteractionsProjection, host_thread_id: &str) {
    projection
        .hosts
        .entry(host_thread_id.to_owned())
        .or_insert_with(|| ChildInteractionsHost {
            revision: 1,
            updated_at: crate::studio::unix_seconds(),
            children: Default::default(),
        });
}

fn changed_state(
    projection: &mut ChildInteractionsProjection,
    host_thread_id: &str,
) -> StudioChildInteractionsState {
    let host = projection
        .hosts
        .get_mut(host_thread_id)
        .expect("changed child interaction host exists");
    host.revision = host
        .revision
        .checked_add(1)
        .expect("child interaction revision exhausted");
    host.updated_at = crate::studio::unix_seconds();
    StudioChildInteractionsState {
        host_thread_id: host_thread_id.to_owned(),
        state: ObservedResource::ready(host.revision, host.updated_at, flatten(host)),
    }
}

fn flatten(host: &ChildInteractionsHost) -> Vec<ChildInteractionSummary> {
    host.children
        .values()
        .flat_map(|summaries| summaries.iter().cloned())
        .collect()
}
