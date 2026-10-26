//! Runtime-wide ownership of admitted detail calls. Caller cancellation never abandons a read.
use std::collections::BTreeMap;
use std::future::Future;
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
use pl_protocol::studio::{StudioError, StudioErrorCode, StudioErrorDetails};

use super::background_task::{BackgroundTask, BackgroundTaskFailure};

const DETAIL_CALL_LIMIT: usize = 64;

#[derive(Clone, Default)]
pub(super) struct ReadCalls(Arc<Mutex<State>>);

#[derive(Default)]
struct State {
    sealed: bool,
    tasks: BTreeMap<String, Arc<BackgroundTask>>,
}

/// One admission in the existing runtime-wide pool. A scope retains the same task, not a second
/// permit or wrapper task, so its close can observe the actual query even if its caller leaves.
pub(super) struct ReadCall<T> {
    pub(super) id: String,
    pub(super) task: Arc<BackgroundTask>,
    result: tokio::sync::oneshot::Receiver<Result<T>>,
    owner: ReadCalls,
}

#[derive(Debug, thiserror::Error)]
#[error("Detail read {id} did not join successfully")]
pub(super) struct ReadCallJoinFailure {
    pub(super) id: String,
    #[source]
    pub(super) error: Arc<BackgroundTaskFailure>,
}

impl<T: Send + 'static> ReadCall<T> {
    /// Preserve the original accepted operation's completion after the admission fence closes.
    /// This does not admit new calls, bypass capacity, or detach a worker from its close owner.
    pub(super) async fn wait_committed(self) -> Result<T> {
        self.task
            .join()
            .await
            .context("committed detail call task failed")?;
        let value = self
            .result
            .await
            .context("committed detail call result was not published")?;
        self.owner
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .tasks
            .remove(&self.id);
        value
    }

    pub(super) async fn wait(self) -> Result<T> {
        self.task.join().await.context("detail read task failed")?;
        let value = self
            .result
            .await
            .context("detail read result was not published")?;
        let mut state = self
            .owner
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.tasks.remove(&self.id);
        if state.sealed {
            return Err(cancelled());
        }
        value
    }
}

impl ReadCalls {
    /// Admission, task installation and closing share one synchronous registration boundary.
    pub(super) fn run<T, F>(
        &self,
        read: F,
    ) -> impl Future<Output = Result<T>> + Send + 'static + use<T, F>
    where
        T: Send + 'static,
        F: Future<Output = Result<T>> + Send + 'static,
    {
        let admitted = self.register(read);
        async move { admitted?.wait().await }
    }

    pub(super) fn register<T, F>(&self, read: F) -> Result<ReadCall<T>>
    where
        T: Send + 'static,
        F: Future<Output = Result<T>> + Send + 'static,
    {
        self.register_with_cleanup(read, || {})
    }

    pub(super) fn register_with_cleanup<T, F>(
        &self,
        read: F,
        cleanup: impl FnOnce() + Send + 'static,
    ) -> Result<ReadCall<T>>
    where
        T: Send + 'static,
        F: Future<Output = Result<T>> + Send + 'static,
    {
        {
            let mut state = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.tasks.retain(|_, task| !task.succeeded());
            if state.sealed {
                Err(cancelled())
            } else if state.tasks.len() >= DETAIL_CALL_LIMIT {
                Err(StudioError::new(
                    StudioErrorCode::Overloaded,
                    "Studio detail-call capacity is exhausted",
                    true,
                )
                .with_details(StudioErrorDetails::ResourceLimit {
                    resource: "detailCalls".into(),
                    capacity: DETAIL_CALL_LIMIT as u64,
                })
                .into())
            } else {
                let id = crate::studio::new_id("detail-call");
                let (result, receiver) = tokio::sync::oneshot::channel();
                let task = BackgroundTask::with_cleanup(
                    tokio::spawn(async move {
                        let value = read.await;
                        let _ = result.send(value);
                    }),
                    cleanup,
                );
                state.tasks.insert(id.clone(), task.clone());
                Ok(ReadCall {
                    id,
                    task,
                    result: receiver,
                    owner: self.clone(),
                })
            }
        }
    }

    pub(super) fn seal(&self) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed = true;
    }

    pub(super) async fn close(&self) -> Vec<ReadCallJoinFailure> {
        self.seal();
        let tasks: Vec<_> = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .tasks
            .iter()
            .map(|(id, task)| (id.clone(), task.clone()))
            .collect();
        let results = futures::future::join_all(tasks.iter().map(|(_, task)| task.join())).await;
        let mut state = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.tasks.retain(|_, task| !task.succeeded());
        tasks
            .into_iter()
            .zip(results)
            .filter_map(|((id, _), result)| {
                result.err().map(|error| ReadCallJoinFailure { id, error })
            })
            .collect()
    }
}

fn cancelled() -> anyhow::Error {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Studio detail reads are closed",
        false,
    )
    .into()
}
