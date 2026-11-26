//! Independent immutable-history and unified `ConversationFeed` HTTP read owners.

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
use pl_studio_runtime::history::HistoryReader;
use pl_studio_runtime::{
    StudioError, StudioErrorCode, StudioErrorReason,
    history::{
        HistoryAccountingHead, HistoryBodyPage, HistoryBodyWindow, HistoryBusinessPage, HistoryCut,
        HistoryDemand, HistoryEventBodyRef, HistoryEventRecord, HistoryEventsPage,
        HistoryEventsQuery, HistoryTimelinePage, HistoryWorkRangePage,
    },
    timeline::{
        BodyRef, BodyWindow, ConversationFeed, LiveStatusSnapshot, SessionDetailKind,
        SessionDetailWindow, SessionMetaSnapshot, TimelinePatch, WorkGroupMember,
    },
};
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
    Feed {
        thread_id: String,
        feed: ConversationFeed,
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

    fn feed(thread_id: String, feed: ConversationFeed, permit: OwnedSemaphorePermit) -> Self {
        Self::Feed {
            thread_id,
            feed,
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
            Self::History { thread_id, .. } | Self::Feed { thread_id, .. } => thread_id,
        }
    }

    fn history_reader(&self) -> Option<&HistoryReader> {
        match self {
            Self::History { reader, .. } => Some(reader),
            Self::Feed { .. } => None,
        }
    }

    fn conversation_feed(&self) -> Option<&ConversationFeed> {
        match self {
            Self::History { .. } => None,
            Self::Feed { feed, .. } => Some(feed),
        }
    }

    fn cancel(&self) -> &CancellationToken {
        match self {
            Self::History { cancel, .. } | Self::Feed { cancel, .. } => cancel,
        }
    }

    fn tasks(&self) -> &TaskTracker {
        match self {
            Self::History { tasks, .. } | Self::Feed { tasks, .. } => tasks,
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
            | Self::Feed {
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
            | Self::Feed {
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
            | Self::Feed {
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
            Self::Feed { feed, .. } => feed.request_close(),
        }
        tasks.close();
    }

    async fn close(&self) -> Result<(), StudioError> {
        self.request_close();
        let _close = match self {
            Self::History { close_gate, .. } | Self::Feed { close_gate, .. } => {
                close_gate.lock().await
            }
        };
        match self {
            Self::History { reader, .. } => reader.close().await,
            Self::Feed { feed, .. } => feed.close().await,
        }
        self.tasks().wait().await;
        match self {
            Self::History { permit, .. } | Self::Feed { permit, .. } => {
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
                | Self::Feed {
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
                | Self::Feed {
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

    fn feed(&self) -> Result<&ConversationFeed, ApiError> {
        self.owner.conversation_feed().ok_or_else(stale_scope)
    }
}

impl Drop for TimelineReadLease {
    fn drop(&mut self) {
        if self._permit.is_none() {
            match self.owner.as_ref() {
                TimelineOwner::History { active_reads, .. }
                | TimelineOwner::Feed { active_reads, .. } => {
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
        self.closing_by_id(thread_id, &header_id(headers)?)
    }

    fn closing_by_id(
        &self,
        thread_id: &str,
        id: &str,
    ) -> Result<(String, Arc<TimelineOwner>), ApiError> {
        let owners = self.inner.lock().expect("timeline owners poisoned");
        let owner = owners
            .owners
            .get(id)
            .filter(|owner| owner.thread_id() == thread_id)
            .cloned()
            .ok_or_else(stale_scope)?;
        Ok((id.to_owned(), owner))
    }

    fn borrow(
        &self,
        thread_id: &str,
        headers: &HeaderMap,
        shutdown: &CancellationToken,
    ) -> Result<TimelineReadLease, ApiError> {
        self.borrow_by_id(thread_id, &header_id(headers)?, shutdown)
    }

    fn borrow_by_id(
        &self,
        thread_id: &str,
        id: &str,
        shutdown: &CancellationToken,
    ) -> Result<TimelineReadLease, ApiError> {
        let owners = self.inner.lock().expect("timeline owners poisoned");
        let owner = owners
            .owners
            .get(id)
            .filter(|owner| owner.thread_id() == thread_id)
            .cloned()
            .ok_or_else(stale_scope)?;
        let registry_closed = owners.closed;
        drop(owners);
        if registry_closed || shutdown.is_cancelled() || owner.cancel().is_cancelled() {
            return Err(stale_scope());
        }
        let (reads, activity, activity_changed) = match owner.as_ref() {
            TimelineOwner::History {
                reads,
                activity,
                activity_changed,
                ..
            }
            | TimelineOwner::Feed {
                reads,
                activity,
                activity_changed,
                ..
            } => (reads, activity, activity_changed),
        };
        let permit = {
            let mut last = activity.lock().expect("timeline activity poisoned");
            if owner.cancel().is_cancelled() {
                return Err(stale_scope());
            }
            let permit = reads
                .clone()
                .try_acquire_owned()
                .map_err(|_| ApiError::overloaded())?;
            *last = tokio::time::Instant::now();
            permit
        };
        activity_changed.notify_one();
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
        self.borrow_watch_by_id(thread_id, &header_id(headers)?, shutdown)
    }

    fn borrow_watch_by_id(
        &self,
        thread_id: &str,
        id: &str,
        shutdown: &CancellationToken,
    ) -> Result<TimelineReadLease, ApiError> {
        let owners = self.inner.lock().expect("timeline owners poisoned");
        let owner = owners
            .owners
            .get(id)
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
            | TimelineOwner::Feed { active_reads, .. } => {
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

#[derive(Debug, Default, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct OpenFeedRequest {
    #[serde(default)]
    initial_limit: Option<u32>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) struct OpenFeedResponse {
    pub feed_id: String,
    pub thread_id: String,
    #[schema(value_type = Object)]
    pub live_status: LiveStatusSnapshot,
    #[schema(value_type = Object)]
    pub session_meta: SessionMetaSnapshot,
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/feed/open",
    operation_id = "thread.openFeed",
    params(("thread_id" = String, Path)),
    request_body = OpenFeedRequest,
    responses(StudioApiErrors, (status = 200, body = OpenFeedResponse)))]
pub(crate) async fn open_feed(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiJson(request): ApiJson<OpenFeedRequest>,
) -> Result<impl IntoResponse, ApiError> {
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let limit = request.initial_limit.unwrap_or(64).clamp(1, 512);
    let feed = state
        .runtime
        .open_conversation_feed(&thread_id, limit)
        .await?;
    let live_status = feed.live_status_snapshot();
    let session_meta = feed.session_meta_snapshot();
    let feed_id = next_owner("feed", &thread_id);
    let owner = Arc::new(TimelineOwner::feed(thread_id.clone(), feed, permit));
    if let Err(error) = state
        .timelines
        .register(&state, feed_id.clone(), Arc::clone(&owner))
    {
        owner.request_close();
        let _ = owner.close().await;
        return Err(error);
    }
    Ok((
        [(CONVERSATION_HEADER, feed_id.clone())],
        Json(OpenFeedResponse {
            feed_id,
            thread_id,
            live_status,
            session_meta,
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
pub(crate) struct HistoryWorkRangeRequest {
    after_seq: Option<u64>,
    before_seq: Option<u64>,
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

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/history/work-range",
    operation_id = "thread.readHistoryWorkRange",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = HistoryWorkRangeRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn work_range(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<HistoryWorkRangeRequest>,
) -> Result<Json<HistoryWorkRangePage>, ApiError> {
    let lease = state
        .timelines
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .history()?
            .work_range_page(
                request.after_seq,
                request.before_seq,
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
) -> Result<Json<HistoryBusinessPage>, ApiError> {
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
) -> Result<Json<HistoryEventRecord>, ApiError> {
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
) -> Result<Json<HistoryBusinessPage>, ApiError> {
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
pub(crate) struct FeedOlderRequest {
    cursor: String,
    #[serde(default)]
    limit: Option<u32>,
}

#[derive(Debug, Default, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct FeedWorkGroupRequest {
    after_seq: Option<u64>,
    before_seq: Option<u64>,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct FeedBodyRequest {
    #[schema(value_type = Object)]
    reference: BodyRef,
    offset: u64,
    max_bytes: u32,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct FeedDetailRequest {
    kind: SessionDetailKind,
    offset: u64,
    max_bytes: u32,
}

#[derive(Debug, Default, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct FeedResetRequest {
    #[serde(default)]
    limit: Option<u32>,
}

#[utoipa::path(get, path = "/api/v1/threads/{thread_id}/feed/{feed_id}/events",
    operation_id = "thread.streamFeedEvents",
    params(("thread_id" = String, Path), ("feed_id" = String, Path)),
    responses(StudioApiErrors, (status = 200, body = String, content_type = "text/event-stream")))]
pub(crate) async fn feed_events(
    State(state): State<AppState>,
    Path((thread_id, feed_id)): Path<(String, String)>,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    let lease = state
        .timelines
        .borrow_watch_by_id(&thread_id, &feed_id, &state.shutdown)?;
    let feed = lease.feed()?.clone();
    let owner = Arc::clone(&lease.owner);
    let (sender, receiver) = mpsc::channel(16);
    let task_owner = Arc::clone(&owner);
    owner.spawn_task(async move {
        let _lease = lease;
        run_feed_events(&state, task_owner.as_ref(), feed, sender).await;
    })?;
    Ok(Sse::new(ReceiverStream::new(receiver))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")))
}

async fn run_feed_events(
    state: &AppState,
    owner: &TimelineOwner,
    feed: ConversationFeed,
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
        let next = tokio::select! { biased;
            () = state.shutdown.cancelled() => break,
            () = owner.cancel().cancelled() => break,
            () = sender.closed() => break,
            ev = feed.next_event() => ev,
        };
        match next {
            Some(ev) => {
                let Ok(event) = Event::default().event("event").json_data(ev) else {
                    break;
                };
                capacity.send(Ok(event));
            }
            None => break,
        }
    }
    let _ = sender.try_send(Ok(Event::default().event("closed").data("{}")));
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/feed/{feed_id}/older",
    operation_id = "thread.loadFeedOlder",
    params(("thread_id" = String, Path), ("feed_id" = String, Path)),
    request_body = FeedOlderRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn feed_older(
    State(state): State<AppState>,
    Path((thread_id, feed_id)): Path<(String, String)>,
    ApiJson(request): ApiJson<FeedOlderRequest>,
) -> Result<Json<TimelinePatch>, ApiError> {
    let lease = state
        .timelines
        .borrow_by_id(&thread_id, &feed_id, &state.shutdown)?;
    let limit = request.limit.unwrap_or(64).clamp(1, 512);
    Ok(Json(lease.feed()?.load_older(request.cursor, limit).await?))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/feed/{feed_id}/work-group",
    operation_id = "thread.loadFeedWorkGroup",
    params(("thread_id" = String, Path), ("feed_id" = String, Path)),
    request_body = FeedWorkGroupRequest,
    responses(StudioApiErrors, (status = 200, body = Vec<Object>)))]
pub(crate) async fn feed_work_group(
    State(state): State<AppState>,
    Path((thread_id, feed_id)): Path<(String, String)>,
    ApiJson(request): ApiJson<FeedWorkGroupRequest>,
) -> Result<Json<Vec<WorkGroupMember>>, ApiError> {
    let lease = state
        .timelines
        .borrow_by_id(&thread_id, &feed_id, &state.shutdown)?;
    Ok(Json(
        lease
            .feed()?
            .load_work_group_members(request.after_seq, request.before_seq)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/feed/{feed_id}/body",
    operation_id = "thread.readFeedBody",
    params(("thread_id" = String, Path), ("feed_id" = String, Path)),
    request_body = FeedBodyRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn feed_body(
    State(state): State<AppState>,
    Path((thread_id, feed_id)): Path<(String, String)>,
    ApiJson(request): ApiJson<FeedBodyRequest>,
) -> Result<Json<BodyWindow>, ApiError> {
    let lease = state
        .timelines
        .borrow_by_id(&thread_id, &feed_id, &state.shutdown)?;
    Ok(Json(
        lease
            .feed()?
            .read_body_window(&request.reference, request.offset, request.max_bytes)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/feed/{feed_id}/detail",
    operation_id = "thread.readFeedDetail",
    params(("thread_id" = String, Path), ("feed_id" = String, Path)),
    request_body = FeedDetailRequest,
    responses(StudioApiErrors, (status = 200, body = SessionDetailWindow)))]
pub(crate) async fn feed_detail(
    State(state): State<AppState>,
    Path((thread_id, feed_id)): Path<(String, String)>,
    ApiJson(request): ApiJson<FeedDetailRequest>,
) -> Result<Json<SessionDetailWindow>, ApiError> {
    let lease = state
        .timelines
        .borrow_by_id(&thread_id, &feed_id, &state.shutdown)?;
    Ok(Json(lease.feed()?.read_session_detail(
        request.kind,
        request.offset,
        request.max_bytes,
    )?))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/feed/{feed_id}/reset",
    operation_id = "thread.resetFeedToLatest",
    params(("thread_id" = String, Path), ("feed_id" = String, Path)),
    request_body = FeedResetRequest,
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn feed_reset(
    State(state): State<AppState>,
    Path((thread_id, feed_id)): Path<(String, String)>,
    ApiJson(request): ApiJson<FeedResetRequest>,
) -> Result<Json<TimelinePatch>, ApiError> {
    let lease = state
        .timelines
        .borrow_by_id(&thread_id, &feed_id, &state.shutdown)?;
    let limit = request.limit.unwrap_or(64).clamp(1, 512);
    Ok(Json(lease.feed()?.reset_to_latest(limit).await?))
}

#[utoipa::path(get, path = "/api/v1/threads/{thread_id}/feed/{feed_id}/meta",
    operation_id = "thread.readFeedMeta",
    params(("thread_id" = String, Path), ("feed_id" = String, Path)),
    responses(StudioApiErrors, (status = 200, body = Object)))]
pub(crate) async fn feed_meta(
    State(state): State<AppState>,
    Path((thread_id, feed_id)): Path<(String, String)>,
) -> Result<Json<SessionMetaSnapshot>, ApiError> {
    let lease = state
        .timelines
        .borrow_by_id(&thread_id, &feed_id, &state.shutdown)?;
    Ok(Json(lease.feed()?.session_meta_snapshot()))
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
    let (id, owner) = state.timelines.closing(&thread_id, &headers)?;
    if owner.history_reader().is_none() {
        return Err(stale_scope());
    }
    owner.request_close();
    owner.close().await.map_err(ApiError)?;
    state.timelines.forget(&id);
    Ok(axum::http::StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/feed/{feed_id}/close",
    operation_id = "thread.closeFeed",
    params(("thread_id" = String, Path), ("feed_id" = String, Path)),
    responses(StudioApiErrors, (status = 204)))]
pub(crate) async fn close_feed(
    State(state): State<AppState>,
    Path((thread_id, feed_id)): Path<(String, String)>,
) -> Result<axum::http::StatusCode, ApiError> {
    let (id, owner) = state.timelines.closing_by_id(&thread_id, &feed_id)?;
    if owner.conversation_feed().is_none() {
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
    use axum::http::StatusCode;
    use axum::response::IntoResponse;
    use pl_studio_runtime::history::{
        HistoryEvent, HistoryEventKind, HistoryLimits, HistoryStore, HistoryTimelineRole,
    };
    use pl_studio_runtime::{StudioHostKind, StudioRuntime, StudioRuntimeOptions};
    use std::path::{Path as FsPath, PathBuf};
    use tokio_util::sync::CancellationToken;

    #[tokio::test]
    async fn registered_history_reader_returns_events_and_closes() -> anyhow::Result<()> {
        const FIXTURE: &str = "STUDIO_TIMELINE_READ_TEST_DIR";
        if let Some(directory) = std::env::var_os(FIXTURE) {
            return read_registered_history(&PathBuf::from(directory)).await;
        }

        // A synchronous lock regression blocks its executor, so time out a separate process.
        let directory = tempfile::tempdir()?;
        let mut child = tokio::process::Command::new(std::env::current_exe()?)
            .args([
                "--exact",
                "timeline::tests::registered_history_reader_returns_events_and_closes",
                "--nocapture",
            ])
            .env(FIXTURE, directory.path())
            .kill_on_drop(true)
            .spawn()?;
        match tokio::time::timeout(Duration::from_secs(20), child.wait()).await {
            Ok(status) => anyhow::ensure!(status?.success(), "History reader test process failed"),
            Err(_) => {
                child.kill().await?;
                anyhow::bail!("the registered History reader did not return and close");
            }
        }
        assert!(directory.path().join("read-complete").is_file());
        Ok(())
    }

    async fn read_registered_history(directory: &FsPath) -> anyhow::Result<()> {
        let thread_id = "timeline-http-read";
        let store = HistoryStore::open(
            directory.join("history.sqlite"),
            thread_id,
            HistoryLimits::default(),
        )
        .await?;
        store
            .accept_batch(&[HistoryEvent::new(
                "first",
                HistoryEventKind::RunStarted,
                HistoryTimelineRole::Hidden,
                1,
            )])
            .await?;
        store.flush().await?;
        let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::http_server(Some(directory.join("studio")))
        })
        .await?;
        let state = AppState::new(runtime.clone(), CancellationToken::new());
        let owner = TimelineOwner::history(
            thread_id.into(),
            store.reader(),
            state.streams.clone().try_acquire_owned()?,
        );
        let reader_id = next_owner("history", thread_id);
        state
            .timelines
            .register(&state, reader_id.clone(), Arc::new(owner))
            .map_err(|error| error.0)?;
        let mut headers = HeaderMap::new();
        headers.insert(CONVERSATION_HEADER, reader_id.parse()?);
        let read = events(
            State(state.clone()),
            Path(thread_id.into()),
            headers.clone(),
            ApiJson(HistoryEventsRequest {
                query: HistoryEventsQuery::AllEvents,
                cut: None,
                cursor: None,
                demand: HistoryDemand::default(),
            }),
        )
        .await;
        let close = close_history(State(state.clone()), Path(thread_id.into()), headers).await;
        state.timelines.shutdown().await?;
        runtime.shutdown_runtime().await?;
        store.close().await?;

        let Json(page) = read.map_err(|error| error.0)?;
        assert_eq!(page.entries.len(), 1);
        assert_eq!(page.entries[0].event_id, "first");
        assert_eq!(close.map_err(|error| error.0)?, StatusCode::NO_CONTENT);
        tokio::fs::write(directory.join("read-complete"), b"").await?;
        Ok(())
    }

    #[tokio::test]
    async fn http_open_handlers_reject_unknown_protocol_before_thread_lookup() {
        let home = tempfile::tempdir().expect("isolated Studio home");
        // The handlers borrow the normal runtime API; the existing isolated
        // host avoids depending on this machine's system credential service.
        let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::http_server(Some(home.path().to_path_buf()))
        })
        .await
        .expect("initialize isolated HTTP runtime");
        let state = AppState::new(runtime.clone(), CancellationToken::new());

        let history = match open_history(
            State(state.clone()),
            Path("missing-thread".into()),
            ApiJson(OpenHistoryRequest {
                history_protocol_version: pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION + 1,
            }),
        )
        .await
        {
            Err(error) => error,
            Ok(_) => panic!("unknown history protocol accepted"),
        };
        assert_eq!(history.0.code, StudioErrorCode::Protocol);
        assert_eq!(
            history.0.reason(),
            Some(StudioErrorReason::ProtocolVersionMismatch.label())
        );
        assert_eq!(history.into_response().status(), StatusCode::BAD_REQUEST);

        let feed = match open_feed(
            State(state.clone()),
            Path("missing-thread".into()),
            ApiJson(OpenFeedRequest::default()),
        )
        .await
        {
            Err(error) => error,
            Ok(_) => panic!("missing thread accepted"),
        };
        assert_eq!(feed.into_response().status(), StatusCode::NOT_FOUND);

        runtime
            .shutdown_runtime()
            .await
            .expect("shutdown isolated HTTP runtime");
    }
}
