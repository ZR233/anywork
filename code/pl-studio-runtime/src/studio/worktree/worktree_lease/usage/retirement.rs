//! Retirement seals and exclusive physical removal permits.
use super::{
    Seal, UsageTarget, WorkspaceCloseSeal, WorkspaceIdentity, WorkspaceRemovalPermit,
    WorkspaceUsageLease, WorktreeLeaseOwner, lock_state,
};
use anyhow::{Context, Result, ensure};
use std::collections::BTreeSet;
use std::sync::{Arc, Weak};

impl WorktreeLeaseOwner {
    pub(in crate::studio) fn try_seal_workspace(
        &self,
        owner: &str,
        identity: WorkspaceIdentity,
        closing: &BTreeSet<String>,
    ) -> Result<WorkspaceCloseSeal> {
        let mut state = lock_state(&self.state);
        let blockers = state.workspace.blockers(&identity, closing);
        ensure!(
            blockers.is_empty(),
            "workspace is still used or resolving by agents: {}",
            blockers.into_iter().collect::<Vec<_>>().join(", ")
        );
        if let Some(seal) = state.workspace.seals.get(owner) {
            ensure!(
                seal.identity == identity,
                "retirement workspace identity changed"
            );
            return Ok(WorkspaceCloseSeal {
                owner: self.clone(),
                id: owner.into(),
                serial: seal.serial,
            });
        }
        let serial = state.workspace.next()?;
        state.workspace.seals.insert(
            owner.into(),
            Seal {
                identity,
                serial,
                durable: false,
            },
        );
        Ok(WorkspaceCloseSeal {
            owner: self.clone(),
            id: owner.into(),
            serial,
        })
    }
    pub(in crate::studio) fn restore_workspace_seal(
        &self,
        owner: &str,
        identity: WorkspaceIdentity,
    ) -> Result<()> {
        let mut state = lock_state(&self.state);
        if let Some(seal) = state.workspace.seals.get_mut(owner) {
            ensure!(
                seal.identity == identity,
                "durable workspace seal changed identity"
            );
            seal.durable = true;
            return Ok(());
        }
        let serial = state.workspace.next()?;
        state.workspace.seals.insert(
            owner.into(),
            Seal {
                identity,
                serial,
                durable: true,
            },
        );
        Ok(())
    }

    /// Physical deletion admission ends after its durable terminal result, not agent reopening.
    pub(in crate::studio) fn release_workspace_seal(
        &self,
        owner: &str,
        identity: &WorkspaceIdentity,
    ) -> Result<()> {
        let mut state = lock_state(&self.state);
        ensure!(
            !state.workspace.removals.values().any(|(id, _)| id == owner),
            "workspace removal owner has not finished"
        );
        ensure!(
            state
                .workspace
                .seals
                .get(owner)
                .is_none_or(|seal| seal.identity == *identity),
            "completed workspace seal identity changed"
        );
        state.workspace.seals.remove(owner);
        state.workspace.resources.remove(owner);
        Ok(())
    }
    pub(in crate::studio) fn begin_workspace_removal(
        &self,
        owner: &str,
        identity: &WorkspaceIdentity,
    ) -> Result<WorkspaceRemovalPermit> {
        self.begin_removal(owner, identity, None, true)
    }

    /// A reversible root archive, Recovery cleanup or failed creation does not permanently retire
    /// the assigned path. Its exact preparer may transfer to cleanup, but no other live use may.
    pub(in crate::studio) fn begin_workspace_cleanup(
        &self,
        owner: &str,
        identity: &WorkspaceIdentity,
        usage: Option<&WorkspaceUsageLease>,
    ) -> Result<WorkspaceRemovalPermit> {
        self.begin_removal(owner, identity, usage, false)
    }

    fn begin_removal(
        &self,
        owner: &str,
        identity: &WorkspaceIdentity,
        usage: Option<&WorkspaceUsageLease>,
        permanent: bool,
    ) -> Result<WorkspaceRemovalPermit> {
        if let Some(usage) = usage {
            ensure!(
                Weak::ptr_eq(&usage.0.state, &Arc::downgrade(&self.state))
                    && Arc::strong_count(&usage.0) == 1,
                "workspace preparation still has another live owner: {owner}"
            );
        }
        let mut state = lock_state(&self.state);
        if permanent {
            let seal = state
                .workspace
                .seals
                .get(owner)
                .context("workspace removal has no retirement seal")?;
            ensure!(
                seal.durable && seal.identity == *identity,
                "workspace removal seal identity or phase changed"
            );
        }
        let serial = state.workspace.next()?;
        ensure!(
            state.workspace.resources.get(owner).is_none_or(
                |target| matches!(target, UsageTarget::Assigned(actual) if actual == identity)
            ),
            "workspace removal resource identity changed"
        );
        // The caller has joined its actual runtime owners. Transfer only its remaining
        // Git resource into this cleanup permit atomically; every actual use (including its own
        // preparer/Entry) and every other pending cleanup owner still has to be absent.
        if let Some(usage) = usage {
            let entry = state
                .workspace
                .active
                .get(&usage.0.serial)
                .context("workspace preparer is no longer registered")?;
            ensure!(
                entry.owner == owner
                    && matches!(&entry.target, UsageTarget::Assigned(actual) if actual == identity),
                "cleanup preparer identity changed"
            );
        }
        let resources = state.workspace.resources.remove(owner);
        let transferred = usage.and_then(|usage| state.workspace.active.remove(&usage.0.serial));
        let blockers = state.workspace.blockers(identity, &BTreeSet::new());
        if !blockers.is_empty() {
            if let Some(resources) = resources {
                state.workspace.resources.insert(owner.into(), resources);
            }
            if let Some(entry) = transferred {
                state
                    .workspace
                    .active
                    .insert(usage.unwrap().0.serial, entry);
            }
            anyhow::bail!(
                "workspace cleanup is blocked by agents: {}",
                blockers.into_iter().collect::<Vec<_>>().join(", ")
            );
        }
        state
            .workspace
            .removals
            .insert(serial, (owner.into(), identity.clone()));
        Ok(WorkspaceRemovalPermit {
            owner: self.clone(),
            id: owner.into(),
            serial,
            resources,
            usage: transferred.map(|entry| (usage.unwrap().clone(), entry)),
        })
    }
    pub(in crate::studio) fn ensure_thread_workspace_idle(&self, owner: &str) -> Result<()> {
        self.ensure_thread_workspace_idle_except(owner, None)
    }

    pub(in crate::studio) fn ensure_thread_workspace_idle_except(
        &self,
        owner: &str,
        usage: Option<&WorkspaceUsageLease>,
    ) -> Result<()> {
        if let Some(usage) = usage {
            ensure!(
                Weak::ptr_eq(&usage.0.state, &Arc::downgrade(&self.state))
                    && Arc::strong_count(&usage.0) == 1,
                "workspace preparation still has another live owner: {owner}"
            );
            ensure!(
                self.usage_owner(usage)? == owner,
                "workspace cleanup owner changed"
            );
        }
        let state = lock_state(&self.state);
        ensure!(
            !state
                .workspace
                .active
                .values()
                .any(|entry| entry.owner == owner
                    && !usage.is_some_and(|usage| state
                        .workspace
                        .active
                        .get(&usage.0.serial)
                        .is_some_and(|allowed| std::ptr::eq(allowed, entry)))),
            "workspace preparation or execution is still owned by {owner}"
        );
        Ok(())
    }
}
