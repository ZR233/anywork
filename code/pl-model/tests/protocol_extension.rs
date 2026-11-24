use pl_model::{
    completion::{CompletionRequest, Message, MessageContent, MessageRole, SystemPrompt},
    config::{AccountConfig, ModelCatalogId},
    model::{ModelDefinition, ModelRequestProfile},
    protocol::{
        ApiKeyHeaderScheme, InstructionWireRole, ProtocolEndpoint, ProtocolId, ProtocolRegistry,
        discovery::{ModelCatalogQuery, ModelCatalogQueryResult},
    },
    runtime::{ModelInvocationContext, new_with_registry},
};
use pl_model_wire::{
    adapter::Adapter,
    discovery::{DiscoveryPolicy, ModelCatalogQueryError, ParsedCatalogPage, Record},
};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
use serde_json::{Value, json};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

static EXTENSION: Adapter = Adapter {
    id: ProtocolId::from_static("fixture_openai_derivative"),
    codec: &pl_model_openai_wire::OPENAI_WIRE_CODEC,
    api_key_header: ApiKeyHeaderScheme::AuthorizationBearer,
    responses_instruction_role: InstructionWireRole::System,
    discovery: DiscoveryPolicy::COMPATIBLE,
    discovery_query_params: &[],
    discovery_page_token_param: None,
    file_upload: None,
    hosted_search_label: None,
    on_base_url_override: None,
    prepare_request: Some(|_, profile: &mut ModelRequestProfile| {
        profile
            .body
            .insert("fixture_option".into(), json!("variant"));
    }),
    parse_catalog_page: |bytes| {
        let body: Value =
            serde_json::from_slice(bytes).map_err(|_| ModelCatalogQueryError::Protocol)?;
        let slug = body
            .get("fixtureSlug")
            .and_then(Value::as_str)
            .ok_or(ModelCatalogQueryError::Protocol)?;
        Ok(ParsedCatalogPage {
            records: vec![Record {
                id: slug.into(),
                ..Record::default()
            }],
            next_page_token: None,
        })
    },
};

#[tokio::test]
async fn a_registered_derivative_owns_its_catalog_and_request_policy() {
    let adapters = [&EXTENSION];
    let registry = ProtocolRegistry::new(&adapters).unwrap();
    let catalog = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}/v1", catalog.local_addr().unwrap());
    let server = tokio::spawn(async move {
        let (mut socket, _) = catalog.accept().await.unwrap();
        let mut request = Vec::new();
        while !request.ends_with(b"\r\n\r\n") {
            request.push(socket.read_u8().await.unwrap());
            assert!(request.len() < 4096);
        }
        assert!(request.starts_with(b"GET /v1/models?client_version=0.170.0 HTTP/1.1\r\n"));
        let body = r#"{"fixtureSlug":"fixture-model"}"#;
        socket.write_all(format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()
        ).as_bytes()).await.unwrap();
    });

    let endpoint = ProtocolEndpoint::new(EXTENSION.id.clone(), "Derived", base);
    let mut account =
        AccountConfig::from_bundled_catalog(endpoint, ModelCatalogId::new("xai").unwrap(), vec![]);
    let query = ModelCatalogQuery::for_account_with_registry(&account, registry).unwrap();
    let ModelCatalogQueryResult::Updated { models, .. } = query.execute(None).await.unwrap() else {
        panic!("expected a fresh catalog");
    };
    account.set_model_catalog_overlay(models).unwrap();
    server.await.unwrap();

    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "fixture prompt",
        0,
        Reply::Sse(responses_text(
            "provider result",
            "fixture-attempt",
            "fixture-model",
        )),
    )])
    .await
    .unwrap();
    let model = account
        .effective_catalog_with_registry(None, registry)
        .unwrap()
        .into_iter()
        .find(|entry| entry.model.base.slug == "fixture-model")
        .expect("discovered model must be usable")
        .model;
    let mut endpoint = account.to_endpoint_with_registry(registry).unwrap();
    endpoint.base_url = fixture.base_url();
    let runtime = new_with_registry("fixture", endpoint, model, registry).unwrap();
    let request = CompletionRequest::builder()
        .system_prompt(SystemPrompt::new("trusted instruction"))
        .messages(vec![Message {
            role: MessageRole::User,
            content: MessageContent::text("fixture prompt"),
            presentation: Default::default(),
            reasoning_content: None,
            tool_calls: None,
            tool_result: None,
            metadata: Default::default(),
        }])
        .build();
    let response = runtime
        .complete(request, ModelInvocationContext::default())
        .await
        .unwrap();
    assert_eq!(response.content.as_deref(), Some("provider result"));
    let records = fixture.finish().await.unwrap();
    assert_eq!(records[0].body["input"][0]["role"], "system");
    assert_eq!(records[0].body["fixture_option"], "variant");
}

#[test]
fn protocol_config_preserves_unknown_ids_until_assembly() {
    let endpoint = ProtocolEndpoint::new(
        EXTENSION.id.clone(),
        "Unregistered",
        "https://fixture.invalid",
    );
    let original =
        AccountConfig::from_explicit_models(endpoint, vec![ModelDefinition::compatible("fixture")]);
    let account: AccountConfig =
        serde_json::from_value(serde_json::to_value(&original).unwrap()).unwrap();
    assert_eq!(account.protocol.as_str(), "fixture_openai_derivative");
    assert!(
        account
            .to_endpoint()
            .unwrap_err()
            .to_string()
            .contains("unregistered model protocol")
    );
    assert!(ProtocolRegistry::new(&[&EXTENSION, &EXTENSION]).is_err());
}

#[test]
fn responses_native_context_keeps_its_persisted_shape() {
    use pl_model::completion::ModelContextItem;

    let old = json!({"type":"responses","item":{
        "kind":"reasoning",
        "value":{"type":"reasoning","id":"fixture","encrypted_content":"unchanged"}
    }});
    let item: ModelContextItem = serde_json::from_value(old.clone()).unwrap();
    assert_eq!(serde_json::to_value(item).unwrap(), old);
}

#[test]
fn hosted_search_retains_both_storage_and_descriptor_labels() {
    use pl_model::{
        config::account_service_capabilities_descriptor,
        protocol::{ProtocolServiceCapabilities, providers::deepseek},
    };

    let mut capabilities = ProtocolServiceCapabilities::default();
    capabilities.web_search.hosted_dialect = deepseek::HOSTED_SEARCH_DIALECT;
    let encoded = serde_json::to_value(&capabilities).unwrap();
    assert_eq!(
        encoded["web_search"]["hosted_dialect"],
        "deep_seek_responses"
    );
    let decoded: ProtocolServiceCapabilities = serde_json::from_value(encoded).unwrap();
    let descriptor = account_service_capabilities_descriptor(&decoded);
    assert_eq!(descriptor.web_search.hosted_dialect, "deepseek_responses");
}
