use super::{control, read_routes as read, types::EmptyRequest};
use crate::{
    AppState,
    error::ApiError,
    routes::{ApiJson, StudioApiErrors},
};
use axum::{
    extract::{FromRequestParts, State},
    http::{HeaderValue, request::Parts},
    response::{IntoResponse, Response, Sse, sse::KeepAlive},
};
use pl_protocol::{
    products::feed::model_catalog::ModelCatalogFrame,
    studio::{StudioError, StudioErrorCode, StudioErrorDetails},
};
use utoipa_axum::{router::OpenApiRouter, routes};

pub(crate) fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(events))
        // 每个 handler 各自声明自己的 path/method：`routes!` 只产生一个 MethodRouter，
        // 多个同 method 的 handler 放进同一次调用会在装配期重复登记 POST。
        .routes(routes!(control::ack))
        .routes(routes!(control::request_close))
        .routes(routes!(control::close))
        .routes(routes!(control::retry_close))
        .routes(routes!(control::request_read_close))
        .routes(routes!(control::read_close))
        .routes(routes!(control::retry_read_close))
        .routes(routes!(read::open_catalog))
        .routes(routes!(read::open_status))
        .routes(routes!(read::open_delegation))
        .routes(routes!(read::catalog_header))
        .routes(routes!(read::entries))
        .routes(routes!(read::entity))
        .routes(routes!(read::lookup_account))
        .routes(routes!(read::accounts))
        .routes(routes!(read::models))
        .routes(routes!(read::effort_after_model_selection))
        .routes(routes!(read::first_text_model))
        .routes(routes!(read::text))
        .routes(routes!(read::strings))
        .routes(routes!(read::type_support))
        .routes(routes!(read::type_exclusions))
        .routes(routes!(read::connection_modes))
        .routes(routes!(read::input_capabilities))
        .routes(routes!(read::input_sources))
        .routes(routes!(read::modalities))
        .routes(routes!(read::price_tiers))
        .routes(routes!(read::source_header))
        .routes(routes!(read::delegation_header))
        .routes(routes!(read::selection_sources))
        .routes(routes!(read::evaluations))
}
struct NoReplay;
impl FromRequestParts<AppState> for NoReplay {
    type Rejection = ApiError;
    async fn from_request_parts(parts: &mut Parts, _: &AppState) -> Result<Self, Self::Rejection> {
        if parts.headers.contains_key("last-event-id") {
            return Err(StudioError::new(
                StudioErrorCode::Conflict,
                "Catalog streams do not support replay; open a new POST stream",
                false,
            )
            .with_details(StudioErrorDetails::Reason {
                reason: "replayUnsupported".into(),
            })
            .into());
        }
        Ok(Self)
    }
}
#[utoipa::path(post, path = "/api/v1/products/model-catalog/events", operation_id = "modelCatalog.events", request_body = EmptyRequest,
    responses(StudioApiErrors, (status = 200, body = ModelCatalogFrame, content_type = "text/event-stream", headers(("x-studio-feed-id" = String, description = "Original native Catalog feed ID; no replay")))))]
async fn events(
    State(state): State<AppState>,
    _: NoReplay,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Response, ApiError> {
    state.models.reap();
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let mut opening = state
        .models
        .open_feed(&state.runtime, &state.shutdown, permit)?;
    let identity = opening.ready().await?;
    let id =
        HeaderValue::from_str(&identity.feed_id).map_err(|_| ApiError(StudioError::internal()))?;
    let body = opening.body()?;
    let mut response = Sse::new(body)
        .keep_alive(KeepAlive::default())
        .into_response();
    response.headers_mut().insert("x-studio-feed-id", id);
    Ok(response)
}
