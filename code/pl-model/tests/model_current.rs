//! Current factory integration: the real provider accumulator, not a DTO-only capture stub.
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSnapshot},
    model::{ModelFactory, ModelRequest, ToolCallMode},
    thread::current::RuntimeEpoch,
};
use pl_model::{
    completion::{ModelStreamCurrent, ModelStreamCurrentState, ReasoningConfig},
    model::{
        ModelDefinition, ModelProtocolOptions, ModelTransportProfile, ResponsesMaxTokensField,
    },
    protocol::ProtocolEndpoint,
    runtime::{CancellationToken, HostedTool, ThreadModel},
};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
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
    let mut model = ModelDefinition::compatible("current-model");
    model
        .extra
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    ModelFactory::new(ThreadModel::new(
        pl_model::runtime::new_with_account_id(
            "fixture",
            pl_model::protocol::providers::openai::compatible_endpoint("fixture", base_url),
            model,
        )
        .unwrap(),
        None,
    ))
}

fn recovery_info(transport: ModelTransportProfile) -> ModelDefinition {
    let mut info = ModelDefinition::compatible("current-model");
    info.extra.binding.set_transport(transport);
    let effort_path = match &mut info.extra.binding.request.protocol {
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
        info.extra.binding.request.protocol,
        ModelProtocolOptions::ChatCompletions(_)
    ) {
        info.extra
            .binding
            .request
            .body
            .insert("store".into(), json!(false));
    }
    info.extra.parameters = vec![
        serde_json::from_value(json!({
            "name":"effort", "candidates":["low","high"],
            "wire":{
                "low":{"set":[{"path":effort_path,"value":"low"}]},
                "high":{"set":[{"path":effort_path,"value":"high"}]}
            }
        }))
        .unwrap(),
    ];
    info.extra.capabilities.reasoning = true;
    info.extra.capabilities.web_search = true;
    info.base.supports_parallel_tool_calls = Some(true);
    info.extra.max_output_tokens = Some(700);
    info
}

fn recovery_factory(
    fixture: &FixtureServer,
    info: ModelDefinition,
    reasoning: Option<ReasoningConfig>,
    hosted: Vec<HostedTool>,
) -> ModelFactory {
    recovery_factory_with_endpoint(
        pl_model::protocol::providers::openai::compatible_endpoint("fixture", fixture.base_url()),
        info,
        reasoning,
        hosted,
    )
}

fn recovery_factory_with_endpoint(
    mut endpoint: ProtocolEndpoint,
    info: ModelDefinition,
    reasoning: Option<ReasoningConfig>,
    hosted: Vec<HostedTool>,
) -> ModelFactory {
    endpoint.service_capabilities.web_search.hosted_responses = true;
    endpoint
        .service_capabilities
        .responses_tools
        .programmatic_tool_calling = info
        .extra
        .binding
        .request
        .supports_programmatic_tool_calling();
    ModelFactory::new(
        ThreadModel::new(
            pl_model::runtime::new_with_account_id("fixture", endpoint, info).unwrap(),
            reasoning,
        )
        .with_hosted_tools(hosted),
    )
}

fn confirmed_request(attempt: &str, text: &str) -> ModelRequest {
    let mut request = request(attempt, CancellationToken::new());
    Arc::make_mut(&mut request.context.records)[0].content =
        vec![ContextContent::Text { text: text.into() }];
    request
}

#[tokio::test]
async fn restart_on_new_websocket_session_starts_without_continuation() {
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
    session.close().await.unwrap();
    let mut session = factory.open_session().await.unwrap();
    let resumed = next(history, second, "ws-recovery", "restart confirmed");
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
        let execution = tokio::spawn(prepared.execute_with_current());
        reached.cancelled().await;
        // The fixture handshake says the prefix is written, not yet that the client merged it.
        // Capture the producer view until the written prefix has been accepted.
        if !empty {
            let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
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
                assert!(
                    tokio::time::Instant::now() < deadline,
                    "producer did not accept prefix"
                );
                tokio::task::yield_now().await;
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
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
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
        assert!(
            tokio::time::Instant::now() < deadline,
            "producer did not reach expected state"
        );
        tokio::task::yield_now().await;
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
        assert!(
            tokio::time::Instant::now() < deadline,
            "producer did not reach expected state"
        );
        tokio::task::yield_now().await;
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
        assert!(
            tokio::time::Instant::now() < deadline,
            "producer did not reach expected state"
        );
        tokio::task::yield_now().await;
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
