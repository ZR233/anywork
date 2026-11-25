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
                Some("INTERNAL" | "UNAVAILABLE") => (Kind::ServiceBusy, true),
                Some("DEADLINE_EXCEEDED") => (Kind::Transport, true),
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
            "MALFORMED_FUNCTION_CALL" | "UNEXPECTED_TOOL_CALL" | "TOO_MANY_TOOL_CALLS" => {
                Kind::Protocol
            }
            _ => Kind::Unknown,
        };
        let mut error = ClassifiedProviderError::new(
            kind,
            false,
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
