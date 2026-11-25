//! ACP children use the existing workspace and final-worktree owners, not Native Threads.
//! Close-intent transitions live in `close_child::ChildCloseCoordinator`.
use super::{StudioThreadFactory, child_resources::PreparedChildWorkspace, errors::resource_error};
use crate::thread_assembler::{ChildThreadRequest, ThreadAssemblyError};

impl StudioThreadFactory {
    pub(in crate::studio) async fn verify_acp_workspace(
        &self,
        id: &str,
        project: &crate::studio::WorkspaceRecord,
        business_root: &str,
    ) -> anyhow::Result<()> {
        let frozen = self
            .services
            .store
            .workspace_identity(id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("ACP member has no physical workspace identity"))?;
        let actual = self
            .resolve_workspace_identity(project, std::path::Path::new(business_root))
            .await?;
        anyhow::ensure!(frozen == actual, "ACP physical workspace identity changed");
        if let Some(lease) = self.services.worktrees.get(id) {
            lease.validate_identity()?;
            anyhow::ensure!(
                actual.matches_root(&lease.path),
                "ACP worktree binding changed"
            );
        }
        Ok(())
    }

    pub(in crate::studio) async fn prepare_acp_child_workspace(
        &self,
        request: &ChildThreadRequest,
        mode: crate::AgentWorkspaceMode,
    ) -> Result<PreparedChildWorkspace, ThreadAssemblyError> {
        let prepared = self.prepare_child_workspace(request, mode).await?;
        if let Some(worktree) = &prepared.worktree {
            self.confirm_worktree_binding(
                &worktree.lease,
                &prepared.workspace_usage,
                &request.workspace_owner,
            )
            .await
            .map_err(|error| resource_error("activate ACP child workspace", error))?;
        }
        Ok(prepared)
    }
}
