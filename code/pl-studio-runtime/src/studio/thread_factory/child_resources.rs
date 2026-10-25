//! Physical child resources assembled from one resolved product configuration snapshot.
use super::StudioThreadFactory;
use super::errors::resource_error;
use crate::resource_store::FileResourceStore;
use crate::studio::ThreadRecord;
use crate::studio::agent_host::workspace_preparation::WorkspaceCloseFailure;
use crate::thread_assembler::{
    ChildThreadRequest, StudioChildResources, StudioThreadSpec, ThreadAssemblyError,
};
use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_core::context::{
    ContextContent, ContextRecord, ContextSource, OpaquePayload, ResourceAccess,
};
use pl_tool::workspace::{AgentWorkspace, ToolWorkspace};
use std::{
    collections::BTreeMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::studio) enum FactoryClosePhase {
    Manager,
    AbandonedIdentity,
    AbandonedProjection,
}

#[derive(Debug, Clone)]
pub(in crate::studio) enum FactoryCloseIssue {
    Workspace(WorkspaceCloseFailure),
    #[allow(dead_code)] // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
    Failed {
        phase: FactoryClosePhase,
        cause: Arc<anyhow::Error>,
    },
}
#[allow(dead_code)] // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
impl FactoryCloseIssue {
    pub(in crate::studio) fn workspace_failure(&self) -> Option<&WorkspaceCloseFailure> {
        match self {
            Self::Workspace(failure) => Some(failure),
            Self::Failed { .. } => None,
        }
    }
    pub(in crate::studio) fn raw_cause(&self) -> Option<&Arc<anyhow::Error>> {
        match self {
            Self::Failed { cause, .. } => Some(cause),
            Self::Workspace(_) => None,
        }
    }
    pub(in crate::studio) fn phase_label(&self) -> &'static str {
        match self {
            Self::Workspace(_) => "workspace",
            Self::Failed {
                phase: FactoryClosePhase::Manager,
                ..
            } => "manager",
            Self::Failed {
                phase: FactoryClosePhase::AbandonedIdentity,
                ..
            } => "abandonedIdentity",
            Self::Failed {
                phase: FactoryClosePhase::AbandonedProjection,
                ..
            } => "abandonedProjection",
        }
    }
}

#[derive(Clone)]
pub(crate) struct FactoryCloseFailure {
    run: Arc<FactoryClose>,
    pub(in crate::studio) issues: Vec<FactoryCloseIssue>,
}
impl std::fmt::Debug for FactoryCloseFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("FactoryCloseFailure")
            .field("issues", &self.issues)
            .finish_non_exhaustive()
    }
}
impl std::fmt::Display for FactoryCloseFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("original child factory resources remain unresolved")
    }
}
impl std::error::Error for FactoryCloseFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.issues.first().map(|issue| match issue {
            FactoryCloseIssue::Workspace(failure) => failure as _,
            FactoryCloseIssue::Failed { cause, .. } => cause.as_ref().as_ref(),
        })
    }
}
impl FactoryCloseFailure {
    pub(crate) fn original_is_complete(&self) -> bool {
        let progress = self
            .run
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        matches!(progress.workspace, WorkspaceStep::Complete)
            && matches!(progress.directory, DirectoryStep::Complete)
    }
    pub(crate) fn can_resume_original(&self) -> bool {
        let progress = self
            .run
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let workspace = match &progress.workspace {
            WorkspaceStep::Unattempted => true,
            WorkspaceStep::Wait(wait) => match wait.peek() {
                None | Some(Ok(())) => true,
                Some(Err(failure)) => {
                    failure.can_resume_original() || failure.original_is_complete()
                }
            },
            WorkspaceStep::Complete | WorkspaceStep::Manager(_) => false,
        };
        let directory = self.run.directory_identity_matches()
            && match &progress.directory {
                DirectoryStep::Unattempted => true,
                DirectoryStep::Wait(wait) => match wait.peek() {
                    None | Some(Ok(())) => true,
                    Some(Err(error)) => directory_retryable(error),
                },
                DirectoryStep::Complete | DirectoryStep::Identity(_) => false,
            };
        workspace || directory
    }
    /// Caller retains the original assembler operation/cleanup boundary. This continuation never
    /// calls the product factory again and freezes only already failed eligible leaf outcomes.
    pub(crate) async fn resume_original(&self) -> Result<(), Self> {
        if self.original_is_complete() {
            return Ok(());
        }
        if !self.can_resume_original() {
            return Err(self.clone());
        }
        self.run.drive(self.run.grant()).await
    }
}

type WorkspaceWait = Shared<BoxFuture<'static, Result<(), Arc<WorkspaceCloseFailure>>>>;
type DirectoryWait = Shared<BoxFuture<'static, Result<(), Arc<anyhow::Error>>>>;
enum WorkspaceStep {
    Unattempted,
    Wait(WorkspaceWait),
    Manager(Arc<anyhow::Error>),
    Complete,
}
enum DirectoryStep {
    Unattempted,
    Wait(DirectoryWait),
    Identity(Arc<anyhow::Error>),
    Complete,
}
struct FactoryProgress {
    workspace: WorkspaceStep,
    directory: DirectoryStep,
}
#[derive(Default)]
struct FactoryGrant {
    workspace: Option<Arc<WorkspaceCloseFailure>>,
    directory: Option<Arc<anyhow::Error>>,
}
struct FactoryClose {
    worktrees: crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner,
    ssh_manager: Arc<pl_tool::remote::SshManager>,
    events: crate::studio::ProductEventBus,
    id: String,
    lease: Option<crate::studio::agent_host::worktree_lease::WorktreeLease>,
    disposition: pl_tool::collaboration::thread::AgentWorkspaceDisposition,
    product: Option<pl_protocol::Thread>,
    progress: Mutex<FactoryProgress>,
}

impl FactoryClose {
    fn directory_identity_matches(&self) -> bool {
        let Some(original) = &self.product else {
            return true;
        };
        self.events
            .thread_snapshot(&self.id)
            .is_some_and(|current| {
                current.id == original.id
                    && current.root_thread_id == original.root_thread_id
                    && current.project_id == original.project_id
                    && current.parent_thread_id == original.parent_thread_id
                    && current.created_at == original.created_at
            })
    }

    fn directory_wait(&self) -> DirectoryWait {
        let events = self.events.clone();
        let id = self.id.clone();
        async move {
            events
                .fault_unregistered_child(&id, "child preparation was not published")
                .await
                .map_err(Arc::new)
        }
        .boxed()
        .shared()
    }

    fn grant(&self) -> FactoryGrant {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let workspace = match &progress.workspace {
            WorkspaceStep::Wait(wait) => wait
                .peek()
                .and_then(|result| result.as_ref().err())
                .filter(|failure| failure.can_resume_original() || failure.original_is_complete())
                .cloned(),
            _ => None,
        };
        let directory = match &progress.directory {
            DirectoryStep::Wait(wait) => wait
                .peek()
                .and_then(|result| result.as_ref().err())
                .filter(|error| self.directory_identity_matches() && directory_retryable(error))
                .cloned(),
            _ => None,
        };
        FactoryGrant {
            workspace,
            directory,
        }
    }

    async fn workspace(
        &self,
        grant: Option<&Arc<WorkspaceCloseFailure>>,
    ) -> Result<(), FactoryCloseIssue> {
        let unattempted = matches!(
            self.progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .workspace,
            WorkspaceStep::Unattempted
        );
        if unattempted {
            use crate::studio::agent_host::worktree_lease::{
                WorktreeLeaseOwnerKind, WorktreeLeaseState,
            };
            let candidate = match self.lease.as_ref().filter(|lease| {
                lease.owner_kind == WorktreeLeaseOwnerKind::Child
                    && lease.state != WorktreeLeaseState::Cleaned
            }) {
                None => WorkspaceStep::Complete,
                Some(lease) => {
                    match crate::studio::agent_host::workspace_preparation::manager_from_lease(
                        &self.ssh_manager,
                        lease,
                    ) {
                        Err(error) => WorkspaceStep::Manager(Arc::new(anyhow::Error::new(error))),
                        Ok(manager) => {
                            let leases = self.worktrees.clone();
                            let lease = lease.clone();
                            let disposition = self.disposition;
                            WorkspaceStep::Wait(async move {
                            crate::studio::agent_host::workspace_preparation::close_workspace(&leases, &manager, lease, disposition)
                                .await.map_err(Arc::new)
                        }.boxed().shared())
                        }
                    }
                }
            };
            let retired = {
                let mut progress = self
                    .progress
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if matches!(progress.workspace, WorkspaceStep::Unattempted) {
                    Some(std::mem::replace(&mut progress.workspace, candidate))
                } else {
                    Some(candidate)
                }
            };
            drop(retired);
        }
        let (wait, retired) = {
            let mut progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            match &mut progress.workspace {
                WorkspaceStep::Complete => return Ok(()),
                WorkspaceStep::Manager(cause) => {
                    return Err(FactoryCloseIssue::Failed {
                        phase: FactoryClosePhase::Manager,
                        cause: cause.clone(),
                    });
                }
                WorkspaceStep::Wait(wait) => {
                    let failed = wait
                        .peek()
                        .and_then(|result| result.as_ref().err())
                        .cloned();
                    let retired = if let Some(failed) = failed
                        && grant.is_some_and(|original| Arc::ptr_eq(original, &failed))
                        && (failed.can_resume_original() || failed.original_is_complete())
                    {
                        Some(std::mem::replace(
                            wait,
                            async move { failed.resume_original().await.map_err(Arc::new) }
                                .boxed()
                                .shared(),
                        ))
                    } else {
                        None
                    };
                    (wait.clone(), retired)
                }
                WorkspaceStep::Unattempted => unreachable!("workspace step installed"),
            }
        };
        drop(retired);
        match wait.await {
            Ok(()) => {
                let retired = std::mem::replace(
                    &mut self
                        .progress
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .workspace,
                    WorkspaceStep::Complete,
                );
                drop(retired);
                Ok(())
            }
            Err(failure) => Err(FactoryCloseIssue::Workspace(failure.as_ref().clone())),
        }
    }

    async fn directory(&self, grant: Option<&Arc<anyhow::Error>>) -> Result<(), FactoryCloseIssue> {
        let unattempted = matches!(
            self.progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .directory,
            DirectoryStep::Unattempted
        );
        if unattempted {
            let candidate = if self.product.is_some() {
                if !self.directory_identity_matches() {
                    DirectoryStep::Identity(Arc::new(anyhow::anyhow!(
                        "original abandoned child directory identity changed"
                    )))
                } else {
                    DirectoryStep::Wait(self.directory_wait())
                }
            } else {
                DirectoryStep::Complete
            };
            let retired = {
                let mut progress = self
                    .progress
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if matches!(progress.directory, DirectoryStep::Unattempted) {
                    Some(std::mem::replace(&mut progress.directory, candidate))
                } else {
                    Some(candidate)
                }
            };
            drop(retired);
        }
        let (wait, retired) = {
            let mut progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            match &mut progress.directory {
                DirectoryStep::Complete => return Ok(()),
                DirectoryStep::Identity(cause) => {
                    return Err(FactoryCloseIssue::Failed {
                        phase: FactoryClosePhase::AbandonedIdentity,
                        cause: cause.clone(),
                    });
                }
                DirectoryStep::Wait(wait) => {
                    // Only this failed projection may be retried. The original operation permit
                    // still protects the factory identity; the existing helper owns its DTO rules.
                    let failed = wait
                        .peek()
                        .and_then(|result| result.as_ref().err())
                        .cloned();
                    let retired = if let Some(failed) = failed
                        && grant.is_some_and(|original| Arc::ptr_eq(original, &failed))
                        && self.directory_identity_matches()
                        && directory_retryable(&failed)
                    {
                        Some(std::mem::replace(wait, self.directory_wait()))
                    } else {
                        None
                    };
                    (wait.clone(), retired)
                }
                DirectoryStep::Unattempted => unreachable!("directory step installed"),
            }
        };
        drop(retired);
        match wait.await {
            Ok(()) => {
                let retired = std::mem::replace(
                    &mut self
                        .progress
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .directory,
                    DirectoryStep::Complete,
                );
                drop(retired);
                Ok(())
            }
            Err(cause) => Err(FactoryCloseIssue::Failed {
                phase: FactoryClosePhase::AbandonedProjection,
                cause,
            }),
        }
    }

    async fn drive(self: &Arc<Self>, grant: FactoryGrant) -> Result<(), FactoryCloseFailure> {
        let (workspace, directory) = futures::join!(
            self.workspace(grant.workspace.as_ref()),
            self.directory(grant.directory.as_ref())
        );
        let issues: Vec<_> = [workspace.err(), directory.err()]
            .into_iter()
            .flatten()
            .collect();
        if issues.is_empty() {
            Ok(())
        } else {
            Err(FactoryCloseFailure {
                run: self.clone(),
                issues,
            })
        }
    }
}

fn directory_retryable(error: &anyhow::Error) -> bool {
    !error
        .chain()
        .any(|source| source.is::<tokio::task::JoinError>())
        && error.chain().any(|source| source.is::<std::io::Error>())
}

impl StudioThreadFactory {
    async fn close_factory_resources(
        &self,
        id: &str,
        kind: FactoryCloseKind,
    ) -> Result<(), FactoryCloseFailure> {
        let product = if matches!(kind, FactoryCloseKind::Unpublished) {
            self.services.product_events.thread_snapshot(id)
        } else {
            None
        };
        let disposition = match kind {
            FactoryCloseKind::Published(disposition) => disposition,
            FactoryCloseKind::Unpublished => {
                pl_tool::collaboration::thread::AgentWorkspaceDisposition::Cleanup
            }
        };
        let run = Arc::new(FactoryClose {
            worktrees: self.services.worktrees.clone(),
            ssh_manager: self.services.ssh_manager.clone(),
            events: self.services.product_events.clone(),
            id: id.to_owned(),
            lease: self.services.worktrees.get(id),
            disposition,
            progress: Mutex::new(FactoryProgress {
                workspace: WorkspaceStep::Unattempted,
                directory: if product.is_some() {
                    DirectoryStep::Unattempted
                } else {
                    DirectoryStep::Complete
                },
            }),
            product,
        });
        run.drive(FactoryGrant::default()).await
    }
}

enum FactoryCloseKind {
    Published(pl_tool::collaboration::thread::AgentWorkspaceDisposition),
    Unpublished,
}

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
        let project_root = match self
            .bind_bot_project(&request.id, &parent.root_thread_id, &mut project)
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
        let (assignment, worktree) =
            crate::studio::agent_host::workspace_preparation::prepare_workspace(
                &self.services.worktrees,
                &self.services.ssh_manager,
                crate::studio::agent_host::workspace_preparation::WorkspacePreparation {
                    project: &project,
                    project_root,
                    root_thread_id: &parent.root_thread_id,
                    child_id: &request.id,
                    mode: profile.profile.workspace_mode,
                    writable_paths: request.writable_paths.clone(),
                    session_root,
                    review_target,
                },
            )
            .await
            .map_err(|error| resource_error("prepare child workspace", error))?;
        check_cancelled(request)?;
        let workspace =
            ToolWorkspace::new(assigned_workspace(&assignment, root_thread.workspace_mode))
                .with_lsp_runtime(Some(self.services.lsp_runtime.clone()));
        let store = FileResourceStore::new(
            self.services
                .store
                .session_resources_dir_for(&parent.project_id, &request.id)
                .map_err(|error| resource_error("resolve child session resources", error))?,
        );
        let mut prepared_tools = self
            .prepare_thread_tools(super::thread_tools::ThreadToolAssembly {
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
        let (mut initial_context, instruction_sources) =
            super::thread_seed::capture(super::thread_seed::ThreadInstructionSeed {
                thread_id: &request.id,
                config: &profile.config,
                model: &profile.route.model,
                root: std::path::Path::new(&assignment.root),
                label: &profile.profile.display_name,
                instructions: &profile.profile.system_instructions,
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
        if let Some(worktree) = worktree {
            let mut lease = worktree.lease;
            lease.transition(crate::studio::agent_host::worktree_lease::WorktreeLeaseState::Active);
            self.services
                .worktrees
                .record(lease)
                .map_err(|error| resource_error("activate workspace lease", error))?;
        }
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
            preparation_guard: prepared_tools.binding_guard.take(),
            context_preparation: crate::compaction::preparer(
                &profile.route,
                model.clone(),
                profile.config.runtime.openai_compaction_mode,
                self.services.thread_modes.clone(),
            )?,
            agent_controls: crate::thread_assembler::AgentControlExposure::Disabled,
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
        disposition: pl_tool::collaboration::thread::AgentWorkspaceDisposition,
    ) -> Result<(), ThreadAssemblyError> {
        self.close_factory_resources(id, FactoryCloseKind::Published(disposition))
            .await
            .map_err(|failure| resource_error("close original published workspace", failure))
    }

    async fn discard_unpublished(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        self.close_factory_resources(id, FactoryCloseKind::Unpublished)
            .await
            .map_err(|failure| resource_error("close original unpublished resources", failure))
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
    /// lease 为 canonical 事实并核对物理工作树仍存在，非 worktree 被审者的工作区即会话工作区
    /// 根，由 `prepare_workspace` 派生。review child 不获取、不转移被审者的 lease。
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
        let Some(lease) = self.services.worktrees.get(target_id) else {
            return Ok(
                crate::studio::agent_host::workspace_preparation::ReviewWorkspaceTarget {
                    agent_id: target_id.to_owned(),
                    worktree: None,
                },
            );
        };
        if lease.owner_kind != WorktreeLeaseOwnerKind::Child
            || lease.root_thread_id != parent.root_thread_id
            || lease.state == WorktreeLeaseState::Cleaned
        {
            return Err(invalid());
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
        match manager.preview_existing(&handle).await {
            Ok(Some(_)) => {}
            Ok(None) => return Err(invalid()),
            Err(error) => return Err(resource_error("preview reviewed workspace", error)),
        }
        Ok(
            crate::studio::agent_host::workspace_preparation::ReviewWorkspaceTarget {
                agent_id: target_id.to_owned(),
                worktree: Some(pl_protocol::AgentWorktreeSnapshot {
                    repository_root: lease.repository_root.clone(),
                    path: lease.path.clone(),
                    branch: lease.branch.clone(),
                    base_commit: lease.base_commit.clone(),
                }),
            },
        )
    }
}
