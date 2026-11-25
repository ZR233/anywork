//! Provider-owned classification and shared failure context for HTTP, SSE and WebSocket.

mod retry;
mod transport;

use pl_protocol::{
    ProviderFailure, ProviderFailureKind as Kind, ProviderFailureStage, RetryDisposition,
};
pub use pl_protocol::{ProviderFailureKind, ProviderRecovery};
use serde_json::Value;

use crate::protocol::{ProtocolEndpoint, WireApi};

pub use retry::{ErrorObservedAt, ObservedRetry, RetryHint};
pub use transport::{reqwest_body_error_to_pure, reqwest_error_to_pure};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderErrorEntry {
    HttpResponse,
    Sse,
    WebSocket,
}

/// The payload is borrowed and may be absent for an HTTP response without JSON.
pub struct ProviderErrorInput<'a> {
    pub entry: ProviderErrorEntry,
    /// SSE event field when the transport supplied one.
    pub event_name: Option<&'a str>,
    pub wire_api: Option<WireApi>,
    pub endpoint: Option<&'a ProtocolEndpoint>,
    pub http_status: Option<u16>,
    pub payload: Option<&'a Value>,
}

impl ProviderErrorInput<'_> {
    /// A failing HTTP status governs status-based fallback. An established stream
    /// and a successful HTTP response may carry a different status in the payload.
    pub fn failure_status(&self, payload_status: Option<u16>) -> Option<u16> {
        self.http_status
            .filter(|status| *status >= 300)
            .or(payload_status)
    }
}

#[derive(Clone, Copy)]
pub struct ErrorPolicyBinding<'a> {
    pub policy: &'a dyn ProviderErrorPolicy,
    pub wire_api: WireApi,
    pub endpoint: Option<&'a ProtocolEndpoint>,
}

impl<'a> ErrorPolicyBinding<'a> {
    pub fn input<'p>(
        self,
        entry: ProviderErrorEntry,
        http_status: Option<u16>,
        payload: Option<&'p Value>,
    ) -> ProviderErrorInput<'p>
    where
        'a: 'p,
    {
        ProviderErrorInput {
            entry,
            event_name: None,
            wire_api: Some(self.wire_api),
            endpoint: self.endpoint,
            http_status,
            payload,
        }
    }
}

pub trait ProviderErrorPolicy: Send + Sync + std::fmt::Debug {
    fn decode_error(
        &self,
        input: ProviderErrorInput<'_>,
    ) -> Result<Option<ClassifiedProviderError>, ErrorDecodeError>;
}

/// An identifiable error envelope whose declared fields could not be decoded.
#[derive(Debug, thiserror::Error)]
pub enum ErrorDecodeError {
    #[error("invalid provider error envelope")]
    Envelope(#[from] serde_json::Error),
    #[error("invalid provider error envelope: {0}")]
    Structure(&'static str),
}

/// A provider classification awaiting receive time, request identity and redaction.
pub struct ClassifiedProviderError {
    pub kind: Kind,
    pub retryable: bool,
    pub code: Option<String>,
    pub error_type: Option<String>,
    /// Status declared inside the payload, if any.
    pub http_status: Option<u16>,
    pub message: String,
    pub recovery: ProviderRecovery,
    pub retry_hint: RetryHint,
    pub details: Option<Box<Value>>,
}

impl ClassifiedProviderError {
    pub fn new(kind: Kind, retryable: bool, message: impl Into<String>) -> Self {
        Self {
            kind,
            retryable,
            code: None,
            error_type: None,
            http_status: None,
            message: message.into(),
            recovery: ProviderRecovery::None,
            retry_hint: RetryHint::Absent,
            details: None,
        }
    }

    /// Conservative HTTP fallback for endpoints with no recognized business reason.
    pub fn from_http_status(status: Option<u16>) -> Self {
        let (kind, retryable) = match status {
            Some(401) => (Kind::Authentication, false),
            Some(403) => (Kind::Authorization, false),
            Some(400 | 404 | 405 | 413 | 415 | 422) => (Kind::InvalidRequest, false),
            Some(429) => (Kind::Unknown, true),
            Some(500 | 503) => (Kind::ServiceBusy, true),
            // No generic retry promise for 408, 409, 425 or other server/proxy errors.
            _ => (Kind::Unknown, false),
        };
        let message = match status {
            Some(status) => {
                format!("HTTP {status}: provider returned an unstructured error response")
            }
            None => "provider reported a failure".to_owned(),
        };
        Self::new(kind, retryable, message)
    }

    pub fn into_failure(self, context: &ProviderErrorContext<'_>) -> ProviderFailure {
        let wait = context
            .header_retry
            .combine(self.retry_hint.observed(context.observed_at));
        let retry = match wait {
            ObservedRetry::Unrepresentable { .. }
                if self.retryable || self.recovery != ProviderRecovery::None =>
            {
                RetryDisposition::WaitUnrepresentable
            }
            ObservedRetry::At { delay_ms, .. } if self.retryable => RetryDisposition::Retryable {
                retry_after_ms: Some(delay_ms),
            },
            ObservedRetry::Absent if self.retryable => RetryDisposition::Retryable {
                retry_after_ms: None,
            },
            _ => RetryDisposition::Permanent,
        };
        let redact = context.redact;
        let mut failure = ProviderFailure::new(self.kind, redact(&self.message), retry);
        let observed_wall = match wait {
            ObservedRetry::At { wall, .. } | ObservedRetry::Unrepresentable { wall } => wall,
            ObservedRetry::Absent => context.observed_at.wall,
        };
        failure.observed_at_unix_ms = observed_wall
            .duration_since(std::time::UNIX_EPOCH)
            .ok()
            .and_then(|elapsed| u64::try_from(elapsed.as_millis()).ok());
        failure.context.stage = context.stage;
        failure.context.request_id = context.request_id.map(redact);
        failure.context.recovery = self.recovery;
        failure.code = self.code.map(|code| redact(&code));
        failure.error_type = self.error_type.map(|kind| redact(&kind));
        failure.http_status = context
            .http_status
            .filter(|status| *status >= 300)
            .or(self.http_status)
            .or(context.http_status);
        failure.details = self
            .details
            .map(|details| Box::new(redact_json(*details, redact)));
        if let ObservedRetry::At {
            deadline, delay_ms, ..
        } = wait
        {
            failure = failure.with_retry_deadline(deadline);
            if !self.retryable {
                failure.reported_wait_ms = Some(delay_ms);
            }
        }
        failure
    }
}

pub struct ProviderErrorContext<'a> {
    pub stage: ProviderFailureStage,
    /// Already validated by the transport.
    pub request_id: Option<&'a str>,
    /// Failed HTTP status; leave empty for established streams.
    pub http_status: Option<u16>,
    pub observed_at: ErrorObservedAt,
    pub header_retry: ObservedRetry,
    pub redact: &'a dyn Fn(&str) -> String,
}

pub struct StreamFrameContext<'a> {
    pub policy: &'a dyn ProviderErrorPolicy,
    pub entry: ProviderErrorEntry,
    pub event_name: Option<&'a str>,
    pub wire_api: WireApi,
    pub endpoint: Option<&'a ProtocolEndpoint>,
    pub failure: ProviderErrorContext<'a>,
}

impl StreamFrameContext<'_> {
    pub fn decode_failure(&self, payload: &Value) -> Option<ProviderFailure> {
        decode_provider_failure(
            self.policy,
            ProviderErrorInput {
                entry: self.entry,
                event_name: self.event_name,
                wire_api: Some(self.wire_api),
                endpoint: self.endpoint,
                http_status: self.failure.http_status,
                payload: Some(payload),
            },
            &self.failure,
        )
        .or_else(|| {
            matches!(
                self.event_name,
                Some("error" | "response.failed" | "response.incomplete")
            )
            .then(|| ClassifiedProviderError::from_http_status(None).into_failure(&self.failure))
        })
    }

    pub fn protocol_failure(&self, message: impl Into<String>) -> ProviderFailure {
        let mut failure = ClassifiedProviderError::new(Kind::Protocol, false, message)
            .into_failure(&self.failure);
        failure.code = Some("invalid_response".to_owned());
        failure
    }
}

/// Converts a recognized failure (including a malformed error envelope) once.
pub fn decode_provider_failure(
    policy: &dyn ProviderErrorPolicy,
    input: ProviderErrorInput<'_>,
    context: &ProviderErrorContext<'_>,
) -> Option<ProviderFailure> {
    match policy.decode_error(input) {
        Ok(classified) => classified.map(|error| error.into_failure(context)),
        Err(error) => Some(
            ClassifiedProviderError::new(Kind::Protocol, false, error.to_string())
                .into_failure(context)
                .with_source(error),
        ),
    }
}

pub fn transport_failure(
    stage: ProviderFailureStage,
    message: impl Into<String>,
) -> ProviderFailure {
    ProviderFailure::new(
        Kind::Transport,
        redact_secret_like_values(&message.into()),
        RetryDisposition::Retryable {
            retry_after_ms: None,
        },
    )
    .at_stage(stage)
}

pub fn protocol_failure(
    stage: ProviderFailureStage,
    message: impl Into<String>,
) -> ProviderFailure {
    ProviderFailure::new(
        Kind::Protocol,
        redact_secret_like_values(&message.into()),
        RetryDisposition::Permanent,
    )
    .at_stage(stage)
}

pub fn invalid_request(message: impl Into<String>) -> ProviderFailure {
    ProviderFailure::new(
        Kind::InvalidRequest,
        redact_secret_like_values(&message.into()),
        RetryDisposition::Permanent,
    )
    .at_stage(ProviderFailureStage::Request)
}

pub fn request_id(headers: &reqwest::header::HeaderMap) -> Option<&str> {
    ["x-request-id", "x-goog-request-id", "request-id"]
        .into_iter()
        .filter_map(|name| headers.get(name)?.to_str().ok())
        .find(|value| {
            !value.is_empty()
                && value.len() <= 128
                && value
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || b"-_.:/".contains(&byte))
        })
}

fn redact_json(value: Value, redact: &dyn Fn(&str) -> String) -> Value {
    match value {
        Value::String(text) => Value::String(redact(&text)),
        Value::Array(values) => Value::Array(
            values
                .into_iter()
                .map(|value| redact_json(value, redact))
                .collect(),
        ),
        Value::Object(values) => Value::Object(
            values
                .into_iter()
                .map(|(key, value)| (redact(&key), redact_json(value, redact)))
                .collect(),
        ),
        other => other,
    }
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
    let lower = trimmed.to_ascii_lowercase();
    if (lower.starts_with("sk-") || lower.starts_with("sk_"))
        && trimmed.len() >= 12
        && trimmed
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '*' | '.'))
    {
        token.replacen(trimmed, "[REDACTED_API_KEY]", 1)
    } else {
        token.to_string()
    }
}
