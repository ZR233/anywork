use pl_model_wire::completion::stream::event::ModelStreamEvent;
use pl_model_wire::completion::{CompletionRequest, ModelContextItem, ToolSpec};
use pl_model_wire::model::{ModelDefinition, UsageReport, reasoning_fields};
use pl_model_wire::protocol::{ProtocolEndpoint, WireApi};
use pl_model_wire::provider_error::{ClassifiedProviderError, StreamFrameContext};
use pl_model_wire::transport::SseContentTypePolicy;
use pl_model_wire::wire_codec::{
    CapturedUsageObservation, DecodedSseFrame, EncodeHttpRequestInput, PreparedHttpRequest,
    VisibleOutputProtocol, WireCodec, WireStreamDecoder,
};
use pl_protocol::{ProviderFailure, PureError, Result};
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
            terminal_failure: false,
            chat_failure: None,
        })
    }
}

struct OpenAiWireStreamDecoder {
    decoder: OpenAiStreamDecoder,
    terminal_failure: bool,
    chat_failure: Option<ProviderFailure>,
}

impl WireStreamDecoder for OpenAiWireStreamDecoder {
    fn decode_frame(
        &mut self,
        data: &str,
        context: &StreamFrameContext<'_>,
    ) -> Result<DecodedSseFrame> {
        self.decode_openai_frame(data, context).map_err(|error| {
            self.terminal_failure = true;
            match self.chat_failure.take() {
                Some(primary) => primary.with_source(error).into(),
                None => error,
            }
        })
    }

    fn finish(&mut self) -> Vec<ModelStreamEvent> {
        if self.terminal_failure {
            return Vec::new();
        }
        let mut events = self.decoder.finish();
        if let Some(failure) = self.chat_failure.take() {
            self.terminal_failure = true;
            events.retain(|event| !matches!(event, ModelStreamEvent::Completed { .. }));
            events.push(ModelStreamEvent::Failed { failure });
        }
        events
    }
}

impl OpenAiWireStreamDecoder {
    fn terminate_failure(&mut self, failure: ProviderFailure) -> ProviderFailure {
        self.terminal_failure = true;
        match self.chat_failure.take() {
            Some(primary) => primary.with_source(failure),
            None => failure,
        }
    }

    fn decode_openai_frame(
        &mut self,
        data: &str,
        context: &StreamFrameContext<'_>,
    ) -> Result<DecodedSseFrame> {
        if self.terminal_failure {
            return Ok(DecodedSseFrame {
                events: Vec::new(),
                usage_capture: None,
                reached_terminal: true,
            });
        }
        let value: Value = serde_json::from_str(data).map_err(|error| {
            context
                .protocol_failure("invalid SSE JSON")
                .with_source(error)
        })?;
        if !value.is_object() {
            return Err(context
                .protocol_failure("OpenAI stream event must be an object")
                .into());
        }
        let mut failure = context.decode_failure(&value).or_else(|| {
            matches!(
                value.get("type").and_then(Value::as_str),
                Some("error" | "response.failed" | "response.incomplete")
            )
            .then(|| ClassifiedProviderError::from_http_status(None).into_failure(&context.failure))
        });
        if let Some(problem) = responses_terminal_conflict(&value, context) {
            let diagnostic = context.protocol_failure(problem);
            failure = Some(match failure {
                Some(failure) if failure.kind == pl_protocol::ProviderFailureKind::Protocol => {
                    failure
                }
                Some(mut failure) => {
                    if failure.kind == pl_protocol::ProviderFailureKind::Unknown {
                        failure.kind = pl_protocol::ProviderFailureKind::Protocol;
                    }
                    failure.reported_wait_ms =
                        failure.reported_wait_ms.or(failure.retry.retry_after_ms());
                    failure.retry = pl_protocol::RetryDisposition::Permanent;
                    failure.context.recovery = pl_protocol::ProviderRecovery::None;
                    failure.with_source(diagnostic)
                }
                None => diagnostic,
            });
        }
        if let Some(failure) = failure {
            let chat_choice = context.wire_api == WireApi::ChatCompletions
                && value.get("choices").is_some_and(Value::is_array)
                && value.get("error").is_none()
                && !matches!(context.event_name, Some("error"))
                && value.get("type").and_then(Value::as_str) != Some("error");
            if chat_choice {
                // Chat reports final usage in a separate empty-choices chunk.
                self.chat_failure.get_or_insert(failure);
            } else {
                let failure = self.terminate_failure(failure);
                return Ok(failed_frame(&value, failure, context.wire_api));
            }
        }
        let sample = usage_observation(&value, context.wire_api).map_err(|error| {
            context
                .protocol_failure("invalid OpenAI stream usage")
                .with_source(error)
        })?;
        let mut event: SseStreamEvent = serde_json::from_value(value).map_err(|error| {
            context
                .protocol_failure("invalid OpenAI stream event")
                .with_source(error)
        })?;
        if event.kind.is_empty()
            && let Some(name) = context.event_name.filter(|name| *name != "message")
        {
            event.kind = name.to_owned();
        }
        if event.kind.is_empty() && event.choices.is_none() {
            return Err(context
                .protocol_failure("OpenAI stream event has no type or choices")
                .into());
        }
        if event.kind == "response.completed"
            && event
                .response
                .as_ref()
                .is_none_or(|response| !response.is_object())
        {
            return Err(context
                .protocol_failure("completed Responses event has no response object")
                .into());
        }
        let mut events = self.decoder.decode(&event);
        let reached_terminal = event.kind == "response.completed";
        let usage_capture = sample.map(|(usage, capture)| {
            let terminal = match context.wire_api {
                WireApi::ChatCompletions => {
                    event.chat_has_finish_reason()
                        || (self.decoder.chat_finished()
                            && event.choices.as_ref().is_some_and(Vec::is_empty))
                }
                _ => reached_terminal,
            };
            let before_terminal = events
                .iter()
                .position(|event| {
                    matches!(
                        event,
                        ModelStreamEvent::Completed { .. } | ModelStreamEvent::Failed { .. }
                    )
                })
                .unwrap_or(events.len());
            events.insert(before_terminal, ModelStreamEvent::Usage { usage, terminal });
            capture
        });
        for event in &mut events {
            if let ModelStreamEvent::Failed { failure } = event {
                failure.context.request_id = context.failure.request_id.map(context.failure.redact);
                self.terminal_failure = true;
            }
        }
        if self.chat_failure.is_some()
            && event.choices.as_ref().is_some_and(Vec::is_empty)
            && usage_capture.is_some()
        {
            events.extend(self.finish());
        }
        Ok(DecodedSseFrame {
            events,
            usage_capture,
            reached_terminal: self.terminal_failure || reached_terminal,
        })
    }
}

fn responses_terminal_conflict(
    value: &Value,
    context: &StreamFrameContext<'_>,
) -> Option<&'static str> {
    if context.wire_api != WireApi::Responses {
        return None;
    }
    let kind = value
        .get("type")
        .and_then(Value::as_str)
        .or(context.event_name)?;
    let status = match kind {
        "response.completed" => "completed",
        "response.failed" => "failed",
        "response.incomplete" => "incomplete",
        _ => return None,
    };
    let response = value.get("response")?;
    if response
        .get("status")
        .is_some_and(|value| value.as_str() != Some(status))
    {
        return Some("Responses terminal event contradicts its response status");
    }
    if status == "completed"
        && ["error", "incomplete_details"]
            .iter()
            .any(|field| response.get(field).is_some_and(|value| !value.is_null()))
    {
        return Some("completed Responses event contains failure metadata");
    }
    None
}

fn usage_observation(
    value: &Value,
    api: WireApi,
) -> serde_json::Result<Option<(UsageReport, CapturedUsageObservation)>> {
    let response = value.get("response");
    let inner = response.and_then(|response| response.get("usage"));
    let outer = value.get("usage").filter(|usage| !usage.is_null());
    let normalize = |usage: ProviderTokenUsage| {
        let report = match api {
            WireApi::ChatCompletions => usage.to_chat_usage(),
            _ => usage.to_responses_usage(),
        }?;
        Some((report, usage))
    };
    let decode = |value: Option<&Value>| {
        value
            .and_then(ProviderTokenUsage::from_value)
            .and_then(normalize)
    };
    let sample = match api {
        WireApi::ChatCompletions => outer
            .cloned()
            .map(serde_json::from_value::<ProviderTokenUsage>)
            .transpose()?
            .and_then(normalize)
            .or_else(|| decode(inner)),
        _ => decode(inner).or_else(|| decode(outer)),
    };
    let Some((report, usage)) = sample else {
        return Ok(None);
    };
    let capture = CapturedUsageObservation {
        response_id: value
            .get("id")
            .and_then(Value::as_str)
            .or_else(|| response.and_then(|r| r.get("id")?.as_str()))
            .map(str::to_owned),
        model: value
            .get("model")
            .and_then(Value::as_str)
            .or_else(|| response.and_then(|r| r.get("model")?.as_str()))
            .map(str::to_owned),
        service_tier: response.and_then(|r| r.get("service_tier")?.as_str().map(str::to_owned)),
        usage: serde_json::to_value(usage)?,
    };
    Ok(Some((report, capture)))
}

fn failed_frame(value: &Value, failure: ProviderFailure, api: WireApi) -> DecodedSseFrame {
    let response = value.get("response").unwrap_or(value);
    let mut events = Vec::new();
    if let Some(model) = response.get("model").and_then(Value::as_str) {
        events.push(ModelStreamEvent::ResponseModelObserved {
            model: model.to_owned(),
            terminal: true,
        });
    }
    let usage_capture = usage_observation(value, api)
        .ok()
        .flatten()
        .map(|(usage, capture)| {
            events.push(ModelStreamEvent::Usage {
                usage,
                terminal: true,
            });
            capture
        });
    events.push(ModelStreamEvent::Failed { failure });
    DecodedSseFrame {
        events,
        usage_capture,
        reached_terminal: true,
    }
}
