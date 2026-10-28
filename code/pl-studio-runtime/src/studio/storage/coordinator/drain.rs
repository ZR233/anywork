//! Drain failures come from every original incarnation, never the public latest-row projection.

use std::sync::Arc;

use super::{
    ThreadPersistenceCoordinator, ThreadPersistenceMetrics, WriterState, WriterTaskFailure,
};
use crate::studio::storage::thread_writer::HistoryChannel;

/// Every writer task that ended abnormally, as this layer's own typed reason.
///
/// `wait_for_writers_end` returns it instead of reporting success: a drained queue followed by a
/// panicking worker or helper is a failure of the close, not a clean end. All of them are kept —
/// reporting only the first would hide another incarnation's real failure.
#[derive(Debug)]
pub(crate) struct WriterTasksEndFailure(Vec<Arc<WriterTaskFailure>>);

impl std::fmt::Display for WriterTasksEndFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "{} writer task(s) did not end normally: {}",
            self.0.len(),
            self.0
                .first()
                .map_or_else(String::new, |failure| failure.to_string())
        )
    }
}

impl std::error::Error for WriterTasksEndFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.0
            .first()
            .map(|failure| failure.as_ref() as &(dyn std::error::Error + 'static))
    }
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum ThreadPersistenceDrainFailure {
    #[error("Thread persistence retained failed writer incarnations")]
    Incarnations(Vec<ThreadPersistenceDrainIssue>),
    #[error("Thread persistence progress channel closed")]
    ProgressClosed(#[source] tokio::sync::watch::error::RecvError),
}

impl ThreadPersistenceDrainFailure {
    /// Permission to re-observe after original explicit recovery, not a request to run recovery.
    #[allow(dead_code)] // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
    pub(crate) fn can_retry(&self) -> bool {
        match self {
            Self::Incarnations(issues) => {
                !issues.is_empty()
                    && issues.iter().all(|issue| {
                        issue.writer == WriterState::Running
                            && issue.released_dirty.is_none()
                            && issue.error.is_some()
                            && issue.metrics.fault.is_some()
                    })
            }
            Self::ProgressClosed(_) => false,
        }
    }
}

/// A bounded capture of one original failure. Existing string diagnostics are retained as-is;
/// neither their text nor a newer writer's public metrics determine recovery permission.
#[derive(Debug, Clone, thiserror::Error)]
#[error(
    "Thread {thread_id} writer {incarnation} retained {pending_commits} pending commit(s): {error:?}; released: {released_dirty:?}"
)]
pub(crate) struct ThreadPersistenceDrainIssue {
    thread_id: String,
    incarnation: usize,
    pending_commits: u64,
    metrics: ThreadPersistenceMetrics,
    error: Option<String>,
    released_dirty: Option<String>,
    writer: WriterState,
}

impl ThreadPersistenceCoordinator {
    /// Waits until the writer tasks of `thread_id` — or of every Thread — really ended.
    ///
    /// This is deliberately *not* part of [`Self::wait_for_drain`]. A drained queue only means the
    /// admitted facts are durable; it says nothing about the writer task, its helpers, or the
    /// history connections they hold. Keeping the two apart is what lets a running process flush
    /// without waiting for writers that are still legitimately alive.
    ///
    /// The registered task completions are awaited here instead of trusting the incarnation row: if
    /// the task that would have observed them died, this waiter still drives their real end and
    /// finishes the incarnation itself, so "stopped" can never be reported for tasks that are still
    /// running.
    pub(crate) async fn wait_for_writers_end(&self, thread_id: Option<&str>) -> anyhow::Result<()> {
        let mut progress = self.subscribe();
        loop {
            // Mark the snapshot seen before reading canonical state, exactly like `wait_for_drain`:
            // an end published after this read always leaves a wake behind.
            let _ = progress.borrow_and_update().clone();
            let (live, running) = {
                let threads = self
                    .0
                    .threads
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                let selected = threads.iter().filter(|(id, _)| match thread_id {
                    Some(thread_id) => id.as_str() == thread_id,
                    None => true,
                });
                let mut live = 0_usize;
                let mut running = Vec::new();
                for (id, status) in selected {
                    for (owner, incarnation) in &status.incarnations {
                        if !incarnation.is_live() {
                            continue;
                        }
                        live += 1;
                        if let Some(tasks) = &incarnation.tasks {
                            running.push((id.clone(), *owner, tasks.clone()));
                        }
                    }
                }
                (live, running)
            };
            if live == 0 {
                // The tasks really ended — but a queue that drained and a task that ended are two
                // different facts. The canonical rows are read here (not a value this wait happened
                // to observe), so an incarnation that stopped before this wait started still fails
                // the close, every time it is asked.
                let failures = self.task_end_failures(thread_id);
                return match failures.is_empty() {
                    true => Ok(()),
                    false => Err(anyhow::Error::new(WriterTasksEndFailure(failures))),
                };
            }
            if !running.is_empty() {
                for (id, owner, tasks) in running {
                    let outcome = tasks.join().await;
                    self.finish_incarnation(&id, owner, outcome);
                }
                continue;
            }
            progress
                .changed()
                .await
                .map_err(ThreadPersistenceDrainFailure::ProgressClosed)?;
        }
    }

    pub(crate) async fn wait_for_drain(&self) -> anyhow::Result<()> {
        let mut progress = self.subscribe();
        loop {
            // Subscribe/mark seen before reading canonical state. Updates made after that read
            // publish a wake, including updates whose aggregate happens to look unchanged.
            let snapshot = progress.borrow_and_update().clone();
            let (preparing, pending, issues) = {
                let threads = self
                    .0
                    .threads
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                let mut preparing = false;
                let mut pending = 0_u64;
                let mut issues = Vec::new();
                for (thread_id, status) in threads.iter() {
                    for (incarnation, row) in &status.incarnations {
                        preparing |= row.writer == WriterState::Preparing;
                        pending = pending.saturating_add(row.owed());
                        if let Some(error) = row.failure() {
                            issues.push(ThreadPersistenceDrainIssue {
                                thread_id: thread_id.clone(),
                                incarnation: *incarnation,
                                pending_commits: row.owed(),
                                metrics: row.metrics.clone(),
                                error: Some(error),
                                released_dirty: row.released_dirty.clone(),
                                writer: row.writer,
                            });
                        }
                    }
                }
                (preparing, pending, issues)
            };
            // Claim may retire a stopped predecessor before the replacement's first queue report.
            // Preparing remains an in-flight obligation even in that zero-counter interval.
            // Do not cache a failure classification before that handoff has settled either.
            if !preparing {
                if !issues.is_empty() {
                    return Err(ThreadPersistenceDrainFailure::Incarnations(issues).into());
                }
                if pending == 0 {
                    return Ok(());
                }
            }
            let queue = self.queue_snapshot();
            tracing::debug!(
                calls_admitted = snapshot.calls_admitted_sequence,
                calls_durable = snapshot.calls_durable_sequence,
                calls_oldest_pending_age_millis = ?snapshot.calls_oldest_pending_age_millis,
                pending_operations = queue.pending_operations,
                pending_bytes = queue.pending_bytes,
                in_flight_bytes = queue.in_flight_bytes,
                oldest_pending_age_millis = ?queue.oldest_pending_age_millis,
                pressure_paused = queue.pressure_paused,
                threads = queue.threads.len(),
                "waiting for Thread persistence to drain"
            );
            progress
                .changed()
                .await
                .map_err(ThreadPersistenceDrainFailure::ProgressClosed)?;
        }
    }

    /// Checks only the captured channel's original executor capability. It neither creates a
    /// channel nor requests a retry, and cannot authorize replacing a barrier's fixed ticket.
    pub(crate) fn can_retry_history_channel(
        &self,
        thread_id: &str,
        channel: &Arc<HistoryChannel>,
    ) -> bool {
        // Existing retirement takes channels -> channel progress after releasing threads;
        // writer reports take channel progress -> threads. This read takes channels -> threads
        // only, never channel progress, and performs no notifications or IO under either guard.
        let channels = self
            .0
            .channels
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !channels
            .get(thread_id)
            .is_some_and(|current| Arc::ptr_eq(current, channel))
        {
            return false;
        }
        let threads = self
            .0
            .threads
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        threads.get(thread_id).is_some_and(|status| {
            status
                .incarnations
                .values()
                .any(|row| row.writer == WriterState::Running)
        })
    }
}
