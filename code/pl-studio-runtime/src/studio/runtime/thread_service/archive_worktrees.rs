//! Physical cleanup stays in WorktreeManager; this record only retains the original operation.
use anyhow::{Context, Result, ensure};

use super::super::StudioRuntime;
use crate::{
    agent::worktree::{WorktreeCleanupPolicy, WorktreeHandle},
    studio::{
        agent_host::{
            workspace_preparation::{cleanup_identity, manager_from_lease},
            worktree_lease::WorktreeLeaseState,
        },
        store::thread_archive::ThreadArchiveOperation,
    },
};

impl StudioRuntime {
    pub(super) async fn clean_archive_worktrees(
        &self,
        operation: &mut ThreadArchiveOperation,
    ) -> Result<()> {
        for index in 0..operation.worktrees.len() {
            self.clean_archive_worktree(operation, index, false).await?;
        }
        Ok(())
    }

    pub(super) async fn clean_deleted_worktrees(
        &self,
        operation: &mut ThreadArchiveOperation,
    ) -> Result<()> {
        let mut failures = super::delete::DeletionFailures::default();
        for index in 0..operation.worktrees.len() {
            let member = operation.worktrees[index].lease.owner_thread_id.clone();
            failures.record(
                "删除专属工作树",
                super::delete::deletion_step(
                    &member,
                    "删除专属工作树",
                    self.clean_archive_worktree(operation, index, true),
                )
                .await,
            );
        }
        failures.finish()
    }

    async fn clean_archive_worktree(
        &self,
        operation: &mut ThreadArchiveOperation,
        index: usize,
        deleting: bool,
    ) -> Result<()> {
        let entry = operation.worktrees[index].clone();
        let owner = &entry.lease.owner_thread_id;
        let leases = &self.agent_facility.worktrees;
        let current = leases
            .get(owner)
            .context("archive worktree lease disappeared")?;
        ensure!(
            current.owner_kind == entry.lease.owner_kind
                && current.workspace_id == entry.lease.workspace_id
                && current.root_thread_id == entry.lease.root_thread_id
                && current.repository_root == entry.lease.repository_root
                && current.path == entry.lease.path
                && current.ssh_alias == entry.lease.ssh_alias
                && current.base_commit == entry.lease.base_commit
                && cleanup_identity(&self.store, &current).await? == entry.identity,
            "archive original worktree lease or endpoint changed"
        );
        current.validate_identity()?;
        if entry.identity.endpoint
            == crate::studio::agent_host::worktree_lease::WorkspaceEndpoint::Local
        {
            let home = self.store.paths().home().to_owned();
            let home = tokio::task::spawn_blocking(move || dunce::canonicalize(home)).await??;
            ensure!(
                !home.starts_with(&entry.identity.root),
                "cannot remove a worktree containing Studio reliable storage"
            );
        }
        let manager = manager_from_lease(&self.store, &self.ssh_manager, &current).await?;
        let handle = WorktreeHandle {
            path: entry.lease.path.clone().into(),
            base_commit: entry.lease.base_commit.clone(),
        };
        let common = manager
            .git_common_dir(std::path::Path::new(&entry.lease.repository_root))
            .await?
            .context("archive Git common-dir is unavailable")?;
        if let Some(original) = &entry.common_dir {
            ensure!(*original == common, "archive repository identity changed");
        }
        let removal = leases.begin_workspace_cleanup(owner, &entry.identity, None)?;
        // Git no longer claims this path. Permanent deletion may release the stale association,
        // but must preserve the entire unowned directory (including its SessionFiles subtree).
        // Archive retains its stricter physical cleanup guarantee.
        let unregistered = deleting && !manager.is_registered(&handle).await?;
        let (site, registered) = if unregistered {
            tracing::warn!(thread_id = %owner, reason = "worktree_unregistered",
                decision = "preserve", "永久删除保留未登记的工作树路径，仅释放会话关联");
            (None, false)
        } else {
            manager.removal_site(&handle).await?
        };
        if entry.cleaned || current.state == WorktreeLeaseState::Cleaned {
            ensure!(
                site.is_none() && !registered,
                "completed archive refuses a replacement worktree"
            );
        } else if entry.removal_started {
            ensure!(
                site.is_none() && !registered,
                "previous archive Git removal outcome is unresolved; possible replacement preserved"
            );
        } else if !unregistered {
            let mut intent = current.clone();
            intent.transition(WorktreeLeaseState::CleanupRequested);
            leases.record_durable(intent).await?;
            let mut intent = operation.clone();
            intent.worktrees[index].common_dir = Some(common);
            intent.worktrees[index].removal_started = true;
            intent.changed()?;
            self.store.save_thread_archive(&intent).await?;
            *operation = intent;
            if let Err(error) = manager
                .cleanup(&handle, WorktreeCleanupPolicy::Discard)
                .await
            {
                // A real Git refusal consumes no authority. Transport/exit uncertainty leaves
                // removal_started durable, so restart cannot remove a replacement checkout.
                if crate::studio::thread_factory::worktree_removal_definitely_refused(&error)
                    && let Some(original) = &site
                    && let Ok((Some(remaining), true)) = manager.removal_site(&handle).await
                    && remaining == *original
                {
                    operation.worktrees[index].removal_started = false;
                    operation.changed()?;
                    self.store.save_thread_archive(operation).await?;
                }
                return Err(error.into());
            }
        }
        let mut cleaned = leases
            .get(owner)
            .context("archive cleanup lost its lease")?;
        if cleaned.state != WorktreeLeaseState::Cleaned {
            cleaned.transition(WorktreeLeaseState::Cleaned);
            leases.record_durable(cleaned).await?;
        }
        // Failed completion ACKs must not leak into another worktree's independent save.
        // The physical removal and durable lease remain available for a safe retry.
        let mut completed = operation.clone();
        completed.worktrees[index].cleaned = true;
        completed.changed()?;
        self.store.save_thread_archive(&completed).await?;
        *operation = completed;
        removal.complete();
        leases.release_workspace_seal(owner, &entry.identity)?;
        Ok(())
    }
}
