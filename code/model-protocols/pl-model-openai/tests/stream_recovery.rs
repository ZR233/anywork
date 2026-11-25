//! Loopback coverage for provider terminal events and usage across retries.

use pl_model_openai::adapter::ADAPTER;
use pl_model_runtime::runtime::{ModelInvocationContext, ModelRuntime, ModelSubAttemptReceipt};
use pl_model_wire::completion::{
    CompletionFailure, CompletionRequest, CompletionResponse, Message, MessageContent, MessageRole,
};
use pl_model_wire::model::{ModelDefinition, ModelTransportProfile};
use pl_protocol::ProviderFailureKind as Kind;
use std::{cell::Cell, time::Duration};
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    net::TcpListener,
};

struct Reply<'a> {
    frames: &'a str,
    disconnect: bool,
}

async fn complete(
    transport: ModelTransportProfile,
    replies: &[Reply<'_>],
) -> Result<CompletionResponse, CompletionFailure> {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let endpoint = pl_model_openai::endpoint::endpoint(Some(format!(
        "http://{}",
        listener.local_addr().unwrap()
    )));
    let mut model = ModelDefinition::compatible("fixture");
    model.extra.binding.set_transport(transport);
    let runtime = ModelRuntime::bind(
        "fixture",
        endpoint,
        model,
        ADAPTER.codec,
        ADAPTER.error_policy,
        None,
    )
    .unwrap();
    let request = CompletionRequest::builder()
        .messages(vec![Message {
            role: MessageRole::User,
            content: MessageContent::text("Check this sample"),
            presentation: Default::default(),
            reasoning_content: None,
            tool_calls: None,
            tool_result: None,
            metadata: Default::default(),
        }])
        .build();

    let served = Cell::new(0);
    let server = async {
        for reply in replies {
            let (socket, _) = listener.accept().await.unwrap();
            let mut socket = BufReader::new(socket);
            let mut content_length = None;
            loop {
                let mut header = String::new();
                assert_ne!(socket.read_line(&mut header).await.unwrap(), 0);
                if header == "\r\n" {
                    break;
                }
                if let Some((name, value)) = header.split_once(':')
                    && name.eq_ignore_ascii_case("content-length")
                {
                    content_length = Some(value.trim().parse::<usize>().unwrap());
                }
            }
            let length = content_length.unwrap();
            assert!(length < 16_384);
            socket.read_exact(&mut vec![0; length]).await.unwrap();
            served.set(served.get() + 1);
            socket.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\nRetry-After-Ms: 0\r\n\r\n").await.unwrap();
            socket
                .write_all(format!("{:x}\r\n{}\r\n", reply.frames.len(), reply.frames).as_bytes())
                .await
                .unwrap();
            if !reply.disconnect {
                socket.write_all(b"0\r\n\r\n").await.unwrap();
            }
            socket.shutdown().await.unwrap();
        }
        listener.accept().await.unwrap();
        panic!("the model sent an unexpected additional request");
    };
    let result = tokio::time::timeout(Duration::from_secs(10), async {
        tokio::select! {
            biased;
            _ = server => unreachable!(),
            result = runtime.complete(request, ModelInvocationContext::in_memory(Default::default())) => result,
        }
    })
    .await
    .expect("loopback completion finishes");
    assert_eq!(served.get(), replies.len());
    result
}

#[tokio::test]
async fn chat_output_limit_stays_primary_through_a_late_error_or_disconnect() {
    use pl_protocol::{ProviderFailure, PureError};
    use std::error::Error;

    const LIMIT: &str =
        "data: {\"id\":\"chat\",\"choices\":[{\"delta\":{},\"finish_reason\":\"length\"}]}\n\n";
    let late = format!(
        "{LIMIT}data: {{\"type\":\"error\",\"error\":{{\"code\":\"server_error\"}},\"usage\":{{\"prompt_tokens\":11}}}}\n\n"
    );
    for (tail, secondary_json) in [
        ("{invalid JSON}", true),
        ("[]", false),
        (r#"{"choices":[42]}"#, true),
        (r#"{"choices":[],"usage":{"prompt_tokens":"bad"}}"#, true),
    ] {
        let frames = format!("{LIMIT}data: {tail}\n\n");
        let failure = complete(
            ModelTransportProfile::chat_completions_http(),
            &[Reply {
                frames: &frames,
                disconnect: false,
            }],
        )
        .await
        .unwrap_err();
        let provider = failure.source.provider_failure_ref().unwrap();
        assert_eq!(provider.kind, Kind::OutputLimit, "{tail}");
        assert_eq!(provider.message, "provider stopped generation: length");
        assert!(!provider.retry.is_retryable());
        let cause = provider.source().unwrap();
        let cause = cause
            .downcast_ref::<ProviderFailure>()
            .or_else(|| cause.downcast_ref::<PureError>()?.provider_failure_ref())
            .unwrap();
        assert_eq!(cause.kind, Kind::Protocol);
        assert_eq!(
            cause
                .source()
                .is_some_and(|source| source.is::<serde_json::Error>()),
            secondary_json
        );
    }
    for (frames, disconnect, usage) in [(late.as_str(), false, Some(11)), (LIMIT, true, None)] {
        let failure = complete(
            ModelTransportProfile::chat_completions_http(),
            &[Reply { frames, disconnect }],
        )
        .await
        .unwrap_err();
        let provider = failure.source.provider_failure_ref().unwrap();
        assert_eq!(provider.kind, Kind::OutputLimit);
        assert_eq!(provider.message, "provider stopped generation: length");
        assert!(!provider.retry.is_retryable());
        assert_eq!(failure.accounting.usage.input_tokens, usage);
        assert_eq!(failure.usage_is_terminal, usage.is_some());
        assert_eq!(failure.settlements.len(), 1);
        let cause = provider.source().unwrap();
        let cause = cause
            .downcast_ref::<ProviderFailure>()
            .or_else(|| cause.downcast_ref::<PureError>()?.provider_failure_ref())
            .unwrap();
        assert_eq!(
            cause.kind,
            if disconnect {
                Kind::Transport
            } else {
                Kind::ServiceBusy
            }
        );
        if disconnect {
            assert!(
                cause
                    .source()
                    .is_some_and(|source| source.is::<reqwest::Error>())
            );
        }
    }
}

#[tokio::test]
async fn responses_intermediate_usage_survives_disconnect_and_terminal_failure() {
    const PARTIAL: &str = concat!(
        "data: {\"type\":\"response.in_progress\",\"response\":{\"id\":\"first\",\"usage\":{\"input_tokens\":7}}}\n\n",
        "data: {\"type\":\"response.in_progress\",\"response\":{\"id\":\"first\",\"usage\":{}}}\n\n",
    );
    const COMPLETE: &str = "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"second\",\"status\":\"completed\"}}\n\n";
    let failed = format!(
        "{PARTIAL}data: {{\"type\":\"response.failed\",\"response\":{{\"id\":\"first\",\"status\":\"failed\",\"error\":{{\"code\":\"insufficient_quota\"}}}}}}\n\n"
    );
    let failure = complete(
        ModelTransportProfile::responses_http(),
        &[Reply {
            frames: &failed,
            disconnect: false,
        }],
    )
    .await
    .unwrap_err();
    assert_eq!(
        failure.source.provider_failure_ref().unwrap().kind,
        Kind::Quota
    );
    assert_eq!(failure.accounting.usage.input_tokens, Some(7));
    assert!(!failure.usage_is_terminal);

    let response = complete(
        ModelTransportProfile::responses_http(),
        &[
            Reply {
                frames: PARTIAL,
                disconnect: true,
            },
            Reply {
                frames: COMPLETE,
                disconnect: false,
            },
        ],
    )
    .await
    .unwrap();
    assert_eq!(response.settlements.len(), 2);
    let receipt: ModelSubAttemptReceipt =
        serde_json::from_str(response.settlements[0].content()).unwrap();
    assert_eq!(receipt.provider_failure.unwrap().kind, Kind::Transport);
    assert_eq!(receipt.billing.accounting.usage.input_tokens, Some(7));
    assert!(!receipt.billing.attempt.unwrap().usage_is_terminal);
    assert_eq!(response.accounting.usage.input_tokens, None);
    assert!(!response.usage_is_terminal);
}

#[tokio::test]
async fn contradictory_responses_completion_is_rejected_without_resending() {
    for (frames, kind) in [
        (
            "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"wrong\",\"status\":\"failed\",\"error\":{\"code\":\"insufficient_quota\"}}}\n\n",
            Kind::Quota,
        ),
        (
            "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"wrong\",\"status\":42}}\n\n",
            Kind::Protocol,
        ),
    ] {
        let failure = complete(
            ModelTransportProfile::responses_http(),
            &[Reply {
                frames,
                disconnect: false,
            }],
        )
        .await
        .unwrap_err();
        let provider = failure.source.provider_failure_ref().unwrap();
        assert_eq!(provider.kind, kind);
        assert!(!provider.retry.is_retryable());
    }
}
