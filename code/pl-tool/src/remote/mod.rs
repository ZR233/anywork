//! SSH remote helper 的本地管理、协议客户端与工具宿主。

use crate::environment::ExecutionEnvironment;
pub use bytes::Bytes;
pub use pl_protocol::remote::{RemoteDirectoryEntry, RemoteDirectoryListing, RemoteErrorCode};

mod error;

mod manager;
pub(crate) mod path;
mod ssh_config;

use crate::command::ExecutorCommandBackend;
use crate::workspace_file::ExecutorWorkspaceFileBackend;
pub use error::{SshAuthFailure, SshError};
pub use manager::{
    RemoteHelperAssets, RemoteHelperTarget, SshConnectionSnapshot, SshConnectionState, SshManager,
    SshServerProfile,
};
pub use path::{RemotePathError, normalize_remote_absolute_path};
pub use ssh_config::{
    SshConfigEntry, SshConfigFile, allocate_alias, sanitize_alias_base, validate_alias,
};

/// A frozen SSH endpoint fact and the common execution binding it selected.
/// File, command and Git views are projections of this one concrete executor.
#[derive(Debug, Clone)]
pub struct SshWorkspaceBinding {
    pub profile: std::sync::Arc<SshServerProfile>,
    pub execution: crate::command::WorkspaceExecutionBinding,
    pub execution_environment: ExecutionEnvironment,
}
impl SshWorkspaceBinding {
    pub fn files(&self) -> ExecutorWorkspaceFileBackend {
        self.execution.files()
    }
    pub fn commands(&self) -> ExecutorCommandBackend {
        self.execution.commands(self.execution_environment.clone())
    }
    pub fn git(&self) -> crate::execution::ExecutorExecutionBackend {
        self.execution.git()
    }
}
