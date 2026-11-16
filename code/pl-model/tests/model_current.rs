//! Current factory integration: the real provider accumulator, not a DTO-only capture stub.
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSnapshot, OpaquePayload},
    model::{ModelFactory, ModelFailureKind, ModelRequest, ModelToolDeclaration, ToolCallMode},
    thread::current::RuntimeEpoch,
};
use pl_model::{
    completion::{
        ModelStreamCurrent, ModelStreamCurrentState, ReasoningConfig, ReasoningSummary, ToolSpec,
    },
    model::{ModelInfo, ModelProtocolOptions, ModelTransportProfile, ResponsesMaxTokensField},
    protocol::{ProtocolEndpoint, ProtocolKind, WireApi},
    runtime::{
        CancellationToken, HostedTool, HostedWebSearchOptions, ModelRuntime, ThreadModel,
        model_request_receipt, thread_tool_declaration,
    },
};
use pl_provider_fixture::{
    FixtureServer, Protocol, RealtimeToolCall, Reply, Step, responses_text, responses_tool_calls,
};
use serde_json::json;
use std::{sync::Arc, time::Duration};

fn request(attempt_id: &str, cancellation: CancellationToken) -> ModelRequest {
    ModelRequest {
        thread_id: "current-thread".into(),
        turn_id: "current-turn".into(),
        attempt_id: attempt_id.into(),
        context: ContextSnapshot {
            revision: 0,
            records: vec![ContextRecord {
                id: "input".into(),
                turn_id: Some("current-turn".into()),
                source: pl_core::context::ContextSource::User,
                content: vec![ContextContent::Text {
                    text: "current capture".into(),
                }],
                tool_calls: Vec::new(),
            }]
            .into(),
        },
        tools: Arc::from([]),
        tool_call_mode: ToolCallMode::Parallel,
        solo_tool_ids: Arc::from([]),
        recovery_parameters: None,
        committed_private_context: None,
        resources: None,
        cancellation,
        progress: None,
        members: None,
    }
}

fn factory(fixture: &FixtureServer) -> ModelFactory {
    endpoint_factory(fixture.base_url())
}

fn endpoint_factory(base_url: impl Into<String>) -> ModelFactory {
    let mut model = ModelInfo::compatible("current-model");
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    ModelFactory::new(ThreadModel::new_current(
        ModelRuntime::new_with_account_id(
            "fixture",
            ProtocolEndpoint::compatible("fixture", base_url),
            model,
        )
        .unwrap(),
        None,
    ))
}

fn recovery_info(transport: ModelTransportProfile) -> ModelInfo {
    let mut info = ModelInfo::compatible("current-model");
    info.binding.set_transport(transport);
    let effort_path = match &mut info.binding.request.protocol {
        ModelProtocolOptions::Responses(options) => {
            options.max_tokens_field = ResponsesMaxTokensField::MaxOutputTokens;
            "reasoning.effort"
        }
        ModelProtocolOptions::ChatCompletions(options) => {
            options.parallel_tool_calls = true;
            "reasoning_effort"
        }
    };
    if matches!(
        info.binding.request.protocol,
        ModelProtocolOptions::ChatCompletions(_)
    ) {
        info.binding
            .request
            .body
            .insert("store".into(), json!(false));
    }
    info.parameters = vec![
        serde_json::from_value(json!({
            "name":"effort", "candidates":["low","high"],
            "wire":{
                "low":{"set":[{"path":effort_path,"value":"low"}]},
                "high":{"set":[{"path":effort_path,"value":"high"}]}
            }
        }))
        .unwrap(),
    ];
    info.capabilities.reasoning = true;
    info.capabilities.web_search = true;
    info.capabilities.tools.parallel_tool_calls = true;
    info.max_output_tokens = Some(700);
    info
}

fn search(external_web_access: bool) -> HostedTool {
    HostedTool::WebSearch(HostedWebSearchOptions::OpenAi {
        external_web_access,
        indexed_web_access: None,
        filters: None,
        user_location: None,
        search_context_size: None,
        search_content_types: None,
    })
}

fn recovery_factory(
    fixture: &FixtureServer,
    info: ModelInfo,
    reasoning: Option<ReasoningConfig>,
    hosted: Vec<HostedTool>,
) -> ModelFactory {
    recovery_factory_with_endpoint(
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        info,
        reasoning,
        hosted,
    )
}

fn recovery_factory_with_endpoint(
    mut endpoint: ProtocolEndpoint,
    info: ModelInfo,
    reasoning: Option<ReasoningConfig>,
    hosted: Vec<HostedTool>,
) -> ModelFactory {
    endpoint.service_capabilities.web_search.hosted_responses = true;
    endpoint
        .service_capabilities
        .responses_tools
        .programmatic_tool_calling = info.binding.request.supports_programmatic_tool_calling();
    ModelFactory::new(
        ThreadModel::new_current(
            ModelRuntime::new_with_account_id("fixture", endpoint, info).unwrap(),
            reasoning,
        )
        .with_hosted_tools(hosted),
    )
}

fn local_tool(name: &str) -> ModelToolDeclaration {
    ModelToolDeclaration {
        tool_id: format!("core-{name}"),
        declaration: thread_tool_declaration(&ToolSpec::Custom {
            name: name.into(),
            description: "registered text tool".into(),
            format: pl_protocol::ToolFormat::Text,
            allowed_callers: vec![
                pl_protocol::ToolCallerMode::Direct,
                pl_protocol::ToolCallerMode::Programmatic,
            ],
            output_schema: Some(json!({"type":"string"})),
        })
        .unwrap(),
        presentation_contract: None,
    }
}

fn confirmed_request(attempt: &str, text: &str) -> ModelRequest {
    let mut request = request(attempt, CancellationToken::new());
    Arc::make_mut(&mut request.context.records)[0].content =
        vec![ContextContent::Text { text: text.into() }];
    request
}

async fn saved_parameters(
    factory: &ModelFactory,
    tools: Vec<ModelToolDeclaration>,
) -> OpaquePayload {
    let mut session = factory.open_session().await.unwrap();
    let mut source = request("saved-source", CancellationToken::new());
    source.tools = tools.into();
    let prepared = session.prepare(source).await.unwrap();
    let parameters = prepared.request_metadata().unwrap().clone();
    drop(prepared);
    session.close().await.unwrap();
    parameters
}

fn edit_parameters(
    parameters: &OpaquePayload,
    edit: impl FnOnce(&mut serde_json::Value),
) -> OpaquePayload {
    let mut value = serde_json::from_str(parameters.content()).unwrap();
    edit(&mut value);
    OpaquePayload::new(parameters.format(), parameters.version(), value.to_string()).unwrap()
}

#[tokio::test]
async fn recovery_does_not_infer_compatible_chat_parallel_or_storage_defaults() {
    let fixture = FixtureServer::start(Vec::new()).await.unwrap();
    let info = recovery_info(ModelTransportProfile::chat_completions_http());
    let source = recovery_factory(&fixture, info.clone(), None, Vec::new());
    let parameters = saved_parameters(&source, vec![local_tool("saved_tool")]).await;
    let mut unknown_parallel = info.clone();
    if let ModelProtocolOptions::ChatCompletions(options) =
        &mut unknown_parallel.binding.request.protocol
    {
        options.parallel_tool_calls = false;
    }
    let mut unknown_store = info.clone();
    unknown_store.binding.request.body.remove("store");
    let mut null_store = info;
    null_store
        .binding
        .request
        .body
        .insert("store".into(), json!(null));
    for (case, current, reason) in [
        ("unknown parallel", unknown_parallel, "parallel"),
        ("unknown store", unknown_store, "storage"),
        ("null store", null_store, "storage"),
    ] {
        let mut session = recovery_factory(&fixture, current, None, Vec::new())
            .open_session()
            .await
            .unwrap();
        let mut resumed = confirmed_request(case, case);
        resumed.tools = vec![local_tool("saved_tool")].into();
        resumed.recovery_parameters = Some(parameters.clone());
        let error = match session.prepare(resumed).await {
            Err(error) => error,
            Ok(_) => panic!("unproved provider default admitted: {case}"),
        };
        assert_eq!(error.kind, ModelFailureKind::IncompatibleContext);
        assert!(error.to_string().contains(reason), "{case}: {error}");
        session.close().await.unwrap();
    }
    assert!(fixture.finish().await.unwrap().is_empty());
}

#[tokio::test]
async fn recovery_omit_limit_checks_final_output_tokens_not_an_intermediate_body() {
    let fixture = FixtureServer::start(vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            "fixed cap",
            0,
            Reply::Sse(responses_text("done", "fixed", "current-model")),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            "parameter cap",
            1,
            Reply::Sse(responses_text("done", "parameter", "current-model")),
        ),
    ])
    .await
    .unwrap();
    let mut info = recovery_info(ModelTransportProfile::responses_http());
    info.max_output_tokens = Some(500);
    let reasoning = Some(ReasoningConfig {
        effort: Some("high".into()),
        summary: None,
    });
    let source = recovery_factory(&fixture, info.clone(), reasoning.clone(), Vec::new());
    let parameters = saved_parameters(&source, Vec::new()).await;
    assert_eq!(
        model_request_receipt(&parameters).unwrap().max_tokens,
        Some(500)
    );
    if let ModelProtocolOptions::Responses(options) = &mut info.binding.request.protocol {
        options.max_tokens_field = ResponsesMaxTokensField::Omit;
    }
    for overlay in [
        json!({}),
        json!({"max_output_tokens":499}),
        json!({"max_tokens":500}),
        json!({"max_completion_tokens":500}),
        json!({"max_tool_calls":500}),
        json!({"max_output_tokens":500,"max_tokens":500}),
    ] {
        let mut current = info.clone();
        current.binding.request.body = serde_json::from_value(overlay.clone()).unwrap();
        let mut session = recovery_factory(&fixture, current, reasoning.clone(), Vec::new())
            .open_session()
            .await
            .unwrap();
        let mut resumed = confirmed_request("invalid cap", "invalid cap");
        resumed.recovery_parameters = Some(parameters.clone());
        let error = match session.prepare(resumed).await {
            Err(error) => error,
            Ok(_) => panic!("unconfirmed output-token cap admitted: {overlay}"),
        };
        assert_eq!(error.kind, ModelFailureKind::IncompatibleContext);
        session.close().await.unwrap();
    }
    assert!(fixture.recorded().is_empty());
    for (text, from_parameter) in [("fixed cap", false), ("parameter cap", true)] {
        let mut current = info.clone();
        if from_parameter {
            current.parameters[0]
                .wire
                .get_mut("high")
                .unwrap()
                .set
                .push(pl_model::model::WireAssignment {
                    path: "max_output_tokens".into(),
                    value: json!(500),
                });
        } else {
            current
                .binding
                .request
                .body
                .insert("max_output_tokens".into(), json!(500));
        }
        let mut session = recovery_factory(&fixture, current, reasoning.clone(), Vec::new())
            .open_session()
            .await
            .unwrap();
        let mut resumed = confirmed_request(text, text);
        resumed.recovery_parameters = Some(parameters.clone());
        session
            .prepare(resumed)
            .await
            .unwrap()
            .execute()
            .await
            .unwrap();
        session.close().await.unwrap();
    }
    let recorded = fixture.finish().await.unwrap();
    assert_eq!(recorded.len(), 2);
    for request in recorded {
        assert_eq!(request.body["max_output_tokens"], 500);
        assert!(request.body.get("max_tokens").is_none());
        assert!(request.body.get("max_completion_tokens").is_none());
    }
}

#[tokio::test]
async fn recovery_rejects_remote_history_and_storage_but_allows_neutral_responses_overlays() {
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "neutral overlay",
        0,
        Reply::Sse(responses_text("done", "neutral", "current-model")),
    )])
    .await
    .unwrap();
    let info = recovery_info(ModelTransportProfile::responses_http());
    let source = recovery_factory(&fixture, info.clone(), None, Vec::new());
    let parameters = saved_parameters(&source, Vec::new()).await;
    for overlay in [
        json!({"conversation":"server-history"}),
        json!({"conversation":{"id":"server-history"}}),
        json!({"previous_response_id":"old-response"}),
        json!({"prompt":{"id":"old-template"}}),
        json!({"store":true}),
        json!({"store":null}),
        json!({"background":true}),
    ] {
        let mut current = info.clone();
        current.binding.request.body = serde_json::from_value(overlay.clone()).unwrap();
        let mut session = recovery_factory(&fixture, current, None, Vec::new())
            .open_session()
            .await
            .unwrap();
        let mut resumed = confirmed_request("unsafe-response-overlay", "unsafe overlay");
        resumed.recovery_parameters = Some(parameters.clone());
        let error = match session.prepare(resumed).await {
            Err(error) => error,
            Ok(_) => panic!("admitted {overlay}"),
        };
        assert_eq!(
            error.kind,
            ModelFailureKind::IncompatibleContext,
            "{overlay}: {error}"
        );
        session.close().await.unwrap();
    }
    assert!(fixture.recorded().is_empty());
    let mut current = info;
    current.binding.request.body = serde_json::from_value(json!({
        "conversation":null,"previous_response_id":null,"prompt":null,
        "store":false,"background":false,"metadata":{"conversation":"annotation only"}
    }))
    .unwrap();
    let mut session = recovery_factory(&fixture, current, None, Vec::new())
        .open_session()
        .await
        .unwrap();
    let mut resumed = confirmed_request("neutral-response-overlay", "neutral overlay");
    resumed.recovery_parameters = Some(parameters);
    session
        .prepare(resumed)
        .await
        .unwrap()
        .execute()
        .await
        .unwrap();
    session.close().await.unwrap();
    let recorded = fixture.finish().await.unwrap();
    assert_eq!(recorded.len(), 1);
    assert_eq!(recorded[0].body["store"], false);
    assert!(recorded[0].body["conversation"].is_null());
    assert_eq!(
        recorded[0].body["metadata"]["conversation"],
        "annotation only"
    );
}

#[tokio::test]
async fn recovery_chat_preserves_false_parallel_only_when_tools_can_run() {
    let reply = || {
        Reply::Sse(vec![json!({"id":"serial","model":"current-model",
        "choices":[{"index":0,"delta":{"role":"assistant","content":"done"},"finish_reason":"stop"}],
        "usage":{"prompt_tokens":3,"completion_tokens":1}})])
    };
    let fixture = FixtureServer::start(vec![
        Step::prompt(Protocol::Chat, "serial restored", 0, reply()),
        Step::prompt(Protocol::Chat, "no tools", 1, reply()),
        Step::prompt(Protocol::Chat, "disabled tools", 2, reply()),
    ])
    .await
    .unwrap();
    let info = recovery_info(ModelTransportProfile::chat_completions_http());
    let source = recovery_factory(&fixture, info.clone(), None, Vec::new());
    let mut session = source.open_session().await.unwrap();
    let mut original = request("serial-source", CancellationToken::new());
    original.tool_call_mode = ToolCallMode::Sequential;
    original.tools = vec![local_tool("saved_tool")].into();
    let prepared = session.prepare(original).await.unwrap();
    let parameters = prepared.request_metadata().unwrap().clone();
    assert!(
        !model_request_receipt(&parameters)
            .unwrap()
            .parallel_tool_calls
    );
    drop(prepared);
    session.close().await.unwrap();
    let mut no_field = info.clone();
    if let ModelProtocolOptions::ChatCompletions(options) = &mut no_field.binding.request.protocol {
        options.parallel_tool_calls = false;
    }
    let mut stored = info.clone();
    stored
        .binding
        .request
        .body
        .insert("store".into(), json!(true));
    for current in [no_field.clone(), stored] {
        let mut session = recovery_factory(&fixture, current, None, Vec::new())
            .open_session()
            .await
            .unwrap();
        let mut resumed = confirmed_request("invalid-serial", "invalid serial");
        resumed.tools = vec![local_tool("saved_tool")].into();
        resumed.recovery_parameters = Some(parameters.clone());
        let error = match session.prepare(resumed).await {
            Err(error) => error,
            Ok(_) => panic!("unsafe Chat request admitted"),
        };
        assert_eq!(error.kind, ModelFailureKind::IncompatibleContext);
        session.close().await.unwrap();
    }
    assert!(fixture.recorded().is_empty());
    for (text, mut current, parameters, tools) in [
        (
            "serial restored",
            info,
            parameters.clone(),
            vec![local_tool("saved_tool")],
        ),
        (
            "no tools",
            no_field.clone(),
            edit_parameters(&parameters, |value| value["tools"] = json!([])),
            Vec::new(),
        ),
        (
            "disabled tools",
            no_field,
            edit_parameters(&parameters, |value| value["toolChoice"] = json!("none")),
            vec![local_tool("saved_tool")],
        ),
    ] {
        // This compatible fixture explicitly requests no storage; it proves wire intent,
        // not an account-independent storage default for arbitrary compatible services.
        current
            .binding
            .request
            .body
            .insert("store".into(), json!(false));
        let mut session = recovery_factory(&fixture, current, None, Vec::new())
            .open_session()
            .await
            .unwrap();
        let mut resumed = confirmed_request(text, text);
        resumed.tools = tools.into();
        resumed.recovery_parameters = Some(parameters);
        session
            .prepare(resumed)
            .await
            .unwrap()
            .execute()
            .await
            .unwrap();
        session.close().await.unwrap();
    }
    let recorded = fixture.finish().await.unwrap();
    assert_eq!(recorded.len(), 3);
    assert_eq!(recorded[0].body["parallel_tool_calls"], false);
    assert!(recorded[1].body.get("parallel_tool_calls").is_none());
    assert!(recorded[2].body.get("parallel_tool_calls").is_none());
    assert_eq!(recorded[2].body["tool_choice"], "none");
}

#[tokio::test]
async fn recovery_effort_wire_accepts_equal_values_and_rejects_actual_changes() {
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "equal wire",
        0,
        Reply::Sse(responses_text("done", "equal", "current-model")),
    )])
    .await
    .unwrap();
    let info = recovery_info(ModelTransportProfile::responses_http());
    let reasoning = Some(ReasoningConfig {
        effort: Some("high".into()),
        summary: None,
    });
    let source = recovery_factory(&fixture, info.clone(), reasoning.clone(), Vec::new());
    let parameters = edit_parameters(&saved_parameters(&source, Vec::new()).await, |value| {
        value["temperature"] = json!(0.25)
    });
    for (field, value) in [("stream", json!(false)), ("temperature", json!(0.9))] {
        let mut current = info.clone();
        current.parameters[0]
            .wire
            .get_mut("high")
            .unwrap()
            .set
            .push(pl_model::model::WireAssignment {
                path: field.into(),
                value,
            });
        let mut session = recovery_factory(&fixture, current, reasoning.clone(), Vec::new())
            .open_session()
            .await
            .unwrap();
        let mut resumed = confirmed_request(field, "changed wire");
        resumed.recovery_parameters = Some(parameters.clone());
        let error = match session.prepare(resumed).await {
            Err(error) => error,
            Ok(_) => panic!("changed {field} admitted"),
        };
        assert_eq!(error.kind, ModelFailureKind::IncompatibleContext);
        session.close().await.unwrap();
    }
    assert!(fixture.recorded().is_empty());
    let mut current = info;
    // Temporary writes are not side effects: only the final actual request can change behavior.
    current
        .binding
        .request
        .body
        .insert("store".into(), json!(true));
    let wire = current.parameters[0].wire.get_mut("high").unwrap();
    for (field, value) in [
        ("stream", json!(false)),
        ("stream", json!(true)),
        ("temperature", json!(0.25)),
        ("store", json!(false)),
    ] {
        wire.set.push(pl_model::model::WireAssignment {
            path: field.into(),
            value,
        });
    }
    let mut session = recovery_factory(&fixture, current, reasoning, Vec::new())
        .open_session()
        .await
        .unwrap();
    let mut resumed = confirmed_request("equal-wire", "equal wire");
    resumed.recovery_parameters = Some(parameters);
    session
        .prepare(resumed)
        .await
        .unwrap()
        .execute()
        .await
        .unwrap();
    session.close().await.unwrap();
    let recorded = fixture.finish().await.unwrap();
    assert_eq!(recorded.len(), 1);
    assert_eq!(recorded[0].body["stream"], true);
    assert_eq!(recorded[0].body["temperature"], 0.25);
    assert_eq!(recorded[0].body["store"], false);
}

#[tokio::test]
async fn recovery_requires_the_saved_final_sent_model_not_the_current_alias() {
    let fixture = FixtureServer::start(vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            "same physical",
            0,
            Reply::Sse(responses_text("done", "same", "physical-a")),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            "effective same",
            1,
            Reply::Sse(responses_text("done", "effective", "physical-a")),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            "native config same",
            2,
            Reply::Sse(responses_text("done", "native", "physical-c")),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            "new preparing",
            3,
            Reply::Sse(responses_text("done", "new", "physical-b")),
        ),
    ])
    .await
    .unwrap();
    let mut info = recovery_info(ModelTransportProfile::responses_http());
    info.binding.request.api_model = Some("physical-a".into());
    let source = recovery_factory(&fixture, info.clone(), None, Vec::new());
    let parameters = saved_parameters(&source, Vec::new()).await;
    assert_eq!(
        model_request_receipt(&parameters)
            .unwrap()
            .sent_model
            .as_deref(),
        Some("physical-a")
    );
    let unknown = edit_parameters(&parameters, |value| {
        value.as_object_mut().unwrap().remove("sentModel");
    });
    assert!(
        model_request_receipt(&unknown)
            .unwrap()
            .sent_model
            .is_none(),
        "old receipts remain readable as unknown"
    );
    let mut remapped = info.clone();
    remapped.binding.request.api_model = Some("physical-b".into());
    let mut changed_native = info.clone();
    changed_native
        .binding
        .request
        .body
        .insert("model".into(), json!("physical-c"));
    for (case, current, parameters) in [
        ("api alias changed", remapped.clone(), parameters.clone()),
        (
            "effective native model changed",
            changed_native.clone(),
            parameters.clone(),
        ),
        ("missing sentModel", info.clone(), unknown),
        (
            "unproved sentModel",
            info.clone(),
            edit_parameters(&parameters, |value| value["sentModel"] = json!("unproved")),
        ),
    ] {
        let mut session = recovery_factory(&fixture, current, None, Vec::new())
            .open_session()
            .await
            .unwrap();
        let mut resumed = confirmed_request(case, case);
        resumed.recovery_parameters = Some(parameters);
        let error = match session.prepare(resumed).await {
            Err(error) => error,
            Ok(_) => panic!("admitted {case}"),
        };
        assert_eq!(
            error.kind,
            ModelFailureKind::IncompatibleContext,
            "{case}: {error}"
        );
        if case == "missing sentModel" {
            assert!(
                error.to_string().contains("sentModel"),
                "unknown origin must be explained"
            );
        }
        session.close().await.unwrap();
    }
    assert!(
        fixture.recorded().is_empty(),
        "all incompatible preparations must precede network IO"
    );
    let mut session = source.open_session().await.unwrap();
    let mut resumed = confirmed_request("same-physical", "same physical");
    resumed.recovery_parameters = Some(parameters.clone());
    let prepared = session.prepare(resumed).await.unwrap();
    assert_eq!(
        model_request_receipt(prepared.request_metadata().unwrap())
            .unwrap()
            .sent_model
            .as_deref(),
        Some("physical-a")
    );
    prepared.execute().await.unwrap();
    session.close().await.unwrap();
    // Compare final wire models, not raw aliases: the overlay keeps A despite an alias change.
    let mut effective_same = remapped.clone();
    effective_same
        .binding
        .request
        .body
        .insert("model".into(), json!("physical-a"));
    let mut session = recovery_factory(&fixture, effective_same, None, Vec::new())
        .open_session()
        .await
        .unwrap();
    let mut resumed = confirmed_request("effective-same", "effective same");
    resumed.recovery_parameters = Some(parameters);
    session
        .prepare(resumed)
        .await
        .unwrap()
        .execute()
        .await
        .unwrap();
    session.close().await.unwrap();
    // A current producer captures the overlay model C, not the intermediate api_model alias A.
    let native_source = recovery_factory(&fixture, changed_native.clone(), None, Vec::new());
    let native_parameters = saved_parameters(&native_source, Vec::new()).await;
    assert_eq!(
        model_request_receipt(&native_parameters)
            .unwrap()
            .sent_model
            .as_deref(),
        Some("physical-c")
    );
    changed_native.binding.request.api_model = Some("physical-b".into());
    let mut session = recovery_factory(&fixture, changed_native, None, Vec::new())
        .open_session()
        .await
        .unwrap();
    let mut resumed = confirmed_request("native-same", "native config same");
    resumed.recovery_parameters = Some(native_parameters);
    session
        .prepare(resumed)
        .await
        .unwrap()
        .execute()
        .await
        .unwrap();
    session.close().await.unwrap();
    // Preparing without a frozen receipt is a fresh call, even after the alias changes.
    let mut session = recovery_factory(&fixture, remapped.clone(), None, Vec::new())
        .open_session()
        .await
        .unwrap();
    let fresh = session
        .prepare(confirmed_request("new-preparing", "new preparing"))
        .await
        .unwrap();
    assert_eq!(
        model_request_receipt(fresh.request_metadata().unwrap())
            .unwrap()
            .sent_model
            .as_deref(),
        Some("physical-b")
    );
    fresh.execute().await.unwrap();
    session.close().await.unwrap();
    // An invalid effective model fails preparation instead of writing a guessed model_id.
    remapped
        .binding
        .request
        .body
        .insert("model".into(), serde_json::Value::Null);
    let mut session = recovery_factory(&fixture, remapped, None, Vec::new())
        .open_session()
        .await
        .unwrap();
    assert!(
        session
            .prepare(request("invalid-sent-model", CancellationToken::new()))
            .await
            .is_err()
    );
    session.close().await.unwrap();
    let recorded = fixture.finish().await.unwrap();
    assert_eq!(recorded.len(), 4);
    for (request, expected) in
        recorded
            .iter()
            .zip(["physical-a", "physical-a", "physical-c", "physical-b"])
    {
        assert_eq!(request.body["model"], expected);
    }
}

#[tokio::test]
async fn recovery_applies_saved_options_and_hosted_plan_to_new_input_without_granting_extra_tools()
{
    let calls = |name| {
        responses_tool_calls(
            "resumed",
            "current-model",
            &[RealtimeToolCall {
                name,
                call_id: "call_0",
                item_id: "item_0",
                arguments: json!({"input":"payload"}).to_string(),
            }],
        )
    };
    let fixture = FixtureServer::start(vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            "confirmed replacement",
            0,
            Reply::Sse(calls("saved_tool")),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            "fresh replacement",
            1,
            Reply::Sse(responses_text("done", "fresh", "current-model")),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            "unadvertised call",
            2,
            Reply::Sse(calls("added_tool")),
        ),
    ])
    .await
    .unwrap();
    let mut info = recovery_info(ModelTransportProfile::responses_http());
    info.capabilities.tools.programmatic_tool_calling = true;
    if let ModelProtocolOptions::Responses(options) = &mut info.binding.request.protocol {
        options.programmatic_tool_calling = true;
    }
    let source = recovery_factory(
        &fixture,
        info.clone(),
        Some(ReasoningConfig {
            effort: Some("high".into()),
            summary: Some(ReasoningSummary::Auto),
        }),
        vec![search(false), HostedTool::ProgrammaticToolCalling],
    );
    let parameters = saved_parameters(&source, vec![local_tool("saved_tool")]).await;
    // Include explicit non-default scalar options in the saved fixture. Fresh ThreadModel has
    // no public temperature/tool_choice setters; the recovery API must nevertheless honor them.
    let parameters = edit_parameters(&parameters, |value| {
        value["temperature"] = json!(0.25);
        value["toolChoice"] = json!("required");
    });
    let mut current = info;
    current.max_output_tokens = Some(33);
    current.default_temperature = Some(0.9);
    current.binding.request.body = serde_json::from_value(json!({
        "temperature":0.9, "max_output_tokens":33, "reasoning":{"effort":"low"},
        "parallel_tool_calls":false, "tool_choice":"none", "vendor_extra":{"opaque":"retained"}
    }))
    .unwrap();
    let current = recovery_factory(
        &fixture,
        current,
        Some(ReasoningConfig {
            effort: Some("low".into()),
            summary: Some(ReasoningSummary::Disabled),
        }),
        vec![search(true)],
    );
    let mut session = current.open_session().await.unwrap();
    let catalog: Arc<[ModelToolDeclaration]> =
        vec![local_tool("saved_tool"), local_tool("added_tool")].into();
    let mut resumed = confirmed_request("new-attempt", "confirmed replacement");
    resumed.tools = catalog.clone();
    resumed.recovery_parameters = Some(parameters.clone());
    let prepared = session.prepare(resumed).await.unwrap();
    let receipt = model_request_receipt(prepared.request_metadata().unwrap()).unwrap();
    assert_eq!(receipt.max_tokens, Some(700));
    assert_eq!(receipt.temperature, Some(0.25));
    let output = prepared.execute().await.unwrap();
    assert_eq!(output.tool_calls[0].tool_id, "core-saved_tool");
    assert_eq!(output.tool_calls[0].arguments.format(), "text/plain");
    assert_eq!(output.tool_calls[0].arguments.content(), "payload");
    let mut fresh = confirmed_request("fresh-attempt", "fresh replacement");
    fresh.tools = catalog.clone();
    let fresh_output = session
        .prepare(fresh)
        .await
        .unwrap()
        .execute()
        .await
        .unwrap_or_else(|error| {
            panic!(
                "{error}; fixture rejection: {:?}",
                fixture
                    .recorded()
                    .last()
                    .and_then(|request| request.diagnostic.as_ref())
            )
        });

    let mut unadvertised = confirmed_request("unadvertised-attempt", "unadvertised call");
    unadvertised.tools = catalog;
    unadvertised.recovery_parameters = Some(parameters);
    let output = session
        .prepare(unadvertised)
        .await
        .unwrap()
        .execute()
        .await
        .unwrap();
    assert!(output.tool_calls[0].tool_id.is_empty());
    assert!(matches!(&output.tool_calls[0].rejection,
        Some(pl_core::model::ModelToolCallRejection::UnknownTool { name }) if name == "added_tool"));

    // A foreign source embedded in the new confirmed context must be rejected, not have its
    // native replay silently stripped. No fourth network operation is permitted by this fixture.
    let mut foreign = confirmed_request("foreign-context", "foreign context");
    let content = fresh_output
        .content
        .into_iter()
        .map(|content| match content {
            ContextContent::Opaque { payload } if payload.format() == "pl.model.assistant" => {
                let payload = edit_parameters(&payload, |value| {
                    value["receipt"]["binding"]["accountId"] = json!("foreign");
                });
                ContextContent::Opaque { payload }
            }
            other => other,
        })
        .collect();
    let mut record = foreign.context.records[0].clone();
    record.id = "fresh-attempt:output".into();
    record.source = pl_core::context::ContextSource::Assistant;
    record.content = content;
    foreign.context.records = vec![record].into();
    foreign.recovery_parameters =
        Some(saved_parameters(&source, vec![local_tool("saved_tool")]).await);
    let error = match session.prepare(foreign).await {
        Err(error) => error,
        Ok(_) => panic!("foreign native context admitted"),
    };
    assert_eq!(error.kind, ModelFailureKind::IncompatibleContext);
    session.close().await.unwrap();
    let recorded = fixture.finish().await.unwrap();
    assert_eq!(recorded.len(), 3);
    let resumed = &recorded[0].body;
    assert_eq!(resumed["temperature"], 0.25);
    assert_eq!(resumed["max_output_tokens"], 700);
    assert_eq!(resumed["parallel_tool_calls"], true);
    assert_eq!(resumed["tool_choice"], "required");
    assert_eq!(
        resumed["reasoning"],
        json!({"effort":"high","summary":"auto"})
    );
    assert_eq!(resumed["tools"].as_array().unwrap().len(), 3);
    assert!(!resumed.to_string().contains("added_tool"));
    assert!(!resumed.to_string().contains("current capture"));
    assert_eq!(resumed["vendor_extra"], json!({"opaque":"retained"}));
    let saved_search = resumed["tools"]
        .as_array()
        .unwrap()
        .iter()
        .find(|tool| tool["type"] == "web_search")
        .unwrap();
    assert_eq!(saved_search["external_web_access"], false);
    assert!(
        resumed["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tool| tool["type"] == "programmatic_tool_calling")
    );
    let saved_tool = resumed["tools"]
        .as_array()
        .unwrap()
        .iter()
        .find(|tool| tool["name"] == "saved_tool")
        .unwrap();
    assert!(saved_tool.get("output_schema").is_some());
    let fresh = &recorded[1].body;
    assert_eq!(fresh["temperature"], 0.9);
    assert_eq!(fresh["max_output_tokens"], 33);
    assert_eq!(fresh["reasoning"]["effort"], "low");
    assert_eq!(fresh["parallel_tool_calls"], false);
    assert_eq!(fresh["tool_choice"], "none");
    assert!(
        fresh["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tool| tool["name"] == "added_tool")
    );
    let fresh_search = fresh["tools"]
        .as_array()
        .unwrap()
        .iter()
        .find(|tool| tool["type"] == "web_search")
        .unwrap();
    assert_eq!(fresh_search["external_web_access"], true);
    assert!(
        !fresh["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tool| tool["type"] == "programmatic_tool_calling")
    );
}

#[tokio::test]
async fn recovery_rejects_unbound_or_unrepresentable_saved_material_before_io() {
    let fixture = FixtureServer::start(Vec::new()).await.unwrap();
    let info = recovery_info(ModelTransportProfile::responses_http());
    let source = recovery_factory(&fixture, info.clone(), None, Vec::new());
    let parameters = saved_parameters(&source, vec![local_tool("saved_tool")]).await;
    let mut variants = Vec::new();
    for (field, value) in [
        ("accountId", json!("another-account")),
        ("modelId", json!("another-model")),
        (
            "protocol",
            serde_json::to_value(ProtocolKind::DeepSeek).unwrap(),
        ),
        (
            "wireApi",
            serde_json::to_value(WireApi::ChatCompletions).unwrap(),
        ),
        ("isolation", json!("another-deployment")),
    ] {
        variants.push((
            field,
            edit_parameters(&parameters, |saved| saved["binding"][field] = value),
        ));
    }
    variants.push((
        "unregistered tool",
        edit_parameters(&parameters, |saved| {
            saved["tools"][0]["name"] = json!("unregistered")
        }),
    ));
    variants.push((
        "changed declaration",
        edit_parameters(&parameters, |saved| {
            saved["tools"][0]["description"] = json!("not registered")
        }),
    ));
    variants.push((
        "duplicate tool",
        edit_parameters(&parameters, |saved| {
            let tool = saved["tools"][0].clone();
            saved["tools"].as_array_mut().unwrap().push(tool);
        }),
    ));
    variants.push((
        "unsupported effort",
        edit_parameters(&parameters, |saved| {
            saved["reasoning"] = json!({"effort":"not-supported","summary":null})
        }),
    ));
    variants.push((
        "wrong hosted dialect",
        edit_parameters(&parameters, |saved| {
            saved["tools"].as_array_mut().unwrap().push(
                serde_json::to_value(ToolSpec::WebSearch {
                    options: HostedWebSearchOptions::DeepSeek,
                })
                .unwrap(),
            )
        }),
    ));
    variants.push((
        "wrong format",
        OpaquePayload::new(
            "not-a-prepared-request",
            parameters.version(),
            parameters.content(),
        )
        .unwrap(),
    ));
    variants.push((
        "unknown version",
        OpaquePayload::new(parameters.format(), 99, parameters.content()).unwrap(),
    ));
    variants.push((
        "unconfirmed parameters",
        OpaquePayload::new(parameters.format(), parameters.version(), "{}").unwrap(),
    ));
    let mut session = source.open_session().await.unwrap();
    for (case, parameters) in variants {
        let mut resumed = request(case, CancellationToken::new());
        resumed.tools = vec![local_tool("saved_tool")].into();
        resumed.recovery_parameters = Some(parameters);
        let error = match session.prepare(resumed).await {
            Err(error) => error,
            Ok(_) => panic!("admitted {case}"),
        };
        assert_eq!(
            error.kind,
            ModelFailureKind::IncompatibleContext,
            "{case}: {error}"
        );
    }
    session.close().await.unwrap();
    let mut configurations = Vec::new();
    let mut omit = info.clone();
    if let ModelProtocolOptions::Responses(options) = &mut omit.binding.request.protocol {
        options.max_tokens_field = ResponsesMaxTokensField::Omit;
    }
    configurations.push(("omitted token limit", omit, parameters.clone()));
    let mut exhausted = info.clone();
    exhausted.context_window = Some(500);
    exhausted.max_output_tokens = Some(33);
    configurations.push(("exhausted output budget", exhausted, parameters.clone()));
    let mut no_temperature = info.clone();
    no_temperature.capabilities.temperature = false;
    configurations.push((
        "unsupported temperature",
        no_temperature,
        edit_parameters(&parameters, |saved| saved["temperature"] = json!(0.25)),
    ));
    for (key, value) in [
        ("input", json!([{"role":"user","content":"unconfirmed"}])),
        ("model", json!("silent-model-replacement")),
        ("previous_response_id", json!("old-stream")),
    ] {
        let mut injected = info.clone();
        injected.binding.request.body.insert(key.into(), value);
        configurations.push((key, injected, parameters.clone()));
    }
    let mut unsafe_wire = info.clone();
    unsafe_wire.parameters[0].wire.get_mut("high").unwrap().set[0].path = "input".into();
    configurations.push((
        "wire changes input",
        unsafe_wire,
        edit_parameters(&parameters, |saved| {
            saved["reasoning"] = json!({"effort":"high","summary":null})
        }),
    ));
    for (case, info, parameters) in configurations {
        let mut session = recovery_factory(&fixture, info, None, Vec::new())
            .open_session()
            .await
            .unwrap();
        let mut resumed = request(case, CancellationToken::new());
        resumed.tools = vec![local_tool("saved_tool")].into();
        resumed.recovery_parameters = Some(parameters);
        let error = match session.prepare(resumed).await {
            Err(error) => error,
            Ok(_) => panic!("admitted {case}"),
        };
        assert_eq!(
            error.kind,
            ModelFailureKind::IncompatibleContext,
            "{case}: {error}"
        );
        session.close().await.unwrap();
    }
    let endpoint = ProtocolEndpoint::compatible("fixture", fixture.base_url());
    let missing_hosted = ModelFactory::new(ThreadModel::new_current(
        ModelRuntime::new_with_account_id("fixture", endpoint, info.clone()).unwrap(),
        None,
    ));
    let mut session = missing_hosted.open_session().await.unwrap();
    let mut resumed = request("missing hosted service", CancellationToken::new());
    resumed.tools = vec![local_tool("saved_tool")].into();
    let source_hosted = recovery_factory(&fixture, info.clone(), None, vec![search(false)]);
    resumed.recovery_parameters =
        Some(saved_parameters(&source_hosted, vec![local_tool("saved_tool")]).await);
    let error = match session.prepare(resumed).await {
        Err(error) => error,
        Ok(_) => panic!("unavailable hosted service admitted"),
    };
    assert_eq!(error.kind, ModelFailureKind::IncompatibleContext);
    session.close().await.unwrap();

    // Reserve the saved output budget, not the current smaller default, against new input.
    let mut narrow = info;
    narrow.context_window = Some(800);
    narrow.max_output_tokens = Some(33);
    let mut session = recovery_factory(&fixture, narrow, None, Vec::new())
        .open_session()
        .await
        .unwrap();
    let mut resumed = confirmed_request("saved output reserve", &"x".repeat(1000));
    resumed.tools = vec![local_tool("saved_tool")].into();
    resumed.recovery_parameters = Some(parameters);
    let error = match session.prepare(resumed).await {
        Err(error) => error,
        Ok(_) => panic!("new input ignored the saved output reserve"),
    };
    assert_eq!(error.kind, ModelFailureKind::ContextLimit);
    session.close().await.unwrap();
    assert!(fixture.finish().await.unwrap().is_empty());
}

#[tokio::test]
async fn recovery_chat_uses_saved_effort_and_limit_and_keeps_absent_options_absent() {
    let fixture = FixtureServer::start(vec![Step::prompt(Protocol::Chat, "confirmed chat", 0,
        Reply::Sse(vec![
            json!({"id":"chat-result","model":"current-model","choices":[{"index":0,"delta":{"role":"assistant","content":"done"},"finish_reason":null}]}),
            json!({"id":"chat-result","model":"current-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":1}}),
        ])), Step::prompt(Protocol::Chat, "official default parallel", 1, Reply::Sse(vec![
            json!({"id":"default-result","model":"current-model","choices":[{"index":0,"delta":{"role":"assistant","content":"done"},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":1}})
        ]))]).await.unwrap();
    let info = recovery_info(ModelTransportProfile::chat_completions_http());
    let official = |info, reasoning| {
        recovery_factory_with_endpoint(
            ProtocolEndpoint::openai(Some(fixture.base_url())),
            info,
            reasoning,
            Vec::new(),
        )
    };
    let source = official(
        info.clone(),
        Some(ReasoningConfig {
            effort: Some("high".into()),
            summary: None,
        }),
    );
    let parameters = saved_parameters(&source, vec![local_tool("saved_tool")]).await;
    let mut current = info.clone();
    current.max_output_tokens = Some(33);
    current.binding.request.body = serde_json::from_value(json!({
        "temperature":0.9,"max_tokens":33,"max_completion_tokens":33,"reasoning_effort":"low",
        "vendor_reasoning":{"effort":"low"}
    }))
    .unwrap();
    current.parameters[0]
        .wire
        .get_mut("low")
        .unwrap()
        .set
        .push(pl_model::model::WireAssignment {
            path: "vendor_reasoning.effort".into(),
            value: json!("low"),
        });
    if let ModelProtocolOptions::ChatCompletions(options) = &mut current.binding.request.protocol {
        options.max_tokens_field = pl_model::model::MaxTokensField::MaxCompletionTokens;
    }
    let mut session = official(
        current,
        Some(ReasoningConfig {
            effort: Some("low".into()),
            summary: None,
        }),
    )
    .open_session()
    .await
    .unwrap();
    let mut resumed = confirmed_request("chat-recovery", "confirmed chat");
    resumed.tools = vec![local_tool("saved_tool")].into();
    resumed.recovery_parameters = Some(parameters.clone());
    session
        .prepare(resumed)
        .await
        .unwrap()
        .execute()
        .await
        .unwrap();
    session.close().await.unwrap();
    let mut current = info.clone();
    if let ModelProtocolOptions::ChatCompletions(options) = &mut current.binding.request.protocol {
        options.parallel_tool_calls = false;
    }
    let mut session = official(current, None).open_session().await.unwrap();
    let mut false_request = confirmed_request("official false omitted", "must not send");
    false_request.tools = vec![local_tool("saved_tool")].into();
    false_request.recovery_parameters = Some(edit_parameters(&parameters, |value| {
        value["parallelToolCalls"] = json!(false)
    }));
    let error = match session.prepare(false_request).await {
        Err(error) => error,
        Ok(_) => panic!("official true default cannot represent saved false"),
    };
    assert_eq!(error.kind, ModelFailureKind::IncompatibleContext);
    let mut resumed = confirmed_request("official-default", "official default parallel");
    resumed.tools = vec![local_tool("saved_tool")].into();
    resumed.recovery_parameters = Some(parameters.clone());
    session
        .prepare(resumed)
        .await
        .unwrap()
        .execute()
        .await
        .unwrap();
    session.close().await.unwrap();
    let mut session = official(info, None).open_session().await.unwrap();
    let mut unsupported = request("summary", CancellationToken::new());
    unsupported.tools = vec![local_tool("saved_tool")].into();
    unsupported.recovery_parameters = Some(edit_parameters(&parameters, |value| {
        value["reasoning"]["summary"] = json!("auto")
    }));
    let error = match session.prepare(unsupported).await {
        Err(error) => error,
        Ok(_) => panic!("Chat summary admitted"),
    };
    assert_eq!(error.kind, ModelFailureKind::IncompatibleContext);
    session.close().await.unwrap();
    let recorded = fixture.finish().await.unwrap();
    assert_eq!(recorded.len(), 2);
    assert!(
        recorded[1].body.get("parallel_tool_calls").is_none(),
        "official omission must be accepted as its true default"
    );
    assert!(
        recorded
            .iter()
            .all(|request| request.body["store"] == false),
        "the wire requests no storage rather than claiming an account default"
    );
    let body = &recorded[0].body;
    assert_eq!(body["reasoning_effort"], "high");
    assert_eq!(body["parallel_tool_calls"], true);
    assert_eq!(body["max_completion_tokens"], 700);
    assert!(body.get("max_tokens").is_none());
    assert!(body.get("temperature").is_none());
    assert!(
        body.get("vendor_reasoning").is_none(),
        "a current default's unused effort wire must not leak an empty native object"
    );
    assert!(!body.to_string().contains("current capture"));
}

#[tokio::test]
async fn recovery_on_reused_websocket_session_starts_without_continuation() {
    let fixture = FixtureServer::start(vec![
        Step::prompt(
            Protocol::ResponsesWebSocket,
            "current capture",
            0,
            Reply::WebSocket(responses_text(
                "first body",
                "first-response",
                "current-model",
            )),
        ),
        Step::prompt(
            Protocol::ResponsesWebSocket,
            "next confirmed",
            1,
            Reply::WebSocket(responses_text(
                "second body",
                "second-response",
                "current-model",
            )),
        ),
        Step::prompt(
            Protocol::ResponsesWebSocket,
            "restart confirmed",
            2,
            Reply::WebSocket(responses_text(
                "third body",
                "third-response",
                "current-model",
            )),
        ),
    ])
    .await
    .unwrap();
    let info = recovery_info(ModelTransportProfile::responses_websocket());
    let factory = recovery_factory(&fixture, info, None, Vec::new());
    let mut session = factory.open_session().await.unwrap();
    let initial = request("ws-first", CancellationToken::new());
    let history = initial.context.records.to_vec();
    let prepared = session.prepare(initial).await.unwrap();
    let parameters = prepared.request_metadata().unwrap().clone();
    let first = prepared.execute().await.unwrap();
    let next = |mut history: Vec<ContextRecord>,
                output: pl_core::model::ModelStepOutput,
                attempt: &str,
                text: &str| {
        history.push(ContextRecord {
            id: format!("{}:output", output.attempt_id),
            turn_id: Some("current-turn".into()),
            source: pl_core::context::ContextSource::Assistant,
            content: output.content,
            tool_calls: output.tool_calls,
        });
        let mut request = confirmed_request(attempt, text);
        let mut input = request.context.records[0].clone();
        input.id = format!("{attempt}:input");
        history.push(input);
        request.context.records = history.into();
        request.committed_private_context = output.private_context;
        request
    };
    let second = next(history, first, "ws-second", "next confirmed");
    let history = second.context.records.to_vec();
    let second = session
        .prepare(second)
        .await
        .unwrap()
        .execute()
        .await
        .unwrap();
    let mut resumed = next(history, second, "ws-recovery", "restart confirmed");
    resumed.recovery_parameters = Some(parameters);
    session
        .prepare(resumed)
        .await
        .unwrap()
        .execute()
        .await
        .unwrap();
    session.close().await.unwrap();
    let recorded = fixture.finish().await.unwrap();
    assert_eq!(recorded.len(), 3);
    assert_eq!(
        recorded[1].body["previous_response_id"], "first-response",
        "the control request must exercise actual native continuation"
    );
    assert!(recorded[2].body.get("previous_response_id").is_none());
    assert!(
        recorded[2].body["input"].as_array().unwrap().len() > 1,
        "RestartOnly must send the confirmed history, not only the continuation delta"
    );
}

#[tokio::test]
async fn current_capture_during_first_byte_and_next_frame_keeps_one_request_and_final_partial() {
    for empty in [true, false] {
        let reached = CancellationToken::new();
        let release = CancellationToken::new();
        let partial = "{\"path\":\"src/ma";
        let prefix = if empty {
            Vec::new()
        } else {
            vec![
                json!({"type":"response.created","response":{"id":"partial-response"}}),
                json!({"type":"response.output_item.added","output_index":0,"item":{"id":"commentary","type":"message","role":"assistant","phase":"commentary","content":[]}}),
                json!({"type":"response.output_text.delta","item_id":"commentary","content_index":0,"delta":"complete accepted commentary"}),
                json!({"type":"response.output_item.added","output_index":1,"item":{"id":"tool","type":"function_call","call_id":"call_0","name":"read_file","arguments":"","signature":"keep-native"}}),
                json!({"type":"response.function_call_arguments.delta","item_id":"tool","call_id":"call_0","delta":partial}),
            ]
        };
        let fixture = FixtureServer::start(vec![Step::prompt(
            Protocol::ResponsesHttp,
            "current capture",
            0,
            Reply::GatedSse {
                before: prefix,
                reached: reached.clone(),
                release: release.clone(),
                after: Vec::new(),
            },
        )])
        .await
        .unwrap();
        let mut session = factory(&fixture).open_session().await.unwrap();
        let cancellation = CancellationToken::new();
        let prepared = session
            .prepare(request("actual-attempt", cancellation.clone()))
            .await
            .unwrap();
        let capture = prepared.current_capture().unwrap().clone();
        let epoch = RuntimeEpoch::new();
        let changes = capture.subscribe_changes();
        let execution = tokio::spawn(prepared.execute_with_current());
        reached.cancelled().await;
        // The fixture handshake says the prefix is written, not yet that the client merged it.
        // Observe dirty revisions rather than sleeping or issuing another network request.
        if !empty {
            let mut changes = changes.clone();
            loop {
                let view = ModelStreamCurrent::decode(
                    &capture
                        .capture(epoch, "actual-attempt", CancellationToken::new())
                        .await
                        .unwrap(),
                )
                .unwrap();
                if !view.tool_inputs.is_empty() {
                    break;
                }
                tokio::time::timeout(Duration::from_secs(1), changes.changed())
                    .await
                    .unwrap()
                    .unwrap();
            }
        }
        assert!(
            capture
                .capture(epoch, "wrong-attempt", CancellationToken::new())
                .await
                .is_err()
        );
        let snapshot = capture
            .capture(epoch, "actual-attempt", CancellationToken::new())
            .await
            .unwrap();
        let view = ModelStreamCurrent::decode(&snapshot).unwrap();
        assert_eq!(view.state, ModelStreamCurrentState::Open);
        if empty {
            assert!(view.content_parts.is_empty());
        } else {
            assert_eq!(view.tool_inputs[0].input, partial);
            assert!(view.tool_calls.is_empty());
            assert!(
                view.content_parts
                    .iter()
                    .any(|part| part.text == "complete accepted commentary")
            );
            assert!(*changes.borrow() > 0);
        }
        cancellation.cancel();
        let exit = tokio::time::timeout(Duration::from_secs(2), execution)
            .await
            .unwrap()
            .unwrap();
        assert!(exit.result.is_err());
        let final_view = ModelStreamCurrent::decode(&exit.current.unwrap()).unwrap();
        assert!(matches!(
            final_view.state,
            ModelStreamCurrentState::Failed { .. }
        ));
        if !empty {
            assert_eq!(final_view.tool_inputs[0].input, partial);
            assert!(final_view.tool_calls.is_empty());
        }
        release.cancel();
        session.close().await.unwrap();
        let requests = fixture.finish().await.unwrap();
        assert_eq!(requests.len(), 1, "capture must not reconnect or resend");
    }
}

#[tokio::test]
async fn current_capture_while_opening_http_response_does_not_redial() {
    use tokio::io::AsyncReadExt;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let reached = CancellationToken::new();
    let release = CancellationToken::new();
    let server = tokio::spawn({
        let reached = reached.clone();
        let release = release.clone();
        async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut bytes = [0_u8; 4096];
            assert!(socket.read(&mut bytes).await.unwrap() > 0);
            reached.cancel(); // No HTTP status/headers have been sent: stream opening still awaits.
            tokio::select! {
                _ = release.cancelled() => false,
                second = listener.accept() => { let _second = second.unwrap(); true },
            }
        }
    });
    let mut session = endpoint_factory(format!("http://{address}"))
        .open_session()
        .await
        .unwrap();
    let cancellation = CancellationToken::new();
    let prepared = session
        .prepare(request("opening-source", cancellation.clone()))
        .await
        .unwrap();
    let capture = prepared.current_capture().unwrap().clone();
    let execution = tokio::spawn(prepared.execute_with_current());
    reached.cancelled().await;
    let view = ModelStreamCurrent::decode(
        &capture
            .capture(
                RuntimeEpoch::new(),
                "opening-source",
                CancellationToken::new(),
            )
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(view.state, ModelStreamCurrentState::Open);
    assert!(view.content_parts.is_empty());
    cancellation.cancel();
    let exit = tokio::time::timeout(Duration::from_secs(2), execution)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        exit.result.unwrap_err().kind,
        pl_core::model::ModelFailureKind::Cancelled
    );
    assert!(matches!(
        ModelStreamCurrent::decode(&exit.current.unwrap())
            .unwrap()
            .state,
        ModelStreamCurrentState::Failed { .. }
    ));
    release.cancel();
    assert!(
        !server.await.unwrap(),
        "capture must not establish a second connection"
    );
    session.close().await.unwrap();
}

#[tokio::test]
async fn current_success_hands_off_before_accumulator_consumption() {
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "current capture",
        0,
        Reply::Sse(responses_text(
            "complete final body",
            "complete-response",
            "current-model",
        )),
    )])
    .await
    .unwrap();
    let mut session = factory(&fixture).open_session().await.unwrap();
    let exit = session
        .prepare(request("source-success", CancellationToken::new()))
        .await
        .unwrap()
        .execute_with_current()
        .await;
    let output = exit.result.unwrap();
    assert_eq!(output.attempt_id, "source-success");
    let view = ModelStreamCurrent::decode(&exit.current.unwrap()).unwrap();
    assert_eq!(view.state, ModelStreamCurrentState::Completed);
    assert_eq!(view.response_id.as_deref(), Some("complete-response"));
    assert!(
        view.content_parts
            .iter()
            .any(|part| part.text == "complete final body")
    );
    assert!(!view.replay.items.is_empty());
    assert!(!view.presentation_items.is_empty());
    session.close().await.unwrap();
    fixture.finish().await.unwrap();
}

#[tokio::test]
async fn current_codec_failure_keeps_the_completed_producer_view() {
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "current capture",
        0,
        Reply::Sse(responses_text(
            "accepted before codec rejection",
            "codec-response",
            "current-model",
        )),
    )])
    .await
    .unwrap();
    let mut session = factory(&fixture).open_session().await.unwrap();
    // A faulty caller supplies no source attempt. The new codec must fail closed after the real
    // provider finishes, and the ordinary exit must still hand off all accepted stream material.
    let exit = session
        .prepare(request("", CancellationToken::new()))
        .await
        .unwrap()
        .execute_with_current()
        .await;
    assert!(exit.result.is_err());
    let view = ModelStreamCurrent::decode(&exit.current.unwrap()).unwrap();
    assert_eq!(view.state, ModelStreamCurrentState::Completed);
    assert!(
        view.content_parts
            .iter()
            .any(|part| part.text == "accepted before codec rejection")
    );
    assert!(!view.replay.items.is_empty());
    session.close().await.unwrap();
    fixture.finish().await.unwrap();
}

#[tokio::test]
async fn current_retry_keeps_failed_generations_separate_from_the_successful_response() {
    let first = CancellationToken::new();
    let release_first = CancellationToken::new();
    let second = CancellationToken::new();
    let release_second = CancellationToken::new();
    let fixture = FixtureServer::start(vec![
        Step::prompt(Protocol::ResponsesHttp, "current capture", 0, Reply::GatedSse {
            before: vec![
                json!({"type":"response.created","response":{"id":"old-response"}}),
                json!({"type":"response.output_text.delta","item_id":"old-item","content_index":0,"delta":"old partial"}),
            ], reached: first.clone(), release: release_first.clone(),
            after: vec![json!({"type":"response.failed","response":{"id":"old-response","error":{"code":"server_error","message":"retry this generation"}}})],
        }),
        Step::prompt(Protocol::ResponsesHttp, "current capture", 1, Reply::GatedSse {
            before: vec![
                json!({"type":"response.created","response":{"id":"new-response"}}),
                json!({"type":"response.output_text.delta","item_id":"new-item","content_index":0,"delta":"new body"}),
            ], reached: second.clone(), release: release_second.clone(),
            after: vec![
                json!({"type":"response.output_item.done","output_index":0,"item":{"id":"new-item","type":"message","role":"assistant","phase":"final","status":"completed","content":[{"type":"output_text","text":"new body"}]}}),
                json!({"type":"response.completed","response":{"id":"new-response"}}),
            ],
        }),
    ]).await.unwrap();
    let mut session = factory(&fixture).open_session().await.unwrap();
    let prepared = session
        .prepare(request("retry-source", CancellationToken::new()))
        .await
        .unwrap();
    let capture = prepared.current_capture().unwrap().clone();
    let mut changes = capture.subscribe_changes();
    let execution = tokio::spawn(prepared.execute_with_current());
    let epoch = RuntimeEpoch::new();
    first.cancelled().await;
    loop {
        let view = ModelStreamCurrent::decode(
            &capture
                .capture(epoch, "retry-source", CancellationToken::new())
                .await
                .unwrap(),
        )
        .unwrap();
        if view
            .content_parts
            .iter()
            .any(|part| part.text == "old partial")
        {
            break;
        }
        changes.changed().await.unwrap();
    }
    release_first.cancel();
    loop {
        let view = ModelStreamCurrent::decode(
            &capture
                .capture(epoch, "retry-source", CancellationToken::new())
                .await
                .unwrap(),
        )
        .unwrap();
        if matches!(view.state, ModelStreamCurrentState::Failed { .. }) {
            assert_eq!(
                view.generation, 0,
                "capture is serviced during retry backoff, before a new send"
            );
            break;
        }
        changes.changed().await.unwrap();
    }
    tokio::time::timeout(Duration::from_secs(3), second.cancelled())
        .await
        .unwrap();
    loop {
        let view = ModelStreamCurrent::decode(
            &capture
                .capture(epoch, "retry-source", CancellationToken::new())
                .await
                .unwrap(),
        )
        .unwrap();
        if view
            .content_parts
            .iter()
            .any(|part| part.text == "new body")
        {
            assert_eq!(view.generation, 1);
            assert_eq!(view.previous_generations.len(), 1);
            assert!(matches!(
                view.previous_generations[0].state,
                ModelStreamCurrentState::Failed { .. }
            ));
            assert!(
                view.previous_generations[0]
                    .content_parts
                    .iter()
                    .any(|part| part.text == "old partial")
            );
            assert!(
                !view
                    .content_parts
                    .iter()
                    .any(|part| part.text.contains("old partial"))
            );
            break;
        }
        changes.changed().await.unwrap();
    }
    release_second.cancel();
    let exit = execution.await.unwrap();
    let output = exit.result.unwrap();
    assert!(output.content.iter().any(
        |content| matches!(content, ContextContent::Text { text } if text.as_ref() == "new body")
    ));
    assert!(!format!("{output:?}").contains("old partial"));
    let final_view = ModelStreamCurrent::decode(&exit.current.unwrap()).unwrap();
    assert_eq!(final_view.generation, 1);
    assert_eq!(final_view.previous_generations.len(), 1);
    session.close().await.unwrap();
    assert_eq!(fixture.finish().await.unwrap().len(), 2);
}
