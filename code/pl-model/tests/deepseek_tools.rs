use pl_model::config::{
    AccountCapabilitySelection, AccountConfig, AccountTemplateId, ModelCatalogId,
};
use pl_model::protocol::{
    ProtocolEndpoint, ProtocolServiceCapabilities, StandaloneWebSearchDialect,
    WebSearchServiceCapabilities,
};

/// 公开配置解析的搜索能力门控：canonical preset 继承 DeepSeek 官方工具方言，非 canonical
/// DeepSeek TemplateDefaults 仅撤销该 DeepSeek 方言，Explicit 声明仍可 opt-in。该撤销只针对
/// DeepSeek 原生方言，OpenAI 自定义 endpoint 的 `/alpha/search` standalone 继承语义保持不变。
#[test]
fn deepseek_tools_capability_gating_follows_canonical_preset_and_explicit_opt_in() {
    let canonical = AccountConfig::deepseek_template();
    let capabilities = canonical.service_capabilities().unwrap();
    assert_eq!(
        capabilities.web_search.standalone,
        Some(StandaloneWebSearchDialect::DeepSeekToolsApi)
    );
    assert!(!capabilities.web_search.hosted_responses);

    let mut custom = AccountConfig::deepseek_template();
    custom.base_url = "https://proxy.example.com".to_string();
    let capabilities = custom.service_capabilities().unwrap();
    assert_eq!(capabilities.web_search.standalone, None);
    assert!(!capabilities.web_search.hosted_responses);

    custom.capabilities = AccountCapabilitySelection::Explicit(ProtocolServiceCapabilities {
        web_search: WebSearchServiceCapabilities {
            standalone: Some(StandaloneWebSearchDialect::DeepSeekToolsApi),
            ..WebSearchServiceCapabilities::default()
        },
        ..ProtocolServiceCapabilities::default()
    });
    let capabilities = custom.service_capabilities().unwrap();
    assert_eq!(
        capabilities.web_search.standalone,
        Some(StandaloneWebSearchDialect::DeepSeekToolsApi)
    );

    let openai_custom = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::openai(Some("https://ai.muxai.net".to_string())),
        ModelCatalogId::new("openai").unwrap(),
        Vec::new(),
    )
    .with_template(AccountTemplateId::new("openai").unwrap());
    let capabilities = openai_custom.service_capabilities().unwrap();
    assert_eq!(
        capabilities.web_search.standalone,
        Some(StandaloneWebSearchDialect::OpenAiSearchApi)
    );
    assert_eq!(
        capabilities.prompt_cache.dialect,
        pl_model::protocol::PromptCacheDialect::None
    );
}
