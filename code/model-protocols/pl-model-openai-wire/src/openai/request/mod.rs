use crate::completion::CompletionRequest;
use crate::model::info::{ModelInfo, ResponsesMaxTokensField};
use crate::protocol::{InstructionWireRole, WireApi};
use pl_model_wire::completion::request_support::{
    finalize_body, merge_base_body, messages_after_last_compaction, to_object_map,
    validate_tool_history,
};
use pl_protocol::{PureError, Result};
use serde::Serialize;
use serde_json::{Map, Value};

mod body;
mod chat;
pub mod chatgpt;
mod responses;

use chat::ChatRequestBody;
use responses::ResponsesRequestBody;
pub use pl_model_wire::completion::request_support::sent_model_from_wire_body;

#[derive(Debug, Clone, Serialize)]
#[serde(untagged)]
pub enum OpenAiRequestBody {
    Responses(Map<String, Value>),
    Chat(Map<String, Value>),
}

impl OpenAiRequestBody {
    /// Model overrides and compaction material cannot replace the host's resolved cache affinity.
    pub fn validate_prompt_cache_key(&self, expected: Option<&str>) -> Result<()> {
        let body = match self {
            Self::Responses(body) | Self::Chat(body) => body,
        };
        let expected = expected.map(|key| Value::String(key.to_owned()));
        if body.get("prompt_cache_key") != expected.as_ref() {
            return Err(protocol_error(
                "prompt_cache_key must match the runtime-resolved PromptCacheScope; model body and parameter wire cannot override it",
            ));
        }
        Ok(())
    }

    pub fn sent_model(&self) -> Result<String> {
        let body = match self {
            Self::Responses(body) | Self::Chat(body) => body,
        };
        sent_model_from_wire_body(body)
    }

    pub fn prepare_compaction(&mut self) {
        match self {
            Self::Responses(body) | Self::Chat(body) => {
                for key in ["store", "tool_choice", "previous_response_id"] {
                    body.remove(key);
                }
            }
        }
    }
    pub fn apply_compaction_body(&mut self, options: &Map<String, Value>) {
        match self {
            Self::Responses(body) | Self::Chat(body) => merge_base_body(body, options),
        }
    }

    /// Rejects any attempt to re-open the removed top-level `instructions` channel.
    ///
    /// The trusted instruction body now travels exclusively through the typed `SystemPrompt`
    /// interface; model fixed bodies and parameter wire must not inject the
    /// reserved `instructions` field back into the wire body. The caller's configuration is kept
    /// and the conflict is surfaced as a protocol error before any network I/O.
    pub fn reject_reserved_instruction_channel(&self) -> Result<()> {
        let body = match self {
            Self::Responses(body) | Self::Chat(body) => body,
        };
        if body.contains_key("instructions") {
            return Err(protocol_error(
                "model body or parameter wire must not inject the reserved top-level `instructions` field; use the typed SystemPrompt interface",
            ));
        }
        Ok(())
    }
}

pub fn build_openai_request_body(
    endpoint: WireApi,
    instruction_role: InstructionWireRole,
    request: &CompletionRequest,
    model: &ModelInfo,
    prompt_cache_key: Option<&str>,
    chatgpt: bool,
) -> Result<OpenAiRequestBody> {
    request.validate_replay_spans()?;
    let messages = messages_after_last_compaction(&request.input);
    validate_tool_history(&messages)?;
    match endpoint {
        WireApi::Responses => {
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
            let original = body.clone();
            if chatgpt {
                chatgpt::validate_model_overrides(model, request, &original)?;
            }
            apply_responses_max_tokens_field(
                &mut body,
                request.max_tokens,
                options.max_tokens_field,
            );
            finalize_body(&mut body, model, &request.reasoning);
            if chatgpt {
                chatgpt::validate_body(&body, &original)?;
            }
            Ok(OpenAiRequestBody::Responses(body))
        }
        WireApi::ChatCompletions => {
            let mut body = to_object_map(&ChatRequestBody::from_request(
                request,
                model,
                instruction_role,
            )?)?;
            finalize_body(&mut body, model, &request.reasoning);
            Ok(OpenAiRequestBody::Chat(body))
        }
        WireApi::GeminiGenerateContent => Err(protocol_error(
            "OpenAI wire codec does not handle gemini_generate_content",
        )),
    }
}

fn apply_responses_max_tokens_field(
    body: &mut Map<String, Value>,
    max_tokens: Option<u64>,
    field: ResponsesMaxTokensField,
) {
    let Some(max_tokens) = max_tokens else {
        return;
    };
    let key = match field {
        ResponsesMaxTokensField::Omit => return,
        ResponsesMaxTokensField::MaxOutputTokens => "max_output_tokens",
        ResponsesMaxTokensField::MaxTokens => "max_tokens",
        ResponsesMaxTokensField::MaxCompletionTokens => "max_completion_tokens",
    };
    body.insert(key.to_string(), Value::from(max_tokens));
}

fn protocol_error(message: impl Into<String>) -> PureError {
    let msg = message.into();
    PureError::LlmError(format!("OpenAI request protocol error: {msg}"))
}
