use std::time::Duration;

use axum::extract::State;
use axum::http::HeaderValue;
use axum::response::sse::{KeepAlive, Sse};
use axum::response::{IntoResponse, Response};
use pl_protocol::products::feed::recovery::RecoveryFrame;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use utoipa_axum::{router::OpenApiRouter, routes};

use super::{control, read_routes};
use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, NoReplay, StudioApiErrors};
use crate::templates::EmptyRequest;

pub(crate) fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(events))
        .routes(routes!(control::ack))
        .routes(routes!(control::request_close))
        .routes(routes!(control::close))
        .routes(routes!(control::retry_close))
        .routes(routes!(control::request_read_close))
        .routes(routes!(control::read_close))
        .routes(routes!(control::retry_read_close))
        .routes(routes!(read_routes::open))
        .routes(routes!(read_routes::open_source))
        .routes(routes!(read_routes::header))
        .routes(routes!(read_routes::entries))
        .routes(routes!(read_routes::entity))
        .routes(routes!(read_routes::lookup_issue))
        .routes(routes!(read_routes::issues))
        .routes(routes!(read_routes::changed_files))
        .routes(routes!(read_routes::text))
        .routes(routes!(read_routes::source_header))
        .routes(routes!(read_routes::source_text))
}

#[utoipa::path(post, path = "/api/v1/products/recovery/events", operation_id = "recovery.events", request_body = EmptyRequest,
    responses(StudioApiErrors, (status = 200, description = "Original Recovery typed stream. Baseline occupies one of two unACKed Data credits. Explicit ACK and request-close/close/retry-close use /api/v1/recovery-feeds/{feed_id}/. No replay; Last-Event-ID is rejected.",
        headers(("x-studio-feed-id" = String, description = "Original native Recovery feed ID")),
        body = RecoveryFrame, content_type = "text/event-stream")))]
async fn events(
    State(state): State<AppState>,
    _replay: NoReplay,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Response, ApiError> {
    state.recovery.reap();
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::overloaded())?;
    let mut opening = state
        .recovery
        .open(&state.runtime, &state.shutdown, permit)?;
    let identity = opening.ready().await?;
    let feed_id = HeaderValue::from_str(&identity.feed_id).map_err(|_| {
        ApiError(StudioError::new(
            StudioErrorCode::Protocol,
            "The native Recovery feed ID is not a valid HTTP header",
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
