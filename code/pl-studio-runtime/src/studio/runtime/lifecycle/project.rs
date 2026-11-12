use std::path::Path;
use std::sync::Arc;

use anyhow::{Context, Result};

use pl_tool::workspace::resolve_workspace_root;

use super::super::StudioRuntime;
use super::super::lsp_state::health;
use super::super::{SkillSearchResult, SkillsStateSnapshot};

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct ProjectActivationRecoveryBlock<'a> {
    workspace_id: &'a str,
    issues: Vec<crate::StudioRecoveryIssue>,
}

impl StudioRuntime {
    /// Prepares workspace services and schedules optional language services in the background.
    /// This is not a read-only navigation/history query; blocked projects remain available through
    /// the independent directory and history reads when their access is not blocked.
    pub async fn activate_project(&self, workspace_id: &str) -> Result<()> {
        let issues = self
            .recovery_issues()
            .into_iter()
            .filter(|issue| {
                let applies = match issue.scope {
                    crate::StudioRecoveryIssueScope::Application => true,
                    crate::StudioRecoveryIssueScope::Project => {
                        issue.workspace_id.as_deref() == Some(workspace_id)
                    }
                    crate::StudioRecoveryIssueScope::Thread => false,
                };
                applies
                    && match issue.impact {
                        crate::StudioRecoveryImpact::Advisory => false,
                        crate::StudioRecoveryImpact::ExecutionBlocked
                        | crate::StudioRecoveryImpact::AccessBlocked => true,
                    }
            })
            .collect::<Vec<_>>();
        if !issues.is_empty() {
            return Err(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Unavailable,
                "Project execution preparation is blocked by recovery",
                true,
            )
            .with_details(serde_json::to_value(ProjectActivationRecoveryBlock {
                workspace_id,
                issues,
            })?)
            .into());
        }
        let project = self.project_record(workspace_id).await?;
        let lsp = self.external_runtimes.lsp.execution_scope(
            &super::super::lsp_state::execution_endpoint(project.ssh_alias.as_deref()),
        );
        if let Some(server_id) = &project.ssh_alias {
            let host = self
                .ssh_manager
                .open_workspace_host(server_id, project.path.clone())
                .await?;
            let workspace_root = std::path::PathBuf::from(host.files.canonical_path());
            let settings = self.config_runtime.read()?;
            lsp.configure_workspace_from_directory(
                &workspace_root,
                Some(Arc::new(host.clone())),
                None,
            )
            .await;
            let fingerprint = format!(
                "ssh:{server_id}:{}:{}:{}",
                workspace_root.display(),
                host.files.executor().id().to_string().as_str(),
                super::super::skill_catalog::skills_fingerprint(&settings.config.skills)?,
            );
            let _activation_command = self.activation.command_lock.lock().await;
            if self
                .activation
                .applied
                .read()
                .await
                .as_ref()
                .is_some_and(|applied| {
                    applied.workspace_id == workspace_id && applied.fingerprint == fingerprint
                })
            {
                return Ok(());
            }
            let _command = self.external_runtimes.lsp_state.command().await;
            self.external_runtimes
                .lsp_state
                .begin(pl_protocol::StateOperation::Activate)
                .await?;
            let health = health(&self.external_runtimes.lsp).await;
            self.external_runtimes.lsp_state.ready(health, true).await?;
            let _ = self
                .skills
                .discover_remote(
                    workspace_id,
                    &workspace_root,
                    &settings.config.skills,
                    tokio_util::sync::CancellationToken::new(),
                    Arc::new(host.files.clone()),
                )
                .await?;
            *self.activation.applied.write().await = Some(super::super::ProjectActivation {
                workspace_id: workspace_id.to_string(),
                fingerprint,
            });
            return Ok(());
        }
        let workspace_root = resolve_workspace_root(Path::new(&project.path))?;
        let settings = self.config_runtime.read()?;
        let host = self.local_lsp_host(&workspace_root).await;
        lsp.configure_workspace_from_directory(
            &workspace_root,
            host,
            Some(self.store.paths().home().join("lsp/host")),
        )
        .await;
        let fingerprint = format!(
            "{}:{}",
            workspace_root.display(),
            super::super::skill_catalog::skills_fingerprint(&settings.config.skills)?,
        );
        let _activation_command = self.activation.command_lock.lock().await;
        if self
            .activation
            .applied
            .read()
            .await
            .as_ref()
            .is_some_and(|applied| {
                applied.workspace_id == workspace_id && applied.fingerprint == fingerprint
            })
        {
            return Ok(());
        }
        let _command = self.external_runtimes.lsp_state.command().await;
        self.external_runtimes
            .lsp_state
            .begin(pl_protocol::StateOperation::Activate)
            .await?;
        let health = health(&self.external_runtimes.lsp).await;
        self.external_runtimes.lsp_state.ready(health, true).await?;
        let _ = self
            .skills
            .discover(workspace_id, &workspace_root, &settings.config.skills)
            .await?;
        *self.activation.applied.write().await = Some(super::super::ProjectActivation {
            workspace_id: workspace_id.to_string(),
            fingerprint,
        });
        Ok(())
    }

    pub async fn discover_skills(&self, workspace_id: &str) -> Result<SkillsStateSnapshot> {
        let project = self.project_record(workspace_id).await?;
        if let Some(server_id) = &project.ssh_alias {
            let host = self
                .ssh_manager
                .open_workspace_host(server_id, project.path.clone())
                .await?;
            let workspace_root = std::path::PathBuf::from(host.files.canonical_path());
            let settings = self.config_runtime.read()?;
            return self
                .skills
                .discover_remote(
                    workspace_id,
                    &workspace_root,
                    &settings.config.skills,
                    tokio_util::sync::CancellationToken::new(),
                    Arc::new(host.files.clone()),
                )
                .await;
        }
        let workspace_root = resolve_workspace_root(Path::new(&project.path))?;
        let settings = self.config_runtime.read()?;
        self.skills
            .discover(workspace_id, &workspace_root, &settings.config.skills)
            .await
    }

    pub async fn search_skills(
        &self,
        workspace_id: &str,
        query: &str,
        limit: usize,
    ) -> Result<SkillSearchResult> {
        self.project_record(workspace_id).await?;
        self.skills.search(workspace_id, query, limit).await
    }

    pub async fn probe_lsp_server(&self, workspace_id: &str) -> Result<()> {
        let project = self.project_record(workspace_id).await?;
        let lsp = self.external_runtimes.lsp.execution_scope(
            &super::super::lsp_state::execution_endpoint(project.ssh_alias.as_deref()),
        );
        let (workspace_root, host, defaults) = if let Some(alias) = &project.ssh_alias {
            let host = self
                .ssh_manager
                .open_workspace_host(alias, project.path.clone())
                .await?;
            (
                std::path::PathBuf::from(host.files.canonical_path()),
                Some(Arc::new(host) as Arc<dyn pl_lsp::host::LspHostBackend>),
                None,
            )
        } else {
            let root = resolve_workspace_root(Path::new(&project.path))?;
            let host = self.local_lsp_host(&root).await;
            (root, host, Some(self.store.paths().home().join("lsp/host")))
        };
        let _command = self.external_runtimes.lsp_state.command().await;
        self.external_runtimes
            .lsp_state
            .begin(pl_protocol::StateOperation::Probe)
            .await?;
        lsp.configure_workspace_from_directory(&workspace_root, host, defaults)
            .await;
        lsp.retry_workspace_configuration(&workspace_root).await;
        let health = health(&self.external_runtimes.lsp).await;
        self.external_runtimes.lsp_state.ready(health, true).await?;
        Ok(())
    }

    async fn reset_lsp(
        &self,
        lsp: pl_lsp::runtime::LspRuntimeRegistry,
        scope: pl_lsp::runtime::LspScope,
    ) -> Result<()> {
        let _command = self.external_runtimes.lsp_state.command().await;
        self.external_runtimes
            .lsp_state
            .begin(pl_protocol::StateOperation::Reset)
            .await?;
        let result = lsp.reset_lsp(scope).await.map_err(anyhow::Error::from);
        match result {
            Ok(()) => {
                let health = health(&self.external_runtimes.lsp).await;
                self.external_runtimes
                    .lsp_state
                    .ready(health, false)
                    .await?;
                Ok(())
            }
            Err(error) => {
                self.external_runtimes.lsp_state.failed(&error).await?;
                Err(error)
            }
        }
    }

    /// Resolves transport-neutral Project identities into an internal LSP reset scope.
    pub async fn reset_lsp_request(
        &self,
        request: pl_protocol::studio::LspResetRequest,
    ) -> Result<()> {
        let workspace_id = match &request {
            pl_protocol::studio::LspResetRequest::Server { workspace_id, .. }
            | pl_protocol::studio::LspResetRequest::Workspace { workspace_id } => {
                Some(workspace_id)
            }
            pl_protocol::studio::LspResetRequest::All => None,
        };
        let lsp = if let Some(id) = workspace_id {
            let project = self.project_record(id).await?;
            self.external_runtimes.lsp.execution_scope(
                &super::super::lsp_state::execution_endpoint(project.ssh_alias.as_deref()),
            )
        } else {
            self.external_runtimes.lsp.clone()
        };
        let scope = match request {
            pl_protocol::studio::LspResetRequest::Server {
                workspace_id,
                server_id,
            } => pl_lsp::runtime::LspScope::Server {
                workspace_root: self.project_workspace_root(&workspace_id).await?,
                server_id,
            },
            pl_protocol::studio::LspResetRequest::Workspace { workspace_id } => {
                pl_lsp::runtime::LspScope::Workspace {
                    workspace_root: self.project_workspace_root(&workspace_id).await?,
                }
            }
            pl_protocol::studio::LspResetRequest::All => pl_lsp::runtime::LspScope::All,
        };
        self.reset_lsp(lsp, scope).await
    }

    async fn project_workspace_root(&self, workspace_id: &str) -> Result<std::path::PathBuf> {
        let project = self.project_record(workspace_id).await?;
        if project.ssh_alias.is_some() {
            Ok(std::path::PathBuf::from(project.path))
        } else {
            Ok(resolve_workspace_root(Path::new(&project.path))?)
        }
    }

    async fn local_lsp_host(&self, root: &Path) -> Option<Arc<dyn pl_lsp::host::LspHostBackend>> {
        let root = root.to_str()?;
        pl_lsp::host::ExecutorLspHost::new(self.thread_factory.local_executor(), root)
            .map(|host| Arc::new(host) as Arc<dyn pl_lsp::host::LspHostBackend>)
            .map_err(|error| tracing::warn!(%error, "LSP host preparation failed"))
            .ok()
    }

    async fn project_record(&self, workspace_id: &str) -> Result<crate::WorkspaceRecord> {
        self.agent_facility
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.id == workspace_id)
            .context("selected project not found")
    }
}
