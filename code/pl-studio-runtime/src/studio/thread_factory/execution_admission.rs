//! Actual execution dependencies, shared by read-only audit and last-mile admission.
use super::StudioThreadFactory;
use crate::studio::{
    ProjectRecord,
    agent_host::{
        workspace_preparation,
        worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity, WorktreeLeaseState},
    },
};
use anyhow::{Context, Result, ensure};
use std::path::Path;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum ExecutionWorkspaceCheck {
    Audit,
    Prepare,
    Execute,
}

impl StudioThreadFactory {
    pub(crate) async fn verify_project_workspace(&self, project: &ProjectRecord) -> Result<()> {
        let identity = self
            .resolve_workspace_identity(project, Path::new(&project.path))
            .await
            .with_context(|| format!("resolve project execution resource {}", project.path))?;
        self.verify_execution_identity(project, &identity).await
    }

    /// Audit never opens cold history. Admission resolves unknown child bindings on demand only;
    /// neither mode activates a model or repairs/rebinds a physical resource.
    pub(crate) async fn verify_execution_workspace(
        &self,
        thread: &pl_protocol::Thread,
        snapshot: Option<&pl_core::thread::ThreadSnapshot>,
        check: ExecutionWorkspaceCheck,
    ) -> Result<()> {
        let associated = self.project_record(&thread.project_id).await?;
        let frozen = self.services.store.workspace_identity(&thread.id).await?;
        if let Some(bot) = self
            .services
            .bots
            .config_for_thread(&thread.root_thread_id)
            .await?
        {
            ensure!(
                bot.project_id == thread.project_id
                    && thread.workspace_mode == pl_protocol::ThreadWorkspaceMode::Local,
                "bot execution directory association is incompatible"
            );
            let complete = self
                .services
                .bots
                .workspace_migration_complete(&bot, &thread.id, &associated.path)
                .await?;
            if !complete {
                ensure!(
                    check != ExecutionWorkspaceCheck::Execute,
                    "bot execution files have not completed materialization"
                );
                ensure!(
                    associated.ssh_alias.is_none(),
                    "old bot migration source has no proven local binding"
                );
                self.verify_project_workspace(&associated)
                    .await
                    .context("bot migration still requires its original source")?;
                let source = Path::new(&associated.path)
                    .join(pl_tool::workspace::SessionFiles::new(&thread.id).root());
                pl_tool::workspace::path_safety::validate_path_for_write_async(
                    Path::new(&associated.path),
                    &source,
                )
                .await?;
            }
            let managed = self.services.bots.workspace_root(&bot);
            let mut effective = associated;
            effective.path = managed.to_string_lossy().into_owned();
            effective.ssh_alias = None;
            if !complete
                && frozen.is_none()
                && check == ExecutionWorkspaceCheck::Prepare
                && !tokio::fs::try_exists(&managed).await?
            {
                // Only preparation may materialize a missing managed target, while its still-needed
                // original source has just been proved. Audit/execution never infer completion.
                return Ok(());
            }
            let identity = self
                .resolve_workspace_identity(&effective, &managed)
                .await?;
            ensure!(
                frozen.as_ref().is_none_or(|frozen| *frozen == identity),
                "bot physical execution identity changed"
            );
            self.verify_execution_identity(&effective, &identity)
                .await?;
            if check != ExecutionWorkspaceCheck::Audit {
                self.ensure_bot_execution_workspace(thread, snapshot)
                    .await?;
            }
            return Ok(());
        }
        let loaded;
        let snapshot =
            if snapshot.is_none() && frozen.is_none() && thread.parent_thread_id.is_some() {
                ensure!(
                    check != ExecutionWorkspaceCheck::Audit,
                    "cold child execution binding requires on-demand resolution"
                );
                loaded = super::recovery::load_checkpoint_read_only(&self.services.store, thread)
                    .await?
                    .context("child execution binding has no saved checkpoint")?;
                Some(&loaded.state)
            } else {
                snapshot
            };
        let assignment = snapshot
            .map(crate::studio::workspace_receipt::from_snapshot)
            .transpose()
            .map_err(anyhow::Error::msg)?
            .flatten();
        let effective = snapshot
            .and_then(|snapshot| snapshot.extensions.get("studio.project"))
            .map(|saved| -> Result<ProjectRecord> {
                ensure!(
                    saved.payload.format() == "pl.studio.project" && saved.payload.version() == 1,
                    "unsupported execution project binding"
                );
                Ok(serde_json::from_str(saved.payload.content())?)
            })
            .transpose()?
            .unwrap_or(associated.clone());
        ensure!(
            effective.id == thread.project_id
                && effective.path == associated.path
                && effective.ssh_alias == associated.ssh_alias,
            "execution project binding changed"
        );
        let root = match (&frozen, &assignment) {
            (Some(identity), Some(assignment)) => {
                ensure!(
                    identity.root == assignment.root,
                    "execution assignment differs from its frozen identity"
                );
                identity.root.clone()
            }
            (Some(identity), None) => identity.root.clone(),
            (None, Some(assignment)) => assignment.root.clone(),
            (None, None) if thread.parent_thread_id.is_none() => thread.workspace_path.clone(),
            _ => anyhow::bail!("child execution binding remains unknown"),
        };
        let lease = self
            .services
            .worktrees
            .snapshot()
            .into_iter()
            .find(|lease| {
                lease.path == root
                    && lease.root_thread_id == thread.root_thread_id
                    && lease.project_id == thread.project_id
            });
        if let Some(lease) = &lease {
            lease.validate_identity()?;
            ensure!(
                lease.state != WorktreeLeaseState::Cleaned,
                "execution worktree was cleaned"
            );
        }
        let actual = self
            .resolve_workspace_identity(&effective, Path::new(&root))
            .await?;
        ensure!(
            frozen.as_ref().is_none_or(|identity| *identity == actual),
            "execution canonical identity or endpoint changed"
        );
        self.verify_execution_identity(&effective, &actual).await?;
        if let Some(lease) = lease {
            let manager = workspace_preparation::manager_from_lease(
                &self.services.store,
                &self.services.ssh_manager,
                &lease,
            )
            .await?;
            manager
                .verify(&crate::agent::worktree::WorktreeHandle {
                    path: lease.path.into(),
                    base_commit: lease.base_commit,
                })
                .await?;
        } else if assignment
            .as_ref()
            .is_some_and(|assignment| assignment.worktree.is_some())
        {
            anyhow::bail!("execution worktree has no matching owner or borrower lease");
        }
        Ok(())
    }

    async fn verify_execution_identity(
        &self,
        project: &ProjectRecord,
        identity: &WorkspaceIdentity,
    ) -> Result<()> {
        let current = self
            .resolve_workspace_identity(project, Path::new(&identity.root))
            .await
            .with_context(|| format!("verify execution root {}", identity.root))?;
        ensure!(
            current == *identity,
            "execution resource changed canonical identity"
        );
        if identity.endpoint == WorkspaceEndpoint::Local {
            ensure!(
                tokio::fs::metadata(&identity.root).await?.is_dir(),
                "execution resource is not a directory"
            );
        }
        Ok(())
    }
}
