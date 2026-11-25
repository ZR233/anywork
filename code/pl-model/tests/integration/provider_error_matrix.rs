use pl_model::protocol::{ProtocolId, WireApi, builtin_protocols, providers};
use pl_model_wire::{
    provider_error::{ErrorObservedAt, ErrorPolicyBinding, ObservedRetry, ProviderErrorContext},
    transport::response_failure,
};
use pl_protocol::{ProviderFailure, ProviderFailureKind as Kind, ProviderFailureStage};
use serde_json::{Value, json};

fn classify(protocol: ProtocolId, status: u16, payload: Value) -> ProviderFailure {
    let adapter = builtin_protocols().resolve(&protocol).unwrap();
    response_failure(
        Some(ErrorPolicyBinding {
            policy: adapter.error_policy,
            wire_api: if protocol == providers::gemini::ID {
                WireApi::GeminiGenerateContent
            } else {
                WireApi::ChatCompletions
            },
            endpoint: None,
        }),
        &serde_json::to_vec(&payload).unwrap(),
        &ProviderErrorContext {
            stage: ProviderFailureStage::Request,
            request_id: Some("policy-matrix-request"),
            http_status: Some(status),
            observed_at: ErrorObservedAt::now(),
            header_retry: ObservedRetry::Absent,
            redact: &str::to_owned,
        },
    )
}

#[test]
fn registered_provider_policies_follow_the_documented_failure_matrix() {
    let cases = [
        (
            providers::openai::ID,
            429,
            json!({"error":{"code":"insufficient_quota","type":"rate_limit_error"}}),
            Kind::Quota,
            false,
        ),
        (
            providers::openai::ID,
            429,
            json!({"error":{"code":"usage_limit_reached"}}),
            Kind::Quota,
            false,
        ),
        (
            providers::openai::ID,
            429,
            json!({"error":{"code":"rate_limit_exceeded"}}),
            Kind::RateLimit,
            true,
        ),
        (
            providers::openai::ID,
            500,
            json!({"error":{"code":"invalid_api_key"}}),
            Kind::Authentication,
            false,
        ),
        (
            providers::deepseek::ID,
            402,
            json!({"error":{"message":"balance unavailable"}}),
            Kind::Quota,
            false,
        ),
        (
            providers::deepseek::ID,
            429,
            json!({"error":{"type":"insufficient_balance"}}),
            Kind::Quota,
            false,
        ),
        (
            providers::deepseek::ID,
            429,
            json!({"error":{"message":"rate limited"}}),
            Kind::RateLimit,
            true,
        ),
        (
            providers::deepseek::ID,
            503,
            json!({"error":{"message":"unavailable"}}),
            Kind::ServiceBusy,
            true,
        ),
        (
            providers::glm::ID,
            429,
            json!({"error":{"code":1113}}),
            Kind::Quota,
            false,
        ),
        (
            providers::glm::ID,
            429,
            json!({"error":{"code":1302}}),
            Kind::RateLimit,
            true,
        ),
        (
            providers::glm::ID,
            429,
            json!({"error":{"code":"1305"}}),
            Kind::ServiceBusy,
            true,
        ),
        (
            providers::glm::ID,
            429,
            json!({"error":{"code":1308}}),
            Kind::Quota,
            false,
        ),
        (
            providers::glm::ID,
            429,
            json!({"error":{"code":1316}}),
            Kind::Quota,
            false,
        ),
        (
            providers::glm::ID,
            429,
            json!({"error":{"code":1321}}),
            Kind::Quota,
            false,
        ),
        (
            providers::glm::ID,
            429,
            json!({"error":{"code":1311}}),
            Kind::Authorization,
            false,
        ),
        (
            providers::glm::ID,
            429,
            json!({"error":{"code":1234}}),
            Kind::Unknown,
            false,
        ),
        (
            providers::mimo::ID,
            402,
            json!({"error":{"message":"balance unavailable"}}),
            Kind::Quota,
            false,
        ),
        (
            providers::mimo::ID,
            421,
            json!({"error":{"message":"blocked"}}),
            Kind::ContentBlocked,
            false,
        ),
        (
            providers::mimo::ID,
            429,
            json!({"error":{"message":"monthly quota exceeded"}}),
            Kind::Unknown,
            true,
        ),
        (
            providers::xai::ID,
            429,
            json!({"error":{"type":"permission_error"}}),
            Kind::Authorization,
            false,
        ),
        (
            providers::xai::ID,
            429,
            json!({"error":{"message":"too many requests"}}),
            Kind::RateLimit,
            true,
        ),
        (
            providers::gemini::ID,
            429,
            json!({"error":{"code":429,"status":"RESOURCE_EXHAUSTED","details":[{"@type":"type.googleapis.com/google.rpc.QuotaFailure","violations":[{"quotaId":"GenerateRequestsPerDayPerProjectPerModel"}]}]}}),
            Kind::Quota,
            false,
        ),
        (
            providers::gemini::ID,
            429,
            json!({"error":{"code":429,"status":"RESOURCE_EXHAUSTED","details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"60s"}]}}),
            Kind::Unknown,
            true,
        ),
        (
            providers::gemini::ID,
            503,
            json!([{ "error":{"code":503,"status":"UNAVAILABLE"}}]),
            Kind::ServiceBusy,
            true,
        ),
        (
            providers::openai::COMPATIBLE_ID,
            200,
            json!({"error":{"code":"insufficient_quota","message":"text does not establish a provider contract"}}),
            Kind::Unknown,
            false,
        ),
        (
            providers::openai::COMPATIBLE_ID,
            200,
            json!({"error":{"code":"upstream_error"}}),
            Kind::ServiceBusy,
            true,
        ),
    ];
    for (protocol, status, payload, kind, retryable) in cases {
        let failure = classify(protocol.clone(), status, payload.clone());
        assert_eq!(
            (failure.kind, failure.retry.is_retryable()),
            (kind, retryable),
            "{protocol} HTTP {status}, payload={payload}"
        );
        assert_eq!(failure.http_status, Some(status));
        assert_eq!(
            failure.context.request_id.as_deref(),
            Some("policy-matrix-request")
        );
        if let Some(code) = payload.pointer("/error/code") {
            let code = code
                .as_str()
                .map_or_else(|| code.to_string(), str::to_owned);
            assert_eq!(failure.code.as_deref(), Some(code.as_str()));
        }
    }
}

#[test]
fn deepseek_known_permanent_type_is_not_hidden_by_an_unknown_code() {
    for (error_type, expected) in [
        ("insufficient_balance", Kind::Quota),
        ("authentication_error", Kind::Authentication),
    ] {
        let failure = classify(
            providers::deepseek::ID,
            429,
            json!({"error":{"code":"future_detail_code","type":error_type}}),
        );
        assert_eq!(failure.kind, expected, "error.type={error_type}");
        assert!(!failure.retry.is_retryable());
        assert_eq!(failure.code.as_deref(), Some("future_detail_code"));
        assert_eq!(failure.error_type.as_deref(), Some(error_type));
    }
}
