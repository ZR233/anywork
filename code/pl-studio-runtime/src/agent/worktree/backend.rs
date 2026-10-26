use std::collections::BTreeMap;
use std::fmt;
use std::path::{Path, PathBuf};
use std::time::Duration;

use futures::FutureExt;
use futures::future::BoxFuture;
use pl_tool::execution::{
    ExecutionOutput, ExecutionRequest, LocalExecutionBackend, LocalExecutionFailure,
};

use pl_tool::git::GitPolicy;

const WORKTREE_GIT_TIMEOUT: Duration = Duration::from_secs(120);

#[derive(Debug, thiserror::Error)]
pub enum WorktreeError {
    #[error("worktree path is missing; no cleanup was performed")]
    Missing,
    #[error("worktree identity mismatch: {0}")]
    IdentityMismatch(String),
    #[error("invalid worktree resource: {0}")]
    InvalidResource(String),
    #[error("unsafe git branch `{0}`")]
    UnsafeBranch(String),
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
    #[error("{operation}: filesystem error ({:?}, os={:?})", .source.kind(), .source.raw_os_error())]
    LocalIo {
        operation: &'static str,
        #[source]
        source: std::io::Error,
    },
    #[error("{operation}: {}", super::diagnostic::remote_code(.source))]
    Remote {
        operation: &'static str,
        #[source]
        source: super::RemoteClientError,
    },
    #[error("git {}: {}", super::diagnostic::git_operation(.args), super::diagnostic::execution_cause(.source))]
    RemoteExecution {
        args: String,
        #[source]
        source: super::RemoteExecutionError,
    },
    #[error("{operation}: remote file operation failed")]
    RemoteFile {
        operation: &'static str,
        #[source]
        source: crate::PureError,
    },
    #[error("{operation}; rollback succeeded")]
    OperationFailedAfterCleanup { operation: Box<WorktreeError> },
    #[error("{operation}; rollback failed: {cleanup}")]
    OperationFailedWithCleanup {
        operation: Box<WorktreeError>,
        cleanup: Box<WorktreeError>,
    },
    #[error("{context} cleanup failed: {failures:?}")]
    CleanupFailed {
        context: String,
        failures: Vec<WorktreeError>,
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
    /// A reuse decision needs this: the path alone does not prove the directory at that path is the
    /// worktree the saved lease describes, and a detached HEAD cannot prove it either.
    pub branch: Option<String>,
    pub changed_files: Vec<String>,
}

#[derive(Debug, thiserror::Error)]
#[error("{error}")]
pub struct WorktreeCreateFailure {
    error: WorktreeError,
    disposition: WorktreeCreateFailureDisposition,
}

impl WorktreeCreateFailure {
    pub fn no_side_effects(error: WorktreeError) -> Self {
        Self {
            error,
            disposition: WorktreeCreateFailureDisposition::NoSideEffects,
        }
    }

    pub fn may_have_created(error: WorktreeError) -> Self {
        Self {
            error,
            disposition: WorktreeCreateFailureDisposition::MayHaveCreated,
        }
    }

    pub fn disposition(&self) -> WorktreeCreateFailureDisposition {
        self.disposition
    }

    pub fn into_error(self) -> WorktreeError {
        self.error
    }
}

pub trait WorktreeBackend: fmt::Debug + Send + Sync {
    fn resolve_repo_root<'a>(
        &'a self,
        path: &'a Path,
    ) -> BoxFuture<'a, Result<PathBuf, WorktreeError>>;

    fn create_parent<'a>(
        &'a self,
        repo_root: &'a Path,
        target_path: &'a Path,
    ) -> BoxFuture<'a, Result<(), WorktreeError>>;

    fn path_exists<'a>(&'a self, path: &'a Path) -> BoxFuture<'a, Result<bool, WorktreeError>>;

    fn remove_leaf<'a>(
        &'a self,
        repo_root: &'a Path,
        target_path: &'a Path,
    ) -> BoxFuture<'a, Result<(), WorktreeError>>;

    fn create<'a>(
        &'a self,
        repo_root: &'a Path,
        branch: &'a str,
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

    fn delete_branch<'a>(
        &'a self,
        repo_root: &'a Path,
        branch: &'a str,
    ) -> BoxFuture<'a, Result<(), WorktreeError>>;

    /// Lists the worktrees this repository has registered, as Git itself reports them.
    ///
    /// This is the repository's own identity statement: a directory can exist at an expected path and
    /// even be a Git worktree of *another* repository, but only the resolved repository can report it
    /// as its own worktree on a given branch.
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
}

#[derive(Debug, Clone)]
pub struct LocalWorktreeBackend {
    backend: LocalExecutionBackend,
    policy: GitPolicy,
}

impl Default for LocalWorktreeBackend {
    fn default() -> Self {
        Self {
            backend: LocalExecutionBackend,
            policy: GitPolicy::default(),
        }
    }
}

impl LocalWorktreeBackend {
    async fn run_git_output(
        &self,
        cwd: &Path,
        args: &[String],
    ) -> Result<ExecutionOutput, WorktreeError> {
        let request = git_request(cwd, args);
        let arguments = args.join(" ");
        self.backend
            .run_classified(request)
            .await
            .map_err(|failure| match failure {
                LocalExecutionFailure::BeforeSpawn(message) => WorktreeError::GitLaunchFailed {
                    args: arguments,
                    message,
                },
                LocalExecutionFailure::AfterSpawn(stderr) => WorktreeError::GitStatusUnknown {
                    args: arguments,
                    stderr,
                },
                LocalExecutionFailure::TimedOut => WorktreeError::GitTimedOut { args: arguments },
            })
    }

    async fn run_git(&self, cwd: &Path, args: &[String]) -> Result<ExecutionOutput, WorktreeError> {
        checked_output(args, self.run_git_output(cwd, args).await?)
    }
}

impl WorktreeBackend for LocalWorktreeBackend {
    fn resolve_repo_root<'a>(
        &'a self,
        path: &'a Path,
    ) -> BoxFuture<'a, Result<PathBuf, WorktreeError>> {
        async move {
            let args = vec!["rev-parse".to_string(), "--show-toplevel".to_string()];
            let output = self.run_git(path, &args).await?;
            let root = non_empty_head(&args, &output.stdout)?;
            dunce::canonicalize(root).map_err(|source| WorktreeError::LocalIo {
                operation: "canonicalize repository root",
                source,
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
            pl_tool::workspace::path_safety::validate_path_for_write(repo_root, target_path)
                .map_err(|error| WorktreeError::InvalidResource(error.to_string()))?;
            let parent = target_path.parent().ok_or_else(|| {
                WorktreeError::InvalidResource("worktree target has no parent".to_string())
            })?;
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|source| WorktreeError::LocalIo {
                    operation: "create worktree parent",
                    source,
                })
        }
        .boxed()
    }

    fn path_exists<'a>(&'a self, path: &'a Path) -> BoxFuture<'a, Result<bool, WorktreeError>> {
        async move {
            match tokio::fs::symlink_metadata(path).await {
                Ok(_) => Ok(true),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
                Err(source) => Err(WorktreeError::LocalIo {
                    operation: "stat worktree path",
                    source,
                }),
            }
        }
        .boxed()
    }

    fn remove_leaf<'a>(
        &'a self,
        repo_root: &'a Path,
        target_path: &'a Path,
    ) -> BoxFuture<'a, Result<(), WorktreeError>> {
        async move {
            pl_tool::workspace::path_safety::remove_dir_all_no_follow_async(
                &repo_root.join(".anywork/worktrees"),
                target_path,
            )
            .await
            .map_err(|error| match error {
                pl_tool::workspace::path_safety::PathSafetyError::Io {
                    source, operation, ..
                } => WorktreeError::LocalIo { operation, source },
                other => WorktreeError::InvalidResource(other.to_string()),
            })
        }
        .boxed()
    }

    fn create<'a>(
        &'a self,
        repo_root: &'a Path,
        branch: &'a str,
        target_path: &'a Path,
        base_commit: &'a str,
    ) -> BoxFuture<'a, Result<(), WorktreeCreateFailure>> {
        async move {
            self.policy.validate_branch(branch).map_err(|_| {
                WorktreeCreateFailure::no_side_effects(WorktreeError::UnsafeBranch(
                    branch.to_string(),
                ))
            })?;
            let args = vec![
                "worktree".to_string(),
                "add".to_string(),
                "-b".to_string(),
                branch.to_string(),
                local_git_path_argument(target_path),
                base_commit.to_string(),
            ];
            let output =
                self.run_git_output(repo_root, &args)
                    .await
                    .map_err(|error| match error {
                        WorktreeError::GitLaunchFailed { .. } => {
                            WorktreeCreateFailure::no_side_effects(error)
                        }
                        _ => WorktreeCreateFailure::may_have_created(error),
                    })?;
            checked_output(&args, output)
                .map(|_| ())
                .map_err(WorktreeCreateFailure::no_side_effects)
        }
        .boxed()
    }

    fn resolve_head<'a>(
        &'a self,
        worktree_path: &'a Path,
    ) -> BoxFuture<'a, Result<String, WorktreeError>> {
        async move {
            let args = vec!["rev-parse".to_string(), "HEAD".to_string()];
            let output = self.run_git(worktree_path, &args).await?;
            non_empty_head(&args, &output.stdout)
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
            args.push(local_git_path_argument(target_path));
            self.run_git(repo_root, &args).await.map(|_| ())
        }
        .boxed()
    }

    fn delete_branch<'a>(
        &'a self,
        repo_root: &'a Path,
        branch: &'a str,
    ) -> BoxFuture<'a, Result<(), WorktreeError>> {
        async move {
            self.policy
                .validate_branch(branch)
                .map_err(|_| WorktreeError::UnsafeBranch(branch.to_string()))?;
            let args = vec!["branch".to_string(), "-D".to_string(), branch.to_string()];
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

pub(super) fn git_request(cwd: &Path, args: &[String]) -> ExecutionRequest {
    let cwd = dunce::simplified(cwd);
    let mut full_args = vec![
        "-c".to_string(),
        "core.hooksPath=/dev/null".to_string(),
        "-c".to_string(),
        format!("safe.directory={}", cwd.display()),
        "-c".to_string(),
        "credential.helper=".to_string(),
    ];
    #[cfg(windows)]
    full_args.extend(["-c".to_string(), "core.longpaths=true".to_string()]);
    full_args.extend_from_slice(args);
    ExecutionRequest {
        program: PathBuf::from("git"),
        args: full_args,
        cwd: cwd.to_path_buf(),
        env: BTreeMap::from([("LC_ALL".into(), "C".into())]),
        timeout: Some(WORKTREE_GIT_TIMEOUT),
    }
}

fn local_git_path_argument(path: &Path) -> String {
    dunce::simplified(path).to_string_lossy().into_owned()
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
    let mut files = stdout
        .lines()
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

/// One worktree a repository has registered: its path and the branch checked out there.
///
/// `branch` is `None` for a detached worktree, which cannot prove a declared branch.
pub(crate) struct RegisteredWorktree {
    pub path: String,
    pub branch: Option<String>,
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
        let mut branch = None;
        let mut prunable = false;
        for line in block.lines() {
            if let Some(value) = line.strip_prefix("worktree ") {
                path = Some(value.trim().to_string());
            } else if let Some(value) = line.strip_prefix("branch ") {
                branch = value.trim().strip_prefix("refs/heads/").map(str::to_string);
            } else if line.trim() == "prunable" || line.starts_with("prunable ") {
                prunable = true;
            }
        }
        if let Some(path) = path {
            worktrees.push(RegisteredWorktree {
                path,
                branch,
                prunable,
            });
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
/// `git rev-parse --abbrev-ref HEAD` answers `HEAD` for a detached worktree, which proves nothing
/// about the branch a caller declared, so it is reported as "unknown" instead of as a branch name.
pub(super) fn current_branch(output: &ExecutionOutput) -> Option<String> {
    let branch = output.stdout.trim();
    if branch.is_empty() || branch == "HEAD" {
        return None;
    }
    Some(branch.to_string())
}
