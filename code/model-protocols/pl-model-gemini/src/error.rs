use pl_model_wire::wire_codec::ParsedHttpError;
use pl_protocol::{ProviderFailureKind, RetryDisposition};
use serde::Deserialize;

#[derive(Deserialize)]
struct GoogleErrorEnvelope {
    error: GoogleRpcError,
}

#[derive(Deserialize)]
struct GoogleRpcError {
    code: Option<serde_json::Value>,
    message: Option<String>,
    status: Option<String>,
    details: Option<Vec<serde_json::Value>>,
}

pub fn parse_google_http_error(body: &[u8]) -> Option<ParsedHttpError> {
    let envelope = match body.iter().copied().find(|b| !b.is_ascii_whitespace()) {
        Some(b'[') => serde_json::from_slice::<Vec<GoogleErrorEnvelope>>(body)
            .ok()
            .and_then(|mut list| (!list.is_empty()).then(|| list.remove(0))),
        Some(b'{') => serde_json::from_slice::<GoogleErrorEnvelope>(body).ok(),
        _ => None,
    }?;
    let rpc = envelope.error;
    let status_str = rpc
        .status
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let numeric_code = rpc.code.as_ref().and_then(|v| {
        v.as_u64()
            .and_then(|n| u16::try_from(n).ok())
            .or_else(|| v.as_str()?.parse::<u16>().ok())
    });
    let code = status_str.map(ToOwned::to_owned).or_else(|| {
        rpc.code.as_ref().and_then(|v| match v {
            serde_json::Value::String(s) => Some(s.clone()),
            serde_json::Value::Number(n) => Some(n.to_string()),
            _ => None,
        })
    });
    let message = rpc.message.clone();
    let (code_override, force_kind, mut force_retry) =
        classify_google_error(status_str, numeric_code, message.as_deref());
    if let Some(RetryDisposition::Retryable { retry_after_ms }) = &mut force_retry {
        *retry_after_ms = rpc
            .details
            .as_deref()
            .unwrap_or_default()
            .iter()
            .filter(|detail| {
                detail.get("@type").and_then(serde_json::Value::as_str)
                    == Some("type.googleapis.com/google.rpc.RetryInfo")
            })
            .filter_map(|detail| retry_delay_millis(detail.get("retryDelay")?.as_str()?))
            .max();
    }
    Some(ParsedHttpError {
        code: code_override.map(str::to_owned).or(code),
        message,
        business_auth_failure: false,
        force_kind,
        force_retry,
    })
}

// google.protobuf.Duration uses decimal seconds with at most nine fractional digits.
// Round up to milliseconds so retrying never precedes the server's minimum delay.
fn retry_delay_millis(value: &str) -> Option<u64> {
    let seconds = value.strip_suffix('s')?;
    let (whole, fraction) = seconds.split_once('.').unwrap_or((seconds, ""));
    if whole.is_empty()
        || !whole.bytes().all(|b| b.is_ascii_digit())
        || fraction.len() > 9
        || !fraction.bytes().all(|b| b.is_ascii_digit())
    {
        return None;
    }
    let whole = whole.parse::<u64>().ok()?;
    let nanos = if fraction.is_empty() {
        0
    } else {
        fraction
            .parse::<u64>()
            .ok()?
            .checked_mul(10_u64.pow(9 - fraction.len() as u32))?
    };
    whole
        .checked_mul(1000)?
        .checked_add(nanos.div_ceil(1_000_000))
}

fn classify_google_error(
    status: Option<&str>,
    numeric_code: Option<u16>,
    message: Option<&str>,
) -> (
    Option<&'static str>,
    Option<ProviderFailureKind>,
    Option<RetryDisposition>,
) {
    match status {
        Some("UNAUTHENTICATED") => {
            return (
                None,
                Some(ProviderFailureKind::Authentication),
                Some(RetryDisposition::Permanent),
            );
        }
        Some("PERMISSION_DENIED") => {
            return (
                None,
                Some(ProviderFailureKind::Authorization),
                Some(RetryDisposition::Permanent),
            );
        }
        Some("RESOURCE_EXHAUSTED") => {
            return (
                None,
                Some(ProviderFailureKind::Capacity),
                Some(RetryDisposition::Retryable {
                    retry_after_ms: None,
                }),
            );
        }
        Some("UNAVAILABLE" | "DEADLINE_EXCEEDED" | "ABORTED" | "INTERNAL") => {
            return (
                None,
                Some(ProviderFailureKind::Capacity),
                Some(RetryDisposition::Retryable {
                    retry_after_ms: None,
                }),
            );
        }
        Some("INVALID_ARGUMENT") => {
            if message.is_some_and(is_context_limit_message) {
                return (
                    Some("context_length_exceeded"),
                    Some(ProviderFailureKind::Configuration),
                    Some(RetryDisposition::Permanent),
                );
            }
            return (
                None,
                Some(ProviderFailureKind::Configuration),
                Some(RetryDisposition::Permanent),
            );
        }
        Some("NOT_FOUND" | "FAILED_PRECONDITION" | "OUT_OF_RANGE" | "UNIMPLEMENTED") => {
            return (
                None,
                Some(ProviderFailureKind::Configuration),
                Some(RetryDisposition::Permanent),
            );
        }
        _ => {}
    }
    match numeric_code {
        Some(401) => (
            None,
            Some(ProviderFailureKind::Authentication),
            Some(RetryDisposition::Permanent),
        ),
        Some(403) => (
            None,
            Some(ProviderFailureKind::Authorization),
            Some(RetryDisposition::Permanent),
        ),
        Some(408 | 429 | 500..=599) => (
            None,
            Some(ProviderFailureKind::Capacity),
            Some(RetryDisposition::Retryable {
                retry_after_ms: None,
            }),
        ),
        Some(400..=499) => (
            None,
            Some(ProviderFailureKind::Configuration),
            Some(RetryDisposition::Permanent),
        ),
        _ => (None, None, None),
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
            let body = serde_json::json!({"error":{"code":429,"status":"RESOURCE_EXHAUSTED","details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":delay}]}});
            let parsed = parse_google_http_error(&serde_json::to_vec(&body).unwrap()).unwrap();
            assert_eq!(
                parsed.force_retry.unwrap().retry_after_ms(),
                expected,
                "{delay}"
            );
        }
        let body = br#"{"error":{"status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"3s"}]}}"#;
        assert_eq!(
            parse_google_http_error(body).unwrap().force_retry,
            Some(RetryDisposition::Permanent)
        );
    }

    #[test]
    fn parses_google_rpc_object_and_array_envelopes() {
        let obj =
            br#"{"error":{"code":404,"message":"Publisher model not found","status":"NOT_FOUND"}}"#;
        let parsed = parse_google_http_error(obj).unwrap();
        assert_eq!(parsed.code.as_deref(), Some("NOT_FOUND"));
        assert_eq!(parsed.force_kind, Some(ProviderFailureKind::Configuration));
        assert_eq!(parsed.force_retry, Some(RetryDisposition::Permanent));

        let arr =
            br#"[{"error":{"code":429,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED"}}]"#;
        let parsed = parse_google_http_error(arr).unwrap();
        assert_eq!(parsed.code.as_deref(), Some("RESOURCE_EXHAUSTED"));
        assert_eq!(parsed.force_kind, Some(ProviderFailureKind::Capacity));
        assert!(matches!(
            parsed.force_retry,
            Some(RetryDisposition::Retryable { .. })
        ));
    }

    #[test]
    fn classifies_context_limit_invalid_argument() {
        let body = br#"{"error":{"code":400,"message":"The input token count (1200000) exceeds the maximum number of tokens allowed (1048576).","status":"INVALID_ARGUMENT"}}"#;
        let parsed = parse_google_http_error(body).unwrap();
        assert_eq!(parsed.code.as_deref(), Some("context_length_exceeded"));
        assert_eq!(parsed.force_kind, Some(ProviderFailureKind::Configuration));
        assert_eq!(parsed.force_retry, Some(RetryDisposition::Permanent));
    }
}
