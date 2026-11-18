//! Loopback wire coverage through the OpenAI Images client.
use pl_model_openai::images::{
    ImageGenerationBackground, ImageGenerationRequest, ImagesClient, ImagesError,
};
use pl_model_types::protocol::ProtocolEndpoint;
use pretty_assertions::assert_eq;
use serde_json::{Value, json};
use std::time::Duration;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    task::JoinHandle,
};

const PNG: &[u8] = b"\x89PNG\r\n\x1a\n\0\0\0\rIHDRsynthetic";
const JPEG: &[u8] = b"\xFF\xD8\xFF\xE0\0\0synthetic";
const WEBP: &[u8] = b"RIFF\x10\0\0\0WEBPVP8 synthetic";

fn base64(bytes: &[u8]) -> String {
    use base64::{Engine, engine::general_purpose::STANDARD};
    STANDARD.encode(bytes)
}

struct Request {
    line: String,
    headers: String,
    body: String,
}

impl Request {
    fn json(&self) -> Value {
        serde_json::from_str(&self.body).unwrap()
    }
}

struct Server {
    url: String,
    task: JoinHandle<Vec<Request>>,
}

impl Drop for Server {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl Server {
    /// 依次用一个原始响应回答一次请求；请求被完整读取（含 body）。
    async fn respond(responses: Vec<String>) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let task = tokio::spawn(async move {
            let mut requests = Vec::new();
            for response in responses {
                let (mut socket, _) = listener.accept().await.unwrap();
                requests.push(read_request(&mut socket).await);
                let _ = socket.write_all(response.as_bytes()).await;
            }
            requests
        });
        Self { url, task }
    }

    fn base_v1(&self) -> String {
        format!("{}/v1", self.url)
    }

    async fn finish(mut self) -> Vec<Request> {
        tokio::time::timeout(Duration::from_secs(5), &mut self.task)
            .await
            .unwrap()
            .unwrap()
    }
}

async fn read_request(socket: &mut TcpStream) -> Request {
    let mut bytes = Vec::new();
    while !bytes.ends_with(b"\r\n\r\n") {
        let mut byte = [0];
        socket.read_exact(&mut byte).await.unwrap();
        bytes.push(byte[0]);
        assert!(bytes.len() < 65_536);
    }
    let headers = String::from_utf8(bytes).unwrap();
    let length = headers
        .lines()
        .skip(1)
        .filter_map(|line| line.split_once(':'))
        .find(|(name, _)| name.trim().eq_ignore_ascii_case("content-length"))
        .map(|(_, value)| value.trim().parse::<usize>().unwrap())
        .unwrap_or(0);
    let mut body = vec![0; length];
    if length > 0 {
        socket.read_exact(&mut body).await.unwrap();
    }
    Request {
        line: headers.lines().next().unwrap().to_string(),
        headers,
        body: String::from_utf8(body).unwrap(),
    }
}

fn http(status: u16, headers: &str, body: &str) -> String {
    format!(
        "HTTP/1.1 {status} Test\r\nContent-Length: {}\r\nConnection: close\r\n{headers}\r\n{body}",
        body.len()
    )
}

fn endpoint(url: &str, token: Option<&str>) -> ProtocolEndpoint {
    let mut endpoint = ProtocolEndpoint::openai(Some(url.to_string()));
    endpoint.bearer_token = token.map(str::to_owned);
    endpoint
}

fn client(url: &str) -> ImagesClient {
    ImagesClient::new(endpoint(url, Some("synthetic-token"))).unwrap()
}

fn request(prompt: &str, background: ImageGenerationBackground) -> ImageGenerationRequest {
    ImageGenerationRequest {
        model: "gpt-image-2".into(),
        prompt: prompt.into(),
        background,
    }
}

#[tokio::test]
async fn request_appends_the_dialect_path_after_the_configured_base_url() {
    let server = Server::respond(vec![
        http(
            200,
            "",
            &json!({ "data": [{ "b64_json": base64(PNG) }] }).to_string(),
        ),
        http(
            200,
            "",
            &json!({ "data": [{ "b64_json": base64(PNG) }] }).to_string(),
        ),
    ])
    .await;
    client(&server.base_v1())
        .generate(request("画一只猫", ImageGenerationBackground::Opaque))
        .await
        .unwrap();
    client(&format!("{}/tenant/proxy/", server.url))
        .generate(request("画一只猫", ImageGenerationBackground::Opaque))
        .await
        .unwrap();
    let requests = server.finish().await;
    // 版本前缀只来自配置的 base_url，不插入也不猜测。
    assert_eq!(requests[0].line, "POST /v1/images/generations HTTP/1.1");
    assert_eq!(
        requests[1].line,
        "POST /tenant/proxy/images/generations HTTP/1.1"
    );
    let lower = requests[0].headers.to_ascii_lowercase();
    assert!(lower.contains("authorization: bearer synthetic-token\r\n"));
    assert!(lower.contains("content-type: application/json"));
}

#[tokio::test]
async fn only_transparent_background_is_sent() {
    let server = Server::respond(vec![
        http(
            200,
            "",
            &json!({ "data": [{ "b64_json": base64(PNG) }] }).to_string(),
        ),
        http(
            200,
            "",
            &json!({ "data": [{ "b64_json": base64(PNG) }] }).to_string(),
        ),
    ])
    .await;
    let client = client(&server.base_v1());
    client
        .generate(request("opaque", ImageGenerationBackground::Opaque))
        .await
        .unwrap();
    client
        .generate(request(
            "transparent",
            ImageGenerationBackground::Transparent,
        ))
        .await
        .unwrap();
    let requests = server.finish().await;
    // 只发送提示词与模型；尺寸、质量、数量与响应格式交给供应商默认。
    assert_eq!(
        requests[0].json(),
        json!({ "model": "gpt-image-2", "prompt": "opaque" })
    );
    assert_eq!(
        requests[1].json(),
        json!({ "model": "gpt-image-2", "prompt": "transparent", "background": "transparent" })
    );
}

#[tokio::test]
async fn inline_base64_images_are_decoded_and_typed_by_magic_bytes() {
    let server = Server::respond(vec![
        http(
            200,
            "",
            &json!({ "data": [{ "b64_json": base64(PNG), "revised_prompt": "改写的提示词" }] })
                .to_string(),
        ),
        http(
            200,
            "",
            &json!({ "data": [{ "b64_json": base64(JPEG) }] }).to_string(),
        ),
        http(
            200,
            "",
            &json!({ "data": [{ "b64_json": base64(WEBP), "revised_prompt": "" }] }).to_string(),
        ),
        http(
            200,
            "",
            &json!({ "data": [{ "b64_json": base64(b"not an image") }] }).to_string(),
        ),
        http(200, "", &json!({ "data": [] }).to_string()),
        http(200, "", &json!({ "data": [{}] }).to_string()),
    ])
    .await;
    let client = client(&server.base_v1());
    let image = client
        .generate(request("png", ImageGenerationBackground::Opaque))
        .await
        .unwrap();
    assert_eq!(image.bytes, PNG);
    assert_eq!(image.media_type, "image/png");
    assert_eq!(image.revised_prompt.as_deref(), Some("改写的提示词"));
    let jpeg = client
        .generate(request("jpeg", ImageGenerationBackground::Opaque))
        .await
        .unwrap();
    assert_eq!((jpeg.media_type, jpeg.revised_prompt), ("image/jpeg", None));
    assert_eq!(
        client
            .generate(request("webp", ImageGenerationBackground::Opaque))
            .await
            .unwrap()
            .media_type,
        "image/webp"
    );
    // 未知字节、空列表与缺失 b64_json 都是协议错误。
    assert_eq!(
        client
            .generate(request("unknown", ImageGenerationBackground::Opaque))
            .await,
        Err(ImagesError::Protocol)
    );
    assert_eq!(
        client
            .generate(request("empty", ImageGenerationBackground::Opaque))
            .await,
        Err(ImagesError::Protocol)
    );
    assert_eq!(
        client
            .generate(request("missing", ImageGenerationBackground::Opaque))
            .await,
        Err(ImagesError::Protocol)
    );
    server.finish().await;
}

#[tokio::test]
async fn non_success_status_reports_only_the_code_without_credentials() {
    let server = Server::respond(vec![http(
        401,
        "Content-Type: application/json\r\n",
        &json!({ "error": { "message": "synthetic-body-secret" } }).to_string(),
    )])
    .await;
    let client = client(&server.base_v1());
    assert!(!format!("{client:?}").contains("synthetic-token"));
    let error = client
        .generate(request("unauthorized", ImageGenerationBackground::Opaque))
        .await
        .unwrap_err();
    assert_eq!(error, ImagesError::Http { status: 401 });
    let rendered = format!("{error} {error:?}");
    assert!(!rendered.contains("synthetic-token"));
    assert!(!rendered.contains("synthetic-body-secret"));
    server.finish().await;
}

#[tokio::test]
async fn oversized_responses_are_rejected() {
    let oversized = format!(
        "HTTP/1.1 200 Test\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        32 * 1024 * 1024 + 1
    );
    let server = Server::respond(vec![oversized]).await;
    assert_eq!(
        client(&server.base_v1())
            .generate(request("too large", ImageGenerationBackground::Opaque))
            .await,
        Err(ImagesError::TooLarge)
    );
    server.finish().await;
}

#[tokio::test]
async fn redirects_are_not_followed() {
    // 第二跳目标保持监听但不服务；若客户端跟随重定向，这里会收到连接。
    let trap = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let trap_url = format!("http://{}", trap.local_addr().unwrap());
    let server = Server::respond(vec![http(
        302,
        &format!("Location: {trap_url}/v1/images/generations\r\n"),
        "",
    )])
    .await;
    assert_eq!(
        client(&server.base_v1())
            .generate(request("redirect", ImageGenerationBackground::Opaque))
            .await,
        Err(ImagesError::Http { status: 302 })
    );
    assert!(
        tokio::time::timeout(Duration::from_millis(200), trap.accept())
            .await
            .is_err(),
        "image generation must not follow redirects"
    );
    let requests = server.finish().await;
    assert_eq!(requests.len(), 1);
}
