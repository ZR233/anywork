//! Independent immutable-history and mutable-current HTTP read owners.

use std::{
    collections::HashMap,
    convert::Infallible,
    future::Future,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, AtomicUsize, Ordering},
    },
    time::Duration,
};

use axum::{
    Json,
    extract::{Path, State},
    http::HeaderMap,
    response::{
        IntoResponse,
        sse::{Event, KeepAlive, Sse},
    },
};
use futures::Stream;
use pl_studio_runtime::{
    ContentRange, CurrentCollectionPage, CurrentCollectionRef, CurrentContentRef, CurrentRevision,
    ReadDemand, StudioError, StudioErrorCode, StudioErrorReason,
    history::{
        HistoryAccountingHead, HistoryBodyPage, HistoryBodyWindow, HistoryCut, HistoryDemand,
        HistoryEventBodyRef, HistoryEventDetail, HistoryEventsPage, HistoryEventsQuery,
        HistoryGroupPage, HistoryTimelinePage,
    },
};
use pl_studio_runtime::{CurrentReader, CurrentWatch, history::HistoryReader};
use serde::{Deserialize, Serialize};
use tokio::{
    sync::{OwnedSemaphorePermit, Semaphore, mpsc},
    task::JoinSet,
};
use tokio_stream::wrappers::ReceiverStream;
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use utoipa::ToSchema;

use crate::{
    AppState,
    error::ApiError,
    routes::{ApiJson, StudioApiErrors},
};

pub(crate) const CONVERSATION_HEADER: &str = "x-anywork-conversation";
const IDLE_READER_TIMEOUT: Duration = Duration::from_secs(120);
const MAX_READS: usize = crate::MAX_REQUESTS + crate::MAX_STREAMS;
static NEXT_OWNER: AtomicU64 = AtomicU64::new(1);

#[derive(Default)]
pub(crate) struct Timelines {
    inner: Mutex<TimelineOwners>,
}

#[derive(Default)]
struct TimelineOwners {
    closed: bool,
    owners: HashMap<String, Arc<TimelineOwner>>,
    tasks: JoinSet<()>,
}

enum TimelineOwner {
    History {
        thread_id: String,
        reader: HistoryReader,
        permit: Mutex<Option<OwnedSemaphorePermit>>,
        activity: Mutex<tokio::time::Instant>,
        activity_changed: tokio::sync::Notify,
        reads: Arc<Semaphore>,
        active_reads: AtomicUsize,
        cancel: CancellationToken,
        admission: Mutex<()>,
        tasks: TaskTracker,
        close_gate: tokio::sync::Mutex<()>,
    },
    Current {
        thread_id: String,
        reader: CurrentReader,
        permit: Mutex<Option<OwnedSemaphorePermit>>,
        activity: Mutex<tokio::time::Instant>,
        activity_changed: tokio::sync::Notify,
        reads: Arc<Semaphore>,
        active_reads: AtomicUsize,
        cancel: CancellationToken,
        admission: Mutex<()>,
        tasks: TaskTracker,
        close_gate: tokio::sync::Mutex<()>,
    },
}

impl TimelineOwner {
    fn history(thread_id: String, reader: HistoryReader, permit: OwnedSemaphorePermit) -> Self {
        Self::History {
            thread_id,
            reader,
            permit: Mutex::new(Some(permit)),
            activity: Mutex::new(tokio::time::Instant::now()),
            activity_changed: tokio::sync::Notify::new(),
            reads: Arc::new(Semaphore::new(MAX_READS)),
            active_reads: AtomicUsize::new(0),
            cancel: CancellationToken::new(),
            admission: Mutex::new(()),
            tasks: TaskTracker::new(),
            close_gate: tokio::sync::Mutex::new(()),
        }
    }

    fn current(thread_id: String, reader: CurrentReader, permit: OwnedSemaphorePermit) -> Self {
        Self::Current {
            thread_id,
            reader,
            permit: Mutex::new(Some(permit)),
            activity: Mutex::new(tokio::time::Instant::now()),
            activity_changed: tokio::sync::Notify::new(),
            reads: Arc::new(Semaphore::new(MAX_READS)),
            active_reads: AtomicUsize::new(0),
            cancel: CancellationToken::new(),
            admission: Mutex::new(()),
            tasks: TaskTracker::new(),
            close_gate: tokio::sync::Mutex::new(()),
        }
    }

    fn thread_id(&self) -> &str {
        match self {
            Self::History { thread_id, .. } | Self::Current { thread_id, .. } => thread_id,
        }
    }

    fn history_reader(&self) -> Option<&HistoryReader> {
        match self {
            Self::History { reader, .. } => Some(reader),
            Self::Current { .. } => None,
        }
    }

    fn current_reader(&self) -> Option<&CurrentReader> {
        match self {
            Self::History { .. } => None,
            Self::Current { reader, .. } => Some(reader),
        }
    }

    fn cancel(&self) -> &CancellationToken {
        match self {
            Self::History { cancel, .. } | Self::Current { cancel, .. } => cancel,
        }
    }

    fn tasks(&self) -> &TaskTracker {
        match self {
            Self::History { tasks, .. } | Self::Current { tasks, .. } => tasks,
        }
    }

    fn spawn_task(&self, task: impl Future<Output = ()> + Send + 'static) -> Result<(), ApiError> {
        let (admission, cancel, tasks) = match self {
            Self::History {
                admission,
                cancel,
                tasks,
                ..
            }
            | Self::Current {
                admission,
                cancel,
                tasks,
                ..
            } => (admission, cancel, tasks),
        };
        let _gate = admission.lock().expect("timeline admission poisoned");
        if cancel.is_cancelled() || tasks.is_closed() {
            return Err(stale_scope());
        }
        tasks.spawn(task);
        Ok(())
    }

    fn touch(&self) {
        let (activity, changed) = match self {
            Self::History {
                activity,
                activity_changed,
                ..
            }
            | Self::Current {
                activity,
                activity_changed,
                ..
            } => (activity, activity_changed),
        };
        *activity.lock().expect("timeline activity poisoned") = tokio::time::Instant::now();
        changed.notify_one();
    }

    fn request_close(&self) {
        let (admission, cancel, tasks) = match self {
            Self::History {
                admission,
                cancel,
                tasks,
                ..
            }
            | Self::Current {
                admission,
                cancel,
                tasks,
                ..
            } => (admission, cancel, tasks),
        };
        let _gate = admission.lock().expect("timeline admission poisoned");
        cancel.cancel();
        match self {
            Self::History { reader, .. } => reader.request_close(),
            Self::Current { reader, .. } => reader.request_close(),
        }
        tasks.close();
    }

    async fn close(&self) -> Result<(), StudioError> {
        self.request_close();
        let _close = match self {
            Self::History { close_gate, .. } | Self::Current { close_gate, .. } => {
                close_gate.lock().await
            }
        };
        let result = match self {
            Self::History { reader, .. } => {
                reader.close().await;
                Ok(())
            }
            Self::Current { reader, .. } => reader
                .close()
                .await
                .map_err(pl_studio_runtime::studio_error_from_anyhow),
        };
        self.tasks().wait().await;
        result?;
        match self {
            Self::History { permit, .. } | Self::Current { permit, .. } => {
                permit.lock().expect("timeline permit poisoned").take();
            }
        }
        Ok(())
    }

    async fn wait_idle(&self, timeout: Duration) {
        loop {
            let notified = match self {
                Self::History {
                    activity_changed, ..
                }
                | Self::Current {
                    activity_changed, ..
                } => activity_changed.notified(),
            };
            let (deadline, reads, active) = match self {
                Self::History {
                    activity,
                    reads,
                    active_reads,
                    ..
                }
                | Self::Current {
                    activity,
                    reads,
                    active_reads,
                    ..
                } => (
                    *activity.lock().expect("timeline activity poisoned") + timeout,
                    reads.clone(),
                    active_reads.load(Ordering::Acquire),
                ),
            };
            let now = tokio::time::Instant::now();
            if deadline <= now && reads.available_permits() == MAX_READS && active == 0 {
                self.request_close();
                return;
            }
            if deadline <= now {
                notified.await;
            } else {
                tokio::select! {
                    _ = tokio::time::sleep_until(deadline) => {}
                    _ = notified => {}
                }
            }
        }
    }
}

pub(crate) struct TimelineReadLease {
    owner: Arc<TimelineOwner>,
    _permit: Option<OwnedSemaphorePermit>,
}

impl TimelineReadLease {
    fn history(&self) -> Result<&HistoryReader, ApiError> {
        self.owner.history_reader().ok_or_else(stale_scope)
    }

    fn current(&self) -> Result<&CurrentReader, ApiError> {
        self.owner.current_reader().ok_or_else(stale_scope)
    }
}

impl Drop for TimelineReadLease {
    fn drop(&mut self) {
        if self._permit.is_none() {
            match self.owner.as_ref() {
                TimelineOwner::History { active_reads, .. }
                | TimelineOwner::Current { active_reads, .. } => {
                    active_reads.fetch_sub(1, Ordering::AcqRel);
                }
            }
        }
        self.owner.touch();
    }
}

impl Timelines {
    fn register(
        &self,
        state: &AppState,
        id: String,
        owner: Arc<TimelineOwner>,
    ) -> Result<(), ApiError> {
        let mut owners = self.inner.lock().expect("timeline owners poisoned");
        if owners.closed || state.shutdown.is_cancelled() {
            return Err(stale_scope());
        }
        while let Some(result) = owners.tasks.try_join_next() {
            if let Err(error) = result {
                tracing::warn!(%error, "timeline owner task failed");
            }
        }
        owners.owners.insert(id.clone(), Arc::clone(&owner));
        let task_state = state.clone();
        let task_id = id;
        let task_owner = Arc::clone(&owner);
        owners.tasks.spawn(async move {
            tokio::select! { biased;
                _ = task_state.shutdown.cancelled() => {}
                _ = task_owner.cancel().cancelled() => {}
                _ = task_owner.wait_idle(IDLE_READER_TIMEOUT) => {}
            }
            task_owner.request_close();
            if task_owner.close().await.is_ok() {
                task_state.timelines.forget(&task_id);
            }
        });
        Ok(())
    }

    fn forget(&self, id: &str) {
        self.inner
            .lock()
            .expect("timeline owners poisoned")
            .owners
            .remove(id);
    }

    fn closing(
        &self,
        thread_id: &str,
        headers: &HeaderMap,
    ) -> Result<(String, Arc<TimelineOwner>), ApiError> {
        let id = header_id(headers)?;
        let owners = self.inner.lock().expect("timeline owners poisoned");
        let owner = owners
            .owners
            .get(&id)
            .filter(|owner| owner.thread_id() == thread_id)
            .cloned()
            .ok_or_else(stale_scope)?;
        Ok((id, owner))
    }

    fn borrow(
        &self,
        thread_id: &str,
        headers: &HeaderMap,
        shutdown: &CancellationToken,
    ) -> Result<TimelineReadLease, ApiError> {
        let id = header_id(headers)?;
        let owners = self.inner.lock().expect("timeline owners poisoned");
        let owner = owners
            .owners
            .get(&id)
            .filter(|owner| owner.thread_id() == thread_id)
            .cloned()
            .ok_or_else(stale_scope)?;
        let registry_closed = owners.closed;
        drop(owners);
        if registry_closed || shutdown.is_cancelled() || owner.cancel().is_cancelled() {
            return Err(stale_scope());
        }
        let (reads, activity) = match owner.as_ref() {
            TimelineOwner::History {
                reads, activity, ..
            }
            | TimelineOwner::Current {
                reads, activity, ..
            } => (reads.clone(), activity),
        };
        let permit = {
            let mut last = activity.lock().expect("timeline activity poisoned");
            if owner.cancel().is_cancelled() {
                return Err(stale_scope());
            }
            let permit = reads
                .try_acquire_owned()
                .map_err(|_| ApiError::overloaded())?;
            *last = tokio::time::Instant::now();
            owner.touch();
            permit
        };
        Ok(TimelineReadLease {
            owner,
            _permit: Some(permit),
        })
    }

    fn borrow_watch(
        &self,
        thread_id: &str,
        headers: &HeaderMap,
        shutdown: &CancellationToken,
    ) -> Result<TimelineReadLease, ApiError> {
        let id = header_id(headers)?;
        let owners = self.inner.lock().expect("timeline owners poisoned");
        let owner = owners
            .owners
            .get(&id)
            .filter(|owner| owner.thread_id() == thread_id)
            .cloned()
            .ok_or_else(stale_scope)?;
        let registry_closed = owners.closed;
        drop(owners);
        if registry_closed || shutdown.is_cancelled() || owner.cancel().is_cancelled() {
            return Err(stale_scope());
        }
        match owner.as_ref() {
            TimelineOwner::History { active_reads, .. }
            | TimelineOwner::Current { active_reads, .. } => {
                active_reads.fetch_add(1, Ordering::AcqRel);
            }
        }
        owner.touch();
        Ok(TimelineReadLease {
            owner,
            _permit: None,
        })
    }

    pub(crate) async fn shutdown(&self) -> anyhow::Result<()> {
        let mut failure: Option<anyhow::Error> = None;
        let mut tasks = {
            let mut owners = self.inner.lock().expect("timeline owners poisoned");
            owners.closed = true;
            for owner in owners.owners.values() {
                owner.request_close();
            }
            std::mem::take(&mut owners.tasks)
        };
        while let Some(result) = tasks.join_next().await {
            if let Err(error) = result {
                let error = anyhow::Error::new(error);
                failure = Some(match failure {
                    Some(previous) => {
                        previous.context(format!("another timeline join failed: {error:#}"))
                    }
                    None => error,
                });
            }
        }
        let owners = self
            .inner
            .lock()
            .expect("timeline owners poisoned")
            .owners
            .iter()
            .map(|(id, owner)| (id.clone(), owner.clone()))
            .collect::<Vec<_>>();
        for (id, owner) in owners {
            match owner.close().await {
                Ok(()) => self.forget(&id),
                Err(error) => {
                    let error = anyhow::Error::new(error);
                    failure = Some(match failure {
                        Some(previous) => {
                            previous.context(format!("timeline {id} close also failed: {error:#}"))
                        }
                        None => error.context(format!("timeline {id} close failed")),
                    });
                }
            }
        }
        match failure {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }
}

fn header_id(headers: &HeaderMap) -> Result<String, ApiError> {
    let mut ids = headers.get_all(CONVERSATION_HEADER).iter();
    let id = ids
        .next()
        .and_then(|value| value.to_str().ok())
        .filter(|value| !value.is_empty())
        .ok_or_else(stale_scope)?;
    if ids.next().is_some() {
        return Err(stale_scope());
    }
    Ok(id.to_owned())
}

pub(crate) fn stale_scope() -> ApiError {
    ApiError(
        StudioError::new(
            StudioErrorCode::Conflict,
            "The original timeline read scope is no longer available",
            false,
        )
        .with_reason(StudioErrorReason::StaleReadScope, serde_json::Value::Null),
    )
}

fn next_owner(kind: &str, thread_id: &str) -> String {
    format!(
        "{kind}:{thread_id}:{}",
        NEXT_OWNER.fetch_add(1, Ordering::Relaxed)
    )
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct OpenHistoryRequest {
    history_protocol_version: u32,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) struct OpenHistoryResponse {
    pub history_protocol_version: u32,
    pub reader_id: String,
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/open",
    operation_id = "thread.openHistory",
    params(("thread_id" = String, Path)),
    request_body = OpenHistoryRequest,
    responses(StudioApiErrors, (status = 200, body = OpenHistoryResponse)))]
pub(crate) async fn open_history(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiJson(request): ApiJson<OpenHistoryRequest>,
) -> Result<impl IntoResponse, ApiError> {
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let reader = state
        .runtime
        .open_history_reader(&thread_id, request.history_protocol_version)
        .await?;
    let id = next_owner("history", &thread_id);
    let owner = Arc::new(TimelineOwner::history(thread_id, reader, permit));
    if let Err(error) = state
        .timelines
        .register(&state, id.clone(), Arc::clone(&owner))
    {
        owner.request_close();
        let _ = owner.close().await;
        return Err(error);
    }
    Ok((
        [(CONVERSATION_HEADER, id.clone())],
        Json(OpenHistoryResponse {
            history_protocol_version: request.history_protocol_version,
            reader_id: id,
        }),
    ))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct OpenCurrentRequest {
    current_protocol_version: u32,
    demand: ReadDemand,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) struct OpenCurrentResponse {
    pub current_protocol_version: u32,
    pub current_owner_id: String,
    pub reader_id: String,
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/current/open",
    operation_id = "thread.openCurrent",
    params(("thread_id" = String, Path)),
    request_body = OpenCurrentRequest,
    responses(StudioApiErrors, (status = 200, body = OpenCurrentResponse)))]
pub(crate) async fn open_current(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiJson(request): ApiJson<OpenCurrentRequest>,
) -> Result<impl IntoResponse, ApiError> {
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let reader = state
        .runtime
        .open_current_reader(&thread_id, request.current_protocol_version, request.demand)
        .await?;
    let initial = match reader.snapshot(request.demand).await {
        Ok(view) => view,
        Err(error) => {
            reader.request_close();
            let _ = reader.close().await;
            return Err(error.into());
        }
    };
    let id = next_owner("current", &thread_id);
    let owner = Arc::new(TimelineOwner::current(thread_id, reader, permit));
    if let Err(error) = state
        .timelines
        .register(&state, id.clone(), Arc::clone(&owner))
    {
        owner.request_close();
        let _ = owner.close().await;
        return Err(error);
    }
    Ok((
        [(CONVERSATION_HEADER, id.clone())],
        Json(OpenCurrentResponse {
            current_protocol_version: request.current_protocol_version,
            current_owner_id: initial.revision.owner_id,
            reader_id: id,
        }),
    ))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct HistoryPageRequest {
    #[schema(value_type = Object)]
    cut: Option<HistoryCut>,
    cursor: Option<String>,
    #[schema(value_type = Object)]
    demand: HistoryDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct HistoryGroupRequest {
    group_id: String,
    #[schema(value_type = Object)]
    cut: Option<HistoryCut>,
    cursor: Option<String>,
    #[schema(value_type = Object)]
    demand: HistoryDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct HistoryEventsRequest {
    #[schema(value_type = Object)]
    query: HistoryEventsQuery,
    #[schema(value_type = Object)]
    cut: Option<HistoryCut>,
    cursor: Option<String>,
    #[schema(value_type = Object)]
    demand: HistoryDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct HistoryEventRequest {
    event_id: String,
    #[schema(value_type = Object)]
    demand: HistoryDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct HistoryBodiesRequest {
    event_id: String,
    cursor: Option<String>,
    #[schema(value_type = Object)]
    demand: HistoryDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct HistoryBodyRequest {
    #[schema(value_type = Object)]
    reference: HistoryEventBodyRef,
    offset: u64,
    max_bytes: u32,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct HistoryCutRequest {
    #[schema(value_type = Object)]
    cut: HistoryCut,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct HistoryAccountingRequest {
    #[schema(value_type = Object)]
    cut: Option<HistoryCut>,
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/capture",
    operation_id = "thread.captureHistory",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn capture(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
) -> Result<Json<HistoryCut>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(lease.history()?.capture().await?))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/timeline",
    operation_id = "thread.readHistoryTimeline",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = HistoryPageRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn timeline(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<HistoryPageRequest>,
) -> Result<Json<HistoryTimelinePage>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .history()?
            .timeline_page(request.cut, request.cursor, request.demand)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/group",
    operation_id = "thread.readHistoryGroup",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = HistoryGroupRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn group(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<HistoryGroupRequest>,
) -> Result<Json<HistoryGroupPage>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .history()?
            .group_page(
                request.group_id,
                request.cut,
                request.cursor,
                request.demand,
            )
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/turns",
    operation_id = "thread.readHistoryTurns",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = HistoryPageRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn turns(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<HistoryPageRequest>,
) -> Result<Json<HistoryTimelinePage>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .history()?
            .turns_page(request.cut, request.cursor, request.demand)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/events",
    operation_id = "thread.readHistoryEvents",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = HistoryEventsRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn events(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<HistoryEventsRequest>,
) -> Result<Json<HistoryEventsPage>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .history()?
            .events_page(request.query, request.cut, request.cursor, request.demand)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/event",
    operation_id = "thread.readHistoryEvent",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = HistoryEventRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn event(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<HistoryEventRequest>,
) -> Result<Json<HistoryEventDetail>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .history()?
            .read_event(request.event_id, request.demand)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/bodies",
    operation_id = "thread.listHistoryBodies",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = HistoryBodiesRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn bodies(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<HistoryBodiesRequest>,
) -> Result<Json<HistoryBodyPage>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .history()?
            .list_bodies(request.event_id, request.cursor, request.demand)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/body",
    operation_id = "thread.readHistoryBody",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = HistoryBodyRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn body(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<HistoryBodyRequest>,
) -> Result<Json<HistoryBodyWindow>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .history()?
            .read_body(request.reference, request.offset, request.max_bytes)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/costs",
    operation_id = "thread.readHistoryCosts",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = HistoryPageRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn costs(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<HistoryPageRequest>,
) -> Result<Json<HistoryTimelinePage>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .history()?
            .costs_page(request.cut, request.cursor, request.demand)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/accounting",
    operation_id = "thread.readHistoryAccounting",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = HistoryAccountingRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn accounting(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<HistoryAccountingRequest>,
) -> Result<Json<Option<HistoryAccountingHead>>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(lease.history()?.accounting(request.cut).await?))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/changed",
    operation_id = "thread.watchHistoryChanged",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = HistoryCutRequest,
    responses(StudioApiErrors, (status = 200, body = String, content_type = "text/event-stream")))]
pub(crate) async fn changed(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<HistoryCutRequest>,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    let lease = state
        .timelines
        .borrow_watch(&thread_id, &headers, &state.shutdown)?;
    let reader = lease.history()?.clone();
    let owner = Arc::clone(&lease.owner);
    let (sender, receiver) = mpsc::channel(1);
    Arc::clone(&owner).spawn_task(async move {
        let _lease = lease;
        let mut cut = request.cut;
        loop {
            let capacity = tokio::select! { biased;
                () = state.shutdown.cancelled() => break,
                () = owner.cancel().cancelled() => break,
                capacity = sender.reserve() => match capacity {
                    Ok(capacity) => capacity,
                    Err(_) => break,
                },
            };
            let changed = tokio::select! { biased;
                () = state.shutdown.cancelled() => break,
                () = owner.cancel().cancelled() => break,
                () = sender.closed() => break,
                changed = reader.wait_changed(cut.clone()) => changed,
            };
            let changed = match changed {
                Ok(changed) => changed,
                Err(error) => {
                    if let Ok(event) = Event::default().event("error").json_data(
                        pl_studio_runtime::studio_error_from_anyhow(anyhow::Error::new(error)),
                    ) {
                        capacity.send(Ok(event));
                    }
                    break;
                }
            };
            cut = changed.clone();
            let Ok(event) = Event::default().event("changed").json_data(changed) else {
                break;
            };
            capacity.send(Ok(event));
        }
        let _ = sender.try_send(Ok(Event::default().event("closed").data("{}")));
    })?;
    Ok(Sse::new(ReceiverStream::new(receiver))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct CurrentSnapshotRequest {
    demand: ReadDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct CurrentWatchRequest {
    after: Option<CurrentRevision>,
    demand: ReadDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct CurrentPageRequest {
    reference: CurrentCollectionRef,
    continuation: Option<String>,
    demand: ReadDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct CurrentBodyRequest {
    reference: CurrentContentRef,
    range: ContentRange,
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/current/snapshot",
    operation_id = "thread.snapshotCurrent",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = CurrentSnapshotRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn snapshot(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<CurrentSnapshotRequest>,
) -> Result<Json<pl_studio_runtime::CurrentView>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(lease.current()?.snapshot(request.demand).await?))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/current/watch",
    operation_id = "thread.watchCurrent",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = CurrentWatchRequest,
    responses(StudioApiErrors, (status = 200, body = String, content_type = "text/event-stream")))]
pub(crate) async fn watch(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<CurrentWatchRequest>,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    let lease = state
        .timelines
        .borrow_watch(&thread_id, &headers, &state.shutdown)?;
    let current = lease.current()?.clone();
    let owner = Arc::clone(&lease.owner);
    let watch = current.watch(request.after, request.demand).await?;
    let (sender, receiver) = mpsc::channel(1);
    let task_owner = Arc::clone(&owner);
    owner.spawn_task(async move {
        let _lease = lease;
        run_current_watch(&state, task_owner.as_ref(), watch, sender).await;
    })?;
    Ok(Sse::new(ReceiverStream::new(receiver))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")))
}

async fn run_current_watch(
    state: &AppState,
    owner: &TimelineOwner,
    mut watch: CurrentWatch,
    sender: mpsc::Sender<Result<Event, Infallible>>,
) {
    loop {
        let capacity = tokio::select! { biased;
            () = state.shutdown.cancelled() => break,
            () = owner.cancel().cancelled() => break,
            capacity = sender.reserve() => match capacity {
                Ok(capacity) => capacity,
                Err(_) => break,
            },
        };
        let frame = tokio::select! { biased;
            () = state.shutdown.cancelled() => break,
            () = owner.cancel().cancelled() => break,
            () = sender.closed() => break,
            frame = watch.next() => frame,
        };
        match frame {
            Ok(Some(frame)) => {
                let Ok(event) = Event::default().event("current").json_data(frame) else {
                    break;
                };
                capacity.send(Ok(event));
            }
            Ok(None) => break,
            Err(error) => {
                if let Ok(event) = Event::default()
                    .event("error")
                    .json_data(pl_studio_runtime::studio_error_from_anyhow(error))
                {
                    capacity.send(Ok(event));
                }
                break;
            }
        }
    }
    watch.request_close();
    if let Err(error) = watch.close().await {
        tracing::warn!(%error, "current SSE watch close failed");
    }
    let _ = sender.try_send(Ok(Event::default().event("closed").data("{}")));
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/current/page",
    operation_id = "thread.pageCurrent",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = CurrentPageRequest,
    responses(StudioApiErrors, (status = 200, body = CurrentCollectionPage)))]
pub(crate) async fn page(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<CurrentPageRequest>,
) -> Result<Json<CurrentCollectionPage>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .current()?
            .page_collection(request.reference, request.continuation, request.demand)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/current/body/read",
    operation_id = "thread.readCurrentBody",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = CurrentBodyRequest,
    responses(StudioApiErrors, (status = 200, body = pl_studio_runtime::ContentWindow)))]
pub(crate) async fn body_read(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<CurrentBodyRequest>,
) -> Result<Json<pl_studio_runtime::ContentWindow>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .current()?
            .read_body(request.reference, request.range)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/current/body/watch",
    operation_id = "thread.watchCurrentBody",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = CurrentBodyRequest,
    responses(StudioApiErrors, (status = 200, body = String, content_type = "text/event-stream")))]
pub(crate) async fn body_watch(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<CurrentBodyRequest>,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    let lease = state
        .timelines
        .borrow_watch(&thread_id, &headers, &state.shutdown)?;
    let watch = lease
        .current()?
        .watch_body(request.reference, request.range)
        .await?;
    let owner = Arc::clone(&lease.owner);
    let (sender, receiver) = mpsc::channel(1);
    let task_owner = Arc::clone(&owner);
    owner.spawn_task(async move {
        let _lease = lease;
        run_body_watch(&state, task_owner.as_ref(), watch, sender).await;
    })?;
    Ok(Sse::new(ReceiverStream::new(receiver))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")))
}

async fn run_body_watch(
    state: &AppState,
    owner: &TimelineOwner,
    mut watch: pl_studio_runtime::CurrentBodyWatch,
    sender: mpsc::Sender<Result<Event, Infallible>>,
) {
    loop {
        let capacity = tokio::select! { biased;
            () = state.shutdown.cancelled() => break,
            () = owner.cancel().cancelled() => break,
            capacity = sender.reserve() => match capacity {
                Ok(capacity) => capacity,
                Err(_) => break,
            },
        };
        let window = tokio::select! { biased;
            () = state.shutdown.cancelled() => break,
            () = owner.cancel().cancelled() => break,
            () = sender.closed() => break,
            window = watch.next() => window,
        };
        match window {
            Ok(Some(window)) => {
                let Ok(event) = Event::default().event("body").json_data(window) else {
                    break;
                };
                capacity.send(Ok(event));
            }
            Ok(None) => break,
            Err(error) => {
                if let Ok(event) = Event::default()
                    .event("error")
                    .json_data(pl_studio_runtime::studio_error_from_anyhow(error))
                {
                    capacity.send(Ok(event));
                }
                break;
            }
        }
    }
    watch.request_close();
    if let Err(error) = watch.close().await {
        tracing::warn!(%error, "current body SSE watch close failed");
    }
    let _ = sender.try_send(Ok(Event::default().event("closed").data("{}")));
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/close",
    operation_id = "thread.closeHistory",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    responses(StudioApiErrors, (status = 204)))]
pub(crate) async fn close_history(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
) -> Result<axum::http::StatusCode, ApiError> {
    close_owner(state, thread_id, headers, false).await
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/current/close",
    operation_id = "thread.closeCurrent",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    responses(StudioApiErrors, (status = 204)))]
pub(crate) async fn close_current(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
) -> Result<axum::http::StatusCode, ApiError> {
    close_owner(state, thread_id, headers, true).await
}

async fn close_owner(
    state: AppState,
    thread_id: String,
    headers: HeaderMap,
    current: bool,
) -> Result<axum::http::StatusCode, ApiError> {
    let (id, owner) = state.timelines.closing(&thread_id, &headers)?;
    if current != owner.current_reader().is_some() {
        return Err(stale_scope());
    }
    owner.request_close();
    owner.close().await.map_err(ApiError)?;
    state.timelines.forget(&id);
    Ok(axum::http::StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn body_window_limit_matches_history_owner() {
        assert!(pl_studio_runtime::history::BODY_CHUNK_BYTES > 0);
    }
}
