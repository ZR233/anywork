//! Receipt loss is injected at the public HTTP/2 boundary, without production test hooks.
use anyhow::{Context, ensure};
use pl_protocol::remote::*;
use pl_remote_helper::{
    budget::{ResourceBudget, ResourcePolicy},
    transport::{self, Bytes, Client},
};
use sha2::{Digest, Sha256};
use std::{
    path::Path,
    process::Stdio,
    time::{Duration, Instant},
};

struct Attachment {
    child: tokio::process::Child,
    wire: Client,
    budget: ResourceBudget,
    session: RemoteSession,
}
impl Attachment {
    async fn open(executable: &Path, session: Option<RemoteSession>) -> anyhow::Result<Self> {
        let mut command = tokio::process::Command::new(executable);
        if let Some(session) = &session {
            command.arg("--attach").arg(&session.socket_path);
        } else {
            command.arg("--serve");
        }
        let mut child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .kill_on_drop(true)
            .spawn()?;
        let allocation = ResourcePolicy::default().allocation()?;
        let budget = ResourceBudget::new(allocation)?;
        let wire = Client::connect(
            transport::Io {
                reader: child.stdout.take().context("stdout")?,
                writer: child.stdin.take().context("stdin")?,
            },
            allocation,
        )
        .await?;
        let request = session.map_or(
            RemoteRequest::Hello {
                protocol_version: REMOTE_PROTOCOL_VERSION,
            },
            |session| RemoteRequest::Attach { session },
        );
        let reply = wire
            .request("handshake", 0, &request, Bytes::new(), &budget)
            .await?;
        let RemoteResponse::Hello(hello) = reply.response else {
            anyhow::bail!("expected hello");
        };
        Ok(Self {
            child,
            wire,
            budget,
            session: hello.session,
        })
    }
    async fn request(
        &self,
        id: &str,
        request: RemoteRequest,
        body: &[u8],
    ) -> anyhow::Result<RemoteResponse> {
        let reply = self
            .wire
            .request(
                id,
                self.session.epoch,
                &request,
                Bytes::copy_from_slice(body),
                &self.budget,
            )
            .await?;
        match reply.response {
            RemoteResponse::Error(error) => anyhow::bail!("{error:?}"),
            response => Ok(response),
        }
    }
    async fn release(&self, id: &str) -> anyhow::Result<()> {
        self.request(
            "release",
            RemoteRequest::ReleaseOperation {
                operation_id: id.into(),
            },
            &[],
        )
        .await?;
        Ok(())
    }
    async fn close(mut self) -> anyhow::Result<()> {
        self.request("shutdown", RemoteRequest::Shutdown, &[])
            .await?;
        self.wire.close().await?;
        ensure!(
            tokio::time::timeout(Duration::from_secs(5), self.child.wait())
                .await??
                .success()
        );
        Ok(())
    }
}
pub async fn verify(executable: &Path) -> anyhow::Result<()> {
    let root = tempfile::tempdir()?;
    let mut attachment = Attachment::open(executable, None).await?;
    let outcome = exercise(executable, root.path(), &mut attachment).await;
    let close = attachment.close().await;
    outcome?;
    close?;
    println!("RETAINED_RECEIPT_ACCEPTANCE=PASS");
    Ok(())
}
async fn reconnect(executable: &Path, current: &mut Attachment) -> anyhow::Result<()> {
    let session = current.session.clone();
    let started = Instant::now();
    // Establish a new attachment while the old one is still alive: successful authentication
    // must fence the old epoch before any recovery query can declare an operation absent.
    let replacement = Attachment::open(executable, Some(session.clone())).await?;
    ensure!(
        replacement.session.instance_id == session.instance_id
            && replacement.session.epoch > session.epoch
    );
    let old = std::mem::replace(current, replacement);
    old.wire.close().await?;
    let mut child = old.child;
    tokio::time::timeout(Duration::from_secs(5), child.wait()).await??;
    let stale = current
        .wire
        .request(
            "stale",
            session.epoch,
            &RemoteRequest::Heartbeat,
            Bytes::new(),
            &current.budget,
        )
        .await?;
    ensure!(matches!(
        stale.response,
        RemoteResponse::Error(RemoteError {
            code: RemoteErrorCode::StaleConnection,
            ..
        })
    ));
    println!(
        "{}",
        serde_json::json!({"scenario":"receipt-recovery", "durationMs":started.elapsed().as_secs_f64()*1000.0, "oldEpochRejected":true})
    );
    Ok(())
}
async fn exercise(
    executable: &Path,
    root: &Path,
    attachment: &mut Attachment,
) -> anyhow::Result<()> {
    let workspace = attachment
        .request(
            "workspace",
            RemoteRequest::OpenWorkspace {
                path: root.to_string_lossy().into_owned(),
            },
            &[],
        )
        .await?;
    let RemoteResponse::WorkspaceOpened(workspace) = workspace else {
        anyhow::bail!("workspace");
    };
    attachment.release("workspace").await?;
    let target = |path: &str| RemotePathRequest {
        workspace_id: workspace.workspace_id.clone(),
        path: path.into(),
    };
    // Discard the returned spawn acknowledgement before receipt release. Recovery must return
    // the retained fact, not create another process. A visible file detects any duplicate spawn.
    attachment.request("spawn", RemoteRequest::Spawn(RemoteSpawnRequest {
        process_id: "receipt-command".into(), workspace_id: workspace.workspace_id.clone(), program: "/bin/sh".into(),
        arguments: vec!["-c".into(), "printf start >> starts; IFS= read -r line; printf '%s' \"$line\" > stdin-result".into()],
        cwd: ".".into(), remove_environment: vec![], environment: Default::default(), capture: RemoteCapture::None,
                remaining_timeout_ms: None,
    }), &[]).await?;
    reconnect(executable, attachment).await?;
    let recovered = attachment
        .request(
            "spawn-query",
            RemoteRequest::OperationResult {
                operation_id: "spawn".into(),
            },
            &[],
        )
        .await?;
    ensure!(matches!(recovered, RemoteResponse::ProcessSpawned { .. }));
    attachment.release("spawn").await?;
    attachment
        .request(
            "stdin",
            RemoteRequest::WriteStdin {
                process_id: "receipt-command".into(),
                offset: 0,
            },
            b"exactly-once\n",
        )
        .await?;
    reconnect(executable, attachment).await?;
    let offset = attachment
        .request(
            "stdin-query",
            RemoteRequest::OperationResult {
                operation_id: "stdin".into(),
            },
            &[],
        )
        .await?;
    ensure!(matches!(offset, RemoteResponse::InputOffset { offset: 13 }));
    attachment.release("stdin").await?;
    attachment
        .request(
            "wait",
            RemoteRequest::WaitProcess {
                process_id: "receipt-command".into(),
            },
            &[],
        )
        .await?;
    ensure!(std::fs::read(root.join("starts"))? == b"start");
    ensure!(std::fs::read(root.join("stdin-result"))? == b"exactly-once");
    attachment
        .request(
            "process-release",
            RemoteRequest::ReleaseProcess {
                process_id: "receipt-command".into(),
            },
            &[],
        )
        .await?;

    std::fs::write(root.join("append"), b"prefix:")?;
    let opened = attachment
        .request(
            "begin",
            RemoteRequest::BeginWrite(RemoteWriteRequest {
                target: target("append"),
                mode: RemoteWriteMode::Append,
                total_len: 7,
            }),
            &[],
        )
        .await?;
    let RemoteResponse::Transfer(file) = opened else {
        anyhow::bail!("transfer");
    };
    attachment.release("begin").await?;
    let digest = hex::encode(Sha256::digest(b"payload"));
    attachment
        .request(
            "chunk",
            RemoteRequest::WriteChunk {
                transfer_id: file.transfer_id.clone(),
                offset: 0,
                sha256: digest.clone(),
            },
            b"payload",
        )
        .await?;
    reconnect(executable, attachment).await?;
    let chunk = attachment
        .request(
            "chunk-query",
            RemoteRequest::OperationResult {
                operation_id: "chunk".into(),
            },
            &[],
        )
        .await?;
    ensure!(matches!(
        chunk,
        RemoteResponse::ChunkWritten {
            confirmed_offset: 7,
            ..
        }
    ));
    attachment.release("chunk").await?;
    attachment
        .request(
            "commit",
            RemoteRequest::CommitWrite {
                transfer_id: file.transfer_id.clone(),
                length: 7,
                sha256: digest,
            },
            &[],
        )
        .await?;
    reconnect(executable, attachment).await?;
    let commit = attachment
        .request(
            "commit-query",
            RemoteRequest::OperationResult {
                operation_id: "commit".into(),
            },
            &[],
        )
        .await?;
    ensure!(matches!(
        commit,
        RemoteResponse::Transfer(RemoteTransferStatus {
            committed: true,
            offset: 7,
            ..
        })
    ));
    ensure!(std::fs::read(root.join("append"))? == b"prefix:payload");
    attachment.release("commit").await?;
    attachment
        .request(
            "file-close",
            RemoteRequest::CloseTransfer {
                transfer_id: file.transfer_id,
            },
            &[],
        )
        .await?;

    let opened = attachment
        .request("source", RemoteRequest::OpenRead(target("append")), &[])
        .await?;
    let RemoteResponse::Transfer(file) = opened else {
        anyhow::bail!("source");
    };
    attachment.release("source").await?;
    std::fs::write(root.join("append"), b"changed")?;
    let changed = attachment
        .wire
        .request(
            "changed",
            attachment.session.epoch,
            &RemoteRequest::ReadFileChunk {
                transfer_id: file.transfer_id.clone(),
                offset: 0,
                max_bytes: 1,
            },
            Bytes::new(),
            &attachment.budget,
        )
        .await?;
    ensure!(matches!(
        changed.response,
        RemoteResponse::Error(RemoteError {
            code: RemoteErrorCode::SourceChanged,
            ..
        })
    ));
    attachment.release("changed").await?;
    attachment
        .request(
            "source-close",
            RemoteRequest::CloseTransfer {
                transfer_id: file.transfer_id,
            },
            &[],
        )
        .await?;
    #[cfg(unix)]
    {
        ensure!(
            std::process::Command::new("mkfifo")
                .arg(root.join("fifo"))
                .status()?
                .success()
        );
        let rejected = tokio::time::timeout(
            Duration::from_secs(5),
            attachment.request("fifo", RemoteRequest::OpenRead(target("fifo")), &[]),
        )
        .await?;
        ensure!(rejected.is_err(), "special-file read did not fail promptly");
        attachment.release("fifo").await?;
    }
    attachment
        .request(
            "close-workspace",
            RemoteRequest::CloseWorkspace {
                workspace_id: workspace.workspace_id,
            },
            &[],
        )
        .await?;
    let stats = attachment
        .request("heartbeat", RemoteRequest::Heartbeat, &[])
        .await?;
    let RemoteResponse::Heartbeat(stats) = stats else {
        anyhow::bail!("heartbeat");
    };
    ensure!(
        stats.active_connections == 1
            && stats.processes == 0
            && stats.transfers == 0
            && stats.retained_operations == 0
    );
    Ok(())
}
