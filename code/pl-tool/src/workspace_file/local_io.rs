//! Pre-owned, cancellation-safe root acquisition and ordinary-file read workers.

use std::sync::{Arc, Mutex};

use pl_protocol::Result;
use tokio::sync::oneshot;
use tokio_util::task::TaskTracker;

/// Host-owned root/read work. Store a clone in the host lifecycle *before* calling an async
/// root/backend factory. Cloning a temporary owner inside that future is not host ownership.
#[derive(Debug, Clone, Default)]
pub struct LocalFileIoOwner(Arc<IoState>);

#[derive(Debug, Default)]
struct IoState {
    sealed: Mutex<bool>,
    tasks: TaskTracker,
}

impl LocalFileIoOwner {
    /// Seals new root/read admission and waits for the real blocking workers to be joined.
    /// Cancelling this wait leaves the same tracker and workers available for another close.
    /// Root acquisition and reads have no pending mutable stage or cleanup to replay.
    /// # Errors
    /// This root/read owner has no fallible finalizer; individual IO/worker failures belong
    /// to their request. Authorized managed directories persist after a cancelled ensure.
    /// Completion, not a successful read or root acquisition, releases the work.
    pub async fn close(&self) -> Result<()> {
        {
            let mut sealed = self
                .0
                .sealed
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            *sealed = true;
        }
        // Admission is already sealed. Notify tracker waiters outside the registry lock.
        self.0.tasks.close();
        self.0.tasks.wait().await;
        Ok(())
    }

    pub(super) async fn run<T, F>(&self, operation: F) -> Result<T>
    where
        T: Send + 'static,
        F: FnOnce() -> Result<T> + Send + 'static,
    {
        let (reply, result) = oneshot::channel();
        {
            let sealed = self
                .0
                .sealed
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if *sealed {
                return Err(crate::tool_error("file", "local file IO owner is closed"));
            }
            // Track the supervisor before releasing the admission lock. It, not the caller,
            // owns and awaits the blocking JoinHandle even when the reply receiver is dropped.
            let owner = self.clone();
            self.0.tasks.spawn(async move {
                let completed = tokio::task::spawn_blocking(operation).await;
                let completed = completed
                    .map_err(|error| crate::tool_error("file", error))
                    .and_then(std::convert::identity);
                let _ = reply.send(completed);
                drop(owner);
            });
        }
        result
            .await
            .map_err(|error| crate::tool_error("file", error))?
    }
}
