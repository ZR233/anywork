use pl_model_gemini::{GEMINI_WIRE_CODEC, bundled_definition, endpoint};
use pl_model_wire::completion::{
    AssistantReplay, AttachmentModality, AttachmentRepresentation, CompletionRequest,
    CompletionResponse, ContentPart, Message, MessageContent, MessageRole, ModelContextItem,
    ReasoningConfig, ResolvedAttachment, SystemPrompt, ToolCall, ToolCallKind, ToolResultReceipt,
    ToolResultRecord, ToolSpec,
    stream::{event::ModelStreamEvent, replay::ReplayCollector},
};
use pl_model_wire::model::{InferenceAccounting, ModelProtocolOptions};
use pl_model_wire::wire_codec::{EncodeHttpRequestInput, WireCodec};
use serde_json::json;

#[test]
fn request_encodes_multimodal_inline_data_and_coalesces_parallel_tool_results() {
    let bundled = bundled_definition().unwrap();
    let model = bundled
        .models
        .iter()
        .find(|m| m.base.slug == "gemini-3.7-flash")
        .unwrap()
        .clone();
    let ep = endpoint::vertex_endpoint(None);

    let mut req = CompletionRequest::builder()
        .system_prompt(SystemPrompt::new("Be concise."))
        .tools(vec![ToolSpec::Function {
            name: "read_file".into(),
            description: "Read a file".into(),
            input_schema: json!({
                "type": "object",
                "properties": { "path": { "type": "string" } },
                "required": ["path"]
            }),
            allowed_callers: Vec::new(),
            output_schema: None,
        }])
        .reasoning(Some(ReasoningConfig {
            effort: Some("high".into()),
            summary: None,
        }))
        .build();

    req.input.push(ModelContextItem::Message {
        message: Message {
            role: MessageRole::User,
            content: MessageContent::new(vec![
                ContentPart::Text {
                    text: "Check both files and this image.".into(),
                },
                ContentPart::Attachment {
                    attachment_id: "att-img".into(),
                    modality: AttachmentModality::Image,
                    media_type: "image/png".into(),
                    filename: Some("a.png".into()),
                },
                ContentPart::Attachment {
                    attachment_id: "att-pdf".into(),
                    modality: AttachmentModality::File,
                    media_type: "application/pdf".into(),
                    filename: Some("b.pdf".into()),
                },
            ]),
            presentation: Default::default(),
            reasoning_content: None,
            tool_calls: None,
            tool_result: None,
            metadata: Default::default(),
        },
    });
    req.prepared_content = vec![
        ResolvedAttachment {
            attachment_id: "att-img".into(),
            modality: AttachmentModality::Image,
            media_type: "image/png".into(),
            filename: Some("a.png".into()),
            sources: vec![AttachmentRepresentation::DataUrl {
                base64: "AAAA".into(),
            }],
        },
        ResolvedAttachment {
            attachment_id: "att-pdf".into(),
            modality: AttachmentModality::File,
            media_type: "application/pdf".into(),
            filename: Some("b.pdf".into()),
            sources: vec![AttachmentRepresentation::DataUrl {
                base64: "BBBB".into(),
            }],
        },
    ];

    let resp = CompletionResponse {
        response_id: Some("r1".into()),
        content: None,
        replay: Some(AssistantReplay::Gemini {
            parts: vec![
                json!({"text": "thinking", "thought": true}),
                json!({
                    "functionCall": {"name": "read_file", "args": {"path": "a.txt"}, "id": "call_1"},
                    "thoughtSignature": "SIG_1"
                }),
                json!({
                    "functionCall": {"name": "read_file", "args": {"path": "b.txt"}}
                }),
            ],
        }),
        reasoning_content: Some("thinking".into()),
        tool_calls: vec![
            ToolCall::function("call_1", "read_file", json!({"path": "a.txt"}), "call_1"),
            ToolCall::function(
                "gemini_noid:2",
                "read_file",
                json!({"path": "b.txt"}),
                "gemini_noid:2",
            ),
        ],
        responses_context_items: Vec::new(),
        presentation_items: Vec::new(),
        orchestration: Default::default(),
        timing: None,
        accounting: InferenceAccounting::default(),
        model: "gemini-3.7-flash".into(),
        model_observation: None,
        observation: Default::default(),
    };
    req.append_response_from(&resp, Some("acct:gemini:1"))
        .unwrap();

    for (id, text) in [("call_1", "content A"), ("gemini_noid:2", "content B")] {
        req.input.push(ModelContextItem::ToolResult {
            message: Message {
                role: MessageRole::Tool,
                content: MessageContent::text(text),
                presentation: Default::default(),
                reasoning_content: None,
                tool_calls: None,
                tool_result: Some(ToolResultRecord {
                    item_id: id.into(),
                    call_id: id.into(),
                    name: "read_file".into(),
                    kind: ToolCallKind::Function,
                }),
                metadata: Default::default(),
            },
            receipt: ToolResultReceipt {
                call_id: id.into(),
                tool_name: "read_file".into(),
                arguments_hash: "a".into(),
                result_hash: "b".into(),
                total_bytes: 9,
                visible_bytes: 9,
                truncated: false,
                artifacts: Vec::new(),
                continuation: None,
                reused_from_call_id: None,
            },
        });
    }

    let prepared = GEMINI_WIRE_CODEC
        .encode_http_request(EncodeHttpRequestInput {
            endpoint: &ep,
            model: &model,
            request: &req,
            prompt_cache_key: None,
            compaction_body: None,
            is_compaction: false,
        })
        .unwrap();

    assert_eq!(
        prepared.path_and_query,
        "/models/gemini-3.7-flash:streamGenerateContent?alt=sse"
    );
    assert!(prepared.body.get("model").is_none());
    assert_eq!(
        prepared.body["generationConfig"]["thinkingConfig"]["thinkingLevel"],
        "high"
    );
    assert_eq!(
        prepared.body["generationConfig"]["thinkingConfig"]["includeThoughts"],
        true
    );
    assert_eq!(
        prepared.body["tools"][0]["functionDeclarations"][0]["parametersJsonSchema"]["type"],
        "object"
    );

    let contents = prepared.body["contents"].as_array().unwrap();
    assert_eq!(contents.len(), 3);
    // User multimodal turn
    let user_parts = contents[0]["parts"].as_array().unwrap();
    assert_eq!(user_parts[1]["inlineData"]["mimeType"], "image/png");
    assert_eq!(user_parts[1]["inlineData"]["data"], "AAAA");
    assert_eq!(user_parts[2]["inlineData"]["mimeType"], "application/pdf");
    assert_eq!(user_parts[2]["inlineData"]["data"], "BBBB");
    // Model replay turn preserves thoughtSignature intact
    let model_parts = contents[1]["parts"].as_array().unwrap();
    assert_eq!(model_parts[1]["thoughtSignature"], "SIG_1");
    // Parallel tool results coalesced into one user turn; synthetic gemini_noid id omitted
    assert_eq!(contents[2]["role"], "user");
    let fr_parts = contents[2]["parts"].as_array().unwrap();
    assert_eq!(fr_parts.len(), 2);
    assert_eq!(fr_parts[0]["functionResponse"]["id"], "call_1");
    assert!(fr_parts[1]["functionResponse"].get("id").is_none());
}

#[test]
fn sse_decoder_preserves_trailing_thought_signature_and_tool_calls() {
    let mut decoder = GEMINI_WIRE_CODEC
        .new_stream_decoder(pl_model_wire::protocol::WireApi::GeminiGenerateContent);
    let mut collector = ReplayCollector::default();

    let frames = [
        r#"{"candidates":[{"content":{"role":"model","parts":[{"text":"Let me think.","thought":true}]}}],"usageMetadata":{"trafficType":"ON_DEMAND"},"modelVersion":"gemini-3-flash-preview","responseId":"resp-1"}"#,
        r#"{"candidates":[{"content":{"role":"model","parts":[{"text":"Hello!"}]}}]}"#,
        r#"{"candidates":[{"content":{"role":"model","parts":[{"text":"","thoughtSignature":"SIG_TAIL"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"thoughtsTokenCount":7,"totalTokenCount":22}}"#,
    ];

    let mut saw_usage = None;
    for frame in frames {
        let decoded = decoder
            .decode_frame(frame, Some("goog-req-1"), &|s| s.to_owned())
            .unwrap();
        for ev in decoded.events {
            match ev {
                ModelStreamEvent::Replay(u) => collector.apply(u).unwrap(),
                ModelStreamEvent::Usage(u) => saw_usage = Some(u),
                _ => {}
            }
        }
    }
    let tail = decoder.finish();
    assert!(
        tail.iter()
            .any(|e| matches!(e, ModelStreamEvent::Completed { .. }))
    );

    let replay = collector.finish().unwrap().unwrap();
    assert!(replay.has_opaque_provider_state());
    let AssistantReplay::Gemini { parts } = replay else {
        panic!("expected Gemini replay");
    };
    assert_eq!(parts.len(), 3);
    assert_eq!(parts[2]["thoughtSignature"], "SIG_TAIL");
    let usage = saw_usage.unwrap();
    assert_eq!(usage.input_tokens, Some(10));
    assert_eq!(usage.output_tokens, Some(12));
    assert_eq!(usage.reasoning_tokens, Some(7));
}

#[test]
fn rejects_cross_owner_thought_signature_replay_and_invalid_model_path() {
    let bundled = bundled_definition().unwrap();
    let mut model = bundled.models[0].clone();
    let ep = endpoint::vertex_endpoint(None);
    let mut req = CompletionRequest::builder().build();
    let resp = CompletionResponse {
        response_id: None,
        content: Some("ok".into()),
        replay: Some(AssistantReplay::Gemini {
            parts: vec![json!({"text": "ok", "thoughtSignature": "SECRET_SIG"})],
        }),
        reasoning_content: None,
        tool_calls: Vec::new(),
        responses_context_items: Vec::new(),
        presentation_items: Vec::new(),
        orchestration: Default::default(),
        timing: None,
        accounting: InferenceAccounting::default(),
        model: "gemini-3.7-flash".into(),
        model_observation: None,
        observation: Default::default(),
    };
    req.append_response_from(&resp, Some("other-account:gemini:99"))
        .unwrap();
    assert!(
        GEMINI_WIRE_CODEC
            .validate_context(&ep, &model, "current-account", &req)
            .is_err()
    );

    model.extra.binding.request.api_model = Some("../evil/path".into());
    assert!(
        GEMINI_WIRE_CODEC
            .encode_http_request(EncodeHttpRequestInput {
                endpoint: &ep,
                model: &model,
                request: &CompletionRequest::builder().build(),
                prompt_cache_key: None,
                compaction_body: None,
                is_compaction: false,
            })
            .is_err()
    );
    assert!(matches!(
        model.extra.binding.request.protocol,
        ModelProtocolOptions::GeminiGenerateContent(_)
    ));
}
