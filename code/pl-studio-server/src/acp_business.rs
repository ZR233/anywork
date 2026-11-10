//! ACP production HTTP boundary. The runtime owns sessions, publication and SDK IO.

mod frames;
#[cfg(test)]
mod tests;

use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::{IntoResponse, Response};
use futures::stream;
use pl_protocol::studio::*;
use utoipa_axum::{router::OpenApiRouter, routes};

use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, StudioApiErrors};
use frames::OpenFrames;

pub(crate) fn routes() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(open))
        .routes(routes!(prompt))
        .routes(routes!(replace))
        .routes(routes!(interrupt))
        .routes(routes!(configure))
        .routes(routes!(set_mode))
        .routes(routes!(permission))
        .routes(routes!(list))
        .routes(routes!(snapshot))
        .routes(routes!(close))
}

/// Preserve business diagnostics, including original RPC data and auth methods.
enum AcpApiError {
    Business(AcpBusinessFailure),
    Runtime(ApiError),
}

impl From<AcpBusinessFailure> for AcpApiError {
    fn from(error: AcpBusinessFailure) -> Self {
        Self::Business(error)
    }
}

impl From<anyhow::Error> for AcpApiError {
    fn from(error: anyhow::Error) -> Self {
        match error.downcast::<AcpBusinessFailure>() {
            Ok(error) => Self::Business(error),
            Err(error) => Self::Runtime(ApiError::from(error)),
        }
    }
}

impl IntoResponse for AcpApiError {
    fn into_response(self) -> Response {
        match self {
            Self::Runtime(error) => error.into_response(),
            Self::Business(error) => {
                let status = match error.kind {
                    AcpBusinessFailureKind::Busy
                    | AcpBusinessFailureKind::Stale
                    | AcpBusinessFailureKind::NotReady => StatusCode::CONFLICT,
                    AcpBusinessFailureKind::Closed => StatusCode::GONE,
                    AcpBusinessFailureKind::Unsupported => StatusCode::NOT_IMPLEMENTED,
                    AcpBusinessFailureKind::UnsupportedVersion
                    | AcpBusinessFailureKind::ServerVersionMismatch
                    | AcpBusinessFailureKind::InvalidOption => StatusCode::BAD_REQUEST,
                    AcpBusinessFailureKind::Rpc => StatusCode::BAD_GATEWAY,
                    AcpBusinessFailureKind::InstallRequired
                    | AcpBusinessFailureKind::InstallationInvalid
                    | AcpBusinessFailureKind::UnsupportedPlatform
                    | AcpBusinessFailureKind::MissingExecutable
                    | AcpBusinessFailureKind::InvalidWorkingDirectory
                    | AcpBusinessFailureKind::InvalidDefinition
                    | AcpBusinessFailureKind::Io
                    | AcpBusinessFailureKind::Cancelled
                    | AcpBusinessFailureKind::Preparation
                    | AcpBusinessFailureKind::Publication => StatusCode::SERVICE_UNAVAILABLE,
                };
                (status, Json(error)).into_response()
            }
        }
    }
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/open", operation_id = "acpSessions.open",
    request_body = OpenAcpSessionRequest,
    responses(StudioApiErrors, (status = 200, body = AcpSessionFrame, content_type = "text/event-stream"),
        (status = 502, body = AcpBusinessFailure)))]
async fn open(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<OpenAcpSessionRequest>,
) -> Result<impl IntoResponse, AcpApiError> {
    // Reserve capacity before admission; rejecting a transport must not open a session.
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| AcpApiError::Runtime(ApiError::overloaded()))?;
    let opened = state.runtime.open_acp_session(request).await?;
    let source = (OpenFrames::new(opened), permit, state.shutdown);
    let events = stream::unfold(source, |(mut frames, permit, shutdown)| async move {
        let frame = tokio::select! {
            biased;
            () = shutdown.cancelled() => return None,
            frame = frames.next() => frame?,
        };
        Some((
            Event::default().event("acpSession").json_data(frame),
            (frames, permit, shutdown),
        ))
    });
    // Dropping this response only drops the observation and its completion waiter.
    // It never calls business close, cancel or interrupt.
    Ok(Sse::new(events).keep_alive(KeepAlive::default()))
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/prompt", operation_id = "acpSessions.prompt",
    request_body = AcpPromptRequest,
    responses(StudioApiErrors, (status = 200, body = AcpRunId), (status = 502, body = AcpBusinessFailure)))]
async fn prompt(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpPromptRequest>,
) -> Result<Json<AcpRunId>, AcpApiError> {
    Ok(Json(
        state
            .runtime
            .prompt_acp_session(request.target, request.content)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/replace", operation_id = "acpSessions.replace",
    request_body = AcpReplaceRequest,
    responses(StudioApiErrors, (status = 200, body = AcpRunId), (status = 502, body = AcpBusinessFailure)))]
async fn replace(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpReplaceRequest>,
) -> Result<Json<AcpRunId>, AcpApiError> {
    Ok(Json(
        state
            .runtime
            .replace_acp_session(request.target, request.run, request.content)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/interrupt", operation_id = "acpSessions.interrupt",
    request_body = AcpInterruptRequest,
    responses(StudioApiErrors, (status = 204), (status = 502, body = AcpBusinessFailure)))]
async fn interrupt(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpInterruptRequest>,
) -> Result<StatusCode, AcpApiError> {
    state
        .runtime
        .interrupt_acp_session(request.target, request.run)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/configure", operation_id = "acpSessions.configure",
    request_body = AcpConfigureRequest,
    responses(StudioApiErrors, (status = 204), (status = 502, body = AcpBusinessFailure)))]
async fn configure(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpConfigureRequest>,
) -> Result<StatusCode, AcpApiError> {
    state
        .runtime
        .configure_acp_session(request.target, request.config_id, request.value)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/set-mode", operation_id = "acpSessions.setMode",
    request_body = AcpSetModeRequest,
    responses(StudioApiErrors, (status = 204), (status = 502, body = AcpBusinessFailure)))]
async fn set_mode(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpSetModeRequest>,
) -> Result<StatusCode, AcpApiError> {
    state
        .runtime
        .set_acp_session_mode(request.target, request.mode_id)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/permission", operation_id = "acpSessions.permission",
    request_body = AcpPermissionAnswerRequest,
    responses(StudioApiErrors, (status = 204), (status = 502, body = AcpBusinessFailure)))]
async fn permission(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpPermissionAnswerRequest>,
) -> Result<StatusCode, AcpApiError> {
    state
        .runtime
        .answer_acp_permission(request.target, request.permission_id, request.option_id)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/list", operation_id = "acpSessions.list",
    request_body = AcpListRequest,
    responses(StudioApiErrors, (status = 200, description = "Official ACP ListSessionsResponse"),
        (status = 502, body = AcpBusinessFailure)))]
async fn list(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpListRequest>,
) -> Result<Json<ListSessionsResponse>, AcpApiError> {
    Ok(Json(
        state
            .runtime
            .list_acp_sessions(request.target, request.request)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/snapshot", operation_id = "acpSessions.snapshot",
    request_body = AcpSessionTarget,
    responses(StudioApiErrors, (status = 200, body = AcpBusinessSnapshot), (status = 502, body = AcpBusinessFailure)))]
async fn snapshot(
    State(state): State<AppState>,
    ApiJson(target): ApiJson<AcpSessionTarget>,
) -> Result<Json<AcpBusinessSnapshot>, AcpApiError> {
    Ok(Json(state.runtime.acp_session_snapshot(target).await?))
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/close", operation_id = "acpSessions.close",
    request_body = AcpSessionTarget,
    responses(StudioApiErrors, (status = 200, body = AcpBusinessClose), (status = 502, body = AcpBusinessFailure)))]
async fn close(
    State(state): State<AppState>,
    ApiJson(target): ApiJson<AcpSessionTarget>,
) -> Result<Json<AcpBusinessClose>, AcpApiError> {
    Ok(Json(state.runtime.close_acp_session(target).await?))
}
