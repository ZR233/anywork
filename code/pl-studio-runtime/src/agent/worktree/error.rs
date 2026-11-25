use pl_tool::execution::ExecutionFailure;

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
