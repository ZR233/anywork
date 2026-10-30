//! Product workspace allocation independent of Agent execution and model sessions.
use super::worktree_lease::{
    WorkspaceEndpoint, WorkspaceIdentity, WorkspaceUsageLease, WorktreeLease, WorktreeLeaseOwner,
    WorktreeLeaseOwnerKind, WorktreeLeaseState,
};
use crate::agent::worktree::{
    LocalWorktreeBackend, RemoteWorktreeBackend, WorktreeBackend, WorktreeCleanupPolicy,
    WorktreeCreateFailureDisposition, WorktreeCreateSpec, WorktreeError, WorktreeHandle,
    WorktreeManager, WorktreeOwnership,
};
use crate::studio::records::WorkspaceRecord;
use anyhow::{Context, Result};
use pl_protocol::{AgentWorkspaceAssignmentSnapshot, AgentWorkspaceMode, AgentWorktreeSnapshot};
use std::{
    path::{Path, PathBuf},
    sync::Arc,
};

pub(in crate::studio) struct WorkspacePreparation<'a> {
    pub store: &'a crate::studio::StudioStore,
    pub usage: &'a WorkspaceUsageLease,
    pub project: &'a WorkspaceRecord,
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
}

/// A prepared ownership lease is promoted exactly once, before child publication.
pub(in crate::studio) struct PreparedWorktree {
    pub lease: WorktreeLease,
}

pub(in crate::studio) async fn prepare_workspace(
    worktrees: &WorktreeLeaseOwner,
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    request: WorkspacePreparation<'_>,
) -> Result<(AgentWorkspaceAssignmentSnapshot, Option<PreparedWorktree>)> {
    request
        .store
        .begin_thread_preparation(
            crate::studio::store::thread_preparation::PreparationIdentity {
                thread_id: request.child_id.to_owned(),
                workspace_id: request.project.id.clone(),
                parent_id: Some(request.root_thread_id.to_owned()),
                root_id: request.root_thread_id.to_owned(),
            },
        )
        .await?;
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

    let (assignment, lease) = match mode {
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
            return Err(lifecycle_error(
                "review creation must consume its verified target assignment",
            ));
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
            .await?;
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
            let base_commit = manager.clean_spawn_head(&caller_root).await?;
            if manager.git_common_dir(&caller_root).await?.is_none()
                || manager.git_common_dir(&caller_root).await?
                    != manager.git_common_dir(&repository_root).await?
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

            let identity =
                WorkspaceIdentity::canonical(endpoint, workspace_path_text(&path, remote)?)?;
            worktrees.assign_workspace(request.usage, identity.clone())?;
            request
                .store
                .bind_thread_preparation(&child_id, &identity)
                .await?;
            request
                .store
                .bind_workspace_identity(&child_id, &identity)
                .await?;
            // 远端 lease 的仓库根与 worktree 路径必须记录为 POSIX：会话工作区根、workspace
            // 打开参数与 git 路径参数都从该记录派生，宿主分隔符不得进入 durable 事实。
            let repository_root_text = workspace_path_text(&repository_root, remote)?;
            let mut durable = WorktreeLease {
                revision: 1,
                state: WorktreeLeaseState::Prepared,
                owner_kind: WorktreeLeaseOwnerKind::Child,
                owner_thread_id: child_id.clone(),
                root_thread_id: request.root_thread_id.to_owned(),
                workspace_id: request.project.id.clone(),
                ssh_alias: request.project.ssh_alias.clone(),
                repository_root: repository_root_text.clone(),
                path: workspace_path_text(&path, remote)?,
                base_commit: base_commit.clone(),
            };
            let current = super::worktree_lease::resolve_physical_workspace(
                ssh_manager,
                request.project,
                &caller_root,
            )
            .await?;
            if current != caller || manager.clean_spawn_head(&caller_root).await? != base_commit {
                return Err(lifecycle_error(
                    "caller execution identity or HEAD changed before worktree creation",
                ));
            }
            worktrees.record_durable(durable.clone()).await?;
            worktrees.preserve_workspace_resources(&child_id, identity);
            let handle = create_prepared_worktree(
                worktrees,
                &manager,
                &durable,
                WorktreeCreateSpec {
                    repo_root: repository_root.clone(),
                    root_thread_id: request.root_thread_id.to_owned(),
                    ownership,
                    base_commit: base_commit.clone(),
                },
            )
            .await?;
            let handle_path_text = workspace_path_text(&handle.path, remote)?;
            durable.path = handle_path_text.clone();

            (
                AgentWorkspaceAssignmentSnapshot {
                    mode,
                    project_root: project_root_text,
                    root: handle_path_text.clone(),
                    writable_paths: None,
                    worktree: Some(AgentWorktreeSnapshot {
                        repository_root: repository_root_text,
                        path: handle_path_text,
                        base_commit,
                    }),
                    review_target: None,
                },
                Some(PreparedWorktree { lease: durable }),
            )
        }
    };

    if mode != AgentWorkspaceMode::Worktree {
        let identity = super::worktree_lease::resolve_physical_workspace(
            ssh_manager,
            request.project,
            Path::new(&assignment.root),
        )
        .await?;
        worktrees.assign_workspace(request.usage, identity.clone())?;
        request
            .store
            .bind_thread_preparation(&child_id, &identity)
            .await?;
        request
            .store
            .bind_workspace_identity(&child_id, &identity)
            .await?;
    }
    Ok((assignment, lease))
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
                .map_err(anyhow::Error::from)
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
    if let Some(identity) = store.workspace_identity(&lease.owner_thread_id).await?
        && (endpoint != identity.endpoint || !identity.matches_root(&lease.path))
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
            identity.matches_root(&lease.path)
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
    let repository_root =
        WorktreeManager::resolve_repository_root(resolver.as_ref(), project_root).await?;
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

pub(in crate::studio) async fn create_root_session_worktree<F>(
    store: &crate::studio::StudioStore,
    worktrees: &WorktreeLeaseOwner,
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    project: &WorkspaceRecord,
    thread_id: &str,
    progress: &F,
) -> Result<WorktreeLease>
where
    F: Fn(pl_protocol::studio::ThreadPreparationStage, Option<&str>, Option<&str>) + Send + Sync,
{
    use pl_protocol::studio::ThreadPreparationStage;
    store
        .begin_thread_preparation(
            crate::studio::store::thread_preparation::PreparationIdentity {
                thread_id: thread_id.into(),
                workspace_id: project.id.clone(),
                parent_id: None,
                root_id: thread_id.into(),
            },
        )
        .await?;
    let usage = worktrees
        .reserve_project_workspace(thread_id, ssh_manager, project)
        .await?;
    progress(ThreadPreparationStage::ResolvingRepository, None, None);
    let project_root = resolved_project_root(project)?;
    let (repository_root, manager, endpoint) =
        repository_manager(ssh_manager, project.ssh_alias.as_deref(), &project_root)
            .await
            .map_err(|error| {
                error.context(pl_protocol::studio::StudioError::new(
                    pl_protocol::studio::StudioErrorCode::Unavailable,
                    "Could not resolve the project's Git repository. Check that the project is inside a Git repository and the repository is accessible.",
                    false,
                ))
            })?;
    let base_commit = manager
        .resolve_head(&repository_root)
        .await
        .map_err(|error| {
            anyhow::Error::from(error).context(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Unavailable,
                "Could not resolve the repository's HEAD. Check that the repository has a commit and is accessible.",
                false,
            ))
        })?;
    let ownership = WorktreeOwnership::Session {
        thread_id: thread_id.to_owned(),
    };
    let path = WorktreeManager::allocate_path(&repository_root, thread_id, &ownership);

    // 远端项目的 durable lease 记录 POSIX 形式；本地项目保留宿主形态。
    let remote = project.ssh_alias.is_some();
    anyhow::ensure!(
        worktrees.get(thread_id).is_none(),
        "root creation cannot replace an existing lease or rebuild an archived checkout"
    );
    let revision = 1;
    let durable = WorktreeLease {
        revision,
        state: WorktreeLeaseState::Prepared,
        owner_kind: WorktreeLeaseOwnerKind::Session,
        owner_thread_id: thread_id.to_owned(),
        root_thread_id: thread_id.to_owned(),
        workspace_id: project.id.clone(),
        ssh_alias: project.ssh_alias.clone(),
        repository_root: workspace_path_text(&repository_root, remote)?,
        path: workspace_path_text(&path, remote)?,
        base_commit: base_commit.clone(),
    };
    let identity = WorkspaceIdentity::canonical(endpoint, durable.path.clone())?;
    worktrees.assign_workspace(&usage, identity.clone())?;
    store.bind_thread_preparation(thread_id, &identity).await?;
    store.bind_workspace_identity(thread_id, &identity).await?;
    prepare_repository_worktree_pool(
        ssh_manager,
        project.ssh_alias.as_deref(),
        &repository_root,
        &identity.endpoint,
    )
    .await?;
    worktrees.record_durable(durable.clone()).await?;
    worktrees.preserve_workspace_resources(thread_id, identity);
    progress(
        ThreadPreparationStage::CreatingWorktree,
        Some(&durable.path),
        None,
    );
    let handle = match create_prepared_worktree(
        worktrees,
        &manager,
        &durable,
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
            return Err(error.context(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Unavailable,
                "Git could not create or check out the session worktree. Check repository permissions and available disk space.",
                false,
            )));
        }
    };
    if !workspace_paths_equal(&handle.path, &path, remote)? {
        let mut retained = durable;
        retained.transition(WorktreeLeaseState::Preserved);
        worktrees.record_durable(retained).await?;
        return Err(WorktreeError::IdentityMismatch(
            "created root path differs from its original allocation".into(),
        )
        .into());
    }
    Ok(durable)
}

/// All removal entries retain the same durable sequence: ownership/intent → Git → result.
/// The caller owns its lifecycle/agent operation until this entire sequence settles.
pub(in crate::studio) async fn cleanup_workspace(
    store: &crate::studio::StudioStore,
    leases: &WorktreeLeaseOwner,
    manager: &WorktreeManager,
    mut lease: WorktreeLease,
    policy: WorktreeCleanupPolicy,
) -> Result<()> {
    anyhow::ensure!(
        store.agent_close(&lease.owner_thread_id).await?.is_none(),
        "closed child worktrees belong to their durable close owner, not generic Recovery cleanup"
    );
    lease.validate_identity()?;
    let identity = cleanup_identity(store, &lease).await?;
    let removal = leases.begin_workspace_cleanup(&lease.owner_thread_id, &identity, None)?;
    let handle = WorktreeHandle {
        path: lease.path.clone().into(),
        base_commit: lease.base_commit.clone(),
    };
    if lease.state == WorktreeLeaseState::Cleaned {
        let (site, registered) = manager.child_cleanup_site(&handle).await?;
        anyhow::ensure!(
            site.is_none() && !registered,
            "terminal cleanup refuses a replacement checkout or registration"
        );
        leases.record_durable(lease).await?;
        removal.complete();
        return Ok(());
    }
    lease.transition(WorktreeLeaseState::CleanupRequested);
    leases.record_durable(lease.clone()).await?;
    if let Err(error) = manager.cleanup(&handle, policy).await {
        lease.transition(WorktreeLeaseState::Preserved);
        leases.record_durable(lease).await?;
        return Err(error.into());
    }
    lease.transition(WorktreeLeaseState::Cleaned);
    leases.record_durable(lease).await?;
    removal.complete();
    Ok(())
}

/// A failure result is not proof that this operation created the path. Retain uncertain facts;
/// neither this helper nor unpublished cleanup removes a possible pre-existing checkout.
async fn create_prepared_worktree(
    worktrees: &WorktreeLeaseOwner,
    manager: &WorktreeManager,
    lease: &WorktreeLease,
    spec: WorktreeCreateSpec,
) -> Result<WorktreeHandle> {
    match manager.create(spec).await {
        Ok(handle) => Ok(handle),
        Err(failure) => {
            let mut retained = lease.clone();
            retained.transition(match failure.disposition() {
                WorktreeCreateFailureDisposition::NoSideEffects => WorktreeLeaseState::Cleaned,
                WorktreeCreateFailureDisposition::MayHaveCreated => WorktreeLeaseState::Preserved,
            });
            worktrees
                .record_durable(retained)
                .await
                .context("save actual creation failure disposition")?;
            Err(failure.into())
        }
    }
}

/// Resolves the actual root session site without changing its binding or rebuilding a checkout.
/// Local sessions use the caller's actual session directory (including an already-bound bot M),
/// while worktree sessions require their original Session lease and physical identity.
pub(in crate::studio) async fn root_session_workspace_root(
    store: &crate::studio::StudioStore,
    worktrees: &WorktreeLeaseOwner,
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    root: &crate::studio::ThreadRecord,
    project: &WorkspaceRecord,
    local_root: PathBuf,
) -> Result<PathBuf> {
    anyhow::ensure!(
        root.parent_thread_id.is_none()
            && root.id == root.root_thread_id
            && root.workspace_id == project.id,
        WorktreeError::IdentityMismatch("root/project: session association changed".into())
    );
    let frozen = store.workspace_identity(&root.id).await?;
    anyhow::ensure!(
        project.kind != pl_protocol::studio::WorkspaceKind::Standalone
            || (root.workspace_mode == pl_protocol::ThreadWorkspaceMode::Local
                && project.ssh_alias.is_none()),
        "standalone sessions only support local workspaces"
    );
    if root.workspace_mode == pl_protocol::ThreadWorkspaceMode::Local {
        let actual =
            super::worktree_lease::resolve_physical_workspace(ssh_manager, project, &local_root)
                .await?;
        anyhow::ensure!(
            frozen.as_ref().is_none_or(|identity| *identity == actual),
            WorktreeError::IdentityMismatch("local root path or endpoint changed".into())
        );
        return Ok(PathBuf::from(actual.root));
    }
    let lease = worktrees.get(&root.id).ok_or_else(|| {
        WorktreeError::IdentityMismatch("owner: root session lease is missing".into())
    })?;
    lease.validate_identity()?;
    anyhow::ensure!(
        lease.owner_kind == WorktreeLeaseOwnerKind::Session
            && lease.owner_thread_id == root.id
            && lease.root_thread_id == root.id
            && lease.workspace_id == project.id
            && lease.ssh_alias == project.ssh_alias
            && workspace_paths_equal(
                Path::new(&root.workspace_path),
                Path::new(&lease.path),
                project.ssh_alias.is_some(),
            )?
            && !matches!(
                lease.state,
                WorktreeLeaseState::Cleaned | WorktreeLeaseState::CleanupRequested
            ),
        WorktreeError::IdentityMismatch(
            "owner/root/project/remote target or lease state differs from the root session".into()
        )
    );
    let frozen = frozen.ok_or_else(|| {
        WorktreeError::IdentityMismatch("root worktree has no frozen physical identity".into())
    })?;
    anyhow::ensure!(
        frozen.matches_root(&lease.path),
        WorktreeError::IdentityMismatch(
            "root worktree path differs from its frozen identity".into()
        )
    );
    // Checks the currently configured transport against the frozen endpoint before Git I/O.
    let manager = manager_from_lease(store, ssh_manager, &lease).await?;
    let (repository_root, _, endpoint) = repository_manager(
        ssh_manager,
        project.ssh_alias.as_deref(),
        &resolved_project_root(project)?,
    )
    .await?;
    anyhow::ensure!(
        endpoint == frozen.endpoint
            && workspace_paths_equal(
                &repository_root,
                Path::new(&lease.repository_root),
                project.ssh_alias.is_some(),
            )?,
        WorktreeError::IdentityMismatch(
            "repository/endpoint: session lease differs from its frozen binding".into()
        )
    );
    let actual = super::worktree_lease::resolve_physical_workspace(
        ssh_manager,
        project,
        Path::new(&lease.path),
    )
    .await?;
    anyhow::ensure!(
        actual == frozen,
        WorktreeError::IdentityMismatch("root worktree canonical path or endpoint changed".into())
    );
    manager
        .verify(&WorktreeHandle {
            path: PathBuf::from(&lease.path),
            base_commit: lease.base_commit,
        })
        .await?;
    Ok(PathBuf::from(lease.path))
}

pub(in crate::studio) fn validate_root_session_lease(
    lease: &WorktreeLease,
    project: &WorkspaceRecord,
    root_thread_id: &str,
) -> std::result::Result<(), WorktreeError> {
    lease.validate_identity()?;
    if lease.owner_kind != WorktreeLeaseOwnerKind::Session
        || lease.owner_thread_id != root_thread_id
        || lease.workspace_id != project.id
        || lease.ssh_alias != project.ssh_alias
        || matches!(
            lease.state,
            WorktreeLeaseState::Cleaned | WorktreeLeaseState::CleanupRequested
        )
    {
        return Err(WorktreeError::IdentityMismatch(
            "owner/project/remote target differs from the root lease".into(),
        ));
    }
    Ok(())
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
                .await?;
            if WorkspaceEndpoint::from_profile(Some(&host.profile)) != *expected_endpoint
                || host.files.canonical_path() != workspace_path_text(repository_root, true)?
            {
                return Err(lifecycle_error(
                    "worktree pool endpoint or canonical repository changed before preparation",
                ));
            }
            pl_tool::workspace::prepare_worktree_pool(&host.files)
                .await
                .map_err(anyhow::Error::from)
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
            .await?;
            pl_tool::workspace::prepare_worktree_pool(&backend)
                .await
                .map_err(anyhow::Error::from)
        }
    }
}

pub(in crate::studio) fn resolved_project_root(project: &WorkspaceRecord) -> Result<PathBuf> {
    if project.ssh_alias.is_some() {
        let value = pl_tool::remote::normalize_remote_absolute_path(project.path.trim())?;
        if value == "/" {
            return Err(lifecycle_error(format!(
                "invalid remote project workspace: {}",
                project.path
            )));
        }
        Ok(PathBuf::from(value))
    } else {
        pl_tool::workspace::resolve_workspace_root(&PathBuf::from(&project.path))
            .map_err(anyhow::Error::from)
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
            .map_err(anyhow::Error::from)
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

fn lifecycle_error(error: impl Into<String>) -> anyhow::Error {
    WorktreeError::InvalidResource(error.into()).into()
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
