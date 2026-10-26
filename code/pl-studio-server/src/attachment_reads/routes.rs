use axum::Json;
use axum::body::Bytes;
use axum::extract::State;
use axum::http::{HeaderMap, HeaderValue, header};
use pl_protocol::studio::{
    AttachmentBinaryOpenReply, AttachmentBinaryTarget, FeedCloseReport, OpenDraftBinaryRequest,
    OpenThreadBinaryRequest, StudioError,
};
use utoipa_axum::{router::OpenApiRouter, routes};

use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, ApiPath, ApiQuery, StudioApiErrors};

#[derive(serde::Deserialize, utoipa::IntoParams)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[into_params(parameter_in = Query, rename_all = "camelCase")]
struct BinaryQuery {
    offset: i64,
    max_bytes: Option<i64>,
}

pub(crate) fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(open_draft))
        .routes(routes!(open_thread))
        .routes(routes!(bytes))
        .routes(routes!(close))
        .routes(routes!(retry_close))
}

#[utoipa::path(post, path = "/api/v1/attachment-reads/draft", operation_id = "attachment.openDraftBinary", request_body = OpenDraftBinaryRequest, responses(StudioApiErrors, (status = 200, body = AttachmentBinaryOpenReply)))]
async fn open_draft(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<OpenDraftBinaryRequest>,
) -> Result<Json<AttachmentBinaryOpenReply>, ApiError> {
    let mut opening = state.attachment_reads.open(
        state.runtime.clone(),
        AttachmentBinaryTarget::Draft {
            draft_id: body.draft_id,
        },
    )?;
    let reply = opening.ready().await?;
    opening.adopt()?;
    Ok(Json(reply))
}

#[utoipa::path(post, path = "/api/v1/attachment-reads/thread", operation_id = "attachment.openThreadBinary", request_body = OpenThreadBinaryRequest, responses(StudioApiErrors, (status = 200, body = AttachmentBinaryOpenReply)))]
async fn open_thread(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<OpenThreadBinaryRequest>,
) -> Result<Json<AttachmentBinaryOpenReply>, ApiError> {
    let mut opening = state.attachment_reads.open(
        state.runtime.clone(),
        AttachmentBinaryTarget::Thread {
            thread_id: body.thread_id,
            attachment_id: body.attachment_id,
        },
    )?;
    let reply = opening.ready().await?;
    opening.adopt()?;
    Ok(Json(reply))
}

#[utoipa::path(get, path = "/api/v1/attachment-reads/{scope_id}/bytes", operation_id = "attachment.readBinary", params(("scope_id" = String, Path), BinaryQuery), responses(StudioApiErrors, (status = 200, body = Vec<u8>, content_type = "application/octet-stream", headers(("Anywork-Offset" = i64, description = "This block's original byte offset"), ("Anywork-Next-Offset" = Option<i64>, description = "Present only for nonterminal blocks")))))]
async fn bytes(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiQuery(query): ApiQuery<BinaryQuery>,
) -> Result<(HeaderMap, Bytes), ApiError> {
    let read = state.attachment_reads.read(&id)?;
    let chunk = read
        .query(|read| read.read(query.offset, query.max_bytes))?
        .await?;
    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/octet-stream"),
    );
    headers.insert("anywork-offset", header_number(chunk.offset)?);
    if let Some(next) = chunk.next_offset {
        headers.insert("anywork-next-offset", header_number(next)?);
    }
    Ok((headers, Bytes::from(chunk.bytes)))
}

#[utoipa::path(post, path = "/api/v1/attachment-reads/{scope_id}/close", operation_id = "attachment.closeBinary", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn close(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        state.attachment_reads.read(&id)?.close_report(id).await,
    ))
}

#[utoipa::path(post, path = "/api/v1/attachment-reads/{scope_id}/retry-close", operation_id = "attachment.retryCloseBinary", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn retry_close(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        state.attachment_reads.read(&id)?.close_report(id).await,
    ))
}

fn header_number(value: i64) -> Result<HeaderValue, ApiError> {
    HeaderValue::from_str(&value.to_string()).map_err(|_| ApiError(StudioError::internal()))
}
