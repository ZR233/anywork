//! Private producer failures; public persistence DTOs remain redacted projections.
use std::sync::Arc;

use tokio::sync::{oneshot, watch};
use tokio::task::JoinError;

use crate::PureError;

use super::state::WriterHealth;

#[derive(Debug, thiserror::Error)]
pub(in crate::studio) enum WriteBehindCause {
    #[error("write-behind store operation failed")]
    Store(#[source] Arc<PureError>),
    #[error("write-behind inner worker did not join successfully")]
    WorkerJoin(#[source] Arc<JoinError>),
    #[error("write-behind supervisor did not join successfully")]
    SupervisorJoin(#[source] Arc<JoinError>),
    #[error("write-behind supervisor admission closed")]
    AdmissionClosed(#[source] Arc<oneshot::error::RecvError>),
    #[error("write-behind progress closed")]
    ProgressClosed(#[source] Arc<watch::error::RecvError>),
    #[error("{0}")]
    LegacyDiagnostic(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::studio) enum WriteBehindTaskState {
    NotStarted,
    Running,
    Stopping,
    Joined,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::studio) enum WriteBehindFlushFailureKind {
    Blocked,
    NotRunning,
    StoppingUnsaved,
    StoppedBeforeTicket,
    DurabilityClosed,
    HealthClosed,
    SupervisorFailed,
}

/// Captures one fixed fence and its real producer, never a lookup of a newer writer by ID.
#[derive(Debug, Clone, thiserror::Error)]
#[error("write-behind flush through {through} failed ({kind:?})")]
pub(in crate::studio) struct WriteBehindFlushFailure {
    pub(in crate::studio) through: u64,
    pub(in crate::studio) kind: WriteBehindFlushFailureKind,
    pub(in crate::studio) executor: WriteBehindTaskState,
    /// Present only for this task (or an explicitly unidentified legacy capture).
    pub(in crate::studio) health: Option<WriterHealth>,
    pub(in crate::studio) completion: Option<Result<(), Arc<WriteBehindCause>>>,
    #[source]
    pub(in crate::studio) cause: Option<Arc<WriteBehindCause>>,
    pub(super) owner: Arc<()>,
    pub(super) task: Option<Arc<()>>,
}

#[derive(Debug, Clone, thiserror::Error)]
pub(in crate::studio) enum WriteBehindShutdownIssue {
    #[error("write-behind supervisor failed")]
    Supervisor(#[source] Arc<WriteBehindCause>),
    #[error("write-behind retained a blocked producer")]
    Blocked(#[source] Arc<WriteBehindCause>),
    #[error("write-behind stopped after a retryable store failure")]
    Degraded(#[source] Arc<WriteBehindCause>),
    #[error("write-behind stopped with {pending} unsaved commits")]
    Unsaved { pending: usize },
    #[error("write-behind stopped at {durable} before its fixed fence {through}")]
    FenceNotDurable { through: u64, durable: u64 },
}

/// A failed stop retains all simultaneous facts, including a failed actual supervisor join.
#[derive(Debug, Clone, thiserror::Error)]
#[error("write-behind shutdown through {through} retained unresolved obligations")]
pub(in crate::studio) struct WriteBehindShutdownFailure {
    pub(in crate::studio) through: u64,
    pub(in crate::studio) health: WriterHealth,
    pub(in crate::studio) issues: Vec<WriteBehindShutdownIssue>,
    #[source]
    pub(in crate::studio) cause: Option<Arc<WriteBehindCause>>,
    pub(in crate::studio) owner: Arc<()>,
    pub(in crate::studio) task: Option<Arc<()>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::studio) enum WriteBehindRetryFailureKind {
    ShutdownInProgress,
    SupervisorFailed,
    QueueNotRetained,
}

#[derive(Debug, Clone, thiserror::Error)]
#[error("original write-behind recovery was not admitted ({kind:?})")]
pub(in crate::studio) struct WriteBehindRetryFailure {
    pub(in crate::studio) kind: WriteBehindRetryFailureKind,
    #[source]
    pub(in crate::studio) cause: Option<Arc<WriteBehindCause>>,
    pub(in crate::studio) owner: Arc<()>,
    pub(in crate::studio) task: Option<Arc<()>>,
}
