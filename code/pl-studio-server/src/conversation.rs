//! HTTP operations borrowing the read capability owned by an existing conversation SSE.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use axum::Json;
use axum::extract::{Path, State};
use axum::http::HeaderMap;
use pl_protocol::{
    ChatBatch, ContentManifestPage, ContentRange, ContentRef, ContentWindow, CurrentCollectionPage,
    CurrentCollectionRef, ReadDemand,
    studio::{StudioError, StudioErrorCode, StudioErrorReason},
};
use pl_studio_runtime::ConversationReader;
use serde::Deserialize;
use tokio::sync::{OwnedSemaphorePermit, Semaphore};
use tokio::task::JoinSet;
use tokio_util::sync::CancellationToken;
use utoipa::ToSchema;

use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, StudioApiErrors};

pub(crate) const CONVERSATION_HEADER: &str = "x-anywork-conversation";
const MAX_READS: u32 = (crate::MAX_REQUESTS + crate::MAX_STREAMS) as u32;

#[cfg(test)]
mod tests;

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
    pub(crate) cancel: CancellationToken,
    reads: Arc<Semaphore>,
}

impl ReadOwner {
    pub(crate) fn new(thread_id: String, reader: ConversationReader) -> Self {
        Self {
            thread_id,
            reader,
            cancel: CancellationToken::new(),
            reads: Arc::new(Semaphore::new(MAX_READS as usize)),
        }
    }

    pub(crate) async fn drain(&self) {
        // Removal from the index precedes this wait, so no new permits can be
        // acquired. Watches drop their permit only after closing their source.
        let _all = self.reads.acquire_many(MAX_READS).await;
    }
}

pub(crate) struct ReadLease {
    pub(crate) owner: Arc<ReadOwner>,
    _permit: OwnedSemaphorePermit,
}

impl Conversations {
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
        if owners.closed || shutdown.is_cancelled() || owner.thread_id != thread_id {
            return Err(stale_scope());
        }
        let permit = owner
            .reads
            .clone()
            .try_acquire_owned()
            .map_err(|_| ApiError::overloaded())?;
        Ok(ReadLease {
            owner: owner.clone(),
            _permit: permit,
        })
    }

    pub(crate) fn remove(&self, id: &str) {
        let mut owners = self.0.lock().expect("conversation owners poisoned");
        if let Some(owner) = owners.readers.remove(id) {
            owner.cancel.cancel();
        }
    }

    pub(crate) async fn shutdown(&self) {
        let mut tasks = {
            let mut owners = self.0.lock().expect("conversation owners poisoned");
            owners.closed = true;
            for (_, owner) in owners.readers.drain() {
                owner.cancel.cancel();
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
pub(crate) struct PositionRequest {
    pub completion_seq: u64,
    pub before: Option<String>,
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

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/chat/before",
    operation_id = "thread.readBefore",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = PositionRequest,
    responses(StudioApiErrors, (status = 200, body = ChatBatch)))]
pub(crate) async fn before(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<PositionRequest>,
) -> Result<Json<ChatBatch>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .owner
            .reader
            .read_before(
                request.completion_seq,
                request.before.as_deref(),
                request.demand,
            )
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/chat/at",
    operation_id = "thread.readAt",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = PositionRequest,
    responses(StudioApiErrors, (status = 200, body = ChatBatch)))]
pub(crate) async fn at(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<PositionRequest>,
) -> Result<Json<ChatBatch>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .owner
            .reader
            .read_at(
                request.completion_seq,
                request.before.as_deref(),
                request.demand,
            )
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
