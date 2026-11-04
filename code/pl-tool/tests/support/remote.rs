//! Isolated real-helper acceptance fixture. No simulated framing or production-data access.
use anyhow::{Context, ensure};
use pl_protocol::remote::*;
use pl_tool::remote::RemoteClient;
use std::{path::Path, process::Stdio, time::Duration};
use tokio_util::sync::CancellationToken;

pub struct Helper {
    pub client: RemoteClient,
    pub workspace: String,
    pub root: tempfile::TempDir,
    pub(super) relay: tokio::process::Child,
    pub(super) heartbeat_stop: CancellationToken,
    pub(super) heartbeat: tokio::task::JoinHandle<()>,
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
        heartbeat(&client).await?;
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
            root,
            relay,
            heartbeat_stop,
            heartbeat,
        })
    }
    pub async fn close(mut self) -> anyhow::Result<()> {
        self.heartbeat_stop.cancel();
        self.heartbeat.await?;
        self.client.close().await?;
        tokio::time::timeout(Duration::from_secs(8), self.relay.wait()).await??;
        Ok(())
    }
}
pub(super) fn spawn_relay(
    executable: &Path,
    socket: Option<&str>,
) -> anyhow::Result<tokio::process::Child> {
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
