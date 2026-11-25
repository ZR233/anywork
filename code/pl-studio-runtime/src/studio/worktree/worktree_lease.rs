use crate::agent::worktree::git_path::workspace_path_text;
use anyhow::Result;
use serde::{Deserialize, Serialize};

use crate::studio::StudioStore;
use crate::studio::storage::write_behind::ThreadWriteBehindWriter;
use crate::studio::store::object::PersistedStudioObject;
mod identity;
mod usage;
pub(in crate::studio) use identity::migrate_bot_identities;
pub(in crate::studio) use identity::resolve_physical_workspace;
pub(crate) use identity::{WorkspaceEndpoint, WorkspaceIdentity};
pub(crate) use usage::WeakWorkspaceUsageLease;
pub use usage::WorkspaceUsageLease;

mod migration;

#[cfg(test)]
mod admission_tests;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::studio) enum WorktreeLeaseState {
    Prepared,
    Active,
    Preserved,
    CleanupRequested,
    Cleaned,
}

impl WorktreeLeaseState {
    pub(in crate::studio) const fn label(self) -> &'static str {
        match self {
            Self::Prepared => "prepared",
            Self::Active => "active",
            Self::Preserved => "preserved",
            Self::CleanupRequested => "cleanupRequested",
            Self::Cleaned => "cleaned",
        }
    }
}

/// worktree lease 的归属类型：根会话自身工作区，或子智能体工作区。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::studio) enum WorktreeLeaseOwnerKind {
    Session,
    Child,
}

impl WorktreeLeaseOwnerKind {
    pub(in crate::studio) const fn label(self) -> &'static str {
        match self {
            Self::Session => "session",
            Self::Child => "child",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct WorktreeLease {
    pub revision: u64,
    pub state: WorktreeLeaseState,
    pub owner_kind: WorktreeLeaseOwnerKind,
    /// 归属 Thread id：`session` 为根会话自身，`child` 为子智能体 Thread。
    pub owner_thread_id: String,
    pub root_thread_id: String,
    pub workspace_id: String,
    pub ssh_alias: Option<String>,
    pub repository_root: String,
    pub path: String,
    pub base_commit: String,
}

impl WorktreeLease {
    /// Moves the lease to `state` and bumps its revision.
    pub fn transition(&mut self, state: WorktreeLeaseState) {
        self.revision = self.revision.saturating_add(1);
        self.state = state;
    }

    /// 该 lease 的稳定归属；不约束可变的 Git 分支或 HEAD。
    pub(in crate::studio) fn ownership(&self) -> crate::agent::worktree::WorktreeOwnership {
        use crate::agent::worktree::WorktreeOwnership;
        match self.owner_kind {
            WorktreeLeaseOwnerKind::Session => WorktreeOwnership::Session {
                thread_id: self.owner_thread_id.clone(),
            },
            WorktreeLeaseOwnerKind::Child => WorktreeOwnership::Child {
                child_id: self.owner_thread_id.clone(),
            },
        }
    }

    /// 按稳定归属校验受管路径，Git 注册与仓库检查由物理边界负责。
    pub(in crate::studio) fn validate_identity(
        &self,
    ) -> Result<(), crate::agent::worktree::WorktreeError> {
        use crate::agent::worktree::{WorktreeError, WorktreeManager};
        let mismatch = |reason: &str| WorktreeError::IdentityMismatch(reason.to_owned());
        let repository_root = std::path::Path::new(&self.repository_root);
        let ownership = self.ownership();
        if self.owner_kind == WorktreeLeaseOwnerKind::Session
            && self.owner_thread_id != self.root_thread_id
        {
            return Err(mismatch("owner: session lease belongs to another root"));
        }
        let expected =
            WorktreeManager::allocate_path(repository_root, &self.root_thread_id, &ownership);
        if self.ssh_alias.is_some() {
            let expected = workspace_path_text(&expected, true)
                .map_err(|_| mismatch("path: remote managed leaf is invalid"))?;
            let actual = workspace_path_text(std::path::Path::new(&self.path), true)
                .map_err(|_| mismatch("path: remote lease path is invalid"))?;
            if actual != expected {
                return Err(mismatch("path: lease differs from its owned leaf"));
            }
        } else {
            if std::path::Path::new(&self.path) != expected {
                return Err(mismatch("path: lease differs from its owned leaf"));
            }
        }
        Ok(())
    }
}

impl PersistedStudioObject for WorktreeLease {
    type PersistenceDto = Self;

    const OWNER_KIND: &'static str = "agent";
    const OBJECT_KIND: &'static str = "worktreeLease";
    const SCHEMA_VERSION: i64 = 5;

    fn revision(&self) -> u64 {
        self.revision
    }

    fn to_persistence_dto(&self) -> Self::PersistenceDto {
        self.clone()
    }

    fn from_persistence_dto(mut dto: Self::PersistenceDto) -> Result<Self> {
        if dto.ssh_alias.is_some() {
            dto.repository_root =
                workspace_path_text(std::path::Path::new(&dto.repository_root), true)?;
            dto.path = workspace_path_text(std::path::Path::new(&dto.path), true)?;
        }
        dto.validate_identity()?;
        Ok(dto)
    }

    fn validate_owner(&self, owner_id: &str) -> Result<()> {
        anyhow::ensure!(
            owner_id == self.owner_thread_id,
            "worktree lease owner identity mismatch"
        );
        Ok(())
    }
}

pub(in crate::studio) async fn load_leases(store: &StudioStore) -> Result<Vec<WorktreeLease>> {
    migration::load(store.database())
        .await
        .map_err(|error| error.context(WorktreeLeaseMigrationFailed))
}

/// A failed lease upgrade must stop startup, never enter backup/reset recovery.
#[derive(Debug, thiserror::Error)]
#[error("worktree lease storage upgrade failed")]
pub(in crate::studio) struct WorktreeLeaseMigrationFailed;

/// Canonical process-local lease owner. Storage never participates in admission.
#[derive(Clone)]
pub(in crate::studio) struct WorktreeLeaseOwner {
    state: std::sync::Arc<std::sync::Mutex<LeaseOwnerState>>,
    /// 进程内「创建中」标记：不持久化，重启后消失。
    ///
    /// 创建路径在记录 `prepared` 之前设置、在创建收束（成功 `active` 或失败 settle 并发布）
    /// 之后清除；标记存续期间该 lease 既不进入 Recovery，也不可被显式清理，即使 owner
    /// Thread 记录尚未发布。
    writer: ThreadWriteBehindWriter,
}

#[derive(Default)]
struct LeaseOwnerState {
    entries: std::collections::BTreeMap<String, LeaseEntry>,
    creating: std::collections::BTreeSet<String>,
    workspace: usage::WorkspaceAdmission,
}

/// Keep receipt release usable during unwinding, as for workspace usage guards. All lease and
/// admission accesses share this policy; recovering never clears poison or grants a fresh identity.
fn lock_state(
    state: &std::sync::Mutex<LeaseOwnerState>,
) -> std::sync::MutexGuard<'_, LeaseOwnerState> {
    state
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// A receipt is associated with the same admitted revision, never a later global queue snapshot.
#[derive(Clone)]
struct LeaseEntry {
    lease: WorktreeLease,
    ticket: u64,
}

impl WorktreeLeaseOwner {
    pub(in crate::studio) fn new(writer: ThreadWriteBehindWriter) -> Self {
        Self {
            state: Default::default(),
            writer,
        }
    }

    /// Marks a lease as still being created in this process.
    pub(in crate::studio) fn mark_creating(&self, owner_thread_id: &str) {
        lock_state(&self.state)
            .creating
            .insert(owner_thread_id.to_string());
    }

    /// Clears the creating mark once creation converged (active, settled or published).
    pub(in crate::studio) fn clear_creating(&self, owner_thread_id: &str) {
        lock_state(&self.state).creating.remove(owner_thread_id);
    }

    pub(in crate::studio) fn is_creating(&self, owner_thread_id: &str) -> bool {
        lock_state(&self.state).creating.contains(owner_thread_id)
    }

    /// 开始一个创建窗口，返回在**所有**出口（含提前返回、取消与 panic 展开）清除标记的守卫。
    pub(in crate::studio) fn creation_guard(&self, owner_thread_id: &str) -> WorktreeCreationGuard {
        WorktreeCreationGuard::new(self, owner_thread_id)
    }

    /// Startup hydration never replaces facts already admitted in this process.
    pub(in crate::studio) async fn restore(
        &self,
        store: &StudioStore,
        leases: Vec<WorktreeLease>,
    ) -> Result<()> {
        // Read durable bindings before taking the admission lock. An SSH alias alone is not
        // authority, but an existing frozen endpoint must not become an unproven legacy use.
        let mut restored = Vec::with_capacity(leases.len());
        for lease in leases {
            let identity = store.workspace_identity(&lease.owner_thread_id).await?;
            if let Some(identity) = &identity {
                anyhow::ensure!(
                    identity.matches_root(&lease.path)
                        && matches!(identity.endpoint, WorkspaceEndpoint::Ssh { .. })
                            == lease.ssh_alias.is_some(),
                    "restored worktree physical binding no longer matches its lease"
                );
            }
            restored.push((lease, identity));
        }
        let mut state = lock_state(&self.state);
        for (mut lease, identity) in restored {
            state.workspace.preserve_restored_lease(&lease, identity);
            let explicitly_retiring = state.workspace.is_retiring(&lease.owner_thread_id);
            if let std::collections::btree_map::Entry::Vacant(entry) =
                state.entries.entry(lease.owner_thread_id.clone())
            {
                // An interrupted process no longer owns an in-flight cleanup operation.
                // Preserve uncertain physical state for explicit reconciliation.
                let ticket = if lease.state == WorktreeLeaseState::CleanupRequested
                    && !explicitly_retiring
                {
                    // A site whose cleanup did not settle also lost the restore window it may still
                    // have carried: the next settlement starts from scratch, never from an old grant.
                    lease.transition(WorktreeLeaseState::Preserved);
                    self.writer.record_worktree_lease(lease.clone())
                } else {
                    // Hydrated values have already crossed the product database transaction.
                    0
                };
                entry.insert(LeaseEntry { lease, ticket });
            }
        }
        Ok(())
    }

    pub(in crate::studio) fn get(&self, owner_thread_id: &str) -> Option<WorktreeLease> {
        lock_state(&self.state)
            .entries
            .get(owner_thread_id)
            .map(|entry| entry.lease.clone())
    }

    pub(in crate::studio) fn snapshot(&self) -> Vec<WorktreeLease> {
        lock_state(&self.state)
            .entries
            .values()
            .map(|entry| entry.lease.clone())
            .collect()
    }

    pub(in crate::studio) fn forget_deleted(&self, id: &str) -> Result<()> {
        let mut state = lock_state(&self.state);
        anyhow::ensure!(
            state
                .entries
                .get(id)
                .is_none_or(|entry| entry.lease.state == WorktreeLeaseState::Cleaned),
            "cannot forget an unfinished worktree cleanup"
        );
        state.entries.remove(id);
        state.creating.remove(id);
        Ok(())
    }

    pub(in crate::studio) fn is_durable(&self, lease: &WorktreeLease) -> bool {
        lock_state(&self.state)
            .entries
            .get(&lease.owner_thread_id)
            .is_some_and(|entry| {
                entry.lease == *lease && self.writer.saved_watermark() >= entry.ticket
            })
    }

    /// Revision admission and queue order share one short, IO-free critical section.
    fn record_ticket(&self, lease: WorktreeLease) -> Result<u64> {
        let mut state = lock_state(&self.state);
        self.record_ticket_locked(&mut state, lease)
    }

    fn record_ticket_locked(
        &self,
        state: &mut LeaseOwnerState,
        lease: WorktreeLease,
    ) -> Result<u64> {
        let entries = &mut state.entries;
        if let Some(previous) = entries.get(&lease.owner_thread_id) {
            if previous.lease == lease {
                if previous.ticket != 0 {
                    return Ok(previous.ticket);
                }
                // Hydration proves the old database fact, not an ACK from this writer.
                // Re-admit that same value without changing its business revision.
            } else {
                anyhow::ensure!(
                    lease.revision
                        == previous
                            .lease
                            .revision
                            .checked_add(1)
                            .ok_or_else(|| anyhow::anyhow!("worktree lease revision exhausted"))?,
                    "worktree lease revision conflict for {}",
                    lease.owner_thread_id
                );
            }
        } else {
            anyhow::ensure!(
                lease.state == WorktreeLeaseState::Prepared,
                "new worktree lease must be prepared"
            );
        }
        let ticket = self.writer.record_worktree_lease(lease.clone());
        entries.insert(lease.owner_thread_id.clone(), LeaseEntry { lease, ticket });
        Ok(ticket)
    }

    /// A destructive phase may start only after its exact lease intent crossed the writer ACK.
    /// Cancellation stops this waiter, not the already registered write-behind owner.
    pub(in crate::studio) async fn record_durable(&self, lease: WorktreeLease) -> Result<()> {
        let ticket = self.record_ticket(lease)?;
        self.writer.flush_through(ticket).await?;
        Ok(())
    }

    /// Failed root preparation retains its original binding, including when factory
    /// confirmation advanced that same binding after the caller captured it.
    pub(in crate::studio) async fn preserve_failed_session_binding(
        &self,
        expected: &WorktreeLease,
    ) -> Result<WorktreeLease> {
        expected.validate_identity()?;
        anyhow::ensure!(
            expected.owner_kind == WorktreeLeaseOwnerKind::Session
                && matches!(
                    expected.state,
                    WorktreeLeaseState::Prepared
                        | WorktreeLeaseState::Active
                        | WorktreeLeaseState::Preserved
                ),
            "failed session retention requires a root session binding"
        );
        let (retained, ticket) = {
            let mut state = lock_state(&self.state);
            let current = &state
                .entries
                .get(&expected.owner_thread_id)
                .ok_or_else(|| anyhow::anyhow!("failed session binding no longer exists"))?
                .lease;
            let mut binding = expected.clone();
            binding.revision = current.revision;
            binding.state = current.state;
            anyhow::ensure!(
                binding == *current
                    && current.revision >= expected.revision
                    && (current.revision > expected.revision || current.state == expected.state),
                "failed session binding changed"
            );
            anyhow::ensure!(
                !state.workspace.is_retiring(&expected.owner_thread_id)
                    && !state.workspace.is_removing(&expected.owner_thread_id)
                    && matches!(
                        current.state,
                        WorktreeLeaseState::Prepared
                            | WorktreeLeaseState::Active
                            | WorktreeLeaseState::Preserved
                    ),
                "retiring, cleaned or cleanup-requested session cannot be retained"
            );
            let mut retained = current.clone();
            if retained.state != WorktreeLeaseState::Preserved {
                retained.revision = retained
                    .revision
                    .checked_add(1)
                    .ok_or_else(|| anyhow::anyhow!("worktree lease revision exhausted"))?;
                retained.state = WorktreeLeaseState::Preserved;
            }
            let ticket = self.record_ticket_locked(&mut state, retained.clone())?;
            (retained, ticket)
        };
        self.writer.flush_through(ticket).await?;
        Ok(retained)
    }
}

/// 进程内创建窗口守卫。
///
/// 创建路径在记录 `prepared` 之前构造它；无论成功、失败、取消还是展开，离开作用域时标记
/// 都会被清除，因此不存在「收束了但标记仍存续」的泄漏。
pub(in crate::studio) struct WorktreeCreationGuard {
    worktrees: WorktreeLeaseOwner,
    owner_thread_id: String,
}

impl WorktreeCreationGuard {
    pub(in crate::studio) fn new(worktrees: &WorktreeLeaseOwner, owner_thread_id: &str) -> Self {
        worktrees.mark_creating(owner_thread_id);
        Self {
            worktrees: worktrees.clone(),
            owner_thread_id: owner_thread_id.to_string(),
        }
    }
}

impl Drop for WorktreeCreationGuard {
    fn drop(&mut self) {
        self.worktrees.clear_creating(&self.owner_thread_id);
    }
}
