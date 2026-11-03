//! Root-scoped pending child interaction projection.

use anyhow::Result;
use pl_core::thread::{ThreadLifecycle, ThreadSnapshot};
use pl_protocol::{ChildInteractionSummary, ObservedResource, SessionDirectoryRow};

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
        let state = resource_state(&projection, host_thread_id);
        StudioChildInteractionsState {
            host_thread_id: host_thread_id.to_owned(),
            state,
        }
    }

    /// Initializes directory membership without emitting a collection event.
    ///
    /// Root preparation calls this before observation/reconciliation. Existing revisions and child
    /// sequence watermarks are retained across warm-up and restore.
    pub(super) fn prepare_child_interaction_directory(&self, entries: &[SessionDirectoryRow]) {
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
        thread_id: &str,
        snapshot: &ThreadSnapshot,
    ) -> Result<Option<StudioProductEventEnvelope>> {
        let summaries = if snapshot.lifecycle == ThreadLifecycle::Open {
            crate::thread_assembler::project_pending_child_interactions(thread_id, snapshot)?
        } else {
            Vec::new()
        };
        let catalog = self.store.catalog();
        let current = catalog.agent_by_thread(thread_id);
        let eligible = current.as_ref().is_some_and(|agent| {
            catalog
                .get_session(&agent.session_id)
                .is_some_and(|session| {
                    !session.archived
                        && agent.parent_agent_id.as_deref() == Some(session.root_agent_id.as_str())
                })
        });
        let changed = {
            let mut projection = self
                .child_interactions
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            update_member(
                &mut projection,
                thread_id,
                snapshot.commit_sequence,
                summaries,
                eligible,
            )
        };
        Ok(changed.map(|state| self.emit(StudioProductEventKind::ChildInteractionsChanged(state))))
    }
}

pub(super) fn prepare_entries(
    projection: &mut ChildInteractionsProjection,
    entries: &[SessionDirectoryRow],
) {
    for row in entries {
        // A root directory row does not prove that its children's pending facts were loaded.
        // The host is established by actual child membership/facts, never by a fabricated empty set.
        let direct_host = row
            .parent_agent_id
            .as_deref()
            .filter(|parent| *parent == row.session_id)
            .filter(|_| !row.archived);
        if let Some(host_thread_id) = direct_host {
            initialize_host(projection, host_thread_id);
            let member = projection
                .members
                .entry(row.thread_id.clone())
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
            let was_ready = host_ready(projection, id);
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
                || !was_ready
            {
                changed_hosts.insert(id.clone());
            }
        }
        if let Some(member) = projection.members.get_mut(id) {
            let was_unprepared = member.active && member.commit_sequence.is_none();
            member.active = false;
            let host_thread_id = member.host_thread_id.clone();
            if projection
                .hosts
                .get_mut(&host_thread_id)
                .is_some_and(|host| host.children.remove(id).is_some())
                || was_unprepared
            {
                changed_hosts.insert(host_thread_id);
            }
        }
    }
    let mut changed = Vec::new();
    for host_thread_id in changed_hosts {
        if host_ready(projection, &host_thread_id) {
            changed.push(changed_state(projection, &host_thread_id));
        }
    }
    changed
}

fn update_member(
    projection: &mut ChildInteractionsProjection,
    thread_id: &str,
    commit_sequence: u64,
    summaries: Vec<ChildInteractionSummary>,
    eligible: bool,
) -> Option<StudioChildInteractionsState> {
    // Only the authoritative directory establishes membership. A snapshot alone cannot prove
    // that the host's complete roster was registered; the host is the registered member's
    // directory parent (a direct child of the session root), never a Native snapshot field.
    let host_thread_id = projection.members.get(thread_id)?.host_thread_id.clone();
    let was_ready = host_ready(projection, &host_thread_id);
    let member = projection.members.get_mut(thread_id)?;
    if !eligible
        || !member.active
        || member
            .commit_sequence
            .is_some_and(|applied| commit_sequence <= applied)
    {
        return None;
    }
    member.commit_sequence = Some(commit_sequence);
    let host = projection
        .hosts
        .get_mut(&host_thread_id)
        .expect("child interaction host initialized");
    let changed = if summaries.is_empty() {
        host.children.remove(thread_id).is_some()
    } else if host.children.get(thread_id) == Some(&summaries) {
        false
    } else {
        host.children.insert(thread_id.to_owned(), summaries);
        true
    };
    (host_ready(projection, &host_thread_id) && (changed || !was_ready))
        .then(|| changed_state(projection, &host_thread_id))
}

fn host_ready(projection: &ChildInteractionsProjection, host_thread_id: &str) -> bool {
    projection.hosts.contains_key(host_thread_id)
        && !projection.members.values().any(|member| {
            member.active
                && member.host_thread_id == host_thread_id
                && member.commit_sequence.is_none()
        })
}

fn resource_state(
    projection: &ChildInteractionsProjection,
    host_thread_id: &str,
) -> ObservedResource<Vec<ChildInteractionSummary>> {
    match projection.hosts.get(host_thread_id) {
        Some(host) if host_ready(projection, host_thread_id) => {
            ObservedResource::ready(host.revision, host.updated_at, flatten(host))
        }
        _ => ObservedResource::uninitialized(0),
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    fn directory_row(id: &str) -> SessionDirectoryRow {
        SessionDirectoryRow {
            session_id: id.into(),
            agent_id: id.into(),
            parent_agent_id: None,
            thread_id: id.into(),
            workspace_id: String::new(),
            title: String::new(),
            mode: pl_protocol::ThreadModeId::simple(),
            workspace_mode: pl_protocol::ThreadWorkspaceMode::Local,
            delegation_mode: Default::default(),
            delegation_preference: Default::default(),
            workspace_path: String::new(),
            role: String::new(),
            binding: pl_protocol::AgentBinding::Native(pl_protocol::NativeAgentConfig {
                route: None,
                system_instructions: None,
            }),
            status: pl_protocol::ThreadStatus::Idle,
            created_at: 0,
            updated_at: 0,
            last_user_message_at: None,
            archived: false,
        }
    }

    fn child(id: &str, host: &str) -> SessionDirectoryRow {
        let mut row = directory_row(id);
        row.session_id = host.to_owned();
        row.parent_agent_id = Some(host.to_owned());
        row
    }

    #[test]
    fn directory_membership_does_not_publish_an_unprepared_empty_collection() {
        let mut projection = ChildInteractionsProjection::default();
        prepare_entries(&mut projection, &[directory_row("root")]);
        assert!(matches!(
            resource_state(&projection, "root"),
            ObservedResource::Uninitialized(_)
        ));

        let first = child("first", "root");
        let second = child("second", "root");
        prepare_entries(&mut projection, &[first.clone(), second.clone()]);
        assert!(matches!(
            resource_state(&projection, "root"),
            ObservedResource::Uninitialized(_)
        ));
        assert!(update_member(&mut projection, "first", 7, vec![], true).is_none());
        assert!(matches!(
            resource_state(&projection, "root"),
            ObservedResource::Uninitialized(_)
        ));

        let ready = update_member(&mut projection, "second", 9, vec![], true)
            .expect("the last authoritative member establishes the complete empty set");
        assert!(matches!(&ready.state, ObservedResource::Ready(_)));
        assert!(ready.state.value().unwrap().is_empty());
        let revision = ready.state.revision();
        assert!(update_member(&mut projection, "first", 8, vec![], true).is_none());
        assert_eq!(resource_state(&projection, "root").revision(), revision);
    }

    #[test]
    fn removing_an_unprepared_member_can_establish_only_its_hosts_empty_collection() {
        let mut projection = ChildInteractionsProjection::default();
        let first = child("first", "root");
        let second = child("second", "root");
        let other = child("other", "another-root");
        prepare_entries(&mut projection, &[first.clone(), second.clone(), other]);
        assert!(update_member(&mut projection, "first", 3, vec![], true).is_none());
        let changed = remove_entries(&mut projection, std::slice::from_ref(&second.thread_id));
        assert_eq!(changed.len(), 1);
        assert_eq!(changed[0].host_thread_id, "root");
        assert!(matches!(&changed[0].state, ObservedResource::Ready(_)));
        assert!(changed[0].state.value().unwrap().is_empty());
        assert!(matches!(
            resource_state(&projection, "another-root"),
            ObservedResource::Uninitialized(_)
        ));
    }
}
