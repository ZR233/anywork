use std::path::Path;

use super::{WorktreeLease, WorktreeLeaseOwnerKind, WorktreeLeaseState};
use crate::agent::worktree::{WorktreeManager, WorktreeOwnership};

pub(in crate::studio) fn prepared_child_lease(repo: &Path, id: &str) -> WorktreeLease {
    let ownership = WorktreeOwnership::Child {
        child_id: id.into(),
    };
    WorktreeLease {
        revision: 1,
        state: WorktreeLeaseState::Prepared,
        owner_kind: WorktreeLeaseOwnerKind::Child,
        owner_thread_id: id.into(),
        root_thread_id: "root".into(),
        workspace_id: "project".into(),
        ssh_alias: None,
        repository_root: repo.to_string_lossy().into_owned(),
        path: WorktreeManager::allocate_path(repo, "root", &ownership)
            .to_string_lossy()
            .into_owned(),
        base_commit: "a".repeat(40),
    }
}
