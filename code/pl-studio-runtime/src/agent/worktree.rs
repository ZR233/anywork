//! Studio child Agent 的 Git worktree 隔离实现。

mod backend;
mod manager;
mod remote;

pub(crate) use backend::RegisteredWorktree;
pub use backend::{
    LocalWorktreeBackend, WorktreeBackend, WorktreeCreateFailure, WorktreeCreateFailureDisposition,
    WorktreeError, WorktreeStatus,
};
pub use manager::{
    WorktreeCreateSpec, WorktreeHandle, WorktreeManager, WorktreeOwnership,
    WorktreeRetirementRequest, is_pure_branch,
};
pub use pl_tool::remote::{SshManager, SshServerProfile};
pub use remote::RemoteWorktreeBackend;
