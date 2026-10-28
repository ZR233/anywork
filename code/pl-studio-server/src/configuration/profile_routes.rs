//! Concrete HTTP Profiles reads. All tickets belong to the original domain Transport.
use super::{profile_control, read::OpenReadKind, read_routes::opened, types::*};
use crate::{
    AppState,
    error::ApiError,
    routes::{ApiJson, ApiPath as Path, NoReplay, StudioApiErrors},
};
use axum::{
    Json,
    extract::State,
    http::HeaderValue,
    response::{
        IntoResponse, Response,
        sse::{KeepAlive, Sse},
    },
};
use pl_protocol::products::feed::agent_profiles::AgentProfilesFrame;
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::agent_profiles::*;
use pl_protocol::products::references::AgentProfilesReadRef;
use pl_protocol::products::source::ProductSourceStatusReadHeader;
use pl_protocol::studio::{StudioError, StudioErrorCode, TextChunk};
use serde::Deserialize;
use std::time::Duration;
use utoipa::ToSchema;
use utoipa_axum::{router::OpenApiRouter, routes};

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct OpenProfilesRequest {
    pub feed_id: String,
    pub reference: AgentProfilesReadRef,
}
#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct LookupProfileRequest {
    pub profile_id: String,
}

pub(super) fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        // 每个 handler 各自声明自己的 path/method：`routes!` 只产生一个 MethodRouter，
        // 多个同 method 的 handler 放进同一次调用会在装配期重复登记 POST。
        .routes(routes!(events))
        .routes(routes!(open))
        .routes(routes!(open_source))
        .routes(routes!(header))
        .routes(routes!(text))
        .routes(routes!(entries))
        .routes(routes!(entity))
        .routes(routes!(lookup_profile))
        .routes(routes!(profiles))
        .routes(routes!(diagnostics))
        .routes(routes!(source_header))
        .routes(routes!(source_text))
        .routes(routes!(profile_control::ack))
        .routes(routes!(profile_control::request_close))
        .routes(routes!(profile_control::close))
        .routes(routes!(profile_control::retry_close))
        .routes(routes!(profile_control::request_read_close))
        .routes(routes!(profile_control::read_close))
        .routes(routes!(profile_control::retry_read_close))
}
#[utoipa::path(post, path = "/api/v1/products/agent-profiles/events", operation_id = "agentProfiles.events", request_body = EmptyRequest,
    responses(StudioApiErrors, (status = 200, description = "Original Profiles stream, no replay; baseline occupies ordinary ACK credit.",
        headers(("x-studio-feed-id" = String, description = "Native Profiles feed ID")), body = AgentProfilesFrame, content_type = "text/event-stream")))]
async fn events(
    State(state): State<AppState>,
    _replay: NoReplay,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Response, ApiError> {
    state.configuration.reap();
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let mut opening =
        state
            .configuration
            .open_profiles(state.runtime.clone(), &state.shutdown, permit)?;
    let identity = opening.ready().await?;
    let feed_id = HeaderValue::from_str(&identity.feed_id).map_err(|_| {
        ApiError(StudioError::new(
            StudioErrorCode::Protocol,
            "Profiles feed ID is not a valid HTTP header",
            false,
        ))
    })?;
    let body = opening.take_body()?;
    let mut response = Sse::new(body)
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text(""))
        .into_response();
    response.headers_mut().insert("x-studio-feed-id", feed_id);
    Ok(response)
}
#[utoipa::path(post, path = "/api/v1/reads/agent-profiles", operation_id = "agentProfiles.read.open", request_body = OpenProfilesRequest, responses(StudioApiErrors, (status = 200, body = OpenReadReply)))]
async fn open(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<OpenProfilesRequest>,
) -> Result<Json<OpenReadReply>, ApiError> {
    opened(
        &state,
        &body.feed_id,
        OpenReadKind::Profiles(body.reference),
    )
    .await
}
#[utoipa::path(post, path = "/api/v1/reads/agent-profiles-source-status", operation_id = "agentProfiles.sourceStatus.open", request_body = OpenStatusRequest, responses(StudioApiErrors, (status = 200, body = OpenReadReply)))]
async fn open_source(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<OpenStatusRequest>,
) -> Result<Json<OpenReadReply>, ApiError> {
    opened(&state, &body.feed_id, OpenReadKind::Source(body.reference)).await
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-reads/{scope_id}/header", operation_id = "agentProfiles.read.header", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = AgentProfilesReadHeader)))]
async fn header(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<AgentProfilesReadHeader>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| Ok(source.profiles()?.header()))?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-reads/{scope_id}/text", operation_id = "agentProfiles.read.text", params(("scope_id" = String, Path)), request_body = TextRequest, responses(StudioApiErrors, (status = 200, body = TextChunk)))]
async fn text(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<TextRequest>,
) -> Result<Json<TextChunk>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source.profiles()?.text(
                    body.field_id,
                    body.offset,
                    body.max_bytes.unwrap_or(65536),
                ))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-reads/{scope_id}/entries", operation_id = "agentProfiles.read.entries", params(("scope_id" = String, Path)), request_body = EntriesRequest, responses(StudioApiErrors, (status = 200, body = AgentProfilesEntryPage)))]
async fn entries(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<EntriesRequest>,
) -> Result<Json<AgentProfilesEntryPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source
                    .profiles()?
                    .entries(body.offset, body.limit.unwrap_or(32)))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-reads/{scope_id}/entity", operation_id = "agentProfiles.read.entity", params(("scope_id" = String, Path)), request_body = EntityRequest, responses(StudioApiErrors, (status = 200, body = AgentProfilesEntityRead)))]
async fn entity(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<EntityRequest>,
) -> Result<Json<AgentProfilesEntityRead>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| Ok(source.profiles()?.entity(body.reference)))?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-reads/{scope_id}/lookup-profile", operation_id = "agentProfiles.read.lookupProfile", params(("scope_id" = String, Path)), request_body = LookupProfileRequest, responses(StudioApiErrors, (status = 200, body = Option<ProductEntityRef>)))]
async fn lookup_profile(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<LookupProfileRequest>,
) -> Result<Json<Option<ProductEntityRef>>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| Ok(source.profiles()?.lookup_profile(body.profile_id)))?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-reads/{scope_id}/profiles", operation_id = "agentProfiles.read.profiles", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = AgentProfileReadPage)))]
async fn profiles(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<AgentProfileReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source
                    .profiles()?
                    .profiles(body.list_id, body.offset, body.limit.unwrap_or(32)))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-reads/{scope_id}/diagnostics", operation_id = "agentProfiles.read.diagnostics", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ProfileDiagnosticReadPage)))]
async fn diagnostics(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ProfileDiagnosticReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source.profiles()?.diagnostics(
                    body.list_id,
                    body.offset,
                    body.limit.unwrap_or(32),
                ))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-reads/{scope_id}/source-header", operation_id = "agentProfiles.sourceStatus.header", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = ProductSourceStatusReadHeader)))]
async fn source_header(
    State(state): State<AppState>,
    Path(id): Path<String>,
    body: ApiJson<EmptyRequest>,
) -> Result<Json<ProductSourceStatusReadHeader>, ApiError> {
    super::read_routes::source_header(State(state), Path(id), body).await
}
#[utoipa::path(post, path = "/api/v1/agent-profiles-reads/{scope_id}/source-text", operation_id = "agentProfiles.sourceStatus.text", params(("scope_id" = String, Path)), request_body = TextRequest, responses(StudioApiErrors, (status = 200, body = TextChunk)))]
async fn source_text(
    State(state): State<AppState>,
    Path(id): Path<String>,
    body: ApiJson<TextRequest>,
) -> Result<Json<TextChunk>, ApiError> {
    super::read_routes::source_text(State(state), Path(id), body).await
}
