//! Worktree-specific safe failure facts, not a general-purpose secret sanitizer.
use super::{RemoteClientError, RemoteExecutionError, WorktreeError};

impl WorktreeError {
    pub(crate) fn safe_diagnostic(&self) -> String {
        let message = match self {
            Self::Missing => "stat: worktree path not found".into(),
            Self::IdentityMismatch(_) => {
                "worktree registration, common-dir or branch identity mismatch".into()
            }
            Self::GitLaunchFailed { args, message } => format!(
                "git {}: launch failed; {}",
                git_operation(args),
                safe_command_cause(message)
            ),
            Self::GitTimedOut { args } => format!("git {}: timed out", git_operation(args)),
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
            Self::LocalIo { operation, source } => format!(
                "{operation}: filesystem {:?}; os_code={:?}",
                source.kind(),
                source.raw_os_error()
            ),
            Self::Remote { operation, source } => format!("{operation}: {}", remote_code(source)),
            Self::RemoteExecution { args, source } => {
                format!("git {}: {}", git_operation(args), execution_cause(source))
            }
            Self::RemoteFile { operation, source } => format!(
                "{operation}: {}",
                match source {
                    crate::PureError::Io(error) => format!(
                        "remote file I/O {:?}; os_code={:?}",
                        error.kind(),
                        error.raw_os_error()
                    ),
                    crate::PureError::PermissionDenied(_) => "remote file permission denied".into(),
                    _ => "remote file operation failed; no structured cause is available".into(),
                }
            ),
            Self::InvalidResource(_) => "worktree backend or owned-path validation failed".into(),
            Self::UnsafeBranch(_) => "branch validation refused the operation".into(),
            Self::OperationFailedAfterCleanup { operation } => {
                format!("{}; rollback succeeded", operation.safe_diagnostic())
            }
            Self::OperationFailedWithCleanup { operation, cleanup } => format!(
                "{}; rollback failed: {}",
                operation.safe_diagnostic(),
                cleanup.safe_diagnostic()
            ),
            Self::CleanupFailed { failures, .. } => format!(
                "worktree cleanup failed: {}",
                failures
                    .iter()
                    .take(4)
                    .map(Self::safe_diagnostic)
                    .collect::<Vec<_>>()
                    .join("; ")
            ),
        };
        message.chars().take(2048).collect()
    }
}

/// Render the one upstream execution error tree without reflecting arbitrary transport text.
pub(super) fn execution_cause(error: &RemoteExecutionError) -> String {
    match error {
        RemoteExecutionError::WorkingDirectory => {
            "remote working directory invalid or outside workspace".into()
        }
        RemoteExecutionError::Spawn { source } => format!("remote spawn: {}", remote_code(source)),
        RemoteExecutionError::OutputMissing => {
            "remote output acquisition: output stream missing".into()
        }
        RemoteExecutionError::UnexpectedCapture => {
            "remote output collection: unexpected capture receipt".into()
        }
        RemoteExecutionError::Buffer { source } => {
            format!("remote output buffer: {}", remote_code(source))
        }
        RemoteExecutionError::Read { source } => format!(
            "remote output read: {:?}; os_code={:?}",
            source.kind(),
            source.raw_os_error()
        ),
        RemoteExecutionError::Wait { .. } => {
            "remote wait: cause unknown (upstream provides only unstructured text)".into()
        }
        RemoteExecutionError::TimedOut {
            settlement_error: None,
        } => "remote timeout; process exit and output drain completed".into(),
        RemoteExecutionError::TimedOut {
            settlement_error: Some(error),
        } => format!(
            "remote timeout; process/output settlement failed: {}",
            execution_cause(error)
        ),
    }
}

pub(super) fn remote_code(error: &RemoteClientError) -> String {
    match error {
        RemoteClientError::ManagerClosing => "SSH ManagerClosing".into(),
        RemoteClientError::Disconnected => "SSH Disconnected".into(),
        RemoteClientError::Cancelled => "SSH Cancelled before admission".into(),
        RemoteClientError::AuthenticationFailed(_) => "SSH AuthenticationFailed".into(),
        RemoteClientError::Protocol(_) => {
            "SSH Protocol failure (unclassified details withheld)".into()
        }
        RemoteClientError::Remote { code, .. } => format!("remote helper {code:?}"),
    }
}

/// C-locale Git/OS diagnostics select only a closed vocabulary. Never echo a captured line, path,
/// config value or credential. These facts explain failure; they never establish path absence.
fn safe_command_cause(diagnostic: &str) -> &'static str {
    if diagnostic.contains("Permission denied")
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
        (Some("rev-parse"), Some("HEAD")) => "rev-parse HEAD",
        (Some("rev-parse"), Some("--show-toplevel")) => "rev-parse --show-toplevel",
        (Some("status"), _) => "status --porcelain=v1 --untracked-files=all --ignored=matching",
        (Some("branch"), _) => "branch",
        _ => "inspection",
    }
}
