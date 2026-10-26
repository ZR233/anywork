use super::{
    native::{Capability, OpenRead, ReadKind},
    types::*,
};
use crate::{
    AppState,
    error::ApiError,
    routes::{ApiJson, ApiPath, StudioApiErrors},
};
use axum::{Json, extract::State};
use pl_protocol::{
    products::{
        identity::ProductEntityRef,
        models::ModelSelection,
        read::{
            delegation_models::*, model_pages::*, models::ModelCatalogReadHeader,
            primitives::TextReadPage,
        },
        source::ProductSourceStatusReadHeader,
    },
    studio::TextChunk,
};

async fn opened(state: AppState, request: OpenRead) -> Result<Json<OpenReadReply>, ApiError> {
    let mut opening = state
        .models
        .open_read(&state.runtime, &state.shutdown, request)?;
    let reply = opening.ready().await?;
    reply.ensure_budget()?;
    opening.adopt()?;
    Ok(Json(reply))
}
#[utoipa::path(post, path = "/api/v1/reads/model-catalog/open", operation_id = "modelCatalog.read.open", request_body = OpenCatalogRequest, responses(StudioApiErrors, (status = 200, body = OpenReadReply)))]
pub(super) async fn open_catalog(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<OpenCatalogRequest>,
) -> Result<Json<OpenReadReply>, ApiError> {
    opened(
        state,
        OpenRead::Catalog {
            reference: body.reference,
            origin: body.origin,
        },
    )
    .await
}
#[utoipa::path(post, path = "/api/v1/reads/model-catalog-source-status/open", operation_id = "modelCatalog.sourceStatus.open", request_body = OpenStatusRequest, responses(StudioApiErrors, (status = 200, body = OpenReadReply)))]
pub(super) async fn open_status(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<OpenStatusRequest>,
) -> Result<Json<OpenReadReply>, ApiError> {
    opened(
        state,
        OpenRead::SourceStatus {
            reference: body.reference,
            origin: body.origin,
        },
    )
    .await
}
#[utoipa::path(post, path = "/api/v1/reads/delegation-model/open", operation_id = "delegationModel.read.open", request_body = DelegationModelReadTarget, responses(StudioApiErrors, (status = 200, body = OpenReadReply)))]
pub(super) async fn open_delegation(
    State(state): State<AppState>,
    ApiJson(target): ApiJson<DelegationModelReadTarget>,
) -> Result<Json<OpenReadReply>, ApiError> {
    opened(state, OpenRead::Delegation(target)).await
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/catalog-header", operation_id = "modelCatalog.read.header", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = ModelCatalogReadHeader)))]
pub(super) async fn catalog_header(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<ModelCatalogReadHeader>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Kind(ReadKind::Catalog)))?
        .query(|v| Ok(v.catalog()?.header()))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/entries", operation_id = "modelCatalog.read.entries", params(("scope_id" = String, Path)), request_body = EntriesRequest, responses(StudioApiErrors, (status = 200, body = ModelCatalogEntryPage)))]
pub(super) async fn entries(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<EntriesRequest>,
) -> Result<Json<ModelCatalogEntryPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Kind(ReadKind::Catalog)))?
        .query(|v| Ok(v.catalog()?.entries(body.offset, body.limit.unwrap_or(32))))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/entity", operation_id = "modelCatalog.read.entity", params(("scope_id" = String, Path)), request_body = EntityRequest, responses(StudioApiErrors, (status = 200, body = ModelCatalogEntityRead)))]
pub(super) async fn entity(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<EntityRequest>,
) -> Result<Json<ModelCatalogEntityRead>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Kind(ReadKind::Catalog)))?
        .query(|v| Ok(v.catalog()?.entity(body.reference)))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/lookup-account", operation_id = "modelCatalog.read.lookupAccount", params(("scope_id" = String, Path)), request_body = LookupRequest, responses(StudioApiErrors, (status = 200, body = Option<ProductEntityRef>)))]
pub(super) async fn lookup_account(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<LookupRequest>,
) -> Result<Json<Option<ProductEntityRef>>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Kind(ReadKind::Catalog)))?
        .query(|v| Ok(v.catalog()?.lookup_account(body.account_id)))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/accounts", operation_id = "modelCatalog.read.accounts", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = AccountCatalogEntryReadPage)))]
pub(super) async fn accounts(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<AccountCatalogEntryReadPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Kind(ReadKind::Catalog)))?
        .query(|v| {
            Ok(v.catalog()?
                .accounts(body.list_id, body.offset, body.limit.unwrap_or(32)))
        })?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/models", operation_id = "modelCatalog.read.models", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelDescriptorReadPage)))]
pub(super) async fn models(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelDescriptorReadPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Kind(ReadKind::Catalog)))?
        .query(|v| {
            Ok(v.catalog()?
                .models(body.list_id, body.offset, body.limit.unwrap_or(32)))
        })?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/effort-after-model-selection", operation_id = "modelCatalog.read.effortAfterModelSelection", params(("scope_id" = String, Path)), request_body = EffortRequest, responses(StudioApiErrors, (status = 200, body = Option<String>)))]
pub(super) async fn effort_after_model_selection(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<EffortRequest>,
) -> Result<Json<Option<String>>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Kind(ReadKind::Catalog)))?
        .query(|v| {
            Ok(v.catalog()?.effort_after_model_selection(
                body.account_id,
                body.model_id,
                body.candidate,
            ))
        })?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/first-text-model", operation_id = "modelCatalog.read.firstTextModel", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = Option<ModelSelection>)))]
pub(super) async fn first_text_model(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<Option<ModelSelection>>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Kind(ReadKind::Catalog)))?
        .query(|v| Ok(v.catalog()?.first_text_model()))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/text", operation_id = "models.read.text", params(("scope_id" = String, Path)), request_body = TextRequest, responses(StudioApiErrors, (status = 200, body = TextChunk)))]
pub(super) async fn text(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<TextRequest>,
) -> Result<Json<TextChunk>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Text))?
        .query(|v| Ok(v.text(body.field_id, body.offset, body.max_bytes.unwrap_or(65536))))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/strings", operation_id = "models.read.strings", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = TextReadPage)))]
pub(super) async fn strings(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<TextReadPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Fields))?
        .query(|v| v.strings(body.list_id, body.offset, body.limit.unwrap_or(32)))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/type-support", operation_id = "models.read.typeSupport", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelTypeSupportReadPage)))]
pub(super) async fn type_support(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelTypeSupportReadPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Fields))?
        .query(|v| v.type_support(body.list_id, body.offset, body.limit.unwrap_or(32)))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/type-exclusions", operation_id = "models.read.typeExclusions", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelTypeExclusionReadPage)))]
pub(super) async fn type_exclusions(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelTypeExclusionReadPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Fields))?
        .query(|v| v.type_exclusions(body.list_id, body.offset, body.limit.unwrap_or(32)))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/connection-modes", operation_id = "models.read.connectionModes", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ConnectionModeReadPage)))]
pub(super) async fn connection_modes(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ConnectionModeReadPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Fields))?
        .query(|v| v.connection_modes(body.list_id, body.offset, body.limit.unwrap_or(32)))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/input-capabilities", operation_id = "models.read.inputCapabilities", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelInputCapabilityReadPage)))]
pub(super) async fn input_capabilities(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelInputCapabilityReadPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Fields))?
        .query(|v| v.input_capabilities(body.list_id, body.offset, body.limit.unwrap_or(32)))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/input-sources", operation_id = "models.read.inputSources", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelInputSourceReadPage)))]
pub(super) async fn input_sources(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelInputSourceReadPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Fields))?
        .query(|v| v.input_sources(body.list_id, body.offset, body.limit.unwrap_or(32)))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/modalities", operation_id = "models.read.modalities", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelModalityReadPage)))]
pub(super) async fn modalities(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelModalityReadPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Fields))?
        .query(|v| v.modalities(body.list_id, body.offset, body.limit.unwrap_or(32)))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/price-tiers", operation_id = "models.read.priceTiers", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelPriceTierReadPage)))]
pub(super) async fn price_tiers(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelPriceTierReadPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Fields))?
        .query(|v| v.price_tiers(body.list_id, body.offset, body.limit.unwrap_or(32)))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/source-header", operation_id = "modelCatalog.sourceStatus.header", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = ProductSourceStatusReadHeader)))]
pub(super) async fn source_header(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<ProductSourceStatusReadHeader>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Kind(ReadKind::SourceStatus)))?
        .query(|v| Ok(v.status()?.header()))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/delegation-header", operation_id = "delegationModel.read.header", params(("scope_id" = String, Path)), request_body = EmptyRequest, responses(StudioApiErrors, (status = 200, body = DelegationModelReadHeader)))]
pub(super) async fn delegation_header(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<DelegationModelReadHeader>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Kind(ReadKind::Delegation)))?
        .query(|v| Ok(v.delegation()?.header()))?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/selection-sources", operation_id = "delegationModel.read.selectionSources", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = ModelSelectionSourceReadPage)))]
pub(super) async fn selection_sources(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<ModelSelectionSourceReadPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Kind(ReadKind::Delegation)))?
        .query(|v| {
            Ok(v.delegation()?.selection_sources(
                body.list_id,
                body.offset,
                body.limit.unwrap_or(32),
            ))
        })?;
    Ok(Json(query.await?))
}
#[utoipa::path(post, path = "/api/v1/models-reads/{scope_id}/evaluations", operation_id = "delegationModel.read.evaluations", params(("scope_id" = String, Path)), request_body = ListRequest, responses(StudioApiErrors, (status = 200, body = AgentEvaluationReadPage)))]
pub(super) async fn evaluations(
    State(state): State<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiJson(body): ApiJson<ListRequest>,
) -> Result<Json<AgentEvaluationReadPage>, ApiError> {
    let query = state
        .models
        .read(&id, Some(Capability::Kind(ReadKind::Delegation)))?
        .query(|v| {
            Ok(v.delegation()?
                .evaluations(body.list_id, body.offset, body.limit.unwrap_or(32)))
        })?;
    Ok(Json(query.await?))
}
