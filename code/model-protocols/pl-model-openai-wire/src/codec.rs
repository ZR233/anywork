use pl_model_wire::completion::stream::event::ModelStreamEvent;
use pl_model_wire::completion::{CompletionRequest, ModelContextItem, ToolSpec};
use pl_model_wire::model::{ModelDefinition, reasoning_fields};
use pl_model_wire::protocol::{ProtocolEndpoint, WireApi};
use pl_model_wire::transport::{SseContentTypePolicy, default_parse_http_error};
use pl_model_wire::wire_codec::{
    CapturedUsageObservation, DecodedSseFrame, EncodeHttpRequestInput, ParsedHttpError,
    PreparedHttpRequest, VisibleOutputProtocol, WireCodec, WireStreamDecoder,
};
use pl_protocol::{PureError, Result};
use serde_json::Value;

use crate::openai::sse::{OpenAiStreamDecoder, SseStreamEvent};
use crate::openai::usage::ProviderTokenUsage;
use crate::openai::{OpenAiRequestBody, build_request, validate_chatgpt_request};

pub static OPENAI_WIRE_CODEC: OpenAiWireCodec = OpenAiWireCodec;

#[derive(Debug, Clone, Copy, Default)]
pub struct OpenAiWireCodec;

impl WireCodec for OpenAiWireCodec {
    fn supports_wire_api(&self, api: WireApi) -> bool {
        matches!(api, WireApi::Responses | WireApi::ChatCompletions)
    }

    fn validate_context_items(&self, api: WireApi, items: &[ModelContextItem]) -> Result<()> {
        if api == WireApi::Responses {
            return Ok(());
        }
        for item in items {
            if matches!(
                item,
                ModelContextItem::Compaction { .. } | ModelContextItem::Native { .. }
            ) {
                return Err(PureError::ConfigError(
                    "session history contains native Responses context (for example an encrypted \
                     compaction checkpoint) that a Chat Completions model cannot consume; use a \
                     Responses-protocol model for this session or start a new session"
                        .into(),
                ));
            }
        }
        Ok(())
    }

    fn validate_context(
        &self,
        endpoint: &ProtocolEndpoint,
        model: &ModelDefinition,
        isolation: &str,
        request: &CompletionRequest,
    ) -> Result<()> {
        if endpoint.authorization.is_some() {
            validate_chatgpt_request(request)?;
            if !endpoint.service_capabilities.web_search.hosted_responses
                && request
                    .tools
                    .iter()
                    .any(|tool| matches!(tool, ToolSpec::WebSearch { .. }))
            {
                return Err(PureError::ConfigError(
                    "ChatGPT request.tools.web_search requires the account's hosted search capability"
                        .into(),
                ));
            }
        }
        self.validate_context_items(model.extra.binding.transport.protocol, &request.input)?;
        if model.extra.binding.transport.protocol == WireApi::ChatCompletions
            && model
                .extra
                .capabilities
                .interleaved
                .as_ref()
                .is_some_and(|capability| capability.field == reasoning_fields::REASONING_DETAILS)
            && request
                .input
                .iter()
                .filter_map(ModelContextItem::as_message)
                .any(|message| {
                    message
                        .reasoning_content
                        .as_ref()
                        .is_some_and(|text| !text.is_empty())
                })
        {
            return Err(PureError::ConfigError(
                "typed reasoning_details cannot be reconstructed from text reasoning history"
                    .into(),
            ));
        }
        if request.replay_spans.iter().any(|span| {
            span.source_isolation
                .as_deref()
                .is_some_and(|source| source != isolation)
                && span
                    .output
                    .iter()
                    .any(|item| item.get("type").and_then(Value::as_str) == Some("reasoning"))
        }) {
            return Err(PureError::ConfigError(
                "this request cannot replay native reasoning from a different credential owner"
                    .into(),
            ));
        }
        Ok(())
    }

    fn encode_http_request(
        &self,
        input: EncodeHttpRequestInput<'_>,
    ) -> Result<PreparedHttpRequest> {
        let api = input.model.extra.binding.transport.protocol;
        let mut body = build_request(
            api,
            input.endpoint.instruction_wire_role(api),
            input.request,
            input.model,
            input.prompt_cache_key,
            input.endpoint.authorization.is_some(),
        )?;
        if let Some(compaction_body) = input.compaction_body {
            body.apply_compaction_body(compaction_body);
        }
        body.reject_reserved_instruction_channel()?;
        body.validate_prompt_cache_key(input.prompt_cache_key)?;
        if input.is_compaction {
            body.prepare_compaction();
        }
        let sent_model = body.sent_model()?;
        let sse_content_type = if input.endpoint.authorization.is_some() {
            SseContentTypePolicy::AllowMissingForChatGpt
        } else {
            SseContentTypePolicy::Required
        };
        let (path_and_query, map, capture_protocol, close_on_terminal) = match body {
            OpenAiRequestBody::Responses(map) => {
                ("/responses".to_owned(), map, "responsesHttp", true)
            }
            OpenAiRequestBody::Chat(map) => (
                "/chat/completions".to_owned(),
                map,
                "chatCompletions",
                false,
            ),
        };
        Ok(PreparedHttpRequest {
            path_and_query,
            body: map,
            sent_model,
            capture_protocol,
            sse_content_type,
            visible_output: VisibleOutputProtocol::of(api),
            close_on_terminal,
        })
    }

    fn new_stream_decoder(&self, api: WireApi) -> Box<dyn WireStreamDecoder> {
        Box::new(OpenAiWireStreamDecoder {
            decoder: OpenAiStreamDecoder::new(VisibleOutputProtocol::of(api)),
        })
    }

    fn parse_http_error(&self, body: &[u8]) -> Option<ParsedHttpError> {
        default_parse_http_error(body)
    }
}

struct OpenAiWireStreamDecoder {
    decoder: OpenAiStreamDecoder,
}

impl WireStreamDecoder for OpenAiWireStreamDecoder {
    fn decode_frame(
        &mut self,
        data: &str,
        request_id: Option<&str>,
        redact: &dyn Fn(&str) -> String,
    ) -> Result<DecodedSseFrame> {
        let mut event = serde_json::from_str::<SseStreamEvent>(data)
            .map_err(|_| PureError::Protocol("invalid SSE JSON".into()))?;
        event.request_id = request_id.map(str::to_owned);
        redact_sse_event(&mut event, redact);
        let usage_capture = usage_observation(&event);
        let reached_terminal = matches!(
            event.kind.as_str(),
            "response.completed" | "response.failed" | "response.incomplete"
        );
        let events = self.decoder.decode(&event);
        Ok(DecodedSseFrame {
            events,
            usage_capture,
            reached_terminal,
        })
    }

    fn finish(&mut self) -> Vec<ModelStreamEvent> {
        self.decoder.finish()
    }
}

fn usage_observation(event: &SseStreamEvent) -> Option<CapturedUsageObservation> {
    let response = event.response.as_ref();
    let response_usage = response
        .and_then(|response| response.get("usage"))
        .and_then(ProviderTokenUsage::from_value);
    let usage = event.usage.as_ref().or(response_usage.as_ref())?;
    let usage = serde_json::to_value(usage).ok()?;
    Some(CapturedUsageObservation {
        response_id: event
            .id
            .clone()
            .or_else(|| response.and_then(|r| r.get("id")?.as_str().map(str::to_owned))),
        model: event
            .model
            .clone()
            .or_else(|| response.and_then(|r| r.get("model")?.as_str().map(str::to_owned))),
        service_tier: response.and_then(|r| r.get("service_tier")?.as_str().map(str::to_owned)),
        usage,
    })
}

fn redact_value(value: &mut Value, redact: &dyn Fn(&str) -> String) {
    match value {
        Value::String(text) => *text = redact(text),
        Value::Array(values) => values.iter_mut().for_each(|v| redact_value(v, redact)),
        Value::Object(values) => values.values_mut().for_each(|v| redact_value(v, redact)),
        _ => {}
    }
}

fn redact_sse_event(event: &mut SseStreamEvent, redact: &dyn Fn(&str) -> String) {
    if let Some(request_id) = &mut event.request_id {
        *request_id = redact(request_id);
    }
    if let Some(error) = &mut event.error {
        redact_value(error, redact);
    }
    if let Some(error) = event
        .response
        .as_mut()
        .and_then(|response| response.get_mut("error"))
    {
        redact_value(error, redact);
    }
    if let Some(response) = event.response.as_mut() {
        match event.kind.as_str() {
            "response.failed" => {
                for field in ["message", "code"] {
                    if let Some(Value::String(text)) = response.get_mut(field) {
                        *text = redact(text);
                    }
                }
            }
            "response.incomplete" => {
                if let Some(Value::String(reason)) = response
                    .get_mut("incomplete_details")
                    .and_then(|details| details.get_mut("reason"))
                {
                    *reason = redact(reason);
                }
            }
            _ => {}
        }
    }
    if event.kind == "error" {
        for value in [&mut event.message, &mut event.code].into_iter().flatten() {
            *value = redact(value);
        }
    }
}
