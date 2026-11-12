//! SSH remote helper 的本地管理、协议客户端与工具宿主。

use crate::environment::ExecutionEnvironment;
pub use bytes::Bytes;
pub use pl_protocol::remote::{RemoteDirectoryEntry, RemoteDirectoryListing, RemoteErrorCode};

mod error;

mod lsp;
mod manager;
pub(crate) mod path;
mod skill;
mod ssh_config;

use crate::command::ExecutorCommandBackend;
use crate::workspace_file::ExecutorWorkspaceFileBackend;
pub use error::{SshAuthFailure, SshError};
pub use manager::{
    RemoteHelperAssets, RemoteHelperTarget, SshConnectionSnapshot, SshConnectionState, SshManager,
    SshServerProfile,
};
pub use path::{RemotePathError, normalize_remote_absolute_path};
pub use skill::RemoteSkillProvider;
pub use ssh_config::{
    SshConfigEntry, SshConfigFile, allocate_alias, sanitize_alias_base, validate_alias,
};

/// 一个远端 workspace 的本地后端集合。
///
/// 该类型只暴露环境原语；工具名与 schema 由 pl-tool 提供，权限策略与 Turn 装配由宿主负责。
#[derive(Debug, Clone)]
pub struct RemoteWorkspaceHost {
    /// Frozen non-secret endpoint of the exact transport that returned this canonical workspace.
    pub profile: std::sync::Arc<SshServerProfile>,
    pub files: ExecutorWorkspaceFileBackend,
    pub commands: ExecutorCommandBackend,
    pub git: crate::execution::ExecutorExecutionBackend,
    pub execution_environment: ExecutionEnvironment,
}

pub(crate) use lsp::resolve_lsp_query_path;
