//! Integration tests for Gemini / Vertex AI catalog composition, paginated discovery and runtime execution.

use base64::{Engine, engine::general_purpose::STANDARD};
use pl_model::{
    completion::{
        AttachmentInput, AttachmentModality, AttachmentSource, CompletionRequest, ContentPart,
        Message, MessageContent, MessageRole, ReasoningConfig, SystemPrompt, ToolCallKind,
        ToolResultReceipt, ToolResultRecord, ToolSpec,
    },
    config::{AccountConfig, AccountModelCatalogConfig, ModelCatalogId, builtin_account_catalog},
    model::{PricingOutcome, bundled_model_definition, bundled_selection_guide},
    protocol::{
        WireApi,
        discovery::{ModelCatalogQuery, ModelCatalogQueryError, ModelCatalogQueryResult},
        providers::gemini::{gemini_api_endpoint, vertex_endpoint},
    },
    runtime::{ModelInvocationContext, new_with_account_id},
};
use serde_json::json;
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
        hydrogen.resolve_context(None).auto_compact_limit,
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
        carbon.resolve_context(None).auto_compact_limit,
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

#[tokio::test]
async fn runtime_executes_gemini_multimodal_tool_roundtrip_over_mock_http() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!(
        "http://{}/v1/publishers/google",
        listener.local_addr().unwrap()
    );

    let server = tokio::spawn(async move {
        let mut captured_bodies = Vec::new();
        for step in 0..2 {
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
            let json_body: serde_json::Value = serde_json::from_slice(&body_bytes).unwrap();
            captured_bodies.push(json_body);

            let sse = if step == 0 {
                concat!(
                    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"Checking tool\",\"thought\":true}]}}],\"modelVersion\":\"gemini-4-hydrogen\",\"responseId\":\"g-1\"}\n\n",
                    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"lookup\",\"args\":{\"q\":\"hi\"},\"id\":\"call_abc\"},\"thoughtSignature\":\"SIG_XYZ\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":12,\"candidatesTokenCount\":4,\"thoughtsTokenCount\":6,\"totalTokenCount\":22}}\n\n"
                )
            } else {
                "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"All done.\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":20,\"candidatesTokenCount\":3,\"thoughtsTokenCount\":0,\"totalTokenCount\":23}}\n\n"
            };
            let resp = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nx-goog-request-id: goog-req-{step}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{sse}",
                sse.len()
            );
            socket.write_all(resp.as_bytes()).await.unwrap();
        }
        captured_bodies
    });

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
    assert_eq!(resp1.tool_calls[0].name, "lookup");
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
                    item_id: "call_abc".into(),
                    call_id: "call_abc".into(),
                    name: "lookup".into(),
                    kind: ToolCallKind::Function,
                }),
                metadata: Default::default(),
            },
            receipt: ToolResultReceipt {
                call_id: "call_abc".into(),
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
    // Second turn must replay thoughtSignature verbatim and send matching functionResponse id
    assert_eq!(
        captured[1]["contents"][1]["parts"][1]["thoughtSignature"],
        "SIG_XYZ"
    );
    assert_eq!(
        captured[1]["contents"][2]["parts"][0]["functionResponse"]["id"],
        "call_abc"
    );
}
