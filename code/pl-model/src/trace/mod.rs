//! 模型流式完成增量与 trace 生命周期事件。

mod part;
mod sink;

use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;

pub use part::*;
pub use sink::*;

pub type AgentEventSender = broadcast::Sender<AgentEvent>;
pub type AgentEventReceiver = broadcast::Receiver<AgentEvent>;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum AgentEvent {
    TracePartStarted { item: TracePart },
    TracePartDelta { event: TracePartDeltaEvent },
    TracePartCompleted { item: TracePart },
    TracePartFailed { item: TracePart },
}

/// Append-only internal trace event for model streaming diagnostics.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TraceEvent {
    pub session_id: String,
    pub sequence: u64,
    pub timestamp: i64,
    pub kind: TraceEventKind,
}

impl TraceEvent {
    /// The turn that owns this event, independent of the active session projection.
    pub fn turn_id(&self) -> &str {
        match &self.kind {
            TraceEventKind::TracePartStarted { item }
            | TraceEventKind::TracePartCompleted { item }
            | TraceEventKind::TracePartFailed { item } => item.turn_id(),
            TraceEventKind::TracePartDelta { event } => &event.turn_id,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "type"
)]
pub enum TraceEventKind {
    TracePartStarted { item: TracePart },
    TracePartDelta { event: TracePartDeltaEvent },
    TracePartCompleted { item: TracePart },
    TracePartFailed { item: TracePart },
}
