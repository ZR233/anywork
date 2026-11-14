//! ACP production HTTP boundary. The runtime owns sessions, publication and SDK IO.

mod frames;

use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::{IntoResponse, Response};
use futures::stream;
use pl_protocol::studio::*;
use utoipa_axum::{router::OpenApiRouter, routes};

use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, StudioApiErrors};
use frames::OpenFrames;

pub(crate) fn routes() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(open))
        .routes(routes!(prompt))
        .routes(routes!(replace))
        .routes(routes!(interrupt))
        .routes(routes!(configure))
        .routes(routes!(set_mode))
        .routes(routes!(permission))
        .routes(routes!(list))
        .routes(routes!(snapshot))
        .routes(routes!(close))
}

/// Preserve business diagnostics, including original RPC data and auth methods.
enum AcpApiError {
    Business(AcpBusinessFailure),
    Runtime(ApiError),
}

impl From<AcpBusinessFailure> for AcpApiError {
    fn from(error: AcpBusinessFailure) -> Self {
        Self::Business(error)
    }
}

impl From<anyhow::Error> for AcpApiError {
    fn from(error: anyhow::Error) -> Self {
        match error.downcast::<AcpBusinessFailure>() {
            Ok(error) => Self::Business(error),
            Err(error) => Self::Runtime(ApiError::from(error)),
        }
    }
}

impl IntoResponse for AcpApiError {
    fn into_response(self) -> Response {
        match self {
            Self::Runtime(error) => error.into_response(),
            Self::Business(error) => {
                let status = match error.kind {
                    AcpBusinessFailureKind::Busy
                    | AcpBusinessFailureKind::Stale
                    | AcpBusinessFailureKind::NotReady => StatusCode::CONFLICT,
                    AcpBusinessFailureKind::Closed => StatusCode::GONE,
                    AcpBusinessFailureKind::Unsupported => StatusCode::NOT_IMPLEMENTED,
                    AcpBusinessFailureKind::UnsupportedVersion
                    | AcpBusinessFailureKind::ServerVersionMismatch
                    | AcpBusinessFailureKind::InvalidOption => StatusCode::BAD_REQUEST,
                    AcpBusinessFailureKind::Rpc => StatusCode::BAD_GATEWAY,
                    AcpBusinessFailureKind::InstallRequired
                    | AcpBusinessFailureKind::InstallationInvalid
                    | AcpBusinessFailureKind::UnsupportedPlatform
                    | AcpBusinessFailureKind::MissingExecutable
                    | AcpBusinessFailureKind::InvalidWorkingDirectory
                    | AcpBusinessFailureKind::InvalidDefinition
                    | AcpBusinessFailureKind::Io
                    | AcpBusinessFailureKind::Cancelled
                    | AcpBusinessFailureKind::Preparation
                    | AcpBusinessFailureKind::Publication => StatusCode::SERVICE_UNAVAILABLE,
                };
                (status, Json(error)).into_response()
            }
        }
    }
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/open", operation_id = "acpSessions.open",
    request_body = OpenAcpSessionRequest,
    responses(StudioApiErrors, (status = 200, body = AcpSessionFrame, content_type = "text/event-stream"),
        (status = 502, body = AcpBusinessFailure)))]
async fn open(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<OpenAcpSessionRequest>,
) -> Result<impl IntoResponse, AcpApiError> {
    // Reserve capacity before admission; rejecting a transport must not open a session.
    let permit = state
        .streams
        .clone()
        .try_acquire_owned()
        .map_err(|_| AcpApiError::Runtime(ApiError::overloaded()))?;
    let opened = state.runtime.open_acp_session(request).await?;
    let source = (OpenFrames::new(opened), permit, state.shutdown);
    let events = stream::unfold(source, |(mut frames, permit, shutdown)| async move {
        let frame = tokio::select! {
            biased;
            () = shutdown.cancelled() => return None,
            frame = frames.next() => frame?,
        };
        Some((
            Event::default().event("acpSession").json_data(frame),
            (frames, permit, shutdown),
        ))
    });
    // Dropping this response only drops the observation and its completion waiter.
    // It never calls business close, cancel or interrupt.
    Ok(Sse::new(events).keep_alive(KeepAlive::default()))
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/prompt", operation_id = "acpSessions.prompt",
    request_body = AcpPromptRequest,
    responses(StudioApiErrors, (status = 200, body = AcpRunId), (status = 502, body = AcpBusinessFailure)))]
async fn prompt(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpPromptRequest>,
) -> Result<Json<AcpRunId>, AcpApiError> {
    Ok(Json(
        state
            .runtime
            .prompt_acp_session(request.target, request.content)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/replace", operation_id = "acpSessions.replace",
    request_body = AcpReplaceRequest,
    responses(StudioApiErrors, (status = 200, body = AcpRunId), (status = 502, body = AcpBusinessFailure)))]
async fn replace(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpReplaceRequest>,
) -> Result<Json<AcpRunId>, AcpApiError> {
    Ok(Json(
        state
            .runtime
            .replace_acp_session(request.target, request.run, request.content)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/interrupt", operation_id = "acpSessions.interrupt",
    request_body = AcpInterruptRequest,
    responses(StudioApiErrors, (status = 204), (status = 502, body = AcpBusinessFailure)))]
async fn interrupt(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpInterruptRequest>,
) -> Result<StatusCode, AcpApiError> {
    state
        .runtime
        .interrupt_acp_session(request.target, request.run)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/configure", operation_id = "acpSessions.configure",
    request_body = AcpConfigureRequest,
    responses(StudioApiErrors, (status = 204), (status = 502, body = AcpBusinessFailure)))]
async fn configure(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpConfigureRequest>,
) -> Result<StatusCode, AcpApiError> {
    state
        .runtime
        .configure_acp_session(request.target, request.config_id, request.value)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/set-mode", operation_id = "acpSessions.setMode",
    request_body = AcpSetModeRequest,
    responses(StudioApiErrors, (status = 204), (status = 502, body = AcpBusinessFailure)))]
async fn set_mode(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpSetModeRequest>,
) -> Result<StatusCode, AcpApiError> {
    state
        .runtime
        .set_acp_session_mode(request.target, request.mode_id)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/permission", operation_id = "acpSessions.permission",
    request_body = AcpPermissionAnswerRequest,
    responses(StudioApiErrors, (status = 204), (status = 502, body = AcpBusinessFailure)))]
async fn permission(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpPermissionAnswerRequest>,
) -> Result<StatusCode, AcpApiError> {
    state
        .runtime
        .answer_acp_permission(request.target, request.permission_id, request.option_id)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/list", operation_id = "acpSessions.list",
    request_body = AcpListRequest,
    responses(StudioApiErrors, (status = 200, description = "Official ACP ListSessionsResponse"),
        (status = 502, body = AcpBusinessFailure)))]
async fn list(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AcpListRequest>,
) -> Result<Json<ListSessionsResponse>, AcpApiError> {
    Ok(Json(
        state
            .runtime
            .list_acp_sessions(request.target, request.request)
            .await?,
    ))
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/snapshot", operation_id = "acpSessions.snapshot",
    request_body = AcpSessionTarget,
    responses(StudioApiErrors, (status = 200, body = AcpBusinessSnapshot), (status = 502, body = AcpBusinessFailure)))]
async fn snapshot(
    State(state): State<AppState>,
    ApiJson(target): ApiJson<AcpSessionTarget>,
) -> Result<Json<AcpBusinessSnapshot>, AcpApiError> {
    Ok(Json(state.runtime.acp_session_snapshot(target).await?))
}

#[utoipa::path(post, path = "/api/v1/acp/sessions/close", operation_id = "acpSessions.close",
    request_body = AcpSessionTarget,
    responses(StudioApiErrors, (status = 200, body = AcpBusinessClose), (status = 502, body = AcpBusinessFailure)))]
async fn close(
    State(state): State<AppState>,
    ApiJson(target): ApiJson<AcpSessionTarget>,
) -> Result<Json<AcpBusinessClose>, AcpApiError> {
    Ok(Json(state.runtime.close_acp_session(target).await?))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;

    #[tokio::test]
    async fn business_error_keeps_status_kind_rpc_data_and_authentication_methods() {
        use AcpBusinessFailureKind as K;
        use StatusCode as S;

        for (kind, status) in [
            (K::Busy, S::CONFLICT),
            (K::Stale, S::CONFLICT),
            (K::NotReady, S::CONFLICT),
            (K::Closed, S::GONE),
            (K::Unsupported, S::NOT_IMPLEMENTED),
            (K::UnsupportedVersion, S::BAD_REQUEST),
            (K::ServerVersionMismatch, S::BAD_REQUEST),
            (K::InvalidOption, S::BAD_REQUEST),
            (K::Rpc, S::BAD_GATEWAY),
            (K::InstallRequired, S::SERVICE_UNAVAILABLE),
            (K::InstallationInvalid, S::SERVICE_UNAVAILABLE),
            (K::UnsupportedPlatform, S::SERVICE_UNAVAILABLE),
            (K::MissingExecutable, S::SERVICE_UNAVAILABLE),
            (K::InvalidWorkingDirectory, S::SERVICE_UNAVAILABLE),
            (K::InvalidDefinition, S::SERVICE_UNAVAILABLE),
            (K::Io, S::SERVICE_UNAVAILABLE),
            (K::Cancelled, S::SERVICE_UNAVAILABLE),
            (K::Preparation, S::SERVICE_UNAVAILABLE),
            (K::Publication, S::SERVICE_UNAVAILABLE),
        ] {
            let failure = AcpBusinessFailure {
                kind: kind.clone(),
                rpc_code: Some(-32000),
                message: "original safe runtime message".into(),
                rpc_data: Some(Box::new(serde_json::json!({
                    "retry": false, "nested": [null, {"scope": "actual-peer"}]
                }))),
                auth_methods: vec![AcpAuthMethod {
                    id: "actual-login".into(),
                    name: "Peer login".into(),
                    description: Some("Actual initialize description".into()),
                    kind: AcpAuthMethodKind::Agent,
                }],
            };
            let expected = serde_json::to_value(&failure).unwrap();
            let error = AcpApiError::from(anyhow::Error::new(failure).context("open failed"));
            let response = error.into_response();
            assert_eq!(response.status(), status, "{kind:?}");
            assert!(
                !response
                    .headers()
                    .contains_key(axum::http::header::RETRY_AFTER)
            );
            let body = to_bytes(response.into_body(), 8192).await.unwrap();
            let decoded: AcpBusinessFailure = serde_json::from_slice(&body).unwrap();
            assert_eq!(decoded.kind, kind);
            assert_eq!(serde_json::to_value(decoded).unwrap(), expected);
        }
    }

    #[tokio::test]
    async fn nonbusiness_anyhow_failure_keeps_runtime_typed_envelope() {
        let failure = StudioError::new(StudioErrorCode::StaleRevision, "stale document", false);
        let correlation_id = failure.correlation_id.clone();
        let response = AcpApiError::from(anyhow::Error::new(failure)).into_response();
        assert_eq!(response.status(), StatusCode::CONFLICT);
        assert_eq!(response.headers()["x-correlation-id"], correlation_id);
        let body = to_bytes(response.into_body(), 8192).await.unwrap();
        let failure: StudioError = serde_json::from_slice(&body).unwrap();
        assert_eq!(failure.code, StudioErrorCode::StaleRevision);
        assert_eq!(failure.message, "stale document");
    }

    #[test]
    fn request_qualification_does_not_substitute_product_instance_for_sdk_run() {
        let request: AcpReplaceRequest = serde_json::from_value(serde_json::json!({
            "target": {
                "sessionId": "product-session", "agentId": "product-agent",
                "threadId": "product-thread", "instance": 41
            },
            "run": { "instance": 9, "sequence": 12 },
            "content": [{ "type": "text", "text": " replacement " }]
        }))
        .unwrap();
        assert_eq!(request.target.instance, 41);
        assert_eq!(request.run.instance, 9);
        assert_eq!(request.run.sequence, 12);
        let value = serde_json::to_value(request).unwrap();
        assert_eq!(value["content"][0]["text"], " replacement ");
    }

    #[test]
    fn partial_close_preserves_all_cleanup_facts() {
        let close = AcpBusinessClose {
            local_complete: false,
            sdk_finished: true,
            cleanup_timed_out: true,
            remote_close_error: None,
            sdk_error: None,
            worker_error: Some("worker still closing".into()),
            driver_error: None,
            unfinished_prompt: Some(AcpRunId {
                instance: 9,
                sequence: 12,
            }),
            unfinished_controls: true,
            last_completed: None,
            owner_failures: vec![AcpMemberCloseFailure {
                thread_id: "actual-child".into(),
                message: "cleanup pending".into(),
            }],
        };
        let encoded = serde_json::to_value(&close).unwrap();
        let decoded: AcpBusinessClose = serde_json::from_value(encoded.clone()).unwrap();
        assert_eq!(serde_json::to_value(decoded).unwrap(), encoded);
        assert_eq!(encoded["localComplete"], false);
        assert_eq!(encoded["unfinishedPrompt"]["instance"], 9);
        assert_eq!(encoded["ownerFailures"][0]["threadId"], "actual-child");
    }

    #[test]
    fn snapshot_keeps_distinct_config_types_grouping_metadata_and_absent_vs_empty() {
        let configs = serde_json::json!([
            {
                "id": "select-config", "name": "Model", "description": "Choose model",
                "category": "model", "type": "select", "currentValue": "second",
                "options": [{
                    "group": "peer-group", "name": "Peer models",
                    "options": [
                        {"value": "first", "name": "First", "description": "First model"},
                        {"value": "second", "name": "Second", "_meta": {"weight": 2}}
                    ],
                    "_meta": {"groupOrder": 3}
                }],
                "_meta": {"order": 7, "nested": {"peer": true}}
            },
            {
                "id": "boolean-config", "name": "Review", "description": "Require review",
                "type": "boolean", "currentValue": false,
                "_meta": {"order": 2}
            }
        ]);
        let mut snapshot = AcpBusinessSnapshot {
            target: AcpSessionTarget {
                session_id: "product-session".into(),
                agent_id: "product-agent".into(),
                thread_id: "product-thread".into(),
                instance: 41,
            },
            acp_session_id: Some("remote-session".into()),
            ready: true,
            closing: false,
            config_pending: false,
            config_options: Some(serde_json::from_value(configs.clone()).unwrap()),
            modes: None,
            active_run: None,
            last_completed: None,
            observation_gap: None,
            auth_methods: vec![],
        };
        let value = serde_json::to_value(&snapshot).unwrap();
        assert_eq!(value["configOptions"], configs);
        let decoded: AcpBusinessSnapshot = serde_json::from_value(value).unwrap();
        assert_eq!(decoded.config_options, snapshot.config_options);
        snapshot.config_options = Some(vec![]);
        assert_eq!(
            serde_json::to_value(&snapshot).unwrap()["configOptions"],
            serde_json::json!([])
        );
        snapshot.config_options = None;
        assert_eq!(
            serde_json::to_value(snapshot).unwrap()["configOptions"],
            serde_json::Value::Null
        );
    }

    #[cfg(target_os = "linux")]
    mod real_transport {
        //! Real loopback HTTP -> Runtime -> supervised shared peer, not synthetic frames.
        use std::panic::AssertUnwindSafe;
        use std::path::PathBuf;
        use std::time::Duration;

        use anyhow::{Context, Result, ensure};
        use futures::{FutureExt, StreamExt};
        use pl_protocol::studio::*;
        use reqwest::{Client, Response};
        use serde::{Serialize, de::DeserializeOwned};
        use tokio::time::{sleep, timeout};
        use tokio_util::sync::CancellationToken;

        // Other consumers use open/ready directly; this consumer opens through real HTTP.

        use acp_transport_fixture::AcpTransportFixture as Fixture;

        struct Server {
            base: String,
            client: Client,
            state: crate::AppState,
            body_gate: Option<CancellationToken>,
            task: tokio::task::JoinHandle<std::io::Result<()>>,
        }

        impl Server {
            async fn start(fixture: &Fixture) -> Result<Self> {
                Self::start_with_body_gate(fixture, None).await
            }

            async fn start_with_body_gate(
                fixture: &Fixture,
                body_gate: Option<CancellationToken>,
            ) -> Result<Self> {
                let prepared = async {
                    let client = Client::builder().no_proxy().build()?;
                    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
                    let address = listener.local_addr()?;
                    Ok::<_, anyhow::Error>((client, listener, address))
                }
                .await;
                let (client, listener, address) = match prepared {
                    Ok(prepared) => prepared,
                    Err(error) => {
                        fixture.runtime.shutdown_runtime().await?;
                        return Err(error);
                    }
                };
                let state = crate::AppState::new(fixture.runtime.clone(), CancellationToken::new());
                let base = format!("http://{address}/api/v1/acp/sessions");
                let mut app = crate::router(state.clone());
                if let Some(gate) = body_gate.clone() {
                    // Test-only downstream backpressure: pass the original Accepted bytes,
                    // then do not poll the original SSE body until the test releases it.
                    // No ACP frames, observations or completion results are manufactured.
                    app = app.layer(axum::middleware::from_fn(
                        move |request: axum::extract::Request, next: axum::middleware::Next| {
                            let gate = gate.clone();
                            async move {
                                let opening = request.uri().path() == "/api/v1/acp/sessions/open";
                                let response = next.run(request).await;
                                if !opening {
                                    return response;
                                }
                                let (parts, body) = response.into_parts();
                                let stream = futures::stream::unfold(
                                    (body.into_data_stream(), false, gate),
                                    |(mut body, accepted, gate)| async move {
                                        if accepted {
                                            gate.cancelled().await;
                                        }
                                        let bytes = body.next().await?;
                                        Some((bytes, (body, true, gate)))
                                    },
                                );
                                axum::response::Response::from_parts(
                                    parts,
                                    axum::body::Body::from_stream(stream),
                                )
                            }
                        },
                    ));
                }
                let stop = state.shutdown.clone();
                let task = tokio::spawn(async move {
                    axum::serve(listener, app)
                        .with_graceful_shutdown(stop.cancelled_owned())
                        .await
                });
                Ok(Self {
                    base,
                    client,
                    state,
                    body_gate,
                    task,
                })
            }

            async fn post(&self, method: &str, body: &impl Serialize) -> Result<Response> {
                Ok(self
                    .client
                    .post(format!("{}/{method}", self.base))
                    .json(body)
                    .send()
                    .await?)
            }

            async fn json<T: DeserializeOwned>(
                &self,
                method: &str,
                body: &impl Serialize,
            ) -> Result<T> {
                Ok(self
                    .post(method, body)
                    .await?
                    .error_for_status()?
                    .json()
                    .await?)
            }

            // Called outside catch_unwind/timeout while fixture still owns home and runtime.
            async fn finish(mut self, fixture: &Fixture) -> Result<()> {
                let release = std::fs::write(fixture.home.path().join("release"), "");
                if let Some(gate) = &self.body_gate {
                    gate.cancel();
                }
                self.state.shutdown.cancel();
                self.state.conversations.shutdown().await;
                let shutdown = fixture.runtime.shutdown_runtime().await;
                let joined = timeout(Duration::from_secs(20), &mut self.task).await;
                if joined.is_err() {
                    self.task.abort();
                    let _ = self.task.await;
                    anyhow::bail!("HTTP listener did not join after shutdown");
                }
                for name in ["pid", "child"] {
                    if fixture.home.path().join(name).exists() {
                        let pid = fixture.pid(name)?;
                        ensure!(
                            !PathBuf::from(format!("/proc/{pid}")).exists(),
                            "{name} {pid} leaked"
                        );
                    }
                }
                release?;
                joined???;
                ensure!(shutdown?.state.is_stopped());
                Ok(())
            }
        }

        // Only SSE framing is decoded here; ACP payloads use the original typed serde.
        struct Sse {
            response: Response,
            buffered: Vec<u8>,
        }

        impl Sse {
            fn new(response: Response) -> Result<Self> {
                let response = response.error_for_status()?;
                ensure!(
                    response.headers()["content-type"] == "text/event-stream",
                    "open must be same-POST SSE"
                );
                Ok(Self {
                    response,
                    buffered: vec![],
                })
            }

            async fn next(&mut self) -> Result<Option<AcpSessionFrame>> {
                loop {
                    if let Some(end) = self.buffered.windows(2).position(|pair| pair == b"\n\n") {
                        let bytes: Vec<_> = self.buffered.drain(..end + 2).collect();
                        let block = std::str::from_utf8(&bytes)?;
                        if let Some(data) =
                            block.lines().find_map(|line| line.strip_prefix("data: "))
                        {
                            ensure!(block.lines().any(|line| line == "event: acpSession"));
                            return Ok(Some(serde_json::from_str(data)?));
                        }
                        continue; // SSE keepalive comment.
                    }
                    match self.response.chunk().await? {
                        Some(bytes) => self.buffered.extend(bytes),
                        None => {
                            ensure!(self.buffered.is_empty(), "truncated SSE frame");
                            return Ok(None);
                        }
                    }
                }
            }
        }

        fn request(fixture: &Fixture, thread_id: Option<String>) -> OpenAcpSessionRequest {
            OpenAcpSessionRequest {
                account_id: "business-peer".into(),
                expected_connection_revision: fixture.revision,
                workspace_id: fixture.workspace.id.clone(),
                thread_id,
                intent: AcpOpenIntent::Load("remote-one".into()),
            }
        }

        async fn accepted(stream: &mut Sse, observed: bool) -> Result<AcpSessionTarget> {
            let Some(AcpSessionFrame::Accepted {
                target,
                has_observation,
            }) = stream.next().await?
            else {
                anyhow::bail!("first HTTP frame was not Accepted");
            };
            ensure!(has_observation == observed);
            ensure!(target.session_id != target.agent_id && target.agent_id != target.thread_id);
            Ok(target)
        }

        async fn initialized(stream: &mut Sse) -> Result<()> {
            let Some(AcpSessionFrame::Event { event }) = stream.next().await? else {
                anyhow::bail!("missing initialization event");
            };
            let AcpSessionEvent::Initialized { capabilities } = *event else {
                anyhow::bail!("initialize must precede replay and publication");
            };
            ensure!(capabilities.load_session);
            Ok(())
        }

        async fn published(stream: &mut Sse) -> Result<()> {
            let (mut ready, mut settled) = (0, 0);
            while ready == 0 || settled == 0 {
                match stream
                    .next()
                    .await?
                    .context("HTTP open ended before publication")?
                {
                    AcpSessionFrame::Event { event } => match *event {
                        AcpSessionEvent::Ready { response } => {
                            ensure!(response.session_id.to_string() == "remote-one");
                            ready += 1;
                        }
                        other => anyhow::bail!("unexpected publication event: {other:?}"),
                    },
                    AcpSessionFrame::Settled { result } => {
                        result?;
                        settled += 1;
                    }
                    other => anyhow::bail!("unexpected publication frame: {other:?}"),
                }
            }
            ensure!(ready == 1 && settled == 1);
            // A second Settled/Ready, if already queued, must not be silently ignored.
            ensure!(
                timeout(Duration::from_millis(100), stream.next())
                    .await
                    .is_err()
            );
            Ok(())
        }

        async fn marker(fixture: &Fixture, name: &str) -> Result<()> {
            timeout(Duration::from_secs(10), async {
                while !fixture.home.path().join(name).exists() {
                    sleep(Duration::from_millis(10)).await;
                }
            })
            .await?;
            Ok(())
        }

        async fn closed(server: &Server, target: &AcpSessionTarget) -> Result<AcpBusinessClose> {
            let close: AcpBusinessClose = server.json("close", target).await?;
            ensure!(
                close.local_complete && !close.sdk_finished && !close.cleanup_timed_out,
                "{close:?}"
            );
            ensure!(
                close.owner_failures.is_empty()
                    && close.worker_error.is_none()
                    && close.driver_error.is_none(),
                "{close:?}"
            );
            ensure!(
                close.unfinished_prompt.is_none() && !close.unfinished_controls,
                "{close:?}"
            );
            Ok(close)
        }

        #[tokio::test]
        async fn real_peer_http_load_resident_disconnect_prompt_and_owner_close() -> Result<()> {
            let fixture = Fixture::new("load-hold").await?;
            let server = Server::start(&fixture).await?;
            let outcome = AssertUnwindSafe(timeout(Duration::from_secs(45), async {
                let stream_capacity = server.state.streams.available_permits();
                let mut stream = Sse::new(server.post("open", &request(&fixture, None)).await?)?;
                let target = accepted(&mut stream, true).await?;
                initialized(&mut stream).await?;
                marker(&fixture, "opening").await?;
                let Some(AcpSessionFrame::Event { event }) = stream.next().await? else {
                    anyhow::bail!("missing pre-release original update");
                };
                let AcpSessionEvent::Update { update } = *event else {
                    anyhow::bail!("Ready/Settled overtook held Load result");
                };
                ensure!(update.session_id.to_string() == "remote-one");
                ensure!(
                    serde_json::to_value(update)?["update"]["content"]["text"]
                        == "history before ready"
                );
                ensure!(
                    timeout(Duration::from_millis(100), stream.next())
                        .await
                        .is_err()
                );
                std::fs::write(fixture.home.path().join("release"), "")?;
                published(&mut stream).await?;
                let snapshot: AcpBusinessSnapshot = server.json("snapshot", &target).await?;
                ensure!(snapshot.ready && snapshot.target == target);
                ensure!(snapshot.acp_session_id.as_deref() == Some("remote-one"));

                let calls_before = std::fs::read_to_string(fixture.home.path().join("calls"))?;
                let mut resident = Sse::new(
                    server
                        .post("open", &request(&fixture, Some(target.thread_id.clone())))
                        .await?,
                )?;
                ensure!(accepted(&mut resident, false).await? == target);
                let Some(AcpSessionFrame::Settled { result }) = resident.next().await? else {
                    anyhow::bail!("resident must settle without replay or Ready");
                };
                result?;
                ensure!(resident.next().await?.is_none());
                drop(resident);
                ensure!(
                    std::fs::read_to_string(fixture.home.path().join("calls"))? == calls_before
                );

                std::fs::remove_file(fixture.home.path().join("release"))?;
                std::fs::write(fixture.home.path().join("mode"), "prompt-hold")?;
                let run: AcpRunId = server
                    .json(
                        "prompt",
                        &AcpPromptRequest {
                            target: target.clone(),
                            content: vec![acp_schema::ContentBlock::Text(
                                acp_schema::TextContent::new("actual HTTP run"),
                            )],
                        },
                    )
                    .await?;
                marker(&fixture, "prompting").await?;
                let active: AcpBusinessSnapshot = server.json("snapshot", &target).await?;
                ensure!(active.active_run == Some(run));
                drop(stream); // Drop the actual response/socket while the real prompt is held.
                // Wait for the server to drop the original SSE state/permit before release;
                // client-side drop alone would race server disconnect handling.
                while server.state.streams.available_permits() != stream_capacity {
                    sleep(Duration::from_millis(10)).await;
                }
                let after_drop = fixture.runtime.acp_session_snapshot(target.clone()).await?;
                ensure!(
                    after_drop.ready && !after_drop.closing && after_drop.active_run == Some(run)
                );
                std::fs::write(fixture.home.path().join("release"), "")?;
                let completed = loop {
                    let snapshot: AcpBusinessSnapshot = server.json("snapshot", &target).await?;
                    if let Some(completed) = snapshot.last_completed {
                        break completed;
                    }
                    sleep(Duration::from_millis(10)).await;
                };
                ensure!(completed.run == run && completed.result.is_ok());
                ensure!(completed.summary == "actual answer");
                let close = closed(&server, &target).await?;
                ensure!(close.last_completed.as_ref().map(|done| done.run) == Some(run));
                // Closing a member retains the shared account process; finish verifies its final exit.
                ensure!(PathBuf::from(format!("/proc/{}", fixture.pid("pid")?)).exists());

                // Reopen the real product member to distinguish stale qualification from Closed.
                let mut reopened = Sse::new(
                    server
                        .post("open", &request(&fixture, Some(target.thread_id.clone())))
                        .await?,
                )?;
                let current = accepted(&mut reopened, true).await?;
                initialized(&mut reopened).await?;
                published(&mut reopened).await?;
                ensure!(current.agent_id == target.agent_id && current.instance != target.instance);
                for (method, body) in [
                    ("snapshot", serde_json::to_value(&target)?),
                    (
                        "interrupt",
                        serde_json::to_value(AcpInterruptRequest {
                            target: current.clone(),
                            run,
                        })?,
                    ),
                    (
                        "permission",
                        serde_json::to_value(AcpPermissionAnswerRequest {
                            target: current.clone(),
                            permission_id: AcpPermissionId {
                                instance: run.instance,
                                sequence: run.sequence,
                            },
                            option_id: None,
                        })?,
                    ),
                ] {
                    let response = server.post(method, &body).await?;
                    ensure!(response.status() == reqwest::StatusCode::CONFLICT);
                    ensure!(
                        response.json::<AcpBusinessFailure>().await?.kind
                            == AcpBusinessFailureKind::Stale
                    );
                }
                drop(reopened);
                closed(&server, &current).await?;
                let methods = std::fs::read_to_string(fixture.home.path().join("calls"))?;
                ensure!(!methods.lines().any(|method| method == "session/cancel"));
                // A new supervised process was expected only for the explicit cold reopen.
                ensure!(
                    methods
                        .lines()
                        .filter(|method| *method == "session/load")
                        .count()
                        == 2
                );
                ensure!(!methods.lines().any(|method| method == "session/new"));
                Ok::<_, anyhow::Error>(())
            }))
            .catch_unwind()
            .await;
            server.finish(&fixture).await?;
            match outcome {
                Ok(result) => result?,
                Err(panic) => std::panic::resume_unwind(panic),
            }
        }

        #[tokio::test]
        async fn real_peer_http_gap_preserves_original_settlement() -> Result<()> {
            let fixture = Fixture::new("gap").await?;
            let body_gate = CancellationToken::new();
            let server = Server::start_with_body_gate(&fixture, Some(body_gate.clone())).await?;
            let outcome = AssertUnwindSafe(timeout(Duration::from_secs(30), async {
                let mut stream = Sse::new(server.post("open", &request(&fixture, None)).await?)?;
                let target = accepted(&mut stream, true).await?;
                loop {
                    match fixture.runtime.acp_session_snapshot(target.clone()).await {
                        Ok(snapshot) if snapshot.ready => break,
                        Ok(_) => {}
                        Err(error) if error.kind == AcpBusinessFailureKind::NotReady => {}
                        Err(error) => return Err(error.into()),
                    }
                    sleep(Duration::from_millis(10)).await;
                }
                body_gate.cancel();
                let (mut gap, mut settled) = (false, 0);
                while let Some(frame) = stream.next().await? {
                    match frame {
                        AcpSessionFrame::Event { event } => match *event {
                            AcpSessionEvent::Gap {
                                gap: AcpObservationGap::WindowExceeded,
                            } => gap = true,
                            AcpSessionEvent::Update { .. } if !gap => {}
                            other => anyhow::bail!("unexpected gap-path event: {other:?}"),
                        },
                        AcpSessionFrame::Settled { result } => {
                            result?;
                            settled += 1;
                        }
                        other => anyhow::bail!("unexpected gap-path frame: {other:?}"),
                    }
                }
                ensure!(
                    gap && settled == 1,
                    "real SDK gap and original completion required"
                );
                let snapshot: AcpBusinessSnapshot = server.json("snapshot", &target).await?;
                ensure!(snapshot.ready && snapshot.target == target);
                ensure!(matches!(
                    snapshot.observation_gap,
                    Some(AcpObservationGap::WindowExceeded)
                ));
                closed(&server, &target).await?;
                Ok::<_, anyhow::Error>(())
            }))
            .catch_unwind()
            .await;
            server.finish(&fixture).await?;
            match outcome {
                Ok(result) => result?,
                Err(panic) => std::panic::resume_unwind(panic),
            }
        }

        use crate::test_fixture_acp_transport_fixture as acp_transport_fixture;
    }
}
