//! Effective catalog origin, membership and catalog-declared discovery.
use pl_model::{
    config::{
        AccountCapabilitySelection, AccountConfig, AccountId, AccountModelCatalogConfig,
        AccountModelOrigin, AccountTemplateId, AgentModelConfig, AgentRoleId, ModelCatalogId,
        ModelRouteConfig, builtin_account_catalog, builtin_model_catalog, model_descriptor,
    },
    model::{ModelInfo, ModelPricing, ModelTransportProfile, ModelType, bundled_model_definition},
    protocol::{
        ProtocolEndpoint, ProtocolKind,
        discovery::{ModelCatalogQuery, ModelCatalogQueryResult},
    },
};
use pretty_assertions::assert_eq;
use serde_json::json;
use std::time::Duration;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
    task::JoinHandle,
};

struct Server {
    url: String,
    task: JoinHandle<Vec<String>>,
}

impl Drop for Server {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl Server {
    async fn json(body: serde_json::Value) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let payload = body.to_string();
        let task = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut bytes = Vec::new();
            while !bytes.ends_with(b"\r\n\r\n") {
                let mut byte = [0];
                socket.read_exact(&mut byte).await.unwrap();
                bytes.push(byte[0]);
                assert!(bytes.len() < 16_384);
            }
            let response = format!(
                "HTTP/1.1 200 Test\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{payload}",
                payload.len()
            );
            let _ = socket.write_all(response.as_bytes()).await;
            vec![String::from_utf8(bytes).unwrap()]
        });
        Self { url, task }
    }

    async fn finish(mut self) -> Vec<String> {
        tokio::time::timeout(Duration::from_secs(5), &mut self.task)
            .await
            .unwrap()
            .unwrap()
    }
}

fn openai_provider(url: &str) -> AccountConfig {
    AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::openai(Some(url.into())),
        ModelCatalogId::new("openai").unwrap(),
        Vec::new(),
    )
}

fn mimo_provider(url: &str) -> AccountConfig {
    AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::compatible("MiMo API", url).with_protocol(ProtocolKind::MiMo),
        ModelCatalogId::new("mimo").unwrap(),
        Vec::new(),
    )
}

fn updated(result: ModelCatalogQueryResult) -> Vec<ModelInfo> {
    match result {
        ModelCatalogQueryResult::Updated { models, .. } => models,
        _ => panic!("expected updated catalog"),
    }
}

/// 账号模板描述投影携带权威协议与能力，并以 camelCase 产品 wire 输出和修订。
#[test]
fn account_template_descriptor_projects_protocol_and_camel_case_wire() {
    let mut registry = builtin_account_catalog().unwrap();
    let snapshot = registry.snapshot().unwrap();
    assert_eq!(registry.snapshot().unwrap().revision, snapshot.revision);
    let value = serde_json::to_value(&snapshot).unwrap();
    assert_eq!(value["schemaVersion"], 19);
    assert!(value.get("presets").is_none());
    assert!(value.get("templates").is_some());
    assert!(value.get("modelCatalogs").is_some());
    let wire_templates = value["templates"].as_array().unwrap();
    let deepseek_wire = wire_templates
        .iter()
        .find(|template| template["id"] == "deepseek")
        .unwrap();
    assert_eq!(deepseek_wire["protocol"], "deep_seek");
    assert_eq!(deepseek_wire["defaultBillingKind"], "metered");
    assert_eq!(deepseek_wire["supportsModelDiscovery"], true);
    assert_eq!(deepseek_wire.get("supportsUsageQuery"), Some(&json!(null)));
    assert!(deepseek_wire.get("default_billing_kind").is_none());
    assert!(deepseek_wire.get("supports_model_discovery").is_none());
    assert!(deepseek_wire.get("supports_usage_query").is_none());
    assert!(
        snapshot
            .templates
            .iter()
            .all(|template| template.supports_usage_query.is_none())
    );
    let compatible = snapshot
        .templates
        .iter()
        .find(|template| template.id == "openai-compatible")
        .unwrap();
    assert_eq!(
        compatible.default_billing_kind,
        pl_protocol::BillingKind::Unknown
    );
    assert!(!compatible.supports_model_discovery);
    assert!(deepseek_wire.get("suggestedModelId").is_some());
    assert!(deepseek_wire.get("modelCatalogId").is_some());
    assert!(deepseek_wire.get("baseUrl").is_some());
    assert!(deepseek_wire.get("displayName").is_some());
    assert!(
        deepseek_wire["serviceCapabilities"]
            .get("promptCacheDialect")
            .is_some()
    );
    assert!(
        value["modelCatalogs"]["deepseek"]["models"][0]
            .get("modelId")
            .is_some()
    );
    assert!(
        value["modelCatalogs"]["deepseek"]["models"][0]
            .get("contextWindow")
            .is_some()
    );
    assert!(
        value["modelCatalogs"]["deepseek"]["models"][0]["transport"]
            .get("defaultConnectionMode")
            .is_some()
    );

    // 用描述投影本身创建账号：协议来自 catalog，不按模板 ID 或地址猜测。
    let descriptor = snapshot
        .templates
        .iter()
        .find(|template| template.id == "deepseek")
        .unwrap();
    assert_eq!(
        descriptor.default_billing_kind,
        pl_protocol::BillingKind::Metered
    );
    assert!(descriptor.supports_model_discovery);
    let kind: ProtocolKind = descriptor.protocol.parse().unwrap();
    assert_eq!(kind, ProtocolKind::DeepSeek);
    let account = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::compatible(descriptor.display_name.clone(), descriptor.base_url.clone())
            .with_protocol(kind),
        ModelCatalogId::new(descriptor.model_catalog_id.clone()).unwrap(),
        Vec::new(),
    )
    .with_template(AccountTemplateId::new(descriptor.id.clone()).unwrap());
    assert_eq!(
        account.to_endpoint().unwrap().protocol,
        ProtocolKind::DeepSeek
    );
    assert_eq!(
        account.template_id().map(|id| id.as_str()),
        Some("deepseek")
    );
    assert_eq!(
        account.to_endpoint().unwrap().service_capabilities.files,
        pl_model::protocol::FileUploadCapability::DeepSeek
    );
    assert!(
        account
            .effective_models(None)
            .unwrap()
            .iter()
            .any(|model| model.model_id == descriptor.suggested_model_id)
    );

    for (id, protocol) in [
        ("openai", "open_ai"),
        ("deepseek", "deep_seek"),
        ("xai", "xai"),
        ("zhipu", "zhipu"),
        ("zhipu-coding-plan", "zhipu"),
        ("mimo-api", "mi_mo"),
        ("mimo-token-plan", "mi_mo"),
        ("openai-compatible", "open_ai_compatible"),
    ] {
        let template = snapshot
            .templates
            .iter()
            .find(|template| template.id == id)
            .unwrap();
        assert_eq!(template.protocol, protocol);
        assert_eq!(
            template.protocol.parse::<ProtocolKind>().unwrap().as_str(),
            protocol
        );
    }

    // Metadata is projected from the owned account/catalog, not inferred from its template ID.
    registry
        .templates
        .iter_mut()
        .find(|template| template.id.as_str() == "deepseek")
        .unwrap()
        .account
        .billing_kind = Some(pl_protocol::BillingKind::NoCharge);
    let billing_changed = registry.snapshot().unwrap();
    let changed_template = billing_changed
        .templates
        .iter()
        .find(|template| template.id == "deepseek")
        .unwrap();
    assert_eq!(
        changed_template.default_billing_kind,
        pl_protocol::BillingKind::NoCharge
    );
    assert_ne!(billing_changed.revision, snapshot.revision);
    let changed_wire = serde_json::to_value(changed_template).unwrap();
    assert_eq!(changed_wire["defaultBillingKind"], "noCharge");

    registry
        .model_catalogs
        .get_mut(&ModelCatalogId::new("deepseek").unwrap())
        .unwrap()
        .discovery = None;
    let discovery_changed = registry.snapshot().unwrap();
    assert!(
        !discovery_changed
            .templates
            .iter()
            .find(|template| template.id == "deepseek")
            .unwrap()
            .supports_model_discovery
    );
    assert_ne!(discovery_changed.revision, billing_changed.revision);
}

/// 当前 capability 来源 wire 只有 `template_defaults`；旧 `preset_defaults` 不再解析。
#[test]
fn template_capabilities_use_only_the_current_source_token() {
    let selection = AccountCapabilitySelection::TemplateDefaults;
    assert_eq!(
        serde_json::to_value(&selection).unwrap(),
        json!({"source": "template_defaults"})
    );
    assert_eq!(
        serde_json::from_value::<AccountCapabilitySelection>(
            json!({"source": "template_defaults"})
        )
        .unwrap(),
        selection
    );
    assert!(
        serde_json::from_value::<AccountCapabilitySelection>(json!({"source": "preset_defaults"}))
            .is_err(),
        "the retired capability source token is converted by the config migration, not parsed here"
    );

    let account = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::deepseek(None),
        ModelCatalogId::new("deepseek").unwrap(),
        Vec::new(),
    )
    .with_template(AccountTemplateId::new("deepseek").unwrap());
    let persisted = serde_json::to_value(&account).unwrap();
    assert_eq!(
        persisted["capabilities"]["source"], "template_defaults",
        "new rounds persist the current token"
    );
    let reread: AccountConfig = serde_json::from_value(persisted).unwrap();
    assert_eq!(
        reread.capabilities,
        AccountCapabilitySelection::TemplateDefaults
    );
}

#[tokio::test]
async fn overlay_retains_missing_bundled_members_disabled_and_keeps_exact_price_join() {
    let definition = bundled_model_definition("openai").unwrap();
    let known = &definition.models[0];
    let withdrawn = definition
        .models
        .iter()
        .find(|model| model.model_id != known.model_id)
        .unwrap();
    let server = Server::json(json!({"data":[{"id": known.model_id}, {"id":"online-only"}]})).await;
    let mut config = openai_provider(&server.url);
    let mut manual = ModelInfo::compatible("manual");
    manual.pricing = known.pricing.clone();
    if let AccountModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut config.catalog
    {
        additional_models.push(manual.clone());
    }
    let observed = updated(
        ModelCatalogQuery::for_account(&config)
            .unwrap()
            .execute(None)
            .await
            .unwrap(),
    );
    config.set_model_catalog_overlay(observed).unwrap();
    let catalog = config.effective_catalog(None).unwrap();
    let missing = catalog
        .iter()
        .find(|entry| entry.model.model_id == withdrawn.model_id)
        .unwrap();
    assert_eq!(missing.origin, AccountModelOrigin::Bundled);
    assert!(!missing.enabled);
    let known_entry = catalog
        .iter()
        .find(|entry| entry.model.model_id == known.model_id)
        .unwrap();
    assert_eq!(known_entry.origin, AccountModelOrigin::Online);
    assert_eq!(known_entry.model.pricing, known.pricing);
    let unknown = catalog
        .iter()
        .find(|entry| entry.model.model_id == "online-only")
        .unwrap();
    assert_eq!(unknown.origin, AccountModelOrigin::Online);
    assert_eq!(unknown.model.pricing, ModelPricing::Unknown);
    let manual_entry = catalog
        .iter()
        .find(|entry| entry.model.model_id == "manual")
        .unwrap();
    assert_eq!(manual_entry.origin, AccountModelOrigin::Manual);
    assert_eq!(manual_entry.model, manual);
    assert_eq!(
        model_descriptor(manual_entry).origin,
        pl_protocol::ModelOriginDto::Manual
    );
    server.finish().await;
}

#[test]
fn bundled_without_overlay_keeps_bundled_origin_and_manual_members() {
    let mut config = openai_provider("http://127.0.0.1:1");
    let manual = ModelInfo::compatible("manual");
    if let AccountModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut config.catalog
    {
        additional_models.push(manual.clone());
    }
    let catalog = config.effective_catalog(None).unwrap();
    assert!(
        catalog
            .iter()
            .any(|entry| entry.origin == AccountModelOrigin::Bundled)
    );
    assert!(catalog.iter().any(|entry| {
        entry.origin == AccountModelOrigin::Manual && entry.model.model_id == "manual"
    }));
    assert!(
        catalog
            .iter()
            .all(|entry| entry.origin != AccountModelOrigin::Online)
    );
}

#[tokio::test]
async fn same_id_manual_model_hides_online_entry() {
    let model_id = "shared-online";
    let server = Server::json(json!({"data":[{"id": model_id}]})).await;
    let mut config = openai_provider(&server.url);
    let mut manual = ModelInfo::compatible(model_id);
    manual.display_name = "Authoritative manual".into();
    if let AccountModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut config.catalog
    {
        additional_models.push(manual.clone());
    }
    let observed = updated(
        ModelCatalogQuery::for_account(&config)
            .unwrap()
            .execute(None)
            .await
            .unwrap(),
    );
    config.set_model_catalog_overlay(observed).unwrap();
    let catalog = config.effective_catalog(None).unwrap();
    let matches: Vec<_> = catalog
        .iter()
        .filter(|entry| entry.model.model_id == model_id)
        .collect();
    assert_eq!(matches.len(), 1);
    assert_eq!(matches[0].origin, AccountModelOrigin::Manual);
    assert_eq!(matches[0].model.display_name, "Authoritative manual");
    server.finish().await;
}

#[tokio::test]
async fn removing_same_id_manual_restores_online_entry() {
    let definition = bundled_model_definition("openai").unwrap();
    let known = &definition.models[0];
    let model_id = "shared-online";
    let server = Server::json(json!({"data":[{"id": model_id}, {"id": known.model_id}]})).await;
    let mut config = openai_provider(&server.url);
    let mut manual = ModelInfo::compatible(model_id);
    manual.display_name = "Temporary manual".into();
    if let AccountModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut config.catalog
    {
        additional_models.push(manual);
    }
    let observed = updated(
        ModelCatalogQuery::for_account(&config)
            .unwrap()
            .execute(None)
            .await
            .unwrap(),
    );
    config.set_model_catalog_overlay(observed).unwrap();
    let before = config.effective_catalog(None).unwrap();
    let matches: Vec<_> = before
        .iter()
        .filter(|entry| entry.model.model_id == model_id)
        .collect();
    assert_eq!(matches.len(), 1);
    assert_eq!(matches[0].origin, AccountModelOrigin::Manual);

    config.remove_manual_model(model_id).unwrap();
    let after = config.effective_catalog(None).unwrap();
    let restored = after
        .iter()
        .filter(|entry| entry.model.model_id == model_id)
        .collect::<Vec<_>>();
    // Restored same-model_id overlay members are not in the bundled membership/price
    // table, so pricing is Unknown. A bundled priced model_id cannot be used as the
    // same-model_id manual because catalog_membership rejects additional_models that
    // collide with bundled model_ids. Exact price join is asserted on the in-overlay
    // bundled priced model_id below.
    assert_eq!(restored.len(), 1);
    assert_eq!(restored[0].origin, AccountModelOrigin::Online);
    assert_eq!(restored[0].model.pricing, ModelPricing::Unknown);
    let priced = after
        .iter()
        .find(|entry| entry.model.model_id == known.model_id)
        .unwrap();
    assert_eq!(priced.origin, AccountModelOrigin::Online);
    assert_eq!(priced.model.pricing, known.pricing);
    server.finish().await;
}

#[test]
fn explicit_catalog_is_entirely_manual() {
    let models = vec![ModelInfo::compatible("one"), ModelInfo::compatible("two")];
    let config =
        AccountConfig::from_explicit_models(ProtocolEndpoint::openai(None), models.clone());
    let catalog = config.effective_catalog(None).unwrap();
    assert_eq!(
        catalog
            .iter()
            .map(|entry| (entry.model.model_id.as_str(), entry.origin))
            .collect::<Vec<_>>(),
        vec![
            ("one", AccountModelOrigin::Manual),
            ("two", AccountModelOrigin::Manual)
        ]
    );
    assert!(config.discovery_profile().unwrap().is_none());

    // An unfinished account can be saved and reconstructed, but never supplies a route.
    let account_id = AccountId::new("unfinished").unwrap();
    let empty = AccountConfig::from_explicit_models(
        ProtocolEndpoint::compatible("Unfinished account", "http://127.0.0.1:1"),
        Vec::new(),
    );
    empty.validate_declarations(&account_id).unwrap();
    let declarations = AgentModelConfig {
        accounts: [(account_id.clone(), empty)].into(),
        routes: Default::default(),
    };
    declarations.validate_declarations().unwrap();
    let mut restored: AgentModelConfig =
        serde_json::from_value(serde_json::to_value(&declarations).unwrap()).unwrap();
    restored.validate_declarations().unwrap();
    restored.reconcile_model_catalog().unwrap();
    restored.validate_declarations().unwrap();
    let account = &restored.accounts[&account_id];
    assert!(account.effective_catalog(None).unwrap().is_empty());
    assert!(
        account
            .selectable_catalog(Some(ModelType::Text))
            .unwrap()
            .is_empty()
    );
    assert!(account.discovery_profile().unwrap().is_none());
    assert!(matches!(
        restored.validate(),
        Err(pl_protocol::PureError::ConfigError(_))
    ));

    let role = AgentRoleId::new("unfinished-role").unwrap();
    let route = ModelRouteConfig {
        account_id,
        model_id: "not-declared".into(),
        effort: None,
    };
    assert!(matches!(
        restored.route_availability(&route),
        Err(pl_protocol::PureError::ConfigError(_))
    ));
    assert!(matches!(
        restored.resolve_route(role.clone(), &route),
        Err(pl_protocol::PureError::ConfigError(_))
    ));
    restored.routes.insert(role.clone(), route);
    assert!(matches!(
        restored.validate_declarations(),
        Err(pl_protocol::PureError::ConfigError(_))
    ));
    assert!(matches!(
        restored.resolve(&role),
        Err(pl_protocol::PureError::ConfigError(_))
    ));
}

#[test]
fn remove_manual_model_clears_overrides_and_rejects_non_manual_ids() {
    let mut config = openai_provider("http://127.0.0.1:1");
    let bundled_slug = config.effective_models(None).unwrap()[0].model_id.clone();
    let mut keep = ModelInfo::compatible("keep-manual");
    keep.display_name = "Keep".into();
    let mut remove = ModelInfo::compatible("remove-manual");
    remove.display_name = "Remove".into();
    if let AccountModelCatalogConfig::Bundled {
        additional_models,
        connection_overrides,
        auto_compact_overrides,
        ..
    } = &mut config.catalog
    {
        additional_models.extend([keep.clone(), remove.clone()]);
        connection_overrides.insert(
            "remove-manual".into(),
            pl_model::protocol::ConnectionMode::Http,
        );
        connection_overrides.insert(
            "keep-manual".into(),
            pl_model::protocol::ConnectionMode::Http,
        );
        auto_compact_overrides.insert("remove-manual".into(), 1_234);
        auto_compact_overrides.insert("keep-manual".into(), 2_000);
    }
    let before = config.clone();
    config.remove_manual_model("remove-manual").unwrap();
    let catalog = config.effective_catalog(None).unwrap();
    assert!(
        catalog
            .iter()
            .all(|entry| entry.model.model_id != "remove-manual")
    );
    assert!(catalog.iter().any(|entry| {
        entry.origin == AccountModelOrigin::Manual && entry.model.model_id == "keep-manual"
    }));
    assert!(!config.connection_overrides().contains_key("remove-manual"));
    assert!(
        !config
            .auto_compact_overrides()
            .contains_key("remove-manual")
    );
    assert_eq!(
        config.connection_overrides()["keep-manual"],
        pl_model::protocol::ConnectionMode::Http
    );
    assert_eq!(config.auto_compact_overrides()["keep-manual"], 2_000);

    let after_remove = config.clone();
    let rejected = config.remove_manual_model(&bundled_slug).unwrap_err();
    assert!(matches!(
        rejected,
        pl_protocol::PureError::ConfigError(message)
            if message == format!("unknown model: {bundled_slug}")
    ));
    assert_eq!(config, after_remove);

    let missing = config.remove_manual_model("does-not-exist").unwrap_err();
    assert!(matches!(
        missing,
        pl_protocol::PureError::ConfigError(message) if message == "unknown model: does-not-exist"
    ));
    assert_eq!(config, after_remove);
    assert_ne!(config, before);
}

#[test]
fn remove_manual_model_applies_to_explicit_catalog() {
    let keep = ModelInfo::compatible("keep");
    let remove = ModelInfo::compatible("remove");
    let mut config = AccountConfig::from_explicit_models(
        ProtocolEndpoint::openai(None),
        vec![keep.clone(), remove.clone()],
    );
    if let AccountModelCatalogConfig::Explicit {
        connection_overrides,
        auto_compact_overrides,
        ..
    } = &mut config.catalog
    {
        connection_overrides.insert("remove".into(), pl_model::protocol::ConnectionMode::Http);
        auto_compact_overrides.insert("remove".into(), 4_321);
        auto_compact_overrides.insert("keep".into(), 3_000);
    }
    config.remove_manual_model("remove").unwrap();
    let catalog = config.effective_catalog(None).unwrap();
    assert_eq!(
        catalog
            .iter()
            .map(|entry| entry.model.model_id.as_str())
            .collect::<Vec<_>>(),
        vec!["keep"]
    );
    assert!(!config.connection_overrides().contains_key("remove"));
    assert!(!config.auto_compact_overrides().contains_key("remove"));
    assert_eq!(config.auto_compact_overrides()["keep"], 3_000);
    let missing = config.remove_manual_model("remove").unwrap_err();
    assert!(matches!(
        missing,
        pl_protocol::PureError::ConfigError(message) if message == "unknown model: remove"
    ));
}

fn manual_model(model_id: &str) -> ModelInfo {
    let mut model = ModelInfo::compatible(model_id);
    model.context_window = None;
    model.max_output_tokens = None;
    model
        .binding
        .set_transport(ModelTransportProfile::responses_websocket());
    model
}

#[test]
fn historical_cache_preserves_complete_membership() {
    // 修复前写入的在线缓存可能仍含已被排除的非对话 model_id。
    let mut config = openai_provider("http://127.0.0.1:1");
    config
        .set_model_catalog_overlay(vec![
            manual_model("gpt-6-astra"),
            manual_model("gpt-image-2"),
            manual_model("text-embedding-3-large"),
            manual_model("GPT-Image-2"),
        ])
        .unwrap();
    let ids = config
        .effective_catalog(None)
        .unwrap()
        .into_iter()
        .filter(|entry| entry.origin == AccountModelOrigin::Online)
        .map(|entry| entry.model.model_id)
        .collect::<Vec<_>>();
    assert_eq!(
        ids,
        [
            "GPT-Image-2",
            "gpt-6-astra",
            "gpt-image-2",
            "text-embedding-3-large"
        ]
    );
}

#[test]
fn online_and_manual_members_share_one_route() {
    let mut config = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::openai(Some("http://127.0.0.1:1".into())),
        ModelCatalogId::new("openai").unwrap(),
        vec![manual_model("gpt-image-manual")],
    );
    config
        .set_model_catalog_overlay(vec![
            manual_model("gpt-6-astra"),
            manual_model("gpt-image-manual"),
        ])
        .unwrap();
    assert_eq!(
        config
            .effective_catalog(None)
            .unwrap()
            .iter()
            .filter(|entry| entry.origin != AccountModelOrigin::Bundled)
            .map(|entry| (entry.model.model_id.as_str(), entry.origin))
            .collect::<Vec<_>>(),
        vec![
            ("gpt-6-astra", AccountModelOrigin::Online),
            ("gpt-image-manual", AccountModelOrigin::Manual)
        ]
    );
}

#[test]
fn explicit_catalogs_do_not_acquire_discovery() {
    // 智谱目录不声明发现能力，不可能持有在线缓存；其手工图像类模型保留。
    let mut zhipu = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::zhipu(None),
        ModelCatalogId::new("zhipu").unwrap(),
        vec![ModelInfo::compatible("gpt-image-manual")],
    );
    assert!(zhipu.discovery_profile().unwrap().is_none());
    assert!(matches!(
        zhipu.set_model_catalog_overlay(Vec::new()),
        Err(pl_protocol::PureError::Protocol(_))
    ));
    assert!(zhipu.effective_catalog(None).unwrap().iter().any(|entry| {
        entry.model.model_id == "gpt-image-manual" && entry.origin == AccountModelOrigin::Manual
    }));
    // openai-compatible 是用户完全自定义的显式目录，同样不排除任何条目。
    let mut compatible = AccountConfig::from_explicit_models(
        ProtocolEndpoint::compatible("Custom", "http://127.0.0.1:1"),
        vec![
            ModelInfo::compatible("gpt-image-2"),
            ModelInfo::compatible("text-embedding-3-large"),
        ],
    );
    assert!(compatible.discovery_profile().unwrap().is_none());
    assert!(matches!(
        compatible.set_model_catalog_overlay(Vec::new()),
        Err(pl_protocol::PureError::Protocol(_))
    ));
    assert_eq!(
        compatible
            .effective_catalog(None)
            .unwrap()
            .iter()
            .map(|entry| entry.model.model_id.as_str())
            .collect::<Vec<_>>(),
        vec!["gpt-image-2", "text-embedding-3-large"]
    );
}

#[tokio::test]
async fn discovery_keeps_all_model_families_and_exact_case() {
    let server = Server::json(json!({
        "data":[
            {"id":"gpt-6-astra"},
            {"id":"gpt-image-2"},
            {"id":"gpt-image-1.5"},
            {"id":"dall-e-3"},
            {"id":"text-embedding-3-large"},
            {"id":"tts-1"},
            {"id":"whisper-1"},
            {"id":"omni-moderation-latest"},
            {"id":"text-moderation-latest"},
            {"id":"GPT-Image-2"}
        ]
    }))
    .await;
    let config = openai_provider(&server.url);
    let discovery = config.discovery_profile().unwrap().unwrap();
    assert_eq!(
        discovery.transport,
        ModelTransportProfile::responses_websocket()
    );
    let models = updated(
        ModelCatalogQuery::for_account(&config)
            .unwrap()
            .execute(None)
            .await
            .unwrap(),
    );
    // 前缀匹配大小写敏感：不缩小写家族之外的相似 model_id。
    assert_eq!(
        models
            .iter()
            .map(|model| model.model_id.as_str())
            .collect::<Vec<_>>(),
        vec![
            "gpt-6-astra",
            "gpt-image-2",
            "gpt-image-1.5",
            "dall-e-3",
            "text-embedding-3-large",
            "tts-1",
            "whisper-1",
            "omni-moderation-latest",
            "text-moderation-latest",
            "GPT-Image-2"
        ]
    );
    server.finish().await;
}

#[tokio::test]
async fn discovery_keeps_manual_members_and_complete_online_inventory() {
    let server = Server::json(json!({
        "data":[{"id":"gpt-6-astra"},{"id":"gpt-image-2"}]
    }))
    .await;
    let catalog_id = ModelCatalogId::new("openai").unwrap();
    let bundled = builtin_model_catalog(&catalog_id).unwrap();
    let mut config = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::openai(Some(server.url.clone())),
        catalog_id,
        vec![manual_model("gpt-image-manual")],
    );
    // 尚无在线成功观察时，内置默认名单完整保留；排除声明只作用于在线结果。
    let defaults = config.effective_catalog(None).unwrap();
    assert_eq!(
        defaults
            .iter()
            .filter(|entry| entry.origin == AccountModelOrigin::Bundled)
            .count(),
        bundled.models.len()
    );
    assert!(defaults.iter().any(|entry| {
        entry.origin == AccountModelOrigin::Manual && entry.model.model_id == "gpt-image-manual"
    }));
    let models = updated(
        ModelCatalogQuery::for_account(&config)
            .unwrap()
            .execute(None)
            .await
            .unwrap(),
    );
    config.set_model_catalog_overlay(models).unwrap();
    let catalog = config.effective_catalog(None).unwrap();
    assert_eq!(
        catalog
            .iter()
            .filter(|entry| entry.origin != AccountModelOrigin::Bundled)
            .map(|entry| (entry.model.model_id.as_str(), entry.origin))
            .collect::<Vec<_>>(),
        vec![
            ("gpt-6-astra", AccountModelOrigin::Online),
            ("gpt-image-2", AccountModelOrigin::Online),
            ("gpt-image-manual", AccountModelOrigin::Manual)
        ]
    );
    server.finish().await;
}

#[tokio::test]
async fn discovery_keeps_mimo_media_models() {
    let server = Server::json(json!({
        "data":[
            {"id":"mimo-v2.5-pro"},
            {"id":"mimo-v2.5-asr"},
            {"id":"mimo-v2.5-tts"},
            {"id":"mimo-v2.5-tts-voiceclone"},
            {"id":"mimo-v2.5-tts-voicedesign"}
        ]
    }))
    .await;
    let config = mimo_provider(&server.url);
    let discovery = config.discovery_profile().unwrap().unwrap();
    assert_eq!(
        discovery.transport,
        ModelTransportProfile::chat_completions_http()
    );
    // MiMo 仍只按精确 model_id 排除语音模型，不声明前缀家族。

    let models = updated(
        ModelCatalogQuery::for_account(&config)
            .unwrap()
            .execute(None)
            .await
            .unwrap(),
    );
    assert_eq!(
        models
            .iter()
            .map(|model| model.model_id.as_str())
            .collect::<Vec<_>>(),
        vec![
            "mimo-v2.5-pro",
            "mimo-v2.5-asr",
            "mimo-v2.5-tts",
            "mimo-v2.5-tts-voiceclone",
            "mimo-v2.5-tts-voicedesign"
        ]
    );
    server.finish().await;
}

#[tokio::test]
async fn media_only_inventory_remains_selectable() {
    let server = Server::json(json!({
        "data":[
            {"id":"mimo-v2.5-asr"},
            {"id":"mimo-v2.5-tts"}
        ]
    }))
    .await;
    let mut config = mimo_provider(&server.url);
    let models = updated(
        ModelCatalogQuery::for_account(&config)
            .unwrap()
            .execute(None)
            .await
            .unwrap(),
    );
    assert_eq!(models.len(), 2);
    config.set_model_catalog_overlay(models).unwrap();
    assert_eq!(
        config
            .effective_catalog(None)
            .unwrap()
            .iter()
            .filter(|entry| entry.origin == AccountModelOrigin::Online)
            .count(),
        2
    );
    server.finish().await;
}

#[tokio::test]
async fn chat_discovery_profile_accepts_chat_transport_and_joins_exact_prices() {
    let catalog = builtin_model_catalog(&ModelCatalogId::new("mimo").unwrap()).unwrap();
    let priced = catalog
        .models
        .iter()
        .find(|model| model.model_id == "mimo-v2.5-pro")
        .unwrap();
    let server =
        Server::json(json!({"data":[{"id":"mimo-v2.5-pro"},{"id":"mimo-chat-only"}]})).await;
    let mut config = mimo_provider(&server.url);
    let models = updated(
        ModelCatalogQuery::for_account(&config)
            .unwrap()
            .execute(None)
            .await
            .unwrap(),
    );
    assert_eq!(
        models[0].binding.transport,
        ModelTransportProfile::chat_completions_http()
    );
    config.set_model_catalog_overlay(models).unwrap();
    let catalog = config.effective_catalog(None).unwrap();
    let joined = catalog
        .iter()
        .find(|entry| entry.model.model_id == "mimo-v2.5-pro")
        .unwrap();
    assert_eq!(joined.origin, AccountModelOrigin::Online);
    assert_eq!(joined.model.pricing, priced.pricing);
    let unknown = catalog
        .iter()
        .find(|entry| entry.model.model_id == "mimo-chat-only")
        .unwrap();
    assert_eq!(unknown.model.pricing, ModelPricing::Unknown);
    server.finish().await;
}

#[test]
fn unknown_online_price_is_not_zero_and_descriptor_keeps_origin() {
    let mut config = openai_provider("http://127.0.0.1:1");
    let mut observed = ModelInfo::compatible("online-only");
    observed
        .binding
        .set_transport(ModelTransportProfile::responses_websocket());
    observed.context_window = None;
    observed.max_output_tokens = None;
    config.set_model_catalog_overlay(vec![observed]).unwrap();
    let catalog = config.effective_catalog(None).unwrap();
    let entry = catalog
        .iter()
        .find(|entry| entry.model.model_id == "online-only")
        .unwrap();
    assert_eq!(entry.origin, AccountModelOrigin::Online);
    assert_eq!(entry.model.pricing, ModelPricing::Unknown);
    let descriptor = model_descriptor(entry);
    assert_eq!(descriptor.origin, pl_protocol::ModelOriginDto::Online);
    assert_eq!(descriptor.pricing, None);
}
