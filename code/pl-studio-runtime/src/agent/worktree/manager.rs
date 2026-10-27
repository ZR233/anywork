use std::path::{Path, PathBuf};
use std::sync::Arc;

use super::{WorktreeBackend, WorktreeCreateFailure, WorktreeError, WorktreeStatus};

const WORKTREE_DIR: &str = ".anywork/worktrees";
pub const SESSION_WORKTREE_LEAF: &str = "session";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorktreeHandle {
    pub path: PathBuf,
    /// Frozen creation provenance, not a constraint on the checkout's current HEAD.
    pub base_commit: String,
}

/// Stable ownership determines the managed leaf, never the mutable Git state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WorktreeOwnership {
    Session { thread_id: String },
    Child { child_id: String },
}

impl WorktreeOwnership {
    pub fn leaf(&self) -> &str {
        match self {
            Self::Session { .. } => SESSION_WORKTREE_LEAF,
            Self::Child { child_id } => child_id,
        }
    }

    pub fn owner_id(&self) -> &str {
        match self {
            Self::Session { thread_id } => thread_id,
            Self::Child { child_id } => child_id,
        }
    }
}

/// Authorization is supplied by the owning lifecycle entry, not inferred from Git state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorktreeCleanupPolicy {
    /// Independent Recovery cleanup must preserve all local content and requires a present site.
    Safe,
    /// An existing explicitly authorized cleanup may discard content, never bypassing Git locks.
    Discard,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorktreeCreateSpec {
    pub repo_root: PathBuf,
    pub root_thread_id: String,
    pub ownership: WorktreeOwnership,
    /// The caller's already resolved immutable commit. Creation forwards this value to Git and
    /// never chooses a Project/root checkout or resolves a mutable default branch itself.
    pub base_commit: String,
}

#[derive(Debug, Clone)]
pub struct WorktreeManager {
    repo_root: PathBuf,
    backend: Arc<dyn WorktreeBackend>,
}

impl WorktreeManager {
    pub fn new(repo_root: PathBuf, backend: Arc<dyn WorktreeBackend>) -> Self {
        Self { repo_root, backend }
    }

    pub async fn resolve_repository_root(
        backend: &dyn WorktreeBackend,
        project_path: &Path,
    ) -> Result<PathBuf, WorktreeError> {
        backend.resolve_repo_root(project_path).await
    }

    pub fn allocate_path(
        repo_root: &Path,
        root_thread_id: &str,
        ownership: &WorktreeOwnership,
    ) -> PathBuf {
        repo_root
            .join(WORKTREE_DIR)
            .join(safe_component(root_thread_id))
            .join(safe_component(ownership.leaf()))
    }

    pub async fn resolve_head(&self, path: &Path) -> Result<String, WorktreeError> {
        self.backend.resolve_head(path).await
    }

    pub(crate) async fn registered_worktrees(
        &self,
    ) -> Result<Vec<super::RegisteredWorktree>, WorktreeError> {
        Ok(super::backend::registered_worktrees(
            &self.backend.worktree_list(&self.repo_root).await?,
        ))
    }

    pub(crate) async fn git_common_dir(
        &self,
        path: &Path,
    ) -> Result<Option<String>, WorktreeError> {
        let raw = self.backend.git_common_dir(path).await?;
        Ok(super::backend::resolved_git_path(
            &raw,
            &path.to_string_lossy(),
        ))
    }

    /// Verifies physical repository/path identity without reading tracked, untracked or ignored files.
    pub async fn verify(&self, handle: &WorktreeHandle) -> Result<(), WorktreeError> {
        if !self.inspect_identity(handle).await?.0 {
            return Err(WorktreeError::Missing);
        }
        Ok(())
    }

    pub async fn preview(&self, handle: &WorktreeHandle) -> Result<WorktreeStatus, WorktreeError> {
        self.verify(handle).await?;
        self.backend.status(&handle.path).await
    }

    /// Git alone adjudicates creation conflicts. An uncertain failure retains cleanup ownership;
    /// the caller must not assume an error means no physical side effects occurred.
    pub async fn create(
        &self,
        spec: WorktreeCreateSpec,
    ) -> Result<WorktreeHandle, WorktreeCreateFailure> {
        if spec.repo_root != self.repo_root || spec.base_commit.trim().is_empty() {
            return Err(WorktreeCreateFailure::no_side_effects(
                WorktreeError::InvalidResource("repository or resolved base is invalid".into()),
            ));
        }
        let handle = WorktreeHandle {
            path: Self::allocate_path(&self.repo_root, &spec.root_thread_id, &spec.ownership),
            base_commit: spec.base_commit,
        };
        self.validate_handle(&handle)
            .map_err(WorktreeCreateFailure::no_side_effects)?;
        self.backend
            .create_parent(&self.repo_root, &handle.path)
            .await
            .map_err(WorktreeCreateFailure::no_side_effects)?;
        self.backend
            .create(&self.repo_root, &handle.path, &handle.base_commit)
            .await?;
        Ok(handle)
    }

    fn validate_handle(&self, handle: &WorktreeHandle) -> Result<(), WorktreeError> {
        let expected_root = self.repo_root.join(WORKTREE_DIR);
        if !handle.path.starts_with(&expected_root)
            || handle.path.components().count() != expected_root.components().count() + 2
        {
            return Err(WorktreeError::IdentityMismatch(
                "path is not an exact managed worktree leaf".into(),
            ));
        }
        Ok(())
    }

    /// Returns (checkout exists, registration exists). Missing checkouts may retain a Git
    /// registration; only explicit destructive authorization may reconcile that state.
    async fn inspect_identity(
        &self,
        handle: &WorktreeHandle,
    ) -> Result<(bool, bool), WorktreeError> {
        self.validate_handle(handle)?;
        let exists = self
            .backend
            .path_exists(&self.repo_root, &handle.path)
            .await?;
        let registered = self.registered_worktrees().await?;
        let target = super::backend::resolved_git_path(
            &handle.path.to_string_lossy(),
            &self.repo_root.to_string_lossy(),
        )
        .ok_or_else(|| {
            WorktreeError::IdentityMismatch("managed path cannot be normalized".into())
        })?;
        let registration = registered.iter().find(|entry| {
            super::backend::resolved_git_path(&entry.path, &self.repo_root.to_string_lossy())
                .as_deref()
                == Some(target.as_str())
        });
        if exists {
            if registration.is_none_or(|entry| entry.prunable) {
                return Err(WorktreeError::IdentityMismatch(
                    "registration does not name the existing managed checkout".into(),
                ));
            }
            let site = self.git_common_dir(&handle.path).await?;
            let repository = self.git_common_dir(&self.repo_root).await?;
            if site.is_none() || site != repository {
                return Err(WorktreeError::IdentityMismatch(
                    "repository common-dir differs from the owning repository".into(),
                ));
            }
            let common = site.ok_or_else(|| {
                WorktreeError::IdentityMismatch(
                    "repository common-dir could not be confirmed".into(),
                )
            })?;
            let backlink = self
                .backend
                .worktree_backlink(&handle.path, &common)
                .await?;
            if backlink != format!("{target}/.git") {
                return Err(WorktreeError::IdentityMismatch(
                    "registration admin backlink names another checkout".into(),
                ));
            }
        }
        Ok((exists, registration.is_some()))
    }

    /// The single physical removal boundary. No branch deletion, recursive filesystem fallback,
    /// double force or repository-wide prune is permitted. The caller durably owns cleanup intent.
    pub async fn cleanup(
        &self,
        handle: &WorktreeHandle,
        policy: WorktreeCleanupPolicy,
    ) -> Result<(), WorktreeError> {
        let (exists, registered) = self.inspect_identity(handle).await?;
        if policy == WorktreeCleanupPolicy::Safe {
            if !exists {
                return Err(WorktreeError::Missing);
            }
            if !self
                .backend
                .status(&handle.path)
                .await?
                .changed_files
                .is_empty()
            {
                return Err(WorktreeError::InvalidResource(
                    "cleanup refused tracked, untracked or ignored local content".into(),
                ));
            }
        }
        if exists || registered {
            self.backend
                .remove(
                    &self.repo_root,
                    &handle.path,
                    policy == WorktreeCleanupPolicy::Discard,
                )
                .await?;
            let (exists, registered) = self.inspect_identity(handle).await?;
            if exists || registered {
                return Err(WorktreeError::IdentityMismatch(
                    "Git removal left a checkout or registration; cleanup is incomplete".into(),
                ));
            }
        }
        Ok(())
    }
}

fn safe_component(raw: &str) -> String {
    let mut value = raw
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_') {
                character
            } else {
                '-'
            }
        })
        .collect::<String>();
    value.truncate(80);
    if value.trim_matches('-').is_empty() {
        "agent".into()
    } else {
        value
    }
}
