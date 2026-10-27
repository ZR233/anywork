use std::path::{Path, PathBuf};
use std::sync::Arc;

use super::{WorktreeBackend, WorktreeCreateFailureDisposition, WorktreeError, WorktreeStatus};

const WORKTREE_DIR: &str = ".anywork/worktrees";
const CHILD_BRANCH_PREFIX: &str = "pure-agent-";
const SESSION_BRANCH_PREFIX: &str = "pure-session-";
/// 根会话自身工作区使用的受控 leaf 名称。
pub const SESSION_WORKTREE_LEAF: &str = "session";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorktreeHandle {
    pub path: PathBuf,
    pub branch: String,
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

/// Pure-owned worktree 归属；路径 leaf 与分支名都由归属派生，不接受外部指定。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WorktreeOwnership {
    /// 根会话自身工作区：`<repo>/.anywork/worktrees/<root-thread-id>/session` 与
    /// `pure-session-<thread-id>`。
    Session { thread_id: String },
    /// 子智能体工作区：`<repo>/.anywork/worktrees/<root-thread-id>/<child-id>` 与
    /// `pure-agent-<child-id>`。
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

    pub fn branch(&self) -> String {
        match self {
            Self::Session { thread_id } => {
                format!("{SESSION_BRANCH_PREFIX}{}", safe_component(thread_id))
            }
            Self::Child { child_id } => {
                format!("{CHILD_BRANCH_PREFIX}{}", safe_component(child_id))
            }
        }
    }
}

/// Rejects any branch that is not a Pure-owned registration identity.
pub fn is_pure_branch(branch: &str) -> bool {
    branch.starts_with(CHILD_BRANCH_PREFIX) || branch.starts_with(SESSION_BRANCH_PREFIX)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorktreeCreateSpec {
    pub repo_root: PathBuf,
    pub root_thread_id: String,
    pub ownership: WorktreeOwnership,
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

    pub fn branch_for(ownership: &WorktreeOwnership) -> String {
        ownership.branch()
    }

    pub async fn resolve_head(&self, path: &Path) -> Result<String, WorktreeError> {
        self.backend.resolve_head(path).await
    }

    /// Pins the caller's actual clean checkout before a child or branch is created.
    pub(crate) async fn clean_spawn_head(&self, path: &Path) -> Result<String, WorktreeError> {
        let head = self.backend.resolve_head(path).await.map_err(|error| {
            WorktreeError::InvalidResource(format!(
                "工作区需要有效的初始 commit 才能派生工作树: {error}"
            ))
        })?;
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

    /// Exact path inspection; an absent path never authorizes removing a stale registration.
    pub(crate) async fn child_cleanup_site(
        &self,
        handle: &WorktreeHandle,
    ) -> Result<(Option<WorktreeStatus>, bool), WorktreeError> {
        self.validate_handle(handle)?;
        let base = self.repo_root.to_string_lossy();
        let key = super::backend::resolved_git_path(&handle.path.to_string_lossy(), &base)
            .ok_or_else(|| {
                WorktreeError::InvalidResource("unresolved child cleanup path".into())
            })?;
        let registered = self.registered_worktrees().await?;
        let registration = registered.iter().find(|entry| {
            super::backend::resolved_git_path(&entry.path, &base).as_ref() == Some(&key)
        });
        if registration.is_some_and(|entry| entry.branch.as_deref() != Some(handle.branch.as_str()))
        {
            return Err(WorktreeError::InvalidResource(
                "child worktree registration changed branch".into(),
            ));
        }
        let exists = self.backend.path_exists(&handle.path).await?;
        if !exists {
            return Ok((None, registration.is_some()));
        }
        self.validate_registered_site(&handle.path, &handle.branch)
            .await?;
        let status = self.backend.status(&handle.path).await?;
        if status.branch.as_deref() != Some(handle.branch.as_str()) {
            return Err(WorktreeError::InvalidResource(
                "child worktree branch changed".into(),
            ));
        }
        Ok((Some(status), true))
    }

    /// The worktrees this repository has registered, as Git itself reports them.
    ///
    /// This is how a directory proves it belongs to *this* repository: a directory at an expected
    /// path may exist, be a Git worktree of another repository, or not be a worktree at all, but only
    /// the resolved repository's own registration list names it as its worktree on a given branch.
    ///
    /// # Errors
    /// Rejects an unreadable or failed `git worktree list` in the repository.
    pub(crate) async fn registered_worktrees(
        &self,
    ) -> Result<Vec<super::RegisteredWorktree>, WorktreeError> {
        let stdout = self.backend.worktree_list(&self.repo_root).await?;
        Ok(super::backend::registered_worktrees(&stdout))
    }

    /// The Git directory shared by this repository and the given directory, resolved to one form.
    ///
    /// Equal answers prove both directories belong to the same repository; `None` means Git's answer
    /// cannot be normalized, so the caller must treat the identity as unproven.
    ///
    /// # Errors
    /// Rejects an unreadable or failed `git rev-parse --git-common-dir` in that directory.
    pub(crate) async fn git_common_dir(
        &self,
        path: &Path,
    ) -> Result<Option<String>, WorktreeError> {
        let raw = self.backend.git_common_dir(path).await?;
        let base = path.to_string_lossy();
        Ok(super::backend::resolved_git_path(&raw, &base))
    }

    /// Proves the saved path/branch belongs to this repository rather than merely existing.
    pub(crate) async fn validate_registered_site(
        &self,
        path: &Path,
        branch: &str,
    ) -> Result<(), WorktreeError> {
        let base = self.repo_root.to_string_lossy();
        let expected = super::backend::resolved_git_path(&path.to_string_lossy(), &base)
            .ok_or_else(|| WorktreeError::InvalidResource("unresolved worktree path".into()))?;
        let registered = self.registered_worktrees().await?;
        if !registered.iter().any(|entry| {
            !entry.prunable
                && entry.branch.as_deref() == Some(branch)
                && super::backend::resolved_git_path(&entry.path, &base).as_ref() == Some(&expected)
        }) {
            return Err(WorktreeError::InvalidResource(
                "repository does not register the saved worktree on its declared branch".into(),
            ));
        }
        let owner = self.git_common_dir(&self.repo_root).await?.ok_or_else(|| {
            WorktreeError::InvalidResource("repository Git identity cannot be resolved".into())
        })?;
        let site = self.git_common_dir(path).await?.ok_or_else(|| {
            WorktreeError::InvalidResource("worktree Git identity cannot be resolved".into())
        })?;
        if site != owner {
            return Err(WorktreeError::InvalidResource(
                "saved worktree belongs to another Git repository".into(),
            ));
        }
        Ok(())
    }

    pub async fn preview(&self, handle: &WorktreeHandle) -> Result<WorktreeStatus, WorktreeError> {
        self.validate_handle(handle)?;
        self.backend.status(&handle.path).await
    }

    /// Previews a remaining owned worktree while allowing cleanup retries after directory removal.
    ///
    /// # Errors
    /// Rejects invalid owned-leaf identity, failed existence checks and unreadable existing worktrees.
    pub async fn preview_existing(
        &self,
        handle: &WorktreeHandle,
    ) -> Result<Option<WorktreeStatus>, WorktreeError> {
        self.validate_handle(handle)?;
        if self.backend.path_exists(&handle.path).await? {
            self.backend.status(&handle.path).await.map(Some)
        } else {
            Ok(None)
        }
    }

    pub async fn create(&self, spec: WorktreeCreateSpec) -> Result<WorktreeHandle, WorktreeError> {
        if spec.repo_root != self.repo_root || spec.base_commit.trim().is_empty() {
            return Err(WorktreeError::InvalidResource(
                "worktree spawn spec has mismatched repository or empty base".to_string(),
            ));
        }
        let path = Self::allocate_path(&self.repo_root, &spec.root_thread_id, &spec.ownership);
        let branch = Self::branch_for(&spec.ownership);
        let expected_parent = self
            .repo_root
            .join(WORKTREE_DIR)
            .join(safe_component(&spec.root_thread_id));
        if path.parent() != Some(expected_parent.as_path()) {
            return Err(WorktreeError::InvalidResource(
                "worktree target is not an exact Pure-owned leaf".to_string(),
            ));
        }
        let handle = WorktreeHandle {
            path,
            branch,
            base_commit: spec.base_commit,
        };
        let base = self.repo_root.to_string_lossy();
        let path_key = super::backend::resolved_git_path(&handle.path.to_string_lossy(), &base)
            .ok_or_else(|| {
                WorktreeError::InvalidResource("unresolved creation worktree path".into())
            })?;
        if self.backend.path_exists(&handle.path).await?
            || self.registered_worktrees().await?.iter().any(|entry| {
                super::backend::resolved_git_path(&entry.path, &base).as_ref() == Some(&path_key)
                    || entry.branch.as_deref() == Some(handle.branch.as_str())
            })
            || self
                .backend
                .branch_head(&self.repo_root, &handle.branch)
                .await?
                .is_some()
        {
            return Err(WorktreeError::InvalidResource(
                "creation target or branch already exists; no existing resource was adopted".into(),
            ));
        }
        self.backend
            .create_parent(&self.repo_root, &handle.path)
            .await?;
        if let Err(failure) = self
            .backend
            .create(
                &self.repo_root,
                &handle.branch,
                &handle.path,
                &handle.base_commit,
            )
            .await
        {
            let disposition = failure.disposition();
            let operation = failure.into_error();
            if disposition == WorktreeCreateFailureDisposition::NoSideEffects {
                return Err(operation);
            }
            return Err(WorktreeError::CreationIncomplete {
                operation: Box::new(operation),
            });
        }
        let verification = async {
            self.validate_registered_site(&handle.path, &handle.branch)
                .await?;
            let status = self.backend.status(&handle.path).await?;
            if status.head != handle.base_commit
                || status.branch.as_deref() != Some(handle.branch.as_str())
            {
                return Err(WorktreeError::InvalidResource(
                    "created worktree does not match its frozen base and declared branch".into(),
                ));
            }
            Ok(())
        }
        .await;
        if let Err(operation) = verification {
            return Err(WorktreeError::CreationIncomplete {
                operation: Box::new(operation),
            });
        }
        Ok(handle)
    }

    fn validate_handle(&self, handle: &WorktreeHandle) -> Result<(), WorktreeError> {
        let expected_root = self.repo_root.join(WORKTREE_DIR);
        if !handle.path.starts_with(&expected_root)
            || handle.path.components().count() != expected_root.components().count() + 2
            || !is_pure_branch(&handle.branch)
        {
            return Err(WorktreeError::InvalidResource(
                "cleanup refused a non-Pure or non-leaf worktree identity".to_string(),
            ));
        }
        Ok(())
    }

    /// Discards an explicitly authorized, idle owned workspace, including uncommitted content.
    /// The caller holds the product ownership/removal permit; Git identity and locks still bind.
    /// No filesystem fallback is permitted, even if Git reports success but the path remains.
    pub async fn discard(&self, handle: &WorktreeHandle) -> Result<(), WorktreeError> {
        self.discard_owned(handle, None).await
    }

    /// A failed creation may only roll back a branch still at that operation's frozen base.
    /// Unproven partial resources stay with the product cleanup owner rather than being guessed away.
    pub(crate) async fn discard_incomplete_creation(
        &self,
        handle: &WorktreeHandle,
    ) -> Result<(), WorktreeError> {
        self.discard_owned(handle, Some(&handle.base_commit)).await
    }

    async fn discard_owned(
        &self,
        handle: &WorktreeHandle,
        creation_head: Option<&str>,
    ) -> Result<(), WorktreeError> {
        self.validate_handle(handle)?;
        let refuse = |reason: &str| WorktreeError::InvalidResource(reason.into());
        let base = self.repo_root.to_string_lossy();
        let path_key = super::backend::resolved_git_path(&handle.path.to_string_lossy(), &base)
            .ok_or_else(|| refuse("unresolved cleanup worktree path"))?;
        let common_dir = self
            .git_common_dir(&self.repo_root)
            .await?
            .ok_or_else(|| refuse("cleanup repository Git identity cannot be resolved"))?;
        let registered = self.registered_worktrees().await?;
        let registration = registered.iter().find(|entry| {
            super::backend::resolved_git_path(&entry.path, &base).as_ref() == Some(&path_key)
        });
        if registration.is_some_and(|entry| entry.branch.as_deref() != Some(handle.branch.as_str()))
            || registered.iter().any(|entry| {
                entry.branch.as_deref() == Some(handle.branch.as_str())
                    && super::backend::resolved_git_path(&entry.path, &base).as_ref()
                        != Some(&path_key)
            })
        {
            return Err(refuse(
                "cleanup worktree registration or branch identity changed",
            ));
        }
        let head = self
            .backend
            .branch_head(&self.repo_root, &handle.branch)
            .await?;
        if creation_head
            .is_some_and(|expected| head.as_deref().is_some_and(|head| head != expected))
        {
            return Err(refuse(
                "incomplete creation branch changed from its frozen base",
            ));
        }
        let exists = self.backend.path_exists(&handle.path).await?;
        if creation_head.is_some() && !exists && registration.is_none() && head.is_some() {
            return Err(refuse(
                "incomplete creation left an unproven unregistered branch",
            ));
        }
        if exists {
            self.validate_registered_site(&handle.path, &handle.branch)
                .await?;
            let status = self.backend.status(&handle.path).await?;
            if status.branch.as_deref() != Some(handle.branch.as_str())
                || head.as_deref() != Some(status.head.as_str())
            {
                return Err(refuse(
                    "cleanup workspace no longer matches its declared branch and HEAD",
                ));
            }
        }
        if exists || registration.is_some() {
            self.backend
                .remove(&self.repo_root, &handle.path, true)
                .await?;
        }
        if self.git_common_dir(&self.repo_root).await?.as_ref() != Some(&common_dir) {
            return Err(refuse("cleanup repository Git identity changed"));
        }
        let remaining = self.registered_worktrees().await?;
        if self.backend.path_exists(&handle.path).await?
            || remaining.iter().any(|entry| {
                super::backend::resolved_git_path(&entry.path, &base).as_ref() == Some(&path_key)
                    || entry.branch.as_deref() == Some(handle.branch.as_str())
            })
        {
            return Err(refuse(
                "Git did not remove the owned worktree and its registration",
            ));
        }
        if let Some(head) = head {
            self.backend
                .delete_branch_at(&self.repo_root, &handle.branch, &head)
                .await?;
        }
        self.verify_discarded(handle).await
    }

    /// Read-only completion check; a saved Cleaned label never authorizes deleting a replacement.
    pub(crate) async fn verify_discarded(
        &self,
        handle: &WorktreeHandle,
    ) -> Result<(), WorktreeError> {
        self.validate_handle(handle)?;
        let base = self.repo_root.to_string_lossy();
        let path_key = super::backend::resolved_git_path(&handle.path.to_string_lossy(), &base)
            .ok_or_else(|| {
                WorktreeError::InvalidResource("unresolved cleaned worktree path".into())
            })?;
        if self.backend.path_exists(&handle.path).await?
            || self.registered_worktrees().await?.iter().any(|entry| {
                super::backend::resolved_git_path(&entry.path, &base).as_ref() == Some(&path_key)
                    || entry.branch.as_deref() == Some(handle.branch.as_str())
            })
            || self
                .backend
                .branch_head(&self.repo_root, &handle.branch)
                .await?
                .is_some()
        {
            return Err(WorktreeError::InvalidResource(
                "cleaned worktree, registration or branch is present; refusing a stale cleanup receipt".into(),
            ));
        }
        Ok(())
    }

    /// Read-only delivery proof, used before grant persistence and again before Git removal.
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
            return Err(WorktreeError::InvalidResource(
                "close repository or root delivery target identity changed".into(),
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

    /// Removes only the frozen, existing child worktree after delivery, or explicit force.
    /// No filesystem fallback bypasses a Git refusal; every physical postcondition is checked.
    pub async fn retire_child(
        &self,
        handle: &WorktreeHandle,
        request: &WorktreeRetirementRequest,
    ) -> Result<(), WorktreeError> {
        self.validate_handle(handle)?;
        let refuse = |reason: &str| WorktreeError::InvalidResource(reason.into());
        if !handle.branch.starts_with(CHILD_BRANCH_PREFIX)
            || handle
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
            return Err(refuse(
                "retirement requires a frozen child identity and a distinct delivery target",
            ));
        }
        self.validate_child_delivery(request).await?;
        let base = self.repo_root.to_string_lossy();
        let path_key = super::backend::resolved_git_path(&handle.path.to_string_lossy(), &base)
            .ok_or_else(|| refuse("unresolved retirement worktree path"))?;
        let registered = self.registered_worktrees().await?;
        let registration = registered.iter().find(|entry| {
            super::backend::resolved_git_path(&entry.path, &base).as_ref() == Some(&path_key)
        });
        if registration.is_some_and(|entry| entry.branch.as_deref() != Some(handle.branch.as_str()))
        {
            return Err(refuse("retirement worktree registration changed branch"));
        }
        let exists = self.backend.path_exists(&handle.path).await?;
        if exists {
            self.validate_registered_site(&handle.path, &handle.branch)
                .await?;
            let status = self.backend.status(&handle.path).await?;
            if status.branch.as_deref() != Some(handle.branch.as_str())
                || status.head != request.expected_head
            {
                return Err(refuse(
                    "retirement workspace no longer matches its authorized HEAD and branch",
                ));
            }
            if !request.force && !status.changed_files.is_empty() {
                return Err(refuse(
                    "child has uncommitted or untracked changes; explicit force is required",
                ));
            }
        }
        let head = self
            .backend
            .branch_head(&self.repo_root, &handle.branch)
            .await?;
        if head.as_deref() != Some(request.expected_head.as_str()) {
            return Err(refuse(
                "retirement branch no longer matches its authorized HEAD",
            ));
        }
        if !exists {
            return Err(refuse(
                "child path disappeared before Git removal; registration was preserved",
            ));
        }
        self.backend
            .remove(&self.repo_root, &handle.path, request.force)
            .await?;
        if self.backend.path_exists(&handle.path).await?
            || self.registered_worktrees().await?.iter().any(|entry| {
                super::backend::resolved_git_path(&entry.path, &base).as_ref() == Some(&path_key)
            })
        {
            return Err(refuse(
                "Git did not remove the retired worktree and its registration",
            ));
        }
        Ok(())
    }

    /// Read-only postcondition. A terminal retry never invokes removal or ref deletion
    /// against a new registration that happens to reuse the old path, branch and commit.
    pub(crate) async fn verify_child_retired(
        &self,
        handle: &WorktreeHandle,
        expected_common_dir: &str,
    ) -> Result<(), WorktreeError> {
        self.validate_handle(handle)?;
        let refuse = |reason: &str| WorktreeError::InvalidResource(reason.into());
        if self.git_common_dir(&self.repo_root).await?.as_deref() != Some(expected_common_dir) {
            return Err(refuse("retired repository identity changed"));
        }
        let base = self.repo_root.to_string_lossy();
        let path_key = super::backend::resolved_git_path(&handle.path.to_string_lossy(), &base)
            .ok_or_else(|| refuse("unresolved retired worktree path"))?;
        if self.backend.path_exists(&handle.path).await?
            || self.registered_worktrees().await?.iter().any(|entry| {
                super::backend::resolved_git_path(&entry.path, &base).as_ref() == Some(&path_key)
            })
        {
            return Err(refuse(
                "closed child path or exact registration is present; replacement was preserved",
            ));
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
        "agent".to_string()
    } else {
        value
    }
}
