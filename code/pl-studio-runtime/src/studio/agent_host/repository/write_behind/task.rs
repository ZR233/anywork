//! The writer's original supervisor slot and retained real completion.
use std::sync::{Arc, Mutex};

use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use tokio::sync::oneshot;
use tokio::task::AbortHandle;

use super::failure::WriteBehindCause;
use super::handle::WriterShared;
use super::worker::supervise_writer;

type Completion = Shared<BoxFuture<'static, Result<(), Arc<WriteBehindCause>>>>;

pub(super) struct SupervisorTask {
    pub(super) identity: Arc<()>,
    completion: Completion,
    finished: AbortHandle,
}

impl SupervisorTask {
    /// The start gate prevents business execution until the original slot is installed.
    pub(super) fn prepare(
        shared: Arc<WriterShared>,
        pending: Arc<std::sync::atomic::AtomicUsize>,
    ) -> (Arc<Self>, oneshot::Sender<()>) {
        let identity = Arc::new(());
        let worker_identity = identity.clone();
        let (start, admitted) = oneshot::channel();
        let task = tokio::spawn(async move {
            admitted.await?;
            supervise_writer(shared, pending, worker_identity).await;
            Ok::<_, oneshot::error::RecvError>(())
        });
        let finished = task.abort_handle();
        let completion = async move {
            match task.await {
                Ok(Ok(())) => Ok(()),
                Ok(Err(error)) => Err(Arc::new(WriteBehindCause::AdmissionClosed(Arc::new(error)))),
                Err(error) => Err(Arc::new(WriteBehindCause::SupervisorJoin(Arc::new(error)))),
            }
        }
        .boxed()
        .shared();
        (
            Arc::new(Self {
                identity,
                completion,
                finished,
            }),
            start,
        )
    }

    pub(super) async fn join(&self) -> Result<(), Arc<WriteBehindCause>> {
        self.completion.clone().await
    }

    pub(super) fn observed_result(&self) -> Option<Result<(), Arc<WriteBehindCause>>> {
        self.completion.peek().cloned()
    }

    /// Negative lifecycle information only; callers still join before replacing the slot.
    pub(super) fn is_finished(&self) -> bool {
        self.finished.is_finished()
    }
}

#[derive(Default)]
pub(super) struct SupervisorLifecycle {
    // None means never started, not a handle taken by shutdown. Joined tasks remain here.
    pub(super) task: Option<Arc<SupervisorTask>>,
    pub(super) stopping_through: Option<u64>,
    pub(super) shutdown_observers: usize,
}

/// Cancellation drops only this observation, never the retained actual task or stopping fence.
pub(super) struct ShutdownObservation {
    pub(super) through: u64,
    pub(super) task: Option<Arc<SupervisorTask>>,
    lifecycle: Arc<Mutex<SupervisorLifecycle>>,
}

impl ShutdownObservation {
    pub(super) fn register(lifecycle: &Arc<Mutex<SupervisorLifecycle>>, through: u64) -> Self {
        let mut state = lifecycle
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let through = *state.stopping_through.get_or_insert(through);
        state.shutdown_observers += 1;
        Self {
            through,
            task: state.task.clone(),
            lifecycle: lifecycle.clone(),
        }
    }
}

impl Drop for ShutdownObservation {
    fn drop(&mut self) {
        let mut state = self
            .lifecycle
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.shutdown_observers -= 1;
    }
}
