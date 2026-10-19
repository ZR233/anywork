//! Discovery contract through public API and real localhost HTTP. No live credentials or catalog mirror.
use pl_model::{
    config::{
        AccountConfig, AccountId, AgentModelConfig, AgentRoleId, ModelCatalogId,
        ModelRouteAvailability, ModelRouteConfig, ReasoningEffort, model_descriptor,
    },
    model::{
        BundledModelDefinition, ModelDefinitionError, ModelInfo, ModelModality, ModelParameter,
        ModelPricing, ModelTransportProfile, ModelType, ModelTypeExclusion, ParameterWire,
        WireAssignment, bundled_model_definition,
    },
    protocol::{
        ConnectionMode, ProtocolEndpoint, ProtocolKind,
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
fn provider(url: &str, adapter: ProtocolKind) -> AccountConfig {
    let (endpoint, id) = match adapter {
        ProtocolKind::OpenAi => (ProtocolEndpoint::openai(Some(url.into())), "openai"),
        ProtocolKind::DeepSeek => (ProtocolEndpoint::deepseek(Some(url.into())), "deepseek"),
        ProtocolKind::Xai => (ProtocolEndpoint::xai(Some(url.into())), "xai"),
        ProtocolKind::MiMo => (
            ProtocolEndpoint::compatible("MiMo API", url).with_protocol(ProtocolKind::MiMo),
            "mimo",
        ),
        _ => unreachable!(),
    };
    AccountConfig::from_bundled_catalog(endpoint, ModelCatalogId::new(id).unwrap(), Vec::new())
}
fn updated(result: ModelCatalogQueryResult) -> Vec<ModelInfo> {
    match result {
        ModelCatalogQueryResult::Updated { models, .. } => models,
        _ => panic!("expected updated catalog"),
    }
}
fn cached_model(model_id: &str, adapter: ProtocolKind) -> ModelInfo {
    let mut model = ModelInfo::compatible(model_id);
    model.context_window = None;
    model.max_output_tokens = None;
    model
        .binding
        .set_transport(if adapter == ProtocolKind::OpenAi {
            ModelTransportProfile::responses_websocket()
        } else {
            ModelTransportProfile::responses_http()
        });
    model
}
async fn discover(body: Value, adapter: ProtocolKind) -> Vec<ModelInfo> {
    let server = Server::json(body).await;
    let query = ModelCatalogQuery::for_account(&provider(&server.url, adapter)).unwrap();
    let result = updated(query.execute(None).await.unwrap());
    server.finish().await;
    result
}

fn accept_observation(provider: &mut AccountConfig, mut models: Vec<ModelInfo>, order: u64) {
    for model in &mut models {
        if let Some(observation) = &mut model.observation {
            observation.commit(order);
        }
    }
    provider.set_model_catalog_overlay(models).unwrap();
}

#[tokio::test]
async fn text_lists_use_each_account_own_definition_and_do_not_gate_route_execution() {
    let mut a = provider("http://127.0.0.1:1", ProtocolKind::OpenAi);
    accept_observation(&mut a, discover(json!({"data":[
        {"id":"shared","input_modalities":["text"],"output_modalities":["text"]},
        {"id":"unknown-budget","input_modalities":["text"],"output_modalities":["text"]},
        {"id":"max-only","max_context_window":4096},
        {"id":"without-tools-or-prices","context_window":2048,"supports_function_calling":false},
        {"id":"image-output","context_window":1024,"input_modalities":["text"],"output_modalities":["image"]},
        {"id":"image-input","context_window":1024,"input_modalities":["image"],"output_modalities":["text"]},
        {"id":"empty-output","context_window":1024,"output_modalities":[]}
    ]}), ProtocolKind::OpenAi).await, 10);
    let mut b = provider("http://127.0.0.1:1", ProtocolKind::Xai);
    accept_observation(
        &mut b,
        discover(
            json!({"data":[{"id":"shared","context_length":8192}]}),
            ProtocolKind::Xai,
        )
        .await,
        20,
    );
    let a_id = AccountId::new("a").unwrap();
    let b_id = AccountId::new("b").unwrap();
    let mut config = AgentModelConfig {
        accounts: [(a_id.clone(), a), (b_id.clone(), b)].into(),
        routes: Default::default(),
    };
    config.reconcile_model_catalog().unwrap();
    let a = &config.accounts[&a_id];
    let all = a.effective_catalog(None).unwrap();
    assert_eq!(all.len(), 7);
    assert_eq!(
        a.effective_models(Some(ModelType::Text))
            .unwrap()
            .iter()
            .map(|model| model.model_id.as_str())
            .collect::<Vec<_>>(),
        ["max-only", "without-tools-or-prices"]
    );
    assert_eq!(
        config.accounts[&b_id]
            .effective_models(Some(ModelType::Text))
            .unwrap()
            .len(),
        1
    );
    let shared = all
        .iter()
        .find(|entry| entry.model.model_id == "shared")
        .unwrap();
    // Another account's declaration for the same model_id is not this account's fact.
    assert_eq!(shared.model.context_window, None);
    assert_eq!(
        model_descriptor(shared).type_support[0].exclusions,
        [ModelTypeExclusion::ContextWindowUnknown]
    );
    assert_eq!(
        config.accounts[&b_id]
            .effective_catalog(None)
            .unwrap()
            .iter()
            .find(|entry| entry.model.model_id == "shared")
            .unwrap()
            .model
            .context_window,
        Some(8192)
    );
    for (id, reason) in [
        ("unknown-budget", ModelTypeExclusion::ContextWindowUnknown),
        ("image-output", ModelTypeExclusion::TextOutputUnsupported),
        ("image-input", ModelTypeExclusion::TextInputUnsupported),
        ("empty-output", ModelTypeExclusion::TextOutputUnsupported),
    ] {
        let entry = all.iter().find(|entry| entry.model.model_id == id).unwrap();
        assert_eq!(
            entry.model.type_support(ModelType::Text).exclusions,
            [reason]
        );
    }
    accept_observation(
        config.accounts.get_mut(&b_id).unwrap(),
        discover(
            json!({"data":[{"id":"shared","context_length":null,"input_modalities":[]}]}),
            ProtocolKind::Xai,
        )
        .await,
        30,
    );
    config.reconcile_model_catalog().unwrap();
    for id in [a_id, b_id] {
        let provider = &config.accounts[&id];
        assert!(
            provider
                .effective_models(Some(ModelType::Text))
                .unwrap()
                .iter()
                .all(|model| model.model_id != "shared")
        );
        assert!(
            provider
                .effective_models(None)
                .unwrap()
                .iter()
                .any(|model| model.model_id == "shared")
        );
        assert_eq!(
            config
                .route_availability(&ModelRouteConfig {
                    account_id: id,
                    model_id: "shared".into(),
                    effort: None
                })
                .unwrap(),
            ModelRouteAvailability::Available
        );
    }
}

#[tokio::test]
async fn captured_camelcase_effort_defaults_keep_their_clock_and_do_not_restore_withdrawn_candidates()
 {
    let server = Server::responses(vec![
        http(200, "", &json!({"data":[{"id":"shared-effort","context_window":4096,"supportsReasoningEffort":true,"reasoningEffort":"high","reasoningEfforts":[{"value":"low","label":"Low"},{"value":"high","label":"High","default":true}]}]}).to_string()),
        http(200, "", &json!({"data":[{"id":"shared-effort","reasoningEfforts":[{"value":"low"},{"value":"high"}]}]}).to_string()),
        http(200, "", &json!({"data":[{"id":"shared-effort","reasoningEfforts":[{"value":"low"}]}]}).to_string()),
        http(200, "", &json!({"data":[{"id":"shared-effort","reasoningEffort":null}]}).to_string()),
        http(200, "", &json!({"data":[{"id":"shared-effort","supportsReasoningEffort":false}]}).to_string()),
    ]).await;
    let mut a = provider(&server.url, ProtocolKind::OpenAi);
    let query = ModelCatalogQuery::for_account(&a).unwrap();
    let mut models = updated(query.execute(None).await.unwrap());
    assert_eq!(models[0].supported_efforts(), ["low", "high"]);
    assert_eq!(models[0].default_effort().as_deref(), Some("high"));
    accept_observation(&mut a, models.clone(), 10);
    models = a.effective_models(None).unwrap();
    let mut b = provider("http://127.0.0.1:1", ProtocolKind::OpenAi);
    accept_observation(
        &mut b,
        discover(
            json!({"data":[{"id":"shared-effort","reasoningEffort":"low"}]}),
            ProtocolKind::OpenAi,
        )
        .await,
        20,
    );
    let a_id = AccountId::new("a").unwrap();
    let mut config = AgentModelConfig {
        accounts: [(a_id.clone(), a), (AccountId::new("b").unwrap(), b)].into(),
        routes: Default::default(),
    };
    for order in [30, 40, 50, 60] {
        let cache = ModelCatalogQueryCache {
            identity: query.identity().into(),
            etag: None,
            models,
        };
        let next = updated(query.execute(Some(&cache)).await.unwrap());
        accept_observation(config.accounts.get_mut(&a_id).unwrap(), next, order);
        models = config.accounts[&a_id].effective_models(None).unwrap();
        assert_eq!(
            models[0].observation.as_ref().unwrap().parameter_defaults["effort"].order,
            if order < 50 { 10 } else { 50 }
        );
        config.reconcile_model_catalog().unwrap();
        let observed = config.accounts[&a_id]
            .effective_models(None)
            .unwrap()
            .remove(0);
        match order {
            30 => {
                assert_eq!(observed.supported_efforts(), ["low", "high"]);
                // The captured default survives a candidate-only update; it is not replaced by
                // another account's later default declaration.
                assert_eq!(observed.default_effort().as_deref(), Some("high"));
            }
            40 | 50 => {
                assert_eq!(observed.supported_efforts(), ["low"]);
                // Without an explicit default the candidate order decides; the withdrawn
                // "high" value is not restored.
                assert_eq!(observed.default_effort().as_deref(), Some("low"));
            }
            _ => {
                assert!(observed.supported_efforts().is_empty());
                assert!(
                    observed.capabilities.reasoning,
                    "fixed reasoning survives effort withdrawal"
                );
            }
        }
        // The sibling account declares its own default without candidates; it never inherits
        // this account's candidates, defaults or withdrawal history.
        let sibling = config.accounts[&AccountId::new("b").unwrap()]
            .effective_models(None)
            .unwrap()
            .remove(0);
        assert!(sibling.supported_efforts().is_empty());
        assert_eq!(sibling.default_effort(), None);
        assert!(!sibling.capabilities.reasoning);
    }
    server.finish().await;
}

#[tokio::test]
async fn account_catalog_resolves_own_fields_prices_and_wire_without_cross_account_leaks() {
    let a = discover(json!({"data":[
        {"id":"shared", "context_window":4096, "max_output_tokens":128, "input_modalities":["text"],
         "supports_function_calling":true, "effort":{"supported_levels":["medium"]}},
        {"id":"shared", "display_name":"Final A", "supports_streaming":false}
    ]}), ProtocolKind::OpenAi).await;
    assert_eq!(a.len(), 1);
    assert_eq!(a[0].context_window, Some(4096));
    let b = discover(
        json!({"data":[{"id":"shared", "context_length":8192,
            "input_modalities":[], "supports_function_calling":false,
            "effort":{"supported_levels":[]}, "prompt_text_token_price":20000,
            "completion_text_token_price":100000, "cached_prompt_text_token_price":5000
        }]}),
        ProtocolKind::Xai,
    )
    .await;
    let mut local = cached_model("shared", ProtocolKind::OpenAi);
    local.pricing = ModelPricing::published(
        "USD",
        vec![pl_model::model::TokenPriceTier::flat(1.0, 4.0, None, None)],
        "local-a",
    );
    local.max_output_tokens = Some(256);
    let mut first = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::openai(None),
        ModelCatalogId::new("openai").unwrap(),
        vec![local.clone()],
    );
    let mut second = provider("http://127.0.0.1:1", ProtocolKind::Xai);
    accept_observation(&mut first, a, 1);
    accept_observation(&mut second, b, 2);
    let mut explicit = ModelInfo::compatible("shared");
    explicit.pricing = ModelPricing::published(
        "CNY",
        vec![pl_model::model::TokenPriceTier::flat(3.0, 6.0, None, None)],
        "local-c",
    );
    let mut config = AgentModelConfig::default();
    for (id, provider) in [
        ("z-first", first),
        ("a-second", second),
        (
            "third",
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible("third", "http://127.0.0.1:1"),
                vec![explicit.clone()],
            ),
        ),
        (
            "unrelated",
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible("unrelated", "http://127.0.0.1:1"),
                vec![ModelInfo::compatible("other")],
            ),
        ),
    ] {
        config
            .accounts
            .insert(AccountId::new(id).unwrap(), provider);
    }
    config.reconcile_model_catalog().unwrap();
    let route = |id: &str, effort: Option<&str>| {
        config
            .resolve_route(
                AgentRoleId::new("test").unwrap(),
                &ModelRouteConfig {
                    account_id: AccountId::new(id).unwrap(),
                    model_id: "shared".into(),
                    effort: effort.map(ReasoningEffort::new),
                },
            )
            .unwrap()
    };
    // The observing account keeps its own manual wire/price and its own online metadata.
    let first_route = route("z-first", Some("medium"));
    assert_eq!(first_route.model.display_name, "Final A");
    assert_eq!(first_route.model.context_window, Some(4096));
    assert_eq!(first_route.model.max_output_tokens, Some(128));
    assert_eq!(first_route.model.supported_efforts(), ["medium"]);
    assert_eq!(first_route.model.pricing, local.pricing);
    assert_eq!(first_route.model.binding.transport, local.binding.transport);
    // A sibling account never receives the first account's display name, limits or manual price.
    let second_route = route("a-second", None);
    assert_eq!(second_route.model.display_name, "shared");
    assert_eq!(second_route.model.context_window, Some(8192));
    assert_eq!(second_route.model.max_output_tokens, None);
    // xAI `/models` 不声明模态：未知模型保持 text-only，也不借用别家声明。
    assert_eq!(
        second_route.model.capabilities.input,
        [pl_model::model::ModelInputCapability::text()]
    );
    assert!(!second_route.model.capabilities.supports_function_calling());
    // The other account's explicit `streaming = false` is not inherited here.
    assert!(second_route.model.capabilities.streaming);
    assert!(second_route.model.supported_efforts().is_empty());
    assert_eq!(
        second_route.model.binding.transport,
        ModelTransportProfile::responses_http()
    );
    let ModelPricing::Rates {
        currency, tiers, ..
    } = second_route.model.pricing
    else {
        panic!("online price missing")
    };
    assert_eq!(currency, "USD");
    assert_eq!(tiers[0].input_per_mtok, 2.0);
    assert_eq!(tiers[0].output_per_mtok, 10.0);
    assert_eq!(tiers[0].cache_read_per_mtok, Some(0.5));
    // A fully explicit account resolves only its own declaration.
    let third_route = route("third", None);
    assert_eq!(third_route.model.display_name, "shared");
    assert!(third_route.model.supported_efforts().is_empty());
    assert_eq!(third_route.model.pricing, explicit.pricing);
    assert_eq!(
        third_route.model.binding.transport,
        explicit.binding.transport
    );
    assert_eq!(
        config.accounts[&AccountId::new("unrelated").unwrap()]
            .effective_models(None)
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        config.accounts[&AccountId::new("unrelated").unwrap()]
            .effective_models(None)
            .unwrap()[0]
            .model_id,
        "other"
    );
    let first_snapshot = config.clone();
    config.reconcile_model_catalog().unwrap();
    assert_eq!(config, first_snapshot);
    // An effort that only another account declares is invalid for this account's model.
    let foreign_effort = ModelRouteConfig {
        account_id: AccountId::new("third").unwrap(),
        model_id: "shared".into(),
        effort: Some(ReasoningEffort::new("medium")),
    };
    config
        .routes
        .insert(AgentRoleId::new("test").unwrap(), foreign_effort.clone());
    assert!(config.validate_declarations().is_err());
    assert!(
        config
            .resolve_route(AgentRoleId::new("test").unwrap(), &foreign_effort)
            .is_err()
    );
}

#[tokio::test]
async fn missing_fields_and_304_keep_original_order_within_one_account_only() {
    let server = Server::responses(vec![
        http(
            200,
            "ETag: \"v1\"\r\n",
            &json!({"data":[{"id":"shared","context_window":4096,"max_context_window":4096}]})
                .to_string(),
        ),
        http(
            200,
            "ETag: \"v2\"\r\n",
            &json!({"data":[{"id":"shared","description":"new description"}]}).to_string(),
        ),
        http(304, "", ""),
    ])
    .await;
    let mut first = provider(&server.url, ProtocolKind::OpenAi);
    let query = ModelCatalogQuery::for_account(&first).unwrap();
    let mut models = updated(query.execute(None).await.unwrap());
    for model in &mut models {
        model.observation.as_mut().unwrap().commit(1);
    }
    let cache = ModelCatalogQueryCache {
        identity: query.identity().into(),
        etag: Some("\"v1\"".into()),
        models,
    };
    let mut second = provider("http://127.0.0.1:1", ProtocolKind::Xai);
    accept_observation(
        &mut second,
        discover(
            json!({"data":[{"id":"shared","context_length":8192,
                "capabilities":{"reasoning_effort":["high"]}}]}),
            ProtocolKind::Xai,
        )
        .await,
        2,
    );
    let mut newest = updated(query.execute(Some(&cache)).await.unwrap());
    for model in &mut newest {
        model.observation.as_mut().unwrap().commit(3);
    }
    assert_eq!(
        newest[0].observation.as_ref().unwrap().fields
            [&pl_model::model::ModelMetadataField::ContextWindow],
        1
    );
    let cache = ModelCatalogQueryCache {
        identity: query.identity().into(),
        etag: Some("\"v2\"".into()),
        models: newest.clone(),
    };
    assert!(matches!(
        query.execute(Some(&cache)).await.unwrap(),
        ModelCatalogQueryResult::NotModified { .. }
    ));
    first.set_model_catalog_overlay(newest).unwrap();
    let mut config = AgentModelConfig::default();
    config
        .accounts
        .insert(AccountId::new("z-first").unwrap(), first);
    config
        .accounts
        .insert(AccountId::new("a-second").unwrap(), second);
    config.accounts.insert(
        AccountId::new("chat-route").unwrap(),
        AccountConfig::from_explicit_models(
            ProtocolEndpoint::compatible("chat-route", "http://127.0.0.1:1"),
            vec![ModelInfo::compatible("shared")],
        ),
    );
    config.reconcile_model_catalog().unwrap();
    let model = |id: &str| {
        config.accounts[&AccountId::new(id).unwrap()]
            .effective_models(None)
            .unwrap()
            .remove(0)
    };
    let observed = model("z-first");
    assert_eq!(observed.context_window, Some(4096));
    assert_eq!(observed.max_context_window, Some(4096));
    assert_eq!(observed.description.as_deref(), Some("new description"));
    assert!(observed.supported_efforts().is_empty());
    let sibling = model("a-second");
    assert_eq!(sibling.context_window, Some(8192));
    assert_eq!(sibling.description, None);
    assert_eq!(sibling.supported_efforts(), ["high"]);
    assert_eq!(
        sibling
            .effort_parameter()
            .unwrap()
            .wire_for("high")
            .unwrap()
            .set[0]
            .path,
        "reasoning.effort"
    );
    let chat = model("chat-route");
    assert_eq!(chat.context_window, Some(32_000));
    assert_eq!(chat.description, None);
    assert!(chat.supported_efforts().is_empty());
    assert!(
        server.finish().await[2]
            .to_ascii_lowercase()
            .contains("if-none-match: \"v2\"")
    );
}

#[tokio::test]
async fn later_success_wins_inside_the_observing_account_only() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let (started_tx, started_rx) = tokio::sync::oneshot::channel();
    let (release_tx, release_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        let mut headers = Vec::new();
        while !headers.ends_with(b"\r\n\r\n") {
            let mut byte = [0];
            socket.read_exact(&mut byte).await.unwrap();
            headers.push(byte[0]);
        }
        started_tx.send(()).unwrap();
        release_rx.await.unwrap();
        socket
            .write_all(
                http(
                    200,
                    "",
                    &json!({"data":[{"id":"shared","context_window":4096}]}).to_string(),
                )
                .as_bytes(),
            )
            .await
            .unwrap();
    });
    let mut slow = provider(&url, ProtocolKind::OpenAi);
    let query = ModelCatalogQuery::for_account(&slow).unwrap();
    let mut first_started = Box::pin(query.execute(None));
    tokio::select! {
        result = &mut first_started => panic!("response completed before release: {result:?}"),
        ready = started_rx => ready.unwrap(),
    }
    let mut fast = provider("http://127.0.0.1:1", ProtocolKind::Xai);
    accept_observation(
        &mut fast,
        discover(
            json!({"data":[{"id":"shared","display_name":"Fast source",
                "context_length":8192}]}),
            ProtocolKind::Xai,
        )
        .await,
        1,
    );
    release_tx.send(()).unwrap();
    accept_observation(&mut slow, updated(first_started.await.unwrap()), 2);
    server.await.unwrap();
    let mut config = AgentModelConfig::default();
    config
        .accounts
        .insert(AccountId::new("a-slow").unwrap(), slow);
    config
        .accounts
        .insert(AccountId::new("z-fast").unwrap(), fast);
    config.reconcile_model_catalog().unwrap();
    let model = |id: &str| {
        config.accounts[&AccountId::new(id).unwrap()]
            .effective_models(None)
            .unwrap()
            .remove(0)
    };
    // Each account only observes its own successful request; completion order is not global.
    let slow_model = model("a-slow");
    assert_eq!(slow_model.context_window, Some(4096));
    assert_eq!(slow_model.display_name, "shared");
    assert_eq!(slow_model.max_output_tokens, None);
    let fast_model = model("z-fast");
    assert_eq!(fast_model.context_window, Some(8192));
    assert_eq!(fast_model.display_name, "Fast source");
    // xAI `/models` declares no output limit; an unknown model keeps it unknown.
    assert_eq!(fast_model.max_output_tokens, None);
}

#[tokio::test]
async fn recognized_invalid_prices_fail_and_unsupported_prices_keep_local_rates() {
    for record in [
        json!({"id":"shared","prompt_text_token_price":-1,"completion_text_token_price":10}),
        json!({"id":"shared","prompt_text_token_price":1}),
        json!({"id":"shared","pricing":{"kind":"rates","currency":"USD","tiers":[]}}),
    ] {
        let server = Server::json(json!({"data":[record]})).await;
        let query =
            ModelCatalogQuery::for_account(&provider(&server.url, ProtocolKind::Xai)).unwrap();
        assert_eq!(
            query.execute(None).await.unwrap_err(),
            ModelCatalogQueryError::Protocol
        );
        server.finish().await;
    }
    let models = discover(
        json!({"data":[{"id":"shared","pricing":{"per_image":1,"currency":"USD"}}]}),
        ProtocolKind::Xai,
    )
    .await;
    assert_eq!(models[0].pricing, ModelPricing::Unknown);
    let zero_threshold = discover(json!({"data":[{"id":"priced","prompt_text_token_price":10000,"completion_text_token_price":20000,"long_context_threshold":0}]}), ProtocolKind::Xai).await;
    let omitted_threshold = discover(json!({"data":[{"id":"priced","prompt_text_token_price":10000,"completion_text_token_price":20000}]}), ProtocolKind::Xai).await;
    assert_eq!(zero_threshold[0].pricing, omitted_threshold[0].pricing);
}

#[tokio::test]
async fn current_endpoint_prefix_query_auth_and_safe_identity_are_used() {
    let server = Server::json(json!({"data":[{"id":"unregistered-Future-ID"}]})).await;
    let mut config = provider(
        &format!("{}/tenant/proxy/?region=synthetic-secret", server.url),
        ProtocolKind::OpenAi,
    );
    config.bearer_token = Some("synthetic-token".into());
    config.http_headers = Some(HashMap::from([(
        "x-account".into(),
        "synthetic-account".into(),
    )]));
    let query = ModelCatalogQuery::for_account(&config).unwrap();
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
    assert_eq!(model.model_id, "unregistered-Future-ID");
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
        model_descriptor(&config.effective_catalog(None).unwrap()[0]);
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
            ModelCatalogQuery::for_account(&changed).unwrap().identity(),
            identity
        );
    }
    config.http_headers = Some(HashMap::from([(
        "X-Account".into(),
        "synthetic-account".into(),
    )]));
    assert_eq!(
        ModelCatalogQuery::for_account(&config).unwrap().identity(),
        identity
    );
    let explicit = AccountConfig::from_explicit_models(
        ProtocolEndpoint::openai(None),
        vec![ModelInfo::compatible("manual")],
    );
    assert!(matches!(
        ModelCatalogQuery::for_account(&explicit),
        Err(ModelCatalogQueryError::Unsupported)
    ));
    let unsupported = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::zhipu(None),
        ModelCatalogId::new("zhipu").unwrap(),
        Vec::new(),
    );
    assert!(matches!(
        ModelCatalogQuery::for_account(&unsupported),
        Err(ModelCatalogQueryError::Unsupported)
    ));
    config.http_headers = Some(HashMap::from([
        ("x-account".into(), "one".into()),
        ("X-Account".into(), "two".into()),
    ]));
    assert!(matches!(
        ModelCatalogQuery::for_account(&config),
        Err(ModelCatalogQueryError::Configuration)
    ));
}
fn independent_query_identity(
    magic: &[u8],
    protocol: Option<&str>,
    catalog: &str,
    discovery_transport: &str,
    url: &str,
    headers: &[(&str, &str)],
) -> String {
    use sha2::{Digest, Sha256};
    let mut hash = Sha256::new();
    let mut part = |bytes: &[u8]| {
        hash.update((bytes.len() as u64).to_be_bytes());
        hash.update(bytes);
    };
    part(magic);
    part(catalog.as_bytes());
    if let Some(protocol) = protocol {
        part(protocol.as_bytes());
    }
    part(discovery_transport.as_bytes());
    part(url.as_bytes());
    let mut sorted = headers.to_vec();
    sorted.sort_by(|left, right| left.0.cmp(right.0));
    for (name, value) in sorted {
        part(name.as_bytes());
        part(value.as_bytes());
    }
    hex::encode(hash.finalize())
}

/// Query 身份绑定厂商协议；旧 v1 定位方法只供显式缓存迁移使用。
#[tokio::test]
async fn query_identity_binds_vendor_protocol_and_locates_legacy_v1_only_for_migration() {
    let server = Server::json(json!({"data":[{"id":"x","context_window":4096}]})).await;
    let mut config = provider(&server.url, ProtocolKind::DeepSeek);
    config.bearer_token = Some("synthetic-token".into());
    config.http_headers = Some(HashMap::from([(
        "x-account".into(),
        "synthetic-account".into(),
    )]));
    let url = format!("{}/models", server.url);
    let headers = [
        ("authorization", "Bearer synthetic-token"),
        ("x-account", "synthetic-account"),
    ];
    let expected_v1 = independent_query_identity(
        b"model-catalog-query-v1",
        None,
        "deepseek",
        "responses-http",
        &url,
        &headers,
    );
    let expected_v2 = independent_query_identity(
        b"model-catalog-query-v2",
        Some("deep_seek"),
        "deepseek",
        "responses-http",
        &url,
        &headers,
    );
    let query = ModelCatalogQuery::for_account(&config).unwrap();
    assert_eq!(query.identity(), expected_v2);
    assert_eq!(query.legacy_v1_identity_for_migration(), expected_v1);
    assert_ne!(query.identity(), expected_v1);

    // 显示名不是身份；账号外层 ID 也不进入 query 内 hash。
    let mut renamed = config.clone();
    renamed.name = "Renamed display".into();
    assert_eq!(
        ModelCatalogQuery::for_account(&renamed).unwrap().identity(),
        expected_v2
    );

    // 只切换厂商协议是合法配置；当前身份必须变化，旧 v1 locator 保持同一文件定位。
    let mut switched = config.clone();
    switched.protocol = ProtocolKind::OpenAiCompatible;
    switched
        .validate_declarations(&AccountId::new("switched").unwrap())
        .unwrap();
    let switched_query = ModelCatalogQuery::for_account(&switched).unwrap();
    let expected_switched = independent_query_identity(
        b"model-catalog-query-v2",
        Some("open_ai_compatible"),
        "deepseek",
        "responses-http",
        &url,
        &headers,
    );
    assert_eq!(switched_query.identity(), expected_switched);
    assert_ne!(switched_query.identity(), query.identity());
    assert_eq!(
        switched_query.legacy_v1_identity_for_migration(),
        expected_v1
    );

    // 旧 protocol 的当前缓存不能被新 protocol 复用，也不应发出请求。
    let models = updated(query.execute(None).await.unwrap());
    let cache = ModelCatalogQueryCache {
        identity: query.identity().into(),
        etag: None,
        models,
    };
    assert_eq!(
        switched_query.execute(Some(&cache)).await.unwrap_err(),
        ModelCatalogQueryError::CacheIdentity
    );
    let requests = server.finish().await;
    assert_eq!(
        requests.len(),
        1,
        "a mismatched current identity must not reach the network"
    );
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
    for (adapter, body, effort_path, declares_image) in [
        (
            ProtocolKind::DeepSeek,
            json!({"data":[{"id":"future-model","name":"Future","context_window":64000,"max_output_tokens":8000,"input_modalities":["text","image"],"output_modalities":["text"],"effort":{"supported_levels":["gentle","new-ultra"],"default_level":"new-ultra"},"pricing":{"input":0},"supports_function_calling":true}]}),
            "reasoning_effort",
            true,
        ),
        (
            ProtocolKind::OpenAi,
            json!({"models":[{"slug":"future-model","display_name":"Future","description":"independent metadata","context_window":64000,"max_context_window":128000,"auto_compact_token_limit":12000,"supported_reasoning_levels":[{"effort":"gentle","description":"less"},{"effort":"new-ultra","description":"more"}],"default_reasoning_level":"new-ultra","base_instructions":"DO NOT IMPORT","shell_type":"powershell","supports_temperature":false}]}),
            "reasoning",
            true,
        ),
        (
            ProtocolKind::Xai,
            json!({"data":[{"id":"future-model","context_length":64000,"input_modalities":["text","image"],"output_modalities":["text"],"capabilities":{"reasoning_effort":["gentle","new-ultra"],"default_reasoning_effort":"new-ultra"}}]}),
            "reasoning",
            false,
        ),
    ] {
        let models = discover(body, adapter).await;
        let mut model = models[0].clone();
        assert_eq!(model.supported_efforts(), ["gentle", "new-ultra"]);
        assert_eq!(model.default_effort().as_deref(), Some("new-ultra"));
        assert_eq!(model.context_window, Some(64000));
        assert_eq!(
            model
                .capabilities
                .supports_input_modality(ModelModality::Image),
            declares_image,
            "only a vendor that declared image input (or the OpenAI Codex default) exposes it"
        );
        assert!(model.base_instructions.is_empty());
        let mut config = provider("http://127.0.0.1:1", adapter);
        config.set_model_catalog_overlay(models).unwrap();
        let descriptor = model_descriptor(&config.effective_catalog(None).unwrap()[0]);
        assert_eq!(descriptor.context_window, Some(64000));
        let preset = (adapter == ProtocolKind::OpenAi).then_some(12_000);
        assert_eq!(descriptor.auto_compact_token_limit, preset);
        assert_eq!(
            model.resolved_auto_compact_limit(),
            Some(preset.unwrap_or(57_600))
        );
        assert_eq!(descriptor.pricing, None);
        let reasoning = descriptor.reasoning.unwrap();
        assert_eq!(reasoning.candidates, ["gentle", "new-ultra"]);
        assert_eq!(reasoning.default.as_deref(), Some("new-ultra"));
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
            ProtocolKind::OpenAi => ProtocolEndpoint::openai(Some(fixture.base_url())),
            ProtocolKind::Xai => ProtocolEndpoint::xai(Some(fixture.base_url())),
            _ => ProtocolEndpoint::deepseek(Some(fixture.base_url())),
        };
        model.binding.transport.default_connection_mode = pl_model::protocol::ConnectionMode::Http;
        let runtime = ModelRuntime::new_with_account_id("fixture", endpoint, model).unwrap();
        let mut png = std::io::Cursor::new(Vec::new());
        image::DynamicImage::new_rgb8(1, 1)
            .write_to(&mut png, image::ImageFormat::Png)
            .unwrap();
        let mut parts = vec![ContentPart::Text {
            text: "hello".into(),
        }];
        let mut attachments = Vec::new();
        if declares_image {
            parts.push(ContentPart::Attachment {
                attachment_id: "pixel".into(),
                modality: AttachmentModality::Image,
                media_type: "image/png".into(),
                filename: None,
            });
            attachments.push(AttachmentInput {
                attachment_id: "pixel".into(),
                modality: AttachmentModality::Image,
                media_type: "image/png".into(),
                filename: None,
                source: AttachmentSource::Bytes {
                    bytes: std::sync::Arc::from(png.into_inner()),
                },
            });
        }
        let request = CompletionRequest::builder()
            .messages(vec![Message {
                role: MessageRole::User,
                content: MessageContent::new(parts),
                reasoning_content: None,
                tool_calls: None,
                tool_result: None,
                metadata: Default::default(),
                presentation: Default::default(),
            }])
            .attachments(attachments)
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
            let content = record.body["input"][0]["content"].as_array().unwrap();
            if declares_image {
                assert_eq!(content[1]["type"], "input_image");
                assert!(
                    content[1]["image_url"]
                        .as_str()
                        .unwrap()
                        .starts_with("data:image/png;base64,")
                );
            } else {
                assert_eq!(content.len(), 1);
                assert_eq!(content[0]["type"], "input_text");
            }
        }
    }
}

/// 各厂商只解释自己的 envelope、字段与价格单位；未知模态不虚构图片。
#[tokio::test]
async fn vendor_typed_catalog_boundaries_do_not_leak_envelopes_fields_or_prices() {
    let error = |server: Server, kind: ProtocolKind| async move {
        let query = ModelCatalogQuery::for_account(&provider(&server.url, kind)).unwrap();
        assert_eq!(
            query.execute(None).await.unwrap_err(),
            ModelCatalogQueryError::Protocol
        );
        server.finish().await;
    };
    // OpenAI/Codex `models`/`slug` 不是 DeepSeek 或 OpenAI-compatible 的合法名单。
    for body in [
        json!({"models":[{"slug":"x"}]}),
        json!({"data":[{"slug":"x"}]}),
        json!({"models":[],"data":[]}),
    ] {
        let server = Server::json(body).await;
        error(server, ProtocolKind::DeepSeek).await;
    }
    for body in [
        json!({"models":[{"slug":"x"}]}),
        json!({"data":[{"slug":"x"}]}),
    ] {
        let server = Server::json(body).await;
        error(server, ProtocolKind::MiMo).await;
    }
    for body in [
        json!({"models":[{"slug":"x"}]}),
        json!({"data":[{"slug":"x"}]}),
    ] {
        let server = Server::json(body).await;
        error(server, ProtocolKind::Xai).await;
    }

    // DeepSeek 忽略 xAI 专属字段：context_length 与官方 token 价格不生效。
    let deepseek = discover(
        json!({"data":[{"id":"x","context_length":4096,
            "prompt_text_token_price":20000,"completion_text_token_price":100000}]}),
        ProtocolKind::DeepSeek,
    )
    .await
    .remove(0);
    assert_eq!(deepseek.context_window, None);
    assert_eq!(deepseek.pricing, ModelPricing::Unknown);

    // xAI 用 context_length 与官方 native 价格单位（USD cents/100M）；context_window 不生效。
    let xai = discover(
        json!({"data":[{"id":"x","context_length":4096,"context_window":9999,
            "input_modalities":["text","image"],"output_modalities":["text"],
            "prompt_text_token_price":20000,"completion_text_token_price":100000,
            "cached_prompt_text_token_price":5000}]}),
        ProtocolKind::Xai,
    )
    .await
    .remove(0);
    assert_eq!(xai.context_window, Some(4096));
    assert!(
        !xai.capabilities
            .supports_input_modality(ModelModality::Image),
        "xAI /models declares no modalities; extension fields are ignored"
    );
    let ModelPricing::Rates {
        currency, tiers, ..
    } = xai.pricing
    else {
        panic!("xAI native token price must be a token rate")
    };
    assert_eq!(currency, "USD");
    assert_eq!(tiers[0].input_per_mtok, 2.0);
    assert_eq!(tiers[0].output_per_mtok, 10.0);
    assert_eq!(tiers[0].cache_read_per_mtok, Some(0.5));

    // OpenAI 不套用 xAI 字段，也不因此产生价格或窗口声明。
    let openai = discover(
        json!({"models":[{"slug":"x","context_length":4096,
            "prompt_text_token_price":20000,"completion_text_token_price":100000}]}),
        ProtocolKind::OpenAi,
    )
    .await
    .remove(0);
    assert_eq!(openai.context_window, None);
    assert_eq!(openai.pricing, ModelPricing::Unknown);

    // xAI 只接受自己的 reasoning_effort 声明，Codex/DeepSeek 的候选字段不生效。
    let xai_ignored = discover(
        json!({"data":[{"id":"x","supported_reasoning_levels":[{"effort":"low"}],
            "reasoningEfforts":[{"value":"low"}],"reasoning_effort":["low"]}]}),
        ProtocolKind::Xai,
    )
    .await
    .remove(0);
    assert!(xai_ignored.supported_efforts().is_empty());
    let xai_effort = discover(
        json!({"data":[{"id":"x","capabilities":{
            "reasoning_effort":["low","high"],"default_reasoning_effort":"high"}}]}),
        ProtocolKind::Xai,
    )
    .await
    .remove(0);
    assert_eq!(xai_effort.supported_efforts(), ["low", "high"]);
    assert_eq!(xai_effort.default_effort().as_deref(), Some("high"));
    assert_eq!(
        xai_effort
            .effort_parameter()
            .unwrap()
            .wire_for("high")
            .unwrap()
            .set[0]
            .path,
        "reasoning.effort"
    );

    // 缺模态声明的未知模型保持 text-only：只有 OpenAI/Codex 缺省 text+image。
    let openai_unknown = discover(json!({"models":[{"slug":"unknown"}]}), ProtocolKind::OpenAi)
        .await
        .remove(0);
    assert!(
        openai_unknown
            .capabilities
            .supports_input_modality(ModelModality::Image)
    );
    for kind in [
        ProtocolKind::DeepSeek,
        ProtocolKind::Xai,
        ProtocolKind::MiMo,
    ] {
        let unknown = discover(json!({"data":[{"id":"unknown"}]}), kind)
            .await
            .remove(0);
        assert!(
            !unknown
                .capabilities
                .supports_input_modality(ModelModality::Image),
            "{kind:?} must not fabricate image input"
        );
        assert!(
            unknown.binding.request.media.is_empty(),
            "{kind:?} must not fabricate a media profile"
        );
        assert_eq!(unknown.resolved_context_window(), None);
    }

    // OpenAI-compatible 共同契约可用，但 xAI 的 context_length 不生效。
    let mimo = discover(
        json!({"data":[{"id":"mimo-x","context_window":8192,"context_length":4096,
            "supports_function_calling":true}]}),
        ProtocolKind::MiMo,
    )
    .await
    .remove(0);
    assert_eq!(mimo.context_window, Some(8192));
    assert!(mimo.capabilities.tools.function_calling);
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
        http(200,"", &json!({"data":[{"id":known.model_id}]}).to_string()),
        http(200,"", &json!({"models":[{"slug":known.model_id,"supported_reasoning_levels":[],"input_modalities":[],"output_modalities":[],"supports_streaming":false,"supports_function_calling":false}]}).to_string()),
        http(200,"", &json!({"data":[{"id":"cached-only"}]}).to_string()),
        http(200,"", &json!({"data":[{"id":"cached-only","capabilities":{"input":[{"modality":"text","sources":[]}]}}]}).to_string()),
    ]).await;
    let query =
        ModelCatalogQuery::for_account(&provider(&server.url, ProtocolKind::OpenAi)).unwrap();
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
    cached.model_id = "cached-only".into();
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
        !third[0]
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
    let adapter = ProtocolKind::OpenAi;
    let model_id = "gpt-6.1-sol";
    let mut old = discover(
        json!({"data":[{"id":"unregistered-old-id","display_name":"GPT-6.1 Sol","description":"Provider description without capability declarations."}]}),
        adapter,
    )
    .await
    .remove(0);
    old.model_id = model_id.into();
    old.observation = None;
    // Persisted skeleton from the previous text-only normalization rule.
    old.capabilities.input = vec![pl_model::model::ModelInputCapability::text()];
    old.binding.request.media.clear();
    let description = old.description.clone();
    let server = Server::responses(vec![
        http(200, "", &json!({"data":[{"id":model_id,"display_name":"GPT-6.1 Sol","created":1790640000,"object":"model","owned_by":"openai","type":"model"}]}).to_string()),
        http(200, "", &json!({"data":[{"id":model_id,"input_modalities":["text"],"supported_reasoning_levels":[]}]}).to_string()),
    ]).await;
    let mut config = provider(&server.url, adapter);
    let query = ModelCatalogQuery::for_account(&config).unwrap();
    let cache = ModelCatalogQueryCache {
        identity: query.identity().into(),
        etag: None,
        models: vec![old],
    };
    // Unknown legacy provenance stays usable and is completed by the canonical global catalog.
    config
        .set_model_catalog_overlay(cache.models.clone())
        .unwrap();
    let mut canonical = AgentModelConfig {
        accounts: [(AccountId::new("instance").unwrap(), config.clone())].into(),
        routes: Default::default(),
    };
    canonical.reconcile_model_catalog().unwrap();
    let startup = canonical
        .accounts
        .values()
        .next()
        .unwrap()
        .effective_models(None)
        .unwrap()
        .remove(0);
    assert_eq!(startup.display_name, "GPT-6.1 Sol");
    assert_eq!(
        startup.description,
        bundled_model_definition("openai")
            .unwrap()
            .models
            .into_iter()
            .find(|model| model.model_id == model_id)
            .unwrap()
            .description
    );
    assert!(
        startup
            .capabilities
            .supports_input_modality(ModelModality::Image)
    );
    let models = updated(query.execute(Some(&cache)).await.unwrap());
    config.set_model_catalog_overlay(models).unwrap();
    let mut model = config.effective_models(None).unwrap().remove(0);
    assert_eq!(model.model_id, model_id);
    assert_eq!(model.description, description);
    assert_eq!(model.context_window, Some(1_050_000));
    assert_eq!(
        model_descriptor(&pl_model::config::AccountModelEntry {
            model: model.clone(),
            origin: pl_model::config::AccountModelOrigin::Online,
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
        model_descriptor(&pl_model::config::AccountModelEntry {
            model: model.clone(),
            origin: pl_model::config::AccountModelOrigin::Online,
        })
        .pricing
        .is_some()
    );
    let explicit = updated(query.execute(None).await.unwrap());
    config.set_model_catalog_overlay(explicit).unwrap();
    let explicit = config.effective_models(None).unwrap().remove(0);
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
        Reply::Sse(responses_text("a pixel", "gpt61-image", model_id)),
    )])
    .await
    .unwrap();
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::openai(Some(fixture.base_url())),
        model,
    )
    .unwrap();
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
    assert_eq!(records[0].body["model"], model_id);
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
    let mut config = provider(&server.url, ProtocolKind::DeepSeek);
    let models = updated(
        ModelCatalogQuery::for_account(&config)
            .unwrap()
            .execute(None)
            .await
            .unwrap(),
    );
    assert_eq!(models.len(), 1);
    assert_eq!(models[0].model_id, "deepseek-flash");
    assert_eq!(models[0].context_window, Some(1_048_576));
    assert_eq!(models[0].max_context_window, Some(1_048_576));
    // 未违反上限的继承默认预算保持原值。
    assert_eq!(models[0].max_output_tokens, Some(384_000));
    config.set_model_catalog_overlay(models).unwrap();
    let entry = &config.effective_catalog(None).unwrap()[0];
    assert_eq!(entry.origin, pl_model::config::AccountModelOrigin::Online);
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
        .find(|model| model.model_id == "gpt-6.1-sol")
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
        ModelCatalogQuery::for_account(&provider(&server.url, ProtocolKind::OpenAi)).unwrap();
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
    let mut config = provider("http://127.0.0.1:1", ProtocolKind::OpenAi);
    config.set_model_catalog_overlay(raised.clone()).unwrap();
    let effective = config.effective_catalog(None).unwrap();
    let entry = &effective[0];
    assert_eq!(entry.origin, pl_model::config::AccountModelOrigin::Online);
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
    assert_eq!(online_effort[0].model_id, "unregistered-online-effort");
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
            ModelCatalogQuery::for_account(&provider(&conflict.url, ProtocolKind::OpenAi)).unwrap();
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
    let mut config = provider(&server.url, ProtocolKind::DeepSeek);
    let models = updated(
        ModelCatalogQuery::for_account(&config)
            .unwrap()
            .execute(None)
            .await
            .unwrap(),
    );
    server.finish().await;
    assert_eq!(
        models
            .iter()
            .map(|model| model.model_id.as_str())
            .collect::<Vec<_>>(),
        ["deepseek-flash", "deepseek-v4-pro"]
    );
    // 未知字段（如 `api_capabilities`）被忽略，且不使整份名单解析失败。
    let flash = models
        .iter()
        .find(|model| model.model_id == "deepseek-flash")
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
    let effective = config.effective_catalog(None).unwrap();
    for model_id in ["deepseek-flash", "deepseek-v4-pro"] {
        let entry = effective
            .iter()
            .find(|entry| entry.model.model_id == model_id)
            .unwrap();
        assert_eq!(entry.origin, pl_model::config::AccountModelOrigin::Online);
        // 价格只按该 provider 绑定目录的大小写敏感精确 ID 关联。
        let local = definition
            .models
            .iter()
            .find(|model| model.model_id == model_id)
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
        .find(|model| model.model_id == "deepseek-flash")
        .unwrap();
    let builtin_pro = definition
        .models
        .iter()
        .find(|model| model.model_id == "deepseek-v4-pro")
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
    let mut config = provider(&server.url, ProtocolKind::DeepSeek);
    let query = ModelCatalogQuery::for_account(&config).unwrap();
    let models = updated(query.execute(None).await.unwrap());
    assert_eq!(
        models
            .iter()
            .map(|model| model.model_id.as_str())
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
    let effective = config.effective_catalog(None).unwrap();
    let flash_entry = effective
        .iter()
        .find(|entry| entry.model.model_id == "deepseek-flash")
        .unwrap();
    assert_eq!(
        flash_entry.origin,
        pl_model::config::AccountModelOrigin::Online
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
        .find(|entry| entry.model.model_id == "deepseek-v4-pro")
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
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::deepseek(Some(fixture.base_url())),
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
        ModelCatalogQuery::for_account(&provider(&server.url, ProtocolKind::DeepSeek)).unwrap();
    let cache = ModelCatalogQueryCache {
        identity: query.identity().into(),
        etag: None,
        models: vec![cached_model("last-good", ProtocolKind::DeepSeek)],
    };
    let error = query.execute(Some(&cache)).await.unwrap_err();
    assert_eq!(error, ModelCatalogQueryError::Protocol);
    assert_eq!(cache.models[0].model_id, "last-good");
    server.finish().await;
}

#[tokio::test]
async fn overlay_replaces_inventory_manual_wins_and_prices_join_only_local_exact_ids() {
    let definition = bundled_model_definition("openai").unwrap();
    let known = &definition.models[0];
    let model_id = known.model_id.clone();
    let foreign = bundled_model_definition("deepseek").unwrap().models[0]
        .model_id
        .clone();
    let api = discover(json!({"data":[{"id":model_id},{"id":model_id.to_uppercase()},{"id":format!("{model_id}-variant")},{"id":foreign},{"id":"manual"}]}), ProtocolKind::OpenAi).await;
    let mut config = provider("http://127.0.0.1:1", ProtocolKind::OpenAi);
    let mut manual = ModelInfo::compatible("manual");
    manual.display_name = "Authoritative manual model".into();
    manual.pricing = known.pricing.clone();
    if let pl_model::config::AccountModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut config.catalog
    {
        additional_models.push(manual.clone());
    }
    config.set_model_catalog_overlay(api).unwrap();
    let effective = config.effective_models(None).unwrap();
    assert_eq!(
        effective
            .iter()
            .find(|m| m.model_id == model_id)
            .unwrap()
            .pricing,
        known.pricing
    );
    for model in effective
        .iter()
        .filter(|m| m.model_id != model_id && m.model_id != "manual")
    {
        assert_eq!(model.pricing, ModelPricing::Unknown);
        assert_eq!(model.context_window, None);
    }
    assert_eq!(
        effective.iter().find(|m| m.model_id == "manual").unwrap(),
        &manual
    );
    let persisted = serde_json::to_value(&config).unwrap();
    let reread: AccountConfig = serde_json::from_value(persisted).unwrap();
    assert!(!reread.has_model_catalog_overlay());
    config.set_model_catalog_overlay(Vec::new()).unwrap();
    assert_eq!(config.effective_models(None).unwrap(), vec![manual]);
    if let pl_model::config::AccountModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut config.catalog
    {
        additional_models.push(known.clone());
    }
    assert_eq!(
        config
            .effective_catalog(None)
            .unwrap()
            .iter()
            .filter(|entry| entry.model.model_id == known.model_id)
            .count(),
        1
    );
    let empty = discover(json!({"data":[]}), ProtocolKind::DeepSeek).await;
    assert!(empty.is_empty());
    let mut fresh = provider("http://127.0.0.1:1", ProtocolKind::DeepSeek);
    fresh.set_model_catalog_overlay(empty).unwrap();
    assert!(fresh.effective_models(None).unwrap().is_empty());
}

#[tokio::test]
async fn availability_preserves_removed_choice_without_weakening_strict_edits_or_structure_validation()
 {
    let mut selected_provider = provider("http://127.0.0.1:1", ProtocolKind::OpenAi);
    let mut selected = selected_provider.effective_models(None).unwrap()[0].clone();
    selected.model_id = "remote-only-choice".into();
    selected_provider
        .set_model_catalog_overlay(vec![selected.clone()])
        .unwrap();
    selected_provider
        .set_model_connection_mode(&selected.model_id, pl_model::protocol::ConnectionMode::Http)
        .unwrap();
    selected_provider
        .set_model_auto_compact_override(&selected.model_id, Some(1234))
        .unwrap();
    selected_provider
        .set_model_catalog_overlay(Vec::new())
        .unwrap();
    let id = AccountId::new("instance-a").unwrap();
    let role = AgentRoleId::new("explorer").unwrap();
    let route = ModelRouteConfig {
        account_id: id.clone(),
        model_id: selected.model_id.clone(),
        effort: selected.default_effort().map(ReasoningEffort::new),
    };
    let mut config = AgentModelConfig {
        accounts: [(id.clone(), selected_provider)].into(),
        routes: [(role.clone(), route.clone())].into(),
    };
    config.validate_declarations().unwrap();
    assert_eq!(
        config.route_availability(&route).unwrap(),
        ModelRouteAvailability::ModelUnavailable {
            account_id: id.clone(),
            model_id: selected.model_id.clone()
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
    let mut narrowed = cached_model("connection-choice", ProtocolKind::OpenAi);
    narrowed.binding.transport.supported_connection_modes = vec![ConnectionMode::WebSocket];
    let server = Server::json(json!({"models":[{
        "slug": narrowed.model_id,
        "binding": narrowed.binding,
        "input_modalities": ["text"],
        "context_window": 64000
    }]}))
    .await;
    let mut connection_provider = provider(&server.url, ProtocolKind::OpenAi);
    connection_provider
        .set_model_catalog_overlay(vec![cached_model(
            "connection-choice",
            ProtocolKind::OpenAi,
        )])
        .unwrap();
    connection_provider
        .set_model_connection_mode("connection-choice", ConnectionMode::Http)
        .unwrap();
    let desired_before_observation = serde_json::to_value(&connection_provider).unwrap();
    let query = ModelCatalogQuery::for_account(&connection_provider).unwrap();
    let observed = updated(query.execute(None).await.unwrap());
    assert_eq!(observed[0].binding.transport, narrowed.binding.transport);
    connection_provider
        .set_model_catalog_overlay(observed)
        .unwrap();
    connection_provider.validate_declarations(&id).unwrap();
    let display = model_descriptor(&connection_provider.effective_catalog(None).unwrap()[0]);
    assert_eq!(display.context_window, Some(64000));
    assert_eq!(display.transport.default_connection_mode, "web_socket");
    assert_eq!(display.transport.connection_modes.len(), 1);
    assert_eq!(display.transport.connection_modes[0].id, "web_socket");
    assert_eq!(
        connection_provider.connection_overrides()["connection-choice"],
        ConnectionMode::Http
    );
    let connection_route = ModelRouteConfig {
        account_id: id.clone(),
        model_id: "connection-choice".into(),
        effort: None,
    };
    let mut connection_config = AgentModelConfig {
        accounts: [(id.clone(), connection_provider)].into(),
        routes: [(role.clone(), connection_route.clone())].into(),
    };
    connection_config.validate_declarations().unwrap();
    assert_eq!(
        connection_config
            .route_availability(&connection_route)
            .unwrap(),
        ModelRouteAvailability::ConnectionUnavailable {
            account_id: id.clone(),
            model_id: "connection-choice".into(),
            connection_mode: ConnectionMode::Http,
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
        serde_json::to_value(&connection_config.accounts[&id]).unwrap(),
        desired_before_observation
    );
    assert_eq!(connection_config.routes[&role], connection_route);
    let mut manual_config = connection_config.clone();
    if let pl_model::config::AccountModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut manual_config.accounts.get_mut(&id).unwrap().catalog
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
        ConnectionMode::Http
    );
    if let pl_model::config::AccountModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut manual_config.accounts.get_mut(&id).unwrap().catalog
    {
        additional_models[0] = narrowed.clone();
    }
    assert!(manual_config.validate_declarations().is_err());
    assert!(manual_config.route_availability(&connection_route).is_err());
    assert!(manual_config.resolve(&role).is_err());
    let mut explicit =
        AccountConfig::from_explicit_models(ProtocolEndpoint::openai(None), vec![narrowed.clone()]);
    if let pl_model::config::AccountModelCatalogConfig::Explicit {
        connection_overrides,
        ..
    } = &mut explicit.catalog
    {
        connection_overrides.insert(narrowed.model_id.clone(), ConnectionMode::Http);
    }
    assert!(explicit.effective_models(None).is_err());
    assert!(explicit.validate_declarations(&id).is_err());
    let mut non_discovery = connection_config.clone();
    let provider = non_discovery.accounts.get_mut(&id).unwrap();
    let connection_overrides = provider.connection_overrides().clone();
    let auto_compact_overrides = provider.auto_compact_overrides().clone();
    provider.catalog = pl_model::config::AccountModelCatalogConfig::Bundled {
        catalog: ModelCatalogId::new("zhipu").unwrap(),
        additional_models: Vec::new(),
        connection_overrides,
        auto_compact_overrides,
    };
    assert!(non_discovery.validate_declarations().is_err());
    let mut bad_profile = manual_config.clone();
    if let pl_model::config::AccountModelCatalogConfig::Bundled {
        additional_models,
        connection_overrides,
        ..
    } = &mut bad_profile.accounts.get_mut(&id).unwrap().catalog
    {
        // Even an otherwise valid override cannot repair a contradictory declared default.
        additional_models[0]
            .binding
            .transport
            .default_connection_mode = ConnectionMode::Http;
        connection_overrides.insert(narrowed.model_id.clone(), ConnectionMode::WebSocket);
    }
    assert!(bad_profile.validate_declarations().is_err());
    let instance = connection_config.accounts.get_mut(&id).unwrap();
    assert!(
        instance
            .set_model_connection_mode("connection-choice", ConnectionMode::Http)
            .is_err()
    );
    assert_eq!(
        instance.connection_overrides()["connection-choice"],
        ConnectionMode::Http
    );
    instance
        .set_model_connection_mode("connection-choice", ConnectionMode::WebSocket)
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
        ConnectionMode::WebSocket
    );
    // Only discovery was sent: rejected resolution cannot construct a fallback inference request.
    let requests = server.finish().await;
    assert_eq!(requests.len(), 1);
    assert!(requests[0].starts_with("GET /models HTTP/1.1\r\n"));

    let mut current = selected.clone();
    current.parameters.clear();
    current.binding.request.body.clear();
    config
        .accounts
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
    if let pl_model::config::AccountModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut config.accounts.get_mut(&id).unwrap().catalog
    {
        additional_models.push(manual);
    }
    let manual_route = ModelRouteConfig {
        account_id: id.clone(),
        model_id: "manual-choice".into(),
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
    config.accounts.get_mut(&id).unwrap().name.clear();
    assert!(config.route_availability(&route).is_err());
}

#[tokio::test]
async fn invalid_declaration_rejects_whole_response_without_leaking_response_or_mutating_cache() {
    let invalid_profile = json!({"transport":{"protocol":"chat_completions","supported_connection_modes":["web_socket"],"default_connection_mode":"web_socket"},"request":{"protocol":{"api":"chatCompletions","parallelToolCalls":false,"maxTokensField":"max_tokens","includeUsage":false,"toolStream":false}}});
    let mut invalid_bodies = vec![
        json!({"data":[{"id":" "}]}),
        json!({"data":[{"id":"ok","context_window":0}]}),
        json!({"data":[{"id":"ok","max_output_tokens":-1}]}),
        json!({"data":[{"id":"ok","effort":{"supported_levels":["one"],"default_level":"absent"}}]}),
        json!({"data":[{"id":"ok","effort":{"supported_levels":["one"],"default_level":"one"},"default_reasoning_level":"absent"}]}),
        json!({"data":[{"id":"ok","reasoningEfforts":[{"value":"low","default":true},{"value":"high","default":true}]}]}),
        json!({"data":[{"id":"ok","reasoningEfforts":[{"value":"low","default":true}],"reasoningEffort":"high"}]}),
        json!({"data":[{"id":"ok","reasoningEfforts":[{"value":"low"}],"supportsReasoningEffort":false}]}),
        json!({"data":[{"id":"ok","reasoningEfforts":[{"value":"low"},{"value":"low"}]}]}),
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
        let mut binding =
            serde_json::to_value(cached_model("invalid-profile", ProtocolKind::OpenAi).binding)
                .unwrap();
        binding["transport"]["protocol"] = json!(protocol);
        binding["transport"]["supported_connection_modes"] = modes;
        binding["transport"]["default_connection_mode"] = json!(default);
        invalid_bodies.push(json!({"models":[{"slug":"valid-before-invalid"},{"slug":"invalid-profile","binding":binding}]}));
    }
    for body in invalid_bodies {
        let server = Server::json(body).await;
        let query =
            ModelCatalogQuery::for_account(&provider(&server.url, ProtocolKind::OpenAi)).unwrap();
        let cache = ModelCatalogQueryCache {
            identity: query.identity().into(),
            etag: None,
            models: vec![cached_model("last-good", ProtocolKind::OpenAi)],
        };
        let error = query.execute(Some(&cache)).await.unwrap_err();
        assert_eq!(error, ModelCatalogQueryError::Protocol);
        assert!(!format!("{error:?}: {error}").contains("synthetic-secret-response"));
        assert_eq!(cache.models[0].model_id, "last-good");
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
        ModelCatalogQuery::for_account(&provider(&server.url, ProtocolKind::OpenAi)).unwrap();
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
    let mut priced = cached_model("cached-price", ProtocolKind::OpenAi);
    priced.pricing = ModelPricing::published(
        "USD",
        vec![pl_model::model::TokenPriceTier::flat(-1.0, 2.0, None, None)],
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
    let mut model = cached_model("profile-order", ProtocolKind::OpenAi);
    model.binding.transport.supported_connection_modes.reverse();
    let models = discover(
        json!({"data":[{"id":model.model_id,"binding":model.binding,"input_modalities":["text"]}]}),
        ProtocolKind::OpenAi,
    )
    .await;
    assert_eq!(
        models[0].binding.transport,
        ModelTransportProfile::responses_websocket()
    );
    let mut config = provider("http://127.0.0.1:1", ProtocolKind::OpenAi);
    config
        .set_model_catalog_overlay(vec![model.clone()])
        .unwrap();
    config
        .set_model_connection_mode("profile-order", pl_model::protocol::ConnectionMode::Http)
        .unwrap();
    assert_eq!(
        config.effective_models(None).unwrap()[0]
            .binding
            .transport
            .default_connection_mode,
        pl_model::protocol::ConnectionMode::Http
    );

    model.binding.transport.supported_connection_modes = vec![ConnectionMode::WebSocket];
    let server = Server::responses(vec![
        http(
            200,
            "ETag: \"narrowed\"\r\n",
            &json!({"models":[{"slug":model.model_id,"binding":model.binding,"input_modalities":["text"]}]}).to_string(),
        ),
        http(304, "", ""),
        http(200, "", &json!({"data":[{"id":model.model_id}]}).to_string()),
    ])
    .await;
    let query =
        ModelCatalogQuery::for_account(&provider(&server.url, ProtocolKind::OpenAi)).unwrap();
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
    let descriptor = model_descriptor(&config.effective_catalog(None).unwrap()[0]);
    assert_eq!(descriptor.transport.connection_modes.len(), 1);
    assert_eq!(descriptor.transport.connection_modes[0].id, "web_socket");
    for modes in [
        Vec::new(),
        vec![ConnectionMode::WebSocket, ConnectionMode::WebSocket],
        vec![ConnectionMode::Http],
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
    assert_eq!(config.effective_models(None).unwrap(), inherited);
    let requests = server.finish().await;
    assert_eq!(requests.len(), 3);
    assert!(
        requests[1]
            .to_ascii_lowercase()
            .contains("if-none-match: \"narrowed\"\r\n")
    );

    let deepseek = cached_model("deepseek-profile", ProtocolKind::DeepSeek);
    let observed = discover(
        json!({"data":[{"id":deepseek.model_id,"binding":deepseek.binding,"input_modalities":["text"]}]}),
        ProtocolKind::DeepSeek,
    )
    .await;
    assert_eq!(
        observed[0].binding.transport,
        ModelTransportProfile::responses_http()
    );
    let server =
        Server::json(json!({"models":[{"slug":model.model_id,"binding":model.binding}]})).await;
    let query =
        ModelCatalogQuery::for_account(&provider(&server.url, ProtocolKind::DeepSeek)).unwrap();
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
            ModelCatalogQuery::for_account(&provider(&server.url, ProtocolKind::OpenAi)).unwrap();
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
        let query =
            ModelCatalogQuery::for_account(&provider(&url, ProtocolKind::DeepSeek)).unwrap();
        let cache = ModelCatalogQueryCache {
            identity: query.identity().into(),
            etag: None,
            models: vec![cached_model("last-good", ProtocolKind::DeepSeek)],
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
        assert_eq!(retained_cache.models[0].model_id, "last-good");
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
        schema_version: 2,
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
        default: None,
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
