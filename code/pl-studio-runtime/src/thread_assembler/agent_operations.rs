//! Retained collaboration jobs. Tokio owns scheduling and joins; the driver only drains JoinSet.
use super::{StudioThreadAssembler, agent_services::ServiceError};
use anyhow::{Context, Result, ensure};
use futures::FutureExt;
use futures::future::{BoxFuture, Shared as SharedCompletion};
use futures::task::AtomicWaker;
use std::{
    collections::BTreeMap,
    future::{Future, poll_fn},
    sync::{Arc, Mutex, MutexGuard, Weak},
    task::Poll,
};
use tokio::{
    sync::{Notify, oneshot, watch},
    task::{AbortHandle, Id, JoinError, JoinSet},
};

mod failure;
pub(crate) use failure::{
    AgentOperationJoinIssue, AgentOperationPending, AgentOperationsJoinFailure,
};

#[derive(Debug)]
struct JobFailure {
    issue: AgentOperationJoinIssue,
    admission_delivered: bool,
}

#[derive(Debug, Clone, Copy)]
enum JoinFailureKey {
    Job(Id),
    Driver,
}

type JoinProgress = SharedCompletion<BoxFuture<'static, (bool, Vec<Arc<JoinError>>)>>;

#[derive(Debug, Default)]
struct Jobs {
    closing: bool,
    tasks: JoinSet<()>,
    callers: BTreeMap<Id, String>,
    failures: BTreeMap<Id, JobFailure>,
    // One index per actual unresolved failure, not an attempt history.
    failure_order: Vec<JoinFailureKey>,
    driver: Option<Arc<Driver>>,
    driver_failure: Option<Arc<JoinError>>,
    // One pending poll of the original JoinSet. Shared retains its waker across cancelled or
    // concurrent close waiters; no waiter can replace another waiter's sole JoinSet wake source.
    remaining_join: Option<JoinProgress>,
}

#[derive(Debug, Default)]
struct Shared {
    jobs: Mutex<Jobs>,
    // Admission and closing serialize here; business admission is never called under Jobs.
    admission: tokio::sync::Mutex<()>,
    wake: AtomicWaker,
    changed: Notify,
}

struct Driver {
    abort: AbortHandle,
    completion: SharedCompletion<BoxFuture<'static, Result<(), Arc<JoinError>>>>,
}

impl std::fmt::Debug for Driver {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.debug_struct("Driver").finish_non_exhaustive()
    }
}

impl Driver {
    fn start(owner: Weak<Shared>) -> Arc<Self> {
        let task = tokio::spawn(drive(owner));
        let abort = task.abort_handle();
        Arc::new(Self {
            abort,
            completion: async move { task.await.map_err(Arc::new) }.boxed().shared(),
        })
    }

    async fn join(&self) -> Result<(), Arc<JoinError>> {
        self.completion.clone().await
    }
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
        let jobs = self
            .jobs
            .get_mut()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(driver) = &jobs.driver {
            driver.abort.abort();
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
        let admission = self.0.admission.lock().await;
        let previous = {
            let mut jobs = self.0.jobs();
            ensure!(!jobs.closing, "collaboration operation owner is closing");
            let pending = jobs.failure_order.iter().find_map(|key| match key {
                JoinFailureKey::Job(id) => jobs
                    .failures
                    .get(id)
                    .filter(|failure| !failure.admission_delivered)
                    .map(|_| *id),
                JoinFailureKey::Driver => None,
            });
            pending
                .and_then(|id| jobs.failures.get_mut(&id))
                .map(|failure| {
                    failure.admission_delivered = true;
                    failure.issue.clone()
                })
        };
        if let Some(issue) = previous {
            // Preserve the old one-time admission delivery without deleting close's evidence.
            return Err(anyhow::Error::new(AgentOperationsJoinFailure {
                cause: issue.error.clone(),
                jobs: vec![issue],
                driver: None,
                driver_id: None,
                pending: Vec::new(),
            }));
        }
        admit()?;
        let (publication, mut result) = watch::channel(None);
        let (start, admitted) = oneshot::channel();
        {
            let mut jobs = self.0.jobs();
            if jobs.driver.is_none() {
                // Retain the completion driver before admitting its first worker. It never owns
                // the registry strongly and never takes a lifecycle or per-agent operation gate.
                jobs.driver = Some(Driver::start(Arc::downgrade(&self.0)));
            }
            let task = jobs.tasks.spawn(async move {
                let outcome = async {
                    admitted.await?;
                    operation.await
                }
                .await
                .map_err(|error| Arc::new(ServiceError(error)));
                publication.send_replace(Some(outcome));
            });
            jobs.callers.insert(task.id(), caller);
        }
        drop(admission);
        // No Jobs/admission guard spans business execution or result/wake callbacks.
        let _ = start.send(());
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

    /// The caller must seal this root first. Admissions that passed the seal check before it
    /// must finish registering their jobs before the first inspection of the original Jobs.
    pub(super) async fn join_root(&self, root: &str) -> Result<(), AgentOperationsJoinFailure> {
        drop(self.0.admission.lock().await);
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let driver = self.0.jobs().driver.clone();
            if let Some(result) = driver
                .as_ref()
                .and_then(|driver| driver.join().now_or_never())
            {
                self.record_driver(result);
                // The original driver ended: only join the same remaining JoinSet, never restart it.
                self.drain_remaining(Some(root)).await;
                return self.join_result(Some(root));
            }
            if !self.0.jobs().callers.values().any(|caller| caller == root) {
                return self.join_result(Some(root));
            }
            match driver {
                Some(driver) => tokio::select! {
                    result = driver.join() => { self.record_driver(result); }
                    () = &mut changed => {}
                },
                None => {
                    self.drain_remaining(Some(root)).await;
                    return self.join_result(Some(root));
                }
            }
        }
    }

    /// No abort: a cancelled shutdown waiter leaves the driver handle in its owner slot.
    pub(super) async fn close(&self) -> Result<(), AgentOperationsJoinFailure> {
        let driver = {
            let _admission = self.0.admission.lock().await;
            let mut jobs = self.0.jobs();
            jobs.closing = true;
            jobs.driver.clone()
        };
        self.0.wake.wake();
        if let Some(driver) = driver {
            self.record_driver(driver.join().await);
        }
        self.drain_remaining(None).await;
        self.join_result(None)
    }

    fn record_driver(&self, result: Result<(), Arc<JoinError>>) {
        if let Err(error) = result {
            let changed = {
                let mut jobs = self.0.jobs();
                if jobs.driver_failure.is_none() {
                    jobs.driver_failure = Some(error);
                    jobs.failure_order.push(JoinFailureKey::Driver);
                    true
                } else {
                    false
                }
            };
            if changed {
                self.0.changed.notify_waiters();
            }
        }
    }

    async fn drain_remaining(&self, root: Option<&str>) {
        loop {
            let next = {
                let mut jobs = self.0.jobs();
                let done = match root {
                    Some(root) => !jobs.callers.values().any(|caller| root == caller.as_str()),
                    None => jobs.tasks.is_empty(),
                };
                if done {
                    return;
                }
                if jobs
                    .remaining_join
                    .as_ref()
                    .is_none_or(|join| join.peek().is_some())
                {
                    jobs.remaining_join = Some(join_remaining(Arc::downgrade(&self.0)));
                }
                jobs.remaining_join
                    .as_ref()
                    .expect("original remaining join installed")
                    .clone()
            };
            let (joined, errors) = next.await;
            publish_joins(&self.0, joined, errors);
        }
    }

    fn join_result(&self, root: Option<&str>) -> Result<(), AgentOperationsJoinFailure> {
        let jobs = self.0.jobs();
        let in_scope = |failure: &JobFailure| {
            root.is_none_or(|root| {
                failure
                    .issue
                    .caller
                    .as_deref()
                    .is_none_or(|caller| root == caller)
            })
        };
        let failures = jobs
            .failure_order
            .iter()
            .filter_map(|key| match key {
                JoinFailureKey::Job(id) => jobs
                    .failures
                    .get(id)
                    .filter(|failure| in_scope(failure))
                    .map(|failure| failure.issue.clone()),
                JoinFailureKey::Driver => None,
            })
            .collect::<Vec<_>>();
        let cause = jobs.failure_order.iter().find_map(|key| match key {
            JoinFailureKey::Job(id) => jobs
                .failures
                .get(id)
                .filter(|failure| in_scope(failure))
                .map(|failure| failure.issue.error.clone()),
            JoinFailureKey::Driver => jobs.driver_failure.clone(),
        });
        match cause {
            Some(cause) => Err(AgentOperationsJoinFailure {
                jobs: failures,
                driver: jobs.driver_failure.clone(),
                driver_id: jobs.driver_failure.as_ref().map(|error| error.id()),
                pending: jobs
                    .callers
                    .iter()
                    .filter(|(_, caller)| root.is_none_or(|root| root == caller.as_str()))
                    .map(|(task_id, caller)| AgentOperationPending {
                        task_id: *task_id,
                        caller: caller.clone(),
                    })
                    .collect(),
                cause,
            }),
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
        let (done, joined, errors) = {
            let mut jobs = owner.jobs();
            let (joined, errors) = join_ready(&mut jobs, context);
            (jobs.closing && jobs.tasks.is_empty(), joined, errors)
        };
        publish_joins(&owner, joined, errors);
        if done { Poll::Ready(()) } else { Poll::Pending }
    })
    .await;
}

fn join_remaining(owner: Weak<Shared>) -> JoinProgress {
    poll_fn(move |context| {
        let Some(owner) = owner.upgrade() else {
            return Poll::Ready((false, Vec::new()));
        };
        let (empty, joined, errors) = {
            let mut jobs = owner.jobs();
            let (joined, errors) = join_ready(&mut jobs, context);
            (jobs.tasks.is_empty(), joined, errors)
        };
        if empty || joined {
            Poll::Ready((joined, errors))
        } else {
            Poll::Pending
        }
    })
    .boxed()
    .shared()
}

fn join_ready(
    jobs: &mut Jobs,
    context: &mut std::task::Context<'_>,
) -> (bool, Vec<Arc<JoinError>>) {
    let mut changed = false;
    let mut errors = Vec::new();
    while let Poll::Ready(Some(joined)) = jobs.tasks.poll_join_next_with_id(context) {
        changed = true;
        match joined {
            Ok((id, ())) => {
                jobs.callers.remove(&id);
            }
            Err(error) => {
                let id = error.id();
                let caller = jobs.callers.remove(&id);
                let error = Arc::new(error);
                if let std::collections::btree_map::Entry::Vacant(entry) = jobs.failures.entry(id) {
                    entry.insert(JobFailure {
                        issue: AgentOperationJoinIssue {
                            task_id: id,
                            caller,
                            error: error.clone(),
                        },
                        admission_delivered: false,
                    });
                    jobs.failure_order.push(JoinFailureKey::Job(id));
                }
                errors.push(error);
            }
        }
    }
    (changed, errors)
}

fn publish_joins(owner: &Shared, changed: bool, errors: Vec<Arc<JoinError>>) {
    // Both diagnostics and wake callbacks run after the Jobs guard has been released.
    if changed {
        owner.changed.notify_waiters();
    }
    for error in errors {
        tracing::error!(%error, "collaboration operation task failed");
    }
}

impl StudioThreadAssembler {
    pub(super) async fn join_root_operations(
        &self,
        root: &str,
    ) -> Result<(), AgentOperationsJoinFailure> {
        let services = self.0.state().agent_services.clone();
        if let Some(services) = services {
            services.operations.join_root(root).await?;
        }
        Ok(())
    }

    pub(super) async fn close_agent_operations(&self) -> Result<(), AgentOperationsJoinFailure> {
        let services = self.0.state().agent_services.clone();
        if let Some(services) = services {
            services.operations.close().await?;
        }
        Ok(())
    }
}
