//! Failed unpublished preparation and explicit ordinary archive release only assigned resources.
use super::StudioThreadFactory;
use crate::studio::agent_host::{
    workspace_preparation,
    worktree_lease::{
        WorkspaceEndpoint, WorkspaceIdentity, WorkspaceUsageLease, WorktreeLeaseState,
    },
};
use anyhow::{Context, Result, ensure};
use std::path::{Path, PathBuf};

impl StudioThreadFactory {
    pub(in crate::studio) async fn prepare_workspace_cleanup(
        &self,
        lease: &crate::studio::agent_host::worktree_lease::WorktreeLease,
    ) -> Result<()> {
        workspace_preparation::cleanup_identity(&self.services.store, lease).await?;
        Ok(())
    }

    pub(super) async fn discard_prepared_workspace(
        &self,
        id: &str,
        usage: Option<&WorkspaceUsageLease>,
    ) -> Result<()> {
        ensure!(
            !self.services.store.agent_close(id).await?.is_some(),
            "explicitly closed resources belong to the child close owner"
        );
        let result = self.discard_prepared_workspace_inner(id, usage).await;
        if let Err(error) = result {
            if let Some(mut lease) = self.services.worktrees.get(id)
                && lease.state != WorktreeLeaseState::Cleaned
            {
                lease.settle(WorktreeLeaseState::Preserved);
                if let Err(retention) = self.services.worktrees.record_durable(lease).await {
                    return Err(error.context(format!(
                        "cannot persist unpublished workspace cleanup owner: {retention:#}"
                    )));
                }
            }
            return Err(error);
        }
        Ok(())
    }

    async fn discard_prepared_workspace_inner(
        &self,
        id: &str,
        usage: Option<&WorkspaceUsageLease>,
    ) -> Result<()> {
        let lease = self.services.worktrees.get(id);
        let identity = match self.services.store.workspace_identity(id).await? {
            Some(identity) => identity,
            None if lease.is_none() => return Ok(()),
            None => {
                workspace_preparation::cleanup_identity(
                    &self.services.store,
                    lease.as_ref().unwrap(),
                )
                .await?
            }
        };
        let removal = if let Some(lease) = &lease {
            self.prepare_workspace_cleanup(lease).await?;
            Some(
                self.services
                    .worktrees
                    .begin_workspace_cleanup(id, &identity, usage)?,
            )
        } else {
            self.services
                .worktrees
                .ensure_thread_workspace_idle_except(id, usage)?;
            None
        };
        // This cleanup use survives every filesystem/Git await. It is not an execution borrow and
        // cannot activate a retired member; it still blocks a containing workspace's deletion.
        let resolution = if removal.is_none() {
            Some(
                self.services
                    .worktrees
                    .cleanup_resolution(id, identity.clone())?,
            )
        } else {
            None
        };
        if let Some(mut lease) = lease {
            let manager = workspace_preparation::manager_from_lease(
                &self.services.store,
                &self.services.ssh_manager,
                &lease,
            )
            .await?;
            lease.validate_identity()?;
            let handle = crate::agent::worktree::WorktreeHandle {
                path: lease.path.clone().into(),
                branch: lease.branch.clone(),
                base_commit: lease.base_commit.clone(),
            };
            // A NoSideEffects create failure already settled Cleaned. It grants no authority to
            // remove a pre-existing site. Unpublished children have never executed, so rollback
            // of a real partial creation is restricted to its frozen base, not a later branch.
            if lease.state == WorktreeLeaseState::Cleaned {
                manager.verify_discarded(&handle).await?;
            } else {
                manager.discard_incomplete_creation(&handle).await?;
            }
            // Git removed the whole exclusive root, including SessionFiles. Do not delete files
            // inside it before Git proves identity or in order to bypass a Git refusal.
            lease.settle(WorktreeLeaseState::Cleaned);
            self.services.worktrees.record_durable(lease).await?;
        } else {
            self.remove_owned_execution_files(id, &identity, Path::new(&identity.root))
                .await?;
        }
        drop(resolution);
        if let Some(removal) = removal {
            removal.complete();
        } else {
            self.services
                .worktrees
                .release_workspace_resources(id, &identity)?;
        }
        Ok(())
    }

    pub(in crate::studio) async fn cleanup_archived_execution_files(
        &self,
        id: &str,
        retiring_worktrees: &[WorkspaceIdentity],
    ) -> Result<()> {
        let thread = self
            .services
            .store
            .catalog()
            .get(id)
            .context("archive cleanup owner is missing")?;
        ensure!(
            thread.to_thread().archived,
            "execution files cleanup needs the ordinary archive's committed intent"
        );
        if self.services.store.agent_close(id).await?.is_some() {
            return Ok(());
        }
        self.services.worktrees.ensure_thread_workspace_idle(id)?;
        let Some(identity) = self.services.store.workspace_identity(id).await? else {
            return Ok(());
        };
        // Ordinary local-root archiving never acquired final-retirement authority for its shared
        // execution files. Release only files already inside this archive's destructive WT scope.
        if !retiring_worktrees
            .iter()
            .any(|outer| identity.within(outer))
        {
            return Ok(());
        }
        let resolution = self
            .services
            .worktrees
            .cleanup_resolution(id, identity.clone())?;
        let container = self.services.worktrees.get(id).map_or_else(
            || PathBuf::from(&identity.root),
            |lease| PathBuf::from(lease.repository_root),
        );
        self.remove_owned_execution_files(id, &identity, &container)
            .await?;
        drop(resolution);
        if self.services.worktrees.get(id).is_none() {
            self.services
                .worktrees
                .release_workspace_resources(id, &identity)?;
        }
        Ok(())
    }

    async fn remove_owned_execution_files(
        &self,
        id: &str,
        identity: &WorkspaceIdentity,
        container: &Path,
    ) -> Result<()> {
        let source =
            Path::new(&identity.root).join(pl_tool::workspace::SessionFiles::new(id).root());
        match &identity.endpoint {
            WorkspaceEndpoint::Local => {
                pl_tool::workspace::path_safety::validate_path_for_write_async(container, &source)
                    .await?;
                pl_tool::workspace::path_safety::remove_dir_all_no_follow_async(container, &source)
                    .await?;
                ensure!(
                    !tokio::fs::try_exists(&source).await?,
                    "execution files remain after cleanup for {id}"
                );
            }
            WorkspaceEndpoint::Ssh { .. } => {
                let profile = self
                    .services
                    .ssh_manager
                    .list_servers()
                    .await
                    .into_iter()
                    .find(|entry| {
                        WorkspaceEndpoint::from_profile(Some(&entry.profile)) == identity.endpoint
                    })
                    .context("frozen cleanup SSH endpoint is not configured")?
                    .profile;
                let host = self
                    .services
                    .ssh_manager
                    .open_workspace_host(&profile.alias, container.to_string_lossy().into_owned())
                    .await?;
                ensure!(
                    WorkspaceEndpoint::from_profile(Some(&host.profile)) == identity.endpoint
                        && host.files.canonical_path() == container.to_string_lossy(),
                    "execution cleanup endpoint or canonical container changed"
                );
                let path = source.to_string_lossy().into_owned();
                if host
                    .files
                    .stat_optional(path.clone(), None)
                    .await?
                    .is_some()
                {
                    host.files.remove_path(path.clone(), None, true).await?;
                }
                ensure!(
                    host.files.stat_optional(path, None).await?.is_none(),
                    "execution files remain after cleanup for {id}"
                );
            }
        }
        Ok(())
    }
}
