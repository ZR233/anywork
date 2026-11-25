use pl_model_gemini::{GEMINI_WIRE_CODEC, bundled_definition, endpoint};
use pl_model_wire::completion::{
    AssistantReplay, AttachmentModality, AttachmentRepresentation, CompletionRequest,
    CompletionResponse, ContentPart, Message, MessageContent, MessageRole, ModelContextItem,
    ReasoningConfig, ResolvedAttachment, SystemPrompt, ThreadAttachment, ToolCall, ToolCallKind,
    ToolMediaContext, ToolResultReceipt, ToolResultRecord, ToolSpec,
    stream::{event::ModelStreamEvent, replay::ReplayCollector},
};
use pl_model_wire::model::{InferenceAccounting, ModelDefinition, ModelProtocolOptions};
use pl_model_wire::wire_codec::{EncodeHttpRequestInput, VisibleOutputProtocol, WireCodec};
use serde_json::{Value, json};

fn message(role: MessageRole, text: &str) -> Message {
    Message {
        role,
        content: MessageContent::text(text),
        presentation: Default::default(),
        reasoning_content: None,
        tool_calls: None,
        tool_result: None,
        metadata: Default::default(),
    }
}

fn lookup_result(item_id: &str, call_id: &str) -> Message {
    Message {
        tool_result: Some(ToolResultRecord {
            item_id: item_id.into(),
            call_id: call_id.into(),
            name: "lookup".into(),
            kind: ToolCallKind::Function,
        }),
        ..message(MessageRole::Tool, "result")
    }
}

#[test]
fn gemini_declares_tagged_union_fields_without_losing_branch_semantics() {
    let original = json!({"type":"object","$defs":{"Name":{"type":"string","minLength":1}},"oneOf":[
        {"type":"object","additionalProperties":false,
            "properties":{"action":{"type":"string","const":"create"},"name":{"$ref":"#/$defs/Name"},"content":{"type":"string"}},
            "required":["action","name","content"]},
        {"type":"object","additionalProperties":false,
            "properties":{"action":{"type":"string","const":"delete"},"name":{"$ref":"#/$defs/Name"}},
            "required":["action","name"]}
    ]});
    let model = bundled_definition().unwrap().models.remove(0);
    let endpoint = endpoint::gemini_api_endpoint(None);
    let mut request = CompletionRequest::builder()
        .messages(vec![message(MessageRole::User, "manage")])
        .tools(vec![ToolSpec::Function {
            name: "manage".into(),
            description: "Manage documents".into(),
            input_schema: original.clone(),
            allowed_callers: vec![],
            output_schema: None,
        }])
        .build();
    for (choice, expected_mode) in [("auto", "VALIDATED"), ("required", "ANY"), ("none", "NONE")] {
        request.tool_choice = choice.into();
        let encoded = GEMINI_WIRE_CODEC
            .encode_http_request(EncodeHttpRequestInput {
                endpoint: &endpoint,
                model: &model,
                request: &request,
                prompt_cache_key: None,
                compaction_body: None,
                is_compaction: false,
            })
            .unwrap();
        assert_eq!(
            encoded.body["toolConfig"]["functionCallingConfig"]["mode"],
            expected_mode
        );
        let schema = &encoded.body["tools"][0]["functionDeclarations"][0]["parametersJsonSchema"];
        assert_eq!(schema["required"], json!(["action", "name"]));
        assert_eq!(
            schema["properties"],
            json!({"action":{},"name":{},"content":{}})
        );
        assert_eq!(schema["oneOf"], original["oneOf"]);
        assert_eq!(schema["$defs"], original["$defs"]);
    }
    let ToolSpec::Function { input_schema, .. } = &request.tools[0] else {
        panic!("function")
    };
    assert_eq!(
        input_schema, &original,
        "the frozen author contract must stay unchanged"
    );
}

#[test]
fn gemini_refuses_root_unions_that_cannot_declare_equivalent_named_parameters() {
    let model = bundled_definition().unwrap().models.remove(0);
    let endpoint = endpoint::gemini_api_endpoint(None);
    for schema in [
        json!({"type":"object","oneOf":[{"type":"object","properties":{"value":{"type":"integer"}},"additionalProperties":true}]}),
        json!({"type":"object","oneOf":[{"type":"object","properties":{"value":{"type":"integer"}},"additionalProperties":false,"patternProperties":{"^x":{"type":"string"}}}]}),
        json!({"type":"object","additionalProperties":false,"oneOf":[{"type":"object","properties":{"value":{"type":"integer"}},"additionalProperties":false}]}),
    ] {
        let request = CompletionRequest::builder()
            .messages(vec![message(MessageRole::User, "manage")])
            .tools(vec![ToolSpec::Function {
                name: "manage".into(),
                description: "Manage documents".into(),
                input_schema: schema,
                allowed_callers: vec![],
                output_schema: None,
            }])
            .build();
        let error = GEMINI_WIRE_CODEC
            .encode_http_request(EncodeHttpRequestInput {
                endpoint: &endpoint,
                model: &model,
                request: &request,
                prompt_cache_key: None,
                compaction_body: None,
                is_compaction: false,
            })
            .unwrap_err();
        assert!(
            error.to_string().contains("closed object branches"),
            "{error}"
        );
    }
}

#[test]
fn google_rpc_stream_failures_preserve_protocol_classification() {
    use pl_protocol::{ProviderFailureKind, ProviderFailureStage};
    for (status, code, kind, retryable) in [
        (
            "INVALID_ARGUMENT",
            400,
            ProviderFailureKind::Configuration,
            false,
        ),
        (
            "UNAUTHENTICATED",
            401,
            ProviderFailureKind::Authentication,
            false,
        ),
        (
            "PERMISSION_DENIED",
            403,
            ProviderFailureKind::Authorization,
            false,
        ),
        (
            "RESOURCE_EXHAUSTED",
            429,
            ProviderFailureKind::Capacity,
            true,
        ),
        ("UNAVAILABLE", 503, ProviderFailureKind::Capacity, true),
        ("INTERNAL", 13, ProviderFailureKind::Capacity, true),
        (
            "FAILED_PRECONDITION",
            9,
            ProviderFailureKind::Configuration,
            false,
        ),
        (
            "OUT_OF_RANGE",
            11,
            ProviderFailureKind::Configuration,
            false,
        ),
        (
            "UNIMPLEMENTED",
            12,
            ProviderFailureKind::Configuration,
            false,
        ),
    ] {
        let mut decoder = GEMINI_WIRE_CODEC
            .new_stream_decoder(pl_model_wire::protocol::WireApi::GeminiGenerateContent);
        let frame = json!({"error":{"code":code,"status":status,"message":"provider detail"}});
        let decoded = decoder
            .decode_frame(&frame.to_string(), Some("google-request"), &str::to_owned)
            .unwrap();
        let ModelStreamEvent::Failed { failure } = &decoded.events[0] else {
            panic!("typed Google failure")
        };
        assert_eq!(failure.kind, kind, "{status}");
        assert_eq!(failure.retry.is_retryable(), retryable, "{status}");
        assert_eq!(failure.code.as_deref(), Some(status));
        assert_eq!(failure.context.stage, ProviderFailureStage::Stream);
        assert_eq!(
            failure.context.request_id.as_deref(),
            Some("google-request")
        );
        assert_eq!(
            failure.http_status, None,
            "the stream's RPC error is not the outer HTTP status"
        );
        assert!(decoded.reached_terminal);
        assert!(decoder.finish().is_empty());
    }
}

#[test]
fn rejects_interrupted_gemini_tool_batches_and_duplicate_ids_in_the_same_batch() {
    let model = bundled_definition().unwrap().models.remove(0);
    let endpoint = endpoint::vertex_endpoint(None);
    let assistant = |ids: &[(&str, &str)]| Message {
        tool_calls: Some(
            ids.iter()
                .map(|(item, call)| {
                    ToolCall::function(*item, "lookup", json!({}), *call).history_record()
                })
                .collect(),
        ),
        ..message(MessageRole::Assistant, "")
    };
    let encode = |messages| {
        GEMINI_WIRE_CODEC.encode_http_request(EncodeHttpRequestInput {
            endpoint: &endpoint,
            model: &model,
            request: &CompletionRequest::builder().messages(messages).build(),
            prompt_cache_key: None,
            compaction_body: None,
            is_compaction: false,
        })
    };
    let first = [("a", "a"), ("b", "b")];
    let invalid = [
        (
            "interrupted result batch",
            vec![
                assistant(&first),
                lookup_result("a", "a"),
                message(MessageRole::User, "interrupt the batch"),
                lookup_result("b", "b"),
            ],
        ),
        (
            "duplicate ID",
            vec![
                assistant(&[("same", "x-1"), ("same", "x-2")]),
                lookup_result("same", "x-1"),
                lookup_result("same", "x-2"),
            ],
        ),
    ];
    let accepted: Vec<_> = invalid
        .into_iter()
        .filter_map(|(case, messages)| encode(messages).ok().map(|request| (case, request.body)))
        .collect();
    assert!(accepted.is_empty(), "incorrectly accepted {accepted:?}");

    let request = encode(vec![
        assistant(&first),
        lookup_result("a", "a"),
        lookup_result("b", "b"),
        assistant(&[("a", "a")]),
        lookup_result("a", "a"),
    ])
    .unwrap();
    let contents = request.body["contents"].as_array().unwrap();
    assert_eq!(contents.len(), 4);
    assert_eq!(contents[1]["parts"][0]["functionResponse"]["id"], "a");
    assert_eq!(contents[1]["parts"][1]["functionResponse"]["id"], "b");
    assert_eq!(contents[3]["parts"][0]["functionResponse"]["id"], "a");
}

#[test]
fn request_encodes_multimodal_inline_data_and_coalesces_parallel_tool_results() {
    let bundled = bundled_definition().unwrap();
    let model = bundled
        .models
        .iter()
        .find(|m| m.base.slug == "gemini-4-hydrogen")
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
            effort: Some("xhigh".into()),
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
        model: "gemini-4-hydrogen".into(),
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
        "/models/gemini-4-hydrogen:streamGenerateContent?alt=sse"
    );
    assert!(prepared.body.get("model").is_none());
    assert_eq!(
        prepared.body["generationConfig"]["thinkingConfig"]["thinkingLevel"],
        "xhigh"
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

    let Some(ModelContextItem::ToolResult { message, .. }) = req.input.last_mut() else {
        panic!("expected a tool result");
    };
    message.tool_result.as_mut().unwrap().name = "another_tool".into();
    let error = GEMINI_WIRE_CODEC
        .encode_http_request(EncodeHttpRequestInput {
            endpoint: &ep,
            model: &model,
            request: &req,
            prompt_cache_key: None,
            compaction_body: None,
            is_compaction: false,
        })
        .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("tool result name does not match"),
        "{error}"
    );

    for (field, value, expected) in [
        (
            "name",
            json!("another_tool"),
            "differs from submitted binding",
        ),
        (
            "id",
            json!("different-id"),
            "id differs from submitted binding",
        ),
        ("id", json!(73), "id must be a string"),
        (
            "args",
            json!({"path":"other.txt"}),
            "args differ from submitted binding",
        ),
    ] {
        let mut altered = resp.clone();
        let Some(AssistantReplay::Gemini { parts }) = altered.replay.as_mut() else {
            panic!("expected Gemini replay");
        };
        parts[1]["functionCall"][field] = value;
        let error = CompletionRequest::builder()
            .build()
            .append_response(&altered)
            .unwrap_err();
        assert!(error.to_string().contains(expected), "{field}: {error}");
    }

    let mut duplicate = resp.clone();
    let Some(AssistantReplay::Gemini { parts }) = duplicate.replay.as_mut() else {
        panic!("expected Gemini replay");
    };
    parts[2]["functionCall"]["id"] = json!("call_1");
    duplicate.tool_calls[1].id = "call_1".into();
    duplicate.tool_calls[1].call_id = "call_1".into();
    let error = CompletionRequest::builder()
        .build()
        .append_response(&duplicate)
        .unwrap_err();
    assert!(error.to_string().contains("duplicate"), "{error}");

    let mut omitted_args = resp;
    let Some(AssistantReplay::Gemini { parts }) = omitted_args.replay.as_mut() else {
        panic!("expected Gemini replay");
    };
    parts[1]["functionCall"]
        .as_object_mut()
        .unwrap()
        .remove("args");
    let mut request = CompletionRequest::builder().build();
    let error = request.append_response(&omitted_args).unwrap_err();
    assert!(error.to_string().contains("args differ"), "{error}");
    omitted_args.tool_calls[0] = ToolCall::function("call_1", "read_file", json!({}), "call_1");
    request.append_response(&omitted_args).unwrap();
}

#[test]
fn sse_decoder_preserves_trailing_thought_signature_and_tool_calls() {
    use pl_model_wire::completion::stream::event::ToolInputDeltaPayload;

    let mut decoder = GEMINI_WIRE_CODEC
        .new_stream_decoder(pl_model_wire::protocol::WireApi::GeminiGenerateContent);
    let mut collector = ReplayCollector::default();

    let thought = json!({"text":"Let me think.","thought":true});
    let first = json!({
        "functionCall":{"name":"lookup","args":{"q":"one"},"id":"id-1"},
        "thoughtSignature":"SIG_FIRST",
        "future":{"preserve":true},
    });
    let second = json!({"functionCall":{"name":"lookup","args":{"q":"two"},"id":"id-2"}});
    let third = json!({"functionCall":{"name":"lookup","args":{"q":"three"},"id":"id-3"}});
    let tail_signature = json!({"text":"","thoughtSignature":"SIG_TAIL"});
    let frames = [
        json!({"candidates":[{"content":{"role":"model","parts":[thought,first,second]}}],
            "modelVersion":"gemini-4-hydrogen","responseId":"resp-1"}),
        json!({"candidates":[{"content":{"role":"model","parts":[third]}}]}),
        json!({"candidates":[{"content":{"role":"model","parts":[tail_signature]},"finishReason":"STOP"}],
            "usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"thoughtsTokenCount":7,"totalTokenCount":22}}),
    ];

    let mut saw_usage = None;
    let mut ready = Vec::new();
    for frame in frames {
        let decoded = decoder
            .decode_frame(&frame.to_string(), Some("goog-req-1"), &|s| s.to_owned())
            .unwrap();
        assert!(!decoded.reached_terminal);
        for ev in decoded.events {
            match ev {
                ModelStreamEvent::Replay(u) => collector.apply(u).unwrap(),
                ModelStreamEvent::Usage(u) => saw_usage = Some(u),
                ModelStreamEvent::ToolCallReady {
                    call_id: Some(id),
                    name: Some(name),
                    payload: Some(ToolInputDeltaPayload::FunctionArguments(args)),
                    ..
                } => ready.push((
                    id,
                    name,
                    serde_json::from_str::<serde_json::Value>(&args).unwrap(),
                )),
                ModelStreamEvent::Completed { .. } => panic!("Gemini completed before stream EOF"),
                _ => {}
            }
        }
    }
    assert_eq!(
        ready,
        [
            ("id-1".to_owned(), "lookup".to_owned(), json!({"q":"one"})),
            ("id-2".to_owned(), "lookup".to_owned(), json!({"q":"two"})),
            ("id-3".to_owned(), "lookup".to_owned(), json!({"q":"three"})),
        ]
    );
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
    assert_eq!(parts, [thought, first, second, third, tail_signature]);
    let usage = saw_usage.unwrap();
    assert_eq!(usage.input_tokens, Some(10));
    assert_eq!(usage.output_tokens, Some(12));
    assert_eq!(usage.reasoning_tokens, Some(7));
}

#[test]
fn refuses_gemini_streamed_function_arguments_in_request_and_response() {
    let mut model = bundled_definition().unwrap().models.remove(0);
    let endpoint = endpoint::vertex_endpoint(None);
    let request = CompletionRequest::builder().build();
    let encode = |model: &ModelDefinition| {
        GEMINI_WIRE_CODEC.encode_http_request(EncodeHttpRequestInput {
            endpoint: &endpoint,
            model,
            request: &request,
            prompt_cache_key: None,
            compaction_body: None,
            is_compaction: false,
        })
    };
    for (tool, calling, stream) in [
        (
            "toolConfig",
            "functionCallingConfig",
            "streamFunctionCallArguments",
        ),
        (
            "toolConfig",
            "functionCallingConfig",
            "stream_function_call_arguments",
        ),
        (
            "toolConfig",
            "function_calling_config",
            "streamFunctionCallArguments",
        ),
        (
            "tool_config",
            "functionCallingConfig",
            "streamFunctionCallArguments",
        ),
        (
            "tool_config",
            "function_calling_config",
            "stream_function_call_arguments",
        ),
    ] {
        model.extra.binding.request.body = json!({(tool):{(calling):{(stream):true}}})
            .as_object()
            .unwrap()
            .clone();
        let error = encode(&model).unwrap_err();
        assert!(
            error.to_string().contains("streamFunctionCallArguments"),
            "{error}"
        );
    }
    for body in [
        json!({"toolConfig":{"functionCallingConfig":{"streamFunctionCallArguments":false,"stream_function_call_arguments":true}}}),
        json!({"toolConfig":{"functionCallingConfig":{"streamFunctionCallArguments":false},"function_calling_config":{"streamFunctionCallArguments":true}}}),
        json!({"toolConfig":{"functionCallingConfig":{"streamFunctionCallArguments":false}},"tool_config":{"functionCallingConfig":{"streamFunctionCallArguments":true}}}),
    ] {
        model.extra.binding.request.body = body.as_object().unwrap().clone();
        let error = encode(&model).unwrap_err();
        assert!(
            error.to_string().contains("streamFunctionCallArguments"),
            "{error}"
        );
    }
    model.extra.binding.request.body = json!({
        "tool_config":{"function_calling_config":{"stream_function_call_arguments":false}},
        "labels":{"stream_function_call_arguments":"true"},
    })
    .as_object()
    .unwrap()
    .clone();
    let prepared = encode(&model).unwrap();
    assert_eq!(
        prepared.body["labels"]["stream_function_call_arguments"],
        "true"
    );

    for function_call in [
        json!({"name":"lookup","partialArgs":[{"jsonPath":"$.q","stringValue":"look"}],"willContinue":true}),
        json!({"name":"lookup","willContinue":true}),
        json!({"partialArgs":[{"jsonPath":"$.q","stringValue":"up"}],"willContinue":false}),
        json!({"name":"lookup","args":{},"willContinue":"true"}),
        json!({"name":"lookup","willContinue":false,"partialArgs":[]}),
        json!({"name":"lookup","args":{},"partial_args":[{"json_path":"$.q","string_value":"look"}]}),
        json!({"name":"lookup","args":{},"willContinue":false,"will_continue":true}),
    ] {
        let mut decoder = GEMINI_WIRE_CODEC
            .new_stream_decoder(pl_model_wire::protocol::WireApi::GeminiGenerateContent);
        let frame = json!({"candidates":[{"content":{"role":"model","parts":[
            {"functionCall":function_call},
        ]},"finishReason":"STOP"}]});
        let decoded = decoder
            .decode_frame(&frame.to_string(), None, &str::to_owned)
            .unwrap();
        assert!(decoded.events.iter().any(|event| matches!(event,
            ModelStreamEvent::Failed { failure } if failure.message.contains("streamed function arguments")
        )), "{function_call}");
        assert!(
            !decoded
                .events
                .iter()
                .any(|event| matches!(event, ModelStreamEvent::ToolCallReady { .. }))
        );
        assert!(decoder.finish().is_empty());
    }

    for part in [
        json!({"functionCall":{"name":"lookup","args":{"q":"complete"},"willContinue":false,"partialArgs":[]}}),
        json!({"function_call":{"name":"lookup","args":{"q":"complete"},"will_continue":false,"partial_args":[]}}),
    ] {
        let mut decoder = GEMINI_WIRE_CODEC
            .new_stream_decoder(pl_model_wire::protocol::WireApi::GeminiGenerateContent);
        let full_call = json!({"candidates":[{"content":{"role":"model","parts":[part]},"finishReason":"STOP"}]});
        let decoded = decoder
            .decode_frame(&full_call.to_string(), None, &str::to_owned)
            .unwrap();
        assert!(
            decoded.events.iter().any(|event| matches!(event,
                ModelStreamEvent::ToolCallReady { name: Some(name), .. } if name == "lookup"
            )),
            "{part}"
        );
        assert!(
            decoder
                .finish()
                .iter()
                .any(|event| matches!(event, ModelStreamEvent::Completed { .. }))
        );
    }
}

#[test]
fn rejects_gemini_argument_fragments_in_public_replay() {
    let model = bundled_definition().unwrap().models.remove(0);
    let endpoint = endpoint::vertex_endpoint(None);
    let mut response = CompletionResponse {
        response_id: None,
        content: None,
        replay: None,
        reasoning_content: None,
        tool_calls: vec![ToolCall::function(
            "internal",
            "lookup",
            json!({}),
            "internal",
        )],
        responses_context_items: Vec::new(),
        presentation_items: Vec::new(),
        orchestration: Default::default(),
        timing: None,
        accounting: InferenceAccounting::default(),
        model: "gemini-4-hydrogen".into(),
        model_observation: None,
        observation: Default::default(),
    };
    let encode = |request: &CompletionRequest| {
        GEMINI_WIRE_CODEC.encode_http_request(EncodeHttpRequestInput {
            endpoint: &endpoint,
            model: &model,
            request,
            prompt_cache_key: None,
            compaction_body: None,
            is_compaction: false,
        })
    };
    let full =
        json!({"functionCall":{"name":"lookup","args":{},"partialArgs":[],"willContinue":false}});
    response.replay = Some(AssistantReplay::Gemini {
        parts: vec![full.clone()],
    });
    let mut valid = CompletionRequest::builder().build();
    valid.append_response(&response).unwrap();
    valid
        .input
        .push(lookup_result("internal", "internal").into());
    assert_eq!(
        encode(&valid).unwrap().body["contents"][0]["parts"][0],
        full
    );

    let fragments: [Value; 3] = [
        json!({"functionCall":{"name":"lookup","partialArgs":[{"jsonPath":"$.q","stringValue":"look"}],"willContinue":true}}),
        json!({"functionCall":{"name":"lookup","partial_args":[{"json_path":"$.q","string_value":"look"}],"will_continue":true}}),
        json!({"function_call":{"name":"lookup","partial_args":[{"json_path":"$.q","string_value":"look"}],"will_continue":true}}),
    ];
    for fragment in fragments {
        response.replay = Some(AssistantReplay::Gemini {
            parts: vec![fragment.clone()],
        });
        let mut history = CompletionRequest::builder().build();
        let appended = history.append_response(&response);
        let mut altered = valid.clone();
        altered.replay_spans[0].output[0] = fragment;
        let encoded = encode(&altered);
        assert!(
            matches!(&appended, Err(error) if error.to_string().contains("streamed function arguments"))
                && matches!(&encoded, Err(error) if error.to_string().contains("streamed function arguments")),
            "append returned {appended:?}, encoding returned {encoded:?}"
        );
    }
}

#[test]
fn gemini_tool_calls_do_not_make_an_abnormal_stream_successful() {
    for finish_reason in [None, Some("MAX_TOKENS"), Some("SAFETY")] {
        let mut decoder = GEMINI_WIRE_CODEC
            .new_stream_decoder(pl_model_wire::protocol::WireApi::GeminiGenerateContent);
        let mut candidate = json!({"content":{"role":"model","parts":[
            {"functionCall":{"name":"lookup","args":{"q":"ready"}}},
        ]}});
        if let Some(reason) = finish_reason {
            candidate["finishReason"] = json!(reason);
        }
        let frame = json!({"candidates":[candidate]});
        let decoded = decoder
            .decode_frame(&frame.to_string(), None, &str::to_owned)
            .unwrap();
        if let Some(reason) = finish_reason {
            assert!(decoded.events.iter().any(|event| matches!(event,
                ModelStreamEvent::Failed { failure } if failure.code.as_deref() == Some(reason)
            )));
        }
        assert!(
            !decoded
                .events
                .iter()
                .any(|event| matches!(event, ModelStreamEvent::Completed { .. }))
        );
        assert!(decoder.finish().is_empty());
    }
}

#[test]
fn rejects_malformed_gemini_function_call_identity_before_ready() {
    for (call, expected) in [
        (json!({"name":"lookup","id":null}), "id must be a string"),
        (json!({"name":"lookup","id":42}), "id must be a string"),
        (json!({"args":{}}), "missing name"),
    ] {
        let mut decoder = GEMINI_WIRE_CODEC
            .new_stream_decoder(pl_model_wire::protocol::WireApi::GeminiGenerateContent);
        let frame = json!({"candidates":[{"content":{"role":"model","parts":[
            {"functionCall":call},
        ]},"finishReason":"STOP"}]});
        let decoded = decoder
            .decode_frame(&frame.to_string(), None, &str::to_owned)
            .unwrap();
        assert!(
            decoded.events.iter().any(|event| matches!(event,
                ModelStreamEvent::Failed { failure } if failure.message.contains(expected)
            )),
            "{call}"
        );
        assert!(
            !decoded
                .events
                .iter()
                .any(|event| matches!(event, ModelStreamEvent::ToolCallReady { .. }))
        );
        assert!(decoder.finish().is_empty());
    }
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
        model: "gemini-4-hydrogen".into(),
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

#[test]
fn tool_media_after_function_response_uses_separate_user_turn() {
    let bundled = bundled_definition().unwrap();
    let model = bundled
        .models
        .iter()
        .find(|m| m.base.slug == "gemini-4-hydrogen")
        .unwrap()
        .clone();
    let ep = endpoint::vertex_endpoint(None);

    let mut req = CompletionRequest::builder().build();
    req.input.push(ModelContextItem::Message {
        message: Message {
            role: MessageRole::User,
            content: MessageContent::text("inspect sample.png"),
            presentation: Default::default(),
            reasoning_content: None,
            tool_calls: None,
            tool_result: None,
            metadata: Default::default(),
        },
    });
    let resp = CompletionResponse {
        response_id: Some("resp-media-1".into()),
        content: None,
        replay: Some(AssistantReplay::Gemini {
            parts: vec![json!({
                "functionCall": {"name": "exec", "args": {"path": "sample.png"}, "id": "call_img_1"},
                "thoughtSignature": "SIG_IMG_1"
            })],
        }),
        reasoning_content: None,
        tool_calls: vec![ToolCall::function(
            "call_img_1",
            "exec",
            json!({"path": "sample.png"}),
            "call_img_1",
        )],
        responses_context_items: Vec::new(),
        presentation_items: Vec::new(),
        orchestration: Default::default(),
        timing: None,
        accounting: InferenceAccounting::default(),
        model: "gemini-4-hydrogen".into(),
        model_observation: None,
        observation: Default::default(),
    };
    req.append_response_from(&resp, Some("acct:vertex:1"))
        .unwrap();

    req.input.push(ModelContextItem::ToolResult {
        message: Message {
            role: MessageRole::Tool,
            content: MessageContent::text("{\"path\":\"sample.png\"}"),
            presentation: Default::default(),
            reasoning_content: None,
            tool_calls: None,
            tool_result: Some(ToolResultRecord {
                item_id: "call_img_1".into(),
                call_id: "call_img_1".into(),
                name: "exec".into(),
                kind: ToolCallKind::Function,
            }),
            metadata: Default::default(),
        },
        receipt: ToolResultReceipt {
            call_id: "call_img_1".into(),
            tool_name: "exec".into(),
            arguments_hash: "a".into(),
            result_hash: "b".into(),
            total_bytes: 21,
            visible_bytes: 21,
            truncated: false,
            artifacts: Vec::new(),
            continuation: None,
            reused_from_call_id: None,
        },
    });

    req.input.push(ModelContextItem::ToolMedia {
        items: vec![ToolMediaContext {
            call_id: "call_img_1".into(),
            label: "sample.png".into(),
            attachment: ThreadAttachment {
                id: "att-sample-png".into(),
                modality: AttachmentModality::Image,
                media_type: "image/png".into(),
                filename: Some("sample.png".into()),
                width: Some(128),
                height: Some(128),
                byte_size: 454,
            },
        }],
    });
    req.prepared_content.push(ResolvedAttachment {
        attachment_id: "att-sample-png".into(),
        modality: AttachmentModality::Image,
        media_type: "image/png".into(),
        filename: Some("sample.png".into()),
        sources: vec![AttachmentRepresentation::DataUrl {
            base64: "iVBORw0KGgo=".into(),
        }],
    });

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

    assert_eq!(prepared.visible_output, VisibleOutputProtocol::TaggedText);
    let contents = prepared.body["contents"].as_array().unwrap();
    assert_eq!(contents.len(), 4);
    assert_eq!(contents[0]["role"], "user");
    assert_eq!(contents[1]["role"], "model");
    assert_eq!(contents[2]["role"], "user");
    let fr_parts = contents[2]["parts"].as_array().unwrap();
    assert_eq!(fr_parts.len(), 1);
    assert!(fr_parts[0].get("functionResponse").is_some());
    assert_eq!(contents[3]["role"], "user");
    let media_parts = contents[3]["parts"].as_array().unwrap();
    assert!(media_parts.iter().any(|p| p.get("text").is_some()));
    assert!(media_parts.iter().any(|p| {
        p.get("inlineData")
            .and_then(|d| d.get("mimeType"))
            .and_then(|v| v.as_str())
            == Some("image/png")
    }));
}
