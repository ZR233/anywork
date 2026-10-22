use super::error::{FeishuError, FeishuErrorKind};
use super::frame::{FrameType, HeaderKey, MessageType, Pbbp2Frame};
use super::http::FeishuHttp;
use super::{
    FRAGMENT_TTL_MS, MAX_EVENT_BYTES, MAX_EVENT_FRAGMENTS, MAX_PENDING_EVENTS, WS_ENDPOINT_PATH,
};
use futures::{SinkExt, StreamExt};
use prost::Message;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{Duration, Instant};
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};
use tokio_util::sync::CancellationToken;
use url::Url;

pub type WsStream = WebSocketStream<MaybeTlsStream<TcpStream>>;

#[derive(Clone)]
pub struct ConnectConfig {
    pub connect_url: String,
    pub service_id: i32,
    pub ping_interval: Duration,
    pub reconnect_count: i32,
    pub reconnect_interval: Duration,
    pub reconnect_nonce: Duration,
}

#[derive(Debug, Deserialize)]
struct EndpointEnvelope {
    code: i64,
    #[serde(default)]
    msg: Option<String>,
    #[serde(default)]
    data: Option<EndpointData>,
}

#[derive(Debug, Deserialize)]
struct EndpointData {
    #[serde(rename = "URL")]
    url: Option<String>,
    #[serde(rename = "ClientConfig")]
    client_config: Option<ClientConfigWire>,
}

#[derive(Debug, Deserialize)]
struct ClientConfigWire {
    #[serde(rename = "PingInterval")]
    ping_interval: Option<u64>,
    #[serde(rename = "ReconnectCount")]
    reconnect_count: Option<i32>,
    #[serde(rename = "ReconnectInterval")]
    reconnect_interval: Option<u64>,
    #[serde(rename = "ReconnectNonce")]
    reconnect_nonce: Option<u64>,
}

#[derive(Debug, Deserialize)]
pub struct PongConfig {
    #[serde(rename = "PingInterval")]
    pub ping_interval: Option<u64>,
    #[serde(rename = "ReconnectCount")]
    pub reconnect_count: Option<i32>,
    #[serde(rename = "ReconnectInterval")]
    pub reconnect_interval: Option<u64>,
    #[serde(rename = "ReconnectNonce")]
    pub reconnect_nonce: Option<u64>,
}

#[derive(Serialize)]
struct EndpointBody<'a> {
    #[serde(rename = "AppID")]
    app_id: &'a str,
    #[serde(rename = "AppSecret")]
    app_secret: &'a str,
}

pub struct WsEndpointDiscovery {
    http: FeishuHttp,
}

impl WsEndpointDiscovery {
    pub fn new(http: FeishuHttp) -> Self {
        Self { http }
    }

    pub async fn discover(
        &self,
        app_id: &str,
        app_secret: &str,
    ) -> Result<ConnectConfig, FeishuError> {
        let url = self
            .http
            .open_api()
            .join(WS_ENDPOINT_PATH.trim_start_matches('/'))
            .map_err(|error| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    format!("invalid ws endpoint path: {error}"),
                    false,
                    None,
                )
            })?;
        let response = self
            .http
            .client()
            .post(url)
            .header("locale", "zh")
            .json(&EndpointBody { app_id, app_secret })
            .send()
            .await
            .map_err(|error| {
                let kind = if error.is_timeout() {
                    FeishuErrorKind::Timeout
                } else {
                    FeishuErrorKind::Transport
                };
                FeishuError::new(kind, "ws endpoint discovery failed", true, None)
            })?;
        let status = response.status();
        let bytes = response.bytes().await.map_err(|error| {
            FeishuError::new(
                FeishuErrorKind::Transport,
                format!("ws endpoint body failed: {error}"),
                true,
                None,
            )
        })?;
        let envelope: EndpointEnvelope = serde_json::from_slice(&bytes).map_err(|error| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                format!("invalid ws endpoint JSON (HTTP {status}): {error}"),
                status.is_server_error(),
                None,
            )
        })?;
        if envelope.code != 0 {
            let retryable = matches!(envelope.code, 1 | 1000040343);
            let kind = match envelope.code {
                514 | 403 | 1000040343 => FeishuErrorKind::Auth,
                1000040350 => FeishuErrorKind::Unavailable,
                _ => FeishuErrorKind::Unavailable,
            };
            return Err(FeishuError::new(
                kind,
                envelope
                    .msg
                    .unwrap_or_else(|| "ws endpoint discovery rejected".to_string()),
                retryable,
                Some(envelope.code.to_string()),
            ));
        }
        let data = envelope.data.ok_or_else(|| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                "ws endpoint missing data",
                true,
                None,
            )
        })?;
        let connect_url = data.url.filter(|value| !value.is_empty()).ok_or_else(|| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                "ws endpoint missing URL",
                true,
                None,
            )
        })?;
        self.http.policy().validate_ws_url(&connect_url)?;
        let parsed = Url::parse(&connect_url).map_err(|error| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                format!("invalid ws url: {error}"),
                false,
                None,
            )
        })?;
        let service_id = parsed
            .query_pairs()
            .find(|(key, _)| key == "service_id")
            .ok_or_else(|| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "ws url missing service_id",
                    false,
                    None,
                )
            })?
            .1
            .parse::<i32>()
            .map_err(|_| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "ws url has an invalid service_id",
                    false,
                    None,
                )
            })?;
        let config = data.client_config.unwrap_or(ClientConfigWire {
            ping_interval: Some(120),
            reconnect_count: Some(-1),
            reconnect_interval: Some(120),
            reconnect_nonce: Some(30),
        });
        Ok(ConnectConfig {
            connect_url,
            service_id,
            ping_interval: Duration::from_secs(config.ping_interval.unwrap_or(120).max(5)),
            reconnect_count: config.reconnect_count.unwrap_or(-1),
            reconnect_interval: Duration::from_secs(
                config.reconnect_interval.unwrap_or(120).max(1),
            ),
            reconnect_nonce: Duration::from_secs(config.reconnect_nonce.unwrap_or(30)),
        })
    }
}

pub struct FeishuWsSession {
    stream: WsStream,
    pub config: ConnectConfig,
    fragments: FragmentCache,
}

pub struct EventAck {
    pub frame: Pbbp2Frame,
    pub payload: serde_json::Value,
}

impl FeishuWsSession {
    pub async fn connect(
        config: ConnectConfig,
        cancel: &CancellationToken,
    ) -> Result<Self, FeishuError> {
        tokio::select! {
            _ = cancel.cancelled() => Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "ws connect cancelled",
                true,
                None,
            )),
            result = tokio_tungstenite::connect_async(&config.connect_url) => {
                let (stream, response) = result.map_err(|_error| {
                    FeishuError::new(
                        FeishuErrorKind::Transport,
                        "ws handshake failed",
                        true,
                        None,
                    )
                })?;
                inspect_handshake(response.headers())?;
                Ok(Self {
                    stream,
                    config,
                    fragments: FragmentCache::new(),
                })
            }
        }
    }

    pub async fn send_ping(&mut self) -> Result<(), FeishuError> {
        self.send_frame(&Pbbp2Frame::ping(self.config.service_id))
            .await
    }

    pub async fn send_ack(&mut self, frame: &Pbbp2Frame, ok: bool) -> Result<(), FeishuError> {
        let payload = serde_json::json!({
            "code": if ok { 200 } else { 500 }
        });
        let mut ack = frame.clone();
        ack.headers.push(super::frame::Pbbp2Header {
            key: HeaderKey::BIZ_RT.to_string(),
            value: "0".to_string(),
        });
        ack.payload = Some(payload.to_string().into_bytes());
        self.send_frame(&ack).await
    }

    async fn send_frame(&mut self, frame: &Pbbp2Frame) -> Result<(), FeishuError> {
        let bytes = frame.encode_to_vec();
        self.stream
            .send(WsMessage::Binary(bytes.into()))
            .await
            .map_err(|error| {
                FeishuError::new(
                    FeishuErrorKind::Transport,
                    format!("ws send failed: {error}"),
                    true,
                    None,
                )
            })
    }

    pub async fn next_event(
        &mut self,
        cancel: &CancellationToken,
    ) -> Result<Option<WsInbound>, FeishuError> {
        loop {
            let message = tokio::select! {
                _ = cancel.cancelled() => return Ok(None),
                message = self.stream.next() => message,
            };
            let Some(message) = message else {
                return Ok(None);
            };
            let message = message.map_err(|error| {
                FeishuError::new(
                    FeishuErrorKind::Transport,
                    format!("ws receive failed: {error}"),
                    true,
                    None,
                )
            })?;
            match message {
                WsMessage::Binary(bytes) => {
                    if let Some(inbound) = self.handle_binary(&bytes)? {
                        return Ok(Some(inbound));
                    }
                }
                WsMessage::Close(_) => return Ok(None),
                WsMessage::Ping(payload) => {
                    self.stream
                        .send(WsMessage::Pong(payload))
                        .await
                        .map_err(|error| {
                            FeishuError::new(
                                FeishuErrorKind::Transport,
                                format!("ws pong failed: {error}"),
                                true,
                                None,
                            )
                        })?;
                }
                WsMessage::Pong(_) | WsMessage::Text(_) | WsMessage::Frame(_) => {}
            }
        }
    }

    fn handle_binary(&mut self, bytes: &[u8]) -> Result<Option<WsInbound>, FeishuError> {
        let frame = Pbbp2Frame::decode(bytes).map_err(|error| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                format!("invalid pbbp2 frame: {error}"),
                false,
                None,
            )
        })?;
        if let Some(status) = frame.header(HeaderKey::HANDSHAKE_STATUS) {
            let ok = status == "0" || status.eq_ignore_ascii_case("ok") || status == "200";
            if !ok {
                let auth = frame.header(HeaderKey::HANDSHAKE_AUTHERRCODE);
                return Err(FeishuError::new(
                    FeishuErrorKind::Auth,
                    frame
                        .header(HeaderKey::HANDSHAKE_MSG)
                        .unwrap_or("ws handshake rejected")
                        .to_string(),
                    false,
                    auth.map(str::to_string),
                ));
            }
        }
        if frame.method == FrameType::Control as i32 {
            if frame.header(HeaderKey::TYPE) == Some(MessageType::PONG)
                && let Some(payload) = frame.payload.as_ref()
                && let Ok(pong) = serde_json::from_slice::<PongConfig>(payload)
            {
                if let Some(interval) = pong.ping_interval {
                    self.config.ping_interval = Duration::from_secs(interval.max(5));
                }
                if let Some(count) = pong.reconnect_count {
                    self.config.reconnect_count = count;
                }
                if let Some(interval) = pong.reconnect_interval {
                    self.config.reconnect_interval = Duration::from_secs(interval.max(1));
                }
                if let Some(nonce) = pong.reconnect_nonce {
                    self.config.reconnect_nonce = Duration::from_secs(nonce);
                }
            }
            return Ok(None);
        }
        if frame.method != FrameType::Data as i32 {
            return Ok(None);
        }
        if frame.header(HeaderKey::TYPE) != Some(MessageType::EVENT) {
            return Ok(None);
        }
        let Some(merged) = self.fragments.merge(&frame)? else {
            return Ok(None);
        };
        Ok(Some(WsInbound::Event(EventAck {
            frame,
            payload: merged,
        })))
    }

    pub async fn close(&mut self) {
        let _ = self.stream.close(None).await;
    }
}

pub enum WsInbound {
    Event(EventAck),
}

pub struct FragmentCache {
    entries: HashMap<String, FragmentEntry>,
}

struct FragmentEntry {
    parts: Vec<Option<Vec<u8>>>,
    created: Instant,
    bytes: usize,
}

impl FragmentCache {
    pub fn new() -> Self {
        Self {
            entries: HashMap::new(),
        }
    }

    pub fn merge(&mut self, frame: &Pbbp2Frame) -> Result<Option<serde_json::Value>, FeishuError> {
        self.expire();
        let message_id = frame.header(HeaderKey::MESSAGE_ID).ok_or_else(|| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                "event frame missing message_id",
                false,
                None,
            )
        })?;
        let sum = parse_count(frame.header(HeaderKey::SUM).unwrap_or("1"))?;
        let seq = parse_count(frame.header(HeaderKey::SEQ).unwrap_or("0"))?;
        if sum == 0 || sum > MAX_EVENT_FRAGMENTS || seq >= sum {
            return Err(FeishuError::new(
                FeishuErrorKind::Protocol,
                format!("invalid event fragment metadata sum={sum} seq={seq}"),
                false,
                None,
            ));
        }
        let payload = frame.payload.clone().unwrap_or_default();
        if payload.len() > MAX_EVENT_BYTES {
            return Err(FeishuError::new(
                FeishuErrorKind::Protocol,
                "event fragment exceeds byte limit",
                false,
                None,
            ));
        }
        if !self.entries.contains_key(message_id) && self.entries.len() >= MAX_PENDING_EVENTS {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "pending event cache is full",
                true,
                None,
            ));
        }
        let entry = self
            .entries
            .entry(message_id.to_string())
            .or_insert_with(|| FragmentEntry {
                parts: vec![None; sum],
                created: Instant::now(),
                bytes: 0,
            });
        if entry.parts.len() != sum {
            return Err(FeishuError::new(
                FeishuErrorKind::Protocol,
                "event fragment sum conflict",
                false,
                None,
            ));
        }
        if entry.parts[seq].is_some() {
            if entry.parts[seq].as_deref() != Some(payload.as_slice()) {
                return Err(FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "event fragment content conflict",
                    false,
                    None,
                ));
            }
            return Ok(None);
        }
        entry.bytes = entry.bytes.saturating_add(payload.len());
        if entry.bytes > MAX_EVENT_BYTES {
            self.entries.remove(message_id);
            return Err(FeishuError::new(
                FeishuErrorKind::Protocol,
                "merged event exceeds byte limit",
                false,
                None,
            ));
        }
        entry.parts[seq] = Some(payload);
        if entry.parts.iter().any(Option::is_none) {
            return Ok(None);
        }
        let mut merged = Vec::new();
        for part in entry.parts.iter().flatten() {
            merged.extend_from_slice(part);
        }
        self.entries.remove(message_id);
        serde_json::from_slice(&merged).map(Some).map_err(|error| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                format!("invalid merged event JSON: {error}"),
                false,
                None,
            )
        })
    }

    fn expire(&mut self) {
        let ttl = Duration::from_millis(FRAGMENT_TTL_MS);
        self.entries
            .retain(|_, entry| entry.created.elapsed() <= ttl);
    }
}

fn parse_count(value: &str) -> Result<usize, FeishuError> {
    value.parse::<usize>().map_err(|_| {
        FeishuError::new(
            FeishuErrorKind::Protocol,
            format!("invalid fragment count {value}"),
            false,
            None,
        )
    })
}

fn inspect_handshake(
    headers: &tokio_tungstenite::tungstenite::http::HeaderMap,
) -> Result<(), FeishuError> {
    let status = headers
        .get("handshake-status")
        .or_else(|| headers.get("Handshake-Status"))
        .and_then(|value| value.to_str().ok());
    if let Some(status) = status
        && status != "0"
        && status != "200"
        && !status.eq_ignore_ascii_case("ok")
    {
        let auth = headers
            .get("handshake-autherrcode")
            .and_then(|value| value.to_str().ok())
            .map(str::to_string);
        return Err(FeishuError::new(
            FeishuErrorKind::Auth,
            "ws handshake rejected",
            false,
            auth,
        ));
    }
    Ok(())
}
