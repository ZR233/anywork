use super::types::{AckRequest, EmptyRequest};
use crate::{
    AppState,
    error::ApiError,
    routes::{ApiJson, ApiPath as Path, StudioApiErrors},
};
use axum::{Json, extract::State, http::StatusCode};
use pl_protocol::studio::{FeedCloseOutcome, FeedCloseReport};

#[utoipa::path(post, path = "/api/v1/configuration-feeds/{feed_id}/ack", operation_id = "configuration.feed.ack", params(("feed_id" = String, Path)), request_body = AckRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn ack(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<AckRequest>,
) -> Result<StatusCode, ApiError> {
    let owner = state.configuration.feed(&id)?;
    let feed = owner.runtime_feed().ok_or_else(super::tasks::cancelled)?;
    owner.admit(|| feed.ack_through(body.delivery_sequence))?;
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/configuration-feeds/{feed_id}/request-close", operation_id = "configuration.feed.requestClose", params(("feed_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn request_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<StatusCode, ApiError> {
    state.configuration.feed(&id)?.request_close();
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/configuration-feeds/{feed_id}/close", operation_id = "configuration.feed.close", params(("feed_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    let issues = state.configuration.feed(&id)?.close_issues().await;
    let report = FeedCloseReport {
        feed_id: id,
        outcome: if issues.is_empty() {
            FeedCloseOutcome::Clean
        } else {
            FeedCloseOutcome::Unresolved { issues }
        },
    };
    state.configuration.reap();
    Ok(Json(report))
}
#[utoipa::path(post, path = "/api/v1/configuration-feeds/{feed_id}/retry-close", operation_id = "configuration.feed.retryClose", params(("feed_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn retry_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    body: ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    close(State(state), Path(id), body).await
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/request-close", operation_id = "configuration.read.requestClose", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn request_read_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<StatusCode, ApiError> {
    state.configuration.read(&id)?.request_close();
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/close", operation_id = "configuration.read.close", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn read_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    let issues = state.configuration.read(&id)?.close().await;
    Ok(Json(FeedCloseReport {
        feed_id: id,
        outcome: if issues.is_empty() {
            FeedCloseOutcome::Clean
        } else {
            FeedCloseOutcome::Unresolved { issues }
        },
    }))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/retry-close", operation_id = "configuration.read.retryClose", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn retry_read_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    body: ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    read_close(State(state), Path(id), body).await
}
