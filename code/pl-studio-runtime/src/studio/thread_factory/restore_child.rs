//! Cold child activation restores saved facts and opens fresh services; a `worktree` child whose
//! saved receipt has no physical worktree (or whose lease was cleaned by an archive) is recreated
//! at the same deterministic path instead of reusing the missing location.
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
        let assignment: pl_protocol::AgentWorkspaceAssignmentSnapshot =
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
        let history = self
            .services
            .store
            .history_for(&thread.project_id, id)
            .await
            .map_err(|error| resource_error("open child instruction migration writer", error))?;
        let checkpoint = history
            .migrate_recovery_checkpoint(&checkpoint, |state| {
                crate::instruction::migrate_saved_representation(state, &saved_identity)
            })
            .await
            .map_err(|error| resource_error("migrate saved child instructions", error))?;
        // 迁移后的快照是后续读取与持久化的唯一来源。
        let restored = checkpoint.state.clone();
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
            Ok::<_, crate::PureError>((project_root, session_root))
        })
        .await??;
        if std::path::Path::new(&assignment.project_root) != root {
            return Err(ThreadAssemblyError::Identity(
                "saved child workspace has a different project root".into(),
            ));
        }
        match assignment.mode {
            pl_protocol::AgentWorkspaceMode::Unrestricted
            | pl_protocol::AgentWorkspaceMode::Directory
                if std::path::Path::new(&assignment.root) == session_root
                    && assignment.worktree.is_none() => {}
            pl_protocol::AgentWorkspaceMode::Review => {
                self.ensure_restored_review_workspace(&assignment, &thread, &session_root)
                    .await?;
            }
            pl_protocol::AgentWorkspaceMode::Worktree => {
                let receipt = assignment
                    .worktree
                    .as_ref()
                    .filter(|receipt| receipt.path == assignment.root)
                    .ok_or_else(|| {
                        ThreadAssemblyError::Identity("invalid saved worktree receipt".into())
                    })?;
                self.ensure_restored_child_worktree(receipt, &thread, &project)
                    .await?;
            }
            pl_protocol::AgentWorkspaceMode::Unrestricted
            | pl_protocol::AgentWorkspaceMode::Directory => {
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

        let resources = FileResourceStore::new(
            self.services
                .store
                .session_resources_dir_for(&thread.project_id, id)
                .map_err(|error| {
                    resource_error("resolve restored child session resources", error)
                })?,
        );
        let mut prepared = self
            .prepare_thread_tools(ThreadToolAssembly {
                thread_id: id,
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
        let initial_extensions = BTreeMap::new();
        let model = pl_model::runtime::ThreadModel::new(
            pl_model::runtime::ModelRuntime::from_route(&route)?,
            route.reasoning_config(),
        )
        .with_hosted_tools(prepared.hosted);
        let spec = StudioThreadSpec {
            preparation_guard: prepared.binding_guard.take(),
            context_preparation: crate::compaction::preparer(
                &route,
                model.clone(),
                config.runtime.openai_compaction_mode,
                self.services.thread_modes.clone(),
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
    }

    /// 校验 review child 的被审目标工作区仍与冻结收据一致；reviewer 不拥有 lease，
    /// 因此从不代为重建被审者的工作树，目标缺失或已清理时类型化失败。
    async fn ensure_restored_review_workspace(
        &self,
        assignment: &pl_protocol::AgentWorkspaceAssignmentSnapshot,
        thread: &crate::studio::ThreadRecord,
        session_root: &std::path::Path,
    ) -> Result<(), ThreadAssemblyError> {
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
                let lease = self
                    .services
                    .worktrees
                    .get(target_id)
                    .filter(|lease| {
                        lease.owner_kind == WorktreeLeaseOwnerKind::Child
                            && lease.root_thread_id == thread.root_thread_id
                            && lease.path == expected.path
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
                if !matches!(manager.preview_existing(&handle).await, Ok(Some(_))) {
                    return Err(ThreadAssemblyError::Identity(format!(
                        "review target {target_id} worktree is missing"
                    )));
                }
            }
            None => {
                if std::path::Path::new(&assignment.root) != session_root {
                    return Err(ThreadAssemblyError::Identity(
                        "review workspace root does not match the session workspace".into(),
                    ));
                }
            }
        }
        Ok(())
    }

    /// 保存的 worktree receipt 对应物理工作树缺失、或 lease 已被归档清理时，在同一确定性
    /// 路径重建工作树并记录 renewed 的 `prepared` lease；已有可用现场时保持不变。
    async fn ensure_restored_child_worktree(
        &self,
        receipt: &pl_protocol::AgentWorktreeSnapshot,
        thread: &crate::studio::ThreadRecord,
        project: &crate::studio::ProjectRecord,
    ) -> Result<(), ThreadAssemblyError> {
        use crate::studio::agent_host::worktree_lease::WorktreeLeaseState;
        let child_id = &thread.id;
        let recreate = match self.services.worktrees.get(child_id) {
            None => true,
            Some(lease) if lease.state == WorktreeLeaseState::Cleaned => true,
            Some(lease) => {
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
                matches!(manager.preview_existing(&handle).await, Ok(None))
            }
        };
        if !recreate {
            return Ok(());
        }
        let _creating = self.services.worktrees.creation_guard(child_id);
        crate::studio::agent_host::workspace_preparation::recreate_child_worktree(
            &self.services.worktrees,
            &self.services.ssh_manager,
            project,
            &thread.root_thread_id,
            child_id,
            receipt,
        )
        .await
        .map_err(|error| resource_error("recreate restored child worktree", error))?;
        Ok(())
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
