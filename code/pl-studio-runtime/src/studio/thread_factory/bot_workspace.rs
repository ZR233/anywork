//! Bot execution admission is read-only and precedes migration, tools, worktrees and model opening.
use super::{StudioThreadFactory, errors::resource_error};
use crate::studio::worktree::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity};
use crate::thread_assembler::{ChildThreadRequest, ThreadAssemblyError};
use crate::{AgentWorkspaceMode, ThreadWorkspaceMode};
use std::path::Path;

#[derive(Clone, Copy)]
pub(super) enum BotWorkspacePreparation {
    New,
    Existing,
}

impl StudioThreadFactory {
    pub(super) async fn bind_bot_project(
        &self,
        thread_id: &str,
        root_id: &str,
        project: &mut crate::studio::WorkspaceRecord,
        execution: &crate::studio::WorkspaceUsageLease,
        preparation: BotWorkspacePreparation,
    ) -> Result<Option<std::path::PathBuf>, ThreadAssemblyError> {
        if let Some(bot) = self
            .services
            .bots
            .saved_config_for_thread(root_id)
            .await
            .map_err(|error| resource_error("resolve bot workspace", error))?
        {
            // Migration reads the previous execution root as well as writing the bot-owned root.
            // Both admissions precede the copy; a resolver alone is not permission to prepare.
            let complete = matches!(preparation, BotWorkspacePreparation::New)
                || self
                    .services
                    .bots
                    .workspace_migration_complete(&bot, thread_id, &project.path)
                    .await
                    .map_err(|error| resource_error("verify bot workspace migration", error))?;
            let source = if complete {
                None
            } else {
                let source = self
                    .services
                    .worktrees
                    .reserve_project_workspace(thread_id, &self.services.ssh_manager, project)
                    .await
                    .map_err(Self::workspace_usage_error)?;
                let original = self
                    .resolve_workspace_identity(project, std::path::Path::new(&project.path))
                    .await
                    .map_err(Self::workspace_usage_error)?;
                self.services
                    .worktrees
                    .assign_workspace(&source, original)
                    .map_err(Self::workspace_usage_error)?;
                Some(source)
            };
            let root = self.services.bots.workspace_root(&bot);
            let mut assigned = project.clone();
            assigned.path = root.to_string_lossy().into_owned();
            assigned.ssh_alias = None;
            // Migration uses its own source/target reservations. Strict bot Profile admission has
            // already established that the final execution root is this managed root, never a WT.
            let target = self
                .reserve_workspace_use(thread_id, &assigned)
                .await
                .map_err(Self::workspace_usage_error)?;
            let parent = root
                .parent()
                .ok_or_else(|| {
                    ThreadAssemblyError::Identity("bot workspace has no managed parent".into())
                })?
                .to_owned();
            let canonical_parent = tokio::task::spawn_blocking(move || dunce::canonicalize(parent))
                .await?
                .map_err(|error| resource_error("resolve managed bot directory", error))?;
            let planned = canonical_parent.join("workspace");
            let identity = crate::studio::worktree::worktree_lease::WorkspaceIdentity::canonical(
                crate::studio::worktree::worktree_lease::WorkspaceEndpoint::Local,
                planned.to_string_lossy().into_owned(),
            )
            .map_err(Self::workspace_usage_error)?;
            if self
                .services
                .store
                .thread_preparation(thread_id)
                .await
                .map_err(|error| resource_error("read managed preparation owner", error))?
                .is_some()
            {
                self.services
                    .store
                    .bind_thread_preparation(thread_id, &identity)
                    .await
                    .map_err(|error| {
                        resource_error("fix managed execution binding before preparation", error)
                    })?;
            }
            if let Some(frozen) = self
                .services
                .store
                .workspace_identity(thread_id)
                .await
                .map_err(|error| resource_error("read frozen bot migration target", error))?
                && frozen != identity
            {
                return Err(ThreadAssemblyError::Workspace {
                    thread_id: thread_id.into(),
                    reason: "bot migration cannot rebind an existing physical execution identity"
                        .into(),
                });
            }
            self.services
                .worktrees
                .assign_workspace(&target, identity.clone())
                .map_err(Self::workspace_usage_error)?;
            pl_tool::workspace::path_safety::validate_path_for_write_async(
                &canonical_parent,
                &planned,
            )
            .await
            .map_err(|error| resource_error("validate managed bot workspace preparation", error))?;
            tokio::fs::create_dir_all(&planned)
                .await
                .map_err(|error| resource_error("materialize managed bot workspace", error))?;
            let actual = self
                .resolve_workspace_identity(&assigned, &planned)
                .await
                .map_err(Self::workspace_usage_error)?;
            self.services
                .worktrees
                .assign_workspace(&target, actual.clone())
                .map_err(Self::workspace_usage_error)?;
            // The canonical final assignment is known before any SessionFiles copy starts. The
            // real preparer/Entry owns `execution`, and the same lease owner retains failed files
            // across ordinary errors and restart. No auxiliary migration registry is needed.
            self.services
                .worktrees
                .assign_workspace(execution, actual.clone())
                .map_err(Self::workspace_usage_error)?;
            self.services
                .store
                .bind_workspace_identity(thread_id, &actual)
                .await
                .map_err(|error| resource_error("freeze final bot execution identity", error))?;
            self.services
                .worktrees
                .preserve_workspace_resources(thread_id, actual);
            project.path = match preparation {
                BotWorkspacePreparation::New => {
                    self.services
                        .bots
                        .prepare_new_workspace(&bot, thread_id)
                        .await
                }
                BotWorkspacePreparation::Existing => {
                    self.services
                        .bots
                        .prepare_workspace(&bot, thread_id, &project.path)
                        .await
                }
            }
            .map_err(|error| resource_error("prepare bot workspace", error))?
            .to_string_lossy()
            .into_owned();
            project.ssh_alias = None;
            drop(source);
            return Ok(Some(std::path::PathBuf::from(&project.path)));
        }
        Ok(None)
    }

    pub(super) async fn check_bot_spawn_workspace(
        &self,
        request: &ChildThreadRequest,
        mode: AgentWorkspaceMode,
        root: &crate::studio::records::DirectoryMember,
        managed_root: Option<&Path>,
    ) -> Result<(), ThreadAssemblyError> {
        let Some(managed) = managed_root else {
            return Ok(());
        };
        if root.session.workspace_mode != ThreadWorkspaceMode::Local
            || mode == AgentWorkspaceMode::Worktree
        {
            return Err(bot_workspace_refusal(
                &request.id,
                "bot children must use the bot-managed execution root; worktree Profiles are not permitted",
            ));
        }
        if mode == AgentWorkspaceMode::Review {
            let target = request.review_target_agent_id.as_deref().ok_or_else(|| {
                bot_workspace_refusal(&request.id, "bot review requires a frozen review target")
            })?;
            let target = self.directory_member(target)?;
            let assignment = request.review_workspace.as_ref().ok_or_else(|| {
                bot_workspace_refusal(&request.id, "bot review has no current target workspace")
            })?;
            if target.root_thread_id != root.root_thread_id
                || assignment.worktree.is_some()
                || !super::workspace_validation::same_workspace_path(
                    &assignment.root,
                    &managed.to_string_lossy(),
                    false,
                )
            {
                return Err(bot_workspace_refusal(
                    &request.id,
                    "bot review target is outside its managed execution root",
                ));
            }
        }
        Ok(())
    }

    /// Existing incompatible records remain readable. This gate neither migrates their history nor
    /// rewrites a binding; it only denies activation/continuation and emits a typed workspace error.
    pub(super) async fn verify_saved_bot_child_workspace(
        &self,
        thread: &crate::Thread,
        snapshot: Option<&pl_core::thread::ThreadSnapshot>,
        expected: &WorkspaceIdentity,
    ) -> Result<(), ThreadAssemblyError> {
        let snapshot = snapshot.ok_or_else(|| {
            bot_workspace_refusal(&thread.id, "bot child has no saved workspace receipt")
        })?;
        let assignment = crate::studio::workspace_receipt::from_snapshot(snapshot)
            .map_err(|error| resource_error("decode saved bot workspace receipt", error))?
            .ok_or_else(|| {
                bot_workspace_refusal(&thread.id, "bot child has no frozen workspace assignment")
            })?;
        let profile = crate::studio::model_route::required_saved_profile(snapshot, &thread.id)
            .map_err(|error| resource_error("decode saved bot child Profile", error))?;
        if assignment.mode == AgentWorkspaceMode::Worktree
            || assignment.worktree.is_some()
            || profile.workspace_mode != assignment.mode
        {
            return Err(bot_workspace_refusal(
                &thread.id,
                "saved bot child has an incompatible worktree/Profile binding; original data was preserved",
            ));
        }
        let actual = local_identity(Path::new(&assignment.root)).await?;
        let project = local_identity(Path::new(&assignment.project_root)).await?;
        if &actual != expected || &project != expected {
            return Err(bot_workspace_refusal(
                &thread.id,
                "saved bot child execution root differs from its bot-managed canonical root",
            ));
        }
        if assignment.mode == AgentWorkspaceMode::Review {
            let target = assignment.review_target.as_ref().ok_or_else(|| {
                bot_workspace_refusal(&thread.id, "saved bot reviewer has no frozen target")
            })?;
            self.check_bot_review_target(
                &thread.id,
                &thread.root_thread_id,
                &target.agent_id,
                expected,
            )
            .await?;
        }
        Ok(())
    }

    async fn check_bot_review_target(
        &self,
        reviewer: &str,
        root_id: &str,
        target: &str,
        expected: &WorkspaceIdentity,
    ) -> Result<(), ThreadAssemblyError> {
        let record = self.thread_record(target).await?;
        if record.root_thread_id != root_id || self.services.worktrees.get(target).is_some() {
            return Err(bot_workspace_refusal(
                reviewer,
                "bot review target has a different root or an owned worktree",
            ));
        }
        let frozen = self
            .services
            .store
            .workspace_identity(target)
            .await
            .map_err(|error| resource_error("read frozen bot review target", error))?
            .ok_or_else(|| {
                bot_workspace_refusal(
                    reviewer,
                    "bot review target has no frozen physical execution identity",
                )
            })?;
        self.check_bot_frozen_identity(reviewer, &frozen, expected)
            .await
    }

    async fn check_bot_frozen_identity(
        &self,
        id: &str,
        frozen: &WorkspaceIdentity,
        expected: &WorkspaceIdentity,
    ) -> Result<(), ThreadAssemblyError> {
        if frozen.endpoint != WorkspaceEndpoint::Local
            || frozen != expected
            || local_identity(Path::new(&frozen.root)).await? != *expected
        {
            return Err(bot_workspace_refusal(
                id,
                "frozen bot workspace is not the bot-managed canonical execution root",
            ));
        }
        Ok(())
    }
}

async fn local_identity(path: &Path) -> Result<WorkspaceIdentity, ThreadAssemblyError> {
    let path = path.to_owned();
    let canonical = tokio::task::spawn_blocking(move || dunce::canonicalize(path))
        .await?
        .map_err(|error| resource_error("resolve canonical bot execution root", error))?;
    WorkspaceIdentity::canonical(
        WorkspaceEndpoint::Local,
        canonical.to_string_lossy().into_owned(),
    )
    .map_err(StudioThreadFactory::workspace_usage_error)
}

fn bot_workspace_refusal(id: &str, reason: &str) -> ThreadAssemblyError {
    ThreadAssemblyError::Workspace {
        thread_id: id.into(),
        reason: reason.into(),
    }
}

#[cfg(test)]
#[path = "bot_workspace/migration_tests.rs"]
mod migration_tests;
