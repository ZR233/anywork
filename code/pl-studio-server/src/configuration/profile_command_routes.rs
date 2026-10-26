//! Concrete endpoints over the existing command index/permit/task, with kind-checked controls.
use super::types::EmptyRequest;
use crate::{
    AppState,
    error::ApiError,
    routes::{ApiJson, ApiPath as Path, StudioApiErrors},
};
use axum::{Json, extract::State, http::StatusCode};
use pl_protocol::products::configuration_calls::{
    ConfigurationCallKind, ConfigurationCallOutcome, ConfigurationCallRequest,
};
use pl_protocol::products::configuration_commands::ConfigurationCommandCallIdentity;
use pl_protocol::products::profile_commands::{
    ConfigurationReloadOutcome, ConfigurationReloadRequest, ProfileCommandOutcome,
    ProfileCommandRequest,
};
use pl_protocol::studio::{FeedCloseOutcome, FeedCloseReport, StudioError};
use serde::Deserialize;
use utoipa::ToSchema;
use utoipa_axum::{router::OpenApiRouter, routes};

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct FindCallRequest {
    operation_id: String,
}

pub(super) fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        // 每个 handler 各自声明自己的 path/method：`routes!` 只产生一个 MethodRouter，
        // 多个同 method 的 handler 放进同一次调用会在装配期重复登记 POST。
        .routes(routes!(begin_profile))
        .routes(routes!(find_profile))
        .routes(routes!(profile_result))
        .routes(routes!(profile_request_close))
        .routes(routes!(profile_close))
        .routes(routes!(profile_retry_close))
        .routes(routes!(begin_reload))
        .routes(routes!(find_reload))
        .routes(routes!(reload_result))
        .routes(routes!(reload_request_close))
        .routes(routes!(reload_close))
        .routes(routes!(reload_retry_close))
}
fn begin(
    state: &AppState,
    request: ConfigurationCallRequest,
) -> Result<Json<ConfigurationCommandCallIdentity>, ApiError> {
    if request.operation_id().trim().is_empty() {
        return Err(StudioError::invalid_argument("operationId is required").into());
    }
    let owner = state.configuration.begin_command(
        state.runtime.clone(),
        &state.shutdown,
        &state.normal_requests,
        request,
    )?;
    Ok(Json(owner.identity()))
}
fn find(
    state: &AppState,
    operation_id: &str,
    kind: ConfigurationCallKind,
) -> Result<Json<Option<ConfigurationCommandCallIdentity>>, ApiError> {
    Ok(Json(
        state
            .configuration
            .find_command(operation_id, kind)?
            .map(|owner| owner.identity()),
    ))
}
async fn close(
    state: AppState,
    id: String,
    kind: ConfigurationCallKind,
) -> Result<Json<FeedCloseReport>, ApiError> {
    let issues = state.configuration.command(&id, kind)?.close().await;
    state.configuration.reap();
    Ok(Json(FeedCloseReport {
        feed_id: id,
        outcome: if issues.is_empty() {
            FeedCloseOutcome::Clean
        } else {
            FeedCloseOutcome::Unresolved { issues }
        },
    }))
}
#[utoipa::path(post, path = "/api/v1/products/agent-profiles/commands/begin", operation_id = "agentProfiles.command.begin", request_body = ProfileCommandRequest, responses(StudioApiErrors, (status = 200, body = ConfigurationCommandCallIdentity)))]
async fn begin_profile(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<ProfileCommandRequest>,
) -> Result<Json<ConfigurationCommandCallIdentity>, ApiError> {
    begin(&state, ConfigurationCallRequest::Profile(request))
}
#[utoipa::path(post, path = "/api/v1/products/agent-profiles/commands/find", operation_id = "agentProfiles.command.find", request_body = FindCallRequest, responses(StudioApiErrors, (status = 200, body = Option<ConfigurationCommandCallIdentity>)))]
async fn find_profile(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<FindCallRequest>,
) -> Result<Json<Option<ConfigurationCommandCallIdentity>>, ApiError> {
    find(
        &state,
        &request.operation_id,
        ConfigurationCallKind::Profile,
    )
}
#[utoipa::path(post, path = "/api/v1/profile-commands/{call_id}/result", operation_id = "agentProfiles.command.result", params(("call_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = ProfileCommandOutcome)))]
async fn profile_result(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<ProfileCommandOutcome>, ApiError> {
    let owner = state
        .configuration
        .command(&id, ConfigurationCallKind::Profile)?;
    let mut query = owner.result_query()?;
    match query.result().await? {
        ConfigurationCallOutcome::Profile(outcome) => Ok(Json(outcome)),
        _ => Err(wrong_kind().into()),
    }
}
#[utoipa::path(post, path = "/api/v1/profile-commands/{call_id}/request-close", operation_id = "agentProfiles.command.requestClose", params(("call_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 204)))]
async fn profile_request_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<StatusCode, ApiError> {
    state
        .configuration
        .command(&id, ConfigurationCallKind::Profile)?
        .request_close();
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/profile-commands/{call_id}/close", operation_id = "agentProfiles.command.close", params(("call_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn profile_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    close(state, id, ConfigurationCallKind::Profile).await
}
#[utoipa::path(post, path = "/api/v1/profile-commands/{call_id}/retry-close", operation_id = "agentProfiles.command.retryClose", params(("call_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn profile_retry_close(
    state: State<AppState>,
    id: Path<String>,
    body: ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    profile_close(state, id, body).await
}

#[utoipa::path(post, path = "/api/v1/products/configuration/reload/begin", operation_id = "configuration.reload.begin", request_body = ConfigurationReloadRequest, responses(StudioApiErrors, (status = 200, body = ConfigurationCommandCallIdentity)))]
async fn begin_reload(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<ConfigurationReloadRequest>,
) -> Result<Json<ConfigurationCommandCallIdentity>, ApiError> {
    begin(&state, ConfigurationCallRequest::Reload(request))
}
#[utoipa::path(post, path = "/api/v1/products/configuration/reload/find", operation_id = "configuration.reload.find", request_body = FindCallRequest, responses(StudioApiErrors, (status = 200, body = Option<ConfigurationCommandCallIdentity>)))]
async fn find_reload(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<FindCallRequest>,
) -> Result<Json<Option<ConfigurationCommandCallIdentity>>, ApiError> {
    find(&state, &request.operation_id, ConfigurationCallKind::Reload)
}
#[utoipa::path(post, path = "/api/v1/configuration-reloads/{call_id}/result", operation_id = "configuration.reload.result", params(("call_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = ConfigurationReloadOutcome)))]
async fn reload_result(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<ConfigurationReloadOutcome>, ApiError> {
    let owner = state
        .configuration
        .command(&id, ConfigurationCallKind::Reload)?;
    let mut query = owner.result_query()?;
    match query.result().await? {
        ConfigurationCallOutcome::Reload(outcome) => Ok(Json(outcome)),
        _ => Err(wrong_kind().into()),
    }
}
#[utoipa::path(post, path = "/api/v1/configuration-reloads/{call_id}/request-close", operation_id = "configuration.reload.requestClose", params(("call_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 204)))]
async fn reload_request_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<StatusCode, ApiError> {
    state
        .configuration
        .command(&id, ConfigurationCallKind::Reload)?
        .request_close();
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/configuration-reloads/{call_id}/close", operation_id = "configuration.reload.close", params(("call_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn reload_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    close(state, id, ConfigurationCallKind::Reload).await
}
#[utoipa::path(post, path = "/api/v1/configuration-reloads/{call_id}/retry-close", operation_id = "configuration.reload.retryClose", params(("call_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
async fn reload_retry_close(
    state: State<AppState>,
    id: Path<String>,
    body: ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    reload_close(state, id, body).await
}

fn wrong_kind() -> StudioError {
    StudioError::new(
        pl_protocol::studio::StudioErrorCode::Protocol,
        "Original call result has the wrong resource kind",
        false,
    )
}
