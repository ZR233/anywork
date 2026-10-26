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
        // 每个 handler 各自声明自己的 path/method：`routes!` 只产生一个 MethodRouter，
        // 多个同 method 的 handler 放进同一次调用会在装配期重复登记 POST。
        .routes(routes!(control::ack))
        .routes(routes!(control::request_close))
        .routes(routes!(control::close))
        .routes(routes!(control::retry_close))
        .routes(routes!(control::request_read_close))
        .routes(routes!(control::read_close))
        .routes(routes!(control::retry_read_close))
        .routes(routes!(read_routes::open))
        .routes(routes!(read_routes::open_role))
        .routes(routes!(read_routes::open_start))
        .routes(routes!(read_routes::open_source))
        .routes(routes!(read_routes::header))
        .routes(routes!(read_routes::text))
        .routes(routes!(read_routes::entries))
        .routes(routes!(read_routes::entity))
        .routes(routes!(read_routes::lookup_account))
        .routes(routes!(read_routes::accounts))
        .routes(routes!(read_routes::acp_accounts))
        .routes(routes!(read_routes::custom_models))
        .routes(routes!(read_routes::model_connections))
        .routes(routes!(read_routes::auto_compact_overrides))
        .routes(routes!(read_routes::mode_routes))
        .routes(routes!(read_routes::role_routes))
        .routes(routes!(read_routes::mcp_configs))
        .routes(routes!(read_routes::strings))
        .routes(routes!(read_routes::input_capabilities))
        .routes(routes!(read_routes::input_sources))
        .routes(routes!(read_routes::role_header))
        .routes(routes!(read_routes::role_route))
        .routes(routes!(read_routes::start_header))
        .routes(routes!(read_routes::start_route))
        .routes(routes!(read_routes::source_header))
        .routes(routes!(read_routes::source_text))
        .routes(routes!(command::begin))
        .routes(routes!(command::find))
        .routes(routes!(command::result))
        .routes(routes!(command::request_close))
        .routes(routes!(command::close))
        .routes(routes!(command::retry_close))
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
