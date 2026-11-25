use pl_model_wire::completion::ModelTextChannel;
use pl_model_wire::completion::replay::{gemini_function_call, gemini_function_call_id};
use pl_model_wire::completion::stream::event::{
    ModelBlockKind, ModelStreamEvent, ToolInputDeltaPayload,
};
use pl_model_wire::completion::stream::replay::ReplayUpdate;
use pl_model_wire::wire_codec::{CapturedUsageObservation, DecodedSseFrame, WireStreamDecoder};
use pl_protocol::{PureError, Result};
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
        request_id: Option<String>,
        message: &str,
    ) -> DecodedSseFrame {
        self.failed = true;
        self.close_open_text_block(&mut events);
        events.push(ModelStreamEvent::Failed {
            request_id,
            code: Some("invalid_response".into()),
            http_status: None,
            retry_after_ms: None,
            message: message.into(),
        });
        DecodedSseFrame {
            events,
            usage_capture: None,
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

        if value.get("error").is_some()
            && let Some(parsed) = parse_google_http_error(data.as_bytes())
        {
            self.failed = true;
            let mut events = Vec::new();
            self.close_open_text_block(&mut events);
            events.push(ModelStreamEvent::Failed {
                request_id: request_id.map(redact),
                code: parsed.code.map(|c| redact(&c)),
                http_status: None,
                retry_after_ms: None,
                message: parsed
                    .message
                    .map(|m| redact(&m))
                    .unwrap_or_else(|| "Gemini stream returned error".into()),
            });
            return Ok(DecodedSseFrame {
                events,
                usage_capture: None,
                reached_terminal: true,
            });
        }

        let mut events = Vec::new();
        let response_id = value
            .get("responseId")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .map(str::to_owned);
        if self.response_id.is_none() && response_id.is_some() {
            self.response_id.clone_from(&response_id);
        }
        if !self.sent_started {
            self.sent_started = true;
            events.push(ModelStreamEvent::ResponseStarted {
                response_id: self.response_id.clone(),
            });
        }

        let candidate = value
            .get("candidates")
            .and_then(Value::as_array)
            .and_then(|list| list.first());
        let finish_reason = candidate
            .and_then(|c| c.get("finishReason"))
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .map(str::to_owned);

        let model_version = value
            .get("modelVersion")
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
                .filter(|s| !s.is_empty())
        {
            self.failed = true;
            self.close_open_text_block(&mut events);
            events.push(ModelStreamEvent::Failed {
                request_id: request_id.map(redact),
                code: Some(block_reason.to_owned()),
                http_status: None,
                retry_after_ms: None,
                message: format!("Gemini prompt blocked: {block_reason}"),
            });
            return Ok(DecodedSseFrame {
                events,
                usage_capture: None,
                reached_terminal: true,
            });
        }

        if let Some(parts) = candidate
            .and_then(|c| c.get("content"))
            .and_then(|c| c.get("parts"))
            .and_then(Value::as_array)
        {
            for part in parts {
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
                            request_id.map(redact),
                            "Gemini functionCall part missing name",
                        ));
                    };
                    let upstream_id = match gemini_function_call_id(fc_obj) {
                        Ok(id) => id,
                        Err(error) => {
                            return Ok(self.fail_invalid_response(
                                events,
                                request_id.map(redact),
                                &error.to_string(),
                            ));
                        }
                    };
                    self.close_open_text_block(&mut events);
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

        let mut usage_capture = None;
        if let Some(meta_value) = value.get("usageMetadata")
            && let Ok(meta) = serde_json::from_value::<GeminiUsageMetadata>(meta_value.clone())
            && let Some(report) = meta.to_usage_report()
        {
            if let Ok(usage_json) = serde_json::to_value(&meta) {
                usage_capture = Some(CapturedUsageObservation {
                    response_id: self.response_id.clone(),
                    model: model_version,
                    service_tier: None,
                    usage: usage_json,
                });
            }
            events.push(ModelStreamEvent::Usage(report));
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
                        request_id: request_id.map(redact),
                        code: Some(other.to_owned()),
                        http_status: None,
                        retry_after_ms: None,
                        message: format!("Gemini generation terminated with finishReason={other}"),
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
        let mut events = Vec::new();
        self.close_open_text_block(&mut events);
        events.push(ModelStreamEvent::Completed {
            response_id: self.response_id.take(),
        });
        events
    }
}

fn is_ignorable_empty_part(part: &Value) -> bool {
    let Some(obj) = part.as_object() else {
        return false;
    };
    obj.len() == 1 && obj.get("text").and_then(Value::as_str) == Some("")
}
