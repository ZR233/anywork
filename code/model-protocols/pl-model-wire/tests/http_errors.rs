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

    let mut source = std::error::Error::source(&error);
    assert!(
        std::iter::from_fn(|| {
            let cause = source?;
            source = cause.source();
            Some(cause)
        })
        .any(|cause| cause.is::<tokio::time::error::Elapsed>())
    );

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
                        (200, PureError::Provider(failure)) => {
                            assert_eq!(failure.kind, ProviderFailureKind::Protocol);
                            assert!(failure.message.contains("expected text/event-stream"));
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

#[test]
fn http_retry_headers_keep_the_largest_constraint_at_the_original_observation() {
    use pl_model_wire::provider_error::{
        ClassifiedProviderError, ErrorObservedAt, ObservedRetry, ProviderErrorContext, RetryHint,
    };
    use pl_model_wire::transport::response_failure;
    use pl_protocol::ProviderFailureStage;
    use reqwest::header::{HeaderMap, HeaderValue, RETRY_AFTER};

    let received = ErrorObservedAt {
        wall: httpdate::parse_http_date("Sun, 06 Nov 1994 08:49:37 GMT").unwrap(),
        monotonic: std::time::Instant::now(),
    };
    for (seconds_or_date, millis, expected) in [
        (
            "Sun, 06 Nov 1994 08:50:22 GMT",
            "125",
            RetryDisposition::Retryable {
                retry_after_ms: Some(45_000),
            },
        ),
        (
            "2",
            "45001",
            RetryDisposition::Retryable {
                retry_after_ms: Some(45_001),
            },
        ),
        (
            "Sun, 06 Nov 1994 08:49:36 GMT",
            "0",
            RetryDisposition::Retryable {
                retry_after_ms: Some(0),
            },
        ),
        (
            "184467440737095516160",
            "2",
            RetryDisposition::WaitUnrepresentable,
        ),
    ] {
        let mut headers = HeaderMap::new();
        headers.insert(RETRY_AFTER, HeaderValue::from_static(seconds_or_date));
        headers.insert("retry-after-ms", HeaderValue::from_static(millis));
        let context = ProviderErrorContext {
            stage: ProviderFailureStage::Request,
            request_id: Some("req-later"),
            http_status: Some(503),
            observed_at: ErrorObservedAt {
                wall: received.wall + Duration::from_secs(5),
                monotonic: received.monotonic + Duration::from_secs(5),
            },
            header_retry: ObservedRetry::from_headers(&headers, received),
            redact: &str::to_owned,
        };
        let failure = response_failure(None, b"<html>temporary gateway failure</html>", &context);
        assert_eq!(failure.retry, expected, "{seconds_or_date} and {millis}");
        assert_eq!(failure.observed_at_unix_ms, Some(784_111_777_000));
        let deadline = expected
            .retry_after_ms()
            .map(|ms| received.monotonic + Duration::from_millis(ms));
        assert_eq!(failure.retry_deadline(), deadline);
        let error = PureError::from(failure.clone());
        assert_eq!(
            error.provider_failure_ref().unwrap().retry_deadline(),
            deadline
        );
        let persisted = serde_json::to_string(&failure).unwrap();
        let decoded: pl_protocol::ProviderFailure = serde_json::from_str(&persisted).unwrap();
        assert_eq!(decoded, failure);
        assert_eq!(decoded.retry_deadline(), None);
    }

    // A 42s body hint received 5s later wins over a 45s header hint.
    let body_received = ErrorObservedAt {
        wall: received.wall + Duration::from_secs(5),
        monotonic: received.monotonic + Duration::from_secs(5),
    };
    let mut error = ClassifiedProviderError::from_http_status(Some(503));
    error.retry_hint = RetryHint::from_millis("42000");
    let failure = error.into_failure(&ProviderErrorContext {
        stage: ProviderFailureStage::Request,
        request_id: Some("req-later"),
        http_status: Some(503),
        observed_at: body_received,
        header_retry: RetryHint::from_millis("45000").observed(received),
        redact: &str::to_owned,
    });
    assert_eq!(failure.observed_at_unix_ms, Some(784_111_782_000));
    assert_eq!(failure.retry.retry_after_ms(), Some(42_000));
    assert_eq!(
        failure.retry_deadline(),
        Some(received.monotonic + Duration::from_secs(47))
    );
}
