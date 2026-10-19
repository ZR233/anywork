//! 图像生成服务能力、后端选择与 Images 方言客户端的公开 API 契约。
//!
//! 只使用 `pl-model` 公开入口与本地 `TcpListener` 模拟服务端；不使用真实供应商或凭据。
use pl_model::{
    PureError,
    config::{
        AgentModelConfig, ImageGenerationBackend, ModelCatalogId, ProviderCapabilitySelection,
        ProviderConfig, ProviderId, ProviderPresetId,
    },
    model::{ModelInfo, ModelTransportProfile},
    provider::{
        ImageGenerationCapabilities, ImageGenerationDialect, ProviderEndpoint,
        ProviderServiceCapabilities,
        images::{ImageGenerationBackground, ImageGenerationRequest, ImagesClient, ImagesError},
    },
};
use pretty_assertions::assert_eq;
use serde_json::{Value, json};
use std::time::Duration;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    task::JoinHandle,
};

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

fn endpoint(url: &str, token: Option<&str>) -> ProviderEndpoint {
    let mut endpoint = ProviderEndpoint::openai(Some(url.to_string()));
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

/// 一个通过在线观察校验、且符合 OpenAI 目录 transport 的在线模型。
fn observed(slug: &str) -> ModelInfo {
    let mut model = ModelInfo::compatible(slug);
    model.context_window = None;
    model.max_output_tokens = None;
    model
        .binding
        .set_transport(ModelTransportProfile::responses_websocket());
    model
}

fn openai_provider(url: &str) -> ProviderConfig {
    ProviderConfig::from_bundled_catalog(
        ProviderEndpoint::openai(Some(url.into())),
        ModelCatalogId::new("openai").unwrap(),
        Vec::new(),
    )
}

fn provider_id(id: &str) -> ProviderId {
    ProviderId::new(id).unwrap()
}

fn observed_provider(url: &str, token: Option<&str>, slugs: &[&str]) -> ProviderConfig {
    let mut provider = openai_provider(url);
    provider.bearer_token = token.map(str::to_owned);
    provider
        .set_model_catalog_overlay(slugs.iter().map(|slug| observed(slug)).collect())
        .unwrap();
    provider
}

fn config(providers: Vec<(&str, ProviderConfig)>) -> AgentModelConfig {
    AgentModelConfig {
        providers: providers
            .into_iter()
            .map(|(id, provider)| (provider_id(id), provider))
            .collect(),
        routes: Default::default(),
    }
}

fn declared(model_prefixes: &[&str], preferred_models: &[&str]) -> ProviderServiceCapabilities {
    ProviderServiceCapabilities {
        image_generation: Some(ImageGenerationCapabilities {
            dialect: ImageGenerationDialect::OpenAiImages,
            model_prefixes: model_prefixes
                .iter()
                .map(|value| value.to_string())
                .collect(),
            preferred_models: preferred_models
                .iter()
                .map(|value| value.to_string())
                .collect(),
        }),
        ..ProviderServiceCapabilities::default()
    }
}

const PNG: &[u8] = b"\x89PNG\r\n\x1a\n\0\0\0\rIHDRsynthetic";
const JPEG: &[u8] = b"\xFF\xD8\xFF\xE0\0\0synthetic";
const WEBP: &[u8] = b"RIFF\x10\0\0\0WEBPVP8 synthetic";

fn base64(bytes: &[u8]) -> String {
    use base64::{Engine, engine::general_purpose::STANDARD};
    STANDARD.encode(bytes)
}

#[test]
fn openai_canonical_declaration_is_usable() {
    let capabilities = ProviderEndpoint::openai(None).service_capabilities;
    let declaration = capabilities.image_generation.unwrap();
    assert_eq!(declaration.dialect, ImageGenerationDialect::OpenAiImages);
    assert_eq!(declaration.model_prefixes, vec!["gpt-image-".to_string()]);
    assert_eq!(
        declaration.preferred_models,
        vec!["gpt-image-1".to_string()]
    );
    // 方言同时声明身份字符串与追加到 base_url 的路径。
    assert_eq!(declaration.dialect.as_str(), "open_ai_images");
    assert_eq!(declaration.dialect.path(), "/images/generations");
    assert_eq!(
        "open_ai_images".parse::<ImageGenerationDialect>(),
        Ok(ImageGenerationDialect::OpenAiImages)
    );
    assert!("images".parse::<ImageGenerationDialect>().is_err());
    assert_eq!(
        serde_json::to_string(&ImageGenerationDialect::OpenAiImages).unwrap(),
        "\"open_ai_images\""
    );

    // 其它目录不声明该能力。
    assert!(
        ProviderEndpoint::deepseek(None)
            .service_capabilities
            .image_generation
            .is_none()
    );
    assert!(
        ProviderEndpoint::compatible("Custom", "http://127.0.0.1:1")
            .service_capabilities
            .image_generation
            .is_none()
    );
}

#[test]
fn preset_keeps_image_generation_when_base_url_is_overridden() {
    let config = ProviderConfig::from_bundled_catalog(
        ProviderEndpoint::openai(Some("https://proxy.example.com".into())),
        ModelCatalogId::new("openai").unwrap(),
        Vec::new(),
    )
    .with_preset(ProviderPresetId::new("openai").unwrap());
    let capabilities = config.service_capabilities().unwrap();
    // 覆盖 base_url 撤销 hosted 能力，但保留 Images 继承：路径追加在该前缀之后。
    assert!(!capabilities.remote_compaction);
    assert!(!capabilities.web_search.hosted_responses);
    assert_eq!(
        capabilities.image_generation,
        Some(ImageGenerationCapabilities::openai_images())
    );
    // 端点点携带同一份声明，客户端才能按方言组装路径。
    assert_eq!(
        config
            .to_endpoint()
            .unwrap()
            .service_capabilities
            .image_generation,
        Some(ImageGenerationCapabilities::openai_images())
    );
}

#[test]
fn declaration_requires_a_non_empty_model_prefix() {
    let mut config = openai_provider("http://127.0.0.1:1");
    config.capabilities = ProviderCapabilitySelection::Explicit(declared(&[], &[]));
    assert!(matches!(
        config.service_capabilities(),
        Err(PureError::ConfigError(message))
            if message.contains("at least one model prefix")
    ));
    // 既有公开校验入口必须触发同一份定义错误。
    assert!(matches!(
        config.validate_declarations(&provider_id("openai")),
        Err(PureError::ConfigError(message)) if message.contains("at least one model prefix")
    ));
    assert!(matches!(
        config.to_endpoint(),
        Err(PureError::ConfigError(_))
    ));
}

#[test]
fn declared_prefix_must_be_excluded_by_its_catalog() {
    let mut config = openai_provider("http://127.0.0.1:1");
    config.capabilities = ProviderCapabilitySelection::Explicit(declared(
        &["text-completion-"],
        &["text-completion-1"],
    ));
    assert!(matches!(
        config.service_capabilities(),
        Err(PureError::ConfigError(message))
            if message.contains("not excluded by its model catalog: text-completion-")
    ));
    // 命中目录前缀家族（大小写敏感）的声明可用。
    config.capabilities =
        ProviderCapabilitySelection::Explicit(declared(&["gpt-image-"], &["gpt-image-1"]));
    assert!(
        config
            .service_capabilities()
            .unwrap()
            .image_generation
            .is_some()
    );
    // 没有在线目录声明的目录无法覆盖任何前缀。
    let mut zhipu = ProviderConfig::from_bundled_catalog(
        ProviderEndpoint::zhipu(None),
        ModelCatalogId::new("zhipu").unwrap(),
        Vec::new(),
    );
    zhipu.capabilities = ProviderCapabilitySelection::Explicit(declared(&["gemini-image-"], &[]));
    assert!(matches!(
        zhipu.service_capabilities(),
        Err(PureError::ConfigError(_))
    ));
}

#[test]
fn preferred_model_must_match_a_declared_prefix() {
    let mut config = openai_provider("http://127.0.0.1:1");
    config.capabilities =
        ProviderCapabilitySelection::Explicit(declared(&["gpt-image-"], &["dall-e-3"]));
    assert!(matches!(
        config.service_capabilities(),
        Err(PureError::ConfigError(message))
            if message.contains("does not match a declared prefix: dall-e-3")
    ));
}

#[test]
fn image_generation_models_come_from_the_online_observation_only() {
    let mut config = openai_provider("http://127.0.0.1:1");
    // 尚无成功观察：声明存在，可用模型为空，不能由默认定义补齐。
    assert_eq!(
        config.image_generation_service().unwrap(),
        Some(pl_model::config::ImageGenerationService {
            capabilities: ImageGenerationCapabilities::openai_images(),
            models: Vec::new(),
        })
    );
    config
        .set_model_catalog_overlay(vec![
            observed("gpt-image-2"),
            observed("text-embedding-3"),
            observed("gpt-6-astra"),
        ])
        .unwrap();
    let service = config.image_generation_service().unwrap().unwrap();
    assert_eq!(service.models, vec!["gpt-image-2".to_string()]);
    assert_eq!(
        service.capabilities,
        ImageGenerationCapabilities::openai_images()
    );
    // 回归保护：生图模型不进入有效对话目录。
    assert_eq!(
        config
            .effective_models()
            .unwrap()
            .iter()
            .map(|model| model.slug.as_str())
            .collect::<Vec<_>>(),
        vec!["gpt-6-astra"]
    );
    // 未声明能力的 provider 返回 None。
    let zhipu = ProviderConfig::from_bundled_catalog(
        ProviderEndpoint::zhipu(None),
        ModelCatalogId::new("zhipu").unwrap(),
        Vec::new(),
    );
    assert_eq!(zhipu.image_generation_service().unwrap(), None);
}

#[test]
fn backend_selection_is_deterministic_across_providers() {
    let models = config(vec![
        (
            "zeta",
            observed_provider(
                "http://127.0.0.1:2/v1",
                Some("zeta-token"),
                &["gpt-image-2"],
            ),
        ),
        (
            "alpha",
            observed_provider(
                "http://127.0.0.1:1/v1",
                Some("alpha-token"),
                &["gpt-image-2"],
            ),
        ),
    ]);
    let selection = models.image_generation_backend().unwrap();
    let backend = selection.backend.unwrap();
    assert!(selection.any_declared);
    let ImageGenerationBackend {
        provider_id,
        endpoint,
        model,
        dialect,
    } = backend;
    assert_eq!(provider_id, "alpha");
    assert_eq!(endpoint.base_url, "http://127.0.0.1:1/v1");
    assert_eq!(endpoint.bearer_token.as_deref(), Some("alpha-token"));
    assert_eq!(model, "gpt-image-2");
    assert_eq!(dialect, ImageGenerationDialect::OpenAiImages);
}

#[test]
fn providers_without_credentials_are_skipped() {
    let models = config(vec![
        (
            "alpha",
            observed_provider("http://127.0.0.1:1/v1", None, &["gpt-image-2"]),
        ),
        (
            "beta",
            observed_provider(
                "http://127.0.0.1:2/v1",
                Some("beta-token"),
                &["gpt-image-2"],
            ),
        ),
    ]);
    let selection = models.image_generation_backend().unwrap();
    assert!(selection.any_declared);
    assert_eq!(
        selection.backend.map(|backend| backend.provider_id),
        Some("beta".to_string())
    );
}

#[test]
fn declared_but_unavailable_capability_is_reported_without_a_backend() {
    // 完全没有声明该能力的配置：两者都是 false/None。
    let undeclared = config(vec![(
        "zhipu",
        ProviderConfig::from_bundled_catalog(
            ProviderEndpoint::zhipu(None),
            ModelCatalogId::new("zhipu").unwrap(),
            Vec::new(),
        ),
    )]);
    let selection = undeclared.image_generation_backend().unwrap();
    assert!(!selection.any_declared);
    assert!(selection.backend.is_none());

    // 已声明但当前无在线生图模型：any_declared 仍为真。
    let empty = config(vec![(
        "alpha",
        observed_provider(
            "http://127.0.0.1:1/v1",
            Some("alpha-token"),
            &["gpt-6-astra"],
        ),
    )]);
    let selection = empty.image_generation_backend().unwrap();
    assert!(selection.any_declared);
    assert!(selection.backend.is_none());
}

#[test]
fn preferred_models_win_and_absent_preferences_fall_back_to_dictionary_order() {
    let preferred = config(vec![(
        "alpha",
        observed_provider(
            "http://127.0.0.1:1/v1",
            Some("alpha-token"),
            &["gpt-image-2", "gpt-image-1"],
        ),
    )]);
    assert_eq!(
        preferred
            .image_generation_backend()
            .unwrap()
            .backend
            .unwrap()
            .model,
        "gpt-image-1"
    );

    let fallback = config(vec![(
        "alpha",
        observed_provider(
            "http://127.0.0.1:1/v1",
            Some("alpha-token"),
            &["gpt-image-3", "gpt-image-2"],
        ),
    )]);
    assert_eq!(
        fallback
            .image_generation_backend()
            .unwrap()
            .backend
            .unwrap()
            .model,
        "gpt-image-2"
    );
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
