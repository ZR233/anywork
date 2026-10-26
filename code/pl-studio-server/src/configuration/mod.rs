//! HTTP ownership for the real Configuration native domain; no copied writer or read budget.
mod command;
mod control;
mod feed;
mod product;
mod profile_command_routes;
mod profile_control;
mod profile_routes;
mod read;
mod read_routes;
mod routes;
mod stream;
mod tasks;
mod types;

pub(crate) use feed::ConfigurationTransports;
pub(crate) use routes::router;

/// These exact routes own a permit from the existing Server pool, or are actual controls.
/// `Stream` here means the handler retains its own permit; commands use normal_requests, not
/// a second command semaphore. Root must consult this before its ordinary request middleware.
pub(crate) fn request_class(path: &str) -> Option<crate::templates::RequestClass> {
    use crate::templates::RequestClass;
    match path {
        "/api/v1/products/configuration/events"
        | "/api/v1/products/configuration/commands/begin"
        | "/api/v1/products/agent-profiles/commands/begin"
        | "/api/v1/products/configuration/reload/begin"
        | "/api/v1/products/agent-profiles/events" => Some(RequestClass::Stream),
        "/api/v1/configuration-feeds/{feed_id}/ack"
        | "/api/v1/configuration-feeds/{feed_id}/request-close"
        | "/api/v1/configuration-feeds/{feed_id}/close"
        | "/api/v1/configuration-feeds/{feed_id}/retry-close"
        | "/api/v1/configuration-reads/{scope_id}/request-close"
        | "/api/v1/configuration-reads/{scope_id}/close"
        | "/api/v1/configuration-reads/{scope_id}/retry-close"
        | "/api/v1/products/configuration/commands/find"
        | "/api/v1/configuration-commands/{call_id}/result"
        | "/api/v1/configuration-commands/{call_id}/request-close"
        | "/api/v1/configuration-commands/{call_id}/close"
        | "/api/v1/configuration-commands/{call_id}/retry-close" => Some(RequestClass::Control),
        "/api/v1/products/agent-profiles/commands/find"
        | "/api/v1/products/configuration/reload/find"
        | "/api/v1/profile-commands/{call_id}/result"
        | "/api/v1/profile-commands/{call_id}/request-close"
        | "/api/v1/profile-commands/{call_id}/close"
        | "/api/v1/profile-commands/{call_id}/retry-close"
        | "/api/v1/configuration-reloads/{call_id}/result"
        | "/api/v1/configuration-reloads/{call_id}/request-close"
        | "/api/v1/configuration-reloads/{call_id}/close"
        | "/api/v1/configuration-reloads/{call_id}/retry-close" => Some(RequestClass::Control),
        "/api/v1/agent-profiles-feeds/{feed_id}/ack"
        | "/api/v1/agent-profiles-feeds/{feed_id}/request-close"
        | "/api/v1/agent-profiles-feeds/{feed_id}/close"
        | "/api/v1/agent-profiles-feeds/{feed_id}/retry-close"
        | "/api/v1/agent-profiles-reads/{scope_id}/request-close"
        | "/api/v1/agent-profiles-reads/{scope_id}/close"
        | "/api/v1/agent-profiles-reads/{scope_id}/retry-close" => Some(RequestClass::Control),
        _ => None,
    }
}
