//! Network execution only. The invocation owner decides whether an operation can be retried.
mod diagnostics;
mod sse_limit;
pub use diagnostics::RequestDiagnostics;

use futures::{StreamExt, stream::BoxStream};
use pl_protocol::{ProviderFailure, ProviderFailureKind as Kind, ProviderFailureStage};
use pl_protocol::{PureError, Result};
use reqwest::header::{CONTENT_TYPE, HeaderMap};
use std::sync::{Arc, Mutex};

pub const HTTP_REQUEST_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(180);

pub use super::provider_error::reqwest_error_to_pure;
use super::provider_error::{
    ClassifiedProviderError, ErrorObservedAt, ErrorPolicyBinding, ObservedRetry,
    ProviderErrorContext, ProviderErrorEntry, decode_provider_failure, redact_secret_like_values,
    request_id, reqwest_body_error_to_pure, transport_failure,
};

pub use pl_model_types::headers;

pub async fn checked(response: reqwest::Response) -> Result<reqwest::Response> {
    check_response(response, None, ProviderFailureStage::Request, None).await
}

pub async fn check_response(
    response: reqwest::Response,
    binding: Option<ErrorPolicyBinding<'_>>,
    stage: ProviderFailureStage,
    diagnostics: Option<&RequestDiagnostics>,
) -> Result<reqwest::Response> {
    if response.status().is_success() {
        return Ok(response);
    }
    Err(read_response_error(
        response,
        binding,
        stage,
        diagnostics,
        ErrorObservedAt::now(),
    )
    .await
    .failure
    .into())
}

/// Failure facts from reading an unsuccessful HTTP response once.
///
/// Body completeness is a transport observation, not permission to replay a submission.
/// Upload implementations combine it with their endpoint's rejection contract.
#[derive(Debug)]
pub struct HttpResponseFailure {
    pub failure: ProviderFailure,
    pub body_complete: bool,
}

/// Reads and classifies an unsuccessful HTTP response, retaining body-read completeness.
/// The caller captures `headers_received` as soon as the response arrives.
pub async fn read_response_error(
    response: reqwest::Response,
    binding: Option<ErrorPolicyBinding<'_>>,
    stage: ProviderFailureStage,
    diagnostics: Option<&RequestDiagnostics>,
    headers_received: ErrorObservedAt,
) -> HttpResponseFailure {
    let status = response.status().as_u16();
    let headers = response.headers().clone();
    let mut body = Vec::new();
    let mut stream = response.bytes_stream();
    let mut body_failure = None;
    let mut body_complete = false;
    let mut payload_received = headers_received;
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(15);
    loop {
        let chunk = match tokio::time::timeout_at(deadline, stream.next()).await {
            Ok(Some(Ok(chunk))) => chunk,
            Ok(Some(Err(error))) => {
                body_failure = Some(reqwest_body_error_to_pure(error));
                break;
            }
            Ok(None) => {
                body_complete = true;
                break;
            }
            Err(error) => {
                body_failure = Some(
                    transport_failure(stage, "error response body read deadline exceeded")
                        .with_source(error)
                        .into(),
                );
                break;
            }
        };
        payload_received = ErrorObservedAt::now();
        let remaining = 16_384_usize.saturating_sub(body.len());
        body.extend_from_slice(&chunk[..chunk.len().min(remaining)]);
        if body.len() == 16_384 {
            break;
        }
    }
    let redact = |input: &str| match diagnostics {
        Some(diagnostics) => diagnostics.redact_text(input),
        None => redact_secret_like_values(input),
    };
    let context = ProviderErrorContext {
        stage,
        request_id: request_id(&headers),
        http_status: Some(status),
        observed_at: payload_received,
        header_retry: ObservedRetry::from_headers(&headers, headers_received),
        redact: &redact,
    };
    let mut failure = response_failure(binding, &body, &context);
    // Failed HTTP status and headers are still useful when reading the error body failed.
    if let Some(body_failure) = body_failure {
        failure
            .message
            .push_str(&format!("; {}", redact(&body_failure.to_string())));
        failure = failure.with_source(body_failure);
    }
    HttpResponseFailure {
        failure,
        body_complete,
    }
}

/// Classifies a buffered failed HTTP response or a successful non-streaming response
/// at a streaming endpoint. `context.http_status` is the actual HTTP status.
pub fn response_failure(
    binding: Option<ErrorPolicyBinding<'_>>,
    body: &[u8],
    context: &ProviderErrorContext<'_>,
) -> ProviderFailure {
    let payload = binding.and_then(|_| serde_json::from_slice::<serde_json::Value>(body).ok());
    if let Some(binding) = binding
        && let Some(failure) = decode_provider_failure(
            binding.policy,
            binding.input(
                ProviderErrorEntry::HttpResponse,
                context.http_status,
                payload.as_ref(),
            ),
            context,
        )
    {
        return failure;
    }
    let classified = match context.http_status {
        Some(status @ 200..=299) => ClassifiedProviderError::new(
            Kind::Protocol,
            false,
            format!(
                "provider returned a non-SSE response (HTTP {status}); expected text/event-stream"
            ),
        ),
        status => ClassifiedProviderError::from_http_status(status),
    };
    classified.into_failure(context)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SseContentTypePolicy {
    Required,
    AllowMissingForChatGpt,
}

#[derive(Clone)]
pub struct RawSseFrame {
    pub data: String,
    pub event_name: Option<String>,
    pub request_id: Option<String>,
    pub diagnostics: Arc<RequestDiagnostics>,
    pub observed_at: ErrorObservedAt,
    pub header_retry: ObservedRetry,
}

impl RawSseFrame {
    pub fn decode(
        &self,
        decoder: &mut dyn crate::wire_codec::WireStreamDecoder,
        binding: ErrorPolicyBinding<'_>,
    ) -> Result<crate::wire_codec::DecodedSseFrame> {
        let redact = |text: &str| self.diagnostics.redact_text(text);
        decoder.decode_frame(
            &self.data,
            &super::provider_error::StreamFrameContext {
                policy: binding.policy,
                entry: ProviderErrorEntry::Sse,
                event_name: self.event_name.as_deref(),
                wire_api: binding.wire_api,
                endpoint: binding.endpoint,
                failure: ProviderErrorContext {
                    stage: ProviderFailureStage::Stream,
                    request_id: self.request_id.as_deref(),
                    http_status: None,
                    observed_at: self.observed_at,
                    header_retry: self.header_retry,
                    redact: &redact,
                },
            },
        )
    }
}

pub async fn sse_frames(
    request: reqwest::RequestBuilder,
    content_type_policy: SseContentTypePolicy,
    binding: Option<ErrorPolicyBinding<'_>>,
) -> Result<BoxStream<'static, Result<RawSseFrame>>> {
    // Inspect the built request once using reqwest's sensitive-header flags. This context
    // belongs only to this send/stream and is never logged, cached globally or Debug-derived.
    let (client, request) = request.build_split();
    let request = request.map_err(reqwest_error_to_pure)?;
    let diagnostics = Arc::new(RequestDiagnostics::from_headers(request.headers()));
    let response = tokio::time::timeout(HTTP_REQUEST_TIMEOUT, client.execute(request))
        .await
        .map_err(|error| {
            transport_failure(
                ProviderFailureStage::Request,
                "HTTP request header deadline exceeded",
            )
            .with_source(error)
        })?
        .map_err(reqwest_error_to_pure)?;
    let headers_received = ErrorObservedAt::now();
    if !response.status().is_success() {
        return Err(read_response_error(
            response,
            binding,
            ProviderFailureStage::Request,
            Some(&diagnostics),
            headers_received,
        )
        .await
        .failure
        .into());
    }
    let is_sse = match response.headers().get(CONTENT_TYPE) {
        Some(value) => value
            .to_str()
            .ok()
            .and_then(|value| value.split(';').next())
            .is_some_and(|value| value.trim().eq_ignore_ascii_case("text/event-stream")),
        None => content_type_policy == SseContentTypePolicy::AllowMissingForChatGpt,
    };
    if !is_sse {
        return Err(read_response_error(
            response,
            binding,
            ProviderFailureStage::Request,
            Some(&diagnostics),
            headers_received,
        )
        .await
        .failure
        .into());
    }
    let version = response.version();
    let status = response.status().as_u16();
    let request_id = request_id(response.headers()).map(|id| diagnostics.redact_text(id));
    let header_retry = ObservedRetry::from_headers(response.headers(), headers_received);
    let started = std::time::Instant::now();
    let mut received_bytes = 0_u64;
    let transport_diagnostics = diagnostics.clone();
    let body_request_id = request_id.clone();
    // The framer can retain a chunk across polls when it contains multiple events.
    // All those frames inherit the time that chunk was read from the HTTP body.
    let chunk_received = Arc::new(Mutex::new(headers_received));
    let record_chunk_time = chunk_received.clone();
    let body = response.bytes_stream().map(move |chunk| match chunk {
        Ok(chunk) => {
            *record_chunk_time.lock().expect("SSE receive clock") = ErrorObservedAt::now();
            received_bytes = received_bytes.saturating_add(chunk.len() as u64);
            Ok(chunk)
        }
        Err(error) => {
            let mut error = reqwest_body_error_to_pure(error);
            if let PureError::Provider(failure) = &mut error {
                failure.context.stage = pl_protocol::ProviderFailureStage::Stream;
                failure.context.request_id = body_request_id.clone();
                failure.http_status = Some(status);
                failure.message.push_str(&format!(
                    "; version={version:?}; received_bytes={received_bytes}; read_elapsed_ms={}; request_id={}",
                    started.elapsed().as_millis(),
                    body_request_id.as_deref().unwrap_or("unknown"),
                ));
            }
            transport_diagnostics.redact_error(&mut error);
            Err(error)
        }
    });
    let stream = sse_stream::SseByteStream::new(sse_limit::bounded(body, request_id.clone()));
    Ok(stream
        .take_while(|event| {
            futures::future::ready(!event.as_ref().is_ok_and(|event| {
                !is_failure_event(event.event.as_deref())
                    && event
                        .data
                        .as_deref()
                        .is_some_and(|data| data.trim() == "[DONE]")
            }))
        })
        .filter_map(move |event| {
            let diagnostics = diagnostics.clone();
            let request_id = request_id.clone();
            let observed_at = *chunk_received.lock().expect("SSE receive clock");
            async move {
                match event {
                    Ok(event)
                        if is_failure_event(event.event.as_deref())
                            && event
                                .data
                                .as_deref()
                                .is_none_or(|data| data.trim().is_empty()) =>
                    {
                        Some(Err(sse_protocol_error(
                            "SSE failure event is missing data",
                            request_id,
                        )))
                    }
                    Ok(event)
                        if event
                            .data
                            .as_deref()
                            .is_none_or(|data| data.trim().is_empty()) =>
                    {
                        None
                    }
                    Ok(event) => Some(Ok(RawSseFrame {
                        data: event.data.expect("data checked above"),
                        event_name: event.event,
                        request_id,
                        diagnostics,
                        observed_at,
                        header_retry,
                    })),
                    Err(sse_stream::Error::Body(error)) => Some(Err(error
                        .downcast::<PureError>()
                        .map(|error| *error)
                        .unwrap_or_else(|_| sse_protocol_error("invalid SSE body", request_id)))),
                    Err(error) => {
                        Some(Err(sse_protocol_failure("invalid SSE framing", request_id)
                            .with_source(error)
                            .into()))
                    }
                }
            }
        })
        .boxed())
}

fn is_failure_event(name: Option<&str>) -> bool {
    matches!(
        name,
        Some("error" | "response.failed" | "response.incomplete")
    )
}

fn sse_protocol_error(message: &str, request_id: Option<String>) -> PureError {
    sse_protocol_failure(message, request_id).into()
}

fn sse_protocol_failure(message: &str, request_id: Option<String>) -> ProviderFailure {
    let mut failure =
        super::provider_error::protocol_failure(ProviderFailureStage::Stream, message);
    failure.context.request_id = request_id;
    failure.code = Some("invalid_response".to_owned());
    failure
}
