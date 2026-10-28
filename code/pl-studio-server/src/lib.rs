//! Loopback HTTP/OpenAPI/SSE adapter for [`pl_studio_runtime::StudioRuntime`].

mod attachment_reads;
mod bots;
mod configuration;
mod draft_commands;
mod error;
mod exit;
mod models;
mod recovery;
mod routes;
mod security;
mod skills_schema;
mod sse;
mod templates;
mod thread_transport;

use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::Context;
use axum::Router;
use axum::extract::MatchedPath;
use axum::extract::{DefaultBodyLimit, Request, State};
use axum::middleware;
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use futures::FutureExt;
use pl_studio_runtime::{StudioRuntime, StudioRuntimeOptions};
use tokio::net::TcpListener;
use tokio::sync::Semaphore;
use tokio_util::sync::CancellationToken;
use utoipa::openapi::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

pub const DEFAULT_LISTEN: &str = "127.0.0.1:1421";
pub const MAX_JSON_BODY_BYTES: usize = 4 * 1024 * 1024;
const MAX_REQUESTS: usize = 64;
const MAX_STREAMS: usize = 64;
const MAX_CONTROLS: usize = 64;

#[derive(Default)]
struct LegacyStreams {
    active: Vec<tokio::task::JoinHandle<()>>,
    failures: Vec<tokio::task::JoinError>,
}

#[derive(Debug, Clone)]
pub struct ServerOptions {
    pub listen: SocketAddr,
    pub studio_home: Option<PathBuf>,
}

#[derive(Clone)]
pub(crate) struct AppState {
    runtime: StudioRuntime,
    normal_requests: Arc<Semaphore>,
    streams: Arc<Semaphore>,
    controls: Arc<Semaphore>,
    templates: Arc<templates::TemplatesTransports>,
    models: Arc<models::ModelsTransports>,
    configuration: Arc<configuration::ConfigurationTransports>,
    recovery: Arc<recovery::RecoveryTransports>,
    attachment_reads: Arc<attachment_reads::AttachmentReads>,
    thread_transports: Arc<thread_transport::ThreadTransports>,
    draft_commands: Arc<draft_commands::DraftCommands>,
    legacy_streams: Arc<std::sync::Mutex<LegacyStreams>>,
    shutdown: CancellationToken,
}

impl AppState {
    fn new(runtime: StudioRuntime, shutdown: CancellationToken) -> Self {
        Self {
            runtime,
            normal_requests: Arc::new(Semaphore::new(MAX_REQUESTS)),
            streams: Arc::new(Semaphore::new(MAX_STREAMS)),
            controls: Arc::new(Semaphore::new(MAX_CONTROLS)),
            templates: Arc::default(),
            models: Arc::default(),
            configuration: Arc::default(),
            recovery: Arc::default(),
            attachment_reads: Arc::default(),
            thread_transports: Arc::default(),
            draft_commands: Arc::default(),
            legacy_streams: Arc::default(),
            shutdown,
        }
    }

    /// Retain the pre-existing pumps too, so adding one supervised domain cannot let the shared
    /// server finalizer run past an unobserved legacy JoinHandle. Their wire semantics stay intact.
    fn track_legacy_stream(&self, task: tokio::task::JoinHandle<()>) {
        let mut streams = self
            .legacy_streams
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for mut old in std::mem::take(&mut streams.active) {
            match (&mut old).now_or_never() {
                Some(Ok(())) => {}
                Some(Err(error)) => streams.failures.push(error),
                None => streams.active.push(old),
            }
        }
        streams.active.push(task);
    }
}

pub fn openapi_document() -> OpenApi {
    routes::api_router().into_openapi()
}

pub fn openapi_json() -> anyhow::Result<String> {
    serde_json::to_string_pretty(&openapi_document()).context("failed to serialize OpenAPI")
}

pub async fn serve(options: ServerOptions) -> anyhow::Result<()> {
    security::ensure_loopback_bind(options.listen)?;
    let listener = TcpListener::bind(options.listen)
        .await
        .with_context(|| format!("failed to bind {}", options.listen))?;
    let runtime = StudioRuntime::initialize(StudioRuntimeOptions::http_server(options.studio_home))
        .await
        .map_err(anyhow::Error::new)?;
    let shutdown = CancellationToken::new();
    let state = AppState::new(runtime, shutdown);
    let app = router(state.clone());
    exit::run(listener, app, state).await
}

fn router(state: AppState) -> Router {
    let (router, openapi) = routes::api_router().split_for_parts();
    router
        .merge(SwaggerUi::new("/docs").url("/openapi.json", openapi))
        .layer(DefaultBodyLimit::max(MAX_JSON_BODY_BYTES))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            limit_normal_requests,
        ))
        .layer(middleware::from_fn(security::validate_request))
        .with_state(state)
}

async fn limit_normal_requests(
    State(state): State<AppState>,
    mut request: Request,
    next: Next,
) -> Response {
    if state.shutdown.is_cancelled() {
        return error::ApiError(pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Cancelled,
            "Studio HTTP admission is closed",
            false,
        ))
        .into_response();
    }
    let class = request
        .extensions()
        .get::<MatchedPath>()
        .map(|path| match path.as_str() {
            "/api/v1/attachment-reads/{scope_id}/close"
            | "/api/v1/attachment-reads/{scope_id}/retry-close" => templates::RequestClass::Control,
            "/api/v1/threads/{thread_id}/execution/events" => templates::RequestClass::Stream,
            "/api/v1/threads/{thread_id}/authoring/events" => templates::RequestClass::Stream,
            "/api/v1/thread-creations/progress" | "/api/v1/thread-creations/execution/events" => {
                templates::RequestClass::Stream
            }
            "/api/v1/attachment-admissions/find"
            | "/api/v1/attachment-admissions/result"
            | "/api/v1/attachment-admissions/request-close"
            | "/api/v1/attachment-admissions/close"
            | "/api/v1/attachment-admissions/retry-close"
            | "/api/v1/thread-creations/find"
            | "/api/v1/thread-creations/result"
            | "/api/v1/thread-creations/execution-source"
            | "/api/v1/thread-creations/request-close"
            | "/api/v1/thread-creations/close"
            | "/api/v1/thread-creations/retry-close"
            | "/api/v1/attachment-uploads/find"
            | "/api/v1/attachment-uploads/result"
            | "/api/v1/attachment-uploads/request-close"
            | "/api/v1/attachment-uploads/close"
            | "/api/v1/attachment-uploads/retry-close" => templates::RequestClass::Control,
            "/api/v1/thread-feeds/{feed_id}/ack"
            | "/api/v1/thread-feeds/{feed_id}/request-close"
            | "/api/v1/thread-feeds/{feed_id}/close"
            | "/api/v1/thread-feeds/{feed_id}/retry-close"
            | "/api/v1/thread-reads/{scope_id}/request-close"
            | "/api/v1/thread-reads/{scope_id}/close"
            | "/api/v1/thread-reads/{scope_id}/retry-close" => templates::RequestClass::Control,
            "/api/v1/authoring-feeds/{feed_id}/ack"
            | "/api/v1/authoring-feeds/{feed_id}/request-close"
            | "/api/v1/authoring-feeds/{feed_id}/close"
            | "/api/v1/authoring-feeds/{feed_id}/retry-close"
            | "/api/v1/authoring-reads/{scope_id}/request-close"
            | "/api/v1/authoring-reads/{scope_id}/close"
            | "/api/v1/authoring-reads/{scope_id}/retry-close" => templates::RequestClass::Control,
            path => models::request_class(path)
                .or_else(|| configuration::request_class(path))
                .or_else(|| recovery::request_class(path))
                .unwrap_or_else(|| templates::request_class(path)),
        })
        .unwrap_or(templates::RequestClass::Normal);
    match class {
        templates::RequestClass::Stream => return next.run(request).await,
        templates::RequestClass::Control => {
            let Ok(_permit) = state.controls.clone().try_acquire_owned() else {
                return error::ApiError::overloaded().into_response();
            };
            return next.run(request).await;
        }
        templates::RequestClass::Normal => {}
    }
    // Only the existing GET streams still use their legacy routing form. Every new Templates
    // POST above is explicitly classified by its exact registered MatchedPath.
    let path = request.uri().path();
    if path == "/api/v1/events/product"
        || (path.starts_with("/api/v1/threads/") && path.ends_with("/events"))
    {
        return next.run(request).await;
    }
    let Ok(_permit) = state.normal_requests.clone().try_acquire_owned() else {
        return error::ApiError::overloaded().into_response();
    };
    if request.uri().path() == "/api/v1/attachments/drafts/upload" {
        // Move this exact existing permit into the upload owner before any body/file IO. The
        // registry retains it after response loss and returns it only after real cleanup join.
        request
            .extensions_mut()
            .insert(draft_commands::UploadPermit(Arc::new(
                std::sync::Mutex::new(Some(_permit)),
            )));
        return next.run(request).await;
    }
    next.run(request).await
}

async fn wait_for_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{SignalKind, signal};
        let mut terminate = signal(SignalKind::terminate()).ok();
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = async {
                if let Some(signal) = terminate.as_mut() {
                    signal.recv().await;
                } else {
                    std::future::pending::<()>().await;
                }
            } => {}
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}
