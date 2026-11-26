//! Worktree-specific safe failure facts, not a general-purpose secret sanitizer.
use super::{ExecutionFailure, WorkspaceDownloadError, WorktreeError};

impl WorktreeError {
    pub(crate) fn safe_diagnostic(&self) -> String {
        let message = match self {
            Self::Missing => "stat: worktree path not found".into(),
            Self::MissingHead => "工作区没有有效的 HEAD commit；请先完成初始 commit 后重试".into(),
            // Identity messages are produced only from fixed application vocabulary, never stderr.
            Self::IdentityMismatch(reason) => format!("worktree identity: {reason}"),
            Self::GitExited {
                args,
                exit_code,
                stderr,
            } => format!(
                "git {}: exited with code {exit_code}; {}",
                git_operation(args),
                safe_command_cause(stderr)
            ),
            Self::GitStatusUnknown { args, stderr } => format!(
                "git {}: execution outcome unknown; {}",
                git_operation(args),
                safe_command_cause(stderr)
            ),
            Self::Target { operation, source } => format!("{operation}: {}", file_cause(source)),
            Self::Execution { args, source } => {
                format!("git {}: {}", git_operation(args), execution_cause(source))
            }
            Self::Download { operation, source } => {
                format!("{operation}: {}", download_cause(source))
            }
            Self::File { operation, source } => format!(
                "{operation}: {}",
                match source {
                    crate::PureError::Io(error) => format!(
                        "target file I/O {:?}; os_code={:?}",
                        error.kind(),
                        error.raw_os_error()
                    ),
                    crate::PureError::PermissionDenied(_) => "target file permission denied".into(),
                    _ => "target file operation failed; no structured cause is available".into(),
                }
            ),
            Self::InvalidResource(_) => "worktree backend or owned-path validation failed".into(),
        };
        message.chars().take(2048).collect()
    }
}

/// Preserve the transfer phase and typed cause without reflecting paths or arbitrary helper text.
pub(super) fn download_cause(error: &WorkspaceDownloadError) -> String {
    match error {
        WorkspaceDownloadError::Path(source) => file_cause(source),
        WorkspaceDownloadError::Open(source) => execution_error(source),
        WorkspaceDownloadError::Io(source) | WorkspaceDownloadError::Read(source) => format!(
            "file transfer IO {:?}; os={:?}",
            source.kind(),
            source.raw_os_error()
        ),
        WorkspaceDownloadError::TooLarge { limit } => {
            format!("file transfer exceeds {limit} bytes")
        }
        WorkspaceDownloadError::Incomplete => "file transfer incomplete".into(),
    }
}
pub(super) fn execution_cause(error: &ExecutionFailure) -> String {
    match error {
        ExecutionFailure::Spawn(source) => format!(
            "spawn {:?}: {}",
            source.knowledge,
            execution_error(&source.cause)
        ),
        ExecutionFailure::Execution(source) => execution_error(source),
        ExecutionFailure::TimedOut => "command timed out; cleanup is owned by the executor".into(),
    }
}
fn execution_error(error: &pl_remote_helper::ExecutionError) -> String {
    use pl_remote_helper::ExecutionError;
    match error {
        ExecutionError::Io { source, .. } => {
            format!("IO {:?}; os={:?}", source.kind(), source.raw_os_error())
        }
        ExecutionError::TargetIo(source) => {
            format!("target IO {:?}; os={:?}", source.kind, source.raw_os_error)
        }
        ExecutionError::InvalidInput(_) => "invalid execution input".into(),
        ExecutionError::Disconnected(_) => "execution disconnected; result may be unknown".into(),
        ExecutionError::Protocol(_) | ExecutionError::ProtocolMismatch { .. } => {
            "execution protocol failure".into()
        }
        ExecutionError::Cancelled => "execution cancelled".into(),
        ExecutionError::CollectFailed { cause, .. } => {
            format!("output incomplete: {}", execution_error(cause))
        }
        ExecutionError::Http(_) => "HTTP egress failed".into(),
    }
}

/// C-locale Git/OS diagnostics select only a closed vocabulary. Never echo a captured line, path,
/// config value or credential. These facts explain failure; they never establish path absence.
fn safe_command_cause(diagnostic: &str) -> &'static str {
    if diagnostic
        .lines()
        .any(|line| line.ends_with(": No space left on device"))
    {
        "project host has no free disk space; free space before retrying"
    } else if diagnostic
        .lines()
        .any(|line| line.ends_with(": Disk quota exceeded"))
    {
        "project host disk quota exceeded; free space within the quota before retrying"
    } else if diagnostic.contains("Permission denied")
        || diagnostic.contains("Operation not permitted")
        || diagnostic.contains("Access is denied")
    {
        "permission denied"
    } else if diagnostic.contains("bad config line")
        || diagnostic.contains("invalid config")
        || diagnostic.contains("bad boolean config value")
        || diagnostic.contains("bad numeric config value")
        || diagnostic.contains("bad configuration")
        || diagnostic.contains("unable to read config file")
    {
        "Git configuration could not be parsed or read"
    } else if diagnostic.contains("not a git repository") {
        "Git repository identity is unavailable"
    } else if diagnostic.contains("is locked")
        || diagnostic.contains("locked working tree")
        || diagnostic.contains("locked worktree")
        || diagnostic.contains("Unable to create") && diagnostic.contains(".lock")
    {
        "Git resource is locked or its lock cannot be created"
    } else if diagnostic.contains("contains modified or untracked files")
        || diagnostic.contains("contains submodules")
    {
        "Git refused removal of local content or submodules"
    } else if diagnostic.contains("No such file or directory") {
        "command or command input could not be opened (does not establish worktree absence)"
    } else if diagnostic.contains("Too many open files") {
        "process file descriptor limit exceeded"
    } else if diagnostic
        .lines()
        .any(|line| line.starts_with("error: unable to write file "))
    {
        // Git can report a checkout write failure without its underlying OS error.
        "Git could not write checkout files; check disk space, quota, and write permissions on the project host"
    } else {
        "unclassified Git/process failure; unsafe free-form details withheld"
    }
}

pub(super) fn git_operation(args: &str) -> &'static str {
    let mut args = args.split_whitespace();
    match (args.next(), args.next()) {
        (Some("worktree"), Some("list")) => "worktree list --porcelain",
        (Some("worktree"), Some("remove")) => "worktree remove",
        (Some("worktree"), Some("add")) => "worktree add",
        (Some("rev-parse"), Some("--git-common-dir")) => "rev-parse --git-common-dir",
        (Some("rev-parse"), Some("--abbrev-ref")) => "rev-parse --abbrev-ref HEAD",
        (Some("rev-parse"), Some("--verify")) => "rev-parse --verify --quiet HEAD^{commit}",
        (Some("rev-parse"), Some("--absolute-git-dir")) => "rev-parse --absolute-git-dir",
        (Some("rev-parse"), Some("HEAD")) => "rev-parse HEAD",
        (Some("rev-parse"), Some("--show-toplevel")) => "rev-parse --show-toplevel",
        (Some("merge-base"), Some("--is-ancestor")) => "merge-base --is-ancestor",
        (Some("status"), _) => "status --porcelain=v1 --untracked-files=all --ignored=matching",
        _ => "inspection",
    }
}

pub(super) fn file_cause(error: &pl_tool::workspace_file::WorkspaceFileError) -> String {
    use pl_tool::workspace_file::WorkspaceFileError;
    match error {
        WorkspaceFileError::Execution(source) => execution_error(source),
        WorkspaceFileError::Removal(source) => {
            format!("removal unconfirmed: {}", execution_error(source))
        }
        WorkspaceFileError::Policy(_) => "workspace path policy rejected".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::{WorktreeError, git_operation};

    #[test]
    fn worktree_checkout_failures_report_actionable_causes_without_echoing_stderr() {
        for (stderr, cause) in [
            (
                "fatal: could not write '/private-checkout/index.lock': No space left on device",
                "project host has no free disk space; free space before retrying",
            ),
            (
                "fatal: could not write '/private-checkout/index.lock': Disk quota exceeded",
                "project host disk quota exceeded; free space within the quota before retrying",
            ),
            (
                "error: unable to write file private-checkout/No space left on device\nfatal: Could not reset index file to revision 'HEAD'.",
                "Git could not write checkout files; check disk space, quota, and write permissions on the project host",
            ),
        ] {
            let error = WorktreeError::GitExited {
                args: "worktree add --detach /private-checkout/session abc".into(),
                exit_code: 128,
                stderr: stderr.into(),
            };
            assert_eq!(
                error.safe_diagnostic(),
                format!("git worktree add: exited with code 128; {cause}"),
            );
        }
    }

    #[test]
    fn classifies_current_rev_parse_and_merge_base_forms() {
        assert_eq!(
            git_operation("rev-parse --verify --quiet HEAD^{commit}"),
            "rev-parse --verify --quiet HEAD^{commit}"
        );
        assert_eq!(
            git_operation("rev-parse --absolute-git-dir"),
            "rev-parse --absolute-git-dir"
        );
        assert_eq!(
            git_operation("merge-base --is-ancestor a b"),
            "merge-base --is-ancestor"
        );
        assert_eq!(
            git_operation("rev-parse --show-toplevel"),
            "rev-parse --show-toplevel"
        );
    }
}
