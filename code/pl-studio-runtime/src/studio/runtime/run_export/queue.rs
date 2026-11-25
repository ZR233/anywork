//! Bounded admission, backpressure and producer cancellation for one run.
use super::types::{
    BuildInfoV3, ExecutionErrorV3, ExecutionLifecycleExportV3, MAX_QUEUED_BATCHES,
    MAX_QUEUED_METADATA_BYTES, TraceSummaryV3,
};
use crate::history::{HistoryCut, HistoryReader};
use crate::studio::thread_projection::PreparedAccounting;
use anyhow::Result;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

/// Commands queued onto the single background writer task.
pub enum ExportCommand {
    RunStarted {
        build: BuildInfoV3,
        manifest_sha256: String,
    },
    AgentRegistered {
        agent_id: String,
        thread_id: String,
        parent_agent_id: Option<String>,
        parent_thread_id: Option<String>,
        role: Option<String>,
        workspace_id: String,
        spawn_tool_call_id: Option<String>,
        initial_effect_seq: u64,
        initial_history_cut: HistoryCut,
        initial_history_seq: u64,
        history: HistoryReader,
    },
    SkillsDiscovered {
        thread_id: String,
        report: pl_tool::skill::SkillDiscoveryReport,
    },
    LiveHandoff(Box<LiveHandoff>),
    Finalize {
        agent_ok: bool,
        flush_ok: bool,
        pending_after: Option<usize>,
        reply: tokio::sync::oneshot::Sender<FinalizeWriterOutcome>,
    },
}

pub(in crate::studio) struct LiveHandoff {
    pub(super) thread_id: String,
    pub(super) effect_seq: u64,
    pub(super) accounting: PreparedAccounting,
    pub(super) lifecycle: Arc<[ExecutionLifecycleExportV3]>,
    pub(super) history: HistoryReader,
    pub(super) history_cut: HistoryCut,
    pub(super) history_seq: u64,
    pub(super) current_owner_id: String,
    pub(super) current_revision: u64,
}

pub struct FinalizeWriterOutcome {
    pub trace_complete: bool,
    pub usage_complete: bool,
    pub cost_complete: bool,
    pub trace: TraceSummaryV3,
    pub usage: Option<super::types::UsageExportV3>,
    pub failure: Option<ExecutionErrorV3>,
}

pub(super) const EVENTS_REL_PATH: &str = "events.jsonl";

impl FinalizeWriterOutcome {
    pub(super) fn failed(error: ExecutionErrorV3) -> Self {
        Self {
            trace_complete: false,
            usage_complete: false,
            cost_complete: false,
            trace: TraceSummaryV3 {
                events_path: EVENTS_REL_PATH.to_owned(),
                events_sha256: None,
                event_count: 0,
                last_event_seq: None,
                sealed: false,
                reason: Some(error.message.clone()),
            },
            usage: None,
            failure: Some(error),
        }
    }
}

struct QueuedItem {
    cmd: ExportCommand,
    metadata_bytes: usize,
}

#[derive(Default)]
struct QueueState {
    queue: VecDeque<QueuedItem>,
    queued_batches: usize,
    queued_bytes: usize,
    admission_closed: bool,
    fatal_error: Option<ExecutionErrorV3>,
    writer_exited: bool,
}

pub struct BoundedExportQueue {
    state: Mutex<QueueState>,
    slot_notify: Notify,
    work_notify: Notify,
    run_cancel: CancellationToken,
}

impl BoundedExportQueue {
    pub fn new(run_cancel: CancellationToken) -> Arc<Self> {
        Arc::new(Self {
            state: Mutex::new(QueueState::default()),
            slot_notify: Notify::new(),
            work_notify: Notify::new(),
            run_cancel,
        })
    }

    pub async fn admit(
        &self,
        cmd: ExportCommand,
        metadata_bytes: usize,
    ) -> Result<(), Box<ExecutionErrorV3>> {
        if metadata_bytes > MAX_QUEUED_METADATA_BYTES {
            let err = ExecutionErrorV3::export(
                "exportBatchTooLarge",
                format!(
                    "export metadata batch ({metadata_bytes} bytes) exceeds 16 MiB admission bound"
                ),
            );
            self.fail_permanently(err.clone());
            return Err(Box::new(err));
        }

        loop {
            let notified = {
                let mut guard = self
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if let Some(fatal) = &guard.fatal_error {
                    return Err(Box::new(fatal.clone()));
                }
                if guard.admission_closed || guard.writer_exited {
                    return Err(Box::new(ExecutionErrorV3::export(
                        "exportAdmissionClosed",
                        "run exporter admission gate is closed",
                    )));
                }
                if guard.queued_batches < MAX_QUEUED_BATCHES
                    && guard.queued_bytes.saturating_add(metadata_bytes)
                        <= MAX_QUEUED_METADATA_BYTES
                {
                    guard.queued_batches += 1;
                    guard.queued_bytes += metadata_bytes;
                    guard.queue.push_back(QueuedItem {
                        cmd,
                        metadata_bytes,
                    });
                    drop(guard);
                    self.work_notify.notify_one();
                    return Ok(());
                }
                self.slot_notify.notified()
            };
            notified.await;
        }
    }

    /// Enqueues Finalize even when `admission_closed` was armed on deadline, provided writer task
    /// has not exited, so finalize can still flush/report partial state.
    pub async fn enqueue_finalize(
        &self,
        agent_ok: bool,
        flush_ok: bool,
        pending_after: Option<usize>,
    ) -> Result<tokio::sync::oneshot::Receiver<FinalizeWriterOutcome>, Box<ExecutionErrorV3>> {
        let (tx, rx) = tokio::sync::oneshot::channel();
        {
            let mut guard = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if guard.writer_exited {
                return Err(Box::new(guard.fatal_error.clone().unwrap_or(
                    ExecutionErrorV3::export(
                        "exportWriterStopped",
                        "exporter writer task exited before finalization",
                    ),
                )));
            }
            guard.queue.push_back(QueuedItem {
                cmd: ExportCommand::Finalize {
                    agent_ok,
                    flush_ok,
                    pending_after,
                    reply: tx,
                },
                metadata_bytes: 0,
            });
            guard.queued_batches += 1;
        }
        self.work_notify.notify_one();
        Ok(rx)
    }

    pub fn close_admission(&self, reason: ExecutionErrorV3) {
        self.fail_permanently(reason);
    }

    pub fn fail_permanently(&self, err: ExecutionErrorV3) {
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.admission_closed = true;
        if guard.fatal_error.is_none() {
            guard.fatal_error = Some(err);
        }
        drop(guard);
        self.slot_notify.notify_waiters();
        self.work_notify.notify_waiters();
        self.run_cancel.cancel();
    }

    pub fn fatal_error(&self) -> Option<ExecutionErrorV3> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .fatal_error
            .clone()
    }

    pub(super) async fn pop(&self) -> Option<ExportCommand> {
        loop {
            let notified = {
                let mut guard = self
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if let Some(item) = guard.queue.pop_front() {
                    guard.queued_batches = guard.queued_batches.saturating_sub(1);
                    guard.queued_bytes = guard.queued_bytes.saturating_sub(item.metadata_bytes);
                    drop(guard);
                    self.slot_notify.notify_waiters();
                    return Some(item.cmd);
                }
                if guard.writer_exited {
                    return None;
                }
                self.work_notify.notified()
            };
            notified.await;
        }
    }

    pub(super) fn mark_writer_exited(&self) {
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.writer_exited = true;
        guard.admission_closed = true;
        guard.queue.clear();
        guard.queued_batches = 0;
        guard.queued_bytes = 0;
        drop(guard);
        self.slot_notify.notify_waiters();
    }
}

/// Estimates serialized metadata byte size charged against the 16 MiB queue bound without copying
/// body content into the queue.
pub fn estimate_handoff_metadata_bytes(accounting: &PreparedAccounting) -> usize {
    usize::try_from(accounting.retained_bytes())
        .unwrap_or(usize::MAX)
        .saturating_add(std::mem::size_of::<ExportCommand>())
        .saturating_add(accounting.thread_id.len())
}
