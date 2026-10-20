//! 图像生成服务能力、后端选择与 Images 方言客户端的公开 API 契约。
//!
//! 只使用 `pl-model` 公开入口与本地 `TcpListener` 模拟服务端；不使用真实供应商或凭据。
use pl_model::{
    PureError,
    config::{
        AccountCapabilitySelection, AccountConfig, AccountId, AccountTemplateId, AgentModelConfig,
        ImageGenerationBackend, ImageGenerationService, ModelCatalogId,
    },
    model::{ModelInfo, ModelModality, ModelTransportProfile, ModelType},
    protocol::{
        ImageGenerationCapabilities, ImageGenerationDialect, ProtocolEndpoint,
        ProtocolServiceCapabilities,
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

fn account_id(id: &str) -> AccountId {
    AccountId::new(id).unwrap()
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

/// 只输出图像的模型：进入生图库存，但不得留在 text 类型目录。
fn image_output(slug: &str) -> ModelInfo {
    let mut model = observed(slug);
    model.capabilities.output = vec![ModelModality::Image];
    model
}

fn openai_account(url: &str) -> AccountConfig {
    AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::openai(Some(url.into())),
        ModelCatalogId::new("openai").unwrap(),
        Vec::new(),
    )
}

fn observing_account(url: &str, token: Option<&str>, models: Vec<ModelInfo>) -> AccountConfig {
    let mut account = openai_account(url);
    account.bearer_token = token.map(str::to_owned);
    account.set_model_catalog_overlay(models).unwrap();
    account
}

fn config(accounts: Vec<(&str, AccountConfig)>) -> AgentModelConfig {
    AgentModelConfig {
        accounts: accounts
            .into_iter()
            .map(|(id, account)| (account_id(id), account))
            .collect(),
        routes: Default::default(),
    }
}

fn declared(prefixes: &[&str], preferred: &[&str]) -> ProtocolServiceCapabilities {
    ProtocolServiceCapabilities {
        image_generation: Some(ImageGenerationCapabilities {
            dialect: ImageGenerationDialect::OpenAiImages,
            model_prefixes: prefixes.iter().map(|value| value.to_string()).collect(),
            preferred_models: preferred.iter().map(|value| value.to_string()).collect(),
        }),
        ..ProtocolServiceCapabilities::default()
    }
}

fn selected(config: &AgentModelConfig) -> ImageGenerationBackend {
    config
        .image_generation_backend()
        .unwrap()
        .backend
        .expect("configured accounts expose one image generation backend")
}

fn selected_model(config: &AgentModelConfig) -> String {
    selected(config).model
}

fn observed_models(slugs: &[&str]) -> Vec<ModelInfo> {
    slugs.iter().map(|slug| observed(slug)).collect()
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
    let capabilities = ProtocolEndpoint::openai(None).service_capabilities;
    let declaration = capabilities.image_generation.unwrap();
    assert_eq!(declaration.dialect, ImageGenerationDialect::OpenAiImages);
    assert_eq!(declaration.model_prefixes, vec!["gpt-image-".to_string()]);
    // 首选序有意留空：版本择优决定具体 slug，不把某个模型固化成默认。
    assert_eq!(declaration.preferred_models, Vec::<String>::new());
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

    // 其它 endpoint 不声明该能力。
    assert!(
        ProtocolEndpoint::deepseek(None)
            .service_capabilities
            .image_generation
            .is_none()
    );
    assert!(
        ProtocolEndpoint::compatible("Custom", "http://127.0.0.1:1")
            .service_capabilities
            .image_generation
            .is_none()
    );
}

#[test]
fn template_keeps_image_generation_when_base_url_is_overridden() {
    let account = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::openai(Some("https://proxy.example.com".into())),
        ModelCatalogId::new("openai").unwrap(),
        Vec::new(),
    )
    .with_template(AccountTemplateId::new("openai").unwrap());
    let capabilities = account.service_capabilities().unwrap();
    // 覆盖 base_url 撤销 hosted 能力，但保留 Images 继承：路径追加在该前缀之后。
    assert!(!capabilities.remote_compaction);
    assert!(!capabilities.web_search.hosted_responses);
    assert_eq!(
        capabilities.image_generation,
        Some(ImageGenerationCapabilities::openai_images())
    );
    // endpoint 携带同一份声明，客户端才能按方言组装路径。
    assert_eq!(
        account
            .to_endpoint()
            .unwrap()
            .service_capabilities
            .image_generation,
        Some(ImageGenerationCapabilities::openai_images())
    );
}

#[test]
fn declaration_requires_a_non_empty_model_prefix() {
    let mut account = openai_account("http://127.0.0.1:1");
    account.capabilities = AccountCapabilitySelection::Explicit(declared(&[], &[]));
    assert!(matches!(
        account.service_capabilities(),
        Err(PureError::ConfigError(_))
    ));
    // 既有公开校验入口必须触发同一份定义错误。
    assert!(matches!(
        account.validate_declarations(&account_id("openai")),
        Err(PureError::ConfigError(message)) if message.contains("at least one model prefix")
    ));
    assert!(matches!(
        account.to_endpoint(),
        Err(PureError::ConfigError(_))
    ));

    // 空串前缀同样无效，不能被当作「匹配所有模型」。
    account.capabilities =
        AccountCapabilitySelection::Explicit(declared(&["gpt-image-", "  "], &[]));
    assert!(matches!(
        account.validate_declarations(&account_id("openai")),
        Err(PureError::ConfigError(message)) if message.contains("empty model prefix")
    ));

    // 合法声明通过校验。
    account.capabilities = AccountCapabilitySelection::Explicit(declared(&["gpt-image-"], &[]));
    account
        .validate_declarations(&account_id("openai"))
        .unwrap();
}

#[test]
fn declaration_does_not_require_a_catalog_exclusion_rule() {
    // 声明的可用性由目录候选与凭据决定，不由「非对话排除规则」覆盖；前缀不命中任何模型
    // 仍然是合法声明，只是当前没有可用模型。
    let mut account = openai_account("http://127.0.0.1:1");
    account.capabilities = AccountCapabilitySelection::Explicit(declared(
        &["text-completion-"],
        &["text-completion-1"],
    ));
    account
        .validate_declarations(&account_id("openai"))
        .unwrap();
    assert_eq!(
        account.image_generation_service().unwrap(),
        Some(ImageGenerationService {
            capabilities: ImageGenerationCapabilities {
                dialect: ImageGenerationDialect::OpenAiImages,
                model_prefixes: vec!["text-completion-".to_string()],
                preferred_models: vec!["text-completion-1".to_string()],
            },
            models: Vec::new(),
        })
    );
}

#[test]
fn preferred_model_must_match_a_declared_prefix() {
    let mut account = openai_account("http://127.0.0.1:1");
    account.capabilities =
        AccountCapabilitySelection::Explicit(declared(&["gpt-image-"], &["dall-e-3"]));
    assert!(matches!(
        account.validate_declarations(&account_id("openai")),
        Err(PureError::ConfigError(message))
            if message.contains("does not match a declared prefix: dall-e-3")
    ));
}

#[test]
fn image_generation_models_come_from_the_effective_catalog() {
    let account = openai_account("http://127.0.0.1:1");
    // 尚无成功观察：声明存在，可用模型为空，不能由默认定义补齐。
    assert_eq!(
        account.image_generation_service().unwrap(),
        Some(ImageGenerationService {
            capabilities: ImageGenerationCapabilities::openai_images(),
            models: Vec::new(),
        })
    );

    // 手工模型与在线观察都算目录成员：命中前缀即进入库存，按字典序去重。
    let manual = ModelInfo::compatible("gpt-image-1");
    let mut account = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::openai(Some("http://127.0.0.1:1".into())),
        ModelCatalogId::new("openai").unwrap(),
        vec![manual],
    );
    account
        .set_model_catalog_overlay(vec![
            observed("gpt-image-2"),
            observed("gpt-image-1"),
            observed("text-embedding-3"),
            observed("gpt-6-astra"),
        ])
        .unwrap();
    let service = account.image_generation_service().unwrap().unwrap();
    assert_eq!(
        service.models,
        vec!["gpt-image-1".to_string(), "gpt-image-2".to_string()]
    );
    assert_eq!(
        service.capabilities,
        ImageGenerationCapabilities::openai_images()
    );

    // 未声明能力的 account 返回 None。
    let zhipu = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::zhipu(None),
        ModelCatalogId::new("zhipu").unwrap(),
        Vec::new(),
    );
    assert_eq!(zhipu.image_generation_service().unwrap(), None);
}

#[test]
fn image_output_models_stay_out_of_the_text_catalog() {
    let account = observing_account(
        "http://127.0.0.1:1",
        Some("token"),
        vec![image_output("gpt-image-2"), observed("gpt-6-astra")],
    );
    // 生图库存来自完整目录成员。
    assert_eq!(
        account.image_generation_service().unwrap().unwrap().models,
        vec!["gpt-image-2".to_string()]
    );
    // 图像输出模型不属于对话目录，因此不参与路由、压缩与附件能力校验。
    assert_eq!(
        account
            .effective_models(Some(ModelType::Text))
            .unwrap()
            .iter()
            .map(|model| model.model_id.as_str())
            .collect::<Vec<_>>(),
        vec!["gpt-6-astra"]
    );
}

#[test]
fn backend_selection_is_deterministic_across_accounts() {
    let models = config(vec![
        (
            "zeta",
            observing_account(
                "http://127.0.0.1:1/v1",
                Some("zeta-token"),
                observed_models(&["gpt-image-2"]),
            ),
        ),
        (
            "alpha",
            observing_account(
                "http://127.0.0.1:1/v1",
                Some("alpha-token"),
                observed_models(&["gpt-image-2"]),
            ),
        ),
    ]);
    let selection = models.image_generation_backend().unwrap();
    assert!(selection.any_declared);
    let ImageGenerationBackend {
        account_id,
        endpoint,
        model,
        dialect,
    } = selection.backend.unwrap();
    // account 按标识字典序稳定遍历，不依赖插入顺序。
    assert_eq!(account_id, AccountId::new("alpha").unwrap());
    assert_eq!(endpoint.base_url, "http://127.0.0.1:1/v1");
    assert_eq!(endpoint.bearer_token.as_deref(), Some("alpha-token"));
    assert_eq!(model, "gpt-image-2");
    assert_eq!(dialect, ImageGenerationDialect::OpenAiImages);
}

#[test]
fn accounts_without_credentials_are_skipped() {
    let models = config(vec![
        (
            "alpha",
            observing_account(
                "http://127.0.0.1:1/v1",
                None,
                observed_models(&["gpt-image-2"]),
            ),
        ),
        (
            "beta",
            observing_account(
                "http://127.0.0.1:1/v1",
                Some("beta-token"),
                observed_models(&["gpt-image-2"]),
            ),
        ),
    ]);
    let selection = models.image_generation_backend().unwrap();
    assert!(selection.any_declared);
    assert_eq!(
        selection.backend.map(|backend| backend.account_id),
        Some(account_id("beta"))
    );
}

#[test]
fn declared_but_unavailable_capability_is_reported_without_a_backend() {
    // 完全没有声明该能力的配置：两者都是 false/None。
    let undeclared = config(vec![(
        "zhipu",
        AccountConfig::from_bundled_catalog(
            ProtocolEndpoint::zhipu(None),
            ModelCatalogId::new("zhipu").unwrap(),
            Vec::new(),
        ),
    )]);
    let selection = undeclared.image_generation_backend().unwrap();
    assert!(!selection.any_declared);
    assert!(selection.backend.is_none());

    // 已声明但当前无生图模型：any_declared 仍为真。
    let empty = config(vec![(
        "alpha",
        observing_account(
            "http://127.0.0.1:1/v1",
            Some("alpha-token"),
            observed_models(&["gpt-6-astra"]),
        ),
    )]);
    let selection = empty.image_generation_backend().unwrap();
    assert!(selection.any_declared);
    assert!(selection.backend.is_none());
}

#[test]
fn explicitly_pinned_models_win_over_version_preference() {
    let mut account = observing_account(
        "http://127.0.0.1:1/v1",
        Some("token"),
        observed_models(&["gpt-image-2", "gpt-image-1"]),
    );
    account.capabilities =
        AccountCapabilitySelection::Explicit(declared(&["gpt-image-"], &["gpt-image-1"]));
    assert_eq!(
        selected_model(&config(vec![("alpha", account)])),
        "gpt-image-1"
    );
}

#[test]
fn version_preference_selects_the_highest_parseable_model() {
    // 版本高者优先：1.5 > 1。
    let newest = config(vec![(
        "alpha",
        observing_account(
            "http://127.0.0.1:1/v1",
            Some("token"),
            observed_models(&["gpt-image-1", "gpt-image-1.5"]),
        ),
    )]);
    assert_eq!(selected_model(&newest), "gpt-image-1.5");

    // 同版本无变体后缀者优先，即使字典序相反。
    let mut prefixed = observing_account(
        "http://127.0.0.1:1/v1",
        Some("token"),
        observed_models(&["gpt-image-3-alpha", "images-3"]),
    );
    prefixed.capabilities =
        AccountCapabilitySelection::Explicit(declared(&["gpt-image-", "images-"], &[]));
    assert_eq!(
        selected_model(&config(vec![("alpha", prefixed)])),
        "images-3"
    );

    // 同版本同形态按 slug 字典序。
    let variants = config(vec![(
        "alpha",
        observing_account(
            "http://127.0.0.1:1/v1",
            Some("token"),
            observed_models(&["gpt-image-2.5-sunburst", "gpt-image-2.5-flare"]),
        ),
    )]);
    assert_eq!(selected_model(&variants), "gpt-image-2.5-flare");

    // 无法解析版本的候选排在最后，即使字典序最靠前。
    let unparsed = config(vec![(
        "alpha",
        observing_account(
            "http://127.0.0.1:1/v1",
            Some("token"),
            observed_models(&["gpt-image-", "gpt-image-1"]),
        ),
    )]);
    assert_eq!(selected_model(&unparsed), "gpt-image-1");

    // 选择只由候选与声明决定：重复调用结果一致。
    assert_eq!(selected_model(&newest), selected_model(&newest));
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
