//! Read-only review admission consumes the execution binding and the existing disk owner.
use super::{StudioThreadFactory, tool_bindings::ToolBinding};
use crate::{AgentWorkspaceAssignmentSnapshot, AgentWorkspaceMode, ThreadWorkspaceMode};
use crate::{
    agent::worktree::{
        ExecutorWorktreeBackend, WorktreeBackend, WorktreeError, WorktreeHandle, WorktreeManager,
    },
    studio::{
        ThreadRecord, WorkspaceRecord,
        agent_host::worktree_lease::{WorktreeLease, WorktreeLeaseState},
    },
    thread_assembler::ThreadAssemblyError,
};
use std::{
    path::{Path, PathBuf},
    sync::Arc,
};

#[derive(Debug, thiserror::Error)]
pub(crate) enum ReviewWorkspaceError {
    #[error("review workspace is invalid: {0}")]
    Invalid(&'static str),
    #[error("review workspace check is unconfirmed: {0}")]
    Unconfirmed(&'static str),
    #[error("review workspace declaration/owner could not be read")]
    Assembly(#[from] ThreadAssemblyError),
    #[error("review worktree verification failed")]
    Worktree(#[source] Box<WorktreeError>),
    #[error("review SSH workspace verification failed")]
    Remote(#[from] pl_tool::remote::SshError),
    #[error("review workspace filesystem verification failed")]
    Io(#[from] std::io::Error),
}

impl ReviewWorkspaceError {
    pub(crate) fn is_unconfirmed(&self) -> bool {
        match self {
            Self::Invalid(_) => false,
            Self::Assembly(
                ThreadAssemblyError::Identity(_)
                | ThreadAssemblyError::Workspace { .. }
                | ThreadAssemblyError::ReviewTargetInvalid(_)
                | ThreadAssemblyError::Closed
                | ThreadAssemblyError::InvalidatedBinding(_),
            ) => false,
            Self::Unconfirmed(_) | Self::Assembly(_) => true,
            Self::Io(error) => error.kind() != std::io::ErrorKind::NotFound,
            Self::Remote(error) => !error.is_not_found(),
            Self::Worktree(error) => match error.as_ref() {
                WorktreeError::Missing
                | WorktreeError::IdentityMismatch(_)
                | WorktreeError::InvalidResource(_) => false,
                WorktreeError::Target { source, .. } => !source.is_not_found(),
                _ => true,
            },
        }
    }
}

impl From<WorktreeError> for ReviewWorkspaceError {
    fn from(error: WorktreeError) -> Self {
        Self::Worktree(Box::new(error))
    }
}

/// Existing lifetime permit only; this does not register a new borrow or lock the filesystem.
pub(crate) struct ReviewWorkspaceCheck {
    factory: StudioThreadFactory,
    target: String,
    binding: ToolBinding,
    root_binding: Option<(String, ToolBinding)>,
    lease: Option<WorktreeLease>,
    root: String,
    _permit: tokio::sync::OwnedMutexGuard<()>,
}

impl ReviewWorkspaceCheck {
    pub(crate) fn target(&self) -> &str {
        &self.target
    }
    pub(crate) async fn confirm(&self) -> Result<(), ReviewWorkspaceError> {
        self.recheck()?;
        let binding = &self.binding;
        super::tool_bindings::ensure_frozen_ssh_profile(
            &self.factory.services.ssh_manager,
            binding.ssh_profile.as_ref(),
        )
        .await?;
        if let Some(alias) = &binding.project.ssh_alias {
            let frozen = &binding
                .remote
                .as_ref()
                .ok_or(ReviewWorkspaceError::Unconfirmed(
                    "SSH execution connection is unavailable",
                ))?
                .files();
            self.factory
                .services
                .ssh_manager
                .open_workspace_binding_on_connection(alias, frozen, self.root.clone())
                .await?;
        }
        self.recheck()
    }
    pub(crate) fn recheck(&self) -> Result<(), ReviewWorkspaceError> {
        let bindings = self.factory.binding_snapshots();
        let current = bindings
            .get(&self.target)
            .ok_or(ReviewWorkspaceError::Unconfirmed(
                "execution binding disappeared",
            ))?;
        check_generation(current, &self.binding)?;
        if let Some((id, expected)) = &self.root_binding {
            check_generation(
                bindings.get(id).ok_or(ReviewWorkspaceError::Unconfirmed(
                    "root execution binding disappeared",
                ))?,
                expected,
            )?;
        }
        drop(bindings);
        if let Some(lease) = &self.lease
            && self
                .factory
                .services
                .worktrees
                .get(&lease.owner_thread_id)
                .as_ref()
                != Some(lease)
        {
            return Err(ReviewWorkspaceError::Invalid(
                "worktree ownership changed during verification",
            ));
        }
        Ok(())
    }
}

fn check_generation(
    current: &ToolBinding,
    expected: &ToolBinding,
) -> Result<(), ReviewWorkspaceError> {
    if !Arc::ptr_eq(&current.incarnation, &expected.incarnation)
        || !Arc::ptr_eq(&current.lifetime, &expected.lifetime)
        || current.lifetime.cancellation.is_cancelled()
        || current.lifetime.target_invalidated()
        || !current.authorization.is_active()
    {
        return Err(ReviewWorkspaceError::Unconfirmed(
            "execution binding was replaced, cancelled or invalidated",
        ));
    }
    Ok(())
}

impl StudioThreadFactory {
    /// All three review admission boundaries use this same read-only owner/physical verification.
    pub(crate) async fn verify_review_workspace(
        &self,
        id: &str,
        assignment: &AgentWorkspaceAssignmentSnapshot,
    ) -> Result<ReviewWorkspaceCheck, ReviewWorkspaceError> {
        let binding =
            self.binding_snapshots()
                .get(id)
                .cloned()
                .ok_or(ReviewWorkspaceError::Unconfirmed(
                    "review target has no current tool owner",
                ))?;
        let permit = binding.lifetime.gate.clone().lock_owned().await;
        let mut check = ReviewWorkspaceCheck {
            factory: self.clone(),
            target: id.into(),
            binding,
            root_binding: None,
            lease: None,
            root: assignment.root.clone(),
            _permit: permit,
        };
        check.recheck()?;
        let target = self.thread_record(id).await?;
        let root = self.directory_member(&target.root_thread_id)?;
        let binding = &check.binding;
        let remote = binding.project.ssh_alias.is_some();
        if binding.project.id != target.workspace_id
            || !same_workspace_path(
                &assignment.root,
                &binding.workspace.root().to_string_lossy(),
                remote,
            )
            || !same_workspace_path(
                &assignment.project_root,
                &binding
                    .workspace
                    .workspace()
                    .project_root()
                    .to_string_lossy(),
                remote,
            )
        {
            return Err(ReviewWorkspaceError::Invalid(
                "frozen assignment differs from the live execution binding",
            ));
        }
        if remote
            && (binding.remote.is_none()
                || binding
                    .ssh_profile
                    .as_ref()
                    .map(|profile| profile.alias.as_str())
                    != binding.project.ssh_alias.as_deref())
        {
            return Err(ReviewWorkspaceError::Unconfirmed(
                "SSH execution binding has no matching frozen connection/profile",
            ));
        }
        let project = binding.project.clone();
        let mut owner = target.clone();
        let mut declared = assignment.clone();
        let mut visited = std::collections::BTreeSet::new();
        // Resolve the Project's repository only through the confirmed frozen binding.
        check.confirm().await?;
        let worktree = loop {
            if !visited.insert(owner.id.clone()) {
                return Err(ReviewWorkspaceError::Invalid(
                    "review target ownership chain contains a cycle",
                ));
            }
            match declared.mode {
                AgentWorkspaceMode::Review => {
                    let next =
                        declared
                            .review_target
                            .as_ref()
                            .ok_or(ReviewWorkspaceError::Invalid(
                                "review workspace has no bound target",
                            ))?;
                    let next_owner = self.thread_record(&next.agent_id).await?;
                    if next_owner.parent_thread_id != owner.parent_thread_id
                        || next_owner.root_thread_id != target.root_thread_id
                        || next_owner.workspace_id != project.id
                    {
                        return Err(ReviewWorkspaceError::Invalid(
                            "review target ownership chain leaves its parent/root/project",
                        ));
                    }
                    let next_assignment = self
                        .binding_snapshots()
                        .get(&next.agent_id)
                        .and_then(|binding| binding.assignment.clone())
                        .ok_or(ReviewWorkspaceError::Unconfirmed(
                            "review owner has no current workspace binding",
                        ))?;
                    if !same_workspace_path(
                        &declared.root,
                        &next_assignment.root,
                        project.ssh_alias.is_some(),
                    ) || declared.worktree != next_assignment.worktree
                        || declared.project_root != next_assignment.project_root
                    {
                        return Err(ReviewWorkspaceError::Invalid(
                            "review borrowed workspace differs from its actual target",
                        ));
                    }
                    owner = next_owner;
                    declared = next_assignment;
                }
                AgentWorkspaceMode::Directory | AgentWorkspaceMode::Unrestricted => {
                    if declared.worktree.is_some() {
                        return Err(ReviewWorkspaceError::Invalid(
                            "shared workspace cannot claim a child worktree receipt",
                        ));
                    }
                    if root.session.workspace_mode == ThreadWorkspaceMode::Worktree {
                        let lease = self.services.worktrees.get(&root.agent.thread_id).ok_or(
                            ReviewWorkspaceError::Invalid("shared root Session lease is missing"),
                        )?;
                        crate::studio::agent_host::workspace_preparation::validate_root_session_lease(&lease, &project, &root.agent.thread_id)?;
                        let (repository_root, repository) = self
                            .review_repository_manager(
                                &project,
                                Path::new(&declared.project_root),
                                Some(&check.binding),
                            )
                            .await?;
                        if !same_workspace_path(
                            &lease.path,
                            &declared.root,
                            project.ssh_alias.is_some(),
                        ) || !same_workspace_path(
                            &lease.repository_root,
                            &repository_root.to_string_lossy(),
                            project.ssh_alias.is_some(),
                        ) {
                            return Err(ReviewWorkspaceError::Invalid(
                                "shared workspace differs from its root Session lease",
                            ));
                        }
                        break Some((lease, repository));
                    } else {
                        check.root_binding = self
                            .binding_snapshots()
                            .get(&root.agent.thread_id)
                            .cloned()
                            .map(|binding| (root.agent.thread_id.clone(), binding));
                        let expected = check
                            .root_binding
                            .as_ref()
                            .map(|(_, binding)| binding.workspace.root().to_path_buf())
                            .unwrap_or_else(|| PathBuf::from(&project.path));
                        if !same_workspace_path(
                            &expected.to_string_lossy(),
                            &declared.root,
                            project.ssh_alias.is_some(),
                        ) {
                            return Err(ReviewWorkspaceError::Unconfirmed(
                                "shared root cannot be proven from its current execution binding",
                            ));
                        }
                    }
                    break None;
                }
                AgentWorkspaceMode::Worktree => {
                    let receipt =
                        declared
                            .worktree
                            .as_ref()
                            .ok_or(ReviewWorkspaceError::Invalid(
                                "owned worktree has no frozen receipt",
                            ))?;
                    let lease = self.services.worktrees.get(&owner.id).ok_or(
                        ReviewWorkspaceError::Invalid("owned Child lease is missing"),
                    )?;
                    lease.validate_identity()?;
                    if matches!(
                        lease.state,
                        WorktreeLeaseState::Cleaned | WorktreeLeaseState::CleanupRequested
                    ) {
                        return Err(ReviewWorkspaceError::Invalid(
                            "owned worktree is cleaned or being cleaned",
                        ));
                    }
                    let (repository_root, repository) = self
                        .review_repository_manager(
                            &project,
                            Path::new(&declared.project_root),
                            Some(&check.binding),
                        )
                        .await?;
                    verify_worktree_declarations(
                        &lease,
                        receipt,
                        &owner,
                        &project,
                        &repository_root,
                    )?;
                    if !same_workspace_path(
                        &receipt.path,
                        &declared.root,
                        project.ssh_alias.is_some(),
                    ) {
                        return Err(ReviewWorkspaceError::Invalid(
                            "owned worktree root differs from its receipt",
                        ));
                    }
                    break Some((lease, repository));
                }
            }
        };
        check.lease = worktree.as_ref().map(|(lease, _)| lease.clone());
        // Admission and final confirmation both use the same logical client/profile, without
        // connection establishment; the intervening physical probe cannot redirect the binding.
        check.confirm().await?;
        if let Some((lease, repository)) = worktree {
            repository
                .verify(&WorktreeHandle {
                    path: PathBuf::from(&lease.path),
                    base_commit: lease.base_commit.clone(),
                })
                .await?;
        } else if let Some(remote) = check.binding.remote.as_ref() {
            let stat = remote
                .files()
                .inspect_path(".".into(), None)
                .await
                .map_err(pl_tool::remote::SshError::from)?
                .ok_or(ReviewWorkspaceError::Invalid(
                    "frozen SSH workspace is missing",
                ))?;
            if !stat.is_dir
                || !same_workspace_path(remote.files().canonical_path(), &assignment.root, true)
            {
                return Err(ReviewWorkspaceError::Invalid(
                    "frozen SSH workspace is not the same canonical directory",
                ));
            }
        } else {
            let path = Path::new(&assignment.root);
            if !tokio::fs::metadata(path).await?.is_dir()
                || !same_workspace_path(
                    &tokio::fs::canonicalize(path).await?.to_string_lossy(),
                    &assignment.root,
                    false,
                )
            {
                return Err(ReviewWorkspaceError::Invalid(
                    "frozen local workspace is not the same canonical directory",
                ));
            }
        }
        check.confirm().await?;
        Ok(check)
    }

    /// Project and repository roots are distinct; derive both resolver and verifier backends
    /// from the same frozen logical connection, never from a lease's claimed repository.
    async fn review_repository_manager(
        &self,
        project: &WorkspaceRecord,
        project_root: &Path,
        binding: Option<&ToolBinding>,
    ) -> Result<(PathBuf, WorktreeManager), ReviewWorkspaceError> {
        let executor = match &project.ssh_alias {
            Some(_) => binding
                .and_then(|binding| binding.remote.as_ref())
                .ok_or(ReviewWorkspaceError::Unconfirmed(
                    "SSH execution binding disappeared",
                ))?
                .files()
                .executor()
                .clone(),
            None => self.services.local_executor.clone(),
        };
        let backend = |_root: &Path,
                       _canonical_repository: bool|
         -> Result<Arc<dyn WorktreeBackend>, ReviewWorkspaceError> {
            Ok(Arc::new(ExecutorWorktreeBackend::new(executor.clone())))
        };
        let resolver = backend(project_root, false)?;
        let repository_root =
            WorktreeManager::resolve_repository_root(resolver.as_ref(), project_root).await?;
        let repository =
            WorktreeManager::new(repository_root.clone(), backend(&repository_root, true)?);
        Ok((repository_root, repository))
    }
}

// Shared declaration rules are moved here from restore_child; restoration uses the same functions.
pub(super) fn verify_worktree_declarations(
    lease: &WorktreeLease,
    receipt: &crate::AgentWorktreeSnapshot,
    owner: &ThreadRecord,
    project: &WorkspaceRecord,
    repository_root: &Path,
) -> Result<(), WorktreeError> {
    use crate::studio::agent_host::worktree_lease::WorktreeLeaseOwnerKind;
    let mismatch = |reason: &str| WorktreeError::IdentityMismatch(reason.into());
    let remote = project.ssh_alias.is_some();
    if lease.owner_kind != WorktreeLeaseOwnerKind::Child || lease.owner_thread_id != owner.id {
        return Err(mismatch(
            "the saved worktree lease belongs to a different workspace owner",
        ));
    }
    if lease.root_thread_id != owner.root_thread_id {
        return Err(mismatch(
            "the saved worktree lease belongs to a different root session",
        ));
    }
    if lease.workspace_id != project.id {
        return Err(mismatch(
            "the saved worktree lease belongs to a different project",
        ));
    }
    if lease.ssh_alias != project.ssh_alias {
        return Err(mismatch(
            "the saved worktree lease runs on a different remote target",
        ));
    }
    if !same_workspace_path(
        &lease.repository_root,
        &repository_root.to_string_lossy(),
        remote,
    ) {
        return Err(mismatch(
            "the saved worktree lease is outside this project's repository",
        ));
    }
    if !same_workspace_path(&lease.repository_root, &receipt.repository_root, remote) {
        return Err(mismatch(
            "the saved lease and its receipt name different repositories",
        ));
    }
    if !same_workspace_path(&lease.path, &receipt.path, remote) {
        return Err(mismatch(
            "the saved lease and its receipt name different worktree paths",
        ));
    }
    if lease.base_commit != receipt.base_commit {
        return Err(mismatch(
            "the saved lease and its receipt were created from different base commits",
        ));
    }
    Ok(())
}

pub(super) fn same_workspace_path(left: &str, right: &str, remote: bool) -> bool {
    if remote {
        match (
            pl_tool::remote::normalize_remote_absolute_path(left),
            pl_tool::remote::normalize_remote_absolute_path(right),
        ) {
            (Ok(left), Ok(right)) => left == right,
            _ => false,
        }
    } else {
        dunce::simplified(Path::new(left)) == dunce::simplified(Path::new(right))
    }
}
