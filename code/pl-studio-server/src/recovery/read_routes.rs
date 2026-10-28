use axum::Json;
use axum::extract::State;
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::primitives::TextReadPage;
use pl_protocol::products::read::recovery::{
    RecoveryEntityRead, RecoveryEntryPage, RecoveryIssueReadPage, RecoveryReadHeader,
};
use pl_protocol::products::source::ProductSourceStatusReadHeader;
use pl_protocol::studio::TextChunk;

use super::{native::OpenReadKind, types::*};
use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, ApiPath as Path, StudioApiErrors};
use crate::templates::EmptyRequest;

async fn opened(
    state: &AppState,
    feed_id: &str,
    kind: OpenReadKind,
) -> Result<Json<RecoveryOpenReadReply>, ApiError> {
    let mut opening = state
        .recovery
        .feed(feed_id)?
        .open_read(&state.runtime, kind)?;
    let identity = opening.ready().await?;
    opening.adopt()?;
    Ok(Json(RecoveryOpenReadReply {
        scope_id: identity.scope_id.clone(),
        identity,
    }))
}

#[utoipa::path(post, path = "/api/v1/reads/recovery", operation_id = "recovery.read.open", request_body = RecoveryOpenReadRequest, responses(StudioApiErrors, (status = 200, body = RecoveryOpenReadReply)))]
pub(super) async fn open(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<RecoveryOpenReadRequest>,
) -> Result<Json<RecoveryOpenReadReply>, ApiError> {
    opened(&state, &body.feed_id, OpenReadKind::Value(body.reference)).await
}

#[utoipa::path(post, path = "/api/v1/reads/recovery-source-status", operation_id = "recovery.sourceStatus.open", request_body = RecoveryOpenStatusRequest, responses(StudioApiErrors, (status = 200, body = RecoveryOpenReadReply)))]
pub(super) async fn open_source(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<RecoveryOpenStatusRequest>,
) -> Result<Json<RecoveryOpenReadReply>, ApiError> {
    opened(
        &state,
        &body.feed_id,
        OpenReadKind::SourceStatus(body.reference),
    )
    .await
}

#[utoipa::path(post, path = "/api/v1/recovery-reads/{scope_id}/header", operation_id = "recovery.read.header", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = RecoveryReadHeader)))]
pub(super) async fn header(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<RecoveryReadHeader>, ApiError> {
    Ok(Json(
        state
            .recovery
            .read(&id)?
            .query(|source| Ok(source.value()?.header()))?
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/recovery-reads/{scope_id}/entries", operation_id = "recovery.read.entries", params(("scope_id" = String, Path)), request_body = RecoveryEntriesRequest, responses(StudioApiErrors, (status = 200, body = RecoveryEntryPage)))]
pub(super) async fn entries(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<RecoveryEntriesRequest>,
) -> Result<Json<RecoveryEntryPage>, ApiError> {
    Ok(Json(
        state
            .recovery
            .read(&id)?
            .query(|source| {
                Ok(source
                    .value()?
                    .entries(body.offset, body.limit.unwrap_or(32)))
            })?
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/recovery-reads/{scope_id}/entity", operation_id = "recovery.read.entity", params(("scope_id" = String, Path)), request_body = RecoveryEntityRequest, responses(StudioApiErrors, (status = 200, body = RecoveryEntityRead)))]
pub(super) async fn entity(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<RecoveryEntityRequest>,
) -> Result<Json<RecoveryEntityRead>, ApiError> {
    Ok(Json(
        state
            .recovery
            .read(&id)?
            .query(|source| Ok(source.value()?.entity(body.reference)))?
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/recovery-reads/{scope_id}/lookup-issue", operation_id = "recovery.read.lookupIssue", params(("scope_id" = String, Path)), request_body = RecoveryLookupIssueRequest, responses(StudioApiErrors, (status = 200, body = Option<ProductEntityRef>)))]
pub(super) async fn lookup_issue(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<RecoveryLookupIssueRequest>,
) -> Result<Json<Option<ProductEntityRef>>, ApiError> {
    Ok(Json(
        state
            .recovery
            .read(&id)?
            .query(|source| Ok(source.value()?.lookup_issue(body.issue_id)))?
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/recovery-reads/{scope_id}/issues", operation_id = "recovery.read.issues", params(("scope_id" = String, Path)), request_body = RecoveryListRequest, responses(StudioApiErrors, (status = 200, body = RecoveryIssueReadPage)))]
pub(super) async fn issues(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<RecoveryListRequest>,
) -> Result<Json<RecoveryIssueReadPage>, ApiError> {
    Ok(Json(
        state
            .recovery
            .read(&id)?
            .query(|source| {
                Ok(source
                    .value()?
                    .issues(body.list_id, body.offset, body.limit.unwrap_or(32)))
            })?
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/recovery-reads/{scope_id}/changed-files", operation_id = "recovery.read.changedFiles", params(("scope_id" = String, Path)), request_body = RecoveryListRequest, responses(StudioApiErrors, (status = 200, body = TextReadPage)))]
pub(super) async fn changed_files(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<RecoveryListRequest>,
) -> Result<Json<TextReadPage>, ApiError> {
    Ok(Json(
        state
            .recovery
            .read(&id)?
            .query(|source| {
                Ok(source.value()?.changed_files(
                    body.list_id,
                    body.offset,
                    body.limit.unwrap_or(32),
                ))
            })?
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/recovery-reads/{scope_id}/text", operation_id = "recovery.read.text", params(("scope_id" = String, Path)), request_body = RecoveryTextRequest, responses(StudioApiErrors, (status = 200, body = TextChunk)))]
pub(super) async fn text(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<RecoveryTextRequest>,
) -> Result<Json<TextChunk>, ApiError> {
    Ok(Json(
        state
            .recovery
            .read(&id)?
            .query(|source| {
                Ok(source.value()?.text(
                    body.field_id,
                    body.offset,
                    body.max_bytes.unwrap_or(65536),
                ))
            })?
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/recovery-reads/{scope_id}/source-header", operation_id = "recovery.sourceStatus.header", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = ProductSourceStatusReadHeader)))]
pub(super) async fn source_header(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<ProductSourceStatusReadHeader>, ApiError> {
    Ok(Json(
        state
            .recovery
            .read(&id)?
            .query(|source| Ok(source.status()?.header()))?
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/recovery-reads/{scope_id}/source-text", operation_id = "recovery.sourceStatus.text", params(("scope_id" = String, Path)), request_body = RecoveryTextRequest, responses(StudioApiErrors, (status = 200, body = TextChunk)))]
pub(super) async fn source_text(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<RecoveryTextRequest>,
) -> Result<Json<TextChunk>, ApiError> {
    Ok(Json(
        state
            .recovery
            .read(&id)?
            .query(|source| {
                Ok(source.status()?.text(
                    body.field_id,
                    body.offset,
                    body.max_bytes.unwrap_or(65536),
                ))
            })?
            .await?,
    ))
}
