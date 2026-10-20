use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};

use pl_protocol::remote::{RemoteCapture, RemoteSpawnRequest};
use tokio::io::{AsyncRead, AsyncReadExt};

use crate::execution::{ExecutionBackend, ExecutionOutput, ExecutionRequest};
use crate::shell::shell_quote_word;

use super::RemoteClient;
use super::path::relative_workspace_path;

static NEXT_EXECUTION_ID: AtomicU64 = AtomicU64::new(0);

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
    type Error = String;

    async fn run(
        &self,
        request: ExecutionRequest,
    ) -> std::result::Result<ExecutionOutput, Self::Error> {
        let sequence = NEXT_EXECUTION_ID
            .fetch_add(1, Ordering::Relaxed)
            .saturating_add(1);
        let process_id = format!("execution-{}-{sequence}", std::process::id());
        let cwd = remote_cwd(&request.cwd, &self.canonical_root)?;
        let command = std::iter::once(request.program.to_string_lossy().into_owned())
            .chain(request.args)
            .map(|part| shell_quote_word(&part))
            .collect::<Vec<_>>()
            .join(" ");
        let mut transport = self
            .client
            .spawn_workspace_process(
                self.lease.clone(),
                RemoteSpawnRequest {
                    process_id: process_id.clone(),
                    workspace_id: self.workspace_id.clone(),
                    command,
                    cwd,
                    environment: request.env,
                    capture: RemoteCapture::None,
                },
            )
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
