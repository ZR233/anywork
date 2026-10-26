use super::{read::OpenReadKind, types::*};
use crate::{
    AppState,
    error::ApiError,
    routes::{ApiJson, ApiPath as Path, StudioApiErrors},
};
use axum::{Json, extract::State};
use pl_protocol::products::configuration::{
    ConfigurationRoleReadTarget, RoleRouteRead, StartRouteQuery, StartRouteRead,
};
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::configuration::*;
use pl_protocol::products::read::configuration_pages::*;
use pl_protocol::products::read::model_pages::{
    ModelInputCapabilityReadPage, ModelInputSourceReadPage,
};
use pl_protocol::products::read::primitives::TextReadPage;
use pl_protocol::products::source::ProductSourceStatusReadHeader;
use pl_protocol::studio::TextChunk;

pub(super) async fn opened(
    state: &AppState,
    feed_id: &str,
    kind: OpenReadKind,
) -> Result<Json<OpenReadReply>, ApiError> {
    let mut opening = state
        .configuration
        .feed(feed_id)?
        .open_read(state.runtime.clone(), kind)?;
    let identity = opening.ready().await?;
    opening.adopt()?;
    Ok(Json(OpenReadReply {
        scope_id: identity.scope_id.clone(),
        identity,
    }))
}
#[utoipa::path(post, path = "/api/v1/reads/configuration", operation_id = "configuration.read.open", request_body = OpenReadRequest, responses(StudioApiErrors, (status = 200, body = OpenReadReply)))]
pub(super) async fn open(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<OpenReadRequest>,
) -> Result<Json<OpenReadReply>, ApiError> {
    opened(&state, &body.feed_id, OpenReadKind::Value(body.reference)).await
}
#[utoipa::path(post, path = "/api/v1/reads/configuration-role", operation_id = "configuration.role.open", request_body = OpenPairRequest, responses(StudioApiErrors, (status = 200, body = OpenReadReply)))]
pub(super) async fn open_role(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<OpenPairRequest>,
) -> Result<Json<OpenReadReply>, ApiError> {
    opened(&state, &body.feed_id, OpenReadKind::Role(body.sources)).await
}
#[utoipa::path(post, path = "/api/v1/reads/configuration-start", operation_id = "configuration.start.open", request_body = OpenPairRequest, responses(StudioApiErrors, (status = 200, body = OpenReadReply)))]
pub(super) async fn open_start(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<OpenPairRequest>,
) -> Result<Json<OpenReadReply>, ApiError> {
    opened(&state, &body.feed_id, OpenReadKind::Start(body.sources)).await
}
#[utoipa::path(post, path = "/api/v1/reads/configuration-source-status", operation_id = "configuration.sourceStatus.open", request_body = OpenStatusRequest, responses(StudioApiErrors, (status = 200, body = OpenReadReply)))]
pub(super) async fn open_source(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<OpenStatusRequest>,
) -> Result<Json<OpenReadReply>, ApiError> {
    opened(&state, &body.feed_id, OpenReadKind::Source(body.reference)).await
}

#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/header", operation_id = "configuration.read.header", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = ConfigurationReadHeader)))]
pub(super) async fn header(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<ConfigurationReadHeader>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| Ok(source.value()?.header()))?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/text", operation_id = "configuration.read.text", params(("scope_id" = String, Path)), request_body = TextRequest, responses(StudioApiErrors, (status = 200, body = TextChunk)))]
pub(super) async fn text(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<TextRequest>,
) -> Result<Json<TextChunk>, ApiError> {
    Ok(Json(
        state
            .configuration
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
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/entries", operation_id = "configuration.read.entries", params(("scope_id" = String, Path)), request_body = EntriesRequest, responses(StudioApiErrors, (status = 200, body = ConfigurationEntryPage)))]
pub(super) async fn entries(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<EntriesRequest>,
) -> Result<Json<ConfigurationEntryPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source
                    .value()?
                    .entries(body.offset, body.limit.unwrap_or(32)))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/entity", operation_id = "configuration.read.entity", params(("scope_id" = String, Path)), request_body = EntityRequest, responses(StudioApiErrors, (status = 200, body = ConfigurationEntityRead)))]
pub(super) async fn entity(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<EntityRequest>,
) -> Result<Json<ConfigurationEntityRead>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| Ok(source.value()?.entity(body.reference)))?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/lookup-account", operation_id = "configuration.read.lookupAccount", params(("scope_id" = String, Path)), request_body = LookupRequest, responses(StudioApiErrors, (status = 200, body = Option<ProductEntityRef>)))]
pub(super) async fn lookup_account(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<LookupRequest>,
) -> Result<Json<Option<ProductEntityRef>>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| Ok(source.value()?.lookup_account(body.account_id)))?
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/accounts", operation_id = "configuration.read.accounts", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = AccountConfigurationReadPage)))]
pub(super) async fn accounts(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<AccountConfigurationReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source
                    .value()?
                    .accounts(body.list_id, body.offset, body.limit.unwrap_or(32)))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/acp-accounts", operation_id = "configuration.read.acpAccounts", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = AcpAccountConfigurationReadPage)))]
pub(super) async fn acp_accounts(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<AcpAccountConfigurationReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source.value()?.acp_accounts(
                    body.list_id,
                    body.offset,
                    body.limit.unwrap_or(32),
                ))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/custom-models", operation_id = "configuration.read.customModels", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = CustomModelConfigurationReadPage)))]
pub(super) async fn custom_models(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<CustomModelConfigurationReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source.value()?.custom_models(
                    body.list_id,
                    body.offset,
                    body.limit.unwrap_or(32),
                ))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/model-connections", operation_id = "configuration.read.modelConnections", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelConnectionReadPage)))]
pub(super) async fn model_connections(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelConnectionReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source.value()?.model_connections(
                    body.list_id,
                    body.offset,
                    body.limit.unwrap_or(32),
                ))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/auto-compact-overrides", operation_id = "configuration.read.autoCompactOverrides", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelAutoCompactReadPage)))]
pub(super) async fn auto_compact_overrides(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelAutoCompactReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source.value()?.auto_compact_overrides(
                    body.list_id,
                    body.offset,
                    body.limit.unwrap_or(32),
                ))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/mode-routes", operation_id = "configuration.read.modeRoutes", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModeModelRouteReadPage)))]
pub(super) async fn mode_routes(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModeModelRouteReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source
                    .value()?
                    .mode_routes(body.list_id, body.offset, body.limit.unwrap_or(32)))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/role-routes", operation_id = "configuration.read.roleRoutes", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = RoleModelRouteReadPage)))]
pub(super) async fn role_routes(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<RoleModelRouteReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source
                    .value()?
                    .role_routes(body.list_id, body.offset, body.limit.unwrap_or(32)))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/mcp-configs", operation_id = "configuration.read.mcpConfigs", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = McpConfigurationReadPage)))]
pub(super) async fn mcp_configs(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<McpConfigurationReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source
                    .value()?
                    .mcp_configs(body.list_id, body.offset, body.limit.unwrap_or(32)))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/strings", operation_id = "configuration.read.strings", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = TextReadPage)))]
pub(super) async fn strings(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<TextReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source
                    .value()?
                    .strings(body.list_id, body.offset, body.limit.unwrap_or(32)))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/input-capabilities", operation_id = "configuration.read.inputCapabilities", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelInputCapabilityReadPage)))]
pub(super) async fn input_capabilities(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelInputCapabilityReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source.value()?.input_capabilities(
                    body.list_id,
                    body.offset,
                    body.limit.unwrap_or(32),
                ))
            })?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/input-sources", operation_id = "configuration.read.inputSources", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelInputSourceReadPage)))]
pub(super) async fn input_sources(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelInputSourceReadPage>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source.value()?.input_sources(
                    body.list_id,
                    body.offset,
                    body.limit.unwrap_or(32),
                ))
            })?
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/role-header", operation_id = "configuration.role.header", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = ConfigurationRoleReadTarget)))]
pub(super) async fn role_header(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<ConfigurationRoleReadTarget>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| Ok(source.role()?.header()))?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/role-route", operation_id = "configuration.role.route", params(("scope_id" = String, Path)), request_body = RoleRequest, responses(StudioApiErrors, (status = 200, body = RoleRouteRead)))]
pub(super) async fn role_route(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<RoleRequest>,
) -> Result<Json<RoleRouteRead>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| Ok(source.role()?.role_route(body.role_id)))?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/start-header", operation_id = "configuration.start.header", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = ConfigurationRoleReadTarget)))]
pub(super) async fn start_header(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<ConfigurationRoleReadTarget>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| Ok(source.start()?.header()))?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/start-route", operation_id = "configuration.start.resolve", params(("scope_id" = String, Path)), request_body = StartRouteQuery, responses(StudioApiErrors, (status = 200, body = StartRouteRead)))]
pub(super) async fn start_route(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<StartRouteQuery>,
) -> Result<Json<StartRouteRead>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| Ok(source.start()?.resolve(body)))?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/source-header", operation_id = "configuration.sourceStatus.header", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = ProductSourceStatusReadHeader)))]
pub(super) async fn source_header(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<ProductSourceStatusReadHeader>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| Ok(source.source()?.header()))?
            .await?,
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-reads/{scope_id}/source-text", operation_id = "configuration.sourceStatus.text", params(("scope_id" = String, Path)), request_body = TextRequest, responses(StudioApiErrors, (status = 200, body = TextChunk)))]
pub(super) async fn source_text(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<TextRequest>,
) -> Result<Json<TextChunk>, ApiError> {
    Ok(Json(
        state
            .configuration
            .read(&id)?
            .query(|source| {
                Ok(source.source()?.text(
                    body.field_id,
                    body.offset,
                    body.max_bytes.unwrap_or(65536),
                ))
            })?
            .await?,
    ))
}
