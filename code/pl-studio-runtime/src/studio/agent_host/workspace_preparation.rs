//! Product workspace allocation independent of Agent execution and model sessions.
use super::worktree_lease::{
    WorkspaceEndpoint, WorkspaceIdentity, WorkspaceUsageLease, WorktreeLease, WorktreeLeaseOwner,
    WorktreeLeaseOwnerKind, WorktreeLeaseState,
};
use crate::agent::worktree::{
    LocalWorktreeBackend, RemoteWorktreeBackend, WorktreeBackend, WorktreeCreateSpec,
    WorktreeHandle, WorktreeManager, WorktreeOwnership,
};
use crate::studio::records::ProjectRecord;
use crate::{PureError, Result};
use pl_protocol::{AgentWorkspaceAssignmentSnapshot, AgentWorkspaceMode, AgentWorktreeSnapshot};
use std::{
    path::{Path, PathBuf},
    sync::Arc,
};

pub(in crate::studio) struct WorkspacePreparation<'a> {
    pub store: &'a crate::studio::StudioStore,
    pub usage: &'a WorkspaceUsageLease,
    pub project: &'a ProjectRecord,
    /// Already resolved by the owner; bot roots must not expand to an enclosing repository.
    pub project_root: PathBuf,
    pub root_thread_id: &'a str,
    pub child_id: &'a str,
    pub mode: AgentWorkspaceMode,
    pub writable_paths: Option<Vec<String>>,
    /// 根会话的工作区根；`local` 会话等于 canonical Project 路径，`worktree` 会话为
    /// 其自身 worktree。非 worktree child 的工作区根跟随该值。
    pub session_root: PathBuf,
    /// Frozen from the caller's authoritative ToolWorkspace, never its inherited directory row.
    pub caller_workspace: Option<WorkspaceIdentity>,
    /// For a managed caller checkout, retain its existing pool's repository rather than nesting
    /// another pool inside the caller worktree. This is not the spawn HEAD source.
    pub caller_repository_root: Option<PathBuf>,
    /// review Profile 的被审目标；产品层完成关系与可用性校验后传入。
    pub review_target: Option<ReviewWorkspaceTarget>,
}

/// review child 采用的被审目标工作区事实。
///
/// 直接消费被审者的冻结实际 assignment，不能将非 worktree 目标反推为调用者会话根。
pub(in crate::studio) struct ReviewWorkspaceTarget {
    pub agent_id: String,
    pub assignment: AgentWorkspaceAssignmentSnapshot,
}

pub(in crate::studio) struct SpawnWorktreeLease {
    pub lease: WorktreeLease,
}

pub(in crate::studio) async fn prepare_workspace(
    worktrees: &WorktreeLeaseOwner,
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    request: WorkspacePreparation<'_>,
) -> Result<(AgentWorkspaceAssignmentSnapshot, Option<SpawnWorktreeLease>)> {
    let project_root = request.project_root;
    let session_root = request.session_root;
    let child_id = request.child_id.to_owned();
    let mode = request.mode;
    let remote = request.project.ssh_alias.is_some();
    if mode != AgentWorkspaceMode::Directory && request.writable_paths.is_some() {
        return Err(lifecycle_error(
            "only directory Profiles accept writablePaths",
        ));
    }
    let writable_paths = normalize_scope(request.writable_paths)?;
    let project_root_text = workspace_path_text(&project_root, remote)?;
    let session_root_text = workspace_path_text(&session_root, remote)?;

    let (assignment, worktree) = match mode {
        AgentWorkspaceMode::Unrestricted => (
            AgentWorkspaceAssignmentSnapshot {
                mode,
                project_root: project_root_text,
                root: session_root_text,
                writable_paths: None,
                worktree: None,
                review_target: None,
            },
            None,
        ),
        AgentWorkspaceMode::Review => {
            let target = request.review_target.ok_or_else(|| {
                lifecycle_error("review workspace requires a reviewed agent workspace")
            })?;
            (
                AgentWorkspaceAssignmentSnapshot {
                    mode,
                    project_root: target.assignment.project_root,
                    root: target.assignment.root,
                    writable_paths: None,
                    worktree: target.assignment.worktree,
                    review_target: Some(pl_protocol::AgentReviewTargetSnapshot {
                        agent_id: target.agent_id,
                    }),
                },
                None,
            )
        }
        AgentWorkspaceMode::Directory => {
            let writable_paths = writable_paths
                .map(|paths| {
                    paths
                        .into_iter()
                        .map(|path| {
                            let path = if path == "." {
                                session_root.clone()
                            } else {
                                session_root.join(path)
                            };
                            workspace_path_text(&path, remote)
                        })
                        .collect::<Result<Vec<_>>>()
                })
                .transpose()?;
            (
                AgentWorkspaceAssignmentSnapshot {
                    mode,
                    project_root: project_root_text,
                    root: session_root_text,
                    writable_paths,
                    worktree: None,
                    review_target: None,
                },
                None,
            )
        }
        AgentWorkspaceMode::Worktree => {
            let caller = request.caller_workspace.ok_or_else(|| {
                lifecycle_error("worktree spawn has no authoritative caller execution workspace")
            })?;
            let caller_root = PathBuf::from(&caller.root);
            let (mut repository_root, mut manager, endpoint) = repository_manager(
                ssh_manager,
                request.project.ssh_alias.as_deref(),
                &caller_root,
            )
            .await?;
            if endpoint != caller.endpoint {
                return Err(lifecycle_error(
                    "caller execution endpoint changed during worktree spawn",
                ));
            }
            let actual = super::worktree_lease::resolve_physical_workspace(
                ssh_manager,
                request.project,
                &caller_root,
            )
            .await
            .map_err(|error| lifecycle_error(error.to_string()))?;
            if actual != caller {
                return Err(lifecycle_error(
                    "caller execution canonical identity changed during worktree spawn",
                ));
            }
            if let Some(owned_repository) = request.caller_repository_root {
                let (backend, rebound) = backend_for(
                    ssh_manager,
                    request.project.ssh_alias.as_deref(),
                    &owned_repository,
                    WorktreeBackendRoot::Repository,
                )
                .await?;
                if rebound != caller.endpoint {
                    return Err(lifecycle_error(
                        "managed caller repository endpoint changed",
                    ));
                }
                repository_root = owned_repository;
                manager = WorktreeManager::new(repository_root.clone(), backend);
            }
            let base_commit = manager
                .clean_spawn_head(&caller_root)
                .await
                .map_err(|error| lifecycle_error(error.to_string()))?;
            if manager
                .git_common_dir(&caller_root)
                .await
                .map_err(|error| lifecycle_error(error.to_string()))?
                .is_none()
                || manager
                    .git_common_dir(&caller_root)
                    .await
                    .map_err(|error| lifecycle_error(error.to_string()))?
                    != manager
                        .git_common_dir(&repository_root)
                        .await
                        .map_err(|error| lifecycle_error(error.to_string()))?
            {
                return Err(lifecycle_error(
                    "caller execution checkout differs from the resolved Git repository",
                ));
            }
            let ownership = WorktreeOwnership::Child {
                child_id: child_id.clone(),
            };
            let path = WorktreeManager::allocate_path(
                &repository_root,
                request.root_thread_id,
                &ownership,
            );
            let branch = WorktreeManager::branch_for(&ownership);
            let identity =
                WorkspaceIdentity::canonical(endpoint, workspace_path_text(&path, remote)?)
                    .map_err(|error| lifecycle_error(error.to_string()))?;
            worktrees
                .assign_workspace(request.usage, identity.clone())
                .map_err(|error| lifecycle_error(error.to_string()))?;
            request
                .store
                .bind_workspace_identity(&child_id, &identity)
                .await
                .map_err(|error| lifecycle_error(error.to_string()))?;
            // 远端 lease 的仓库根与 worktree 路径必须记录为 POSIX：会话工作区根、workspace
            // 打开参数与 git 路径参数都从该记录派生，宿主分隔符不得进入 durable 事实。
            let repository_root_text = workspace_path_text(&repository_root, remote)?;
            let mut durable = WorktreeLease {
                revision: 1,
                state: WorktreeLeaseState::Prepared,
                owner_kind: WorktreeLeaseOwnerKind::Child,
                owner_thread_id: child_id.clone(),
                root_thread_id: request.root_thread_id.to_owned(),
                project_id: request.project.id.clone(),
                ssh_alias: request.project.ssh_alias.clone(),
                repository_root: repository_root_text.clone(),
                path: workspace_path_text(&path, remote)?,
                branch: branch.clone(),
                base_commit: base_commit.clone(),
                restore_authorized_at: None,
            };
            prepare_repository_worktree_pool(
                ssh_manager,
                request.project.ssh_alias.as_deref(),
                &repository_root,
                &identity.endpoint,
            )
            .await?;
            let current = super::worktree_lease::resolve_physical_workspace(
                ssh_manager,
                request.project,
                &caller_root,
            )
            .await
            .map_err(|error| lifecycle_error(error.to_string()))?;
            if current != caller
                || manager
                    .clean_spawn_head(&caller_root)
                    .await
                    .map_err(|error| lifecycle_error(error.to_string()))?
                    != base_commit
            {
                return Err(lifecycle_error(
                    "caller execution identity or HEAD changed before worktree creation",
                ));
            }
            worktrees
                .record_durable(durable.clone())
                .await
                .map_err(|error| lifecycle_error(error.to_string()))?;
            worktrees.preserve_workspace_resources(&child_id, identity);
            let handle = match create_with_cleanup(
                worktrees,
                &manager,
                &durable,
                request.usage,
                WorktreeCreateSpec {
                    repo_root: repository_root.clone(),
                    root_thread_id: request.root_thread_id.to_owned(),
                    ownership,
                    base_commit: base_commit.clone(),
                },
            )
            .await
            {
                Ok(handle) => handle,
                Err(error) => {
                    settle_failed_create(worktrees, durable, &error).await;
                    return Err(lifecycle_error(error.to_string()));
                }
            };
            let handle_path_text = workspace_path_text(&handle.path, remote)?;
            durable.path = handle_path_text.clone();
            durable.branch = handle.branch.clone();
            (
                AgentWorkspaceAssignmentSnapshot {
                    mode,
                    project_root: project_root_text,
                    root: handle_path_text.clone(),
                    writable_paths: None,
                    worktree: Some(AgentWorktreeSnapshot {
                        repository_root: repository_root_text,
                        path: handle_path_text,
                        branch: handle.branch.clone(),
                        base_commit,
                    }),
                    review_target: None,
                },
                Some(SpawnWorktreeLease { lease: durable }),
            )
        }
    };

    if mode != AgentWorkspaceMode::Worktree {
        let identity = super::worktree_lease::resolve_physical_workspace(
            ssh_manager,
            request.project,
            Path::new(&assignment.root),
        )
        .await
        .map_err(|error| lifecycle_error(error.to_string()))?;
        worktrees
            .assign_workspace(request.usage, identity.clone())
            .map_err(|error| lifecycle_error(error.to_string()))?;
        request
            .store
            .bind_workspace_identity(&child_id, &identity)
            .await
            .map_err(|error| lifecycle_error(error.to_string()))?;
    }
    Ok((assignment, worktree))
}

pub(in crate::studio) enum WorktreeBackendRoot {
    Project,
    Repository,
}

pub(in crate::studio) async fn backend_for(
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    ssh_alias: Option<&str>,
    project_root: &Path,
    kind: WorktreeBackendRoot,
) -> Result<(Arc<dyn WorktreeBackend>, WorkspaceEndpoint)> {
    match ssh_alias {
        Some(server_id) => {
            let profile = ssh_manager
                .list_servers()
                .await
                .into_iter()
                .find(|entry| entry.profile.alias == server_id)
                .ok_or_else(|| lifecycle_error("SSH worktree endpoint is not configured"))?
                .profile;
            let endpoint = WorkspaceEndpoint::from_profile(Some(&profile));
            let backend = match kind {
                WorktreeBackendRoot::Project => RemoteWorktreeBackend::new(
                    ssh_manager.clone(),
                    profile,
                    project_root.to_path_buf(),
                ),
                WorktreeBackendRoot::Repository => RemoteWorktreeBackend::canonical_repository(
                    ssh_manager.clone(),
                    profile,
                    project_root.to_path_buf(),
                ),
            };
            backend
                .map(|backend| (Arc::new(backend) as Arc<dyn WorktreeBackend>, endpoint))
                .map_err(|error| lifecycle_error(error.to_string()))
        }
        None => Ok((
            Arc::new(LocalWorktreeBackend::default()),
            WorkspaceEndpoint::Local,
        )),
    }
}

pub(in crate::studio) async fn manager_from_lease(
    store: &crate::studio::StudioStore,
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    lease: &WorktreeLease,
) -> Result<WorktreeManager> {
    let repository_root = PathBuf::from(&lease.repository_root);
    let (backend, endpoint) = backend_for(
        ssh_manager,
        lease.ssh_alias.as_deref(),
        &repository_root,
        WorktreeBackendRoot::Repository,
    )
    .await?;
    if let Some(identity) = store
        .workspace_identity(&lease.owner_thread_id)
        .await
        .map_err(|error| lifecycle_error(error.to_string()))?
        && (endpoint != identity.endpoint || identity.root != lease.path)
    {
        return Err(lifecycle_error(
            "worktree lease endpoint changed from its frozen physical identity",
        ));
    }
    // Legacy inspection/restoration is not deletion authority. Every destructive caller below
    // separately requires cleanup_identity, which refuses an SSH lease lacking its old endpoint.
    Ok(WorktreeManager::new(repository_root, backend))
}

pub(in crate::studio) async fn cleanup_identity(
    store: &crate::studio::StudioStore,
    lease: &WorktreeLease,
) -> anyhow::Result<WorkspaceIdentity> {
    lease.validate_identity()?;
    if let Some(identity) = store.workspace_identity(&lease.owner_thread_id).await? {
        anyhow::ensure!(
            identity.root == lease.path
                && matches!(identity.endpoint, WorkspaceEndpoint::Ssh { .. })
                    == lease.ssh_alias.is_some(),
            "worktree physical binding no longer matches its lease"
        );
        return Ok(identity);
    }
    // Old local leases record an OS-canonical Git-derived path. An SSH alias without its original
    // endpoint does not prove a site; never grant deletion by resolving today's configuration.
    anyhow::ensure!(
        lease.ssh_alias.is_none(),
        "legacy SSH lease has no frozen physical endpoint; original resources preserved"
    );
    WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, lease.path.clone())
}

/// Resolves a Project's repository root and returns the backend and manager anchored on
/// that resolved root.
///
/// 本地和 SSH 项目都以创建时解析出的仓库根作为 worktree backend 根：远端项目的
/// workspace handle 根、Git 工作目录与相对路径基准都取自该仓库根，而不是配置的 Project
/// 目录，因此 Project 目录是仓库子目录时同样成立。解析本身在 Project 目录上执行，返回的
/// manager 与 `manager_from_lease` 使用同一约定，创建路径因此与恢复、preview 和清理一致。
pub(in crate::studio) async fn repository_manager(
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    ssh_alias: Option<&str>,
    project_root: &Path,
) -> Result<(PathBuf, WorktreeManager, WorkspaceEndpoint)> {
    let (resolver, endpoint) = backend_for(
        ssh_manager,
        ssh_alias,
        project_root,
        WorktreeBackendRoot::Project,
    )
    .await?;
    let repository_root = WorktreeManager::resolve_repository_root(resolver.as_ref(), project_root)
        .await
        .map_err(|error| lifecycle_error(error.to_string()))?;
    let (backend, rebound) = backend_for(
        ssh_manager,
        ssh_alias,
        &repository_root,
        WorktreeBackendRoot::Repository,
    )
    .await?;
    if endpoint != rebound {
        return Err(lifecycle_error(
            "SSH repository endpoint changed while resolving",
        ));
    }
    Ok((
        repository_root.clone(),
        WorktreeManager::new(repository_root, backend),
        endpoint,
    ))
}

/// Creates the physical worktree of a root session and records its `prepared` lease.
///
/// Preflight (repository root and `HEAD` resolution over the Project's own backend) runs
/// before any resource exists; the physical create then runs on the backend rooted at that
/// repository root, so local and SSH Projects share one convention. A failed physical
/// create settles the durable lease through the existing
/// `WorktreeCreateFailureDisposition` and never bypasses a Git lock or a registered
/// worktree identity.
pub(in crate::studio) async fn create_root_session_worktree<F>(
    store: &crate::studio::StudioStore,
    worktrees: &WorktreeLeaseOwner,
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    project: &ProjectRecord,
    thread_id: &str,
    progress: &F,
) -> anyhow::Result<WorktreeLease>
where
    F: Fn(pl_protocol::studio::ThreadPreparationStage, Option<&str>, Option<&str>) + Send + Sync,
{
    use pl_protocol::studio::ThreadPreparationStage;
    let usage = worktrees
        .reserve_project_workspace(thread_id, ssh_manager, project)
        .await?;
    progress(ThreadPreparationStage::ResolvingRepository, None, None);
    let project_root = resolved_project_root(project)?;
    let (repository_root, manager, endpoint) =
        repository_manager(ssh_manager, project.ssh_alias.as_deref(), &project_root)
            .await
            .map_err(|error| {
                anyhow::Error::new(error).context(pl_protocol::studio::StudioError::new(
                    pl_protocol::studio::StudioErrorCode::Unavailable,
                    "Could not resolve the project's Git repository. Check that the project is inside a Git repository and the repository is accessible.",
                    false,
                ))
            })?;
    let base_commit = manager
        .resolve_head(&repository_root)
        .await
        .map_err(|error| {
            anyhow::Error::new(error).context(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Unavailable,
                "Could not resolve the repository's HEAD. Check that the repository has a commit and is accessible.",
                false,
            ))
        })?;
    let ownership = WorktreeOwnership::Session {
        thread_id: thread_id.to_owned(),
    };
    let path = WorktreeManager::allocate_path(&repository_root, thread_id, &ownership);
    let branch = WorktreeManager::branch_for(&ownership);
    // 远端项目的 durable lease 记录 POSIX 形式；本地项目保留宿主形态。
    let remote = project.ssh_alias.is_some();
    // 会话冷恢复会在同一 owner 上重建 lease；revision 必须相对已有记录递增，
    // 否则 `record` 的版本准入会拒绝重建（design/17 §17.1）。
    let revision = worktrees
        .get(thread_id)
        .map(|lease| lease.revision.saturating_add(1))
        .unwrap_or(1);
    let durable = WorktreeLease {
        revision,
        state: WorktreeLeaseState::Prepared,
        owner_kind: WorktreeLeaseOwnerKind::Session,
        owner_thread_id: thread_id.to_owned(),
        root_thread_id: thread_id.to_owned(),
        project_id: project.id.clone(),
        ssh_alias: project.ssh_alias.clone(),
        repository_root: workspace_path_text(&repository_root, remote)?,
        path: workspace_path_text(&path, remote)?,
        branch,
        base_commit: base_commit.clone(),
        restore_authorized_at: None,
    };
    let identity = WorkspaceIdentity::canonical(endpoint, durable.path.clone())?;
    worktrees.assign_workspace(&usage, identity.clone())?;
    store.bind_workspace_identity(thread_id, &identity).await?;
    prepare_repository_worktree_pool(
        ssh_manager,
        project.ssh_alias.as_deref(),
        &repository_root,
        &identity.endpoint,
    )
    .await?;
    worktrees
        .record_durable(durable.clone())
        .await
        .map_err(|error| lifecycle_error(error.to_string()))?;
    worktrees.preserve_workspace_resources(thread_id, identity);
    progress(
        ThreadPreparationStage::CreatingWorktree,
        Some(&durable.path),
        Some(&durable.branch),
    );
    let handle = match create_with_cleanup(
        worktrees,
        &manager,
        &durable,
        &usage,
        WorktreeCreateSpec {
            repo_root: repository_root,
            root_thread_id: thread_id.to_owned(),
            ownership,
            base_commit,
        },
    )
    .await
    {
        Ok(handle) => handle,
        Err(error) => {
            settle_failed_create(worktrees, durable, &error).await;
            return Err(anyhow::Error::new(error).context(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Unavailable,
                "Git could not create or check out the session worktree. Check repository permissions and available disk space.",
                false,
            )));
        }
    };
    if !workspace_paths_equal(&handle.path, &path, remote)? || handle.branch != durable.branch {
        return Err(settle_identity_mismatch(worktrees, durable).into());
    }
    Ok(durable)
}

/// 收束一个 durable worktree lease：`validate_identity → preview_existing →
/// cleanupRequested → discard → cleaned`，任一步失败回落 `preserved` 并返回错误。
///
/// 这是 child 关闭路径与归档清理共用的唯一实现；`disposition == Preserve` 时只把 lease
/// 收束为 `preserved` 而不删除物理资源，`Cleanup` 才删除 Pure-owned 工作树与分支。
pub(in crate::studio) async fn close_workspace(
    store: &crate::studio::StudioStore,
    leases: &WorktreeLeaseOwner,
    manager: &WorktreeManager,
    mut lease: WorktreeLease,
    disposition: pl_tool::collaboration::thread::WorkspaceRelease,
) -> anyhow::Result<()> {
    use pl_tool::collaboration::thread::WorkspaceRelease;
    // A settled site may still carry an archive-restore grant whose rebuild never happened; ending
    // the window is itself the settlement, so the residue is consumed instead of being left behind
    // where a later ordinary activation could read it as a live permission.
    if lease.state == WorktreeLeaseState::Cleaned {
        return cleanup_workspace(store, leases, manager, lease).await;
    }
    // A new explicit cleanup ends the window of any earlier archive-restore authorization: that
    // authorization only ever covered the site the restore itself was reacting to.
    match disposition {
        WorkspaceRelease::Preserve => {
            lease.settle(WorktreeLeaseState::Preserved);
            leases.record(lease)
        }
        WorkspaceRelease::Cleanup => cleanup_workspace(store, leases, manager, lease).await,
    }
}

/// Resumes an explicitly authorized cleanup phase. Callers hold lifecycle/owner admission and
/// prove that the resource has no live owner; a phase label never supplies that authorization.
pub(in crate::studio) async fn cleanup_workspace(
    store: &crate::studio::StudioStore,
    leases: &WorktreeLeaseOwner,
    manager: &WorktreeManager,
    lease: WorktreeLease,
) -> anyhow::Result<()> {
    let owner = lease.owner_thread_id.clone();
    let independently_archived = store
        .catalog()
        .get(&owner)
        .is_some_and(|entry| entry.to_thread().archived);
    anyhow::ensure!(
        independently_archived || store.agent_close(&owner).await?.is_none(),
        "explicit child close does not grant generic cleanup; an independent root archive is required"
    );
    let result = cleanup_workspace_inner(store, leases, manager, lease).await;
    if let Err(error) = result {
        if let Some(mut current) = leases.get(&owner)
            && current.state != WorktreeLeaseState::Cleaned
        {
            current.settle(WorktreeLeaseState::Preserved);
            if let Err(retention) = leases.record_durable(current).await {
                return Err(error.context(format!(
                    "cannot persist pending workspace cleanup owner: {retention:#}"
                )));
            }
        }
        return Err(error);
    }
    Ok(())
}

async fn cleanup_workspace_inner(
    store: &crate::studio::StudioStore,
    leases: &WorktreeLeaseOwner,
    manager: &WorktreeManager,
    mut lease: WorktreeLease,
) -> anyhow::Result<()> {
    lease.validate_identity()?;
    let identity = cleanup_identity(store, &lease).await?;
    let removal = leases.begin_workspace_cleanup(&lease.owner_thread_id, &identity, None)?;
    if lease.state == WorktreeLeaseState::Cleaned {
        manager
            .verify_discarded(&WorktreeHandle {
                path: lease.path.clone().into(),
                branch: lease.branch.clone(),
                base_commit: lease.base_commit.clone(),
            })
            .await?;
        lease.consume_restore();
        leases.record_durable(lease).await?;
        removal.complete();
        return Ok(());
    }
    let handle = WorktreeHandle {
        path: PathBuf::from(&lease.path),
        branch: lease.branch.clone(),
        base_commit: lease.base_commit.clone(),
    };
    manager.preview_existing(&handle).await?;
    if lease.state != WorktreeLeaseState::CleanupRequested {
        lease.settle(WorktreeLeaseState::CleanupRequested);
    }
    leases.record_durable(lease.clone()).await?;
    manager.discard(&handle).await?;
    lease.settle(WorktreeLeaseState::Cleaned);
    leases.record_durable(lease).await?;
    removal.complete();
    Ok(())
}

/// 冷激活时在同一确定性路径重建一个 child worktree，并记录 renewed 的 `prepared` lease。
///
/// 只在保存的 receipt 对应物理工作树缺失或 lease 已清理时调用；路径与 base 都来自冻结的
/// receipt，因此重建落在与原地址一致的位置，child 地址保持稳定。
pub(in crate::studio) struct ChildWorktreeRecreation<'a> {
    pub project: &'a ProjectRecord,
    pub root_thread_id: &'a str,
    pub child_id: &'a str,
    pub receipt: &'a AgentWorktreeSnapshot,
    pub repository_root: &'a Path,
}

pub(in crate::studio) async fn recreate_child_worktree(
    store: &crate::studio::StudioStore,
    worktrees: &WorktreeLeaseOwner,
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    request: ChildWorktreeRecreation<'_>,
) -> Result<WorktreeLease> {
    let ChildWorktreeRecreation {
        project,
        root_thread_id,
        child_id,
        receipt,
        repository_root,
    } = request;
    let usage = worktrees
        .reserve_project_workspace(child_id, ssh_manager, project)
        .await
        .map_err(|error| lifecycle_error(error.to_string()))?;
    let (backend, endpoint) = backend_for(
        ssh_manager,
        project.ssh_alias.as_deref(),
        repository_root,
        WorktreeBackendRoot::Repository,
    )
    .await?;
    let manager = WorktreeManager::new(repository_root.to_path_buf(), backend);
    let ownership = WorktreeOwnership::Child {
        child_id: child_id.to_owned(),
    };
    let path = WorktreeManager::allocate_path(repository_root, root_thread_id, &ownership);
    let remote = project.ssh_alias.is_some();
    if !workspace_paths_equal(&path, Path::new(&receipt.path), remote)? {
        return Err(lifecycle_error(
            "saved child worktree receipt does not match its Pure-owned deterministic path",
        ));
    }
    let branch = WorktreeManager::branch_for(&ownership);
    let revision = worktrees
        .get(child_id)
        .map(|lease| lease.revision.saturating_add(1))
        .unwrap_or(1);
    // The expiry of a rebuild authorization belongs to the successful rebuild, not to this record:
    // carrying it over keeps a failed or interrupted attempt retryable, and the caller clears it only
    // after the physical worktree really exists.
    let restore_authorized_at = worktrees
        .get(child_id)
        .and_then(|lease| lease.restore_authorized_at);
    let durable = WorktreeLease {
        revision,
        state: WorktreeLeaseState::Prepared,
        owner_kind: WorktreeLeaseOwnerKind::Child,
        owner_thread_id: child_id.to_owned(),
        root_thread_id: root_thread_id.to_owned(),
        project_id: project.id.clone(),
        ssh_alias: project.ssh_alias.clone(),
        repository_root: workspace_path_text(repository_root, remote)?,
        path: workspace_path_text(Path::new(&receipt.path), remote)?,
        branch: branch.clone(),
        base_commit: receipt.base_commit.clone(),
        restore_authorized_at,
    };
    let identity = WorkspaceIdentity::canonical(endpoint, durable.path.clone())
        .map_err(|error| lifecycle_error(error.to_string()))?;
    worktrees
        .assign_workspace(&usage, identity.clone())
        .map_err(|error| lifecycle_error(error.to_string()))?;
    store
        .bind_workspace_identity(child_id, &identity)
        .await
        .map_err(|error| lifecycle_error(error.to_string()))?;
    prepare_repository_worktree_pool(
        ssh_manager,
        project.ssh_alias.as_deref(),
        repository_root,
        &identity.endpoint,
    )
    .await?;
    worktrees
        .record_durable(durable.clone())
        .await
        .map_err(|error| lifecycle_error(error.to_string()))?;
    worktrees.preserve_workspace_resources(child_id, identity);
    let handle = match create_with_cleanup(
        worktrees,
        &manager,
        &durable,
        &usage,
        WorktreeCreateSpec {
            repo_root: repository_root.to_path_buf(),
            root_thread_id: root_thread_id.to_owned(),
            ownership,
            base_commit: receipt.base_commit.clone(),
        },
    )
    .await
    {
        Ok(handle) => handle,
        Err(error) => {
            settle_failed_create(worktrees, durable, &error).await;
            return Err(lifecycle_error(error.to_string()));
        }
    };
    if !workspace_paths_equal(&handle.path, &path, remote)? || handle.branch != durable.branch {
        return Err(settle_identity_mismatch(worktrees, durable));
    }
    Ok(durable)
}

/// 收束一个身份不符的已创建会话 worktree：保留现场（`preserved`）并返回类型化错误。
///
/// 绝不删除物理资源，也不留下停在 `prepared` 的 lease；调用方负责随后的发布。
fn settle_identity_mismatch(worktrees: &WorktreeLeaseOwner, mut lease: WorktreeLease) -> PureError {
    let error =
        lifecycle_error("created session worktree identity differs from its Pure-owned lease");
    lease.transition(WorktreeLeaseState::Preserved);
    if let Err(persist_error) = worktrees.record(lease.clone()) {
        tracing::error!(
            owner_thread_id = lease.owner_thread_id,
            error = %persist_error,
            "failed to preserve an identity-mismatched session worktree lease"
        );
    }
    error
}

/// Resolves the workspace root of a root session from its canonical product fact.
///
/// `local` uses the canonical Project root. `worktree` requires an identity-matching
/// `active` session lease; a missing, mismatched or cleaned lease fails explicitly and
/// never silently falls back to the main workspace.
pub(in crate::studio) fn root_session_workspace_root(
    worktrees: &WorktreeLeaseOwner,
    workspace_mode: pl_protocol::ThreadWorkspaceMode,
    root_thread_id: &str,
    project_root: PathBuf,
) -> Result<PathBuf> {
    use pl_protocol::ThreadWorkspaceMode;
    match workspace_mode {
        ThreadWorkspaceMode::Local => Ok(project_root),
        ThreadWorkspaceMode::Worktree => {
            let lease = worktrees.get(root_thread_id).ok_or_else(|| {
                lifecycle_error(format!(
                    "Thread {root_thread_id} workspace mode is worktree but no durable lease exists"
                ))
            })?;
            if lease.owner_kind != WorktreeLeaseOwnerKind::Session {
                return Err(lifecycle_error(format!(
                    "Thread {root_thread_id} workspace lease is not owned by its session"
                )));
            }
            if lease.state != WorktreeLeaseState::Active {
                return Err(lifecycle_error(format!(
                    "Thread {root_thread_id} session worktree lease is {} instead of active",
                    lease.state.label()
                )));
            }
            lease
                .validate_identity()
                .map_err(|error| lifecycle_error(error.to_string()))?;
            Ok(PathBuf::from(&lease.path))
        }
    }
}

async fn create_with_cleanup(
    worktrees: &WorktreeLeaseOwner,
    manager: &WorktreeManager,
    lease: &WorktreeLease,
    usage: &WorkspaceUsageLease,
    spec: WorktreeCreateSpec,
) -> std::result::Result<WorktreeHandle, crate::agent::worktree::WorktreeError> {
    use crate::agent::worktree::WorktreeError;
    match manager.create(spec).await {
        Err(WorktreeError::CreationIncomplete { operation }) => {
            let cleanup = async {
                let identity = WorkspaceIdentity::canonical(
                    worktrees.usage_endpoint(usage)?,
                    lease.path.clone(),
                )?;
                let permit = worktrees.begin_workspace_cleanup(
                    &lease.owner_thread_id,
                    &identity,
                    Some(usage),
                )?;
                manager
                    .discard_incomplete_creation(&WorktreeHandle {
                        path: lease.path.clone().into(),
                        branch: lease.branch.clone(),
                        base_commit: lease.base_commit.clone(),
                    })
                    .await?;
                permit.complete();
                Ok::<_, anyhow::Error>(())
            }
            .await;
            match cleanup {
                Ok(()) => Err(WorktreeError::OperationFailedAfterCleanup { operation }),
                Err(cleanup) => Err(WorktreeError::OperationFailedWithCleanup {
                    operation,
                    cleanup: Box::new(WorktreeError::InvalidResource(format!("{cleanup:#}"))),
                }),
            }
        }
        result => result,
    }
}

async fn settle_failed_create(
    worktrees: &WorktreeLeaseOwner,
    mut lease: WorktreeLease,
    error: &crate::agent::worktree::WorktreeError,
) {
    let state = match error {
        crate::agent::worktree::WorktreeError::OperationFailedWithCleanup { .. } => {
            WorktreeLeaseState::Preserved
        }
        _ => WorktreeLeaseState::Cleaned,
    };
    lease.transition(state);
    if let Err(persist_error) = worktrees.record(lease.clone()) {
        tracing::error!(
            owner_thread_id = lease.owner_thread_id,
            error = %persist_error,
            "failed to settle durable worktree lease after create failure"
        );
    }
}

async fn prepare_repository_worktree_pool(
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    ssh_alias: Option<&str>,
    repository_root: &Path,
    expected_endpoint: &WorkspaceEndpoint,
) -> Result<()> {
    match ssh_alias {
        Some(server) => {
            let host = ssh_manager
                .open_workspace_host(server, workspace_path_text(repository_root, true)?)
                .await
                .map_err(|error| lifecycle_error(error.to_string()))?;
            if WorkspaceEndpoint::from_profile(Some(&host.profile)) != *expected_endpoint
                || host.files.canonical_path() != workspace_path_text(repository_root, true)?
            {
                return Err(lifecycle_error(
                    "worktree pool endpoint or canonical repository changed before preparation",
                ));
            }
            pl_tool::workspace::prepare_worktree_pool(&host.files)
                .await
                .map_err(|error| lifecycle_error(error.to_string()))
        }
        None => {
            if *expected_endpoint != WorkspaceEndpoint::Local {
                return Err(lifecycle_error(
                    "worktree pool transport changed before preparation",
                ));
            }
            let backend = pl_tool::workspace_file::LocalWorkspaceFileBackend::new(
                repository_root.to_path_buf(),
                false,
            )
            .await
            .map_err(|error| lifecycle_error(error.to_string()))?;
            pl_tool::workspace::prepare_worktree_pool(&backend)
                .await
                .map_err(|error| lifecycle_error(error.to_string()))
        }
    }
}

pub(in crate::studio) fn resolved_project_root(project: &ProjectRecord) -> Result<PathBuf> {
    if project.ssh_alias.is_some() {
        let value = pl_tool::remote::normalize_remote_absolute_path(project.path.trim())
            .map_err(|error| lifecycle_error(error.to_string()))?;
        if value == "/" {
            return Err(lifecycle_error(format!(
                "invalid remote project workspace: {}",
                project.path
            )));
        }
        Ok(PathBuf::from(value))
    } else {
        pl_tool::workspace::resolve_workspace_root(&PathBuf::from(&project.path))
            .map_err(|error| lifecycle_error(error.to_string()))
    }
}

/// 远端项目的跨端路径文本统一为 POSIX；本地项目保留宿主形态。
///
/// 归一化表达本身收敛在 [`pl_tool::remote::normalize_remote_absolute_path`]，这里只负责按
/// 项目形态选择：远端 lease、会话工作区根与 workspace 打开参数必须以同一 POSIX 结果
/// 记录，本地项目不得被改写为 POSIX。
fn workspace_path_text(path: &Path, remote: bool) -> Result<String> {
    if remote {
        pl_tool::remote::normalize_remote_absolute_path(&path.to_string_lossy())
            .map_err(|error| lifecycle_error(error.to_string()))
    } else {
        Ok(path.to_string_lossy().into_owned())
    }
}

fn workspace_paths_equal(left: &Path, right: &Path, remote: bool) -> Result<bool> {
    if remote {
        Ok(workspace_path_text(left, true)? == workspace_path_text(right, true)?)
    } else {
        Ok(left == right)
    }
}

fn lifecycle_error(error: impl Into<String>) -> PureError {
    PureError::ToolExecutionFailed {
        tool: "studio_workspace".into(),
        error: error.into(),
    }
}

fn normalize_scope(requested: Option<Vec<String>>) -> Result<Option<Vec<String>>> {
    let Some(requested) = requested else {
        return Ok(None);
    };
    let mut normalized = std::collections::BTreeSet::new();
    for path in requested {
        let value = path.trim();
        if value.is_empty()
            || value.contains(['\\', '\0', ':'])
            || value.starts_with('/')
            || value.contains("//")
        {
            return Err(lifecycle_error(format!(
                "invalid project-relative write directory: {path}"
            )));
        }
        let mut parts = Vec::new();
        for component in value.split('/') {
            match component {
                ".." => {
                    return Err(lifecycle_error(format!(
                        "write directory escapes the project: {path}"
                    )));
                }
                "." | "" => {}
                part => parts.push(part),
            }
        }
        normalized.insert(if parts.is_empty() {
            ".".to_owned()
        } else {
            parts.join("/")
        });
    }
    if normalized.contains(".") {
        return Ok(Some(vec![".".to_owned()]));
    }
    let mut compact: Vec<String> = Vec::new();
    for candidate in normalized {
        if !compact.iter().any(|parent| {
            candidate
                .strip_prefix(parent)
                .is_some_and(|tail| tail.starts_with('/'))
        }) {
            compact.push(candidate);
        }
    }
    Ok(Some(compact))
}
