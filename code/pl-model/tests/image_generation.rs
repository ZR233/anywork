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
    },
};
use pretty_assertions::assert_eq;
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
    let text_models = account.selectable_catalog(Some(ModelType::Text)).unwrap();
    assert!(
        text_models
            .iter()
            .any(|entry| entry.model.model_id == "gpt-6-astra")
    );
    assert!(
        text_models
            .iter()
            .all(|entry| entry.model.model_id != "gpt-image-2")
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
