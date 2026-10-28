//! Listener and socket lifecycle owner for the isolated peer.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, ensure};
use axum::Router;
use axum::extract::DefaultBodyLimit;
use axum::routing::{get, post};
use tokio::net::TcpListener;
use tokio::sync::{Mutex, oneshot};
use tokio_util::sync::CancellationToken;

use super::control::join_sockets;
use super::guard::HttpState;
use super::state::JoinSlot;
use super::state::{self, Inner};
use super::{
    APP_ID_PREFIX, FeishuControl, FeishuLiveStatus, FeishuPeerOptions, FeishuReadyFile,
    FeishuReport, http, ws,
};
use super::{cardkit, media, messages};

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
                get(messages::message_list).post(messages::message_send),
            )
            .route(
                "/open-apis/im/v1/messages/{message_id}",
                get(messages::message_read),
            )
            .route(
                "/open-apis/im/v1/messages/{message_id}/resources/{file_key}",
                get(media::download::download),
            )
            .route(
                "/open-apis/im/v1/files",
                post(media::upload::upload)
                    .layer(DefaultBodyLimit::max(media::upload::MAX_MULTIPART_BYTES)),
            )
            .route("/open-apis/cardkit/v1/cards", post(cardkit::card_create))
            .route(
                "/open-apis/cardkit/v1/cards/{card_id}",
                axum::routing::put(cardkit::card_whole_update),
            )
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
        {
            let mut inner = self.shared.lock().await;
            inner.closing = true;
            inner.media.permits.close();
        }
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
