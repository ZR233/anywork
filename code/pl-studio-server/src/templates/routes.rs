use std::time::Duration;

use axum::extract::{FromRequestParts, State};
use axum::http::{HeaderValue, request::Parts};
use axum::response::sse::{KeepAlive, Sse};
use axum::response::{IntoResponse, Response};
use pl_protocol::products::feed::account_templates::AccountTemplatesFrame;
use pl_protocol::studio::{StudioError, StudioErrorCode, StudioErrorDetails};
use utoipa_axum::{router::OpenApiRouter, routes};

use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, StudioApiErrors};
use super::{control, read_routes};
use super::types::EmptyRequest;

struct NoReplay;

impl FromRequestParts<AppState> for NoReplay {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, _: &AppState) -> Result<Self, Self::Rejection> {
        if parts.headers.contains_key("last-event-id") {
            return Err(StudioError::new(StudioErrorCode::Conflict,
                "Templates streams do not support replay; create a new POST stream", false)
                .with_details(StudioErrorDetails::Reason { reason: "replayUnsupported".into() }).into());
        }
        Ok(Self)
    }
}

pub(crate) fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(events))
        .routes(routes!(control::ack, control::request_close, control::close, control::retry_close))
        .routes(routes!(control::request_read_close, control::read_close, control::retry_read_close))
        .routes(routes!(read_routes::open, read_routes::header, read_routes::text, read_routes::entries, read_routes::entity))
        .routes(routes!(read_routes::lookup_template, read_routes::templates, read_routes::catalogs, read_routes::models))
        .routes(routes!(read_routes::type_support, read_routes::type_exclusions, read_routes::connection_modes))
        .routes(routes!(read_routes::input_capabilities, read_routes::input_sources, read_routes::modalities))
        .routes(routes!(read_routes::price_tiers, read_routes::strings))
}

#[utoipa::path(post, path = "/api/v1/products/account-templates/events", operation_id = "templates.events", request_body = EmptyRequest,
    responses(StudioApiErrors, (status = 200, description = "Templates typed frames; explicit ACK via the returned x-studio-feed-id. No replay; Last-Event-ID is rejected.",
        headers(("x-studio-feed-id" = String, description = "Original native Templates feed ID")),
        body = AccountTemplatesFrame, content_type = "text/event-stream")))]
async fn events(State(state): State<AppState>, _replay: NoReplay, ApiJson(_): ApiJson<EmptyRequest>) -> Result<Response, ApiError> {
    state.templates.reap();
    let permit = state.streams.clone().try_acquire_owned().map_err(|_| ApiError::overloaded())?;
    let mut opening = state.templates.open(state.runtime.clone(), &state.shutdown, permit)?;
    let identity = opening.ready().await?;
    let feed_id = HeaderValue::from_str(&identity.feed_id).map_err(|_| ApiError(StudioError::new(
        StudioErrorCode::Protocol, "The native Templates feed ID is not a valid HTTP header", false)))?;
    let body = opening.take_body()?;
    let mut response = Sse::new(body).keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("")).into_response();
    response.headers_mut().insert("x-studio-feed-id", feed_id);
    Ok(response)
}
