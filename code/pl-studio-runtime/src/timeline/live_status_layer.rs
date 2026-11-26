//! Pure RAM Live Status state machine (`Idle` / `Working` / `StreamingText` / `Compacting` / `Reconnecting` / `Stopping`).
//!
//! Never reads SQLite or `current.json`. Reuses `HistoryTimelineRole` semantics:
//! - `Hidden` controls lifecycle (`TurnStarted` -> `Working`, `TurnEnded`/`RunEnded` -> `Idle`).
//! - `Work` and ephemeral reasoning/tool progress accumulate in the current `Working` container.
//! - `Boundary` and ephemeral display transitions (`TextStream*`, `CompactionStarted`,
//!   `ModelRecovery`, `Stopping`) immediately switch phase and reset the working container,
//!   naturally segmenting work groups in sync with `TimelineDataLayer`.

use std::{
    sync::Mutex,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use pl_core::model::ModelRecoveryPhase;
use pl_core::thread::{CoreLiveEvent, ExecutionPhase};

use crate::ChatTerminalOutcome;
use crate::history::{
    HistoryBodyRole, HistoryEntityState, HistoryEventKind, HistoryEventRecord, HistoryTimelineRole,
    decode_event_envelope,
};

use super::models::{LiveAttention, LiveStatusPhase, LiveStatusSnapshot, LiveWorkItem};

pub const STREAMING_TEXT_COALESCE_INTERVAL: Duration = Duration::from_millis(16);
const REASONING_PREVIEW_LIMIT: usize = 240;
const TOOL_SUMMARY_LIMIT: usize = 160;

#[derive(Debug, Default)]
struct State {
    revision: u64,
    phase: Option<LiveStatusPhase>,
    working_items: Vec<LiveWorkItem>,
    reasoning_preview: Option<String>,
    reasoning_summary_text: String,
    reasoning_body_text: String,
    reasoning_dirty: bool,
    working_started_at_ms: Option<i64>,
    stream_text: String,
    stream_attempt_id: Option<String>,
    stream_item_id: Option<String>,
    stream_started_at_ms: Option<i64>,
    stream_dirty: bool,
    turn_active: bool,
    stopping: bool,
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

    fn clear_working_container(&mut self) {
        self.working_items.clear();
        self.reasoning_preview = None;
        self.reasoning_summary_text.clear();
        self.reasoning_body_text.clear();
        self.reasoning_dirty = false;
        self.working_started_at_ms = None;
    }

    fn clear_stream_buffer(&mut self) {
        self.stream_text.clear();
        self.stream_attempt_id = None;
        self.stream_item_id = None;
        self.stream_started_at_ms = None;
        self.stream_dirty = false;
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

    fn enter_fresh_working(&mut self, now_ms: i64) {
        self.clear_working_container();
        self.enter_working(now_ms);
    }

    fn enter_stopping(&mut self, now_ms: i64) {
        self.stopping = true;
        self.clear_working_container();
        self.clear_stream_buffer();
        let started = match self.phase {
            Some(LiveStatusPhase::Stopping { started_at_ms }) => started_at_ms.or(Some(now_ms)),
            _ => Some(now_ms),
        };
        self.phase = Some(LiveStatusPhase::Stopping {
            started_at_ms: started,
        });
    }

    fn enter_idle(&mut self) {
        self.phase = Some(LiveStatusPhase::Idle);
        self.clear_working_container();
        self.clear_stream_buffer();
        self.turn_active = false;
        self.stopping = false;
        self.attentions.clear();
        self.suppressed_by_interaction = false;
    }

    fn upsert_work_item(&mut self, item: LiveWorkItem) {
        if let Some(existing) = self.working_items.iter_mut().find(|existing| {
            existing.id == item.id
                || (existing.call_id.is_some() && existing.call_id == item.call_id)
        }) {
            let started_at_ms = existing.started_at_ms.or(item.started_at_ms);
            let kind = if existing.kind == "tool" && item.kind != "tool" {
                item.kind
            } else {
                existing.kind.clone()
            };
            let should_replace_summary = is_informative_summary(&item.summary, &item.tool_name)
                && (item.finished_at_ms.is_none()
                    || !is_informative_summary(&existing.summary, &existing.tool_name));
            let summary = if should_replace_summary {
                item.summary
            } else {
                existing.summary.clone()
            };
            existing.status = item.status;
            existing.kind = kind;
            existing.summary = summary;
            existing.started_at_ms = started_at_ms;
            if item.finished_at_ms.is_some() {
                existing.finished_at_ms = item.finished_at_ms;
            }
        } else {
            self.working_items.push(item);
        }
    }

    fn upsert_reasoning_completed(
        &mut self,
        entity_id: &str,
        summary: Option<String>,
        status: String,
        started_at_ms: Option<i64>,
        finished_at_ms: i64,
    ) {
        let exact_id = format!("reasoning:{entity_id}");
        let idx = self
            .working_items
            .iter()
            .position(|item| item.id == exact_id)
            .or_else(|| {
                self.working_items
                    .iter()
                    .rposition(|item| item.kind == "thinking" && item.status == "running")
            });
        let clean_summary = summary.as_deref().and_then(bounded_tail_preview);
        if let Some(summary_text) = &clean_summary
            && self.reasoning_summary_text.trim().is_empty()
        {
            self.reasoning_preview = Some(summary_text.clone());
        }
        if let Some(idx) = idx {
            let existing = &mut self.working_items[idx];
            existing.status = status;
            existing.started_at_ms = existing.started_at_ms.or(started_at_ms);
            existing.finished_at_ms = Some(finished_at_ms);
            if let Some(summary_text) = clean_summary {
                existing.summary = summary_text;
            }
        } else {
            self.working_items.push(LiveWorkItem {
                id: exact_id,
                call_id: None,
                kind: "thinking".into(),
                tool_name: "thinking".into(),
                status,
                summary: clean_summary.unwrap_or_default(),
                started_at_ms: started_at_ms.or(Some(finished_at_ms)),
                finished_at_ms: Some(finished_at_ms),
            });
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

fn truncate_single_line(text: &str, max_chars: usize) -> Option<String> {
    let single = text
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())?
        .trim();
    if single.is_empty() {
        return None;
    }
    let count = single.chars().count();
    if count <= max_chars {
        Some(single.to_owned())
    } else {
        let head: String = single.chars().take(max_chars.saturating_sub(1)).collect();
        Some(format!("{head}…"))
    }
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
        let skipped: String = trimmed
            .chars()
            .skip(count - REASONING_PREVIEW_LIMIT)
            .collect();
        Some(format!("…{skipped}"))
    }
}

fn is_informative_summary(summary: &str, tool_name: &str) -> bool {
    let trimmed = summary.trim();
    !trimmed.is_empty() && trimmed != "tool" && trimmed != tool_name
}

fn classify_live_tool_kind(tool_name: &str, contract: Option<&str>) -> &'static str {
    let normalized = tool_name.trim();
    if matches!(
        normalized,
        "exec" | "exec_command" | "shell" | "write_stdin" | "bash"
    ) || contract.is_some_and(|c| c.contains("exec"))
    {
        return "command";
    }
    if matches!(normalized, "view_image" | "read_image") {
        return "readImage";
    }
    if matches!(
        normalized,
        "read_file" | "read" | "read_session_note" | "stat_path"
    ) {
        return "read";
    }
    if matches!(
        normalized,
        "grep"
            | "find_files"
            | "web_search"
            | "deepseek_web_search"
            | "deepseek_web_fetch"
            | "search_session_note"
            | "lsp_query"
            | "lsp_capabilities"
            | "lsp_status"
    ) {
        return "search";
    }
    if matches!(
        normalized,
        "apply_patch"
            | "edit_file"
            | "write_file"
            | "create_directory"
            | "delete_path"
            | "move_path"
            | "copy_path"
            | "apply_session_note_patch"
            | "write_session_note"
    ) {
        return "edit";
    }
    if matches!(normalized, "wait" | "sleep") {
        return "wait";
    }
    if matches!(normalized, "spawn_agent" | "send_message" | "delegate") {
        return "agent";
    }
    "tool"
}

fn extract_argument_summary(arguments_json: &str) -> Option<String> {
    let trimmed = arguments_json.trim();
    if trimmed.is_empty() {
        return None;
    }
    if let Ok(value) = serde_json::from_str::<serde_json::Value>(trimmed)
        && let Some(obj) = value.as_object()
    {
        for key in [
            "command",
            "cmd",
            "path",
            "file_path",
            "filePath",
            "target",
            "query",
            "pattern",
            "url",
            "title",
            "task",
            "message",
            "recipient",
        ] {
            if let Some(s) = obj.get(key).and_then(|v| v.as_str())
                && let Some(clean) = truncate_single_line(s, TOOL_SUMMARY_LIMIT)
            {
                return Some(clean);
            }
        }
        for key in ["paths", "files", "queries"] {
            if let Some(arr) = obj.get(key).and_then(|v| v.as_array())
                && let Some(first) = arr.first().and_then(|v| v.as_str())
                && let Some(clean) = truncate_single_line(first, TOOL_SUMMARY_LIMIT)
            {
                return Some(clean);
            }
        }
    }
    None
}

fn status_from_entity_state(state: &HistoryEntityState) -> &'static str {
    match state {
        HistoryEntityState::Unknown | HistoryEntityState::KnownActive { .. } => "running",
        HistoryEntityState::KnownTerminal { outcome } => match outcome {
            ChatTerminalOutcome::Completed => "completed",
            ChatTerminalOutcome::Failed => "failed",
            ChatTerminalOutcome::Cancelled => "cancelled",
            ChatTerminalOutcome::Transferred => "backgrounded",
        },
    }
}

fn extract_live_tool_info(
    record: &HistoryEventRecord,
    tool_name: &str,
) -> (
    String,
    String,
    Option<&'static str>,
    Option<i64>,
    Option<i64>,
) {
    let default_kind = classify_live_tool_kind(tool_name, None).to_owned();
    let Ok(envelope) = decode_event_envelope(record) else {
        return (default_kind, tool_name.to_owned(), None, None, None);
    };
    let kind = classify_live_tool_kind(tool_name, envelope.meta.presentation_contract.as_deref())
        .to_owned();
    let summary = envelope
        .bodies
        .iter()
        .find(|b| b.key == "tool.arguments" || b.role == HistoryBodyRole::ToolArguments.as_str())
        .and_then(|b| b.inline_text.as_deref())
        .and_then(extract_argument_summary)
        .unwrap_or_else(|| tool_name.to_owned());

    let terminal_status = match record.kind {
        HistoryEventKind::ToolCompleted => {
            let state_kind = envelope
                .data
                .get("state")
                .and_then(|s| s.get("kind"))
                .and_then(|v| v.as_str());
            Some(match state_kind {
                Some("failed") => "failed",
                Some("denied") => "denied",
                Some("cancelled") | Some("interrupted") => "cancelled",
                Some("succeeded") => "completed",
                _ => status_from_entity_state(&envelope.meta.state),
            })
        }
        _ => None,
    };

    (
        kind,
        summary,
        terminal_status,
        envelope.meta.started_at,
        envelope.meta.finished_at,
    )
}

fn extract_reasoning_info(
    record: &HistoryEventRecord,
) -> (Option<String>, &'static str, Option<i64>, Option<i64>) {
    let Ok(envelope) = decode_event_envelope(record) else {
        return (None, "completed", None, None);
    };
    let summary = envelope
        .bodies
        .iter()
        .find(|b| {
            b.key == "part.summaryText.0" || b.role == HistoryBodyRole::ReasoningSummary.as_str()
        })
        .and_then(|b| b.inline_text.as_deref())
        .map(str::to_owned);
    let status = status_from_entity_state(&envelope.meta.state);
    (
        summary,
        if status == "running" {
            "completed"
        } else {
            status
        },
        envelope.meta.started_at,
        envelope.meta.finished_at,
    )
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
    /// notified immediately (`None` when a delta was buffered for 16ms coalescing).
    pub fn on_live_event(&self, event: &CoreLiveEvent) -> Option<LiveStatusSnapshot> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let now_ms = now_millis();

        if let CoreLiveEvent::RunActivity { execution } = event {
            return match execution {
                Some(exec) if exec.phase == ExecutionPhase::Stopping => {
                    let already_stopping = state.stopping
                        && matches!(state.phase, Some(LiveStatusPhase::Stopping { .. }));
                    state.turn_active = true;
                    state.enter_stopping(now_ms);
                    if already_stopping {
                        None
                    } else {
                        state.revision += 1;
                        Some(state.snapshot())
                    }
                }
                Some(_) => {
                    if state.stopping {
                        return None;
                    }
                    state.turn_active = true;
                    if matches!(state.current_phase(), LiveStatusPhase::Idle) {
                        state.enter_fresh_working(now_ms);
                        state.revision += 1;
                        return Some(state.snapshot());
                    }
                    None
                }
                None => {
                    if !matches!(state.current_phase(), LiveStatusPhase::Idle)
                        || state.turn_active
                        || state.stopping
                    {
                        state.enter_idle();
                        state.revision += 1;
                        return Some(state.snapshot());
                    }
                    None
                }
            };
        }

        if state.stopping {
            return None;
        }

        match event {
            CoreLiveEvent::TextStreamStarted {
                attempt_id,
                item_id,
                ..
            } => {
                state.clear_working_container();
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
                    state.clear_working_container();
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
                state.clear_stream_buffer();
                if state.turn_active {
                    state.enter_fresh_working(now_ms);
                } else {
                    state.enter_idle();
                }
                state.revision += 1;
                Some(state.snapshot())
            }
            CoreLiveEvent::ReasoningDelta {
                item_id,
                text,
                replace,
                is_summary,
                ..
            } => {
                if *is_summary {
                    if *replace {
                        state.reasoning_summary_text = text.clone();
                    } else {
                        state.reasoning_summary_text.push_str(text);
                    }
                } else if *replace {
                    state.reasoning_body_text = text.clone();
                } else {
                    state.reasoning_body_text.push_str(text);
                }

                let preview = bounded_tail_preview(&state.reasoning_summary_text)
                    .or_else(|| bounded_tail_preview(&state.reasoning_body_text));
                state.reasoning_preview = preview.clone();
                state.turn_active = true;

                state.upsert_work_item(LiveWorkItem {
                    id: format!("reasoning:{item_id}"),
                    call_id: None,
                    kind: "thinking".into(),
                    tool_name: "thinking".into(),
                    status: "running".into(),
                    summary: preview.unwrap_or_default(),
                    started_at_ms: Some(now_ms),
                    finished_at_ms: None,
                });

                if !matches!(state.phase, Some(LiveStatusPhase::Working { .. })) {
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
                let kind = classify_live_tool_kind(tool_id, None).to_owned();
                state.upsert_work_item(LiveWorkItem {
                    id: format!("call:{call_id}"),
                    call_id: Some(call_id.clone()),
                    kind,
                    tool_name: tool_id.clone(),
                    status: "running".into(),
                    summary: preview,
                    started_at_ms: Some(now_ms),
                    finished_at_ms: None,
                });
                if !matches!(
                    state.current_phase(),
                    LiveStatusPhase::StreamingText { .. }
                        | LiveStatusPhase::Compacting { .. }
                        | LiveStatusPhase::Reconnecting { .. }
                ) {
                    state.enter_working(now_ms);
                    state.revision += 1;
                    Some(state.snapshot())
                } else {
                    None
                }
            }
            CoreLiveEvent::CompactionStarted { manual, .. } => {
                state.clear_working_container();
                state.clear_stream_buffer();
                state.phase = Some(LiveStatusPhase::Compacting {
                    manual: *manual,
                    started_at_ms: Some(now_ms),
                });
                state.revision += 1;
                Some(state.snapshot())
            }
            CoreLiveEvent::ModelRecovery { attempt_id, status } => {
                state.clear_stream_buffer();
                match status.phase {
                    ModelRecoveryPhase::Repairing
                    | ModelRecoveryPhase::Waiting
                    | ModelRecoveryPhase::Retrying => {
                        state.clear_working_container();
                        state.phase = Some(LiveStatusPhase::Reconnecting {
                            attempt_id: attempt_id.clone(),
                            message: String::new(),
                            retry_after_ms: None,
                            attempt: status.retry,
                            max_attempts: status.max_retries,
                        });
                    }
                    ModelRecoveryPhase::Recovered
                    | ModelRecoveryPhase::Exhausted
                    | ModelRecoveryPhase::Failed
                    | ModelRecoveryPhase::Cancelled => {
                        if state.turn_active {
                            state.enter_fresh_working(now_ms);
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
                        state.enter_fresh_working(now_ms);
                    } else {
                        state.enter_idle();
                    }
                    state.revision += 1;
                    return Some(state.snapshot());
                }
                None
            }
            CoreLiveEvent::RunActivity { .. } => unreachable!(),
        }
    }

    /// Flushes coalesced `StreamingText` and `ReasoningDelta` updates (called on the 16ms ticker).
    pub fn flush_coalesced(&self) -> Option<LiveStatusSnapshot> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.stopping {
            state.stream_dirty = false;
            state.reasoning_dirty = false;
            return None;
        }
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
        let now_ms = record
            .occurred_at
            .or(Some(record.recorded_at))
            .unwrap_or_else(now_millis);

        // 1. Hidden lifecycle events own turn boundaries.
        match &record.kind {
            HistoryEventKind::TurnStarted => {
                if state.stopping {
                    return None;
                }
                state.turn_active = true;
                state.suppressed_by_interaction = false;
                if matches!(state.current_phase(), LiveStatusPhase::Idle) {
                    state.enter_fresh_working(now_ms);
                    state.revision += 1;
                    return Some(state.snapshot());
                }
                return None;
            }
            HistoryEventKind::TurnEnded | HistoryEventKind::RunEnded => {
                if matches!(state.current_phase(), LiveStatusPhase::Idle)
                    && !state.turn_active
                    && !state.stopping
                    && state.attentions.is_empty()
                {
                    return None;
                }
                state.enter_idle();
                state.revision += 1;
                return Some(state.snapshot());
            }
            _ => {}
        }

        if state.stopping {
            return None;
        }

        // 2. Work vs Boundary directly mirrors persistence `timeline_role`.
        match record.timeline_role {
            HistoryTimelineRole::Hidden => None,
            HistoryTimelineRole::Work => {
                let is_terminal = matches!(
                    record.kind,
                    HistoryEventKind::ToolCompleted
                        | HistoryEventKind::ToolBackgrounded
                        | HistoryEventKind::ReasoningCompleted
                        | HistoryEventKind::AgentCompleted
                );
                if matches!(state.current_phase(), LiveStatusPhase::Idle)
                    && !state.turn_active
                    && is_terminal
                {
                    return None;
                }

                match &record.kind {
                    HistoryEventKind::ReasoningCompleted => {
                        let entity_id = record
                            .entity_id
                            .clone()
                            .unwrap_or_else(|| record.event_id.clone());
                        let (summary, status, started_at, finished_at) =
                            extract_reasoning_info(record);
                        state.turn_active = true;
                        state.upsert_reasoning_completed(
                            &entity_id,
                            summary,
                            status.into(),
                            started_at,
                            finished_at.unwrap_or(now_ms),
                        );
                    }
                    HistoryEventKind::ToolCalled
                    | HistoryEventKind::ToolWaitingApproval
                    | HistoryEventKind::ToolBackgrounded
                    | HistoryEventKind::ToolCancelRequested
                    | HistoryEventKind::ToolCompleted => {
                        let call_id = record
                            .call_id
                            .clone()
                            .or_else(|| record.entity_id.clone())
                            .unwrap_or_else(|| record.event_id.clone());
                        let tool_name = record.tool_name.clone().unwrap_or_else(|| "tool".into());
                        let (kind, summary, terminal_status, started_at, finished_at) =
                            extract_live_tool_info(record, &tool_name);
                        let status = match record.kind {
                            HistoryEventKind::ToolCalled => "running",
                            HistoryEventKind::ToolWaitingApproval => "awaitingApproval",
                            HistoryEventKind::ToolBackgrounded => "backgrounded",
                            HistoryEventKind::ToolCancelRequested => "cancelling",
                            HistoryEventKind::ToolCompleted => {
                                terminal_status.unwrap_or("completed")
                            }
                            _ => "unknown",
                        };
                        state
                            .attentions
                            .retain(|a| a.call_id.as_deref() != Some(call_id.as_str()));
                        let is_done = matches!(
                            status,
                            "completed" | "failed" | "denied" | "cancelled" | "backgrounded"
                        );
                        state.turn_active = true;
                        state.upsert_work_item(LiveWorkItem {
                            id: format!("call:{call_id}"),
                            call_id: Some(call_id),
                            kind,
                            tool_name,
                            status: status.into(),
                            summary,
                            started_at_ms: Some(started_at.unwrap_or(now_ms)),
                            finished_at_ms: is_done.then(|| finished_at.unwrap_or(now_ms)),
                        });
                    }
                    HistoryEventKind::AgentSpawned | HistoryEventKind::AgentCompleted => {
                        let entity_id = record
                            .entity_id
                            .clone()
                            .unwrap_or_else(|| record.event_id.clone());
                        let terminal = record.kind == HistoryEventKind::AgentCompleted;
                        state.turn_active = true;
                        state.upsert_work_item(LiveWorkItem {
                            id: entity_id.clone(),
                            call_id: None,
                            kind: "agent".into(),
                            tool_name: "agent".into(),
                            status: if terminal { "completed" } else { "running" }.into(),
                            summary: record.tool_name.clone().unwrap_or(entity_id),
                            started_at_ms: Some(now_ms),
                            finished_at_ms: terminal.then_some(now_ms),
                        });
                    }
                    _ => return None,
                }

                if !matches!(
                    state.current_phase(),
                    LiveStatusPhase::StreamingText { .. }
                        | LiveStatusPhase::Compacting { .. }
                        | LiveStatusPhase::Reconnecting { .. }
                ) {
                    state.enter_working(now_ms);
                    state.revision += 1;
                    return Some(state.snapshot());
                }
                None
            }
            HistoryTimelineRole::Boundary => {
                // Any Boundary item naturally segments the current work group.
                match &record.kind {
                    HistoryEventKind::InputAccepted | HistoryEventKind::InboxMessageReceived => {
                        state.turn_active = true;
                        state.suppressed_by_interaction = false;
                        state.clear_stream_buffer();
                        let keep_empty_working = matches!(
                            state.phase,
                            Some(LiveStatusPhase::Working { ref items, .. }) if items.is_empty()
                        );
                        if !keep_empty_working {
                            state.enter_fresh_working(now_ms);
                            state.revision += 1;
                            return Some(state.snapshot());
                        }
                        None
                    }
                    HistoryEventKind::TurnReceiptRecorded => {
                        state.enter_idle();
                        state.revision += 1;
                        Some(state.snapshot())
                    }
                    HistoryEventKind::ConnectionDisconnected => {
                        state.clear_working_container();
                        state.clear_stream_buffer();
                        if matches!(state.current_phase(), LiveStatusPhase::Reconnecting { .. })
                            || matches!(state.current_phase(), LiveStatusPhase::Idle)
                        {
                            None
                        } else {
                            state.enter_idle();
                            state.revision += 1;
                            Some(state.snapshot())
                        }
                    }
                    HistoryEventKind::CompactionCompleted => {
                        state.clear_working_container();
                        state.clear_stream_buffer();
                        if state.turn_active {
                            state.enter_fresh_working(now_ms);
                        } else {
                            state.enter_idle();
                        }
                        state.revision += 1;
                        Some(state.snapshot())
                    }
                    _ => {
                        let had_work_items = !state.working_items.is_empty();
                        let was_streaming =
                            matches!(state.current_phase(), LiveStatusPhase::StreamingText { .. });
                        state.clear_working_container();
                        state.clear_stream_buffer();
                        if matches!(state.current_phase(), LiveStatusPhase::Reconnecting { .. }) {
                            return None;
                        }
                        if state.turn_active {
                            if had_work_items || was_streaming {
                                state.enter_fresh_working(now_ms);
                                state.revision += 1;
                                return Some(state.snapshot());
                            }
                            None
                        } else {
                            if !matches!(state.current_phase(), LiveStatusPhase::Idle) {
                                state.enter_idle();
                                state.revision += 1;
                                return Some(state.snapshot());
                            }
                            None
                        }
                    }
                }
            }
        }
    }
}
