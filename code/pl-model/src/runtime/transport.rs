//! Network execution only. The invocation owner decides whether an operation can be retried.
mod diagnostics;
mod sse_limit;
use diagnostics::RequestDiagnostics;

use futures::{StreamExt, stream::BoxStream};
use pl_protocol::{PureError, Result};
use reqwest::header::{AUTHORIZATION, CONTENT_TYPE, HeaderMap, HeaderName, HeaderValue};
use serde::Deserialize;
use std::collections::HashMap;

use super::openai::sse::SseStreamEvent;
pub(crate) use super::provider_error::reqwest_error_to_pure;
use super::provider_error::{provider_stream_failure, reqwest_body_error_to_pure};

pub(crate) fn headers(
    token: Option<&str>,
    provider: Option<&HashMap<String, String>>,
    model: &HashMap<String, String>,
) -> Result<HeaderMap> {
    let mut headers = HeaderMap::new();
    if let Some(token) = token {
        let mut value = HeaderValue::from_str(&format!("Bearer {token}"))
            .map_err(|_| PureError::ConfigError("invalid authorization header".into()))?;
        value.set_sensitive(true);
        headers.insert(AUTHORIZATION, value);
    }
    for layer in provider.into_iter().chain(std::iter::once(model)) {
        let mut names = std::collections::HashSet::new();
        for (key, value) in layer {
            let name = HeaderName::from_bytes(key.as_bytes())
                .map_err(|_| PureError::ConfigError("invalid provider header name".into()))?;
            if !names.insert(name.clone()) {
                return Err(PureError::ConfigError(
                    "duplicate provider header name".into(),
                ));
            }
            let mut value = HeaderValue::from_str(value)
                .map_err(|_| PureError::ConfigError("invalid provider header value".into()))?;
            value.set_sensitive(true);
            headers.insert(name, value);
        }
    }
    Ok(headers)
}

#[derive(Deserialize)]
#[serde(untagged)]
enum ErrorEnvelope {
    OpenAi {
        error: ErrorDetail,
    },
    Business {
        code: i64,
        msg: String,
        success: bool,
    },
    Detail {
        detail: String,
    },
}

#[derive(Deserialize)]
struct ErrorDetail {
    code: Option<String>,
    message: Option<String>,
}

pub(crate) async fn checked(response: reqwest::Response) -> Result<reqwest::Response> {
    if response.status().is_success() {
        return Ok(response);
    }
    Err(read_response_error(response, None).await)
}

async fn read_response_error(
    response: reqwest::Response,
    diagnostics: Option<&RequestDiagnostics>,
) -> PureError {
    let status = response.status().as_u16();
    let headers = response.headers().clone();
    let mut body = Vec::new();
    let mut stream = response.bytes_stream();
    let mut body_failure = None;
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(15);
    loop {
        let chunk = match tokio::time::timeout_at(deadline, stream.next()).await {
            Ok(Some(chunk)) => chunk,
            Ok(None) => break,
            Err(_) => {
                body_failure = Some(PureError::transient_model_transport(
                    "error response body read deadline exceeded",
                ));
                break;
            }
        };
        let chunk = match chunk {
            Ok(chunk) => chunk,
            Err(error) => {
                body_failure = Some(reqwest_body_error_to_pure(error));
                break;
            }
        };
        let remaining = 16_384_usize.saturating_sub(body.len());
        body.extend_from_slice(&chunk[..chunk.len().min(remaining)]);
        if body.len() == 16_384 {
            break;
        }
    }
    let mut error = response_error_with_diagnostics(
        status,
        &headers,
        &body,
        pl_protocol::ProviderFailureStage::Request,
        diagnostics,
    );
    // The status and retry headers already describe the failed request. A
    // damaged error body must not turn authentication failures into retries.
    if let (Some(body_failure), PureError::Provider(failure)) = (body_failure, &mut error) {
        failure.message.push_str(&format!("; {body_failure}"));
    }
    error
}

pub(crate) fn response_error(
    status: u16,
    headers: &HeaderMap,
    body: &[u8],
    stage: pl_protocol::ProviderFailureStage,
) -> PureError {
    response_error_with_diagnostics(status, headers, body, stage, None)
}

fn response_error_with_diagnostics(
    status: u16,
    headers: &HeaderMap,
    body: &[u8],
    stage: pl_protocol::ProviderFailureStage,
    diagnostics: Option<&RequestDiagnostics>,
) -> PureError {
    let request_id = response_request_id(headers);
    let retry_after = headers
        .get("retry-after-ms")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<u64>().ok())
        .or_else(|| {
            headers
                .get("retry-after")
                .and_then(|value| value.to_str().ok())
                .and_then(|value| value.parse::<u64>().ok())
                .map(|seconds| seconds.saturating_mul(1000))
        });
    let parsed = serde_json::from_slice::<ErrorEnvelope>(body).ok();
    let business_authentication_failure = matches!(
        parsed,
        Some(ErrorEnvelope::Business {
            code: 1000,
            success: false,
            ..
        })
    );
    let detail = match parsed {
        Some(ErrorEnvelope::OpenAi { error }) => Some(error),
        Some(ErrorEnvelope::Business {
            code,
            msg,
            success: false,
        }) => Some(ErrorDetail {
            code: Some(code.to_string()),
            message: Some(msg),
        }),
        Some(ErrorEnvelope::Business { success: true, .. }) | None => None,
        Some(ErrorEnvelope::Detail { detail }) => Some(ErrorDetail {
            code: None,
            message: Some(if diagnostics.is_some() {
                detail
            } else {
                "provider returned a detail error response".into()
            }),
        }),
    };
    if (200..300).contains(&status) && detail.is_none() {
        return PureError::Protocol(format!(
            "provider returned a non-SSE response (HTTP {status}); expected text/event-stream"
        ));
    }
    let code = detail.as_ref().and_then(|detail| detail.code.as_deref());
    let message = detail
        .as_ref()
        .and_then(|detail| detail.message.as_deref())
        .unwrap_or("provider returned an unstructured error response");
    let message = if diagnostics.is_none() && detail.is_some() {
        "provider returned an error response"
    } else {
        message
    };
    let mut error = provider_stream_failure(
        code,
        Some(status),
        retry_after,
        format!(
            "HTTP {status}, request_id={}: {message}",
            request_id.as_deref().unwrap_or("unknown")
        ),
    );
    if let PureError::Provider(failure) = &mut error {
        // This business envelope reports authentication failure with HTTP 200.
        // Keep its actual status/code while preventing transport retries.
        if business_authentication_failure {
            failure.kind = pl_protocol::ProviderFailureKind::Authentication;
            failure.retry = pl_protocol::RetryDisposition::Permanent;
        }
        failure.context.request_id = request_id;
        if matches!(status, 400 | 404) && matches!(code, Some("file_not_found" | "file_expired")) {
            failure.context.recovery = pl_protocol::ProviderRecovery::RefreshAttachments;
        }
    }
    if let PureError::Provider(failure) = &mut error {
        failure.context.stage = stage;
    }
    if let Some(diagnostics) = diagnostics {
        diagnostics.redact_error(&mut error);
    }
    error
}

fn response_request_id(headers: &HeaderMap) -> Option<String> {
    let value = headers.get("x-request-id")?.to_str().ok()?;
    if value.is_empty()
        || value.len() > 128
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"-_.:".contains(&byte))
    {
        return None;
    }
    Some(super::provider_error::redact_secret_like_values(value))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum SseContentTypePolicy {
    Required,
    AllowMissingForChatGpt,
}

pub(crate) async fn sse(
    request: reqwest::RequestBuilder,
    content_type_policy: SseContentTypePolicy,
) -> Result<BoxStream<'static, Result<SseStreamEvent>>> {
    // Inspect the built request once using reqwest's sensitive-header flags. This context
    // belongs only to this send/stream and is never logged, cached globally or Debug-derived.
    let (client, request) = request.build_split();
    let request = request.map_err(reqwest_error_to_pure)?;
    let diagnostics = std::sync::Arc::new(RequestDiagnostics::from_headers(request.headers()));
    let response = tokio::time::timeout(
        super::transport_policy::HTTP_REQUEST_TIMEOUT,
        client.execute(request),
    )
    .await
    .map_err(|_| PureError::transient_model_transport("HTTP request header deadline exceeded"))?
    .map_err(reqwest_error_to_pure)?;
    if !response.status().is_success() {
        return Err(read_response_error(response, Some(&diagnostics)).await);
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
        return Err(read_response_error(response, Some(&diagnostics)).await);
    }
    let version = response.version();
    let status = response.status().as_u16();
    let request_id = response_request_id(response.headers());
    let started = std::time::Instant::now();
    let mut received_bytes = 0_u64;
    let transport_diagnostics = diagnostics.clone();
    let body_request_id = request_id.clone();
    let body = response.bytes_stream().map(move |chunk| match chunk {
        Ok(chunk) => {
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
    let stream = sse_stream::SseByteStream::new(sse_limit::bounded(body));
    Ok(stream
        .take_while(|event| {
            futures::future::ready(!event.as_ref().is_ok_and(|event| {
                event
                    .data
                    .as_deref()
                    .is_some_and(|data| data.trim() == "[DONE]")
            }))
        })
        .filter_map(move |event| {
            let diagnostics = diagnostics.clone();
            let request_id = request_id.clone();
            async move {
                match event {
                    Ok(event)
                        if event
                            .data
                            .as_deref()
                            .is_none_or(|data| data.trim().is_empty()) =>
                    {
                        None
                    }
                    Ok(event) => Some(
                        serde_json::from_str::<SseStreamEvent>(
                            event.data.as_deref().expect("data checked above"),
                        )
                        .map(|mut event| {
                            event.request_id = request_id;
                            diagnostics.redact_event(&mut event);
                            event
                        })
                        .map_err(|_| PureError::Protocol("invalid SSE JSON".into())),
                    ),
                    Err(sse_stream::Error::Body(error)) => Some(Err(error
                        .downcast::<PureError>()
                        .map(|error| *error)
                        .unwrap_or_else(|_| PureError::Protocol("invalid SSE body".into())))),
                    Err(_) => Some(Err(PureError::Protocol("invalid SSE framing".into()))),
                }
            }
        })
        .boxed())
}

#[cfg(test)]
mod chatgpt_tests {
    use super::*;
    use pl_protocol::{ProviderFailureKind as Kind, RetryDisposition};
    use serde_json::json;

    const SYNTHETIC_BEARER: &str = "oauth.synthetic.opaque-credential";

    fn diagnostics() -> RequestDiagnostics {
        RequestDiagnostics::from_headers(
            &headers(
                Some("oauth.synthetic.opaque-credential"),
                None,
                &HashMap::new(),
            )
            .unwrap(),
        )
    }

    fn classified(status: u16, body: serde_json::Value) -> pl_protocol::ProviderFailure {
        let mut headers = HeaderMap::new();
        headers.insert("x-request-id", HeaderValue::from_static("req-synthetic"));
        headers.insert("retry-after-ms", HeaderValue::from_static("123"));
        let PureError::Provider(failure) = response_error_with_diagnostics(
            status,
            &headers,
            &serde_json::to_vec(&body).unwrap(),
            pl_protocol::ProviderFailureStage::Request,
            Some(&diagnostics()),
        ) else {
            panic!("expected a provider failure")
        };
        failure
    }

    #[test]
    fn siwc_detail_classification_uses_metadata_not_diagnostic_words() {
        for (status, kind, retryable) in [
            (400, Kind::Configuration, false),
            (401, Kind::Authentication, false),
            (403, Kind::Authorization, false),
            (429, Kind::Capacity, true),
            (503, Kind::Capacity, true),
        ] {
            let failure = classified(
                status,
                json!({"detail":"invalid field; server_error rate_limit_exceeded"}),
            );
            assert_eq!(failure.http_status, Some(status));
            assert_eq!(failure.code, None);
            assert_eq!(failure.kind, kind);
            assert_eq!(failure.context.request_id.as_deref(), Some("req-synthetic"));
            assert_eq!(
                failure.context.stage,
                pl_protocol::ProviderFailureStage::Request
            );
            if retryable {
                assert_eq!(
                    failure.retry,
                    RetryDisposition::Retryable {
                        retry_after_ms: Some(123)
                    }
                );
            } else {
                assert_eq!(failure.retry, RetryDisposition::Permanent);
            }
            assert!(failure.message.contains("invalid field"));
        }
    }

    #[test]
    fn siwc_detail_is_string_only_and_does_not_override_existing_envelopes() {
        for detail in [
            json!({"raw":"do-not-echo"}),
            json!(["do-not-echo"]),
            json!(null),
        ] {
            let failure = classified(400, json!({"detail":detail,"opaque":"do-not-echo"}));
            assert!(failure.message.contains("unstructured"));
            assert!(!failure.message.contains("do-not-echo"));
            assert!(matches!(
                response_error_with_diagnostics(
                    200,
                    &HeaderMap::new(),
                    &serde_json::to_vec(&json!({"detail":detail})).unwrap(),
                    pl_protocol::ProviderFailureStage::Request,
                    Some(&diagnostics()),
                ),
                PureError::Protocol(_)
            ));
        }
        let failure = classified(
            400,
            json!({"detail":"secondary","error":{"code":"invalid_request_error","message":"primary"}}),
        );
        assert_eq!(failure.code.as_deref(), Some("invalid_request_error"));
        assert!(failure.message.contains("primary"));
        assert!(!failure.message.contains("secondary"));
        let failure = classified(
            200,
            json!({"detail":"secondary","code":1000,"success":false,"msg":"primary"}),
        );
        assert_eq!(failure.kind, Kind::Authentication);
        assert_eq!(failure.retry, RetryDisposition::Permanent);
        assert_eq!(failure.code.as_deref(), Some("1000"));
    }

    #[test]
    fn siwc_diagnostics_remove_exact_non_sk_credentials_from_all_published_error_fields() {
        for envelope in [
            json!({"detail":"reflected oauth.synthetic.opaque-credential"}),
            json!({"error":{"code":"oauth.synthetic.opaque-credential","message":"Bearer oauth.synthetic.opaque-credential"}}),
        ] {
            let failure = classified(400, envelope);
            assert!(!format!("{failure:?}").contains("oauth.synthetic.opaque-credential"));
            assert!(failure.message.contains("[REDACTED_CREDENTIAL]"));
        }
        let failure = response_error(
            400,
            &HeaderMap::new(),
            br#"{"detail":"do-not-echo-without-request-context"}"#,
            pl_protocol::ProviderFailureStage::Handshake,
        );
        assert!(!failure.to_string().contains("do-not-echo"));
        let failure = classified(400, json!({"detail":"safe"}));
        assert_eq!(failure.context.request_id.as_deref(), Some("req-synthetic"));
        let mut event: SseStreamEvent = serde_json::from_value(json!({
            "type":"error","code":"oauth.synthetic.opaque-credential",
            "message":"reflected oauth.synthetic.opaque-credential",
            "error":{"message":"oauth.synthetic.opaque-credential"}
        }))
        .unwrap();
        diagnostics().redact_event(&mut event);
        assert!(!format!("{event:?}").contains("oauth.synthetic.opaque-credential"));
        let mut headers = HeaderMap::new();
        headers.insert(
            "x-request-id",
            HeaderValue::from_static("oauth.synthetic.opaque-credential"),
        );
        let failure = response_error_with_diagnostics(
            400,
            &headers,
            br#"{"detail":"safe"}"#,
            pl_protocol::ProviderFailureStage::Request,
            Some(&diagnostics()),
        );
        assert!(!format!("{failure:?}").contains("oauth.synthetic.opaque-credential"));
    }

    async fn loopback_response(
        status: u16,
        content_type: Option<&'static str>,
        body: String,
    ) -> (String, tokio::task::JoinHandle<tokio::net::TcpListener>) {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut request = Vec::new();
            loop {
                let mut chunk = [0; 1024];
                let count = socket.read(&mut chunk).await.unwrap();
                assert!(count > 0, "fixture request ended before its body");
                request.extend_from_slice(&chunk[..count]);
                if let Some(header_end) = request.windows(4).position(|bytes| bytes == b"\r\n\r\n")
                {
                    let headers = std::str::from_utf8(&request[..header_end]).unwrap();
                    let length: usize = headers
                        .lines()
                        .find_map(|line| {
                            let (name, value) = line.split_once(':')?;
                            name.eq_ignore_ascii_case("content-length")
                                .then(|| value.trim().parse().unwrap())
                        })
                        .unwrap();
                    if request.len() >= header_end + 4 + length {
                        break;
                    }
                }
            }
            assert!(
                std::str::from_utf8(&request)
                    .unwrap()
                    .contains(SYNTHETIC_BEARER)
            );
            let content_type = content_type
                .map(|value| format!("Content-Type: {value}\r\n"))
                .unwrap_or_default();
            socket.write_all(format!("HTTP/1.1 {status} Fixture\r\n{content_type}Content-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).as_bytes()).await.unwrap();
            // The transport does not retry; the caller remains the sole retry owner.
            listener
        });
        (format!("http://{address}"), server)
    }

    #[tokio::test]
    async fn siwc_http_detail_uses_the_actual_sensitive_request_headers_without_retry() {
        let (url, server) = loopback_response(
        400, Some("application/json"),
        r#"{"detail":"unsupported tool; reflected oauth.synthetic.opaque-credential","opaque":"do-not-echo"}"#.into(),
    ).await;
        let request = reqwest::Client::new()
            .post(url)
            .headers(
                headers(
                    Some("oauth.synthetic.opaque-credential"),
                    None,
                    &HashMap::new(),
                )
                .unwrap(),
            )
            .json(&json!({"input":[]}));
        let error = match sse(request, SseContentTypePolicy::Required).await {
            Err(error) => error,
            Ok(_) => panic!("expected 400"),
        };
        let PureError::Provider(failure) = error else {
            panic!("expected provider failure")
        };
        assert_eq!(failure.http_status, Some(400));
        assert_eq!(failure.retry, RetryDisposition::Permanent);
        assert_eq!(failure.context.request_id, None);
        assert!(failure.message.contains("unsupported tool"));
        assert!(!failure.message.contains("oauth.synthetic"));
        assert!(!failure.message.contains("opaque"));
        let listener = server.await.unwrap();
        assert!(
            tokio::time::timeout(std::time::Duration::from_millis(20), listener.accept())
                .await
                .is_err()
        );
    }

    async fn model_sse(
        events: Vec<serde_json::Value>,
    ) -> std::result::Result<
        crate::completion::CompletionResponse,
        crate::completion::CompletionFailure,
    > {
        use crate::{
            completion::{CompletionRequest, Message, MessageContent, MessageRole},
            model::{ModelInfo, ModelTransportProfile},
            protocol::ProtocolEndpoint,
            runtime::{ModelInvocationContext, ModelRuntime},
        };
        let body = events
            .into_iter()
            .map(|event| format!("data: {event}\n\n"))
            .collect::<String>()
            + "data: [DONE]\n\n";
        let (url, server) = loopback_response(200, Some("text/event-stream"), body).await;
        let mut endpoint = ProtocolEndpoint::compatible("terminal diagnostic fixture", url);
        endpoint.bearer_token = Some(SYNTHETIC_BEARER.into());
        let mut model = ModelInfo::compatible("synthetic-model");
        model
            .binding
            .set_transport(ModelTransportProfile::responses_http());
        let runtime =
            ModelRuntime::new_with_account_id("terminal-fixture", endpoint, model).unwrap();
        let request = CompletionRequest::builder()
            .messages(vec![Message {
                role: MessageRole::User,
                content: MessageContent::text("synthetic request"),
                presentation: Default::default(),
                reasoning_content: None,
                tool_calls: None,
                tool_result: None,
                metadata: Default::default(),
            }])
            .build();
        let result = tokio::time::timeout(
            std::time::Duration::from_secs(5),
            runtime.complete(request, ModelInvocationContext::default()),
        )
        .await
        .unwrap();
        let listener = server.await.unwrap();
        assert!(
            tokio::time::timeout(std::time::Duration::from_millis(20), listener.accept(),)
                .await
                .is_err(),
            "terminal fixture unexpectedly received another request"
        );
        result
    }

    // The official ChatGPT resource cannot be replaced with a loopback URL. Exercise the exact
    // production transport -> Responses decoder -> terminal collector without a resource bypass
    // or a test-only runner injection seam.
    async fn transport_completion(
        status: u16,
        content_type: Option<&'static str>,
        body: String,
        policy: SseContentTypePolicy,
    ) -> std::result::Result<
        crate::completion::CompletionResponse,
        crate::completion::CompletionFailure,
    > {
        use crate::completion::stream::{
            StreamCollectContext, collect_completion_event_stream_with_idle_timeout,
        };
        let (url, server) = loopback_response(status, content_type, body).await;
        let request = reqwest::Client::new()
            .post(url)
            .headers(headers(Some(SYNTHETIC_BEARER), None, &HashMap::new()).unwrap())
            .json(&json!({"input":[],"store":false,"stream":true}));
        let (events, _receiver) = tokio::sync::broadcast::channel(16);
        let result = tokio::time::timeout(std::time::Duration::from_secs(5), async {
            let raw = sse(request, policy).await.map_err(|source| {
                crate::completion::CompletionFailure::new(source, Box::default())
            })?;
            let decoded = crate::runtime::openai::OpenAiBase.decode_stream(
                crate::protocol::WireApi::Responses,
                raw,
                None,
            );
            collect_completion_event_stream_with_idle_timeout(
                decoded,
                StreamCollectContext {
                    event_tx: &events,
                    trace: None,
                    trace_sink: None,
                    cancellation: None,
                    model_observation: None,
                    on_stream_end: &|| {},
                    members: None,
                    generation: 0,
                },
                None,
            )
            .await
        })
        .await
        .unwrap();
        let listener = server.await.unwrap();
        assert!(
            tokio::time::timeout(std::time::Duration::from_millis(20), listener.accept(),)
                .await
                .is_err(),
            "media policy must not introduce a retry"
        );
        result
    }

    fn completed_sse() -> String {
        format!(
            "data: {}\n\n",
            json!({
                "type":"response.completed","response":{
                    "id":"media-response","model":"synthetic-model","output":[{
                        "type":"message","id":"media-message","role":"assistant",
                        "content":[{"type":"output_text","text":"OK"}]
                    }]
                }
            })
        )
    }

    #[tokio::test]
    async fn siwc_content_type_policy_is_narrow_and_preserves_present_header_semantics() {
        for policy in [
            SseContentTypePolicy::Required,
            SseContentTypePolicy::AllowMissingForChatGpt,
        ] {
            for (content_type, valid_present) in [
                (None, false),
                (Some("text/event-stream"), true),
                (Some("TEXT/Event-Stream; charset=utf-8"), true),
                (Some("application/json"), false),
                (Some("text/html"), false),
                (Some(""), false),
                // Legal HTTP obs-text, but not a valid to_str() media type. It is PRESENT.
                (Some("\u{0080}"), false),
            ] {
                let result = transport_completion(200, content_type, completed_sse(), policy).await;
                let allowed = valid_present
                    || (content_type.is_none()
                        && policy == SseContentTypePolicy::AllowMissingForChatGpt);
                if allowed {
                    assert_eq!(result.unwrap().content.as_deref(), Some("OK"));
                } else {
                    let failure = result.unwrap_err();
                    assert!(
                        matches!(failure.source.as_ref(), PureError::Protocol(_)),
                        "{policy:?}, {content_type:?}: {failure}"
                    );
                }
            }
        }
    }

    #[tokio::test]
    async fn siwc_missing_content_type_still_requires_a_complete_sse_terminal() {
        for body in [
            r#"{"output_text":"not an SSE response"}"#.to_owned(),
            String::new(),
            "data: [DONE]\n\n".into(),
            format!(
                "data: {}\n\n",
                json!({"type":"response.created","response":{"id":"unfinished"}})
            ),
        ] {
            assert!(
                transport_completion(
                    200,
                    None,
                    body,
                    SseContentTypePolicy::AllowMissingForChatGpt,
                )
                .await
                .is_err()
            );
        }
        for event in [
            json!({"type":"response.failed","response":{
            "status":400,"code":SYNTHETIC_BEARER,"message":format!("failed {SYNTHETIC_BEARER}")}}),
            json!({"type":"response.incomplete","response":{
            "status":400,"incomplete_details":{"reason":SYNTHETIC_BEARER}}}),
        ] {
            let failure = transport_completion(
                200,
                None,
                format!("data: {event}\n\n"),
                SseContentTypePolicy::AllowMissingForChatGpt,
            )
            .await
            .unwrap_err();
            assert!(!format!("{failure:?}").contains(SYNTHETIC_BEARER));
            let PureError::Provider(provider) = failure.source.as_ref() else {
                panic!("expected the existing classified terminal failure");
            };
            assert_eq!(provider.code.as_deref(), Some("[REDACTED_CREDENTIAL]"));
            assert_eq!(provider.http_status, Some(400));
            assert_eq!(
                provider.context.stage,
                pl_protocol::ProviderFailureStage::Stream
            );
            assert_eq!(provider.retry, RetryDisposition::Permanent);
        }
    }

    #[tokio::test]
    async fn siwc_missing_content_type_never_admits_non_success_http_status() {
        for policy in [
            SseContentTypePolicy::Required,
            SseContentTypePolicy::AllowMissingForChatGpt,
        ] {
            let failure = transport_completion(
                400,
                None,
                json!({"detail":format!("rejected {SYNTHETIC_BEARER}")}).to_string(),
                policy,
            )
            .await
            .unwrap_err();
            assert!(!format!("{failure:?}").contains(SYNTHETIC_BEARER));
            let PureError::Provider(provider) = failure.source.as_ref() else {
                panic!("expected the existing HTTP error path");
            };
            assert_eq!(provider.http_status, Some(400));
            assert_eq!(
                provider.context.stage,
                pl_protocol::ProviderFailureStage::Request
            );
            assert_eq!(provider.retry, RetryDisposition::Permanent);
        }
    }

    #[tokio::test]
    async fn siwc_model_sse_terminal_diagnostics_redact_fallbacks_and_preserve_classification() {
        for (event, expected_code, expected_message) in [
            (
                json!({"type":"response.failed","response":{
                "status":400,"error":{"code":"invalid_request_error",
                    "message":format!("nested {SYNTHETIC_BEARER}")}}}),
                "invalid_request_error",
                "nested [REDACTED_CREDENTIAL]",
            ),
            (
                json!({"type":"response.failed","response":{
                "status":400,"code":SYNTHETIC_BEARER,
                "message":format!("fallback {SYNTHETIC_BEARER}")}}),
                "[REDACTED_CREDENTIAL]",
                "fallback [REDACTED_CREDENTIAL]",
            ),
            (
                json!({"type":"response.incomplete","response":{
                "status":400,"incomplete_details":{"reason":SYNTHETIC_BEARER}}}),
                "[REDACTED_CREDENTIAL]",
                "response incomplete",
            ),
            (
                json!({"type":"response.failed","response":{
                "status":400,"code":"invalid_request_error","message":"unchanged diagnostic"}}),
                "invalid_request_error",
                "unchanged diagnostic",
            ),
            (
                json!({"type":"response.incomplete","response":{
                "status":400,"incomplete_details":{"reason":"max_output_tokens"}}}),
                "max_output_tokens",
                "response incomplete",
            ),
        ] {
            let failure = model_sse(vec![event]).await.unwrap_err();
            // CompletionFailure's published message is its Display implementation. Check the
            // entire failure too: provider metadata/partial receipts must not retain the secret.
            assert!(!failure.to_string().contains(SYNTHETIC_BEARER));
            assert!(!format!("{failure:?}").contains(SYNTHETIC_BEARER));
            assert!(failure.to_string().contains(expected_message));
            let PureError::Provider(provider) = failure.source.as_ref() else {
                panic!("expected a classified provider failure");
            };
            assert_eq!(provider.code.as_deref(), Some(expected_code));
            assert_eq!(provider.message, expected_message);
            assert_eq!(provider.http_status, Some(400));
            assert_eq!(provider.kind, Kind::Configuration);
            assert_eq!(
                provider.context.stage,
                pl_protocol::ProviderFailureStage::Stream
            );
            assert_eq!(provider.retry, RetryDisposition::Permanent);
        }
    }

    #[tokio::test]
    async fn siwc_model_sse_preserves_normal_output_and_opaque_reasoning() {
        let text = format!("normal output {SYNTHETIC_BEARER}");
        let message = json!({"type":"message","id":"message-id","role":"assistant",
        "content":[{"type":"output_text","text":text}]});
        let reasoning = json!({"type":"reasoning","id":"reasoning-id",
        "encrypted_content":SYNTHETIC_BEARER,"summary":[],"status":"completed",
        "opaque":{"code":SYNTHETIC_BEARER,"message":SYNTHETIC_BEARER}});
        let response = model_sse(vec![
            json!({"type":"response.output_item.added","item":{
            "type":"message","id":"message-id","role":"assistant","content":[]}}),
            json!({"type":"response.output_text.delta","item_id":"message-id",
            "content_index":0,"delta":text}),
            json!({"type":"response.output_item.done","item":message}),
            json!({"type":"response.output_item.done","item":reasoning}),
            json!({"type":"response.completed","response":{
            "id":"response-id","model":"synthetic-model","output":[message,reasoning]}}),
        ])
        .await
        .unwrap();
        assert_eq!(response.content.as_deref(), Some(text.as_str()));
        let Some(crate::completion::AssistantReplay::Responses { output }) = response.replay else {
            panic!("expected native replay material");
        };
        assert!(output.contains(&message));
        assert!(output.contains(&reasoning));
    }
}
