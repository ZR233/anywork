//! Resolve outside the canonical admission mutex; no business workspace preparation precedes it.
use super::{StudioThreadFactory, errors::resource_error};
use crate::studio::{
    WorkspaceRecord,
    agent_host::worktree_lease::{
        WorkspaceEndpoint, WorkspaceIdentity, WorkspaceUsageLease, WorktreeLease,
    },
};
use crate::thread_assembler::ThreadAssemblyError;
use anyhow::Result;
use std::path::Path;

impl StudioThreadFactory {
    /// Restore execution seals and only unfinished physical delete seals before preparation opens.
    pub(in crate::studio) async fn restore_workspace_admission(
        &self,
        leases: Vec<WorktreeLease>,
    ) -> Result<()> {
        let records = self.services.store.agent_closes().await?;
        for record in &records {
            self.services
                .store
                .catalog()
                .project_explicit_close(&record.agent_id)
                .await?;
            if let Some(binding) = &record.worktree {
                if record.worktree_cleanup.is_terminal() {
                    self.services
                        .worktrees
                        .release_workspace_seal(&record.agent_id, &binding.identity)?;
                } else {
                    self.services
                        .worktrees
                        .restore_workspace_seal(&record.agent_id, binding.identity.clone())?;
                    self.services
                        .worktrees
                        .preserve_workspace_resources(&record.agent_id, binding.identity.clone());
                }
            }
        }
        // Pending physical seals must precede hydration so cleanupRequested is not downgraded.
        // Conversely, hydration's legacy-resource protection cannot revive a terminal member's
        // already returned use: retained SessionFiles and refs are not live borrowers.
        self.services.worktrees.restore(leases);
        for record in &records {
            if record.worktree_cleanup.is_terminal() {
                self.services
                    .worktrees
                    .release_stopped_runtime_resources(&record.agent_id);
            }
        }
        Ok(())
    }

    pub(in crate::studio) async fn reserve_workspace_use(
        &self,
        id: &str,
        project: &WorkspaceRecord,
    ) -> Result<WorkspaceUsageLease> {
        self.services
            .worktrees
            .reserve_project_workspace(id, &self.services.ssh_manager, project)
            .await
    }
    pub(super) async fn reserve_thread_workspace_use(
        &self,
        id: &str,
        root_id: &str,
        project: &WorkspaceRecord,
    ) -> Result<WorkspaceUsageLease> {
        if self
            .services
            .bots
            .config_for_thread(root_id)
            .await?
            .is_some()
        {
            self.services
                .worktrees
                .reserve_workspace(id, WorkspaceEndpoint::Local)
        } else {
            self.reserve_workspace_use(id, project).await
        }
    }

    pub(in crate::studio) async fn resolve_workspace_identity(
        &self,
        project: &WorkspaceRecord,
        root: &Path,
    ) -> Result<WorkspaceIdentity> {
        crate::studio::agent_host::worktree_lease::resolve_physical_workspace(
            &self.services.ssh_manager,
            project,
            root,
        )
        .await
    }

    pub(in crate::studio) async fn assign_workspace_use(
        &self,
        usage: &WorkspaceUsageLease,
        project: &WorkspaceRecord,
        root: &Path,
    ) -> Result<WorkspaceIdentity> {
        let identity = self.resolve_workspace_identity(project, root).await?;
        self.services
            .worktrees
            .assign_workspace(usage, identity.clone())?;
        self.services
            .store
            .bind_workspace_identity(&self.services.worktrees.usage_owner(usage)?, &identity)
            .await?;
        Ok(identity)
    }

    pub(in crate::studio) fn workspace_usage_error(error: anyhow::Error) -> ThreadAssemblyError {
        resource_error("workspace physical usage admission", error)
    }
}
