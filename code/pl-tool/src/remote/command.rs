use std::collections::BTreeMap;
use std::path::Path;

use pl_protocol::remote::{RemoteCapture, RemoteSpawnRequest};
use pl_protocol::{PureError, Result};
use serde_json::Value;

use crate::command::{
    CommandBackend, CommandCaptureOwnership, CommandCaptureReceipt, CommandCaptureStream,
    CommandExit, CommandIo, CommandOutputSizes, CommandOutputTarget, CommandSpawnRequest,
    ManagedCommand, command_output_model_path,
};

use super::RemoteClient;

#[derive(Debug, Clone)]
pub struct RemoteCommandBackend {
    client: RemoteClient,
    workspace_id: String,
}

impl RemoteCommandBackend {
    pub(crate) fn new(client: RemoteClient, workspace_id: String) -> Self {
        Self {
            client,
            workspace_id,
        }
    }
    /// 常驻协议进程仅传输 stdin/stdout，不创建命令捕获或消费一次性命令额度。
    pub(super) async fn spawn_stream(
        &self,
        process_id: String,
        command: String,
        cwd: String,
    ) -> Result<ManagedCommand> {
        self.spawn_remote(RemoteSpawnRequest {
            process_id,
            workspace_id: self.workspace_id.clone(),
            command,
            cwd,
            environment: BTreeMap::new(),
            capture: RemoteCapture::None,
        })
        .await
    }

    async fn spawn_remote(&self, request: RemoteSpawnRequest) -> Result<ManagedCommand> {
        let process_id = request.process_id.clone();
        let expects_capture = matches!(request.capture, RemoteCapture::File { .. });
        let client = self.client.clone();
        let transport = self
            .client
            .spawn_process(request)
            .await
            .map_err(remote_exec_error)?;
        let mut exit = transport.exit;
        Ok(ManagedCommand::new(
            None,
            CommandIo {
                stdin: Some(Box::pin(transport.stdin)),
                stdout: Some(Box::pin(transport.stdout)),
                stderr: Some(Box::pin(transport.stderr)),
            },
            move |cancellation| async move {
                let result = tokio::select! {
                    result = &mut exit => result,
                    _ = cancellation.cancelled() => {
                        // The exit receiver remains owned even if the cancellation RPC fails.
                        let _ = client.terminate_process(&process_id).await;
                        exit.await
                    }
                };
                result
                    .map_err(|_| "remote process exit channel closed".to_string())?
                    .and_then(|exit| {
                        if exit.capture.is_some() != expects_capture {
                            return Err(super::RemoteClientError::Protocol(
                                "capture receipt does not match spawn policy".into(),
                            ));
                        }
                        Ok(CommandExit {
                            exit_code: exit.exit_code,
                            capture: exit.capture.map(|receipt| CommandCaptureReceipt {
                                limit_bytes: receipt.limit_bytes,
                                // helper File 策略只写这一份文件，其精确成本等于文件长度。
                                committed_len: receipt.charged_bytes,
                                charged_bytes: receipt.charged_bytes,
                                refused_bytes: receipt.refused_bytes,
                            }),
                        })
                    })
                    .map_err(|error| error.to_string())
            },
        ))
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
        let model_file = command_output_model_path(session_id, tool_id);
        Ok(CommandOutputTarget::new(model_file.clone(), model_file))
    }

    async fn spawn(&self, request: CommandSpawnRequest) -> Result<ManagedCommand> {
        self.spawn_remote(RemoteSpawnRequest {
            process_id: request.process_id,
            workspace_id: self.workspace_id.clone(),
            command: request.command,
            cwd: request.cwd,
            environment: BTreeMap::new(),
            capture: RemoteCapture::File {
                path: path_to_posix(request.output_target.capture_file())?,
                limit_bytes: request.capture_limit_bytes,
            },
        })
        .await
    }

    async fn prepare_output(
        &self,
        _target: &CommandOutputTarget,
        _command: &str,
        _working_directory: &str,
        _capture_limit_bytes: u64,
    ) -> Result<u64> {
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
