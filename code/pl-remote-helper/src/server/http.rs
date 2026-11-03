//! Streaming HTTP egress proxy over the helper's existing HTTP/2 attachment.

use std::{collections::HashSet, io};

use futures::stream;
use http::{HeaderMap, HeaderName, HeaderValue, Method, Response};
use pl_protocol::remote::{
    REMOTE_HTTP_HEAD_MAX_BYTES, RemoteError, RemoteErrorCode, RemoteHttpExchangeStart,
    RemoteHttpHeader, RemoteHttpRequestHead, RemoteHttpResponseHead,
};
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

use crate::{
    budget::{ByteLease, ResourceBudget},
    path::remote_error,
    transport::{self, BINARY_CONTENT, Bytes},
};

#[derive(Clone)]
pub(super) struct HttpProxy {
    client: reqwest::Client,
}

impl HttpProxy {
    pub(super) fn new() -> io::Result<Self> {
        let client = reqwest::Client::builder()
            .pool_max_idle_per_host(0)
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(io::Error::other)?;
        Ok(Self { client })
    }

    pub(super) async fn exchange(
        &self,
        exchange_id: &str,
        request: http::Request<h2::RecvStream>,
        mut sender: h2::server::SendResponse<Bytes>,
        budget: &ResourceBudget,
        stop: CancellationToken,
    ) -> io::Result<()> {
        if exchange_id.is_empty() {
            return respond_early_error(
                &mut sender,
                remote_error(
                    RemoteErrorCode::InvalidRequest,
                    "missing HTTP exchange identity",
                ),
                &stop,
            )
            .await;
        }

        let mut recv = request.into_body();
        let (head, initial_body) = match read_request_head(&mut recv, budget, &stop).await {
            Ok(value) => value,
            Err(error) => return respond_early_error(&mut sender, error, &stop).await,
        };

        let method = match Method::from_bytes(head.method.as_bytes()) {
            Ok(method) => method,
            Err(error) => {
                return respond_early_error(
                    &mut sender,
                    remote_error(
                        RemoteErrorCode::InvalidRequest,
                        format!("invalid HTTP method '{}': {error}", head.method),
                    ),
                    &stop,
                )
                .await;
            }
        };

        let parsed_url = match reqwest::Url::parse(&head.url) {
            Ok(url) if matches!(url.scheme(), "http" | "https") => url,
            Ok(url) => {
                return respond_early_error(
                    &mut sender,
                    remote_error(
                        RemoteErrorCode::InvalidRequest,
                        format!("unsupported HTTP URL scheme '{}'", url.scheme()),
                    ),
                    &stop,
                )
                .await;
            }
            Err(error) => {
                return respond_early_error(
                    &mut sender,
                    remote_error(
                        RemoteErrorCode::InvalidRequest,
                        format!("invalid HTTP URL '{}': {error}", head.url),
                    ),
                    &stop,
                )
                .await;
            }
        };

        let mut request_headers = match build_outbound_headers(&head.headers) {
            Ok(headers) => headers,
            Err(error) => return respond_early_error(&mut sender, error, &stop).await,
        };
        if let Some(env_var) = head.bearer_token_env_var.as_deref()
            && !request_headers.contains_key(http::header::AUTHORIZATION)
        {
            let token = match std::env::var(env_var)
                .ok()
                .map(|value| value.trim().to_owned())
                .filter(|value| !value.is_empty())
            {
                Some(token) => token,
                None => {
                    return respond_early_error(
                        &mut sender,
                        remote_error(
                            RemoteErrorCode::InvalidRequest,
                            format!("missing remote bearer token environment variable '{env_var}'"),
                        ),
                        &stop,
                    )
                    .await;
                }
            };
            let auth_value = match HeaderValue::from_str(&format!("Bearer {token}")) {
                Ok(value) => value,
                Err(error) => {
                    return respond_early_error(
                        &mut sender,
                        remote_error(
                            RemoteErrorCode::InvalidRequest,
                            format!("invalid bearer token in '{env_var}': {error}"),
                        ),
                        &stop,
                    )
                    .await;
                }
            };
            request_headers.insert(http::header::AUTHORIZATION, auth_value);
        }

        let mut send_stream = open_response_stream(&mut sender)?;
        let mut builder = self
            .client
            .request(method, parsed_url)
            .headers(request_headers);

        let has_request_body = initial_body.is_some() || !recv.is_end_stream();
        let (body_tx, body_rx) = if has_request_body {
            let (tx, rx) = mpsc::channel::<Result<(Bytes, ByteLease), io::Error>>(1);
            let stream = stream::unfold(rx, |mut rx| async move {
                rx.recv()
                    .await
                    .map(|item| (item.map(|(bytes, _lease)| bytes), rx))
            });
            builder = builder.body(reqwest::Body::wrap_stream(stream));
            (Some(tx), None::<()>)
        } else {
            (None, None)
        };
        let _ = body_rx;

        let pump_body = async {
            if let Some(tx) = body_tx {
                pump_request_body(&mut recv, initial_body, tx, budget, &stop).await
            } else {
                Ok(())
            }
        };

        let drive_response = async {
            let upstream = tokio::select! {
                _ = stop.cancelled() => return Err(io::Error::new(io::ErrorKind::BrokenPipe, "HTTP exchange cancelled")),
                result = builder.send() => result,
            };
            let mut upstream = match upstream {
                Ok(response) => response,
                Err(error) => {
                    let start = RemoteHttpExchangeStart::Error(remote_error(
                        RemoteErrorCode::Io,
                        format!("remote HTTP request failed: {error}"),
                    ));
                    return send_exchange_start(&mut send_stream, &start, true, budget, &stop)
                        .await;
                }
            };

            let response_head = RemoteHttpResponseHead {
                status: upstream.status().as_u16(),
                headers: extract_inbound_headers(upstream.headers()),
            };
            let start = RemoteHttpExchangeStart::Head(response_head);
            if let Err(error) =
                send_exchange_start(&mut send_stream, &start, false, budget, &stop).await
            {
                send_stream.send_reset(h2::Reason::CANCEL);
                return Err(error);
            }

            let fragment_limit = budget.allocation().fragment_bytes.max(1);
            loop {
                let next_chunk = tokio::select! {
                    _ = stop.cancelled() => {
                        send_stream.send_reset(h2::Reason::CANCEL);
                        return Err(io::Error::new(io::ErrorKind::BrokenPipe, "HTTP exchange cancelled"));
                    }
                    chunk = upstream.chunk() => chunk,
                };
                match next_chunk {
                    Ok(Some(mut chunk)) => {
                        while !chunk.is_empty() {
                            let piece_len = chunk.len().min(fragment_limit);
                            let piece = chunk.split_to(piece_len);
                            let _lease = match budget.reserve(piece.len(), &stop).await {
                                Ok(lease) => lease,
                                Err(error) => {
                                    send_stream.send_reset(h2::Reason::INTERNAL_ERROR);
                                    return Err(error);
                                }
                            };
                            if let Err(error) =
                                transport::send_bytes(&mut send_stream, piece, false, &stop).await
                            {
                                send_stream.send_reset(h2::Reason::CANCEL);
                                return Err(error);
                            }
                        }
                    }
                    Ok(None) => {
                        send_stream
                            .send_data(Bytes::new(), true)
                            .map_err(io::Error::other)?;
                        return Ok(());
                    }
                    Err(error) => {
                        send_stream.send_reset(h2::Reason::INTERNAL_ERROR);
                        return Err(io::Error::other(format!(
                            "remote HTTP response body stream failed: {error}"
                        )));
                    }
                }
            }
        };

        let (body_result, response_result) = tokio::join!(pump_body, drive_response);
        response_result?;
        body_result
    }
}

pub(super) async fn respond_early_error(
    sender: &mut h2::server::SendResponse<Bytes>,
    error: RemoteError,
    stop: &CancellationToken,
) -> io::Result<()> {
    let mut send_stream = open_response_stream(sender)?;
    let start = RemoteHttpExchangeStart::Error(error);
    let encoded = encode_exchange_start(&start)?;
    transport::send_bytes(&mut send_stream, encoded, true, stop).await?;
    Ok(())
}

fn open_response_stream(
    sender: &mut h2::server::SendResponse<Bytes>,
) -> io::Result<h2::SendStream<Bytes>> {
    let response = Response::builder()
        .status(200)
        .header("content-type", BINARY_CONTENT)
        .body(())
        .map_err(io::Error::other)?;
    sender
        .send_response(response, false)
        .map_err(io::Error::other)
}

async fn send_exchange_start(
    send_stream: &mut h2::SendStream<Bytes>,
    start: &RemoteHttpExchangeStart,
    finish: bool,
    budget: &ResourceBudget,
    stop: &CancellationToken,
) -> io::Result<()> {
    let encoded = match encode_exchange_start(start) {
        Ok(bytes) => bytes,
        Err(_) => encode_exchange_start(&RemoteHttpExchangeStart::Error(remote_error(
            RemoteErrorCode::ResourceExhausted,
            format!("HTTP response head exceeds {REMOTE_HTTP_HEAD_MAX_BYTES} bytes"),
        )))?,
    };
    let _lease = budget
        .reserve(
            encoded.len().min(budget.allocation().fragment_bytes.max(1)),
            stop,
        )
        .await?;
    if encoded.is_empty() && finish {
        send_stream
            .send_data(Bytes::new(), true)
            .map_err(io::Error::other)?;
        return Ok(());
    }
    transport::send_bytes(send_stream, encoded, finish, stop).await?;
    Ok(())
}

fn encode_exchange_start(start: &RemoteHttpExchangeStart) -> io::Result<Bytes> {
    let payload = serde_json::to_vec(start).map_err(io::Error::other)?;
    if payload.len() > REMOTE_HTTP_HEAD_MAX_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "HTTP exchange start frame exceeds maximum head size",
        ));
    }
    let len = u32::try_from(payload.len()).map_err(io::Error::other)?;
    let mut framed = Vec::with_capacity(4 + payload.len());
    framed.extend_from_slice(&len.to_be_bytes());
    framed.extend_from_slice(&payload);
    Ok(Bytes::from(framed))
}

async fn read_request_head(
    recv: &mut h2::RecvStream,
    budget: &ResourceBudget,
    stop: &CancellationToken,
) -> Result<(RemoteHttpRequestHead, Option<(Bytes, ByteLease)>), RemoteError> {
    let mut prefix = [0_u8; 4];
    let mut prefix_filled = 0usize;
    let mut leftover = Bytes::new();

    while prefix_filled < 4 {
        let chunk = next_recv_chunk(recv, stop).await?.ok_or_else(|| {
            remote_error(
                RemoteErrorCode::InvalidRequest,
                "incomplete HTTP request head length prefix",
            )
        })?;
        let needed = (4 - prefix_filled).min(chunk.len());
        prefix[prefix_filled..prefix_filled + needed].copy_from_slice(&chunk[..needed]);
        prefix_filled += needed;
        if chunk.len() > needed {
            leftover = chunk.slice(needed..);
        }
    }

    let head_len = u32::from_be_bytes(prefix) as usize;
    if head_len == 0 || head_len > REMOTE_HTTP_HEAD_MAX_BYTES {
        return Err(remote_error(
            RemoteErrorCode::InvalidRequest,
            format!(
                "HTTP request head length {head_len} is outside 1..={REMOTE_HTTP_HEAD_MAX_BYTES}"
            ),
        ));
    }

    let head_lease = budget
        .reserve(
            head_len.min(budget.allocation().fragment_bytes.max(1)),
            stop,
        )
        .await
        .map_err(|error| remote_error(RemoteErrorCode::ResourceExhausted, error.to_string()))?;
    let mut head_bytes = Vec::with_capacity(head_len);

    if !leftover.is_empty() {
        let take = head_len.min(leftover.len());
        head_bytes.extend_from_slice(&leftover[..take]);
        leftover = leftover.slice(take..);
    }

    while head_bytes.len() < head_len {
        let chunk = next_recv_chunk(recv, stop).await?.ok_or_else(|| {
            remote_error(
                RemoteErrorCode::InvalidRequest,
                "incomplete HTTP request head frame",
            )
        })?;
        let needed = (head_len - head_bytes.len()).min(chunk.len());
        head_bytes.extend_from_slice(&chunk[..needed]);
        if chunk.len() > needed {
            leftover = chunk.slice(needed..);
        }
    }

    let head: RemoteHttpRequestHead = serde_json::from_slice(&head_bytes)
        .map_err(|error| remote_error(RemoteErrorCode::InvalidRequest, error.to_string()))?;
    drop(head_lease);

    let initial_body = if leftover.is_empty() {
        None
    } else {
        let lease = budget
            .reserve(
                leftover
                    .len()
                    .min(budget.allocation().fragment_bytes.max(1)),
                stop,
            )
            .await
            .map_err(|error| remote_error(RemoteErrorCode::ResourceExhausted, error.to_string()))?;
        Some((leftover, lease))
    };

    Ok((head, initial_body))
}

async fn next_recv_chunk(
    recv: &mut h2::RecvStream,
    stop: &CancellationToken,
) -> Result<Option<Bytes>, RemoteError> {
    loop {
        let piece = tokio::select! {
            _ = stop.cancelled() => {
                return Err(remote_error(
                    RemoteErrorCode::RemoteDisconnected,
                    "HTTP exchange cancelled",
                ));
            }
            piece = recv.data() => piece,
        };
        let Some(piece) = piece else {
            return Ok(None);
        };
        let piece = piece.map_err(|error| {
            remote_error(
                RemoteErrorCode::Io,
                format!("HTTP request stream failed: {error}"),
            )
        })?;
        if piece.is_empty() {
            continue;
        }
        recv.flow_control()
            .release_capacity(piece.len())
            .map_err(|error| {
                remote_error(
                    RemoteErrorCode::Io,
                    format!("HTTP request flow control failed: {error}"),
                )
            })?;
        return Ok(Some(piece));
    }
}

async fn pump_request_body(
    recv: &mut h2::RecvStream,
    initial_body: Option<(Bytes, ByteLease)>,
    tx: mpsc::Sender<Result<(Bytes, ByteLease), io::Error>>,
    budget: &ResourceBudget,
    stop: &CancellationToken,
) -> io::Result<()> {
    if let Some(first) = initial_body
        && tx.send(Ok(first)).await.is_err()
    {
        return Ok(());
    }
    let fragment_limit = budget.allocation().fragment_bytes.max(1);
    loop {
        let piece = tokio::select! {
            _ = stop.cancelled() => return Ok(()),
            _ = tx.closed() => return Ok(()),
            piece = recv.data() => piece,
        };
        let Some(piece) = piece else {
            return Ok(());
        };
        let mut piece = match piece {
            Ok(bytes) => bytes,
            Err(error) => {
                let io_err = io::Error::other(format!("HTTP request body stream error: {error}"));
                let _ = tx
                    .send(Err(io::Error::other(format!(
                        "HTTP request body stream error: {error}"
                    ))))
                    .await;
                return Err(io_err);
            }
        };
        if piece.is_empty() {
            continue;
        }
        let total_len = piece.len();
        while !piece.is_empty() {
            let chunk_len = piece.len().min(fragment_limit);
            let chunk = piece.split_to(chunk_len);
            let lease = match budget.reserve(chunk.len(), stop).await {
                Ok(lease) => lease,
                Err(error) => {
                    let _ = tx.send(Err(io::Error::other(error.to_string()))).await;
                    return Err(error);
                }
            };
            if tx.send(Ok((chunk, lease))).await.is_err() {
                return Ok(());
            }
        }
        recv.flow_control()
            .release_capacity(total_len)
            .map_err(io::Error::other)?;
    }
}

fn build_outbound_headers(headers: &[RemoteHttpHeader]) -> Result<HeaderMap, RemoteError> {
    let nominated = collect_connection_nominated_headers(headers);
    let mut map = HeaderMap::with_capacity(headers.len());
    for header in headers {
        let name = HeaderName::from_bytes(header.name.as_bytes()).map_err(|error| {
            remote_error(
                RemoteErrorCode::InvalidRequest,
                format!("invalid HTTP header name '{}': {error}", header.name),
            )
        })?;
        if is_hop_by_hop_header(name.as_str(), true, &nominated) {
            continue;
        }
        let value = HeaderValue::from_bytes(&header.value).map_err(|error| {
            remote_error(
                RemoteErrorCode::InvalidRequest,
                format!("invalid HTTP header value for '{}': {error}", header.name),
            )
        })?;
        map.append(name, value);
    }
    Ok(map)
}

fn extract_inbound_headers(headers: &HeaderMap) -> Vec<RemoteHttpHeader> {
    let nominated = collect_response_connection_nominated_headers(headers);
    let mut out = Vec::with_capacity(headers.len());
    for (name, value) in headers.iter() {
        if is_hop_by_hop_header(name.as_str(), false, &nominated) {
            continue;
        }
        out.push(RemoteHttpHeader {
            name: name.as_str().to_owned(),
            value: value.as_bytes().to_vec(),
        });
    }
    out
}

fn collect_connection_nominated_headers(headers: &[RemoteHttpHeader]) -> HashSet<String> {
    let mut set = HashSet::new();
    for header in headers {
        if header.name.eq_ignore_ascii_case("connection")
            && let Ok(text) = std::str::from_utf8(&header.value)
        {
            for token in text.split(',') {
                let trimmed = token.trim();
                if !trimmed.is_empty() {
                    set.insert(trimmed.to_ascii_lowercase());
                }
            }
        }
    }
    set
}

fn collect_response_connection_nominated_headers(headers: &HeaderMap) -> HashSet<String> {
    let mut set = HashSet::new();
    for value in headers.get_all(http::header::CONNECTION) {
        if let Ok(text) = value.to_str() {
            for token in text.split(',') {
                let trimmed = token.trim();
                if !trimmed.is_empty() {
                    set.insert(trimmed.to_ascii_lowercase());
                }
            }
        }
    }
    set
}

fn is_hop_by_hop_header(name: &str, strip_host: bool, nominated: &HashSet<String>) -> bool {
    let lower = name.to_ascii_lowercase();
    if strip_host && lower == "host" {
        return true;
    }
    matches!(
        lower.as_str(),
        "connection"
            | "keep-alive"
            | "proxy-authenticate"
            | "proxy-authorization"
            | "te"
            | "trailer"
            | "transfer-encoding"
            | "upgrade"
    ) || nominated.contains(&lower)
}
