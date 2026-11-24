use std::time::Duration;

use pl_model_wire::transport::checked;
use pl_protocol::{ProviderFailureKind, PureError, RetryDisposition};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[tokio::test]
async fn stalled_authentication_error_body_preserves_status_and_retry_policy() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/responses", listener.local_addr().unwrap());
    let (release, wait) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        let mut headers = Vec::new();
        while !headers.ends_with(b"\r\n\r\n") {
            headers.push(socket.read_u8().await.unwrap());
            assert!(headers.len() <= 4096);
        }
        socket
            .write_all(b"HTTP/1.1 401 Unauthorized\r\nContent-Length: 100\r\n\r\n{\"error\":")
            .await
            .unwrap();
        wait.await.unwrap();
    });
    let response = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(5))
        .build()
        .unwrap()
        .get(url)
        .send()
        .await
        .unwrap();

    tokio::time::pause();
    let result = checked(response);
    tokio::pin!(result);
    assert!(futures::poll!(&mut result).is_pending());
    tokio::time::advance(Duration::from_secs(14)).await;
    assert!(futures::poll!(&mut result).is_pending());
    tokio::time::advance(Duration::from_secs(2)).await;
    let error = result.await.unwrap_err();
    tokio::time::resume();
    release.send(()).unwrap();
    server.await.unwrap();

    let PureError::Provider(failure) = error else {
        panic!("expected a classified provider error, got {error}");
    };
    assert_eq!(failure.http_status, Some(401));
    assert_eq!(failure.kind, ProviderFailureKind::Authentication);
    assert_eq!(failure.retry, RetryDisposition::Permanent);
    assert!(
        failure
            .message
            .contains("error response body read deadline exceeded"),
        "{}",
        failure.message
    );
}

#[tokio::test]
async fn chatgpt_content_type_policy_only_relaxes_an_absent_header() {
    use futures::TryStreamExt;
    use pl_model_wire::transport::{SseContentTypePolicy, sse_frames};

    for policy in [
        SseContentTypePolicy::Required,
        SseContentTypePolicy::AllowMissingForChatGpt,
    ] {
        for (status, content_type, expected) in [
            (
                200,
                "Content-Type: text/event-stream; charset=utf-8\r\n",
                true,
            ),
            (200, "Content-Type: application/json\r\n", false),
            (
                200,
                "",
                matches!(policy, SseContentTypePolicy::AllowMissingForChatGpt),
            ),
            (401, "", false),
        ] {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let url = format!("http://{}/responses", listener.local_addr().unwrap());
            let server = tokio::spawn(async move {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut headers = Vec::new();
                while !headers.ends_with(b"\r\n\r\n") {
                    headers.push(socket.read_u8().await.unwrap());
                    assert!(headers.len() <= 4096);
                }
                let body = "data: {\"type\":\"response.completed\"}\n\n";
                let response = format!(
                    "HTTP/1.1 {status} Fixture\r\n{content_type}Content-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                socket.write_all(response.as_bytes()).await.unwrap();
            });
            let result = sse_frames(reqwest::Client::new().get(url), policy, None).await;
            match result {
                Ok(mut stream) => {
                    assert!(
                        expected,
                        "unexpected SSE admission for {status} {content_type:?}"
                    );
                    assert!(stream.try_next().await.unwrap().is_some());
                }
                Err(error) => {
                    assert!(!expected, "unexpected SSE rejection: {error}");
                    match (status, error) {
                        (200, PureError::Protocol(message)) => {
                            assert!(message.contains("expected text/event-stream"));
                        }
                        (401, PureError::Provider(failure)) => {
                            assert_eq!(failure.kind, ProviderFailureKind::Authentication);
                        }
                        (status, error) => panic!("unexpected HTTP {status} failure: {error}"),
                    }
                }
            }
            server.await.unwrap();
        }
    }
}
