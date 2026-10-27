//! Failed unpublished preparation retains uncertain worktrees and its real cleanup owner.
use super::StudioThreadFactory;
use crate::studio::agent_host::{
    workspace_preparation,
    worktree_lease::{
        WorkspaceEndpoint, WorkspaceIdentity, WorkspaceUsageLease, WorktreeLeaseState,
    },
};
use anyhow::{Context, Result, ensure};
use std::path::Path;

impl StudioThreadFactory {
    pub(super) async fn discard_prepared_workspace(
        &self,
        id: &str,
        usage: Option<&WorkspaceUsageLease>,
    ) -> Result<()> {
        ensure!(
            self.services.store.agent_close(id).await?.is_none(),
            "explicitly closed resources belong to the child close owner"
        );
        let result = self.discard_prepared_workspace_inner(id, usage).await;
        if let Err(error) = result {
            if let Some(mut lease) = self.services.worktrees.get(id)
                && lease.state != WorktreeLeaseState::Cleaned
            {
                lease.transition(WorktreeLeaseState::Preserved);
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
        let removal = if lease.is_some() {
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
            if lease.state != WorktreeLeaseState::Cleaned {
                lease.transition(WorktreeLeaseState::Preserved);
                self.services.worktrees.record_durable(lease).await?;
                anyhow::bail!(
                    "unpublished worktree creation has no confirmed deletion authority; original site and preparation owner preserved"
                );
            }
            // NoSideEffects is the only settled creation failure. Do not probe or delete a path
            // that may have predated this attempt; only discharge our logical cleanup use.
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
