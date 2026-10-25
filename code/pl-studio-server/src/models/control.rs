use super::types::AckRequest;
use crate::{
    AppState,
    error::ApiError,
    routes::{ApiJson, ApiPath, StudioApiErrors},
};
use axum::{Json, extract::State, http::StatusCode};
use pl_protocol::studio::FeedCloseReport;

#[utoipa::path(post, path = "/api/v1/model-catalog-feeds/{feed_id}/ack", operation_id = "modelCatalog.ack", params(("feed_id" = String, Path)), request_body = AckRequest, responses(StudioApiErrors, (status = 204)))]
pub(super) async fn ack(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<AckRequest>,
) -> Result<StatusCode, ApiError> {
    state.models.feed(&id)?.ack(body.delivery_sequence)?;
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/model-catalog-feeds/{feed_id}/request-close", operation_id = "modelCatalog.requestClose", params(("feed_id" = String, Path)), responses(StudioApiErrors, (status = 204)))]
pub(super) async fn request_close(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<StatusCode, ApiError> {
    state.models.feed(&id)?.request_close();
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/model-catalog-feeds/{feed_id}/close", operation_id = "modelCatalog.close", params(("feed_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn close(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(state.models.feed(&id)?.close_report().await?))
}
#[utoipa::path(post, path = "/api/v1/model-catalog-feeds/{feed_id}/retry-close", operation_id = "modelCatalog.retryClose", params(("feed_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn retry_close(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(state.models.feed(&id)?.close_report().await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/request-close", operation_id = "models.read.requestClose", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 204)))]
pub(super) async fn request_read_close(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<StatusCode, ApiError> {
    state.models.read(&id, None)?.request_close();
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/close", operation_id = "models.read.close", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn read_close(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        state.models.read(&id, None)?.close_report(false).await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/retry-close", operation_id = "models.read.retryClose", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn retry_read_close(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        state.models.read(&id, None)?.close_report(true).await?,
    ))
}
