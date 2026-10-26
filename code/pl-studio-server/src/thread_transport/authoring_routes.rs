use super::types::*;
use super::*;
use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, ApiPath, StudioApiErrors};
use axum::Json;
use axum::extract::State as App;
use axum::http::{HeaderMap, HeaderValue, StatusCode};
use axum::response::sse::KeepAlive;
use axum::response::{IntoResponse, Response, Sse};
use pl_protocol::thread_facets::authoring::AuthoringFrame;
use utoipa_axum::{router::OpenApiRouter, routes};

pub(crate) fn authoring_router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(events))
        .routes(routes!(ack))
        .routes(routes!(request_close))
        .routes(routes!(close))
        .routes(routes!(retry_close))
        .routes(routes!(request_read_close))
        .routes(routes!(read_close))
        .routes(routes!(retry_read_close))
        // 每个 handler 各自声明自己的 path/method：`routes!` 只产生一个 MethodRouter，
        // 多个同 method 的 handler 放进同一次调用会在装配期重复登记 POST。
        .routes(routes!(authoring_read_routes::todo_open))
        .routes(routes!(authoring_read_routes::workflow_open))
        .routes(routes!(authoring_read_routes::plan_document_open))
        .routes(routes!(authoring_read_routes::todo_header))
        .routes(routes!(authoring_read_routes::todo_items))
        .routes(routes!(authoring_read_routes::workflow_header))
        .routes(routes!(authoring_read_routes::plan_document_header))
        .routes(routes!(authoring_read_routes::plan_document))
        .routes(routes!(authoring_read_routes::text))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/authoring/events", operation_id = "thread.authoring.events", params(("thread_id" = String, Path)), request_body = AuthoringRequest,
    responses(StudioApiErrors, (status = 200, body = AuthoringFrame, content_type = "text/event-stream", headers(("x-studio-feed-id" = String, description = "Original Authoring feed ID; no replay")))))]
async fn events(
    App(state): App<AppState>,
    ApiPath(thread_id): ApiPath<String>,
    headers: HeaderMap,
    ApiJson(body): ApiJson<AuthoringRequest>,
) -> Result<Response, ApiError> {
    if headers.contains_key("last-event-id") {
        return Err(StudioError::new(
            StudioErrorCode::Conflict,
            "Authoring streams do not support replay",
            false,
        )
        .into());
    }
    state.thread_transports.reap();
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let mut opening = state.thread_transports.open(
        state.runtime.clone(),
        Open::Authoring {
            thread_id,
            mode: body.mode,
        },
        Some(permit),
    )?;
    let Identity::Feed(identity) = opening.ready().await? else {
        return Err(StudioError::internal().into());
    };
    let id =
        HeaderValue::from_str(&identity.feed_id).map_err(|_| ApiError(StudioError::internal()))?;
    let body = opening.authoring_body()?;
    let mut response = Sse::new(body)
        .keep_alive(KeepAlive::default())
        .into_response();
    response.headers_mut().insert("x-studio-feed-id", id);
    Ok(response)
}

#[utoipa::path(post, path = "/api/v1/authoring-feeds/{feed_id}/ack", operation_id = "thread.authoring.ack", params(("feed_id" = String, Path)), request_body = Ack, responses(StudioApiErrors, (status = 204)))]
async fn ack(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<Ack>,
) -> Result<StatusCode, ApiError> {
    let Native::Authoring(feed) = state.thread_transports.get_authoring_feed(&id)?.native()? else {
        return Err(wrong().into());
    };
    feed.ack_through(body.delivery_sequence)?;
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/authoring-feeds/{feed_id}/request-close", operation_id = "thread.authoring.requestClose", params(("feed_id" = String, Path)), responses(StudioApiErrors, (status = 204)))]
async fn request_close(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<StatusCode, ApiError> {
    state
        .thread_transports
        .get_authoring_feed(&id)?
        .request_close();
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/authoring-feeds/{feed_id}/close", operation_id = "thread.authoring.close", params(("feed_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn close(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        state
            .thread_transports
            .get_authoring_feed(&id)?
            .close_report(id)
            .await,
    ))
}
#[utoipa::path(post, path = "/api/v1/authoring-feeds/{feed_id}/retry-close", operation_id = "thread.authoring.retryClose", params(("feed_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn retry_close(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        state
            .thread_transports
            .get_authoring_feed(&id)?
            .close_report(id)
            .await,
    ))
}
#[utoipa::path(post, path = "/api/v1/authoring-reads/{scope_id}/request-close", operation_id = "thread.read.authoringRequestClose", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 204)))]
async fn request_read_close(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<StatusCode, ApiError> {
    state
        .thread_transports
        .get_authoring_read(&id)?
        .request_close();
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/authoring-reads/{scope_id}/close", operation_id = "thread.read.authoringClose", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn read_close(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        state
            .thread_transports
            .get_authoring_read(&id)?
            .close_report(id)
            .await,
    ))
}
#[utoipa::path(post, path = "/api/v1/authoring-reads/{scope_id}/retry-close", operation_id = "thread.read.authoringRetryClose", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn retry_read_close(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        state
            .thread_transports
            .get_authoring_read(&id)?
            .close_report(id)
            .await,
    ))
}
