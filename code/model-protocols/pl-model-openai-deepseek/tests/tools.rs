//! DeepSeek Search、Fetch 和 Files 公开 API 的 loopback 测试。
//!
//! 全部用例通过真实 loopback HTTP 服务驱动 [`ToolsClient`]，只消费公开类型；不访问任何真实
//! 供应商，也不断言线上兼容性。

use std::{collections::HashMap, error::Error, sync::Arc, time::Duration};

use base64::Engine;
use pl_model_openai_deepseek::tools::{
    CancellationToken, FetchRequest, FetchResponse, Observed, SearchRequest, ToolsClient,
    ToolsError, ToolsOptions,
};
use pl_model_openai_deepseek::upload::upload_file;
use pl_model_wire::{
    completion::{AttachmentInput, AttachmentModality, AttachmentSource},
    files::{FileUploadFailure, FileUploadRequest, UploadFailureOutcome, UploadedFile},
    protocol::ProtocolEndpoint,
};
use pl_protocol::{ProviderFailureKind as Kind, ProviderFailureStage};
use serde_json::{Value, json};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::sync::mpsc;

/// 一次 loopback 响应脚本。
enum Reply {
    Json {
        status: u16,
        body: Value,
    },
    Raw {
        status: u16,
        content_type: &'static str,
        body: Vec<u8>,
    },
    Redirect {
        status: u16,
        location: String,
    },
    /// 只发送响应头与声明的 Content-Length，正文永远不到达。
    HeadersOnly {
        status: u16,
        declared_length: usize,
    },
    Upload {
        status: u16,
        body: &'static str,
        headers: &'static [(&'static str, &'static str)],
        extra_declared_bytes: usize,
    },
    Disconnect,
    UnexpectedRequest,
    /// 接受连接并读取请求，但永不响应。
    Hang,
}

struct MockServer {
    base_url: String,
    requests: mpsc::UnboundedReceiver<String>,
    task: Option<tokio::task::JoinHandle<()>>,
}

impl MockServer {
    fn base_url(&self) -> String {
        self.base_url.clone()
    }

    async fn request(&mut self) -> String {
        self.requests
            .recv()
            .await
            .expect("mock server did not capture a request")
    }

    async fn assert_no_request(&mut self) {
        if tokio::time::timeout(Duration::from_millis(200), self.requests.recv())
            .await
            .is_ok()
        {
            panic!("expected no HTTP request to be dispatched");
        }
    }

    async fn finish(mut self) {
        if let Some(task) = self.task.take() {
            task.await.expect("mock server task panicked");
        }
    }

    fn abort(&mut self) {
        if let Some(task) = self.task.take() {
            task.abort();
        }
    }

    async fn finish_upload(mut self, expect_post: bool) {
        if expect_post {
            let request = tokio::time::timeout(Duration::from_secs(3), self.request())
                .await
                .expect("upload POST was captured");
            assert!(request.starts_with("POST /files HTTP/1.1\r\n"));
            assert_eq!(
                header(&request, "authorization").as_deref(),
                Some("Bearer fixture-upload-credential")
            );
            assert!(request.contains("name=\"purpose\"\r\n\r\nuser_data\r\n"));
            assert!(request.contains("name=\"expires_after[seconds]\"\r\n\r\n86400\r\n"));
        }
        assert!(
            self.requests.try_recv().is_err(),
            "unexpected upload submission"
        );
        let task = self.task.take().unwrap();
        task.abort();
        let error = task
            .await
            .expect_err("fixture waits for an unexpected request");
        assert!(
            error.is_cancelled(),
            "unexpected upload submission: {error}"
        );
    }
}

impl Drop for MockServer {
    fn drop(&mut self) {
        self.abort();
    }
}

async fn mock_server(reply: Reply) -> MockServer {
    mock_server_sequence(vec![reply]).await
}

async fn mock_server_sequence(replies: Vec<Reply>) -> MockServer {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base_url = format!("http://{}", listener.local_addr().unwrap());
    let (sender, requests) = mpsc::unbounded_channel();
    let task = tokio::spawn(async move {
        for reply in replies {
            let (mut socket, _) = listener.accept().await.expect("accept");
            socket.set_nodelay(true).unwrap();
            let captured = read_request(&mut socket).await;
            let _ = sender.send(String::from_utf8_lossy(&captured).into_owned());
            match reply {
                Reply::Json { status, body } => {
                    let payload = serde_json::to_vec(&body).unwrap();
                    write_response(&mut socket, status, "application/json", &payload).await;
                }
                Reply::Raw {
                    status,
                    content_type,
                    body,
                } => {
                    write_response(&mut socket, status, content_type, &body).await;
                }
                Reply::Redirect { status, location } => {
                    let head = format!(
                        "HTTP/1.1 {status} {}\r\nLocation: {location}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                        reason(status),
                    );
                    socket.write_all(head.as_bytes()).await.unwrap();
                    socket.flush().await.unwrap();
                    if tokio::time::timeout(Duration::from_millis(200), listener.accept())
                        .await
                        .is_ok()
                    {
                        panic!("server received a second request after redirect");
                    }
                }
                Reply::HeadersOnly {
                    status,
                    declared_length,
                } => {
                    let head = format!(
                        "HTTP/1.1 {status} {}\r\nContent-Type: application/json\r\nContent-Length: {declared_length}\r\nConnection: close\r\n\r\n",
                        reason(status),
                    );
                    socket.write_all(head.as_bytes()).await.unwrap();
                    socket.flush().await.unwrap();
                    tokio::time::sleep(Duration::from_secs(300)).await;
                }
                Reply::Upload {
                    status,
                    body,
                    headers,
                    extra_declared_bytes,
                } => {
                    write_response_with_headers(
                        &mut socket,
                        status,
                        "application/json",
                        body.as_bytes(),
                        body.len() + extra_declared_bytes,
                        headers,
                    )
                    .await;
                }
                Reply::Disconnect => {}
                Reply::UnexpectedRequest => panic!("unexpected HTTP request"),
                Reply::Hang => {
                    tokio::time::sleep(Duration::from_secs(300)).await;
                }
            }
        }
    });
    MockServer {
        base_url,
        requests,
        task: Some(task),
    }
}

async fn read_request(socket: &mut tokio::net::TcpStream) -> Vec<u8> {
    let mut request = Vec::new();
    let mut buffer = [0u8; 4096];
    loop {
        let count = socket.read(&mut buffer).await.unwrap();
        if count == 0 {
            break;
        }
        request.extend_from_slice(&buffer[..count]);
        if let Some(end) = request.windows(4).position(|window| window == b"\r\n\r\n") {
            let headers = String::from_utf8_lossy(&request[..end]).to_ascii_lowercase();
            let length = headers
                .lines()
                .find_map(|line| line.strip_prefix("content-length: "))
                .and_then(|value| value.trim().parse::<usize>().ok())
                .unwrap_or(0);
            if request.len() >= end + 4 + length {
                break;
            }
        }
    }
    request
}

async fn write_response(
    socket: &mut tokio::net::TcpStream,
    status: u16,
    content_type: &str,
    body: &[u8],
) {
    write_response_with_headers(socket, status, content_type, body, body.len(), &[]).await;
}

async fn write_response_with_headers(
    socket: &mut tokio::net::TcpStream,
    status: u16,
    content_type: &str,
    body: &[u8],
    declared_length: usize,
    headers: &[(&str, &str)],
) {
    use std::fmt::Write;

    let mut head = format!(
        "HTTP/1.1 {status} {}\r\nContent-Type: {content_type}\r\nContent-Length: {declared_length}\r\nConnection: close\r\n",
        reason(status),
    );
    for (name, value) in headers {
        write!(&mut head, "{name}: {value}\r\n").unwrap();
    }
    head.push_str("\r\n");
    socket.write_all(head.as_bytes()).await.unwrap();
    socket.write_all(body).await.unwrap();
    socket.flush().await.unwrap();
}

fn reason(status: u16) -> &'static str {
    match status {
        200 => "OK",
        201 => "Created",
        302 => "Found",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        _ => "Status",
    }
}

fn endpoint(base_url: impl Into<String>, credential: Option<&str>) -> ProtocolEndpoint {
    let mut endpoint = pl_model_openai_deepseek::endpoint::endpoint(Some(base_url.into()));
    endpoint.bearer_token = credential.map(str::to_string);
    endpoint
}

fn header(request: &str, name: &str) -> Option<String> {
    request.lines().find_map(|line| {
        let (key, value) = line.split_once(':')?;
        key.eq_ignore_ascii_case(name)
            .then_some(value.trim().to_string())
    })
}

fn body_json(request: &str) -> Value {
    let (_, body) = request.split_once("\r\n\r\n").expect("request body");
    serde_json::from_str(body).expect("request body is JSON")
}

fn search_request(query: impl Into<String>) -> SearchRequest {
    SearchRequest {
        query: query.into(),
    }
}

fn fetch_request(url: impl Into<String>) -> FetchRequest {
    FetchRequest { url: url.into() }
}

fn sources_response() -> Value {
    json!({
        "results": [
            {
                "url": "https://example.com/a",
                "title": "A",
                "snippet": "alpha excerpt",
                "date": "2024-01-01",
                "summary": "do not consume",
                "content": "full page",
                "site_name": "Example",
                "site_icon": "https://example.com/icon.png",
                "rerank_score": 0.9,
                "authority": "high"
            },
            {
                "url": "https://example.com/b",
                "title": "B",
                "snippet": "beta excerpt",
                "date": null
            },
            {
                "url": "https://example.com/a",
                "title": "A duplicate",
                "snippet": "",
                "date": ""
            }
        ]
    })
}

fn fetch_response() -> Value {
    json!({
        "title": "Fetched page",
        "content": "markdown body"
    })
}

fn observed_raw(error: &ToolsError) -> &Value {
    match error.observed_response().expect("observed response") {
        Observed::Search(response) => &response.raw_response,
        Observed::Fetch(response) => &response.raw_response,
    }
}

/// 断言已完整收到的非 JSON 正文以 base64 约定无损留存，并返回解码后的原始字节。
fn observed_raw_body(error: &ToolsError) -> Vec<u8> {
    let raw = observed_raw(error);
    assert_eq!(
        raw["encoding"],
        Value::String("base64".to_string()),
        "non-JSON bodies are keyed by their encoding"
    );
    if let Observed::Search(response) = error.observed_response().unwrap() {
        assert!(
            response.sources.is_empty(),
            "an unparsed body must not fabricate sources"
        );
    }
    let data = raw["data"].as_str().expect("base64 data payload");
    base64::engine::general_purpose::STANDARD
        .decode(data)
        .expect("valid base64 payload")
}

fn client_for(server: &MockServer) -> ToolsClient {
    ToolsClient::new(
        &endpoint(server.base_url(), Some("k")),
        ToolsOptions::default(),
    )
    .unwrap()
}

/// `ToolsClient` 只从 provider base_url 派生一对官方工具端点：保留自定义 path 前缀、归一化
/// canonical `/v1` 版本别名；已指向 `/anthropic` 或 `/anthropic/v1` 时明确拒绝。
#[test]
fn deepseek_tools_derives_endpoints_from_provider_base_url() {
    let expected_search = "https://api.deepseek.com/v1/tools/search";
    let expected_fetch = "https://api.deepseek.com/v1/tools/fetch";
    for base in [
        "https://api.deepseek.com",
        "https://api.deepseek.com/",
        "https://api.deepseek.com/v1",
        "https://api.deepseek.com/v1/",
    ] {
        let mut endpoint = pl_model_openai_deepseek::endpoint::endpoint(Some(base.to_string()));
        endpoint.bearer_token = Some("k".to_string());
        let client = ToolsClient::new(&endpoint, ToolsOptions::default()).unwrap();
        assert_eq!(client.search_endpoint(), expected_search, "base url {base}");
        assert_eq!(client.fetch_endpoint(), expected_fetch, "base url {base}");
    }

    let mut endpoint = pl_model_openai_deepseek::endpoint::endpoint(Some(
        "https://proxy.example.com/proxy".to_string(),
    ));
    endpoint.bearer_token = Some("k".to_string());
    let client = ToolsClient::new(&endpoint, ToolsOptions::default()).unwrap();
    assert_eq!(
        client.search_endpoint(),
        "https://proxy.example.com/proxy/v1/tools/search"
    );
    assert_eq!(
        client.fetch_endpoint(),
        "https://proxy.example.com/proxy/v1/tools/fetch"
    );

    let mut endpoint = pl_model_openai_deepseek::endpoint::endpoint(Some(
        "http://127.0.0.1:8080/proxy/v1".to_string(),
    ));
    endpoint.bearer_token = Some("k".to_string());
    let client = ToolsClient::new(&endpoint, ToolsOptions::default()).unwrap();
    assert_eq!(
        client.search_endpoint(),
        "http://127.0.0.1:8080/proxy/v1/tools/search"
    );
    assert_eq!(
        client.fetch_endpoint(),
        "http://127.0.0.1:8080/proxy/v1/tools/fetch"
    );
}

#[test]
fn deepseek_tools_rejects_anthropic_compatible_base_urls() {
    for base in [
        "https://api.deepseek.com/anthropic",
        "https://api.deepseek.com/anthropic/",
        "https://api.deepseek.com/anthropic/v1",
        "https://api.deepseek.com/anthropic/v1/",
        "https://proxy.example.com/proxy/anthropic",
        "http://127.0.0.1:8080/proxy/anthropic/v1",
    ] {
        let mut endpoint = pl_model_openai_deepseek::endpoint::endpoint(Some(base.to_string()));
        endpoint.bearer_token = Some("k".to_string());
        let result = ToolsClient::new(&endpoint, ToolsOptions::default());
        match result {
            Err(ToolsError::Config { message }) => {
                assert!(
                    message.contains("official tools API") || message.contains("API root"),
                    "base url {base} should mention the official tools API, got {message}"
                );
            }
            other => panic!("base url {base} should be rejected, got {other:?}"),
        }
    }
}

/// 无效地址在发出任何请求前被拒绝，且绝不回退到官方域名。
#[test]
fn deepseek_tools_rejects_invalid_base_urls() {
    for base in [
        "",
        "ftp://api.deepseek.com",
        "https://user:pass@api.deepseek.com",
        "https://api.deepseek.com?x=1",
        "https://api.deepseek.com#frag",
        "not a url",
        "https://",
    ] {
        let mut endpoint = pl_model_openai_deepseek::endpoint::endpoint(Some(base.to_string()));
        endpoint.bearer_token = Some("k".to_string());
        let result = ToolsClient::new(&endpoint, ToolsOptions::default());
        assert!(
            matches!(result, Err(ToolsError::Config { .. })),
            "base url {base:?} should be rejected"
        );
        if let Err(error) = result {
            let rendered = format!("{error:?}");
            assert!(!rendered.contains("api.deepseek.com") || base.contains("api.deepseek.com"));
        }
    }
}

/// `Debug` 输出不泄漏凭据，只展示解析出的端点。
#[test]
fn deepseek_tools_debug_does_not_leak_the_credential() {
    let mut endpoint =
        pl_model_openai_deepseek::endpoint::endpoint(Some("https://api.deepseek.com".to_string()));
    endpoint.bearer_token = Some("super-secret-token".to_string());
    let client = ToolsClient::new(&endpoint, ToolsOptions::default()).unwrap();
    let rendered = format!("{client:?}");
    assert!(!rendered.contains("super-secret-token"));
    assert!(rendered.contains("/v1/tools/search"));
    assert!(rendered.contains("/v1/tools/fetch"));
}

#[tokio::test]
async fn deepseek_tools_sends_search_wire_without_anthropic_headers() {
    let mut server = mock_server(Reply::Json {
        status: 200,
        body: sources_response(),
    })
    .await;
    let client = ToolsClient::new(
        &endpoint(format!("{}/proxy", server.base_url()), Some("secret-key")),
        ToolsOptions::default(),
    )
    .unwrap();
    let response = client
        .search(&search_request("  rust async  "), CancellationToken::new())
        .await
        .unwrap();

    let request = server.request().await;
    assert_eq!(
        request.lines().next().unwrap(),
        "POST /proxy/v1/tools/search HTTP/1.1"
    );
    assert_eq!(
        header(&request, "authorization").as_deref(),
        Some("Bearer secret-key")
    );
    assert!(header(&request, "x-api-key").is_none());
    assert!(header(&request, "anthropic-version").is_none());
    assert_eq!(
        header(&request, "content-type").as_deref(),
        Some("application/json")
    );
    assert_eq!(
        header(&request, "accept").as_deref(),
        Some("application/json")
    );

    let body = body_json(&request);
    let object = body.as_object().expect("search body object");
    assert_eq!(object.len(), 3);
    assert_eq!(body["query"], "rust async");
    assert_eq!(body["count"], 10);
    assert_eq!(body["need_content"], false);
    assert!(!response.sources.is_empty());
    server.finish().await;
}

#[tokio::test]
async fn deepseek_tools_sends_fetch_wire_with_only_url() {
    let mut server = mock_server(Reply::Json {
        status: 200,
        body: fetch_response(),
    })
    .await;
    let client = client_for(&server);
    let response = client
        .fetch(
            &fetch_request("https://example.com/page"),
            CancellationToken::new(),
        )
        .await
        .unwrap();

    let request = server.request().await;
    assert_eq!(
        request.lines().next().unwrap(),
        "POST /v1/tools/fetch HTTP/1.1"
    );
    assert_eq!(
        header(&request, "authorization").as_deref(),
        Some("Bearer k")
    );
    assert!(header(&request, "x-api-key").is_none());
    assert!(header(&request, "anthropic-version").is_none());
    let body = body_json(&request);
    let object = body.as_object().expect("fetch body object");
    assert_eq!(object.len(), 1);
    assert_eq!(body["url"], "https://example.com/page");
    assert_eq!(response.status, 200);
    assert_eq!(response.content, "markdown body");
    assert_eq!(response.title.as_deref(), Some("Fetched page"));
    server.finish().await;
}

#[tokio::test]
async fn deepseek_tools_search_dedupes_by_first_url_and_maps_optional_fields() {
    let server = mock_server(Reply::Json {
        status: 200,
        body: sources_response(),
    })
    .await;
    let client = client_for(&server);
    let response = client
        .search(&search_request("query"), CancellationToken::new())
        .await
        .unwrap();

    assert_eq!(response.sources.len(), 2);
    assert_eq!(response.sources[0].url, "https://example.com/a");
    assert_eq!(response.sources[0].title.as_deref(), Some("A"));
    assert_eq!(
        response.sources[0].snippet.as_deref(),
        Some("alpha excerpt")
    );
    assert_eq!(
        response.sources[0].published_at.as_deref(),
        Some("2024-01-01")
    );
    assert_eq!(response.sources[1].url, "https://example.com/b");
    assert_eq!(response.sources[1].title.as_deref(), Some("B"));
    assert_eq!(response.sources[1].snippet.as_deref(), Some("beta excerpt"));
    assert!(response.sources[1].published_at.is_none());
    assert_eq!(
        response.raw_response["results"][0]["summary"],
        "do not consume"
    );
    server.finish().await;
}

#[tokio::test]
async fn deepseek_tools_search_accepts_a_legal_empty_result_array() {
    let server = mock_server(Reply::Json {
        status: 200,
        body: json!({ "results": [] }),
    })
    .await;
    let client = client_for(&server);
    let response = client
        .search(&search_request("query"), CancellationToken::new())
        .await
        .unwrap();
    assert!(response.sources.is_empty());
    assert_eq!(response.raw_response["results"], json!([]));
    server.finish().await;
}

/// search 侧空串与 `null` 必须归一为缺失，且该来源不得被 URL 去重丢弃。
#[tokio::test]
async fn deepseek_tools_search_normalizes_blank_strings_to_none() {
    let server = mock_server(Reply::Json {
        status: 200,
        body: json!({
            "results": [
                {
                    "url": "https://example.com/blank",
                    "title": "",
                    "snippet": "",
                    "date": ""
                },
                {
                    "url": "https://example.com/null-date",
                    "title": "Has title",
                    "snippet": "Has snippet",
                    "date": null
                }
            ]
        }),
    })
    .await;
    let client = client_for(&server);
    let response = client
        .search(&search_request("query"), CancellationToken::new())
        .await
        .unwrap();

    assert_eq!(response.sources.len(), 2);
    assert_eq!(response.sources[0].url, "https://example.com/blank");
    assert!(response.sources[0].title.is_none());
    assert!(response.sources[0].snippet.is_none());
    assert!(response.sources[0].published_at.is_none());
    assert_eq!(response.sources[1].url, "https://example.com/null-date");
    assert_eq!(response.sources[1].title.as_deref(), Some("Has title"));
    assert_eq!(response.sources[1].snippet.as_deref(), Some("Has snippet"));
    assert!(response.sources[1].published_at.is_none());
    server.finish().await;
}

#[tokio::test]
async fn deepseek_tools_search_fails_on_malformed_results() {
    for body in [
        json!({ "ok": true }),
        json!({ "results": { "url": "https://example.com" } }),
        json!({ "results": ["https://example.com"] }),
        json!({ "results": [{ "url": "" }] }),
        json!({ "results": [{ "title": "A" }] }),
        json!({ "results": [{ "url": "https://example.com", "title": 1 }] }),
        json!({ "results": [{ "url": "https://example.com", "snippet": true }] }),
        json!({ "results": [{ "url": "https://example.com", "date": 2024 }] }),
    ] {
        let server = mock_server(Reply::Json {
            status: 200,
            body: body.clone(),
        })
        .await;
        let client = client_for(&server);
        let error = client
            .search(&search_request("query"), CancellationToken::new())
            .await
            .unwrap_err();
        assert!(
            matches!(error, ToolsError::MalformedResults { .. }),
            "expected MalformedResults for {body}"
        );
        assert_eq!(observed_raw(&error), &body);
        server.finish().await;
    }
}

#[tokio::test]
async fn deepseek_tools_fetch_succeeds_and_treats_empty_title_as_missing() {
    let server = mock_server(Reply::Json {
        status: 200,
        body: json!({ "title": "", "content": "body" }),
    })
    .await;
    let client = client_for(&server);
    let response: FetchResponse = client
        .fetch(
            &fetch_request("https://example.com"),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    assert_eq!(response.status, 200);
    assert!(response.title.is_none());
    assert_eq!(response.content, "body");
    server.finish().await;
}

#[tokio::test]
async fn deepseek_tools_fetch_preserves_non_200_success_status() {
    let server = mock_server(Reply::Json {
        status: 201,
        body: json!({ "title": "Created", "content": "created body" }),
    })
    .await;
    let client = client_for(&server);
    let response = client
        .fetch(
            &fetch_request("https://example.com/created"),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    assert_eq!(response.status, 201);
    assert_eq!(response.title.as_deref(), Some("Created"));
    assert_eq!(response.content, "created body");
    server.finish().await;
}

#[tokio::test]
async fn deepseek_tools_fetch_fails_without_string_content() {
    for body in [json!({ "title": "Page" }), json!({ "content": 1 })] {
        let server = mock_server(Reply::Json {
            status: 200,
            body: body.clone(),
        })
        .await;
        let client = client_for(&server);
        let error = client
            .fetch(
                &fetch_request("https://example.com"),
                CancellationToken::new(),
            )
            .await
            .unwrap_err();
        assert!(matches!(error, ToolsError::MissingContent { .. }));
        match error.observed_response() {
            Some(Observed::Fetch(observed)) => assert_eq!(observed.status, 200),
            other => panic!("expected Observed::Fetch, got {other:?}"),
        }
        assert_eq!(observed_raw(&error), &body);
        server.finish().await;
    }
}

/// 完整收到但非 JSON 的 HTTP 失败正文必须无损留存：`Display` 错误有界，`observed_response`
/// 保留完整原始字节，且不伪造来源。
#[tokio::test]
async fn deepseek_tools_preserves_a_long_non_json_http_failure_body() {
    let body = format!("upstream boom {}", "x".repeat(4096));
    let server = mock_server(Reply::Raw {
        status: 500,
        content_type: "text/plain",
        body: body.clone().into_bytes(),
    })
    .await;
    let client = client_for(&server);
    let error = client
        .search(&search_request("query"), CancellationToken::new())
        .await
        .unwrap_err();
    match &error {
        ToolsError::HttpStatus {
            status, message, ..
        } => {
            assert_eq!(*status, 500);
            assert!(message.chars().count() <= 512);
            assert!(!message.contains("x".repeat(600).as_str()));
        }
        other => panic!("expected HttpStatus, got {other:?}"),
    }
    assert!(format!("{error}").chars().count() < 800);
    assert_eq!(observed_raw_body(&error), body.into_bytes());
    server.finish().await;
}

/// 2xx 但正文不是合法 JSON：错误仍然失败，完整原始正文可从 `observed_response` 无损取得。
#[tokio::test]
async fn deepseek_tools_preserves_a_malformed_json_success_body() {
    let body = format!("{{ not json {}", "y".repeat(2048));
    let server = mock_server(Reply::Raw {
        status: 200,
        content_type: "application/json",
        body: body.clone().into_bytes(),
    })
    .await;
    let client = client_for(&server);
    let error = client
        .search(&search_request("query"), CancellationToken::new())
        .await
        .unwrap_err();
    assert!(matches!(error, ToolsError::InvalidResponse { .. }));
    assert_eq!(observed_raw_body(&error), body.into_bytes());
    server.finish().await;
}

/// 非 UTF-8 字节的完整正文同样无损留存：base64 载荷逐字节等于原始正文。
#[tokio::test]
async fn deepseek_tools_preserves_non_utf8_response_bytes() {
    let body = vec![0xff, 0xfe, 0x00, 0x80, b'o', b'k', 0xc3, 0x28, 0xa0, 0xa1];
    let server = mock_server(Reply::Raw {
        status: 200,
        content_type: "application/json",
        body: body.clone(),
    })
    .await;
    let client = client_for(&server);
    let error = client
        .search(&search_request("query"), CancellationToken::new())
        .await
        .unwrap_err();
    assert!(matches!(error, ToolsError::InvalidResponse { .. }));
    assert_eq!(observed_raw_body(&error), body);
    server.finish().await;
}

/// JSON error 详情同样有界，且仍然保留已解析的原始响应。
#[tokio::test]
async fn deepseek_tools_bounds_json_error_messages() {
    let server = mock_server(Reply::Json {
        status: 429,
        body: json!({ "error": { "message": "x".repeat(2000) } }),
    })
    .await;
    let client = client_for(&server);
    let error = client
        .search(&search_request("query"), CancellationToken::new())
        .await
        .unwrap_err();
    match &error {
        ToolsError::HttpStatus {
            status, message, ..
        } => {
            assert_eq!(*status, 429);
            assert_eq!(message.chars().count(), 512);
            assert_eq!(*message, "x".repeat(512));
        }
        other => panic!("expected HttpStatus, got {other:?}"),
    }
    assert!(error.observed_response().is_some());
    server.finish().await;
}

#[tokio::test]
async fn deepseek_tools_does_not_follow_redirects() {
    let mut server = mock_server(Reply::Redirect {
        status: 302,
        location: "https://example.com/elsewhere".to_string(),
    })
    .await;
    let client = client_for(&server);
    let error = client
        .search(&search_request("query"), CancellationToken::new())
        .await
        .unwrap_err();
    match &error {
        ToolsError::HttpStatus { status, .. } => assert_eq!(*status, 302),
        other => panic!("expected HttpStatus, got {other:?}"),
    }
    let request = server.request().await;
    assert_eq!(
        request.lines().next().unwrap(),
        "POST /v1/tools/search HTTP/1.1"
    );
    server.finish().await;
}

#[tokio::test]
async fn deepseek_tools_cancellation_aborts_before_headers() {
    let mut server = mock_server(Reply::Hang).await;
    let client = client_for(&server);
    let cancellation = CancellationToken::new();
    let search = tokio::spawn({
        let cancellation = cancellation.clone();
        async move { client.search(&search_request("query"), cancellation).await }
    });
    let _ = server.request().await;
    cancellation.cancel();
    let error = search.await.unwrap().unwrap_err();
    assert!(matches!(error, ToolsError::Cancelled { .. }));
    assert!(error.observed_response().is_none());
    server.abort();
}

#[tokio::test]
async fn deepseek_tools_cancellation_aborts_a_pending_body() {
    let mut server = mock_server(Reply::HeadersOnly {
        status: 200,
        declared_length: 64,
    })
    .await;
    let client = client_for(&server);
    let cancellation = CancellationToken::new();
    let search = tokio::spawn({
        let cancellation = cancellation.clone();
        async move { client.search(&search_request("query"), cancellation).await }
    });
    let _ = server.request().await;
    cancellation.cancel();
    let error = search.await.unwrap().unwrap_err();
    assert!(matches!(error, ToolsError::Cancelled { .. }));
    assert!(error.observed_response().is_none());
    server.abort();
}

#[tokio::test]
async fn deepseek_tools_timeout_covers_the_whole_request() {
    let mut server = mock_server(Reply::Hang).await;
    let options = ToolsOptions {
        timeout: Duration::from_millis(300),
        ..ToolsOptions::default()
    };
    let client = ToolsClient::new(&endpoint(server.base_url(), Some("k")), options).unwrap();
    let error = client
        .search(&search_request("query"), CancellationToken::new())
        .await
        .unwrap_err();
    assert!(matches!(error, ToolsError::Timeout { .. }));
    assert!(error.observed_response().is_none());
    server.abort();
}

#[tokio::test]
async fn deepseek_tools_requires_a_credential_without_dispatching() {
    let mut server = mock_server(Reply::Json {
        status: 200,
        body: sources_response(),
    })
    .await;
    let result = ToolsClient::new(&endpoint(server.base_url(), None), ToolsOptions::default());
    assert!(matches!(result, Err(ToolsError::MissingCredential)));
    server.assert_no_request().await;
    server.abort();
}

#[tokio::test]
async fn deepseek_tools_rejects_invalid_count_and_timeout_without_dispatching() {
    let mut server = mock_server(Reply::Json {
        status: 200,
        body: sources_response(),
    })
    .await;
    for options in [
        ToolsOptions {
            count: 0,
            ..ToolsOptions::default()
        },
        ToolsOptions {
            count: 51,
            ..ToolsOptions::default()
        },
        ToolsOptions {
            timeout: Duration::ZERO,
            ..ToolsOptions::default()
        },
    ] {
        let result = ToolsClient::new(&endpoint(server.base_url(), Some("k")), options);
        assert!(matches!(result, Err(ToolsError::Config { .. })));
    }
    server.assert_no_request().await;
    server.abort();
}

#[tokio::test]
async fn deepseek_tools_rejects_an_empty_query_without_dispatching() {
    let mut server = mock_server(Reply::Json {
        status: 200,
        body: sources_response(),
    })
    .await;
    let client = client_for(&server);
    let error = client
        .search(&search_request("   "), CancellationToken::new())
        .await
        .unwrap_err();
    assert!(matches!(error, ToolsError::EmptyQuery));
    server.assert_no_request().await;
    server.abort();
}

#[tokio::test]
async fn deepseek_tools_rejects_an_overlong_query_without_dispatching() {
    let mut server = mock_server(Reply::Json {
        status: 200,
        body: sources_response(),
    })
    .await;
    let client = client_for(&server);
    let error = client
        .search(&search_request("你".repeat(129)), CancellationToken::new())
        .await
        .unwrap_err();
    match &error {
        ToolsError::InvalidQuery { message } => {
            assert!(message.contains("128"));
        }
        other => panic!("expected InvalidQuery, got {other:?}"),
    }
    let display = error.to_string();
    assert!(
        display.starts_with("invalid deepseek tools query:"),
        "Display must name query, got {display}"
    );
    assert!(
        !display.to_ascii_lowercase().contains("url"),
        "Display must not mention url, got {display}"
    );
    server.assert_no_request().await;
    server.abort();
}

#[tokio::test]
async fn deepseek_tools_rejects_illegal_fetch_urls_without_dispatching() {
    let mut server = mock_server(Reply::Json {
        status: 200,
        body: fetch_response(),
    })
    .await;
    let client = client_for(&server);
    let overlong = format!("https://example.com/{}", "x".repeat(8193));
    for url in [
        "",
        "   ",
        "ftp://example.com",
        "https://user:pass@example.com",
        "ftp://user:pass@example.com",
        "not a url",
        overlong.as_str(),
    ] {
        let error = client
            .fetch(&fetch_request(url), CancellationToken::new())
            .await
            .unwrap_err();
        assert!(
            matches!(error, ToolsError::InvalidUrl { .. }),
            "url {url:?} should be rejected, got {error:?}"
        );
        let display = error.to_string();
        assert!(
            !display.contains("user:pass"),
            "Display must not echo userinfo for {url:?}, got {display}"
        );
    }
    server.assert_no_request().await;
    server.abort();
}

const UPLOAD_NOW: i64 = 1_700_000_000;

async fn upload_fixture(reply: Reply) -> MockServer {
    mock_server_sequence(vec![reply, Reply::UnexpectedRequest]).await
}

async fn attempt_upload(
    server: &MockServer,
    media_type: &str,
    model_headers: &HashMap<String, String>,
) -> Result<Option<UploadedFile>, FileUploadFailure> {
    let endpoint = endpoint(server.base_url(), Some("fixture-upload-credential"));
    let client = reqwest::Client::builder()
        .retry(reqwest::retry::never())
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap();
    let bytes: Arc<[u8]> = Arc::from(&b"plain text fixture"[..]);
    let input = AttachmentInput {
        attachment_id: "fixture-file".into(),
        modality: AttachmentModality::File,
        media_type: media_type.into(),
        filename: Some("upload.txt".into()),
        source: AttachmentSource::Bytes {
            bytes: bytes.clone(),
        },
    };
    tokio::time::timeout(
        Duration::from_secs(5),
        upload_file(FileUploadRequest {
            client: &client,
            endpoint: &endpoint,
            model_headers,
            input: &input,
            bytes: &bytes,
            now: UPLOAD_NOW,
        }),
    )
    .await
    .expect("upload completes against loopback")
}

fn failed_upload(result: Result<Option<UploadedFile>, FileUploadFailure>) -> FileUploadFailure {
    match result {
        Err(failure) => failure,
        Ok(_) => panic!("expected an upload failure"),
    }
}

fn has_reqwest_cause(error: &dyn Error) -> bool {
    let mut cause = error.source();
    while let Some(error) = cause {
        if error.is::<reqwest::Error>() {
            return true;
        }
        cause = error.source();
    }
    false
}

#[tokio::test]
async fn upload_http_failure_retains_the_typed_cause_and_separate_submission_outcome() {
    for (status, body, extra_declared_bytes, outcome, kind) in [
        (
            429,
            r#"{"error":{"code":"fixture-rate-limit","type":"fixture-upload-credential","message":"echo fixture-upload-credential"}}"#,
            0,
            UploadFailureOutcome::Rejected,
            Kind::RateLimit,
        ),
        (503, "", 0, UploadFailureOutcome::Unknown, Kind::ServiceBusy),
        (
            429,
            r#"{"error":{"code":"fixture-rate-limit","type":"fixture-upload-credential","message":"echo fixture-upload-credential"}}"#,
            40,
            UploadFailureOutcome::Unknown,
            Kind::RateLimit,
        ),
        (
            503,
            r#"{"error": {"#,
            40,
            UploadFailureOutcome::Unknown,
            Kind::ServiceBusy,
        ),
    ] {
        let server = upload_fixture(Reply::Upload {
            status,
            body,
            extra_declared_bytes,
            headers: &[
                ("x-request-id", "fixture-upload-request"),
                ("retry-after-ms", "127"),
            ],
        })
        .await;
        let failure = failed_upload(attempt_upload(&server, "text/plain", &HashMap::new()).await);
        assert_eq!(
            failure.outcome, outcome,
            "HTTP {status}, extra bytes {extra_declared_bytes}"
        );
        let provider = failure.source.provider_failure_ref().unwrap();
        assert_eq!(provider.kind, kind);
        assert_eq!(provider.http_status, Some(status));
        assert_eq!(provider.context.stage, ProviderFailureStage::Attachment);
        assert_eq!(
            provider.context.request_id.as_deref(),
            Some("fixture-upload-request")
        );
        assert!(provider.retry.is_retryable());
        assert_eq!(provider.retry.retry_after_ms(), Some(127));
        assert!(provider.retry_deadline().is_some());
        assert_eq!(has_reqwest_cause(&failure), extra_declared_bytes != 0);
        if status == 429 && extra_declared_bytes == 0 {
            assert_eq!(provider.code.as_deref(), Some("fixture-rate-limit"));
            assert_eq!(
                provider.error_type.as_deref(),
                Some("[REDACTED_CREDENTIAL]")
            );
            assert_eq!(provider.message, "echo [REDACTED_CREDENTIAL]");
        }
        assert!(!format!("{failure:?} {failure}").contains("fixture-upload-credential"));
        assert!(
            !serde_json::to_string(provider)
                .unwrap()
                .contains("fixture-upload-credential")
        );
        server.finish_upload(true).await;
    }
}

#[tokio::test]
async fn upload_response_without_a_trustworthy_file_id_leaves_submission_unknown() {
    for (reply, kind, retryable, typed_cause) in [
        (Reply::Disconnect, Kind::Transport, true, true),
        (
            Reply::Raw {
                status: 200,
                content_type: "application/json",
                body: b"{invalid JSON}".to_vec(),
            },
            Kind::Protocol,
            false,
            true,
        ),
        (
            Reply::Json {
                status: 200,
                body: json!({"id":""}),
            },
            Kind::Protocol,
            false,
            false,
        ),
    ] {
        let server = upload_fixture(reply).await;
        let failure = failed_upload(attempt_upload(&server, "text/plain", &HashMap::new()).await);
        assert_eq!(failure.outcome, UploadFailureOutcome::Unknown);
        let provider = failure.source.provider_failure_ref().unwrap();
        assert_eq!(provider.kind, kind);
        assert_eq!(provider.context.stage, ProviderFailureStage::Attachment);
        assert_eq!(provider.retry.is_retryable(), retryable);
        assert_eq!(has_reqwest_cause(&failure), typed_cause);
        server.finish_upload(true).await;
    }
}

#[tokio::test]
async fn upload_rejects_invalid_media_type_and_headers_before_posting() {
    let server = mock_server(Reply::UnexpectedRequest).await;
    let invalid_media =
        failed_upload(attempt_upload(&server, "not a MIME type", &HashMap::new()).await);
    assert_eq!(invalid_media.outcome, UploadFailureOutcome::Rejected);
    assert!(has_reqwest_cause(&invalid_media));

    let headers = HashMap::from([("bad\nheader".into(), "ignored".into())]);
    let invalid_header = failed_upload(attempt_upload(&server, "text/plain", &headers).await);
    assert_eq!(invalid_header.outcome, UploadFailureOutcome::Rejected);
    assert!(matches!(
        invalid_header.source,
        pl_protocol::PureError::ConfigError(_)
    ));
    server.finish_upload(false).await;
}

#[tokio::test]
async fn upload_preserves_file_id_and_lease_and_recognizes_unsupported_endpoints() {
    for (body, expires_at) in [
        (
            json!({"id":"file-ok","expires_at":UPLOAD_NOW + 900}),
            UPLOAD_NOW + 900,
        ),
        (json!({"id":"file-ok"}), UPLOAD_NOW + 86_400),
    ] {
        let server = upload_fixture(Reply::Json { status: 201, body }).await;
        let file = attempt_upload(&server, "text/plain", &HashMap::new())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(file.id, "file-ok");
        assert_eq!(file.expires_at, expires_at);
        server.finish_upload(true).await;
    }

    for status in [404, 405, 501] {
        let server = upload_fixture(Reply::Json {
            status,
            body: json!({}),
        })
        .await;
        assert!(
            attempt_upload(&server, "text/plain", &HashMap::new())
                .await
                .unwrap()
                .is_none(),
            "HTTP {status}"
        );
        server.finish_upload(true).await;
    }
}

#[tokio::test]
async fn upload_truncated_unsupported_status_does_not_allow_fallback() {
    let mut accepted = Vec::new();
    for status in [404, 405, 501] {
        let server = upload_fixture(Reply::Upload {
            status,
            body: "{}",
            headers: &[],
            extra_declared_bytes: 40,
        })
        .await;
        let result = attempt_upload(&server, "text/plain", &HashMap::new()).await;
        server.finish_upload(true).await;
        match result {
            Ok(_) => accepted.push(status),
            Err(failure) => {
                assert_eq!(
                    failure.outcome,
                    UploadFailureOutcome::Unknown,
                    "HTTP {status}"
                );
                let provider = failure.source.provider_failure_ref().unwrap();
                assert_eq!(provider.http_status, Some(status));
                assert_eq!(provider.context.stage, ProviderFailureStage::Attachment);
                assert!(
                    has_reqwest_cause(&failure),
                    "HTTP {status} lost the body read error"
                );
            }
        }
    }
    assert!(
        accepted.is_empty(),
        "truncated HTTP responses allowed fallback: {accepted:?}"
    );
}

#[tokio::test]
async fn upload_truncated_error_retains_the_error_envelope_decode_cause() {
    use pl_model_wire::provider_error::ErrorDecodeError;

    let server = upload_fixture(Reply::Upload {
        status: 429,
        body: r#"{"error":42}"#,
        headers: &[("retry-after-ms", "127")],
        extra_declared_bytes: 40,
    })
    .await;
    let failure = failed_upload(attempt_upload(&server, "text/plain", &HashMap::new()).await);
    server.finish_upload(true).await;
    assert_eq!(failure.outcome, UploadFailureOutcome::Unknown);
    let provider = failure.source.provider_failure_ref().unwrap();
    assert_eq!(provider.kind, Kind::Protocol);
    assert_eq!(provider.http_status, Some(429));
    assert!(!provider.retry.is_retryable());
    assert_eq!(provider.reported_wait_ms, Some(127));
    assert!(provider.retry_deadline().is_some());
    assert!(
        matches!(
            provider
                .source()
                .and_then(|cause| cause.downcast_ref::<ErrorDecodeError>()),
            Some(ErrorDecodeError::Structure("error must be an object")),
        ),
        "the first source must be the envelope decode error, got {:?}",
        provider.source()
    );
    let mut causes = provider.sources();
    assert_eq!(
        causes.len(),
        2,
        "one decode cause and one independent read cause"
    );
    assert!(matches!(
        causes.next().unwrap().downcast_ref::<ErrorDecodeError>(),
        Some(ErrorDecodeError::Structure("error must be an object")),
    ));
    assert!(
        has_reqwest_cause(causes.next().unwrap()),
        "the independent read cause must retain its reqwest error chain"
    );
}
