use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use pl_model_runtime::runtime::{
    ModelInvocationContext, ModelRuntime, ModelSession, ModelSubAttemptReceipt,
};
use pl_model_wire::completion::{
    CompletionRequest, CompletionTraceContext, Message, MessageContent, MessageRole,
};
use pl_model_wire::model::{ModelDefinition, ModelTransportProfile};
use pl_model_wire::provider_error::{
    ClassifiedProviderError, ErrorDecodeError, ProviderErrorInput, ProviderErrorPolicy,
};
use pl_protocol::{ProviderFailureKind, ProviderRecovery, RetryDisposition};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, WebSocketAction, responses_text};
use serde_json::json;

const MODEL: &str = "ws-test-model";
const PROMPT: &str = "continue";

fn request() -> CompletionRequest {
    CompletionRequest::builder()
        .messages(vec![Message {
            role: MessageRole::User,
            content: MessageContent::text(PROMPT),
            presentation: Default::default(),
            reasoning_content: None,
            tool_calls: None,
            tool_result: None,
            metadata: Default::default(),
        }])
        .build()
}

fn runtime(
    fixture: &FixtureServer,
    token: Option<&str>,
    policy: &'static dyn ProviderErrorPolicy,
) -> ModelRuntime {
    let mut endpoint = pl_model_openai::endpoint::endpoint(Some(fixture.base_url()));
    endpoint.bearer_token = token.map(str::to_owned);
    let mut model = ModelDefinition::compatible(MODEL);
    model
        .extra
        .binding
        .set_transport(ModelTransportProfile::responses_websocket());
    ModelRuntime::bind(
        "fixture",
        endpoint,
        model,
        &pl_model_openai_wire::OPENAI_WIRE_CODEC,
        policy,
        None,
    )
    .unwrap()
}

#[tokio::test]
async fn oversized_numeric_retry_header_takes_precedence_over_finite_error_body() {
    let frame = r#"{"type":"error","headers":{"retry-after-ms":184467440737095516160},
        "error":{"code":"rate_limit_exceeded","message":"busy","retry_after_ms":1000}}"#;
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesWebSocket,
        PROMPT,
        0,
        Reply::WebSocketScript(vec![WebSocketAction::RawText(frame.into())]),
    )])
    .await
    .unwrap();
    let session = ModelSession::default();
    let failure = tokio::time::timeout(
        Duration::from_secs(5),
        runtime(
            &fixture,
            None,
            pl_model_openai::adapter::ADAPTER.error_policy,
        )
        .complete(
            request(),
            ModelInvocationContext::in_memory(session.clone()),
        ),
    )
    .await
    .unwrap()
    .unwrap_err();
    let upstream = failure.source.provider_failure_ref().unwrap();
    assert_eq!(upstream.kind, ProviderFailureKind::RateLimit);
    assert_eq!(upstream.retry, RetryDisposition::WaitUnrepresentable);
    assert_eq!(failure.settlements.len(), 1);
    session.close().await.unwrap();
    assert_eq!(fixture.finish().await.unwrap().len(), 1);
}

#[derive(Debug)]
struct CountedPolicy(AtomicUsize);

impl ProviderErrorPolicy for CountedPolicy {
    fn decode_error(
        &self,
        input: ProviderErrorInput<'_>,
    ) -> Result<Option<ClassifiedProviderError>, ErrorDecodeError> {
        if input
            .payload
            .is_some_and(|payload| payload["type"] == "error")
        {
            self.0.fetch_add(1, Ordering::Relaxed);
        }
        pl_model_openai::adapter::ADAPTER
            .error_policy
            .decode_error(input)
    }
}

#[tokio::test]
async fn websocket_top_level_error_keeps_same_frame_usage_and_redacted_request_id() {
    static POLICY: CountedPolicy = CountedPolicy(AtomicUsize::new(0));
    const TOKEN: &str = "fixture-reflected-credential";
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesWebSocket,
        PROMPT,
        0,
        Reply::WebSocket(vec![json!({
            "type": "error",
            "headers": {"X-Request-Id": format!("trace-{TOKEN}")},
            "error": {"code": "insufficient_quota", "message": "quota spent"},
            "usage": {"input_tokens": 11, "output_tokens": 3, "total_tokens": 14},
        })]),
    )])
    .await
    .unwrap();
    let session = ModelSession::default();
    let failure = runtime(&fixture, Some(TOKEN), &POLICY)
        .complete(
            request(),
            ModelInvocationContext::in_memory(session.clone()).with_trace_metadata(
                CompletionTraceContext {
                    session_id: "quota-session".into(),
                    turn_id: "quota-turn".into(),
                    inference_id: "quota-attempt".into(),
                },
            ),
        )
        .await
        .unwrap_err();
    let upstream = failure.source.provider_failure_ref().unwrap();
    assert_eq!(upstream.kind, ProviderFailureKind::Quota);
    assert_eq!(upstream.retry, RetryDisposition::Permanent);
    assert_eq!(failure.accounting.usage.total_tokens, Some(14));
    assert!(failure.usage_is_terminal);
    assert_eq!(
        upstream.context.request_id.as_deref(),
        Some("trace-[REDACTED_CREDENTIAL]")
    );
    assert_eq!(failure.settlements.len(), 1);
    let payload = failure.settlements[0].content();
    assert!(!payload.contains(TOKEN));
    let receipt: ModelSubAttemptReceipt = serde_json::from_str(payload).unwrap();
    assert_eq!(receipt.turn_id, None);
    assert_eq!(receipt.attempt_id, "quota-attempt");
    assert_eq!(receipt.provider_failure.as_ref(), Some(upstream));
    assert_eq!(receipt.billing.accounting.usage.total_tokens, Some(14));
    assert!(receipt.billing.attempt.unwrap().usage_is_terminal);
    assert_eq!(POLICY.0.load(Ordering::Relaxed), 1);
    session.close().await.unwrap();
    assert_eq!(fixture.finish().await.unwrap().len(), 1);
}

#[tokio::test]
async fn websocket_partial_usage_stays_with_the_failed_attempt_after_disconnect_or_error() {
    for (fault, expected_kind) in [
        (WebSocketAction::Disconnect, ProviderFailureKind::Transport),
        (
            WebSocketAction::Event(json!({"type": "response.failed", "response": {
                "id": "partial", "status": "failed",
                "error": {"code": "server_error", "message": "temporarily unavailable", "retry_after_ms": 1},
            }})),
            ProviderFailureKind::ServiceBusy,
        ),
    ] {
        let mut actions = vec![WebSocketAction::Event(
            json!({"type": "response.created", "response": {
                "id": "partial", "model": MODEL,
            }}),
        )];
        for (input, output) in [(10, 3), (11, 5)] {
            actions.push(WebSocketAction::Event(
                json!({"type":"response.in_progress", "response": {
                    "id":"partial", "model":MODEL, "usage":{
                        "input_tokens":input, "output_tokens":output, "total_tokens":input + output,
                    },
                }}),
            ));
        }
        actions.push(fault);
        let fixture = FixtureServer::start(vec![
            Step::prompt(
                Protocol::ResponsesWebSocket,
                PROMPT,
                0,
                Reply::WebSocketScript(actions),
            ),
            Step::prompt(
                Protocol::ResponsesWebSocket,
                PROMPT,
                1,
                Reply::WebSocket(responses_text("recovered", "success", MODEL)),
            ),
        ])
        .await
        .unwrap();
        let session = ModelSession::default();
        let response = runtime(
            &fixture,
            None,
            pl_model_openai::adapter::ADAPTER.error_policy,
        )
        .complete(
            request(),
            ModelInvocationContext::in_memory(session.clone()),
        )
        .await
        .unwrap();
        assert_eq!(response.content.as_deref(), Some("recovered"));
        assert_eq!(response.settlements.len(), 2);
        let failed: ModelSubAttemptReceipt =
            serde_json::from_str(response.settlements[0].content()).unwrap();
        let successful: ModelSubAttemptReceipt =
            serde_json::from_str(response.settlements[1].content()).unwrap();
        assert_eq!(failed.provider_failure.unwrap().kind, expected_kind);
        assert_eq!(failed.billing.accounting.usage.input_tokens, Some(11));
        assert_eq!(failed.billing.accounting.usage.output_tokens, Some(5));
        assert_eq!(failed.billing.accounting.usage.total_tokens, Some(16));
        assert!(!failed.billing.attempt.unwrap().usage_is_terminal);
        assert_eq!(
            successful.billing.accounting.usage,
            response.accounting.usage
        );
        assert_eq!(response.accounting.usage.total_tokens, None);
        assert!(successful.billing.attempt.unwrap().usage_is_terminal);
        assert_ne!(successful.billing.inference_id, failed.billing.inference_id);
        session.close().await.unwrap();
        assert_eq!(fixture.finish().await.unwrap().len(), 2);
    }
}

#[tokio::test]
async fn websocket_full_request_cannot_retry_as_an_invalid_continuation() {
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesWebSocket,
        PROMPT,
        0,
        Reply::WebSocket(vec![json!({"type":"error", "error": {
            "code": "previous_response_not_found", "message": "missing previous response",
        }})]),
    )])
    .await
    .unwrap();
    let session = ModelSession::default();
    let failure = runtime(
        &fixture,
        None,
        pl_model_openai::adapter::ADAPTER.error_policy,
    )
    .complete(
        request(),
        ModelInvocationContext::in_memory(session.clone()),
    )
    .await
    .unwrap_err();
    let upstream = failure.source.provider_failure_ref().unwrap();
    assert_eq!(
        upstream.code.as_deref(),
        Some("previous_response_not_found")
    );
    assert_eq!(upstream.context.recovery, ProviderRecovery::None);
    assert_eq!(upstream.retry, RetryDisposition::Permanent);
    assert_eq!(failure.settlements.len(), 1);
    session.close().await.unwrap();
    assert_eq!(fixture.finish().await.unwrap().len(), 1);
}
