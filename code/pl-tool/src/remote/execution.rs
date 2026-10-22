use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use pl_protocol::remote::{RemoteCapture, RemoteResourceClass, RemoteSpawnRequest};
use tokio::io::{AsyncRead, AsyncReadExt};

use crate::execution::{ExecutionBackend, ExecutionOutput, ExecutionRequest};
use crate::shell::shell_quote_word;

use super::manager::{BindingId, Endpoint};
use super::path::relative_workspace_path;

static NEXT_EXECUTION_ID: AtomicU64 = AtomicU64::new(0);

/// 在远端 workspace 中执行宿主传入的 Git/worktree 命令。
///
/// 每次执行在所选物理连接上取得 workspace/stream 租约，进程捕获与退出结算都留在该连接。
#[derive(Debug, Clone)]
pub struct RemoteExecutionBackend {
    endpoint: Arc<Endpoint>,
    canonical_path: String,
    binding: BindingId,
}

impl RemoteExecutionBackend {
    pub(super) fn new(endpoint: Arc<Endpoint>, canonical_path: String, binding: BindingId) -> Self {
        Self {
            endpoint,
            canonical_path,
            binding,
        }
    }
}

impl ExecutionBackend for RemoteExecutionBackend {
    type Error = String;

    async fn run(
        &self,
        request: ExecutionRequest,
    ) -> std::result::Result<ExecutionOutput, Self::Error> {
        let sequence = NEXT_EXECUTION_ID
            .fetch_add(1, Ordering::Relaxed)
            .saturating_add(1);
        let process_id = format!("execution-{}-{sequence}", std::process::id());
        let cwd = remote_cwd(&request.cwd, &self.canonical_path)?;
        let command = std::iter::once(request.program.to_string_lossy().into_owned())
            .chain(request.args)
            .map(|part| shell_quote_word(&part))
            .collect::<Vec<_>>()
            .join(" ");
        let lease = self
            .endpoint
            .acquire(
                &self.canonical_path,
                self.binding,
                RemoteResourceClass::Spawn,
            )
            .await
            .map_err(|error| error.to_string())?;
        let workspace_id = lease
            .workspace_id()
            .ok_or("remote operation has no workspace handle")?
            .to_string();
        let mut transport = lease
            .spawn_process(RemoteSpawnRequest {
                process_id: process_id.clone(),
                workspace_id,
                command,
                cwd,
                environment: request.env,
                capture: RemoteCapture::None,
            })
            .await
            .map_err(|error| error.to_string())?;
        drop(transport.take_stdin());
        let cancellation = transport.cancellation();
        let stdout = transport.take_stdout().ok_or("remote stdout is missing")?;
        let stderr = transport.take_stderr().ok_or("remote stderr is missing")?;
        let wait = collect_process_output(stdout, stderr, &mut transport);
        tokio::pin!(wait);
        let result = match request.timeout {
            Some(timeout) => match tokio::time::timeout(timeout, &mut wait).await {
                Ok(result) => result,
                Err(_) => {
                    cancellation.cancel();
                    return Err(match wait.await {
                        Ok(_) => {
                            "remote command timed out; process exit and output drain completed"
                                .to_string()
                        }
                        Err(error) => format!(
                            "remote command timed out; exit or output drain failed: {error}"
                        ),
                    });
                }
            },
            None => wait.await,
        }?;
        Ok(result)
    }
}

async fn collect_process_output(
    stdout: impl AsyncRead + Unpin,
    stderr: impl AsyncRead + Unpin,
    command: &mut crate::command::ManagedCommand,
) -> Result<ExecutionOutput, String> {
    let (stdout, stderr, exit) = tokio::join!(read_all(stdout), read_all(stderr), command.wait());
    let exit = exit?;
    if exit.capture.is_some() {
        return Err("stream-only execution returned an unexpected capture receipt".into());
    }
    Ok(ExecutionOutput {
        status: exit.exit_code.unwrap_or(-1),
        stdout: String::from_utf8_lossy(&stdout?).into_owned(),
        stderr: String::from_utf8_lossy(&stderr?).into_owned(),
    })
}

async fn read_all(mut reader: impl AsyncRead + Unpin) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    reader
        .read_to_end(&mut bytes)
        .await
        .map_err(|error| format!("failed to read remote process output: {error}"))?;
    Ok(bytes)
}

fn remote_cwd(cwd: &Path, canonical_root: &str) -> Result<String, String> {
    relative_workspace_path(canonical_root, cwd).map_err(|()| {
        format!(
            "remote command cwd '{}' escapes workspace '{canonical_root}'",
            cwd.display()
        )
    })
}
