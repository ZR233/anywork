//! Named Profiles control endpoints dispatch to the same original domain owners.
use super::{
    control,
    types::{AckRequest, EmptyRequest},
};
use crate::{
    AppState,
    error::ApiError,
    routes::{ApiJson, ApiPath as Path, StudioApiErrors},
};
use axum::{Json, extract::State, http::StatusCode};
use pl_protocol::studio::FeedCloseReport;

#[utoipa::path(post, path = "/api/v1/agent-profiles-feeds/{feed_id}/ack", operation_id = "agentProfiles.feed.ack", params(("feed_id" = String, Path)), request_body = AckRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn ack(
    state: State<AppState>,
    id: Path<String>,
    body: ApiJson<AckRequest>,
) -> Result<StatusCode, ApiError> {
    control::ack(state, id, body).await
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-feeds/{feed_id}/request-close", operation_id = "agentProfiles.feed.requestClose", params(("feed_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn request_close(
    state: State<AppState>,
    id: Path<String>,
    body: ApiJson<EmptyRequest>,
) -> Result<StatusCode, ApiError> {
    control::request_close(state, id, body).await
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-feeds/{feed_id}/close", operation_id = "agentProfiles.feed.close", params(("feed_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn close(
    state: State<AppState>,
    id: Path<String>,
    body: ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    control::close(state, id, body).await
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-feeds/{feed_id}/retry-close", operation_id = "agentProfiles.feed.retryClose", params(("feed_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn retry_close(
    state: State<AppState>,
    id: Path<String>,
    body: ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    control::retry_close(state, id, body).await
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-reads/{scope_id}/request-close", operation_id = "agentProfiles.read.requestClose", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn request_read_close(
    state: State<AppState>,
    id: Path<String>,
    body: ApiJson<EmptyRequest>,
) -> Result<StatusCode, ApiError> {
    control::request_read_close(state, id, body).await
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-reads/{scope_id}/close", operation_id = "agentProfiles.read.close", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn read_close(
    state: State<AppState>,
    id: Path<String>,
    body: ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    control::read_close(state, id, body).await
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-reads/{scope_id}/retry-close", operation_id = "agentProfiles.read.retryClose", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn retry_read_close(
    state: State<AppState>,
    id: Path<String>,
    body: ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    control::retry_read_close(state, id, body).await
}
