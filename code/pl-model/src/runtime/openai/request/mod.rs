use pl_protocol::{Message, ModelContextItem, PureError, Result};
use serde::Serialize;
use serde_json::{Map, Value};

use super::OpenAiEndpoint;
use crate::completion::CompletionRequest;
use crate::model::info::{ModelInfo, ResponsesMaxTokensField};
use crate::protocol::{ProtocolKind, WireApi};

mod body;
pub(crate) use body::recovery_touches_input;
mod chat;
pub(crate) mod chatgpt;
mod content;
mod responses;
mod tool_history;

use body::{finalize_body, to_object_map};
use chat::ChatRequestBody;
use responses::ResponsesRequestBody;
use tool_history::validate_tool_history;

#[derive(Debug, Clone, Serialize)]
#[serde(untagged)]
pub(crate) enum OpenAiRequestBody {
    Responses(Map<String, Value>),
    Chat(Map<String, Value>),
}

impl OpenAiRequestBody {
    /// Model and native overlays cannot replace the host's resolved cache affinity.
    pub(crate) fn validate_prompt_cache_key(&self, expected: Option<&str>) -> Result<()> {
        let body = match self {
            Self::Responses(body) | Self::Chat(body) => body,
        };
        let expected = expected.map(|key| Value::String(key.to_owned()));
        if body.get("prompt_cache_key") != expected.as_ref() {
            return Err(protocol_error(
                "prompt_cache_key must match the runtime-resolved PromptCacheScope; model body, parameter wire and native options cannot override it",
            ));
        }
        Ok(())
    }

    pub(crate) fn sent_model(&self) -> Result<String> {
        let body = match self {
            Self::Responses(body) | Self::Chat(body) => body,
        };
        sent_model_from_wire_body(body)
    }

    pub(crate) fn prepare_compaction(&mut self) {
        match self {
            Self::Responses(body) | Self::Chat(body) => {
                for key in ["store", "tool_choice", "previous_response_id"] {
                    body.remove(key);
                }
            }
        }
    }
    /// Rejects any attempt to re-open the removed top-level `instructions` channel.
    ///
    /// The trusted instruction body now travels exclusively through the typed `SystemPrompt`
    /// interface; model fixed bodies, parameter wire and native options must not inject the
    /// reserved `instructions` field back into the wire body. The caller's configuration is kept
    /// and the conflict is surfaced as a protocol error before any network I/O.
    pub(crate) fn reject_reserved_instruction_channel(&self) -> Result<()> {
        let body = match self {
            Self::Responses(body) | Self::Chat(body) => body,
        };
        if body.contains_key("instructions") {
            return Err(protocol_error(
                "model body, parameter wire or native options must not inject the reserved top-level `instructions` field; use the typed SystemPrompt interface",
            ));
        }
        Ok(())
    }
}

pub(crate) fn sent_model_from_wire_body(body: &Map<String, Value>) -> Result<String> {
    match body.get("model") {
        Some(Value::String(model)) if !model.trim().is_empty() => Ok(model.clone()),
        Some(Value::String(_)) => Err(protocol_error("final request body model must not be blank")),
        Some(_) => Err(protocol_error("final request body model must be a string")),
        None => Err(protocol_error("final request body model is required")),
    }
}

pub(crate) fn build_openai_request_body(
    endpoint: OpenAiEndpoint,
    protocol: ProtocolKind,
    request: &CompletionRequest,
    model: &ModelInfo,
    prompt_cache_key: Option<&str>,
    chatgpt: bool,
    native_options: &Map<String, Value>,
) -> Result<OpenAiRequestBody> {
    let instruction_role = protocol.instruction_wire_role(match endpoint {
        OpenAiEndpoint::Responses => WireApi::Responses,
        OpenAiEndpoint::ChatCompletions => WireApi::ChatCompletions,
    });
    request.validate_replay_spans()?;
    let messages = messages_after_last_compaction(&request.input);
    validate_tool_history(&messages)?;
    match endpoint {
        OpenAiEndpoint::Responses => {
            let crate::model::ModelProtocolOptions::Responses(options) =
                &model.binding.request.protocol
            else {
                return Err(protocol_error(
                    "Responses request requires Responses options",
                ));
            };
            let mut body = to_object_map(&ResponsesRequestBody::from_request(
                request,
                model,
                prompt_cache_key,
                instruction_role,
                chatgpt,
            )?)?;
            let original = chatgpt.then(|| body.clone());
            if let Some(original) = &original {
                chatgpt::validate_model_overrides(model, request, original)?;
            }
            apply_responses_max_tokens_field(
                &mut body,
                request.max_tokens,
                options.max_tokens_field,
            );
            finalize_body(&mut body, model, request, native_options, protocol, chatgpt)?;
            if let Some(original) = &original {
                chatgpt::validate_body(&body, original)?;
            }
            Ok(OpenAiRequestBody::Responses(body))
        }
        OpenAiEndpoint::ChatCompletions => {
            let mut body = to_object_map(&ChatRequestBody::from_request(
                request,
                model,
                instruction_role,
            )?)?;
            finalize_body(&mut body, model, request, native_options, protocol, chatgpt)?;
            Ok(OpenAiRequestBody::Chat(body))
        }
    }
}

fn messages_after_last_compaction(input: &[ModelContextItem]) -> Vec<Message> {
    let start = input
        .iter()
        .rposition(ModelContextItem::is_compaction)
        .map_or(0, |index| index + 1);
    input[start..]
        .iter()
        .filter_map(ModelContextItem::as_message)
        .cloned()
        .collect()
}

fn apply_responses_max_tokens_field(
    body: &mut Map<String, Value>,
    max_tokens: Option<u64>,
    field: ResponsesMaxTokensField,
) {
    let Some(max_tokens) = max_tokens else {
        return;
    };
    let Some(key) = responses_max_tokens_key(field) else {
        return;
    };
    body.insert(key.to_string(), Value::from(max_tokens));
}

pub(super) fn responses_max_tokens_key(field: ResponsesMaxTokensField) -> Option<&'static str> {
    match field {
        ResponsesMaxTokensField::Omit => None,
        ResponsesMaxTokensField::MaxOutputTokens => Some("max_output_tokens"),
        ResponsesMaxTokensField::MaxTokens => Some("max_tokens"),
        ResponsesMaxTokensField::MaxCompletionTokens => Some("max_completion_tokens"),
    }
}

fn protocol_error(message: impl Into<String>) -> PureError {
    let msg = message.into();
    PureError::LlmError(format!("OpenAI request protocol error: {msg}"))
}
