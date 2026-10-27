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

/// Durable caller authorization for one exact, stopped child workspace identity.
/// The product owner must separately prove lease ownership, no active borrowers and writer ACK.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorktreeRetirementRequest {
    pub delivery_target: PathBuf,
    pub expected_head: String,
    pub expected_common_dir: String,
    /// Only permits discarding dirty or not-yet-integrated content. Git locks remain binding.
    pub force: bool,
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

    /// Pins the caller's actual clean checkout before a child or branch is created.
    pub(crate) async fn clean_spawn_head(&self, path: &Path) -> Result<String, WorktreeError> {
        let head = self.backend.resolve_head(path).await?;
        let status = self.backend.status(path).await?;
        if !status.changed_files.is_empty() {
            return Err(WorktreeError::InvalidResource(
                "请先完成 commit，使工作区干净后重试（包括已暂存、未暂存及未跟踪文件）".into(),
            ));
        }
        if status.head != head {
            return Err(WorktreeError::InvalidResource(
                "工作区 HEAD 在准备期间发生变化，请重试".into(),
            ));
        }
        Ok(head)
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
        self.verify(&handle)
            .await
            .map_err(WorktreeCreateFailure::may_have_created)?;
        let created_head = self
            .backend
            .resolve_head(&handle.path)
            .await
            .map_err(WorktreeCreateFailure::may_have_created)?;
        if created_head != handle.base_commit {
            return Err(WorktreeCreateFailure::may_have_created(
                WorktreeError::IdentityMismatch(
                    "created worktree HEAD differs from the pinned base".into(),
                ),
            ));
        }
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

    pub(crate) async fn child_cleanup_site(
        &self,
        handle: &WorktreeHandle,
    ) -> Result<(Option<WorktreeStatus>, bool), WorktreeError> {
        let (exists, registered) = self.inspect_identity(handle).await?;
        Ok((
            if exists {
                Some(self.backend.status(&handle.path).await?)
            } else {
                None
            },
            registered,
        ))
    }

    pub(crate) async fn validate_child_delivery(
        &self,
        request: &WorktreeRetirementRequest,
    ) -> Result<(), WorktreeError> {
        if self.git_common_dir(&self.repo_root).await?.as_ref()
            != Some(&request.expected_common_dir)
            || self
                .git_common_dir(&request.delivery_target)
                .await?
                .as_ref()
                != Some(&request.expected_common_dir)
        {
            return Err(WorktreeError::IdentityMismatch(
                "close repository or actual delivery site changed".into(),
            ));
        }
        if !request.force {
            let delivered = self.backend.resolve_head(&request.delivery_target).await?;
            if !self
                .backend
                .is_ancestor(&self.repo_root, &request.expected_head, &delivered)
                .await?
            {
                return Err(WorktreeError::InvalidResource("child HEAD is not contained in the actual root delivery HEAD; integrate it or explicitly force close".into()));
            }
        }
        Ok(())
    }

    pub async fn retire_child(
        &self,
        handle: &WorktreeHandle,
        request: &WorktreeRetirementRequest,
    ) -> Result<(), WorktreeError> {
        self.validate_handle(handle)?;
        if handle
            .path
            .file_name()
            .is_some_and(|leaf| leaf == SESSION_WORKTREE_LEAF)
            || handle.path == request.delivery_target
            || !matches!(request.expected_head.len(), 40 | 64)
            || !request
                .expected_head
                .bytes()
                .all(|byte| byte.is_ascii_hexdigit())
            || request.expected_common_dir.is_empty()
        {
            return Err(WorktreeError::InvalidResource(
                "retirement requires one stopped child and a distinct delivery target".into(),
            ));
        }
        self.validate_child_delivery(request).await?;
        let (site, _) = self.child_cleanup_site(handle).await?;
        let site = site.ok_or_else(|| {
            WorktreeError::IdentityMismatch(
                "child disappeared before removal; registration preserved".into(),
            )
        })?;
        if site.head != request.expected_head {
            return Err(WorktreeError::IdentityMismatch(
                "child HEAD changed after the persisted deletion grant".into(),
            ));
        }
        if !request.force && !site.changed_files.is_empty() {
            return Err(WorktreeError::InvalidResource(
                "child has uncommitted or untracked changes; explicit force is required".into(),
            ));
        }
        self.backend
            .remove(&self.repo_root, &handle.path, request.force)
            .await?;
        self.verify_child_retired(handle, &request.expected_common_dir)
            .await
    }

    pub(crate) async fn verify_child_retired(
        &self,
        handle: &WorktreeHandle,
        common: &str,
    ) -> Result<(), WorktreeError> {
        if self.git_common_dir(&self.repo_root).await?.as_deref() != Some(common) {
            return Err(WorktreeError::IdentityMismatch(
                "retired repository identity changed".into(),
            ));
        }
        let (exists, registered) = self.inspect_identity(handle).await?;
        if exists || registered {
            return Err(WorktreeError::IdentityMismatch(
                "closed child path or exact registration is present; replacement preserved".into(),
            ));
        }
        Ok(())
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
            let status = self.backend.status(&handle.path).await?;
            if !status.changed_files.is_empty() || !status.ignored_files.is_empty() {
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
