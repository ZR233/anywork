//! Studio child Agent 的 Git worktree 隔离实现。

mod backend;
mod diagnostic;
mod error;
pub(crate) mod git_path;
mod manager;

pub(crate) use backend::RegisteredWorktree;
pub use backend::{ExecutorWorktreeBackend, WorktreeBackend, WorktreeStatus};
pub use error::{WorktreeCreateFailure, WorktreeCreateFailureDisposition, WorktreeError};
pub use manager::{
    WorktreeCleanupPolicy, WorktreeCreateSpec, WorktreeHandle, WorktreeManager, WorktreeOwnership,
    WorktreeRetirementRequest,
};
pub use pl_tool::execution::ExecutionFailure;
pub use pl_tool::workspace_file::WorkspaceDownloadError;
