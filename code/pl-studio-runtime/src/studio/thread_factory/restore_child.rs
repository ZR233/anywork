//! Cold child activation restores saved facts and opens fresh services.
//!
//! A `worktree` child whose saved receipt has no physical worktree is **not** silently rebuilt: a
//! missing directory is a broken site and fails with a typed `Workspace` error that the activation
//! path publishes as a Recovery diagnosis. Ordinary activation never recreates the saved site.
use super::workspace_validation::{same_workspace_path, verify_worktree_declarations};
use super::{
    StudioThreadFactory,
    errors::{resource_error, workspace_error},
    execution_admission::decode_saved_project,
};
use crate::{
    agent::definition::VerifiedAgentIdentity,
    thread_assembler::{StudioThreadSpec, ThreadAssemblyError, ThreadPreparation},
};
use pl_model::config::AgentRoleId;
use pl_tool::workspace::ToolWorkspace;
use std::{collections::BTreeMap, path::PathBuf};

impl StudioThreadFactory {
    pub(super) async fn prepare_restored_child(
        &self,
        request: ThreadPreparation,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        super::native_assembly::NativeThreadAssemblyBuilder::restored_child(self, request)
            .assemble()
            .await
    }

    /// Restored-child pipeline. Shared steps are reservation, canonical root resolution,
    /// assignment, session resources, tool binding, persistence, model binding, spec
    /// composition, and worktree confirmation. Cancellation after tools is `Closed`, not
    /// the new-child `Cancelled` result, and this path does not enroll a new export member.
    pub(super) async fn assemble_native_restored_child(
        &self,
        request: ThreadPreparation,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        let id = request.identity.id();
        self.bind_resource_scope(id, &request.workspace_owner.native_resources())?;
        self.ensure_member_execution_allowed(id)
            .await
            .map_err(|error| resource_error("restore child admission", error))?;
        let thread = self.thread_record(id).await?;
        if thread.parent_thread_id.as_deref() != request.identity.parent_id()
            || thread.parent_thread_id.is_none()
        {
            return Err(ThreadAssemblyError::Identity(id.to_owned()));
        }
        if thread.visibility != crate::studio::ThreadVisibility::Active {
            return Err(ThreadAssemblyError::Closed);
        }
        if thread.role == crate::config::ROOT_AGENT_ROUTE_KEY {
            return Err(ThreadAssemblyError::Identity(
                "child role is retired: planner".into(),
            ));
        }
        let protocol_thread: crate::Thread = thread.clone().into();
        let mut current = request.current.ok_or_else(|| {
            ThreadAssemblyError::Identity(format!("child {id} has no saved current"))
        })?;
        let mut restored = current.state.to_paused_snapshot();
        self.admit_saved_execution(&protocol_thread, Some(&restored))
            .await?;
        // Core Closed belongs to the previous owner (including graceful host shutdown).
        // Only Studio's durable explicit-close intent prohibits a new execution incarnation.
        if crate::studio::agent_close::is_explicitly_closed(&restored)
            .map_err(|error| resource_error("read child close intent", error))?
        {
            self.project_child_close(&protocol_thread, &restored)
                .await?;
            return Err(ThreadAssemblyError::Closed);
        }
        let mut project = self.project_record(&thread.workspace_id).await?;
        let workspace_usage = self
            .reserve_native_workspace(
                id,
                &thread.root_thread_id,
                &project,
                &request.workspace_owner,
            )
            .await?;
        let bot_root = self
            .bind_bot_project(
                id,
                &thread.root_thread_id,
                &mut project,
                &workspace_usage,
                super::bot_workspace::BotWorkspacePreparation::Existing,
            )
            .await?;
        let workspace_mismatch = |reason: &str| ThreadAssemblyError::Workspace {
            thread_id: id.to_owned(),
            reason: reason.into(),
        };
        let saved = restored
            .extensions
            .get(crate::studio::workspace_receipt::EXTENSION)
            .ok_or_else(|| workspace_mismatch("saved child has no workspace receipt"))?;
        let assignment: crate::AgentWorkspaceAssignmentSnapshot =
            crate::studio::workspace_receipt::from_payload(&saved.payload)
                .map_err(|error| resource_error("decode saved workspace binding", error))?;

        let config = self
            .services
            .config_runtime
            .read()
            .map(|snapshot| snapshot.config)?;
        let role = AgentRoleId::new(thread.role.clone())?;
        let profile = crate::studio::model_route::required_saved_profile(&restored, id)
            .map_err(|error| resource_error("load saved child Agent Profile", error))?;
        if profile.profile_id != thread.role {
            return Err(ThreadAssemblyError::Identity(
                "saved child Agent Profile identity does not match its directory role".into(),
            ));
        }
        // The frozen Profile supplies the Agent identity for a legacy instruction snapshot; the
        // saved role text is preserved and never re-rendered from the current catalog.
        let saved_identity = VerifiedAgentIdentity::child(&profile).map_err(|error| {
            ThreadAssemblyError::Identity(format!("invalid child Agent: {error}"))
        })?;
        // Instruction migration only rewrites the frozen extension payload. Keep the complete
        // current state intact instead of round-tripping it through a legacy checkpoint.
        crate::instruction::migrate_saved_representation(&mut restored, &saved_identity)
            .map_err(|error| resource_error("migrate saved child instructions", error))?;
        current.state.extensions = restored.extensions.clone();
        current.state.extension_sequence = restored.extension_sequence;
        let route_selector = crate::studio::model_route::profile_route(&profile)
            .map_err(|error| resource_error("read saved child model route", error))?;
        let resolved = crate::studio::delegation::resolve_child_route(&config, &profile);
        let (route, model_available) = match resolved {
            Ok(route) => (route, true),
            Err(error) => {
                tracing::warn!(thread_id = id, %error, "saved child model route is unavailable");
                let fallback = crate::studio::model_route::unavailable_placeholder(
                    &config,
                    role,
                    &route_selector,
                )
                .map_err(|error| resource_error("restore unavailable child placeholder", error))?;
                (fallback, false)
            }
        };
        let saved_project = restored
            .extensions
            .get("studio.project")
            .ok_or_else(|| workspace_mismatch("saved child has no project binding"))?;
        let previous = decode_saved_project(&saved_project.payload)
            .map_err(|error| resource_error("decode saved child project binding", error))?;
        if previous.id != project.id
            || previous.kind != project.kind
            || previous.path != project.path
            || previous.ssh_alias != project.ssh_alias
        {
            return Err(workspace_mismatch("child project target changed"));
        }
        // Resolve the actual root once. Existing child worktrees keep their original receipt;
        // this boundary neither selects a new HEAD nor rebuilds the session checkout.
        let workspace_mode = thread.workspace_mode;
        let root_thread = self.directory_member(&thread.root_thread_id)?;
        if root_thread.session.workspace_mode != workspace_mode {
            return Err(workspace_mismatch(
                "saved child root workspace mode changed",
            ));
        }
        let local_root = bot_root
            .clone()
            .unwrap_or_else(|| PathBuf::from(&root_thread.session.workspace_path));
        let project_copy = project.clone();
        let root = Self::resolve_canonical_project_root(
            project_copy,
            bot_root,
            "resolve restored session workspace",
        )
        .await?;
        let session_root =
            crate::studio::worktree::workspace_preparation::root_session_workspace_root(
                &self.services.store,
                &self.services.worktrees,
                &self.services.ssh_manager,
                &root_thread,
                &project,
                local_root,
            )
            .await
            .map_err(|error| workspace_error("resolve restored root session workspace", error))?
            .0;
        if std::path::Path::new(&assignment.project_root) != root {
            return Err(workspace_mismatch(
                "saved child workspace has a different project root",
            ));
        }
        let mut verified_lease = None;
        match assignment.mode {
            crate::AgentWorkspaceMode::Unrestricted | crate::AgentWorkspaceMode::Directory
                if std::path::Path::new(&assignment.root) == session_root
                    && assignment.worktree.is_none() => {}
            crate::AgentWorkspaceMode::Review => {
                // Explicit activation prepares its real connection below, then validates the
                // borrowed owner through the same factory boundary as hot review admission.
            }
            crate::AgentWorkspaceMode::Worktree => {
                let receipt = assignment
                    .worktree
                    .as_ref()
                    .filter(|receipt| receipt.path == assignment.root)
                    .ok_or_else(|| workspace_mismatch("invalid saved worktree receipt"))?;
                let verified = self
                    .ensure_restored_child_worktree(receipt, &thread, &project)
                    .await?;
                // The workspace below is built from the saved assignment, so the directory that was
                // actually verified must be exactly the one that assignment names; anything else would
                // hand the child tools a root the identity checks never covered.
                if !same_workspace_path(
                    &verified.path,
                    &assignment.root,
                    project.ssh_alias.is_some(),
                ) {
                    return Err(workspace_mismatch(
                        "verified child worktree differs from the saved workspace assignment root",
                    ));
                }
                verified_lease = Some(verified);
            }
            crate::AgentWorkspaceMode::Unrestricted | crate::AgentWorkspaceMode::Directory => {
                return Err(workspace_mismatch(
                    "invalid saved child workspace assignment",
                ));
            }
        }
        if profile.workspace_mode != assignment.mode {
            return Err(workspace_mismatch(
                "saved child Profile conflicts with its workspace assignment",
            ));
        }
        let workspace = super::child_resources::assigned_workspace(&assignment, workspace_mode);
        self.assign_native_workspace(&workspace_usage, &project, workspace.root())
            .await?;

        let resources = self.open_session_resources(
            &thread.workspace_id,
            id,
            "resolve restored child session resources",
        )?;
        let mut prepared = self
            .bind_native_tools(super::native_assembly::NativeToolBinding {
                workspace_usage: workspace_usage.clone(),
                thread_id: id,
                cancellation: &request.cancellation,
                config: &config,
                route: &route,
                project: &project,
                root_thread_id: &thread.root_thread_id,
                workspace: ToolWorkspace::new(workspace),
                store: resources.clone(),
                assignment: Some(&assignment),
            })
            .await?;

        let review_check = if assignment.mode == crate::AgentWorkspaceMode::Review {
            Some(
                self.verify_review_workspace(id, &assignment)
                    .await
                    .map_err(|error| resource_error("verify restored review workspace", error))?,
            )
        } else {
            None
        };
        if request.cancellation.is_cancelled() {
            return Err(ThreadAssemblyError::Closed);
        }
        let persistence = self
            .open_native_persistence(protocol_thread, "open restored child persistence")
            .await?;
        let initial_extensions = BTreeMap::new();
        let model = self.bind_native_model(
            &route,
            &config,
            prepared.hosted,
            if model_available {
                super::native_assembly::NativeModelAvailability::Bind
            } else {
                super::native_assembly::NativeModelAvailability::LeaveUnbound
            },
        )?;
        let spec = Self::compose_native_spec(super::native_assembly::NativeSpecParts {
            workspace: &prepared.workspace,
            preparation_guard: prepared.binding_guard.take(),
            agent_controls: Vec::new(),
            max_model_steps: Self::CHILD_MODEL_STEP_LIMIT,
            id: id.to_owned(),
            parent_id: thread.parent_thread_id,
            route,
            model,
            current: Some(current),
            initial_context: Vec::new(),
            initial_extensions,
            store: resources,
            workspace_usage: Some(workspace_usage),
            persistence,
        });
        Self::configure_review_finish(&mut prepared.tools, id, &profile, &assignment)?;
        if let Some(check) = review_check {
            check
                .confirm()
                .await
                .map_err(|error| resource_error("recheck restored review workspace", error))?;
        }
        if let Some(lease) = verified_lease {
            self.confirm_native_worktree(
                &lease,
                spec.workspace_usage
                    .as_ref()
                    .expect("child preparation use"),
                &request.workspace_owner,
                "confirm restored child worktree binding",
            )
            .await?;
        }
        Ok(prepared.tools.install(spec))
    }

    /// Verifies and reuses the original child site; missing or cleaned sites are never rebuilt.
    async fn ensure_restored_child_worktree(
        &self,
        receipt: &crate::AgentWorktreeSnapshot,
        thread: &crate::studio::ThreadRecord,
        project: &crate::studio::WorkspaceRecord,
    ) -> Result<crate::studio::worktree::worktree_lease::WorktreeLease, ThreadAssemblyError> {
        let child_id = &thread.id;
        let missing = |reason: &str| ThreadAssemblyError::Workspace {
            thread_id: child_id.clone(),
            reason: reason.to_owned(),
        };
        // Resolve through the current Project before accepting the saved lease and receipt.
        let (repository_root, project_endpoint) = self.restored_child_repository(project).await?;
        let lease = self.services.worktrees.get(child_id).ok_or_else(|| {
            missing(
                "the saved child worktree has no session lease; a normal continuation does not create one",
            )
        })?;
        // A site whose cleanup is in flight is not a reusable site: the directory is about to be
        // removed, so presenting it as the child's workspace would hand out a path that disappears
        // underneath the owner.
        if matches!(
            lease.state,
            crate::studio::worktree::worktree_lease::WorktreeLeaseState::CleanupRequested
                | crate::studio::worktree::worktree_lease::WorktreeLeaseState::Cleaned
        ) {
            return Err(missing(
                "the saved child worktree is cleaned or cleanup is in progress",
            ));
        }
        // The saved site is only ever touched at the managed path its stable ownership
        // derives, and only while it still matches this child, its root, its project and its receipt.
        lease
            .validate_identity()
            .map_err(|error| workspace_error("validate restored child worktree lease", error))?;
        verify_worktree_declarations(&lease, receipt, thread, project, &repository_root).map_err(
            |error| workspace_error("validate restored child worktree declarations", error),
        )?;
        let manager = crate::studio::worktree::workspace_preparation::manager_from_lease(
            &self.services.store,
            &self.services.ssh_manager,
            &lease,
            Some(&project_endpoint),
        )
        .await
        .map_err(|error| workspace_error("open restored child workspace manager", error))?;
        let handle = crate::agent::worktree::WorktreeHandle {
            path: PathBuf::from(&lease.path),
            base_commit: lease.base_commit.clone(),
        };
        manager
            .verify(&handle)
            .await
            .map_err(|error| resource_error("inspect restored child workspace", error))?;
        Ok(lease)
    }

    /// The repository and endpoint the current Project resolves to.
    ///
    /// This is resolved through the Project's own backend, never from what a lease or its receipt
    /// claim, so every site check compares against the repository the user's project points at today.
    async fn restored_child_repository(
        &self,
        project: &crate::studio::WorkspaceRecord,
    ) -> Result<
        (
            PathBuf,
            crate::studio::worktree::worktree_lease::WorkspaceEndpoint,
        ),
        ThreadAssemblyError,
    > {
        let project_root =
            crate::studio::worktree::workspace_preparation::resolved_project_root(project)
                .map_err(|error| workspace_error("resolve restored child project root", error))?;
        crate::studio::worktree::workspace_preparation::project_repository(
            &self.services.ssh_manager,
            project.ssh_alias.as_deref(),
            &project_root,
        )
        .await
        .map_err(|error| workspace_error("resolve restored child repository", error))
    }
}
