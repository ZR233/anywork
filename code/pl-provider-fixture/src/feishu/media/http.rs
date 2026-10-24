//! Shared resource HTTP admission and deliberately broken transport responses.

use axum::Json;
use axum::body::{Body, Bytes};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use tokio::sync::OwnedSemaphorePermit;

use crate::feishu::http::HttpState;
use crate::feishu::state::bearer_ok;
use crate::feishu::types::CallKind;

pub(crate) enum AdmissionFailure {
    ClosedOrLimit,
    Unauthorized,
    Forbidden,
    Busy,
}

impl IntoResponse for AdmissionFailure {
    fn into_response(self) -> Response {
        match self {
            Self::ClosedOrLimit => error(
                StatusCode::SERVICE_UNAVAILABLE,
                99991400,
                "peer resource request limit or shutdown",
            ),
            Self::Unauthorized => error(StatusCode::BAD_REQUEST, 99991663, "unauthorized"),
            Self::Forbidden => error(StatusCode::BAD_REQUEST, 99991672, "forbidden call"),
            Self::Busy => error(
                StatusCode::TOO_MANY_REQUESTS,
                99991400,
                "resource concurrency limit",
            ),
        }
    }
}

pub(crate) async fn begin(
    state: &HttpState,
    headers: &HeaderMap,
    kind: CallKind,
    method: &str,
    path: &str,
) -> Result<(usize, OwnedSemaphorePermit), AdmissionFailure> {
    let mut inner = state.shared.lock().await;
    if inner.closing || !inner.media.admit_request() {
        return Err(AdmissionFailure::ClosedOrLimit);
    }
    if !bearer_ok(
        &inner,
        headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok()),
    ) {
        inner.record(method, path, Some(kind), false, Some("unauthorized".into()));
        return Err(AdmissionFailure::Unauthorized);
    }
    if let Some(reason) = inner.kind_forbidden_or_excess(kind) {
        inner.record(method, path, Some(kind), false, Some(reason));
        return Err(AdmissionFailure::Forbidden);
    }
    let permit = match inner.media.permits.clone().try_acquire_owned() {
        Ok(permit) => permit,
        Err(_) => {
            inner.record(
                method,
                path,
                Some(kind),
                false,
                Some("resource concurrency limit".into()),
            );
            if let Some(call) = inner.calls.last_mut() {
                call.owned_reject = true;
            }
            return Err(AdmissionFailure::Busy);
        }
    };
    let index = inner.calls.len();
    inner.record(method, path, Some(kind), false, None);
    Ok((index, permit))
}

pub(crate) fn error(status: StatusCode, code: i32, msg: &str) -> Response {
    (status, Json(serde_json::json!({"code": code, "msg": msg}))).into_response()
}

pub(crate) fn interrupted_body(prefix: Bytes) -> Body {
    let mut chunks = Vec::with_capacity(2);
    if !prefix.is_empty() {
        chunks.push(Ok(prefix));
    }
    chunks.push(Err(std::io::Error::new(
        std::io::ErrorKind::ConnectionReset,
        "synthetic peer response disconnected",
    )));
    Body::from_stream(futures::stream::iter(chunks))
}
