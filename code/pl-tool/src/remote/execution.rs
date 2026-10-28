use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};

use pl_protocol::remote::{RemoteCapture, RemoteSpawnRequest};
use tokio::io::AsyncRead;

use crate::execution::{ExecutionBackend, ExecutionOutput, ExecutionRequest};

use super::path::relative_workspace_path;
use super::{RemoteClient, RemoteClientError};

static NEXT_EXECUTION_ID: AtomicU64 = AtomicU64::new(0);

/// 远端命令失败的阶段；显示文本不包含路径、命令或底层诊断原文。
///
/// 原生来源供宿主分类并安全生成诊断，不能直接展示完整 source 链。
#[derive(thiserror::Error)]
pub enum RemoteExecutionError {
    #[error("remote command working directory is invalid or escapes the workspace")]
    WorkingDirectory,
    #[error("remote command spawn failed")]
    Spawn {
        #[source]
        source: RemoteClientError,
    },
    #[error("remote command output stream is missing")]
    OutputMissing,
    #[error("stream-only remote execution returned an unexpected capture receipt")]
    UnexpectedCapture,
    #[error("remote command output buffer allocation failed")]
    Buffer {
        #[source]
        source: RemoteClientError,
    },
    #[error("remote command output read failed")]
    Read {
        #[source]
        source: std::io::Error,
    },
    /// ManagedCommand 已只提供字符串，不推测其中的远端错误码。
    #[error("remote command wait failed")]
    Wait { reason: String },
    /// 取消后已等待进程退出与输出收束；保留收束失败而不冒称成功。
    #[error("remote command timed out")]
    TimedOut {
        #[source]
        settlement_error: Option<Box<RemoteExecutionError>>,
    },
}

impl std::fmt::Debug for RemoteExecutionError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        std::fmt::Display::fmt(self, formatter)
    }
}

/// 在远端 workspace 中执行宿主传入的 Git/worktree 命令。
#[derive(Debug, Clone)]
pub struct RemoteExecutionBackend {
    lease: std::sync::Arc<super::client::workspace::WorkspaceLease>,
    client: RemoteClient,
    workspace_id: String,
    canonical_root: String,
}

impl RemoteExecutionBackend {
    pub(super) fn new(
        client: RemoteClient,
        lease: std::sync::Arc<super::client::workspace::WorkspaceLease>,
    ) -> Self {
        Self {
            client,
            workspace_id: lease.id.clone(),
            canonical_root: lease.path.clone(),
            lease,
        }
    }
}

impl ExecutionBackend for RemoteExecutionBackend {
    type Error = RemoteExecutionError;

    async fn run(
        &self,
        request: ExecutionRequest,
    ) -> std::result::Result<ExecutionOutput, Self::Error> {
        let sequence = NEXT_EXECUTION_ID
            .fetch_add(1, Ordering::Relaxed)
            .saturating_add(1);
        let process_id = format!("execution-{}-{sequence}", std::process::id());
        let cwd = remote_cwd(&request.cwd, &self.canonical_root)?;
        let mut transport = self
            .client
            .spawn_workspace_process(
                self.lease.clone(),
                RemoteSpawnRequest {
                    process_id: process_id.clone(),
                    workspace_id: self.workspace_id.clone(),
                    program: request.program.to_string_lossy().into_owned(),
                    arguments: request.args,
                    remove_environment: vec!["BASH_ENV".into(), "ENV".into()],
                    cwd,
                    environment: request.env,
                    capture: RemoteCapture::None,
                    remaining_timeout_ms: None,
                },
                None,
            )
            .await
            .map_err(|source| RemoteExecutionError::Spawn { source })?;
        drop(transport.take_stdin());
        let cancellation = transport.cancellation();
        let stdout = transport.take_stdout();
        let stderr = transport.take_stderr();
        let wait = collect_process_output(stdout, stderr, &mut transport, &self.client);
        tokio::pin!(wait);
        let result = match request.timeout {
            Some(timeout) => match tokio::time::timeout(timeout, &mut wait).await {
                Ok(result) => result,
                Err(_) => {
                    cancellation.cancel();
                    return Err(RemoteExecutionError::TimedOut {
                        settlement_error: wait.await.err().map(Box::new),
                    });
                }
            },
            None => wait.await,
        }?;
        Ok(result)
    }
}

async fn collect_process_output(
    stdout: Option<impl AsyncRead + Unpin>,
    stderr: Option<impl AsyncRead + Unpin>,
    command: &mut crate::command::ManagedCommand,
    client: &RemoteClient,
) -> Result<ExecutionOutput, RemoteExecutionError> {
    let (stdout, stderr, exit) = tokio::join!(
        read_all(stdout, client, command.cancellation()),
        read_all(stderr, client, command.cancellation()),
        command.wait()
    );
    // Output failures request cancellation. Report the typed initiating failure rather
    // than replacing it with an untyped wait error caused by that cancellation.
    let stdout = stdout?;
    let stderr = stderr?;
    let exit = exit.map_err(|reason| RemoteExecutionError::Wait { reason })?;
    if exit.capture.is_some() {
        return Err(RemoteExecutionError::UnexpectedCapture);
    }
    Ok(ExecutionOutput {
        status: exit.exit_code.unwrap_or(-1),
        stdout: String::from_utf8_lossy(&stdout).into_owned(),
        stderr: String::from_utf8_lossy(&stderr).into_owned(),
    })
}

async fn read_all(
    reader: Option<impl AsyncRead + Unpin>,
    client: &RemoteClient,
    cancellation: crate::command::CommandCancellation,
) -> Result<Vec<u8>, RemoteExecutionError> {
    let Some(mut reader) = reader else {
        cancellation.cancel();
        return Err(RemoteExecutionError::OutputMissing);
    };
    let mut bytes = match client.resident_buffer(client.content_budget()) {
        Ok(bytes) => bytes,
        Err(source) => {
            cancellation.cancel();
            return Err(RemoteExecutionError::Buffer { source });
        }
    };
    if let Err(error) = tokio::io::copy(&mut reader, &mut bytes).await {
        cancellation.cancel();
        return Err(RemoteExecutionError::Read { source: error });
    }
    Ok(bytes.into_bytes())
}

fn remote_cwd(cwd: &Path, canonical_root: &str) -> Result<String, RemoteExecutionError> {
    relative_workspace_path(canonical_root, cwd)
        .map_err(|()| RemoteExecutionError::WorkingDirectory)
}
