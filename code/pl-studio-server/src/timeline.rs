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
    DisplayBlockRef, DisplayMemberWindow, LiveDisplayWindow, ReadDemand, TimelineBatch,
    studio::{StudioError, StudioErrorCode},
};
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use utoipa::ToSchema;

use crate::{
    AppState,
    conversation::{CONVERSATION_HEADER, NativeFeed, OlderRequest, stale_scope},
    error::ApiError,
    routes::{ApiJson, StudioApiErrors},
};

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct OpenRequest {
    demand: ReadDemand,
}

#[derive(Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) struct OpenResponse {
    subscription_id: String,
    presentation_version: u32,
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/timeline/open",
    operation_id = "thread.openTimeline",
    params(("thread_id" = String, Path)),
    request_body = OpenRequest,
    responses(StudioApiErrors, (status = 200, body = OpenResponse)))]
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
    let feed = state
        .runtime
        .open_timeline_feed(&thread_id, request.demand)
        .await?;
    let id = crate::sse::register_conversation(
        &state,
        thread_id,
        NativeFeed::Timeline(Box::new(feed)),
        permit,
        None,
    )
    .await?;
    Ok((
        [(CONVERSATION_HEADER, id.clone())],
        Json(OpenResponse {
            subscription_id: id,
            presentation_version: pl_protocol::PRESENTATION_VERSION,
        }),
    ))
}

#[utoipa::path(get, path = "/api/v1/threads/{thread_id}/timeline/events",
    operation_id = "thread.timelineEvents",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    responses(StudioApiErrors, (status = 200, body = String, content_type = "text/event-stream")))]
pub(crate) async fn events(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    let (sender, receiver) = mpsc::channel(1);
    let start = lease
        .owner
        .events
        .lock()
        .expect("conversation start poisoned")
        .take()
        .ok_or_else(|| {
            ApiError(StudioError::new(
                StudioErrorCode::Conflict,
                "Timeline events can only be attached once to the original open",
                false,
            ))
        })?;
    start.send(sender).map_err(|_| stale_scope())?;
    Ok(Sse::new(ReceiverStream::new(receiver))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/timeline/older",
    operation_id = "thread.loadTimelineOlder",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = OlderRequest,
    responses(StudioApiErrors, (status = 200, body = TimelineBatch)))]
pub(crate) async fn older(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<OlderRequest>,
) -> Result<Json<TimelineBatch>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    let batch = lease
        .owner
        .reader
        .load_timeline_older(&request.before, request.demand)
        .await?;
    batch.validate().map_err(ApiError)?;
    Ok(Json(batch))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/timeline/live-older",
    operation_id = "thread.loadLiveOlder",
    params(("thread_id" = String, Path), ("X-Anywork-Conversation" = String, Header)),
    request_body = OlderRequest,
    responses(StudioApiErrors, (status = 200, body = LiveDisplayWindow)))]
pub(crate) async fn live_older(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<OlderRequest>,
) -> Result<Json<LiveDisplayWindow>, ApiError> {
    let lease = state
        .conversations
        .borrow(&thread_id, &headers, &state.shutdown)?;
    Ok(Json(
        lease
            .owner
            .reader
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
    let mut completed = owner.completed.subscribe();
    loop {
        if completed.borrow_and_update().is_some() {
            break;
        }
        completed.changed().await.map_err(|_| stale_scope())?;
    }
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
