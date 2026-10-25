use super::{command, control, read_routes, types::EmptyRequest};
use crate::{
    AppState,
    error::ApiError,
    routes::{ApiJson, StudioApiErrors},
};
use axum::{
    extract::{FromRequestParts, State},
    http::{HeaderValue, request::Parts},
    response::{
        IntoResponse, Response,
        sse::{KeepAlive, Sse},
    },
};
use pl_protocol::products::feed::configuration::ConfigurationFrame;
use pl_protocol::studio::{StudioError, StudioErrorCode, StudioErrorDetails};
use std::time::Duration;
use utoipa_axum::{router::OpenApiRouter, routes};

pub(super) struct NoReplay;
impl FromRequestParts<AppState> for NoReplay {
    type Rejection = ApiError;
    async fn from_request_parts(parts: &mut Parts, _: &AppState) -> Result<Self, Self::Rejection> {
        if parts.headers.contains_key("last-event-id") {
            return Err(StudioError::new(
                StudioErrorCode::Conflict,
                "Product streams do not support replay; create a new POST stream",
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
pub(crate) fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(events))
        .routes(routes!(
            control::ack,
            control::request_close,
            control::close,
            control::retry_close
        ))
        .routes(routes!(
            control::request_read_close,
            control::read_close,
            control::retry_read_close
        ))
        .routes(routes!(
            read_routes::open,
            read_routes::open_role,
            read_routes::open_start,
            read_routes::open_source
        ))
        .routes(routes!(
            read_routes::header,
            read_routes::text,
            read_routes::entries,
            read_routes::entity,
            read_routes::lookup_account
        ))
        .routes(routes!(
            read_routes::accounts,
            read_routes::custom_models,
            read_routes::model_connections,
            read_routes::auto_compact_overrides
        ))
        .routes(routes!(
            read_routes::mode_routes,
            read_routes::role_routes,
            read_routes::mcp_configs,
            read_routes::strings
        ))
        .routes(routes!(
            read_routes::input_capabilities,
            read_routes::input_sources
        ))
        .routes(routes!(
            read_routes::role_header,
            read_routes::role_route,
            read_routes::start_header,
            read_routes::start_route
        ))
        .routes(routes!(
            read_routes::source_header,
            read_routes::source_text
        ))
        .routes(routes!(
            command::begin,
            command::find,
            command::result,
            command::request_close,
            command::close,
            command::retry_close
        ))
        .merge(super::profile_routes::router())
        .merge(super::profile_command_routes::router())
}
#[utoipa::path(post, path = "/api/v1/products/configuration/events", operation_id = "configuration.events", request_body = EmptyRequest,
    responses(StudioApiErrors, (status = 200, description = "Original typed Configuration stream; baseline occupies ACK credit; no replay.",
        headers(("x-studio-feed-id" = String, description = "Original native Configuration feed ID")), body = ConfigurationFrame, content_type = "text/event-stream")))]
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
    let mut opening = state
        .configuration
        .open(state.runtime.clone(), &state.shutdown, permit)?;
    let identity = opening.ready().await?;
    let feed_id = HeaderValue::from_str(&identity.feed_id).map_err(|_| {
        ApiError(StudioError::new(
            StudioErrorCode::Protocol,
            "Configuration feed ID is not a valid HTTP header",
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
