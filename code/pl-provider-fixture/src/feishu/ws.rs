//! Real axum WebSocket upgrade and pbbp2 frame session.

use axum::body::Bytes;
use axum::extract::ws::{Message, WebSocket};
use axum::extract::{Query, State, WebSocketUpgrade};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use futures::{SinkExt, StreamExt};
use serde::Deserialize;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

use super::http::HttpState;
use super::state::{WsConn, note_ping, record_ack, retire_socket};
use super::types::{
    CallKind, ClientConfig, EventBody, OutboundWs, SyntheticEvent, WsUpgradeScript,
};
use super::wire::{
    FRAME_TYPE_CONTROL, HEADER_TYPE, MESSAGE_TYPE_PING, Pbbp2Frame, event_payload, split_payload,
};

#[derive(Deserialize)]
pub(crate) struct ConnectQuery {
    #[serde(default)]
    pub service_id: Option<i32>,
}

pub(crate) async fn connect(
    State(state): State<HttpState>,
    Query(query): Query<ConnectQuery>,
    upgrade: Result<WebSocketUpgrade, axum::extract::ws::rejection::WebSocketUpgradeRejection>,
) -> Response {
    let path = "/callback/ws/connect";
    let upgrade = match upgrade {
        Ok(upgrade) => upgrade,
        Err(rejection) => {
            record_upgrade_reject(&state, rejection.to_string()).await;
            return rejection.into_response();
        }
    };
    let script = {
        let mut inner = state.shared.lock().await;
        if let Some(reason) = inner.kind_forbidden_or_excess(CallKind::WsUpgrade) {
            inner.record(
                "GET",
                path,
                Some(CallKind::WsUpgrade),
                false,
                Some(reason.clone()),
            );
            return (StatusCode::FORBIDDEN, reason).into_response();
        }
        let script = inner.ws.upgrade.clone();
        match &script {
            WsUpgradeScript::HttpReject { status } => {
                inner.record(
                    "GET",
                    path,
                    Some(CallKind::WsUpgrade),
                    true,
                    Some(format!("http reject {status}")),
                );
                return (
                    StatusCode::from_u16(*status).unwrap_or(StatusCode::UNAUTHORIZED),
                    "websocket rejected",
                )
                    .into_response();
            }
            WsUpgradeScript::Accept | WsUpgradeScript::HandshakeReject { .. } => {
                inner.record("GET", path, Some(CallKind::WsUpgrade), true, None);
            }
        }
        script
    };
    let service = query.service_id.unwrap_or(1);
    upgrade.on_upgrade(move |socket| async move {
        let (tx, rx) = mpsc::channel(32);
        let shared = state.shared.clone();
        let cancel = state.cancel.clone();
        let (app_id, bot_open_id, config) = {
            let inner = shared.lock().await;
            (
                inner.options.app_id.clone(),
                inner.options.bot_open_id.clone(),
                inner.ws.client_config.clone(),
            )
        };
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        let id = {
            let mut inner = shared.lock().await;
            let id = inner.ws.next_id;
            inner.ws.next_id += 1;
            id
        };
        let handle = tokio::spawn(session(
            socket,
            rx,
            ready_rx,
            SessionContext {
                cancel,
                shared: shared.clone(),
                script,
                service,
                id,
                identity: SessionIdentity {
                    app_id,
                    bot_open_id,
                    config,
                },
            },
        ));
        let mut inner = shared.lock().await;
        inner.ws.connections += 1;
        inner.ws.active += 1;
        inner.ws.sockets.push(WsConn {
            id,
            tx,
            join: std::sync::Arc::new(tokio::sync::Mutex::new(super::state::JoinSlot::Pending(
                handle,
            ))),
            closed: false,
        });
        drop(inner);
        let _ = ready_tx.send(());
    })
}

struct SessionIdentity {
    app_id: String,
    bot_open_id: String,
    config: ClientConfig,
}

struct SessionContext {
    cancel: CancellationToken,
    shared: super::state::Shared,
    script: WsUpgradeScript,
    service: i32,
    id: u64,
    identity: SessionIdentity,
}

async fn session(
    socket: WebSocket,
    mut outbound: mpsc::Receiver<OutboundWs>,
    ready: tokio::sync::oneshot::Receiver<()>,
    context: SessionContext,
) {
    let _ = ready.await;
    let SessionContext {
        cancel,
        shared,
        script,
        service,
        id,
        identity,
    } = context;
    let (mut sink, mut stream) = socket.split();
    if let WsUpgradeScript::HandshakeReject {
        status,
        auth_err_code,
    } = script
    {
        let frame = Pbbp2Frame::handshake_reject(status, auth_err_code, "auth failed");
        let _ = sink
            .send(Message::Binary(Bytes::from(frame.encode_vec())))
            .await;
        let _ = sink.send(Message::Close(None)).await;
        retire_socket(&shared, id).await;
        return;
    }

    loop {
        tokio::select! {
            () = cancel.cancelled() => {
                let _ = sink.send(Message::Close(None)).await;
                break;
            }
            message = stream.next() => {
                match message {
                    None => break,
                    Some(Err(_)) => break,
                    Some(Ok(Message::Close(_))) => break,
                    Some(Ok(Message::Ping(payload))) => {
                        if sink.send(Message::Pong(payload)).await.is_err() {
                            break;
                        }
                    }
                    Some(Ok(Message::Pong(_))) => {}
                    Some(Ok(Message::Text(_))) => {
                        let mut inner = shared.lock().await;
                        inner.violations.push("websocket text frame is not pbbp2".into());
                    }
                    Some(Ok(Message::Binary(bytes))) => {
                        match Pbbp2Frame::decode_slice(&bytes) {
                            Ok(frame) => {
                                if inbound_is_ping(&frame) {
                                    note_ping(&shared).await;
                                    let payload =
                                        serde_json::to_vec(&identity.config).unwrap_or_default();
                                    let pong = Pbbp2Frame::pong(service, &payload);
                                    if sink
                                        .send(Message::Binary(Bytes::from(pong.encode_vec())))
                                        .await
                                        .is_err()
                                    {
                                        break;
                                    }
                                } else {
                                    record_ack(&shared, &frame).await;
                                }
                            }
                            Err(error) => {
                                let mut inner = shared.lock().await;
                                inner.violations.push(format!("illegal pbbp2 frame: {error}"));
                            }
                        }
                    }
                }
            }
            outbound = outbound.recv() => {
                let Some(outbound) = outbound else { break; };
                if send_outbound(
                    &mut sink,
                    outbound,
                    service,
                    &identity.app_id,
                    &identity.bot_open_id,
                )
                    .await
                    .is_err()
                {
                    break;
                }
            }
        }
    }
    retire_socket(&shared, id).await;
}

fn inbound_is_ping(frame: &Pbbp2Frame) -> bool {
    frame.method == FRAME_TYPE_CONTROL && frame.header(HEADER_TYPE) == Some(MESSAGE_TYPE_PING)
}

async fn record_upgrade_reject(state: &HttpState, diagnostic: String) {
    let mut inner = state.shared.lock().await;
    inner.record(
        "GET",
        "/callback/ws/connect",
        Some(CallKind::WsUpgrade),
        false,
        Some(diagnostic),
    );
    if let Some(last) = inner.calls.last_mut() {
        last.owned_reject = true;
    }
}

async fn send_outbound(
    sink: &mut futures::stream::SplitSink<WebSocket, Message>,
    outbound: OutboundWs,
    service: i32,
    app_id: &str,
    bot_open_id: &str,
) -> Result<(), ()> {
    match outbound {
        OutboundWs::Close { code, reason } => {
            let _ = sink
                .send(Message::Close(Some(axum::extract::ws::CloseFrame {
                    code: axum::extract::ws::CloseCode::from(code),
                    reason: reason.into(),
                })))
                .await;
            Err(())
        }
        OutboundWs::IllegalBytes => sink
            .send(Message::Binary(Bytes::from_static(
                super::wire::ILLEGAL_PBBP2,
            )))
            .await
            .map_err(|_| ()),
        OutboundWs::Event(event) => send_event(sink, service, app_id, bot_open_id, &event, 1).await,
        OutboundWs::DuplicateEvent(event) => {
            send_event(sink, service, app_id, bot_open_id, &event, 1).await?;
            send_event(sink, service, app_id, bot_open_id, &event, 1).await
        }
        OutboundWs::ConflictEvent { event, other_text } => {
            send_event(sink, service, app_id, bot_open_id, &event, 1).await?;
            let mut other = event;
            other.body = EventBody::Text(other_text);
            send_event(sink, service, app_id, bot_open_id, &other, 1).await
        }
        OutboundWs::EventFragments { event, parts } => {
            send_event(sink, service, app_id, bot_open_id, &event, parts.max(1)).await
        }
        OutboundWs::IncompleteFragment {
            event,
            sum,
            seq,
            payload,
        } => {
            let frame = Pbbp2Frame::event_fragment(
                service,
                &event.message_id,
                &format!("trace_{}", event.message_id),
                sum,
                seq,
                &payload,
            );
            sink.send(Message::Binary(Bytes::from(frame.encode_vec())))
                .await
                .map_err(|_| ())
        }
    }
}

async fn send_event(
    sink: &mut futures::stream::SplitSink<WebSocket, Message>,
    service: i32,
    app_id: &str,
    bot_open_id: &str,
    event: &SyntheticEvent,
    parts: usize,
) -> Result<(), ()> {
    let payload =
        serde_json::to_vec(&event_payload(event, app_id, bot_open_id)).unwrap_or_default();
    let chunks = split_payload(&payload, parts).unwrap_or_else(|_| vec![payload.clone()]);
    let sum = chunks.len() as u32;
    for (seq, chunk) in chunks.iter().enumerate() {
        let frame = Pbbp2Frame::event_fragment(
            service,
            &event.message_id,
            &format!("trace_{}", event.message_id),
            sum,
            seq as u32,
            chunk,
        );
        sink.send(Message::Binary(Bytes::from(frame.encode_vec())))
            .await
            .map_err(|_| ())?;
    }
    Ok(())
}
