//! Frozen assistant history, independent of the final-answer presentation.

use serde::{Deserialize, Serialize};
use serde_json::Map;
pub use serde_json::Value;
use std::collections::BTreeSet;

use super::{
    CompletionResponse, Message, MessageContent, MessageRole, ModelContextItem, ToolCallKind,
    ToolCallRecord,
};
use crate::completion::{ResponsesContextItem, ResponsesContextItemKind};
use pl_protocol::{PureError, Result};

/// Model-owned replay material. Open provider output fields stay opaque at this boundary.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum AssistantReplay {
    Responses { output: Vec<Value> },
    Chat { content: String },
    Gemini { parts: Vec<Value> },
}

impl AssistantReplay {
    /// Whether this replay carries opaque provider-encrypted reasoning state
    /// (such as OpenAI `encrypted_content` or Gemini `thoughtSignature`).
    pub fn has_opaque_provider_state(&self) -> bool {
        match self {
            Self::Responses { output } => output
                .iter()
                .any(|item| item.get("type").and_then(Value::as_str) == Some("reasoning")),
            Self::Gemini { parts } => parts.iter().any(|part| {
                ["thoughtSignature", "thought_signature"]
                    .into_iter()
                    .any(|key| {
                        part.get(key)
                            .and_then(Value::as_str)
                            .is_some_and(|sig| !sig.is_empty())
                    })
            }),
            Self::Chat { .. } => false,
        }
    }

    /// Derive execution intent from frozen protocol history, never from a display projection.
    pub fn is_commentary_only(&self) -> Result<bool> {
        match self {
            Self::Responses { output } => {
                let mut commentary = false;
                for item in output {
                    if item.get("type").and_then(Value::as_str) == Some("message") {
                        if item.get("phase").and_then(Value::as_str) != Some("commentary") {
                            return Ok(false);
                        }
                        commentary = true;
                    }
                }
                Ok(commentary)
            }
            Self::Chat { content } => {
                use super::CompletionPresentationItemKind::Text;
                use crate::completion::ModelTextChannel::{Commentary, Final};
                let segments =
                    super::stream::chat_presentation::completed_chat_presentation(content, None)?;
                Ok(segments.iter().any(|item| item.kind == Text(Commentary))
                    && !segments.iter().any(|item| item.kind == Text(Final)))
            }
            // Gemini/Vertex AI rejects requests ending with a `model` turn, so text-only
            // commentary without tool calls must not trigger a bare continuation turn.
            Self::Gemini { .. } => Ok(false),
        }
    }

    pub fn semantic_input(&self, response: &CompletionResponse) -> Result<Vec<ModelContextItem>> {
        let mut input = Vec::new();
        let mut text = String::new();
        let tool_calls: Vec<_> = response
            .tool_calls
            .iter()
            .map(super::ToolCall::history_record)
            .collect();
        match self {
            Self::Chat { content } => text.clone_from(content),
            Self::Gemini { parts } => {
                gemini_replay_tool_calls(parts, tool_calls.iter())?;
                for part in parts {
                    if let Some(part_text) = part.get("text").and_then(Value::as_str) {
                        let is_thought = part.get("thought").and_then(Value::as_bool) == Some(true);
                        if !is_thought {
                            text.push_str(part_text);
                        }
                    }
                }
            }
            Self::Responses { output } => {
                let mut calls = BTreeSet::new();
                let mut ids = BTreeSet::new();
                for item in output {
                    if item
                        .get("role")
                        .and_then(Value::as_str)
                        .is_some_and(|role| role != "assistant")
                    {
                        return Err(invalid("native assistant output changes message authority"));
                    }
                    if let Some(id) = item.get("id").and_then(Value::as_str)
                        && !ids.insert(id)
                    {
                        return Err(invalid("duplicate assistant output item identity"));
                    }
                    match item.get("type").and_then(Value::as_str) {
                        Some("message") => {
                            let parts = item
                                .get("content")
                                .and_then(Value::as_array)
                                .ok_or_else(|| invalid("assistant message has no content parts"))?;
                            for part in parts {
                                if let Some(value) = part
                                    .get("text")
                                    .or_else(|| part.get("refusal"))
                                    .and_then(Value::as_str)
                                {
                                    text.push_str(value);
                                }
                            }
                        }
                        Some(kind @ ("function_call" | "custom_tool_call")) => {
                            let call_id = item
                                .get("call_id")
                                .or_else(|| item.get("id"))
                                .and_then(Value::as_str)
                                .ok_or_else(|| invalid("assistant call has no identity"))?;
                            let call = response
                                .tool_calls
                                .iter()
                                .find(|call| call.call_id == call_id)
                                .ok_or_else(|| {
                                    invalid("native assistant call has no submitted binding")
                                })?;
                            let (wire_kind, field) = match call.kind() {
                                ToolCallKind::Function => ("function_call", "arguments"),
                                ToolCallKind::Custom => ("custom_tool_call", "input"),
                            };
                            if !calls.insert(call_id)
                                || kind != wire_kind
                                || item.get("name").and_then(Value::as_str)
                                    != Some(call.name.as_str())
                                || item.get(field).and_then(Value::as_str)
                                    != Some(call.payload_text().as_str())
                                || item
                                    .get("id")
                                    .and_then(Value::as_str)
                                    .is_some_and(|id| id != call.id)
                            {
                                return Err(invalid(
                                    "native assistant call differs from submitted binding",
                                ));
                            }
                        }
                        Some("function_call_output" | "custom_tool_call_output") => {
                            return Err(invalid("assistant output cannot fabricate a tool result"));
                        }
                        Some(_) => {
                            let native = ResponsesContextItem::from_wire(item.clone())
                                .unwrap_or_else(|| ResponsesContextItem {
                                    kind: ResponsesContextItemKind::Unknown,
                                    value: item.clone(),
                                });
                            input.push(native.into());
                        }
                        None => return Err(invalid("assistant output has no type")),
                    }
                }
                if calls.len() != response.tool_calls.len() {
                    return Err(invalid("assistant output is missing a submitted call"));
                }
            }
        }
        input.push(ModelContextItem::from(Message {
            presentation: Default::default(),
            role: MessageRole::Assistant,
            content: MessageContent::text(text),
            reasoning_content: response.reasoning_content.clone(),
            tool_calls: (!tool_calls.is_empty()).then_some(tool_calls),
            tool_result: None,
            metadata: Default::default(),
        }));
        Ok(input)
    }
}

/// Reads a Gemini function call Part in complete argument mode.
pub fn gemini_function_call(part: &Value) -> Result<Option<&Map<String, Value>>> {
    if !part.is_object()
        || part.get("functionResponse").is_some()
        || part.get("function_response").is_some()
    {
        return Err(invalid(
            "gemini assistant replay must contain model parts, not function responses",
        ));
    }
    let function = match (part.get("functionCall"), part.get("function_call")) {
        (Some(_), Some(_)) => return Err(invalid("ambiguous gemini functionCall field")),
        (Some(function), None) | (None, Some(function)) => function,
        (None, None) => return Ok(None),
    };
    let function = function
        .as_object()
        .ok_or_else(|| invalid("gemini functionCall must be a JSON object"))?;
    let has_full_args = function.get("args").is_some_and(Value::is_object);
    if function.get("args").is_some_and(|args| !args.is_object()) {
        return Err(invalid("gemini functionCall args must be a JSON object"));
    }
    // Neutral control values only describe a complete call when the full args object is present.
    let invalid_partials = ["partialArgs", "partial_args"]
        .into_iter()
        .filter_map(|key| function.get(key))
        .any(|value| !has_full_args || !value.as_array().is_some_and(Vec::is_empty));
    let invalid_continuation = ["willContinue", "will_continue"]
        .into_iter()
        .filter_map(|key| function.get(key))
        .any(|value| !has_full_args || value.as_bool() != Some(false));
    if invalid_partials || invalid_continuation {
        return Err(invalid(
            "Gemini streamed function arguments are unsupported",
        ));
    }
    Ok(Some(function))
}

/// Reads the optional upstream ID from an unmodified Gemini function call.
pub fn gemini_function_call_id(call: &Map<String, Value>) -> Result<Option<&str>> {
    match call.get("id") {
        None => Ok(None),
        Some(Value::String(id)) => Ok((!id.is_empty()).then_some(id.as_str())),
        Some(_) => Err(invalid("gemini functionCall id must be a string")),
    }
}

fn gemini_replay_tool_calls<'part, 'call>(
    parts: &'part [Value],
    mut calls: impl Iterator<Item = &'call ToolCallRecord>,
) -> Result<Vec<(&'part str, Option<&'part str>)>> {
    let mut upstream_calls = Vec::new();
    let mut bound_ids = BTreeSet::new();
    for part in parts {
        if !part.is_object() {
            return Err(invalid("gemini replay part must be a JSON object"));
        }
        let Some(function) = gemini_function_call(part)? else {
            continue;
        };
        let name = function
            .get("name")
            .and_then(Value::as_str)
            .filter(|name| !name.is_empty())
            .ok_or_else(|| invalid("gemini functionCall missing name"))?;
        let call = calls
            .next()
            .ok_or_else(|| invalid("gemini replay call has no submitted binding"))?;
        if call.kind != ToolCallKind::Function || call.name != name {
            return Err(invalid("gemini replay call differs from submitted binding"));
        }
        let id = gemini_function_call_id(function)?;
        if id.is_some_and(|id| id != call.call_id) {
            return Err(invalid(
                "gemini replay call id differs from submitted binding",
            ));
        }
        if !bound_ids.insert(call.call_id.as_str()) {
            return Err(invalid("duplicate gemini replay call identity"));
        }
        let expected = serde_json::from_str::<Value>(
            &super::request_support::record_arguments_text(&call.arguments),
        )
        .map_err(|_| invalid("gemini submitted call args are not JSON"))?;
        let matches = function.get("args").map_or_else(
            || expected.as_object().is_some_and(Map::is_empty),
            |args| args == &expected,
        );
        if !matches {
            return Err(invalid(
                "gemini replay call args differ from submitted binding",
            ));
        }
        upstream_calls.push((name, id));
    }
    if calls.next().is_some() {
        return Err(invalid("gemini replay output is missing a submitted call"));
    }
    Ok(upstream_calls)
}

/// Consumes only facts present in frames that predate complete replay recording.
/// It deliberately does not recover text or phase from presentation projections.
pub fn recorded_input(response: &CompletionResponse) -> Result<Vec<ModelContextItem>> {
    let mut input = Vec::new();
    for native in &response.responses_context_items {
        if native
            .value
            .get("role")
            .and_then(Value::as_str)
            .is_some_and(|role| role != "assistant")
        {
            return Err(invalid(
                "native assistant material changes message authority",
            ));
        }
        input.push(native.clone().into());
    }
    input.push(ModelContextItem::from(Message {
        role: MessageRole::Assistant,
        content: MessageContent::text(response.content.clone().unwrap_or_default()),
        presentation: Default::default(),
        reasoning_content: response.reasoning_content.clone(),
        tool_calls: (!response.tool_calls.is_empty()).then(|| {
            response
                .tool_calls
                .iter()
                .map(super::ToolCall::history_record)
                .collect()
        }),
        tool_result: None,
        metadata: Default::default(),
    }));
    Ok(input)
}

fn invalid(message: &str) -> PureError {
    crate::provider_error::invalid_request(message).into()
}

#[derive(Debug, Clone)]
pub struct ReplaySpan {
    pub start: usize,
    pub semantic: Vec<ModelContextItem>,
    pub output: Vec<Value>,
    /// 产生 `output` 的 provider 隔离身份（[`binding_cache_namespace`]）。
    ///
    /// 出站请求据此判断原生 reasoning 的 `encrypted_content` 是否可能被目标 provider 解释；
    /// 缺失（旧帧或无来源证据）时不改写既有回放语义。
    pub source_isolation: Option<String>,
}

impl ReplaySpan {
    /// Returns upstream names and optional IDs in the order of a Gemini replay's tool bindings.
    pub fn gemini_tool_calls(&self) -> Result<Vec<(&str, Option<&str>)>> {
        let calls = self
            .semantic
            .iter()
            .filter_map(ModelContextItem::as_message)
            .flat_map(|message| message.tool_calls.iter().flatten());
        gemini_replay_tool_calls(&self.output, calls)
    }
}
