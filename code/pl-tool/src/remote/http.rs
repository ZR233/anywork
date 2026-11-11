//! Client-side streaming HTTP proxy over `RemoteClient`'s HTTP/2 helper attachment.

use futures::{StreamExt, stream, stream::BoxStream};
use http::{HeaderMap, HeaderName, HeaderValue, StatusCode};
use pl_protocol::remote::{
    REMOTE_HTTP_HEAD_MAX_BYTES, RemoteErrorCode, RemoteHttpExchangeStart, RemoteHttpHeader,
    RemoteHttpRequestHead,
};
use pl_remote_helper::transport::{self, Bytes};
use tokio_util::sync::CancellationToken;

use super::{RemoteClient, RemoteClientError};

pub struct RemoteHttpResponse {
    pub status: StatusCode,
    pub headers: Vec<RemoteHttpHeader>,
    pub body: BoxStream<'static, Result<Bytes, RemoteClientError>>,
}

impl std::fmt::Debug for RemoteHttpResponse {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RemoteHttpResponse")
            .field("status", &self.status)
            .field("headers", &self.headers.len())
            .finish_non_exhaustive()
    }
}

impl RemoteHttpResponse {
    pub fn header_map(&self) -> Result<HeaderMap, RemoteClientError> {
        let mut map = HeaderMap::with_capacity(self.headers.len());
        for header in &self.headers {
            let name = HeaderName::from_bytes(header.name.as_bytes()).map_err(|error| {
                RemoteClientError::Protocol(format!(
                    "invalid remote HTTP response header name '{}': {error}",
                    header.name
                ))
            })?;
            let value = HeaderValue::from_bytes(&header.value).map_err(|error| {
                RemoteClientError::Protocol(format!(
                    "invalid remote HTTP response header value for '{}': {error}",
                    header.name
                ))
            })?;
            map.append(name, value);
        }
        Ok(map)
    }

    pub async fn collect_body(mut self, max_bytes: usize) -> Result<Bytes, RemoteClientError> {
        let mut out = Vec::new();
        while let Some(chunk) = self.body.next().await {
            let chunk = chunk?;
            if out.len().saturating_add(chunk.len()) > max_bytes {
                return Err(RemoteClientError::Remote {
                    removal_effect: None,
                    code: RemoteErrorCode::ResourceExhausted,
                    message: format!("remote HTTP response body exceeds {max_bytes} bytes"),
                });
            }
            out.extend_from_slice(&chunk);
        }
        Ok(Bytes::from(out))
    }
}

impl RemoteClient {
    pub async fn http_exchange(
        &self,
        head: RemoteHttpRequestHead,
        body: Bytes,
    ) -> Result<RemoteHttpResponse, RemoteClientError> {
        let head_payload = serde_json::to_vec(&head)
            .map_err(|error| RemoteClientError::Protocol(error.to_string()))?;
        if head_payload.is_empty() || head_payload.len() > REMOTE_HTTP_HEAD_MAX_BYTES {
            return Err(RemoteClientError::Remote {
                removal_effect: None,
                code: RemoteErrorCode::InvalidRequest,
                message: format!(
                    "remote HTTP request head length {} is outside 1..={REMOTE_HTTP_HEAD_MAX_BYTES}",
                    head_payload.len()
                ),
            });
        }
        let head_len = u32::try_from(head_payload.len())
            .map_err(|error| RemoteClientError::Protocol(error.to_string()))?;
        let mut framed_head = Vec::with_capacity(4 + head_payload.len());
        framed_head.extend_from_slice(&head_len.to_be_bytes());
        framed_head.extend_from_slice(&head_payload);
        let framed_head = Bytes::from(framed_head);

        let (exchange_id, generation, epoch, wire, stop) = self.open_http_wire().await?;
        let (mut send_stream, response_future) = match wire
            .open_http_exchange(&exchange_id, epoch)
            .await
        {
            Ok(opened) => opened,
            Err(error) => {
                if wire.is_closed() {
                    self.notify_wire_detached(generation, format!("HTTP exchange open: {error}"));
                }
                return Err(error.into());
            }
        };

        let send_stop = wire.stop_token();
        if body.is_empty() {
            transport::send_bytes(&mut send_stream, framed_head, true, &send_stop).await?;
        } else {
            transport::send_bytes(&mut send_stream, framed_head, false, &send_stop).await?;
            transport::send_bytes(&mut send_stream, body, true, &send_stop).await?;
        }

        let response = tokio::select! {
            _ = stop.cancelled() => return Err(RemoteClientError::Disconnected),
            result = response_future => match result {
                Ok(response) => response,
                Err(error) => {
                    if wire.is_closed() || error.is_io() || error.is_go_away() {
                        self.notify_wire_detached(generation, format!("HTTP exchange response: {error}"));
                    }
                    return Err(RemoteClientError::Protocol(format!("remote HTTP exchange failed: {error}")));
                }
            }
        };

        let mut recv = response.into_body();
        let (start, initial_body) =
            read_exchange_start(self, &mut recv, &stop, generation, &wire).await?;

        match start {
            RemoteHttpExchangeStart::Error(error) => {
                if error.code == RemoteErrorCode::StaleConnection {
                    self.notify_wire_detached(generation, error.message.clone());
                }
                Err(RemoteClientError::Remote {
                    removal_effect: error.removal_effect,
                    code: error.code,
                    message: error.message,
                })
            }
            RemoteHttpExchangeStart::Head(response_head) => {
                let status = StatusCode::from_u16(response_head.status).map_err(|error| {
                    RemoteClientError::Protocol(format!(
                        "invalid remote HTTP status code {}: {error}",
                        response_head.status
                    ))
                })?;
                let client = self.clone();
                let body_stream = stream::unfold(
                    (recv, initial_body, client, stop, generation, wire, false),
                    |(mut recv, mut initial, client, stop, generation, wire, terminated)| async move {
                        if terminated {
                            return None;
                        }
                        if let Some(first) = initial.take()
                            && !first.is_empty()
                        {
                            return Some((
                                Ok(first),
                                (recv, None, client, stop, generation, wire, false),
                            ));
                        }
                        loop {
                            let piece = tokio::select! {
                                _ = stop.cancelled() => {
                                    return Some((
                                        Err(RemoteClientError::Disconnected),
                                        (recv, None, client, stop, generation, wire, true),
                                    ));
                                }
                                piece = recv.data() => piece,
                            };
                            match piece {
                                Some(Ok(bytes)) => {
                                    if bytes.is_empty() {
                                        continue;
                                    }
                                    if let Err(error) =
                                        recv.flow_control().release_capacity(bytes.len())
                                    {
                                        return Some((
                                            Err(RemoteClientError::Protocol(format!(
                                                "remote HTTP flow control release failed: {error}"
                                            ))),
                                            (recv, None, client, stop, generation, wire, true),
                                        ));
                                    }
                                    return Some((
                                        Ok(bytes),
                                        (recv, None, client, stop, generation, wire, false),
                                    ));
                                }
                                Some(Err(error)) => {
                                    if wire.is_closed() || error.is_io() || error.is_go_away() {
                                        client.notify_wire_detached(
                                            generation,
                                            format!("remote HTTP body stream: {error}"),
                                        );
                                    }
                                    return Some((
                                        Err(RemoteClientError::Protocol(format!(
                                            "remote HTTP response stream failed: {error}"
                                        ))),
                                        (recv, None, client, stop, generation, wire, true),
                                    ));
                                }
                                None => return None,
                            }
                        }
                    },
                )
                .boxed();

                Ok(RemoteHttpResponse {
                    status,
                    headers: response_head.headers,
                    body: body_stream,
                })
            }
        }
    }
}

async fn read_exchange_start(
    client: &RemoteClient,
    recv: &mut h2::RecvStream,
    stop: &CancellationToken,
    generation: u64,
    wire: &pl_remote_helper::transport::Client,
) -> Result<(RemoteHttpExchangeStart, Option<Bytes>), RemoteClientError> {
    let mut prefix = [0_u8; 4];
    let mut prefix_filled = 0usize;
    let mut leftover = Bytes::new();

    while prefix_filled < 4 {
        let chunk = next_response_chunk(client, recv, stop, generation, wire)
            .await?
            .ok_or_else(|| {
                RemoteClientError::Protocol(
                    "remote HTTP exchange closed before start frame length prefix".into(),
                )
            })?;
        let needed = (4 - prefix_filled).min(chunk.len());
        prefix[prefix_filled..prefix_filled + needed].copy_from_slice(&chunk[..needed]);
        prefix_filled += needed;
        if chunk.len() > needed {
            leftover = chunk.slice(needed..);
        }
    }

    let start_len = u32::from_be_bytes(prefix) as usize;
    if start_len == 0 || start_len > REMOTE_HTTP_HEAD_MAX_BYTES {
        return Err(RemoteClientError::Protocol(format!(
            "remote HTTP start frame length {start_len} is outside 1..={REMOTE_HTTP_HEAD_MAX_BYTES}"
        )));
    }

    let mut start_bytes = Vec::with_capacity(start_len);

    if !leftover.is_empty() {
        let take = start_len.min(leftover.len());
        start_bytes.extend_from_slice(&leftover[..take]);
        leftover = leftover.slice(take..);
    }

    while start_bytes.len() < start_len {
        let chunk = next_response_chunk(client, recv, stop, generation, wire)
            .await?
            .ok_or_else(|| {
                RemoteClientError::Protocol(
                    "remote HTTP exchange closed before start frame completed".into(),
                )
            })?;
        let needed = (start_len - start_bytes.len()).min(chunk.len());
        start_bytes.extend_from_slice(&chunk[..needed]);
        if chunk.len() > needed {
            leftover = chunk.slice(needed..);
        }
    }

    let start: RemoteHttpExchangeStart = serde_json::from_slice(&start_bytes)
        .map_err(|error| RemoteClientError::Protocol(error.to_string()))?;
    let initial = (!leftover.is_empty()).then_some(leftover);
    Ok((start, initial))
}

async fn next_response_chunk(
    client: &RemoteClient,
    recv: &mut h2::RecvStream,
    stop: &CancellationToken,
    generation: u64,
    wire: &pl_remote_helper::transport::Client,
) -> Result<Option<Bytes>, RemoteClientError> {
    loop {
        let piece = tokio::select! {
            _ = stop.cancelled() => return Err(RemoteClientError::Disconnected),
            piece = recv.data() => piece,
        };
        let Some(piece) = piece else {
            return Ok(None);
        };
        let piece = match piece {
            Ok(bytes) => bytes,
            Err(error) => {
                if wire.is_closed() || error.is_io() || error.is_go_away() {
                    client.notify_wire_detached(
                        generation,
                        format!("remote HTTP start frame: {error}"),
                    );
                }
                return Err(RemoteClientError::Protocol(format!(
                    "remote HTTP start stream failed: {error}"
                )));
            }
        };
        if piece.is_empty() {
            continue;
        }
        recv.flow_control()
            .release_capacity(piece.len())
            .map_err(|error| {
                RemoteClientError::Protocol(format!(
                    "remote HTTP start flow control failed: {error}"
                ))
            })?;
        return Ok(Some(piece));
    }
}
