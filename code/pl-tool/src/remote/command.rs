use std::collections::BTreeMap;
use std::path::Path;

use pl_protocol::remote::{RemoteCapture, RemoteSpawnRequest};
use pl_protocol::{PureError, Result};
use serde_json::Value;

use crate::command::{
    CommandBackend, CommandCaptureOwnership, CommandCaptureStream, CommandOutputSizes,
    CommandOutputTarget, CommandSpawnRequest, ManagedCommand, command_output_model_path,
};

use super::RemoteClient;

#[derive(Debug, Clone)]
pub struct RemoteCommandBackend {
    lease: std::sync::Arc<super::client::workspace::WorkspaceLease>,
    client: RemoteClient,
    workspace_id: String,
}

impl RemoteCommandBackend {
    pub(super) fn new(
        client: RemoteClient,
        lease: std::sync::Arc<super::client::workspace::WorkspaceLease>,
    ) -> Self {
        Self {
            client,
            workspace_id: lease.id.clone(),
            lease,
        }
    }

    fn lease_files(&self) -> super::RemoteWorkspaceFileBackend {
        super::RemoteWorkspaceFileBackend::new(self.client.clone(), self.lease.clone())
    }
    /// 常驻协议进程仅传输 stdin/stdout，不创建命令捕获或消费一次性命令额度。
    pub(super) async fn spawn_stream(
        &self,
        process_id: String,
        command: String,
        cwd: String,
    ) -> Result<ManagedCommand> {
        let (program, arguments) = self
            .client
            .shell_argv(&command)
            .map_err(remote_exec_error)?;
        self.spawn_remote(
            RemoteSpawnRequest {
                process_id,
                workspace_id: self.workspace_id.clone(),
                program,
                arguments,
                remove_environment: vec!["BASH_ENV".into(), "ENV".into()],
                cwd,
                environment: BTreeMap::new(),
                capture: RemoteCapture::None,
                remaining_timeout_ms: None,
            },
            None,
        )
        .await
    }

    async fn spawn_remote(
        &self,
        request: RemoteSpawnRequest,
        start: Option<crate::command::CommandStartControl>,
    ) -> Result<ManagedCommand> {
        self.client
            .spawn_workspace_process(self.lease.clone(), request, start)
            .await
            .map_err(remote_exec_error)
    }
}

impl CommandBackend for RemoteCommandBackend {
    type Error = PureError;

    fn process_capacity(&self) -> Option<usize> {
        Some(self.client.process_capacity())
    }

    fn capture_ownership(&self) -> CommandCaptureOwnership {
        CommandCaptureOwnership::Producer
    }

    fn capture_storage_cost(
        &self,
        _target: &CommandOutputTarget,
        _stream: CommandCaptureStream,
        chunk: &[u8],
    ) -> u64 {
        // Producer 不调用该计价入口；磁盘预算由 helper 执行，客户端仅受传输窗口约束。
        chunk.len() as u64
    }

    async fn resolve_cwd(
        &self,
        cwd: Option<&Path>,
        _allow_workspace_escape: bool,
    ) -> Result<String> {
        normalize_cwd(cwd)
    }

    async fn output_target(
        &self,
        session_id: &str,
        tool_id: &str,
        _call_id: &str,
        _command: &str,
    ) -> Result<CommandOutputTarget> {
        let model_file = path_to_posix(&command_output_model_path(session_id, tool_id))?;
        Ok(CommandOutputTarget::new(model_file.clone(), model_file))
    }

    async fn spawn(&self, request: CommandSpawnRequest) -> Result<ManagedCommand> {
        let (program, arguments) = self
            .client
            .shell_argv(&request.command)
            .map_err(remote_exec_error)?;
        self.spawn_remote(
            RemoteSpawnRequest {
                process_id: request.process_id,
                workspace_id: self.workspace_id.clone(),
                program,
                arguments,
                remove_environment: vec!["BASH_ENV".into(), "ENV".into()],
                cwd: request.cwd,
                environment: BTreeMap::new(),
                capture: RemoteCapture::Files {
                    stdout_path: path_to_posix(request.output_target.capture_file())?,
                    stderr_path: path_to_posix(
                        request
                            .output_target
                            .stream_capture_file(CommandCaptureStream::Stderr),
                    )?,
                    limit_bytes: request.capture_limit_bytes,
                },
                remaining_timeout_ms: Some(
                    request
                        .start_control
                        .deadline()
                        .saturating_duration_since(tokio::time::Instant::now())
                        .as_millis()
                        .min(u64::MAX as u128) as u64,
                ),
            },
            Some(request.start_control),
        )
        .await
    }

    async fn prepare_output(
        &self,
        target: &CommandOutputTarget,
        _command: &str,
        _working_directory: &str,
        _capture_limit_bytes: u64,
    ) -> Result<u64> {
        crate::workspace::prepare_command_capture(&self.lease_files(), target.model_file()).await?;
        // The remote helper owns the capture beside the remote workspace and streams it to the live
        // observer; there is no local fragment, so the local committed length starts at zero.
        Ok(0)
    }

    async fn append_output_chunk(
        &self,
        _target: &CommandOutputTarget,
        _stream: CommandCaptureStream,
        _chunk: &[u8],
    ) -> Result<u64> {
        // The helper writes the full capture next to the remote workspace while streaming bytes.
        Ok(0)
    }

    async fn repair_output_chunk(
        &self,
        _capture_file: &Path,
        _stream: CommandCaptureStream,
        _committed_len: u64,
        _chunk: &[u8],
    ) -> Result<u64> {
        // There is no local fragment for a remote command, so this backend cannot honestly claim a
        // local repair. A remote capture is stored by the helper; a request for a local repair is
        // refused rather than reported as a successful store of bytes this side never wrote.
        Err(PureError::ToolExecutionFailed {
            tool: "exec".to_string(),
            error:
                "the remote command helper owns its capture; there is no local fragment to repair"
                    .to_string(),
        })
    }

    async fn publish_output(&self, _target: &CommandOutputTarget) -> Result<()> {
        Ok(())
    }

    async fn collect_output_artifacts(
        &self,
        _target: &CommandOutputTarget,
        _sizes: CommandOutputSizes,
    ) -> Result<Vec<Value>> {
        Ok(Vec::new())
    }
}

fn normalize_cwd(cwd: Option<&Path>) -> Result<String> {
    let Some(cwd) = cwd else {
        return Ok(".".to_string());
    };
    path_to_posix(cwd)
}

fn path_to_posix(path: &Path) -> Result<String> {
    let value = path.to_string_lossy().replace('\\', "/");
    if value.starts_with('/') {
        return Err(remote_exec_error(
            "exec.cwd must be workspace-relative for SSH; use \".\" for the workspace root",
        ));
    }
    let mut parts = Vec::new();
    for part in value.split('/') {
        match part {
            "" | "." => {}
            ".." => return Err(remote_exec_error("remote command path escapes workspace")),
            value => parts.push(value),
        }
    }
    Ok(if parts.is_empty() {
        ".".to_string()
    } else {
        parts.join("/")
    })
}

fn remote_exec_error(error: impl std::fmt::Display) -> PureError {
    PureError::ToolExecutionFailed {
        tool: "exec".to_string(),
        error: error.to_string(),
    }
}
