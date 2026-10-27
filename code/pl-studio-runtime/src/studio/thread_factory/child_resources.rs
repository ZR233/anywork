//! Physical child resources assembled from one resolved product configuration snapshot.
use super::StudioThreadFactory;
use super::errors::resource_error;
use crate::agent::definition::ResolvedAgentDefinition;
use crate::resource_store::FileResourceStore;
use crate::studio::ThreadRecord;
use crate::thread_assembler::{
    ChildThreadRequest, StudioChildResources, StudioThreadSpec, ThreadAssemblyError,
};
use pl_core::context::{
    ContextContent, ContextRecord, ContextSource, OpaquePayload, ResourceAccess,
};
use pl_tool::workspace::{AgentWorkspace, ToolWorkspace};
use std::{collections::BTreeMap, path::PathBuf, sync::Arc};

impl StudioChildResources for StudioThreadFactory {
    async fn prepare(
        &self,
        request: &ChildThreadRequest,
        profile: &crate::config::ResolvedAgentProfile,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        check_cancelled(request)?;
        let parent = self
            .services
            .product_events
            .thread_snapshot(&request.caller)
            .map(ThreadRecord::from_directory_thread)
            .ok_or_else(|| ThreadAssemblyError::Identity(request.caller.clone()))?;
        let mut project = self
            .services
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.id == parent.project_id)
            .ok_or_else(|| ThreadAssemblyError::Identity(parent.project_id.clone()))?;
        let root_thread = self.thread_record(&parent.root_thread_id).await?;
        self.check_bot_spawn_workspace(request, profile, &root_thread)
            .await?;
        let workspace_usage = self
            .reserve_thread_workspace_use(&request.id, &parent.root_thread_id, &project)
            .await
            .map_err(Self::workspace_usage_error)?;
        request.workspace_owner.retain(&workspace_usage);
        let project_root = match self
            .bind_bot_project(
                &request.id,
                &parent.root_thread_id,
                &mut project,
                &workspace_usage,
                super::root_resources::BotWorkspacePreparation::New,
            )
            .await?
        {
            Some(root) => root,
            None => {
                crate::studio::agent_host::workspace_preparation::resolved_project_root(&project)
                    .map_err(|error| resource_error("resolve child project root", error))?
            }
        };
        let session_root =
            crate::studio::agent_host::workspace_preparation::root_session_workspace_root(
                &self.services.worktrees,
                root_thread.workspace_mode,
                &parent.root_thread_id,
                project_root.clone(),
            )
            .map_err(|error| resource_error("resolve session workspace root", error))?;
        // child 的创建窗口与 root 会话一样由进程内 creating 标记保护：标记在记录 `prepared`
        // 之前设置，离开本函数（成功、失败、取消或展开）时由守卫清除。标记键是 child_id，
        // 不会影响会话路径的判定。
        let _creation = self.services.worktrees.creation_guard(&request.id);
        let review_target = match request.review_target_agent_id.as_deref() {
            None => None,
            Some(target_id) => Some(
                self.resolve_review_target(target_id, &request.caller, &parent, &project)
                    .await?,
            ),
        };
        let caller_workspace = if profile.profile.workspace_mode
            == pl_protocol::AgentWorkspaceMode::Worktree
        {
            let (actual, execution_project) = self.actual_tool_workspace(&request.caller)?;
            let identity = self
                .resolve_workspace_identity(&execution_project, actual.root())
                .await
                .map_err(Self::workspace_usage_error)?;
            let frozen = self
                .services
                .store
                .workspace_identity(&request.caller)
                .await
                .map_err(|error| resource_error("read caller physical execution binding", error))?
                .ok_or_else(|| {
                    ThreadAssemblyError::Identity(
                        "caller has no frozen physical execution binding".into(),
                    )
                })?;
            if identity != frozen {
                return Err(ThreadAssemblyError::Identity(
                    "caller actual execution workspace changed".into(),
                ));
            }
            Some(identity)
        } else {
            None
        };
        let caller_repository_root = caller_workspace.as_ref().and_then(|identity| {
            self.services
                .worktrees
                .get(&request.caller)
                .filter(|lease| {
                    lease.path == identity.root
                        && lease.project_id == project.id
                        && lease.root_thread_id == parent.root_thread_id
                })
                .map(|lease| PathBuf::from(lease.repository_root))
        });
        let (assignment, worktree) =
            crate::studio::agent_host::workspace_preparation::prepare_workspace(
                &self.services.worktrees,
                &self.services.ssh_manager,
                crate::studio::agent_host::workspace_preparation::WorkspacePreparation {
                    store: &self.services.store,
                    usage: &workspace_usage,
                    project: &project,
                    project_root,
                    root_thread_id: &parent.root_thread_id,
                    child_id: &request.id,
                    mode: profile.profile.workspace_mode,
                    writable_paths: request.writable_paths.clone(),
                    session_root,
                    caller_workspace,
                    caller_repository_root,
                    review_target,
                },
            )
            .await
            .map_err(|source| ThreadAssemblyError::ChildWorkspacePreparation { source })?;
        check_cancelled(request)?;
        let workspace =
            ToolWorkspace::new(assigned_workspace(&assignment, root_thread.workspace_mode))
                .with_lsp_runtime(Some(self.services.lsp_runtime.clone()));
        self.assign_workspace_use(&workspace_usage, &project, workspace.root())
            .await
            .map_err(Self::workspace_usage_error)?;
        let store = FileResourceStore::new(
            self.services
                .store
                .session_resources_dir_for(&parent.project_id, &request.id)
                .map_err(|error| resource_error("resolve child session resources", error))?,
        );
        let mut prepared_tools = self
            .prepare_thread_tools(super::thread_tools::ThreadToolAssembly {
                assignment: Some(&assignment),
                workspace_usage: workspace_usage.clone(),
                thread_id: &request.id,
                cancellation: &request.cancellation,
                config: &profile.config,
                route: &profile.route,
                project: &project,
                root_thread_id: &parent.root_thread_id,
                workspace,
                store: store.clone(),
                helper_source: self.services.helper_source.clone(),
            })
            .await?;
        check_cancelled(request)?;
        let workspace_payload = crate::studio::workspace_receipt::to_payload(&assignment)
            .map_err(|error| resource_error("encode child workspace receipt", error))?;
        let receipt = workspace_payload.content().to_owned();
        let agent = ResolvedAgentDefinition::from_profile(&profile.profile).map_err(|error| {
            ThreadAssemblyError::Identity(format!("invalid child Agent: {error}"))
        })?;
        let (mut initial_context, instruction_sources) =
            super::thread_seed::capture(super::thread_seed::ThreadInstructionSeed {
                thread_id: &request.id,
                config: &profile.config,
                model: &profile.route.model,
                root: std::path::Path::new(&assignment.root),
                agent: &agent,
                mode: None,
                delegation: None,
                resources: &prepared_tools,
            })
            .await?;
        initial_context.push(ContextRecord {
            id: format!("workspace:{}", request.id),
            turn_id: None,
            source: ContextSource::RuntimeFact {
                source_id: "studio.workspace".into(),
            },
            content: vec![ContextContent::Text {
                text: Arc::from(format!("Assigned workspace:\n{receipt}")),
            }],
            tool_calls: Vec::new(),
        });
        let initial_extensions = BTreeMap::from([
            (
                crate::studio::delegation::EXTENSION.into(),
                crate::studio::delegation::encode(request.delegation)
                    .map_err(|error| resource_error("freeze child delegation provenance", error))?,
            ),
            ("studio.instructions".into(), instruction_sources),
            (
                "studio.project".into(),
                OpaquePayload::new(
                    "pl.studio.project",
                    1,
                    serde_json::to_string(&project)
                        .map_err(|error| resource_error("encode child project binding", error))?,
                )
                .map_err(|error| resource_error("freeze child project binding", error))?,
            ),
            (
                crate::studio::workspace_receipt::EXTENSION.into(),
                workspace_payload,
            ),
            (
                crate::studio::model_route::AGENT_PROFILE_EXTENSION.into(),
                crate::studio::model_route::encode_profile(&profile.profile)
                    .map_err(|error| resource_error("freeze child Agent Profile", error))?,
            ),
            ("studio.creation-metadata".into(), request.metadata.clone()),
        ]);
        if let Some(worktree) = worktree {
            let mut lease = worktree.lease;
            lease.transition(crate::studio::agent_host::worktree_lease::WorktreeLeaseState::Active);
            self.services
                .worktrees
                .record_durable(lease)
                .await
                .map_err(|error| resource_error("activate workspace lease", error))?;
        }
        self.services
            .product_events
            .register_child_thread(crate::studio::store::directory::RegisteredChildThread {
                delegation: request.delegation,
                frozen_model: Some(crate::studio::delegation::profile_model(&profile.profile)),
                id: request.id.clone(),
                parent_thread_id: request.caller.clone(),
                root_thread_id: parent.root_thread_id,
                agent_path: request.id.clone(),
                project_id: parent.project_id,
                mode: parent.mode,
                workspace_mode: parent.workspace_mode,
                workspace_path: parent.workspace_path,
                role: profile.profile.profile_id.clone(),
                title: request.task_summary.as_str().to_owned(),
            })
            .await
            .map_err(|error| resource_error("register child product association", error))?;
        let persisted_thread = self
            .services
            .product_events
            .thread_snapshot(&request.id)
            .ok_or_else(|| ThreadAssemblyError::Identity(request.id.clone()))?;
        let persistence = crate::studio::storage::thread_writer::ThreadStorageSink::new(
            self.services.store.clone(),
            persisted_thread,
            None,
        )
        .await
        .map_err(|error| resource_error("open child chat session", error))?;
        let model = pl_model::runtime::ThreadModel::new(
            pl_model::runtime::ModelRuntime::from_route(&profile.route)?,
            profile.route.reasoning_config(),
        )
        .with_hosted_tools(prepared_tools.hosted);
        let spec = StudioThreadSpec {
            workspace_usage: Some(workspace_usage),
            preparation_guard: prepared_tools.binding_guard.take(),
            context_preparation: crate::compaction::preparer(
                &profile.route,
                model.clone(),
                profile.config.runtime.openai_compaction_mode,
                self.services.thread_modes.clone(),
            )?,
            agent_controls: Vec::new(),
            execution: pl_core::thread::input::InputDriverOptions {
                max_model_steps: Self::CHILD_MODEL_STEP_LIMIT,
            },
            id: request.id.clone(),
            parent_id: Some(request.caller.clone()),
            route: profile.route.clone(),
            model_available: true,
            model,
            checkpoint: None,
            tools: Vec::new(),
            initial_context,
            initial_runtime_facts: super::session_files::session_files_fact(
                &prepared_tools.workspace,
            )
            .into_iter()
            .collect(),
            initial_extensions,
            resources: ResourceAccess::new(store),
            capacity: Default::default(),
            cold_store: Some(pl_core::thread::cold::ColdStoreHandle::new(persistence)),
        };
        Ok(prepared_tools.tools.install(spec))
    }

    async fn close_published(
        &self,
        id: &str,
        disposition: pl_tool::collaboration::thread::WorkspaceRelease,
    ) -> Result<(), ThreadAssemblyError> {
        if self
            .services
            .store
            .agent_close(id)
            .await
            .map_err(|error| resource_error("read explicit retirement ownership", error))?
            .is_some()
        {
            // The explicit close job owns the precise lease revisions now. Ordinary host shutdown
            // only releases its Thread; it cannot mutate or consume this destructive grant.
            return Ok(());
        }
        let Some(lease) = self.services.worktrees.get(id) else {
            return Ok(());
        };
        // 会话自身 worktree 只由显式 Recovery 清理，不随 Thread 关闭删除。
        if lease.owner_kind
            != crate::studio::agent_host::worktree_lease::WorktreeLeaseOwnerKind::Child
        {
            return Ok(());
        }
        let manager = crate::studio::agent_host::workspace_preparation::manager_from_lease(
            &self.services.store,
            &self.services.ssh_manager,
            &lease,
        )
        .await
        .map_err(|error| resource_error("open published workspace manager", error))?;
        if disposition == pl_tool::collaboration::thread::WorkspaceRelease::Cleanup {
            self.prepare_workspace_cleanup(&lease)
                .await
                .map_err(|error| resource_error("check workspace cleanup uses", error))?;
        }
        crate::studio::agent_host::workspace_preparation::close_workspace(
            &self.services.store,
            &self.services.worktrees,
            &manager,
            lease,
            disposition,
        )
        .await
        .map_err(|error| resource_error("close published workspace", error))
    }

    async fn discard_unpublished(
        &self,
        id: &str,
        usage: Option<&crate::studio::WorkspaceUsageLease>,
    ) -> Result<(), ThreadAssemblyError> {
        self.discard_prepared_workspace(id, usage)
            .await
            .map_err(|error| resource_error("discard unpublished assigned resources", error))?;
        if self.services.product_events.thread_snapshot(id).is_some() {
            self.services
                .product_events
                .fault_unregistered_child(id, "child preparation was not published")
                .await
                .map_err(|error| resource_error("record abandoned child", error))?;
        }
        Ok(())
    }
}

/// Creation and cold restoration share the session boundary and directory policy.
pub(super) fn assigned_workspace(
    assignment: &pl_protocol::AgentWorkspaceAssignmentSnapshot,
    session_mode: pl_protocol::ThreadWorkspaceMode,
) -> AgentWorkspace {
    let writable_paths = if assignment.mode == pl_protocol::AgentWorkspaceMode::Directory {
        assignment
            .writable_paths
            .as_ref()
            .map(|paths| paths.iter().map(PathBuf::from).collect())
    } else {
        None
    };
    if assignment.mode == pl_protocol::AgentWorkspaceMode::Review {
        // 边界与被审代理一致：worktree 被审者 Confined 于其 worktree；共享会话 checkout 的
        // 被审者在 worktree 会话下同样 Confined，在 local 会话下 host-permitted。
        if assignment.worktree.is_some()
            || session_mode == pl_protocol::ThreadWorkspaceMode::Worktree
        {
            AgentWorkspace::worktree(&assignment.project_root, &assignment.root)
        } else {
            AgentWorkspace::host_permitted(&assignment.project_root, &assignment.root, None)
        }
    } else if session_mode == pl_protocol::ThreadWorkspaceMode::Worktree
        || assignment.mode == pl_protocol::AgentWorkspaceMode::Worktree
    {
        AgentWorkspace::worktree(&assignment.project_root, &assignment.root)
            .with_writable_paths(writable_paths)
    } else {
        AgentWorkspace::host_permitted(&assignment.project_root, &assignment.root, writable_paths)
    }
}

fn check_cancelled(request: &ChildThreadRequest) -> Result<(), ThreadAssemblyError> {
    if request.cancellation.is_cancelled() {
        Err(pl_core::thread::ThreadError::Cancelled.into())
    } else {
        Ok(())
    }
}

impl StudioThreadFactory {
    /// Resolves one reviewed agent's workspace facts for a `review` Profile spawn.
    ///
    /// 关系校验（调用者的直接 child、同一根会话与 Project）先行；worktree 被审者以 durable
    /// lease 为 canonical 事实并核对物理工作树仍存在；其他目标也只消费其实际冻结 assignment。
    /// review child 不获取、不转移被审者的 ownership lease。
    async fn resolve_review_target(
        &self,
        target_id: &str,
        caller: &str,
        parent: &crate::studio::ThreadRecord,
        project: &crate::studio::ProjectRecord,
    ) -> Result<
        crate::studio::agent_host::workspace_preparation::ReviewWorkspaceTarget,
        ThreadAssemblyError,
    > {
        use crate::studio::agent_host::worktree_lease::{
            WorktreeLeaseOwnerKind, WorktreeLeaseState,
        };
        self.services
            .store
            .ensure_agent_execution_allowed(target_id)
            .await
            .map_err(|error| resource_error("reject borrowing a retiring workspace", error))?;
        let invalid = || ThreadAssemblyError::ReviewTargetInvalid(target_id.to_owned());
        let target = self
            .services
            .product_events
            .thread_snapshot(target_id)
            .map(crate::studio::ThreadRecord::from_directory_thread)
            .ok_or_else(invalid)?;
        if target.parent_thread_id.as_deref() != Some(caller)
            || target.root_thread_id != parent.root_thread_id
            || target.project_id != project.id
        {
            return Err(invalid());
        }
        let protocol = pl_protocol::Thread::from(target.clone());
        let live = self
            .bindings
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(target_id)
            .cloned();
        let assignment = if let Some(binding) = &live {
            if binding.target_invalidated || binding.lifetime.cancellation.is_cancelled() {
                return Err(invalid());
            }
            binding.assignment.clone().ok_or_else(invalid)?
        } else {
            let checkpoint =
                super::recovery::load_checkpoint_read_only(&self.services.store, &protocol)
                    .await
                    .map_err(|error| {
                        resource_error("read reviewed actual workspace assignment", error)
                    })?
                    .ok_or_else(invalid)?;
            if crate::studio::agent_close::is_explicitly_closed(&checkpoint.state)
                .map_err(|error| resource_error("read reviewed close intent", error))?
            {
                return Err(invalid());
            }
            crate::studio::workspace_receipt::from_snapshot(&checkpoint.state)
                .map_err(|error| resource_error("decode reviewed workspace assignment", error))?
                .ok_or_else(invalid)?
        };
        let frozen = self
            .services
            .store
            .workspace_identity(target_id)
            .await
            .map_err(|error| resource_error("read reviewed physical identity", error))?
            .ok_or_else(invalid)?;
        let actual = self
            .resolve_workspace_identity(project, std::path::Path::new(&assignment.root))
            .await
            .map_err(Self::workspace_usage_error)?;
        if actual != frozen {
            return Err(invalid());
        }
        if let Some(binding) = &live
            && binding.workspace.root() != std::path::Path::new(&assignment.root)
        {
            return Err(invalid());
        }
        if assignment.mode == pl_protocol::AgentWorkspaceMode::Worktree {
            let lease = self.services.worktrees.get(target_id).ok_or_else(invalid)?;
            let receipt = assignment.worktree.as_ref().ok_or_else(invalid)?;
            if lease.owner_kind != WorktreeLeaseOwnerKind::Child
                || lease.root_thread_id != parent.root_thread_id
                || lease.project_id != project.id
                || lease.state == WorktreeLeaseState::Cleaned
                || lease.path != assignment.root
                || lease.path != receipt.path
                || lease.branch != receipt.branch
                || lease.base_commit != receipt.base_commit
                || lease.repository_root != receipt.repository_root
            {
                return Err(invalid());
            }
            let manager = crate::studio::agent_host::workspace_preparation::manager_from_lease(
                &self.services.store,
                &self.services.ssh_manager,
                &lease,
            )
            .await
            .map_err(|error| resource_error("open reviewed workspace manager", error))?;
            manager
                .validate_registered_site(std::path::Path::new(&lease.path), &lease.branch)
                .await
                .map_err(|error| resource_error("verify reviewed worktree identity", error))?;
        }
        Ok(
            crate::studio::agent_host::workspace_preparation::ReviewWorkspaceTarget {
                agent_id: target_id.to_owned(),
                assignment,
            },
        )
    }
}
