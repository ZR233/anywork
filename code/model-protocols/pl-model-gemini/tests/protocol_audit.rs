use pl_model_gemini::{GEMINI_WIRE_CODEC, bundled_definition, endpoint};
use pl_model_wire::{
    completion::{
        AssistantReplay, CompletionRequest, CompletionResponse, Message, MessageContent,
        MessageRole, ModelContextItem, ToolCall, ToolCallKind, ToolResultRecord,
        stream::event::ModelStreamEvent,
    },
    model::{ModelDefinition, ModelProtocolOptions},
    wire_codec::{EncodeHttpRequestInput, PreparedHttpRequest, WireCodec},
};
use serde_json::{Value, json};

fn response(parts: Vec<Value>, tool_calls: Vec<ToolCall>) -> CompletionResponse {
    CompletionResponse {
        response_id: None,
        content: None,
        replay: Some(AssistantReplay::Gemini { parts }),
        reasoning_content: None,
        tool_calls,
        responses_context_items: Vec::new(),
        presentation_items: Vec::new(),
        orchestration: Default::default(),
        timing: None,
        accounting: Default::default(),
        model: "gemini-4-hydrogen".into(),
        model_observation: None,
        observation: Default::default(),
        usage_is_terminal: false,
        settlements: Vec::new(),
    }
}

fn message(role: MessageRole) -> Message {
    Message {
        role,
        content: MessageContent::text("content"),
        presentation: Default::default(),
        reasoning_content: None,
        tool_calls: None,
        tool_result: None,
        metadata: Default::default(),
    }
}

fn encode(
    model: &ModelDefinition,
    request: &CompletionRequest,
) -> pl_protocol::Result<PreparedHttpRequest> {
    GEMINI_WIRE_CODEC.encode_http_request(EncodeHttpRequestInput {
        endpoint: &endpoint::gemini_api_endpoint(None),
        model,
        request,
        prompt_cache_key: None,
        compaction_body: None,
        is_compaction: false,
    })
}

#[test]
fn canonical_history_uses_call_identity_and_refuses_to_rewrite_invalid_arguments() {
    let model = bundled_definition().unwrap().models.remove(0);
    for (args, valid) in [
        (json!({"q":"exact"}), true),
        (json!([]), false),
        (json!(null), false),
        (json!(42), false),
        (json!("not JSON"), false),
    ] {
        let mut assistant = message(MessageRole::Assistant);
        assistant.tool_calls = Some(vec![
            ToolCall::function("item-local", "lookup", args.clone(), "call-upstream")
                .history_record(),
        ]);
        let mut result = message(MessageRole::Tool);
        result.tool_result = Some(ToolResultRecord {
            item_id: "item-local".into(),
            call_id: "call-upstream".into(),
            name: "lookup".into(),
            kind: ToolCallKind::Function,
        });
        let request = CompletionRequest::builder()
            .messages(vec![assistant, result])
            .build();
        let encoded = encode(&model, &request);
        if valid {
            let body = encoded.unwrap().body;
            assert_eq!(
                body["contents"][0]["parts"][1]["functionCall"]["id"],
                "call-upstream"
            );
            assert_eq!(
                body["contents"][0]["parts"][1]["functionCall"]["args"],
                args
            );
            assert_eq!(
                body["contents"][1]["parts"][0]["functionResponse"]["id"],
                "call-upstream"
            );
        } else {
            assert!(
                encoded
                    .unwrap_err()
                    .to_string()
                    .contains("args must be a JSON object")
            );
        }
    }
}

#[test]
fn unsupported_request_modes_are_rejected_after_native_options_are_applied() {
    let request = CompletionRequest::builder()
        .messages(vec![message(MessageRole::User)])
        .build();
    for (body, expected) in [
        (
            json!({"system_instruction":{"parts":[{"text":"injected"}]}}),
            "reserved",
        ),
        (
            json!({"generationConfig":{"candidateCount":2}}),
            "one response candidate",
        ),
        (
            json!({"generation_config":{"candidate_count":2}}),
            "one response candidate",
        ),
        (
            json!({"generationConfig":{"maxOutputTokens":65537}}),
            "continuation is unsupported",
        ),
        (
            json!({"generation_config":{"max_output_tokens":65537}}),
            "continuation is unsupported",
        ),
        (
            json!({"continuationToken":"opaque"}),
            "continuation is unsupported",
        ),
        (
            json!({"continuation_token":"opaque"}),
            "continuation is unsupported",
        ),
    ] {
        let mut model = bundled_definition().unwrap().models.remove(0);
        model.extra.binding.request.body = body.as_object().unwrap().clone();
        assert!(
            encode(&model, &request)
                .unwrap_err()
                .to_string()
                .contains(expected),
            "{body}"
        );
    }
    let mut model = bundled_definition().unwrap().models.remove(0);
    let ModelProtocolOptions::GeminiGenerateContent(options) =
        &mut model.extra.binding.request.protocol
    else {
        panic!("Gemini options")
    };
    options.use_parameters_json_schema = false;
    assert!(
        encode(&model, &request)
            .unwrap_err()
            .to_string()
            .contains("legacy parameters Schema")
    );
}

#[test]
fn malformed_stream_structures_and_empty_success_never_submit_an_answer() {
    for mut frame in [
        json!({"error":"malformed error envelope"}),
        json!({"responseId":42}),
        json!({"candidates":{}}),
        json!({"candidates":[{},{}]}),
        json!({"candidates":[{"index":1}]}),
        json!({"candidates":[{"content":{"role":"user","parts":[{"text":"wrong role"}]}}]}),
        json!({"candidates":[{"content":{"parts":{}}}]}),
        json!({"candidates":[{"content":{"parts":[null]}}]}),
        json!({"candidates":[{"content":{"parts":[{"text":42}]}}]}),
        json!({"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"AA=="}}]}}]}),
        json!({"candidates":[{"content":{"parts":[{"text":"x","functionCall":{"name":"lookup","args":{}}}]}}]}),
        json!({"candidates":[{"content":{"parts":[{"functionCall":{"name":"lookup","args":[]}}]}}]}),
        json!({"candidates":[{"content":{"parts":[{"functionCall":{"name":"lookup","args":{},"id":"repeat"}},{"functionCall":{"name":"lookup","args":{},"id":"repeat"}}]}}]}),
    ] {
        frame["usageMetadata"] =
            json!({"promptTokenCount":3,"candidatesTokenCount":2,"totalTokenCount":5});
        let mut decoder = GEMINI_WIRE_CODEC
            .new_stream_decoder(pl_model_wire::protocol::WireApi::GeminiGenerateContent);
        let decoded = decoder
            .decode_frame(&frame.to_string(), &stream_context("audit-request"))
            .unwrap();
        assert!(decoded.events.iter().any(|event| matches!(event, ModelStreamEvent::Usage { usage, .. } if usage.total_tokens == Some(5))), "{frame}");
        assert!(decoded.events.iter().any(|event| matches!(event, ModelStreamEvent::Failed { failure } if failure.kind == pl_protocol::ProviderFailureKind::Protocol)), "{frame}");
        assert!(decoder.finish().is_empty());
    }
    for parts in [
        json!([]),
        json!([{"text":"","thoughtSignature":"keep"}]),
        json!([{"text":"only thought","thought":true}]),
    ] {
        let mut decoder = GEMINI_WIRE_CODEC
            .new_stream_decoder(pl_model_wire::protocol::WireApi::GeminiGenerateContent);
        let frame = json!({"candidates":[{"content":{"role":"model","parts":parts},"finishReason":"STOP"}]});
        decoder
            .decode_frame(&frame.to_string(), &stream_context("audit-request"))
            .unwrap();
        assert!(
            decoder
                .finish()
                .iter()
                .any(|event| matches!(event, ModelStreamEvent::Failed { .. }))
        );
    }
}

#[test]
fn malformed_error_after_stop_cannot_be_ignored_as_trailing_metadata() {
    let mut decoder = GEMINI_WIRE_CODEC
        .new_stream_decoder(pl_model_wire::protocol::WireApi::GeminiGenerateContent);
    let output = json!({"candidates":[{"content":{"role":"model","parts":[{"text":"provisional answer"}]},"finishReason":"STOP"}]});
    decoder
        .decode_frame(&output.to_string(), &stream_context("audit-request"))
        .unwrap();
    let error = decoder
        .decode_frame(
            r#"{"error":"invalid envelope","usageMetadata":{"totalTokenCount":5}}"#,
            &stream_context("audit-request"),
        )
        .unwrap();
    assert!(
        error
            .events
            .iter()
            .any(|event| matches!(event, ModelStreamEvent::Failed { .. }))
    );
    assert!(decoder.finish().is_empty());
}

#[test]
fn blocked_and_failed_frames_keep_usage_and_raw_usage_extensions() {
    let raw = json!({"promptTokenCount":10,"candidatesTokenCount":2,"totalTokenCount":12,"serviceTier":"standard","promptTokensDetails":[{"modality":"TEXT","tokenCount":10}],"futureField":{"keep":true}});
    for mut frame in [
        json!({"promptFeedback":{"blockReason":"SAFETY"}}),
        json!({"error":{"code":500,"status":"INTERNAL","message":"upstream failure"}}),
    ] {
        frame["usageMetadata"] = raw.clone();
        let mut decoder = GEMINI_WIRE_CODEC
            .new_stream_decoder(pl_model_wire::protocol::WireApi::GeminiGenerateContent);
        let decoded = decoder
            .decode_frame(&frame.to_string(), &stream_context("audit-request"))
            .unwrap();
        assert!(
            decoded
                .events
                .iter()
                .any(|event| matches!(event, ModelStreamEvent::Usage { .. }))
        );
        assert!(matches!(
            decoded.events.last(),
            Some(ModelStreamEvent::Failed { .. })
        ));
        let capture = decoded.usage_capture.unwrap();
        assert_eq!(capture.usage, raw);
        assert_eq!(capture.service_tier.as_deref(), Some("standard"));
    }
    let mut decoder = GEMINI_WIRE_CODEC
        .new_stream_decoder(pl_model_wire::protocol::WireApi::GeminiGenerateContent);
    assert!(
        decoder
            .decode_frame(
                r#"{"usageMetadata":{"promptTokenCount":"invalid"}}"#,
                &stream_context("audit-request")
            )
            .is_err()
    );
}

#[test]
fn public_replay_rejects_non_object_arguments_and_isolates_signature_aliases() {
    for args in [json!([]), json!(null), json!("text")] {
        let mut request = CompletionRequest::builder().build();
        let response = response(
            vec![json!({"functionCall":{"name":"lookup","id":"call","args":args}})],
            vec![ToolCall::function("call", "lookup", args.clone(), "call")],
        );
        assert!(
            request
                .append_response(&response)
                .unwrap_err()
                .to_string()
                .contains("args must be a JSON object")
        );
    }
    let mut request = CompletionRequest::builder().build();
    let response = response(
        vec![json!({"text":"answer","thought_signature":"opaque"})],
        vec![],
    );
    assert!(
        response
            .replay
            .as_ref()
            .unwrap()
            .has_opaque_provider_state()
    );
    request
        .append_response_from(&response, Some("original-owner"))
        .unwrap();
    assert!(
        GEMINI_WIRE_CODEC
            .validate_context(
                &endpoint::gemini_api_endpoint(None),
                &bundled_definition().unwrap().models[0],
                "different-owner",
                &request
            )
            .is_err()
    );
    assert!(matches!(request.input[0], ModelContextItem::Message { .. }));
}

fn stream_context(request_id: &str) -> pl_model_wire::provider_error::StreamFrameContext<'_> {
    use pl_model_wire::provider_error::{
        ErrorObservedAt, ObservedRetry, ProviderErrorContext, ProviderErrorEntry,
        StreamFrameContext,
    };
    StreamFrameContext {
        policy: pl_model_gemini::adapter::ADAPTER.error_policy,
        entry: ProviderErrorEntry::Sse,
        event_name: None,
        wire_api: pl_model_wire::protocol::WireApi::GeminiGenerateContent,
        endpoint: None,
        failure: ProviderErrorContext {
            stage: pl_protocol::ProviderFailureStage::Stream,
            request_id: Some(request_id),
            http_status: None,
            observed_at: ErrorObservedAt::now(),
            header_retry: ObservedRetry::Absent,
            redact: &|text| text.replace("fixture-credential", "[REDACTED_CREDENTIAL]"),
        },
    }
}
