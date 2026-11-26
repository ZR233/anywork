//! Actual execution dependencies, shared by read-only audit and last-mile admission.
use super::{
    StudioThreadFactory,
    errors::{WorkspacePreparationFailure, is_workspace_preparation_failure, resource_error},
};
use crate::AgentWorkspaceAssignmentSnapshot;
use crate::agent::worktree::WorktreeError;
use crate::studio::{
    WorkspaceRecord,
    session_data_error::SessionDataError,
    worktree::{
        workspace_preparation,
        worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity, WorktreeLeaseState},
    },
};
use crate::thread_assembler::ThreadAssemblyError;
use anyhow::{Context, Result, ensure};
use pl_core::context::OpaquePayload;
use pl_core::thread::ThreadSnapshot;
use std::path::Path;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum ExecutionWorkspaceCheck {
    Audit,
    Prepare,
}

impl StudioThreadFactory {
    pub(crate) async fn verify_project_workspace(&self, project: &WorkspaceRecord) -> Result<()> {
        let identity = self
            .resolve_workspace_identity(project, Path::new(&project.path))
            .await
            .with_context(|| format!("resolve project execution resource {}", project.path))?;
        Self::verify_resolved_execution_identity(&identity).await
    }

    pub(super) async fn admit_saved_execution(
        &self,
        thread: &crate::Thread,
        snapshot: Option<&ThreadSnapshot>,
    ) -> Result<(), ThreadAssemblyError> {
        self.verify_and_report_execution_workspace(thread, snapshot)
            .await
            .map_err(|error| {
                error
                    .downcast::<ThreadAssemblyError>()
                    .unwrap_or_else(|source| {
                        resource_error("verify saved execution workspace", source)
                    })
            })?;
        self.services
            .recovery
            .ensure_thread_execution_access(thread)
            .map_err(|error| resource_error("saved Thread execution admission", error))
    }

    pub(crate) async fn verify_and_report_execution_workspace(
        &self,
        thread: &crate::Thread,
        snapshot: Option<&ThreadSnapshot>,
    ) -> Result<()> {
        let result = self
            .verify_execution_workspace(thread, snapshot, ExecutionWorkspaceCheck::Prepare)
            .await;
        let failure = match &result {
            Ok(()) => None,
            Err(error) if is_workspace_preparation_failure(error) => Some(error),
            Err(_) => return result,
        };
        self.services.product_events.emit_recovery_state(
            self.services
                .recovery
                .apply_execution_workspace_check(thread, failure),
        );
        result
    }

    /// Verifies the actual workspace against the supplied facts, without loading a checkpoint.
    pub(crate) async fn verify_execution_workspace(
        &self,
        thread: &crate::Thread,
        snapshot: Option<&ThreadSnapshot>,
        check: ExecutionWorkspaceCheck,
    ) -> Result<()> {
        let associated = self.project_record(&thread.workspace_id).await?;
        let frozen = self.services.store.workspace_identity(&thread.id).await?;
        if let Some(bot) = self
            .services
            .bots
            .saved_config_for_thread(&thread.root_thread_id)
            .await?
        {
            ensure!(
                bot.workspace_id == thread.workspace_id
                    && thread.workspace_mode == crate::ThreadWorkspaceMode::Local,
                WorktreeError::IdentityMismatch(
                    "bot execution directory association is incompatible".into()
                )
            );
            let complete = self
                .services
                .bots
                .workspace_migration_complete(&bot, &thread.id, &associated.path)
                .await?;
            if !complete {
                ensure!(
                    associated.ssh_alias.is_none(),
                    WorktreeError::IdentityMismatch(
                        "old bot migration source has no proven local binding".into()
                    )
                );
                self.verify_project_workspace(&associated)
                    .await
                    .context("bot migration still requires its original source")
                    .map_err(WorkspacePreparationFailure)?;
                let source = Path::new(&associated.path)
                    .join(pl_tool::workspace::SessionFiles::new(&thread.id).root());
                pl_tool::workspace::path_safety::validate_path_for_write_async(
                    Path::new(&associated.path),
                    &source,
                )
                .await
                .map_err(|source| WorkspacePreparationFailure(source.into()))?;
            }
            let managed = self.services.bots.workspace_root(&bot);
            let mut effective = associated;
            effective.path = managed.to_string_lossy().into_owned();
            effective.ssh_alias = None;
            if !complete
                && frozen.is_none()
                && thread.parent_thread_id.is_none()
                && check == ExecutionWorkspaceCheck::Prepare
                && !tokio::fs::try_exists(&managed)
                    .await
                    .map_err(|source| WorkspacePreparationFailure(source.into()))?
            {
                // Only preparation may materialize a missing managed target, while its still-needed
                // original source has just been proved. Audit/execution never infer completion.
                return Ok(());
            }
            let identity = self
                .resolve_workspace_identity(&effective, &managed)
                .await
                .map_err(WorkspacePreparationFailure)?;
            ensure!(
                frozen.as_ref().is_none_or(|frozen| *frozen == identity),
                WorktreeError::IdentityMismatch("bot physical execution identity changed".into())
            );
            Self::verify_resolved_execution_identity(&identity)
                .await
                .map_err(WorkspacePreparationFailure)?;
            if check == ExecutionWorkspaceCheck::Prepare && thread.parent_thread_id.is_some() {
                self.verify_saved_bot_child_workspace(thread, snapshot, &identity)
                    .await?;
            }
            return Ok(());
        }
        if check == ExecutionWorkspaceCheck::Audit {
            ensure!(
                snapshot.is_some() || frozen.is_some() || thread.parent_thread_id.is_none(),
                "cold child execution binding requires on-demand resolution"
            );
        }
        let assignment = snapshot
            .map(crate::studio::workspace_receipt::from_snapshot)
            .transpose()?
            .flatten();
        let effective = snapshot
            .and_then(|snapshot| snapshot.extensions.get("studio.project"))
            .map(|saved| decode_saved_project(&saved.payload))
            .transpose()?;
        self.verify_physical_binding(
            thread,
            &associated,
            effective.as_ref().unwrap_or(&associated),
            frozen.as_ref(),
            assignment.as_ref(),
        )
        .await
        .map_err(|source| WorkspacePreparationFailure(source).into())
    }

    async fn verify_physical_binding(
        &self,
        thread: &crate::Thread,
        associated: &WorkspaceRecord,
        effective: &WorkspaceRecord,
        frozen: Option<&WorkspaceIdentity>,
        assignment: Option<&AgentWorkspaceAssignmentSnapshot>,
    ) -> Result<()> {
        ensure!(
            effective.id == thread.workspace_id
                && effective.kind == associated.kind
                && effective.path == associated.path
                && effective.ssh_alias == associated.ssh_alias,
            "execution project binding changed"
        );
        let root = match (frozen, assignment) {
            (Some(identity), Some(assignment)) => {
                ensure!(
                    identity.matches_root(&assignment.root),
                    "execution assignment differs from its frozen identity"
                );
                identity.root.clone()
            }
            (Some(identity), None) => identity.root.clone(),
            (None, Some(assignment)) => assignment.root.clone(),
            (None, None) if thread.parent_thread_id.is_none() => thread.workspace_path.clone(),
            _ => anyhow::bail!("child execution binding remains unknown"),
        };
        let actual = self
            .resolve_workspace_identity(effective, Path::new(&root))
            .await?;
        let lease = self
            .services
            .worktrees
            .snapshot()
            .into_iter()
            .find(|lease| {
                actual.matches_root(&lease.path)
                    && lease.root_thread_id == thread.root_thread_id
                    && lease.workspace_id == thread.workspace_id
            });
        if let Some(lease) = &lease {
            lease.validate_identity()?;
            ensure!(
                lease.state != WorktreeLeaseState::Cleaned,
                "execution worktree was cleaned"
            );
        }
        ensure!(
            frozen.is_none_or(|identity| *identity == actual),
            WorktreeError::IdentityMismatch("execution canonical path or endpoint changed".into())
        );
        Self::verify_resolved_execution_identity(&actual).await?;
        if let Some(lease) = lease {
            let manager = workspace_preparation::manager_from_lease(
                &self.services.store,
                &self.services.ssh_manager,
                &lease,
                None,
            )
            .await?;
            manager
                .verify(&crate::agent::worktree::WorktreeHandle {
                    path: lease.path.into(),
                    base_commit: lease.base_commit,
                })
                .await?;
        } else if assignment.is_some_and(|assignment| assignment.worktree.is_some()) {
            anyhow::bail!("execution worktree has no matching owner or borrower lease");
        }
        Ok(())
    }

    // Call only with the identity just resolved for this admission. Frozen identity/lease
    // comparisons remain at the caller; resolving this same root twice is not a stronger seal.
    async fn verify_resolved_execution_identity(identity: &WorkspaceIdentity) -> Result<()> {
        if identity.endpoint == WorkspaceEndpoint::Local {
            ensure!(
                tokio::fs::metadata(&identity.root).await?.is_dir(),
                "execution resource is not a directory"
            );
        }
        Ok(())
    }
}

pub(super) fn decode_saved_project(payload: &OpaquePayload) -> Result<WorkspaceRecord> {
    const FORMAT: &str = "pl.studio.project";
    let binding_error = |source| SessionDataError::WorkspaceBinding {
        format: FORMAT,
        revision: payload.version(),
        source,
    };
    ensure!(
        payload.format() == FORMAT && payload.version() == 1,
        binding_error(anyhow::anyhow!("unsupported execution project binding"))
    );
    serde_json::from_str(payload.content()).map_err(|source| binding_error(source.into()).into())
}
