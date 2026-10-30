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
        self.services
            .store
            .begin_thread_preparation(
                crate::studio::store::thread_preparation::PreparationIdentity {
                    thread_id: request.id.clone(),
                    workspace_id: parent.workspace_id.clone(),
                    parent_id: Some(parent.id.clone()),
                    root_id: parent.root_thread_id.clone(),
                },
            )
            .await
            .map_err(|error| resource_error("record private assembly owner", error))?;
        let mut project = self
            .services
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.id == parent.workspace_id)
            .ok_or_else(|| ThreadAssemblyError::Identity(parent.workspace_id.clone()))?;
        let root_thread = self.thread_record(&parent.root_thread_id).await?;
        let reviewed =
            if profile.profile.workspace_mode == pl_protocol::AgentWorkspaceMode::Review {
                let target = request
                    .review_target
                    .as_ref()
                    .filter(|target| target.baseline.is_some())
                    .ok_or_else(|| {
                        ThreadAssemblyError::Identity("review has no verified target".into())
                    })?;
                let mut assignment = request.review_workspace.clone().ok_or_else(|| {
                    ThreadAssemblyError::ReviewTargetInvalid(target.agent_id.clone())
                })?;
                if let Some(actual) = self.tool_project(&target.agent_id) {
                    project = actual;
                }
                assignment.mode = pl_protocol::AgentWorkspaceMode::Review;
                assignment.writable_paths = None;
                assignment.review_target = Some(target.clone());
                Some(assignment)
            } else {
                None
            };
        self.check_bot_spawn_workspace(request, profile, &root_thread)
            .await?;
        let workspace_usage = self
            .reserve_thread_workspace_use(&request.id, &parent.root_thread_id, &project)
            .await
            .map_err(Self::workspace_usage_error)?;
        request.workspace_owner.retain(&workspace_usage);
        let bot_root = self
            .bind_bot_project(
                &request.id,
                &parent.root_thread_id,
                &mut project,
                &workspace_usage,
                super::root_resources::BotWorkspacePreparation::New,
            )
            .await?;
        let local_root = bot_root
            .clone()
            .unwrap_or_else(|| PathBuf::from(&root_thread.workspace_path));
        let project_root = if let Some(assignment) = &reviewed {
            PathBuf::from(&assignment.project_root)
        } else {
            match bot_root {
                Some(root) => root,
                None => crate::studio::agent_host::workspace_preparation::resolved_project_root(
                    &project,
                )
                .map_err(|error| resource_error("resolve child project root", error))?,
            }
        };
        let (session_root, _) =
            crate::studio::agent_host::workspace_preparation::root_session_workspace_root(
                &self.services.store,
                &self.services.worktrees,
                &self.services.ssh_manager,
                &root_thread,
                &project,
                local_root,
            )
            .await
            .map_err(|error| resource_error("resolve session workspace root", error))?;
        // child 的创建窗口与 root 会话一样由进程内 creating 标记保护：标记在记录 `prepared`
        // 之前设置，离开本函数（成功、失败、取消或展开）时由守卫清除。标记键是 child_id，
        // 不会影响会话路径的判定。
        let _creation = self.services.worktrees.creation_guard(&request.id);
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
                    identity.matches_root(&lease.path)
                        && lease.workspace_id == project.id
                        && lease.root_thread_id == parent.root_thread_id
                })
                .map(|lease| PathBuf::from(lease.repository_root))
        });
        let (assignment, worktree) = if let Some(assignment) = reviewed {
            (assignment, None)
        } else {
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
                },
            )
            .await
            .map_err(|source| ThreadAssemblyError::ChildWorkspacePreparation {
                source: source.reallocate_into_boxed_dyn_error_without_backtrace(),
            })?
        };
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
                .session_resources_dir_for(&parent.workspace_id, &request.id)
                .map_err(|error| resource_error("resolve child session resources", error))?,
        );
        let mut prepared_tools = self
            .prepare_thread_tools(super::thread_tools::ThreadToolAssembly {
                verified_local: None,
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
        Self::configure_review_finish(
            &mut prepared_tools.tools,
            &request.id,
            &profile.profile,
            &assignment,
        )?;
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
            self.confirm_worktree_binding(
                &worktree.lease,
                &workspace_usage,
                &request.workspace_owner,
            )
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
                workspace_id: parent.workspace_id,
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
        // Logical Preserve must finish before opening any Git/SSH manager. It releases the
        // actual Entry/Tool usage when the existing close owner drops them, not the checkout.
        if disposition != pl_tool::collaboration::thread::WorkspaceRelease::Preserve {
            return Err(ThreadAssemblyError::Identity(
                "generic release cannot authorize worktree deletion".into(),
            ));
        }
        // Preserve returns only the runtime use. A healthy confirmed binding remains Active;
        // failed preparations and explicit close retain their independent settlement owners.
        Ok(())
    }

    async fn discard_unpublished(
        &self,
        id: &str,
        usage: Option<&crate::studio::WorkspaceUsageLease>,
        disposition: pl_tool::collaboration::thread::WorkspaceRelease,
    ) -> Result<(), ThreadAssemblyError> {
        if disposition == pl_tool::collaboration::thread::WorkspaceRelease::Preserve {
            StudioChildResources::close_published(self, id, disposition).await?;
        } else {
            self.discard_prepared_workspace(id, usage)
                .await
                .map_err(|error| resource_error("discard unpublished assigned resources", error))?;
        }
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

impl StudioThreadFactory {
    pub(crate) async fn retire_archive_preparation(
        &self,
        record: &crate::studio::store::thread_preparation::ThreadPreparationRecord,
    ) -> Result<(), ThreadAssemblyError> {
        use crate::studio::store::thread_preparation::{PreparationBinding, PreparationSave};
        if !record.stopped || record.save == PreparationSave::Required || record.published {
            return Err(ThreadAssemblyError::Identity(
                "private archive has no original stop/save ACK".into(),
            ));
        }
        if let Some(lease) = self.services.worktrees.get(&record.identity.thread_id) {
            match &record.binding {
                PreparationBinding::Bound { identity } if identity.matches_root(&lease.path) => {}
                _ => {
                    return Err(ThreadAssemblyError::Identity(
                        "private worktree binding is unconfirmed".into(),
                    ));
                }
            }
        }
        self.services
            .store
            .set_preparation_disposition(
                &record.identity.thread_id,
                crate::studio::store::thread_preparation::PreparationDisposition::ArchivePreserve,
            )
            .await
            .map_err(|error| resource_error("retain private archive temp responsibility", error))?;
        StudioChildResources::discard_unpublished(
            self,
            &record.identity.thread_id,
            None,
            pl_tool::collaboration::thread::WorkspaceRelease::Preserve,
        )
        .await?;
        self.services
            .store
            .confirm_preparation_retirement(&record.identity.thread_id)
            .await
            .map_err(|error| resource_error("confirm private archive resources", error))?;
        self.services
            .worktrees
            .release_stopped_runtime_resources(&record.identity.thread_id);
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
