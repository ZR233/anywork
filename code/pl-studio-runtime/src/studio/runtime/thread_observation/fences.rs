//! Fixed fences retained by the original observation, independently of its waiters.
use std::sync::{Arc, Mutex};

use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_core::thread::ThreadLifecycle;

use crate::studio::agent_host::{ThreadWriteBehindWriter, WriteBehindFlushFailure};
use crate::studio::storage::thread_writer::{HistoryChannel, HistoryStatus};

use super::ObservationServices;

#[derive(Clone)]
pub(super) struct HistoryFence {
    pub(super) channel: Arc<HistoryChannel>,
    pub(super) through: u64,
}

impl std::fmt::Debug for HistoryFence {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HistoryFence")
            .field("through", &self.through)
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Clone, thiserror::Error)]
#[error("Thread {thread_id} history did not reach its original ticket {through}: {status:?}")]
pub(in crate::studio::runtime) struct HistoryFenceFailure {
    pub(in crate::studio::runtime) thread_id: String,
    pub(in crate::studio::runtime) through: u64,
    pub(in crate::studio::runtime) status: HistoryStatus,
    pub(super) fence: HistoryFence,
    #[source]
    pub(in crate::studio::runtime) closed: Option<Arc<tokio::sync::watch::error::RecvError>>,
}

impl HistoryFence {
    pub(super) async fn wait(&self, id: &str) -> Result<(), HistoryFenceFailure> {
        let mut progress = self.channel.subscribe();
        loop {
            let status = progress.borrow_and_update().clone();
            if status.committed_sequence >= self.through {
                return Ok(());
            }
            if status.error.is_some() || status.fault.is_some() {
                return Err(self.failure(id, status, None));
            }
            if let Err(error) = progress.changed().await {
                let status = progress.borrow().clone();
                if status.committed_sequence >= self.through {
                    return Ok(());
                }
                return Err(self.failure(id, status, Some(Arc::new(error))));
            }
        }
    }

    fn failure(
        &self,
        id: &str,
        status: HistoryStatus,
        closed: Option<Arc<tokio::sync::watch::error::RecvError>>,
    ) -> HistoryFenceFailure {
        HistoryFenceFailure {
            thread_id: id.to_owned(),
            through: self.through,
            status,
            fence: self.clone(),
            closed,
        }
    }
}

impl HistoryFenceFailure {
    pub(super) fn can_resume(&self, services: &ObservationServices) -> bool {
        let status = self.fence.channel.subscribe().borrow().clone();
        status.committed_sequence >= self.through
            || (self.closed.is_none()
                && services
                    .store
                    .thread_persistence()
                    .can_retry_history_channel(&self.thread_id, &self.fence.channel))
    }
}

type WriteWait = Shared<BoxFuture<'static, Result<(), WriteBehindFlushFailure>>>;

pub(super) struct WriteFence {
    pub(super) through: u64,
    writer: ThreadWriteBehindWriter,
    wait: Mutex<WriteWait>,
}

impl std::fmt::Debug for WriteFence {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("WriteFence")
            .field("through", &self.through)
            .finish_non_exhaustive()
    }
}

impl WriteFence {
    pub(super) fn capture(writer: &ThreadWriteBehindWriter) -> Arc<Self> {
        let through = writer.admitted_ticket();
        let original = writer.clone();
        Arc::new(Self {
            through,
            writer: writer.clone(),
            wait: Mutex::new(
                async move { original.flush_through(through).await }
                    .boxed()
                    .shared(),
            ),
        })
    }

    pub(super) fn can_resume(&self) -> bool {
        let wait = self
            .wait
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match wait.peek() {
            Some(Err(failure)) => {
                self.writer.saved_watermark() >= self.through
                    || self.writer.can_reobserve_original_flush(failure)
            }
            Some(Ok(())) | None => false,
        }
    }

    pub(super) fn is_pending(&self) -> bool {
        self.wait
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .peek()
            .is_none()
    }

    pub(super) async fn wait(&self) -> Result<(), WriteBehindFlushFailure> {
        let (wait, retired) = {
            let mut slot = self
                .wait
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let failure = slot
                .peek()
                .and_then(|result| result.as_ref().err())
                .cloned();
            let retired = if let Some(failure) = failure
                && (self.writer.saved_watermark() >= self.through
                    || self.writer.can_reobserve_original_flush(&failure))
            {
                let writer = self.writer.clone();
                let next = async move { writer.reobserve_original_flush(&failure).await }
                    .boxed()
                    .shared();
                Some(std::mem::replace(&mut *slot, next))
            } else {
                None
            };
            (slot.clone(), retired)
        };
        drop(retired);
        wait.await
    }
}

/// One original projection target. It contains no Observation/aggregate failure back-reference.
/// A cancelled waiter leaves this capsule in WorkerState; successful synchronization can retire it.
#[derive(Debug)]
pub(super) struct ObservationFence {
    pub(super) target: u64,
    pub(super) lifecycle: ThreadLifecycle,
    pub(super) state: Mutex<ObservationFenceState>,
}

#[derive(Debug, Default)]
pub(super) struct ObservationFenceState {
    pub(super) history: Option<HistoryFence>,
    pub(super) history_done: bool,
    pub(super) final_history: Option<HistoryFence>,
    pub(super) final_history_done: bool,
    pub(super) write: Option<Arc<WriteFence>>,
    pub(super) synchronized: bool,
    pub(super) finished_observed: bool,
    pub(super) completion_observed: bool,
    pub(super) scopes_done: bool,
    pub(super) scope_issues: Vec<pl_protocol::studio::FeedCloseIssue>,
}

impl ObservationFence {
    pub(super) fn new(target: u64, lifecycle: ThreadLifecycle) -> Arc<Self> {
        Arc::new(Self {
            target,
            lifecycle,
            state: Mutex::new(ObservationFenceState::default()),
        })
    }
}

/// Inner projection fences follow the original worker's phase, not a later queue watermark.
#[derive(Default)]
pub(super) struct ProjectionFences {
    pub(super) association: Option<Arc<WriteFence>>,
    pub(super) turn: Option<(String, HistoryFence)>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum ProjectionPhase {
    Initialize,
    Effects,
    Stream,
    Product,
    Summary,
    Directory,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum EffectPhase {
    Project,
    Billing,
    Result,
    Report,
}

pub(super) struct PendingEffect {
    pub(super) write: Arc<pl_core::thread::cold::ThreadWrite>,
    pub(super) phase: EffectPhase,
    pub(super) result: Option<Arc<crate::studio::thread_projection::TurnResult>>,
}

/// Progress inside one original pass. A later fence failure cannot replay an already folded
/// effect, billed fact, acknowledged parent notification or completed product step.
pub(super) struct ProjectionPass {
    pub(super) snapshot: Arc<pl_core::thread::ThreadSnapshot>,
    pub(super) products: bool,
    pub(super) phase: ProjectionPhase,
    pub(super) effect: Option<PendingEffect>,
    pub(super) newest_commit_at: i64,
    pub(super) product: Option<pl_protocol::Thread>,
    pub(super) summary_result: Option<Arc<crate::studio::thread_projection::TurnResult>>,
    pub(super) summary: Option<String>,
}

impl ProjectionPass {
    pub(super) fn new(snapshot: Arc<pl_core::thread::ThreadSnapshot>, products: bool) -> Self {
        Self {
            snapshot,
            products,
            phase: ProjectionPhase::Initialize,
            effect: None,
            newest_commit_at: 0,
            product: None,
            summary_result: None,
            summary: None,
        }
    }
}
