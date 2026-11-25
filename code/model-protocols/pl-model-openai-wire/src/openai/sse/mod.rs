use serde::Deserialize;

use crate::completion::ModelTextChannel;
use crate::completion::stream::event::{ModelStreamEvent, ToolInputDeltaPayload};
use crate::openai::identity::responses_tool_identity;

mod decoder;
mod item;

pub use decoder::OpenAiStreamDecoder;
use item::{
    output_item_native_context, output_item_tool_completed, output_item_tool_started,
    web_search_lifecycle_event,
};

/// SSE 流事件原始结构（从 JSON 解析）
#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct SseStreamEvent {
    pub id: Option<String>,
    pub model: Option<String>,
    #[serde(rename = "type")]
    #[serde(default)]
    pub kind: String,
    pub delta: Option<String>,
    pub item: Option<serde_json::Value>,
    pub part: Option<serde_json::Value>,
    pub item_id: Option<String>,
    pub call_id: Option<String>,
    pub response: Option<serde_json::Value>,
    pub summary_index: Option<i64>,
    pub content_index: Option<i64>,
    pub output_index: Option<u32>,
    pub choices: Option<Vec<ChatStreamChoice>>,
}

impl SseStreamEvent {
    pub(crate) fn chat_has_finish_reason(&self) -> bool {
        self.choices.as_ref().is_some_and(|choices| {
            choices.iter().any(|choice| {
                choice
                    .finish_reason
                    .as_deref()
                    .is_some_and(|reason| !reason.is_empty())
            })
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct ChatStreamChoice {
    pub delta: ChatStreamDelta,
    pub finish_reason: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct ChatStreamDelta {
    pub content: Option<String>,
    pub reasoning_content: Option<String>,
    pub tool_calls: Option<Vec<ChatStreamToolCallDelta>>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ChatStreamToolCallDelta {
    pub index: Option<usize>,
    pub id: Option<String>,
    pub function: Option<ChatStreamFunctionDelta>,
    pub custom: Option<ChatStreamCustomDelta>,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct ChatStreamFunctionDelta {
    pub name: Option<String>,
    pub arguments: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct ChatStreamCustomDelta {
    pub name: Option<String>,
    pub input: Option<String>,
}

const DEFAULT_TEXT_ID: &str = "final";
const DEFAULT_REASONING_ID: &str = "thinking";
/// Chat Completions chunk 的 delta 解析；非 chat 事件（无 choices）返回 `None`。
fn chat_choice_events(event: &SseStreamEvent) -> Option<Vec<ModelStreamEvent>> {
    let choices = event.choices.as_ref()?;
    let mut events = Vec::new();
    let Some(choice) = choices.first() else {
        return Some(events);
    };
    if let Some(delta) = &choice.delta.reasoning_content
        && !delta.is_empty()
    {
        events.push(ModelStreamEvent::ReasoningRawDelta {
            id: DEFAULT_REASONING_ID.to_string(),
            content_index: 0,
            delta: delta.clone(),
            // Chat Completions reports no provider item identity; the raw reasoning is observed as
            // the request-scoped reasoning channel rather than a synthetic item.
            provider: None,
        });
    }

    if let Some(content) = &choice.delta.content
        && !content.is_empty()
    {
        events.push(ModelStreamEvent::text_delta(
            DEFAULT_TEXT_ID.to_string(),
            ModelTextChannel::Final,
            content.clone(),
            None,
        ));
    }

    if let Some(tool_calls) = &choice.delta.tool_calls {
        for tool_call in tool_calls {
            let index = tool_call.index.unwrap_or_default();
            let stream_id = Some(format!("chat_tool_call:{index}"));
            let item_id = tool_call.id.clone().unwrap_or_default();
            // Chat Completions 只暴露 item id；确定性赋 call_id = item_id。
            let call_id = (!item_id.is_empty()).then(|| item_id.clone());
            if let Some(custom) = &tool_call.custom {
                events.push(ModelStreamEvent::ToolInputDelta {
                    stream_id,
                    item_id,
                    call_id,
                    name: custom.name.clone(),
                    payload_delta: ToolInputDeltaPayload::CustomInput(
                        custom.input.clone().unwrap_or_default(),
                    ),
                });
                continue;
            }
            if let Some(function) = &tool_call.function {
                events.push(ModelStreamEvent::ToolInputDelta {
                    stream_id,
                    item_id,
                    call_id,
                    name: function.name.clone(),
                    payload_delta: ToolInputDeltaPayload::FunctionArguments(
                        function.arguments.clone().unwrap_or_default(),
                    ),
                });
            }
        }
    }

    (!events.is_empty()).then_some(events)
}

/// 将原始 SSE 事件解析为 canonical stream event。
pub fn process_sse_events(event: &SseStreamEvent) -> Vec<ModelStreamEvent> {
    let mut events = match process_sse_event(event) {
        Some(StreamEventBatch::Single(event)) => vec![event],
        Some(StreamEventBatch::Many(events)) => events,
        None => Vec::new(),
    };
    if let Some(model_observation) = response_model_observation(event) {
        events.insert(0, model_observation);
    }
    events
}

pub(super) fn response_model_observation(event: &SseStreamEvent) -> Option<ModelStreamEvent> {
    reported_model(event).map(|model| ModelStreamEvent::ResponseModelObserved {
        model,
        terminal: model_declaration_is_terminal(event),
    })
}

fn reported_model(event: &SseStreamEvent) -> Option<String> {
    event
        .response
        .as_ref()
        .and_then(|response| response.get("model"))
        .and_then(serde_json::Value::as_str)
        .map(str::to_owned)
        .or_else(|| event.model.clone())
}

fn model_declaration_is_terminal(event: &SseStreamEvent) -> bool {
    matches!(
        event.kind.as_str(),
        "response.completed" | "response.failed" | "response.incomplete"
    ) || event.chat_has_finish_reason()
}

enum StreamEventBatch {
    Single(ModelStreamEvent),
    Many(Vec<ModelStreamEvent>),
}

fn process_sse_event(event: &SseStreamEvent) -> Option<StreamEventBatch> {
    if let Some(event) = web_search_lifecycle_event(event) {
        return Some(StreamEventBatch::Single(event));
    }
    if let Some(events) = chat_choice_events(event) {
        return Some(StreamEventBatch::Many(events));
    }

    match event.kind.as_str() {
        "response.created" => Some(StreamEventBatch::Single(
            ModelStreamEvent::ResponseStarted {
                response_id: event
                    .response
                    .as_ref()
                    .and_then(|r| r.get("id")?.as_str().map(String::from)),
            },
        )),

        // Responses text and reasoning deltas are decoded by the stateful decoder, which resolves
        // the item identity an event omits from the `output_index` it announced and rejects an
        // unresolvable delta instead of inventing a default item. Chat content arrives through
        // `chat_choice_events` above, so this fallback never fabricates those identities.
        "response.function_call_arguments.delta" => {
            let (item_id, call_id) = responses_tool_identity(
                event.item_id.as_deref(),
                event.call_id.as_deref(),
                &event.kind,
            );
            Some(StreamEventBatch::Single(ModelStreamEvent::ToolInputDelta {
                stream_id: None,
                item_id,
                call_id: Some(call_id),
                name: None,
                payload_delta: ToolInputDeltaPayload::FunctionArguments(
                    event.delta.clone().unwrap_or_default(),
                ),
            }))
        }

        "response.custom_tool_call_input.delta" => {
            let (item_id, call_id) = responses_tool_identity(
                event.item_id.as_deref(),
                event.call_id.as_deref(),
                &event.kind,
            );
            Some(StreamEventBatch::Single(ModelStreamEvent::ToolInputDelta {
                stream_id: None,
                item_id,
                call_id: Some(call_id),
                name: None,
                payload_delta: ToolInputDeltaPayload::CustomInput(
                    event.delta.clone().unwrap_or_default(),
                ),
            }))
        }

        "response.output_item.added" => event
            .item
            .as_ref()
            .and_then(output_item_tool_started)
            .map(StreamEventBatch::Single),

        "response.output_item.done" => event.item.as_ref().and_then(|item| {
            let mut events = output_item_tool_completed(item).unwrap_or_default();
            if let Some(native) = output_item_native_context(item) {
                events.push(native);
            }
            (!events.is_empty()).then_some(StreamEventBatch::Many(events))
        }),

        "response.completed" => Some(StreamEventBatch::Single(ModelStreamEvent::Completed {
            response_id: event
                .response
                .as_ref()
                .and_then(|r| r.get("id")?.as_str().map(String::from)),
        })),

        _ => None,
    }
}

mod replay;
pub use replay::replay_update;
