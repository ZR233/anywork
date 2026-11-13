//! Execution ownership shared by runtime owners, without Turn, history or delivery facts.
use futures::FutureExt;
use std::{
    collections::BTreeMap,
    future::Future,
    sync::{Arc, Mutex},
};
use tokio::sync::watch;
use tokio_util::{sync::CancellationToken, task::TaskTracker};

/// A cancellation request is distinct from an execution's actual completion.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TaskCancellationReceipt {
    Requested,
    AlreadyRequested,
    AlreadyFinished,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExecutionIdentity {
    pub task_id: String,
    pub call_id: String,
    pub tool_id: String,
}

impl ExecutionIdentity {
    /// Uses the actual owner's call identity, never a transport request or capture filename.
    pub fn new(call_id: String, tool_id: String) -> Self {
        Self {
            task_id: format!("task:{call_id}"),
            call_id,
            tool_id,
        }
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum ExecutionError {
    #[error("execution owner is closed")]
    Closed,
    #[error("unknown execution task: {0}")]
    NotFound(String),
    #[error("duplicate execution identity")]
    Duplicate,
    #[error("execution future panicked")]
    Panicked,
    #[error("task observation cancelled")]
    Cancelled,
    #[error("invalid task wait deadline")]
    Deadline,
}

type Completion<R> = Result<Arc<R>, ExecutionError>;

/// Observation of one accepted execution. Dropping this handle never drops its business future.
pub struct ExecutionLease<R> {
    result: watch::Receiver<Option<Completion<R>>>,
}
impl<R> Clone for ExecutionLease<R> {
    fn clone(&self) -> Self {
        Self {
            result: self.result.clone(),
        }
    }
}
impl<R> ExecutionLease<R> {
    pub fn result(&self) -> Option<Completion<R>> {
        self.result.borrow().clone()
    }
    pub async fn wait(&self) -> Completion<R> {
        let mut result = self.result.clone();
        loop {
            if let Some(value) = result.borrow_and_update().clone() {
                return value;
            }
            result.changed().await.map_err(|_| ExecutionError::Closed)?;
        }
    }
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExecutionSnapshot {
    #[serde(flatten)]
    pub identity: ExecutionIdentity,
    pub finished: bool,
    pub cancel_requested: bool,
}

struct Entry<R> {
    identity: ExecutionIdentity,
    cancellation: CancellationToken,
    result: watch::Sender<Option<Completion<R>>>,
}
struct State<R> {
    closed: bool,
    entries: BTreeMap<String, Entry<R>>,
}

/// A real runtime owner's admitted futures, cancellation and immutable completions.
/// Native attaches committed TaskRecords and persistence outside this execution-only boundary.
pub struct ExecutionTasks<R> {
    state: Arc<Mutex<State<R>>>,
    changes: watch::Sender<()>,
    tracker: TaskTracker,
}
impl<R> Default for ExecutionTasks<R> {
    fn default() -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                closed: false,
                entries: BTreeMap::new(),
            })),
            changes: watch::channel(()).0,
            tracker: TaskTracker::new(),
        }
    }
}
impl<R> std::fmt::Debug for ExecutionTasks<R> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        f.debug_struct("ExecutionTasks")
            .field("closed", &state.closed)
            .field("tasks", &state.entries.len())
            .finish()
    }
}

impl<R: Send + Sync + 'static> ExecutionTasks<R> {
    /// Admission and transfer to the owner's tracker are atomic with respect to close.
    pub fn start(
        &self,
        identity: ExecutionIdentity,
        cancellation: CancellationToken,
        future: impl Future<Output = R> + Send + 'static,
    ) -> Result<ExecutionLease<R>, ExecutionError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closed {
            return Err(ExecutionError::Closed);
        }
        if state.entries.contains_key(&identity.task_id) {
            return Err(ExecutionError::Duplicate);
        }
        let id = identity.task_id.clone();
        let (result, receiver) = watch::channel(None);
        state.entries.insert(
            id,
            Entry {
                identity,
                cancellation,
                result: result.clone(),
            },
        );
        let changes = self.changes.clone();
        self.tracker.spawn(async move {
            let output = std::panic::AssertUnwindSafe(future)
                .catch_unwind()
                .await
                .map(Arc::new)
                .map_err(|_| ExecutionError::Panicked);
            result.send_replace(Some(output));
            changes.send_replace(());
        });
        self.changes.send_replace(());
        Ok(ExecutionLease { result: receiver })
    }

    pub fn token(&self, id: &str) -> Option<CancellationToken> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entries
            .get(id)
            .map(|entry| entry.cancellation.clone())
    }
    pub fn keys(&self) -> Vec<String> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entries
            .keys()
            .cloned()
            .collect()
    }
    pub fn list(&self) -> Vec<ExecutionSnapshot> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entries
            .values()
            .map(|entry| ExecutionSnapshot {
                identity: entry.identity.clone(),
                finished: entry.result.borrow().is_some(),
                cancel_requested: entry.cancellation.is_cancelled(),
            })
            .collect()
    }
    pub fn get(&self, id: &str) -> Result<(ExecutionSnapshot, ExecutionLease<R>), ExecutionError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let entry = state
            .entries
            .get(id)
            .ok_or_else(|| ExecutionError::NotFound(id.into()))?;
        Ok((
            ExecutionSnapshot {
                identity: entry.identity.clone(),
                finished: entry.result.borrow().is_some(),
                cancel_requested: entry.cancellation.is_cancelled(),
            },
            ExecutionLease {
                result: entry.result.subscribe(),
            },
        ))
    }
    /// The caller persists any required cancellation fact before issuing the request here.
    pub fn cancel(&self, id: &str) -> Result<TaskCancellationReceipt, ExecutionError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let entry = state
            .entries
            .get(id)
            .ok_or_else(|| ExecutionError::NotFound(id.into()))?;
        use TaskCancellationReceipt as Receipt;
        let receipt = if entry.result.borrow().is_some() {
            Receipt::AlreadyFinished
        } else if entry.cancellation.is_cancelled() {
            Receipt::AlreadyRequested
        } else {
            entry.cancellation.cancel();
            Receipt::Requested
        };
        self.changes.send_replace(());
        Ok(receipt)
    }
    /// Release only after the adapter has transferred the completion to its original result owner.
    pub fn forget(&self, id: &str) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state
            .entries
            .get(id)
            .is_some_and(|entry| entry.result.borrow().is_some())
        {
            state.entries.remove(id);
        }
    }
    pub fn stop_admission(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .closed = true;
        self.tracker.close();
        self.changes.send_replace(());
    }
    pub fn cancel_all(&self) {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for entry in state.entries.values() {
            if entry.result.borrow().is_none() {
                entry.cancellation.cancel();
            }
        }
        self.changes.send_replace(());
    }
    /// Cancellation of this observer leaves all tracked futures owned and progressing.
    pub async fn join(&self) {
        self.tracker.wait().await;
    }

    /// Wait for any selected execution's actual completion. No Native message or delivery semantics.
    pub async fn wait(
        &self,
        ids: &[String],
        timeout: std::time::Duration,
        cancellation: CancellationToken,
    ) -> Result<(Vec<ExecutionSnapshot>, bool), ExecutionError> {
        let deadline = tokio::time::Instant::now()
            .checked_add(timeout)
            .ok_or(ExecutionError::Deadline)?;
        let mut changes = self.changes.subscribe();
        loop {
            changes.borrow_and_update();
            if cancellation.is_cancelled() {
                return Err(ExecutionError::Cancelled);
            }
            let tasks = ids
                .iter()
                .map(|id| self.get(id).map(|(task, _)| task))
                .collect::<Result<Vec<_>, _>>()?;
            if tasks.iter().any(|task| task.finished) {
                return Ok((tasks, false));
            }
            if tokio::time::Instant::now() >= deadline {
                return Ok((tasks, true));
            }
            tokio::select! {
                _ = cancellation.cancelled() => return Err(ExecutionError::Cancelled),
                changed = changes.changed() => changed.map_err(|_| ExecutionError::Closed)?,
                _ = tokio::time::sleep_until(deadline) => {},
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn abandoned_observation_keeps_accepted_future_owned_until_close_and_join() {
        let tasks = ExecutionTasks::default();
        let token = CancellationToken::new();
        let operation = token.clone();
        let (finished, mut completion) = tokio::sync::mpsc::channel(1);
        let identity = ExecutionIdentity::new("real-call".into(), "command".into());
        let id = identity.task_id.clone();
        let lease = tasks
            .start(identity, token, async move {
                operation.cancelled().await;
                finished.send(42).await.unwrap();
                42
            })
            .unwrap();
        drop(lease);
        assert!(!tasks.get(&id).unwrap().0.finished);
        tasks.stop_admission();
        tasks.cancel_all();
        tasks.join().await;
        assert_eq!(completion.recv().await, Some(42));
        assert_eq!(*tasks.get(&id).unwrap().1.wait().await.unwrap(), 42);
        assert!(
            tasks
                .start(
                    ExecutionIdentity::new("other".into(), "command".into()),
                    CancellationToken::new(),
                    async { 0 }
                )
                .is_err()
        );
    }
}
