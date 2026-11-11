//! Verification suite for MCP lifecycle concurrency (T08, T09) and remote MCP
//! forwarding over `pl-remote-helper` (T10, T11, T12, T13).
#![cfg(target_os = "linux")]

#[path = "support/mcp_authorization.rs"]
mod authorization_tests;
#[path = "support/binding_host.rs"]
mod binding_host;
#[path = "support/mcp_binding.rs"]
mod binding_tests;
#[path = "support/helper.rs"]
mod helper;
#[path = "support/mcp_refresh.rs"]
mod refresh_tests;
#[path = "support/mcp_stdio.rs"]
mod stdio;
#[path = "support/remote.rs"]
mod support;

use stdio::{STDIO_MCP_SCRIPT, stdio_effective_config, write_python_mcp_server};

use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

use axum::Router;
use axum::body::Body;
use axum::extract::State;
use axum::http::{HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use bytes::Bytes;
use futures::StreamExt;
use pl_protocol::remote::{
    REMOTE_PROCESS_LEASE_TTL, RemoteCapture, RemoteErrorCode, RemoteHttpHeader,
    RemoteHttpRequestHead, RemoteProcessLeaseId, RemoteRequest, RemoteResponse, RemoteSpawnRequest,
};
use pl_tool::mcp::config::{
    EffectiveMcpServerConfig, McpExecutionContext, McpServerConfig, McpServerMutationPolicy,
    McpServerSourceKind, McpServerStatusKind, McpServerTransport,
};
use pl_tool::mcp::{McpConnectRequest, McpConnector, McpRuntime};
use rmcp::transport::streamable_http_client::StreamableHttpClient;

/// T08 & T09:
/// - T08: `prepare_generation` receiving `Shutdown` cancels in-flight preparation and closes
///   already-connected sessions without leaking processes.
/// - T09: `McpRuntimeHandle::shutdown()` timing out on a slow-exiting session retains the close
///   task; a subsequent `shutdown()` joins the same close task and returns `Ok(())`.
#[tokio::test]
async fn t08_t09_prepare_generation_shutdown_and_retry_join() -> anyhow::Result<()> {
    let executable = helper::remote_helper_executable();
    let temp = tempfile::tempdir()?;
    let script = write_python_mcp_server(temp.path(), "server.py", STDIO_MCP_SCRIPT);

    // --- T08: Shutdown during prepare_generation ---
    let fast_pid_file = temp.path().join("fast.pid");
    let slow_pid_file = temp.path().join("slow.pid");
    let mut fast_env = BTreeMap::new();
    fast_env.insert(
        "MCP_PID_FILE".to_owned(),
        fast_pid_file.to_string_lossy().into_owned(),
    );
    let mut slow_env = BTreeMap::new();
    slow_env.insert(
        "MCP_PID_FILE".to_owned(),
        slow_pid_file.to_string_lossy().into_owned(),
    );
    slow_env.insert("MCP_HANG_INITIALIZE".to_owned(), "1".to_owned());

    let connector = McpConnector::default().with_stdio_worker(executable.to_path_buf());
    let runtime = McpRuntime::new(connector);
    let handle = runtime.handle();

    let mut servers = BTreeMap::new();
    servers.insert(
        "fast".to_owned(),
        stdio_effective_config(
            "fast",
            &script,
            Vec::new(),
            fast_env,
            Some(temp.path().to_string_lossy().into_owned()),
            McpExecutionContext::Host,
        ),
    );
    servers.insert(
        "slow".to_owned(),
        stdio_effective_config(
            "slow",
            &script,
            Vec::new(),
            slow_env,
            Some(temp.path().to_string_lossy().into_owned()),
            McpExecutionContext::Host,
        ),
    );

    let reconcile_handle = handle.clone();
    let reconcile_task = tokio::spawn(async move { reconcile_handle.reconcile(servers).await });

    // Wait until both processes have spawned and `fast` has completed discovery.
    let deadline = Instant::now() + Duration::from_secs(5);
    while (!fast_pid_file.exists() || !slow_pid_file.exists()) && Instant::now() < deadline {
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    tokio::time::sleep(Duration::from_millis(150)).await;
    let fast_pid: u32 = std::fs::read_to_string(&fast_pid_file)?.trim().parse()?;
    let slow_pid: u32 = std::fs::read_to_string(&slow_pid_file)?.trim().parse()?;

    handle.shutdown().await?;
    let reconcile_res = reconcile_task.await?;
    assert!(
        reconcile_res.is_err(),
        "in-flight reconcile must be rejected when shutdown is requested"
    );
    assert!(
        !std::path::Path::new(&format!("/proc/{fast_pid}")).exists(),
        "already-connected session in unpublished generation leaked PID {fast_pid}"
    );
    assert!(
        !std::path::Path::new(&format!("/proc/{slow_pid}")).exists(),
        "in-flight connecting session leaked PID {slow_pid}"
    );

    // --- T09: First shutdown() times out, second shutdown() joins in-flight close and succeeds ---
    // Hold the real remote SIGTERM handler until the first 80ms shutdown returns.
    // Once released, the handler still delays exit by the original 400ms.
    let helper_instance = support::Helper::start(executable).await?;
    let remote_commands = helper_instance
        .client
        .open_command_backend(helper_instance.root.path().to_string_lossy().into_owned())
        .await?;
    let remote_script = write_python_mcp_server(
        helper_instance.root.path(),
        "remote_slow.py",
        STDIO_MCP_SCRIPT,
    );
    let exit_marker = helper_instance.root.path().join("exited.marker");
    let term_started_marker = helper_instance.root.path().join("terminating.marker");
    let term_release_marker = helper_instance
        .root
        .path()
        .join("release-termination.marker");
    let mut delayed_env = BTreeMap::new();
    delayed_env.insert("MCP_IGNORE_TERM_MS".to_owned(), "400".to_owned());
    delayed_env.insert(
        "MCP_EXIT_MARKER".to_owned(),
        exit_marker.to_string_lossy().into_owned(),
    );
    delayed_env.insert(
        "MCP_TERM_STARTED_MARKER".to_owned(),
        term_started_marker.to_string_lossy().into_owned(),
    );
    delayed_env.insert(
        "MCP_TERM_RELEASE_MARKER".to_owned(),
        term_release_marker.to_string_lossy().into_owned(),
    );

    let short_connector = McpConnector::default()
        .with_stdio_worker(executable.to_path_buf())
        .with_close_timeout(Duration::from_millis(80));
    let retry_runtime = McpRuntime::new(short_connector);
    let retry_handle = retry_runtime.handle();

    let mut retry_servers = BTreeMap::new();
    retry_servers.insert(
        "delayed".to_owned(),
        stdio_effective_config(
            "delayed",
            &remote_script,
            Vec::new(),
            delayed_env,
            None,
            McpExecutionContext::Remote {
                commands: remote_commands,
            },
        ),
    );
    retry_handle.reconcile(retry_servers).await?;

    let first_shutdown_handle = retry_handle.clone();
    let first_shutdown_task = tokio::spawn(async move { first_shutdown_handle.shutdown().await });
    let deadline = Instant::now() + Duration::from_secs(5);
    while !term_started_marker.exists() && Instant::now() < deadline {
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    let handler_started = term_started_marker.exists();
    let first_shutdown = first_shutdown_task.await;
    // Release even if readiness, the join, or the original timeout assertion fails.
    std::fs::write(&term_release_marker, b"release")?;
    let first_shutdown = first_shutdown?;
    assert!(
        handler_started,
        "remote stdio server must enter its real SIGTERM handler"
    );
    assert!(
        first_shutdown.is_err(),
        "first shutdown with 80ms close_timeout should report timeout while process takes 400ms"
    );

    // Wait for the process to finish its 400ms SIGTERM handler and exit.
    tokio::time::sleep(Duration::from_millis(500)).await;
    retry_handle
        .shutdown()
        .await
        .expect("second shutdown must join the completed close task and return Ok(())");
    assert!(
        exit_marker.exists(),
        "remote stdio server must have completed its termination handler"
    );

    helper_instance.close().await?;
    Ok(())
}

/// T10 & T11:
/// - T10: Remote stdio MCP forwards `program`, `args` (spaces, quotes, newlines, `$VAR`, `;`),
///   `env`, and `cwd` without shell expansion and without capture files.
/// - T11: Remote process lease renewal keeps the process alive, and stopping renewal expires
///   and terminates the process after `REMOTE_PROCESS_LEASE_TTL`.
#[tokio::test]
async fn t10_t11_remote_stdio_passthrough_and_process_lease() -> anyhow::Result<()> {
    let executable = helper::remote_helper_executable();
    let helper_instance = support::Helper::start(executable).await?;
    let sub_cwd = helper_instance.root.path().join("sub dir");
    std::fs::create_dir_all(&sub_cwd)?;
    let script =
        write_python_mcp_server(helper_instance.root.path(), "mcp_echo.py", STDIO_MCP_SCRIPT);

    let remote_commands = helper_instance
        .client
        .open_command_backend(helper_instance.root.path().to_string_lossy().into_owned())
        .await?;

    let tricky_args = vec![
        "arg with spaces".to_owned(),
        "\"quoted\" 'single'".to_owned(),
        "line1\nline2".to_owned(),
        "$UNEXPANDED_VAR; echo pwned".to_owned(),
    ];
    let mut env = BTreeMap::new();
    env.insert("SPECIAL_ENV".to_owned(), "val=\"1\" & $2".to_owned());

    let connector = McpConnector::default().with_stdio_worker(executable.to_path_buf());
    let config = stdio_effective_config(
        "remote-stdio",
        &script,
        tricky_args.clone(),
        env,
        Some("sub dir".to_owned()),
        McpExecutionContext::Remote {
            commands: remote_commands,
        },
    );

    let session = connector
        .connect(McpConnectRequest {
            server_id: "remote-stdio".to_owned(),
            server: config,
        })
        .await?;
    let tools = session.list_tools().await?;
    assert_eq!(tools.len(), 1);
    assert_eq!(tools[0].name, "inspect_env");

    let call_result = session
        .call_tool("inspect_env".to_owned(), serde_json::json!({}))
        .await?;
    let text = call_result
        .content
        .first()
        .and_then(|c| c.as_text())
        .map(|t| t.text.as_str())
        .expect("text content");
    let parsed: serde_json::Value = serde_json::from_str(text)?;
    let got_argv: Vec<String> = serde_json::from_value(parsed["argv"].clone())?;
    assert_eq!(got_argv, tricky_args);
    assert_eq!(
        std::fs::canonicalize(parsed["cwd"].as_str().unwrap())?,
        std::fs::canonicalize(&sub_cwd)?
    );
    assert_eq!(parsed["special_env"].as_str(), Some("val=\"1\" & $2"));
    assert!(parsed["bash_env"].is_null());

    // Ensure no command capture files were created in workspace.
    assert!(
        !helper_instance.root.path().join(".anywork").exists(),
        "remote stdio MCP must not create capture files"
    );

    session.close().await?;

    // --- T11: Process lease renewal and expiry ---
    let lease_pid_file = helper_instance.root.path().join("leased.pid");
    let lease_id = RemoteProcessLeaseId("lease-test-1".to_owned());
    let spawn_req = RemoteSpawnRequest {
        process_id: "leased-proc".to_owned(),
        workspace_id: helper_instance.workspace.clone(),
        program: "/bin/sh".to_owned(),
        arguments: vec![
            "-c".to_owned(),
            format!("echo $$ > '{}'; sleep 120", lease_pid_file.display()),
        ],
        remove_environment: Vec::new(),
        cwd: ".".to_owned(),
        environment: BTreeMap::new(),
        capture: RemoteCapture::None,
        remaining_timeout_ms: None,
        process_lease: Some(lease_id.clone()),
    };
    let reply = helper_instance
        .client
        .request(RemoteRequest::Spawn(spawn_req), &[])
        .await?;
    assert!(matches!(
        reply.response,
        RemoteResponse::ProcessSpawned { .. }
    ));

    // Renew with wrong lease_id must fail with InvalidRequest.
    let bad_renew = helper_instance
        .client
        .request(
            RemoteRequest::RenewProcessLease {
                process_id: "leased-proc".to_owned(),
                lease_id: RemoteProcessLeaseId("wrong-lease".to_owned()),
            },
            &[],
        )
        .await;
    assert!(
        matches!(
            bad_renew,
            Err(pl_tool::remote::RemoteClientError::Remote {
                code: RemoteErrorCode::InvalidRequest,
                ..
            })
        ),
        "mismatched lease_id must be rejected: {bad_renew:?}"
    );

    // Valid renewal succeeds.
    let good_renew = helper_instance
        .client
        .request(
            RemoteRequest::RenewProcessLease {
                process_id: "leased-proc".to_owned(),
                lease_id: lease_id.clone(),
            },
            &[],
        )
        .await?;
    assert!(matches!(good_renew.response, RemoteResponse::Ack));

    // Wait for PID file, then stop renewing and wait for REMOTE_PROCESS_LEASE_TTL expiry.
    while !lease_pid_file.exists() {
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    let leased_pid: u32 = std::fs::read_to_string(&lease_pid_file)?.trim().parse()?;
    assert!(std::path::Path::new(&format!("/proc/{leased_pid}")).exists());

    let wait_reply = tokio::time::timeout(
        REMOTE_PROCESS_LEASE_TTL + Duration::from_secs(6),
        helper_instance.client.request(
            RemoteRequest::WaitProcess {
                process_id: "leased-proc".to_owned(),
            },
            &[],
        ),
    )
    .await??;
    let RemoteResponse::ProcessExited(exit) = wait_reply.response else {
        anyhow::bail!("expected ProcessExited after lease expiry");
    };
    assert_eq!(
        exit.failure.as_ref().map(|e| e.code),
        Some(RemoteErrorCode::SessionExpired),
        "expired process lease must record SessionExpired: {exit:?}"
    );
    assert!(
        !std::path::Path::new(&format!("/proc/{leased_pid}")).exists(),
        "helper must terminate the process tree when process lease expires"
    );

    helper_instance.close().await?;
    Ok(())
}

#[derive(Clone, Default)]
struct MockMcpHttpState {
    session_generation: Arc<AtomicUsize>,
    deleted_sessions: Arc<std::sync::Mutex<Vec<String>>>,
    get_stream_requests: Arc<AtomicUsize>,
    expire_next_call: Arc<std::sync::atomic::AtomicBool>,
    emit_oversized_sse: Arc<std::sync::atomic::AtomicBool>,
    list_reply: Arc<std::sync::Mutex<Option<serde_json::Value>>>,
    list_gate: Arc<std::sync::Mutex<Option<Arc<tokio::sync::Semaphore>>>>,
    list_entered: Arc<tokio::sync::Notify>,
    list_requests: Arc<AtomicUsize>,
    call_gate: Arc<std::sync::Mutex<Option<Arc<tokio::sync::Semaphore>>>>,
    call_entered: Arc<tokio::sync::Notify>,
}

async fn handle_mcp_post(
    State(state): State<MockMcpHttpState>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    let msg: serde_json::Value = serde_json::from_slice(&body).unwrap_or_default();
    let method = msg.get("method").and_then(|m| m.as_str()).unwrap_or("");
    let id = msg.get("id").cloned().unwrap_or(serde_json::Value::Null);

    if headers.get("x-test-auth").and_then(|v| v.to_str().ok()) == Some("401") {
        return (
            StatusCode::UNAUTHORIZED,
            [(
                axum::http::header::WWW_AUTHENTICATE,
                "Bearer resource_metadata=\"https://example.com/.well-known/oauth\"",
            )],
            "unauthorized",
        )
            .into_response();
    }
    if headers.get("x-test-auth").and_then(|v| v.to_str().ok()) == Some("403") {
        return (
            StatusCode::FORBIDDEN,
            [(
                axum::http::header::WWW_AUTHENTICATE,
                "Bearer error=\"insufficient_scope\", scope=\"mcp:tools\"",
            )],
            "forbidden",
        )
            .into_response();
    }

    match method {
        "server/discover" => {
            let reply = serde_json::json!({
                "jsonrpc": "2.0",
                "id": id,
                "error": { "code": -32601, "message": "method not found" }
            });
            (
                StatusCode::OK,
                [(axum::http::header::CONTENT_TYPE, "application/json")],
                serde_json::to_vec(&reply).unwrap(),
            )
                .into_response()
        }
        "initialize" => {
            let generation = state.session_generation.fetch_add(1, Ordering::SeqCst) + 1;
            let session_id = format!("session-{generation}");
            let reply = serde_json::json!({
                "jsonrpc": "2.0",
                "id": id,
                "result": {
                    "protocolVersion": "2025-11-25",
                    "capabilities": {
                        "tools": { "listChanged": true }
                    },
                    "serverInfo": { "name": "remote-http-mcp", "version": "1.0.0" }
                }
            });
            (
                StatusCode::OK,
                [
                    (axum::http::header::CONTENT_TYPE, "application/json"),
                    (
                        axum::http::HeaderName::from_static("mcp-session-id"),
                        session_id.as_str(),
                    ),
                ],
                serde_json::to_vec(&reply).unwrap(),
            )
                .into_response()
        }
        "notifications/initialized" => StatusCode::ACCEPTED.into_response(),
        "tools/list" => {
            state.list_requests.fetch_add(1, Ordering::SeqCst);
            let gate = state.list_gate.lock().unwrap().clone();
            if let Some(gate) = gate {
                state.list_entered.notify_one();
                gate.acquire().await.unwrap().forget();
            }
            let session = headers
                .get("Mcp-Session-Id")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("none");
            let mut event = serde_json::json!({
                "jsonrpc": "2.0",
                "id": id,
                "result": {
                    "tools": [{
                        "name": "http_echo",
                        "description": format!("Echo tool on {session}"),
                        "inputSchema": { "type": "object", "properties": {} }
                    }]
                }
            });
            if let Some(reply) = state.list_reply.lock().unwrap().clone() {
                event.as_object_mut().unwrap().remove("result");
                event
                    .as_object_mut()
                    .unwrap()
                    .extend(reply.as_object().unwrap().clone());
            }
            let sse_body = format!("data: {}\n\n", serde_json::to_string(&event).unwrap());
            (
                StatusCode::OK,
                [(axum::http::header::CONTENT_TYPE, "text/event-stream")],
                sse_body,
            )
                .into_response()
        }
        "tools/call" => {
            let gate = state.call_gate.lock().unwrap().clone();
            if let Some(gate) = gate {
                state.call_entered.notify_one();
                gate.acquire().await.unwrap().forget();
            }
            if state.expire_next_call.swap(false, Ordering::SeqCst) {
                return (StatusCode::NOT_FOUND, "session expired").into_response();
            }
            if state.emit_oversized_sse.load(Ordering::SeqCst) {
                let huge = "x".repeat(1024);
                let sse_body = format!("data: {huge}\n\n");
                return (
                    StatusCode::OK,
                    [(axum::http::header::CONTENT_TYPE, "text/event-stream")],
                    sse_body,
                )
                    .into_response();
            }
            let session = headers
                .get("Mcp-Session-Id")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("none")
                .to_owned();
            let custom = headers
                .get("x-custom-header")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("")
                .to_owned();
            let auth = headers
                .get(axum::http::header::AUTHORIZATION)
                .and_then(|v| v.to_str().ok())
                .unwrap_or("")
                .to_owned();
            let reply = serde_json::json!({
                "jsonrpc": "2.0",
                "id": id,
                "result": {
                    "content": [{
                        "type": "text",
                        "text": serde_json::json!({
                            "session": session,
                            "custom": custom,
                            "auth": auth,
                        }).to_string()
                    }]
                }
            });
            (
                StatusCode::OK,
                [(axum::http::header::CONTENT_TYPE, "application/json")],
                serde_json::to_vec(&reply).unwrap(),
            )
                .into_response()
        }
        _ => StatusCode::ACCEPTED.into_response(),
    }
}

async fn handle_mcp_get(State(state): State<MockMcpHttpState>) -> Response {
    state.get_stream_requests.fetch_add(1, Ordering::SeqCst);
    if state.emit_oversized_sse.load(Ordering::SeqCst) {
        let huge = "x".repeat(4096);
        let sse_body = format!("data: {huge}\n\n");
        return (
            StatusCode::OK,
            [(axum::http::header::CONTENT_TYPE, "text/event-stream")],
            sse_body,
        )
            .into_response();
    }
    let notification = serde_json::json!({
        "jsonrpc": "2.0",
        "method": "notifications/tools/list_changed"
    });
    let sse_body = format!(
        "data: {}\n\n",
        serde_json::to_string(&notification).unwrap()
    );
    (
        StatusCode::OK,
        [(axum::http::header::CONTENT_TYPE, "text/event-stream")],
        sse_body,
    )
        .into_response()
}

async fn handle_mcp_delete(State(state): State<MockMcpHttpState>, headers: HeaderMap) -> Response {
    if let Some(session) = headers.get("Mcp-Session-Id").and_then(|v| v.to_str().ok()) {
        state
            .deleted_sessions
            .lock()
            .unwrap()
            .push(session.to_owned());
    }
    StatusCode::NO_CONTENT.into_response()
}

/// T12 & T13:
/// - T12: Remote Streamable HTTP MCP full round-trip (POST JSON, POST SSE, GET SSE, DELETE session,
///   401/403 WWW-Authenticate, 404 session expiration re-init, multi-value headers, no redirect,
///   mid-body disconnect propagating h2 RST_STREAM error).
/// - T13: physical resource release to baseline and fatal oversized SSE event without retry loop.
#[tokio::test]
async fn t12_t13_remote_streamable_http_and_cleanup() -> anyhow::Result<()> {
    let executable = helper::remote_helper_executable();
    let helper_instance = support::Helper::start(executable).await?;
    let remote_commands = helper_instance
        .client
        .open_command_backend(helper_instance.root.path().to_string_lossy().into_owned())
        .await?;
    let baseline_stats = support::heartbeat(&helper_instance.client).await?;

    let state = MockMcpHttpState::default();
    let app = Router::new()
        .route(
            "/mcp",
            post(handle_mcp_post)
                .get(handle_mcp_get)
                .delete(handle_mcp_delete),
        )
        .route(
            "/multi-headers",
            get(|headers: HeaderMap| async move {
                let incoming: Vec<String> = headers
                    .get_all("x-multi")
                    .iter()
                    .filter_map(|v| v.to_str().ok().map(str::to_owned))
                    .collect();
                let mut resp = Response::new(Body::from(incoming.join(",")));
                resp.headers_mut()
                    .append("set-cookie", HeaderValue::from_static("a=1"));
                resp.headers_mut()
                    .append("set-cookie", HeaderValue::from_static("b=2"));
                resp
            }),
        )
        .route(
            "/redirect",
            get(|| async {
                (
                    StatusCode::FOUND,
                    [(axum::http::header::LOCATION, "/mcp")],
                    "redirecting",
                )
            }),
        )
        .route(
            "/mid-body-abort",
            get(|| async {
                let (tx, rx) = tokio::sync::mpsc::channel::<Result<Bytes, std::io::Error>>(4);
                let _ = tx.send(Ok(Bytes::from_static(b"partial-chunk"))).await;
                tokio::spawn(async move {
                    tokio::time::sleep(Duration::from_millis(80)).await;
                    let _ = tx
                        .send(Err(std::io::Error::new(
                            std::io::ErrorKind::ConnectionReset,
                            "upstream died mid-body",
                        )))
                        .await;
                });
                let stream = futures::stream::unfold(rx, |mut rx| async move {
                    rx.recv().await.map(|item| (item, rx))
                });
                Response::builder()
                    .status(StatusCode::OK)
                    .body(Body::from_stream(stream))
                    .unwrap()
            }),
        )
        .with_state(state.clone());

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    let addr = listener.local_addr()?;
    let server_task = tokio::spawn(async move {
        let _ = axum::serve(listener, app).await;
    });

    // 1. Multi-value request/response headers preserved, redirects not followed, mid-body abort RST_STREAM.
    let multi_resp = helper_instance
        .client
        .http_exchange(
            RemoteHttpRequestHead {
                method: "GET".to_owned(),
                url: format!("http://{addr}/multi-headers"),
                headers: vec![
                    RemoteHttpHeader {
                        name: "x-multi".to_owned(),
                        value: b"first".to_vec(),
                    },
                    RemoteHttpHeader {
                        name: "x-multi".to_owned(),
                        value: b"second".to_vec(),
                    },
                ],
                bearer_token_env_var: None,
            },
            Bytes::new(),
        )
        .await?;
    let set_cookies: Vec<&[u8]> = multi_resp
        .headers
        .iter()
        .filter(|h| h.name.eq_ignore_ascii_case("set-cookie"))
        .map(|h| h.value.as_slice())
        .collect();
    assert_eq!(set_cookies, vec![b"a=1".as_slice(), b"b=2".as_slice()]);
    let multi_body = multi_resp.collect_body(1024).await?;
    assert_eq!(&multi_body[..], b"first,second");

    let redirect_resp = helper_instance
        .client
        .http_exchange(
            RemoteHttpRequestHead {
                method: "GET".to_owned(),
                url: format!("http://{addr}/redirect"),
                headers: Vec::new(),
                bearer_token_env_var: None,
            },
            Bytes::new(),
        )
        .await?;
    assert_eq!(redirect_resp.status, StatusCode::FOUND);
    let _ = redirect_resp.collect_body(1024).await?;

    let abort_resp = helper_instance
        .client
        .http_exchange(
            RemoteHttpRequestHead {
                method: "GET".to_owned(),
                url: format!("http://{addr}/mid-body-abort"),
                headers: Vec::new(),
                bearer_token_env_var: None,
            },
            Bytes::new(),
        )
        .await?;
    let abort_collect = abort_resp.collect_body(1024).await;
    assert!(
        abort_collect.is_err(),
        "upstream mid-body failure must surface as a stream error, not clean EOF"
    );

    // 2. Full Remote Streamable HTTP MCP session via McpConnector (POST JSON, POST SSE, session re-init, DELETE).
    let mut headers = BTreeMap::new();
    headers.insert("x-custom-header".to_owned(), "custom-val".to_owned());
    let mcp_url = format!("http://{addr}/mcp");
    let config = EffectiveMcpServerConfig {
        id: "remote-http".to_owned(),
        source_kind: McpServerSourceKind::User,
        source_label: "user".to_owned(),
        source_detail: None,
        status_kind: McpServerStatusKind::Enabled,
        status_message: None,
        mutation_policy: McpServerMutationPolicy::UserEditable,
        bearer_token: Some("secret-token".to_owned()),
        tool_effect: None,
        execution_context: McpExecutionContext::Remote {
            commands: remote_commands.clone(),
        },
        config: McpServerConfig {
            transport: McpServerTransport::StreamableHttp,
            command: None,
            args: Vec::new(),
            env: BTreeMap::new(),
            cwd: None,
            url: Some(mcp_url.clone()),
            bearer_token_env_var: None,
            headers,
            enabled: true,
            required: false,
            startup_timeout_secs: Some(10),
            tool_timeout_secs: Some(10),
            enabled_tools: None,
            disabled_tools: Vec::new(),
        },
    };

    let connector = McpConnector::default().with_stdio_worker(executable.to_path_buf());
    let session = connector
        .connect(McpConnectRequest {
            server_id: "remote-http".to_owned(),
            server: config,
        })
        .await?;

    // tools/list returns text/event-stream SSE response.
    let tools = session.list_tools().await?;
    assert_eq!(tools.len(), 1);
    assert_eq!(tools[0].name, "http_echo");

    // tools/call returns application/json response.
    let call1 = session
        .call_tool("http_echo".to_owned(), serde_json::json!({}))
        .await?;
    let call1_json: serde_json::Value =
        serde_json::from_str(call1.content[0].as_text().expect("text").text.as_str())?;
    assert_eq!(call1_json["session"], "session-1");
    assert_eq!(call1_json["custom"], "custom-val");
    assert_eq!(call1_json["auth"], "Bearer secret-token");

    // Trigger 404 session expiration on next call -> rmcp transparently re-initializes session-2!
    state.expire_next_call.store(true, Ordering::SeqCst);
    let call2 = session
        .call_tool("http_echo".to_owned(), serde_json::json!({}))
        .await?;
    let call2_json: serde_json::Value =
        serde_json::from_str(call2.content[0].as_text().expect("text").text.as_str())?;
    assert_eq!(call2_json["session"], "session-2");

    session.close().await?;

    // 3. Verify 401 AuthRequired, 403 InsufficientScope, DELETE session, and T13 oversized SSE fast failure.
    let http_client = pl_tool::mcp::RemoteStreamableHttpClient::new(helper_instance.client.clone());
    let uri: Arc<str> = Arc::from(mcp_url.as_str());

    let init_msg = rmcp::model::ClientJsonRpcMessage::Request(rmcp::model::JsonRpcRequest {
        jsonrpc: rmcp::model::JsonRpcVersion2_0,
        id: rmcp::model::RequestId::Number(1),
        request: rmcp::model::ClientRequest::PingRequest(rmcp::model::PingRequest::default()),
    });

    // 401 AuthRequired
    let mut h401 = HashMap::new();
    h401.insert(
        axum::http::HeaderName::from_static("x-test-auth"),
        HeaderValue::from_static("401"),
    );
    let err401 = http_client
        .post_message(uri.clone(), init_msg.clone(), None, None, h401)
        .await;
    assert!(
        matches!(
            err401,
            Err(rmcp::transport::streamable_http_client::StreamableHttpError::AuthRequired(_))
        ),
        "expected AuthRequired on 401: {err401:?}"
    );

    // 403 InsufficientScope
    let mut h403 = HashMap::new();
    h403.insert(
        axum::http::HeaderName::from_static("x-test-auth"),
        HeaderValue::from_static("403"),
    );
    let err403 = http_client
        .post_message(uri.clone(), init_msg.clone(), None, None, h403)
        .await;
    assert!(
        matches!(
            err403,
            Err(rmcp::transport::streamable_http_client::StreamableHttpError::InsufficientScope(ref s))
                if s.required_scope.as_deref() == Some("mcp:tools")
        ),
        "expected InsufficientScope(mcp:tools) on 403: {err403:?}"
    );

    // DELETE session
    http_client
        .delete_session(
            uri.clone(),
            Arc::from("session-explicit-delete"),
            None,
            HashMap::new(),
        )
        .await?;
    assert!(
        state
            .deleted_sessions
            .lock()
            .unwrap()
            .contains(&"session-explicit-delete".to_owned())
    );

    // T13: Oversized SSE event fails immediately without reconnect loop.
    state.emit_oversized_sse.store(true, Ordering::SeqCst);
    state.get_stream_requests.store(0, Ordering::SeqCst);
    let mut sse_stream = http_client
        .get_stream_with_max_sse_event_size(
            uri.clone(),
            Some(Arc::from("session-2")),
            None,
            None,
            HashMap::new(),
            128,
        )
        .await?;
    let first_item = sse_stream.next().await;
    assert!(
        matches!(first_item, Some(Err(_))),
        "oversized SSE event must return an error"
    );
    assert!(
        sse_stream.next().await.is_none(),
        "stream must terminate after oversized SSE event"
    );
    // Subsequent get_stream on the same client must fail immediately via fatal_sse_error guard.
    let retry_attempt = http_client
        .get_stream_with_max_sse_event_size(
            uri.clone(),
            Some(Arc::from("session-2")),
            None,
            None,
            HashMap::new(),
            128,
        )
        .await;
    assert!(
        retry_attempt.is_err(),
        "fatal oversized SSE error must prevent any reconnect attempt"
    );
    assert_eq!(state.get_stream_requests.load(Ordering::SeqCst), 1);

    drop(sse_stream);
    // T13: Verify helper resources return to baseline (zero active transfers/processes, single connection).
    let stats = support::heartbeat(&helper_instance.client).await?;
    assert_eq!(stats.processes, baseline_stats.processes);
    assert_eq!(stats.transfers, baseline_stats.transfers);
    assert_eq!(stats.cursors, baseline_stats.cursors);
    assert_eq!(stats.workspaces, baseline_stats.workspaces);
    assert_eq!(
        stats.retained_operations,
        baseline_stats.retained_operations
    );
    assert_eq!(stats.active_connections, baseline_stats.active_connections);

    server_task.abort();
    helper_instance.close().await?;
    Ok(())
}
