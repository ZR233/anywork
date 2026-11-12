//! Studio child Agent 的 Git worktree 隔离实现。

mod backend;
mod diagnostic;
mod manager;

pub(crate) use backend::RegisteredWorktree;
pub use backend::{
    ExecutorWorktreeBackend, WorktreeBackend, WorktreeCreateFailure,
    WorktreeCreateFailureDisposition, WorktreeError, WorktreeStatus,
};
pub use manager::{
    WorktreeCleanupPolicy, WorktreeCreateSpec, WorktreeHandle, WorktreeManager, WorktreeOwnership,
    WorktreeRetirementRequest,
};
pub use pl_tool::execution::ExecutionFailure;
pub use pl_tool::workspace_file::WorkspaceDownloadError;
