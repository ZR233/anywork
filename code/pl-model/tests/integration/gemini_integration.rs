//! Integration tests for Gemini / Vertex AI catalog composition, paginated discovery and runtime execution.

use base64::{Engine, engine::general_purpose::STANDARD};
use pl_model::{
    completion::{
        AssistantReplay, AttachmentInput, AttachmentModality, AttachmentSource, CompletionRequest,
        ContentPart, Message, MessageContent, MessageRole, ReasoningConfig, SystemPrompt,
        ToolCallKind, ToolResultReceipt, ToolResultRecord, ToolSpec,
    },
    config::{
        AccountConfig, AccountId, AccountModelCatalogConfig, AgentModelConfig, ModelCatalogId,
        builtin_account_catalog,
    },
    model::{
        DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT, PricingOutcome, bundled_model_definition,
        bundled_selection_guide,
    },
    protocol::{
        WireApi,
        discovery::{ModelCatalogQuery, ModelCatalogQueryError, ModelCatalogQueryResult},
        providers::gemini::{gemini_api_endpoint, vertex_endpoint},
    },
    runtime::{ModelInvocationContext, new_with_account_id},
};
use serde_json::{Value, json};
use std::time::Duration;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
};

#[test]
fn builtin_catalog_includes_and_validates_vertex_ai_and_gemini() {
    let registry = builtin_account_catalog().expect("builtin registry constructs");
    registry.validate().expect("builtin registry validates");

    let vertex = registry
        .templates
        .iter()
        .find(|t| t.id.as_str() == "vertex-ai")
        .expect("vertex-ai template");
    assert_eq!(vertex.credential_env.as_deref(), Some("GCP_API_KEY"));
    assert_eq!(vertex.model_catalog.as_str(), "vertex-ai");
    assert_eq!(vertex.suggested_model_id, "gemini-4-hydrogen");

    let gemini = registry
        .templates
        .iter()
        .find(|t| t.id.as_str() == "gemini")
        .expect("gemini template");
    assert_eq!(gemini.credential_env.as_deref(), Some("GEMINI_API_KEY"));
    assert_eq!(gemini.model_catalog.as_str(), "gemini");
    assert_eq!(gemini.suggested_model_id, "gemini-4-hydrogen");

    let snap = registry.snapshot().expect("snapshot serializes");
    let vertex_desc = snap.templates.iter().find(|t| t.id == "vertex-ai").unwrap();
    assert!(!vertex_desc.supports_model_discovery);
    let gemini_desc = snap.templates.iter().find(|t| t.id == "gemini").unwrap();
    assert!(gemini_desc.supports_model_discovery);

    let expected_ids = [
        "gemini-4-hydrogen",
        "gemini-4-neon",
        "gemini-4-argon",
        "gemini-4-carbon",
    ];
    for catalog_id in ["gemini", "vertex-ai"] {
        let models = &snap.model_catalogs[catalog_id].models;
        let ids: Vec<&str> = models.iter().map(|m| m.model_id.as_str()).collect();
        assert_eq!(ids, expected_ids);
        for m in models {
            assert_eq!(m.transport.protocol, "gemini_generate_content");
            assert_eq!(m.context.context_window, Some(1_048_576));
            assert_eq!(m.context.auto_compact_limit, Some(512_000));
            let pricing = m
                .pricing
                .as_ref()
                .expect("gemini 4 pricing must be populated");
            assert_eq!(pricing.currency, "USD");
            assert!(bundled_selection_guide(catalog_id, &m.model_id).is_some());
        }
        assert!(bundled_selection_guide(catalog_id, "gemini-3.7-flash").is_none());
    }
}

#[tokio::test]
async fn discovery_query_supports_gemini_pagination_with_x_goog_api_key_and_rejects_vertex_ai() {
    let vertex_ep = vertex_endpoint(None);
    let vertex_acct = AccountConfig::from_bundled_catalog(
        vertex_ep,
        ModelCatalogId::new("vertex-ai").unwrap(),
        Vec::new(),
    );
    assert!(matches!(
        ModelCatalogQuery::for_account(&vertex_acct),
        Err(ModelCatalogQueryError::Unsupported)
    ));

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}/v1beta", listener.local_addr().unwrap());
    let server = tokio::spawn(async move {
        let mut seen_requests = Vec::new();
        for page_index in 0..2 {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut buf = Vec::new();
            while !buf.ends_with(b"\r\n\r\n") {
                buf.push(socket.read_u8().await.unwrap());
                assert!(buf.len() < 16384);
            }
            let req = String::from_utf8(buf).unwrap();
            seen_requests.push(req);
            let body = if page_index == 0 {
                json!({
                    "models": [
                        {
                            "name": "models/gemini-4-hydrogen",
                            "displayName": "Gemini 4 Hydrogen",
                            "supportedGenerationMethods": ["generateContent", "countTokens"],
                            "inputTokenLimit": 1048576,
                            "outputTokenLimit": 65536
                        },
                        {
                            "name": "models/embedding-001",
                            "supportedGenerationMethods": ["embedContent"]
                        }
                    ],
                    "nextPageToken": "page-2-tok"
                })
            } else {
                json!({
                    "models": [
                        {
                            "name": "models/gemini-4-carbon",
                            "displayName": "Gemini 4 Carbon",
                            "supportedGenerationMethods": ["generateContent"],
                            "inputTokenLimit": 1048576,
                            "outputTokenLimit": 32768
                        }
                    ]
                })
            }
            .to_string();
            let resp = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nETag: \"v1\"\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            socket.write_all(resp.as_bytes()).await.unwrap();
        }
        seen_requests
    });

    let mut ep = gemini_api_endpoint(Some(base));
    ep.bearer_token = Some("test-goog-secret".into());
    let account =
        AccountConfig::from_bundled_catalog(ep, ModelCatalogId::new("gemini").unwrap(), Vec::new());
    assert!(matches!(
        account.catalog,
        AccountModelCatalogConfig::Bundled { .. }
    ));
    let query = ModelCatalogQuery::for_account(&account).unwrap();
    let result = query.execute(None).await.unwrap();
    let seen = tokio::time::timeout(Duration::from_secs(5), server)
        .await
        .unwrap()
        .unwrap();

    assert!(seen[0].contains("GET /v1beta/models?pageSize=1000 "));
    assert!(
        seen[0]
            .to_ascii_lowercase()
            .contains("x-goog-api-key: test-goog-secret")
    );
    assert!(
        !seen[0]
            .to_ascii_lowercase()
            .contains("authorization: bearer")
    );
    assert!(seen[1].contains("pageSize=1000&pageToken=page-2-tok"));

    let ModelCatalogQueryResult::Updated { etag, models, .. } = result else {
        panic!("expected Updated");
    };
    assert!(
        etag.is_none(),
        "multi-page discovery must not publish a single-page ETag"
    );
    let hydrogen = models
        .iter()
        .find(|m| m.base.slug == "gemini-4-hydrogen")
        .expect("gemini-4-hydrogen present");
    assert_eq!(
        hydrogen.extra.capabilities.output,
        vec![pl_model::model::ModelModality::Text]
    );
    assert!(
        hydrogen
            .extra
            .capabilities
            .supports_input_modality(pl_model::model::ModelModality::File)
    );
    assert_eq!(hydrogen.base.auto_compact_token_limit, Some(512_000));
    assert_eq!(
        hydrogen
            .resolve_context(None, pl_model::model::AutoCompactDefaultPolicy::Bundled)
            .auto_compact_limit,
        Some(512_000)
    );

    let carbon = models
        .iter()
        .find(|m| m.base.slug == "gemini-4-carbon")
        .expect("gemini-4-carbon present");
    assert_eq!(
        carbon.extra.capabilities.output,
        vec![pl_model::model::ModelModality::Text]
    );
    assert_eq!(carbon.base.auto_compact_token_limit, Some(512_000));
    assert_eq!(
        carbon
            .resolve_context(None, pl_model::model::AutoCompactDefaultPolicy::Bundled)
            .auto_compact_limit,
        Some(512_000)
    );

    let embedding = models
        .iter()
        .find(|m| m.base.slug == "embedding-001")
        .expect("non-generative entry preserved for capability inspection");
    assert!(
        embedding.extra.capabilities.output.is_empty(),
        "non-generative embedding model must declare empty text output so chat routing excludes it"
    );
}

async fn serve_gemini_sse(listener: TcpListener, replies: Vec<Vec<Value>>) -> Vec<Value> {
    let mut captured_bodies = Vec::new();
    for (step, frames) in replies.into_iter().enumerate() {
        let (mut socket, _) = listener.accept().await.unwrap();
        let mut raw = Vec::new();
        let header_end = loop {
            raw.push(socket.read_u8().await.unwrap());
            if let Some(pos) = raw.windows(4).position(|w| w == b"\r\n\r\n") {
                break pos;
            }
        };
        let header_text = String::from_utf8_lossy(&raw[..header_end]).to_string();
        assert!(
            header_text
                .to_ascii_lowercase()
                .contains("x-goog-api-key: gcp-secret")
        );
        let content_len: usize = header_text
            .lines()
            .find_map(|l| {
                let (k, v) = l.split_once(':')?;
                k.eq_ignore_ascii_case("content-length")
                    .then(|| v.trim().parse().ok())
                    .flatten()
            })
            .unwrap();
        let mut body_bytes = raw[header_end + 4..].to_vec();
        while body_bytes.len() < content_len {
            let mut tmp = vec![0u8; content_len - body_bytes.len()];
            let n = socket.read(&mut tmp).await.unwrap();
            assert!(n > 0);
            body_bytes.extend_from_slice(&tmp[..n]);
        }
        let json_body = serde_json::from_slice(&body_bytes).unwrap();
        captured_bodies.push(json_body);

        let sse: String = frames
            .into_iter()
            .map(|frame| format!("data: {frame}\n\n"))
            .collect();
        let resp = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nx-goog-request-id: goog-req-{step}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{sse}",
            sse.len()
        );
        socket.write_all(resp.as_bytes()).await.unwrap();
    }
    captured_bodies
}

#[tokio::test]
async fn runtime_replays_single_gemini_tool_with_empty_id_over_mock_http() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!(
        "http://{}/v1/publishers/google",
        listener.local_addr().unwrap()
    );
    let original_call = json!({
        "functionCall":{"name":"lookup","args":{"q":"hi"},"id":""},
        "thoughtSignature":"SIG_XYZ",
    });
    let server = tokio::spawn(serve_gemini_sse(
        listener,
        vec![
            vec![
                json!({"candidates":[{"content":{"role":"model","parts":[{"text":"Checking tool","thought":true}]}}],
                "modelVersion":"gemini-4-hydrogen","responseId":"g-1"}),
                json!({"candidates":[{"content":{"role":"model","parts":[original_call]},"finishReason":"STOP"}],
                "usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":4,"thoughtsTokenCount":6,"totalTokenCount":22}}),
            ],
            vec![
                json!({"candidates":[{"content":{"role":"model","parts":[{"text":"All done."}]},"finishReason":"STOP"}],
            "usageMetadata":{"promptTokenCount":20,"candidatesTokenCount":3,"thoughtsTokenCount":0,"totalTokenCount":23}}),
            ],
        ],
    ));

    let bundled = bundled_model_definition("vertex-ai").unwrap();
    let model = bundled
        .models
        .into_iter()
        .find(|m| m.base.slug == "gemini-4-hydrogen")
        .unwrap();
    assert_eq!(
        model.extra.binding.transport.protocol,
        WireApi::GeminiGenerateContent
    );

    let mut ep = vertex_endpoint(Some(base));
    ep.bearer_token = Some("gcp-secret".into());
    let runtime = new_with_account_id("acct-vertex", ep, model).unwrap();

    // 1x1 PNG bytes
    let png_bytes = STANDARD
        .decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=")
        .unwrap();

    let mut req = CompletionRequest::builder()
        .system_prompt(SystemPrompt::new("System rule"))
        .messages(vec![Message {
            role: MessageRole::User,
            content: MessageContent::new(vec![
                ContentPart::Text {
                    text: "Inspect image and run lookup".into(),
                },
                ContentPart::Attachment {
                    attachment_id: "img1".into(),
                    modality: AttachmentModality::Image,
                    media_type: "image/png".into(),
                    filename: Some("dot.png".into()),
                },
            ]),
            presentation: Default::default(),
            reasoning_content: None,
            tool_calls: None,
            tool_result: None,
            metadata: Default::default(),
        }])
        .attachments(vec![AttachmentInput {
            attachment_id: "img1".into(),
            modality: AttachmentModality::Image,
            media_type: "image/png".into(),
            filename: Some("dot.png".into()),
            source: AttachmentSource::Bytes {
                bytes: png_bytes.into(),
            },
        }])
        .tools(vec![ToolSpec::Function {
            name: "lookup".into(),
            description: "Lookup something".into(),
            input_schema: json!({
                "type": "object",
                "properties": {"q": {"type": "string"}},
                "required": ["q"]
            }),
            allowed_callers: Vec::new(),
            output_schema: None,
        }])
        .reasoning(Some(ReasoningConfig {
            effort: Some("low".into()),
            summary: None,
        }))
        .build();

    let ctx = ModelInvocationContext::default();
    let resp1 = runtime.complete(req.clone(), ctx.clone()).await.unwrap();
    assert_eq!(resp1.tool_calls.len(), 1);
    let call = &resp1.tool_calls[0];
    assert_eq!(call.name, "lookup");
    assert!(!call.call_id.is_empty());
    let Some(AssistantReplay::Gemini { parts }) = resp1.replay.as_ref() else {
        panic!("expected Gemini replay");
    };
    assert_eq!(parts[1], original_call);
    assert_eq!(resp1.accounting.usage.output_tokens, Some(10));
    assert_eq!(resp1.accounting.usage.reasoning_tokens, Some(6));
    assert_eq!(resp1.accounting.usage.cache_read_tokens, Some(0));
    assert!(matches!(
        resp1.accounting.pricing,
        PricingOutcome::Estimated { .. }
    ));

    let isolation = pl_model::runtime::binding_cache_namespace("acct-vertex", runtime.endpoint());
    req.append_response_from(&resp1, Some(&isolation)).unwrap();
    req.input
        .push(pl_model::completion::ModelContextItem::ToolResult {
            message: Message {
                role: MessageRole::Tool,
                content: MessageContent::text("found item"),
                presentation: Default::default(),
                reasoning_content: None,
                tool_calls: None,
                tool_result: Some(ToolResultRecord {
                    item_id: call.id.clone(),
                    call_id: call.call_id.clone(),
                    name: "lookup".into(),
                    kind: ToolCallKind::Function,
                }),
                metadata: Default::default(),
            },
            receipt: ToolResultReceipt {
                call_id: call.call_id.clone(),
                tool_name: "lookup".into(),
                arguments_hash: "h1".into(),
                result_hash: "h2".into(),
                total_bytes: 10,
                visible_bytes: 10,
                truncated: false,
                artifacts: Vec::new(),
                continuation: None,
                reused_from_call_id: None,
            },
        });

    let resp2 = runtime.complete(req, ctx).await.unwrap();
    assert_eq!(resp2.content.as_deref(), Some("All done."));

    let captured = tokio::time::timeout(Duration::from_secs(5), server)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        captured[0]["contents"][0]["parts"][1]["inlineData"]["mimeType"],
        "image/png"
    );
    assert_eq!(
        captured[0]["generationConfig"]["thinkingConfig"]["thinkingLevel"],
        "low"
    );
    assert_eq!(captured[1]["contents"][1]["parts"][1], original_call);
    assert_eq!(
        captured[1]["contents"][2]["parts"][0],
        json!({"functionResponse":{"name":"lookup","response":{"result":"found item"}}}),
    );
}

#[tokio::test]
async fn runtime_recovers_malformed_gemini_response_without_replaying_failed_output() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}/v1beta", listener.local_addr().unwrap());
    let server = tokio::spawn(serve_gemini_sse(
        listener,
        vec![
            vec![
                json!({"responseId":"failed","candidates":[{"content":{"role":"model","parts":[
                    {"text":"discard this answer"},
                    {"functionCall":{"name":"lookup","args":{"q":"discard"}},"thoughtSignature":"FAILED_CALL"}
                ]}}]}),
                json!({"candidates":[{"content":{"role":"model","parts":[
                    {"text":"","thoughtSignature":"FAILED_TAIL"}
                ]},"finishReason":"MALFORMED_RESPONSE"}],
                "usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":4,"thoughtsTokenCount":6,"totalTokenCount":22}}),
            ],
            vec![
                json!({"responseId":"recovered","candidates":[{"content":{"role":"model","parts":[
                {"text":"Recovered answer","thoughtSignature":"SUCCESS"}
            ]},"finishReason":"STOP"}],
            "usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":3,"totalTokenCount":15}}),
            ],
        ],
    ));
    let mut endpoint = gemini_api_endpoint(Some(base));
    endpoint.bearer_token = Some("gcp-secret".into());
    let model = bundled_model_definition("gemini").unwrap().models.remove(0);
    let runtime = new_with_account_id("acct-gemini", endpoint, model).unwrap();
    let response = tokio::time::timeout(
        Duration::from_secs(10),
        runtime.complete(
            CompletionRequest::builder().build(),
            ModelInvocationContext::default(),
        ),
    )
    .await
    .unwrap()
    .expect("a malformed generation must recover within the existing retry budget");
    assert_eq!(response.content.as_deref(), Some("Recovered answer"));
    assert!(
        response.tool_calls.is_empty(),
        "failed-generation calls must never execute"
    );
    assert_eq!(response.response_id.as_deref(), Some("recovered"));
    assert_eq!(response.orchestration.transport_attempts, 2);
    assert_eq!(response.observation.generation, 1);
    assert_eq!(response.observation.failed.len(), 1);
    assert!(
        response.observation.failed[0]
            .message
            .contains("MALFORMED_RESPONSE")
    );
    assert_eq!(response.accounting.usage.output_tokens, Some(3));
    assert_eq!(response.accounting.retry_attempts.len(), 1);
    assert_eq!(
        response.accounting.retry_attempts[0].usage.output_tokens,
        Some(10)
    );
    assert_eq!(response.accounting.usage.total_tokens, Some(15));
    assert_eq!(
        response.accounting.retry_attempts[0].usage.total_tokens,
        Some(22)
    );
    assert!((response.accounting.estimated_costs()[0].amount - 0.0000405).abs() < 1e-12);
    assert!(
        (response.accounting.retry_attempts[0].estimated_costs()[0].amount - 0.000093).abs()
            < 1e-12
    );
    let restored: pl_model::model::InferenceAccounting =
        serde_json::from_value(serde_json::to_value(&response.accounting).unwrap()).unwrap();
    assert_eq!(restored, response.accounting);
    let mut followup = CompletionRequest::builder().build();
    response
        .replay
        .as_ref()
        .expect("successful replay")
        .semantic_input(&response)
        .unwrap();
    followup.append_response_from(&response, None).unwrap();
    let serialized = serde_json::to_string(&response.replay).unwrap();
    assert!(!serialized.contains("FAILED_"));
    assert!(!serialized.contains("discard"));
    let bodies = tokio::time::timeout(Duration::from_secs(5), server)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(bodies.len(), 2);
    assert_eq!(
        bodies[0], bodies[1],
        "recovery resends the frozen input only"
    );
}

#[tokio::test]
async fn malformed_gemini_recovery_respects_retry_budget_and_cancellation() {
    use pl_model::completion::stream::event::ModelStreamEvent;
    use pl_model::runtime::CancellationToken;

    for cancel in [false, true] {
        let attempts = if cancel { 1 } else { 6 };
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}/v1beta", listener.local_addr().unwrap());
        let frame = json!({"candidates":[{"finishReason":"MALFORMED_RESPONSE"}],
            "usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":4,"thoughtsTokenCount":6,"totalTokenCount":22}});
        let server = tokio::spawn(serve_gemini_sse(listener, vec![vec![frame]; attempts]));
        let mut endpoint = gemini_api_endpoint(Some(base));
        endpoint.bearer_token = Some("gcp-secret".into());
        let model = bundled_model_definition("gemini").unwrap().models.remove(0);
        let runtime = new_with_account_id("acct-gemini", endpoint, model).unwrap();
        let cancellation = CancellationToken::new();
        let observer_token = cancellation.clone();
        let context = ModelInvocationContext::default()
            .with_cancellation(Some(cancellation))
            .with_stream_observer(move |_, event| {
                if cancel && matches!(event, ModelStreamEvent::Failed { .. }) {
                    observer_token.cancel();
                }
            });
        let failure = tokio::time::timeout(
            Duration::from_secs(30),
            runtime.complete(CompletionRequest::builder().build(), context),
        )
        .await
        .unwrap()
        .unwrap_err();
        assert_eq!(failure.is_cancelled(), cancel);
        assert_eq!(failure.accounting.retry_attempts.len(), attempts - 1);
        assert_eq!(
            failure
                .accounting
                .retry_attempts
                .iter()
                .chain(std::iter::once(failure.accounting.as_ref()))
                .map(|accounting| accounting.usage.total_tokens)
                .sum::<Option<u64>>(),
            Some(22 * attempts as u64)
        );
        if !cancel {
            let source = failure.source.provider_failure_ref().unwrap();
            assert_eq!(source.code.as_deref(), Some("MALFORMED_RESPONSE"));
            assert_eq!(source.context.request_id.as_deref(), Some("goog-req-5"));
            assert!(source.retry.is_retryable());
            assert_eq!(
                failure
                    .partial_progress
                    .as_ref()
                    .unwrap()
                    .observation()
                    .recovery
                    .unwrap()
                    .phase,
                pl_core::model::ModelRecoveryPhase::Exhausted
            );
        }
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(5), server)
                .await
                .unwrap()
                .unwrap()
                .len(),
            attempts
        );
    }
}

#[tokio::test]
async fn other_gemini_finish_reasons_keep_their_terminal_failure_and_usage() {
    for reason in [
        "SAFETY",
        "MAX_TOKENS",
        "MALFORMED_FUNCTION_CALL",
        "UNKNOWN_REASON",
    ] {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}/v1beta", listener.local_addr().unwrap());
        let server = tokio::spawn(serve_gemini_sse(
            listener,
            vec![vec![json!({"candidates":[{"finishReason":reason}],
                "usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":4,"totalTokenCount":16}})]],
        ));
        let mut endpoint = gemini_api_endpoint(Some(base));
        endpoint.bearer_token = Some("gcp-secret".into());
        let model = bundled_model_definition("gemini").unwrap().models.remove(0);
        let runtime = new_with_account_id("acct-gemini", endpoint, model).unwrap();
        let failure = runtime
            .complete(
                CompletionRequest::builder().build(),
                ModelInvocationContext::default(),
            )
            .await
            .unwrap_err();
        let source = failure.source.provider_failure_ref().unwrap();
        assert_eq!(source.code.as_deref(), Some(reason));
        assert!(!source.retry.is_retryable());
        assert!(failure.accounting.retry_attempts.is_empty());
        assert_eq!(failure.accounting.usage.total_tokens, Some(16));
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(5), server)
                .await
                .unwrap()
                .unwrap()
                .len(),
            1
        );
    }
}

#[tokio::test]
async fn runtime_rejects_gemini_error_received_after_stop_with_tool_call() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}/v1beta", listener.local_addr().unwrap());
    let server = tokio::spawn(serve_gemini_sse(
        listener,
        vec![vec![
            json!({"candidates":[{"content":{"role":"model","parts":[
                {"functionCall":{"name":"lookup","args":{"q":"ready"},"id":"call-1"}},
            ]},"finishReason":"STOP"}]}),
            json!({"error":{"code":400,"status":"INVALID_ARGUMENT","message":"late stream error"}}),
        ]],
    ));
    let mut endpoint = gemini_api_endpoint(Some(base));
    endpoint.bearer_token = Some("gcp-secret".into());
    let model = bundled_model_definition("gemini")
        .unwrap()
        .models
        .into_iter()
        .find(|model| model.base.slug == "gemini-4-hydrogen")
        .unwrap();
    let runtime = new_with_account_id("acct-gemini", endpoint, model).unwrap();
    let request = CompletionRequest::builder().build();

    let error = runtime
        .complete(request, ModelInvocationContext::default())
        .await
        .unwrap_err();
    assert!(error.to_string().contains("late stream error"), "{error}");
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(5), server)
            .await
            .unwrap()
            .unwrap()
            .len(),
        1
    );
}

#[tokio::test]
async fn thread_gemini_replays_parallel_results_in_part_order_across_steps() {
    use pl_core::{
        context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource},
        model::{ModelFactory, ModelRequest, ModelToolDeclaration, ToolCallMode},
    };
    use pl_model::runtime::{ThreadModel, model_response_receipt, thread_tool_declaration};
    use std::sync::Arc;

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}/v1beta", listener.local_addr().unwrap());
    let first = json!({
        "functionCall":{"name":"lookup","args":{"q":"first"},"id":"provider-1"},
        "thoughtSignature":"SIG_STEP_1",
        "future":{"keep":[1,2]},
    });
    let second = json!({"functionCall":{"name":"lookup","args":{"q":"second"}}});
    let third = json!({"functionCall":{"name":"lookup","args":{"q":"third"},"id":""}});
    let fourth =
        json!({"functionCall":{"name":"lookup","args":{"q":"fourth"},"id":"gemini_noid:2"}});
    let tail = json!({"text":"","thoughtSignature":"SIG_TAIL"});
    let next = json!({
        "functionCall":{"name":"lookup","args":{"q":"next"},"id":"provider-1"},
        "thoughtSignature":"SIG_STEP_2",
    });
    let server = tokio::spawn(serve_gemini_sse(
        listener,
        vec![
            vec![
                json!({"candidates":[{"content":{"role":"model","parts":[first,second]}}]}),
                json!({"candidates":[{"content":{"role":"model","parts":[third,fourth]}}]}),
                json!({"candidates":[{"content":{"role":"model","parts":[tail]},"finishReason":"STOP"}]}),
            ],
            vec![
                json!({"candidates":[{"content":{"role":"model","parts":[next]},"finishReason":"STOP"}]}),
            ],
            vec![
                json!({"candidates":[{"content":{"role":"model","parts":[{"text":"Verified."}]},"finishReason":"STOP"}]}),
            ],
        ],
    ));

    let mut endpoint = gemini_api_endpoint(Some(base));
    endpoint.bearer_token = Some("gcp-secret".into());
    let model = bundled_model_definition("gemini")
        .unwrap()
        .models
        .into_iter()
        .find(|model| model.base.slug == "gemini-4-hydrogen")
        .unwrap();
    let runtime = new_with_account_id("acct-gemini", endpoint, model).unwrap();
    let mut session = ModelFactory::new(ThreadModel::new(runtime, None))
        .open_session()
        .await
        .unwrap();
    let lookup = ToolSpec::Function {
        name: "lookup".into(),
        description: "Lookup something".into(),
        input_schema: json!({
            "type":"object","properties":{"q":{"type":"string"}},"required":["q"],
        }),
        allowed_callers: Vec::new(),
        output_schema: None,
    };
    let tools: Arc<[ModelToolDeclaration]> = vec![ModelToolDeclaration {
        tool_id: "lookup-executor".into(),
        declaration: thread_tool_declaration(&lookup).unwrap(),
        presentation_contract: None,
    }]
    .into();
    let mut records = vec![ContextRecord {
        id: "input".into(),
        turn_id: Some("turn".into()),
        source: ContextSource::User,
        content: vec![ContextContent::Text {
            text: "Look up the values.".into(),
        }],
        tool_calls: Vec::new(),
    }];
    let mut internal_ids = std::collections::BTreeSet::new();
    for (index, (attempt, queries)) in [
        (
            "00000000-0000-4000-8000-000000000001",
            &["first", "second", "third", "fourth"][..],
        ),
        ("00000000-0000-4000-8000-000000000002", &["next"][..]),
        ("00000000-0000-4000-8000-000000000003", &[][..]),
    ]
    .into_iter()
    .enumerate()
    {
        let output = session
            .prepare(ModelRequest {
                thread_id: "gemini-thread".into(),
                turn_id: "turn".into(),
                attempt_id: attempt.into(),
                context: ContextSnapshot {
                    revision: index as u64,
                    records: records.clone().into(),
                },
                tools: tools.clone(),
                tool_call_mode: ToolCallMode::Parallel,
                solo_tool_ids: Default::default(),
                committed_private_context: None,
                resources: None,
                cancellation: Default::default(),
                progress: None,
                members: None,
            })
            .await
            .unwrap()
            .execute()
            .await
            .unwrap();
        assert_eq!(output.tool_calls.len(), queries.len());
        let receipt = model_response_receipt(&output).unwrap().unwrap();
        if queries.is_empty() {
            assert_eq!(receipt.response.content.as_deref(), Some("Verified."));
            break;
        }
        let mut results = Vec::new();
        for (binding, query) in output.tool_calls.iter().zip(queries) {
            assert_eq!(binding.tool_id, "lookup-executor");
            assert!(binding.rejection.is_none(), "lookup {query} was rejected");
            assert_eq!(
                serde_json::from_str::<Value>(binding.arguments.content()).unwrap(),
                json!({"q":query}),
            );
            assert!(internal_ids.insert(binding.call_id.clone()));
            results.push(ContextRecord {
                id: format!("{attempt}:{query}"),
                turn_id: Some("turn".into()),
                source: ContextSource::ToolResult {
                    call_id: binding.call_id.clone(),
                    tool_id: binding.tool_id.clone(),
                },
                content: vec![ContextContent::Text {
                    text: format!("result {query}").into(),
                }],
                tool_calls: Vec::new(),
            });
        }
        records.push(ContextRecord {
            id: format!("{attempt}:output"),
            turn_id: Some("turn".into()),
            source: ContextSource::Assistant,
            content: output.content,
            tool_calls: output.tool_calls,
        });
        records.extend(results.into_iter().rev());
    }

    let captured = tokio::time::timeout(Duration::from_secs(5), server)
        .await
        .unwrap()
        .unwrap();
    let batch = json!([
        {"role":"model","parts":[first,second,third,fourth,tail]},
        {"role":"user","parts":[
            {"functionResponse":{"name":"lookup","id":"provider-1","response":{"result":"result first"}}},
            {"functionResponse":{"name":"lookup","response":{"result":"result second"}}},
            {"functionResponse":{"name":"lookup","response":{"result":"result third"}}},
            {"functionResponse":{"name":"lookup","id":"gemini_noid:2","response":{"result":"result fourth"}}},
        ]},
    ]);
    let continuation = captured[1]["contents"].as_array().unwrap();
    assert_eq!(&continuation[1..], batch.as_array().unwrap());
    let final_request = captured[2]["contents"].as_array().unwrap();
    assert_eq!(&final_request[..continuation.len()], continuation);
    assert_eq!(
        &final_request[continuation.len()..],
        [
            json!({"role":"model","parts":[next]}),
            json!({"role":"user","parts":[
                {"functionResponse":{"name":"lookup","id":"provider-1","response":{"result":"result next"}}},
            ]}),
        ]
    );
}

#[tokio::test]
async fn gemini_online_discovery_applies_256k_fallback_only_for_unbundled_models() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}/v1beta", listener.local_addr().unwrap());
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        let mut buf = Vec::new();
        while !buf.ends_with(b"\r\n\r\n") {
            buf.push(socket.read_u8().await.unwrap());
            assert!(buf.len() < 16384);
        }
        let body = json!({
            "models": [
                {
                    "name": "models/gemini-4-hydrogen",
                    "displayName": "Gemini 4 Hydrogen",
                    "supportedGenerationMethods": ["generateContent"],
                    "inputTokenLimit": 1048576,
                    "outputTokenLimit": 65536
                },
                {
                    "name": "models/gemini-4.5-preview",
                    "displayName": "Gemini 4.5 Preview",
                    "supportedGenerationMethods": ["generateContent"],
                    "inputTokenLimit": 1048576,
                    "outputTokenLimit": 65536
                },
                {
                    "name": "models/gemini-mini-preview",
                    "displayName": "Gemini Mini Preview",
                    "supportedGenerationMethods": ["generateContent"],
                    "inputTokenLimit": 128000,
                    "outputTokenLimit": 8192
                },
                {
                    "name": "models/gemini-unknown-preview",
                    "displayName": "Gemini Unknown Preview",
                    "supportedGenerationMethods": ["generateContent"]
                }
            ]
        })
        .to_string();
        let resp = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        socket.write_all(resp.as_bytes()).await.unwrap();
    });

    let mut ep = gemini_api_endpoint(Some(base));
    ep.bearer_token = Some("test-goog-secret".into());
    let mut account =
        AccountConfig::from_bundled_catalog(ep, ModelCatalogId::new("gemini").unwrap(), Vec::new());
    let result = ModelCatalogQuery::for_account(&account)
        .unwrap()
        .execute(None)
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(5), server)
        .await
        .unwrap()
        .unwrap();

    let ModelCatalogQueryResult::Updated { models, .. } = result else {
        panic!("expected Updated");
    };
    account.set_model_catalog_overlay(models).unwrap();

    let mut cfg = AgentModelConfig {
        accounts: [(AccountId::new("gemini").unwrap(), account)].into(),
        routes: std::collections::BTreeMap::new(),
    };
    for phase in ["direct", "reconciled"] {
        if phase == "reconciled" {
            cfg.reconcile_model_catalog().unwrap();
        }
        let entries = cfg.accounts[&AccountId::new("gemini").unwrap()]
            .effective_catalog(None)
            .unwrap();
        let by_id = |id: &str| {
            entries
                .iter()
                .find(|entry| entry.model.base.slug == id)
                .unwrap_or_else(|| panic!("missing {id} in {phase}"))
                .clone()
        };
        assert_eq!(
            by_id("gemini-4-hydrogen").context.auto_compact_limit,
            Some(512_000),
            "{phase}"
        );
        assert_eq!(
            by_id("gemini-4.5-preview").context.auto_compact_limit,
            Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT),
            "{phase}"
        );
        assert_eq!(
            by_id("gemini-mini-preview").context.auto_compact_limit,
            Some(115_200),
            "{phase}"
        );
        let unknown = by_id("gemini-unknown-preview");
        assert_eq!(unknown.context.context_window, None, "{phase}");
        assert_eq!(
            unknown.context.auto_compact_limit,
            Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT),
            "{phase}"
        );
    }

    let account = cfg
        .accounts
        .get_mut(&AccountId::new("gemini").unwrap())
        .unwrap();
    account
        .set_model_auto_compact_override("gemini-4.5-preview", Some(943_718))
        .unwrap();
    assert_eq!(
        account
            .effective_catalog(None)
            .unwrap()
            .into_iter()
            .find(|entry| entry.model.base.slug == "gemini-4.5-preview")
            .unwrap()
            .context
            .auto_compact_limit,
        Some(943_718)
    );
    account
        .set_model_auto_compact_override("gemini-4.5-preview", None)
        .unwrap();
    assert_eq!(
        account
            .effective_catalog(None)
            .unwrap()
            .into_iter()
            .find(|entry| entry.model.base.slug == "gemini-4.5-preview")
            .unwrap()
            .context
            .auto_compact_limit,
        Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT)
    );
}
