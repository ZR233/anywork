//! Cold child activation restores saved facts and opens fresh services.
//!
//! A `worktree` child whose saved receipt has no physical worktree is **not** silently rebuilt: a
//! missing directory is a broken site and fails with a typed `Workspace` error that the activation
//! path publishes as a Recovery diagnosis. Ordinary activation never recreates the saved site.
use super::workspace_validation::{same_workspace_path, verify_worktree_declarations};
use super::{StudioThreadFactory, errors::resource_error, thread_tools::ThreadToolAssembly};
use crate::{
    agent::definition::VerifiedAgentIdentity,
    resource_store::FileResourceStore,
    thread_assembler::{StudioThreadSpec, ThreadAssemblyError, ThreadPreparation},
};
use pl_core::context::{OpaquePayload, ResourceAccess};
use pl_model::config::AgentRoleId;
use pl_tool::workspace::ToolWorkspace;
use std::{collections::BTreeMap, path::PathBuf};

impl StudioThreadFactory {
    pub(super) async fn prepare_restored_child(
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
        self.verify_saved_bot_execution_workspace(&protocol_thread, None)
            .await?;
        self.verify_execution_workspace(
            &protocol_thread,
            None,
            super::ExecutionWorkspaceCheck::Prepare,
        )
        .await
        .map_err(Self::workspace_usage_error)?;
        let mut current =
            super::recovery::load_current_for_recovery(&self.services.store, &protocol_thread)
                .await
                .map_err(|error| resource_error("load Thread current", error))?
                .ok_or_else(|| {
                    ThreadAssemblyError::Identity(format!("child {id} has no saved current"))
                })?;
        // Core Closed belongs to the previous owner (including graceful host shutdown).
        // Only Studio's durable explicit-close intent prohibits a new execution incarnation.
        let restored = current.state.to_paused_snapshot();
        if crate::studio::agent_close::is_explicitly_closed(&restored)
            .map_err(|error| resource_error("read child close intent", error))?
        {
            self.project_child_close(&protocol_thread, &restored)
                .await?;
            return Err(ThreadAssemblyError::Closed);
        }
        let mut project = self.project_record(&thread.workspace_id).await?;
        let workspace_usage = self
            .reserve_thread_workspace_use(id, &thread.root_thread_id, &project)
            .await
            .map_err(Self::workspace_usage_error)?;
        request.workspace_owner.retain(&workspace_usage);
        let bot_root = self
            .bind_bot_project(
                id,
                &thread.root_thread_id,
                &mut project,
                &workspace_usage,
                super::root_resources::BotWorkspacePreparation::Existing,
            )
            .await?;
        let saved = restored
            .extensions
            .get(crate::studio::workspace_receipt::EXTENSION)
            .ok_or_else(|| {
                ThreadAssemblyError::Identity(format!("child {id} has no workspace receipt"))
            })?;
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
        let mut migrated = current.state.to_paused_snapshot();
        crate::instruction::migrate_saved_representation(&mut migrated, &saved_identity)
            .map_err(|error| resource_error("migrate saved child instructions", error))?;
        crate::plan_tool::migrate_saved_plan(&mut migrated)
            .map_err(|error| resource_error("migrate saved child plan", error))?;
        current.state.extensions = migrated.extensions;
        current.state.extension_sequence = migrated.extension_sequence;
        let restored = current.state.to_paused_snapshot();
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
        let saved_project = restored.extensions.get("studio.project").ok_or_else(|| {
            ThreadAssemblyError::Identity(format!("child {id} has no project binding"))
        })?;
        let previous: crate::studio::WorkspaceRecord =
            decode(&saved_project.payload, "pl.studio.project")?;
        if previous.id != project.id
            || previous.kind != project.kind
            || previous.path != project.path
            || previous.ssh_alias != project.ssh_alias
        {
            return Err(ThreadAssemblyError::Identity(
                "child project target changed".into(),
            ));
        }
        // Resolve the actual root once. Existing child worktrees keep their original receipt;
        // this boundary neither selects a new HEAD nor rebuilds the session checkout.
        let workspace_mode = thread.workspace_mode;
        let root_thread = self.directory_member(&thread.root_thread_id)?;
        if root_thread.session.workspace_mode != workspace_mode {
            return Err(ThreadAssemblyError::Identity(
                "saved child root workspace mode changed".into(),
            ));
        }
        let local_root = bot_root
            .clone()
            .unwrap_or_else(|| PathBuf::from(&root_thread.session.workspace_path));
        let project_copy = project.clone();
        let root = tokio::task::spawn_blocking(move || {
            Ok::<_, anyhow::Error>(match bot_root {
                Some(root) => root,
                None => crate::studio::agent_host::workspace_preparation::resolved_project_root(
                    &project_copy,
                )?,
            })
        })
        .await?
        .map_err(|error| resource_error("resolve restored session workspace", error))?;
        let session_root =
            crate::studio::agent_host::workspace_preparation::root_session_workspace_root(
                &self.services.store,
                &self.services.worktrees,
                &self.services.ssh_manager,
                &root_thread,
                &project,
                local_root,
            )
            .await
            .map_err(|error| resource_error("resolve restored root session workspace", error))?
            .0;
        if std::path::Path::new(&assignment.project_root) != root {
            return Err(ThreadAssemblyError::Identity(
                "saved child workspace has a different project root".into(),
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
                    .ok_or_else(|| {
                        ThreadAssemblyError::Identity("invalid saved worktree receipt".into())
                    })?;
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
                    return Err(ThreadAssemblyError::Identity(
                        "the verified child worktree is not the saved workspace assignment root"
                            .into(),
                    ));
                }
                verified_lease = Some(verified);
            }
            crate::AgentWorkspaceMode::Unrestricted | crate::AgentWorkspaceMode::Directory => {
                return Err(ThreadAssemblyError::Identity(
                    "invalid saved child workspace assignment".into(),
                ));
            }
        }
        if profile.workspace_mode != assignment.mode {
            return Err(ThreadAssemblyError::Identity(
                "saved child Profile conflicts with its workspace assignment".into(),
            ));
        }
        let workspace = super::child_resources::assigned_workspace(&assignment, workspace_mode);
        self.assign_workspace_use(&workspace_usage, &project, workspace.root())
            .await
            .map_err(Self::workspace_usage_error)?;

        let resources = FileResourceStore::new(
            self.services
                .store
                .session_resources_dir_for(&thread.workspace_id, id)
                .map_err(|error| {
                    resource_error("resolve restored child session resources", error)
                })?,
        );
        let mut prepared = self
            .prepare_thread_tools(
                ThreadToolAssembly {
                    workspace_usage: workspace_usage.clone(),
                    thread_id: id,
                    cancellation: &request.cancellation,
                    config: &config,
                    route: &route,
                    project: &project,
                    root_thread_id: &thread.root_thread_id,
                    workspace: ToolWorkspace::new(workspace)
                        .with_lsp_runtime(Some(self.services.lsp_runtime.clone())),
                    store: resources.clone(),
                },
                Some(&assignment),
            )
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
        let persistence = crate::studio::storage::thread_writer::ThreadStorageSink::new(
            self.services.store.clone(),
            protocol_thread,
        )
        .await
        .map_err(|error| resource_error("open restored child persistence", error))?;
        let initial_extensions = BTreeMap::new();
        let model = model_available
            .then(|| {
                crate::studio::model_binding::configured_model(
                    &route,
                    &config,
                    self.services.thread_modes.clone(),
                    prepared.hosted,
                )
            })
            .transpose()
            .map_err(|error| resource_error("prepare Native model binding", error))?;
        let spec = StudioThreadSpec {
            workspace_usage: Some(workspace_usage),
            preparation_guard: prepared.binding_guard.take(),
            agent_controls: Vec::new(),
            execution: pl_core::thread::input::InputDriverOptions {
                max_model_steps: Self::CHILD_MODEL_STEP_LIMIT,
            },
            id: id.to_owned(),
            parent_id: thread.parent_thread_id,
            route,
            model,
            current: Some(current),
            initial_context: Vec::new(),
            initial_runtime_facts: super::session_files::session_files_fact(&prepared.workspace)
                .into_iter()
                .collect(),
            initial_extensions,
            tools: Vec::new(),
            resources: ResourceAccess::new(resources),
            capacity: Default::default(),
            history_sink: Some(persistence),
        };
        Self::configure_review_finish(&mut prepared.tools, id, &profile, &assignment)?;
        if let Some(check) = review_check {
            check
                .confirm()
                .await
                .map_err(|error| resource_error("recheck restored review workspace", error))?;
        }
        if let Some(lease) = verified_lease {
            self.confirm_worktree_binding(
                &lease,
                spec.workspace_usage
                    .as_ref()
                    .expect("child preparation use"),
                &request.workspace_owner,
            )
            .await
            .map_err(|error| resource_error("confirm restored child worktree binding", error))?;
        }
        Ok(prepared.tools.install(spec))
    }

    /// Verifies and reuses the original child site; missing or cleaned sites are never rebuilt.
    async fn ensure_restored_child_worktree(
        &self,
        receipt: &crate::AgentWorktreeSnapshot,
        thread: &crate::studio::ThreadRecord,
        project: &crate::studio::WorkspaceRecord,
    ) -> Result<crate::studio::agent_host::worktree_lease::WorktreeLease, ThreadAssemblyError> {
        let child_id = &thread.id;
        let missing = |reason: &str| ThreadAssemblyError::Workspace {
            thread_id: child_id.clone(),
            reason: reason.to_owned(),
        };
        // Resolve through the current Project before accepting the saved lease and receipt.
        let (repository_root, _repository) = self.restored_child_repository(project).await?;
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
            crate::studio::agent_host::worktree_lease::WorktreeLeaseState::CleanupRequested
                | crate::studio::agent_host::worktree_lease::WorktreeLeaseState::Cleaned
        ) {
            return Err(missing(
                "the saved child worktree is cleaned or cleanup is in progress",
            ));
        }
        // The saved site is only ever touched at the managed path its stable ownership
        // derives, and only while it still matches this child, its root, its project and its receipt.
        lease
            .validate_identity()
            .map_err(|error| resource_error("validate restored child worktree lease", error))?;
        verify_worktree_declarations(&lease, receipt, thread, project, &repository_root).map_err(
            |error| resource_error("validate restored child worktree declarations", error),
        )?;
        let manager = crate::studio::agent_host::workspace_preparation::manager_from_lease(
            &self.services.store,
            &self.services.ssh_manager,
            &lease,
        )
        .await
        .map_err(|error| resource_error("open restored child workspace manager", error))?;
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

    /// The repository the current Project really resolves to, plus a manager anchored on it.
    ///
    /// This is resolved through the Project's own backend, never from what a lease or its receipt
    /// claim, so every site check compares against the repository the user's project points at today.
    async fn restored_child_repository(
        &self,
        project: &crate::studio::WorkspaceRecord,
    ) -> Result<(PathBuf, crate::agent::worktree::WorktreeManager), ThreadAssemblyError> {
        let project_root =
            crate::studio::agent_host::workspace_preparation::resolved_project_root(project)
                .map_err(|error| resource_error("resolve restored child project root", error))?;
        crate::studio::agent_host::workspace_preparation::repository_manager(
            &self.services.ssh_manager,
            project.ssh_alias.as_deref(),
            &project_root,
        )
        .await
        .map(|(repository, manager, _)| (repository, manager))
        .map_err(|error| resource_error("resolve restored child repository", error))
    }
}

fn decode<T: serde::de::DeserializeOwned>(
    payload: &OpaquePayload,
    format: &str,
) -> Result<T, ThreadAssemblyError> {
    if payload.format() != format || payload.version() != 1 {
        return Err(ThreadAssemblyError::Identity(format!(
            "unsupported saved binding {} version {}",
            payload.format(),
            payload.version()
        )));
    }
    serde_json::from_str(payload.content())
        .map_err(|error| resource_error("decode saved workspace binding", error))
}
