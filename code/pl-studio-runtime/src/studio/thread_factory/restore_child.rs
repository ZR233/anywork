//! Cold child activation restores saved facts and opens fresh services.
//!
//! A `worktree` child whose saved receipt has no physical worktree is **not** silently rebuilt: a
//! missing directory is a broken site and fails with a typed `Workspace` error that the activation
//! path publishes as a Recovery diagnosis. Ordinary activation never recreates the saved site.
use super::{StudioThreadFactory, errors::resource_error, thread_tools::ThreadToolAssembly};
use crate::{
    agent::definition::VerifiedAgentIdentity,
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
        let preparation_id = request.identity.id.clone();
        let preparation_cancellation = request.cancellation.clone();
        self.with_prepared_lifetime(&preparation_id, &preparation_cancellation, |lifetime| async move {
        let id = &request.identity.id;
        let thread = self.thread_record(id).await?;
        if thread.parent_thread_id != request.identity.parent_id
            || thread.parent_thread_id.is_none()
        {
            return Err(ThreadAssemblyError::Identity(id.clone()));
        }
        if thread.visibility != crate::studio::ThreadVisibility::Active {
            return Err(ThreadAssemblyError::Closed);
        }
        if thread.role == crate::config::ROOT_AGENT_ROUTE_KEY {
            return Err(ThreadAssemblyError::Identity(
                "child role is retired: planner".into(),
            ));
        }
        let protocol_thread: pl_protocol::Thread = thread.clone().into();
        let checkpoint =
            super::recovery::load_checkpoint_for_recovery(&self.services.store, &protocol_thread)
                .await
                .map_err(|error| resource_error("load Thread checkpoint", error))?
                .ok_or_else(|| {
                    ThreadAssemblyError::Identity(format!("child {id} has no saved checkpoint"))
                })?;
        // Core Closed belongs to the previous owner (including graceful host shutdown).
        // Only Studio's durable explicit-close intent prohibits a new execution incarnation.
        if crate::studio::agent_close::is_explicitly_closed(&checkpoint.state)
            .map_err(|error| resource_error("read child close intent", error))?
        {
            self.project_child_close(&protocol_thread, &checkpoint.state)
                .await?;
            return Err(ThreadAssemblyError::Closed);
        }
        let mut project = self.project_record(&thread.project_id).await?;
        let bot_root = self
            .bind_bot_project(id, &thread.root_thread_id, &mut project)
            .await?;
        let restored = checkpoint.state.clone();
        let saved = restored
            .extensions
            .get(crate::studio::workspace_receipt::EXTENSION)
            .ok_or_else(|| {
                ThreadAssemblyError::Identity(format!("child {id} has no workspace receipt"))
            })?;
        let mut assignment: pl_protocol::AgentWorkspaceAssignmentSnapshot =
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
        super::history_preparation::validate_current_instructions(
            &checkpoint.state,
            &saved_identity,
        )
        .map_err(|error| resource_error("validate saved child instructions", error))?;
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
        let previous: crate::studio::ProjectRecord =
            decode(&saved_project.payload, "pl.studio.project")?;
        if previous.id != project.id
            || previous.path != project.path
            || previous.ssh_alias != project.ssh_alias
        {
            return Err(ThreadAssemblyError::Identity(
                "child project target changed".into(),
            ));
        }
        // 非 worktree child 的工作区根跟随其根会话；`worktree` child 仍以 Project 仓库
        // `HEAD` 为 base。
        let workspace_mode = thread.workspace_mode;
        let root_thread_id = thread.root_thread_id.clone();
        let project_copy = project.clone();
        let frozen_assignment = assignment.clone();
        let worktrees = self.services.worktrees.clone();
        let (root, session_root) = tokio::task::spawn_blocking(move || {
            let project_root = match bot_root {
                Some(root) => root,
                None => crate::studio::agent_host::workspace_preparation::resolved_project_root(
                    &project_copy,
                )?,
            };
            let session_root =
                crate::studio::agent_host::workspace_preparation::root_session_workspace_root(
                    &worktrees,
                    workspace_mode,
                    &root_thread_id,
                    project_root.clone(),
                )?;
            validate_frozen_write_scope(&frozen_assignment, project_copy.ssh_alias.is_some())?;
            Ok::<_, ThreadAssemblyError>((project_root, session_root))
        })
        .await??;
        if workspace_mode == pl_protocol::ThreadWorkspaceMode::Worktree {
            crate::studio::agent_host::workspace_preparation::verify_root_session_worktree(
                &self.services.worktrees,
                &self.services.ssh_manager,
                &project,
                &thread.root_thread_id,
            )
            .await
            .map_err(|error| resource_error("verify restored root session workspace", error))?;
        }
        if profile.workspace_mode != assignment.mode {
            return Err(ThreadAssemblyError::Identity(
                "saved child Profile conflicts with its workspace assignment".into(),
            ));
        }
        let normalize_project_root = std::path::Path::new(&assignment.project_root) != root;
        let mut proven_repository = None;
        match assignment.mode {
            pl_protocol::AgentWorkspaceMode::Unrestricted
            | pl_protocol::AgentWorkspaceMode::Directory
                if std::path::Path::new(&assignment.root) == session_root
                    && assignment.worktree.is_none() => {
                if normalize_project_root && workspace_mode == pl_protocol::ThreadWorkspaceMode::Worktree {
                    let lease = self
                        .prove_restored_session_workspace(&thread, &project, &session_root)
                    .await?;
                    proven_repository = Some(lease.repository_root);
            }
            }
            pl_protocol::AgentWorkspaceMode::Review => {
                let lease = self.ensure_restored_review_workspace(&assignment, &thread, &project, &session_root)
                    .await?;
                if normalize_project_root {
                    if let Some(lease) = lease {
                        proven_repository = Some(lease.repository_root);
                    } else if workspace_mode == pl_protocol::ThreadWorkspaceMode::Worktree {
                        let lease = self
                            .prove_restored_session_workspace(&thread, &project, &session_root)
                            .await?;
                        proven_repository = Some(lease.repository_root);
                    }
                }
            }
            pl_protocol::AgentWorkspaceMode::Worktree => {
                let receipt = assignment
                    .worktree
                    .as_ref()
                    .filter(|receipt| receipt.path == assignment.root)
                    .ok_or_else(|| {
                        ThreadAssemblyError::Identity("invalid saved worktree receipt".into())
                    })?;
                let verified = if normalize_project_root {
                    // A redundant legacy field cannot authorize worktree recreation. First
                    // prove the original receipt against the existing lease and physical W.
                    self.validate_child_close(&protocol_thread, &restored)?;
                    let lease = self.services.worktrees.get(id).filter(|lease| lease.ssh_alias == project.ssh_alias).ok_or_else(|| {
                        ThreadAssemblyError::Identity("saved worktree has no ownership lease".into())
                    })?;
                    self.prove_existing_worktree(&lease, &project).await?;
                    proven_repository = Some(lease.repository_root.clone());
                    lease
                } else {
                self.ensure_restored_child_worktree(receipt, &thread, &project)
                        .await?
                };
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
            }
            pl_protocol::AgentWorkspaceMode::Unrestricted
            | pl_protocol::AgentWorkspaceMode::Directory => {
                return Err(ThreadAssemblyError::Identity(
                    "saved local child execution root differs from the canonical session root; preserve its files and receipt, handle the old workspace locally, then spawn a new child".into(),
                ));
            }
        }
        self.validate_child_close(&protocol_thread, &restored)?;
        if normalize_project_root {
            let old_repository = proven_repository.filter(|repository| {
                project.ssh_alias.is_none()
                    && std::path::Path::new(repository) == std::path::Path::new(&assignment.project_root)
            });
            if old_repository.is_none() {
            return Err(ThreadAssemblyError::Identity(
                    "saved child Project root cannot be normalized without changing its proven workspace; preserve its receipt and handle recovery locally before respawning".into(),
            ));
        }
            // Only redundant metadata changes: root, scope, receipt and lease identities stay
            // frozen. Persist this at the existing restore boundary before publishing tools.
            assignment.project_root = root.to_string_lossy().into_owned();
        }
        let workspace = super::child_resources::assigned_workspace(&assignment, workspace_mode);

        let resources = self.services.store.thread_resources_for(&thread.project_id, id).await
            .map_err(|error| resource_error("resolve restored child session resource owner", error))?;
        let prepared = self
            .prepare_thread_tools(ThreadToolAssembly {
                thread_id: id,
                lifetime: lifetime.clone(),
                cancellation: &request.cancellation,
                config: &config,
                route: &route,
                project: &project,
                root_thread_id: &thread.root_thread_id,
                workspace: ToolWorkspace::new(workspace)
                    .with_lsp_runtime(Some(self.services.lsp_runtime.clone())),
                store: resources.clone(),
                helper_source: self.services.helper_source.clone(),
            })
            .await?;
        if request.cancellation.is_cancelled() {
            return Err(ThreadAssemblyError::Closed);
        }
        let persistence = crate::studio::storage::thread_writer::ThreadStorageSink::new(
            self.services.store.clone(),
            protocol_thread,
            Some(&checkpoint),
        )
        .await
        .map_err(|error| resource_error("open restored child persistence", error))?;
        let mut initial_extensions = BTreeMap::new();
        if normalize_project_root {
            initial_extensions.insert(
                crate::studio::workspace_receipt::EXTENSION.into(),
                crate::studio::workspace_receipt::to_payload(&assignment)
                    .map_err(|error| resource_error("normalize saved child Project root", error))?,
            );
        }
        let model = pl_model::runtime::ThreadModel::new(
            pl_model::runtime::ModelRuntime::from_route(&route)?,
            route.reasoning_config(),
        )
        .with_hosted_tools(prepared.hosted)
        .with_preparation_owner(lifetime.preparation.clone())
        .with_user_files(self.user_file_access());
        let spec = StudioThreadSpec {
            preparation_guard: None,
            context_preparation: crate::compaction::preparer(
                &route,
                model.clone(),
                config.runtime.openai_compaction_mode,
                self.services.thread_modes.clone(),
                self.clone(),
            )?,
            agent_controls: Vec::new(),
            execution: pl_core::thread::input::InputDriverOptions {
                max_model_steps: Self::CHILD_MODEL_STEP_LIMIT,
            },
            id: id.clone(),
            parent_id: thread.parent_thread_id,
            route,
            model_available,
            model,
            checkpoint: Some(checkpoint),
            initial_context: Vec::new(),
            initial_runtime_facts: super::session_files::session_files_fact(&prepared.workspace)
                .into_iter()
                .collect(),
            initial_extensions,
            tools: Vec::new(),
            resources: ResourceAccess::new(resources),
            capacity: Default::default(),
            cold_store: Some(pl_core::thread::cold::ColdStoreHandle::new(persistence)),
        };
        Ok(prepared.tools.install(spec))
        }).await
    }

    /// 校验 review child 的被审目标工作区仍与冻结收据一致；reviewer 不拥有 lease，
    /// 因此从不代为重建被审者的工作树，目标缺失或已清理时类型化失败。
    async fn ensure_restored_review_workspace(
        &self,
        assignment: &pl_protocol::AgentWorkspaceAssignmentSnapshot,
        thread: &crate::studio::ThreadRecord,
        project: &crate::studio::ProjectRecord,
        session_root: &std::path::Path,
    ) -> Result<Option<crate::studio::agent_host::worktree_lease::WorktreeLease>, ThreadAssemblyError>
    {
        use crate::studio::agent_host::worktree_lease::{
            WorktreeLeaseOwnerKind, WorktreeLeaseState,
        };
        let target_id = &assignment
            .review_target
            .as_ref()
            .ok_or_else(|| {
                ThreadAssemblyError::Identity(format!(
                    "child {} review workspace has no review target",
                    thread.id
                ))
            })?
            .agent_id;
        let target = self.thread_record(target_id).await?;
        if target.parent_thread_id != thread.parent_thread_id
            || target.root_thread_id != thread.root_thread_id
            || target.project_id != thread.project_id
        {
            return Err(ThreadAssemblyError::Identity(format!(
                "review target {target_id} is not a sibling of child {}",
                thread.id
            )));
        }
        match &assignment.worktree {
            Some(expected) => {
                // The reviewed directory is the one the assignment names, and it is bound to the same
                // facts a reused child site is bound to: the review child must not run anywhere the
                // target's own lease and receipt do not prove.
                let remote = project.ssh_alias.is_some();
                if !same_workspace_path(&assignment.root, &expected.path, remote) {
                    return Err(ThreadAssemblyError::Identity(format!(
                        "review workspace root is not the reviewed worktree of {target_id}"
                    )));
                }
                let lease = self
                    .services
                    .worktrees
                    .get(target_id)
                    .filter(|lease| {
                        lease.owner_kind == WorktreeLeaseOwnerKind::Child
                            && lease.owner_thread_id == target.id
                            && lease.root_thread_id == thread.root_thread_id
                            && lease.project_id == thread.project_id
                            && lease.ssh_alias == project.ssh_alias
                            && assignment.root == expected.path
                            && lease.repository_root == expected.repository_root
                            && lease.path == expected.path
                            && lease.branch == expected.branch
                            && lease.base_commit == expected.base_commit
                    })
                    .ok_or_else(|| {
                        ThreadAssemblyError::Identity(format!(
                            "review target {target_id} no longer owns the reviewed worktree"
                        ))
                    })?;
                if lease.state == WorktreeLeaseState::Cleaned {
                    return Err(ThreadAssemblyError::Identity(format!(
                        "review target {target_id} worktree was already cleaned"
                    )));
                }
                if lease.state == WorktreeLeaseState::CleanupRequested {
                    return Err(ThreadAssemblyError::Identity(format!(
                        "review target {target_id} worktree is being cleaned up"
                    )));
                }
                // A reviewer borrows only an active/preserved site; it cannot complete or adopt
                // the target's pending creation.
                if lease.state == WorktreeLeaseState::Prepared {
                    return Err(ThreadAssemblyError::Identity(format!(
                        "review target {target_id} worktree is still being prepared"
                    )));
                }
                let (repository_root, repository) = self.restored_child_repository(project).await?;
                lease
                    .validate_identity()
                    .map_err(|error| resource_error("validate reviewed worktree lease", error))?;
                verify_worktree_declarations(&lease, expected, &target, project, &repository_root)
                    .map_err(|reason| {
                        ThreadAssemblyError::Identity(format!(
                            "review target {target_id} worktree: {reason}"
                        ))
                    })?;
                let manager = crate::studio::agent_host::workspace_preparation::manager_from_lease(
                    &self.services.ssh_manager,
                    &lease,
                )
                .map_err(|error| resource_error("open reviewed workspace manager", error))?;
                let handle = crate::agent::worktree::WorktreeHandle {
                    path: PathBuf::from(&lease.path),
                    branch: lease.branch.clone(),
                    base_commit: lease.base_commit.clone(),
                };
                let Some(status) = manager
                    .preview_existing(&handle)
                    .await
                    .map_err(|error| resource_error("inspect reviewed workspace", error))?
                else {
                    return Err(ThreadAssemblyError::Identity(format!(
                        "review target {target_id} worktree is missing"
                    )));
                };
                if status.branch.as_deref() != Some(lease.branch.as_str()) {
                    return Err(ThreadAssemblyError::Identity(format!(
                        "review target {target_id} worktree is checked out on another branch"
                    )));
                }
                verify_worktree_site(
                    &repository,
                    &repository_root,
                    &lease.path,
                    &lease.branch,
                    remote,
                )
                .await
                .map_err(|reason| {
                    ThreadAssemblyError::Identity(format!(
                        "review target {target_id} worktree: {reason}"
                    ))
                })?;
                return Ok(Some(lease));
            }
            None => {
                if self.services.worktrees.get(target_id).is_some() {
                    return Err(ThreadAssemblyError::Identity(
                        "saved review receipt omits its target's worktree".into(),
                    ));
                }
                if std::path::Path::new(&assignment.root) != session_root {
                    return Err(ThreadAssemblyError::Identity(
                        "saved local review root differs from the canonical session workspace; preserve its files and receipt, handle it locally, then spawn a new reviewer".into(),
                    ));
                }
            }
        }
        Ok(None)
    }

    async fn prove_restored_session_workspace(
        &self,
        thread: &crate::studio::ThreadRecord,
        project: &crate::studio::ProjectRecord,
        session_root: &std::path::Path,
    ) -> Result<crate::studio::agent_host::worktree_lease::WorktreeLease, ThreadAssemblyError> {
        use crate::studio::agent_host::worktree_lease::WorktreeLeaseOwnerKind;
        let lease = self
            .services
            .worktrees
            .get(&thread.root_thread_id)
            .filter(|lease| {
                lease.owner_kind == WorktreeLeaseOwnerKind::Session
                    && lease.owner_thread_id == thread.root_thread_id
                    && lease.root_thread_id == thread.root_thread_id
                    && lease.project_id == thread.project_id
                    && lease.ssh_alias == project.ssh_alias
                    && std::path::Path::new(&lease.path) == session_root
            })
            .ok_or_else(|| {
                ThreadAssemblyError::Identity(
                    "saved child session workspace ownership cannot be proven".into(),
                )
            })?;
        self.prove_existing_worktree(&lease, project).await?;
        Ok(lease)
    }

    /// Proves an existing W without creating, changing or adopting a lease.
    async fn prove_existing_worktree(
        &self,
        lease: &crate::studio::agent_host::worktree_lease::WorktreeLease,
        project: &crate::studio::ProjectRecord,
    ) -> Result<(), ThreadAssemblyError> {
        use crate::studio::agent_host::worktree_lease::WorktreeLeaseState;
        if !matches!(
            lease.state,
            WorktreeLeaseState::Active | WorktreeLeaseState::Preserved
        ) {
            return Err(ThreadAssemblyError::Identity(
                "saved worktree is not an existing active or preserved workspace".into(),
            ));
        }
        lease
            .validate_identity()
            .map_err(|error| resource_error("validate existing saved workspace", error))?;
        let (repository_root, repository) = self.restored_child_repository(project).await?;
        let remote = project.ssh_alias.is_some();
        if lease.project_id != project.id
            || lease.ssh_alias != project.ssh_alias
            || !same_workspace_path(
                &lease.repository_root,
                &repository_root.to_string_lossy(),
                remote,
            )
        {
            return Err(ThreadAssemblyError::Identity(
                "saved worktree is not owned by the current Project repository and target".into(),
            ));
        }
        let manager = crate::studio::agent_host::workspace_preparation::manager_from_lease(
            &self.services.ssh_manager,
            lease,
        )
        .map_err(|error| resource_error("open saved workspace manager", error))?;
        let handle = crate::agent::worktree::WorktreeHandle {
            path: PathBuf::from(&lease.path),
            branch: lease.branch.clone(),
            base_commit: lease.base_commit.clone(),
        };
        let Some(status) = manager
            .preview_existing(&handle)
            .await
            .map_err(|error| resource_error("prove saved workspace still exists", error))?
        else {
            return Err(ThreadAssemblyError::Identity(
                "saved worktree is missing; Project metadata normalization cannot recreate it"
                    .into(),
            ));
        };
        if status.branch.as_deref() != Some(lease.branch.as_str()) {
            return Err(ThreadAssemblyError::Identity(
                "saved worktree is checked out on another branch".into(),
            ));
        }
        verify_worktree_site(
            &repository,
            &repository_root,
            &lease.path,
            &lease.branch,
            remote,
        )
        .await
        .map_err(ThreadAssemblyError::Identity)?;
        Ok(())
    }

    /// Verifies and reuses the original child site; missing or cleaned sites are never rebuilt.
    async fn ensure_restored_child_worktree(
        &self,
        receipt: &pl_protocol::AgentWorktreeSnapshot,
        thread: &crate::studio::ThreadRecord,
        project: &crate::studio::ProjectRecord,
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
        // The saved site is only ever touched at the Pure-owned path and branch its own identity
        // derives, and only while it still matches this child, its root, its project and its receipt.
        lease
            .validate_identity()
            .map_err(|error| resource_error("validate restored child worktree lease", error))?;
        verify_worktree_declarations(&lease, receipt, thread, project, &repository_root)
            .map_err(|reason| missing(&reason))?;
        let manager = crate::studio::agent_host::workspace_preparation::manager_from_lease(
            &self.services.ssh_manager,
            &lease,
        )
        .map_err(|error| resource_error("open restored child workspace manager", error))?;
        let handle = crate::agent::worktree::WorktreeHandle {
            path: PathBuf::from(&lease.path),
            branch: lease.branch.clone(),
            base_commit: lease.base_commit.clone(),
        };
        manager
            .preview(&handle)
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
        project: &crate::studio::ProjectRecord,
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
        .map_err(|error| resource_error("resolve restored child repository", error))
    }
}

/// Binds a lease and its frozen receipt to the child, its project and the resolved repository.
///
/// These are the facts that do not depend on the physical site: ownership, root session, project,
/// remote target, the repository the current Project resolves
/// to today, and the frozen receipt's repository, path, branch and base commit.
fn verify_worktree_declarations(
    lease: &crate::studio::agent_host::worktree_lease::WorktreeLease,
    receipt: &pl_protocol::AgentWorktreeSnapshot,
    owner: &crate::studio::ThreadRecord,
    project: &crate::studio::ProjectRecord,
    repository_root: &std::path::Path,
) -> Result<(), String> {
    use crate::studio::agent_host::worktree_lease::WorktreeLeaseOwnerKind;
    let remote = project.ssh_alias.is_some();
    if lease.owner_kind != WorktreeLeaseOwnerKind::Child || lease.owner_thread_id != owner.id {
        return Err("the saved worktree lease belongs to a different workspace owner".into());
    }
    if lease.root_thread_id != owner.root_thread_id {
        return Err("the saved worktree lease belongs to a different root session".into());
    }
    if lease.project_id != project.id {
        return Err("the saved worktree lease belongs to a different project".into());
    }
    // The remote target the lease runs on must be the one the Project names, or the site could be a
    // same-looking path on a different host.
    if lease.ssh_alias != project.ssh_alias {
        return Err("the saved worktree lease runs on a different remote target".into());
    }
    if !same_workspace_path(
        &lease.repository_root,
        &repository_root.to_string_lossy(),
        remote,
    ) {
        return Err("the saved worktree lease is outside this project's repository".into());
    }
    if !same_workspace_path(&lease.repository_root, &receipt.repository_root, remote) {
        return Err("the saved lease and its receipt name different repositories".into());
    }
    if !same_workspace_path(&lease.path, &receipt.path, remote) {
        return Err("the saved lease and its receipt name different worktree paths".into());
    }
    if lease.branch != receipt.branch {
        return Err("the saved lease and its receipt name different branches".into());
    }
    if lease.base_commit != receipt.base_commit {
        return Err(
            "the saved lease and its receipt were created from different base commits".into(),
        );
    }
    Ok(())
}

/// Proves that the directory at `path` is a worktree of the resolved repository, on `branch`.
///
/// Two Git facts are required: an existing directory or a stale registration alone proves nothing.
/// The owning repository must register the live site on that branch, and both directories must
/// resolve to the same common Git directory.
async fn verify_worktree_site(
    repository: &crate::agent::worktree::WorktreeManager,
    repository_root: &std::path::Path,
    path: &str,
    branch: &str,
    remote: bool,
) -> Result<(), String> {
    let registered = repository
        .registered_worktrees()
        .await
        .map_err(|error| format!("the project repository cannot list its worktrees: {error}"))?;
    let owned = registered.iter().any(|entry| {
        !entry.prunable
            && same_workspace_path(&entry.path, path, remote)
            && entry.branch.as_deref() == Some(branch)
    });
    if !owned {
        return Err(
            "the resolved repository does not register this directory as its worktree on the declared branch"
                .into(),
        );
    }
    let site = repository
        .git_common_dir(std::path::Path::new(path))
        .await
        .map_err(|error| format!("the saved worktree does not answer as a Git worktree: {error}"))?
        .ok_or_else(|| "the saved worktree's Git identity cannot be resolved".to_string())?;
    let owner = repository
        .git_common_dir(repository_root)
        .await
        .map_err(|error| format!("the project repository cannot name its Git directory: {error}"))?
        .ok_or_else(|| "the project repository's Git identity cannot be resolved".to_string())?;
    if site != owner {
        return Err("the saved worktree belongs to another Git repository".into());
    }
    Ok(())
}

/// Remote paths compare by their normalized text; local paths compare as paths.
fn same_workspace_path(left: &str, right: &str, remote: bool) -> bool {
    if remote {
        match (
            pl_tool::remote::normalize_remote_absolute_path(left),
            pl_tool::remote::normalize_remote_absolute_path(right),
        ) {
            (Ok(left), Ok(right)) => left == right,
            _ => false,
        }
    } else {
        std::path::Path::new(left) == std::path::Path::new(right)
    }
}

/// Uses the existing file-tool path policy; never rebases a frozen absolute write grant.
/// This runs inside the restore path's existing blocking metadata preparation.
fn validate_frozen_write_scope(
    assignment: &pl_protocol::AgentWorkspaceAssignmentSnapshot,
    remote: bool,
) -> Result<(), ThreadAssemblyError> {
    if assignment.mode != pl_protocol::AgentWorkspaceMode::Directory {
        if assignment.writable_paths.is_some() {
            return Err(ThreadAssemblyError::Identity(
                "saved non-directory child carries an invalid frozen write scope".into(),
            ));
        }
        return Ok(());
    }
    let Some(paths) = &assignment.writable_paths else {
        return Ok(());
    };
    if remote {
        // Remote scopes retain their existing POSIX/backend validation. The historical
        // enclosing-repository mistake and this metadata migration are local-only.
        return Ok(());
    }
    let policy = pl_tool::workspace::ToolPathPolicy::new(
        PathBuf::from(&assignment.root),
        false,
        "restore child write scope",
    )
    .map_err(|error| resource_error("resolve frozen child write scope", error))?;
    for path in paths {
        let invalid = || {
            ThreadAssemblyError::Identity(
            "saved absolute child writablePaths cannot be proven without remapping frozen permissions; preserve the receipt, handle the workspace locally, then spawn a new child".into(),
        )
        };
        if !std::path::Path::new(path).is_absolute() {
            return Err(invalid());
        }
        let resolved = policy.resolve_for_write(path).map_err(|error| {
            resource_error(
                "validate frozen child writablePaths; preserve receipt and recover locally",
                error,
            )
        })?;
        if resolved != std::path::Path::new(path) {
            return Err(invalid());
        }
    }
    Ok(())
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
