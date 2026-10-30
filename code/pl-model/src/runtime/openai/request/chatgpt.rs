//! SIWC wire projection checks; canonical context and tool identities are never rewritten.
use crate::completion::{CompletionRequest, ToolSpec};
use pl_protocol::{PureError, Result};
use serde_json::{Map, Value};

fn invalid(path: &str) -> PureError {
    PureError::ConfigError(format!(
        "ChatGPT Responses does not support or permit overriding {path}"
    ))
}

const FORBIDDEN: &[&str] = &[
    "background",
    "conversation",
    "max_output_tokens",
    "max_tool_calls",
    "metadata",
    "moderation",
    "multi_agent",
    "prompt",
    "prompt_cache_retention",
    "safety_identifier",
    "temperature",
    "top_logprobs",
    "top_p",
    "truncation",
    "user",
    "previous_response_id",
];

pub(super) fn validate_model_overrides(
    model: &crate::model::ModelInfo,
    request: &CompletionRequest,
    original: &Map<String, Value>,
) -> Result<()> {
    let mut fixed = original.clone();
    super::body::merge_base_body(&mut fixed, &model.binding.request.body);
    validate_body(&fixed, original)?;
    for parameter in &model.parameters {
        if parameter.name != "effort" {
            continue;
        }
        if let Some(wire) = request
            .reasoning
            .as_ref()
            .and_then(|r| r.effort.as_deref())
            .and_then(|effort| parameter.wire_for(effort))
        {
            for assignment in &wire.set {
                let root = assignment.path.split('.').next().unwrap_or_default();
                if FORBIDDEN.contains(&root) || matches!(root, "input" | "tools") {
                    return Err(invalid(root));
                }
                if matches!(root, "store" | "stream")
                    && (assignment.path != root
                        || assignment.value.as_bool() != Some(root == "stream"))
                {
                    return Err(invalid(root));
                }
            }
            for path in &wire.remove {
                let root = path.split('.').next().unwrap_or_default();
                if matches!(root, "input" | "tools" | "store" | "stream") {
                    return Err(invalid(root));
                }
            }
        }
    }
    Ok(())
}

pub(crate) fn validate_request(request: &CompletionRequest) -> Result<()> {
    if request.temperature.is_some() {
        return Err(invalid("request.temperature"));
    }
    if request.max_tokens.is_some() {
        return Err(invalid("request.max_tokens"));
    }
    for (index, tool) in request.tools.iter().enumerate() {
        match tool {
            ToolSpec::Function {
                allowed_callers, ..
            }
            | ToolSpec::Custom {
                allowed_callers, ..
            } => {
                if !allowed_callers.is_empty()
                    && !allowed_callers.contains(&pl_protocol::ToolCallerMode::Direct)
                {
                    return Err(invalid(&format!("request.tools[{index}].allowed_callers")));
                }
            }
            ToolSpec::WebSearch {
                options: pl_protocol::HostedWebSearchOptions::OpenAi { .. },
            } => {}
            _ => return Err(invalid(&format!("request.tools[{index}].type"))),
        }
    }
    Ok(())
}

pub(super) fn validate_history_item(item: &Value) -> Result<()> {
    let kind = item.get("type").and_then(Value::as_str);
    if !matches!(
        kind,
        Some(
            "message"
                | "function_call"
                | "function_call_output"
                | "custom_tool_call"
                | "custom_tool_call_output"
                | "reasoning"
                | "web_search_call"
                | "compaction"
        )
    ) {
        return Err(invalid("input[*].type"));
    }
    if item.get("role").and_then(Value::as_str) == Some("system") {
        return Err(invalid("input[*].role"));
    }
    if item.get("namespace").is_some()
        || item
            .get("caller")
            .and_then(|caller| caller.get("type"))
            .and_then(Value::as_str)
            .is_some_and(|kind| kind != "direct")
    {
        return Err(invalid("input[*].caller or namespace"));
    }
    Ok(())
}

pub(super) fn validate_body(
    body: &Map<String, Value>,
    original: &Map<String, Value>,
) -> Result<()> {
    for &field in FORBIDDEN {
        if body.contains_key(field) {
            return Err(invalid(field));
        }
    }
    for (field, expected) in [("store", false), ("stream", true)] {
        if body.get(field).and_then(Value::as_bool) != Some(expected) {
            return Err(invalid(field));
        }
    }
    let input = body
        .get("input")
        .and_then(Value::as_array)
        .ok_or_else(|| invalid("input"))?;
    // Equality protects all existing opaque input and the frozen declaration, not just known
    // keys. An override must not bypass the typed plan or silently replace user intent.
    for field in ["input", "tools"] {
        if body.get(field) != original.get(field) {
            return Err(invalid(field));
        }
    }
    for item in input {
        if item.get("type").and_then(Value::as_str) == Some("additional_tools") {
            continue; // Produced only by the typed builder and protected by exact equality.
        }
        validate_history_item(item)?;
    }
    Ok(())
}
