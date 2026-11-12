use pl_model::{
    completion::{CompletionRequest, CompletionTraceContext, Message, MessageContent, MessageRole},
    config::{AccountId, AgentRoleId, ResolvedModelRoute},
    model::{ModelInfo, ModelTransportProfile},
    protocol::{PromptCacheDialect, ProtocolEndpoint},
    runtime::{
        ModelInvocationContext, ModelRuntime, ModelSession, ModelTurnClient, ModelTurnOptions,
        ModelTurnRequest, PromptCacheScope,
    },
};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};

fn request() -> CompletionRequest {
    CompletionRequest::builder()
        .messages(vec![Message {
            role: MessageRole::User,
            content: MessageContent::text("cache scope"),
            presentation: Default::default(),
            reasoning_content: None,
            tool_calls: None,
            tool_result: None,
            metadata: Default::default(),
        }])
        .build()
}

#[test]
fn persisted_route_identity_is_unchanged_by_the_wire_key_format() {
    let binding = pl_model::runtime::ModelCallBinding {
        account_id: "account-a".into(),
        model_id: "model-a".into(),
        protocol: pl_model::protocol::ProtocolKind::OpenAiCompatible,
        wire_api: pl_model::protocol::WireApi::Responses,
        isolation: "binding-fixture".into(),
        purpose: "turn".into(),
        context_window: None,
        max_context_window: None,
        auto_compact_limit: None,
    };
    // Frozen before this refactor: history provenance must retain its exact persisted value.
    assert_eq!(
        binding.route_identity(),
        "pl:dcb4f9186d00ef89833781d7c25807d687d54874d1dcfdb93ca8e44fe2f5d408"
    );
}

#[tokio::test]
async fn cache_scopes_isolate_agents_accounts_models_and_auxiliary_work_on_the_wire() {
    let cases = [
        (
            "account-a",
            "model-a",
            "root-a",
            None,
            false,
            PromptCacheDialect::OpenAiPromptCacheKey,
        ),
        (
            "account-a",
            "model-a",
            "root-a",
            None,
            true,
            PromptCacheDialect::OpenAiPromptCacheKey,
        ),
        (
            "account-a",
            "model-a",
            "child-a",
            None,
            false,
            PromptCacheDialect::OpenAiPromptCacheKey,
        ),
        (
            "account-a",
            "model-a",
            "child-b",
            None,
            false,
            PromptCacheDialect::OpenAiPromptCacheKey,
        ),
        (
            "account-a",
            "model-a",
            "root-b",
            None,
            false,
            PromptCacheDialect::OpenAiPromptCacheKey,
        ),
        (
            "account-b",
            "model-a",
            "root-a",
            None,
            false,
            PromptCacheDialect::OpenAiPromptCacheKey,
        ),
        (
            "account-a",
            "model-b",
            "root-a",
            None,
            false,
            PromptCacheDialect::OpenAiPromptCacheKey,
        ),
        (
            "account-a",
            "model-a",
            "root-a",
            Some("title"),
            false,
            PromptCacheDialect::OpenAiPromptCacheKey,
        ),
        (
            "account-a",
            "model-a",
            "root-a",
            Some("tool-review"),
            false,
            PromptCacheDialect::OpenAiPromptCacheKey,
        ),
        (
            "account-a",
            "model-a",
            "root-a",
            Some("title"),
            true,
            PromptCacheDialect::OpenAiPromptCacheKey,
        ),
        (
            "account-a",
            "model-a",
            "root-a",
            None,
            false,
            PromptCacheDialect::None,
        ),
        (
            "account-a",
            "model-a",
            "root-a",
            None,
            true,
            PromptCacheDialect::ImplicitPrefix,
        ),
    ];
    let fixture = FixtureServer::start(
        cases
            .iter()
            .enumerate()
            .map(|(index, case)| {
                Step::prompt(
                    if case.4 {
                        Protocol::ResponsesWebSocket
                    } else {
                        Protocol::ResponsesHttp
                    },
                    "cache scope",
                    index,
                    if case.4 {
                        Reply::WebSocket(responses_text(
                            "done",
                            &format!("response-{index}"),
                            case.1,
                        ))
                    } else {
                        Reply::Sse(responses_text("done", &format!("response-{index}"), case.1))
                    },
                )
            })
            .collect(),
    )
    .await
    .unwrap();
    for (index, (account, model, thread, purpose, websocket, dialect)) in
        cases.into_iter().enumerate()
    {
        let mut endpoint =
            ProtocolEndpoint::compatible(format!("display-{index}"), fixture.base_url());
        endpoint.service_capabilities.prompt_cache.dialect = dialect;
        let mut info = ModelInfo::compatible(model);
        info.binding.set_transport(if websocket {
            ModelTransportProfile::responses_websocket()
        } else {
            ModelTransportProfile::responses_http()
        });
        let route = ResolvedModelRoute {
            account_id: AccountId::new(account).unwrap(),
            role: AgentRoleId::new("cache-test").unwrap(),
            context: info.resolve_context(None),
            model: info,
            endpoint,
            pricing_mode: pl_protocol::PricingMode::NoCharge,
            effort: None,
        };
        let runtime = ModelRuntime::from_route(&route).unwrap();
        let scope = purpose.map_or_else(
            || PromptCacheScope::thread(thread),
            |purpose| PromptCacheScope::auxiliary(thread, purpose),
        );
        let physical = ModelSession::default();
        let trace = CompletionTraceContext {
            session_id: thread.into(),
            turn_id: format!("turn-{index}"),
            inference_id: format!("attempt-{index}"),
        };
        let text = if purpose.is_some() {
            ModelTurnClient::from_route(&route)
                .unwrap()
                .complete_text(
                    &request().input,
                    ModelTurnRequest::new(),
                    ModelTurnOptions::default()
                        .with_session(physical.clone())
                        .with_prompt_cache_scope(scope)
                        .with_trace_metadata(trace),
                )
                .await
                .unwrap()
        } else {
            let invocation = ModelInvocationContext::new(physical.clone())
                .with_prompt_cache_scope(scope)
                .with_trace_metadata(trace);
            runtime
                .complete(request(), invocation)
                .await
                .unwrap_or_else(|error| {
                    panic!("case {index}: {error}; requests: {:?}", fixture.recorded())
                })
                .content
                .unwrap()
        };
        physical.close().await.unwrap();
        assert_eq!(text, "done");
    }
    let records = fixture.finish().await.unwrap();
    let keys = records
        .iter()
        .map(|r| r.body.get("prompt_cache_key").and_then(|v| v.as_str()))
        .collect::<Vec<_>>();
    assert!(keys[..10].iter().all(|key| key.is_some()));
    assert!(keys[..10].iter().all(|key| key.unwrap().len() == 64));
    assert_eq!(
        keys[0], keys[1],
        "transport, trace IDs and display names do not rotate affinity"
    );
    assert_eq!(
        keys[7], keys[9],
        "auxiliary scopes also survive transport changes"
    );
    let distinct = [0, 2, 3, 4, 5, 6, 7, 8]
        .map(|i| keys[i].unwrap())
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(distinct.len(), 8);
    assert!(
        keys[10..].iter().all(|key| key.is_none()),
        "unsupported and implicit endpoints omit the hint"
    );
}
