//! Business execution and host protocol cwd are distinct facts of the original ACP member.
use super::StudioThreadFactory;
use anyhow::{Context, Result, ensure};
use pl_tool::{
    command::WorkspaceExecutionBinding,
    environment::ExecutionEnvironment,
    remote::SshWorkspaceBinding,
    workspace::{AgentWorkspace, ToolWorkspace},
};
use std::path::{Path, PathBuf};

#[derive(Clone)]
pub(in crate::studio) struct PreparedAcpWorkspace {
    pub workspace: ToolWorkspace,
    pub remote: Option<SshWorkspaceBinding>,
    pub execution: WorkspaceExecutionBinding,
    pub environment: ExecutionEnvironment,
    pub lsp: Option<std::sync::Arc<super::PreparedAcpLsp>>,
    pub skills: Option<(
        std::sync::Arc<pl_tool::skill::FrozenSkillCatalog>,
        pl_tool::skill::SkillDiscoverySources,
    )>,
    pub store: crate::resource_store::FileResourceStore,
    pub host_scratch: PathBuf,
}

pub(in crate::studio) struct AcpWorkspaceRequest<'a> {
    pub id: &'a str,
    pub project: &'a crate::studio::WorkspaceRecord,
    pub business_root: &'a str,
    pub usage: &'a crate::studio::WorkspaceUsageLease,
    pub session_mode: crate::ThreadWorkspaceMode,
    pub config: &'a crate::config::StudioConfig,
    pub cancellation: &'a tokio_util::sync::CancellationToken,
}

impl StudioThreadFactory {
    pub(in crate::studio) async fn prepare_acp_root_worktree(
        &self,
        id: &str,
        project: &crate::studio::WorkspaceRecord,
    ) -> Result<crate::studio::worktree::worktree_lease::WorktreeLease> {
        ensure!(
            project.kind != crate::WorkspaceKind::Standalone,
            "standalone sessions only support local workspaces"
        );
        self.services.worktrees.mark_creating(id);
        crate::studio::worktree::workspace_preparation::create_root_session_worktree(
            &self.services.store,
            &self.services.worktrees,
            &self.services.ssh_manager,
            project,
            id,
            &|_, _, _| {},
        )
        .await
    }

    pub(in crate::studio) async fn confirm_acp_worktree(
        &self,
        lease: &crate::studio::worktree::worktree_lease::WorktreeLease,
        usage: &crate::studio::WorkspaceUsageLease,
        admission: &impl crate::thread_assembler::WorkspaceBindingAdmission,
    ) -> Result<()> {
        self.confirm_worktree_binding(lease, usage, admission).await
    }

    pub(in crate::studio) fn complete_acp_draft_worktree(&self, id: &str) {
        self.services.worktrees.clear_creating(id);
    }

    pub(in crate::studio) async fn preserve_acp_draft_worktree(&self, id: &str) -> Result<()> {
        use crate::studio::worktree::worktree_lease::WorktreeLeaseState;
        if let Some(lease) = self.services.worktrees.get(id)
            && lease.state != WorktreeLeaseState::Cleaned
        {
            self.services
                .worktrees
                .preserve_failed_session_binding(&lease)
                .await?;
        }
        self.services.worktrees.clear_creating(id);
        Ok(())
    }

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
        request: AcpWorkspaceRequest<'_>,
    ) -> Result<PreparedAcpWorkspace> {
        let AcpWorkspaceRequest {
            id,
            project,
            business_root,
            usage,
            session_mode,
            config,
            cancellation,
        } = request;
        let remote = self
            .open_remote_workspace(project, Path::new(business_root))
            .await?;
        ensure!(
            !cancellation.is_cancelled(),
            "ACP workspace preparation cancelled"
        );
        let identity = if let Some(remote) = &remote {
            let identity = crate::studio::worktree::worktree_lease::WorkspaceIdentity::canonical(
                crate::studio::worktree::worktree_lease::WorkspaceEndpoint::from_profile(Some(
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
            self.assign_workspace_identity(usage, identity).await?
        } else {
            self.assign_workspace_use(usage, project, Path::new(business_root))
                .await?
        };
        self.services
            .worktrees
            .preserve_workspace_resources(id, identity);
        let workspace = if self.services.worktrees.get(id).is_some()
            || session_mode == crate::ThreadWorkspaceMode::Worktree
        {
            AgentWorkspace::worktree(&project.path, business_root)
        } else {
            AgentWorkspace::host_permitted(&project.path, business_root, None)
        };
        let workspace =
            super::session_files::bind_thread_session_files(ToolWorkspace::new(workspace), id);
        let execution = match &remote {
            Some(remote) => remote.execution.clone(),
            None => {
                WorkspaceExecutionBinding::new(self.services.local_executor.clone(), business_root)?
            }
        };
        let environment = remote
            .as_ref()
            .map(|remote| remote.execution_environment.clone())
            .unwrap_or_else(ExecutionEnvironment::detect_local);
        super::session_files::prepare_bound_session_files(&workspace, &execution).await?;
        let skills = if config.runtime.tool_capabilities.skills && config.skills.enabled {
            self.services
                .skills
                .prepare_thread_catalog(
                    &project.id,
                    workspace.root(),
                    &config.skills,
                    cancellation.clone(),
                    Some(std::sync::Arc::new(execution.files())),
                )
                .await?
        } else {
            None
        };
        let lsp = if config.runtime.tool_capabilities.lsp {
            Some(std::sync::Arc::new(
                self.prepare_acp_lsp(&workspace, &execution, remote.is_some())
                    .await?,
            ))
        } else {
            None
        };
        Ok(PreparedAcpWorkspace {
            workspace,
            remote,
            execution,
            environment,
            lsp,
            skills,
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
