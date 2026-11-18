use pl_protocol::{ProviderFailureKind as Kind, PureError, RetryDisposition};
use serde_json::json;

const SYNTHETIC_BEARER: &str = "oauth.synthetic.opaque-credential";

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
            if let Some(header_end) = request.windows(4).position(|bytes| bytes == b"\r\n\r\n") {
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

async fn model_sse(
    events: Vec<serde_json::Value>,
) -> std::result::Result<
    pl_model_openai_wire::completion::CompletionResponse,
    pl_model_openai_wire::completion::CompletionFailure,
> {
    use pl_model_openai_wire::{
        completion::{CompletionRequest, Message, MessageContent, MessageRole},
        model::{ModelInfo, ModelTransportProfile},
    };
    use pl_model_runtime::runtime::{ModelInvocationContext, ModelRuntime};
    let body = events
        .into_iter()
        .map(|event| format!("data: {event}\n\n"))
        .collect::<String>()
        + "data: [DONE]\n\n";
    let (url, server) = loopback_response(200, Some("text/event-stream"), body).await;
    let mut endpoint =
        pl_model_openai::endpoint::compatible_endpoint("terminal diagnostic fixture", url);
    endpoint.bearer_token = Some(SYNTHETIC_BEARER.into());
    let mut model = ModelInfo::compatible("synthetic-model");
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    let runtime = ModelRuntime::bind("terminal-fixture", endpoint, model, None).unwrap();
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
    let Some(pl_model_openai_wire::completion::AssistantReplay::Responses { output }) =
        response.replay
    else {
        panic!("expected native replay material");
    };
    assert!(output.contains(&message));
    assert!(output.contains(&reasoning));
}
