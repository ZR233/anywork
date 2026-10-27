//! SSH remote helper 的本地管理、协议客户端与工具宿主。

use crate::environment::ExecutionEnvironment;
pub use pl_protocol::remote::{
    RemoteAllocation, RemoteDirectoryEntry, RemoteDirectoryListing, RemoteErrorCode, RemoteHello,
    RemoteRequest, RemoteResponse, RemoteSession, RemoteSpawnRequest,
};
pub use pl_remote_helper::transport::Bytes;

mod client;
mod command;
mod execution;
mod lsp;
mod manager;
pub(crate) mod path;
mod skill;
mod ssh_config;
mod tools;
mod workspace;

pub use client::{
    RemoteClient, RemoteClientError, RemoteReply, RemoteRequestTiming, SshAuthFailure,
};
pub use command::RemoteCommandBackend;
pub use execution::RemoteExecutionBackend;
pub use manager::{
    RemoteHelperAssets, RemoteHelperTarget, SshConnectionSnapshot, SshConnectionState, SshManager,
    SshServerProfile,
};
pub use path::{RemotePathError, normalize_remote_absolute_path};
pub use skill::RemoteSkillProvider;
pub use ssh_config::{
    SshConfigEntry, SshConfigFile, allocate_alias, sanitize_alias_base, validate_alias,
};
pub use tools::{RemoteMutationKind, RemoteWorkspaceMutationTool};
pub use workspace::{
    RemoteDirectoryReader, RemoteDownloadError, RemoteWorkspaceFileBackend,
    load_remote_workspace_instructions,
};

/// 一个远端 workspace 的本地后端集合。
///
/// 该类型只暴露环境原语；工具名与 schema 由 pl-tool 提供，权限策略与 Turn 装配由宿主负责。
#[derive(Debug, Clone)]
pub struct RemoteWorkspaceHost {
    /// Frozen non-secret endpoint of the exact transport that returned this canonical workspace.
    pub profile: std::sync::Arc<SshServerProfile>,
    pub files: RemoteWorkspaceFileBackend,
    pub commands: RemoteCommandBackend,
    pub git: RemoteExecutionBackend,
    pub execution_environment: ExecutionEnvironment,
}

pub(crate) use lsp::resolve_lsp_query_path;

/// Resource policy configured once by the host for all remote helpers.
pub use pl_remote_helper::budget::ResourcePolicy;
