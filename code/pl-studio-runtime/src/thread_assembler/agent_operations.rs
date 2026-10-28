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
    sync::{Notify, oneshot},
    task::{Id, JoinError, JoinHandle, JoinSet},
};

#[derive(Debug, Default)]
struct Jobs {
    closing: bool,
    tasks: JoinSet<()>,
    callers: BTreeMap<Id, OperationIdentity>,
    failure: BTreeMap<OperationIdentity, Arc<JoinError>>,
    background_failure: BTreeMap<OperationIdentity, Arc<ServiceError>>,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct OperationIdentity {
    caller: String,
    key: OperationKey,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
enum OperationKey {
    Call(String),
    Review(String),
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
    pub(super) fn terminal_blocked(&self, caller: &str, producer: &str) -> bool {
        self.0
            .jobs()
            .background_failure
            .contains_key(&OperationIdentity {
                caller: caller.into(),
                key: OperationKey::Review(producer.into()),
            })
    }
    pub(super) fn resume_terminal(&self, caller: &str, producer: &str) {
        self.0.jobs().background_failure.remove(&OperationIdentity {
            caller: caller.into(),
            key: OperationKey::Review(producer.into()),
        });
        self.0.changed.notify_waiters();
    }
    pub(super) fn block_terminal(
        &self,
        caller: &str,
        producer: &str,
        error: &anyhow::Error,
        first: &mut Option<Vec<String>>,
    ) {
        let current = error
            .chain()
            .take(4)
            .map(|error| error.to_string().chars().take(512).collect::<String>())
            .collect::<Vec<_>>();
        // An ACK failure may subsequently expose its retained receiver's cleanup failure.
        // Keep the first causal episode as well as the latest stage, within the same eight-layer
        // bound; a later cleanup error must not erase the original delivery diagnostic.
        let initial = first.get_or_insert_with(|| current.clone());
        let diagnostic = if initial == &current {
            current.join(": ")
        } else {
            initial
                .iter()
                .chain(&current)
                .take(8)
                .cloned()
                .collect::<Vec<_>>()
                .join(": ")
        };
        let identity = OperationIdentity {
            caller: caller.into(),
            key: OperationKey::Review(producer.into()),
        };
        self.0.jobs().background_failure.insert(
            identity,
            Arc::new(ServiceError(anyhow::anyhow!(diagnostic))),
        );
        self.0.changed.notify_waiters();
    }
    pub(super) fn has_failed_producer(&self, caller: &str) -> bool {
        let jobs = self.0.jobs();
        jobs.background_failure
            .keys()
            .chain(jobs.failure.keys())
            .any(|identity| {
                identity.caller == caller && matches!(identity.key, OperationKey::Review(_))
            })
    }
    /// Register a host producer without making the projection wait for its own later effects.
    /// The same JoinSet owns cancellation, panics and shutdown; a failed producer blocks joins.
    pub(super) async fn start(
        &self,
        caller: String,
        producer: String,
        admit: impl FnOnce() -> Result<()>,
        operation: impl Future<Output = Result<()>> + Send + 'static,
    ) -> Result<()> {
        let mut driver = self.0.driver.lock().await;
        let mut jobs = self.0.jobs();
        ensure!(!jobs.closing, "collaboration operation owner is closing");
        let identity = OperationIdentity {
            caller,
            key: OperationKey::Review(producer),
        };
        if jobs.callers.values().any(|running| running == &identity) {
            // An explicit registration retry asks the SAME retained job to reconsider its block;
            // it never detaches/replaces that job or its frozen authority. Real recovery also has
            // independent history/capacity notifications and does not depend on this request.
            jobs.background_failure.remove(&identity);
            drop(jobs);
            self.0.changed.notify_waiters();
            return Ok(());
        }
        admit()?;
        if driver.is_none() {
            *driver = Some(tokio::spawn(drive(Arc::downgrade(&self.0))));
        }
        let owner = Arc::downgrade(&self.0);
        let result_identity = identity.clone();
        let task = jobs.tasks.spawn(async move {
            let result = operation.await;
            if let Some(owner) = owner.upgrade() {
                let mut jobs = owner.jobs();
                match result {
                    Err(error) => {
                        jobs.background_failure
                            .insert(result_identity, Arc::new(ServiceError(error)));
                    }
                    Ok(()) => {
                        // Only a successful replay of this exact producer can discharge its
                        // earlier error; an unrelated caller's join never consumes it.
                        jobs.background_failure.remove(&result_identity);
                        jobs.failure.remove(&result_identity);
                    }
                }
                owner.changed.notify_waiters();
            }
        });
        jobs.callers.insert(task.id(), identity);
        drop(jobs);
        self.0.wake.wake();
        Ok(())
    }
    /// Register under the same boundary as the final admission check. Dropping a caller's wait
    /// cannot remove the job, its operation permits, or the retained transaction conclusion.
    pub(super) async fn run<T>(
        &self,
        caller: String,
        operation_id: String,
        admit: impl FnOnce() -> Result<()>,
        operation: impl Future<Output = Result<T>> + Send + 'static,
    ) -> Result<T>
    where
        T: Send + 'static,
    {
        let (publication, result) = oneshot::channel();
        {
            let mut driver = self.0.driver.lock().await;
            let mut jobs = self.0.jobs();
            ensure!(!jobs.closing, "collaboration operation owner is closing");
            let identity = OperationIdentity {
                caller,
                key: OperationKey::Call(operation_id),
            };
            admit()?;
            if driver.is_none() {
                // Retain the completion driver before admitting its first worker. It never owns
                // the registry strongly and never takes a lifecycle or per-agent operation gate.
                *driver = Some(tokio::spawn(drive(Arc::downgrade(&self.0))));
            }
            let completed_identity = identity.clone();
            let retained_owner = Arc::downgrade(&self.0);
            let task = jobs.tasks.spawn(async move {
                let outcome = operation
                    .await
                    .map_err(|error| Arc::new(ServiceError(error)));
                if outcome.is_ok()
                    && let Some(owner) = retained_owner.upgrade()
                {
                    owner.jobs().failure.remove(&completed_identity);
                }
                let _ = publication.send(outcome);
            });
            jobs.callers.insert(task.id(), identity);
        }
        self.0.wake.wake();
        result
            .await
            .context("collaboration worker stopped without a conclusion")?
            .map_err(anyhow::Error::new)
    }

    pub(super) async fn join_root(&self, root: &str) -> Result<()> {
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            {
                let jobs = self.0.jobs();
                if let Some(error) = jobs
                    .background_failure
                    .iter()
                    .find(|(identity, _)| identity.caller == root)
                    .map(|(_, error)| error.clone())
                {
                    return Err(anyhow::Error::new(error));
                }
                if !jobs
                    .callers
                    .values()
                    .any(|identity| identity.caller == root)
                {
                    if let Some(error) = jobs
                        .background_failure
                        .iter()
                        .find(|(identity, _)| identity.caller == root)
                        .map(|(_, error)| error.clone())
                    {
                        return Err(anyhow::Error::new(error));
                    }
                    return match jobs
                        .failure
                        .iter()
                        .find(|(identity, _)| identity.caller == root)
                        .map(|(_, error)| error.clone())
                    {
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
            loop {
                let changed = self.0.changed.notified();
                tokio::pin!(changed);
                changed.as_mut().enable();
                if let Some(error) = self.0.jobs().background_failure.values().next().cloned() {
                    // A blocked terminal still owns its JoinSet job and history references.
                    // Returning a close failure must not take/drop the completion driver.
                    return Err(anyhow::Error::new(error));
                }
                tokio::select! {
                        joined = &mut *task => {
                *driver = None;
                joined.context("collaboration completion driver failed")?;
                            break;
                        }
                        () = &mut changed => {},
                    }
            }
        }
        if let Some(error) = self.0.jobs().background_failure.values().next().cloned() {
            return Err(anyhow::Error::new(error));
        }
        match self.0.jobs().failure.values().next().cloned() {
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
                    if let Some(identity) = jobs.callers.get(&id).cloned() {
                        jobs.failure.insert(identity, Arc::new(error));
                    }
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
