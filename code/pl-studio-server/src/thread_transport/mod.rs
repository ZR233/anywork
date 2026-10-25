//! Concrete Thread HTTP handles. Canonical projections, reliable FIFOs and read budgets stay native.
mod authoring_body;
mod authoring_read_routes;
mod authoring_routes;
mod body;
mod read_routes;
mod routes;
mod types;

use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_protocol::studio::{
    CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, FeedCloseReport, StudioError,
    StudioErrorCode, StudioShutdownIssue,
};
use pl_protocol::thread_facets::authoring::PlanDocumentRef;
use pl_protocol::thread_facets::identity::*;
use pl_studio_runtime::StudioRuntime;
use pl_studio_runtime::thread_authoring::StudioThreadAuthoring;
use pl_studio_runtime::thread_authoring_read::{
    StudioPlanDocumentRead, StudioTodoRead, StudioWorkflowRead,
};
use pl_studio_runtime::thread_execution::StudioThreadExecution;
use pl_studio_runtime::thread_execution_read::{
    StudioActivityRead, StudioInteractionIndexRead, StudioInteractionRead, StudioStorageRead,
    StudioTurnRead,
};
use std::future::Future;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokio::sync::{Notify, OwnedSemaphorePermit, oneshot};
use tokio_util::sync::CancellationToken;

pub(crate) use authoring_routes::authoring_router;
pub(crate) use routes::{open_created_execution, router};
type Completion = Shared<BoxFuture<'static, Result<(), Arc<tokio::task::JoinError>>>>;

#[derive(Clone)]
enum Native {
    Execution(Arc<StudioThreadExecution>),
    Turn(Arc<StudioTurnRead>),
    Index(Arc<StudioInteractionIndexRead>),
    Interaction(Arc<StudioInteractionRead>),
    Activity(Arc<StudioActivityRead>),
    Storage(Arc<StudioStorageRead>),
    Authoring(Arc<StudioThreadAuthoring>),
    Todo(Arc<StudioTodoRead>),
    Workflow(Arc<StudioWorkflowRead>),
    PlanDocument(Arc<StudioPlanDocumentRead>),
}
impl Native {
    fn identity(&self) -> Identity {
        match self {
            Self::Execution(value) => Identity::Feed(value.identity()),
            Self::Turn(value) => Identity::Read(value.identity()),
            Self::Index(value) => Identity::Read(value.identity()),
            Self::Interaction(value) => Identity::Read(value.identity()),
            Self::Activity(value) => Identity::Read(value.identity()),
            Self::Storage(value) => Identity::Read(value.identity()),
            Self::Authoring(value) => Identity::Feed(value.identity()),
            Self::Todo(value) => Identity::Read(value.identity()),
            Self::Workflow(value) => Identity::Read(value.identity()),
            Self::PlanDocument(value) => Identity::Read(value.identity()),
        }
    }
    fn request_close(&self) {
        match self {
            Self::Execution(value) => value.request_close(),
            Self::Turn(value) => value.request_close(),
            Self::Index(value) => value.request_close(),
            Self::Interaction(value) => value.request_close(),
            Self::Activity(value) => value.request_close(),
            Self::Storage(value) => value.request_close(),
            Self::Authoring(value) => value.request_close(),
            Self::Todo(value) => value.request_close(),
            Self::Workflow(value) => value.request_close(),
            Self::PlanDocument(value) => value.request_close(),
        }
    }
    async fn close(&self) -> FeedCloseReport {
        match self {
            Self::Execution(value) => value.close().await,
            Self::Turn(value) => value.close().await,
            Self::Index(value) => value.close().await,
            Self::Interaction(value) => value.close().await,
            Self::Activity(value) => value.close().await,
            Self::Storage(value) => value.close().await,
            Self::Authoring(value) => value.close().await,
            Self::Todo(value) => value.close().await,
            Self::Workflow(value) => value.close().await,
            Self::PlanDocument(value) => value.close().await,
        }
    }
}

#[derive(Clone)]
enum Identity {
    Feed(ThreadFeedIdentity),
    Read(ReadScopeIdentity),
}
impl Identity {
    fn id(&self) -> &str {
        match self {
            Self::Feed(value) => &value.feed_id,
            Self::Read(value) => &value.scope_id,
        }
    }
}

// Retain this independently of the payload, including after Clean, so another domain's control
// URL cannot close this original owner merely because both identities have the same wire shape.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Domain {
    Execution,
    Authoring,
}

enum Open {
    Execution {
        thread_id: String,
        mode: ThreadObservationMode,
    },
    CreatedExecution(pl_studio_runtime::draft_commands::StudioCreatedInputExecutionSource),
    Turn {
        thread_id: String,
        reference: TurnReadRef,
        origin: ThreadFacetStamp,
    },
    Index {
        thread_id: String,
        reference: InteractionIndexRef,
        origin: ThreadFacetStamp,
    },
    Interaction {
        thread_id: String,
        reference: InteractionReadRef,
        origin: ThreadFacetStamp,
    },
    Activity {
        thread_id: String,
        reference: ActivityReadRef,
        origin: ThreadFacetStamp,
    },
    Storage {
        thread_id: String,
        reference: StorageReadRef,
        origin: ThreadFacetStamp,
    },
    Authoring {
        thread_id: String,
        mode: ThreadObservationMode,
    },
    Todo {
        thread_id: String,
        reference: TodoReadRef,
        origin: ThreadFacetStamp,
    },
    Workflow {
        thread_id: String,
        reference: WorkflowReadRef,
        origin: ThreadFacetStamp,
    },
    PlanDocument {
        thread_id: String,
        reference: PlanDocumentRef,
        origin: ThreadFacetStamp,
    },
}
impl Open {
    fn domain(&self) -> Domain {
        match self {
            Self::Authoring { .. }
            | Self::Todo { .. }
            | Self::Workflow { .. }
            | Self::PlanDocument { .. } => Domain::Authoring,
            Self::Execution { .. }
            | Self::CreatedExecution(_)
            | Self::Turn { .. }
            | Self::Index { .. }
            | Self::Interaction { .. }
            | Self::Activity { .. }
            | Self::Storage { .. } => Domain::Execution,
        }
    }
    async fn run(self, runtime: StudioRuntime) -> anyhow::Result<Native> {
        Ok(match self {
            Self::Execution { thread_id, mode } => Native::Execution(Arc::new(
                runtime.open_thread_execution(thread_id, mode).await?,
            )),
            Self::CreatedExecution(source) => {
                Native::Execution(Arc::new(source.open_execution().await?))
            }
            Self::Turn {
                thread_id,
                reference,
                origin,
            } => Native::Turn(Arc::new(
                runtime.open_turn_read(thread_id, reference, origin).await?,
            )),
            Self::Index {
                thread_id,
                reference,
                origin,
            } => Native::Index(Arc::new(
                runtime
                    .open_interaction_index_read(thread_id, reference, origin)
                    .await?,
            )),
            Self::Interaction {
                thread_id,
                reference,
                origin,
            } => Native::Interaction(Arc::new(
                runtime
                    .open_interaction_read(thread_id, reference, origin)
                    .await?,
            )),
            Self::Activity {
                thread_id,
                reference,
                origin,
            } => Native::Activity(Arc::new(
                runtime
                    .open_activity_read(thread_id, reference, origin)
                    .await?,
            )),
            Self::Storage {
                thread_id,
                reference,
                origin,
            } => Native::Storage(Arc::new(
                runtime
                    .open_storage_read(thread_id, reference, origin)
                    .await?,
            )),
            Self::Authoring { thread_id, mode } => Native::Authoring(Arc::new(
                runtime.open_thread_authoring(thread_id, mode).await?,
            )),
            Self::Todo {
                thread_id,
                reference,
                origin,
            } => Native::Todo(Arc::new(
                runtime.open_todo_read(thread_id, reference, origin).await?,
            )),
            Self::Workflow {
                thread_id,
                reference,
                origin,
            } => Native::Workflow(Arc::new(
                runtime
                    .open_workflow_read(thread_id, reference, origin)
                    .await?,
            )),
            Self::PlanDocument {
                thread_id,
                reference,
                origin,
            } => Native::PlanDocument(Arc::new(
                runtime
                    .open_plan_document_read(thread_id, reference, origin)
                    .await?,
            )),
        })
    }
}

#[derive(Default)]
pub(crate) struct ThreadTransports(Mutex<Registry>);
#[derive(Default)]
struct Registry {
    sealed: bool,
    owners: Vec<Arc<Owner>>,
}
enum BodyPhase {
    Unclaimed,
    Active,
    Ended,
}
struct State {
    closing: bool,
    domain: Domain,
    identity: Option<Identity>,
    source: Option<Native>,
    task: Option<Completion>,
    body: BodyPhase,
    issues: Vec<FeedCloseIssue>,
    join_issue: Option<FeedCloseIssue>,
    permit: Option<OwnedSemaphorePermit>,
}
struct Owner {
    cancel: CancellationToken,
    changed: Notify,
    state: Mutex<State>,
    cleanup: tokio::sync::Mutex<()>,
}
struct Opening {
    owner: Arc<Owner>,
    ready: Option<oneshot::Receiver<Result<Identity, StudioError>>>,
    adopted: bool,
}

impl ThreadTransports {
    pub(crate) fn reap(&self) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .owners
            .retain(|owner| !owner.clean());
    }
    fn open(
        &self,
        runtime: StudioRuntime,
        request: Open,
        permit: Option<OwnedSemaphorePermit>,
    ) -> Result<Opening, StudioError> {
        let mut registry = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if registry.sealed {
            return Err(cancelled());
        }
        let owner = Arc::new(Owner {
            cancel: CancellationToken::new(),
            changed: Notify::new(),
            cleanup: tokio::sync::Mutex::new(()),
            state: Mutex::new(State {
                closing: false,
                domain: request.domain(),
                identity: None,
                source: None,
                task: None,
                body: BodyPhase::Unclaimed,
                issues: Vec::new(),
                join_issue: None,
                permit,
            }),
        });
        registry.owners.push(owner.clone());
        let (published, ready) = oneshot::channel();
        let work = owner.clone();
        let task = tokio::spawn(async move {
            let native = match request.run(runtime).await {
                Ok(native) => native,
                Err(error) => {
                    work.request_close();
                    let _ = published.send(Err(pl_studio_runtime::studio_error_from_anyhow(error)));
                    return;
                }
            };
            let identity = native.identity();
            let result = {
                let mut state = work
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                state.identity = Some(identity.clone());
                state.source = Some(native);
                if state.closing {
                    Err(cancelled())
                } else {
                    Ok(identity)
                }
            };
            if result.is_err() {
                work.request_close();
            }
            if published.send(result).is_err() {
                work.request_close();
            }
            work.cancel.cancelled().await;
            work.body_ended().await;
            work.close_source().await;
        });
        owner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task = Some(async move { task.await.map_err(Arc::new) }.boxed().shared());
        Ok(Opening {
            owner,
            ready: Some(ready),
            adopted: false,
        })
    }
    fn get(&self, id: &str) -> Result<Arc<Owner>, StudioError> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .owners
            .iter()
            .find(|owner| {
                owner
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .identity
                    .as_ref()
                    .is_some_and(|identity| identity.id() == id)
            })
            .cloned()
            .ok_or_else(|| StudioError::not_found("Thread HTTP handle"))
    }
    fn get_feed(&self, id: &str) -> Result<Arc<Owner>, StudioError> {
        self.get_typed(id, Domain::Execution, true)
    }
    fn get_read(&self, id: &str) -> Result<Arc<Owner>, StudioError> {
        self.get_typed(id, Domain::Execution, false)
    }
    fn get_authoring_feed(&self, id: &str) -> Result<Arc<Owner>, StudioError> {
        self.get_typed(id, Domain::Authoring, true)
    }
    fn get_authoring_read(&self, id: &str) -> Result<Arc<Owner>, StudioError> {
        self.get_typed(id, Domain::Authoring, false)
    }
    fn get_typed(&self, id: &str, domain: Domain, feed: bool) -> Result<Arc<Owner>, StudioError> {
        let owner = self.get(id)?;
        // Native-issued identity survives payload cleanup, so controls stay typed while closing
        // and after Clean. Checking it must not itself request cancellation or join a task.
        let state = owner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let matches = state.domain == domain
            && matches!(
                (&state.identity, feed),
                (Some(Identity::Feed(_)), true) | (Some(Identity::Read(_)), false)
            );
        if !matches {
            return Err(wrong());
        }
        drop(state);
        Ok(owner)
    }
    pub(crate) fn seal(&self) {
        let mut registry = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        registry.sealed = true;
        for owner in &registry.owners {
            owner.request_close();
        }
    }
    pub(crate) async fn close_for_exit(&self, deadline: Instant) -> Vec<StudioShutdownIssue> {
        self.seal();
        let owners = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .owners
            .clone();
        let results = futures::future::join_all(owners.iter().map(|owner| async {
            match tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), owner.close())
                .await
            {
                Ok(issues) => issues,
                Err(_) => {
                    let mut issues = owner.issues();
                    issues.push(issue(
                        "pending",
                        "Thread HTTP opening/query/body has not joined",
                        CleanupRecovery::AwaitCompletion,
                    ));
                    issues
                }
            }
        }))
        .await;
        results
            .into_iter()
            .flatten()
            .map(|issue| issue.diagnostic)
            .collect()
    }
}

impl Opening {
    async fn ready(&mut self) -> Result<Identity, StudioError> {
        self.ready
            .take()
            .ok_or_else(StudioError::internal)?
            .await
            .map_err(|_| StudioError::internal())?
    }
    fn adopt(&mut self) -> Result<(), StudioError> {
        self.owner.native()?;
        self.adopted = true;
        Ok(())
    }
}
impl Drop for Opening {
    fn drop(&mut self) {
        if !self.adopted {
            self.owner.request_close();
        }
    }
}

impl Owner {
    fn native(&self) -> Result<Native, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing {
            return Err(cancelled());
        }
        state.source.clone().ok_or_else(cancelled)
    }
    fn request_close(&self) {
        let source = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.closing = true;
            state.source.clone()
        };
        if let Some(source) = source {
            source.request_close();
        }
        self.cancel.cancel();
        self.changed.notify_waiters();
    }
    async fn close_source(&self) {
        let _cleanup = self.cleanup.lock().await;
        let source = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .source
            .clone();
        if let Some(source) = source {
            let report = source.close().await;
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            match report.outcome {
                FeedCloseOutcome::Clean => {
                    state.source.take();
                    state.issues.clear();
                }
                FeedCloseOutcome::Unresolved { issues } => state.issues = issues,
            }
        }
    }
    async fn body_ended(&self) {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if !matches!(
                self.state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .body,
                BodyPhase::Active
            ) {
                return;
            }
            changed.await;
        }
    }
    async fn close(&self) -> Vec<FeedCloseIssue> {
        self.request_close();
        let task = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task
            .clone();
        if let Some(task) = task
            && task.await.is_err()
        {
            self.state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .join_issue
                .get_or_insert_with(|| {
                    issue(
                        "joinError",
                        "A Thread HTTP owner did not join successfully",
                        CleanupRecovery::Terminal,
                    )
                });
        }
        self.body_ended().await;
        self.close_source().await;
        if self.issues().is_empty() {
            self.state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .permit
                .take();
        }
        self.issues()
    }
    async fn close_report(&self, id: String) -> FeedCloseReport {
        let issues = self.close().await;
        FeedCloseReport {
            feed_id: id,
            outcome: if issues.is_empty() {
                FeedCloseOutcome::Clean
            } else {
                FeedCloseOutcome::Unresolved { issues }
            },
        }
    }
    fn issues(&self) -> Vec<FeedCloseIssue> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut issues = state.issues.clone();
        issues.extend(state.join_issue.iter().cloned());
        issues
    }
    fn clean(&self) -> bool {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.closing
            && state.source.is_none()
            && !matches!(state.body, BodyPhase::Active)
            && state.issues.is_empty()
            && state.join_issue.is_none()
            && state
                .task
                .as_ref()
                .is_some_and(|task| matches!(task.clone().now_or_never(), Some(Ok(()))))
    }
}
fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "The original Thread HTTP handle is closing",
        false,
    )
}
fn wrong() -> StudioError {
    StudioError::invalid_argument("This Thread read scope has a different typed capability")
}
fn issue(code: &str, message: &str, recovery: CleanupRecovery) -> FeedCloseIssue {
    FeedCloseIssue {
        diagnostic: StudioShutdownIssue {
            stage: "threadHttp".into(),
            code: code.into(),
            message: message.into(),
            retryable: recovery != CleanupRecovery::Terminal,
            correlation_id: StudioError::internal().correlation_id,
        },
        recovery,
    }
}
