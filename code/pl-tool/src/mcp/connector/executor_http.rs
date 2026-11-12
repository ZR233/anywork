//! MCP HTTP over the same selected executor egress for Host and SSH.

use std::borrow::Cow;
use std::collections::HashMap;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, ready};
use std::time::Duration;

use bytes::Bytes;
use futures::{Stream, StreamExt, stream::BoxStream};
use http::{HeaderMap, HeaderName, HeaderValue, StatusCode};
use pl_protocol::Result;
use pl_remote_helper::http::{HttpClient, HttpHeader, HttpRequest};
use rmcp::ClientLifecycleMode;
use rmcp::model::{
    ClientJsonRpcMessage, ClientRequest, ErrorData, JsonRpcMessage, ProtocolVersion,
    ServerJsonRpcMessage,
};
use rmcp::service::ClientServiceExt;
use rmcp::transport::StreamableHttpClientTransport;
use rmcp::transport::common::client_side_sse::{ExponentialBackoff, SseRetryPolicy};
use rmcp::transport::streamable_http_client::{
    AuthRequiredError, InsufficientScopeError, SseError, StreamableHttpClient,
    StreamableHttpClientTransportConfig, StreamableHttpClientWorker, StreamableHttpError,
    StreamableHttpPostResponse,
};
use rmcp::transport::worker::WorkerTransport;
use sse_stream::SseByteStream;
use sse_stream_rmcp::Sse;
use thiserror::Error;
use tokio_util::sync::CancellationToken;

use pl_remote_helper::ExecutionError;
use pl_remote_helper::Executor;

use super::{
    ConnectedMcp, McpConnectRequest, ToolListChangedSink, client_handler, connection_config_error,
    connection_error, discovery_lifecycle, should_retry_http_with_initialize,
};

const DEFAULT_MAX_SSE_EVENT_SIZE: usize = 16 * 1024 * 1024;
const MAX_NON_STREAM_BODY_BYTES: usize = 16 * 1024 * 1024;
const ERROR_BODY_LIMIT_BYTES: usize = 256 * 1024;
const JSON_RPC_BODY_PREVIEW_LEN: usize = 256;

const HEADER_SESSION_ID: &str = "Mcp-Session-Id";
const HEADER_LAST_EVENT_ID: &str = "Last-Event-Id";
const HEADER_MCP_PROTOCOL_VERSION: &str = "MCP-Protocol-Version";
const EVENT_STREAM_MIME_TYPE: &str = "text/event-stream";
const JSON_MIME_TYPE: &str = "application/json";

const RESERVED_HEADERS: &[&str] = &[
    "accept",
    HEADER_SESSION_ID,
    HEADER_MCP_PROTOCOL_VERSION,
    HEADER_LAST_EVENT_ID,
];

pub(super) async fn connect(
    request: McpConnectRequest,
    remote_client: Executor,
    tool_list_changed: Option<ToolListChangedSink>,
    close_timeout: Duration,
) -> Result<ConnectedMcp> {
    let config = &request.server.config;
    let uri = config.url.as_deref().ok_or_else(|| {
        connection_config_error(&request.server_id, "streamable HTTP url is required")
    })?;
    let custom_headers = config
        .headers
        .iter()
        .map(|(name, value)| {
            let name = HeaderName::from_bytes(name.as_bytes())
                .map_err(|error| connection_error(&request.server_id, error))?;
            let value = HeaderValue::from_str(value)
                .map_err(|error| connection_error(&request.server_id, error))?;
            Ok((name, value))
        })
        .collect::<Result<HashMap<_, _>>>()?;

    let fatal_sse_error = Arc::new(Mutex::new(None));
    let transport_cancel = CancellationToken::new();
    let cancel_on_drop = transport_cancel.clone().drop_guard();
    let retry_policy = Arc::new(ExecutorSseRetryPolicy {
        inner: ExponentialBackoff::default(),
        fatal_sse_error: fatal_sse_error.clone(),
        cancel: transport_cancel.clone(),
    });

    let mut transport_config = StreamableHttpClientTransportConfig::with_uri(uri.to_string())
        .custom_headers(custom_headers)
        .reinit_on_expired_session(true);
    transport_config.retry_config = retry_policy;
    if let Some(token) = request.server.bearer_token.as_deref() {
        transport_config = transport_config.auth_header(token);
    }

    let http_client = ExecutorStreamableHttpClient {
        client: remote_client.http(),
        fatal_sse_error: fatal_sse_error.clone(),
        cancel: transport_cancel.clone(),
        bearer_token_env_var: if request.server.bearer_token.is_none() {
            config.bearer_token_env_var.clone()
        } else {
            None
        },
    };

    let transport = transport_for(&http_client, transport_config.clone());
    let service = match client_handler(
        &request.server_id,
        ProtocolVersion::V_2026_07_28,
        tool_list_changed.clone(),
    )
    .serve_with_lifecycle(transport, discovery_lifecycle())
    .await
    {
        Ok(service) => service,
        Err(discovery_error)
            if fatal_sse_error
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .is_none()
                && should_retry_http_with_initialize(&discovery_error) =>
        {
            let transport = transport_for(&http_client, transport_config);
            client_handler(
                &request.server_id,
                ProtocolVersion::V_2025_11_25,
                tool_list_changed,
            )
            .serve_with_lifecycle(transport, ClientLifecycleMode::Initialize)
            .await
            .map_err(|initialize_error| {
                connection_error(
                    &request.server_id,
                    format!(
                        "discovery failed ({discovery_error}); standard initialize failed ({initialize_error})"
                    ),
                )
            })?
        }
        Err(error) => {
            if let Some(fatal) = fatal_sse_error
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clone()
            {
                return Err(connection_error(&request.server_id, fatal));
            }
            return Err(connection_error(&request.server_id, error));
        }
    };

    cancel_on_drop.disarm();
    Ok(
        ConnectedMcp::from_running_with_transport_cancel(service, transport_cancel, close_timeout)
            .await,
    )
}

// Each SDK attempt shares its cancellation token with its HTTP owner. A failed
// discover attempt closes only itself; a fresh initialize attempt gets a new token.
fn transport_for(
    client: &ExecutorStreamableHttpClient,
    config: StreamableHttpClientTransportConfig,
) -> StreamableHttpClientTransport<ExecutorStreamableHttpClient> {
    let mut attempt = client.clone();
    attempt.cancel = client.cancel.child_token();
    let cancel = attempt.cancel.clone();
    WorkerTransport::spawn_with_ct(StreamableHttpClientWorker::new(attempt, config), cancel)
}

#[derive(Debug)]
struct ExecutorSseRetryPolicy {
    inner: ExponentialBackoff,
    fatal_sse_error: Arc<Mutex<Option<String>>>,
    cancel: CancellationToken,
}

impl SseRetryPolicy for ExecutorSseRetryPolicy {
    fn retry(&self, current_times: usize) -> Option<Duration> {
        if self.cancel.is_cancelled()
            || self
                .fatal_sse_error
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .is_some()
        {
            return None;
        }
        self.inner.retry(current_times)
    }
}

#[derive(Clone)]
pub struct ExecutorStreamableHttpClient {
    client: HttpClient,
    fatal_sse_error: Arc<Mutex<Option<String>>>,
    cancel: CancellationToken,
    bearer_token_env_var: Option<String>,
}

impl ExecutorStreamableHttpClient {
    pub fn new(client: Executor) -> Self {
        Self {
            client: client.http(),
            fatal_sse_error: Arc::new(Mutex::new(None)),
            cancel: CancellationToken::new(),
            bearer_token_env_var: None,
        }
    }

    fn check_fatal_error(&self) -> std::result::Result<(), StreamableHttpError<ExecutionError>> {
        if let Some(message) = self
            .fatal_sse_error
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
        {
            return Err(StreamableHttpError::Sse(SseError::Body(Box::new(
                BoundedSseStreamError::FatalMessage(message),
            ))));
        }
        if self.cancel.is_cancelled() {
            return Err(StreamableHttpError::Client(ExecutionError::Cancelled));
        }
        Ok(())
    }
}

impl StreamableHttpClient for ExecutorStreamableHttpClient {
    type Error = ExecutionError;

    async fn post_message(
        &self,
        uri: Arc<str>,
        message: ClientJsonRpcMessage,
        session_id: Option<Arc<str>>,
        auth_header: Option<String>,
        custom_headers: HashMap<HeaderName, HeaderValue>,
    ) -> std::result::Result<StreamableHttpPostResponse, StreamableHttpError<Self::Error>> {
        self.post_message_with_max_sse_event_size(
            uri,
            message,
            session_id,
            auth_header,
            custom_headers,
            DEFAULT_MAX_SSE_EVENT_SIZE,
        )
        .await
    }

    async fn post_message_with_max_sse_event_size(
        &self,
        uri: Arc<str>,
        message: ClientJsonRpcMessage,
        session_id: Option<Arc<str>>,
        auth_header: Option<String>,
        custom_headers: HashMap<HeaderName, HeaderValue>,
        max_sse_event_size: usize,
    ) -> std::result::Result<StreamableHttpPostResponse, StreamableHttpError<Self::Error>> {
        self.check_fatal_error()?;

        let mut headers = Vec::with_capacity(custom_headers.len() + 4);
        headers.push(HttpHeader {
            name: http::header::ACCEPT.as_str().to_owned(),
            value: format!("{EVENT_STREAM_MIME_TYPE}, {JSON_MIME_TYPE}").into_bytes(),
        });
        headers.push(HttpHeader {
            name: http::header::CONTENT_TYPE.as_str().to_owned(),
            value: JSON_MIME_TYPE.as_bytes().to_vec(),
        });
        if let Some(auth_header) = auth_header {
            headers.push(HttpHeader {
                name: http::header::AUTHORIZATION.as_str().to_owned(),
                value: format!("Bearer {auth_header}").into_bytes(),
            });
        }
        append_validated_custom_headers(&mut headers, custom_headers)?;

        let session_was_attached = session_id.is_some();
        if let Some(session_id) = session_id {
            headers.push(HttpHeader {
                name: HEADER_SESSION_ID.to_owned(),
                value: session_id.as_bytes().to_vec(),
            });
        }

        let payload = serde_json::to_vec(&message)?;
        let response = tokio::select! {
            _ = self.cancel.cancelled() => return Err(StreamableHttpError::Client(ExecutionError::Cancelled)),
            res = exchange(&self.client,
                HttpRequest {
                    method: "POST".to_owned(),
                    url: uri.to_string(),
                    headers,
                    bearer_token_env_var: self.bearer_token_env_var.clone(),
                },
                Bytes::from(payload),
                self.cancel.clone(),
            ) => res.map_err(StreamableHttpError::Client)?,
        };

        let status = response.status;
        let response_headers = response.header_map().map_err(StreamableHttpError::Client)?;

        if status == StatusCode::UNAUTHORIZED
            && let Some(header) = response_headers.get(http::header::WWW_AUTHENTICATE)
            && let Ok(header) = header.to_str()
        {
            return Err(StreamableHttpError::AuthRequired(AuthRequiredError::new(
                header.to_string(),
            )));
        }

        if status == StatusCode::FORBIDDEN
            && let Some(header) = response_headers.get(http::header::WWW_AUTHENTICATE)
            && let Ok(header) = header.to_str()
        {
            let scope = extract_scope_from_header(header);
            return Err(StreamableHttpError::InsufficientScope(
                InsufficientScopeError::new(header.to_string(), scope),
            ));
        }

        if matches!(status, StatusCode::ACCEPTED | StatusCode::NO_CONTENT) {
            return Ok(StreamableHttpPostResponse::Accepted);
        }

        if !status.is_success() {
            let body_bytes = response
                .collect_body(ERROR_BODY_LIMIT_BYTES)
                .await
                .unwrap_or_else(|_| Bytes::from_static(b"<unavailable>"));
            let body = String::from_utf8_lossy(&body_bytes);

            if status == StatusCode::NOT_FOUND && session_was_attached {
                return Err(StreamableHttpError::SessionExpired);
            }

            if let Some(discover_response) =
                legacy_discover_response(&message, session_was_attached, status, &body)
            {
                return Ok(discover_response);
            }

            if let Some(error_message) = parse_json_rpc_error(&body) {
                return Ok(StreamableHttpPostResponse::Json(error_message, None));
            }

            return Err(StreamableHttpError::UnexpectedServerResponse(Cow::Owned(
                format!("HTTP {status}: {body}"),
            )));
        }

        let content_type = response_headers
            .get(http::header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .map(str::to_owned);
        let session_id = extract_session_id(&response_headers)?;

        match content_type.as_deref() {
            Some(ct) if ct.contains(EVENT_STREAM_MIME_TYPE) => {
                let sse_stream = bounded_sse_stream(
                    response.body,
                    max_sse_event_size,
                    self.fatal_sse_error.clone(),
                    self.cancel.clone(),
                );
                Ok(StreamableHttpPostResponse::Sse(sse_stream, session_id))
            }
            Some(ct) if ct.contains(JSON_MIME_TYPE) => {
                let body = response
                    .collect_body(max_sse_event_size.max(MAX_NON_STREAM_BODY_BYTES))
                    .await
                    .map_err(StreamableHttpError::Client)?;
                if body.is_empty()
                    && matches!(
                        message,
                        ClientJsonRpcMessage::Notification(_)
                            | ClientJsonRpcMessage::Response(_)
                            | ClientJsonRpcMessage::Error(_)
                    )
                {
                    return Ok(StreamableHttpPostResponse::Accepted);
                }
                let parsed: ServerJsonRpcMessage =
                    serde_json::from_slice(&body).map_err(|error| {
                        StreamableHttpError::UnexpectedServerResponse(
                            json_rpc_parse_error_message(&error, &body).into(),
                        )
                    })?;
                Ok(StreamableHttpPostResponse::Json(parsed, session_id))
            }
            None | Some("")
                if matches!(
                    message,
                    ClientJsonRpcMessage::Notification(_)
                        | ClientJsonRpcMessage::Response(_)
                        | ClientJsonRpcMessage::Error(_)
                ) =>
            {
                let body = response
                    .collect_body(MAX_NON_STREAM_BODY_BYTES)
                    .await
                    .map_err(StreamableHttpError::Client)?;
                if body.is_empty() {
                    Ok(StreamableHttpPostResponse::Accepted)
                } else {
                    Err(StreamableHttpError::UnexpectedContentType(content_type))
                }
            }
            _ => Err(StreamableHttpError::UnexpectedContentType(content_type)),
        }
    }

    async fn delete_session(
        &self,
        uri: Arc<str>,
        session_id: Arc<str>,
        auth_header: Option<String>,
        custom_headers: HashMap<HeaderName, HeaderValue>,
    ) -> std::result::Result<(), StreamableHttpError<Self::Error>> {
        let mut headers = Vec::with_capacity(custom_headers.len() + 2);
        if let Some(auth_header) = auth_header {
            headers.push(HttpHeader {
                name: http::header::AUTHORIZATION.as_str().to_owned(),
                value: format!("Bearer {auth_header}").into_bytes(),
            });
        }
        append_validated_custom_headers(&mut headers, custom_headers)?;
        headers.push(HttpHeader {
            name: HEADER_SESSION_ID.to_owned(),
            value: session_id.as_bytes().to_vec(),
        });

        let response = exchange(
            &self.client,
            HttpRequest {
                method: "DELETE".to_owned(),
                url: uri.to_string(),
                headers,
                bearer_token_env_var: self.bearer_token_env_var.clone(),
            },
            Bytes::new(),
            CancellationToken::new(),
        )
        .await
        .map_err(StreamableHttpError::Client)?;

        let status = response.status;
        if status == StatusCode::METHOD_NOT_ALLOWED || status.is_success() {
            return Ok(());
        }

        let body_bytes = response
            .collect_body(ERROR_BODY_LIMIT_BYTES)
            .await
            .unwrap_or_default();
        let body = String::from_utf8_lossy(&body_bytes);
        Err(StreamableHttpError::UnexpectedServerResponse(Cow::Owned(
            format!("HTTP {status}: {body}"),
        )))
    }

    async fn get_stream(
        &self,
        uri: Arc<str>,
        session_id: Option<Arc<str>>,
        last_event_id: Option<String>,
        auth_header: Option<String>,
        custom_headers: HashMap<HeaderName, HeaderValue>,
    ) -> std::result::Result<
        BoxStream<'static, std::result::Result<Sse, SseError>>,
        StreamableHttpError<Self::Error>,
    > {
        self.get_stream_with_max_sse_event_size(
            uri,
            session_id,
            last_event_id,
            auth_header,
            custom_headers,
            DEFAULT_MAX_SSE_EVENT_SIZE,
        )
        .await
    }

    async fn get_stream_with_max_sse_event_size(
        &self,
        uri: Arc<str>,
        session_id: Option<Arc<str>>,
        last_event_id: Option<String>,
        auth_header: Option<String>,
        custom_headers: HashMap<HeaderName, HeaderValue>,
        max_sse_event_size: usize,
    ) -> std::result::Result<
        BoxStream<'static, std::result::Result<Sse, SseError>>,
        StreamableHttpError<Self::Error>,
    > {
        self.check_fatal_error()?;

        let mut headers = Vec::with_capacity(custom_headers.len() + 4);
        headers.push(HttpHeader {
            name: http::header::ACCEPT.as_str().to_owned(),
            value: format!("{EVENT_STREAM_MIME_TYPE}, {JSON_MIME_TYPE}").into_bytes(),
        });
        if let Some(auth_header) = auth_header {
            headers.push(HttpHeader {
                name: http::header::AUTHORIZATION.as_str().to_owned(),
                value: format!("Bearer {auth_header}").into_bytes(),
            });
        }
        append_validated_custom_headers(&mut headers, custom_headers)?;

        let session_was_attached = session_id.is_some();
        if let Some(session_id) = session_id {
            headers.push(HttpHeader {
                name: HEADER_SESSION_ID.to_owned(),
                value: session_id.as_bytes().to_vec(),
            });
        }
        if let Some(last_event_id) = last_event_id {
            headers.push(HttpHeader {
                name: HEADER_LAST_EVENT_ID.to_owned(),
                value: last_event_id.into_bytes(),
            });
        }

        let response = tokio::select! {
            _ = self.cancel.cancelled() => return Err(StreamableHttpError::Client(ExecutionError::Cancelled)),
            res = exchange(&self.client,
                HttpRequest {
                    method: "GET".to_owned(),
                    url: uri.to_string(),
                    headers,
                    bearer_token_env_var: self.bearer_token_env_var.clone(),
                },
                Bytes::new(),
                self.cancel.clone(),
            ) => res.map_err(StreamableHttpError::Client)?,
        };

        let status = response.status;
        if status == StatusCode::METHOD_NOT_ALLOWED {
            return Err(StreamableHttpError::ServerDoesNotSupportSse);
        }

        let response_headers = response.header_map().map_err(StreamableHttpError::Client)?;

        if status == StatusCode::UNAUTHORIZED
            && let Some(header) = response_headers.get(http::header::WWW_AUTHENTICATE)
            && let Ok(header) = header.to_str()
        {
            return Err(StreamableHttpError::AuthRequired(AuthRequiredError::new(
                header.to_string(),
            )));
        }

        if status == StatusCode::FORBIDDEN
            && let Some(header) = response_headers.get(http::header::WWW_AUTHENTICATE)
            && let Ok(header) = header.to_str()
        {
            let scope = extract_scope_from_header(header);
            return Err(StreamableHttpError::InsufficientScope(
                InsufficientScopeError::new(header.to_string(), scope),
            ));
        }

        if status == StatusCode::NOT_FOUND && session_was_attached {
            return Err(StreamableHttpError::SessionExpired);
        }

        if !status.is_success() {
            let body_bytes = response
                .collect_body(ERROR_BODY_LIMIT_BYTES)
                .await
                .unwrap_or_default();
            let body = String::from_utf8_lossy(&body_bytes);
            return Err(StreamableHttpError::UnexpectedServerResponse(Cow::Owned(
                format!("HTTP {status}: {body}"),
            )));
        }

        let content_type = response_headers
            .get(http::header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .map(str::to_owned);
        match content_type.as_deref() {
            Some(ct) if ct.contains(EVENT_STREAM_MIME_TYPE) => Ok(bounded_sse_stream(
                response.body,
                max_sse_event_size,
                self.fatal_sse_error.clone(),
                self.cancel.clone(),
            )),
            _ => Err(StreamableHttpError::UnexpectedContentType(content_type)),
        }
    }
}

fn append_validated_custom_headers(
    out: &mut Vec<HttpHeader>,
    custom_headers: HashMap<HeaderName, HeaderValue>,
) -> std::result::Result<(), StreamableHttpError<ExecutionError>> {
    for (name, value) in custom_headers {
        validate_custom_header(&name).map_err(StreamableHttpError::ReservedHeaderConflict)?;
        out.push(HttpHeader {
            name: name.as_str().to_owned(),
            value: value.as_bytes().to_vec(),
        });
    }
    Ok(())
}

fn validate_custom_header(name: &HeaderName) -> std::result::Result<(), String> {
    if RESERVED_HEADERS
        .iter()
        .any(|&reserved| name.as_str().eq_ignore_ascii_case(reserved))
    {
        if name
            .as_str()
            .eq_ignore_ascii_case(HEADER_MCP_PROTOCOL_VERSION)
        {
            return Ok(());
        }
        return Err(name.to_string());
    }
    Ok(())
}

fn extract_session_id(
    headers: &HeaderMap,
) -> std::result::Result<Option<String>, StreamableHttpError<ExecutionError>> {
    let Some(value) = headers.get(HEADER_SESSION_ID) else {
        return Ok(None);
    };
    let session_id = value.to_str().map_err(|error| {
        StreamableHttpError::UnexpectedServerResponse(
            format!("invalid Mcp-Session-Id header value: {error}").into(),
        )
    })?;
    Ok(Some(session_id.to_owned()))
}

fn extract_scope_from_header(header: &str) -> Option<String> {
    let header_lowercase = header.to_ascii_lowercase();
    let scope_key = "scope=";
    if let Some(pos) = header_lowercase.find(scope_key) {
        let start = pos + scope_key.len();
        let value_slice = &header[start..];
        if let Some(stripped) = value_slice.strip_prefix('"') {
            if let Some(end_quote) = stripped.find('"') {
                return Some(stripped[..end_quote].to_string());
            }
        } else {
            let end = value_slice
                .find(|c: char| c == ',' || c == ';' || c.is_whitespace())
                .unwrap_or(value_slice.len());
            if end > 0 {
                return Some(value_slice[..end].to_string());
            }
        }
    }
    None
}

fn parse_json_rpc_error(body: &str) -> Option<ServerJsonRpcMessage> {
    let trimmed = body.trim();
    if trimmed.is_empty() {
        return None;
    }
    match serde_json::from_str::<ServerJsonRpcMessage>(trimmed) {
        Ok(message @ JsonRpcMessage::Error(_)) => Some(message),
        _ => None,
    }
}

fn legacy_discover_response(
    message: &ClientJsonRpcMessage,
    session_was_attached: bool,
    status: StatusCode,
    body: &str,
) -> Option<StreamableHttpPostResponse> {
    if session_was_attached
        || !status.is_client_error()
        || matches!(status, StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN)
    {
        return None;
    }
    let ClientJsonRpcMessage::Request(request) = message else {
        return None;
    };
    if !matches!(request.request, ClientRequest::DiscoverRequest(_)) {
        return None;
    }
    let error = match serde_json::from_str::<ServerJsonRpcMessage>(body) {
        Ok(ServerJsonRpcMessage::Error(error)) => error.error,
        _ => ErrorData::invalid_request(
            format!("server/discover rejected with HTTP {status}: {body}"),
            None,
        ),
    };
    Some(StreamableHttpPostResponse::Json(
        ServerJsonRpcMessage::error(error, Some(request.id.clone())),
        None,
    ))
}

fn json_rpc_body_preview(body: &[u8]) -> Cow<'static, str> {
    if body.is_empty() {
        return Cow::Borrowed("<empty>");
    }
    let lossy = String::from_utf8_lossy(body);
    if lossy.len() <= JSON_RPC_BODY_PREVIEW_LEN {
        return Cow::Owned(lossy.into_owned());
    }
    let mut end = JSON_RPC_BODY_PREVIEW_LEN;
    while end > 0 && !lossy.is_char_boundary(end) {
        end -= 1;
    }
    Cow::Owned(lossy[..end].to_owned())
}

fn json_rpc_parse_error_message(err: &serde_json::Error, body: &[u8]) -> String {
    format!(
        "could not parse JSON response as ServerJsonRpcMessage: {err}: {}",
        json_rpc_body_preview(body)
    )
}

#[derive(Debug, Error)]
enum BoundedSseStreamError {
    #[error(transparent)]
    Source(Box<dyn std::error::Error + Send + Sync>),
    #[error("SSE event exceeded the maximum size of {max_size} bytes")]
    EventTooLarge { max_size: usize },
    #[error("{0}")]
    FatalMessage(String),
}

#[derive(Debug)]
struct SseEventSizeLimiter {
    max_size: usize,
    retained_size: usize,
    line_size: usize,
    line_is_comment: bool,
    previous_was_cr: bool,
}

impl SseEventSizeLimiter {
    fn new(max_size: usize) -> Self {
        Self {
            max_size,
            retained_size: 0,
            line_size: 0,
            line_is_comment: false,
            previous_was_cr: false,
        }
    }

    fn observe(&mut self, chunk: &[u8]) -> std::result::Result<(), ()> {
        for &byte in chunk {
            if self.previous_was_cr {
                self.previous_was_cr = false;
                if byte == b'\n' {
                    continue;
                }
            }
            match byte {
                b'\r' => {
                    self.finish_line()?;
                    self.previous_was_cr = true;
                }
                b'\n' => self.finish_line()?,
                _ => {
                    if self.line_size == 0 {
                        self.line_is_comment = byte == b':';
                    }
                    self.line_size = self.line_size.saturating_add(1);
                    self.check_limit()?;
                }
            }
        }
        Ok(())
    }

    fn finish_line(&mut self) -> std::result::Result<(), ()> {
        if self.line_size == 0 {
            self.retained_size = 0;
        } else if !self.line_is_comment {
            self.retained_size = self
                .retained_size
                .saturating_add(self.line_size)
                .saturating_add(1);
        }
        self.line_size = 0;
        self.line_is_comment = false;
        self.check_limit()
    }

    fn check_limit(&self) -> std::result::Result<(), ()> {
        if self.retained_size.saturating_add(self.line_size) > self.max_size {
            Err(())
        } else {
            Ok(())
        }
    }
}

struct BoundedSseByteStream {
    inner: BoxStream<'static, std::result::Result<Bytes, ExecutionError>>,
    limiter: SseEventSizeLimiter,
    fatal_sse_error: Arc<Mutex<Option<String>>>,
    cancel: CancellationToken,
    failed: bool,
}

impl Stream for BoundedSseByteStream {
    type Item = std::result::Result<Bytes, BoundedSseStreamError>;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        if this.failed || this.cancel.is_cancelled() {
            return Poll::Ready(None);
        }
        match ready!(this.inner.as_mut().poll_next(cx)) {
            Some(Ok(chunk)) => {
                if this.limiter.observe(&chunk).is_err() {
                    this.failed = true;
                    let err = BoundedSseStreamError::EventTooLarge {
                        max_size: this.limiter.max_size,
                    };
                    *this
                        .fatal_sse_error
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(err.to_string());
                    this.cancel.cancel();
                    Poll::Ready(Some(Err(err)))
                } else {
                    Poll::Ready(Some(Ok(chunk)))
                }
            }
            Some(Err(error)) => {
                this.failed = true;
                Poll::Ready(Some(Err(BoundedSseStreamError::Source(Box::new(error)))))
            }
            None => Poll::Ready(None),
        }
    }
}

fn bounded_sse_stream(
    stream: BoxStream<'static, std::result::Result<Bytes, ExecutionError>>,
    max_event_size: usize,
    fatal_sse_error: Arc<Mutex<Option<String>>>,
    cancel: CancellationToken,
) -> BoxStream<'static, std::result::Result<Sse, SseError>> {
    let stream = BoundedSseByteStream {
        inner: stream,
        limiter: SseEventSizeLimiter::new(max_event_size),
        fatal_sse_error,
        cancel,
        failed: false,
    };
    // rmcp's public transport contract still uses sse-stream 0.2. Keep that
    // type conversion at this boundary; all wire decoding uses 0.3.
    SseByteStream::new(stream)
        .map(|event| {
            event
                .map(|event| Sse {
                    event: event.event,
                    data: event.data,
                    id: event.id,
                    retry: event.retry,
                })
                .map_err(|error| match error {
                    sse_stream::Error::Body(error) => SseError::Body(error),
                    sse_stream::Error::Utf8Parse(error) => SseError::Utf8Parse(error),
                    error => SseError::Body(Box::new(error)),
                })
        })
        .boxed()
}

pub struct Response {
    pub status: StatusCode,
    pub headers: Vec<HttpHeader>,
    pub body: BoxStream<'static, std::result::Result<Bytes, ExecutionError>>,
}

impl std::fmt::Debug for Response {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Response")
            .field("status", &self.status)
            .field("headers", &self.headers.len())
            .finish_non_exhaustive()
    }
}

impl Response {
    pub fn header_map(&self) -> std::result::Result<HeaderMap, ExecutionError> {
        let mut map = HeaderMap::with_capacity(self.headers.len());
        for header in &self.headers {
            let name = HeaderName::from_bytes(header.name.as_bytes()).map_err(|error| {
                ExecutionError::Protocol(format!(
                    "invalid remote HTTP response header name '{}': {error}",
                    header.name
                ))
            })?;
            let value = HeaderValue::from_bytes(&header.value).map_err(|error| {
                ExecutionError::Protocol(format!(
                    "invalid remote HTTP response header value for '{}': {error}",
                    header.name
                ))
            })?;
            map.append(name, value);
        }
        Ok(map)
    }

    pub async fn collect_body(
        mut self,
        max_bytes: usize,
    ) -> std::result::Result<Bytes, ExecutionError> {
        let mut out = Vec::new();
        while let Some(chunk) = self.body.next().await {
            let chunk = chunk?;
            if out.len().saturating_add(chunk.len()) > max_bytes {
                return Err(ExecutionError::Protocol(format!(
                    "HTTP body exceeds {max_bytes} bytes"
                )));
            }
            out.extend_from_slice(&chunk);
        }
        Ok(Bytes::from(out))
    }
}

async fn exchange(
    client: &HttpClient,
    head: HttpRequest,
    body: Bytes,
    cancel: CancellationToken,
) -> std::result::Result<Response, ExecutionError> {
    use tokio_util::io::ReaderStream;
    let response = client.execute(head, body).await?;
    Ok(Response {
        status: StatusCode::from_u16(response.head.status)
            .map_err(|error| ExecutionError::Protocol(error.to_string()))?,
        headers: response
            .head
            .headers
            .into_iter()
            .map(|header| HttpHeader {
                name: header.name,
                value: header.value,
            })
            .collect(),
        body: futures::stream::try_unfold((ReaderStream::new(response.body),cancel),|(mut reader,cancel)|async move {
            tokio::select! {
                _=cancel.cancelled()=>Err(ExecutionError::Cancelled),
                item=reader.next()=>match item {
                    None=>Ok(None),
                    Some(Ok(bytes))=>Ok(Some((bytes,(reader,cancel)))),
                    Some(Err(error))=>Err(ExecutionError::Io{operation:"HTTP body",source:Arc::new(error)}),
                }
            }
        }).boxed(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn current_decoder_preserves_metadata_at_the_rmcp_boundary() {
        let input = concat!(
            "\u{feff}extension: ignored\r\n",
            "event: old\r\nevent: message\r\n",
            "id: old\r\nid: last\r\nid: ignored\0id\r\n",
            "retry: 10\r\nretry: 20\r\nretry: invalid\r\n",
            "data: {\"jsonrpc\":\"2.0\",\r\ndata: \"id\":1,\"result\":{}}\r\n\r\n",
        );
        let bytes = input.bytes().map(|byte| Ok(Bytes::from(vec![byte])));
        let fatal = Arc::new(Mutex::new(None));
        let mut stream = bounded_sse_stream(
            futures::stream::iter(bytes.collect::<Vec<_>>()).boxed(),
            1024,
            fatal.clone(),
            CancellationToken::new(),
        );
        let event = stream.next().await.unwrap().unwrap();
        assert_eq!(event.event.as_deref(), Some("message"));
        assert_eq!(event.id.as_deref(), Some("last"));
        assert_eq!(event.retry, Some(20));
        let data: serde_json::Value = serde_json::from_str(event.data.as_deref().unwrap()).unwrap();
        assert_eq!(data["id"], 1);
        assert_eq!(data["result"], serde_json::json!({}));
        assert!(stream.next().await.is_none());
        assert!(fatal.lock().unwrap().is_none());
    }

    #[tokio::test]
    async fn decoder_errors_end_once_and_receive_limits_cancel_the_owner() {
        for (input, limit, oversized) in [
            (&b"data: \xff\n\ndata: later\n\n"[..], 1024, false),
            (&b"data: too large\n\ndata: later\n\n"[..], 8, true),
        ] {
            let fatal = Arc::new(Mutex::new(None));
            let cancel = CancellationToken::new();
            let mut stream = bounded_sse_stream(
                futures::stream::iter(vec![Ok(Bytes::copy_from_slice(input))]).boxed(),
                limit,
                fatal.clone(),
                cancel.clone(),
            );
            assert!(stream.next().await.unwrap().is_err());
            assert!(stream.next().await.is_none());
            assert!(stream.next().await.is_none());
            assert_eq!(cancel.is_cancelled(), oversized);
            assert_eq!(fatal.lock().unwrap().is_some(), oversized);
        }
    }
}
