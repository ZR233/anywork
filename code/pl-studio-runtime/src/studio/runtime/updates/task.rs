//! Opening allocates only a capability. Start installs exactly one supervised operation.
use super::super::read_scopes::{
    PinnedMaterial, ProductScopeBinding, ReadScopeBudgetKey, ReadScopeOwner,
};
use super::super::{
    StudioRuntime, StudioUpdateRuntime, StudioUpdateStateSnapshot, background_task::BackgroundTask,
    read_calls::ReadCalls,
};
use super::source::{UpdatesMaterial, UpdatesSource, cancelled};
use anyhow::{Context, Result};
use pl_protocol::products::read::updates::{UpdateTaskCloseReport, UpdateTaskIdentity};
use pl_protocol::products::references::UpdatesReadTarget;
use pl_protocol::studio::{
    CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, StudioError, StudioErrorCode,
    StudioShutdownIssue,
};
use std::collections::BTreeMap;
use std::future::Future;
use std::sync::{Arc, Mutex, Weak};

#[derive(Clone)]
enum Intent {
    Check,
    Automatic,
    Prepare {
        expected_revision: u64,
        version: String,
    },
}
struct Phase {
    closing: bool,
    started: bool,
    worker: Option<Arc<BackgroundTask>>,
    shared: Option<Arc<TaskOwner>>,
}
struct TaskOwner {
    identity: UpdateTaskIdentity,
    origin: pl_protocol::products::identity::ProductReadOrigin,
    intent: Intent,
    updater: StudioUpdateRuntime,
    source: Weak<UpdatesSource>,
    cancellation: crate::StudioUpdateCancellation,
    phase: Mutex<Phase>,
    queries: Arc<ReadScopeOwner>,
    _permit: Arc<PinnedMaterial<()>>,
    changed: tokio::sync::Notify,
    terminal: Mutex<Vec<FeedCloseIssue>>,
    result:
        tokio::sync::watch::Sender<Option<std::result::Result<Arc<UpdatesMaterial>, StudioError>>>,
}
#[derive(Default)]
struct TasksState {
    sealed: bool,
    owners: BTreeMap<String, Arc<TaskOwner>>,
    automatic: Option<Arc<TaskOwner>>,
}
#[derive(Default)]
pub(super) struct UpdateTasks(Mutex<TasksState>);
pub struct StudioUpdateTask {
    owner: Arc<TaskOwner>,
    calls: ReadCalls,
}

impl StudioRuntime {
    pub fn open_update_check(
        &self,
        operation_id: String,
    ) -> impl Future<Output = Result<StudioUpdateTask>> + Send + 'static + use<> {
        self.open_update_task(operation_id, Intent::Check)
    }
    pub fn open_automatic_update(
        &self,
        operation_id: String,
    ) -> impl Future<Output = Result<StudioUpdateTask>> + Send + 'static + use<> {
        self.open_update_task(operation_id, Intent::Automatic)
    }
    pub fn open_update_preparation(
        &self,
        operation_id: String,
        expected_revision: u64,
        version: String,
    ) -> impl Future<Output = Result<StudioUpdateTask>> + Send + 'static + use<> {
        self.open_update_task(
            operation_id,
            Intent::Prepare {
                expected_revision,
                version,
            },
        )
    }
    fn open_update_task(
        &self,
        operation_id: String,
        intent: Intent,
    ) -> impl Future<Output = Result<StudioUpdateTask>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            Self::validate_operation_id(&operation_id)?;
            runtime.updates_source.ensure_open()?;
            if let Intent::Prepare { version, .. } = &intent {
                super::super::read_budget::require_budget(version)?;
            }
            let (result, _) = tokio::sync::watch::channel(None);
            let task_id = crate::studio::new_id("update-task");
            let group = runtime.read_scopes.group(
                ReadScopeBudgetKey::Product {
                    resource: pl_protocol::products::identity::ProductResource::Updates,
                    scope: ProductScopeBinding::Named("updates.task"),
                },
                runtime.updates_source.origin().incarnation,
            );
            let (queries, permit) = group.open(task_id.clone(), ())?;
            let owner = Arc::new(TaskOwner {
                identity: UpdateTaskIdentity {
                    runtime_epoch: runtime.owner_epoch.clone(),
                    task_id,
                    operation_id,
                },
                origin: runtime.updates_source.origin().clone(),
                intent,
                updater: runtime.updater.clone(),
                source: Arc::downgrade(&runtime.updates_source),
                cancellation: crate::StudioUpdateCancellation::new(),
                phase: Mutex::new(Phase {
                    closing: false,
                    started: false,
                    worker: None,
                    shared: None,
                }),
                queries,
                _permit: permit,
                changed: tokio::sync::Notify::new(),
                terminal: Mutex::new(Vec::new()),
                result,
            });
            if let Err(error) = runtime.updates_source.tasks.register(owner.clone()) {
                owner.request_close();
                owner.queries.release_if_joined();
                return Err(error.into());
            }
            Ok(StudioUpdateTask {
                owner,
                calls: runtime.read_calls.clone(),
            })
        })
    }
}
impl UpdateTasks {
    fn register(&self, owner: Arc<TaskOwner>) -> Result<(), StudioError> {
        let mut state = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(cancelled());
        }
        if state.owners.len() >= 8 {
            return Err(StudioError::new(
                StudioErrorCode::Overloaded,
                "Update task capacity is exhausted",
                true,
            ));
        }
        if state
            .owners
            .values()
            .any(|existing| existing.identity.operation_id == owner.identity.operation_id)
        {
            return Err(StudioError::new(
                StudioErrorCode::Conflict,
                "This update operation ID already owns a task",
                false,
            ));
        }
        state.owners.insert(owner.identity.task_id.clone(), owner);
        Ok(())
    }
    fn start(&self, owner: &Arc<TaskOwner>) -> Result<(), StudioError> {
        let mut state = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed
            || !state
                .owners
                .get(&owner.identity.task_id)
                .is_some_and(|registered| Arc::ptr_eq(registered, owner))
        {
            return Err(cancelled());
        }
        let mut phase = owner
            .phase
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if phase.closing {
            return Err(cancelled());
        }
        if phase.started {
            return Err(StudioError::new(
                StudioErrorCode::Conflict,
                "Update task was already started; start never replays work",
                false,
            ));
        }
        if let Some(automatic) = &state.automatic {
            let automatic_worker = automatic
                .phase
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .worker
                .clone()
                .ok_or_else(StudioError::internal)?;
            let share = match &owner.intent {
                Intent::Automatic => true,
                Intent::Prepare {
                    expected_revision,
                    version,
                } if !automatic_worker.is_finished() => {
                    let source = owner.source.upgrade().ok_or_else(cancelled)?;
                    let (current, _) = source.observe()?;
                    current.value.revision() >= *expected_revision
                        && current
                            .value
                            .update()
                            .is_some_and(|update| &update.version == version)
                }
                _ => false,
            };
            if share {
                phase.started = true;
                phase.worker = Some(automatic_worker);
                phase.shared = Some(automatic.clone());
                drop(phase);
                owner.changed.notify_waiters();
                return Ok(());
            }
        }
        phase.started = true;
        let worker = owner.clone();
        phase.worker = Some(BackgroundTask::new(tokio::spawn(async move {
            let result = worker.execute().await;
            if let Err(error) = &result
                && (error.is::<super::super::updater::UpdateProjectionFailure>()
                    || error.is::<tokio::task::JoinError>()
                    || error.downcast_ref::<StudioError>().is_some_and(|error| {
                        matches!(
                            error.code,
                            StudioErrorCode::Internal | StudioErrorCode::Protocol
                        ) || error.code == StudioErrorCode::Overloaded && !error.retryable
                    }))
            {
                worker
                    .terminal
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .push(FeedCloseIssue {
                        diagnostic: StudioShutdownIssue {
                            stage: "updateTask".into(),
                            code: "ownerFailed".into(),
                            message: format!("{error:#}"),
                            retryable: false,
                            correlation_id: worker.identity.task_id.clone(),
                        },
                        recovery: CleanupRecovery::Terminal,
                    });
            }
            let result = result.map_err(crate::studio_error_from_anyhow);
            worker.result.send_replace(Some(result));
        })));
        // The process-once marker changes only at actual start, never during a named open.
        if matches!(owner.intent, Intent::Automatic) {
            state.automatic = Some(owner.clone());
        }
        drop(phase);
        owner.changed.notify_waiters();
        Ok(())
    }
    fn unregister(&self, owner: &TaskOwner) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .owners
            .remove(&owner.identity.task_id);
    }
    pub(super) fn seal(&self) {
        let owners = {
            let mut state = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.sealed = true;
            let mut owners = state.owners.values().cloned().collect::<Vec<_>>();
            if let Some(automatic) = &state.automatic
                && !owners.iter().any(|owner| Arc::ptr_eq(owner, automatic))
            {
                owners.push(automatic.clone());
            }
            owners
        };
        for owner in owners {
            owner.request_close();
        }
    }
    pub(super) async fn close(&self) -> Vec<FeedCloseIssue> {
        self.seal();
        let owners = {
            let state = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let mut owners = state.owners.values().cloned().collect::<Vec<_>>();
            if let Some(automatic) = &state.automatic
                && !owners.iter().any(|owner| Arc::ptr_eq(owner, automatic))
            {
                owners.push(automatic.clone());
            }
            owners
        };
        let mut issues = Vec::new();
        for owner in owners {
            let owner_issues = owner.join().await;
            if owner_issues.is_empty() {
                self.unregister(&owner);
            }
            issues.extend(owner_issues);
        }
        if issues.is_empty() {
            self.0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .automatic
                .take();
        }
        issues
    }
}
impl TaskOwner {
    fn request_cancel(&self) {
        let shared = {
            let mut phase = self
                .phase
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            phase.closing = true;
            phase.shared.clone()
        };
        self.cancellation.cancel();
        self.changed.notify_waiters();
        if let Some(shared) = shared {
            shared.cancellation.cancel();
        }
    }
    fn request_close(&self) {
        self.request_cancel();
        self.queries.request_close();
    }
    async fn execute(&self) -> Result<Arc<UpdatesMaterial>> {
        let captured = match &self.intent {
            Intent::Check => {
                self.updater
                    .check_cancellable(&self.cancellation, self.identity.operation_id.clone())
                    .await?
            }
            Intent::Automatic => {
                let checked = self
                    .updater
                    .check_cancellable(&self.cancellation, self.identity.operation_id.clone())
                    .await?;
                if let StudioUpdateStateSnapshot::Available(value) = &checked.value {
                    // Preparation returns the snapshot captured under its original command gate.
                    self.updater
                        .prepare(value.update().clone(), self.cancellation.clone(), None)
                        .await?
                } else {
                    checked
                }
            }
            Intent::Prepare {
                expected_revision,
                version,
            } => {
                let update = self
                    .updater
                    .verified_update(*expected_revision, version)
                    .await?;
                self.updater
                    .prepare(update, self.cancellation.clone(), None)
                    .await?
            }
        };
        Ok(captured)
    }
    async fn join(&self) -> Vec<FeedCloseIssue> {
        self.request_close();
        let worker = self
            .phase
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .worker
            .clone();
        let mut issues = match worker {
            Some(worker) => match worker.join().await {
                Ok(()) => Vec::new(),
                Err(error) => vec![FeedCloseIssue {
                    diagnostic: StudioShutdownIssue {
                        stage: "updateTask".into(),
                        code: "joinFailed".into(),
                        message: format!("{error:?}"),
                        retryable: false,
                        correlation_id: self.identity.task_id.clone(),
                    },
                    recovery: CleanupRecovery::Terminal,
                }],
            },
            None => Vec::new(),
        };
        let shared = self
            .phase
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .shared
            .clone();
        let completion = shared.as_deref().unwrap_or(self);
        issues.extend(
            completion
                .terminal
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .iter()
                .cloned(),
        );
        if self
            .phase
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .started
            && completion.result.borrow().is_none()
            && issues.is_empty()
        {
            issues.push(FeedCloseIssue {
                diagnostic: StudioShutdownIssue {
                    stage: "updateTask".into(),
                    code: "missingCompletion".into(),
                    message: "The joined update owner did not retain its completion".into(),
                    retryable: false,
                    correlation_id: self.identity.task_id.clone(),
                },
                recovery: CleanupRecovery::Terminal,
            });
        }
        if let FeedCloseOutcome::Unresolved {
            issues: query_issues,
        } = self.queries.close().await.outcome
        {
            issues.extend(query_issues);
        }
        issues
    }
}
impl StudioUpdateTask {
    pub fn identity(&self) -> UpdateTaskIdentity {
        self.owner.identity.clone()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        if self
            .owner
            .phase
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .closing
        {
            Err(cancelled())
        } else {
            Ok(())
        }
    }
    pub fn start(&self) -> Result<(), StudioError> {
        let source = self.owner.source.upgrade().ok_or_else(cancelled)?;
        source.tasks.start(&self.owner)
    }
    pub fn finish(
        &self,
    ) -> impl Future<Output = Result<UpdatesReadTarget>> + Send + 'static + use<> {
        let owner = self.owner.clone();
        self.owner.queries.run_committed(&self.calls, async move {
            let (worker, completion) = loop {
                let changed = owner.changed.notified();
                tokio::pin!(changed);
                changed.as_mut().enable();
                let (worker, completion) = {
                    let phase = owner
                        .phase
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    if !phase.started && phase.closing {
                        return Err(cancelled().into());
                    }
                    (
                        phase.worker.clone(),
                        phase.shared.clone().unwrap_or_else(|| owner.clone()),
                    )
                };
                if let Some(worker) = worker {
                    break (worker, completion);
                }
                changed.await;
            };
            // BackgroundTask owns a re-awaitable completion of the actual JoinHandle. Cancelling
            // this finish waiter does not remove the registry entry or abandon the task.
            worker
                .join()
                .await
                .context("Update task worker did not join")?;
            let result = completion
                .result
                .borrow()
                .clone()
                .ok_or_else(StudioError::internal)?;
            let material = result?;
            let target = UpdatesReadTarget {
                origin: owner.origin.clone(),
                reference: material.reference,
            };
            super::super::read_budget::require_budget(&target)?;
            Ok(target)
        })
    }
    pub fn request_cancel(&self) {
        self.owner.request_cancel();
    }
    pub fn request_close(&self) {
        self.owner.request_close();
    }
    pub async fn close(&self) -> UpdateTaskCloseReport {
        let issues = self.owner.join().await;
        if issues.is_empty()
            && let Some(source) = self.owner.source.upgrade()
        {
            source.tasks.unregister(&self.owner);
        }
        UpdateTaskCloseReport {
            identity: self.identity(),
            outcome: if issues.is_empty() {
                FeedCloseOutcome::Clean
            } else {
                FeedCloseOutcome::Unresolved { issues }
            },
        }
    }
    pub async fn retry_close(&self) -> UpdateTaskCloseReport {
        self.close().await
    }
}
impl Drop for StudioUpdateTask {
    fn drop(&mut self) {
        self.request_close();
        let never_started = self
            .owner
            .phase
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .worker
            .is_none();
        self.owner.queries.release_if_joined();
        if never_started && let Some(source) = self.owner.source.upgrade() {
            source.tasks.unregister(&self.owner);
        }
    }
}
