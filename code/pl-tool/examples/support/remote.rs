//! Isolated real-helper acceptance fixture. No simulated framing or production-data access.
use anyhow::{Context, ensure};
use pl_protocol::remote::*;
use pl_tool::{command::ManagedCommand, remote::RemoteClient};
use std::{
    path::{Path, PathBuf},
    process::Stdio,
    time::Duration,
};
use tokio::io::AsyncReadExt;
use tokio_util::sync::CancellationToken;

pub struct Helper {
    pub client: RemoteClient,
    pub workspace: String,
    pub owner_pid: u32,
    pub root: tempfile::TempDir,
    executable: PathBuf,
    relay: tokio::process::Child,
    heartbeat_stop: CancellationToken,
    heartbeat: tokio::task::JoinHandle<()>,
}
impl Helper {
    pub async fn start(executable: &Path) -> anyhow::Result<Self> {
        let root = tempfile::tempdir()?;
        let mut relay = spawn_relay(executable, None)?;
        let client = RemoteClient::from_streams(
            relay.stdout.take().context("stdout")?,
            relay.stdin.take().context("stdin")?,
        )
        .await?;
        client
            .request(
                RemoteRequest::Hello {
                    protocol_version: REMOTE_PROTOCOL_VERSION,
                },
                &[],
            )
            .await?;
        let opened = client
            .request(
                RemoteRequest::OpenWorkspace {
                    path: root.path().to_string_lossy().into_owned(),
                },
                &[],
            )
            .await?;
        let RemoteResponse::WorkspaceOpened(opened) = opened.response else {
            anyhow::bail!("expected workspace");
        };
        let stats = heartbeat(&client).await?;
        let stop = CancellationToken::new();
        let heartbeat_stop = stop.clone();
        let observer = client.clone();
        let heartbeat = tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(5));
            interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
            loop {
                tokio::select! { _ = stop.cancelled() => break, _ = interval.tick() => {} }
                tokio::select! {
                    _ = stop.cancelled() => break,
                    result = observer.request(RemoteRequest::Heartbeat, &[]) => if result.is_err() { break; },
                }
            }
        });
        Ok(Self {
            client,
            workspace: opened.workspace_id,
            owner_pid: stats.owner_pid,
            root,
            executable: executable.to_owned(),
            relay,
            heartbeat_stop,
            heartbeat,
        })
    }
    pub fn target(&self, path: &str) -> RemotePathRequest {
        RemotePathRequest {
            workspace_id: self.workspace.clone(),
            path: path.into(),
        }
    }
    pub async fn command(&self, id: &str, command: &str) -> anyhow::Result<ManagedCommand> {
        Ok(self
            .client
            .spawn_process(RemoteSpawnRequest {
                process_id: id.into(),
                workspace_id: self.workspace.clone(),
                program: "/bin/sh".into(),
                arguments: vec!["-c".into(), command.into()],
                remove_environment: vec![],
                cwd: ".".into(),
                environment: Default::default(),
                capture: RemoteCapture::None,
            })
            .await?)
    }
    pub async fn reconnect(&mut self) -> anyhow::Result<()> {
        let before = self.client.session().context("session identity")?;
        self.relay.kill().await.ok();
        self.relay.wait().await?;
        let mut relay = spawn_relay(&self.executable, Some(&before.socket_path))?;
        let hello = self
            .client
            .reattach(
                relay.stdout.take().context("stdout")?,
                relay.stdin.take().context("stdin")?,
            )
            .await?;
        ensure!(
            hello.session.instance_id == before.instance_id && hello.session.epoch > before.epoch
        );
        self.relay = relay;
        ensure!(
            heartbeat(&self.client).await?.owner_pid == self.owner_pid,
            "helper process was restarted"
        );
        Ok(())
    }
    #[cfg(target_os = "linux")]
    pub async fn expire(self) -> anyhow::Result<()> {
        use std::os::fd::{FromRawFd, OwnedFd};
        // SAFETY: pidfd_open returns a fresh descriptor for this fixture's recorded helper PID.
        // No pointer arguments are passed; only a successful descriptor is claimed once below.
        let descriptor = unsafe { libc::syscall(libc::SYS_pidfd_open, self.owner_pid, 0) };
        ensure!(
            descriptor >= 0,
            "pidfd_open failed: {}",
            std::io::Error::last_os_error()
        );
        // SAFETY: the successful syscall transferred a new owned fd; there is no other owner.
        let descriptor = unsafe { OwnedFd::from_raw_fd(descriptor as i32) };
        // SAFETY: AsyncFd exclusively owns this OwnedFd until drop. No raw close, replacement
        // or descriptor duplication can invalidate its stable AsRawFd identity.
        let exit = unsafe { tokio::io::unix::AsyncFd::register(descriptor)? };
        self.heartbeat_stop.cancel();
        self.heartbeat.await?;
        let started = std::time::Instant::now();
        let _ = tokio::time::timeout(Duration::from_secs(40), exit.readable()).await??;
        let mut relay = self.relay;
        tokio::time::timeout(Duration::from_secs(5), relay.wait()).await??;
        // Physical exit was observed through pidfd; the disconnected logical client can no
        // longer receive a shutdown receipt, so close its local owners separately.
        let local_close = self.client.close().await;
        println!(
            "{}",
            serde_json::json!({"scenario":"lease-expiry", "seconds":started.elapsed().as_secs_f64(),
            "physicalExitObserved":true, "localCloseDiagnostic":local_close.err().map(|error| error.to_string())})
        );
        Ok(())
    }
    pub async fn close_during_attachment(mut self) -> anyhow::Result<()> {
        self.heartbeat_stop.cancel();
        self.heartbeat.await?;
        let session = self.client.session().context("session identity")?;
        let mut replacement = spawn_relay(&self.executable, Some(&session.socket_path))?;
        let (release, gate) = tokio::sync::oneshot::channel();
        let reader = GatedRead {
            reader: replacement.stdout.take().context("replacement stdout")?,
            gate: Some(gate),
        };
        let writer = replacement.stdin.take().context("replacement stdin")?;
        let client = self.client.clone();
        let attaching = tokio::spawn(async move { client.reattach(reader, writer).await });
        // The real helper fences the old attachment before its delayed Hello receipt is consumed.
        tokio::time::timeout(Duration::from_secs(10), self.client.wait_disconnected()).await?;
        let closing = self.client.close();
        tokio::pin!(closing);
        ensure!(
            futures::poll!(&mut closing).is_pending(),
            "close did not join the submitted attachment"
        );
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("attachment receipt gate retired early"))?;
        let (attached, closed) = tokio::join!(attaching, closing);
        let attached = attached??;
        ensure!(attached.session.instance_id == session.instance_id);
        closed?;
        ensure!(
            self.client.generation() == 0 && self.client.is_disconnected(),
            "late attachment resurrected a closed client"
        );
        tokio::time::timeout(Duration::from_secs(5), self.relay.wait()).await??;
        tokio::time::timeout(Duration::from_secs(5), replacement.wait()).await??;
        println!("ATTACHMENT_CLOSE_OWNERSHIP=PASS");
        Ok(())
    }
    pub async fn close(mut self) -> anyhow::Result<()> {
        self.heartbeat_stop.cancel();
        self.heartbeat.await?;
        self.client.close().await?;
        tokio::time::timeout(Duration::from_secs(8), self.relay.wait()).await??;
        Ok(())
    }
}
fn spawn_relay(executable: &Path, socket: Option<&str>) -> anyhow::Result<tokio::process::Child> {
    let mut command = tokio::process::Command::new(executable);
    if let Some(socket) = socket {
        command.arg("--attach").arg(socket);
    } else {
        command.arg("--serve");
    }
    Ok(command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .kill_on_drop(true)
        .spawn()?)
}
pub async fn heartbeat(client: &RemoteClient) -> anyhow::Result<RemoteHeartbeat> {
    let response = tokio::time::timeout(
        Duration::from_secs(10),
        client.request(RemoteRequest::Heartbeat, &[]),
    )
    .await??;
    let RemoteResponse::Heartbeat(stats) = response.response else {
        anyhow::bail!("expected heartbeat resources");
    };
    ensure!(
        stats.active_connections == 1,
        "helper does not have exactly one current attachment"
    );
    Ok(stats)
}
pub async fn drain(mut command: ManagedCommand) -> anyhow::Result<(Vec<u8>, Vec<u8>)> {
    drop(command.take_stdin());
    let mut stdout = command.take_stdout().context("stdout")?;
    let mut stderr = command.take_stderr().context("stderr")?;
    let (out, err, exit) = tokio::join!(
        async {
            let mut bytes = Vec::new();
            stdout.read_to_end(&mut bytes).await?;
            anyhow::Ok(bytes)
        },
        async {
            let mut bytes = Vec::new();
            stderr.read_to_end(&mut bytes).await?;
            anyhow::Ok(bytes)
        },
        command.wait()
    );
    let exit = exit.map_err(anyhow::Error::msg)?;
    ensure!(
        exit.exit_code == Some(0),
        "command exited unsuccessfully: {exit:?}"
    );
    Ok((out?, err?))
}
pub async fn write_file(
    client: &RemoteClient,
    target: RemotePathRequest,
    bytes: &[u8],
) -> anyhow::Result<()> {
    use sha2::{Digest, Sha256};
    let opened = client
        .request(
            RemoteRequest::BeginWrite(RemoteWriteRequest {
                target,
                mode: RemoteWriteMode::Overwrite,
                total_len: bytes.len() as u64,
            }),
            &[],
        )
        .await?;
    let RemoteResponse::Transfer(opened) = opened.response else {
        anyhow::bail!("expected write handle");
    };
    let mut offset = 0;
    while offset < bytes.len() {
        let end = offset
            .saturating_add(client.fragment_bytes())
            .min(bytes.len());
        client
            .request(
                RemoteRequest::WriteChunk {
                    transfer_id: opened.transfer_id.clone(),
                    offset: offset as u64,
                    sha256: hex::encode(Sha256::digest(&bytes[offset..end])),
                },
                &bytes[offset..end],
            )
            .await?;
        offset = end;
    }
    client
        .request(
            RemoteRequest::CommitWrite {
                transfer_id: opened.transfer_id.clone(),
                length: bytes.len() as u64,
                sha256: hex::encode(Sha256::digest(bytes)),
            },
            &[],
        )
        .await?;
    client
        .request(
            RemoteRequest::CloseTransfer {
                transfer_id: opened.transfer_id,
            },
            &[],
        )
        .await?;
    Ok(())
}
pub fn resources(pid: u32) -> serde_json::Value {
    let root = PathBuf::from(format!("/proc/{pid}"));
    let status = std::fs::read_to_string(root.join("status")).unwrap_or_default();
    let rss = status
        .lines()
        .find(|line| line.starts_with("VmRSS:"))
        .unwrap_or("")
        .to_owned();
    let cpu = std::fs::read_to_string(root.join("stat"))
        .ok()
        .and_then(|stat| {
            let fields = stat
                .rsplit_once(") ")?
                .1
                .split_whitespace()
                .collect::<Vec<_>>();
            Some(
                fields
                    .get(11)?
                    .parse::<u64>()
                    .ok()?
                    .saturating_add(fields.get(12)?.parse::<u64>().ok()?),
            )
        });
    serde_json::json!({"cpuTicks":cpu, "fd":std::fs::read_dir(root.join("fd")).map(|entries| entries.count()).ok(),
        "threads":std::fs::read_dir(root.join("task")).map(|entries| entries.count()).ok(), "rss":rss})
}

struct GatedRead<R> {
    reader: R,
    gate: Option<tokio::sync::oneshot::Receiver<()>>,
}
impl<R: tokio::io::AsyncRead + Unpin> tokio::io::AsyncRead for GatedRead<R> {
    fn poll_read(
        mut self: std::pin::Pin<&mut Self>,
        context: &mut std::task::Context<'_>,
        bytes: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        use std::task::Poll;
        if let Some(gate) = &mut self.gate {
            match std::pin::Pin::new(gate).poll(context) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Ok(())) => self.gate = None,
                Poll::Ready(Err(_)) => {
                    return Poll::Ready(Err(std::io::Error::new(
                        std::io::ErrorKind::Interrupted,
                        "attachment gate cancelled",
                    )));
                }
            }
        }
        std::pin::Pin::new(&mut self.reader).poll_read(context, bytes)
    }
}
