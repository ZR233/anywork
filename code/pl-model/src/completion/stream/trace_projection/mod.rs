//! provider 流式增量到 trace part 的投影。
//!
//! 按域拆分:`text` 承载正文与 reasoning 流,`tool` 承载工具与 web search 流,
//! `ids` 承载 item id 解析与别名收敛;本模块保留投影状态、事件记录与
//! 终态收尾。

mod ids;
mod text;
mod tool;

use std::collections::HashMap;
use std::sync::Arc;

use crate::completion::CompletionTraceContext;
use crate::trace::{
    AgentEvent, InMemoryTraceEventSink, TraceEvent, TraceEventDraft, TraceEventKind,
    TraceEventSink, TraceEventSinkError, TracePart, TracePartAction, TracePartCompletion,
    TracePartSource, TracePartState, TraceToolFailureKind,
};

pub(crate) struct TraceProjection {
    turn_id: String,
    inference_id: String,
    started: HashMap<String, TracePart>,
    active_text_items: HashMap<String, String>,
    active_thinking_items: HashMap<String, String>,
    active_tool_items: HashMap<String, String>,
    segment_occurrences: HashMap<String, u64>,
    events: Vec<TraceEvent>,
    sink: Arc<dyn TraceEventSink>,
    trace_error: Option<TraceEventSinkError>,
}

impl TraceProjection {
    pub(crate) fn with_sink(
        context: CompletionTraceContext,
        sink: Option<Arc<dyn TraceEventSink>>,
    ) -> Self {
        let sink = sink.unwrap_or_else(|| {
            Arc::new(InMemoryTraceEventSink::new(context.session_id.clone(), 0))
        });
        Self {
            turn_id: context.turn_id,
            inference_id: context.inference_id,
            started: HashMap::new(),
            active_text_items: HashMap::new(),
            active_thinking_items: HashMap::new(),
            active_tool_items: HashMap::new(),
            segment_occurrences: HashMap::new(),
            events: Vec::new(),
            sink,
            trace_error: None,
        }
    }

    pub(crate) fn take_trace_error(&mut self) -> Option<TraceEventSinkError> {
        self.trace_error.take()
    }

    pub(crate) fn complete_streaming_items(&mut self) -> Vec<AgentEvent> {
        let items = self
            .started
            .values()
            .filter(|item| !item.is_terminal())
            .cloned()
            .collect::<Vec<_>>();
        let mut events = Vec::new();
        for item in items {
            let completion = match item.state() {
                TracePartState::Text(_) => TracePartCompletion::Text {
                    authoritative_content: None,
                },
                TracePartState::Thinking(_) => TracePartCompletion::Thinking {
                    authoritative_summary: None,
                },
                TracePartState::Tool(_) => continue,
            };
            events.extend(self.apply_item(item.item_id(), TracePartAction::Complete(completion)));
        }
        events
    }

    pub(crate) fn fail_attempt(&mut self, error: &str) -> Vec<AgentEvent> {
        self.settle_open(TracePartAction::Fail {
            error: error.to_owned(),
            tool_kind: TraceToolFailureKind::Execution,
        })
    }

    pub(crate) fn cancel_attempt(&mut self, reason: &str) -> Vec<AgentEvent> {
        self.settle_open(TracePartAction::Cancel {
            reason: reason.to_owned(),
        })
    }

    fn settle_open(&mut self, action: TracePartAction) -> Vec<AgentEvent> {
        let mut items = self
            .started
            .values()
            .filter(|item| !item.is_terminal())
            .cloned()
            .collect::<Vec<_>>();
        items.sort_by_key(TracePart::started_sequence);
        let mut events = Vec::new();
        for item in items {
            events.extend(self.apply_item(item.item_id(), action.clone()));
        }
        events
    }

    fn start_item(&mut self, item_id: String, state: TracePartState) -> Vec<AgentEvent> {
        self.record(TraceEventDraft::start(
            unix_seconds(),
            self.turn_id.clone(),
            item_id,
            TracePartSource::Model,
            state,
        ))
        .into_iter()
        .collect()
    }

    fn apply_item(&mut self, item_id: &str, action: TracePartAction) -> Vec<AgentEvent> {
        self.record(TraceEventDraft::apply(
            unix_seconds(),
            self.turn_id.clone(),
            item_id.to_owned(),
            action,
        ))
        .into_iter()
        .collect()
    }

    /// Only returned canonical events enter the producer's read projection and live stream.
    fn record(&mut self, draft: TraceEventDraft) -> Option<AgentEvent> {
        let event = match self.sink.emit(draft) {
            Ok(event) => event,
            Err(error) => {
                self.trace_error.get_or_insert(error);
                return None;
            }
        };
        let live = match &event.kind {
            TraceEventKind::TracePartStarted { item } => {
                self.started.insert(item.item_id().to_owned(), item.clone());
                AgentEvent::TracePartStarted { item: item.clone() }
            }
            TraceEventKind::TracePartCompleted { item } => {
                self.started.insert(item.item_id().to_owned(), item.clone());
                AgentEvent::TracePartCompleted { item: item.clone() }
            }
            TraceEventKind::TracePartFailed { item } => {
                self.started.insert(item.item_id().to_owned(), item.clone());
                AgentEvent::TracePartFailed { item: item.clone() }
            }
            TraceEventKind::TracePartDelta { event } => {
                let item = self.started.get_mut(&event.item_id)?;
                if let Err(error) = item.apply(item.command(
                    event.updated_at,
                    TracePartAction::Append(event.delta.clone()),
                )) {
                    self.trace_error
                        .get_or_insert_with(|| TraceEventSinkError::new(error.to_string()));
                    return None;
                }
                AgentEvent::TracePartDelta {
                    event: event.clone(),
                }
            }
        };
        self.events.push(event);
        Some(live)
    }
}

fn unix_seconds() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}
