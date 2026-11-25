use pl_model_wire::provider_error::{
    ClassifiedProviderError, ErrorObservedAt, ErrorPolicyBinding, ObservedRetry,
    ProviderErrorContext, RetryHint, request_id, transport_failure,
};
use pl_model_wire::transport::RequestDiagnostics;
use pl_protocol::{
    ProviderFailure, ProviderFailureKind, ProviderFailureStage, ProviderRecovery, PureError,
    RetryDisposition,
};
use serde_json::Value;
use tokio_tungstenite::tungstenite::Error as TungsteniteError;
use tokio_tungstenite::tungstenite::protocol::CloseFrame;

pub(super) fn handshake_error(
    error: TungsteniteError,
    binding: ErrorPolicyBinding<'_>,
    diagnostics: &RequestDiagnostics,
) -> PureError {
    let redact = |text: &str| diagnostics.redact_text(text);
    if let TungsteniteError::Http(response) = &error {
        let status = response.status().as_u16();
        let observed_at = ErrorObservedAt::now();
        let context = ProviderErrorContext {
            stage: ProviderFailureStage::Handshake,
            request_id: request_id(response.headers()),
            http_status: Some(status),
            observed_at,
            header_retry: ObservedRetry::from_headers(response.headers(), observed_at),
            redact: &redact,
        };
        let body = response.body().as_deref().unwrap_or_default();
        let mut failure = pl_model_wire::transport::response_failure(
            Some(binding),
            &body[..body.len().min(16_384)],
            &context,
        );
        // A rejected upgrade is a transport capability fact. A recognized business error on
        // the same response still takes precedence.
        if status == 426 && failure.kind == ProviderFailureKind::Unknown {
            let mut upgrade = ClassifiedProviderError::new(
                ProviderFailureKind::Transport,
                false,
                "WebSocket upgrade required",
            );
            upgrade.recovery = ProviderRecovery::HttpFallback;
            failure = upgrade.into_failure(&context);
        }
        return failure.with_source(error).into();
    }
    let failure = if is_connection_error(&error) {
        transport_failure(
            ProviderFailureStage::Handshake,
            "Responses WebSocket handshake failed",
        )
    } else {
        protocol_failure(
            ProviderFailureStage::Handshake,
            "invalid Responses WebSocket handshake",
        )
    };
    failure.with_source(error).into()
}

pub(super) fn handshake_timeout_error(source: tokio::time::error::Elapsed) -> PureError {
    transport_failure(
        ProviderFailureStage::Handshake,
        "Responses WebSocket handshake timed out",
    )
    .with_source(source)
    .into()
}

pub(crate) fn connection_error(detail: impl AsRef<str>) -> PureError {
    transport_failure(ProviderFailureStage::Stream, detail.as_ref()).into()
}

fn is_connection_error(error: &TungsteniteError) -> bool {
    matches!(
        error,
        TungsteniteError::ConnectionClosed
            | TungsteniteError::AlreadyClosed
            | TungsteniteError::Io(_)
            | TungsteniteError::Tls(_)
            | TungsteniteError::WriteBufferFull(_)
            | TungsteniteError::Protocol(
                tokio_tungstenite::tungstenite::error::ProtocolError::ResetWithoutClosingHandshake
            )
    )
}

pub(crate) fn socket_error(error: TungsteniteError) -> PureError {
    let stage = ProviderFailureStage::Stream;
    let failure = if is_connection_error(&error) {
        transport_failure(stage, "Responses WebSocket connection failed")
    } else {
        protocol_failure(stage, "invalid Responses WebSocket frame")
    };
    failure.with_source(error).into()
}

pub(super) fn close_error(frame: Option<CloseFrame>) -> PureError {
    let Some(frame) = frame else {
        return connection_error("server closed the connection without a close frame");
    };
    let code = u16::from(frame.code);
    let detail = format!("Responses WebSocket server closed the connection ({code})");
    if matches!(code, 1002 | 1003 | 1007 | 1008 | 1009 | 1010) {
        protocol_error(detail)
    } else {
        connection_error(detail)
    }
}

pub(super) fn protocol_failure(
    stage: ProviderFailureStage,
    message: impl Into<String>,
) -> ProviderFailure {
    let mut failure = ProviderFailure::new(
        ProviderFailureKind::Protocol,
        message,
        RetryDisposition::Permanent,
    );
    failure.context.stage = stage;
    failure
}

pub(crate) fn protocol_error(detail: impl AsRef<str>) -> PureError {
    protocol_failure(ProviderFailureStage::Stream, detail.as_ref()).into()
}

pub(super) fn frame_headers(
    value: &Value,
    observed_at: ErrorObservedAt,
) -> (Option<String>, ObservedRetry) {
    use reqwest::header::{HeaderMap, HeaderName, HeaderValue, RETRY_AFTER};
    let mut headers = HeaderMap::new();
    let mut numeric_retry = RetryHint::Absent;
    if let Some(frame_headers) = value.get("headers").and_then(Value::as_object) {
        for (name, value) in frame_headers {
            let Ok(name) = HeaderName::try_from(name) else {
                continue;
            };
            let retry = matches!(
                name.as_str(),
                "retry-after" | "retry-after-ms" | "retry_after_ms"
            );
            match value {
                Value::Number(number) if retry => {
                    let hint = match RetryHint::from_number_millis(number) {
                        RetryHint::Delay(delay) if name == RETRY_AFTER => delay
                            .checked_mul(1_000)
                            .map_or(RetryHint::Unrepresentable, RetryHint::Delay),
                        hint => hint,
                    };
                    numeric_retry = numeric_retry.combine(hint);
                }
                Value::String(text)
                    if retry
                        || matches!(
                            name.as_str(),
                            "x-request-id" | "x-goog-request-id" | "request-id"
                        ) =>
                {
                    if let Ok(value) = HeaderValue::from_str(text) {
                        headers.append(name, value);
                    }
                }
                _ => {}
            }
        }
    }
    let retry = RetryHint::from_headers(&headers, observed_at.wall)
        .combine(numeric_retry)
        .observed(observed_at);
    (request_id(&headers).map(str::to_owned), retry)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::time::{Duration, Instant, SystemTime};

    #[test]
    fn mixed_retry_headers_keep_units_and_the_original_receive_time() {
        let at = ErrorObservedAt {
            wall: SystemTime::UNIX_EPOCH + Duration::from_secs(784_111_775),
            monotonic: Instant::now(),
        };
        for (headers, millis) in [
            (json!({"Retry-After": 3, "retry-after-ms": "2500"}), 3000),
            (
                json!({"retry-after": "Sun, 06 Nov 1994 08:49:37 GMT", "retry-after-ms": 1000}),
                2000,
            ),
            (json!({"retry-after": "1", "retry-after-ms": -1}), 1000),
            (json!({"retry-after": 1.25, "retry-after-ms": "0"}), 0),
        ] {
            let (_, retry) = frame_headers(&json!({"headers": headers}), at);
            assert_eq!(
                retry,
                ObservedRetry::At {
                    deadline: at.monotonic + Duration::from_millis(millis),
                    delay_ms: millis,
                    wall: at.wall,
                }
            );
        }
    }

    #[test]
    fn numeric_retry_seconds_overflow_without_replacing_the_hint() {
        let at = ErrorObservedAt::now();
        let (_, retry) = frame_headers(
            &json!({"headers": {
                "retry-after": u64::MAX,
                "retry-after-ms": 1,
            }}),
            at,
        );
        assert_eq!(retry, ObservedRetry::Unrepresentable { wall: at.wall });
    }
}
