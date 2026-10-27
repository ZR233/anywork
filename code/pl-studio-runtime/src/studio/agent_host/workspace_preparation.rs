//! Product workspace allocation independent of Agent execution and model sessions.
use super::worktree_lease::{
    WorktreeLease, WorktreeLeaseOwner, WorktreeLeaseOwnerKind, WorktreeLeaseState,
};
use crate::agent::worktree::{
    LocalWorktreeBackend, RemoteWorktreeBackend, WorktreeBackend, WorktreeCleanupPolicy,
    WorktreeCreateFailureDisposition, WorktreeCreateSpec, WorktreeError, WorktreeHandle,
    WorktreeManager, WorktreeOwnership,
};
use crate::studio::records::ProjectRecord;
use anyhow::{Context, Result};
use pl_protocol::{AgentWorkspaceAssignmentSnapshot, AgentWorkspaceMode, AgentWorktreeSnapshot};
use std::{
    path::{Path, PathBuf},
    sync::Arc,
};

pub(in crate::studio) struct WorkspacePreparation<'a> {
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
    /// review Profile 的被审目标；产品层完成关系与可用性校验后传入。
    pub review_target: Option<ReviewWorkspaceTarget>,
}

/// review child 采用的被审目标工作区事实。
///
/// worktree 被审者的 lease 是 canonical 物理事实；非 worktree 被审者的工作区即会话
/// 工作区根，由 `prepare_workspace` 从 `session_root` 派生。
pub(in crate::studio) struct ReviewWorkspaceTarget {
    pub agent_id: String,
    /// 被审者的 worktree 收据；非 worktree 被审者为 `None`。
    pub worktree: Option<AgentWorktreeSnapshot>,
}

pub(in crate::studio) async fn prepare_workspace(
    worktrees: &WorktreeLeaseOwner,
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    request: WorkspacePreparation<'_>,
) -> Result<AgentWorkspaceAssignmentSnapshot> {
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

    let assignment = match mode {
        AgentWorkspaceMode::Unrestricted => AgentWorkspaceAssignmentSnapshot {
            mode,
            project_root: project_root_text,
            root: session_root_text,
            writable_paths: None,
            worktree: None,
            review_target: None,
        },
        AgentWorkspaceMode::Review => {
            let target = request.review_target.ok_or_else(|| {
                lifecycle_error("review workspace requires a reviewed agent workspace")
            })?;
            let (root, worktree) = match target.worktree {
                Some(worktree) => (worktree.path.clone(), Some(worktree)),
                None => (session_root_text.clone(), None),
            };
            AgentWorkspaceAssignmentSnapshot {
                mode,
                project_root: project_root_text,
                root,
                writable_paths: None,
                worktree,
                review_target: Some(pl_protocol::AgentReviewTargetSnapshot {
                    agent_id: target.agent_id,
                }),
            }
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
            AgentWorkspaceAssignmentSnapshot {
                mode,
                project_root: project_root_text,
                root: session_root_text,
                writable_paths,
                worktree: None,
                review_target: None,
            }
        }
        AgentWorkspaceMode::Worktree => {
            let durable = create_owned_worktree(
                worktrees,
                ssh_manager,
                OwnedWorktreeCreation {
                    project: request.project,
                    project_root: &project_root,
                    root_thread_id: request.root_thread_id,
                    ownership: WorktreeOwnership::Child { child_id },
                },
                &|_, _, _| {},
            )
            .await?;
            AgentWorkspaceAssignmentSnapshot {
                mode,
                project_root: project_root_text,
                root: durable.path.clone(),
                writable_paths: None,
                worktree: Some(AgentWorktreeSnapshot {
                    repository_root: durable.repository_root.clone(),
                    path: durable.path.clone(),
                    base_commit: durable.base_commit.clone(),
                }),
                review_target: None,
            }
        }
    };

    Ok(assignment)
}

pub(in crate::studio) fn backend_for(
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    ssh_alias: Option<&str>,
    project_root: &Path,
) -> Result<Arc<dyn WorktreeBackend>> {
    match ssh_alias {
        Some(server_id) => {
            RemoteWorktreeBackend::new(ssh_manager.clone(), server_id, project_root.to_path_buf())
                .map(|backend| Arc::new(backend) as Arc<dyn WorktreeBackend>)
                .map_err(anyhow::Error::from)
        }
        None => Ok(Arc::new(LocalWorktreeBackend::default())),
    }
}

pub(in crate::studio) fn manager_from_lease(
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    lease: &WorktreeLease,
) -> Result<WorktreeManager> {
    let repository_root = PathBuf::from(&lease.repository_root);
    Ok(WorktreeManager::new(
        repository_root.clone(),
        backend_for(ssh_manager, lease.ssh_alias.as_deref(), &repository_root)?,
    ))
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
) -> Result<(PathBuf, WorktreeManager)> {
    let resolver = backend_for(ssh_manager, ssh_alias, project_root)?;
    let repository_root = WorktreeManager::resolve_repository_root(resolver.as_ref(), project_root)
        .await
        .map_err(anyhow::Error::from)?;
    let backend = backend_for(ssh_manager, ssh_alias, &repository_root)?;
    Ok((
        repository_root.clone(),
        WorktreeManager::new(repository_root, backend),
    ))
}

/// Root and child creation share repository/base resolution, durable ownership and Git creation.
struct OwnedWorktreeCreation<'a> {
    project: &'a ProjectRecord,
    project_root: &'a Path,
    root_thread_id: &'a str,
    ownership: WorktreeOwnership,
}

async fn create_owned_worktree<F>(
    worktrees: &WorktreeLeaseOwner,
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    request: OwnedWorktreeCreation<'_>,
    progress: &F,
) -> Result<WorktreeLease>
where
    F: Fn(pl_protocol::studio::ThreadPreparationStage, Option<&str>, Option<&str>) + Send + Sync,
{
    use pl_protocol::studio::{StudioError, StudioErrorCode, ThreadPreparationStage};
    anyhow::ensure!(
        worktrees.get(request.ownership.owner_id()).is_none(),
        "an owned lease already exists; creation cannot replace its original site"
    );
    progress(ThreadPreparationStage::ResolvingRepository, None, None);
    let (repository_root, manager) = repository_manager(
        ssh_manager,
        request.project.ssh_alias.as_deref(),
        request.project_root,
    )
    .await
    .context(StudioError::new(
        StudioErrorCode::Unavailable,
        "Could not resolve the project's Git repository. Check repository access.",
        false,
    ))?;
    let base_commit = manager
        .resolve_head(&repository_root)
        .await
        .context(StudioError::new(
            StudioErrorCode::Unavailable,
            "Could not resolve the repository's HEAD. Check that it has an accessible commit.",
            false,
        ))?;
    let remote = request.project.ssh_alias.is_some();
    let path = WorktreeManager::allocate_path(
        &repository_root,
        request.root_thread_id,
        &request.ownership,
    );
    let mut lease = WorktreeLease {
        revision: 1,
        state: WorktreeLeaseState::Prepared,
        owner_kind: match &request.ownership {
            WorktreeOwnership::Session { .. } => WorktreeLeaseOwnerKind::Session,
            WorktreeOwnership::Child { .. } => WorktreeLeaseOwnerKind::Child,
        },
        owner_thread_id: request.ownership.owner_id().to_owned(),
        root_thread_id: request.root_thread_id.to_owned(),
        project_id: request.project.id.clone(),
        ssh_alias: request.project.ssh_alias.clone(),
        repository_root: workspace_path_text(&repository_root, remote)?,
        path: workspace_path_text(&path, remote)?,
        base_commit: base_commit.clone(),
    };
    prepare_repository_worktree_pool(
        ssh_manager,
        request.project.ssh_alias.as_deref(),
        &repository_root,
    )
    .await?;
    worktrees.record(lease.clone())?;
    if let Err(error) = worktrees.flush().await {
        // No Git command ran. Do not let unpublished cancellation infer a successful allocation
        // from the prepared fact when persistence itself failed.
        lease.transition(WorktreeLeaseState::Preserved);
        worktrees.record(lease)?;
        return Err(error.context("save prepared worktree ownership; creation was not attempted"));
    }
    progress(
        ThreadPreparationStage::CreatingWorktree,
        Some(&lease.path),
        None,
    );
    if let Err(failure) = manager
        .create(WorktreeCreateSpec {
            repo_root: repository_root,
            root_thread_id: request.root_thread_id.to_owned(),
            ownership: request.ownership,
            base_commit,
        })
        .await
    {
        // A failed spawned command may have left a registration or pre-existing conflicting leaf.
        // Preserve uncertain ownership rather than deleting a resource Git did not confirm creating.
        lease.transition(match failure.disposition() {
            WorktreeCreateFailureDisposition::NoSideEffects => WorktreeLeaseState::Cleaned,
            WorktreeCreateFailureDisposition::MayHaveCreated => WorktreeLeaseState::Preserved,
        });
        worktrees.record(lease)?;
        worktrees
            .flush()
            .await
            .context("settle failed worktree creation")?;
        return Err(anyhow::Error::new(failure).context(StudioError::new(
            StudioErrorCode::Unavailable,
            "Git could not create the managed worktree. Check conflicts, permissions and disk space.", false,
        )));
    }
    Ok(lease)
}

pub(in crate::studio) async fn create_root_session_worktree<F>(
    worktrees: &WorktreeLeaseOwner,
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    project: &ProjectRecord,
    thread_id: &str,
    progress: &F,
) -> Result<WorktreeLease>
where
    F: Fn(pl_protocol::studio::ThreadPreparationStage, Option<&str>, Option<&str>) + Send + Sync,
{
    let project_root = resolved_project_root(project)?;
    create_owned_worktree(
        worktrees,
        ssh_manager,
        OwnedWorktreeCreation {
            project,
            project_root: &project_root,
            root_thread_id: thread_id,
            ownership: WorktreeOwnership::Session {
                thread_id: thread_id.to_owned(),
            },
        },
        progress,
    )
    .await
}

/// All removal entries retain the same durable sequence: ownership/intent → Git → result.
/// The caller owns its lifecycle/agent operation until this entire sequence settles.
pub(in crate::studio) async fn cleanup_workspace(
    leases: &WorktreeLeaseOwner,
    manager: &WorktreeManager,
    mut lease: WorktreeLease,
    policy: WorktreeCleanupPolicy,
) -> Result<()> {
    lease.validate_identity()?;
    lease.transition(WorktreeLeaseState::CleanupRequested);
    leases.record(lease.clone())?;
    if let Err(error) = leases.flush().await {
        lease.transition(WorktreeLeaseState::Preserved);
        leases.record(lease)?;
        return Err(error.context("save worktree cleanup intent; no deletion attempted"));
    }
    let handle = WorktreeHandle {
        path: PathBuf::from(&lease.path),
        base_commit: lease.base_commit.clone(),
    };
    if let Err(error) = manager.cleanup(&handle, policy).await {
        lease.transition(WorktreeLeaseState::Preserved);
        leases.record(lease)?;
        leases
            .flush()
            .await
            .context("save failed worktree cleanup")?;
        return Err(error.into());
    }
    lease.transition(WorktreeLeaseState::Cleaned);
    leases.record(lease)?;
    leases.flush().await?;
    Ok(())
}

/// Preserve never opens or inspects Git. Cleanup carries explicit destructive authorization.
pub(in crate::studio) async fn close_workspace(
    leases: &WorktreeLeaseOwner,
    manager: &WorktreeManager,
    mut lease: WorktreeLease,
    disposition: pl_tool::collaboration::thread::AgentWorkspaceDisposition,
) -> Result<()> {
    use pl_tool::collaboration::thread::AgentWorkspaceDisposition;
    // Keep the existing close API's completed-resource semantics. A historical cleaned lease is
    // not authorization to remove another checkout that later appears at the same textual path.
    if lease.state == WorktreeLeaseState::Cleaned {
        return Ok(());
    }
    match disposition {
        AgentWorkspaceDisposition::Preserve => {
            if lease.state != WorktreeLeaseState::Preserved {
                lease.transition(WorktreeLeaseState::Preserved);
                leases.record(lease)?;
            }
            leases.flush().await
        }
        AgentWorkspaceDisposition::Cleanup => {
            cleanup_workspace(leases, manager, lease, WorktreeCleanupPolicy::Discard).await
        }
    }
}

/// Resolves the workspace root of a root session from its canonical product fact.
///
/// `local` uses the canonical Project root. `worktree` requires an identity-matching
/// reusable session lease; a missing, mismatched or cleaned lease fails explicitly and
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
            if matches!(
                lease.state,
                WorktreeLeaseState::Cleaned | WorktreeLeaseState::CleanupRequested
            ) {
                return Err(lifecycle_error(format!(
                    "Thread {root_thread_id} session worktree lease is {} and cannot be activated",
                    lease.state.label()
                )));
            }
            lease.validate_identity().map_err(anyhow::Error::from)?;
            Ok(PathBuf::from(&lease.path))
        }
    }
}

/// Execution admission verifies the root's original site against the current Project repository.
/// Unlike archive/restore this may perform I/O and must fail closed on an unprovable identity.
pub(in crate::studio) async fn verify_root_session_worktree(
    worktrees: &WorktreeLeaseOwner,
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    project: &ProjectRecord,
    root_thread_id: &str,
) -> Result<()> {
    let lease = worktrees.get(root_thread_id).ok_or_else(|| {
        WorktreeError::IdentityMismatch("owner: root session lease is missing".into())
    })?;
    lease.validate_identity().map_err(anyhow::Error::from)?;
    if lease.owner_kind != WorktreeLeaseOwnerKind::Session
        || lease.owner_thread_id != root_thread_id
        || lease.project_id != project.id
        || lease.ssh_alias != project.ssh_alias
        || matches!(
            lease.state,
            WorktreeLeaseState::Cleaned | WorktreeLeaseState::CleanupRequested
        )
    {
        return Err(WorktreeError::IdentityMismatch(
            "owner/project/remote target differs from the root lease".into(),
        )
        .into());
    }
    let (repository_root, repository) = repository_manager(
        ssh_manager,
        project.ssh_alias.as_deref(),
        &resolved_project_root(project)?,
    )
    .await?;
    if !workspace_paths_equal(
        &repository_root,
        Path::new(&lease.repository_root),
        project.ssh_alias.is_some(),
    )? {
        return Err(WorktreeError::IdentityMismatch(
            "repository: saved session lease belongs to another project repository".into(),
        )
        .into());
    }
    repository
        .verify(&WorktreeHandle {
            path: PathBuf::from(&lease.path),
            base_commit: lease.base_commit,
        })
        .await
        .map_err(anyhow::Error::from)?;
    Ok(())
}

async fn prepare_repository_worktree_pool(
    ssh_manager: &Arc<pl_tool::remote::SshManager>,
    ssh_alias: Option<&str>,
    repository_root: &Path,
) -> Result<()> {
    match ssh_alias {
        Some(server) => {
            let host = ssh_manager
                .open_workspace_host(server, workspace_path_text(repository_root, true)?)
                .await
                .map_err(anyhow::Error::from)?;
            pl_tool::workspace::prepare_worktree_pool(&host.files)
                .await
                .map_err(anyhow::Error::from)
        }
        None => {
            let backend = pl_tool::workspace_file::LocalWorkspaceFileBackend::new(
                repository_root.to_path_buf(),
                false,
            )
            .await
            .map_err(anyhow::Error::from)?;
            pl_tool::workspace::prepare_worktree_pool(&backend)
                .await
                .map_err(anyhow::Error::from)
        }
    }
}

pub(in crate::studio) fn resolved_project_root(project: &ProjectRecord) -> Result<PathBuf> {
    if project.ssh_alias.is_some() {
        let value = pl_tool::remote::normalize_remote_absolute_path(project.path.trim())
            .map_err(anyhow::Error::from)?;
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
