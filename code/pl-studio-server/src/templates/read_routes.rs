use axum::Json;
use axum::extract::State;
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::model_pages::*;
use pl_protocol::products::read::primitives::TextReadPage;
use pl_protocol::products::read::templates::AccountTemplatesReadHeader;
use pl_protocol::studio::TextChunk;

use super::types::*;
use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, ApiPath as Path, StudioApiErrors};

#[utoipa::path(post, path = "/api/v1/reads/account-templates/open", operation_id = "templates.read.open", request_body = OpenReadRequest, responses(StudioApiErrors, (status = 200, body = OpenReadReply)))]
pub(super) async fn open(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<OpenReadRequest>,
) -> Result<Json<OpenReadReply>, ApiError> {
    let parent = state.templates.feed(&body.feed_id)?;
    let mut opening = parent.open_read(state.runtime.clone(), body.reference)?;
    let identity = opening.ready().await?;
    opening.adopt()?;
    Ok(Json(OpenReadReply {
        scope_id: identity.scope_id.clone(),
        identity,
    }))
}

#[utoipa::path(get, path = "/api/v1/reads/account-templates/{scope_id}/header", operation_id = "templates.read.header", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = AccountTemplatesReadHeader)))]
pub(super) async fn header(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<AccountTemplatesReadHeader>, ApiError> {
    let query = state.templates.read(&id)?.query(|source| source.header())?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/text", operation_id = "templates.read.text", params(("scope_id" = String, Path)), request_body = TextRequest, responses(StudioApiErrors, (status = 200, body = TextChunk)))]
pub(super) async fn text(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<TextRequest>,
) -> Result<Json<TextChunk>, ApiError> {
    let query = state.templates.read(&id)?.query(move |source| {
        source.text(body.field_id, body.offset, body.max_bytes.unwrap_or(65536))
    })?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/entries", operation_id = "templates.read.entries", params(("scope_id" = String, Path)), request_body = EntriesRequest, responses(StudioApiErrors, (status = 200, body = AccountTemplatesEntryPage)))]
pub(super) async fn entries(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<EntriesRequest>,
) -> Result<Json<AccountTemplatesEntryPage>, ApiError> {
    let query = state
        .templates
        .read(&id)?
        .query(move |source| source.entries(body.offset, body.limit.unwrap_or(32)))?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/entity", operation_id = "templates.read.entity", params(("scope_id" = String, Path)), request_body = EntityRequest, responses(StudioApiErrors, (status = 200, body = AccountTemplatesEntityRead)))]
pub(super) async fn entity(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<EntityRequest>,
) -> Result<Json<AccountTemplatesEntityRead>, ApiError> {
    let query = state
        .templates
        .read(&id)?
        .query(move |source| source.entity(body.reference))?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/lookup-template", operation_id = "templates.read.lookupTemplate", params(("scope_id" = String, Path)), request_body = LookupRequest, responses(StudioApiErrors, (status = 200, body = Option<ProductEntityRef>)))]
pub(super) async fn lookup_template(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<LookupRequest>,
) -> Result<Json<Option<ProductEntityRef>>, ApiError> {
    let query = state
        .templates
        .read(&id)?
        .query(move |source| source.lookup_template(body.template_id))?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/templates", operation_id = "templates.read.templates", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = AccountTemplateReadPage)))]
pub(super) async fn templates(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<AccountTemplateReadPage>, ApiError> {
    let query = state.templates.read(&id)?.query(move |source| {
        source.templates(body.list_id, body.offset, body.limit.unwrap_or(32))
    })?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/catalogs", operation_id = "templates.read.catalogs", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = NamedModelCatalogReadPage)))]
pub(super) async fn catalogs(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<NamedModelCatalogReadPage>, ApiError> {
    let query = state.templates.read(&id)?.query(move |source| {
        source.catalogs(body.list_id, body.offset, body.limit.unwrap_or(32))
    })?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/models", operation_id = "templates.read.models", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelDescriptorReadPage)))]
pub(super) async fn models(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelDescriptorReadPage>, ApiError> {
    let query = state
        .templates
        .read(&id)?
        .query(move |source| source.models(body.list_id, body.offset, body.limit.unwrap_or(32)))?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/type-support", operation_id = "templates.read.typeSupport", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelTypeSupportReadPage)))]
pub(super) async fn type_support(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelTypeSupportReadPage>, ApiError> {
    let query = state.templates.read(&id)?.query(move |source| {
        source.type_support(body.list_id, body.offset, body.limit.unwrap_or(32))
    })?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/type-exclusions", operation_id = "templates.read.typeExclusions", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelTypeExclusionReadPage)))]
pub(super) async fn type_exclusions(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelTypeExclusionReadPage>, ApiError> {
    let query = state.templates.read(&id)?.query(move |source| {
        source.type_exclusions(body.list_id, body.offset, body.limit.unwrap_or(32))
    })?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/connection-modes", operation_id = "templates.read.connectionModes", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ConnectionModeReadPage)))]
pub(super) async fn connection_modes(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ConnectionModeReadPage>, ApiError> {
    let query = state.templates.read(&id)?.query(move |source| {
        source.connection_modes(body.list_id, body.offset, body.limit.unwrap_or(32))
    })?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/input-capabilities", operation_id = "templates.read.inputCapabilities", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelInputCapabilityReadPage)))]
pub(super) async fn input_capabilities(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelInputCapabilityReadPage>, ApiError> {
    let query = state.templates.read(&id)?.query(move |source| {
        source.input_capabilities(body.list_id, body.offset, body.limit.unwrap_or(32))
    })?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/input-sources", operation_id = "templates.read.inputSources", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelInputSourceReadPage)))]
pub(super) async fn input_sources(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelInputSourceReadPage>, ApiError> {
    let query = state.templates.read(&id)?.query(move |source| {
        source.input_sources(body.list_id, body.offset, body.limit.unwrap_or(32))
    })?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/modalities", operation_id = "templates.read.modalities", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelModalityReadPage)))]
pub(super) async fn modalities(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelModalityReadPage>, ApiError> {
    let query = state.templates.read(&id)?.query(move |source| {
        source.modalities(body.list_id, body.offset, body.limit.unwrap_or(32))
    })?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/price-tiers", operation_id = "templates.read.priceTiers", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelPriceTierReadPage)))]
pub(super) async fn price_tiers(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelPriceTierReadPage>, ApiError> {
    let query = state.templates.read(&id)?.query(move |source| {
        source.price_tiers(body.list_id, body.offset, body.limit.unwrap_or(32))
    })?;
    Ok(Json(query.await?))
}

#[utoipa::path(post, path = "/api/v1/reads/account-templates/{scope_id}/strings", operation_id = "templates.read.strings", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = TextReadPage)))]
pub(super) async fn strings(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<TextReadPage>, ApiError> {
    let query = state
        .templates
        .read(&id)?
        .query(move |source| source.strings(body.list_id, body.offset, body.limit.unwrap_or(32)))?;
    Ok(Json(query.await?))
}
