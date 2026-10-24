//! Isolated loopback Feishu HTTP/WebSocket peer.
//!
//! Canonical namespace for environment control and evidence. Production bot
//! adapters must not import these types, and this module does not import
//! runtime/protocol/tool/server crates.

mod card;
mod cardkit;
mod control;
mod guard;
mod http;
mod observe;
mod observe_cards;
mod state;
mod types;
mod wire;
mod ws;

pub use control::FeishuControl;
pub use observe::{FeishuObserveOptions, run_feishu_observe};
pub use types::{
    APP_ID_PREFIX, AckObservation, BOT_OPEN_ID, CallBound, CallKind, CardDisposition,
    CardEntityReport, CardObservation, CardOperation, ChatType, ClientConfig, DEFAULT_APP_ID,
    DEFAULT_APP_SECRET, DIRECT_CHAT_ID, EventBody, FeishuLiveStatus, FeishuPeerOptions,
    FeishuReadyFile, FeishuReport, GROUP_CHAT_ID, GroupChat, HistoryMessage, Mention, MentionId,
    OTHER_BOT_OPEN_ID, OutboundWs, PAIRING_DIRECT_CHAT_ID, PollObservation, REGISTERED_APP_ID,
    REGISTERED_APP_SECRET, RecordedCall, RegistrationBeginOptions, RegistrationPollScript,
    RegistrationTenantBrand, SendDisposition, SenderKind, SyntheticEvent, TENANT_ACCESS_TOKEN,
    TRUSTED_USER_OPEN_ID, TokenScript, UNKNOWN_USER_OPEN_ID, WsDiscoveryScript, WsUpgradeScript,
};
pub use wire::{
    FRAME_TYPE_CONTROL, FRAME_TYPE_DATA, HEADER_BIZ_RT, HEADER_HANDSHAKE_AUTHERRCODE,
    HEADER_HANDSHAKE_MSG, HEADER_HANDSHAKE_STATUS, HEADER_MESSAGE_ID, HEADER_SEQ, HEADER_SUM,
    HEADER_TRACE_ID, HEADER_TYPE, ILLEGAL_PBBP2, MESSAGE_TYPE_EVENT, MESSAGE_TYPE_PING,
    MESSAGE_TYPE_PONG, Pbbp2Frame, Pbbp2Header, REQUIRED_TENANT_EVENTS, REQUIRED_TENANT_SCOPES,
    all_mention, decode_addons, encode_addons, other_bot_mention, required_addons, text_event,
    trusted_direct, trusted_user_mention, validate_required_addons,
};

use std::net::SocketAddr;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, bail, ensure};
use axum::Router;
use axum::routing::{get, post};
use tokio::net::TcpListener;
use tokio::sync::{Mutex, oneshot};
use tokio_util::sync::CancellationToken;

use control::join_sockets;
use http::HttpState;
use state::Inner;
use state::JoinSlot;

/// Single owner of the Feishu loopback listener, sockets, and tasks.
pub struct FeishuPeer {
    address: SocketAddr,
    origin: String,
    ws_origin: String,
    shared: state::Shared,
    cancel: CancellationToken,
    shutdown: Option<oneshot::Sender<()>>,
    listener: JoinSlot<std::io::Result<()>>,
    listener_joined: bool,
}

impl FeishuPeer {
    pub async fn start() -> Result<Self> {
        Self::start_with_options(FeishuPeerOptions::default()).await
    }

    pub async fn start_with_options(options: FeishuPeerOptions) -> Result<Self> {
        ensure!(
            options.bind_port != Some(1420),
            "Feishu fixture must not bind reserved port 1420"
        );
        ensure!(
            options.app_id.starts_with(APP_ID_PREFIX),
            "synthetic App ID must start with {APP_ID_PREFIX}"
        );
        ensure!(
            options.registered_app_id.starts_with(APP_ID_PREFIX),
            "registered App ID must start with {APP_ID_PREFIX}"
        );
        let bind = options.bind_port.map_or_else(
            || "127.0.0.1:0".to_owned(),
            |port| format!("127.0.0.1:{port}"),
        );
        let listener = TcpListener::bind(&bind)
            .await
            .with_context(|| format!("feishu fixture could not bind {bind}"))?;
        let address = listener.local_addr()?;
        ensure!(
            address.port() != 1420,
            "Feishu fixture bound reserved port 1420"
        );
        let origin = format!("http://{}", address);
        let ws_origin = format!("ws://{}", address);
        let cancel = CancellationToken::new();
        let shared = Arc::new(Mutex::new(Inner::new(
            options,
            origin.clone(),
            ws_origin.clone(),
        )));
        let http = HttpState {
            shared: shared.clone(),
            cancel: cancel.clone(),
        };
        let app = Router::new()
            .route("/oauth/v1/app/registration", post(http::registration))
            .route("/oauth/v3/token", post(http::tenant_token))
            .route("/open-apis/bot/v3/info", get(http::bot_info))
            .route("/callback/ws/endpoint", post(http::ws_endpoint))
            .route("/callback/ws/connect", get(ws::connect))
            .route("/open-apis/im/v1/chats", get(http::chat_list))
            .route("/open-apis/im/v1/chats/{chat_id}", get(http::chat_get))
            .route(
                "/open-apis/im/v1/chats/{chat_id}/members",
                get(http::chat_members),
            )
            .route(
                "/open-apis/im/v1/messages",
                get(http::message_list).post(http::message_send),
            )
            .route("/open-apis/cardkit/v1/cards", post(cardkit::card_create))
            .route(
                "/open-apis/cardkit/v1/cards/{card_id}/elements/{element_id}/content",
                axum::routing::put(cardkit::card_element_content),
            )
            .route(
                "/open-apis/cardkit/v1/cards/{card_id}/settings",
                axum::routing::patch(cardkit::card_settings),
            )
            .fallback(http::unexpected)
            .with_state(http);
        let (shutdown, receiver) = oneshot::channel();
        let task = tokio::spawn(async move {
            axum::serve(listener, app)
                .with_graceful_shutdown(async move {
                    let _ = receiver.await;
                })
                .await
        });
        Ok(Self {
            address,
            origin,
            ws_origin,
            shared,
            cancel,
            shutdown: Some(shutdown),
            listener: JoinSlot::Pending(task),
            listener_joined: false,
        })
    }

    pub fn address(&self) -> SocketAddr {
        self.address
    }

    /// Canonical HTTP origin without a path suffix.
    pub fn origin(&self) -> &str {
        &self.origin
    }

    /// Canonical WS origin on the same host and port.
    pub fn ws_origin(&self) -> &str {
        &self.ws_origin
    }

    pub fn control(&self) -> FeishuControl {
        FeishuControl {
            shared: self.shared.clone(),
        }
    }

    pub async fn live_status(&self) -> FeishuLiveStatus {
        self.shared.lock().await.live_status()
    }

    pub fn ready_file(&self, scenario: impl Into<String>) -> FeishuReadyFile {
        FeishuReadyFile {
            origin: self.origin.clone(),
            ws_origin: self.ws_origin.clone(),
            address: self.address,
            scenario: scenario.into(),
        }
    }

    /// Cancel, close sockets, join every task, then return evidence.
    pub async fn shutdown(&mut self) -> Result<FeishuReport> {
        self.cancel.cancel();
        let socket_result = join_sockets(&self.shared, &self.cancel).await;
        if let Some(shutdown) = self.shutdown.take() {
            let _ = shutdown.send(());
        }
        let listener_result = self
            .listener
            .join_with_timeout(Duration::from_secs(5))
            .await
            .map_err(|error| anyhow::anyhow!(error));
        if listener_result.is_ok() {
            self.listener_joined = true;
        }
        let listener_joined = self.listener_joined || listener_result.is_ok();
        let sockets_joined = socket_result.is_ok();
        let mut join_error = None;
        if let Err(error) = socket_result {
            join_error = Some(error.to_string());
        }
        if let Err(error) = listener_result {
            join_error = Some(match join_error {
                Some(previous) => format!("{previous}; {error}"),
                None => error.to_string(),
            });
        }
        let report =
            self.shared
                .lock()
                .await
                .report(listener_joined, sockets_joined, join_error.clone());
        Ok(report)
    }

    /// Internal lifecycle probe: listener handle still owned after a join timeout.
    pub(crate) fn listener_pending(&self) -> bool {
        !self.listener.is_joined()
    }
}

impl Drop for FeishuPeer {
    fn drop(&mut self) {
        self.cancel.cancel();
        if let Some(shutdown) = self.shutdown.take() {
            let _ = shutdown.send(());
        }
        self.listener.abort();
    }
}

/// CLI options for `--feishu`. Model GUI scenarios stay unchanged.
pub struct FeishuCliOptions {
    pub ready_file: std::path::PathBuf,
    pub requests_file: Option<std::path::PathBuf>,
    pub report_file: Option<std::path::PathBuf>,
    pub status_file: Option<std::path::PathBuf>,
    pub bind_port: Option<u16>,
}

/// Run the independent Feishu peer until SIGINT/SIGTERM, then write evidence.
pub async fn run_feishu_cli(options: FeishuCliOptions) -> Result<()> {
    let mut peer = FeishuPeer::start_with_options(FeishuPeerOptions {
        bind_port: options.bind_port,
        ..FeishuPeerOptions::default()
    })
    .await?;
    let control = peer.control();
    if let Err(error) = write_json(&options.ready_file, &peer.ready_file("feishu")) {
        if let Some(report) = print_shutdown(&mut peer).await {
            for line in report.diagnostic_lines() {
                println!("{line}");
            }
        }
        return Err(error).context("feishu ready file after cleanup");
    }
    let mut status_watch = None;
    if let Some(path) = options.status_file.clone() {
        let control = control.clone();
        let stop = CancellationToken::new();
        let token = stop.clone();
        status_watch = Some((
            stop,
            tokio::spawn(async move {
                let mut written: Option<FeishuLiveStatus> = None;
                write_status(&path, &mut written, control.live_status().await)?;
                loop {
                    tokio::select! {
                        () = token.cancelled() => break,
                        () = tokio::time::sleep(Duration::from_millis(200)) => {
                            write_status(&path, &mut written, control.live_status().await)?;
                        }
                    }
                }
                Ok::<(), anyhow::Error>(())
            }),
        ));
    }
    let wait_outcome = wait_for_stop(status_watch).await;
    let report = print_shutdown(&mut peer).await;
    match wait_outcome {
        WaitOutcome::Signal => {}
        WaitOutcome::Watcher(result) => {
            if let Err(error) = result {
                if let Some(report) = &report {
                    for line in report.diagnostic_lines() {
                        println!("{line}");
                    }
                }
                return Err(error);
            }
        }
    }
    let Some(report) = report else {
        bail!("feishu shutdown did not produce a report");
    };
    if let Some(path) = options.requests_file.as_ref() {
        write_json(path, &report.calls)?;
    }
    if let Some(path) = options.report_file.as_ref() {
        write_json(path, &report)?;
    }
    for line in report.diagnostic_lines() {
        println!("{line}");
    }
    report.verify()?;
    Ok(())
}

enum WaitOutcome {
    Signal,
    Watcher(Result<()>),
}

type StatusWatch = (
    CancellationToken,
    tokio::task::JoinHandle<anyhow::Result<()>>,
);

fn status_watch_failed(joined: Result<anyhow::Result<()>, tokio::task::JoinError>) -> Result<()> {
    match joined {
        Ok(Ok(())) => Ok(()),
        Ok(Err(error)) => Err(error).context("feishu status file cannot be kept fresh"),
        Err(error) => Err(anyhow::Error::new(error).context("feishu status watcher crashed")),
    }
}

async fn wait_for_stop(status_watch: Option<StatusWatch>) -> WaitOutcome {
    let Some((stop, mut handle)) = status_watch else {
        wait_for_signal().await;
        return WaitOutcome::Signal;
    };
    tokio::select! {
        () = wait_for_signal() => {
            stop.cancel();
            let joined = handle.await;
            match status_watch_failed(joined) {
                Ok(()) => WaitOutcome::Signal,
                Err(error) => WaitOutcome::Watcher(Err(error)),
            }
        }
        joined = &mut handle => WaitOutcome::Watcher(status_watch_failed(joined)),
    }
}

async fn wait_for_signal() {
    #[cfg(unix)]
    {
        if let Ok(mut terminate) =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        {
            tokio::select! {
                _ = tokio::signal::ctrl_c() => {}
                _ = terminate.recv() => {}
            }
            return;
        }
    }
    let _ = tokio::signal::ctrl_c().await;
}

async fn print_shutdown(peer: &mut FeishuPeer) -> Option<FeishuReport> {
    match peer.shutdown().await {
        Ok(report) => Some(report),
        Err(error) => {
            println!(
                "feishu_fixture_failure=shutdown error: {}",
                one_line(&error)
            );
            None
        }
    }
}

fn write_status(
    path: &Path,
    written: &mut Option<FeishuLiveStatus>,
    status: FeishuLiveStatus,
) -> Result<()> {
    if written.as_ref() == Some(&status) {
        return Ok(());
    }
    write_json(path, &status)?;
    *written = Some(status);
    Ok(())
}

fn write_json(path: &Path, value: &impl serde::Serialize) -> Result<()> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(parent)?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    serde_json::to_writer_pretty(&mut temporary, value)?;
    temporary.persist(path).map_err(|error| error.error)?;
    Ok(())
}

fn one_line(error: &anyhow::Error) -> String {
    error.to_string().replace(['\n', '\r'], " ")
}
