use std::collections::BTreeMap;
use std::path::Path;
use std::sync::Arc;

use pl_protocol::remote::{RemoteCapture, RemoteResourceClass, RemoteSpawnRequest};
use pl_protocol::{PureError, Result};
use serde_json::Value;

use crate::command::{
    CommandBackend, CommandCaptureOwnership, CommandCaptureStream, CommandOutputSizes,
    CommandOutputTarget, CommandSpawnRequest, ManagedCommand, command_output_model_path,
};

use super::manager::{BindingId, Endpoint};

/// 远端 workspace 的命令 backend：进程流、输入与 capture 都在所选物理连接上结算。
#[derive(Debug, Clone)]
pub struct RemoteCommandBackend {
    endpoint: Arc<Endpoint>,
    canonical_path: String,
    binding: BindingId,
}

impl RemoteCommandBackend {
    pub(super) fn new(endpoint: Arc<Endpoint>, canonical_path: String, binding: BindingId) -> Self {
        Self {
            endpoint,
            canonical_path,
            binding,
        }
    }

    fn files(&self) -> super::RemoteWorkspaceFileBackend {
        super::RemoteWorkspaceFileBackend::new(
            self.endpoint.clone(),
            self.canonical_path.clone(),
            self.binding,
        )
    }

    /// 常驻协议进程仅传输 stdin/stdout，不创建命令捕获或消费一次性命令额度。
    pub(super) async fn spawn_stream(
        &self,
        process_id: String,
        command: String,
        cwd: String,
    ) -> Result<ManagedCommand> {
        self.spawn_remote(
            process_id,
            command,
            cwd,
            BTreeMap::new(),
            RemoteCapture::None,
        )
        .await
    }

    async fn spawn_remote(
        &self,
        process_id: String,
        command: String,
        cwd: String,
        environment: BTreeMap<String, String>,
        capture: RemoteCapture,
    ) -> Result<ManagedCommand> {
        let lease = self
            .endpoint
            .acquire(
                &self.canonical_path,
                self.binding,
                RemoteResourceClass::Spawn,
            )
            .await
            .map_err(remote_exec_error)?;
        let workspace_id = lease
            .workspace_id()
            .ok_or_else(|| remote_exec_error("remote operation has no workspace handle"))?
            .to_string();
        lease
            .spawn_process(RemoteSpawnRequest {
                process_id,
                workspace_id,
                command,
                cwd,
                environment,
                capture,
            })
            .await
            .map_err(remote_exec_error)
    }
}

impl CommandBackend for RemoteCommandBackend {
    type Error = PureError;

    fn capture_ownership(&self) -> CommandCaptureOwnership {
        CommandCaptureOwnership::Producer
    }

    fn capture_storage_cost(
        &self,
        _target: &CommandOutputTarget,
        _stream: CommandCaptureStream,
        chunk: &[u8],
    ) -> u64 {
        // Producer 不调用该计价入口；磁盘预算由 helper 执行，客户端仅受传输背压约束。
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
        self.spawn_remote(
            request.process_id,
            request.command,
            request.cwd,
            BTreeMap::new(),
            RemoteCapture::File {
                path: path_to_posix(request.output_target.capture_file())?,
                limit_bytes: request.capture_limit_bytes,
            },
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
        crate::workspace::prepare_command_capture(&self.files(), target.model_file()).await?;
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
