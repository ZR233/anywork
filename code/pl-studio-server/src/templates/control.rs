use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use pl_protocol::studio::{FeedCloseOutcome, FeedCloseReport};

use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, ApiPath as Path, StudioApiErrors};
use super::types::{AckRequest, EmptyRequest};

#[utoipa::path(post, path = "/api/v1/feeds/{feed_id}/ack", operation_id = "feed.ack", params(("feed_id" = String, Path)), request_body = AckRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn ack(State(state): State<AppState>, Path(id): Path<String>, ApiJson(body): ApiJson<AckRequest>) -> Result<StatusCode, ApiError> {
    let owner = state.templates.feed(&id)?;
    let feed = owner.runtime_feed().ok_or_else(super::tasks::cancelled)?;
    owner.admit(|| feed.ack_through(body.delivery_sequence))?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/feeds/{feed_id}/request-close", operation_id = "feed.requestClose", params(("feed_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn request_close(State(state): State<AppState>, Path(id): Path<String>, ApiJson(_): ApiJson<EmptyRequest>) -> Result<StatusCode, ApiError> {
    state.templates.feed(&id)?.request_close();
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/feeds/{feed_id}/close", operation_id = "feed.close", params(("feed_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn close(State(state): State<AppState>, Path(id): Path<String>, ApiJson(_): ApiJson<EmptyRequest>) -> Result<Json<FeedCloseReport>, ApiError> {
    let issues = state.templates.feed(&id)?.close_issues().await;
    let report = FeedCloseReport { feed_id: id, outcome: if issues.is_empty() { FeedCloseOutcome::Clean }
        else { FeedCloseOutcome::Unresolved { issues } } };
    state.templates.reap();
    Ok(Json(report))
}

#[utoipa::path(post, path = "/api/v1/feeds/{feed_id}/retry-close", operation_id = "feed.retryClose", params(("feed_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn retry_close(State(state): State<AppState>, Path(id): Path<String>, body: ApiJson<EmptyRequest>) -> Result<Json<FeedCloseReport>, ApiError> {
    close(State(state), Path(id), body).await
}

#[utoipa::path(post, path = "/api/v1/read-scopes/{scope_id}/request-close", operation_id = "read.requestClose", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn request_read_close(State(state): State<AppState>, Path(id): Path<String>, ApiJson(_): ApiJson<EmptyRequest>) -> Result<StatusCode, ApiError> {
    state.templates.read(&id)?.request_close();
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/read-scopes/{scope_id}/close", operation_id = "read.close", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn read_close(State(state): State<AppState>, Path(id): Path<String>, ApiJson(_): ApiJson<EmptyRequest>) -> Result<Json<FeedCloseReport>, ApiError> {
    let issues = state.templates.read(&id)?.close().await;
    let report = FeedCloseReport { feed_id: id, outcome: if issues.is_empty() { FeedCloseOutcome::Clean }
        else { FeedCloseOutcome::Unresolved { issues } } };
    Ok(Json(report))
}

#[utoipa::path(post, path = "/api/v1/read-scopes/{scope_id}/retry-close", operation_id = "read.retryClose", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn retry_read_close(State(state): State<AppState>, Path(id): Path<String>, body: ApiJson<EmptyRequest>) -> Result<Json<FeedCloseReport>, ApiError> {
    read_close(State(state), Path(id), body).await
}
