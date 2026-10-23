//! Retained collaboration jobs. Tokio owns scheduling and joins; the driver only drains JoinSet.
use super::{StudioThreadAssembler, agent_services::ServiceError};
use anyhow::{Context, Result, ensure};
use futures::task::AtomicWaker;
use std::{
    collections::BTreeMap,
    future::{Future, poll_fn},
    sync::{Arc, Mutex, MutexGuard, Weak},
    task::Poll,
};
use tokio::{
    sync::{Notify, watch},
    task::{Id, JoinError, JoinHandle, JoinSet},
};

#[derive(Debug, Default)]
struct Jobs {
    closing: bool,
    tasks: JoinSet<()>,
    callers: BTreeMap<Id, String>,
    failure: Option<Arc<JoinError>>,
}

#[derive(Debug, Default)]
struct Shared {
    jobs: Mutex<Jobs>,
    driver: tokio::sync::Mutex<Option<JoinHandle<()>>>,
    wake: AtomicWaker,
    changed: Notify,
}

impl Shared {
    fn jobs(&self) -> MutexGuard<'_, Jobs> {
        self.jobs
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

impl Drop for Shared {
    fn drop(&mut self) {
        if let Some(driver) = self.driver.get_mut() {
            driver.abort();
        }
        // JoinSet aborts on drop. Ordinary shutdown instead cooperatively joins every job first.
    }
}

#[derive(Debug, Clone, Default)]
pub(super) struct AgentOperations(Arc<Shared>);

impl AgentOperations {
    /// Register under the same boundary as the final admission check. Dropping a caller's wait
    /// cannot remove the job, its operation permits, or the retained transaction conclusion.
    pub(super) async fn run<T>(
        &self,
        caller: String,
        admit: impl FnOnce() -> Result<()>,
        operation: impl Future<Output = Result<T>> + Send + 'static,
    ) -> Result<T>
    where
        T: Clone + Send + Sync + 'static,
    {
        let (publication, mut result) = watch::channel(None);
        {
            let mut driver = self.0.driver.lock().await;
            let mut jobs = self.0.jobs();
            ensure!(!jobs.closing, "collaboration operation owner is closing");
            if let Some(error) = jobs.failure.take() {
                return Err(anyhow::Error::new(error));
            }
            admit()?;
            if driver.is_none() {
                // Retain the completion driver before admitting its first worker. It never owns
                // the registry strongly and never takes a lifecycle or per-agent operation gate.
                *driver = Some(tokio::spawn(drive(Arc::downgrade(&self.0))));
            }
            let task = jobs.tasks.spawn(async move {
                let outcome = operation
                    .await
                    .map_err(|error| Arc::new(ServiceError(error)));
                publication.send_replace(Some(outcome));
            });
            jobs.callers.insert(task.id(), caller);
        }
        self.0.wake.wake();
        loop {
            if let Some(outcome) = result.borrow_and_update().clone() {
                return outcome.map_err(anyhow::Error::new);
            }
            result
                .changed()
                .await
                .context("collaboration worker stopped without a conclusion")?;
        }
    }

    pub(super) async fn join_root(&self, root: &str) -> Result<()> {
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            {
                let mut jobs = self.0.jobs();
                if !jobs.callers.values().any(|caller| caller == root) {
                    return match jobs.failure.take() {
                        Some(error) => Err(anyhow::Error::new(error)),
                        None => Ok(()),
                    };
                }
            }
            changed.await;
        }
    }

    /// No abort: a cancelled shutdown waiter leaves the driver handle in its owner slot.
    pub(super) async fn close(&self) -> Result<()> {
        self.0.jobs().closing = true;
        self.0.wake.wake();
        let mut driver = self.0.driver.lock().await;
        if let Some(task) = driver.as_mut() {
            let joined = task.await;
            *driver = None;
            joined.context("collaboration completion driver failed")?;
        }
        match self.0.jobs().failure.take() {
            Some(error) => Err(anyhow::Error::new(error)),
            None => Ok(()),
        }
    }
}

async fn drive(owner: Weak<Shared>) {
    poll_fn(|context| {
        let Some(owner) = owner.upgrade() else {
            return Poll::Ready(());
        };
        // Register before inspecting the set: a new job also wakes an idle (empty-set) driver.
        owner.wake.register(context.waker());
        let mut jobs = owner.jobs();
        while let Poll::Ready(Some(joined)) = jobs.tasks.poll_join_next_with_id(context) {
            let id = match joined {
                Ok((id, ())) => id,
                Err(error) => {
                    let id = error.id();
                    tracing::error!(%error, "collaboration operation task failed");
                    jobs.failure.get_or_insert_with(|| Arc::new(error));
                    id
                }
            };
            jobs.callers.remove(&id);
            // This follows the actual JoinSet join, not just publication of the SQL receipt.
            owner.changed.notify_waiters();
        }
        if jobs.closing && jobs.tasks.is_empty() {
            Poll::Ready(())
        } else {
            Poll::Pending
        }
    })
    .await;
}

impl StudioThreadAssembler {
    pub(super) async fn join_root_operations(&self, root: &str) -> Result<()> {
        let services = self.0.state().agent_services.clone();
        if let Some(services) = services {
            services.operations.join_root(root).await?;
        }
        Ok(())
    }

    pub(super) async fn close_agent_operations(&self) -> Result<()> {
        let services = self.0.state().agent_services.clone();
        if let Some(services) = services {
            services.operations.close().await?;
        }
        Ok(())
    }
}
