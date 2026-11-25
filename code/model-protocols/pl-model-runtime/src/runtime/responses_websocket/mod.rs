use futures::stream::BoxStream;
use pl_model_wire::provider_error::{
    ErrorPolicyBinding, ProviderErrorEntry, ProviderErrorPolicy, transport_failure,
};
use pl_model_wire::transport::{RawSseFrame, RequestDiagnostics};
use pl_model_wire::wire_codec::{VisibleOutputProtocol, WireStreamDecoder};
use pl_protocol::{ProviderFailureStage, ProviderRecovery, RetryDisposition};
use std::{collections::HashMap, sync::Arc};

use futures::StreamExt;
use pl_protocol::{PureError, Result};
use serde_json::{Map, Value};
use tokio::sync::OwnedMutexGuard;
use tokio::time::timeout;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::http::header::AUTHORIZATION;
use tokio_tungstenite::tungstenite::http::{HeaderName, HeaderValue};

use crate::completion::{AssistantReplay, CompletionTraceContext};
use crate::protocol::{RESPONSES_WEBSOCKET_DIALECT, WireApi};
use crate::runtime::ModelSession;
use crate::runtime::invocation::AttemptDispatch;
use crate::runtime::openai::sent_model_from_wire_body;
use crate::runtime::openai::sse::SseStreamEvent;
use crate::runtime::session::{ResponsesWebSocketConnection, ResponsesWebSocketSession};
use crate::runtime::transport_policy::{
    RESPONSES_WEBSOCKET_CONNECT_TIMEOUT, RESPONSES_WEBSOCKET_SEND_TIMEOUT,
};
use crate::stream::event::ModelStreamEvent;
use crate::stream::replay::ReplayCollector;
use crate::stream::{CompletionEventStream, StreamErrorBinding, decode_wire_stream};

mod dialer;
pub(crate) mod error;

use error::{
    close_error, connection_error, handshake_error, handshake_timeout_error, protocol_error,
};
#[derive(Debug)]
enum ResponsesStreamState {
    Open,
    Completed(Box<SseStreamEvent>),
    Failed { detail: String },
    Closed,
}

pub(super) struct StreamResponsesInput<'a> {
    pub api_base: String,
    pub token: Option<String>,
    pub provider_headers: Option<&'a HashMap<String, String>>,
    pub model_headers: &'a HashMap<String, String>,
    pub connection_key: u64,
    pub model_session: ModelSession,
    pub body: Map<String, Value>,
    pub expected_sent_model: String,
    pub trace: Option<CompletionTraceContext>,
    pub endpoint: &'a crate::protocol::ProtocolEndpoint,
    pub error_policy: &'static dyn ProviderErrorPolicy,
    pub decoder: Box<dyn WireStreamDecoder>,
    pub visible_output: VisibleOutputProtocol,
    pub cancellation: tokio_util::sync::CancellationToken,
    pub dispatch: &'a AttemptDispatch<'a>,
}

pub(super) struct OpenedResponsesStream {
    pub events: CompletionEventStream,
    pub sent_model: String,
}

pub(super) async fn stream_responses(
    input: StreamResponsesInput<'_>,
) -> Result<OpenedResponsesStream> {
    let StreamResponsesInput {
        api_base,
        token,
        provider_headers,
        model_headers,
        connection_key,
        model_session,
        mut body,
        expected_sent_model,
        trace,
        endpoint,
        error_policy,
        decoder,
        visible_output,
        cancellation,
        dispatch,
    } = input;
    let (url, request) =
        handshake_request(&api_base, token.as_deref(), provider_headers, model_headers)?;
    let diagnostics = Arc::new(RequestDiagnostics::from_headers(request.headers()));
    normalize_websocket_request_body(&mut body);

    // Own invalidation before the first await that can publish/send a request.
    let mut state = WebSocketEventState {
        guard: model_session.lock_responses_websocket().await,
        state: ResponsesStreamState::Open,
        used_continuation: false,
        full_request: body.clone(),
        model_session: model_session.clone(),
        replay: ReplayCollector::default(),
        diagnostics: diagnostics.clone(),
    };
    if state.guard.connection_key != Some(connection_key)
        || state
            .guard
            .connection
            .as_ref()
            .is_none_or(|connection| connection.is_closed())
    {
        state.guard.invalidate();
        state.guard.reap_retired().await?;
        if cancellation.is_cancelled() {
            return Err(PureError::LlmError(
                "model invocation cancelled before WebSocket connect".into(),
            ));
        }
        dispatch.connecting();
        state.guard.connection = Some(
            connect(
                request,
                &url,
                ErrorPolicyBinding {
                    policy: error_policy,
                    wire_api: crate::protocol::WireApi::Responses,
                    endpoint: Some(endpoint),
                },
                &diagnostics,
            )
            .await?,
        );
        state.guard.connection_key = Some(connection_key);
    }

    let (mut wire_body, used_continuation, fallback_reason) =
        match incremental_request(&state.guard, &body) {
            Ok(incremental) => (incremental, true, None),
            Err(reason) => (body.clone(), false, Some(reason)),
        };
    if used_continuation {
        model_session.record_continuation_attempt();
    }
    state.used_continuation = used_continuation;
    let input = body.get("input");
    let input_items = input.and_then(Value::as_array).map_or(0, Vec::len);
    let context_bytes = input
        .and_then(|input| serde_json::to_vec(input).ok())
        .map_or(0, |input| input.len());
    let wire_input_items = wire_body
        .get("input")
        .and_then(Value::as_array)
        .map_or(0, Vec::len);
    let (previous_prefix_items, first_differing_index) = fallback_reason
        .and_then(IncrementalRequestFallbackReason::prefix_mismatch)
        .map_or((0, 0), |diagnostics| {
            (
                diagnostics.previous_prefix_items,
                diagnostics.first_differing_index,
            )
        });
    let request_mode = if used_continuation {
        "incremental"
    } else {
        "full"
    };
    let sent_model = sent_model_from_wire_body(&wire_body)?;
    if sent_model != expected_sent_model {
        return Err(PureError::LlmError(format!(
            "Responses WebSocket request protocol error: final wire model changed from {expected_sent_model:?} to {sent_model:?}"
        )));
    }
    let request_text = response_create_text(&mut wire_body)?;
    super::wire_capture::capture_responses_websocket(request_mode, &wire_body, trace.as_ref())
        .await?;
    tracing::debug!(
        request_mode,
        fallback_reason = fallback_reason.map_or("none", IncrementalRequestFallbackReason::as_str),
        input_items,
        wire_input_items,
        context_bytes,
        request_bytes = request_text.len(),
        previous_prefix_items,
        first_differing_index,
        "Responses WebSocket request prepared"
    );
    if let Err(error) = send_request(&mut state.guard, &request_text, cancellation, dispatch).await
    {
        state.guard.invalidate();
        return Err(error);
    }

    let stream: BoxStream<'static, Result<RawSseFrame>> =
        futures::stream::unfold(state, |mut state| async move {
            match &state.state {
                ResponsesStreamState::Open => {}
                ResponsesStreamState::Completed(_) => {
                    if let Err(error) = state.finish_completed_response() {
                        let error = state.fail(error);
                        return Some((Err(error), state));
                    }
                    return None;
                }
                ResponsesStreamState::Failed { detail } => {
                    tracing::debug!(detail, "Responses WebSocket stream stopped");
                    return None;
                }
                ResponsesStreamState::Closed => return None,
            }
            let event = state.next_event().await;
            Some((event, state))
        })
        .boxed();
    let events = decode_wire_stream(
        decoder,
        stream,
        visible_output,
        false,
        trace,
        StreamErrorBinding {
            entry: ProviderErrorEntry::WebSocket,
            api: WireApi::Responses,
            endpoint: endpoint.clone(),
            policy: error_policy,
        },
    )
    .map(move |mut event| {
        // Only this owner knows whether the physical request used a continuation.
        let failure = match &mut event {
            Ok(ModelStreamEvent::Failed { failure }) => Some(failure),
            Err(PureError::Provider(failure)) => Some(failure.as_mut()),
            _ => None,
        };
        if let Some(failure) = failure
            && failure.context.recovery == ProviderRecovery::FullContext
        {
            if used_continuation {
                model_session.record_continuation_invalid();
            } else {
                failure.context.recovery = ProviderRecovery::None;
                failure.retry = RetryDisposition::Permanent;
            }
        }
        event
    })
    .boxed();
    Ok(OpenedResponsesStream { events, sent_model })
}

fn normalize_websocket_request_body(body: &mut Map<String, Value>) {
    body.remove("previous_response_id");
    // WS continuation 只属于当前物理连接；供应商会拒绝把该响应持久化到服务端。
    body.insert("store".to_string(), Value::Bool(false));
    // Responses WebSocket v2 的 `response.create` schema 要求显式携带 tools；
    // HTTP Responses 接受省略空工具列表，但兼容 WS 代理可能直接关闭连接。
    body.entry("tools".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
}

fn response_create_text(body: &mut Map<String, Value>) -> Result<String> {
    body.insert(
        "type".to_string(),
        Value::String("response.create".to_string()),
    );
    serde_json::to_string(body).map_err(|error| PureError::ConfigError(error.to_string()))
}

fn incremental_request(
    session: &ResponsesWebSocketSession,
    current: &Map<String, Value>,
) -> std::result::Result<Map<String, Value>, IncrementalRequestFallbackReason> {
    let previous = session
        .last_request
        .as_ref()
        .ok_or(IncrementalRequestFallbackReason::MissingPreviousRequest)?;
    let response_id = session
        .last_response_id
        .as_deref()
        .ok_or(IncrementalRequestFallbackReason::MissingPreviousResponseId)?;
    if request_properties(previous) != request_properties(current) {
        return Err(IncrementalRequestFallbackReason::RequestPropertiesChanged);
    }
    let mut previous_items = previous
        .get("input")
        .and_then(Value::as_array)
        .cloned()
        .ok_or(IncrementalRequestFallbackReason::PreviousInputNotArray)?;
    previous_items.extend(session.last_response_items.iter().cloned());
    let current_items = current
        .get("input")
        .and_then(Value::as_array)
        .ok_or(IncrementalRequestFallbackReason::CurrentInputNotArray)?;
    if !current_items.starts_with(&previous_items) {
        let first_differing_index = previous_items
            .iter()
            .zip(current_items)
            .position(|(previous, current)| previous != current)
            .unwrap_or_else(|| previous_items.len().min(current_items.len()));
        return Err(IncrementalRequestFallbackReason::InputPrefixMismatch {
            previous_prefix_items: previous_items.len(),
            first_differing_index,
        });
    }
    let mut incremental = current.clone();
    incremental.insert(
        "input".to_string(),
        Value::Array(current_items[previous_items.len()..].to_vec()),
    );
    incremental.insert(
        "previous_response_id".to_string(),
        Value::String(response_id.to_string()),
    );
    Ok(incremental)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum IncrementalRequestFallbackReason {
    MissingPreviousRequest,
    MissingPreviousResponseId,
    RequestPropertiesChanged,
    PreviousInputNotArray,
    CurrentInputNotArray,
    InputPrefixMismatch {
        previous_prefix_items: usize,
        first_differing_index: usize,
    },
}

impl IncrementalRequestFallbackReason {
    const fn as_str(self) -> &'static str {
        match self {
            Self::MissingPreviousRequest => "missingPreviousRequest",
            Self::MissingPreviousResponseId => "missingPreviousResponseId",
            Self::RequestPropertiesChanged => "requestPropertiesChanged",
            Self::PreviousInputNotArray => "previousInputNotArray",
            Self::CurrentInputNotArray => "currentInputNotArray",
            Self::InputPrefixMismatch { .. } => "inputPrefixMismatch",
        }
    }

    const fn prefix_mismatch(self) -> Option<InputPrefixMismatchDiagnostics> {
        match self {
            Self::InputPrefixMismatch {
                previous_prefix_items,
                first_differing_index,
            } => Some(InputPrefixMismatchDiagnostics {
                previous_prefix_items,
                first_differing_index,
            }),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct InputPrefixMismatchDiagnostics {
    previous_prefix_items: usize,
    first_differing_index: usize,
}

fn request_properties(body: &Map<String, Value>) -> Map<String, Value> {
    let mut properties = body.clone();
    properties.remove("input");
    properties.remove("previous_response_id");
    properties.remove("type");
    properties
}

fn handshake_request(
    api_base: &str,
    token: Option<&str>,
    provider_headers: Option<&HashMap<String, String>>,
    model_headers: &HashMap<String, String>,
) -> Result<(
    reqwest::Url,
    tokio_tungstenite::tungstenite::handshake::client::Request,
)> {
    let url = responses_websocket_url(api_base)?;
    let mut request = url
        .as_str()
        .into_client_request()
        .map_err(|error| PureError::HttpError(error.to_string()))?;
    request.headers_mut().insert(
        HeaderName::from_static("openai-beta"),
        HeaderValue::from_static(RESPONSES_WEBSOCKET_DIALECT),
    );
    if let Some(token) = token {
        let mut value = HeaderValue::from_str(&format!("Bearer {token}"))
            .map_err(|error| PureError::HttpError(error.to_string()))?;
        value.set_sensitive(true);
        request.headers_mut().insert(AUTHORIZATION, value);
    }
    if let Some(headers) = provider_headers {
        insert_headers(request.headers_mut(), headers)?;
    }
    insert_headers(request.headers_mut(), model_headers)?;

    Ok((url, request))
}

async fn connect(
    request: tokio_tungstenite::tungstenite::handshake::client::Request,
    url: &reqwest::Url,
    error_policy: ErrorPolicyBinding<'_>,
    diagnostics: &RequestDiagnostics,
) -> Result<ResponsesWebSocketConnection> {
    let (connection, _) = timeout(
        RESPONSES_WEBSOCKET_CONNECT_TIMEOUT,
        dialer::connect(request, url),
    )
    .await
    .map_err(handshake_timeout_error)?
    .map_err(|error| handshake_error(error, error_policy, diagnostics))?;
    Ok(ResponsesWebSocketConnection::new(connection))
}

fn responses_websocket_url(api_base: &str) -> Result<reqwest::Url> {
    let mut url = reqwest::Url::parse(api_base.trim_end_matches('/'))
        .map_err(|error| PureError::ConfigError(format!("invalid provider base URL: {error}")))?;
    let websocket_scheme = match url.scheme() {
        "https" => "wss",
        "http" => "ws",
        "wss" => "wss",
        "ws" => "ws",
        scheme => {
            return Err(PureError::ConfigError(format!(
                "unsupported provider URL scheme for WebSocket: {scheme}"
            )));
        }
    };
    url.set_scheme(websocket_scheme).map_err(|()| {
        PureError::ConfigError("failed to construct Responses WebSocket URL".to_string())
    })?;
    let path = format!("{}/responses", url.path().trim_end_matches('/'));
    url.set_path(&path);
    Ok(url)
}

fn insert_headers(
    target: &mut tokio_tungstenite::tungstenite::http::HeaderMap,
    headers: &HashMap<String, String>,
) -> Result<()> {
    for (name, value) in headers {
        let name = HeaderName::from_bytes(name.as_bytes())
            .map_err(|error| PureError::HttpError(error.to_string()))?;
        let mut value = HeaderValue::from_str(value)
            .map_err(|error| PureError::HttpError(error.to_string()))?;
        value.set_sensitive(true);
        target.insert(name, value);
    }
    Ok(())
}

async fn send_request(
    session: &mut OwnedMutexGuard<ResponsesWebSocketSession>,
    request_text: &str,
    cancellation: tokio_util::sync::CancellationToken,
    dispatch: &AttemptDispatch<'_>,
) -> Result<()> {
    let connection = session
        .connection
        .as_mut()
        .ok_or_else(|| connection_error("connection is unavailable"))?;
    if cancellation.is_cancelled() {
        return Err(PureError::LlmError(
            "model invocation cancelled before WebSocket send".into(),
        ));
    }
    dispatch.submitting();
    timeout(
        RESPONSES_WEBSOCKET_SEND_TIMEOUT,
        connection.send(Message::Text(request_text.to_string().into()), cancellation),
    )
    .await
    .map_err(|source| {
        transport_failure(
            ProviderFailureStage::Request,
            "Responses WebSocket send timed out after 15 seconds",
        )
        .with_source(source)
    })?
}

struct WebSocketEventState {
    guard: OwnedMutexGuard<ResponsesWebSocketSession>,
    state: ResponsesStreamState,
    used_continuation: bool,
    full_request: Map<String, Value>,
    model_session: ModelSession,
    replay: ReplayCollector,
    diagnostics: Arc<RequestDiagnostics>,
}

impl WebSocketEventState {
    async fn next_event(&mut self) -> Result<RawSseFrame> {
        loop {
            let next = {
                let connection = self
                    .guard
                    .connection
                    .as_mut()
                    .ok_or_else(|| connection_error("connection is unavailable"))?;
                connection.next().await
            };
            let (message, observed_at) = match next {
                Some(Ok(message)) => message,
                Some(Err(error)) => return Err(self.invalidate_with_connection_error(error)),
                None => {
                    return Err(self.invalidate_with_connection_error(connection_error(
                        "connection closed before a terminal response event",
                    )));
                }
            };
            match message {
                Message::Text(text) => {
                    let value: Value = match serde_json::from_str(text.as_str()) {
                        Ok(value) => value,
                        Err(source) => {
                            let error = error::protocol_failure(
                                ProviderFailureStage::Stream,
                                "invalid JSON WebSocket event",
                            )
                            .with_source(source)
                            .into();
                            return Err(self.fail(error));
                        }
                    };
                    let (request_id, header_retry) = error::frame_headers(&value, observed_at);
                    if let Err(error) = self.observe_frame(value) {
                        return Err(self.fail(error));
                    }
                    return Ok(RawSseFrame {
                        data: text.to_string(),
                        event_name: None,
                        request_id,
                        diagnostics: self.diagnostics.clone(),
                        observed_at,
                        header_retry,
                    });
                }
                Message::Ping(_) | Message::Pong(_) | Message::Frame(_) => {}
                Message::Binary(_) => {
                    let error = protocol_error("unexpected binary event");
                    return Err(self.fail(error));
                }
                Message::Close(frame) => {
                    let error = close_error(frame);
                    return Err(self.fail(error));
                }
            }
        }
    }

    fn observe_frame(&mut self, value: Value) -> Result<()> {
        if matches!(
            value.get("type").and_then(Value::as_str),
            Some("error" | "response.failed" | "response.incomplete")
        ) {
            self.guard.invalidate();
            self.state = ResponsesStreamState::Failed {
                detail: "provider returned terminal response".into(),
            };
            // The bound codec still receives the full frame, including any usage report.
            return Ok(());
        }
        let event: SseStreamEvent = serde_json::from_value(value).map_err(|source| {
            error::protocol_failure(
                ProviderFailureStage::Stream,
                "invalid Responses WebSocket event structure",
            )
            .with_source(source)
        })?;
        if let Some(update) = crate::runtime::openai::sse::replay_update(&event) {
            self.replay.apply(update)?;
        }
        if event.kind == "response.completed" {
            self.state = ResponsesStreamState::Completed(Box::new(event));
        }
        Ok(())
    }

    fn invalidate_with_connection_error(&mut self, error: PureError) -> PureError {
        self.fail(error)
    }

    fn fail(&mut self, error: PureError) -> PureError {
        self.guard.invalidate();
        self.state = ResponsesStreamState::Failed {
            detail: error.to_string(),
        };
        error
    }

    fn commit_completed_response(&mut self, event: &SseStreamEvent) -> Result<()> {
        let response = event.response.as_ref();
        let response_id = response
            .and_then(|response| response.get("id"))
            .and_then(Value::as_str)
            .filter(|id| !id.trim().is_empty())
            .map(ToString::to_string);
        let response_items = match self.replay.finish()? {
            Some(AssistantReplay::Responses { output }) => output,
            _ => {
                return Err(protocol_error(
                    "completed Responses stream has no native replay",
                ));
            }
        };
        // Native replay preserves every output field. An abbreviated terminal can
        // use validated completed items, but an id alone cannot prove an empty prefix.
        let complete_output = !response_items.is_empty()
            || response
                .and_then(|response| response.get("output"))
                .is_some_and(Value::is_array);
        if let Some(response_id) = response_id.filter(|_| complete_output) {
            self.guard.last_request = Some(self.full_request.clone());
            self.guard.last_response_id = Some(response_id);
            self.guard.last_response_items = response_items;
        } else {
            self.guard.last_request = None;
            self.guard.last_response_id = None;
            self.guard.last_response_items.clear();
        }
        Ok(())
    }

    fn finish_completed_response(&mut self) -> Result<()> {
        let ResponsesStreamState::Completed(completed) = &self.state else {
            return Ok(());
        };
        let event = completed.as_ref().clone();
        self.commit_completed_response(&event)?;
        if self.used_continuation {
            self.model_session.record_continuation_used();
        }
        self.state = ResponsesStreamState::Closed;
        Ok(())
    }
}

impl Drop for WebSocketEventState {
    fn drop(&mut self) {
        if !matches!(self.state, ResponsesStreamState::Closed) {
            self.guard.invalidate();
        }
    }
}
