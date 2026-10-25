//! Concrete HTTP ownership only. Native Models owns all source, scope/call and ACK budgets.
mod body;
mod control;
mod feed;
mod native;
mod queries;
mod read;
mod read_routes;
mod registry;
mod routes;
mod tasks;
mod types;

pub(crate) use registry::ModelsTransports;
pub(crate) use routes::router;

pub(crate) fn request_class(path: &str) -> Option<crate::templates::RequestClass> {
    use crate::templates::RequestClass;
    match path {
        "/api/v1/products/model-catalog/events" => Some(RequestClass::Stream),
        "/api/v1/model-catalog-feeds/{feed_id}/ack"
        | "/api/v1/model-catalog-feeds/{feed_id}/request-close"
        | "/api/v1/model-catalog-feeds/{feed_id}/close"
        | "/api/v1/model-catalog-feeds/{feed_id}/retry-close"
        | "/api/v1/models-reads/{scope_id}/request-close"
        | "/api/v1/models-reads/{scope_id}/close"
        | "/api/v1/models-reads/{scope_id}/retry-close" => Some(RequestClass::Control),
        _ => None,
    }
}
