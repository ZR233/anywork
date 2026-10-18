//! Discovery contract through public API and real localhost HTTP. No live credentials or catalog mirror.
use pl_model::{
    config::{
        AgentModelConfig, AgentRoleId, ModelCatalogId, ModelRouteAvailability, ModelRouteConfig,
        ProviderConfig, ProviderId, ReasoningEffort, model_descriptor,
    },
    model::{
        BundledModelDefinition, ModelDefinitionError, ModelInfo, ModelModality, ModelParameter,
        ModelPricing, ModelTransportProfile, ParameterWire, WireAssignment,
        bundled_model_definition,
    },
    provider::{
        ProviderAdapterKind, ProviderConnectionMode, ProviderEndpoint,
        discovery::{
            ModelCatalogQuery, ModelCatalogQueryCache, ModelCatalogQueryError,
            ModelCatalogQueryResult,
        },
    },
};
use pretty_assertions::assert_eq;
use serde_json::{Value, json};
use std::{collections::HashMap, time::Duration};
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
    async fn responses(responses: Vec<String>) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let task = tokio::spawn(async move {
            let mut requests = Vec::new();
            for response in responses {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut bytes = Vec::new();
                while !bytes.ends_with(b"\r\n\r\n") {
                    let mut byte = [0];
                    socket.read_exact(&mut byte).await.unwrap();
                    bytes.push(byte[0]);
                    assert!(bytes.len() < 16_384);
                }
                requests.push(String::from_utf8(bytes).unwrap());
                // An oversized client can close before the fixture finishes writing.
                let _ = socket.write_all(response.as_bytes()).await;
            }
            requests
        });
        Self { url, task }
    }
    async fn json(body: Value) -> Self {
        Self::responses(vec![http(200, "", &body.to_string())]).await
    }
    async fn finish(mut self) -> Vec<String> {
        tokio::time::timeout(Duration::from_secs(5), &mut self.task)
            .await
            .unwrap()
            .unwrap()
    }
}
fn http(status: u16, headers: &str, body: &str) -> String {
    format!(
        "HTTP/1.1 {status} Test\r\nContent-Length: {}\r\nConnection: close\r\n{headers}\r\n{body}",
        body.len()
    )
}
fn provider(url: &str, adapter: ProviderAdapterKind) -> ProviderConfig {
    let (endpoint, id) = match adapter {
        ProviderAdapterKind::OpenAi => (ProviderEndpoint::openai(Some(url.into())), "openai"),
        ProviderAdapterKind::DeepSeek => (ProviderEndpoint::deepseek(Some(url.into())), "deepseek"),
        ProviderAdapterKind::Xai => (ProviderEndpoint::xai(Some(url.into())), "xai"),
        _ => unreachable!(),
    };
    ProviderConfig::from_bundled_catalog(endpoint, ModelCatalogId::new(id).unwrap(), Vec::new())
}
fn updated(result: ModelCatalogQueryResult) -> Vec<ModelInfo> {
    match result {
        ModelCatalogQueryResult::Updated { models, .. } => models,
        _ => panic!("expected updated catalog"),
    }
}
fn cached_model(slug: &str, adapter: ProviderAdapterKind) -> ModelInfo {
    let mut model = ModelInfo::compatible(slug);
    model.context_window = None;
    model.max_output_tokens = None;
    model
        .binding
        .set_transport(if adapter == ProviderAdapterKind::OpenAi {
            ModelTransportProfile::responses_websocket()
        } else {
            ModelTransportProfile::responses_http()
        });
    model
}
async fn discover(body: Value, adapter: ProviderAdapterKind) -> Vec<ModelInfo> {
    let server = Server::json(body).await;
    let query = ModelCatalogQuery::for_provider(&provider(&server.url, adapter)).unwrap();
    let result = updated(query.execute(None).await.unwrap());
    server.finish().await;
    result
}

#[tokio::test]
async fn current_endpoint_prefix_query_auth_and_safe_identity_are_used() {
    let server = Server::json(json!({"data":[{"id":"unregistered-Future-ID"}]})).await;
    let mut config = provider(
        &format!("{}/tenant/proxy/?region=synthetic-secret", server.url),
        ProviderAdapterKind::OpenAi,
    );
    config.bearer_token = Some("synthetic-token".into());
    config.http_headers = Some(HashMap::from([(
        "x-account".into(),
        "synthetic-account".into(),
    )]));
    let query = ModelCatalogQuery::for_provider(&config).unwrap();
    let identity = query.identity().to_owned();
    assert_eq!(identity.len(), 64);
    assert!(!format!("{query:?}").contains("synthetic"));
    let models = updated(query.execute(None).await.unwrap());
    let headers = server.finish().await;
    assert!(
        headers[0].starts_with("GET /tenant/proxy/models?region=synthetic-secret HTTP/1.1\r\n")
    );
    let lower = headers[0].to_ascii_lowercase();
    assert!(lower.contains("authorization: bearer synthetic-token\r\n"));
    assert!(lower.contains("x-account: synthetic-account\r\n"));
    let model = &models[0];
    assert_eq!(model.slug, "unregistered-Future-ID");
    assert_eq!(model.resolved_context_window(), None);
    assert_eq!(model.max_output_tokens, None);
    assert!(model.supported_efforts().is_empty());
    assert!(!model.capabilities.temperature);
    assert!(!model.capabilities.tools.function_calling);
    assert!(
        model
            .capabilities
            .supports_input_modality(ModelModality::Image)
    );
    assert_eq!(
        model.binding.transport,
        ModelTransportProfile::responses_websocket()
    );
    assert_eq!(model.pricing, ModelPricing::Unknown);
    config.set_model_catalog_overlay(models.clone()).unwrap();
    let descriptor: pl_model::config::ModelDescriptor =
        model_descriptor(&config.effective_catalog().unwrap()[0]);
    assert_eq!(descriptor.context_window, None);
    assert_eq!(descriptor.max_context_window, None);
    assert_eq!(descriptor.max_output_tokens, None);
    assert_eq!(descriptor.pricing, None);
    assert_eq!(descriptor.reasoning, None);
    for change in 0..4 {
        let mut changed = config.clone();
        match change {
            0 => changed.base_url.push_str("&other=1"),
            1 => changed.bearer_token = Some("new-token".into()),
            2 => {
                changed
                    .http_headers
                    .as_mut()
                    .unwrap()
                    .insert("x-account".into(), "new-account".into());
            }
            _ => changed.base_url = format!("{}/different/prefix", server_url_for_identity()),
        }
        assert_ne!(
            ModelCatalogQuery::for_provider(&changed)
                .unwrap()
                .identity(),
            identity
        );
    }
    config.http_headers = Some(HashMap::from([(
        "X-Account".into(),
        "synthetic-account".into(),
    )]));
    assert_eq!(
        ModelCatalogQuery::for_provider(&config).unwrap().identity(),
        identity
    );
    let explicit = ProviderConfig::from_explicit_models(
        ProviderEndpoint::openai(None),
        vec![ModelInfo::compatible("manual")],
    );
    assert!(matches!(
        ModelCatalogQuery::for_provider(&explicit),
        Err(ModelCatalogQueryError::Unsupported)
    ));
    let unsupported = ProviderConfig::from_bundled_catalog(
        ProviderEndpoint::zhipu(None),
        ModelCatalogId::new("zhipu").unwrap(),
        Vec::new(),
    );
    assert!(matches!(
        ModelCatalogQuery::for_provider(&unsupported),
        Err(ModelCatalogQueryError::Unsupported)
    ));
    config.http_headers = Some(HashMap::from([
        ("x-account".into(), "one".into()),
        ("X-Account".into(), "two".into()),
    ]));
    assert!(matches!(
        ModelCatalogQuery::for_provider(&config),
        Err(ModelCatalogQueryError::Configuration)
    ));
}
fn server_url_for_identity() -> &'static str {
    "http://127.0.0.1:1"
}

#[tokio::test]
async fn rich_envelopes_drive_real_inference_wire_and_unknown_pricing_preserves_usage() {
    use pl_model::{
        completion::{
            AttachmentInput, AttachmentModality, AttachmentSource, CompletionRequest, ContentPart,
            Message, MessageContent, MessageRole, ReasoningConfig,
        },
        runtime::{ModelInvocationContext, ModelRuntime},
    };
    use pl_protocol::{PricingOutcome, UnpricedReason};
    use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
    for (adapter, body, effort_path) in [
        (
            ProviderAdapterKind::DeepSeek,
            json!({"data":[{"id":"future-model","name":"Future","context_window":64000,"max_output_tokens":8000,"effort":{"supported_levels":["gentle","new-ultra"],"default_level":"new-ultra"},"pricing":{"input":0},"supports_function_calling":true}]}),
            "reasoning_effort",
        ),
        (
            ProviderAdapterKind::OpenAi,
            json!({"models":[{"slug":"future-model","display_name":"Future","description":"independent metadata","context_window":64000,"max_context_window":128000,"auto_compact_token_limit":12000,"supported_reasoning_levels":[{"effort":"gentle","description":"less"},{"effort":"new-ultra","description":"more"}],"default_reasoning_level":"new-ultra","base_instructions":"DO NOT IMPORT","shell_type":"powershell","supports_temperature":false}]}),
            "reasoning",
        ),
        (
            ProviderAdapterKind::Xai,
            json!({"data":[{"id":"future-model","context_window":64000,"supported_reasoning_levels":[{"effort":"gentle"},{"effort":"new-ultra"}],"default_reasoning_level":"new-ultra"}]}),
            "reasoning",
        ),
    ] {
        let models = discover(body, adapter).await;
        let mut model = models[0].clone();
        assert_eq!(model.supported_efforts(), ["gentle", "new-ultra"]);
        assert_eq!(model.default_effort().as_deref(), Some("gentle"));
        assert_eq!(model.context_window, Some(64000));
        assert!(
            model
                .capabilities
                .supports_input_modality(ModelModality::Image)
        );
        assert!(model.base_instructions.is_empty());
        let mut config = provider("http://127.0.0.1:1", adapter);
        config.set_model_catalog_overlay(models).unwrap();
        let descriptor = model_descriptor(&config.effective_catalog().unwrap()[0]);
        assert_eq!(descriptor.context_window, Some(64000));
        let preset = (adapter == ProviderAdapterKind::OpenAi).then_some(12_000);
        assert_eq!(descriptor.auto_compact_token_limit, preset);
        assert_eq!(
            model.resolved_auto_compact_limit(),
            Some(preset.unwrap_or(57_600))
        );
        assert_eq!(descriptor.pricing, None);
        let reasoning = descriptor.reasoning.unwrap();
        assert_eq!(reasoning.candidates, ["gentle", "new-ultra"]);
        assert_eq!(reasoning.default.as_deref(), Some("gentle"));
        let fixture = FixtureServer::start(vec![
            Step::prompt(
                Protocol::ResponsesHttp,
                "hello",
                0,
                Reply::Sse(responses_text("answer", "discovery-wire", "future-model")),
            ),
            Step::prompt(
                Protocol::ResponsesHttp,
                "hello",
                1,
                Reply::Sse(responses_text(
                    "answer",
                    "discovery-disabled",
                    "future-model",
                )),
            ),
        ])
        .await
        .unwrap();
        let endpoint = match adapter {
            ProviderAdapterKind::OpenAi => ProviderEndpoint::openai(Some(fixture.base_url())),
            ProviderAdapterKind::Xai => ProviderEndpoint::xai(Some(fixture.base_url())),
            _ => ProviderEndpoint::deepseek(Some(fixture.base_url())),
        };
        model.binding.transport.default_connection_mode =
            pl_model::provider::ProviderConnectionMode::Http;
        let runtime = ModelRuntime::new(endpoint, model).unwrap();
        let mut png = std::io::Cursor::new(Vec::new());
        image::DynamicImage::new_rgb8(1, 1)
            .write_to(&mut png, image::ImageFormat::Png)
            .unwrap();
        let request = CompletionRequest::builder()
            .messages(vec![Message {
                role: MessageRole::User,
                content: MessageContent::new(vec![
                    ContentPart::Text {
                        text: "hello".into(),
                    },
                    ContentPart::Attachment {
                        attachment_id: "pixel".into(),
                        modality: AttachmentModality::Image,
                        media_type: "image/png".into(),
                        filename: None,
                    },
                ]),
                reasoning_content: None,
                tool_calls: None,
                tool_result: None,
                metadata: Default::default(),
                presentation: Default::default(),
            }])
            .attachments(vec![AttachmentInput {
                attachment_id: "pixel".into(),
                modality: AttachmentModality::Image,
                media_type: "image/png".into(),
                filename: None,
                source: AttachmentSource::Bytes {
                    bytes: std::sync::Arc::from(png.into_inner()),
                },
            }])
            .reasoning(Some(ReasoningConfig {
                effort: Some("new-ultra".into()),
                summary: None,
            }))
            .build();
        let response = runtime
            .complete(request.clone(), ModelInvocationContext::default())
            .await
            .unwrap();
        assert_eq!(response.content.as_deref(), Some("answer"));
        assert_eq!(
            response.accounting.pricing,
            PricingOutcome::Unpriced {
                reason: UnpricedReason::MissingPrice
            }
        );
        assert!(response.accounting.usage.input_tokens.is_some());
        assert!(response.accounting.usage.output_tokens.is_some());
        let disabled = runtime
            .with_pricing_mode(pl_model::model::PricingMode::Disabled)
            .complete(request, ModelInvocationContext::default())
            .await
            .unwrap();
        assert_eq!(disabled.accounting.pricing, PricingOutcome::Disabled);
        assert_eq!(disabled.accounting.usage, response.accounting.usage);
        let records = fixture.finish().await.unwrap();
        if effort_path == "reasoning" {
            assert_eq!(records[0].body[effort_path]["effort"], "new-ultra");
        } else {
            assert_eq!(records[0].body[effort_path], "new-ultra");
            assert_eq!(records[0].body["thinking"]["type"], "enabled");
        }
        assert!(records[0].body.get("temperature").is_none());
        for record in &records {
            assert_eq!(record.body["input"][0]["content"][1]["type"], "input_image");
            assert!(
                record.body["input"][0]["content"][1]["image_url"]
                    .as_str()
                    .unwrap()
                    .starts_with("data:image/png;base64,")
            );
        }
    }
}

#[tokio::test]
async fn missing_metadata_uses_exact_success_then_default_but_explicit_empty_and_false_win() {
    let definition = bundled_model_definition("openai").unwrap();
    let known = definition
        .models
        .iter()
        .find(|m| {
            !m.supported_efforts().is_empty()
                && m.capabilities.supports_input_modality(ModelModality::Image)
        })
        .unwrap();
    let server = Server::responses(vec![
        http(200,"", &json!({"data":[{"id":known.slug}]}).to_string()),
        http(200,"", &json!({"models":[{"slug":known.slug,"supported_reasoning_levels":[],"input_modalities":[],"output_modalities":[],"supports_streaming":false,"supports_function_calling":false}]}).to_string()),
        http(200,"", &json!({"data":[{"id":"cached-only"}]}).to_string()),
        http(200,"", &json!({"data":[{"id":"cached-only","capabilities":{"input":[{"modality":"text","sources":[]}]}}]}).to_string()),
    ]).await;
    let query =
        ModelCatalogQuery::for_provider(&provider(&server.url, ProviderAdapterKind::OpenAi))
            .unwrap();
    let first = updated(query.execute(None).await.unwrap());
    assert_eq!(first[0].supported_efforts(), known.supported_efforts());
    assert_eq!(first[0].context_window, known.context_window);
    let second = updated(query.execute(None).await.unwrap());
    assert!(second[0].supported_efforts().is_empty());
    assert!(second[0].capabilities.input.is_empty());
    assert!(second[0].capabilities.output.is_empty());
    assert!(second[0].binding.request.media.is_empty());
    assert!(!second[0].capabilities.streaming);
    assert!(!second[0].capabilities.tools.function_calling);
    let mut cached = first[0].clone();
    cached.slug = "cached-only".into();
    cached.context_window = Some(12345);
    cached.capabilities.input = vec![pl_model::model::ModelInputCapability::text()];
    cached.binding.request.media.clear();
    let cache = ModelCatalogQueryCache {
        identity: query.identity().into(),
        etag: None,
        models: vec![cached],
    };
    let third = updated(query.execute(Some(&cache)).await.unwrap());
    assert_eq!(third[0].context_window, Some(12345));
    assert_eq!(third[0].pricing, ModelPricing::Unknown);
    assert!(
        third[0]
            .capabilities
            .supports_input_modality(ModelModality::Image)
    );
    let fourth = updated(query.execute(Some(&cache)).await.unwrap());
    assert!(
        !fourth[0]
            .capabilities
            .supports_input_modality(ModelModality::Image)
    );
    assert!(fourth[0].binding.request.media.is_empty());
    server.finish().await;
}

#[tokio::test]
async fn gpt61_id_only_inventory_and_old_fallback_cache_enable_real_image_input() {
    use pl_model::{
        completion::{
            AttachmentInput, AttachmentModality, AttachmentSource, CompletionRequest, ContentPart,
            Message, MessageContent, MessageRole,
        },
        runtime::{ModelInvocationContext, ModelRuntime},
    };
    use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
    let adapter = ProviderAdapterKind::OpenAi;
    let slug = "gpt-6.1-sol";
    let mut old = discover(
        json!({"data":[{"id":"unregistered-old-id","display_name":"GPT-6.1 Sol","description":"Provider description without capability declarations."}]}),
        adapter,
    )
    .await
    .remove(0);
    old.slug = slug.into();
    // Persisted skeleton from the previous text-only normalization rule.
    old.capabilities.input = vec![pl_model::model::ModelInputCapability::text()];
    old.binding.request.media.clear();
    let description = old.description.clone();
    let server = Server::responses(vec![
        http(200, "", &json!({"data":[{"id":slug,"display_name":"GPT-6.1 Sol","created":1790640000,"object":"model","owned_by":"openai","type":"model"}]}).to_string()),
        http(200, "", &json!({"data":[{"id":slug,"input_modalities":["text"],"supported_reasoning_levels":[]}]}).to_string()),
    ]).await;
    let mut config = provider(&server.url, adapter);
    let query = ModelCatalogQuery::for_provider(&config).unwrap();
    let cache = ModelCatalogQueryCache {
        identity: query.identity().into(),
        etag: None,
        models: vec![old],
    };
    // Startup/304/failure retain the successful inventory, enriched before GUI projection.
    config
        .set_model_catalog_overlay(cache.models.clone())
        .unwrap();
    let startup = config.effective_models().unwrap().remove(0);
    assert_eq!(startup.display_name, "GPT-6.1 Sol");
    assert_eq!(startup.description, description);
    assert!(
        startup
            .capabilities
            .supports_input_modality(ModelModality::Image)
    );
    let models = updated(query.execute(Some(&cache)).await.unwrap());
    config.set_model_catalog_overlay(models).unwrap();
    let mut model = config.effective_models().unwrap().remove(0);
    assert_eq!(model.slug, slug);
    assert_eq!(model.description, description);
    assert_eq!(model.context_window, Some(1_050_000));
    assert_eq!(
        model_descriptor(&pl_model::config::ProviderModelEntry {
            model: model.clone(),
            origin: pl_model::config::ProviderModelOrigin::Online,
        })
        .auto_compact_token_limit,
        Some(475_000)
    );
    assert_eq!(model.resolved_auto_compact_limit(), Some(475_000));
    assert_eq!(model.max_output_tokens, Some(128_000));
    assert_eq!(
        model.supported_efforts(),
        ["low", "medium", "high", "xhigh", "max"]
    );
    assert!(
        model_descriptor(&pl_model::config::ProviderModelEntry {
            model: model.clone(),
            origin: pl_model::config::ProviderModelOrigin::Online,
        })
        .pricing
        .is_some()
    );
    let explicit = updated(query.execute(None).await.unwrap());
    config.set_model_catalog_overlay(explicit).unwrap();
    let explicit = config.effective_models().unwrap().remove(0);
    assert!(
        !explicit
            .capabilities
            .supports_input_modality(ModelModality::Image)
    );
    assert!(explicit.supported_efforts().is_empty());
    server.finish().await;

    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "describe",
        0,
        Reply::Sse(responses_text("a pixel", "gpt61-image", slug)),
    )])
    .await
    .unwrap();
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    let runtime =
        ModelRuntime::new(ProviderEndpoint::openai(Some(fixture.base_url())), model).unwrap();
    let mut png = std::io::Cursor::new(Vec::new());
    image::DynamicImage::new_rgb8(1, 1)
        .write_to(&mut png, image::ImageFormat::Png)
        .unwrap();
    let request = CompletionRequest::builder()
        .messages(vec![Message {
            role: MessageRole::User,
            content: MessageContent::new(vec![
                ContentPart::Text {
                    text: "describe".into(),
                },
                ContentPart::Attachment {
                    attachment_id: "pixel".into(),
                    modality: AttachmentModality::Image,
                    media_type: "image/png".into(),
                    filename: None,
                },
            ]),
            reasoning_content: None,
            tool_calls: None,
            tool_result: None,
            metadata: Default::default(),
            presentation: Default::default(),
        }])
        .attachments(vec![AttachmentInput {
            attachment_id: "pixel".into(),
            modality: AttachmentModality::Image,
            media_type: "image/png".into(),
            filename: None,
            source: AttachmentSource::Bytes {
                bytes: std::sync::Arc::from(png.into_inner()),
            },
        }])
        .build();
    let reply = runtime
        .complete(request, ModelInvocationContext::default())
        .await
        .unwrap();
    assert_eq!(reply.content.as_deref(), Some("a pixel"));
    let records = fixture.finish().await.unwrap();
    assert_eq!(records[0].body["model"], slug);
    assert_eq!(
        records[0].body["input"][0]["content"][1]["type"],
        "input_image"
    );
    assert!(
        records[0].body["input"][0]["content"][1]["image_url"]
            .as_str()
            .unwrap()
            .starts_with("data:image/png;base64,")
    );
}

#[tokio::test]
async fn observed_window_lifts_undeclared_inherited_budget_limit() {
    // 真实 DeepSeek 名单只声明 context_window，且大于内置默认上限。
    let server = Server::json(json!({
        "data":[{"id":"deepseek-flash","context_window":1_048_576}]
    }))
    .await;
    let mut config = provider(&server.url, ProviderAdapterKind::DeepSeek);
    let models = updated(
        ModelCatalogQuery::for_provider(&config)
            .unwrap()
            .execute(None)
            .await
            .unwrap(),
    );
    assert_eq!(models.len(), 1);
    assert_eq!(models[0].slug, "deepseek-flash");
    assert_eq!(models[0].context_window, Some(1_048_576));
    assert_eq!(models[0].max_context_window, Some(1_048_576));
    // 未违反上限的继承默认预算保持原值。
    assert_eq!(models[0].max_output_tokens, Some(384_000));
    config.set_model_catalog_overlay(models).unwrap();
    let entry = &config.effective_catalog().unwrap()[0];
    assert_eq!(entry.origin, pl_model::config::ProviderModelOrigin::Online);
    assert_eq!(entry.model.max_context_window, Some(1_048_576));
    server.finish().await;
}

/// 在线显式声明必须优先于同精确 ID 的内置定义；单侧预算声明按观测事实收敛，
/// reasoning 关闭与空候选不补回内置项，最后一次成功结果经同身份缓存往返也不被内置骨架复活。
#[tokio::test]
async fn online_declarations_override_builtin_metadata_across_successful_polls() {
    let definition = bundled_model_definition("openai").unwrap();
    let builtin = definition
        .models
        .iter()
        .find(|model| model.slug == "gpt-6.1-sol")
        .unwrap();
    assert!(!builtin.supported_efforts().is_empty());
    assert!(builtin.capabilities.reasoning);
    let server = Server::responses(vec![
        http(
            200,
            "",
            &json!({"data":[{"id":"gpt-6.1-sol","context_window":2_000_000}]}).to_string(),
        ),
        http(
            200,
            "",
            &json!({"data":[{"id":"gpt-6.1-sol","max_context_window":300_000}]}).to_string(),
        ),
        http(
            200,
            "",
            &json!({"data":[{"id":"gpt-6.1-sol","supports_reasoning":false}]}).to_string(),
        ),
        http(200, "", &json!({"data":[{"id":"gpt-6.1-sol"}]}).to_string()),
        http(
            200,
            "",
            &json!({"data":[{"id":"gpt-6.1-sol","parameters":[]}]}).to_string(),
        ),
        http(
            200,
            "",
            &json!({"data":[{"id":"unregistered-online-effort","description":"online only","parameters":[{"name":"effort","candidates":["low","high"],"wire":{"low":{"set":[{"path":"reasoning.effort","value":"low"}]},"high":{"set":[{"path":"reasoning.effort","value":"high"}]}}}]}]}).to_string(),
        ),
    ])
    .await;
    let query =
        ModelCatalogQuery::for_provider(&provider(&server.url, ProviderAdapterKind::OpenAi))
            .unwrap();
    let cache = |models: &[ModelInfo]| ModelCatalogQueryCache {
        identity: query.identity().into(),
        etag: None,
        models: models.to_vec(),
    };

    // 在线只声明当前窗口：观测值抬升过时的内置上限，其余内置元数据按精确 ID 补全。
    let raised = updated(query.execute(None).await.unwrap());
    assert_eq!(raised.len(), 1);
    assert_eq!(raised[0].context_window, Some(2_000_000));
    assert_eq!(raised[0].max_context_window, Some(2_000_000));
    assert_eq!(raised[0].max_output_tokens, builtin.max_output_tokens);
    assert_eq!(raised[0].display_name, builtin.display_name);
    assert_eq!(raised[0].description, builtin.description);
    assert_eq!(raised[0].pricing, ModelPricing::Unknown);
    assert_eq!(raised[0].supported_efforts(), builtin.supported_efforts());
    assert!(raised[0].capabilities.reasoning);
    let mut config = provider("http://127.0.0.1:1", ProviderAdapterKind::OpenAi);
    config.set_model_catalog_overlay(raised.clone()).unwrap();
    let effective = config.effective_catalog().unwrap();
    let entry = &effective[0];
    assert_eq!(entry.origin, pl_model::config::ProviderModelOrigin::Online);
    // 价格仍只按本地精确 ID 关联。
    assert_eq!(entry.model.pricing, builtin.pricing);
    assert_ne!(entry.model.pricing, ModelPricing::Unknown);
    let descriptor = model_descriptor(entry);
    assert_eq!(descriptor.context_window, Some(2_000_000));
    assert_eq!(descriptor.max_context_window, Some(2_000_000));
    assert_eq!(
        descriptor.auto_compact_token_limit,
        builtin.auto_compact_token_limit
    );
    assert_eq!(entry.model.resolved_auto_compact_limit(), Some(475_000));
    assert!(descriptor.capabilities.reasoning);
    assert_eq!(
        descriptor
            .reasoning
            .as_ref()
            .map(|reasoning| reasoning.candidates.clone()),
        Some(builtin.supported_efforts())
    );

    // 在线只声明更小的上限：继承的当前窗口收敛到在线上限，不因内置窗口更大而拒绝整份名单。
    let narrowed = updated(query.execute(Some(&cache(&raised))).await.unwrap());
    assert_eq!(narrowed[0].context_window, Some(300_000));
    assert_eq!(narrowed[0].max_context_window, Some(300_000));
    assert_eq!(narrowed[0].resolved_auto_compact_limit(), Some(270_000));

    // 在线明确关闭 reasoning：清除继承的 effort 候选；随后的 id-only 响应不复活内置候选。
    let closed = updated(query.execute(Some(&cache(&narrowed))).await.unwrap());
    assert!(!closed[0].capabilities.reasoning);
    assert!(closed[0].effort_parameter().is_none());
    let id_only = updated(query.execute(Some(&cache(&closed))).await.unwrap());
    assert!(!id_only[0].capabilities.reasoning);
    assert!(id_only[0].effort_parameter().is_none());
    assert_eq!(id_only[0].context_window, Some(300_000));
    assert_eq!(id_only[0].max_output_tokens, builtin.max_output_tokens);

    // 空 `parameters` 同样不继承内置候选，未单独声明的 reasoning 随在线候选收敛。
    let empty_parameters = updated(query.execute(Some(&cache(&id_only))).await.unwrap());
    assert!(!empty_parameters[0].capabilities.reasoning);
    assert!(empty_parameters[0].effort_parameter().is_none());

    // 在线非空候选派生 reasoning=true，描述与候选按在线值透传。
    let online_effort = updated(
        query
            .execute(Some(&cache(&empty_parameters)))
            .await
            .unwrap(),
    );
    assert_eq!(online_effort[0].slug, "unregistered-online-effort");
    assert!(online_effort[0].capabilities.reasoning);
    assert_eq!(online_effort[0].supported_efforts(), ["low", "high"]);
    // 在线声明的 wire 规则原样透传到该模型的 effort 参数。
    assert_eq!(
        online_effort[0]
            .effort_parameter()
            .and_then(|parameter| parameter.wire_for("high"))
            .map(|wire| wire.set[0].path.as_str()),
        Some("reasoning.effort")
    );
    assert_eq!(online_effort[0].description.as_deref(), Some("online only"));
    assert_eq!(online_effort[0].context_window, None);
    server.finish().await;

    // 在线声明自身冲突或越界时仍按无效预算/协议失败，不静默丢一方。
    for body in [
        json!({"data":[{"id":"gpt-6.1-sol","supports_reasoning":false,"effort":{"supported_levels":["low"]}}]}),
        json!({"data":[{"id":"gpt-6.1-sol","capabilities":{"reasoning":false},"supported_reasoning_levels":[{"effort":"high"}]}]}),
        json!({"data":[{"id":"gpt-6.1-sol","context_window":0}]}),
    ] {
        let conflict = Server::json(body).await;
        let query =
            ModelCatalogQuery::for_provider(&provider(&conflict.url, ProviderAdapterKind::OpenAi))
                .unwrap();
        let error = query.execute(None).await.unwrap_err();
        assert_eq!(error, ModelCatalogQueryError::Protocol);
        conflict.finish().await;
    }
}

/// 真实 `GET https://api.deepseek.com/models` 报文的完整解码回归。
///
/// 正文取自 `code/pl-provider-fixture/assets/model-lists/deepseek.json`（抓取日期
/// 2026-10-18），在测试内内联而不是读取 fixture crate 的资源路径：本文件的契约测试
/// 只依赖 pl-model 的公开 API，不把另一个 crate 的编译期资源布局变成前置条件。
const DEEPSEEK_MODELS_CAPTURE: &str = r#"{
  "object": "list",
  "data": [
    {
      "id": "deepseek-flash",
      "object": "model",
      "owned_by": "deepseek",
      "name": "DeepSeek-V4.1-Flash",
      "context_window": 1048576,
      "max_output_tokens": 393216,
      "input_modalities": [
        "text",
        "image"
      ],
      "output_modalities": [
        "text"
      ],
      "effort": {
        "supported_levels": [
          "low",
          "high",
          "max"
        ],
        "default_level": "high"
      },
      "api_capabilities": {
        "anthropic_messages": {
          "system_prompt_update": "in-history"
        }
      }
    },
    {
      "id": "deepseek-v4-pro",
      "object": "model",
      "owned_by": "deepseek",
      "name": "DeepSeek-V4-Pro",
      "context_window": 1048576,
      "max_output_tokens": 393216,
      "input_modalities": [
        "text"
      ],
      "output_modalities": [
        "text"
      ],
      "effort": {
        "supported_levels": [
          "low",
          "high",
          "max"
        ],
        "default_level": "high"
      },
      "api_capabilities": {
        "anthropic_messages": {
          "system_prompt_update": "leading-only"
        }
      }
    }
  ]
}
"#;

#[tokio::test]
async fn captured_deepseek_inventory_decodes_metadata_and_keeps_local_pricing() {
    let server = Server::responses(vec![http(200, "", DEEPSEEK_MODELS_CAPTURE)]).await;
    let mut config = provider(&server.url, ProviderAdapterKind::DeepSeek);
    let models = updated(
        ModelCatalogQuery::for_provider(&config)
            .unwrap()
            .execute(None)
            .await
            .unwrap(),
    );
    server.finish().await;
    assert_eq!(
        models
            .iter()
            .map(|model| model.slug.as_str())
            .collect::<Vec<_>>(),
        ["deepseek-flash", "deepseek-v4-pro"]
    );
    // 未知字段（如 `api_capabilities`）被忽略，且不使整份名单解析失败。
    let flash = models
        .iter()
        .find(|model| model.slug == "deepseek-flash")
        .unwrap();
    assert_eq!(flash.display_name, "DeepSeek-V4.1-Flash");
    assert_eq!(flash.context_window, Some(1_048_576));
    // 观测窗口高于内置上限 1_000_000 时抬升继承上限。
    assert_eq!(flash.max_context_window, Some(1_048_576));
    // API 明确声明的输出上限覆盖内置的 384_000。
    assert_eq!(flash.max_output_tokens, Some(393_216));
    assert_eq!(flash.supported_efforts(), ["low", "high", "max"]);
    assert!(
        flash
            .capabilities
            .supports_input_modality(ModelModality::Text)
    );
    assert!(
        flash
            .capabilities
            .supports_input_modality(ModelModality::Image)
    );
    assert_eq!(flash.capabilities.output, vec![ModelModality::Text]);
    // 在线探测从不采信 API 价格。
    assert_eq!(flash.pricing, ModelPricing::Unknown);
    config.set_model_catalog_overlay(models).unwrap();
    let definition = bundled_model_definition("deepseek").unwrap();
    let effective = config.effective_catalog().unwrap();
    for slug in ["deepseek-flash", "deepseek-v4-pro"] {
        let entry = effective
            .iter()
            .find(|entry| entry.model.slug == slug)
            .unwrap();
        assert_eq!(entry.origin, pl_model::config::ProviderModelOrigin::Online);
        // 价格只按该 provider 绑定目录的大小写敏感精确 ID 关联。
        let local = definition
            .models
            .iter()
            .find(|model| model.slug == slug)
            .unwrap();
        assert_eq!(entry.model.pricing, local.pricing);
        assert_ne!(entry.model.pricing, ModelPricing::Unknown);
    }
}

/// DeepSeek 布局：在线关闭 reasoning 时同时清除继承的 effort 候选和 `thinking` 基础 body，
/// 在线只声明更小上限时继承的当前窗口收敛；同身份缓存往返不复活内置项，本地精确计价保持。
#[tokio::test]
async fn deepseek_online_reasoning_closure_drops_thinking_body_and_narrows_inherited_window() {
    use pl_model::{
        completion::{CompletionRequest, ContentPart, Message, MessageContent, MessageRole},
        runtime::{ModelInvocationContext, ModelRuntime},
    };
    use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
    let definition = bundled_model_definition("deepseek").unwrap();
    let builtin = definition
        .models
        .iter()
        .find(|model| model.slug == "deepseek-flash")
        .unwrap();
    let builtin_pro = definition
        .models
        .iter()
        .find(|model| model.slug == "deepseek-v4-pro")
        .unwrap();
    assert!(!builtin.supported_efforts().is_empty());
    assert!(builtin.capabilities.reasoning);
    assert_eq!(
        builtin.binding.request.body["thinking"]["type"],
        serde_json::json!("enabled")
    );
    let server = Server::responses(vec![
        http(
            200,
            "",
            &json!({"data":[
                {"id":"deepseek-flash","context_window":1_048_576,"max_output_tokens":393_216,"capabilities":{"reasoning":false}},
                {"id":"deepseek-v4-pro","max_context_window":524_288,"effort":{"supported_levels":["max"],"default_level":"max"}}
            ]})
            .to_string(),
        ),
        // 同身份 304 等价路径：只给出 ID，继承的同身份成功结果不得由内置骨架补回。
        http(
            200,
            "",
            &json!({"data":[{"id":"deepseek-flash"},{"id":"deepseek-v4-pro"}]}).to_string(),
        ),
    ])
    .await;
    let mut config = provider(&server.url, ProviderAdapterKind::DeepSeek);
    let query = ModelCatalogQuery::for_provider(&config).unwrap();
    let models = updated(query.execute(None).await.unwrap());
    assert_eq!(
        models
            .iter()
            .map(|model| model.slug.as_str())
            .collect::<Vec<_>>(),
        ["deepseek-flash", "deepseek-v4-pro"]
    );
    let flash = &models[0];
    assert_eq!(flash.context_window, Some(1_048_576));
    // 在线只声明当前窗口时，继承的内置上限仍按观测值抬升。
    assert_eq!(flash.max_context_window, Some(1_048_576));
    assert_eq!(flash.max_output_tokens, Some(393_216));
    assert!(!flash.capabilities.reasoning);
    assert!(flash.effort_parameter().is_none());
    assert!(flash.binding.request.body.get("thinking").is_none());
    // 在线探测从不采信 API 价格。
    assert_eq!(flash.pricing, ModelPricing::Unknown);
    let pro = &models[1];
    // 在线只声明更小的上限：继承的 1_000_000 当前窗口收敛到该上限。
    assert_eq!(pro.context_window, Some(524_288));
    assert_eq!(pro.max_context_window, Some(524_288));
    assert_eq!(pro.max_output_tokens, builtin_pro.max_output_tokens);
    // 在线非空候选替换内置候选，并派生 reasoning 与 thinking 基础 body。
    assert_eq!(pro.supported_efforts(), ["max"]);
    assert!(pro.capabilities.reasoning);
    assert_eq!(
        pro.binding.request.body["thinking"]["type"],
        serde_json::json!("enabled")
    );

    // 有效目录只按精确 ID 关联本地价格，在线清除结果不被内置定义重写。
    config.set_model_catalog_overlay(models.clone()).unwrap();
    let effective = config.effective_catalog().unwrap();
    let flash_entry = effective
        .iter()
        .find(|entry| entry.model.slug == "deepseek-flash")
        .unwrap();
    assert_eq!(
        flash_entry.origin,
        pl_model::config::ProviderModelOrigin::Online
    );
    assert_eq!(flash_entry.model.pricing, builtin.pricing);
    assert_ne!(flash_entry.model.pricing, ModelPricing::Unknown);
    assert!(!flash_entry.model.capabilities.reasoning);
    assert!(flash_entry.model.effort_parameter().is_none());
    let descriptor = model_descriptor(flash_entry);
    assert!(descriptor.reasoning.is_none());
    assert!(!descriptor.capabilities.reasoning);
    assert_eq!(descriptor.max_context_window, Some(1_048_576));
    let pro_entry = effective
        .iter()
        .find(|entry| entry.model.slug == "deepseek-v4-pro")
        .unwrap();
    assert_eq!(pro_entry.model.pricing, builtin_pro.pricing);
    assert_eq!(pro_entry.model.context_window, Some(524_288));
    assert_eq!(
        model_descriptor(pro_entry)
            .reasoning
            .as_ref()
            .map(|reasoning| reasoning.candidates.clone()),
        Some(vec!["max".to_string()])
    );

    // 同身份成功缓存作为下次补全来源：清除结果与在线上限保持，不复活内置 current 窗口与 thinking。
    let cache = ModelCatalogQueryCache {
        identity: query.identity().into(),
        etag: None,
        models,
    };
    let roundtrip = updated(query.execute(Some(&cache)).await.unwrap());
    server.finish().await;
    let flash = &roundtrip[0];
    assert_eq!(flash.context_window, Some(1_048_576));
    assert!(!flash.capabilities.reasoning);
    assert!(flash.effort_parameter().is_none());
    assert!(flash.binding.request.body.get("thinking").is_none());
    let pro = &roundtrip[1];
    assert_eq!(pro.context_window, Some(524_288));
    assert_eq!(pro.supported_efforts(), ["max"]);

    // 必要运行时 wire：清除结果在真实请求体里既无 thinking 也无 reasoning_effort。
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "hello",
        0,
        Reply::Sse(responses_text(
            "answer",
            "deepseek-reasoning-closed",
            "deepseek-flash",
        )),
    )])
    .await
    .unwrap();
    let runtime = ModelRuntime::new(
        ProviderEndpoint::deepseek(Some(fixture.base_url())),
        flash.clone(),
    )
    .unwrap();
    let request = CompletionRequest::builder()
        .messages(vec![Message {
            role: MessageRole::User,
            content: MessageContent::new(vec![ContentPart::Text {
                text: "hello".into(),
            }]),
            reasoning_content: None,
            tool_calls: None,
            tool_result: None,
            metadata: Default::default(),
            presentation: Default::default(),
        }])
        .build();
    runtime
        .complete(request, ModelInvocationContext::default())
        .await
        .unwrap();
    let records = fixture.finish().await.unwrap();
    assert!(records[0].body.get("thinking").is_none());
    assert!(records[0].body.get("reasoning_effort").is_none());
}

#[tokio::test]
async fn explicit_inconsistent_window_pair_fails_without_lifting_or_caching() {
    let server = Server::json(json!({
        "data":[{"id":"deepseek-flash","context_window":2_000_000,"max_context_window":1_000_000}]
    }))
    .await;
    let query =
        ModelCatalogQuery::for_provider(&provider(&server.url, ProviderAdapterKind::DeepSeek))
            .unwrap();
    let cache = ModelCatalogQueryCache {
        identity: query.identity().into(),
        etag: None,
        models: vec![cached_model("last-good", ProviderAdapterKind::DeepSeek)],
    };
    let error = query.execute(Some(&cache)).await.unwrap_err();
    assert_eq!(error, ModelCatalogQueryError::Protocol);
    assert_eq!(cache.models[0].slug, "last-good");
    server.finish().await;
}

#[tokio::test]
async fn overlay_replaces_inventory_manual_wins_and_prices_join_only_local_exact_ids() {
    let definition = bundled_model_definition("openai").unwrap();
    let known = &definition.models[0];
    let slug = known.slug.clone();
    let foreign = bundled_model_definition("deepseek").unwrap().models[0]
        .slug
        .clone();
    let api = discover(json!({"data":[{"id":slug},{"id":slug.to_uppercase()},{"id":format!("{slug}-variant")},{"id":foreign},{"id":"manual"}]}), ProviderAdapterKind::OpenAi).await;
    let mut config = provider("http://127.0.0.1:1", ProviderAdapterKind::OpenAi);
    let mut manual = ModelInfo::compatible("manual");
    manual.display_name = "Authoritative manual model".into();
    manual.pricing = known.pricing.clone();
    if let pl_model::config::ProviderModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut config.catalog
    {
        additional_models.push(manual.clone());
    }
    config.set_model_catalog_overlay(api).unwrap();
    let effective = config.effective_models().unwrap();
    assert_eq!(
        effective.iter().find(|m| m.slug == slug).unwrap().pricing,
        known.pricing
    );
    for model in effective
        .iter()
        .filter(|m| m.slug != slug && m.slug != "manual")
    {
        assert_eq!(model.pricing, ModelPricing::Unknown);
        assert_eq!(model.context_window, None);
    }
    assert_eq!(
        effective.iter().find(|m| m.slug == "manual").unwrap(),
        &manual
    );
    let persisted = serde_json::to_value(&config).unwrap();
    let reread: ProviderConfig = serde_json::from_value(persisted).unwrap();
    assert!(!reread.has_model_catalog_overlay());
    config.set_model_catalog_overlay(Vec::new()).unwrap();
    assert_eq!(config.effective_models().unwrap(), vec![manual]);
    if let pl_model::config::ProviderModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut config.catalog
    {
        additional_models.push(known.clone());
    }
    assert!(config.effective_catalog().is_err());
    let empty = discover(json!({"data":[]}), ProviderAdapterKind::DeepSeek).await;
    assert!(empty.is_empty());
    let mut fresh = provider("http://127.0.0.1:1", ProviderAdapterKind::DeepSeek);
    fresh.set_model_catalog_overlay(empty).unwrap();
    assert!(fresh.effective_models().unwrap().is_empty());
}

#[tokio::test]
async fn availability_preserves_removed_choice_without_weakening_strict_edits_or_structure_validation()
 {
    let mut selected_provider = provider("http://127.0.0.1:1", ProviderAdapterKind::OpenAi);
    let mut selected = selected_provider.effective_models().unwrap()[0].clone();
    selected.slug = "remote-only-choice".into();
    selected_provider
        .set_model_catalog_overlay(vec![selected.clone()])
        .unwrap();
    selected_provider
        .set_model_connection_mode(
            &selected.slug,
            pl_model::provider::ProviderConnectionMode::Http,
        )
        .unwrap();
    selected_provider
        .set_model_auto_compact_override(&selected.slug, Some(1234))
        .unwrap();
    selected_provider
        .set_model_catalog_overlay(Vec::new())
        .unwrap();
    let id = ProviderId::new("instance-a").unwrap();
    let role = AgentRoleId::new("explorer").unwrap();
    let route = ModelRouteConfig {
        provider: id.clone(),
        model: selected.slug.clone(),
        effort: selected.default_effort().map(ReasoningEffort::new),
    };
    let mut config = AgentModelConfig {
        providers: [(id.clone(), selected_provider)].into(),
        routes: [(role.clone(), route.clone())].into(),
    };
    config.validate_declarations().unwrap();
    assert_eq!(
        config.route_availability(&route).unwrap(),
        ModelRouteAvailability::ModelUnavailable {
            provider: id.clone(),
            model: selected.slug.clone()
        }
    );
    assert!(config.validate().is_err());
    assert!(config.resolve(&role).is_err());
    assert_eq!(config.routes[&role], route);
    let from_disk: AgentModelConfig =
        serde_json::from_value(serde_json::to_value(&config).unwrap()).unwrap();
    from_disk.validate_declarations().unwrap();
    assert!(matches!(
        from_disk.route_availability(&route).unwrap(),
        ModelRouteAvailability::ModelUnavailable { .. }
    ));
    assert!(from_disk.validate().is_err());

    // A remote model can remain present while withdrawing a saved connection candidate.
    let mut narrowed = cached_model("connection-choice", ProviderAdapterKind::OpenAi);
    narrowed.binding.transport.supported_connection_modes = vec![ProviderConnectionMode::WebSocket];
    let server = Server::json(json!({"models":[{
        "slug": narrowed.slug,
        "binding": narrowed.binding,
        "input_modalities": ["text"],
        "context_window": 64000
    }]}))
    .await;
    let mut connection_provider = provider(&server.url, ProviderAdapterKind::OpenAi);
    connection_provider
        .set_model_catalog_overlay(vec![cached_model(
            "connection-choice",
            ProviderAdapterKind::OpenAi,
        )])
        .unwrap();
    connection_provider
        .set_model_connection_mode("connection-choice", ProviderConnectionMode::Http)
        .unwrap();
    let desired_before_observation = serde_json::to_value(&connection_provider).unwrap();
    let query = ModelCatalogQuery::for_provider(&connection_provider).unwrap();
    let observed = updated(query.execute(None).await.unwrap());
    assert_eq!(observed[0].binding.transport, narrowed.binding.transport);
    connection_provider
        .set_model_catalog_overlay(observed)
        .unwrap();
    connection_provider.validate_declarations(&id).unwrap();
    let display = model_descriptor(&connection_provider.effective_catalog().unwrap()[0]);
    assert_eq!(display.context_window, Some(64000));
    assert_eq!(display.transport.default_connection_mode, "web_socket");
    assert_eq!(display.transport.connection_modes.len(), 1);
    assert_eq!(display.transport.connection_modes[0].id, "web_socket");
    assert_eq!(
        connection_provider.connection_overrides()["connection-choice"],
        ProviderConnectionMode::Http
    );
    let connection_route = ModelRouteConfig {
        provider: id.clone(),
        model: "connection-choice".into(),
        effort: None,
    };
    let mut connection_config = AgentModelConfig {
        providers: [(id.clone(), connection_provider)].into(),
        routes: [(role.clone(), connection_route.clone())].into(),
    };
    connection_config.validate_declarations().unwrap();
    assert_eq!(
        connection_config
            .route_availability(&connection_route)
            .unwrap(),
        ModelRouteAvailability::ConnectionUnavailable {
            provider: id.clone(),
            model: "connection-choice".into(),
            connection_mode: ProviderConnectionMode::Http,
        }
    );
    assert!(connection_config.validate().is_err());
    assert!(connection_config.resolve(&role).is_err());
    assert!(
        connection_config
            .resolve_route(role.clone(), &connection_route)
            .is_err()
    );
    assert_eq!(
        serde_json::to_value(&connection_config.providers[&id]).unwrap(),
        desired_before_observation
    );
    assert_eq!(connection_config.routes[&role], connection_route);
    let mut manual_config = connection_config.clone();
    if let pl_model::config::ProviderModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut manual_config.providers.get_mut(&id).unwrap().catalog
    {
        let mut manual = narrowed.clone();
        manual.binding.transport = ModelTransportProfile::responses_http();
        additional_models.push(manual);
    }
    // The same-ID manual declaration, not the remote WS-only one, is authoritative.
    manual_config.validate().unwrap();
    assert_eq!(
        manual_config.route_availability(&connection_route).unwrap(),
        ModelRouteAvailability::Available
    );
    assert_eq!(
        manual_config
            .resolve(&role)
            .unwrap()
            .model
            .binding
            .transport
            .default_connection_mode,
        ProviderConnectionMode::Http
    );
    if let pl_model::config::ProviderModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut manual_config.providers.get_mut(&id).unwrap().catalog
    {
        additional_models[0] = narrowed.clone();
    }
    assert!(manual_config.validate_declarations().is_err());
    assert!(manual_config.route_availability(&connection_route).is_err());
    assert!(manual_config.resolve(&role).is_err());
    let mut explicit = ProviderConfig::from_explicit_models(
        ProviderEndpoint::openai(None),
        vec![narrowed.clone()],
    );
    if let pl_model::config::ProviderModelCatalogConfig::Explicit {
        connection_overrides,
        ..
    } = &mut explicit.catalog
    {
        connection_overrides.insert(narrowed.slug.clone(), ProviderConnectionMode::Http);
    }
    assert!(explicit.effective_models().is_err());
    assert!(explicit.validate_declarations(&id).is_err());
    let mut non_discovery = connection_config.clone();
    let provider = non_discovery.providers.get_mut(&id).unwrap();
    let connection_overrides = provider.connection_overrides().clone();
    let auto_compact_overrides = provider.auto_compact_overrides().clone();
    provider.catalog = pl_model::config::ProviderModelCatalogConfig::Bundled {
        catalog: ModelCatalogId::new("zhipu").unwrap(),
        additional_models: Vec::new(),
        connection_overrides,
        auto_compact_overrides,
    };
    assert!(non_discovery.validate_declarations().is_err());
    let mut bad_profile = manual_config.clone();
    if let pl_model::config::ProviderModelCatalogConfig::Bundled {
        additional_models,
        connection_overrides,
        ..
    } = &mut bad_profile.providers.get_mut(&id).unwrap().catalog
    {
        // Even an otherwise valid override cannot repair a contradictory declared default.
        additional_models[0]
            .binding
            .transport
            .default_connection_mode = ProviderConnectionMode::Http;
        connection_overrides.insert(narrowed.slug.clone(), ProviderConnectionMode::WebSocket);
    }
    assert!(bad_profile.validate_declarations().is_err());
    let instance = connection_config.providers.get_mut(&id).unwrap();
    assert!(
        instance
            .set_model_connection_mode("connection-choice", ProviderConnectionMode::Http)
            .is_err()
    );
    assert_eq!(
        instance.connection_overrides()["connection-choice"],
        ProviderConnectionMode::Http
    );
    instance
        .set_model_connection_mode("connection-choice", ProviderConnectionMode::WebSocket)
        .unwrap();
    assert_eq!(
        connection_config
            .route_availability(&connection_route)
            .unwrap(),
        ModelRouteAvailability::Available
    );
    connection_config.validate().unwrap();
    assert_eq!(
        connection_config
            .resolve(&role)
            .unwrap()
            .model
            .binding
            .transport
            .default_connection_mode,
        ProviderConnectionMode::WebSocket
    );
    // Only discovery was sent: rejected resolution cannot construct a fallback inference request.
    let requests = server.finish().await;
    assert_eq!(requests.len(), 1);
    assert!(requests[0].starts_with("GET /models HTTP/1.1\r\n"));

    let mut current = selected.clone();
    current.parameters.clear();
    current.binding.request.body.clear();
    config
        .providers
        .get_mut(&id)
        .unwrap()
        .set_model_catalog_overlay(vec![current])
        .unwrap();
    assert!(matches!(
        config.route_availability(&route).unwrap(),
        ModelRouteAvailability::EffortUnavailable { .. }
    ));
    let mut manual = ModelInfo::compatible("manual-choice");
    manual.parameters.clear();
    if let pl_model::config::ProviderModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut config.providers.get_mut(&id).unwrap().catalog
    {
        additional_models.push(manual);
    }
    let manual_route = ModelRouteConfig {
        provider: id.clone(),
        model: "manual-choice".into(),
        effort: Some(ReasoningEffort::new("undeclared")),
    };
    assert!(matches!(
        config.route_availability(&manual_route),
        Err(pl_protocol::PureError::ConfigError(_))
    ));
    config.routes.insert(role, manual_route);
    assert!(matches!(
        config.validate_declarations(),
        Err(pl_protocol::PureError::ConfigError(_))
    ));
    config.providers.get_mut(&id).unwrap().name.clear();
    assert!(config.route_availability(&route).is_err());
}

#[tokio::test]
async fn invalid_declaration_rejects_whole_response_without_leaking_response_or_mutating_cache() {
    let invalid_profile = json!({"transport":{"protocol":"chat_completions","supported_connection_modes":["web_socket"],"default_connection_mode":"web_socket"},"request":{"protocol":{"api":"chatCompletions","parallelToolCalls":false,"maxTokensField":"max_tokens","includeUsage":false,"toolStream":false}}});
    let mut invalid_bodies = vec![
        json!({"data":[{"id":"ok"},{"id":"ok"}]}),
        json!({"data":[{"id":" "}]}),
        json!({"data":[{"id":"ok","context_window":0}]}),
        json!({"data":[{"id":"ok","max_output_tokens":-1}]}),
        json!({"data":[{"id":"ok","effort":{"supported_levels":["one"],"default_level":"absent"}}]}),
        json!({"data":[{"id":"ok","effort":{"supported_levels":["one"],"default_level":"one"},"default_reasoning_level":"absent"}]}),
        json!({"models":[{"slug":"ok","supported_reasoning_levels":[{"effort":"one"},{"effort":"one"}]}]}),
        json!({"data":[{"id":"ok","binding":invalid_profile}]}),
        json!({"data":[{"id":"ok","input_modalities":["video"]}]}),
        json!({"data":[{"id":"ok","parameters":[{"name":"effort","candidates":["a"],"wire":{}}]}]}),
        json!({"error":{"message":"synthetic-secret-response"},"data":[]}),
        json!({"success":false,"data":[]}),
        json!({"models":[],"data":[]}),
        json!({"not-models":[]}),
    ];
    for (protocol, modes, default) in [
        ("responses", json!([]), "web_socket"),
        (
            "responses",
            json!(["web_socket", "web_socket"]),
            "web_socket",
        ),
        ("responses", json!(["web_socket", "unknown"]), "web_socket"),
        ("responses", json!(["web_socket"]), "http"),
        ("responses", json!(["http", "web_socket"]), "http"),
        ("unknown", json!(["web_socket"]), "web_socket"),
    ] {
        let mut binding = serde_json::to_value(
            cached_model("invalid-profile", ProviderAdapterKind::OpenAi).binding,
        )
        .unwrap();
        binding["transport"]["protocol"] = json!(protocol);
        binding["transport"]["supported_connection_modes"] = modes;
        binding["transport"]["default_connection_mode"] = json!(default);
        invalid_bodies.push(json!({"models":[{"slug":"valid-before-invalid"},{"slug":"invalid-profile","binding":binding}]}));
    }
    for body in invalid_bodies {
        let server = Server::json(body).await;
        let query =
            ModelCatalogQuery::for_provider(&provider(&server.url, ProviderAdapterKind::OpenAi))
                .unwrap();
        let cache = ModelCatalogQueryCache {
            identity: query.identity().into(),
            etag: None,
            models: vec![cached_model("last-good", ProviderAdapterKind::OpenAi)],
        };
        let error = query.execute(Some(&cache)).await.unwrap_err();
        assert_eq!(error, ModelCatalogQueryError::Protocol);
        assert!(!format!("{error:?}: {error}").contains("synthetic-secret-response"));
        assert_eq!(cache.models[0].slug, "last-good");
        server.finish().await;
    }
}

#[tokio::test]
async fn conditional_304_requires_same_identity_success_and_returns_etag() {
    let server = Server::responses(vec![
        http(200, "ETag: \"version-a\"\r\n", "{\"data\":[]}"),
        http(304, "", ""),
        http(304, "", ""),
    ])
    .await;
    let query =
        ModelCatalogQuery::for_provider(&provider(&server.url, ProviderAdapterKind::OpenAi))
            .unwrap();
    let ModelCatalogQueryResult::Updated {
        identity,
        etag,
        models,
    } = query.execute(None).await.unwrap()
    else {
        panic!()
    };
    assert_eq!(etag.as_deref(), Some("\"version-a\""));
    let cache = ModelCatalogQueryCache {
        identity: identity.clone(),
        etag: etag.clone(),
        models,
    };
    assert_eq!(
        query.execute(Some(&cache)).await.unwrap(),
        ModelCatalogQueryResult::NotModified { identity, etag }
    );
    assert_eq!(
        query.execute(None).await.unwrap_err(),
        ModelCatalogQueryError::UnexpectedNotModified
    );
    let mut corrupt = cache.clone();
    let mut priced = cached_model("cached-price", ProviderAdapterKind::OpenAi);
    priced.pricing = ModelPricing::published(
        "USD",
        vec![pl_model::model::TokenPriceTier::flat(1.0, 2.0, None, None)],
        "https://synthetic.invalid/pricing",
    );
    corrupt.models.push(priced);
    assert_eq!(
        query.execute(Some(&corrupt)).await.unwrap_err(),
        ModelCatalogQueryError::Protocol
    );
    let mut changed = cache;
    changed.identity = "different-query".into();
    assert_eq!(
        query.execute(Some(&changed)).await.unwrap_err(),
        ModelCatalogQueryError::CacheIdentity
    );
    let requests = server.finish().await;
    assert!(
        requests[1]
            .to_ascii_lowercase()
            .contains("if-none-match: \"version-a\"\r\n")
    );
    assert!(!requests[2].to_ascii_lowercase().contains("if-none-match:"));
}

#[tokio::test]
async fn discovery_profile_validity_is_independent_of_connection_mode_order() {
    let mut model = cached_model("profile-order", ProviderAdapterKind::OpenAi);
    model.binding.transport.supported_connection_modes.reverse();
    let models = discover(
        json!({"data":[{"id":model.slug,"binding":model.binding,"input_modalities":["text"]}]}),
        ProviderAdapterKind::OpenAi,
    )
    .await;
    assert_eq!(
        models[0].binding.transport,
        ModelTransportProfile::responses_websocket()
    );
    let mut config = provider("http://127.0.0.1:1", ProviderAdapterKind::OpenAi);
    config
        .set_model_catalog_overlay(vec![model.clone()])
        .unwrap();
    config
        .set_model_connection_mode(
            "profile-order",
            pl_model::provider::ProviderConnectionMode::Http,
        )
        .unwrap();
    assert_eq!(
        config.effective_models().unwrap()[0]
            .binding
            .transport
            .default_connection_mode,
        pl_model::provider::ProviderConnectionMode::Http
    );

    model.binding.transport.supported_connection_modes = vec![ProviderConnectionMode::WebSocket];
    let server = Server::responses(vec![
        http(
            200,
            "ETag: \"narrowed\"\r\n",
            &json!({"models":[{"slug":model.slug,"binding":model.binding,"input_modalities":["text"]}]}).to_string(),
        ),
        http(304, "", ""),
        http(200, "", &json!({"data":[{"id":model.slug}]}).to_string()),
    ])
    .await;
    let query =
        ModelCatalogQuery::for_provider(&provider(&server.url, ProviderAdapterKind::OpenAi))
            .unwrap();
    let cache = ModelCatalogQueryCache {
        identity: query.identity().into(),
        etag: Some("\"narrowed\"".into()),
        models: updated(query.execute(None).await.unwrap()),
    };
    assert_eq!(cache.models[0].binding.transport, model.binding.transport);
    assert!(matches!(
        query.execute(Some(&cache)).await.unwrap(),
        ModelCatalogQueryResult::NotModified { .. }
    ));
    let inherited = updated(query.execute(Some(&cache)).await.unwrap());
    assert_eq!(inherited[0].binding.transport, model.binding.transport);
    config.set_model_catalog_overlay(inherited.clone()).unwrap();
    let descriptor = model_descriptor(&config.effective_catalog().unwrap()[0]);
    assert_eq!(descriptor.transport.connection_modes.len(), 1);
    assert_eq!(descriptor.transport.connection_modes[0].id, "web_socket");
    for modes in [
        Vec::new(),
        vec![
            ProviderConnectionMode::WebSocket,
            ProviderConnectionMode::WebSocket,
        ],
        vec![ProviderConnectionMode::Http],
    ] {
        let mut invalid = inherited.clone();
        invalid[0].binding.transport.supported_connection_modes = modes;
        assert!(config.set_model_catalog_overlay(invalid.clone()).is_err());
        let invalid_cache = ModelCatalogQueryCache {
            models: invalid,
            ..cache.clone()
        };
        assert_eq!(
            query.execute(Some(&invalid_cache)).await.unwrap_err(),
            ModelCatalogQueryError::Protocol
        );
    }
    assert_eq!(config.effective_models().unwrap(), inherited);
    let requests = server.finish().await;
    assert_eq!(requests.len(), 3);
    assert!(
        requests[1]
            .to_ascii_lowercase()
            .contains("if-none-match: \"narrowed\"\r\n")
    );

    let deepseek = cached_model("deepseek-profile", ProviderAdapterKind::DeepSeek);
    let observed = discover(
        json!({"models":[{"slug":deepseek.slug,"binding":deepseek.binding,"input_modalities":["text"]}]}),
        ProviderAdapterKind::DeepSeek,
    )
    .await;
    assert_eq!(
        observed[0].binding.transport,
        ModelTransportProfile::responses_http()
    );
    let server =
        Server::json(json!({"models":[{"slug":model.slug,"binding":model.binding}]})).await;
    let query =
        ModelCatalogQuery::for_provider(&provider(&server.url, ProviderAdapterKind::DeepSeek))
            .unwrap();
    assert_eq!(
        query.execute(None).await.unwrap_err(),
        ModelCatalogQueryError::Protocol
    );
    server.finish().await;
}

#[tokio::test]
async fn failed_http_redirect_and_body_caps_are_typed_and_never_expose_arbitrary_text() {
    for (response, expected) in [
        (
            http(401, "", "synthetic-token arbitrary body"),
            ModelCatalogQueryError::Http { status: 401 },
        ),
        (
            http(302, "Location: http://127.0.0.1:1/secret\r\n", ""),
            ModelCatalogQueryError::Http { status: 302 },
        ),
        (
            http(503, "Retry-After: 30\r\n", "provider internal secret"),
            ModelCatalogQueryError::Http { status: 503 },
        ),
        (
            http(200, "", "not json synthetic-secret"),
            ModelCatalogQueryError::Protocol,
        ),
        (
            http(200, "", &"x".repeat(4 * 1024 * 1024 + 1)),
            ModelCatalogQueryError::TooLarge,
        ),
        (
            format!(
                "HTTP/1.1 200 Test\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n{:x}\r\n{}\r\n0\r\n\r\n",
                4 * 1024 * 1024 + 1,
                "x".repeat(4 * 1024 * 1024 + 1)
            ),
            ModelCatalogQueryError::TooLarge,
        ),
    ] {
        let server = Server::responses(vec![response]).await;
        let query =
            ModelCatalogQuery::for_provider(&provider(&server.url, ProviderAdapterKind::OpenAi))
                .unwrap();
        let error = query.execute(None).await.unwrap_err();
        assert_eq!(error, expected);
        assert!(!format!("{error:?}: {error}").contains("secret"));
        assert_eq!(server.finish().await.len(), 1);
    }
}

#[tokio::test]
async fn whole_body_timeout_and_future_drop_release_borrow_without_changing_last_good() {
    for cancel in [false, true] {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        let (release_tx, release_rx) = tokio::sync::oneshot::channel();
        let task = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut headers = Vec::new();
            while !headers.ends_with(b"\r\n\r\n") {
                let mut b = [0];
                socket.read_exact(&mut b).await.unwrap();
                headers.push(b[0]);
            }
            socket
                .write_all(b"HTTP/1.1 200 Test\r\nContent-Length: 1000\r\n\r\n{")
                .await
                .unwrap();
            ready_tx.send(()).unwrap();
            release_rx.await.unwrap();
            // Finish the HTTP frame for library-level connection cleanup. Dropping the
            // application future is not a guarantee of immediate TCP FIN from reqwest/Hyper.
            let suffix = "\"data\":[{\"id\":\"late-result\"}]}";
            let remainder = format!("{}{}", " ".repeat(999 - suffix.len()), suffix);
            let _ = socket.write_all(remainder.as_bytes()).await;
            let mut b = [0];
            socket.read(&mut b).await.unwrap_or(0)
        });
        let query = ModelCatalogQuery::for_provider(&provider(&url, ProviderAdapterKind::DeepSeek))
            .unwrap();
        let cache = ModelCatalogQueryCache {
            identity: query.identity().into(),
            etag: None,
            models: vec![cached_model("last-good", ProviderAdapterKind::DeepSeek)],
        };
        let mut future = Box::pin(query.execute(Some(&cache)));
        tokio::select! { result = &mut future => panic!("completed before body: {result:?}"), result = ready_rx => result.unwrap() }
        if cancel {
            drop(future);
        } else {
            assert_eq!(future.await.unwrap_err(), ModelCatalogQueryError::Timeout);
        }
        // Moving the cache proves the query no longer retains the borrowed snapshot.
        let retained_cache = cache;
        release_tx.send(()).unwrap();
        let closed = tokio::time::timeout(Duration::from_secs(3), task).await;
        assert!(
            closed.is_ok(),
            "fixture connection was not reclaimed after cancel={cancel}"
        );
        assert_eq!(closed.unwrap().unwrap(), 0);
        assert_eq!(retained_cache.models[0].slug, "last-good");
    }
}

#[test]
fn malformed_bundled_definition_is_packaging_failure_not_user_config_reset() {
    let json = json!({"schemaVersion":9,"catalog":"synthetic","suggestedModel":"one","suggestedEffort":null,"models":[]}).to_string();
    assert_eq!(
        BundledModelDefinition::parse(&json, "synthetic").unwrap_err(),
        ModelDefinitionError::Identity
    );
    let error: pl_protocol::PureError = ModelDefinitionError::Declaration.into();
    assert!(matches!(error, pl_protocol::PureError::Provider(_)));

    let mut definition = BundledModelDefinition {
        schema_version: 1,
        catalog: "synthetic".into(),
        suggested_model: "one".into(),
        suggested_effort: None,
        models: vec![ModelInfo::compatible("one")],
    };
    let parse = |definition: &BundledModelDefinition| {
        BundledModelDefinition::parse(&serde_json::to_string(definition).unwrap(), "synthetic")
    };
    assert!(parse(&definition).is_ok());
    definition.suggested_effort = Some("stronger".into());
    assert_eq!(
        parse(&definition).unwrap_err(),
        ModelDefinitionError::Recommendation
    );
    let candidates = vec!["gentle".to_owned(), "stronger".to_owned()];
    definition.models[0].parameters.push(ModelParameter {
        name: "effort".into(),
        label: None,
        wire: candidates
            .iter()
            .map(|candidate| {
                (
                    candidate.clone(),
                    ParameterWire {
                        set: vec![WireAssignment {
                            path: "reasoning_effort".into(),
                            value: json!(candidate),
                        }],
                        remove: Vec::new(),
                    },
                )
            })
            .collect(),
        candidates,
    });
    let parsed = parse(&definition).unwrap();
    assert_eq!(parsed.models[0].default_effort().as_deref(), Some("gentle"));
    assert_eq!(parsed.suggested_effort.as_deref(), Some("stronger"));
    for invalid in [None, Some("outside".into())] {
        definition.suggested_effort = invalid;
        assert_eq!(
            parse(&definition).unwrap_err(),
            ModelDefinitionError::Recommendation
        );
    }
}
