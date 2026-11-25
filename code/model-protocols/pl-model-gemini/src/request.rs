use std::collections::{BTreeMap, BTreeSet, VecDeque};

use pl_model_wire::completion::request_support::{
    MediaRepresentationPlan, finalize_body, media_inline_data, message_content_text,
    messages_after_last_compaction, record_arguments_text, tool_media_content,
    validate_tool_history,
};
use pl_model_wire::completion::{
    CompletionRequest, ContentPart, MessageRole, ModelContextItem, ToolSpec,
};
use pl_model_wire::model::{MediaWireFormat, ModelDefinition, ModelProtocolOptions};
use pl_model_wire::transport::SseContentTypePolicy;
use pl_model_wire::wire_codec::{PreparedHttpRequest, VisibleOutputProtocol};
use pl_protocol::{PureError, Result};
use serde_json::{Map, Value, json};

fn protocol_error(message: impl Into<String>) -> PureError {
    PureError::LlmError(format!("Gemini request protocol error: {}", message.into()))
}

pub fn validate_model_path_segment(model: &str) -> Result<String> {
    let trimmed = model.trim();
    if trimmed.is_empty()
        || trimmed != model
        || trimmed.contains("..")
        || trimmed.bytes().any(|b| {
            b.is_ascii_control()
                || b.is_ascii_whitespace()
                || matches!(b, b'/' | b'\\' | b'?' | b'#')
        })
    {
        return Err(protocol_error(format!(
            "invalid Gemini model identifier for URL path: {model:?}"
        )));
    }
    Ok(trimmed.to_owned())
}

pub fn build_http_request(
    request: &CompletionRequest,
    model: &ModelDefinition,
) -> Result<PreparedHttpRequest> {
    request.validate_replay_spans()?;
    let messages = messages_after_last_compaction(&request.input);
    validate_tool_history(&messages)?;

    let ModelProtocolOptions::GeminiGenerateContent(options) =
        &model.extra.binding.request.protocol
    else {
        return Err(protocol_error(
            "Gemini request requires gemini_generate_content protocol options",
        ));
    };

    let raw_model = model
        .extra
        .binding
        .request
        .api_model
        .as_deref()
        .unwrap_or(&model.base.slug);
    let sent_model = validate_model_path_segment(raw_model)?;
    let path_and_query = format!("/models/{sent_model}:streamGenerateContent?alt=sse");

    let media_plan = MediaRepresentationPlan::for_request(request, model)?;

    let replay_by_start: BTreeMap<_, _> = request
        .replay_spans
        .iter()
        .map(|span| (span.start, span))
        .collect();

    let mut contents: Vec<Value> = Vec::new();
    // The validated tool history pairs each result with its call in order, even when
    // the same upstream ID appears in separate assistant responses.
    let mut pending_calls = VecDeque::new();
    let mut index = 0_usize;
    while index < request.input.len() {
        let item = &request.input[index];
        let replay = replay_by_start.get(&index);
        if !pending_calls.is_empty()
            && (replay.is_some()
                || !item
                    .as_message()
                    .is_some_and(|message| message.role == MessageRole::Tool))
        {
            return Err(protocol_error(
                "functionResponse batch must immediately follow its functionCalls",
            ));
        }
        if let Some(span) = replay {
            pending_calls.extend(span.gemini_tool_calls()?);
            if !span.output.is_empty() {
                push_model_parts(&mut contents, span.output.clone());
            }
            index = index.saturating_add(span.semantic.len().max(1));
            continue;
        }
        match item {
            ModelContextItem::ToolMedia { items } => {
                let content = tool_media_content(items);
                let parts = encode_parts(&content.parts, &request.prepared_content, &media_plan)?;
                if !parts.is_empty() {
                    push_user_parts(&mut contents, parts);
                }
            }
            ModelContextItem::Message { message }
            | ModelContextItem::ToolResult { message, .. } => match message.role {
                MessageRole::User => {
                    let parts = encode_parts(
                        &message.content.parts,
                        &request.prepared_content,
                        &media_plan,
                    )?;
                    if !parts.is_empty() {
                        push_user_parts(&mut contents, parts);
                    }
                }
                MessageRole::System => {
                    let text = message_content_text(&message.content);
                    if !text.is_empty() {
                        push_user_parts(&mut contents, vec![json!({ "text": text })]);
                    }
                }
                MessageRole::Assistant => {
                    let mut parts = Vec::new();
                    let mut upstream_ids = BTreeSet::new();
                    let text = message_content_text(&message.content);
                    if !text.is_empty() {
                        parts.push(json!({ "text": text }));
                    }
                    for call in message.tool_calls.iter().flatten() {
                        let args_text = record_arguments_text(&call.arguments);
                        let args = match serde_json::from_str::<Value>(&args_text) {
                            Ok(Value::Object(map)) => Value::Object(map),
                            Ok(other) => json!({ "input": other }),
                            Err(_) => json!({ "raw": args_text }),
                        };
                        let mut fc = Map::new();
                        fc.insert("name".into(), Value::String(call.name.clone()));
                        fc.insert("args".into(), args);
                        let id = (!call.item_id.is_empty()).then_some(call.item_id.as_str());
                        if let Some(id) = id {
                            if !upstream_ids.insert(id) {
                                return Err(protocol_error(
                                    "duplicate functionCall id in the same batch",
                                ));
                            }
                            fc.insert("id".into(), Value::String(id.to_owned()));
                        }
                        pending_calls.push_back((call.name.as_str(), id));
                        parts.push(json!({ "functionCall": fc }));
                    }
                    if parts.is_empty() {
                        parts.push(json!({ "text": "" }));
                    }
                    push_model_parts(&mut contents, parts);
                }
                MessageRole::Tool => {
                    let record = message.tool_result.as_ref().ok_or_else(|| {
                        protocol_error("tool result message missing typed tool_result record")
                    })?;
                    let (name, id) = pending_calls.pop_front().ok_or_else(|| {
                        protocol_error("tool result has no corresponding functionCall")
                    })?;
                    if record.name != name {
                        return Err(protocol_error(
                            "tool result name does not match functionCall",
                        ));
                    }
                    let text = message_content_text(&message.content);
                    let mut fr = Map::new();
                    fr.insert("name".into(), Value::String(name.to_owned()));
                    fr.insert("response".into(), json!({ "result": text }));
                    if let Some(id) = id {
                        fr.insert("id".into(), Value::String(id.to_owned()));
                    }
                    push_function_response(&mut contents, json!({ "functionResponse": fr }));
                }
            },
            ModelContextItem::Compaction { .. } | ModelContextItem::Native { .. } => {
                return Err(protocol_error(
                    "Gemini protocol cannot consume Responses native or compaction items",
                ));
            }
        }
        index += 1;
    }
    if !pending_calls.is_empty() {
        return Err(protocol_error("functionResponse batch is incomplete"));
    }

    let mut body = Map::new();
    if let Some(system_prompt) = &request.system_prompt
        && !system_prompt.content().is_empty()
    {
        body.insert(
            "systemInstruction".into(),
            json!({ "parts": [{ "text": system_prompt.content() }] }),
        );
    }
    body.insert("contents".into(), Value::Array(contents));

    if !request.tools.is_empty() {
        let mut declarations = Vec::with_capacity(request.tools.len());
        for tool in &request.tools {
            match tool {
                ToolSpec::Function {
                    name,
                    description,
                    input_schema,
                    ..
                } => {
                    let mut decl = Map::new();
                    decl.insert("name".into(), Value::String(name.clone()));
                    decl.insert("description".into(), Value::String(description.clone()));
                    let schema_key = if options.use_parameters_json_schema {
                        "parametersJsonSchema"
                    } else {
                        "parameters"
                    };
                    decl.insert(schema_key.into(), input_schema.clone());
                    declarations.push(Value::Object(decl));
                }
                ToolSpec::Custom { .. } => {
                    return Err(protocol_error(
                        "Gemini requires custom tools to be projected to functions",
                    ));
                }
                ToolSpec::ProgrammaticToolCalling | ToolSpec::WebSearch { .. } => {
                    return Err(protocol_error(
                        "Gemini generateContent does not accept OpenAI Responses hosted tools",
                    ));
                }
            }
        }
        body.insert(
            "tools".into(),
            json!([{ "functionDeclarations": declarations }]),
        );
        let mode = match request.tool_choice.as_str() {
            "none" => "NONE",
            "required" => "ANY",
            _ => "AUTO",
        };
        body.insert(
            "toolConfig".into(),
            json!({ "functionCallingConfig": { "mode": mode } }),
        );
    }

    let mut generation_config = Map::new();
    if let Some(temperature) = request.temperature {
        generation_config.insert("temperature".into(), json!(temperature));
    }
    if let Some(max_tokens) = request.max_tokens {
        generation_config.insert("maxOutputTokens".into(), json!(max_tokens));
    }
    if options.include_thoughts && model.extra.capabilities.reasoning {
        generation_config.insert("thinkingConfig".into(), json!({ "includeThoughts": true }));
    }
    if !generation_config.is_empty() {
        body.insert("generationConfig".into(), Value::Object(generation_config));
    }

    if model
        .extra
        .binding
        .request
        .body
        .contains_key("systemInstruction")
        || parameter_writes_path(model, request, "systemInstruction")
    {
        return Err(protocol_error(
            "model body or parameter wire must not inject reserved `systemInstruction`; use SystemPrompt",
        ));
    }

    finalize_body(&mut body, model, &request.reasoning);

    if enables_streamed_function_arguments(&body) {
        return Err(protocol_error(
            "streamFunctionCallArguments is unsupported; Gemini requires complete function arguments",
        ));
    }

    if body.contains_key("model") {
        return Err(protocol_error(
            "Gemini generateContent body must not contain top-level `model`; model is carried in URL path",
        ));
    }

    Ok(PreparedHttpRequest {
        path_and_query,
        body,
        sent_model,
        capture_protocol: "geminiGenerateContent",
        sse_content_type: SseContentTypePolicy::Required,
        visible_output: VisibleOutputProtocol::TaggedText,
        close_on_terminal: false,
    })
}

fn enables_streamed_function_arguments(body: &Map<String, Value>) -> bool {
    ["toolConfig", "tool_config"]
        .into_iter()
        .filter_map(|key| body.get(key))
        .flat_map(|tool_config| {
            ["functionCallingConfig", "function_calling_config"]
                .into_iter()
                .filter_map(move |key| tool_config.get(key))
        })
        .flat_map(|calling_config| {
            [
                "streamFunctionCallArguments",
                "stream_function_call_arguments",
            ]
            .into_iter()
            .filter_map(move |key| calling_config.get(key))
        })
        .any(|mode| mode.as_bool() != Some(false))
}

fn parameter_writes_path(
    model: &ModelDefinition,
    request: &CompletionRequest,
    reserved_root: &str,
) -> bool {
    let Some(effort) = request.reasoning.as_ref().and_then(|r| r.effort.as_deref()) else {
        return false;
    };
    model.parameters().any(|parameter| {
        parameter.name == "effort"
            && parameter.wire_for(effort).is_some_and(|wire| {
                wire.set
                    .iter()
                    .map(|a| a.path.as_str())
                    .chain(wire.remove.iter().map(String::as_str))
                    .any(|path| {
                        path == reserved_root || path.starts_with(&format!("{reserved_root}."))
                    })
            })
    })
}

fn is_function_response_turn(content: &Value) -> bool {
    content.get("role").and_then(Value::as_str) == Some("user")
        && content
            .get("parts")
            .and_then(Value::as_array)
            .is_some_and(|parts| {
                !parts.is_empty() && parts.iter().all(|p| p.get("functionResponse").is_some())
            })
}

fn push_function_response(contents: &mut Vec<Value>, part: Value) {
    if let Some(last) = contents.last_mut()
        && is_function_response_turn(last)
        && let Some(existing) = last.get_mut("parts").and_then(Value::as_array_mut)
    {
        existing.push(part);
        return;
    }
    contents.push(json!({
        "role": "user",
        "parts": [part],
    }));
}

fn push_user_parts(contents: &mut Vec<Value>, parts: Vec<Value>) {
    // Vertex AI rejects user turns that mix `functionResponse` with `text` or `inlineData`.
    if let Some(last) = contents.last_mut()
        && last.get("role").and_then(Value::as_str) == Some("user")
        && !is_function_response_turn(last)
        && let Some(existing) = last.get_mut("parts").and_then(Value::as_array_mut)
    {
        existing.extend(parts);
        return;
    }
    contents.push(json!({
        "role": "user",
        "parts": parts,
    }));
}

fn push_model_parts(contents: &mut Vec<Value>, parts: Vec<Value>) {
    contents.push(json!({
        "role": "model",
        "parts": parts,
    }));
}

fn encode_parts(
    parts: &[ContentPart],
    prepared_content: &[pl_model_wire::completion::ResolvedAttachment],
    media_plan: &MediaRepresentationPlan,
) -> Result<Vec<Value>> {
    let mut encoded = Vec::with_capacity(parts.len());
    for part in parts {
        match part {
            ContentPart::Text { text } => {
                if !text.is_empty() {
                    encoded.push(json!({ "text": text }));
                }
            }
            ContentPart::Attachment {
                attachment_id,
                modality,
                media_type,
                ..
            } => {
                match media_plan.wire(*modality)? {
                    MediaWireFormat::GeminiInlineImage | MediaWireFormat::GeminiInlineFile => {}
                    _ => {
                        return Err(protocol_error(
                            "non-Gemini media wire cannot be serialized by Gemini protocol",
                        ));
                    }
                }
                let (mime_type, data) = media_inline_data(
                    attachment_id,
                    media_type,
                    *modality,
                    prepared_content,
                    media_plan,
                )?;
                encoded.push(json!({
                    "inlineData": {
                        "mimeType": mime_type,
                        "data": data,
                    }
                }));
            }
        }
    }
    Ok(encoded)
}
