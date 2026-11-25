use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result};

use pl_tool::workspace::resolve_workspace_root;

use super::super::StudioRuntime;
use super::super::{SkillSearchResult, SkillsStateSnapshot};

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct ProjectActivationRecoveryBlock<'a> {
    workspace_id: &'a str,
    issues: Vec<crate::StudioRecoveryIssue>,
}

struct ProjectSkillsTarget {
    root: PathBuf,
    remote: Option<RemoteProjectSkills>,
}

struct RemoteProjectSkills {
    alias: String,
    files: Arc<pl_tool::workspace_file::ExecutorWorkspaceFileBackend>,
}

impl ProjectSkillsTarget {
    fn fingerprint(&self, settings: &str) -> String {
        let root = self.root.display();
        match &self.remote {
            Some(remote) => format!(
                "ssh:{}:{root}:{}:{settings}",
                remote.alias,
                remote.files.executor().id()
            ),
            None => format!("{root}:{settings}"),
        }
    }
}

impl StudioRuntime {
    /// Prepares project navigation and skills without retaining language services.
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
            return Err(crate::StudioError::new(
                crate::StudioErrorCode::Unavailable,
                "Project execution preparation is blocked by recovery",
                true,
            )
            .with_details(serde_json::to_value(ProjectActivationRecoveryBlock {
                workspace_id,
                issues,
            })?)
            .into());
        }
        let target = self.project_skills_target(workspace_id).await?;
        let settings = self.config_runtime.read()?.config.skills;
        let fingerprint = target.fingerprint(&self.skills.fingerprint(&settings)?);
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
        self.discover_project_skills(workspace_id, target, &settings)
            .await?;
        *self.activation.applied.write().await = Some(super::super::ProjectActivation {
            workspace_id: workspace_id.to_string(),
            fingerprint,
        });
        Ok(())
    }

    pub async fn discover_skills(&self, workspace_id: &str) -> Result<SkillsStateSnapshot> {
        let target = self.project_skills_target(workspace_id).await?;
        let settings = self.config_runtime.read()?.config.skills;
        self.discover_project_skills(workspace_id, target, &settings)
            .await
    }

    async fn project_skills_target(&self, workspace_id: &str) -> Result<ProjectSkillsTarget> {
        let project = self.project_record(workspace_id).await?;
        if let Some(alias) = project.ssh_alias {
            let host = self
                .ssh_manager
                .open_workspace_binding(&alias, project.path)
                .await?;
            let root = PathBuf::from(host.files().canonical_path());
            let remote = Some(RemoteProjectSkills {
                alias,
                files: Arc::new(host.files().clone()),
            });
            Ok(ProjectSkillsTarget { root, remote })
        } else {
            let root = resolve_workspace_root(Path::new(&project.path))?;
            Ok(ProjectSkillsTarget { root, remote: None })
        }
    }

    async fn discover_project_skills(
        &self,
        workspace_id: &str,
        target: ProjectSkillsTarget,
        settings: &pl_tool::skill::SkillsConfig,
    ) -> Result<SkillsStateSnapshot> {
        match target.remote {
            Some(remote) => {
                self.skills
                    .discover_remote(
                        workspace_id,
                        &target.root,
                        settings,
                        tokio_util::sync::CancellationToken::new(),
                        remote.files,
                    )
                    .await
            }
            None => {
                self.skills
                    .discover(workspace_id, &target.root, settings)
                    .await
            }
        }
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

    pub(in crate::studio::runtime) async fn project_record(
        &self,
        workspace_id: &str,
    ) -> Result<crate::WorkspaceRecord> {
        self.agent_facility
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.id == workspace_id)
            .context("selected project not found")
    }
}
