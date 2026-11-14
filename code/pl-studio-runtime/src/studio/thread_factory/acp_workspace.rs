//! Business execution and host protocol cwd are distinct facts of the original ACP member.
use super::StudioThreadFactory;
use anyhow::{Context, Result, ensure};
use pl_tool::{
    remote::SshWorkspaceBinding,
    workspace::{AgentWorkspace, ToolWorkspace},
};
use std::path::{Path, PathBuf};

#[derive(Clone)]
pub(in crate::studio) struct PreparedAcpWorkspace {
    pub workspace: ToolWorkspace,
    pub remote: SshWorkspaceBinding,
    pub store: crate::resource_store::FileResourceStore,
    pub host_scratch: PathBuf,
}

impl StudioThreadFactory {
    /// New Native and ACP members freeze exactly the same SSH workspace binding.
    pub(in crate::studio) async fn open_remote_workspace(
        &self,
        project: &crate::studio::WorkspaceRecord,
        root: &Path,
    ) -> Result<Option<SshWorkspaceBinding>> {
        match &project.ssh_alias {
            Some(server) => Ok(Some(
                self.services
                    .ssh_manager
                    .open_workspace_binding(
                        server,
                        root.to_str()
                            .context("workspace path is not UTF-8")?
                            .to_owned(),
                    )
                    .await?,
            )),
            None => Ok(None),
        }
    }

    pub(in crate::studio) fn acp_business_root(
        &self,
        id: &str,
        session: &crate::studio::records::SessionDirectoryRecord,
    ) -> String {
        self.services
            .worktrees
            .get(id)
            .map(|lease| lease.path)
            .unwrap_or_else(|| session.workspace_path.clone())
    }

    /// Only the registered product preparation owner calls this, never an auth probe or Agent.
    pub(in crate::studio) async fn prepare_acp_protocol_cwd(
        &self,
        id: &str,
        project: &crate::studio::WorkspaceRecord,
        business_root: &str,
        saved: Option<&str>,
    ) -> Result<String> {
        let path = if project.ssh_alias.is_some() {
            self.services
                .store
                .session_scratch_dir_for(&project.id, id)?
                .join("acp-cwd")
        } else {
            PathBuf::from(business_root)
        };
        let expected = path.to_str().context("ACP protocol cwd is not UTF-8")?;
        ensure!(
            saved.is_none_or(|saved| saved == expected),
            "ACP host protocol cwd changed"
        );
        if project.ssh_alias.is_some() {
            tokio::fs::create_dir_all(&path).await?;
            let metadata = tokio::fs::symlink_metadata(&path).await?;
            ensure!(
                metadata.is_dir() && !metadata.file_type().is_symlink(),
                "ACP cwd must be a private host directory"
            );
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                tokio::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o700)).await?;
            }
        }
        Ok(expected.to_owned())
    }

    pub(in crate::studio) async fn prepare_acp_workspace(
        &self,
        id: &str,
        project: &crate::studio::WorkspaceRecord,
        business_root: &str,
        usage: &crate::studio::WorkspaceUsageLease,
        session_mode: pl_protocol::ThreadWorkspaceMode,
        cancellation: &tokio_util::sync::CancellationToken,
    ) -> Result<PreparedAcpWorkspace> {
        let remote = self
            .open_remote_workspace(project, Path::new(business_root))
            .await?
            .context("ACP workspace tools require an SSH binding")?;
        let identity = crate::studio::agent_host::worktree_lease::WorkspaceIdentity::canonical(
            crate::studio::agent_host::worktree_lease::WorkspaceEndpoint::from_profile(Some(
                &remote.profile,
            )),
            remote.files().canonical_path().into(),
        )?;
        if let Some(frozen) = self.services.store.workspace_identity(id).await? {
            ensure!(
                identity == frozen,
                "ACP physical workspace identity changed"
            );
        }
        ensure!(
            !cancellation.is_cancelled(),
            "ACP workspace preparation cancelled"
        );
        self.assign_workspace_identity(usage, identity.clone())
            .await?;
        self.services
            .worktrees
            .preserve_workspace_resources(id, identity);
        let workspace = if self.services.worktrees.get(id).is_some()
            || session_mode == pl_protocol::ThreadWorkspaceMode::Worktree
        {
            AgentWorkspace::worktree(&project.path, business_root)
        } else {
            AgentWorkspace::host_permitted(&project.path, business_root, None)
        };
        let workspace =
            super::session_files::bind_thread_session_files(ToolWorkspace::new(workspace), id);
        super::session_files::prepare_bound_session_files(&workspace, &remote.execution).await?;
        Ok(PreparedAcpWorkspace {
            workspace,
            remote,
            store: crate::resource_store::FileResourceStore::new(
                self.services
                    .store
                    .session_resources_dir_for(&project.id, id)?,
            ),
            host_scratch: self
                .services
                .store
                .session_scratch_dir_for(&project.id, id)?,
        })
    }
}
