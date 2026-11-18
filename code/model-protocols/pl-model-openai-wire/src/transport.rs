//! Network execution only. The invocation owner decides whether an operation can be retried.
mod diagnostics;
mod sse_limit;
use diagnostics::RequestDiagnostics;

use futures::{StreamExt, stream::BoxStream};
use pl_protocol::{PureError, Result};
use reqwest::header::{CONTENT_TYPE, HeaderMap};
pub const HTTP_REQUEST_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(180);
use serde::Deserialize;

use super::openai::sse::SseStreamEvent;
pub use super::provider_error::reqwest_error_to_pure;
use super::provider_error::{provider_stream_failure, reqwest_body_error_to_pure};

pub use pl_model_types::headers;

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

pub async fn checked(response: reqwest::Response) -> Result<reqwest::Response> {
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

pub fn response_error(
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
pub enum SseContentTypePolicy {
    Required,
    AllowMissingForChatGpt,
}

pub async fn sse(
    request: reqwest::RequestBuilder,
    content_type_policy: SseContentTypePolicy,
) -> Result<BoxStream<'static, Result<SseStreamEvent>>> {
    // Inspect the built request once using reqwest's sensitive-header flags. This context
    // belongs only to this send/stream and is never logged, cached globally or Debug-derived.
    let (client, request) = request.build_split();
    let request = request.map_err(reqwest_error_to_pure)?;
    let diagnostics = std::sync::Arc::new(RequestDiagnostics::from_headers(request.headers()));
    let response = tokio::time::timeout(HTTP_REQUEST_TIMEOUT, client.execute(request))
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
mod tests {
    use super::*;
    use pl_protocol::{ProviderFailureKind as Kind, RetryDisposition};
    use reqwest::header::HeaderValue;
    use serde_json::json;
    use std::collections::HashMap;
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
}
