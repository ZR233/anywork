use std::borrow::Cow;
use std::collections::BTreeMap;
use std::fmt;
use std::path::{Path, PathBuf};
use std::time::Duration;

use futures::FutureExt;
use futures::future::BoxFuture;
use pl_tool::execution::{
    ExecutionFailure, ExecutionOutput, ExecutionRequest, ExecutorExecutionBackend,
};

const WORKTREE_GIT_TIMEOUT: Duration = Duration::from_secs(120);
pub(super) const MAX_ADMIN_BACKLINK_BYTES: usize = 128 * 1024;

#[derive(Debug, thiserror::Error)]
pub enum WorktreeError {
    #[error("worktree path is missing; no cleanup was performed")]
    Missing,
    #[error("工作区没有有效的 HEAD commit；请先完成初始 commit 后重试")]
    MissingHead,
    #[error("worktree identity mismatch: {0}")]
    IdentityMismatch(String),
    #[error("invalid worktree resource: {0}")]
    InvalidResource(String),
    #[error("failed to launch git {args}: {message}")]
    GitLaunchFailed { args: String, message: String },
    #[error("git {args} timed out")]
    GitTimedOut { args: String },
    #[error("git {args} exited with {exit_code}: {stderr}")]
    GitExited {
        args: String,
        exit_code: i32,
        stderr: String,
    },
    #[error("git {args} status is unknown: {stderr}")]
    GitStatusUnknown { args: String, stderr: String },
    #[error("{operation}: target file operation failed")]
    Target {
        operation: &'static str,
        #[source]
        source: pl_tool::workspace_file::WorkspaceFileError,
    },
    #[error("git {}: {}", super::diagnostic::git_operation(.args), super::diagnostic::execution_cause(.source))]
    Execution {
        args: String,
        #[source]
        source: ExecutionFailure,
    },
    #[error("{operation}: {}", super::diagnostic::download_cause(.source))]
    Download {
        operation: &'static str,
        #[source]
        source: super::WorkspaceDownloadError,
    },
    #[error("{operation}: file operation failed")]
    File {
        operation: &'static str,
        #[source]
        source: crate::PureError,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorktreeCreateFailureDisposition {
    NoSideEffects,
    MayHaveCreated,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorktreeStatus {
    pub head: String,
    /// The checked-out branch of the directory, or `None` when it is not on any branch.
    ///
    /// This is mutable state, not resource identity.
    pub branch: Option<String>,
    pub changed_files: Vec<String>,
    /// Ignored content belongs to Recovery Safe protection, not the spawn dirty gate.
    pub ignored_files: Vec<String>,
}

#[derive(Debug, thiserror::Error)]
#[error("{error}")]
pub struct WorktreeCreateFailure {
    #[source]
    error: Box<WorktreeError>,
    disposition: WorktreeCreateFailureDisposition,
}

impl WorktreeCreateFailure {
    pub fn no_side_effects(error: WorktreeError) -> Self {
        Self {
            error: Box::new(error),
            disposition: WorktreeCreateFailureDisposition::NoSideEffects,
        }
    }

    pub fn may_have_created(error: WorktreeError) -> Self {
        Self {
            error: Box::new(error),
            disposition: WorktreeCreateFailureDisposition::MayHaveCreated,
        }
    }

    pub fn disposition(&self) -> WorktreeCreateFailureDisposition {
        self.disposition
    }

    pub fn into_error(self) -> WorktreeError {
        *self.error
    }
}

pub trait WorktreeBackend: fmt::Debug + Send + Sync {
    /// Proves commit delivery without rewriting or deleting any reference.
    fn is_ancestor<'a>(
        &'a self,
        repo_root: &'a Path,
        ancestor: &'a str,
        descendant: &'a str,
    ) -> BoxFuture<'a, Result<bool, WorktreeError>>;

    fn resolve_repo_root<'a>(
        &'a self,
        path: &'a Path,
    ) -> BoxFuture<'a, Result<PathBuf, WorktreeError>>;

    fn create_parent<'a>(
        &'a self,
        repo_root: &'a Path,
        target_path: &'a Path,
    ) -> BoxFuture<'a, Result<(), WorktreeError>>;

    fn path_exists<'a>(
        &'a self,
        repo_root: &'a Path,
        path: &'a Path,
    ) -> BoxFuture<'a, Result<bool, WorktreeError>>;

    fn create<'a>(
        &'a self,
        repo_root: &'a Path,
        target_path: &'a Path,
        base_commit: &'a str,
    ) -> BoxFuture<'a, Result<(), WorktreeCreateFailure>>;

    fn resolve_head<'a>(
        &'a self,
        worktree_path: &'a Path,
    ) -> BoxFuture<'a, Result<String, WorktreeError>>;

    fn status<'a>(
        &'a self,
        worktree_path: &'a Path,
    ) -> BoxFuture<'a, Result<WorktreeStatus, WorktreeError>>;

    fn remove<'a>(
        &'a self,
        repo_root: &'a Path,
        target_path: &'a Path,
        force: bool,
    ) -> BoxFuture<'a, Result<(), WorktreeError>>;

    /// Lists the worktrees this repository has registered, as Git itself reports them.
    ///
    /// This is the repository's own identity statement: an expected directory alone cannot prove
    /// ownership. Branches and HEAD are not identity.
    fn worktree_list<'a>(
        &'a self,
        repo_root: &'a Path,
    ) -> BoxFuture<'a, Result<String, WorktreeError>>;

    /// The Git directory a directory shares with the repository it belongs to.
    ///
    /// Two directories of the same repository answer with the same common Git directory, and a
    /// directory that belongs to another repository answers with a different one, which is what makes
    /// this a repository identity fact rather than a path convention.
    fn git_common_dir<'a>(&'a self, path: &'a Path)
    -> BoxFuture<'a, Result<String, WorktreeError>>;

    /// Reads the checkout backlink from its Git worktree admin directory after checking that the
    /// admin directory is a direct registration under the already verified common directory.
    fn worktree_backlink<'a>(
        &'a self,
        path: &'a Path,
        common_dir: &'a str,
    ) -> BoxFuture<'a, Result<String, WorktreeError>>;
}

#[derive(Debug, Clone)]
pub struct ExecutorWorktreeBackend {
    executor: pl_remote_helper::Executor,
}

impl ExecutorWorktreeBackend {
    pub fn new(executor: pl_remote_helper::Executor) -> Self {
        Self { executor }
    }
    fn files(
        &self,
        root: &str,
    ) -> Result<pl_tool::workspace_file::ExecutorWorkspaceFileBackend, WorktreeError> {
        pl_tool::workspace_file::ExecutorWorkspaceFileBackend::new(self.executor.clone(), root)
            .map_err(|source| WorktreeError::Target {
                operation: "bind worktree files",
                source,
            })
    }
    fn path(&self, path: &Path) -> Result<pl_remote_helper::TargetPath, WorktreeError> {
        let path = path
            .to_str()
            .ok_or_else(|| WorktreeError::InvalidResource("worktree path is not UTF-8".into()))?;
        // A Windows PathBuf may contain host separators after allocation. Interpret them
        // at the remote Git boundary, without changing native POSIX filename semantics.
        let path = if !self.executor.is_local() && self.executor.target_info().os == "linux" {
            Cow::Owned(
                pl_tool::remote::normalize_remote_absolute_path(path)
                    .map_err(|error| WorktreeError::InvalidResource(error.to_string()))?,
            )
        } else {
            Cow::Borrowed(path)
        };
        self.executor
            .path(path.as_ref())
            .map_err(|source| WorktreeError::Target {
                operation: "resolve worktree path",
                source: source.into(),
            })
    }
    async fn run_git_output(
        &self,
        cwd: &Path,
        args: &[String],
    ) -> Result<ExecutionOutput, WorktreeError> {
        let cwd = self.path(cwd)?;
        let request = git_request(
            cwd.as_str(),
            args,
            self.executor.target_info().os == "windows",
        );
        let arguments = args.join(" ");
        ExecutorExecutionBackend::new(self.executor.clone())
            .run_classified(request)
            .await
            .map_err(|source| WorktreeError::Execution {
                args: arguments,
                source,
            })
    }

    async fn run_git(&self, cwd: &Path, args: &[String]) -> Result<ExecutionOutput, WorktreeError> {
        checked_output(args, self.run_git_output(cwd, args).await?)
    }
}

impl WorktreeBackend for ExecutorWorktreeBackend {
    fn is_ancestor<'a>(
        &'a self,
        repo_root: &'a Path,
        ancestor: &'a str,
        descendant: &'a str,
    ) -> BoxFuture<'a, Result<bool, WorktreeError>> {
        async move {
            let args = ancestor_args(ancestor, descendant);
            ancestor_result(&args, self.run_git_output(repo_root, &args).await?)
        }
        .boxed()
    }

    fn worktree_backlink<'a>(
        &'a self,
        path: &'a Path,
        common_dir: &'a str,
    ) -> BoxFuture<'a, Result<String, WorktreeError>> {
        async move {
            let args = vec!["rev-parse".into(), "--absolute-git-dir".into()];
            let output = self.run_git(path, &args).await?;
            let admin = checked_admin_dir(&output.stdout, common_dir)?;
            // Git-confirmed metadata can live outside the checkout. It receives a
            // separate confined file view on the same concrete executor, never a new connection.
            let common =
                self.executor
                    .path(common_dir)
                    .map_err(|source| WorktreeError::Target {
                        operation: "resolve Git common directory",
                        source: source.into(),
                    })?;
            let canonical = self
                .executor
                .fs()
                .canonicalize(&common)
                .await
                .map_err(|source| WorktreeError::Target {
                    operation: "canonicalize Git common directory",
                    source: source.into(),
                })?;
            // Compare with the same Git identity rules as the owning manager.
            // Windows Git identity is case folded, while the physical file view
            // must retain the canonical target spelling returned by the OS.
            if resolved_git_path(common.as_str(), "") != resolved_git_path(canonical.as_str(), "") {
                return Err(WorktreeError::IdentityMismatch(
                    "Git common directory changed physical identity".into(),
                ));
            }
            let files = self.files(canonical.as_str())?;
            let backlink = self
                .executor
                .join_path(
                    &self
                        .executor
                        .path(&admin)
                        .map_err(|source| WorktreeError::Target {
                            operation: "resolve Git admin directory",
                            source: source.into(),
                        })?,
                    "gitdir",
                )
                .map_err(|source| WorktreeError::Target {
                    operation: "resolve Git admin backlink",
                    source: source.into(),
                })?;
            let mut bytes = Vec::new();
            files
                .copy_capture_bounded(
                    backlink.as_str(),
                    &mut bytes,
                    MAX_ADMIN_BACKLINK_BYTES as u64,
                )
                .await
                .map_err(|source| WorktreeError::Download {
                    operation: "read Git admin backlink",
                    source,
                })?;
            decode_backlink(&bytes, &admin)
        }
        .boxed()
    }

    fn resolve_repo_root<'a>(
        &'a self,
        path: &'a Path,
    ) -> BoxFuture<'a, Result<PathBuf, WorktreeError>> {
        async move {
            let args = vec!["rev-parse".to_string(), "--show-toplevel".to_string()];
            let output = self.run_git(path, &args).await?;
            let root = non_empty_head(&args, &output.stdout)?;
            let root = self.path(Path::new(&root))?;
            self.executor
                .fs()
                .canonicalize(&root)
                .await
                .map(|path| PathBuf::from(path.as_str()))
                .map_err(|source| WorktreeError::Target {
                    operation: "canonicalize repository root",
                    source: source.into(),
                })
        }
        .boxed()
    }

    fn create_parent<'a>(
        &'a self,
        repo_root: &'a Path,
        target_path: &'a Path,
    ) -> BoxFuture<'a, Result<(), WorktreeError>> {
        async move {
            let root = self.path(repo_root)?;
            let target = self.path(target_path)?;
            let parent = self
                .executor
                .parent_path(&target)
                .map_err(|source| WorktreeError::Target {
                    operation: "resolve worktree parent",
                    source: source.into(),
                })?
                .ok_or_else(|| {
                    WorktreeError::InvalidResource("worktree target has no parent".into())
                })?;
            self.files(root.as_str())?
                .create_directory(parent.as_str().into(), None)
                .await
                .map_err(|source| WorktreeError::File {
                    operation: "create worktree parent",
                    source,
                })
        }
        .boxed()
    }

    fn path_exists<'a>(
        &'a self,
        repo_root: &'a Path,
        path: &'a Path,
    ) -> BoxFuture<'a, Result<bool, WorktreeError>> {
        async move {
            let root = self.path(repo_root)?;
            let target = self.path(path)?;
            self.files(root.as_str())?
                .inspect_path(target.as_str().into(), None)
                .await
                .map(|stat| stat.is_some())
                .map_err(|source| WorktreeError::Target {
                    operation: "stat worktree path",
                    source,
                })
        }
        .boxed()
    }

    fn create<'a>(
        &'a self,
        repo_root: &'a Path,
        target_path: &'a Path,
        base_commit: &'a str,
    ) -> BoxFuture<'a, Result<(), WorktreeCreateFailure>> {
        async move {
            let args = vec![
                "worktree".to_string(),
                "add".to_string(),
                "--detach".to_string(),
                self.path(target_path)
                    .map_err(WorktreeCreateFailure::no_side_effects)?
                    .as_str()
                    .into(),
                base_commit.to_string(),
            ];
            let output =
                self.run_git_output(repo_root, &args)
                    .await
                    .map_err(|error| match error {
                        WorktreeError::Execution {
                            source:
                                ExecutionFailure::Spawn(pl_remote_helper::SpawnError {
                                    knowledge: pl_remote_helper::StartKnowledge::NotStarted,
                                    ..
                                }),
                            ..
                        } => WorktreeCreateFailure::no_side_effects(error),
                        _ => WorktreeCreateFailure::may_have_created(error),
                    })?;
            checked_output(&args, output)
                .map(|_| ())
                .map_err(WorktreeCreateFailure::may_have_created)
        }
        .boxed()
    }

    fn resolve_head<'a>(
        &'a self,
        worktree_path: &'a Path,
    ) -> BoxFuture<'a, Result<String, WorktreeError>> {
        async move {
            let args = head_args();
            head_result(&args, self.run_git_output(worktree_path, &args).await?)
        }
        .boxed()
    }

    fn status<'a>(
        &'a self,
        worktree_path: &'a Path,
    ) -> BoxFuture<'a, Result<WorktreeStatus, WorktreeError>> {
        async move {
            let head = self.resolve_head(worktree_path).await?;
            let args = vec![
                "status".to_string(),
                "--porcelain=v1".to_string(),
                "--untracked-files=all".to_string(),
                "--ignored=matching".to_string(),
            ];
            let output = self.run_git(worktree_path, &args).await?;
            Ok(WorktreeStatus {
                head,
                branch: current_branch(&self.run_git(worktree_path, &branch_args()).await?),
                changed_files: changed_files(&output.stdout),
                ignored_files: ignored_files(&output.stdout),
            })
        }
        .boxed()
    }

    fn remove<'a>(
        &'a self,
        repo_root: &'a Path,
        target_path: &'a Path,
        force: bool,
    ) -> BoxFuture<'a, Result<(), WorktreeError>> {
        async move {
            let mut args = vec!["worktree".to_string(), "remove".to_string()];
            if force {
                args.push("--force".to_string());
            }
            args.push(self.path(target_path)?.as_str().into());
            self.run_git(repo_root, &args).await.map(|_| ())
        }
        .boxed()
    }

    fn worktree_list<'a>(
        &'a self,
        repo_root: &'a Path,
    ) -> BoxFuture<'a, Result<String, WorktreeError>> {
        async move {
            let args = worktree_list_args();
            let output = self.run_git(repo_root, &args).await?;
            checked_output(&args, output).map(|output| output.stdout)
        }
        .boxed()
    }

    fn git_common_dir<'a>(
        &'a self,
        path: &'a Path,
    ) -> BoxFuture<'a, Result<String, WorktreeError>> {
        async move {
            let args = git_common_dir_args();
            let output = self.run_git(path, &args).await?;
            checked_output(&args, output).map(|output| output.stdout)
        }
        .boxed()
    }
}

pub(super) fn ancestor_args(ancestor: &str, descendant: &str) -> Vec<String> {
    vec![
        "merge-base".into(),
        "--is-ancestor".into(),
        ancestor.into(),
        descendant.into(),
    ]
}

pub(super) fn ancestor_result(
    args: &[String],
    output: ExecutionOutput,
) -> Result<bool, WorktreeError> {
    if output.status == 1 {
        return Ok(false);
    }
    checked_output(args, output).map(|_| true)
}

fn git_request(cwd: &str, args: &[String], windows: bool) -> ExecutionRequest {
    let mut full_args = vec![
        "-c".to_string(),
        "core.hooksPath=/dev/null".to_string(),
        "-c".to_string(),
        format!("safe.directory={cwd}"),
        "-c".to_string(),
        "credential.helper=".to_string(),
    ];
    if windows {
        full_args.extend(["-c".to_string(), "core.longpaths=true".to_string()]);
    }
    full_args.extend_from_slice(args);
    ExecutionRequest {
        program: PathBuf::from("git"),
        args: full_args,
        cwd: PathBuf::from(cwd),
        env: BTreeMap::from([("LC_ALL".into(), "C".into())]),
        timeout: Some(WORKTREE_GIT_TIMEOUT),
    }
}

pub(super) fn checked_output(
    args: &[String],
    output: ExecutionOutput,
) -> Result<ExecutionOutput, WorktreeError> {
    if output.status == 0 {
        Ok(output)
    } else {
        Err(WorktreeError::GitExited {
            args: args.join(" "),
            exit_code: output.status,
            stderr: output.stderr,
        })
    }
}

pub(super) fn head_args() -> Vec<String> {
    vec![
        "rev-parse".into(),
        "--verify".into(),
        "--quiet".into(),
        "HEAD^{commit}".into(),
    ]
}

pub(super) fn head_result(
    args: &[String],
    output: ExecutionOutput,
) -> Result<String, WorktreeError> {
    // --verify --quiet uses 1 for a missing valid commit. Other failures retain their typed Git
    // cause instead of being mislabeled as an unborn repository.
    if output.status == 1 {
        return Err(WorktreeError::MissingHead);
    }
    non_empty_head(args, &checked_output(args, output)?.stdout)
}

pub(super) fn non_empty_head(args: &[String], stdout: &str) -> Result<String, WorktreeError> {
    let head = stdout.trim();
    if head.is_empty() {
        Err(WorktreeError::GitStatusUnknown {
            args: args.join(" "),
            stderr: "git rev-parse HEAD returned an empty value".to_string(),
        })
    } else {
        Ok(head.to_string())
    }
}

pub(super) fn changed_files(stdout: &str) -> Vec<String> {
    status_files(stdout, false)
}

pub(super) fn ignored_files(stdout: &str) -> Vec<String> {
    status_files(stdout, true)
}

fn status_files(stdout: &str, ignored: bool) -> Vec<String> {
    let mut files = stdout
        .lines()
        .filter(|line| line.starts_with("!! ") == ignored)
        .filter_map(|line| line.get(3..))
        .map(|path| path.rsplit_once(" -> ").map_or(path, |(_, path)| path))
        .map(str::to_string)
        .collect::<Vec<_>>();
    files.sort();
    files.dedup();
    files
}

/// The git arguments that report which branch a directory is on.
pub(super) fn worktree_list_args() -> Vec<String> {
    vec![
        "worktree".to_string(),
        "list".to_string(),
        "--porcelain".to_string(),
    ]
}

/// The git arguments that report the Git directory shared with the owning repository.
pub(super) fn git_common_dir_args() -> Vec<String> {
    vec!["rev-parse".to_string(), "--git-common-dir".to_string()]
}

pub(super) fn checked_admin_dir(raw: &str, common_dir: &str) -> Result<String, WorktreeError> {
    let admin = resolved_git_path(raw, "").ok_or_else(|| {
        WorktreeError::IdentityMismatch("registration admin directory cannot be normalized".into())
    })?;
    let prefix = format!("{common_dir}/worktrees/");
    if !admin
        .strip_prefix(&prefix)
        .is_some_and(|leaf| !leaf.is_empty() && !leaf.contains('/'))
    {
        return Err(WorktreeError::IdentityMismatch(
            "registration admin directory is outside the owning repository".into(),
        ));
    }
    Ok(admin)
}

pub(super) fn decode_backlink(bytes: &[u8], admin_dir: &str) -> Result<String, WorktreeError> {
    if bytes.len() > MAX_ADMIN_BACKLINK_BYTES {
        return Err(WorktreeError::IdentityMismatch(
            "registration admin backlink exceeds its path bound".into(),
        ));
    }
    let text = std::str::from_utf8(bytes).map_err(|_| {
        WorktreeError::IdentityMismatch("registration admin backlink is not a UTF-8 path".into())
    })?;
    // Git can rewrite both linking files to relative paths during creation or repair. The
    // backlink is relative to this verified admin directory, not to the checkout or common dir.
    resolved_git_path(text, admin_dir).ok_or_else(|| {
        WorktreeError::IdentityMismatch("registration admin backlink cannot be normalized".into())
    })
}

// --- worktree path normalization (self-contained; verified offline by a scratch harness) ---
//
// Git answers `--git-common-dir` in one of two shapes: `.git` (relative to the directory it was asked
// in) or an absolute path. Two answers are comparable only after the same lexical resolution, and that
// resolution has to be platform-correct: a Windows drive letter and a UNC share are absolute just like a
// POSIX `/`, separators differ, and Windows compares paths case-insensitively while POSIX does not.

/// Resolves one `rev-parse` path answer against the directory it was asked in.
///
/// `None` means the answer cannot be proven: empty, relative to an unresolvable base, or escaping above
/// the filesystem root. Windows-style answers (drive letter or UNC) are folded to lower case, because a
/// Windows path that differs only by case is the same directory; POSIX answers keep their case.
pub(super) fn resolved_git_path(raw: &str, base: &str) -> Option<String> {
    let raw = normalized_separators(raw);
    if raw.is_empty() {
        return None;
    }
    // A drive-relative answer (`C:foo`) is neither an absolute identity nor a usable relative segment:
    // it depends on a per-drive current directory this comparison never knows.
    if drive_relative_git_path(&raw) {
        return None;
    }
    let base = normalized_separators(base);
    let joined = if absolute_git_path(&raw) {
        raw
    } else if absolute_git_path(&base) {
        format!("{}/{}", base.trim_end_matches('/'), raw)
    } else {
        return None;
    };
    let (prefix, rest, windows_style) = split_git_root(&joined)?;
    let mut parts: Vec<&str> = Vec::new();
    for part in rest.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop()?;
            }
            other => parts.push(other),
        }
    }
    let body = parts.join("/");
    let normalized = if prefix.is_empty() {
        format!("/{body}")
    } else if body.is_empty() {
        format!("{prefix}/")
    } else {
        format!("{prefix}/{body}")
    };
    Some(if windows_style {
        normalized.to_ascii_lowercase()
    } else {
        normalized
    })
}

/// Normalizes the separators Git may print on either platform.
fn normalized_separators(value: &str) -> String {
    value.trim().replace('\\', "/")
}

/// Whether the value names an absolute location on either platform.
fn absolute_git_path(value: &str) -> bool {
    value.starts_with('/') || drive_prefix(value).is_some()
}

/// The drive designation of a Windows path, when it has one and is not drive-relative (`C:foo`).
fn drive_prefix(value: &str) -> Option<&str> {
    let bytes = value.as_bytes();
    if bytes.len() < 2 || bytes[1] != b':' || !bytes[0].is_ascii_alphabetic() {
        return None;
    }
    match value[2..].chars().next() {
        None | Some('/') => Some(&value[..2]),
        // `C:foo` is relative to the drive's current directory: not an absolute identity.
        Some(_) => None,
    }
}

/// Whether the value names a location relative to a drive's current directory (`C:foo`).
fn drive_relative_git_path(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() < 2 || bytes[1] != b':' || !bytes[0].is_ascii_alphabetic() {
        return false;
    }
    !matches!(value[2..].chars().next(), None | Some('/'))
}

/// Splits an absolute path into (root, rest, windows_style).
///
/// The root is `/` for POSIX, a drive (`c:`) for Windows paths, and `//server/share` for a UNC path. UNC
/// roots keep their two leading components, which are the share identity and never fold into `..`.
fn split_git_root(value: &str) -> Option<(String, String, bool)> {
    if let Some(rest) = value.strip_prefix("//") {
        let mut parts = rest.splitn(3, '/');
        let server = parts.next().filter(|part| !part.is_empty())?;
        let share = parts.next().filter(|part| !part.is_empty())?;
        let rest = parts.next().unwrap_or_default().to_string();
        return Some((format!("//{server}/{share}"), rest, true));
    }
    if let Some(drive) = drive_prefix(value) {
        let rest = value[2..].trim_start_matches('/').to_string();
        return Some((drive.to_ascii_lowercase(), rest, true));
    }
    if value.starts_with('/') {
        return Some((
            String::new(),
            value.trim_start_matches('/').to_string(),
            false,
        ));
    }
    None
}
// --- end worktree path normalization ---

/// The repository's registration identity; mutable HEAD/branch state is irrelevant here.
pub(crate) struct RegisteredWorktree {
    pub path: String,
    /// Git reports a worktree whose directory is gone as `prunable`: it is a stale registration, not a
    /// site that may be reused.
    pub prunable: bool,
}

/// Parses the porcelain output of `git worktree list`.
///
/// Each block starts with `worktree <path>`, and a branch entry is `branch refs/heads/<name>`; a
/// detached worktree prints `detached` instead, so it is reported without a branch.
pub(crate) fn registered_worktrees(stdout: &str) -> Vec<RegisteredWorktree> {
    let mut worktrees = Vec::new();
    for block in stdout.split("\n\n") {
        let mut path = None;
        let mut prunable = false;
        for line in block.lines() {
            if let Some(value) = line.strip_prefix("worktree ") {
                path = Some(value.trim().to_string());
            } else if line.trim() == "prunable" || line.starts_with("prunable ") {
                prunable = true;
            }
        }
        if let Some(path) = path {
            worktrees.push(RegisteredWorktree { path, prunable });
        }
    }
    worktrees
}

/// The git arguments that report which branch a directory is on.
pub(super) fn branch_args() -> Vec<String> {
    vec![
        "rev-parse".to_string(),
        "--abbrev-ref".to_string(),
        "HEAD".to_string(),
    ]
}

/// The branch a directory is on, or `None` when it is not on any branch.
///
/// `git rev-parse --abbrev-ref HEAD` answers `HEAD` for a detached checkout.
pub(super) fn current_branch(output: &ExecutionOutput) -> Option<String> {
    let branch = output.stdout.trim();
    if branch.is_empty() || branch == "HEAD" {
        return None;
    }
    Some(branch.to_string())
}
