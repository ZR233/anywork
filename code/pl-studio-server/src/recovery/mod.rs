//! Recovery HTTP resource ownership only; the native source owns material, references and credit.
mod control;
mod feed;
mod native;
mod read;
mod read_routes;
mod registry;
mod routes;
mod stream;
mod tasks;
mod types;

pub(crate) use registry::RecoveryTransports;
pub(crate) use routes::router;

pub(crate) fn request_class(path: &str) -> Option<crate::templates::RequestClass> {
    use crate::templates::RequestClass;
    match path {
        "/api/v1/products/recovery/events" => Some(RequestClass::Stream),
        "/api/v1/recovery-feeds/{feed_id}/ack"
        | "/api/v1/recovery-feeds/{feed_id}/request-close"
        | "/api/v1/recovery-feeds/{feed_id}/close"
        | "/api/v1/recovery-feeds/{feed_id}/retry-close"
        | "/api/v1/recovery-reads/{scope_id}/request-close"
        | "/api/v1/recovery-reads/{scope_id}/close"
        | "/api/v1/recovery-reads/{scope_id}/retry-close" => Some(RequestClass::Control),
        _ => None,
    }
}
