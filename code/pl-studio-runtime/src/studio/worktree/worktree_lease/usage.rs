//! Physical workspace admission shares the canonical lease owner's one short mutex.
mod binding;
mod retirement;
use super::{
    LeaseOwnerState, WorkspaceEndpoint, WorkspaceIdentity, WorktreeLeaseOwner, lock_state,
};
use anyhow::{Context, Result, ensure};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{Arc, Mutex, Weak},
};

#[derive(Debug, Clone)]
enum UsageTarget {
    Resolving(WorkspaceEndpoint),
    Assigned(WorkspaceIdentity),
    LegacySshWorktree(String),
}
impl UsageTarget {
    fn may_use(&self, target: &WorkspaceIdentity) -> bool {
        match self {
            Self::Resolving(endpoint) => *endpoint == target.endpoint,
            Self::Assigned(identity) => identity.within(target),
            Self::LegacySshWorktree(root) => {
                matches!(target.endpoint, WorkspaceEndpoint::Ssh { .. })
                    && (root == &target.root
                        || root
                            .strip_prefix(target.root.trim_end_matches('/'))
                            .is_some_and(|suffix| suffix.starts_with('/')))
            }
        }
    }
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum UsagePurpose {
    Execution,
    CleanupResolution,
}
struct Usage {
    owner: String,
    target: UsageTarget,
    purpose: UsagePurpose,
}
struct Seal {
    identity: WorkspaceIdentity,
    durable: bool,
    serial: u64,
}

#[derive(Default)]
pub(super) struct WorkspaceAdmission {
    serial: u64,
    active: BTreeMap<u64, Usage>,
    resources: BTreeMap<String, UsageTarget>,
    seals: BTreeMap<String, Seal>,
    removals: BTreeMap<u64, (String, WorkspaceIdentity)>,
}
impl WorkspaceAdmission {
    pub(super) fn preserve_restored_lease(
        &mut self,
        lease: &super::WorktreeLease,
        identity: Option<WorkspaceIdentity>,
    ) {
        if lease.state == super::WorktreeLeaseState::Cleaned
            || self.resources.contains_key(&lease.owner_thread_id)
        {
            return;
        }
        let target = if let Some(identity) = identity {
            UsageTarget::Assigned(identity)
        } else if lease.ssh_alias.is_some() {
            // A pre-identity SSH lease does not prove an endpoint. Its original Git-derived
            // canonical path remains protected at any matching SSH site, never rebound by scan.
            UsageTarget::LegacySshWorktree(lease.path.clone())
        } else {
            match WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, lease.path.clone()) {
                Ok(identity) => UsageTarget::Assigned(identity),
                Err(_) => UsageTarget::Resolving(WorkspaceEndpoint::Local),
            }
        };
        self.resources.insert(lease.owner_thread_id.clone(), target);
    }
    pub(super) fn is_retiring(&self, id: &str) -> bool {
        self.seals.contains_key(id)
    }
    pub(super) fn is_removing(&self, id: &str) -> bool {
        self.removals.values().any(|(owner, _)| owner == id)
    }
    fn sealing_owners<'a>(
        &'a self,
        identity: &'a WorkspaceIdentity,
    ) -> impl Iterator<Item = &'a str> {
        self.seals
            .iter()
            .filter(|(_, seal)| identity.within(&seal.identity))
            .map(|(owner, _)| owner.as_str())
            .chain(
                self.removals
                    .values()
                    .filter(|(_, target)| identity.within(target))
                    .map(|(owner, _)| owner.as_str()),
            )
    }
    fn next(&mut self) -> Result<u64> {
        self.serial = self
            .serial
            .checked_add(1)
            .context("workspace admission serial exhausted")?;
        Ok(self.serial)
    }
    fn blockers(
        &self,
        identity: &WorkspaceIdentity,
        allowed: &BTreeSet<String>,
    ) -> BTreeSet<String> {
        self.active
            .values()
            .filter(|usage| !allowed.contains(&usage.owner) && usage.target.may_use(identity))
            .map(|usage| usage.owner.clone())
            .chain(
                self.resources
                    .iter()
                    .filter(|(owner, target)| !allowed.contains(*owner) && target.may_use(identity))
                    .map(|(owner, _)| owner.clone()),
            )
            .chain(
                self.removals
                    .values()
                    .filter(|(owner, target)| !allowed.contains(owner) && target.within(identity))
                    .map(|(owner, _)| owner.clone()),
            )
            .collect()
    }
}

struct UsageToken {
    state: Weak<Mutex<LeaseOwnerState>>,
    serial: u64,
}
impl Drop for UsageToken {
    fn drop(&mut self) {
        if let Some(state) = self.state.upgrade() {
            let removed = lock_state(&state).workspace.active.remove(&self.serial);
            drop(removed);
        }
    }
}
/// Opaque Studio workspace use; only the canonical product owner can issue or assign it.
#[derive(Clone)]
pub struct WorkspaceUsageLease(Arc<UsageToken>);

#[derive(Clone)]
pub(crate) struct WeakWorkspaceUsageLease(Weak<UsageToken>);

impl WorkspaceUsageLease {
    pub(crate) fn downgrade(&self) -> WeakWorkspaceUsageLease {
        WeakWorkspaceUsageLease(Arc::downgrade(&self.0))
    }
}

impl WeakWorkspaceUsageLease {
    pub(crate) fn upgrade(&self) -> Option<WorkspaceUsageLease> {
        self.0.upgrade().map(WorkspaceUsageLease)
    }
}
/// An already-admitted write, not a durable binding proof.
pub(in crate::studio) struct VerifiedBindingWrite {
    confirmed: super::WorktreeLease,
    ticket: u64,
    identity: WorkspaceIdentity,
}
impl std::fmt::Debug for WorkspaceUsageLease {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_tuple("WorkspaceUsageLease")
            .field(&self.0.serial)
            .finish()
    }
}

/// No implicit unseal on Drop: the managed job must adjudicate the product write outcome first.
pub(in crate::studio) struct WorkspaceCloseSeal {
    owner: WorktreeLeaseOwner,
    id: String,
    serial: u64,
}
pub(in crate::studio) struct WorkspaceRemovalPermit {
    owner: WorktreeLeaseOwner,
    id: String,
    serial: u64,
    resources: Option<UsageTarget>,
    usage: Option<(WorkspaceUsageLease, Usage)>,
}
impl WorkspaceRemovalPermit {
    pub(in crate::studio) fn complete(mut self) {
        self.resources = None;
    }
}
impl Drop for WorkspaceRemovalPermit {
    fn drop(&mut self) {
        let usage = self.usage.take();
        let removed = {
            let mut state = lock_state(&self.owner.state);
            let removed = state.workspace.removals.remove(&self.serial);
            if let Some(resources) = self.resources.take() {
                state.workspace.resources.insert(self.id.clone(), resources);
            }
            if let Some((token, entry)) = usage.as_ref() {
                state.workspace.active.insert(
                    token.0.serial,
                    Usage {
                        owner: entry.owner.clone(),
                        target: entry.target.clone(),
                        purpose: entry.purpose,
                    },
                );
            }
            removed
        };
        drop(removed);
        drop(usage);
    }
}
impl WorkspaceCloseSeal {
    pub(in crate::studio) fn durable(&self) -> Result<()> {
        let mut state = lock_state(&self.owner.state);
        let seal = state
            .workspace
            .seals
            .get_mut(&self.id)
            .context("retirement admission seal disappeared")?;
        ensure!(
            seal.serial == self.serial,
            "retirement admission seal identity changed"
        );
        seal.durable = true;
        Ok(())
    }
}

impl WorktreeLeaseOwner {
    pub(in crate::studio) async fn reserve_project_workspace(
        &self,
        owner: &str,
        ssh: &pl_tool::remote::SshManager,
        project: &crate::studio::WorkspaceRecord,
    ) -> Result<WorkspaceUsageLease> {
        let profile = match project.ssh_alias.as_deref() {
            Some(alias) => Some(
                ssh.list_servers()
                    .await
                    .into_iter()
                    .find(|entry| entry.profile.alias == alias)
                    .context("workspace SSH endpoint is not configured")?
                    .profile,
            ),
            None => None,
        };
        self.reserve_workspace(owner, WorkspaceEndpoint::from_profile(profile.as_ref()))
    }
    pub(in crate::studio) fn reserve_workspace(
        &self,
        owner: &str,
        endpoint: WorkspaceEndpoint,
    ) -> Result<WorkspaceUsageLease> {
        let mut state = lock_state(&self.state);
        let deleting = state
            .workspace
            .removals
            .values()
            .filter(|(_, identity)| identity.endpoint == endpoint)
            .map(|(owner, _)| owner.clone())
            .collect::<Vec<_>>();
        ensure!(
            deleting.is_empty(),
            "workspace resolution is temporarily sealed for removal by agents: {}",
            deleting.join(", ")
        );
        let serial = state.workspace.next()?;
        state.workspace.active.insert(
            serial,
            Usage {
                owner: owner.into(),
                target: UsageTarget::Resolving(endpoint),
                purpose: UsagePurpose::Execution,
            },
        );
        Ok(WorkspaceUsageLease(Arc::new(UsageToken {
            state: Arc::downgrade(&self.state),
            serial,
        })))
    }
    pub(in crate::studio) fn assign_workspace(
        &self,
        usage: &WorkspaceUsageLease,
        identity: WorkspaceIdentity,
    ) -> Result<()> {
        ensure!(
            Weak::ptr_eq(&usage.0.state, &Arc::downgrade(&self.state)),
            "workspace use belongs to another runtime owner"
        );
        let mut state = lock_state(&self.state);
        let entry = state
            .workspace
            .active
            .get(&usage.0.serial)
            .context("workspace preparer is no longer registered")?;
        ensure!(
            entry.purpose == UsagePurpose::Execution,
            "cleanup resolution cannot admit execution"
        );
        let endpoint = match &entry.target {
            UsageTarget::Resolving(endpoint) => endpoint,
            UsageTarget::Assigned(old) => &old.endpoint,
            UsageTarget::LegacySshWorktree(_) => {
                anyhow::bail!("legacy worktree is not an execution reservation")
            }
        };
        ensure!(
            *endpoint == identity.endpoint,
            "workspace endpoint changed while resolving"
        );
        if let UsageTarget::Assigned(old) = &entry.target {
            ensure!(
                *old == identity,
                "assigned workspace identity changed while preparing"
            );
        }
        let blocked = state
            .workspace
            .sealing_owners(&identity)
            .collect::<Vec<_>>();
        ensure!(
            blocked.is_empty(),
            "workspace is permanently sealed for retirement by agents: {}",
            blocked.join(", ")
        );
        state
            .workspace
            .active
            .get_mut(&usage.0.serial)
            .unwrap()
            .target = UsageTarget::Assigned(identity);
        Ok(())
    }
    pub(in crate::studio) fn cleanup_resolution(
        &self,
        owner: &str,
        identity: WorkspaceIdentity,
    ) -> Result<WorkspaceUsageLease> {
        let mut state = lock_state(&self.state);
        let serial = state.workspace.next()?;
        state.workspace.active.insert(
            serial,
            Usage {
                owner: owner.into(),
                target: UsageTarget::Assigned(identity),
                purpose: UsagePurpose::CleanupResolution,
            },
        );
        Ok(WorkspaceUsageLease(Arc::new(UsageToken {
            state: Arc::downgrade(&self.state),
            serial,
        })))
    }
    pub(in crate::studio) fn usage_owner(&self, usage: &WorkspaceUsageLease) -> Result<String> {
        ensure!(
            Weak::ptr_eq(&usage.0.state, &Arc::downgrade(&self.state)),
            "workspace use belongs to another runtime owner"
        );
        Ok(lock_state(&self.state)
            .workspace
            .active
            .get(&usage.0.serial)
            .context("workspace use is no longer registered")?
            .owner
            .clone())
    }
    pub(in crate::studio) fn preserve_workspace_resources(
        &self,
        owner: &str,
        identity: WorkspaceIdentity,
    ) {
        let old = {
            let mut state = lock_state(&self.state);
            state
                .workspace
                .resources
                .insert(owner.into(), UsageTarget::Assigned(identity))
        };
        drop(old);
    }

    /// The tool/process owner joined; Entry/preparer tokens still cover any remaining live work.
    pub(in crate::studio) fn release_stopped_runtime_resources(&self, owner: &str) {
        lock_state(&self.state).workspace.resources.remove(owner);
    }
    /// Caller has joined the real runtime/failed-preparation owner; retained files are not a use.
    pub(in crate::studio) fn release_workspace_resources(
        &self,
        owner: &str,
        identity: &WorkspaceIdentity,
    ) -> Result<()> {
        let removed = {
            let mut state = lock_state(&self.state);
            ensure!(
                state.workspace.resources.get(owner).is_none_or(
                    |target| matches!(target, UsageTarget::Assigned(actual) if actual == identity)
                ),
                "workspace resources have an unproven or changed identity for {owner}"
            );
            state.workspace.resources.remove(owner)
        };
        drop(removed);
        Ok(())
    }
}
