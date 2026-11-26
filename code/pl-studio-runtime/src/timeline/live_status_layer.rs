//! Pure RAM Live Status state machine (`Idle` / `Working` / `StreamingText` / `Compacting` / `Reconnecting`).
//!
//! Never reads SQLite or `current.json`. Transitions immediately on `CoreLiveEvent` and
//! `HistoryEventKind`, with 16ms delta coalescing for `StreamingText`.

use std::{
    sync::Mutex,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use pl_core::model::ModelRecoveryPhase;
use pl_core::thread::CoreLiveEvent;

use crate::history::{HistoryEventKind, HistoryEventRecord, HistoryTimelineRole};

use super::models::{LiveAttention, LiveStatusPhase, LiveStatusSnapshot, LiveWorkItem};

pub const STREAMING_TEXT_COALESCE_INTERVAL: Duration = Duration::from_millis(16);
const REASONING_PREVIEW_LIMIT: usize = 240;

#[derive(Debug, Default)]
struct State {
    revision: u64,
    phase: Option<LiveStatusPhase>,
    working_items: Vec<LiveWorkItem>,
    reasoning_preview: Option<String>,
    reasoning_text: String,
    reasoning_dirty: bool,
    working_started_at_ms: Option<i64>,
    stream_text: String,
    stream_attempt_id: Option<String>,
    stream_item_id: Option<String>,
    stream_started_at_ms: Option<i64>,
    stream_dirty: bool,
    turn_active: bool,
    attentions: Vec<LiveAttention>,
    suppressed_by_interaction: bool,
}

impl State {
    fn current_phase(&self) -> LiveStatusPhase {
        self.phase.clone().unwrap_or(LiveStatusPhase::Idle)
    }

    fn snapshot(&self) -> LiveStatusSnapshot {
        LiveStatusSnapshot {
            revision: self.revision,
            phase: self.current_phase(),
            attentions: self.attentions.clone(),
            suppressed_by_interaction: self.suppressed_by_interaction,
        }
    }

    fn enter_working(&mut self, now_ms: i64) {
        if self.working_started_at_ms.is_none() {
            self.working_started_at_ms = Some(now_ms);
        }
        self.phase = Some(LiveStatusPhase::Working {
            items: self.working_items.clone(),
            reasoning_preview: self.reasoning_preview.clone(),
            started_at_ms: self.working_started_at_ms,
        });
    }

    fn enter_idle(&mut self) {
        self.phase = Some(LiveStatusPhase::Idle);
        self.working_items.clear();
        self.reasoning_preview = None;
        self.reasoning_text.clear();
        self.reasoning_dirty = false;
        self.working_started_at_ms = None;
        self.stream_text.clear();
        self.stream_attempt_id = None;
        self.stream_item_id = None;
        self.stream_started_at_ms = None;
        self.stream_dirty = false;
        self.turn_active = false;
    }

    fn upsert_work_item(&mut self, item: LiveWorkItem) {
        if let Some(existing) = self.working_items.iter_mut().find(|existing| {
            existing.id == item.id
                || (existing.call_id.is_some() && existing.call_id == item.call_id)
        }) {
            *existing = item;
        } else {
            self.working_items.push(item);
        }
    }
}

#[derive(Debug, Default)]
pub struct LiveStatusDataLayer {
    state: Mutex<State>,
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| i64::try_from(d.as_millis()).unwrap_or(i64::MAX))
}

fn bounded_tail_preview(text: &str) -> Option<String> {
    let trimmed = text.lines().rev().find(|l| !l.trim().is_empty())?.trim();
    if trimmed.is_empty() {
        return None;
    }
    let count = trimmed.chars().count();
    if count <= REASONING_PREVIEW_LIMIT {
        Some(trimmed.to_owned())
    } else {
        let skipped: String = trimmed.chars().skip(count - REASONING_PREVIEW_LIMIT).collect();
        Some(format!("…{skipped}"))
    }
}

impl LiveStatusDataLayer {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    #[must_use]
    pub fn snapshot(&self) -> LiveStatusSnapshot {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .snapshot()
    }

    /// Applies an ephemeral `CoreLiveEvent`. Returns `Some(snapshot)` if listeners should be
    /// notified immediately (`None` when a `TextStreamDelta` was buffered for 16ms coalescing).
    pub fn on_live_event(&self, event: &CoreLiveEvent) -> Option<LiveStatusSnapshot> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let now_ms = now_millis();

        match event {
            CoreLiveEvent::TextStreamStarted {
                attempt_id,
                item_id,
                ..
            } => {
                // Hand over the Working group container and immediately switch to StreamingText.
                state.working_items.clear();
                state.reasoning_preview = None;
                state.reasoning_text.clear();
                state.reasoning_dirty = false;
                state.stream_attempt_id = Some(attempt_id.clone());
                state.stream_item_id = Some(item_id.clone());
                state.stream_text.clear();
                state.stream_started_at_ms = Some(now_ms);
                state.stream_dirty = false;
                state.turn_active = true;
                state.phase = Some(LiveStatusPhase::StreamingText {
                    attempt_id: attempt_id.clone(),
                    item_id: item_id.clone(),
                    text: String::new(),
                    started_at_ms: state.stream_started_at_ms,
                });
                state.revision += 1;
                Some(state.snapshot())
            }
            CoreLiveEvent::TextStreamDelta {
                attempt_id,
                item_id,
                text,
                replace,
                ..
            } => {
                if *replace {
                    state.stream_text = text.clone();
                } else {
                    state.stream_text.push_str(text);
                }
                state.stream_attempt_id = Some(attempt_id.clone());
                state.stream_item_id = Some(item_id.clone());
                if state.stream_started_at_ms.is_none() {
                    state.stream_started_at_ms = Some(now_ms);
                }
                let need_immediate_transition =
                    !matches!(state.phase, Some(LiveStatusPhase::StreamingText { .. }));
                state.turn_active = true;
                if need_immediate_transition {
                    let full = state.stream_text.clone();
                    let started = state.stream_started_at_ms;
                    state.phase = Some(LiveStatusPhase::StreamingText {
                        attempt_id: attempt_id.clone(),
                        item_id: item_id.clone(),
                        text: full,
                        started_at_ms: started,
                    });
                    state.stream_dirty = false;
                    state.revision += 1;
                    Some(state.snapshot())
                } else {
                    state.stream_dirty = true;
                    None
                }
            }
            CoreLiveEvent::TextStreamEnded { .. } => {
                state.stream_dirty = false;
                state.stream_text.clear();
                state.stream_attempt_id = None;
                state.stream_item_id = None;
                state.stream_started_at_ms = None;
                if state.turn_active {
                    state.working_items.clear();
                    state.working_started_at_ms = Some(now_ms);
                    state.enter_working(now_ms);
                } else {
                    state.enter_idle();
                }
                state.revision += 1;
                Some(state.snapshot())
            }
            CoreLiveEvent::ReasoningDelta { text, replace, .. } => {
                if *replace {
                    state.reasoning_text = text.clone();
                } else {
                    state.reasoning_text.push_str(text);
                }
                state.reasoning_preview = bounded_tail_preview(&state.reasoning_text);
                state.turn_active = true;
                let need_immediate_transition =
                    !matches!(state.phase, Some(LiveStatusPhase::Working { .. }));
                if need_immediate_transition {
                    state.reasoning_dirty = false;
                    state.enter_working(now_ms);
                    state.revision += 1;
                    Some(state.snapshot())
                } else {
                    state.reasoning_dirty = true;
                    None
                }
            }
            CoreLiveEvent::ToolProgress {
                call_id,
                tool_id,
                progress,
                ..
            } => {
                state.turn_active = true;
                let preview = progress
                    .parts()
                    .last()
                    .and_then(|part| bounded_tail_preview(&part.text()))
                    .unwrap_or_else(|| tool_id.clone());
                state.upsert_work_item(LiveWorkItem {
                    id: format!("call:{call_id}"),
                    call_id: Some(call_id.clone()),
                    kind: "tool".into(),
                    tool_name: tool_id.clone(),
                    status: "running".into(),
                    summary: preview,
                    started_at_ms: Some(now_ms),
                });
                state.enter_working(now_ms);
                state.revision += 1;
                Some(state.snapshot())
            }
            CoreLiveEvent::CompactionStarted { manual, .. } => {
                state.stream_dirty = false;
                state.reasoning_dirty = false;
                state.working_items.clear();
                state.reasoning_preview = None;
                state.reasoning_text.clear();
                state.phase = Some(LiveStatusPhase::Compacting {
                    manual: *manual,
                    started_at_ms: Some(now_ms),
                });
                state.revision += 1;
                Some(state.snapshot())
            }
            CoreLiveEvent::ModelRecovery { attempt_id, status } => {
                state.stream_dirty = false;
                match status.phase {
                    ModelRecoveryPhase::Repairing
                    | ModelRecoveryPhase::Waiting
                    | ModelRecoveryPhase::Retrying => {
                        let phase_label = match status.phase {
                            ModelRecoveryPhase::Repairing => "Repairing",
                            ModelRecoveryPhase::Waiting => "Waiting to retry",
                            ModelRecoveryPhase::Retrying => "Retrying",
                            _ => unreachable!(),
                        };
                        state.phase = Some(LiveStatusPhase::Reconnecting {
                            attempt_id: attempt_id.clone(),
                            message: format!(
                                "{phase_label} ({}/{})",
                                status.retry, status.max_retries
                            ),
                            retry_after_ms: None,
                            attempt: status.retry,
                        });
                    }
                    ModelRecoveryPhase::Recovered
                    | ModelRecoveryPhase::Exhausted
                    | ModelRecoveryPhase::Failed
                    | ModelRecoveryPhase::Cancelled => {
                        if state.turn_active {
                            state.enter_working(now_ms);
                        } else {
                            state.enter_idle();
                        }
                    }
                }
                state.revision += 1;
                Some(state.snapshot())
            }
            CoreLiveEvent::ModelRecoveryCleared { .. } => {
                if matches!(state.phase, Some(LiveStatusPhase::Reconnecting { .. })) {
                    if state.turn_active {
                        state.enter_working(now_ms);
                    } else {
                        state.enter_idle();
                    }
                    state.revision += 1;
                    return Some(state.snapshot());
                }
                None
            }
            CoreLiveEvent::RunActivity { execution } => match execution {
                Some(_) => {
                    state.turn_active = true;
                    if matches!(state.current_phase(), LiveStatusPhase::Idle) {
                        state.enter_working(now_ms);
                        state.revision += 1;
                        return Some(state.snapshot());
                    }
                    None
                }
                None => {
                    if !matches!(state.current_phase(), LiveStatusPhase::Idle) || state.turn_active {
                        state.enter_idle();
                        state.suppressed_by_interaction = false;
                        state.revision += 1;
                        return Some(state.snapshot());
                    }
                    None
                }
            },
        }
    }

    /// Flushes coalesced `StreamingText` and `ReasoningDelta` updates (called on the 16ms ticker).
    pub fn flush_coalesced(&self) -> Option<LiveStatusSnapshot> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.stream_dirty {
            state.stream_dirty = false;
            if let (Some(attempt_id), Some(item_id)) = (
                state.stream_attempt_id.clone(),
                state.stream_item_id.clone(),
            ) {
                let text = state.stream_text.clone();
                let started_at_ms = state.stream_started_at_ms;
                state.phase = Some(LiveStatusPhase::StreamingText {
                    attempt_id,
                    item_id,
                    text,
                    started_at_ms,
                });
                state.revision += 1;
                return Some(state.snapshot());
            }
        }
        if state.reasoning_dirty {
            state.reasoning_dirty = false;
            if matches!(state.phase, Some(LiveStatusPhase::Working { .. })) {
                let now_ms = state.working_started_at_ms.unwrap_or_else(now_millis);
                state.enter_working(now_ms);
                state.revision += 1;
                return Some(state.snapshot());
            }
        }
        None
    }

    /// Updates state machine transitions triggered by durable `HistoryEventRecord` emissions.
    pub fn on_history_record(&self, record: &HistoryEventRecord) -> Option<LiveStatusSnapshot> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let now_ms = record.occurred_at.or(Some(record.recorded_at)).unwrap_or_else(now_millis);

        match &record.kind {
            HistoryEventKind::TurnStarted | HistoryEventKind::InputAccepted => {
                state.turn_active = true;
                state.suppressed_by_interaction = false;
                if matches!(state.current_phase(), LiveStatusPhase::Idle) {
                    state.enter_working(now_ms);
                    state.revision += 1;
                    return Some(state.snapshot());
                }
                None
            }
            HistoryEventKind::TurnEnded | HistoryEventKind::RunEnded => {
                state.enter_idle();
                state.attentions.clear();
                state.suppressed_by_interaction = false;
                state.revision += 1;
                Some(state.snapshot())
            }
            HistoryEventKind::CompactionCompleted => {
                if state.turn_active {
                    state.working_items.clear();
                    state.enter_working(now_ms);
                } else {
                    state.enter_idle();
                }
                state.revision += 1;
                Some(state.snapshot())
            }
            HistoryEventKind::TextCompleted => {
                state.stream_dirty = false;
                if matches!(state.current_phase(), LiveStatusPhase::StreamingText { .. }) {
                    if state.turn_active {
                        state.working_items.clear();
                        state.enter_working(now_ms);
                    } else {
                        state.enter_idle();
                    }
                    state.revision += 1;
                    return Some(state.snapshot());
                }
                None
            }
            HistoryEventKind::ToolCalled
            | HistoryEventKind::ToolWaitingApproval
            | HistoryEventKind::ToolBackgrounded
            | HistoryEventKind::ToolCancelRequested
            | HistoryEventKind::ToolCompleted
                if record.timeline_role == HistoryTimelineRole::Work =>
            {
                let call_id = record
                    .call_id
                    .clone()
                    .or_else(|| record.entity_id.clone())
                    .unwrap_or_else(|| record.event_id.clone());
                let tool_name = record
                    .tool_name
                    .clone()
                    .unwrap_or_else(|| "tool".into());
                let status = match record.kind {
                    HistoryEventKind::ToolCalled => "running",
                    HistoryEventKind::ToolWaitingApproval => "awaitingApproval",
                    HistoryEventKind::ToolBackgrounded => "backgrounded",
                    HistoryEventKind::ToolCancelRequested => "cancelling",
                    HistoryEventKind::ToolCompleted => "completed",
                    _ => "unknown",
                };
                state.attentions.retain(|a| a.call_id.as_deref() != Some(call_id.as_str()));
                if matches!(record.kind, HistoryEventKind::ToolWaitingApproval) {
                    state.suppressed_by_interaction = true;
                    state.attentions.push(LiveAttention {
                        id: format!("attn:{call_id}"),
                        kind: "approval".into(),
                        summary: tool_name.clone(),
                        call_id: Some(call_id.clone()),
                    });
                } else if state.attentions.is_empty() {
                    state.suppressed_by_interaction = false;
                }
                let item_id = format!("call:{call_id}");
                let preserved_summary = matches!(
                    record.kind,
                    HistoryEventKind::ToolCompleted
                        | HistoryEventKind::ToolBackgrounded
                        | HistoryEventKind::ToolCancelRequested
                )
                .then(|| {
                    state
                        .working_items
                        .iter()
                        .find(|existing| {
                            existing.id == item_id
                                || existing.call_id.as_deref() == Some(call_id.as_str())
                        })
                        .map(|existing| existing.summary.clone())
                })
                .flatten()
                .filter(|summary| !summary.is_empty() && summary != "tool" && summary != &tool_name)
                .unwrap_or_else(|| tool_name.clone());
                state.turn_active = true;
                state.upsert_work_item(LiveWorkItem {
                    id: item_id,
                    call_id: Some(call_id),
                    kind: "tool".into(),
                    tool_name,
                    status: status.into(),
                    summary: preserved_summary,
                    started_at_ms: Some(now_ms),
                });
                if !matches!(state.current_phase(), LiveStatusPhase::StreamingText { .. }) {
                    state.enter_working(now_ms);
                    state.revision += 1;
                    return Some(state.snapshot());
                }
                None
            }
            _ => None,
        }
    }
}
