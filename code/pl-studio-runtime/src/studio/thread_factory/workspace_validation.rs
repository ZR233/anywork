//! Read-only review admission consumes the execution binding and the existing disk owner.
use super::{StudioThreadFactory, tool_bindings::ToolBinding};
use crate::{
    agent::worktree::{
        LocalWorktreeBackend, RemoteWorktreeBackend, WorktreeBackend, WorktreeError,
        WorktreeHandle, WorktreeManager,
    },
    studio::{
        ProjectRecord, ThreadRecord,
        agent_host::worktree_lease::{
            WorkspaceEndpoint, WorkspaceIdentity, WorkspaceUsageLease, WorktreeLease,
            WorktreeLeaseState,
        },
    },
    thread_assembler::ThreadAssemblyError,
};
use pl_protocol::{AgentWorkspaceAssignmentSnapshot, AgentWorkspaceMode, ThreadWorkspaceMode};
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
    Remote(#[from] pl_tool::remote::RemoteClientError),
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
            Self::Remote(pl_tool::remote::RemoteClientError::Remote {
                code: pl_protocol::remote::RemoteErrorCode::PathNotFound,
                ..
            }) => false,
            Self::Remote(_) => true,
            Self::Worktree(error) => match error.as_ref() {
                WorktreeError::Missing
                | WorktreeError::IdentityMismatch(_)
                | WorktreeError::InvalidResource(_) => false,
                WorktreeError::LocalIo { source, .. } => {
                    source.kind() != std::io::ErrorKind::NotFound
                }
                WorktreeError::Remote {
                    source:
                        pl_tool::remote::RemoteClientError::Remote {
                            code: pl_protocol::remote::RemoteErrorCode::PathNotFound,
                            ..
                        },
                    ..
                } => false,
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
    binding: Option<ToolBinding>,
    root_binding: Option<(String, ToolBinding)>,
    lease: Option<WorktreeLease>,
    root: String,
    project: Option<ProjectRecord>,
    _usage: Option<WorkspaceUsageLease>,
    _permit: Option<tokio::sync::OwnedMutexGuard<()>>,
}

/// A local-only execution restoration permit. Construction is confined to the same verifier
/// that proved the original binding; it cannot manufacture an SSH execution capability.
pub(crate) struct VerifiedLocalResume {
    check: ReviewWorkspaceCheck,
    pub(super) project: ProjectRecord,
    pub(super) assignment: AgentWorkspaceAssignmentSnapshot,
    identity: WorkspaceIdentity,
}

impl std::fmt::Debug for VerifiedLocalResume {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("VerifiedLocalResume")
            .field("target", &self.check.target)
            .finish_non_exhaustive()
    }
}

impl VerifiedLocalResume {
    pub(super) fn identity(&self) -> WorkspaceIdentity {
        self.identity.clone()
    }
    pub(crate) fn usage(&self) -> WorkspaceUsageLease {
        self.check
            ._usage
            .as_ref()
            .expect("verified cold local use")
            .clone()
    }
    pub(super) fn recheck(&self) -> Result<(), ReviewWorkspaceError> {
        self.check.recheck()
    }
    pub(super) fn check_inputs(
        &self,
        project: &ProjectRecord,
        assignment: &AgentWorkspaceAssignmentSnapshot,
    ) -> Result<(), ReviewWorkspaceError> {
        if project.id != self.project.id
            || project.path != self.project.path
            || project.ssh_alias.is_some()
            || assignment != &self.assignment
        {
            return Err(ReviewWorkspaceError::Invalid(
                "restricted restoration inputs differ from the original proof",
            ));
        }
        self.recheck()
    }
    pub(super) fn confirm_published(&self) -> Result<(), ReviewWorkspaceError> {
        let bindings = self
            .check
            .factory
            .bindings
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let binding = bindings
            .get(&self.check.target)
            .ok_or(ReviewWorkspaceError::Unconfirmed(
                "restricted local binding was not published",
            ))?;
        if binding.project.ssh_alias.is_some()
            || binding.remote.is_some()
            || binding.assignment.as_ref() != Some(&self.assignment)
            || binding.workspace.root() != Path::new(&self.identity.root)
            || binding.lifetime.cancellation.is_cancelled()
            || binding.target_invalidated
        {
            return Err(ReviewWorkspaceError::Invalid(
                "new local binding differs from its original proof",
            ));
        }
        if let Some((id, expected)) = &self.check.root_binding {
            check_generation(
                bindings.get(id).ok_or(ReviewWorkspaceError::Unconfirmed(
                    "root binding disappeared",
                ))?,
                expected,
            )?;
        }
        drop(bindings);
        if let Some(lease) = &self.check.lease
            && self
                .check
                .factory
                .services
                .worktrees
                .get(&lease.owner_thread_id)
                .as_ref()
                != Some(lease)
        {
            return Err(ReviewWorkspaceError::Invalid(
                "original local lease changed",
            ));
        }
        Ok(())
    }
}

impl ReviewWorkspaceCheck {
    pub(crate) fn target(&self) -> &str {
        &self.target
    }
    pub(crate) async fn confirm(&self) -> Result<(), ReviewWorkspaceError> {
        self.recheck()?;
        if let Some(binding) = &self.binding {
            super::tool_bindings::ensure_frozen_ssh_profile(
                &self.factory.services.ssh_manager,
                binding.ssh_profile.as_ref(),
            )
            .await?;
        }
        if let Some(binding) = &self.binding
            && let Some(alias) = &binding.project.ssh_alias
        {
            let frozen = &binding
                .remote
                .as_ref()
                .ok_or(ReviewWorkspaceError::Unconfirmed(
                    "SSH execution connection is unavailable",
                ))?
                .files;
            self.factory
                .services
                .ssh_manager
                .open_workspace_host_on_connection(alias, frozen, self.root.clone())
                .await?;
        }
        self.recheck()
    }
    pub(crate) fn recheck(&self) -> Result<(), ReviewWorkspaceError> {
        if self.binding.is_some()
            && self
                .factory
                .tool_authority_invalidated(&self.target)
                .map_err(|error| {
                    super::errors::resource_error("read review workspace authority", error)
                })?
        {
            return Err(ReviewWorkspaceError::Unconfirmed(
                "execution workspace authority requires refresh",
            ));
        }
        let bindings = self
            .factory
            .bindings
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match (&self.binding, bindings.get(&self.target)) {
            (Some(expected), Some(current)) => check_generation(current, expected)?,
            (None, None) => {}
            _ => {
                return Err(ReviewWorkspaceError::Unconfirmed(
                    "execution binding changed during verification",
                ));
            }
        }
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
        || current.target_invalidated
    {
        return Err(ReviewWorkspaceError::Unconfirmed(
            "execution binding was replaced, cancelled or invalidated",
        ));
    }
    Ok(())
}

impl StudioThreadFactory {
    pub(crate) async fn verify_local_review_resume(
        &self,
        id: &str,
        assignment: &AgentWorkspaceAssignmentSnapshot,
    ) -> Result<VerifiedLocalResume, ReviewWorkspaceError> {
        let check = self.verify_review_workspace(id, assignment).await?;
        if check.binding.is_some() {
            return Err(ReviewWorkspaceError::Unconfirmed(
                "cold execution has no transferable original tool owner",
            ));
        }
        let record = self.thread_record(id).await?;
        let project = check
            .project
            .clone()
            .ok_or(ReviewWorkspaceError::Unconfirmed(
                "verified local project is unavailable",
            ))?;
        if project.ssh_alias.is_some() {
            return Err(ReviewWorkspaceError::Unconfirmed(
                "cold SSH execution has no original logical capability",
            ));
        }
        self.ensure_bot_execution_workspace(&record.clone().into(), None)
            .await?;
        super::session_files::verify_existing_session_files(Path::new(&assignment.root), id)
            .await?;
        check.confirm().await?;
        let identity =
            WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, assignment.root.clone())
                .map_err(|error| {
                    super::errors::resource_error("retain verified local identity", error)
                })?;
        Ok(VerifiedLocalResume {
            check,
            project,
            assignment: assignment.clone(),
            identity,
        })
    }
    /// All three review admission boundaries use this same read-only owner/physical verification.
    pub(crate) async fn verify_review_workspace(
        &self,
        id: &str,
        assignment: &AgentWorkspaceAssignmentSnapshot,
    ) -> Result<ReviewWorkspaceCheck, ReviewWorkspaceError> {
        let binding = self
            .bindings
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .cloned();
        let permit = match &binding {
            Some(binding) => Some(binding.lifetime.gate.clone().lock_owned().await),
            None => None,
        };
        let mut check = ReviewWorkspaceCheck {
            factory: self.clone(),
            target: id.into(),
            binding,
            root_binding: None,
            lease: None,
            root: assignment.root.clone(),
            project: None,
            _usage: None,
            _permit: permit,
        };
        check.recheck()?;
        let target = self.thread_record(id).await?;
        self.services
            .store
            .ensure_agent_execution_allowed(id)
            .await
            .map_err(|error| {
                super::errors::resource_error("review target execution seal", error)
            })?;
        let root = self.thread_record(&target.root_thread_id).await?;
        let project = match &check.binding {
            Some(binding) => {
                let remote = binding.project.ssh_alias.is_some();
                if binding.project.id != target.project_id
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
                binding.project.clone()
            }
            None => {
                let mut project = self.project_record(&target.project_id).await?;
                if let Some(bot) = self
                    .services
                    .bots
                    .config_for_thread(&target.root_thread_id)
                    .await
                    .map_err(|error| {
                        super::errors::resource_error("read existing bot physical binding", error)
                    })?
                {
                    self.ensure_bot_execution_workspace(&target.clone().into(), None)
                        .await?;
                    project.path = self
                        .services
                        .bots
                        .workspace_root(&bot)
                        .to_string_lossy()
                        .into_owned();
                    project.ssh_alias = None;
                }
                project
            }
        };
        check.project = Some(project.clone());
        if project.ssh_alias.is_some() && check.binding.is_none() {
            return Err(ReviewWorkspaceError::Unconfirmed(
                "cold SSH ownership verification cannot establish a connection",
            ));
        }
        let frozen = self
            .services
            .store
            .workspace_identity(id)
            .await
            .map_err(|error| super::errors::resource_error("read review physical binding", error))?
            .ok_or(ReviewWorkspaceError::Unconfirmed(
                "review target has no frozen physical identity",
            ))?;
        let endpoint = WorkspaceEndpoint::from_profile(
            check
                .binding
                .as_ref()
                .and_then(|binding| binding.remote.as_ref())
                .map(|remote| remote.profile.as_ref()),
        );
        let identity = WorkspaceIdentity::canonical(endpoint, assignment.root.clone())
            .map_err(|error| super::errors::resource_error("review physical identity", error))?;
        if frozen != identity {
            return Err(ReviewWorkspaceError::Invalid(
                "review target physical binding changed",
            ));
        }
        // A real use of the existing owner protects this verification, including cold local checks.
        // The live binding already carries a registered use; its clone remains in the guard.
        if check.binding.is_none() {
            let usage = self
                .services
                .worktrees
                .reserve_workspace(id, identity.endpoint.clone())
                .map_err(|error| {
                    super::errors::resource_error("reserve review physical check", error)
                })?;
            self.services
                .worktrees
                .assign_workspace(&usage, identity)
                .map_err(|error| {
                    super::errors::resource_error("bind review physical check", error)
                })?;
            check._usage = Some(usage);
        }
        if check.binding.is_none()
            && tokio::fs::canonicalize(&project.path).await? != Path::new(&assignment.project_root)
        {
            return Err(ReviewWorkspaceError::Unconfirmed(
                "cold Project root does not prove the frozen project binding",
            ));
        }
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
                        || next_owner.project_id != project.id
                    {
                        return Err(ReviewWorkspaceError::Invalid(
                            "review target ownership chain leaves its parent/root/project",
                        ));
                    }
                    let history =
                        self.services
                            .store
                            .history(&next.agent_id)
                            .await
                            .map_err(|error| {
                                super::errors::resource_error("read review owner history", error)
                            })?;
                    let (checkpoint, _) = history
                        .read_only_checkpoint_with_latest_turn()
                        .await
                        .map_err(|error| {
                            super::errors::resource_error("read canonical review owner", error)
                        })?
                        .ok_or(ReviewWorkspaceError::Unconfirmed(
                            "review target ownership chain has no canonical checkpoint",
                        ))?;
                    let next_assignment =
                        crate::studio::workspace_receipt::from_snapshot(&checkpoint.state)
                            .map_err(|error| {
                                super::errors::resource_error(
                                    "decode review owner assignment",
                                    error,
                                )
                            })?
                            .ok_or(ReviewWorkspaceError::Invalid(
                                "review target has no frozen assignment",
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
                    if root.workspace_mode == ThreadWorkspaceMode::Worktree {
                        let lease = self.services.worktrees.get(&root.id).ok_or(
                            ReviewWorkspaceError::Invalid("shared root Session lease is missing"),
                        )?;
                        crate::studio::agent_host::workspace_preparation::validate_root_session_lease(&lease, &project, &root.id)?;
                        let (repository_root, repository) = self
                            .review_repository_manager(
                                &project,
                                Path::new(&declared.project_root),
                                check.binding.as_ref(),
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
                            .bindings
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .get(&root.id)
                            .cloned()
                            .map(|binding| (root.id.clone(), binding));
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
                            check.binding.as_ref(),
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
        } else if let Some(remote) = check
            .binding
            .as_ref()
            .and_then(|binding| binding.remote.as_ref())
        {
            let stat = remote.files.stat_optional(".".into(), None).await?.ok_or(
                ReviewWorkspaceError::Invalid("frozen SSH workspace is missing"),
            )?;
            if !stat.is_dir
                || !same_workspace_path(remote.files.canonical_path(), &assignment.root, true)
            {
                return Err(ReviewWorkspaceError::Invalid(
                    "frozen SSH workspace is not the same canonical directory",
                ));
            }
        } else {
            let path = Path::new(&assignment.root);
            if !tokio::fs::metadata(path).await?.is_dir()
                || tokio::fs::canonicalize(path).await? != path
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
        project: &ProjectRecord,
        project_root: &Path,
        binding: Option<&ToolBinding>,
    ) -> Result<(PathBuf, WorktreeManager), ReviewWorkspaceError> {
        let backend = |root: &Path,
                       canonical_repository: bool|
         -> Result<Arc<dyn WorktreeBackend>, ReviewWorkspaceError> {
            match &project.ssh_alias {
                Some(_) => Ok(Arc::new(RemoteWorktreeBackend::from_frozen_connection(
                    self.services.ssh_manager.clone(),
                    binding
                        .and_then(|binding| binding.ssh_profile.clone())
                        .ok_or(ReviewWorkspaceError::Unconfirmed(
                            "SSH profile binding disappeared",
                        ))?,
                    root.to_path_buf(),
                    binding
                        .and_then(|binding| binding.remote.as_ref())
                        .ok_or(ReviewWorkspaceError::Unconfirmed(
                            "SSH execution binding disappeared",
                        ))?
                        .files
                        .clone(),
                    canonical_repository,
                )?)),
                None => Ok(Arc::new(LocalWorktreeBackend::default())),
            }
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
    receipt: &pl_protocol::AgentWorktreeSnapshot,
    owner: &ThreadRecord,
    project: &ProjectRecord,
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
    if lease.project_id != project.id {
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
        Path::new(left) == Path::new(right)
    }
}
