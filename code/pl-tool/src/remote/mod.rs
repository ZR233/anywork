//! SSH remote helper 的本地管理、协议客户端与工具宿主。
//!
//! 本模块是远端能力对 pl-tool 其余部分与宿主的唯一出口：这里精确重导出公开签名直接使用的
//! wire 类型与 IO 契约，调用方不需要依赖 `pl_protocol` 或 `tokio` 的具体版本来命名这些类型。

use crate::environment::ExecutionEnvironment;

mod client;
mod command;
mod error;
mod execution;
mod lsp;
mod manager;
pub(crate) mod path;
mod skill;
mod ssh_config;
mod tools;
mod workspace;

pub use client::{RemoteClient, RemoteDirectoryStream, RemoteFileReader};
pub use command::RemoteCommandBackend;
pub use error::{RemoteClientError, SshAuthFailure};
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
    RemoteDownloadError, RemoteWorkspaceFileBackend, load_remote_workspace_instructions,
};

// Wire types and IO traits that appear directly in the public signatures above.
pub use pl_protocol::PureError;
pub use pl_protocol::remote::{
    RemoteDirectoryEntry, RemoteDirectoryListing, RemoteDirectoryMetadata, RemoteErrorCode,
    RemoteFileMetadata, RemoteHello, RemoteReadRequest, RemoteRequest, RemoteResponse,
    RemoteSpawnRequest, RemoteWriteMode, RemoteWriteRequest,
};
pub use tokio::io::{AsyncRead, AsyncWrite};
pub use tokio::task::JoinError;

/// 一个远端 workspace 的本地后端集合。
///
/// 该类型只暴露环境原语；工具名与 schema 由 pl-tool 提供，权限策略与 Turn 装配由宿主负责。
/// 它持有逻辑绑定（endpoint 代次 + canonical 路径），不持有物理 workspace 句柄；每次操作在
/// 当前健康物理连接上取得自己的 workspace/stream 租约。
#[derive(Debug, Clone)]
pub struct RemoteWorkspaceHost {
    pub files: RemoteWorkspaceFileBackend,
    pub commands: RemoteCommandBackend,
    pub git: RemoteExecutionBackend,
    pub execution_environment: ExecutionEnvironment,
}

pub(crate) use lsp::resolve_lsp_query_path;
