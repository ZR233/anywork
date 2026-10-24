//! Shared request guards of the loopback HTTP peer.
//!
//! Authentication, forbidden/excess call bounds and rejection recording are one
//! owner used by every HTTP surface (`http`, `cardkit`, `ws`). Keeping them here
//! avoids a second authorization or evidence path per feature.

use axum::http::HeaderMap;
use tokio_util::sync::CancellationToken;

use super::state::{Shared, bearer_ok};

#[derive(Clone)]
pub(crate) struct HttpState {
    pub shared: Shared,
    pub cancel: CancellationToken,
}

pub(crate) async fn auth_ok(shared: &Shared, header: Option<&axum::http::HeaderValue>) -> bool {
    let inner = shared.lock().await;
    bearer_ok(&inner, header.and_then(|value| value.to_str().ok()))
}

pub(crate) async fn kind_blocked(shared: &Shared, kind: super::types::CallKind) -> Option<String> {
    let inner = shared.lock().await;
    inner.kind_forbidden_or_excess(kind)
}

pub(crate) async fn record_reject(
    shared: &Shared,
    method: &str,
    path: &str,
    kind: Option<super::types::CallKind>,
    diagnostic: String,
) {
    let mut inner = shared.lock().await;
    inner.record(method, path, kind, false, Some(diagnostic));
}

/// Bearer check over the request headers, for handlers that only hold both.
pub(crate) async fn headers_authorized(state: &HttpState, headers: &HeaderMap) -> bool {
    auth_ok(
        &state.shared,
        headers.get(axum::http::header::AUTHORIZATION),
    )
    .await
}
