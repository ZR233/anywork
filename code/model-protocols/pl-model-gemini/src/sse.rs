use std::collections::BTreeSet;

use pl_model_wire::completion::ModelTextChannel;
use pl_model_wire::completion::replay::{gemini_function_call, gemini_function_call_id};
use pl_model_wire::completion::stream::event::{
    ModelBlockKind, ModelStreamEvent, ToolInputDeltaPayload,
};
use pl_model_wire::completion::stream::replay::ReplayUpdate;
use pl_model_wire::provider_error::{ClassifiedProviderError, StreamFrameContext};
use pl_model_wire::wire_codec::{CapturedUsageObservation, DecodedSseFrame, WireStreamDecoder};
use pl_protocol::{ProviderFailure, Result};
use serde_json::Value;

use crate::error::google_error_envelope;
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
    incomplete_failure: Option<ProviderFailure>,
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
            incomplete_failure: None,
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
        value: &Value,
        terminal_usage: bool,
        failure: ProviderFailure,
    ) -> DecodedSseFrame {
        self.failed = true;
        self.close_open_text_block(&mut events);
        let usage_capture = append_usage(
            value,
            self.response_id.as_deref(),
            terminal_usage,
            &mut events,
        );
        events.push(ModelStreamEvent::Failed { failure });
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
        context: &StreamFrameContext<'_>,
    ) -> Result<DecodedSseFrame> {
        if self.failed {
            return Ok(DecodedSseFrame {
                events: Vec::new(),
                usage_capture: None,
                reached_terminal: true,
            });
        }

        let value: Value = serde_json::from_str(data).map_err(|error| {
            context
                .protocol_failure("invalid Gemini SSE JSON")
                .with_source(error)
        })?;
        let failure = context.decode_failure(&value);
        let error_envelope = google_error_envelope(&value);
        if error_envelope.is_some() || (failure.is_some() && !value.is_object()) {
            self.failed = true;
            let mut events = Vec::new();
            self.close_open_text_block(&mut events);
            let usage_capture = error_envelope.and_then(|envelope| {
                append_usage(envelope, self.response_id.as_deref(), true, &mut events)
            });
            let failure = failure.unwrap_or_else(|| {
                ClassifiedProviderError::from_http_status(None).into_failure(&context.failure)
            });
            events.push(ModelStreamEvent::Failed { failure });
            return Ok(DecodedSseFrame {
                events,
                usage_capture,
                reached_terminal: true,
            });
        }
        if !value.is_object()
            || ![
                "candidates",
                "promptFeedback",
                "usageMetadata",
                "responseId",
                "modelVersion",
            ]
            .iter()
            .any(|field| value.get(field).is_some())
        {
            return Err(context
                .protocol_failure("invalid Gemini stream event")
                .into());
        }
        if failure.is_none() {
            let invalid_finish_reason = value
                .get("candidates")
                .and_then(Value::as_array)
                .is_some_and(|candidates| {
                    candidates.iter().any(|candidate| {
                        candidate
                            .get("finishReason")
                            .is_some_and(|reason| !reason.is_string())
                    })
                });
            let invalid_block_reason = value
                .get("promptFeedback")
                .and_then(|feedback| feedback.get("blockReason"))
                .is_some_and(|reason| !reason.is_string());
            if invalid_finish_reason || invalid_block_reason {
                let failure = context.protocol_failure("invalid Gemini termination reason");
                let mut events = Vec::new();
                let Some(usage_capture) =
                    append_usage(&value, self.response_id.as_deref(), false, &mut events)
                else {
                    return Err(failure.into());
                };
                self.failed = true;
                self.close_open_text_block(&mut events);
                events.push(ModelStreamEvent::Failed { failure });
                return Ok(DecodedSseFrame {
                    events,
                    usage_capture: Some(usage_capture),
                    reached_terminal: true,
                });
            }
        }

        let mut events = Vec::new();
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
        if let Some(raw_usage) = value.get("usageMetadata").filter(|meta| !meta.is_null()) {
            serde_json::from_value::<GeminiUsageMetadata>(raw_usage.clone()).map_err(|error| {
                context
                    .protocol_failure("invalid Gemini usageMetadata")
                    .with_source(error)
            })?;
        }
        let terminal_usage = failure.is_some()
            || self.finished_ok
            || value
                .get("candidates")
                .and_then(Value::as_array)
                .is_some_and(|candidates| {
                    candidates.iter().any(|candidate| {
                        candidate
                            .get("finishReason")
                            .and_then(Value::as_str)
                            .is_some_and(|reason| {
                                !matches!(reason, "" | "FINISH_REASON_UNSPECIFIED")
                            })
                    })
                });
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
                &value,
                terminal_usage,
                context
                    .protocol_failure("Gemini response must be an object with a stable responseId"),
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
                    &value,
                    terminal_usage,
                    context.protocol_failure(message),
                ));
            }
        };
        let finish_reason = candidate
            .and_then(|c| c.get("finishReason"))
            .and_then(Value::as_str);
        if finish_reason == Some("FINISH_REASON_UNSPECIFIED") {
            // The protobuf default is not a terminal reason. Preserve it for diagnostics
            // if EOF arrives without STOP, without cutting off later signed parts.
            let mut failure =
                context.protocol_failure("Gemini stream ended without a terminal finishReason");
            failure.code = Some("FINISH_REASON_UNSPECIFIED".to_owned());
            self.incomplete_failure = Some(failure);
        }
        let finish_reason =
            finish_reason.filter(|reason| !matches!(*reason, "" | "FINISH_REASON_UNSPECIFIED"));

        if let Some(model) = &model_version {
            events.push(ModelStreamEvent::ResponseModelObserved {
                model: model.clone(),
                terminal: finish_reason.is_some(),
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
                        &value,
                        terminal_usage,
                        context.protocol_failure(message),
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
                            &value,
                            terminal_usage,
                            context
                                .protocol_failure(error.to_string())
                                .with_source(error),
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
                            &value,
                            terminal_usage,
                            context.protocol_failure("Gemini functionCall part missing name"),
                        ));
                    };
                    let upstream_id = match gemini_function_call_id(fc_obj) {
                        Ok(id) => id,
                        Err(error) => {
                            return Ok(self.fail_invalid_response(
                                events,
                                &value,
                                terminal_usage,
                                context
                                    .protocol_failure(error.to_string())
                                    .with_source(error),
                            ));
                        }
                    };
                    if let Some(id) = upstream_id
                        && !self.upstream_call_ids.insert(id.to_owned())
                    {
                        return Ok(self.fail_invalid_response(
                            events,
                            &value,
                            terminal_usage,
                            context.protocol_failure(
                                "duplicate Gemini functionCall id in the same batch",
                            ),
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

        let usage_capture = append_usage(
            &value,
            self.response_id.as_deref(),
            terminal_usage,
            &mut events,
        );

        let reached_terminal = failure.is_some();
        if let Some(failure) = failure {
            self.failed = true;
            self.close_open_text_block(&mut events);
            events.push(ModelStreamEvent::Failed { failure });
        } else if finish_reason == Some("STOP") {
            self.finished_ok = true;
        }

        Ok(DecodedSseFrame {
            events,
            usage_capture,
            reached_terminal,
        })
    }

    fn finish(&mut self) -> Vec<ModelStreamEvent> {
        if self.failed {
            return Vec::new();
        }
        if !self.finished_ok {
            return self
                .incomplete_failure
                .take()
                .map(|failure| ModelStreamEvent::Failed { failure })
                .into_iter()
                .collect();
        }
        self.finished_ok = false;
        let mut events = Vec::new();
        self.close_open_text_block(&mut events);
        if !self.saw_output {
            self.failed = true;
            events.push(ModelStreamEvent::Failed {
                failure: ProviderFailure::new(
                    pl_protocol::ProviderFailureKind::Protocol,
                    "Gemini STOP response contained no answer or function call",
                    pl_protocol::RetryDisposition::Permanent,
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

fn append_usage(
    value: &Value,
    response_id: Option<&str>,
    terminal: bool,
    events: &mut Vec<ModelStreamEvent>,
) -> Option<CapturedUsageObservation> {
    let meta: GeminiUsageMetadata =
        serde_json::from_value(value.get("usageMetadata")?.clone()).ok()?;
    let usage = meta.to_usage_report()?;
    events.push(ModelStreamEvent::Usage { usage, terminal });
    Some(CapturedUsageObservation {
        response_id: value
            .get("responseId")
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
            .or(response_id)
            .map(str::to_owned),
        model: value
            .get("modelVersion")
            .and_then(Value::as_str)
            .filter(|model| !model.is_empty())
            .map(str::to_owned),
        service_tier: value
            .get("usageMetadata")?
            .get("serviceTier")
            .and_then(Value::as_str)
            .map(str::to_owned),
        usage: value.get("usageMetadata")?.clone(),
    })
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

fn is_ignorable_empty_part(part: &Value) -> bool {
    let Some(obj) = part.as_object() else {
        return false;
    };
    obj.len() == 1 && obj.get("text").and_then(Value::as_str) == Some("")
}
