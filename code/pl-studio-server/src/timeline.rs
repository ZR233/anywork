//! Timeline HTTP endpoints borrow the existing conversation capability and lifecycle.

use std::{convert::Infallible, sync::Arc, time::Duration};

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
use pl_protocol::{
    DisplayBlockRef, DisplayMemberWindow, OpenTimeline, ReadDemand, TailSnapshot, TimelinePage,
    ViewCursor, ViewUpdate,
};
use serde::Deserialize;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use utoipa::ToSchema;

use crate::{
    AppState,
    conversation::{CONVERSATION_HEADER, OlderRequest, ReadOwner, stale_scope},
    error::ApiError,
    routes::{ApiJson, StudioApiErrors},
};

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct OpenRequest {
    presentation_version: u32,
    reader_protocol_version: u32,
    demand: ReadDemand,
}

const NEXT_WAIT: Duration = Duration::from_secs(25);
const IDLE_READER_TIMEOUT: Duration = Duration::from_secs(120);

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/timeline/open",
    operation_id = "thread.openTimeline",
    params(("thread_id" = String, Path)),
    request_body = OpenRequest,
    responses(StudioApiErrors, (status = 200, body = OpenTimeline)))]
pub(crate) async fn open(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiJson(request): ApiJson<OpenRequest>,
) -> Result<impl IntoResponse, ApiError> {
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let reader = state
        .runtime
        .open_timeline_reader(
            &thread_id,
            request.presentation_version,
            request.reader_protocol_version,
            request.demand,
        )
        .await?;
    let metadata = reader.metadata();
    let id = metadata.reader_id.clone();
    let owner = Arc::new(ReadOwner::with_timeline(thread_id, reader));
    let registered = {
        let mut owners = state
            .conversations
            .0
            .lock()
            .expect("conversation owners poisoned");
        owners.readers.insert(id.clone(), owner.clone());
        if owners.closed || state.shutdown.is_cancelled() {
            false
        } else {
            while let Some(result) = owners.tasks.try_join_next() {
                if let Err(error) = result {
                    tracing::warn!(%error, "timeline owner task failed");
                }
            }
            let task_state = state.clone();
            let task_id = id.clone();
            let task_owner = owner.clone();
            owners.tasks.spawn(async move {
                let _permit = permit;
                tokio::select! { biased;
                    _ = task_state.shutdown.cancelled() => {},
                    _ = task_owner.cancel.cancelled() => {},
                    _ = task_owner.wait_idle(IDLE_READER_TIMEOUT) => {},
                }
                task_owner.request_close();
                let result = crate::sse::close_conversation(&task_owner).await;
                task_owner.completed.send_replace(Some(result.clone()));
                if result.is_ok() {
                    task_state.conversations.forget(&task_id);
                }
            });
            true
        }
    };
    if !registered {
        owner.request_close();
        crate::sse::close_conversation(&owner)
            .await
            .map_err(ApiError)?;
        state.conversations.forget(&id);
        return Err(stale_scope());
    }
    Ok(([(CONVERSATION_HEADER, id)], Json(metadata)))
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct NextRequest {
    after: ViewCursor,
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/timeline/next",
    operation_id = "thread.nextTimeline",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = NextRequest,
    responses(StudioApiErrors, (status = 200, body = ViewUpdate), (status = 204)))]
pub(crate) async fn next(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<NextRequest>,
) -> Result<axum::response::Response, ApiError> {
    let lease = state
        .conversations
        .borrow_next(&thread_id, &headers, &state.shutdown)?;
    let reader = lease.owner.timeline.as_ref().ok_or_else(stale_scope)?;
    match tokio::time::timeout(NEXT_WAIT, reader.next(request.after)).await {
        Ok(result) => Ok(Json(result?).into_response()),
        Err(_) => Ok(axum::http::StatusCode::NO_CONTENT.into_response()),
    }
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/timeline/older",
    operation_id = "thread.loadTimelineOlder",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = OlderRequest,
    responses(StudioApiErrors, (status = 200, body = TimelinePage)))]
pub(crate) async fn older(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<OlderRequest>,
) -> Result<Json<TimelinePage>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    let page = lease
        .owner
        .timeline
        .as_ref()
        .ok_or_else(stale_scope)?
        .load_older(&request.before, request.demand)
        .await?;
    Ok(Json(page))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/timeline/live-older",
    operation_id = "thread.loadLiveOlder",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = OlderRequest,
    responses(StudioApiErrors, (status = 200, body = TailSnapshot)))]
pub(crate) async fn live_older(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<OlderRequest>,
) -> Result<Json<TailSnapshot>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .owner
            .timeline
            .as_ref()
            .ok_or_else(stale_scope)?
            .load_live_older(&request.before, request.demand)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/timeline/close",
    operation_id = "thread.closeTimeline",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    responses(StudioApiErrors, (status = 204)))]
pub(crate) async fn close(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
) -> Result<axum::http::StatusCode, ApiError> {
    // Do not hold a read permit while waiting for that owner's reads to drain.
    let (id, owner) = state.conversations.closing_owner(&thread_id, &headers)?;
    owner.request_close();
    // Retrying a failed close uses the same retained native slot, never a new feed.
    crate::sse::close_conversation(&owner)
        .await
        .map_err(ApiError)?;
    state.conversations.forget(&id);
    Ok(axum::http::StatusCode::NO_CONTENT)
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct MembersRequest {
    reference: DisplayBlockRef,
    window: DisplayMemberWindow,
    demand: ReadDemand,
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/timeline/members",
    operation_id = "thread.displayMembers",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = MembersRequest,
    responses(StudioApiErrors, (status = 200, body = String, content_type = "text/event-stream")))]
pub(crate) async fn members(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<MembersRequest>,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    let source = lease
        .owner
        .reader
        .open_display_members(request.reference, request.window, request.demand)
        .await?;
    let member = Arc::new(tokio::sync::Mutex::new(Some(source)));
    lease
        .owner
        .members
        .lock()
        .expect("conversation members poisoned")
        .push(Arc::clone(&member));
    let (sender, receiver) = mpsc::channel(1);
    // The original owner task waits on this lease until the real member resource closes.
    tokio::spawn(async move {
        let _permit = permit;
        let mut failure = None;
        let mut native = member.lock().await;
        let source = native.as_mut().expect("registered member resource");
        loop {
            let capacity = tokio::select! {
                biased;
                () = state.shutdown.cancelled() => break,
                () = lease.owner.cancel.cancelled() => break,
                capacity = sender.reserve() => match capacity { Ok(capacity) => capacity, Err(_) => break },
            };
            let received = tokio::select! {
                biased;
                () = state.shutdown.cancelled() => break,
                () = lease.owner.cancel.cancelled() => break,
                () = sender.closed() => break,
                page = source.next() => page,
            };
            match received {
                Ok(Some(page)) => {
                    let sealed = page.sealed;
                    match Event::default().event("members").json_data(page) {
                        Ok(event) => {
                            capacity.send(Ok(event));
                        }
                        Err(_) => break,
                    }
                    if sealed {
                        break;
                    }
                }
                Ok(None) => break,
                Err(error) => {
                    failure = Some(pl_studio_runtime::studio_error_from_anyhow(error));
                    break;
                }
            }
        }
        source.request_close();
        if let Err(error) = source.close().await {
            failure = Some(pl_studio_runtime::studio_error_from_anyhow(error));
        } else {
            native.take();
            lease
                .owner
                .members
                .lock()
                .expect("conversation members poisoned")
                .retain(|entry| !Arc::ptr_eq(entry, &member));
        }
        drop(native);
        if let Some(error) = failure
            && let Ok(event) = Event::default().event("error").json_data(error)
        {
            let _ = sender.try_send(Ok(event));
        }
        let _ = sender.try_send(Ok(Event::default().event("closed").data("{}")));
        drop(lease);
    });
    Ok(Sse::new(ReceiverStream::new(receiver))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timeline_requests_require_explicit_demand_and_fixed_member_window() {
        assert!(serde_json::from_value::<OpenRequest>(serde_json::json!({})).is_err());
        assert!(
            serde_json::from_value::<OpenRequest>(serde_json::json!({
                "demand": { "maxItems": 1 }
            }))
            .is_err()
        );
        assert!(
            serde_json::from_value::<MembersRequest>(serde_json::json!({
                "reference": { "databaseId": "db", "blockId": "work" },
                "demand": { "maxItems": 1, "maxBytes": 4096 }
            }))
            .is_err()
        );
        let request: MembersRequest = serde_json::from_value(serde_json::json!({
            "reference": { "databaseId": "db", "blockId": "work" },
            "window": { "kind": "before", "memberOrder": 7 },
            "demand": { "maxItems": 1, "maxBytes": 4096 }
        }))
        .unwrap();
        assert_eq!(
            request.window,
            DisplayMemberWindow::Before { member_order: 7 }
        );
        assert_eq!(request.demand.max_items, 1);
    }
}
