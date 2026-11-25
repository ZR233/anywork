use pl_protocol::{ProviderFailure, ProviderFailureKind, PureError, RetryDisposition};

fn retryable_provider_failure(code: Option<&str>, http_status: Option<u16>) -> bool {
    match provider_failure_kind(code, http_status, false) {
        ProviderFailureKind::Authentication | ProviderFailureKind::Authorization => false,
        // Responses WebSocket capacity is reported as 400. Other request/configuration
        // failures take precedence over a generic upstream code.
        ProviderFailureKind::Configuration => {
            http_status == Some(400)
                && code.is_some_and(|code| {
                    code.eq_ignore_ascii_case("websocket_connection_limit_reached")
                })
        }
        _ => {
            http_status.is_some_and(retryable_provider_status)
                || code.is_some_and(retryable_provider_code)
        }
    }
}

pub fn provider_stream_failure(
    code: Option<&str>,
    http_status: Option<u16>,
    retry_after_ms: Option<u64>,
    message: String,
) -> PureError {
    PureError::provider_failure(stream_failure(code, http_status, retry_after_ms, message))
}

/// Classifies a wire failure once, before it enters protocol-neutral stream processing.
pub fn stream_failure(
    code: Option<&str>,
    http_status: Option<u16>,
    retry_after_ms: Option<u64>,
    message: String,
) -> ProviderFailure {
    let retryable = retryable_provider_failure(code, http_status);
    ProviderFailure {
        context: pl_protocol::ProviderFailureContext {
            stage: pl_protocol::ProviderFailureStage::Stream,
            ..Default::default()
        },
        kind: provider_failure_kind(code, http_status, retryable),
        code: code.map(str::to_owned),
        http_status,
        message: redact_secret_like_values(&message),
        retry: if retryable {
            RetryDisposition::Retryable { retry_after_ms }
        } else {
            RetryDisposition::Permanent
        },
    }
}

pub fn reqwest_error_to_pure(error: reqwest::Error) -> PureError {
    let error = error.without_url();
    let detail = reqwest_error_detail(&error);
    if error.is_timeout() || error.is_connect() || response_start_connection_closed(&error) {
        return PureError::transient_model_failure(
            detail,
            None,
            None,
            error.status().map(|status| status.as_u16()),
        );
    }
    if error.is_builder() || error.is_redirect() {
        configuration_failure(detail)
    } else if error.is_decode() || error.is_body() {
        // This general boundary also handles Response::json(). Raw byte-stream
        // failures use reqwest_body_error_to_pure before any model decoding.
        protocol_failure(detail)
    } else {
        PureError::provider_failure(ProviderFailure {
            context: Default::default(),
            kind: ProviderFailureKind::Unknown,
            code: None,
            http_status: error.status().map(|status| status.as_u16()),
            message: detail,
            retry: RetryDisposition::Permanent,
        })
    }
}

pub fn reqwest_body_error_to_pure(error: reqwest::Error) -> PureError {
    // At bytes_stream(), Decode refers to HTTP framing/content decoding, not
    // model JSON. Do not depend on a nested io::Error or library error wording.
    let error = error.without_url();
    PureError::transient_model_failure(
        format!(
            "response body read failed: {}",
            reqwest_error_detail(&error)
        ),
        None,
        None,
        error.status().map(|status| status.as_u16()),
    )
}

fn reqwest_error_detail(error: &reqwest::Error) -> String {
    use std::{error::Error, fmt::Write};

    let mut detail = redact_secret_like_values(&error.to_string());
    if error.is_timeout() {
        detail.push_str("; timeout=true");
    }
    let mut source = error.source();
    for _ in 0..8 {
        let Some(cause) = source else { break };
        // Hyper's Display is a fixed category, never its source/body. Do not
        // format arbitrary sources: they may contain URLs or provider content.
        if let Some(error) = cause.downcast_ref::<hyper::Error>() {
            let _ = write!(detail, "; hyper={error}");
        } else if let Some(error) = cause.downcast_ref::<std::io::Error>() {
            let _ = write!(detail, "; io={:?}", error.kind());
            if let Some(code) = error.raw_os_error() {
                let _ = write!(detail, "; os_code={code}");
            }
        }
        source = cause.source();
    }
    detail
}

fn configuration_failure(message: impl Into<String>) -> PureError {
    PureError::provider_failure(ProviderFailure {
        context: Default::default(),
        kind: ProviderFailureKind::Configuration,
        code: None,
        http_status: None,
        message: message.into(),
        retry: RetryDisposition::Permanent,
    })
}

fn protocol_failure(message: impl Into<String>) -> PureError {
    PureError::provider_failure(ProviderFailure {
        context: Default::default(),
        kind: ProviderFailureKind::Protocol,
        code: None,
        http_status: None,
        message: message.into(),
        retry: RetryDisposition::Permanent,
    })
}

fn response_start_connection_closed(error: &reqwest::Error) -> bool {
    if error.is_builder() || error.is_redirect() || error.is_status() {
        return false;
    }
    // decode/body 错误需要保留：它们可能根源于连接中断，逐层检查 source。
    let mut source: Option<&dyn std::error::Error> = Some(error);
    for _ in 0..8 {
        let Some(cause) = source else { break };
        if cause.downcast_ref::<std::io::Error>().is_some_and(|error| {
            matches!(
                error.kind(),
                std::io::ErrorKind::ConnectionAborted
                    | std::io::ErrorKind::ConnectionReset
                    | std::io::ErrorKind::BrokenPipe
                    | std::io::ErrorKind::UnexpectedEof
                    | std::io::ErrorKind::TimedOut
            )
        }) || cause
            .downcast_ref::<hyper::Error>()
            .is_some_and(|error| error.is_incomplete_message() || error.is_closed())
        {
            return true;
        }
        source = cause.source();
    }
    false
}

pub(super) fn retryable_provider_status(status: u16) -> bool {
    matches!(status, 408 | 409 | 425 | 429 | 500..=599)
}

fn provider_failure_kind(
    code: Option<&str>,
    http_status: Option<u16>,
    retryable: bool,
) -> ProviderFailureKind {
    if matches!(http_status, Some(401))
        || code.is_some_and(|code| matches!(code, "invalid_api_key" | "authentication_error"))
    {
        return ProviderFailureKind::Authentication;
    }
    if matches!(http_status, Some(403))
        || code.is_some_and(|code| matches!(code, "permission_denied" | "insufficient_permissions"))
    {
        return ProviderFailureKind::Authorization;
    }
    if retryable {
        return if matches!(http_status, Some(429 | 500..=599))
            || code.is_some_and(retryable_provider_code)
        {
            ProviderFailureKind::Capacity
        } else {
            ProviderFailureKind::Transport
        };
    }
    if matches!(http_status, Some(400 | 404 | 405 | 422))
        || code.is_some_and(|code| {
            matches!(
                code,
                "model_not_found" | "invalid_request_error" | "unsupported_model"
            )
        })
    {
        return ProviderFailureKind::Configuration;
    }
    ProviderFailureKind::Unknown
}

fn retryable_provider_code(code: &str) -> bool {
    matches!(
        code.to_ascii_lowercase().as_str(),
        "websocket_connection_limit_reached"
            | "rate_limit_exceeded"
            | "server_error"
            | "upstream_error"
            | "temporarily_unavailable"
            | "service_unavailable"
            | "request_timeout"
            | "server_is_overloaded"
    )
}

pub fn redact_secret_like_values(input: &str) -> String {
    input
        .split_whitespace()
        .map(redact_secret_like_token)
        .collect::<Vec<_>>()
        .join(" ")
}

fn redact_secret_like_token(token: &str) -> String {
    let trimmed = token.trim_matches(|ch: char| {
        matches!(
            ch,
            '.' | ',' | ';' | ':' | ')' | '(' | '"' | '\'' | '[' | ']' | '{' | '}'
        )
    });
    if !looks_like_secret_token(trimmed) {
        return token.to_string();
    }
    token.replacen(trimmed, "[REDACTED_API_KEY]", 1)
}

fn looks_like_secret_token(token: &str) -> bool {
    let lower = token.to_ascii_lowercase();
    (lower.starts_with("sk-") || lower.starts_with("sk_"))
        && token.len() >= 12
        && token
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '*' | '.'))
}
