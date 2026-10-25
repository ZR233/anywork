//! Templates HTTP transport ownership only. Canonical values and ACK window stay in runtime.
mod control;
mod feed;
mod read;
mod read_routes;
mod routes;
mod stream;
mod tasks;
mod types;

pub(crate) use feed::TemplatesTransports;
pub(crate) use routes::router;

pub(crate) enum RequestClass {
    Normal,
    Stream,
    Control,
}

/// Exact registered route patterns, not substring classification of new POST requests.
pub(crate) fn request_class(path: &str) -> RequestClass {
    match path {
        "/api/v1/products/account-templates/events" => RequestClass::Stream,
        "/api/v1/feeds/{feed_id}/ack"
        | "/api/v1/feeds/{feed_id}/request-close"
        | "/api/v1/feeds/{feed_id}/close"
        | "/api/v1/feeds/{feed_id}/retry-close"
        | "/api/v1/read-scopes/{scope_id}/request-close"
        | "/api/v1/read-scopes/{scope_id}/close"
        | "/api/v1/read-scopes/{scope_id}/retry-close" => RequestClass::Control,
        _ => RequestClass::Normal,
    }
}
