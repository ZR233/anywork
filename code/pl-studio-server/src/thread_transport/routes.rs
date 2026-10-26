use super::types::*;
use super::*;
use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, ApiPath, StudioApiErrors};
use axum::Json;
use axum::extract::State as App;
use axum::http::{HeaderMap, HeaderValue};
use axum::response::sse::KeepAlive;
use axum::response::{IntoResponse, Response, Sse};
use pl_protocol::thread_facets::execution::ExecutionFrame;
use utoipa_axum::{router::OpenApiRouter, routes};

pub(crate) fn router() -> OpenApiRouter<AppState> {
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
        .routes(routes!(read_routes::turn_open))
        .routes(routes!(read_routes::index_open))
        .routes(routes!(read_routes::interaction_open))
        .routes(routes!(read_routes::activity_open))
        .routes(routes!(read_routes::storage_open))
        .routes(routes!(read_routes::resolve_interaction))
        .routes(routes!(read_routes::turn_header))
        .routes(routes!(read_routes::index_header))
        .routes(routes!(read_routes::interaction_header))
        .routes(routes!(read_routes::activity_header))
        .routes(routes!(read_routes::storage_header))
        .routes(routes!(read_routes::index_entries))
        .routes(routes!(read_routes::questions))
        .routes(routes!(read_routes::options))
        .routes(routes!(read_routes::answer_entries))
        .routes(routes!(read_routes::answer_values))
        .routes(routes!(read_routes::tools))
        .routes(routes!(read_routes::wait_targets))
        .routes(routes!(read_routes::latest_wait_targets))
        .routes(routes!(read_routes::text))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/execution/events", operation_id = "thread.execution.events", params(("thread_id" = String, Path)), request_body = ExecutionRequest,
    responses(StudioApiErrors, (status = 200, body = ExecutionFrame, content_type = "text/event-stream", headers(("x-studio-feed-id" = String, description = "Original execution feed ID; no replay")))))]
async fn events(
    App(state): App<AppState>,
    ApiPath(thread_id): ApiPath<String>,
    headers: HeaderMap,
    ApiJson(body): ApiJson<ExecutionRequest>,
) -> Result<Response, ApiError> {
    execution_response(
        state,
        Open::Execution {
            thread_id,
            mode: body.mode,
        },
        headers,
    )
    .await
}

pub(crate) async fn open_created_execution(
    state: AppState,
    source: pl_studio_runtime::draft_commands::StudioCreatedInputExecutionSource,
    headers: HeaderMap,
) -> Result<Response, ApiError> {
    execution_response(state, Open::CreatedExecution(source), headers).await
}

async fn execution_response(
    state: AppState,
    request: Open,
    headers: HeaderMap,
) -> Result<Response, ApiError> {
    if headers.contains_key("last-event-id") {
        return Err(StudioError::new(
            StudioErrorCode::Conflict,
            "Execution streams do not support replay",
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
    let mut opening = state
        .thread_transports
        .open(state.runtime.clone(), request, Some(permit))?;
    let Identity::Feed(identity) = opening.ready().await? else {
        return Err(StudioError::internal().into());
    };
    let id =
        HeaderValue::from_str(&identity.feed_id).map_err(|_| ApiError(StudioError::internal()))?;
    let body = opening.body()?;
    let mut response = Sse::new(body)
        .keep_alive(KeepAlive::default())
        .into_response();
    response.headers_mut().insert("x-studio-feed-id", id);
    Ok(response)
}

#[utoipa::path(post, path = "/api/v1/thread-feeds/{feed_id}/ack", operation_id = "thread.execution.ack", params(("feed_id" = String, Path)), request_body = Ack, responses(StudioApiErrors, (status = 204)))]
async fn ack(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<Ack>,
) -> Result<axum::http::StatusCode, ApiError> {
    let Native::Execution(feed) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    feed.ack_through(body.delivery_sequence)?;
    Ok(axum::http::StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/thread-feeds/{feed_id}/request-close", operation_id = "thread.execution.requestClose", params(("feed_id" = String, Path)), responses(StudioApiErrors, (status = 204)))]
async fn request_close(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<axum::http::StatusCode, ApiError> {
    state.thread_transports.get_feed(&id)?.request_close();
    Ok(axum::http::StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/thread-feeds/{feed_id}/close", operation_id = "thread.execution.close", params(("feed_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn close(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        state
            .thread_transports
            .get_feed(&id)?
            .close_report(id)
            .await,
    ))
}
#[utoipa::path(post, path = "/api/v1/thread-feeds/{feed_id}/retry-close", operation_id = "thread.execution.retryClose", params(("feed_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn retry_close(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        state
            .thread_transports
            .get_feed(&id)?
            .close_report(id)
            .await,
    ))
}
#[utoipa::path(post, path = "/api/v1/thread-reads/{scope_id}/request-close", operation_id = "thread.read.requestClose", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 204)))]
async fn request_read_close(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<axum::http::StatusCode, ApiError> {
    state.thread_transports.get_read(&id)?.request_close();
    Ok(axum::http::StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/thread-reads/{scope_id}/close", operation_id = "thread.read.close", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn read_close(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        state
            .thread_transports
            .get_read(&id)?
            .close_report(id)
            .await,
    ))
}
#[utoipa::path(post, path = "/api/v1/thread-reads/{scope_id}/retry-close", operation_id = "thread.read.retryClose", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn retry_read_close(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        state
            .thread_transports
            .get_read(&id)?
            .close_report(id)
            .await,
    ))
}
