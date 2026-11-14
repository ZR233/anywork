//! HTTP operations borrowing the read capability owned by an existing conversation SSE.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use axum::Json;
use axum::extract::{Path, State};
use axum::http::HeaderMap;
use pl_protocol::{
    ChatBatch, CompletedEntry, ContentManifestPage, ContentRange, ContentRef, ContentWindow,
    CurrentCollectionPage, CurrentCollectionRef, LegacyExecutionEvidencePage, ReadDemand,
    studio::{StudioError, StudioErrorCode, StudioErrorReason},
};
use pl_studio_runtime::{ConversationEvent, ConversationFeed, ConversationReader, TimelineReader};
use serde::Deserialize;
use tokio::sync::{OwnedSemaphorePermit, Semaphore, mpsc, oneshot, watch};
use tokio::task::JoinSet;
use tokio_util::sync::CancellationToken;
use utoipa::ToSchema;

use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, StudioApiErrors};

pub(crate) const CONVERSATION_HEADER: &str = "x-anywork-conversation";
const MAX_READS: u32 = (crate::MAX_REQUESTS + crate::MAX_STREAMS) as u32;

/// Only transport capabilities are indexed here. The reader is cloned from the
/// original feed, never reopened from a Thread ID or a continuation.
#[derive(Default)]
pub(crate) struct Conversations(pub(crate) Mutex<Owners>);

#[derive(Default)]
pub(crate) struct Owners {
    pub(crate) closed: bool,
    pub(crate) readers: HashMap<String, Arc<ReadOwner>>,
    pub(crate) tasks: JoinSet<()>,
}

pub(crate) struct ReadOwner {
    thread_id: String,
    pub(crate) reader: ConversationReader,
    pub(crate) timeline: Option<Arc<TimelineReader>>,
    pub(crate) timeline_permit: Mutex<Option<OwnedSemaphorePermit>>,
    activity: Mutex<tokio::time::Instant>,
    activity_changed: tokio::sync::Notify,
    main_reads: std::sync::atomic::AtomicUsize,
    pub(crate) cancel: CancellationToken,
    reads: Arc<Semaphore>,
    pub(crate) native: tokio::sync::Mutex<Option<NativeFeed>>,
    pub(crate) events: Mutex<Option<oneshot::Sender<EventSender>>>,
    pub(crate) completed: watch::Sender<Option<Result<(), StudioError>>>,
    pub(crate) close_gate: tokio::sync::Mutex<()>,
    /// Failed member closes remain on the original read owner for explicit retry.
    pub(crate) members: Mutex<Vec<MemberRead>>,
}

pub(crate) type MemberRead = Arc<tokio::sync::Mutex<Option<pl_studio_runtime::DisplayMembers>>>;

pub(crate) type EventSender =
    mpsc::Sender<Result<axum::response::sse::Event, std::convert::Infallible>>;

pub(crate) enum NativeFeed {
    Conversation(Box<ConversationFeed>),
}

pub(crate) enum NativeEvent {
    Conversation(ConversationEvent),
}

impl NativeFeed {
    pub(crate) fn subscription_id(&self) -> &str {
        match self {
            Self::Conversation(feed) => feed.subscription_id(),
        }
    }

    pub(crate) fn reader(&self) -> &ConversationReader {
        match self {
            Self::Conversation(feed) => feed.reader(),
        }
    }

    pub(crate) async fn recv(&mut self) -> anyhow::Result<Option<NativeEvent>> {
        match self {
            Self::Conversation(feed) => feed
                .recv()
                .await
                .map(|event| event.map(NativeEvent::Conversation)),
        }
    }

    pub(crate) fn request_close(&self) {
        match self {
            Self::Conversation(feed) => feed.request_close(),
        }
    }

    pub(crate) async fn close(&mut self) -> anyhow::Result<()> {
        match self {
            Self::Conversation(feed) => feed.close().await,
        }
    }
}

impl ReadOwner {
    pub(crate) fn new(thread_id: String, reader: ConversationReader) -> Self {
        Self {
            thread_id,
            reader,
            timeline: None,
            timeline_permit: Mutex::new(None),
            activity: Mutex::new(tokio::time::Instant::now()),
            activity_changed: tokio::sync::Notify::new(),
            main_reads: std::sync::atomic::AtomicUsize::new(0),
            cancel: CancellationToken::new(),
            reads: Arc::new(Semaphore::new(MAX_READS as usize)),
            native: tokio::sync::Mutex::new(None),
            events: Mutex::new(None),
            completed: watch::channel(None).0,
            close_gate: tokio::sync::Mutex::new(()),
            members: Mutex::new(Vec::new()),
        }
    }

    pub(crate) fn with_feed(thread_id: String, feed: NativeFeed) -> Self {
        let owner = Self::new(thread_id, feed.reader().clone());
        *owner.native.try_lock().expect("unpublished owner") = Some(feed);
        owner
    }

    pub(crate) fn request_close(&self) {
        if let Some(reader) = &self.timeline {
            reader.request_close();
        }
        self.cancel.cancel();
        self.reader.request_close();
        self.events
            .lock()
            .expect("conversation start poisoned")
            .take();
    }

    pub(crate) async fn drain(&self) {
        // Removal from the index precedes this wait, so no new permits can be
        // acquired. Watches drop their permit only after closing their source.
        let _all = self.reads.acquire_many(MAX_READS).await;
    }
}

pub(crate) struct ReadLease {
    pub(crate) owner: Arc<ReadOwner>,
    _permit: Option<OwnedSemaphorePermit>,
}

impl ReadOwner {
    pub(crate) fn with_timeline(
        thread_id: String,
        timeline: TimelineReader,
        permit: OwnedSemaphorePermit,
    ) -> Self {
        let mut owner = Self::new(thread_id, timeline.reader().clone());
        owner.timeline = Some(Arc::new(timeline));
        *owner.timeline_permit.lock().expect("unpublished timeline") = Some(permit);
        owner
    }
    fn touch(&self) {
        *self.activity.lock().expect("reader activity poisoned") = tokio::time::Instant::now();
        self.activity_changed.notify_one();
    }
    pub(crate) async fn wait_idle(&self, timeout: std::time::Duration) {
        loop {
            let notified = self.activity_changed.notified();
            let deadline = {
                // Admission and expiry share this short lock. Once expiry wins, the capability
                // is synchronously revoked before any later request can claim an active read.
                let activity = self.activity.lock().expect("reader activity poisoned");
                let deadline = *activity + timeout;
                if deadline <= tokio::time::Instant::now()
                    && self.reads.available_permits() == MAX_READS as usize
                    && self.main_reads.load(std::sync::atomic::Ordering::Acquire) == 0
                    && self
                        .members
                        .lock()
                        .expect("reader members poisoned")
                        .is_empty()
                {
                    self.request_close();
                    return;
                }
                deadline
            };
            if deadline <= tokio::time::Instant::now() {
                notified.await;
            } else {
                tokio::select! { _ = tokio::time::sleep_until(deadline) => {}, _ = notified => {} }
            }
        }
    }
}
impl Drop for ReadLease {
    fn drop(&mut self) {
        if self._permit.is_none() {
            self.owner
                .main_reads
                .fetch_sub(1, std::sync::atomic::Ordering::AcqRel);
        }
        self.owner.touch();
    }
}

impl Conversations {
    pub(crate) fn borrow_next(
        &self,
        thread_id: &str,
        headers: &HeaderMap,
        shutdown: &CancellationToken,
    ) -> Result<ReadLease, ApiError> {
        let (_, owner) = self.closing_owner(thread_id, headers)?;
        {
            let mut activity = owner.activity.lock().expect("reader activity poisoned");
            if shutdown.is_cancelled() || owner.cancel.is_cancelled() || owner.timeline.is_none() {
                return Err(stale_scope());
            }
            owner
                .main_reads
                .fetch_add(1, std::sync::atomic::Ordering::AcqRel);
            *activity = tokio::time::Instant::now();
            owner.activity_changed.notify_one();
        }
        Ok(ReadLease {
            owner,
            _permit: None,
        })
    }
    pub(crate) fn borrow(
        &self,
        thread_id: &str,
        headers: &HeaderMap,
        shutdown: &CancellationToken,
    ) -> Result<ReadLease, ApiError> {
        let mut values = headers.get_all(CONVERSATION_HEADER).iter();
        let id = values
            .next()
            .and_then(|value| value.to_str().ok())
            .filter(|value| !value.is_empty())
            .ok_or_else(stale_scope)?;
        if values.next().is_some() {
            return Err(stale_scope());
        }
        let owners = self.0.lock().expect("conversation owners poisoned");
        let owner = owners.readers.get(id).ok_or_else(stale_scope)?;
        if owners.closed
            || shutdown.is_cancelled()
            || owner.thread_id != thread_id
            || owner.cancel.is_cancelled()
        {
            return Err(stale_scope());
        }
        let permit = {
            let mut activity = owner.activity.lock().expect("reader activity poisoned");
            if owner.cancel.is_cancelled() {
                return Err(stale_scope());
            }
            let permit = owner
                .reads
                .clone()
                .try_acquire_owned()
                .map_err(|_| ApiError::overloaded())?;
            *activity = tokio::time::Instant::now();
            owner.activity_changed.notify_one();
            permit
        };
        Ok(ReadLease {
            owner: owner.clone(),
            _permit: Some(permit),
        })
    }

    pub(crate) fn remove(&self, id: &str) {
        let owners = self.0.lock().expect("conversation owners poisoned");
        if let Some(owner) = owners.readers.get(id) {
            owner.request_close();
        }
    }

    pub(crate) fn forget(&self, id: &str) {
        self.0
            .lock()
            .expect("conversation owners poisoned")
            .readers
            .remove(id);
    }

    /// Close can recover a cancelled owner, but never a foreign Thread or capability.
    pub(crate) fn closing_owner(
        &self,
        thread_id: &str,
        headers: &HeaderMap,
    ) -> Result<(String, Arc<ReadOwner>), ApiError> {
        let mut ids = headers.get_all(CONVERSATION_HEADER).iter();
        let id = ids
            .next()
            .and_then(|id| id.to_str().ok())
            .filter(|id| !id.is_empty())
            .ok_or_else(stale_scope)?;
        if ids.next().is_some() {
            return Err(stale_scope());
        }
        let owners = self.0.lock().expect("conversation owners poisoned");
        let owner = owners
            .readers
            .get(id)
            .filter(|owner| owner.thread_id == thread_id)
            .ok_or_else(stale_scope)?;
        Ok((id.to_owned(), Arc::clone(owner)))
    }

    pub(crate) async fn shutdown(&self) {
        let mut tasks = {
            let mut owners = self.0.lock().expect("conversation owners poisoned");
            owners.closed = true;
            for owner in owners.readers.values() {
                owner.request_close();
            }
            std::mem::take(&mut owners.tasks)
        };
        while let Some(result) = tasks.join_next().await {
            if let Err(error) = result {
                tracing::warn!(%error, "conversation HTTP owner task failed");
            }
        }
    }
}

pub(crate) fn stale_scope() -> ApiError {
    ApiError(
        StudioError::new(
            StudioErrorCode::Conflict,
            "The original conversation read scope is no longer available",
            false,
        )
        .with_reason(StudioErrorReason::StaleReadScope, serde_json::Value::Null),
    )
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct OlderRequest {
    pub before: String,
    pub demand: ReadDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct CompletedRequest {
    pub record_id: String,
    pub demand: ReadDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ManifestRequest {
    pub item_id: String,
    pub continuation: Option<String>,
    pub demand: ReadDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ContentRequest {
    pub reference: ContentRef,
    pub range: ContentRange,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct CurrentRequest {
    pub reference: CurrentCollectionRef,
    pub continuation: Option<String>,
    pub demand: ReadDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct LegacyEvidenceRequest {
    pub continuation: Option<String>,
    pub demand: ReadDemand,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct LegacyEvidenceContentRequest {
    pub evidence_id: String,
    pub revision: u64,
    pub range: ContentRange,
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/legacy-execution-evidence",
    operation_id = "thread.listLegacyExecutionEvidence",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = LegacyEvidenceRequest,
    responses(StudioApiErrors, (status = 200, body = LegacyExecutionEvidencePage)))]
pub(crate) async fn legacy_evidence(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<LegacyEvidenceRequest>,
) -> Result<Json<LegacyExecutionEvidencePage>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .owner
            .reader
            .legacy_execution_evidence(request.continuation.as_deref(), request.demand)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/legacy-execution-evidence/read",
    operation_id = "thread.readLegacyExecutionEvidence",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = LegacyEvidenceContentRequest,
    responses(StudioApiErrors, (status = 200, body = ContentWindow)))]
pub(crate) async fn legacy_evidence_content(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<LegacyEvidenceContentRequest>,
) -> Result<Json<ContentWindow>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .owner
            .reader
            .read_legacy_execution_evidence(&request.evidence_id, request.revision, request.range)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/chat/older",
    operation_id = "thread.loadOlder",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = OlderRequest,
    responses(StudioApiErrors, (status = 200, body = ChatBatch)))]
pub(crate) async fn older(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<OlderRequest>,
) -> Result<Json<ChatBatch>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .owner
            .reader
            .load_older(&request.before, request.demand)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/chat/completed",
    operation_id = "thread.readCompleted",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = CompletedRequest,
    responses(StudioApiErrors, (status = 200, body = CompletedEntry)))]
pub(crate) async fn completed(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<CompletedRequest>,
) -> Result<Json<CompletedEntry>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .owner
            .reader
            .read_completed(&request.record_id, request.demand)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/contents/manifest",
    operation_id = "thread.listContents",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = ManifestRequest,
    responses(StudioApiErrors, (status = 200, body = ContentManifestPage)))]
pub(crate) async fn manifest(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<ManifestRequest>,
) -> Result<Json<ContentManifestPage>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .owner
            .reader
            .list_contents(
                &request.item_id,
                request.continuation.as_deref(),
                request.demand,
            )
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/contents/read",
    operation_id = "thread.readContent",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = ContentRequest,
    responses(StudioApiErrors, (status = 200, body = ContentWindow)))]
pub(crate) async fn read(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<ContentRequest>,
) -> Result<Json<ContentWindow>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .owner
            .reader
            .read_content(&request.reference, request.range)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/current/page",
    operation_id = "thread.pageCurrent",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = CurrentRequest,
    responses(StudioApiErrors, (status = 200, body = CurrentCollectionPage)))]
pub(crate) async fn current(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<CurrentRequest>,
) -> Result<Json<CurrentCollectionPage>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .owner
            .reader
            .page_current(
                &request.reference,
                request.continuation.as_deref(),
                request.demand,
            )
            .await?,
    ))
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use anyhow::{Context, Result, ensure};
    use axum::extract::FromRequestParts;
    use axum::http::{HeaderValue, Request};
    use axum::response::IntoResponse;
    use futures::StreamExt;
    use pl_model::{
        config::{AccountConfig, AccountId, ModelRouteConfig},
        model::{ModelInfo, ModelTransportProfile},
        protocol::ProtocolEndpoint,
    };
    use pl_protocol::{ChatBatch, ChatPlacement, ChatScope};
    use pl_provider_fixture::FixtureServer;
    use pl_studio_runtime::{
        StudioHostKind, StudioRuntime, StudioRuntimeOptions,
        config::{ConfigPaths, ConfigStore, StudioConfig},
    };

    use super::*;
    use crate::routes::ApiQuery;
    use crate::sse::{ConversationQuery, thread_events};

    const DEADLINE: Duration = Duration::from_secs(10);
    const MODEL: &str = "server-fixture";
    const ACCOUNT: &str = "server-fixture";

    /// Both fixtures use the same explicit, credential-free loopback model route.
    fn configure(home: &std::path::Path, base_url: String) -> Result<()> {
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        let mut model = ModelInfo::compatible(MODEL);
        model
            .binding
            .set_transport(ModelTransportProfile::responses_http());
        model.capabilities.instruction_snapshot_overrides = true;
        model.base_instructions = "Respond using the finite fixture script.".into();
        config.models.accounts.insert(
            AccountId::new(ACCOUNT)?,
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible(ACCOUNT, base_url),
                vec![model],
            ),
        );
        let route = ModelRouteConfig {
            account_id: AccountId::new(ACCOUNT)?,
            model_id: MODEL.into(),
            effort: None,
        };
        for selected in config
            .models
            .routes
            .values_mut()
            .chain(config.mode_model_routes.values_mut())
        {
            *selected = route.clone();
        }
        ConfigStore::new(ConfigPaths::from_config_dir(home)).save(&config)?;
        Ok(())
    }

    async fn open(state: &AppState, thread_id: &str) -> Result<axum::response::Response> {
        let (mut parts, _) = Request::builder()
            .uri("/?maxItems=1&maxBytes=16384")
            .header("last-event-id", "timeline:obsolete:999")
            .body(())?
            .into_parts();
        let query = ApiQuery::<ConversationQuery>::from_request_parts(&mut parts, &())
            .await
            .map_err(|error| anyhow::anyhow!("{}", error.0))?;
        thread_events(State(state.clone()), Path(thread_id.into()), query)
            .await
            .map(IntoResponse::into_response)
            .map_err(|error| anyhow::anyhow!("{}", error.0))
    }

    fn assert_stale(result: Result<ReadLease, ApiError>) {
        let Err(error) = result else {
            panic!("stale transport capability was admitted");
        };
        assert_eq!(error.0.code, StudioErrorCode::Conflict);
        assert_eq!(error.0.reason(), Some("staleReadScope"));
    }

    /// Real runtime, database and reader; no duplicated fake Session or stream
    /// harness. TMPDIR can be set by the runner to keep the isolated home local.
    #[tokio::test]
    async fn original_sse_lease_queries_and_both_close_paths() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let project_path = temp.path().join("project");
        std::fs::create_dir(&project_path)?;
        let home = temp.path().join("home");
        // create_thread constructs an owner before any passive SSE is opened. Its
        // binding must therefore be valid, but this script accepts no model call.
        let provider = FixtureServer::start(vec![]).await?;
        let prepared: Result<StudioRuntime> = async {
            configure(&home, provider.base_url())?;
            let mut options = StudioRuntimeOptions::http_server(Some(home));
            options.host = StudioHostKind::Test;
            Box::pin(StudioRuntime::initialize(options))
                .await
                .map_err(Into::into)
        }
        .await;
        let runtime = match prepared {
            Ok(runtime) => runtime,
            Err(error) => {
                let provider = provider.finish().await;
                return Err(error.context(format!("provider cleanup: {provider:?}")));
            }
        };
        let mut states = Vec::new();
        let result = async {
            let project = runtime.open_project(&project_path).await?;
            let thread = runtime
                .create_thread(&project.id, "HTTP read scope")
                .await?;
            for disconnect in [false, true] {
                let state = AppState::new(runtime.clone(), CancellationToken::new());
                states.push(state.clone());
                let response = open(&state, &thread.id).await?;
                tokio::task::yield_now().await;
                assert_eq!(response.status(), axum::http::StatusCode::OK);
                let id = response.headers()[CONVERSATION_HEADER].to_str()?.to_owned();
                let mut headers = HeaderMap::new();
                headers.insert(CONVERSATION_HEADER, HeaderValue::from_str(&id)?);
                let lease = state
                    .conversations
                    .borrow(&thread.id, &headers, &state.shutdown)
                    .map_err(|error| anyhow::anyhow!("{}", error.0))?;
                assert_eq!(id, lease.owner.reader.subscription_id());
                assert_eq!(thread.id, lease.owner.reader.thread_id());

                assert_stale(state.conversations.borrow(
                    "another-thread",
                    &headers,
                    &state.shutdown,
                ));
                assert_stale(state.conversations.borrow(
                    &thread.id,
                    &HeaderMap::new(),
                    &state.shutdown,
                ));
                let mut duplicate = headers.clone();
                duplicate.append(CONVERSATION_HEADER, HeaderValue::from_str(&id)?);
                assert_stale(
                    state
                        .conversations
                        .borrow(&thread.id, &duplicate, &state.shutdown),
                );

                // Leave the response completely unpolled. The first queued frame
                // blocks all further feed receives, but an admitted query still
                // reaches the real reader and reports its own invalid cursor.
                let read = crate::conversation::older(
                    State(state.clone()),
                    Path(thread.id.clone()),
                    headers.clone(),
                    ApiJson(OlderRequest {
                        before: "not-an-original-cursor".into(),
                        demand: ReadDemand {
                            max_items: 4,
                            max_bytes: 16384,
                        },
                    }),
                );
                let error = tokio::time::timeout(DEADLINE, read)
                    .await?
                    .err()
                    .context("invalid cursor unexpectedly admitted")?;
                assert_eq!(error.0.code, StudioErrorCode::InvalidArgument);
                assert_ne!(error.0.reason(), Some("staleReadScope"));

                let mut body = response.into_body().into_data_stream();
                let mut wire = String::new();
                let batch = tokio::time::timeout(DEADLINE, async {
                    loop {
                        let bytes = body.next().await.context("SSE ended before Set")??;
                        wire.push_str(std::str::from_utf8(&bytes)?);
                        for event in wire.split("\n\n") {
                            if event.lines().any(|line| line == "event: chat") {
                                let data = event
                                    .lines()
                                    .find_map(|line| line.strip_prefix("data: "))
                                    .context("chat event lacks payload")?;
                                return Ok::<ChatBatch, anyhow::Error>(serde_json::from_str(data)?);
                            }
                        }
                    }
                })
                .await??;
                assert_eq!(batch.placement, ChatPlacement::Set);
                batch.validate_for(&ChatScope::conversation(None))?;

                if disconnect {
                    drop(body);
                    tokio::time::timeout(DEADLINE, lease.owner.cancel.cancelled()).await?;
                } else {
                    state.shutdown.cancel();
                }
                // Existing short reads are explicitly accounted for until their
                // lease is dropped; shutdown must wait, without permitting new ones.
                let shutdown = state.conversations.shutdown();
                tokio::pin!(shutdown);
                assert!(matches!(
                    futures::poll!(shutdown.as_mut()),
                    std::task::Poll::Pending
                ));
                assert_stale(
                    state
                        .conversations
                        .borrow(&thread.id, &headers, &state.shutdown),
                );
                let reader = lease.owner.reader.clone();
                drop(lease);
                tokio::time::timeout(DEADLINE, shutdown).await?;
                ensure!(state.conversations.0.lock().unwrap().readers.is_empty());
                let after = reader
                    .load_older(
                        "not-an-original-cursor",
                        ReadDemand {
                            max_items: 4,
                            max_bytes: 16384,
                        },
                    )
                    .await;
                ensure!(
                    after.is_err(),
                    "closed read owner retained usable resources"
                );
                assert_eq!(state.streams.available_permits(), crate::MAX_STREAMS);
            }
            Ok::<_, anyhow::Error>(())
        }
        .await;
        let mut cleanup = Ok(());
        for state in states {
            state.shutdown.cancel();
            if let Err(error) = tokio::time::timeout(DEADLINE, state.conversations.shutdown()).await
            {
                cleanup = Err(anyhow::Error::from(error));
            }
        }
        let shutdown = runtime.shutdown_runtime().await;
        let provider = provider.finish().await;
        result.with_context(|| {
            format!(
                "HTTP owners cleanup: {cleanup:?}; runtime: {shutdown:?}; provider: {provider:?}"
            )
        })?;
        cleanup?;
        shutdown?;
        provider?;
        Ok(())
    }

    mod journey {
        //! Real loopback routes and the existing wire provider. No user credentials or
        //! execution resources outside the temporary project are used.
        use std::{collections::HashSet, pin::Pin};

        use anyhow::{Context, Result, bail, ensure};
        use axum::body::Bytes;
        use axum::response::IntoResponse;
        use futures::{Stream, StreamExt};
        use pl_protocol::{
            ChatAtomKind, ChatBatch, ChatPlacement, ChatScope, CompletedEntry, ContentManifestPage,
            ContentOwner, ContentTarget, ContentWindow, PayloadData, ReadDemand,
            ThreadNotification, ThreadSubscriptionUpdate, ThreadWorkspaceMode, Turn, TurnState,
            studio::{
                CreateThreadRequest, NewThreadModelRoute, StudioError, StudioPromptInput,
                SubmitPromptRequest,
            },
        };
        use pl_provider_fixture::{
            FixtureServer, Protocol, ReplyStage, Step, responses_authoritative_final,
            responses_reasoning_text, responses_text, responses_text_chunks,
        };
        use pl_studio_runtime::{StudioHostKind, StudioRuntime, StudioRuntimeOptions};
        use serde::{Serialize, de::DeserializeOwned};
        use serde_json::{Value, json};
        use tokio::{net::TcpListener, task::JoinHandle};
        use tokio_util::sync::CancellationToken;

        use super::super::{CONVERSATION_HEADER, ReadLease};
        use super::{ACCOUNT, AppState, DEADLINE, MODEL, configure};

        const FIRST: &str = "http-first";
        const NEXT: &str = "http-next";
        const SHUTDOWN: &str = "http-shutdown";
        const EXECUTION_HISTORY_OBSERVATION_BYTES: usize = 4 * 1024 * 1024;
        const EXECUTION_HISTORY_PAGE_LIMIT: usize = 64;
        const EXECUTION_HISTORY_MAX_PAGES: usize = 32;
        const EXECUTION_HISTORY_POLL: std::time::Duration = std::time::Duration::from_millis(25);

        fn demand(items: u32) -> ReadDemand {
            ReadDemand {
                max_items: items,
                max_bytes: 256 * 1024,
            }
        }

        /// 原件查询的真实 parent carries Core's encoded `ChatKey("turn", id)`.
        fn turn_parent_key(turn_id: &str) -> String {
            format!("{}:turn{turn_id}", "turn".len())
        }

        struct Environment {
            _temp: tempfile::TempDir,
            runtime: StudioRuntime,
            provider: FixtureServer,
            state: AppState,
            base: String,
            server: JoinHandle<std::io::Result<()>>,
            client: reqwest::Client,
            project: String,
        }

        impl Environment {
            async fn start(steps: Vec<Step>) -> Result<Self> {
                let temp = tempfile::tempdir()?;
                let project = temp.path().join("project");
                std::fs::create_dir(&project)?;
                let home = temp.path().join("home");
                let provider = FixtureServer::start(steps).await?;
                let prepared: Result<StudioRuntime> = async {
                    configure(&home, provider.base_url())?;
                    let mut options = StudioRuntimeOptions::http_server(Some(home));
                    options.host = StudioHostKind::Test;
                    Box::pin(StudioRuntime::initialize(options))
                        .await
                        .map_err(Into::into)
                }
                .await;
                let runtime = match prepared {
                    Ok(runtime) => runtime,
                    Err(error) => {
                        let cleanup = provider.finish().await;
                        return Err(error.context(format!("provider cleanup: {cleanup:?}")));
                    }
                };
                let setup = async {
                    let project = runtime.open_project(project).await?.id;
                    let listener = TcpListener::bind("127.0.0.1:0").await?;
                    let base = format!("http://{}", listener.local_addr()?);
                    let client = reqwest::Client::builder().no_proxy().build()?;
                    Ok::<_, anyhow::Error>((project, listener, base, client))
                }
                .await;
                let (project, listener, base, client) = match setup {
                    Ok(setup) => setup,
                    Err(error) => {
                        let shutdown = runtime.shutdown_runtime().await;
                        let fixture = provider.finish().await;
                        return Err(error.context(format!(
                            "cleanup: runtime={shutdown:?}; provider={fixture:?}"
                        )));
                    }
                };
                let state = AppState::new(runtime.clone(), CancellationToken::new());
                let app = crate::router(state.clone());
                let cancel = state.shutdown.clone();
                let server = tokio::spawn(async move {
                    axum::serve(listener, app)
                        .with_graceful_shutdown(cancel.cancelled_owned())
                        .await
                });
                Ok(Self {
                    _temp: temp,
                    runtime,
                    provider,
                    state,
                    base,
                    server,
                    client,
                    project,
                })
            }

            async fn finish(self, result: Result<()>) -> Result<()> {
                self.state.shutdown.cancel();
                let owners =
                    tokio::time::timeout(DEADLINE, self.state.conversations.shutdown()).await;
                let mut server = self.server;
                let socket = match tokio::time::timeout(DEADLINE, &mut server).await {
                    Ok(Ok(result)) => result.map_err(anyhow::Error::from),
                    Ok(Err(error)) => Err(error.into()),
                    Err(error) => {
                        // Reap even a failing test's stuck connection rather than
                        // leaking a listener into the next test.
                        server.abort();
                        let _ = server.await;
                        Err(error.into())
                    }
                };
                let runtime = self.runtime.shutdown_runtime().await;
                let provider = self.provider.finish().await;
                result.with_context(|| format!(
            "cleanup: owners={owners:?}; socket={socket:?}; runtime={runtime:?}; provider={provider:?}"
        ))?;
                owners.context("HTTP owner join")?;
                socket?;
                runtime?;
                provider?;
                ensure!(self.state.streams.available_permits() == crate::MAX_STREAMS);
                Ok(())
            }

            async fn create(&self) -> Result<String> {
                let reply = Box::pin(self.runtime.create_thread_command(
                    self.project.clone(),
                    CreateThreadRequest {
                        title: Some("HTTP conversation journey".into()),
                        input: input(FIRST),
                        mode: pl_protocol::ThreadModeId::simple().to_string(),
                        route: NewThreadModelRoute {
                            account_id: ACCOUNT.into(),
                            model_id: MODEL.into(),
                            effort: None,
                        },
                        delegation_mode: Some(pl_protocol::DelegationMode::Profile),
                        delegation_preference: None,
                        workspace_mode: ThreadWorkspaceMode::Local,
                    },
                    None,
                ))
                .await?;
                Ok(reply.thread.id)
            }

            async fn submit(&self, thread: &str, prompt: &str) -> Result<()> {
                let snapshot = self.runtime.thread_snapshot(thread).await?;
                self.runtime
                    .submit_prompt_command(
                        thread.into(),
                        SubmitPromptRequest {
                            input: input(prompt),
                            expected_model_route_revision: snapshot
                                .model_route
                                .as_ref()
                                .context("model route")?
                                .revision,
                        },
                    )
                    .await?;
                Ok(())
            }

            async fn open(
                &self,
                thread: &str,
                parent: Option<&str>,
                items: u32,
            ) -> Result<(String, SseBody)> {
                let scope = match parent {
                    Some(parent_id) => ChatScope::conversation(Some(parent_id.to_owned())),
                    None => ChatScope::conversation(None),
                };
                self.open_scope(thread, scope, items).await
            }

            async fn open_scope(
                &self,
                thread: &str,
                scope: ChatScope,
                items: u32,
            ) -> Result<(String, SseBody)> {
                let mut url =
                    url::Url::parse(&format!("{}/api/v1/threads/{thread}/events", self.base))?;
                {
                    let mut query = url.query_pairs_mut();
                    query.append_pair("maxItems", &items.to_string());
                    query.append_pair("maxBytes", &demand(items).max_bytes.to_string());
                    query.append_pair("queryClass", &serde_json::to_string(&scope.query_class)?);
                    if let Some(parent) = scope.parent_id {
                        query.append_pair("parentId", &parent);
                    }
                }
                let request = self
                    .client
                    .get(url)
                    .header("last-event-id", "timeline:obsolete:999");
                let response = tokio::time::timeout(DEADLINE, request.send())
                    .await??
                    .error_for_status()?;
                let id = response
                    .headers()
                    .get(CONVERSATION_HEADER)
                    .context("missing original capability")?
                    .to_str()?
                    .to_owned();
                Ok((id, SseBody::network(response)))
            }

            async fn post(
                &self,
                thread: &str,
                capability: &str,
                path: &str,
                request: &impl Serialize,
            ) -> Result<reqwest::Response> {
                tokio::time::timeout(
                    DEADLINE,
                    self.client
                        .post(format!("{}/api/v1/threads/{thread}/{path}", self.base))
                        .header(CONVERSATION_HEADER, capability)
                        .json(request)
                        .send(),
                )
                .await?
                .map_err(Into::into)
            }

            async fn query<T: DeserializeOwned>(
                &self,
                thread: &str,
                capability: &str,
                path: &str,
                request: &impl Serialize,
            ) -> Result<T> {
                let response = self.post(thread, capability, path, request).await?;
                let status = response.status();
                let bytes = response.bytes().await?;
                ensure!(
                    status.is_success(),
                    "{path}: {status}: {}",
                    String::from_utf8_lossy(&bytes)
                );
                serde_json::from_slice(&bytes).map_err(Into::into)
            }

            fn lease(&self, thread: &str, id: &str) -> Result<ReadLease> {
                let mut headers = axum::http::HeaderMap::new();
                headers.insert(CONVERSATION_HEADER, id.parse()?);
                self.state
                    .conversations
                    .borrow(thread, &headers, &self.state.shutdown)
                    .map_err(|error| anyhow::anyhow!("{}", error.0))
            }
        }

        fn input(text: &str) -> StudioPromptInput {
            StudioPromptInput {
                input_id: format!("input-{text}"),
                text: text.into(),
                attachment_draft_ids: vec![],
            }
        }

        type ByteStream = Pin<Box<dyn Stream<Item = Result<Bytes>> + Send>>;

        struct SseBody {
            bytes: ByteStream,
            buffered: Vec<u8>,
        }

        impl SseBody {
            fn network(response: reqwest::Response) -> Self {
                Self {
                    bytes: Box::pin(
                        response
                            .bytes_stream()
                            .map(|result| result.map_err(Into::into)),
                    ),
                    buffered: vec![],
                }
            }

            fn handler(body: axum::body::Body) -> Self {
                Self {
                    bytes: Box::pin(
                        body.into_data_stream()
                            .map(|result| result.map_err(Into::into)),
                    ),
                    buffered: vec![],
                }
            }

            async fn event(&mut self) -> Result<Option<(String, Value)>> {
                tokio::time::timeout(DEADLINE, async {
                    loop {
                        if let Some(end) =
                            self.buffered.windows(2).position(|bytes| bytes == b"\n\n")
                        {
                            let frame = self.buffered.drain(..end + 2).collect::<Vec<_>>();
                            let text = std::str::from_utf8(&frame)?;
                            let event = text.lines().find_map(|line| line.strip_prefix("event: "));
                            let data = text.lines().find_map(|line| line.strip_prefix("data: "));
                            if let (Some(event), Some(data)) = (event, data) {
                                return Ok(Some((event.into(), serde_json::from_str(data)?)));
                            }
                            continue; // Comment heartbeats carry no application data.
                        }
                        let Some(bytes) = self.bytes.next().await else {
                            ensure!(self.buffered.is_empty(), "truncated SSE frame");
                            return Ok(None);
                        };
                        self.buffered.extend(bytes?);
                        ensure!(
                            self.buffered.len() <= 2 * 256 * 1024,
                            "unbounded SSE test buffer"
                        );
                    }
                })
                .await
                .context("SSE event deadline")?
            }

            async fn chat(&mut self) -> Result<ChatBatch> {
                loop {
                    let (event, value) = self
                        .event()
                        .await
                        .context("waiting for SSE Chat event")?
                        .context("SSE ended before Chat")?;
                    if event == "chat" {
                        return serde_json::from_value(value).map_err(Into::into);
                    }
                    ensure!(
                        event != "error" && event != "closed",
                        "unexpected {event}: {value}"
                    );
                }
            }

            async fn activity(&mut self) -> Result<pl_protocol::ActivitySnapshot> {
                loop {
                    let (event, value) = self
                        .event()
                        .await
                        .context("waiting for SSE Activity event")?
                        .context("SSE ended before Activity")?;
                    if event == "activity" {
                        return serde_json::from_value(value).map_err(Into::into);
                    }
                    ensure!(
                        event != "error" && event != "closed",
                        "unexpected {event}: {value}"
                    );
                }
            }

            async fn window(&mut self) -> Result<ContentWindow> {
                let (event, value) = self
                    .event()
                    .await
                    .context("waiting for SSE content window")?
                    .context("watch ended before window")?;
                ensure!(
                    event == "content",
                    "unexpected watch event {event}: {value}"
                );
                serde_json::from_value(value).map_err(Into::into)
            }

            async fn end(&mut self) -> Result<()> {
                while let Some((event, value)) = self.event().await? {
                    ensure!(
                        event == "closed",
                        "unexpected terminal watch event {event}: {value}"
                    );
                }
                Ok(())
            }
        }

        async fn complete(
            runtime: &StudioRuntime,
            thread: &str,
            stage: &ReplyStage,
            prompt: &str,
        ) -> Result<Turn> {
            // Subscribe before releasing the provider barrier: a fast completion must
            // not be recovered by guessing from Main items or a later snapshot.
            let mut events = runtime.open_conversation_state_feed(thread).await?;
            stage.release();
            tokio::time::timeout(DEADLINE, async {
                while let Some(update) = events.recv().await? {
                    if let ThreadSubscriptionUpdate::Notification { notification } = update
                        && let ThreadNotification::TurnCompleted { turn } =
                            notification.notification
                        && turn.input_id.as_deref() == Some(&format!("input-{prompt}"))
                    {
                        ensure!(
                            turn.thread_id == thread,
                            "completion belongs to another Thread"
                        );
                        ensure!(
                            !turn.id.is_empty(),
                            "completion omitted the actual Turn identity"
                        );
                        ensure!(
                            matches!(&turn.state, TurnState::Completed(_)),
                            "fixture input did not complete successfully: {:?}",
                            turn.state
                        );
                        events.request_close();
                        events.close().await?;
                        return Ok(turn);
                    }
                }
                bail!("Thread ended before completed fixture input")
            })
            .await?
        }

        async fn payload(
            env: &Environment,
            thread: &str,
            capability: &str,
            entry: &CompletedEntry,
        ) -> Result<Value> {
            let payload = entry
                .atom
                .payload
                .as_ref()
                .context("completed atom omitted its frozen payload")?;
            decode_payload(env, thread, capability, payload).await
        }

        async fn item_payload(
            env: &Environment,
            thread: &str,
            capability: &str,
            item: &CompletedEntry,
        ) -> Result<Value> {
            decode_payload(
                env,
                thread,
                capability,
                item.atom
                    .payload
                    .as_ref()
                    .context("completed entry omitted its original payload")?,
            )
            .await
        }

        async fn decode_payload(
            env: &Environment,
            thread: &str,
            capability: &str,
            payload: &PayloadData,
        ) -> Result<Value> {
            let bytes = match payload {
                PayloadData::Inline { bytes } => bytes.clone(),
                PayloadData::Deferred {
                    reference,
                    byte_length,
                } => {
                    let mut bytes = Vec::new();
                    while (bytes.len() as u64) < *byte_length {
                        let window: ContentWindow = env.query(thread, capability, "contents/read", &json!({
                    "reference": reference, "range": {"offset": bytes.len(), "maxBytes": 16384},
                })).await?;
                        ensure!(
                            window.sealed
                                && window.offset == bytes.len() as u64
                                && !window.bytes.is_empty()
                        );
                        bytes.extend(window.bytes);
                    }
                    ensure!(bytes.len() as u64 == *byte_length);
                    bytes
                }
            };
            let value: Value = serde_json::from_slice(&bytes)?;
            ensure!(value["contract"] == "anywork.chat/1");
            Ok(value)
        }

        async fn all_entries(
            env: &Environment,
            thread: &str,
            capability: &str,
            first: ChatBatch,
        ) -> Result<Vec<CompletedEntry>> {
            let ceiling = first.through_seq;
            ensure!(first.from_seq.is_none());
            let mut entries = first.entries;
            let mut before = first.before;
            for _ in 0..32 {
                let Some(cursor) = before else {
                    return Ok(entries);
                };
                let batch: ChatBatch = env
                    .query(
                        thread,
                        capability,
                        "chat/older",
                        &json!({"before": cursor, "demand": demand(3)}),
                    )
                    .await?;
                ensure!(batch.placement == ChatPlacement::Prepend);
                ensure!(
                    batch.from_seq.is_none() && batch.through_seq == ceiling,
                    "Prepend changed its original completion ceiling"
                );
                ensure!(
                    batch.before.as_ref() != Some(&cursor),
                    "nonadvancing cursor"
                );
                entries.splice(0..0, batch.entries);
                before = batch.before;
            }
            bail!("fixture history did not reach EOF within its finite budget")
        }

        async fn all_history(
            env: &Environment,
            thread: &str,
            capability: &str,
            first: ChatBatch,
        ) -> Result<Vec<CompletedEntry>> {
            let entries = all_entries(env, thread, capability, first).await?;
            let ids = entries
                .iter()
                .map(|entry| &entry.record_id)
                .collect::<HashSet<_>>();
            ensure!(
                ids.len() == entries.len(),
                "duplicate completion record identity"
            );
            Ok(entries)
        }

        async fn all_items(
            env: &Environment,
            thread: &str,
            capability: &str,
            first: ChatBatch,
        ) -> Result<Vec<CompletedEntry>> {
            let entries = all_entries(env, thread, capability, first).await?;
            let items = entries;
            let ids = items
                .iter()
                .map(|item| &item.record_id)
                .collect::<HashSet<_>>();
            ensure!(
                ids.len() == items.len(),
                "duplicate completed record identity"
            );
            ensure!(
                items
                    .windows(2)
                    .all(|pair| pair[0].completion_seq < pair[1].completion_seq)
            );
            Ok(items)
        }

        async fn assert_execution_history_members(
            runtime: &StudioRuntime,
            thread: &str,
            turn_id: &str,
        ) -> Result<()> {
            let deadline = std::time::Instant::now() + DEADLINE;
            let mut remaining_bytes = EXECUTION_HISTORY_OBSERVATION_BYTES;
            let mut latest = (0usize, 0usize, 0usize);
            loop {
                ensure!(
                    std::time::Instant::now() < deadline,
                    "execution-history save deadline elapsed for Turn {turn_id}: \
             matching_turns={}, thinking={}, inference={}, remaining_bytes={remaining_bytes}",
                    latest.0,
                    latest.1,
                    latest.2
                );
                let mut cursor = None;
                let mut matched_turns = 0;
                let mut thinking = 0;
                let mut inference = 0;
                let mut reached_eof = false;
                for _ in 0..EXECUTION_HISTORY_MAX_PAGES {
                    let page = match tokio::time::timeout_at(
                        tokio::time::Instant::from_std(deadline),
                        runtime.list_thread_turns(
                            thread,
                            cursor.as_deref(),
                            EXECUTION_HISTORY_PAGE_LIMIT,
                        ),
                    )
                    .await
                    {
                        Ok(result) => result?,
                        Err(_) => {
                            bail!(
                                "execution-history query deadline elapsed for Turn {turn_id}: \
                         matching_turns={}, thinking={}, inference={}, remaining_bytes={remaining_bytes}",
                                latest.0,
                                latest.1,
                                latest.2
                            )
                        }
                    };
                    let encoded_bytes = serde_json::to_vec(&page)?.len();
                    remaining_bytes = remaining_bytes
                .checked_sub(encoded_bytes)
                .with_context(|| {
                    format!(
                        "execution-history observation byte budget exhausted for Turn {turn_id}: \
                     matching_turns={matched_turns}, thinking={thinking}, inference={inference}"
                    )
                })?;
                    for history in page
                        .turns
                        .iter()
                        .filter(|history| history.turn.id == turn_id)
                    {
                        matched_turns += 1;
                        for item in &history.items {
                            match item.atom.kind {
                                ChatAtomKind::Reasoning => thinking += 1,
                                ChatAtomKind::Inference => inference += 1,
                                _ => {}
                            }
                        }
                    }
                    latest = (matched_turns, thinking, inference);
                    let next = page.next_cursor;
                    ensure!(
                        next.is_none() || next != cursor,
                        "execution-history cursor did not advance for Turn {turn_id}"
                    );
                    cursor = next;
                    if cursor.is_none() {
                        reached_eof = true;
                        break;
                    }
                }
                ensure!(
                    reached_eof,
                    "execution-history page budget exceeded for Turn {turn_id}: \
             matching_turns={matched_turns}, thinking={thinking}, inference={inference}"
                );
                latest = (matched_turns, thinking, inference);
                if matched_turns == 1 && thinking == 1 && inference == 1 {
                    return Ok(());
                }
                let remaining = deadline.saturating_duration_since(std::time::Instant::now());
                ensure!(
                    !remaining.is_zero() && remaining_bytes > 0,
                    "execution-history save deadline/resource budget exhausted for Turn {turn_id}: \
             matching_turns={matched_turns}, thinking={thinking}, inference={inference}, \
             remaining_bytes={remaining_bytes}"
                );
                tokio::time::sleep(EXECUTION_HISTORY_POLL.min(remaining)).await;
            }
        }

        async fn activity_with_response(
            body: &mut SseBody,
        ) -> Result<pl_protocol::ActivitySnapshot> {
            for _ in 0..64 {
                let activity = body.activity().await?;
                if activity.entries.iter().any(|entry| {
                    entry.atom.kind == ChatAtomKind::Text
                        && entry.atom.contents.iter().any(|content| {
                            matches!(content.role, pl_protocol::ChatContentRole::Body)
                        })
                }) {
                    return Ok(activity);
                }
            }
            bail!("fixture response did not appear in Activity")
        }

        #[tokio::test]
        async fn real_http_nonempty_history_independent_queries_and_watch_lifecycle() -> Result<()>
        {
            let first_stage = ReplyStage::new();
            let growing = ReplyStage::new();
            let sealing = ReplyStage::new();
            let stopping = ReplyStage::new();
            let old_text = "# 历史正文📖\n\n- **已完成** `代码`\n\n> 原始 Markdown\n\n".repeat(600);
            let frames = responses_reasoning_text(
                &["private activity member"],
                &[&old_text],
                "first-response",
                MODEL,
            );
            let first_delta = frames
                .iter()
                .position(|frame| frame["type"] == "response.output_text.delta")
                .context("first response delta")?
                + 1;
            let live_frames = responses_text_chunks(&["live α", " +β"], "next-response", MODEL);
            let corrected = "authoritative corrected response";
            let (_, authoritative) =
                responses_authoritative_final("live α +β", corrected, "next-response", MODEL);
            let stop_frames = responses_text(
                "still executing while HTTP closes",
                "shutdown-response",
                MODEL,
            );
            let env = Environment::start(vec![
                Step::prompt(
                    Protocol::ResponsesHttp,
                    FIRST,
                    0,
                    first_stage.gated(
                        frames[..first_delta].to_vec(),
                        frames[first_delta..].to_vec(),
                    ),
                ),
                Step::prompt(
                    Protocol::ResponsesHttp,
                    NEXT,
                    1,
                    pl_provider_fixture::ReplyStage::staged(
                        vec![
                            live_frames[..3].to_vec(),
                            live_frames[3..4].to_vec(),
                            authoritative,
                        ],
                        &[&growing, &sealing],
                    ),
                ),
                Step::prompt(
                    Protocol::ResponsesHttp,
                    SHUTDOWN,
                    2,
                    stopping.gated(stop_frames[..3].to_vec(), stop_frames[3..].to_vec()),
                ),
            ])
            .await?;
            let result = async {
        let thread = env.create().await?;
        tokio::time::timeout(DEADLINE, first_stage.wait_reached()).await?;
        // Leave the content handler body completely unpolled: its first bounded
        // send window will fill. State must still reach its authoritative final
        // sample without draining that window or opening a second content feed.
        let paused_content = super::open(&env.state, &thread).await?;
        let state_response = crate::sse::thread_state_events(
            axum::extract::State(env.state.clone()),
            axum::extract::Path(thread.clone()),
        )
        .await
        .map_err(|error| anyhow::anyhow!("{}", error.0))?
        .into_response();
        ensure!(!state_response.headers().contains_key(CONVERSATION_HEADER));
        let mut independent_state = SseBody::handler(state_response.into_body());
        let (kind, value) = independent_state.event().await?.context("State baseline")?;
        ensure!(kind == "snapshot");
        let baseline: ThreadSubscriptionUpdate = serde_json::from_value(value)?;
        ensure!(matches!(baseline, ThreadSubscriptionUpdate::Snapshot { .. }));
        let first_turn = complete(&env.runtime, &thread, &first_stage, FIRST).await?;
        let mut saw_terminal = false;
        let mut saw_final_usage = false;
        while !saw_terminal || !saw_final_usage {
            let (kind, value) = independent_state.event().await?.context("State update")?;
            ensure!(kind == "notification", "unexpected State event {kind}: {value}");
            let update: ThreadSubscriptionUpdate = serde_json::from_value(value)?;
            if let ThreadSubscriptionUpdate::Notification { notification } = update {
                match notification.notification {
                    ThreadNotification::TurnCompleted { turn } => {
                        saw_terminal |= turn.id == first_turn.id;
                    }
                    ThreadNotification::ThreadRuntimeUpdated { runtime, .. } => {
                        saw_final_usage |= runtime.live_usage.is_none()
                            && runtime.turn_completion_tokens > 0;
                    }
                    _ => {}
                }
            }
        }
        drop(independent_state);
        drop(paused_content);
        let turn_id = first_turn.id.clone();
        let parent = turn_parent_key(&turn_id);
        let (capability, mut main) = env.open(&thread, None, 1).await?;
        let first = main.chat().await?;
        let first_items = first.entries.len();
        ensure!(first.from_seq.is_none());
        ensure!(first.placement == ChatPlacement::Set && first_items > 0);
        first.validate_for(&ChatScope::conversation(None))?;
        let original = env.lease(&thread, &capability)?;
        ensure!(original.owner.reader.subscription_id() == capability);
        drop(original);
        let history = all_items(&env, &thread, &capability, first.clone()).await?;
        ensure!(
            history.len() > first_items,
            "older never returned real completed history"
        );
        let mut completed_body = None;
        let mut main_thinking = 0;
        let mut main_inference = 0;
        for message in &history {
            ensure!(message.atom.source_state.is_none());
            let value = item_payload(&env, &thread, &capability, message).await?;
            match value["type"].as_str() {
                Some("thinking") => main_thinking += 1,
                Some("inference") => main_inference += 1,
                _ => {}
            }
            if message.atom.kind == ChatAtomKind::Text {
                ensure!(
                    value["type"] == "text"
                        && message.atom.turn_id.as_deref() == Some(turn_id.as_str())
                        && value["turnId"].as_str() == Some(turn_id.as_str()),
                    "Main text metadata/payload disagrees with the completed business Turn"
                );
            }
            let completion_item_id = message.record_id.as_str();
            let manifest: ContentManifestPage = env
                .query(
                    &thread,
                    &capability,
                    "contents/manifest",
                    &json!({
                        "itemId": completion_item_id,
                        "continuation": null,
                        "demand": demand(8)
                    }),
                )
                .await?;
            if value["type"] == "text"
                && let Some(entry) = manifest.entries.first()
            {
                completed_body = Some(entry.reference.clone());
            }
        }
        ensure!(
            main_thinking == 1 && main_inference == 0,
            "Main and explicit member scopes must expose exactly one real thinking member and no copied inference: \
             thinking={main_thinking}, inference={main_inference}"
        );
        let reference = completed_body.context("real completed response manifest")?;
        let window: ContentWindow = env
            .query(
                &thread,
                &capability,
                "contents/read",
                &json!({
                    "reference": reference, "range": {"offset": 3, "maxBytes": 31},
                }),
            )
            .await?;
        ensure!(window.sealed && window.offset == 3 && window.bytes == old_text.as_bytes()[3..34]);
        ensure!(window.available_through == old_text.len() as u64);
        assert_execution_history_members(&env.runtime, &thread, &turn_id).await?;
        let (child_cap, mut children) = env.open(&thread, Some(&parent), 1).await?;
        let child_set = children.chat().await?;
        ensure!(child_set.placement == ChatPlacement::Set);
        let child_messages = all_history(&env, &thread, &child_cap, child_set).await?;
        ensure!(
            !child_messages.is_empty(),
            "Children omitted this Turn's real Main-member subset"
        );
        let main_member_ids = history.iter().map(|item| item.record_id.clone())

            .collect::<HashSet<_>>();
        let main_ids = history.iter().map(|item| item.record_id.clone()).collect::<HashSet<_>>();
        let main_completion_ids = history.iter().filter_map(|item| item.atom.completion_item_id.clone())

            .collect::<HashSet<_>>();
        let mut thinking = 0;
        let mut inferences = 0;
        let mut turn_receipts = 0;
        for message in &child_messages {
            let value = payload(&env, &thread, &child_cap, message).await?;
            ensure!(
                message.atom.turn_id.as_deref() == Some(turn_id.as_str()),
                "Children returned an atom whose metadata belongs to another Turn"
            );
            if message.atom.kind != ChatAtomKind::TurnReceipt {
                ensure!(
                    main_member_ids.contains(&message.record_id)
                    || message.atom
                        .completion_item_id
                        .as_ref()
                        .is_some_and(|id| main_completion_ids.contains(id)),
                    "Children content was not owned by a Main item or its explicit member scope"
                );
            }
            ensure!(
                value["turnId"].as_str() == Some(turn_id.as_str()),
                "Children payload belongs to another Turn: {}",
                value["turnId"]
            );
            match value["type"].as_str() {
                Some("thinking") => {
                    thinking += 1;
                    ensure!(
                        value["data"]["outcome"]["kind"] == "completed",
                        "Children Thinking member is not complete"
                    );
                }
                Some("inference") => inferences += 1,
                Some("turn") => {
                    turn_receipts += 1;
                    ensure!(
                        message.atom.kind == ChatAtomKind::TurnReceipt
                            && matches!(&message.atom.lifecycle, pl_protocol::ChatAtomLifecycle::Terminal {
                                outcome: pl_protocol::ChatTerminalOutcome::Completed, ..
                            })
                            && value["data"]["inputId"].as_str() == first_turn.input_id.as_deref()
                            && value["data"]["outcome"]["kind"] == "completed",
                        "Children TurnReceipt disagrees with the successful typed completion"
                    );
                }
                Some(
                    "tool" | "text" | "raw" | "agent" | "skill" | "file" | "contextCompaction"
                    | "plan",
                ) => {}
                kind => bail!("unexpected member from this Turn's Children: {kind:?}"),
            }
        }
        ensure!(
            thinking == 1 && inferences == 0 && turn_receipts == 1,
            "Children must retain the real thinking member and business TurnReceipt, not an inference copy: \
             thinking={thinking}, inference={inferences}, receipts={turn_receipts}"
        );
        env.submit(&thread, NEXT).await?;
        tokio::time::timeout(DEADLINE, growing.wait_reached()).await?;
        let activity = activity_with_response(&mut main).await?;
        ensure!(activity.execution_present);
        let live_entry = activity
            .entries
            .iter()
            .find(|entry| {
                entry.atom.kind == ChatAtomKind::Text
                    && matches!(&entry.atom.lifecycle, pl_protocol::ChatAtomLifecycle::Active { .. })
            })
            .context("Activity omitted live text part")?;
        let response_ref = live_entry.atom.contents.iter()
            .find(|content| content.role == pl_protocol::ChatContentRole::Body)
            .context("Activity omitted live Body content reference")?
            .reference
            .clone();
        let live_item_id = live_entry.atom.id.clone();
        let live_turn_id = live_entry.atom.turn_id.clone().context("Activity omitted Turn identity")?;

        // Use a real handler body here to prove server backpressure; a TCP
        // receive buffer could keep draining a supposedly paused socket client.
        let response = super::open(&env.state, &thread).await?;
        let paused_cap = response.headers()[CONVERSATION_HEADER].to_str()?.to_owned();
        let mut paused = SseBody::handler(response.into_body());
        let paused_first = paused.chat().await?;
        ensure!(paused_first.placement == ChatPlacement::Set && paused_first.before.is_some());
        let paused_activity = paused.activity().await?;
        ensure!(paused_activity.execution_present && !paused_activity.entries.is_empty());
        let paused_text = paused_activity.entries.iter().find(|entry| {
            entry.atom.kind == ChatAtomKind::Text
                && entry.atom.contents.iter().any(|content| content.reference == response_ref)
        }).context("Activity omitted the live text part with its Body reference")?;
        ensure!(paused_text.atom.turn_id.as_deref() == Some(live_turn_id.as_str()));
        let older: ChatBatch = env
            .query(
                &thread,
                &paused_cap,
                "chat/older",
                &json!({
                    "before": paused_first.before, "demand": demand(8),
                }),
            )
            .await?;
        ensure!(
            older.placement == ChatPlacement::Prepend
                && !older.entries.is_empty()
        );
        let active_id = match &response_ref.target {
            ContentTarget::Body {
                owner: ContentOwner::Item { item_id },
                ..
            } => item_id.clone(),
            _ => bail!("active response did not retain Item ownership"),
        };
        let manifest: ContentManifestPage = env
            .query(
                &thread,
                &paused_cap,
                "contents/manifest",
                &json!({
                    "itemId": active_id, "continuation": null, "demand": demand(8),
                }),
            )
            .await?;
        ensure!(
            manifest
                .entries
                .iter()
                .any(|entry| entry.reference == response_ref)
        );
        let request = json!({"reference": response_ref, "range": {"offset": 0, "maxBytes": 128}});
        let live: ContentWindow = env
            .query(&thread, &paused_cap, "contents/read", &request)
            .await?;
        ensure!(!live.sealed && live.bytes == "live α".as_bytes());
        let watch = env
            .post(&thread, &paused_cap, "contents/watch", &request)
            .await?
            .error_for_status()?;
        let mut watch = SseBody::network(watch);
        ensure!(watch.window().await? == live);
        // Closing one watch leaves the original lease and execution alive.
        let detached = env
            .post(&thread, &paused_cap, "contents/watch", &request)
            .await?
            .error_for_status()?;
        let mut detached = SseBody::network(detached);
        ensure!(detached.window().await? == live);
        drop(detached);
        let again: ContentWindow = env
            .query(&thread, &paused_cap, "contents/read", &request)
            .await?;
        ensure!(again == live);

        growing.release();
        tokio::time::timeout(DEADLINE, sealing.wait_reached()).await?;
        let updated = watch.window().await?;
        ensure!(!updated.sealed && updated.bytes == "live α +β".as_bytes());
        ensure!(
            updated.generation == live.generation
                && updated.available_through > live.available_through
        );
        // The paused SSE body has not been polled through these valid POSTs.
        let still_independent: ContentWindow = env
            .query(&thread, &paused_cap, "contents/read", &request)
            .await?;
        ensure!(still_independent == updated);
        let next_completed_turn = complete(&env.runtime, &thread, &sealing, NEXT).await?;
        ensure!(
            live_turn_id == next_completed_turn.id,
            "live text and typed completion belong to different Turns"
        );
        let mut sealed = watch.window().await?;
        for _ in 0..8 {
            if sealed.sealed {
                break;
            }
            sealed = watch.window().await?;
        }
        ensure!(
            sealed.sealed
                && sealed.bytes == corrected.as_bytes()
                && sealed.generation != live.generation
        );
        watch.end().await?;
        // Completion appends the same immutable response record, then retires its Activity identity.
        let mut appended = HashSet::new();
        let mut appended_completion_ids = HashSet::new();
        let mut response_seen = false;
        let mut retired = false;
        for _ in 0..64 {
            let batch = main
                .chat()
                .await
                .context("waiting for Main completion Append after NEXT")?;
            ensure!(batch.placement == ChatPlacement::Append && batch.before.is_none());
            let checked_through = batch.through_seq;
            for entry in &batch.entries {
                ensure!(!main_ids.contains(&entry.record_id)
                    && appended.insert(entry.record_id.clone()));
                if let Some(completion_item_id) = &entry.atom.completion_item_id {
                    ensure!(appended_completion_ids.insert(completion_item_id.clone()));
                }
                if entry.record_id == active_id {
                    ensure!(
                        entry.atom.id == live_item_id
                            && entry.atom.turn_id.as_deref() == Some(next_completed_turn.id.as_str())
                            && entry.atom.kind == ChatAtomKind::Text
                            && entry.atom.completion_seq == Some(entry.completion_seq),
                        "completed text changed its activity/content/Turn identity"
                    );
                    response_seen = true;
                }
            }
            let current = main.activity().await?;
            ensure!(
                current.completed_through == checked_through,
                "Activity did not match the accepted completion prefix"
            );
            retired = response_seen
                && !current.entries.iter().any(|entry| {
                    entry.atom.turn_id.as_deref() == Some(next_completed_turn.id.as_str())
                });
            if retired {
                ensure!(response_seen, "current retired before response completion");
                break;
            }
        }
        ensure!(retired && response_seen);
        // Reopening Main preserves the actual display item and original body;
        // successful Turn identity comes from the typed business completion,
        // never from a fabricated Main TurnReceipt.
        let (latest_cap, mut latest) = env.open(&thread, None, 1).await?;
        let latest_set = latest
            .chat()
            .await
            .context("waiting for reopened Main Set after NEXT")?;
        ensure!(latest_set.placement == ChatPlacement::Set);
        let latest_items = all_items(&env, &thread, &latest_cap, latest_set).await?;
        ensure!(latest_items
            .iter()
            .all(|item| item.atom.kind != ChatAtomKind::TurnReceipt),
            "reopening fabricated a successful Main TurnReceipt");
        let next_turn_identity = next_completed_turn.id.clone();
        let next_turn = next_turn_identity.as_str();
        let next_parent = turn_parent_key(&next_turn_identity);
        let restored_text = latest_items
            .iter()
            .find(|item| item.record_id == active_id)
            .context("reopened completed response record")?;
        ensure!(
            restored_text.atom.kind == ChatAtomKind::Text,
            "reopened response kind changed: {:?}",
            restored_text.atom.kind
        );
        ensure!(
            restored_text.atom.completion_item_id.as_deref() == Some(active_id.as_str()),
            "reopened response completion-item identity changed: {:?}",
            restored_text.atom.completion_item_id
        );
        ensure!(
            restored_text.atom.turn_id.as_deref() == Some(next_turn),
            "reopened response Turn identity changed: {:?}",
            restored_text.atom.turn_id
        );
        let pl_protocol::ChatAtomLifecycle::Terminal {
            started: Some(started),
            ended: Some(ended),
            outcome: pl_protocol::ChatTerminalOutcome::Completed,
        } = &restored_text.atom.lifecycle
        else {
            bail!(
                "reopened response did not preserve terminal fact positions: {:?}",
                restored_text.atom.lifecycle
            );
        };
        ensure!(
            started <= ended,
            "response terminal fact precedes its start: {started:?} > {ended:?}"
        );
        ensure!(
            restored_text.atom.contents.iter().any(|content| content.reference == response_ref),
            "reopened response content reference changed"
        );
        let terminal = item_payload(&env, &thread, &latest_cap, restored_text).await?;
        ensure!(terminal["type"] == "text" && terminal["turnId"] == next_turn);
        let reopened: ContentWindow = env
            .query(&thread, &latest_cap, "contents/read", &request)
            .await?;
        ensure!(reopened == sealed, "reopening changed the sealed original response");
        let mut restored_markdown = Vec::new();
        while restored_markdown.len() < old_text.len() {
            let chunk: ContentWindow = env
                .query(&thread, &latest_cap, "contents/read", &json!({
                    "reference": reference,
                    "range": {"offset": restored_markdown.len(), "maxBytes": 4096},
                }))
                .await?;
            ensure!(
                chunk.sealed
                    && chunk.offset == restored_markdown.len() as u64
                    && chunk.available_through == old_text.len() as u64
                    && chunk.generation == window.generation
                    && !chunk.bytes.is_empty()
                    && chunk.bytes.len() <= 4096,
                "reopened large Markdown range changed its sealed owner or failed to progress"
            );
            restored_markdown.extend(chunk.bytes);
        }
        ensure!(
            restored_markdown == old_text.as_bytes(),
            "reopened original body did not preserve the complete Markdown UTF-8 bytes"
        );
        let point_read: CompletedEntry = env
            .query(
                &thread,
                &latest_cap,
                "chat/completed",
                &json!({ "recordId": &active_id, "demand": demand(2) }),
            )
            .await?;
        ensure!(
            point_read.record_id == active_id
                && point_read.completion_seq == restored_text.completion_seq
                && point_read.atom == restored_text.atom,
            "HTTP point lookup did not return the immutable record from the original lease"
        );
        ensure!(next_parent != parent && next_turn_identity != turn_id);
        let (next_cap, mut next_children) = env.open(&thread, Some(&next_parent), 1).await?;
        let next_set = next_children
            .chat()
            .await
            .context("waiting for next-Turn Children Set")?;
        ensure!(next_set.placement == ChatPlacement::Set);
        let next_members = all_history(&env, &thread, &next_cap, next_set).await?;
        ensure!(
            !next_members.is_empty(),
            "second Turn's Children omitted its real business members"
        );
        let latest_completion_ids = latest_items
            .iter()
            .filter_map(|item| item.atom.completion_item_id.as_deref())
            .collect::<HashSet<_>>();
        let mut next_turn_receipts = 0;
        let mut next_inferences = 0;
        let mut next_responses = 0;
        for message in &next_members {
            ensure!(
                message.atom.turn_id.as_deref() == Some(next_turn),
                "second Children scope returned another Turn's atom metadata"
            );
            let value = payload(&env, &thread, &next_cap, message).await?;
            ensure!(
                value["turnId"] == next_turn,
                "second Children payload belongs to another Turn"
            );
            if message.atom.kind != ChatAtomKind::TurnReceipt {
                ensure!(
                    message.atom.completion_item_id.as_deref().is_some_and(|id|
                        latest_completion_ids.contains(id) || appended_completion_ids.contains(id)),
                    "second Children content lost its actual Main content ownership"
                );
            }
            match value["type"].as_str() {
                Some("inference") => next_inferences += 1,
                Some("turn") => {
                    next_turn_receipts += 1;
                    ensure!(
                        message.atom.kind == ChatAtomKind::TurnReceipt
                            && matches!(&message.atom.lifecycle, pl_protocol::ChatAtomLifecycle::Terminal {
                                outcome: pl_protocol::ChatTerminalOutcome::Completed, ..
                            })
                            && value["data"]["inputId"].as_str() == next_completed_turn.input_id.as_deref()
                            && value["data"]["outcome"]["kind"] == "completed",
                        "second Children TurnReceipt disagrees with the successful typed completion"
                    );
                }
                Some("thinking") => ensure!(
                    value["data"]["outcome"]["kind"] == "completed",
                    "second Thinking member is not terminally completed"
                ),
                Some("text") => {
                    next_responses += 1;
                    ensure!(
                        message.atom.kind == ChatAtomKind::Text
                            && message.atom.completion_item_id.as_deref() == Some(active_id.as_str())
                            && message.atom.contents.iter().any(|content| content.reference == response_ref)
                            && value == terminal,
                        "second Children response lost its original content owner or frozen payload"
                    );
                }
                Some(
                    "tool" | "raw" | "agent" | "skill" | "file" | "contextCompaction"
                    | "plan",
                ) => {}
                kind => bail!("unexpected member from the second Turn's Children: {kind:?}"),
            }
        }
        ensure!(
            next_turn_receipts == 1 && next_inferences == 0 && next_responses == 1,
            "second Children must retain its business TurnReceipt and original response without copying inference: \
             receipts={next_turn_receipts}, inference={next_inferences}, responses={next_responses}"
        );
        let next_lease = env.lease(&thread, &next_cap)?;
        drop(next_children);
        tokio::time::timeout(DEADLINE, next_lease.owner.cancel.cancelled()).await?;
        drop(next_lease);
        drop(latest);
        let cross = env
            .post("different-thread", &capability, "contents/read", &request)
            .await?;
        ensure!(cross.status() == reqwest::StatusCode::CONFLICT);
        ensure!(cross.json::<StudioError>().await?.reason() == Some("staleReadScope"));

        // Disconnect the paused original owner with a watch still attached.
        let detached_watch = env
            .post(&thread, &paused_cap, "contents/watch", &request)
            .await?
            .error_for_status()?;
        let mut detached_watch = SseBody::network(detached_watch);
        let _ = detached_watch.window().await?;
        let lease = env.lease(&thread, &paused_cap)?;
        drop(paused);
        tokio::time::timeout(DEADLINE, lease.owner.cancel.cancelled()).await?;
        let stale = env
            .post(
                &thread,
                &paused_cap,
                "chat/older",
                &json!({
                    "before": first.before, "demand": demand(4),
                }),
            )
            .await?;
        ensure!(stale.status() == reqwest::StatusCode::CONFLICT);
        ensure!(stale.json::<StudioError>().await?.reason() == Some("staleReadScope"));
        drop(lease);
        drop(detached_watch);
        drop(children);
        drop(main);
        // Exercise server shutdown with a genuinely pending watch, rather than
        // one which already reached sealed EOF.
        env.submit(&thread, SHUTDOWN).await?;
        tokio::time::timeout(DEADLINE, stopping.wait_reached()).await?;
        let (shutdown_cap, mut shutdown_body) = env.open(&thread, None, 1).await?;
        let initial = shutdown_body.chat().await?;
        ensure!(initial.placement == ChatPlacement::Set);
        let shutdown_activity = activity_with_response(&mut shutdown_body).await?;
        let shutdown_ref = shutdown_activity.entries.iter()
            .find(|entry| entry.atom.kind == ChatAtomKind::Text)
            .and_then(|entry| entry.atom.contents.iter()
                .find(|content| content.role == pl_protocol::ChatContentRole::Body))
            .context("shutdown Activity response reference")?
            .reference.clone();
        let response = env
            .post(
                &thread,
                &shutdown_cap,
                "contents/watch",
                &json!({
                    "reference": shutdown_ref, "range": {"offset": 0, "maxBytes": 128},
                }),
            )
            .await?
            .error_for_status()?;
        let mut shutdown_watch = SseBody::network(response);
        ensure!(!shutdown_watch.window().await?.sealed);
        let admitted = env.lease(&thread, &shutdown_cap)?;
        env.state.shutdown.cancel();
        let join = env.state.conversations.shutdown();
        tokio::pin!(join);
        ensure!(
            matches!(futures::poll!(join.as_mut()), std::task::Poll::Pending),
            "shutdown ignored the admitted query lease"
        );
        ensure!(env.lease(&thread, &shutdown_cap).is_err());
        shutdown_watch.end().await?;
        drop(admitted);
        tokio::time::timeout(DEADLINE, join).await?;
        ensure!(env.state.streams.available_permits() == crate::MAX_STREAMS);
        drop(shutdown_body);
        // Closing transports did not cancel the shared execution.
        complete(&env.runtime, &thread, &stopping, SHUTDOWN).await?;
        Ok(())
    }
    .await;
            first_stage.release();
            growing.release();
            sealing.release();
            stopping.release();
            env.finish(result).await
        }
    }

    mod timeline {
        use super::*;

        fn api<T>(result: Result<T, ApiError>) -> Result<T> {
            result.map_err(|error| anyhow::anyhow!("{}", error.0))
        }

        struct TimelineEnvironment {
            _temp: tempfile::TempDir,
            provider: FixtureServer,
            runtime: StudioRuntime,
            state: AppState,
            thread: String,
        }
        impl TimelineEnvironment {
            async fn new() -> Result<Self> {
                let temp = tempfile::tempdir()?;
                let project_path = temp.path().join("project");
                std::fs::create_dir(&project_path)?;
                let home = temp.path().join("home");
                let provider = FixtureServer::start(vec![]).await?;
                configure(&home, provider.base_url())?;
                let mut options = StudioRuntimeOptions::http_server(Some(home));
                options.host = StudioHostKind::Test;
                let runtime = Box::pin(StudioRuntime::initialize(options)).await?;
                let project = runtime.open_project(&project_path).await?;
                let thread = runtime
                    .create_thread(&project.id, "HTTP cursor lifecycle")
                    .await?
                    .id;
                let state = AppState::new(runtime.clone(), CancellationToken::new());
                Ok(Self {
                    _temp: temp,
                    provider,
                    runtime,
                    state,
                    thread,
                })
            }
            async fn open(&self) -> Result<(pl_protocol::OpenTimeline, HeaderMap)> {
                let request = serde_json::from_value(serde_json::json!({
                    "presentationVersion": 6, "readerProtocolVersion": 1,
                    "demand": { "maxItems": 1, "maxBytes": 16384 }
                }))?;
                let response = api(crate::timeline::open(
                    State(self.state.clone()),
                    Path(self.thread.clone()),
                    ApiJson(request),
                )
                .await)?
                .into_response();
                let mut headers = HeaderMap::new();
                headers.insert(
                    CONVERSATION_HEADER,
                    response.headers()[CONVERSATION_HEADER].clone(),
                );
                let bytes = axum::body::to_bytes(response.into_body(), 16384).await?;
                Ok((serde_json::from_slice(&bytes)?, headers))
            }
            async fn first(
                &self,
                metadata: &pl_protocol::OpenTimeline,
                headers: &HeaderMap,
            ) -> Result<pl_protocol::ViewUpdate> {
                let request =
                    serde_json::from_value(serde_json::json!({"after": metadata.initial_cursor}))?;
                let response = api(crate::timeline::next(
                    State(self.state.clone()),
                    Path(self.thread.clone()),
                    headers.clone(),
                    ApiJson(request),
                )
                .await)?;
                let bytes = axum::body::to_bytes(response.into_body(), 16384).await?;
                Ok(serde_json::from_slice(&bytes)?)
            }
            async fn finish(self, result: Result<()>) -> Result<()> {
                self.state.shutdown.cancel();
                self.state.conversations.shutdown().await;
                let runtime = self.runtime.shutdown_runtime().await;
                let provider = self.provider.finish().await;
                result.with_context(|| {
                    format!("cleanup: runtime={runtime:?}; provider={provider:?}")
                })?;
                runtime?;
                provider?;
                ensure!(self.state.streams.available_permits() == crate::MAX_STREAMS);
                Ok(())
            }
        }

        #[tokio::test]
        async fn timeline_idle_expiry_waits_for_active_reads_and_releases_its_capability()
        -> Result<()> {
            let env = TimelineEnvironment::new().await?;
            // Drive the real ReadOwner expiry directly so the controlled clock has one waiter.
            // The HTTP task uses the same operation with the production 120-second threshold.
            let reader = env
                .runtime
                .open_timeline_reader(
                    &env.thread,
                    6,
                    1,
                    ReadDemand {
                        max_items: 1,
                        max_bytes: 16384,
                    },
                )
                .await?;
            let metadata = reader.metadata();
            let permit = env.state.streams.clone().try_acquire_owned()?;
            let owner = Arc::new(ReadOwner::with_timeline(env.thread.clone(), reader, permit));
            env.state
                .conversations
                .0
                .lock()
                .unwrap()
                .readers
                .insert(metadata.reader_id.clone(), owner.clone());
            let mut headers = HeaderMap::new();
            headers.insert(CONVERSATION_HEADER, metadata.reader_id.parse()?);
            env.first(&metadata, &headers).await?;
            let read =
                api(env
                    .state
                    .conversations
                    .borrow(&env.thread, &headers, &env.state.shutdown))?;
            tokio::time::pause();
            let result = async {
                let idle = owner.wait_idle(Duration::from_millis(2));
                tokio::pin!(idle);
                assert!(matches!(
                    futures::poll!(&mut idle),
                    std::task::Poll::Pending
                ));
                tokio::time::advance(Duration::from_millis(3)).await;
                assert!(matches!(
                    futures::poll!(&mut idle),
                    std::task::Poll::Pending
                ));
                ensure!(!owner.cancel.is_cancelled(), "an active query was expired");
                drop(read);
                tokio::time::advance(Duration::from_millis(1)).await;
                assert!(matches!(
                    futures::poll!(&mut idle),
                    std::task::Poll::Pending
                ));
                ensure!(
                    !owner.cancel.is_cancelled(),
                    "idle time starts after the actual last request"
                );
                tokio::time::advance(Duration::from_millis(1)).await;
                tokio::time::timeout(Duration::from_secs(1), &mut idle).await?;
                ensure!(owner.cancel.is_cancelled());
                Ok(())
            }
            .await;
            tokio::time::resume();
            let result = async {
                result?;
                crate::sse::close_conversation(&owner).await?;
                env.state.conversations.forget(&metadata.reader_id);
                assert_stale(env.state.conversations.borrow(
                    &env.thread,
                    &headers,
                    &env.state.shutdown,
                ));
                ensure!(env.state.streams.available_permits() == crate::MAX_STREAMS);
                Ok(())
            }
            .await;
            env.finish(result).await
        }

        #[tokio::test]
        async fn timeline_next_timeout_and_close_bypass_the_saturated_normal_pool() -> Result<()> {
            use axum::http::{Request, StatusCode};
            use tower::ServiceExt;
            let env = TimelineEnvironment::new().await?;
            let (metadata, headers) = env.open().await?;
            let first = env.first(&metadata, &headers).await?;
            let app = crate::router(env.state.clone());
            let normal = env
                .state
                .normal_requests
                .acquire_many(crate::MAX_REQUESTS as u32)
                .await?;
            let response = app
                .clone()
                .oneshot(
                    Request::builder()
                        .uri("/docs")
                        .header("host", "localhost")
                        .body(axum::body::Body::empty())?,
                )
                .await?;
            ensure!(
                response.status() == StatusCode::TOO_MANY_REQUESTS,
                "positive control did not exhaust normal pool"
            );
            let request = Request::builder()
                .method("POST")
                .uri(format!("/api/v1/threads/{}/timeline/next", env.thread))
                .header("host", "localhost")
                .header("content-type", "application/json")
                .header(CONVERSATION_HEADER, &headers[CONVERSATION_HEADER])
                .body(axum::body::Body::from(serde_json::to_vec(
                    &serde_json::json!({"after": first.next}),
                )?))?;
            let next = app.clone().oneshot(request);
            tokio::pin!(next);
            assert!(matches!(
                futures::poll!(&mut next),
                std::task::Poll::Pending
            ));
            let response = tokio::time::timeout(Duration::from_secs(30), &mut next).await?;
            let result = async {
                let response = response?;
                ensure!(response.status() == StatusCode::NO_CONTENT);
                ensure!(
                    axum::body::to_bytes(response.into_body(), 16384)
                        .await?
                        .is_empty(),
                    "timeout allocated a response cursor"
                );
                let response = app
                    .clone()
                    .oneshot(
                        Request::builder()
                            .method("POST")
                            .uri(format!("/api/v1/threads/{}/timeline/close", env.thread))
                            .header("host", "localhost")
                            .header(CONVERSATION_HEADER, &headers[CONVERSATION_HEADER])
                            .body(axum::body::Body::empty())?,
                    )
                    .await?;
                ensure!(response.status() == StatusCode::NO_CONTENT);
                let old = app
                    .oneshot(
                        Request::builder()
                            .uri(format!("/api/v1/threads/{}/timeline/events", env.thread))
                            .header("host", "localhost")
                            .body(axum::body::Body::empty())?,
                    )
                    .await?;
                ensure!(old.status() == StatusCode::NOT_FOUND);
                ensure!(env.state.streams.available_permits() == crate::MAX_STREAMS);
                Ok(())
            }
            .await;
            drop(normal);
            env.finish(result).await
        }

        #[tokio::test]
        async fn timeline_cursor_replay_queries_and_close_share_original_capability() -> Result<()>
        {
            let temp = tempfile::tempdir()?;
            let project_path = temp.path().join("project");
            std::fs::create_dir(&project_path)?;
            let home = temp.path().join("home");
            let provider = FixtureServer::start(vec![]).await?;
            configure(&home, provider.base_url())?;
            let mut options = StudioRuntimeOptions::http_server(Some(home));
            options.host = StudioHostKind::Test;
            let runtime = Box::pin(StudioRuntime::initialize(options)).await?;
            let state = AppState::new(runtime.clone(), CancellationToken::new());
            let result: Result<()> = async {
                let project = runtime.open_project(&project_path).await?;
                let thread = runtime
                    .create_thread(&project.id, "HTTP timeline scope")
                    .await?;
                for presentation_version in [5, 6] {
                    let request = serde_json::from_value(serde_json::json!({
                        "presentationVersion": presentation_version, "readerProtocolVersion": 1,
                        "demand": { "maxItems": 1, "maxBytes": 16384 }
                    }))?;
                    let opened = crate::timeline::open(
                        State(state.clone()),
                        Path(thread.id.clone()),
                        ApiJson(request),
                    )
                    .await;
                    if presentation_version == 5 {
                        let error = opened.err().context("old protocol was accepted")?;
                        ensure!(error.0.reason() == Some("protocolVersionMismatch"));
                        continue;
                    }
                    let response = api(opened)?.into_response();
                    let id = response.headers()[CONVERSATION_HEADER].to_str()?.to_owned();
                    let bytes = axum::body::to_bytes(response.into_body(), 16384).await?;
                    let metadata: pl_protocol::OpenTimeline = serde_json::from_slice(&bytes)?;
                    ensure!(metadata.reader_id == id);
                    let mut headers = HeaderMap::new();
                    headers.insert(CONVERSATION_HEADER, HeaderValue::from_str(&id)?);
                    let lease =
                        api(state
                            .conversations
                            .borrow(&thread.id, &headers, &state.shutdown))?;
                    let owner = Arc::clone(&lease.owner);
                    drop(lease);
                    assert_stale(state.conversations.borrow(
                        "foreign-thread",
                        &headers,
                        &state.shutdown,
                    ));
                    let request = || {
                        serde_json::from_value(
                            serde_json::json!({ "after": metadata.initial_cursor }),
                        )
                    };
                    ensure!(
                        crate::timeline::next(
                            State(state.clone()),
                            Path(thread.id.clone()),
                            HeaderMap::new(),
                            ApiJson(request()?)
                        )
                        .await
                        .is_err()
                    );
                    let mut first = None;
                    for _ in 0..2 {
                        let response = api(crate::timeline::next(
                            State(state.clone()),
                            Path(thread.id.clone()),
                            headers.clone(),
                            ApiJson(request()?),
                        )
                        .await)?;
                        let bytes = axum::body::to_bytes(response.into_body(), 16384).await?;
                        let update: pl_protocol::ViewUpdate = serde_json::from_slice(&bytes)?;
                        ensure!(update.history.placement == pl_protocol::HistoryPlacement::Set);
                        ensure!(matches!(
                            update.tail,
                            pl_protocol::TailUpdate::Replace { .. }
                        ));
                        if let Some(previous) = &first {
                            ensure!(&update == previous, "retry changed response");
                        }
                        first = Some(update);
                    }
                    let after = first.context("first update")?.next;
                    let waiting = crate::timeline::next(
                        State(state.clone()),
                        Path(thread.id.clone()),
                        headers.clone(),
                        ApiJson(serde_json::from_value(serde_json::json!({"after": after}))?),
                    );
                    tokio::pin!(waiting);
                    assert!(matches!(
                        futures::poll!(&mut waiting),
                        std::task::Poll::Pending
                    ));
                    let duplicate = crate::timeline::next(
                        State(state.clone()),
                        Path(thread.id.clone()),
                        headers.clone(),
                        ApiJson(request()?),
                    )
                    .await
                    .err()
                    .context("concurrent next accepted")?;
                    ensure!(duplicate.0.reason() == Some("concurrentNext"));
                    let query = crate::timeline::older(
                        State(state.clone()),
                        Path(thread.id.clone()),
                        headers.clone(),
                        ApiJson(OlderRequest {
                            before: "invalid-cursor".into(),
                            demand: ReadDemand {
                                max_items: 1,
                                max_bytes: 16384,
                            },
                        }),
                    );
                    let error = tokio::time::timeout(DEADLINE, query)
                        .await?
                        .err()
                        .context("invalid cursor admitted")?;
                    ensure!(error.0.code == StudioErrorCode::InvalidArgument);
                    let closing = crate::timeline::close(
                        State(state.clone()),
                        Path(thread.id.clone()),
                        headers.clone(),
                    );
                    let (closed, ended) = tokio::time::timeout(DEADLINE, async {
                        tokio::join!(closing, &mut waiting)
                    })
                    .await?;
                    api(closed)?;
                    ensure!(ended.is_err(), "close did not revoke parked next");
                    assert_stale(
                        state
                            .conversations
                            .borrow(&thread.id, &headers, &state.shutdown),
                    );
                    ensure!(owner.native.lock().await.is_none());
                }
                ensure!(state.streams.available_permits() == crate::MAX_STREAMS);
                Ok(())
            }
            .await;
            state.shutdown.cancel();
            state.conversations.shutdown().await;
            let shutdown = runtime.shutdown_runtime().await;
            let fixture = provider.finish().await;
            result.context(format!(
                "cleanup: runtime={shutdown:?}; provider={fixture:?}"
            ))
        }
    }
}
