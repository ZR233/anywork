//! One explicit child close owns only its frozen Git worktree, never its history or SessionFiles.
use super::StudioThreadFactory;
use crate::{
    agent::worktree::{
        LocalWorktreeBackend, RemoteWorktreeBackend, WorktreeBackend, WorktreeHandle,
        WorktreeManager, WorktreeRetirementRequest,
    },
    studio::{
        agent_close::{AgentCloseResult, AgentWorktreeCleanup, state_error},
        agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
        store::agent_close::{AgentCloseGitGrant, AgentCloseRecord, OwnedWorktreeBinding},
    },
};
use anyhow::{Context, Result, ensure};
use pl_protocol::Thread;
use std::{
    path::{Path, PathBuf},
    sync::Arc,
};

impl StudioThreadFactory {
    pub(crate) async fn finish_child_worktree_cleanup(
        &self,
        thread: &Thread,
    ) -> Result<(AgentCloseResult, Option<pl_protocol::StateError>)> {
        let mut record = self
            .services
            .store
            .agent_close(&thread.id)
            .await?
            .context("close intent is missing")?;
        ensure!(
            record.execution_closed,
            "child execution/save owners have not finished"
        );
        let cleanup = async {
            self.validate_close_identity(thread, &record)?;
            self.cleanup_one_owned_worktree(&mut record).await
        }
        .await;
        match cleanup {
            Ok(()) => Ok((record.result(), None)),
            Err(error) => {
                if !record.worktree_cleanup.is_terminal() {
                    record.worktree_cleanup = AgentWorktreeCleanup::Failed {
                        path: record
                            .worktree
                            .as_ref()
                            .map(|binding| binding.lease.path.clone()),
                        error: state_error(&error),
                    };
                }
                let mut failure = error;
                record.error = Some(state_error(&failure));
                record.changed()?;
                if let Err(save) = self.services.store.save_agent_close(&record).await {
                    failure =
                        failure.context(format!("close result save remains unconfirmed: {save:#}"));
                }
                Ok((record.result(), Some(state_error(&failure))))
            }
        }
    }

    async fn cleanup_one_owned_worktree(&self, record: &mut AgentCloseRecord) -> Result<()> {
        let Some(binding) = record.worktree.clone() else {
            record.worktree_cleanup = AgentWorktreeCleanup::NotApplicable;
            record.error = None;
            record.changed()?;
            return self.services.store.save_agent_close(record).await;
        };
        if let Some(frozen) = self
            .services
            .store
            .workspace_identity(&record.agent_id)
            .await?
        {
            ensure!(
                frozen == binding.identity,
                "closed child physical identity changed"
            );
        }
        let manager = self.close_worktree_manager(&binding).await?;
        let handle = WorktreeHandle {
            path: binding.lease.path.clone().into(),
            base_commit: binding.lease.base_commit.clone(),
        };
        let common = manager
            .git_common_dir(Path::new(&binding.lease.repository_root))
            .await?
            .context("close repository common-dir cannot be resolved")?;
        if let Some(grant) = &record.git {
            ensure!(
                grant.expected_common_dir == common,
                "close repository common-dir changed"
            );
        }
        if record.worktree_cleanup.is_terminal() {
            // A completed request cannot delete a new site at the same path, even with force.
            let (site, registered) = manager.child_cleanup_site(&handle).await?;
            match &record.worktree_cleanup {
                AgentWorktreeCleanup::Removed { .. } => {
                    manager.verify_child_retired(&handle, &common).await?
                }
                AgentWorktreeCleanup::NotPresent {
                    registration_present,
                    ..
                } => ensure!(
                    site.is_none() && registered == *registration_present,
                    "absent child path/registration changed; replacement preserved"
                ),
                _ => anyhow::bail!("owned worktree has an invalid terminal result"),
            }
            if matches!(
                record.worktree_cleanup,
                AgentWorktreeCleanup::Removed { .. }
            ) {
                self.settle_closed_worktree(&record.agent_id).await?;
            }
            if record.error.is_some() {
                record.error = None;
                record.changed()?;
                self.services.store.save_agent_close(record).await?;
            }
            self.services
                .worktrees
                .release_workspace_seal(&record.agent_id, &binding.identity)?;
            return Ok(());
        }
        self.ensure_close_storage_outside(&binding.identity).await?;
        self.services
            .worktrees
            .ensure_thread_workspace_idle(&record.agent_id)?;
        self.services
            .worktrees
            .try_seal_workspace(
                &record.agent_id,
                binding.identity.clone(),
                &std::collections::BTreeSet::from([record.agent_id.clone()]),
            )?
            .durable()?;
        let removal = self
            .services
            .worktrees
            .begin_workspace_removal(&record.agent_id, &binding.identity)?;
        let (site, registration_present) = manager.child_cleanup_site(&handle).await?;
        let Some(site) = site else {
            record.worktree_cleanup = AgentWorktreeCleanup::NotPresent {
                path: binding.lease.path,
                registration_present,
            };
            record.error = None;
            record.changed()?;
            self.services.store.save_agent_close(record).await?;
            removal.complete();
            self.services
                .worktrees
                .release_workspace_seal(&record.agent_id, &binding.identity)?;
            return Ok(());
        };
        if binding.identity.endpoint == WorkspaceEndpoint::Local {
            let path = PathBuf::from(&binding.identity.root);
            let expected = path.clone();
            let actual = tokio::task::spawn_blocking(move || dunce::canonicalize(path)).await??;
            ensure!(
                actual == expected,
                "owned child path changed canonical identity"
            );
        }
        ensure!(
            !record
                .git
                .as_ref()
                .is_some_and(|grant| grant.removal_started),
            "previous Git removal outcome is unresolved; refusing to replay it against a possible replacement"
        );
        if !record.force {
            ensure!(
                site.changed_files.is_empty(),
                "child has uncommitted or untracked changes; commit/deliver them or explicitly force close"
            );
        }
        let delivery = self
            .services
            .store
            .workspace_identity(&record.root_id)
            .await?
            .context("actual root delivery workspace has no frozen physical binding")?;
        ensure!(
            delivery.endpoint == binding.identity.endpoint
                && delivery.root != binding.identity.root,
            "root delivery workspace endpoint or identity differs from owned child"
        );
        if let Some(grant) = &record.git {
            ensure!(
                grant.delivery == delivery,
                "previous close grant delivery identity changed; possible replacement preserved"
            );
        }
        // A confirmed non-removal consumed no content authority. HEAD is checked again for this
        // attempt and saved in its new grant, never promoted to permanent resource identity.
        if let Ok((workspace, project)) = self.actual_tool_workspace(&record.root_id) {
            let actual = self
                .resolve_workspace_identity(&project, workspace.root())
                .await?;
            ensure!(
                actual == delivery,
                "actual root delivery assignment changed"
            );
        } else if delivery.endpoint == WorkspaceEndpoint::Local {
            let expected = PathBuf::from(&delivery.root);
            let path = expected.clone();
            let actual = tokio::task::spawn_blocking(move || dunce::canonicalize(path)).await??;
            ensure!(
                actual == expected,
                "frozen root delivery path changed canonical identity"
            );
        }
        let request = WorktreeRetirementRequest {
            delivery_target: delivery.root.clone().into(),
            expected_head: site.head.clone(),
            expected_common_dir: common.clone(),
            force: record.force,
        };
        // Content/ancestry refusal precedes the exact destructive grant, so integrating work or
        // explicitly escalating force can retry without looking like an interrupted Git remove.
        manager.validate_child_delivery(&request).await?;
        record.git = Some(AgentCloseGitGrant {
            delivery: delivery.clone(),
            expected_head: site.head.clone(),
            expected_common_dir: common.clone(),
            removal_started: true,
        });
        record.changed()?;
        // The exact delete grant crosses its real transaction ACK before Git is called.
        self.services.store.save_agent_close(record).await?;
        if let Err(error) = manager.retire_child(&handle, &request).await {
            // A known Git refusal can be retried only after re-proving the same remaining site.
            // An interrupted job leaves removal_started set and never replays on restart.
            if removal_definitely_refused(&error)
                && let Ok((Some(current), true)) = manager.child_cleanup_site(&handle).await
                && current.head == request.expected_head
                && let Some(grant) = &mut record.git
            {
                grant.removal_started = false;
            }
            return Err(error.into());
        }
        record.worktree_cleanup = AgentWorktreeCleanup::Removed {
            path: binding.lease.path,
        };
        record.error = None;
        record.changed()?;
        self.services.store.save_agent_close(record).await?;
        self.settle_closed_worktree(&record.agent_id).await?;
        removal.complete();
        self.services
            .worktrees
            .release_workspace_seal(&record.agent_id, &binding.identity)?;
        Ok(())
    }

    async fn settle_closed_worktree(&self, id: &str) -> Result<()> {
        use crate::studio::agent_host::worktree_lease::WorktreeLeaseState;
        let mut lease = self
            .services
            .worktrees
            .get(id)
            .context("closed worktree lease disappeared")?;
        // Final close retains all independent refs. Generic release cannot replay this close's
        // physical authority; its exact terminal result remains in the durable close record.
        if !matches!(
            lease.state,
            WorktreeLeaseState::Preserved | WorktreeLeaseState::Cleaned
        ) {
            lease.transition(WorktreeLeaseState::Preserved);
            self.services.worktrees.record_durable(lease).await?;
        }
        Ok(())
    }

    async fn close_worktree_manager(
        &self,
        binding: &OwnedWorktreeBinding,
    ) -> Result<WorktreeManager> {
        let root = PathBuf::from(&binding.lease.repository_root);
        let backend: Arc<dyn WorktreeBackend> = match &binding.identity.endpoint {
            WorkspaceEndpoint::Local => Arc::new(LocalWorktreeBackend::default()),
            WorkspaceEndpoint::Ssh { .. } => {
                let profile = self
                    .services
                    .ssh_manager
                    .list_servers()
                    .await
                    .into_iter()
                    .find(|entry| {
                        WorkspaceEndpoint::from_profile(Some(&entry.profile))
                            == binding.identity.endpoint
                    })
                    .context("frozen close SSH endpoint is not configured")?
                    .profile;
                Arc::new(RemoteWorktreeBackend::canonical_repository(
                    self.services.ssh_manager.clone(),
                    profile,
                    root.clone(),
                )?)
            }
        };
        Ok(WorktreeManager::new(root, backend))
    }

    async fn ensure_close_storage_outside(&self, identity: &WorkspaceIdentity) -> Result<()> {
        if identity.endpoint == WorkspaceEndpoint::Local {
            let home = self.services.store.paths().home().to_owned();
            let home = tokio::task::spawn_blocking(move || dunce::canonicalize(home)).await??;
            ensure!(
                !home.starts_with(&identity.root),
                "cannot remove a worktree containing Studio history or reliable resources; original data preserved"
            );
        }
        Ok(())
    }
}

/// Only a confirmed refusal before removal can release the persisted started fence. In
/// particular a transport spawn error is not proof that the helper never spawned Git.
fn removal_definitely_refused(error: &crate::agent::worktree::WorktreeError) -> bool {
    use crate::agent::worktree::{RemoteExecutionError, WorktreeError};
    match error {
        WorktreeError::GitExited { args, .. } | WorktreeError::GitLaunchFailed { args, .. } => {
            args.starts_with("worktree remove ")
        }
        WorktreeError::RemoteExecution {
            args,
            source: RemoteExecutionError::WorkingDirectory,
        } => args.starts_with("worktree remove "),
        _ => false,
    }
}
