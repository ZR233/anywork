use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use pl_protocol::studio::FeedCloseReport;

use super::{tasks, types::RecoveryAckRequest};
use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, ApiPath as Path, StudioApiErrors};
use crate::templates::EmptyRequest;

#[utoipa::path(post, path = "/api/v1/recovery-feeds/{feed_id}/ack", operation_id = "recovery.feed.ack", params(("feed_id" = String, Path)), request_body = RecoveryAckRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn ack(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<RecoveryAckRequest>,
) -> Result<StatusCode, ApiError> {
    let owner = state.recovery.feed(&id)?;
    let feed = owner.runtime_feed().ok_or_else(tasks::cancelled)?;
    owner.admit(|| feed.ack_through(body.delivery_sequence))?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/recovery-feeds/{feed_id}/request-close", operation_id = "recovery.feed.requestClose", params(("feed_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn request_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<StatusCode, ApiError> {
    state.recovery.feed(&id)?.request_close();
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/recovery-feeds/{feed_id}/close", operation_id = "recovery.feed.close", params(("feed_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    close_feed(&state, id, false).await
}

#[utoipa::path(post, path = "/api/v1/recovery-feeds/{feed_id}/retry-close", operation_id = "recovery.feed.retryClose", params(("feed_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn retry_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    close_feed(&state, id, true).await
}

async fn close_feed(
    state: &AppState,
    id: String,
    retry: bool,
) -> Result<Json<FeedCloseReport>, ApiError> {
    let issues = state.recovery.feed(&id)?.close_issues(retry).await;
    let report = tasks::report(id, issues);
    state.recovery.reap();
    Ok(Json(report))
}

#[utoipa::path(post, path = "/api/v1/recovery-reads/{scope_id}/request-close", operation_id = "recovery.read.requestClose", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn request_read_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<StatusCode, ApiError> {
    state.recovery.read(&id)?.request_close();
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/recovery-reads/{scope_id}/close", operation_id = "recovery.read.close", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn read_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    let issues = state.recovery.read(&id)?.close(false).await;
    Ok(Json(tasks::report(id, issues)))
}

#[utoipa::path(post, path = "/api/v1/recovery-reads/{scope_id}/retry-close", operation_id = "recovery.read.retryClose", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn retry_read_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    let issues = state.recovery.read(&id)?.close(true).await;
    Ok(Json(tasks::report(id, issues)))
}
