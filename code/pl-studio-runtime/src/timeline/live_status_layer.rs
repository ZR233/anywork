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

use pl_core::model::{ModelRecoveryPhase, ToolProgress};
use pl_core::thread::{CoreLiveEvent, ExecutionPhase};

use crate::history::{HistoryEventKind, HistoryEventRecord, HistoryTimelineRole};

use super::member_decoder::{decode_work_group_member, merge_work_group_member};
use super::models::{LiveAttention, LiveStatusPhase, LiveStatusSnapshot, WorkGroupMember};

pub const STREAMING_TEXT_COALESCE_INTERVAL: Duration = Duration::from_millis(16);
const REASONING_PREVIEW_LIMIT: usize = 240;
const TOOL_PROGRESS_TAIL_BYTES: usize = 2048;

#[derive(Debug, Clone)]
struct LiveReasoningBuffer {
    attempt_id: String,
    item_id: String,
    work_item_id: String,
    summary_text: String,
    body_text: String,
    started_at_ms: i64,
    settled: bool,
}

impl LiveReasoningBuffer {
    fn preview(&self) -> Option<String> {
        latest_reasoning_summary_preview(&self.summary_text)
            .or_else(|| latest_reasoning_summary_preview(&self.body_text))
    }
}

#[derive(Debug, Default)]
struct State {
    revision: u64,
    phase: Option<LiveStatusPhase>,
    working_items: Vec<WorkGroupMember>,
    reasoning_preview: Option<String>,
    reasoning_buffers: Vec<LiveReasoningBuffer>,
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
        self.reasoning_buffers.clear();
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

    fn upsert_work_member(&mut self, member: WorkGroupMember) {
        if let Some(existing) = self
            .working_items
            .iter_mut()
            .find(|existing| existing.id() == member.id())
        {
            merge_work_group_member(existing, member);
        } else {
            self.working_items.push(member);
        }
    }

    fn latest_active_reasoning_preview(&self) -> Option<String> {
        self.reasoning_buffers
            .iter()
            .rev()
            .filter(|buf| !buf.settled)
            .find_map(LiveReasoningBuffer::preview)
    }

    fn upsert_reasoning_completed(&mut self, mut decoded: WorkGroupMember, now_ms: i64) {
        let entity_id = decoded.id().to_owned();
        let prefixed_id = format!("reasoning:{entity_id}");
        let idx = self
            .working_items
            .iter()
            .position(|item| {
                matches!(
                    item,
                    WorkGroupMember::Reasoning { id, .. }
                        if id == &entity_id || id == &prefixed_id
                )
            })
            .or_else(|| {
                self.working_items.iter().position(|item| {
                    matches!(
                        item,
                        WorkGroupMember::Reasoning {
                            outcome,
                            finished_at_ms,
                            ..
                        } if outcome == "running" && finished_at_ms.is_none()
                    )
                })
            });

        if let Some(idx) = idx {
            let (old_id, old_started) = match &self.working_items[idx] {
                WorkGroupMember::Reasoning {
                    id, started_at_ms, ..
                } => (id.clone(), *started_at_ms),
                _ => unreachable!(),
            };
            if let WorkGroupMember::Reasoning {
                started_at_ms,
                finished_at_ms,
                ..
            } = &mut decoded
            {
                if started_at_ms.is_none() {
                    *started_at_ms = old_started.or(Some(now_ms));
                }
                if finished_at_ms.is_none() {
                    *finished_at_ms = Some(now_ms);
                }
            }
            self.reasoning_buffers
                .retain(|buf| buf.work_item_id != old_id);
            self.working_items[idx] = decoded.clone();
        } else {
            if let WorkGroupMember::Reasoning {
                started_at_ms,
                finished_at_ms,
                ..
            } = &mut decoded
            {
                if started_at_ms.is_none() {
                    *started_at_ms = Some(now_ms);
                }
                if finished_at_ms.is_none() {
                    *finished_at_ms = Some(now_ms);
                }
            }
            self.working_items.push(decoded.clone());
        }

        let completed_preview = match &decoded {
            WorkGroupMember::Reasoning { summary, text, .. } => {
                latest_reasoning_summary_preview(summary)
                    .or_else(|| latest_reasoning_summary_preview(text))
            }
            _ => None,
        };
        self.reasoning_preview = self.latest_active_reasoning_preview().or(completed_preview);
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

/// Extracts the latest single-line reasoning summary preview without concatenating older
/// `**Heading**` sections or truncating from the left into broken Markdown markers.
#[must_use]
pub fn latest_reasoning_summary_preview(text: &str) -> Option<String> {
    let line = text
        .rsplit(['\n', '\r'])
        .map(str::trim)
        .find(|line| !line.is_empty())?;
    let segment = extract_latest_bold_segment(line).trim();
    if segment.is_empty() {
        return None;
    }
    if segment.chars().count() <= REASONING_PREVIEW_LIMIT {
        return Some(segment.to_owned());
    }

    let head_limit = REASONING_PREVIEW_LIMIT.saturating_sub(1);
    let head_with_ellipsis: String = segment.chars().take(head_limit).collect();
    let needs_closing_bold =
        segment.starts_with("**") && head_with_ellipsis.matches("**").count() % 2 == 1;
    if needs_closing_bold {
        let mut head: String = segment
            .chars()
            .take(REASONING_PREVIEW_LIMIT.saturating_sub(3))
            .collect();
        if head.ends_with('*') && !head.ends_with("**") {
            head.pop();
        }
        Some(format!("{head}…**"))
    } else {
        let mut head = head_with_ellipsis;
        if segment.starts_with("**") && head.ends_with('*') && !head.ends_with("**") {
            head.pop();
        }
        Some(format!("{head}…"))
    }
}

fn has_meaningful_content(slice: &str) -> bool {
    slice.chars().any(|ch| ch != '*' && !ch.is_whitespace())
}

fn extract_latest_bold_segment(line: &str) -> &str {
    let bytes = line.as_bytes();
    let mut i = 0;
    let mut in_bold = false;
    let mut saw_quad_boundary = false;
    let mut last_quad_start: Option<usize> = None;
    let mut open_positions: Vec<usize> = Vec::new();

    while i < bytes.len() {
        if bytes[i..].starts_with(b"****") {
            let candidate = i + 2;
            if has_meaningful_content(&line[candidate..]) {
                saw_quad_boundary = true;
                last_quad_start = Some(candidate);
                open_positions.push(candidate);
            }
            in_bold = true;
            i += 4;
            continue;
        }
        if bytes[i..].starts_with(b"**") {
            if !in_bold {
                in_bold = true;
                if has_meaningful_content(&line[i..]) {
                    open_positions.push(i);
                }
            } else {
                in_bold = false;
            }
            i += 2;
            continue;
        }
        let ch_len = line[i..].chars().next().map_or(1, char::len_utf8);
        i += ch_len;
    }

    if saw_quad_boundary || open_positions.len() >= 2 {
        let start = last_quad_start
            .into_iter()
            .chain(open_positions.last().copied())
            .max()
            .unwrap_or(0);
        return &line[start..];
    }

    if let Some(&open_pos) = open_positions.last()
        && open_pos > 0
        && !line[..open_pos].ends_with(char::is_whitespace)
    {
        return &line[open_pos..];
    }

    line
}

fn tool_progress_tail(progress: &ToolProgress) -> Option<String> {
    let part = progress.parts().iter().rev().find(|p| !p.is_empty())?;
    let block = part.content();
    let len = block.len();
    if len == 0 {
        return None;
    }
    let start = len.saturating_sub(TOOL_PROGRESS_TAIL_BYTES);
    for offset in 0..4 {
        let candidate = start.saturating_add(offset);
        if candidate > len {
            break;
        }
        if let Some(text) = block.suffix_since(candidate) {
            let trimmed = text.trim();
            return (!trimmed.is_empty()).then(|| trimmed.to_owned());
        }
    }
    None
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
                attempt_id,
                item_id,
                text,
                replace,
                is_summary,
                ..
            } => {
                let idx = if let Some(existing_idx) = state.reasoning_buffers.iter().position(|b| {
                    b.attempt_id == *attempt_id && b.item_id == *item_id && !b.settled
                }) {
                    existing_idx
                } else {
                    let work_item_id = format!("reasoning:{attempt_id}:{item_id}");
                    state.reasoning_buffers.push(LiveReasoningBuffer {
                        attempt_id: attempt_id.clone(),
                        item_id: item_id.clone(),
                        work_item_id,
                        summary_text: String::new(),
                        body_text: String::new(),
                        started_at_ms: now_ms,
                        settled: false,
                    });
                    state.reasoning_buffers.len() - 1
                };

                let (work_item_id, started_at_ms, body_text, summary_preview) = {
                    let buf = &mut state.reasoning_buffers[idx];
                    let target = if *is_summary {
                        &mut buf.summary_text
                    } else {
                        &mut buf.body_text
                    };
                    if *replace {
                        *target = text.clone();
                    } else {
                        target.push_str(text);
                    }
                    (
                        buf.work_item_id.clone(),
                        buf.started_at_ms,
                        buf.body_text.clone(),
                        buf.preview(),
                    )
                };

                if let Some(active_preview) = state.latest_active_reasoning_preview() {
                    state.reasoning_preview = Some(active_preview);
                }
                state.turn_active = true;

                state.upsert_work_member(WorkGroupMember::Reasoning {
                    id: work_item_id,
                    seq: 0,
                    text: body_text,
                    summary: summary_preview.unwrap_or_default(),
                    body_ref: None,
                    outcome: "running".into(),
                    started_at_ms: Some(started_at_ms),
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
                let tail = tool_progress_tail(progress);
                if let Some(WorkGroupMember::ToolCall { result_preview, .. }) =
                    state.working_items.iter_mut().find(|member| {
                        matches!(
                            member,
                            WorkGroupMember::ToolCall {
                                call_id: existing_call_id,
                                ..
                            } if existing_call_id == call_id
                        )
                    })
                {
                    if let Some(tail) = tail {
                        *result_preview = Some(tail);
                    }
                } else {
                    state.working_items.push(WorkGroupMember::ToolCall {
                        id: format!("call:{call_id}"),
                        seq: 0,
                        call_id: call_id.clone(),
                        turn_id: None,
                        tool_name: tool_id.clone(),
                        presentation_contract: None,
                        status: "running".into(),
                        summary: tool_id.clone(),
                        arguments: None,
                        result_preview: tail,
                        payload_json: String::new(),
                        bodies: Vec::new(),
                        wait_json: None,
                        started_at_ms: Some(now_ms),
                        finished_at_ms: None,
                    });
                }

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
            HistoryEventKind::StepPreempted => {
                if state.stopping {
                    return None;
                }
                let needs_reset = !state.working_items.is_empty()
                    || state.reasoning_preview.is_some()
                    || !state.reasoning_buffers.is_empty()
                    || !state.stream_text.is_empty()
                    || state.stream_attempt_id.is_some()
                    || state.stream_dirty
                    || state.reasoning_dirty
                    || !matches!(state.current_phase(), LiveStatusPhase::Working { .. });
                state.clear_stream_buffer();
                if state.turn_active {
                    if needs_reset {
                        state.enter_fresh_working(now_ms);
                        state.revision += 1;
                        return Some(state.snapshot());
                    }
                    return None;
                }
                if !matches!(state.current_phase(), LiveStatusPhase::Idle) {
                    state.enter_idle();
                    state.revision += 1;
                    return Some(state.snapshot());
                }
                return None;
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
                        | HistoryEventKind::ItemRecorded
                );
                if matches!(state.current_phase(), LiveStatusPhase::Idle)
                    && !state.turn_active
                    && is_terminal
                {
                    return None;
                }

                match &record.kind {
                    HistoryEventKind::ReasoningCompleted => {
                        let member = decode_work_group_member(record)?;
                        if !matches!(member, WorkGroupMember::Reasoning { .. }) {
                            return None;
                        }
                        state.turn_active = true;
                        state.upsert_reasoning_completed(member, now_ms);
                    }
                    HistoryEventKind::ToolCalled
                    | HistoryEventKind::ToolWaitingApproval
                    | HistoryEventKind::ToolBackgrounded
                    | HistoryEventKind::ToolCancelRequested
                    | HistoryEventKind::ToolCompleted => {
                        let mut member = decode_work_group_member(record)?;
                        if let WorkGroupMember::ToolCall {
                            call_id,
                            status,
                            started_at_ms,
                            finished_at_ms,
                            ..
                        } = &mut member
                        {
                            state
                                .attentions
                                .retain(|a| a.call_id.as_deref() != Some(call_id.as_str()));
                            if started_at_ms.is_none() {
                                *started_at_ms = Some(now_ms);
                            }
                            let is_done = matches!(
                                status.as_str(),
                                "completed"
                                    | "succeeded"
                                    | "failed"
                                    | "denied"
                                    | "cancelled"
                                    | "interrupted"
                                    | "backgrounded"
                            );
                            if is_done && finished_at_ms.is_none() {
                                *finished_at_ms = Some(now_ms);
                            }
                        }
                        state.turn_active = true;
                        state.upsert_work_member(member);
                    }
                    HistoryEventKind::AgentSpawned
                    | HistoryEventKind::AgentCompleted
                    | HistoryEventKind::ItemRecorded => {
                        let mut member = decode_work_group_member(record)?;
                        if let WorkGroupMember::Agent {
                            status,
                            started_at_ms,
                            finished_at_ms,
                            ..
                        } = &mut member
                        {
                            if started_at_ms.is_none() {
                                *started_at_ms = Some(now_ms);
                            }
                            let is_done = record.kind == HistoryEventKind::AgentCompleted
                                || matches!(status.as_str(), "completed" | "failed" | "cancelled");
                            if is_done && finished_at_ms.is_none() {
                                *finished_at_ms = Some(now_ms);
                            }
                        }
                        state.turn_active = true;
                        state.upsert_work_member(member);
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
