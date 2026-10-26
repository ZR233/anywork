//! PersistenceState 的计算与发布。

use std::sync::Arc;

use pl_protocol::StateError;

use crate::PureError;
use crate::studio::{
    BlockedPersistence, DegradedPersistence, FlushingPersistence, PersistenceState,
    PersistenceStateSnapshot, ReadyPersistence, RecoveringPersistence, unix_seconds,
};

use super::failure::WriteBehindCause;
use super::handle::WriterShared;

/// One canonical watch capture: private cause and public health can never be from different passes.
#[derive(Debug, Clone, Default)]
pub(in crate::studio) struct WriterHealth {
    pub(in crate::studio) snapshot: PersistenceStateSnapshot,
    pub(in crate::studio) cause: Option<Arc<WriteBehindCause>>,
    pub(super) task: Option<Arc<()>>,
}

impl WriterHealth {
    pub(super) fn blocked_cause(&self) -> Option<Arc<WriteBehindCause>> {
        match &self.snapshot.state {
            PersistenceState::Blocked(blocked) => Some(self.cause.clone().unwrap_or_else(|| {
                Arc::new(WriteBehindCause::LegacyDiagnostic(
                    blocked.error.message.clone(),
                ))
            })),
            _ => None,
        }
    }
}

pub(super) fn update_healthy_state(shared: &WriterShared, pending: usize) {
    publish_state(shared, |current| {
        if matches!(
            &current.snapshot.state,
            PersistenceState::Degraded(_)
                | PersistenceState::Recovering(_)
                | PersistenceState::Blocked(_)
        ) {
            return false;
        }
        let state = if pending == 0 {
            PersistenceState::Ready(ReadyPersistence { pending_commits: 0 })
        } else {
            PersistenceState::Flushing(FlushingPersistence {
                pending_commits: pending as u64,
                oldest_pending_revision: oldest_pending_revision(shared),
            })
        };
        let task = current.task.clone();
        set_health(current, state, None, task)
    });
}

pub(super) fn update_after_success(
    shared: &WriterShared,
    pending: usize,
    was_unhealthy: bool,
    task: &Arc<()>,
) {
    publish_state(shared, |current| {
        let state = if pending == 0 {
            PersistenceState::Ready(ReadyPersistence { pending_commits: 0 })
        } else if was_unhealthy {
            PersistenceState::Recovering(RecoveringPersistence {
                pending_commits: pending as u64,
                oldest_pending_revision: oldest_pending_revision(shared),
                first_failed_at: first_failed_at(&current.snapshot.state)
                    .unwrap_or_else(unix_seconds),
            })
        } else {
            PersistenceState::Flushing(FlushingPersistence {
                pending_commits: pending as u64,
                oldest_pending_revision: oldest_pending_revision(shared),
            })
        };
        set_health(current, state, None, Some(task.clone()))
    });
}

pub(super) fn publish_degraded(shared: &WriterShared, error: Arc<PureError>, task: &Arc<()>) {
    let cause = Arc::new(WriteBehindCause::Store(error));
    let message = diagnostic(&cause);
    let pending = pending_from_queue(shared);
    publish_state(shared, |current| {
        let state = PersistenceState::Degraded(DegradedPersistence {
            pending_commits: pending as u64,
            oldest_pending_revision: oldest_pending_revision(shared),
            first_failed_at: first_failed_at(&current.snapshot.state).unwrap_or_else(unix_seconds),
            error: persistence_error("persistenceUnavailable", message, true),
        });
        set_health(current, state, Some(cause), Some(task.clone()))
    });
}

pub(super) fn publish_blocked(shared: &WriterShared, cause: Arc<WriteBehindCause>, task: &Arc<()>) {
    let reason = diagnostic(&cause);
    let log_reason = reason.clone();
    let pending = pending_from_queue(shared);
    publish_state(shared, |current| {
        let state = PersistenceState::Blocked(BlockedPersistence {
            pending_commits: pending as u64,
            oldest_pending_revision: oldest_pending_revision(shared),
            first_failed_at: first_failed_at(&current.snapshot.state).unwrap_or_else(unix_seconds),
            error: persistence_error("persistenceBlocked", reason, false),
        });
        set_health(current, state, Some(cause), Some(task.clone()))
    });
    // Subscriber callbacks are outside the canonical capture: even a logging panic cannot erase
    // the actual inner failure when the supervisor subsequently reports its own failed join.
    tracing::error!(reason = log_reason, "write-behind writer is blocked");
}

fn diagnostic(cause: &WriteBehindCause) -> String {
    match cause {
        WriteBehindCause::Store(error) => error.to_string(),
        WriteBehindCause::WorkerJoin(error) => {
            format!("write-behind worker terminated unexpectedly: {error}")
        }
        WriteBehindCause::SupervisorJoin(error) => {
            format!("write-behind supervisor failed: {error}")
        }
        WriteBehindCause::AdmissionClosed(error) => {
            format!("write-behind admission closed: {error}")
        }
        WriteBehindCause::ProgressClosed(error) => format!("write-behind progress closed: {error}"),
        WriteBehindCause::LegacyDiagnostic(message) => message.clone(),
    }
}

fn set_health(
    current: &mut WriterHealth,
    state: PersistenceState,
    cause: Option<Arc<WriteBehindCause>>,
    task: Option<Arc<()>>,
) -> bool {
    let changed = current.snapshot.state != state;
    let same_cause = match (&current.cause, &cause) {
        (Some(left), Some(right)) => Arc::ptr_eq(left, right),
        (None, None) => true,
        _ => false,
    };
    let same_task = match (&current.task, &task) {
        (Some(left), Some(right)) => Arc::ptr_eq(left, right),
        (None, None) => true,
        _ => false,
    };
    if changed {
        current.snapshot = PersistenceStateSnapshot {
            revision: current.snapshot.revision.saturating_add(1),
            state,
        };
    }
    current.cause = cause;
    current.task = task;
    changed || !same_cause || !same_task
}

fn publish_state(shared: &WriterShared, update: impl FnOnce(&mut WriterHealth) -> bool) {
    // Tokio publishes the whole capture together. No queue/lifecycle guard survives here.
    if shared.state.send_if_modified(update) {
        shared
            .durable_progress
            .send_modify(|next| *next = next.wrapping_add(1));
    }
}

fn persistence_error(code: &str, message: String, retryable: bool) -> StateError {
    StateError {
        code: code.to_string(),
        message,
        retryable,
    }
}

fn first_failed_at(state: &PersistenceState) -> Option<i64> {
    match state {
        PersistenceState::Degraded(state) => Some(state.first_failed_at),
        PersistenceState::Recovering(state) => Some(state.first_failed_at),
        PersistenceState::Blocked(state) => Some(state.first_failed_at),
        PersistenceState::Ready(_) | PersistenceState::Flushing(_) => None,
    }
}

/// 目录事实与 lease 没有单条 revision 概念；保留该位以维持状态快照契约。
fn oldest_pending_revision(_shared: &WriterShared) -> Option<u64> {
    None
}

fn pending_from_queue(shared: &WriterShared) -> usize {
    // A failed worker can still retain its original batch in inflight before recovery. Read the
    // retained facts without panicking on the failed worker's poisoned lock, in the worker order.
    let inflight = shared
        .inflight
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let queue = shared
        .queue
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    inflight.len().saturating_add(queue.len())
}
