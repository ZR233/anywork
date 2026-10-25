use super::UploadPermit;
use super::upload::Upload;
use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, ApiPath, ApiQuery, StudioApiErrors};
use axum::extract::{DefaultBodyLimit, Request, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response, Sse, sse::KeepAlive};
use axum::{Extension, Json};
use pl_protocol::studio::{
    AdmitAttachmentDraftsRequest, AttachmentAdmissionIdentity, AttachmentAdmissionOutcome,
    BeginAttachmentAdmissionRequest, BeginThreadCreationRequest, CreateThreadRequest,
    CreatedInputExecutionIdentity, FeedCloseReport, StudioError, StudioErrorCode,
    ThreadCreationIdentity, ThreadCreationOutcome, ThreadPreparationProgress,
};
use pl_protocol::thread_facets::execution::ExecutionFrame;
use pl_studio_runtime::draft_commands::{StudioAttachmentAdmission, StudioThreadCreation};
use std::sync::Arc;
use utoipa_axum::{router::OpenApiRouter, routes};

#[derive(serde::Deserialize, utoipa::IntoParams)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[into_params(parameter_in = Query, rename_all = "camelCase")]
pub(super) struct OperationQuery {
    operation_id: String,
}

pub(crate) fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(begin_admission))
        .routes(routes!(find_admission))
        .routes(routes!(admission_result))
        .routes(routes!(admission_request_close))
        .routes(routes!(admission_close))
        .routes(routes!(admission_retry_close))
        .routes(routes!(begin_creation))
        .routes(routes!(find_creation))
        .routes(routes!(creation_result))
        .routes(routes!(creation_progress))
        .routes(routes!(creation_source))
        .routes(routes!(creation_events))
        .routes(routes!(creation_request_close))
        .routes(routes!(creation_close))
        .routes(routes!(creation_retry_close))
        .routes(routes!(find_upload))
        .routes(routes!(upload_result))
        .routes(routes!(upload_request_close))
        .routes(routes!(upload_close))
        .routes(routes!(upload_retry_close))
        .routes(routes!(admit_attachment_drafts))
        .routes(routes!(create_thread))
}
pub(crate) fn upload_router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(upload_attachment_drafts))
        .layer(DefaultBodyLimit::max(super::staging::MAX_BODY_BYTES))
}

fn remote_only(request: &AdmitAttachmentDraftsRequest) -> Result<(), StudioError> {
    if request.sources.iter().any(|source| {
        !matches!(
            source,
            pl_protocol::studio::StudioAttachmentDraftSource::RemoteUrl { .. }
        )
    }) {
        return Err(StudioError::invalid_argument(
            "JSON attachment admission accepts only remoteUrl sources; local files use multipart upload",
        ));
    }
    Ok(())
}
fn admission(state: &AppState, id: &str) -> Result<StudioAttachmentAdmission, ApiError> {
    state
        .draft_commands
        .admission(&state.runtime, id)?
        .ok_or_else(|| StudioError::not_found("AttachmentAdmission").into())
}
fn creation(state: &AppState, id: &str) -> Result<StudioThreadCreation, ApiError> {
    state
        .draft_commands
        .creation(&state.runtime, id)?
        .ok_or_else(|| StudioError::not_found("ThreadCreation").into())
}
fn upload(state: &AppState, id: &str) -> Result<Arc<Upload>, ApiError> {
    state
        .draft_commands
        .upload(id)?
        .ok_or_else(|| StudioError::not_found("AttachmentUpload").into())
}
async fn close_admission(
    state: &AppState,
    id: String,
    retry: bool,
) -> Result<Json<FeedCloseReport>, ApiError> {
    let job = admission(state, &id)?;
    let report = if retry {
        job.retry_close().await
    } else {
        job.close().await
    };
    state.draft_commands.reap();
    Ok(Json(report))
}
async fn close_creation(
    state: &AppState,
    id: String,
    retry: bool,
) -> Result<Json<FeedCloseReport>, ApiError> {
    let job = creation(state, &id)?;
    let report = if retry {
        job.retry_close().await
    } else {
        job.close().await
    };
    state.draft_commands.reap();
    Ok(Json(report))
}

#[utoipa::path(post, path = "/api/v1/attachment-admissions", operation_id = "attachment.admission.begin", request_body = BeginAttachmentAdmissionRequest, responses(StudioApiErrors, (status = 200, body = AttachmentAdmissionIdentity)))]
async fn begin_admission(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<BeginAttachmentAdmissionRequest>,
) -> Result<Json<AttachmentAdmissionIdentity>, ApiError> {
    remote_only(&body.request)?;
    Ok(Json(
        state
            .draft_commands
            .begin_admission(&state.runtime, body.operation_id, body.request)?
            .identity(),
    ))
}
#[utoipa::path(get, path = "/api/v1/attachment-admissions/find", operation_id = "attachment.admission.find", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = Option<AttachmentAdmissionIdentity>)))]
async fn find_admission(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<Option<AttachmentAdmissionIdentity>>, ApiError> {
    Ok(Json(
        state
            .draft_commands
            .admission(&state.runtime, &query.operation_id)?
            .map(|job| job.identity()),
    ))
}
#[utoipa::path(get, path = "/api/v1/attachment-admissions/result", operation_id = "attachment.admission.result", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = AttachmentAdmissionOutcome)))]
async fn admission_result(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<AttachmentAdmissionOutcome>, ApiError> {
    Ok(Json(admission(&state, &query.operation_id)?.result().await))
}
#[utoipa::path(post, path = "/api/v1/attachment-admissions/request-close", operation_id = "attachment.admission.requestClose", params(OperationQuery), responses(StudioApiErrors, (status = 204)))]
async fn admission_request_close(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<StatusCode, ApiError> {
    admission(&state, &query.operation_id)?.request_close();
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/attachment-admissions/close", operation_id = "attachment.admission.close", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn admission_close(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    close_admission(&state, query.operation_id, false).await
}
#[utoipa::path(post, path = "/api/v1/attachment-admissions/retry-close", operation_id = "attachment.admission.retryClose", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn admission_retry_close(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    close_admission(&state, query.operation_id, true).await
}

#[utoipa::path(post, path = "/api/v1/thread-creations", operation_id = "thread.creation.begin", request_body = BeginThreadCreationRequest, responses(StudioApiErrors, (status = 200, body = ThreadCreationIdentity)))]
async fn begin_creation(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<BeginThreadCreationRequest>,
) -> Result<Json<ThreadCreationIdentity>, ApiError> {
    Ok(Json(
        state
            .draft_commands
            .begin_creation(&state.runtime, body)?
            .identity(),
    ))
}
#[utoipa::path(get, path = "/api/v1/thread-creations/find", operation_id = "thread.creation.find", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = Option<ThreadCreationIdentity>)))]
async fn find_creation(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<Option<ThreadCreationIdentity>>, ApiError> {
    Ok(Json(
        state
            .draft_commands
            .creation(&state.runtime, &query.operation_id)?
            .map(|job| job.identity()),
    ))
}
#[utoipa::path(get, path = "/api/v1/thread-creations/result", operation_id = "thread.creation.result", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = ThreadCreationOutcome)))]
async fn creation_result(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<ThreadCreationOutcome>, ApiError> {
    Ok(Json(creation(&state, &query.operation_id)?.result().await))
}
#[utoipa::path(get, path = "/api/v1/thread-creations/progress", operation_id = "thread.creation.progress", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = ThreadPreparationProgress, content_type = "text/event-stream")))]
async fn creation_progress(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
    headers: HeaderMap,
) -> Result<Response, ApiError> {
    if headers.contains_key("last-event-id") {
        return Err(StudioError::new(
            StudioErrorCode::Conflict,
            "Preparation progress does not support replay",
            false,
        )
        .into());
    }
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let body = super::progress::ProgressBody::new(
        creation(&state, &query.operation_id)?.subscribe_progress()?,
        permit,
    );
    Ok(Sse::new(body)
        .keep_alive(KeepAlive::default())
        .into_response())
}
#[utoipa::path(get, path = "/api/v1/thread-creations/execution-source", operation_id = "thread.creation.executionSource", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = CreatedInputExecutionIdentity)))]
async fn creation_source(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<CreatedInputExecutionIdentity>, ApiError> {
    let source = creation(&state, &query.operation_id)?
        .execution_source()
        .await?;
    Ok(Json(CreatedInputExecutionIdentity {
        thread_id: source.thread_id(),
        input_id: source.input_id(),
        runtime_epoch: source.runtime_epoch(),
        incarnation: source.incarnation(),
    }))
}
#[utoipa::path(post, path = "/api/v1/thread-creations/execution/events", operation_id = "thread.creation.executionEvents", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = ExecutionFrame, content_type = "text/event-stream")))]
async fn creation_events(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
    headers: HeaderMap,
) -> Result<Response, ApiError> {
    let source = creation(&state, &query.operation_id)?
        .execution_source()
        .await?;
    crate::thread_transport::open_created_execution(state, source, headers).await
}
#[utoipa::path(post, path = "/api/v1/thread-creations/request-close", operation_id = "thread.creation.requestClose", params(OperationQuery), responses(StudioApiErrors, (status = 204)))]
async fn creation_request_close(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<StatusCode, ApiError> {
    creation(&state, &query.operation_id)?.request_close();
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/thread-creations/close", operation_id = "thread.creation.close", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn creation_close(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    close_creation(&state, query.operation_id, false).await
}
#[utoipa::path(post, path = "/api/v1/thread-creations/retry-close", operation_id = "thread.creation.retryClose", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn creation_retry_close(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    close_creation(&state, query.operation_id, true).await
}

#[utoipa::path(get, path = "/api/v1/attachment-uploads/find", operation_id = "attachment.upload.find", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = Option<AttachmentAdmissionIdentity>)))]
async fn find_upload(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<Option<AttachmentAdmissionIdentity>>, ApiError> {
    Ok(Json(
        state
            .draft_commands
            .upload(&query.operation_id)?
            .map(|owner| owner.identity()),
    ))
}
#[utoipa::path(get, path = "/api/v1/attachment-uploads/result", operation_id = "attachment.upload.result", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = AttachmentAdmissionOutcome)))]
async fn upload_result(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<AttachmentAdmissionOutcome>, ApiError> {
    Ok(Json(upload(&state, &query.operation_id)?.result().await))
}
#[utoipa::path(post, path = "/api/v1/attachment-uploads/request-close", operation_id = "attachment.upload.requestClose", params(OperationQuery), responses(StudioApiErrors, (status = 204)))]
async fn upload_request_close(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<StatusCode, ApiError> {
    upload(&state, &query.operation_id)?.request_close();
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/attachment-uploads/close", operation_id = "attachment.upload.close", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn upload_close(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(
        upload(&state, &query.operation_id)?.close(false).await,
    ))
}
#[utoipa::path(post, path = "/api/v1/attachment-uploads/retry-close", operation_id = "attachment.upload.retryClose", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn upload_retry_close(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    Ok(Json(upload(&state, &query.operation_id)?.close(true).await))
}

#[utoipa::path(post, path = "/api/v1/attachments/drafts", operation_id = "attachment.admit", params(OperationQuery), request_body = AdmitAttachmentDraftsRequest, responses(StudioApiErrors, (status = 200, body = AttachmentAdmissionOutcome)))]
async fn admit_attachment_drafts(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
    ApiJson(request): ApiJson<AdmitAttachmentDraftsRequest>,
) -> Result<Json<AttachmentAdmissionOutcome>, ApiError> {
    remote_only(&request)?;
    let job = state
        .draft_commands
        .begin_admission(&state.runtime, query.operation_id, request)?;
    Ok(Json(job.result().await))
}
#[utoipa::path(post, path = "/api/v1/projects/{project_id}/threads", operation_id = "thread.create", params(("project_id" = String, Path), OperationQuery), request_body = CreateThreadRequest, responses(StudioApiErrors, (status = 200, body = ThreadCreationOutcome)))]
async fn create_thread(
    State(state): State<AppState>,
    ApiPath(project_id): ApiPath<String>,
    ApiQuery(query): ApiQuery<OperationQuery>,
    ApiJson(request): ApiJson<CreateThreadRequest>,
) -> Result<Json<ThreadCreationOutcome>, ApiError> {
    let job = state.draft_commands.begin_creation(
        &state.runtime,
        BeginThreadCreationRequest {
            operation_id: query.operation_id,
            project_id,
            request,
        },
    )?;
    Ok(Json(job.result().await))
}
#[utoipa::path(post, path = "/api/v1/attachments/drafts/upload", operation_id = "attachment.upload", params(OperationQuery), responses(StudioApiErrors, (status = 200, body = AttachmentAdmissionOutcome)))]
async fn upload_attachment_drafts(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<OperationQuery>,
    Extension(permit): Extension<UploadPermit>,
    request: Request,
) -> Result<Json<AttachmentAdmissionOutcome>, ApiError> {
    let owner = state.draft_commands.begin_upload(
        state.runtime.clone(),
        query.operation_id,
        permit,
        request,
    )?;
    Ok(Json(owner.result().await))
}
