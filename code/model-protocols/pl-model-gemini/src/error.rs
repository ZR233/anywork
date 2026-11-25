use pl_model_wire::provider_error::{
    ClassifiedProviderError, ErrorDecodeError, ProviderErrorEntry, ProviderErrorInput,
    ProviderErrorPolicy, ProviderFailureKind as Kind, RetryHint,
};
use serde::Deserialize;
use serde_json::Value;

#[derive(Debug)]
pub(crate) struct GeminiErrorPolicy;

#[derive(Deserialize)]
struct GoogleError {
    code: Option<GoogleCode>,
    status: Option<String>,
    message: Option<String>,
    #[serde(default)]
    details: Vec<Value>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum GoogleCode {
    Number(serde_json::Number),
    Text(String),
}

impl GoogleCode {
    fn http_status(&self) -> Option<u16> {
        let status = match self {
            Self::Number(code) => u16::try_from(code.as_u64()?).ok()?,
            Self::Text(code) => code.parse().ok()?,
        };
        (400..=599).contains(&status).then_some(status)
    }
}

impl From<GoogleCode> for String {
    fn from(code: GoogleCode) -> Self {
        match code {
            GoogleCode::Number(code) => code.to_string(),
            GoogleCode::Text(code) => code,
        }
    }
}

#[derive(Deserialize)]
#[serde(tag = "@type")]
enum GoogleDetail {
    #[serde(
        rename = "type.googleapis.com/google.rpc.RetryInfo",
        rename_all = "camelCase"
    )]
    RetryInfo { retry_delay: String },
    #[serde(rename = "type.googleapis.com/google.rpc.QuotaFailure")]
    QuotaFailure { violations: Vec<QuotaViolation> },
    #[serde(rename = "type.googleapis.com/google.rpc.ErrorInfo")]
    ErrorInfo { reason: String },
    #[serde(other)]
    Other,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct QuotaViolation {
    quota_id: Option<String>,
    quota_metric: Option<String>,
}

impl GoogleError {
    fn classify(
        self,
        input: &ProviderErrorInput<'_>,
    ) -> Result<ClassifiedProviderError, ErrorDecodeError> {
        let mut retry_hint = RetryHint::Absent;
        let mut daily_quota = false;
        let mut structured_kind = None;
        for detail in &self.details {
            let detail: GoogleDetail = serde_json::from_value(detail.clone())?;
            match detail {
                GoogleDetail::RetryInfo { retry_delay } => {
                    retry_hint =
                        retry_hint.combine(RetryHint::from_google_retry_delay(&retry_delay));
                }
                GoogleDetail::QuotaFailure { violations } => {
                    daily_quota |= violations.iter().any(|violation| {
                        violation.quota_id.as_deref().is_some_and(is_daily_quota_id)
                            || violation
                                .quota_metric
                                .as_deref()
                                .is_some_and(is_daily_quota_id)
                    });
                }
                GoogleDetail::ErrorInfo { reason } => {
                    structured_kind = match reason.as_str() {
                        "API_KEY_INVALID" | "API_KEY_EXPIRED" => Some(Kind::Authentication),
                        "API_KEY_SERVICE_BLOCKED"
                        | "API_KEY_HTTP_REFERRER_BLOCKED"
                        | "SERVICE_DISABLED" => Some(Kind::Authorization),
                        "BILLING_DISABLED" => Some(Kind::Quota),
                        _ => structured_kind,
                    };
                }
                GoogleDetail::Other => {}
            }
        }
        let http_status = self.code.as_ref().and_then(GoogleCode::http_status);
        let (kind, retryable) = if let Some(kind) = structured_kind {
            (kind, false)
        } else {
            match self.status.as_deref() {
                Some("UNAUTHENTICATED") => (Kind::Authentication, false),
                Some("PERMISSION_DENIED") => (Kind::Authorization, false),
                Some("RESOURCE_EXHAUSTED") if daily_quota => (Kind::Quota, false),
                Some("RESOURCE_EXHAUSTED") => (Kind::Unknown, true),
                Some("INTERNAL" | "UNAVAILABLE" | "ABORTED") => (Kind::ServiceBusy, true),
                Some("DEADLINE_EXCEEDED") => (Kind::Transport, true),
                Some("INVALID_ARGUMENT")
                    if self
                        .message
                        .as_deref()
                        .is_some_and(is_context_limit_message) =>
                {
                    (Kind::ContextLimit, false)
                }
                Some(
                    "INVALID_ARGUMENT"
                    | "FAILED_PRECONDITION"
                    | "NOT_FOUND"
                    | "OUT_OF_RANGE"
                    | "UNIMPLEMENTED",
                ) => (Kind::InvalidRequest, false),
                Some("CANCELLED") => (Kind::Unknown, false),
                _ if daily_quota => (Kind::Quota, false),
                _ => {
                    let fallback = ClassifiedProviderError::from_http_status(
                        input.failure_status(http_status),
                    );
                    (fallback.kind, fallback.retryable)
                }
            }
        };
        let mut error = ClassifiedProviderError::new(
            kind,
            retryable,
            self.message
                .unwrap_or_else(|| "Google reported a generation error".to_owned()),
        );
        error.code = self.code.map(String::from);
        error.error_type = self.status;
        error.http_status = http_status;
        error.retry_hint = retry_hint;
        if !self.details.is_empty() {
            error.details = Some(Box::new(Value::Array(self.details)));
        }
        Ok(error)
    }
}

fn is_daily_quota_id(id: &str) -> bool {
    let id = id.to_ascii_lowercase();
    id.contains("perday") || id.contains("per_day") || id.contains("daily")
}

impl ProviderErrorPolicy for GeminiErrorPolicy {
    fn decode_error(
        &self,
        input: ProviderErrorInput<'_>,
    ) -> Result<Option<ClassifiedProviderError>, ErrorDecodeError> {
        let Some(payload) = input.payload else {
            return Ok(None);
        };
        if let Some(error) =
            google_error_envelope(payload).and_then(|envelope| envelope.get("error"))
        {
            let error: GoogleError = serde_json::from_value(error.clone())?;
            if error.code.is_none() && error.status.is_none() && error.message.is_none() {
                return Err(ErrorDecodeError::Structure("missing Google error fields"));
            }
            return Ok(Some(error.classify(&input)?));
        }
        if input.entry == ProviderErrorEntry::HttpResponse {
            return Ok(None);
        }
        if let Some(reason) = payload
            .get("promptFeedback")
            .and_then(|feedback| feedback.get("blockReason"))
            .and_then(Value::as_str)
            .filter(|reason| !reason.is_empty() && *reason != "BLOCK_REASON_UNSPECIFIED")
        {
            let mut error = ClassifiedProviderError::new(
                Kind::ContentBlocked,
                false,
                format!("Gemini prompt blocked: {reason}"),
            );
            error.code = Some(reason.to_owned());
            return Ok(Some(error));
        }
        let reason = payload
            .get("candidates")
            .and_then(Value::as_array)
            .and_then(|candidates| candidates.first())
            .and_then(|candidate| candidate.get("finishReason"))
            .and_then(Value::as_str);
        let Some(reason) =
            reason.filter(|reason| !matches!(*reason, "" | "STOP" | "FINISH_REASON_UNSPECIFIED"))
        else {
            return Ok(None);
        };
        let kind = match reason {
            "MAX_TOKENS" => Kind::OutputLimit,
            "SAFETY"
            | "RECITATION"
            | "BLOCKLIST"
            | "PROHIBITED_CONTENT"
            | "SPII"
            | "IMAGE_SAFETY"
            | "IMAGE_PROHIBITED_CONTENT"
            | "IMAGE_RECITATION"
            | "MODEL_ARMOR" => Kind::ContentBlocked,
            "MALFORMED_RESPONSE"
            | "MALFORMED_FUNCTION_CALL"
            | "UNEXPECTED_TOOL_CALL"
            | "TOO_MANY_TOOL_CALLS" => Kind::Protocol,
            _ => Kind::Unknown,
        };
        let mut error = ClassifiedProviderError::new(
            kind,
            reason == "MALFORMED_RESPONSE",
            format!("Gemini generation terminated with finishReason={reason}"),
        );
        error.code = Some(reason.to_owned());
        Ok(Some(error))
    }
}

pub(super) fn google_error_envelope(payload: &Value) -> Option<&Value> {
    if payload.get("error").is_some() {
        Some(payload)
    } else {
        payload
            .as_array()?
            .iter()
            .find(|entry| entry.get("error").is_some())
    }
}

fn is_context_limit_message(message: &str) -> bool {
    let lower = message.to_ascii_lowercase();
    lower.contains("token count") && lower.contains("exceeds")
        || lower.contains("exceeds the maximum number of tokens")
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_model_wire::provider_error::ErrorObservedAt;

    fn decode(payload: &Value) -> ClassifiedProviderError {
        GeminiErrorPolicy
            .decode_error(ProviderErrorInput {
                entry: ProviderErrorEntry::HttpResponse,
                event_name: None,
                wire_api: None,
                endpoint: None,
                http_status: None,
                payload: Some(payload),
            })
            .unwrap()
            .unwrap()
    }

    #[test]
    fn google_retry_info_preserves_fractional_minimum_without_changing_permanent_errors() {
        for (delay, expected) in [
            ("3s", Some(3000)),
            ("1.250s", Some(1250)),
            ("0.000000001s", Some(1)),
            ("-1s", None),
            ("1e3s", None),
            ("1.0000000001s", None),
        ] {
            let parsed = decode(&serde_json::json!({"error":{
                "code":429,"status":"RESOURCE_EXHAUSTED","details":[{
                    "@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":delay
                }]
            }}));
            assert!(parsed.retryable);
            let actual = match parsed.retry_hint.observed(ErrorObservedAt::now()) {
                pl_model_wire::provider_error::ObservedRetry::At { delay_ms, .. } => Some(delay_ms),
                pl_model_wire::provider_error::ObservedRetry::Absent => None,
                other => panic!("unexpected retry hint: {other:?}"),
            };
            assert_eq!(actual, expected, "{delay}");
        }
        let parsed = decode(&serde_json::json!({"error":{
            "status":"INVALID_ARGUMENT","details":[{
                "@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"3s"
            }]
        }}));
        assert!(!parsed.retryable);
    }

    #[test]
    fn parses_google_rpc_object_and_array_envelopes() {
        let object = decode(&serde_json::json!({"error":{
            "code":404,"message":"Publisher model not found","status":"NOT_FOUND"
        }}));
        assert_eq!(object.kind, Kind::InvalidRequest);
        assert!(!object.retryable);
        let array = decode(&serde_json::json!([{"error":{
            "code":429,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED"
        }}]));
        assert_eq!(array.kind, Kind::Unknown);
        assert!(array.retryable);
    }

    #[test]
    fn classifies_context_limit_invalid_argument() {
        let parsed = decode(&serde_json::json!({"error":{
            "code":400,
            "message":"The input token count (1200000) exceeds the maximum number of tokens allowed (1048576).",
            "status":"INVALID_ARGUMENT"
        }}));
        assert_eq!(parsed.kind, Kind::ContextLimit);
        assert!(!parsed.retryable);
    }
}
