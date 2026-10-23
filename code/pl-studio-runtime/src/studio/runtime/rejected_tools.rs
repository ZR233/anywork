//! Owns failed candidate closures across refresh retries and cancelled shutdown waiters.
use pl_core::{
    thread::{IdleReconfiguration, ThreadError, ThreadHandle, ThreadSnapshot},
    tool::opaque::{Registration, RejectedTools, ToolError},
};
use std::sync::{Arc, Mutex};

#[derive(Clone, Default)]
pub(super) struct RejectedToolOwners {
    entries: Arc<Mutex<Vec<Arc<Entry>>>>,
    stop: Arc<Mutex<tokio_util::sync::CancellationToken>>,
}
struct Entry {
    thread: ThreadHandle,
    operation: Option<String>,
    gate: tokio::sync::Mutex<()>,
    resources: Mutex<Option<Resources>>,
}
enum Resources {
    Rejected(Box<RejectedTools>),
    // The owned transfer may retire candidates or register a final reconfiguration.
    Retiring(tokio::task::JoinHandle<Result<(), TransferFailure>>),
}
#[derive(Debug)]
enum TransferFailure {
    Core(ThreadError),
    // The product has already transferred any remaining persistence/recovery obligation to its
    // existing owners before returning this resource-free error. Core must not be replayed.
    Product(anyhow::Error),
}
struct Lease {
    entry: Arc<Entry>,
    resources: Option<Resources>,
}
impl Drop for Lease {
    fn drop(&mut self) {
        if let Some(resources) = self.resources.take() {
            *self
                .entry
                .resources
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(resources);
        }
    }
}
#[derive(Debug, thiserror::Error)]
#[error("rejected tool candidate cleanup failed: {0}")]
struct CleanupFailure(#[source] Arc<ToolError>);

#[derive(Debug, thiserror::Error)]
#[error(
    "tool candidate retirement failed ({cleanup}); operation: {operation:?}; original refusal: {rejection:?}"
)]
struct RetirementFailure {
    cleanup: String,
    operation: Option<String>,
    rejection: Option<String>,
}

impl RejectedToolOwners {
    pub(super) fn start(&self) -> tokio_util::sync::CancellationToken {
        let token = tokio_util::sync::CancellationToken::new();
        *self
            .stop
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = token.clone();
        token
    }
    pub(super) fn stop(&self) {
        self.stop
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .cancel();
    }
    pub(super) fn retain(&self, thread: ThreadHandle, resources: Box<RejectedTools>) {
        self.insert(thread, Resources::Rejected(resources), None);
    }

    /// Owns retirement before its first await. Cancelling the waiter leaves the exact in-flight
    /// transfer registered for retry/shutdown, including a late RejectedTools result.
    pub(super) async fn retire(
        &self,
        thread: ThreadHandle,
        tools: Vec<Registration>,
        operation: String,
    ) -> anyhow::Result<()> {
        let owner = thread.clone();
        self.transfer(thread, operation, async move {
            owner
                .retire_tools(tools)
                .await
                .map_err(TransferFailure::Core)
        })
        .await
    }

    /// Owns both the core handoff and the mandatory product continuation. The continuation must
    /// transfer any unfinished persistence/recovery obligation before returning an error.
    pub(super) async fn reconfigure<T, F, C>(
        &self,
        thread: ThreadHandle,
        update: IdleReconfiguration,
        operation: String,
        complete: F,
    ) -> anyhow::Result<T>
    where
        T: Send + 'static,
        F: FnOnce(ThreadSnapshot) -> C + Send + 'static,
        C: std::future::Future<Output = anyhow::Result<T>> + Send + 'static,
    {
        let owner = thread.clone();
        self.transfer(thread, operation, async move {
            let snapshot = owner
                .reconfigure(update)
                .await
                .map_err(TransferFailure::Core)?;
            complete(snapshot).await.map_err(TransferFailure::Product)
        })
        .await
    }

    async fn transfer<T: Send + 'static>(
        &self,
        thread: ThreadHandle,
        operation: String,
        transfer: impl std::future::Future<Output = Result<T, TransferFailure>> + Send + 'static,
    ) -> anyhow::Result<T> {
        let (completed, result) = tokio::sync::oneshot::channel();
        let transfer_operation = operation.clone();
        let task = tokio::spawn(async move {
            match transfer.await {
                Ok(value) => {
                    // All product obligations are complete (or durably transferred) before this
                    // response. Losing its receiver never discards a post-commit continuation.
                    let _ = completed.send(Ok(value));
                    Ok(())
                }
                Err(error) => {
                    let diagnostic = match &error {
                        TransferFailure::Core(ThreadError::RejectedTools(resources)) => {
                            RetirementFailure {
                                cleanup: resources.to_string(),
                                operation: Some(transfer_operation),
                                rejection: resources.rejection().map(ToString::to_string),
                            }
                            .into()
                        }
                        TransferFailure::Core(error) => anyhow::anyhow!(
                            "tool transfer failed ({error}); operation: {transfer_operation}"
                        ),
                        TransferFailure::Product(error) => anyhow::anyhow!(
                            "product completion failed ({error:#}); operation: {transfer_operation}"
                        ),
                    };
                    // Another retry waiter can settle the task first. Keep the original outcome
                    // available independently, but leave its resource box in this owned task.
                    let _ = completed.send(Err(diagnostic));
                    Err(error)
                }
            }
        });
        let entry = self.insert(thread, Resources::Retiring(task), Some(operation));
        let settlement = self.retry_entry(entry).await;
        match (result.await, settlement) {
            (Ok(Ok(value)), Ok(())) => Ok(value),
            (_, Err(error)) | (Ok(Err(error)), Ok(())) => Err(error),
            (Err(error), Ok(())) => Err(error.into()),
        }
    }

    fn insert(
        &self,
        thread: ThreadHandle,
        resources: Resources,
        operation: Option<String>,
    ) -> Arc<Entry> {
        let entry = Arc::new(Entry {
            thread,
            operation,
            gate: Default::default(),
            resources: Mutex::new(Some(resources)),
        });
        self.entries
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(entry.clone());
        entry
    }
    pub(super) async fn retry(&self, thread: Option<&ThreadHandle>) -> anyhow::Result<()> {
        let entries = self
            .entries
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .iter()
            .filter(|entry| thread.is_none_or(|thread| thread.same_instance(&entry.thread)))
            .cloned()
            .collect::<Vec<_>>();
        for entry in entries {
            self.retry_entry(entry).await?;
        }
        Ok(())
    }

    async fn retry_entry(&self, entry: Arc<Entry>) -> anyhow::Result<()> {
        // This permit serializes cleanup operations; the resource data lock never spans IO.
        let _permit = entry.gate.lock().await;
        let resources = entry
            .resources
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        let mut lease = Lease {
            entry: entry.clone(),
            resources,
        };
        match &mut lease.resources {
            Some(Resources::Rejected(resources)) => {
                if let Err(error) = resources.retry_close().await {
                    let error = anyhow::Error::new(CleanupFailure(error));
                    return Err(match &entry.operation {
                        Some(operation) => error.context(operation.clone()),
                        None => error,
                    });
                }
                lease.resources = None;
            }
            Some(Resources::Retiring(task)) => {
                let result = task.await;
                // Join errors are terminal too. Never leave an observed JoinHandle to be polled
                // again; a cancelled waiter, in contrast, returns the unobserved handle via Lease.
                lease.resources = None;
                let result = match result {
                    Ok(result) => result,
                    Err(error) => {
                        self.remove(&entry);
                        return Err(error.into());
                    }
                };
                if let Err(error) = result {
                    match error {
                        TransferFailure::Core(ThreadError::RejectedTools(resources)) => {
                            let diagnostic = RetirementFailure {
                                cleanup: resources.to_string(),
                                operation: entry.operation.clone(),
                                rejection: resources.rejection().map(ToString::to_string),
                            };
                            lease.resources = Some(Resources::Rejected(resources));
                            return Err(diagnostic.into());
                        }
                        TransferFailure::Core(error) => {
                            self.remove(&entry);
                            return Err(error.into());
                        }
                        TransferFailure::Product(error) => {
                            self.remove(&entry);
                            return Err(error);
                        }
                    }
                }
            }
            None => {}
        }
        self.remove(&entry);
        Ok(())
    }

    fn remove(&self, entry: &Arc<Entry>) {
        self.entries
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .retain(|current| !Arc::ptr_eq(current, entry));
    }
}
