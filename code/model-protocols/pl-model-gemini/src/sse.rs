use std::collections::BTreeSet;

use pl_model_wire::completion::ModelTextChannel;
use pl_model_wire::completion::replay::{gemini_function_call, gemini_function_call_id};
use pl_model_wire::completion::stream::event::{
    ModelBlockKind, ModelStreamEvent, ToolInputDeltaPayload,
};
use pl_model_wire::completion::stream::replay::ReplayUpdate;
use pl_model_wire::wire_codec::{CapturedUsageObservation, DecodedSseFrame, WireStreamDecoder};
use pl_protocol::{ProviderFailureKind, PureError, Result, RetryDisposition};
use serde_json::Value;

use crate::error::parse_google_http_error;
use crate::usage::GeminiUsageMetadata;

pub struct GeminiStreamDecoder {
    response_id: Option<String>,
    sent_started: bool,
    open_text_block: Option<String>,
    next_text_seq: u64,
    next_tool_seq: u64,
    finished_ok: bool,
    failed: bool,
    saw_output: bool,
    upstream_call_ids: BTreeSet<String>,
}

impl Default for GeminiStreamDecoder {
    fn default() -> Self {
        Self::new()
    }
}

impl GeminiStreamDecoder {
    pub fn new() -> Self {
        Self {
            response_id: None,
            sent_started: false,
            open_text_block: None,
            next_text_seq: 0,
            next_tool_seq: 0,
            finished_ok: false,
            failed: false,
            saw_output: false,
            upstream_call_ids: BTreeSet::new(),
        }
    }

    fn close_open_text_block(&mut self, events: &mut Vec<ModelStreamEvent>) {
        if let Some(id) = self.open_text_block.take() {
            events.push(ModelStreamEvent::BlockClosed {
                id,
                kind: ModelBlockKind::Text {
                    channel: ModelTextChannel::Final,
                },
                authoritative_content: None,
                provider_metadata: None,
                provider: None,
            });
        }
    }

    fn fail_invalid_response(
        &mut self,
        mut events: Vec<ModelStreamEvent>,
        usage_capture: Option<CapturedUsageObservation>,
        request_id: Option<String>,
        message: &str,
    ) -> DecodedSseFrame {
        self.failed = true;
        self.close_open_text_block(&mut events);
        events.push(ModelStreamEvent::Failed {
            failure: gemini_failure("invalid_response", message.into(), request_id),
        });
        DecodedSseFrame {
            events,
            usage_capture,
            reached_terminal: true,
        }
    }
}

impl WireStreamDecoder for GeminiStreamDecoder {
    fn decode_frame(
        &mut self,
        data: &str,
        request_id: Option<&str>,
        redact: &dyn Fn(&str) -> String,
    ) -> Result<DecodedSseFrame> {
        if self.failed {
            return Ok(DecodedSseFrame {
                events: Vec::new(),
                usage_capture: None,
                reached_terminal: true,
            });
        }

        let value: Value = serde_json::from_str(data)
            .map_err(|_| PureError::Protocol("invalid Gemini SSE JSON".into()))?;
        let response_id = value
            .get("responseId")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .map(str::to_owned);
        let model_version = value
            .get("modelVersion")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .map(str::to_owned);
        let mut events = Vec::new();
        let mut usage_capture = None;
        if let Some(raw_usage) = value.get("usageMetadata").filter(|meta| !meta.is_null()) {
            let meta = serde_json::from_value::<GeminiUsageMetadata>(raw_usage.clone())
                .map_err(|_| PureError::Protocol("invalid Gemini usageMetadata".into()))?;
            if let Some(report) = meta.to_usage_report() {
                events.push(ModelStreamEvent::Usage(report));
                usage_capture = Some(CapturedUsageObservation {
                    response_id: response_id.clone().or_else(|| self.response_id.clone()),
                    model: model_version.clone(),
                    service_tier: raw_usage
                        .get("serviceTier")
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                    usage: raw_usage.clone(),
                });
            }
        }

        if value.get("error").is_some() {
            let Some(parsed) = parse_google_http_error(data.as_bytes()) else {
                return Ok(self.fail_invalid_response(
                    events,
                    usage_capture,
                    request_id.map(redact),
                    "invalid Gemini error envelope",
                ));
            };
            self.failed = true;
            self.close_open_text_block(&mut events);
            let mut failure = pl_model_wire::provider_error::stream_failure(
                parsed.code.as_deref(),
                None,
                None,
                parsed
                    .message
                    .as_deref()
                    .map(redact)
                    .unwrap_or_else(|| "Gemini stream returned error".into()),
            );
            failure.code = parsed.code.as_deref().map(redact);
            failure.context.request_id = request_id.map(redact);
            if let Some(kind) = parsed.force_kind {
                failure.kind = kind;
            }
            if let Some(retry) = parsed.force_retry {
                failure.retry = retry;
            }
            events.push(ModelStreamEvent::Failed { failure });
            return Ok(DecodedSseFrame {
                events,
                usage_capture,
                reached_terminal: true,
            });
        }

        if !value.is_object()
            || value.get("responseId").is_some_and(|id| !id.is_string())
            || self
                .response_id
                .as_ref()
                .zip(response_id.as_ref())
                .is_some_and(|(old, new)| old != new)
        {
            return Ok(self.fail_invalid_response(
                events,
                usage_capture,
                request_id.map(redact),
                "Gemini response must be an object with a stable responseId",
            ));
        }
        if self.response_id.is_none() && response_id.is_some() {
            self.response_id.clone_from(&response_id);
        }
        if !self.sent_started {
            self.sent_started = true;
            events.insert(
                0,
                ModelStreamEvent::ResponseStarted {
                    response_id: self.response_id.clone(),
                },
            );
        }

        let candidate = match single_candidate(&value) {
            Ok(candidate) => candidate,
            Err(message) => {
                return Ok(self.fail_invalid_response(
                    events,
                    usage_capture,
                    request_id.map(redact),
                    message,
                ));
            }
        };
        let finish_reason = candidate
            .and_then(|c| c.get("finishReason"))
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .map(str::to_owned);

        if let Some(model) = &model_version {
            events.push(ModelStreamEvent::ResponseModelObserved {
                model: model.clone(),
                terminal: finish_reason.is_some(),
            });
        }

        if candidate.is_none()
            && let Some(block_reason) = value
                .get("promptFeedback")
                .and_then(|f| f.get("blockReason"))
                .and_then(Value::as_str)
                .filter(|s| !s.is_empty() && *s != "BLOCK_REASON_UNSPECIFIED")
        {
            self.failed = true;
            self.close_open_text_block(&mut events);
            events.push(ModelStreamEvent::Failed {
                failure: gemini_failure(
                    block_reason,
                    format!("Gemini prompt blocked: {block_reason}"),
                    request_id.map(redact),
                ),
            });
            return Ok(DecodedSseFrame {
                events,
                usage_capture,
                reached_terminal: true,
            });
        }

        if let Some(parts) = candidate
            .and_then(|c| c.get("content"))
            .and_then(|c| c.get("parts"))
            .and_then(Value::as_array)
        {
            for part in parts {
                if let Err(message) = validate_part(part) {
                    return Ok(self.fail_invalid_response(
                        events,
                        usage_capture,
                        request_id.map(redact),
                        message,
                    ));
                }
                if !is_ignorable_empty_part(part) {
                    events.push(ModelStreamEvent::Replay(ReplayUpdate::GeminiPart(
                        part.clone(),
                    )));
                }
                let is_thought = part.get("thought").and_then(Value::as_bool) == Some(true);
                if let Some(text) = part.get("text").and_then(Value::as_str)
                    && !text.is_empty()
                {
                    if is_thought {
                        events.push(ModelStreamEvent::ReasoningRawDelta {
                            id: "thinking".to_owned(),
                            content_index: 0,
                            delta: text.to_owned(),
                            provider: None,
                        });
                    } else {
                        self.saw_output = true;
                        let block_id = match &self.open_text_block {
                            Some(id) => id.clone(),
                            None => {
                                self.next_text_seq += 1;
                                let id = format!("final:{}", self.next_text_seq);
                                self.open_text_block = Some(id.clone());
                                events.push(ModelStreamEvent::BlockOpened {
                                    id: id.clone(),
                                    kind: ModelBlockKind::Text {
                                        channel: ModelTextChannel::Final,
                                    },
                                    provider_metadata: None,
                                    provider: None,
                                });
                                id
                            }
                        };
                        events.push(ModelStreamEvent::text_delta(
                            block_id,
                            ModelTextChannel::Final,
                            text.to_owned(),
                            None,
                        ));
                    }
                }
                let function_call = match gemini_function_call(part) {
                    Ok(function_call) => function_call,
                    Err(error) => {
                        return Ok(self.fail_invalid_response(
                            events,
                            usage_capture,
                            request_id.map(redact),
                            &error.to_string(),
                        ));
                    }
                };
                if let Some(fc_obj) = function_call {
                    let Some(name) = fc_obj
                        .get("name")
                        .and_then(Value::as_str)
                        .filter(|s| !s.is_empty())
                    else {
                        return Ok(self.fail_invalid_response(
                            events,
                            usage_capture,
                            request_id.map(redact),
                            "Gemini functionCall part missing name",
                        ));
                    };
                    let upstream_id = match gemini_function_call_id(fc_obj) {
                        Ok(id) => id,
                        Err(error) => {
                            return Ok(self.fail_invalid_response(
                                events,
                                usage_capture,
                                request_id.map(redact),
                                &error.to_string(),
                            ));
                        }
                    };
                    if let Some(id) = upstream_id
                        && !self.upstream_call_ids.insert(id.to_owned())
                    {
                        return Ok(self.fail_invalid_response(
                            events,
                            usage_capture,
                            request_id.map(redact),
                            "duplicate Gemini functionCall id in the same batch",
                        ));
                    }
                    self.close_open_text_block(&mut events);
                    self.saw_output = true;
                    self.next_tool_seq += 1;
                    let stream_id = Some(format!("gemini_tool:{}", self.next_tool_seq));
                    let item_id =
                        upstream_id.map_or_else(|| uuid::Uuid::new_v4().to_string(), str::to_owned);
                    let args_json = fc_obj
                        .get("args")
                        .map(Value::to_string)
                        .unwrap_or_else(|| "{}".into());
                    let call_id = Some(item_id.clone());
                    let payload = ToolInputDeltaPayload::FunctionArguments(args_json);
                    events.push(ModelStreamEvent::ToolInputDelta {
                        stream_id: stream_id.clone(),
                        item_id: item_id.clone(),
                        call_id: call_id.clone(),
                        name: Some(name.to_owned()),
                        payload_delta: payload.clone(),
                    });
                    events.push(ModelStreamEvent::ToolInputCompleted {
                        stream_id: stream_id.clone(),
                        item_id: item_id.clone(),
                        call_id: call_id.clone(),
                        name: Some(name.to_owned()),
                        payload: Some(payload.clone()),
                    });
                    events.push(ModelStreamEvent::ToolCallReady {
                        stream_id,
                        item_id,
                        call_id,
                        name: Some(name.to_owned()),
                        payload: Some(payload),
                    });
                }
            }
        }

        let mut reached_terminal = false;
        if let Some(reason) = finish_reason {
            match reason.as_str() {
                "STOP" => {
                    self.finished_ok = true;
                }
                other => {
                    self.failed = true;
                    reached_terminal = true;
                    self.close_open_text_block(&mut events);
                    events.push(ModelStreamEvent::Failed {
                        failure: gemini_failure(
                            other,
                            format!("Gemini generation terminated with finishReason={other}"),
                            request_id.map(redact),
                        ),
                    });
                }
            }
        }

        Ok(DecodedSseFrame {
            events,
            usage_capture,
            reached_terminal,
        })
    }

    fn finish(&mut self) -> Vec<ModelStreamEvent> {
        if self.failed || !self.finished_ok {
            return Vec::new();
        }
        self.finished_ok = false;
        let mut events = Vec::new();
        self.close_open_text_block(&mut events);
        if !self.saw_output {
            self.failed = true;
            events.push(ModelStreamEvent::Failed {
                failure: gemini_failure(
                    "invalid_response",
                    "Gemini STOP response contained no answer or function call".into(),
                    None,
                ),
            });
            return events;
        }
        events.push(ModelStreamEvent::Completed {
            response_id: self.response_id.take(),
        });
        events
    }
}

fn single_candidate(value: &Value) -> std::result::Result<Option<&Value>, &'static str> {
    let Some(candidates) = value.get("candidates").filter(|value| !value.is_null()) else {
        return Ok(None);
    };
    let candidates = candidates
        .as_array()
        .ok_or("Gemini candidates must be an array")?;
    if candidates.len() > 1 {
        return Err("Gemini supports exactly one response candidate");
    }
    let Some(candidate) = candidates.first() else {
        return Ok(None);
    };
    if !candidate.is_object()
        || candidate
            .get("index")
            .is_some_and(|index| index.as_u64() != Some(0))
    {
        return Err("Gemini candidate must be an object at index 0");
    }
    if let Some(content) = candidate
        .get("content")
        .filter(|content| !content.is_null())
        && (!content.is_object()
            || content
                .get("role")
                .is_some_and(|role| role.as_str() != Some("model"))
            || content.get("parts").is_some_and(|parts| !parts.is_array()))
    {
        return Err("Gemini candidate content must contain model parts");
    }
    if candidate
        .get("finishReason")
        .is_some_and(|reason| !reason.is_string())
    {
        return Err("Gemini finishReason must be a string");
    }
    Ok(Some(candidate))
}

fn validate_part(part: &Value) -> std::result::Result<(), &'static str> {
    if !part.is_object()
        || part.get("text").is_some_and(|text| !text.is_string())
        || part
            .get("thought")
            .is_some_and(|thought| !thought.is_boolean())
        || ["thoughtSignature", "thought_signature"]
            .into_iter()
            .any(|key| {
                part.get(key)
                    .is_some_and(|signature| !signature.is_string())
            })
    {
        return Err("Gemini part has invalid text, thought or signature fields");
    }
    if [
        "inlineData",
        "fileData",
        "executableCode",
        "codeExecutionResult",
        "functionResponse",
        "toolCall",
        "toolResponse",
    ]
    .into_iter()
    .any(|key| part.get(key).is_some())
    {
        return Err("Gemini generated media and server-side tool parts are unsupported");
    }
    if part.get("text").is_some()
        && (part.get("functionCall").is_some() || part.get("function_call").is_some())
    {
        return Err("Gemini part cannot combine text and functionCall");
    }
    Ok(())
}

fn gemini_failure(
    code: &str,
    message: String,
    request_id: Option<String>,
) -> pl_protocol::ProviderFailure {
    let mut failure =
        pl_model_wire::provider_error::stream_failure(Some(code), None, None, message);
    failure.context.request_id = request_id;
    match code {
        "MALFORMED_RESPONSE" => {
            failure.kind = ProviderFailureKind::Protocol;
            failure.retry = RetryDisposition::Retryable {
                retry_after_ms: None,
            };
        }
        "invalid_response" => failure.kind = ProviderFailureKind::Protocol,
        _ => {}
    }
    failure
}

fn is_ignorable_empty_part(part: &Value) -> bool {
    let Some(obj) = part.as_object() else {
        return false;
    };
    obj.len() == 1 && obj.get("text").and_then(Value::as_str) == Some("")
}
