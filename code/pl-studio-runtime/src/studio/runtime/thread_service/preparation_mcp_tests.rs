//! Gated loopback MCP protocol fixture. Tests cross the real create/input and shutdown boundaries.
use super::*;
use pl_protocol::{McpScope, ThreadMcpLifecycleKind as Lifecycle};
use std::sync::atomic::{AtomicUsize, Ordering};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_util::sync::CancellationToken;

#[derive(Clone)]
struct Gate {
    reached: CancellationToken,
    release: CancellationToken,
    handshakes: Arc<AtomicUsize>,
    disconnected: Arc<AtomicUsize>,
}

struct Server {
    url: String,
    gate: Gate,
    stop: CancellationToken,
    task: tokio::task::JoinHandle<Result<()>>,
}

impl Server {
    async fn new(failure: &'static str) -> Result<Self> {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let url = format!("http://{}/mcp", listener.local_addr()?);
        let gate = Gate {
            reached: CancellationToken::new(),
            release: CancellationToken::new(),
            handshakes: Arc::new(AtomicUsize::new(0)),
            disconnected: Arc::new(AtomicUsize::new(0)),
        };
        let stop = CancellationToken::new();
        let stopping = stop.clone();
        let controls = gate.clone();
        let task = tokio::spawn(async move {
            let mut requests = tokio::task::JoinSet::new();
            loop {
                tokio::select! {
                    () = stopping.cancelled() => break,
                    accepted = listener.accept() => {
                        let socket = accepted?.0;
                        requests.spawn(serve_request(socket, controls.clone(), failure));
                    }
                    result = requests.join_next(), if !requests.is_empty() => { result.unwrap()??; }
                }
            }
            // Do not abort handlers or release gates on shutdown. Production must physically
            // disconnect any blocked request before this fixture can finish.
            while let Some(result) = requests.join_next().await {
                result??;
            }
            Ok(())
        });
        Ok(Self {
            url,
            gate,
            stop,
            task,
        })
    }

    async fn close(self) -> Result<()> {
        self.stop.cancel();
        tokio::time::timeout(Duration::from_secs(3), self.task).await???;
        Ok(())
    }
}

async fn read_request(
    socket: &mut tokio::net::TcpStream,
) -> Result<Option<(String, serde_json::Value)>> {
    let mut bytes = Vec::new();
    let (end, length) = loop {
        let mut buffer = [0; 4096];
        let count = socket.read(&mut buffer).await?;
        if count == 0 {
            return Ok(None);
        }
        bytes.extend_from_slice(&buffer[..count]);
        anyhow::ensure!(bytes.len() <= 1024 * 1024, "fixture request too large");
        if let Some(end) = bytes.windows(4).position(|window| window == b"\r\n\r\n") {
            let header = std::str::from_utf8(&bytes[..end])?;
            let length = header
                .lines()
                .find_map(|line| {
                    let (name, value) = line.split_once(':')?;
                    name.eq_ignore_ascii_case("content-length")
                        .then(|| value.trim().parse::<usize>())
                })
                .transpose()?
                .unwrap_or(0);
            break (end + 4, length);
        }
    };
    while bytes.len() < end + length {
        let mut buffer = [0; 4096];
        let count = socket.read(&mut buffer).await?;
        anyhow::ensure!(count > 0, "fixture body ended early");
        bytes.extend_from_slice(&buffer[..count]);
    }
    let message: serde_json::Value = if length == 0 {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes[end..end + length])?
    };
    let http_method = std::str::from_utf8(&bytes[..end])?
        .split_whitespace()
        .next()
        .context("HTTP method")?
        .to_owned();
    Ok(Some((http_method, message)))
}

async fn serve_request(mut socket: tokio::net::TcpStream, gate: Gate, failure: &str) -> Result<()> {
    let Some((http_method, message)) = read_request(&mut socket).await? else {
        return Ok(());
    };
    let method = message["method"].as_str().unwrap_or("");
    eprintln!("MCP_FIXTURE method={method} failure={failure}");
    if method == "initialize" {
        gate.handshakes.fetch_add(1, Ordering::SeqCst);
        gate.reached.cancel();
        let mut byte = [0];
        tokio::select! {
            biased;
            read = socket.read(&mut byte) => {
                anyhow::ensure!(read? == 0, "unexpected pipelined fixture request");
                gate.disconnected.fetch_add(1, Ordering::SeqCst);
                return Ok(());
            }
            () = gate.release.cancelled() => {}
        }
    }
    let id = message["id"].clone();
    let body = match method {
        // Exercise the official legacy fallback; the owner behavior is protocol-independent.
        "server/discover" => serde_json::json!({"jsonrpc":"2.0","id":id,
            "error":{"code":-32601,"message":"fixture uses initialize"}}),
        "initialize" if failure == "handshake" => serde_json::json!({"jsonrpc":"2.0","id":id,
            "error":{"code":-32603,"message":"fixture handshake failure"}}),
        "initialize" => serde_json::json!({"jsonrpc":"2.0","id":id,"result":{
            "protocolVersion":"2025-11-25","capabilities":{"tools":{}},
            "serverInfo":{"name":"gated-fixture","version":"1"}}}),
        "tools/list" if failure == "list" => serde_json::json!({"jsonrpc":"2.0","id":id,
            "error":{"code":-32603,"message":"fixture list failure"}}),
        "tools/list" => serde_json::json!({"jsonrpc":"2.0","id":id,"result":{
            "tools":[{"name":"probe","description":"isolated probe",
                "inputSchema":{"type":"object","properties":{}}}]}}),
        _ => serde_json::Value::Null,
    };
    let (status, body) = if body.is_null() {
        (
            if http_method == "GET" {
                "405 Method Not Allowed"
            } else if http_method == "DELETE" {
                "200 OK"
            } else {
                "202 Accepted"
            },
            String::new(),
        )
    } else {
        ("200 OK", body.to_string())
    };
    let session = if method == "initialize" {
        "Mcp-Session-Id: fixture-session\r\n"
    } else {
        ""
    };
    let response = format!(
        "HTTP/1.1 {status}\r\n{session}Content-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    socket.write_all(response.as_bytes()).await?;
    socket.shutdown().await?;
    Ok(())
}

struct Environment {
    _temp: tempfile::TempDir,
    provider: Mutex<Option<pl_provider_fixture::FixtureServer>>,
    home: std::path::PathBuf,
    project_id: String,
    runtime: StudioRuntime,
}
impl Environment {
    async fn new(servers: &[(&str, &Server, bool, &str)]) -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _unused_endpoint = configure(&home)?;
        let provider = pl_provider_fixture::FixtureServer::start(vec![
            pl_provider_fixture::Step::prompt(
                pl_provider_fixture::Protocol::ResponsesHttp,
                "hello",
                0,
                pl_provider_fixture::Reply::Sse(pl_provider_fixture::responses_text(
                    "done",
                    "initial",
                    "standalone-model",
                )),
            )
            .optional(),
        ])
        .await?;
        let store = ConfigStore::new(ConfigPaths::from_config_dir(&home));
        let mut config = store.load()?;
        config.skills.enabled = false;
        let mut model = ModelInfo::compatible("standalone-model");
        model
            .binding
            .set_transport(pl_model::model::ModelTransportProfile::responses_http());
        config.models.accounts.insert(
            AccountId::new("standalone-fixture")?,
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible("isolated", provider.base_url()),
                vec![model],
            ),
        );
        store.save(&config)?;
        let directory = store.paths().mcp_host_dir();
        tokio::fs::create_dir_all(&directory).await?;
        for (id, server, required, extra) in servers {
            tokio::fs::write(
                directory.join(format!("{id}.toml")),
                document(id, server, *required, extra),
            )
            .await?;
        }
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir(&workspace).await?;
        let project_id = runtime.open_project(&workspace).await?.id;
        Ok(Self {
            _temp: temp,
            provider: Mutex::new(Some(provider)),
            home,
            project_id,
            runtime,
        })
    }
    async fn create(&self) -> Result<crate::StudioStartNewThreadResponse> {
        self.runtime
            .create_thread_command(
                self.project_id.clone(),
                request(pl_protocol::ThreadWorkspaceMode::Local),
                None,
            )
            .await
    }
    async fn shutdown(&self) -> Result<()> {
        let result = self.runtime.shutdown_runtime().await;
        let provider = self.provider.lock().unwrap().take();
        if let Some(provider) = provider {
            provider.finish().await?;
        }
        result?;
        Ok(())
    }
}
fn document(id: &str, server: &Server, required: bool, extra: &str) -> String {
    format!(
        "schema_version = 1\nid = \"{id}\"\nkind = \"server\"\ntransport = \"streamableHttp\"\nurl = \"{}\"\nrequired = {required}\n{extra}",
        server.url
    )
}
async fn wait_state(
    runtime: &StudioRuntime,
    id: &str,
    server: &str,
    state: Lifecycle,
) -> Result<()> {
    let mut events = runtime.agent_facility.product_events.subscribe_internal();
    eprintln!(
        "MCP_WAIT_STATE server={server} target={state:?} current={:?}",
        runtime.read_thread_mcp(id).await?.servers
    );
    loop {
        if runtime
            .read_thread_mcp(id)
            .await?
            .servers
            .iter()
            .any(|entry| entry.id == server && entry.lifecycle == state)
        {
            return Ok(());
        }
        match events.recv().await {
            Ok(_) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
            Err(error) => return Err(error.into()),
        }
    }
}
fn tool_id(server: &str) -> String {
    format!("mcp__{server}__probe")
}
async fn wait_tool(
    runtime: &StudioRuntime,
    thread: &pl_core::thread::ThreadHandle,
    id: String,
) -> Result<()> {
    let mut snapshots = thread.subscribe();
    let mut events = runtime.agent_facility.product_events.subscribe_internal();
    eprintln!(
        "MCP_TOOL_WAIT cleanup={:?} model={:?}",
        thread.snapshot().tool_cleanup,
        thread.snapshot().model_execution
    );
    loop {
        if tokio::time::timeout(
            Duration::from_secs(5),
            thread.reveal_tools(vec![id.clone()]),
        )
        .await
        .with_context(|| {
            format!(
                "actor did not answer reveal; model={:?}",
                thread.snapshot().model_execution
            )
        })?
        .is_ok()
        {
            assert!(
                thread
                    .snapshot()
                    .discovered_tools
                    .iter()
                    .any(|tool| tool.tool_id == id)
            );
            return Ok(());
        }
        let issues = runtime.recovery_issues();
        if let Some(issue) = issues
            .iter()
            .find(|issue| issue.category == crate::studio::StudioRecoveryIssueCategory::ToolCatalog)
        {
            anyhow::bail!("{}", issue.message);
        }
        tokio::select! {
            snapshot = snapshots.next() => { snapshot.context("Thread closed before MCP tool refresh")?; }
            event = events.recv() => { event?; }
        }
    }
}

#[tokio::test]
async fn optional_preparation_accepts_before_handshake_then_refreshes_and_reports_failure()
-> Result<()> {
    tokio::time::timeout(Duration::from_secs(20), async {
        let dispatch = tracing::Dispatch::new(PreparationLog::default());
        let _capture = tracing::dispatcher::set_default(&dispatch);
        let good = Server::new("").await?;
        let failed = Server::new("list").await?;
        let env = Environment::new(&[
            ("optional", &good, false, "startup_timeout_secs = 60\n"),
            ("failed", &failed, false, "startup_timeout_secs = 60\n"),
        ])
        .await?;
        let started = Instant::now();
        let response = env.create().await?;
        good.gate.reached.cancelled().await;
        failed.gate.reached.cancelled().await;
        assert!(!good.gate.release.is_cancelled());
        assert!(
            response.submission.cursor > 0,
            "input accepted while both handshakes are held"
        );
        eprintln!(
            "OPTIONAL_PREPARATION accepted_with_closed_gate=true create_ms={}",
            started.elapsed().as_millis()
        );
        let thread = env.runtime.ensure_thread_owner(&response.thread.id).await?;
        eprintln!("MCP_OPTIONAL owner acquired");
        assert!(
            thread
                .reveal_tools(vec![tool_id("optional")])
                .await
                .is_err()
        );
        eprintln!("MCP_OPTIONAL absent tool checked");
        let initial = env.runtime.read_thread_mcp(&response.thread.id).await?;
        assert!(
            initial
                .servers
                .iter()
                .all(|entry| entry.lifecycle == Lifecycle::Connecting)
        );
        good.gate.release.cancel();
        failed.gate.release.cancel();
        wait_state(
            &env.runtime,
            &response.thread.id,
            "optional",
            Lifecycle::Available,
        )
        .await?;
        wait_state(
            &env.runtime,
            &response.thread.id,
            "failed",
            Lifecycle::Unavailable,
        )
        .await?;
        wait_tool(&env.runtime, &thread, tool_id("optional")).await?;
        eprintln!("MCP_OPTIONAL catalog installed");
        assert!(
            env.runtime
                .read_thread_mcp(&response.thread.id)
                .await?
                .generation
                > initial.generation
        );
        env.shutdown().await?;
        eprintln!("MCP_OPTIONAL runtime stopped");
        good.close().await?;
        eprintln!("MCP_OPTIONAL good fixture stopped");
        failed.close().await?;
        Ok::<_, anyhow::Error>(())
    })
    .await?
}

#[tokio::test]
async fn mixed_preparation_waits_only_required_and_reuses_its_ready_connection() -> Result<()> {
    tokio::time::timeout(Duration::from_secs(20), async {
        let required = Server::new("").await?;
        let optional = Server::new("").await?;
        let env = Environment::new(&[
            ("required", &required, true, "startup_timeout_secs = 60\n"),
            ("optional", &optional, false, "startup_timeout_secs = 60\n"),
        ])
        .await?;
        let creating = env.create();
        tokio::pin!(creating);
        tokio::select! {
            () = required.gate.reached.cancelled() => {}
            result = &mut creating => panic!("required handshake was bypassed: {result:?}"),
        }
        assert!(futures::poll!(&mut creating).is_pending());
        required.gate.release.cancel();
        eprintln!("MCP_MIXED required gate released");
        let response = creating.await?;
        eprintln!("MCP_MIXED created");
        optional.gate.reached.cancelled().await;
        assert!(!optional.gate.release.is_cancelled());
        assert!(response.submission.cursor > 0);
        let thread = env.runtime.ensure_thread_owner(&response.thread.id).await?;
        // Immediate discovery checks the actual first catalog, not just the health projection.
        thread.reveal_tools(vec![tool_id("required")]).await?;
        assert!(
            thread
                .reveal_tools(vec![tool_id("optional")])
                .await
                .is_err()
        );
        optional.gate.release.cancel();
        wait_tool(&env.runtime, &thread, tool_id("optional")).await?;
        assert_eq!(required.gate.handshakes.load(Ordering::SeqCst), 1);
        env.shutdown().await?;
        required.close().await?;
        optional.close().await?;
        Ok::<_, anyhow::Error>(())
    })
    .await?
}

#[tokio::test]
async fn required_failures_compensate_and_disabled_required_does_not_start() -> Result<()> {
    tokio::time::timeout(Duration::from_secs(30), async {
        for (failure, extra) in [
            ("handshake", "startup_timeout_secs = 2\n"),
            ("list", "startup_timeout_secs = 2\n"),
            ("timeout", "startup_timeout_secs = 1\n"),
            (
                "credential",
                "bearer_token_env_var = \"ANYWORK_ISOLATED_MCP_MISSING_CREDENTIAL_6802B2ED\"\n",
            ),
            ("disabled", "enabled = false\n"),
        ] {
            let server = Server::new(failure).await?;
            if failure != "timeout" {
                server.gate.release.cancel();
            }
            let env = Environment::new(&[("required", &server, true, extra)]).await?;
            let result = env.create().await;
            eprintln!(
                "MCP_REQUIRED_CASE kind={failure} accepted={}",
                result.is_ok()
            );
            if failure == "disabled" {
                assert!(result.is_ok(), "{result:?}");
                assert_eq!(server.gate.handshakes.load(Ordering::SeqCst), 0);
            } else {
                let error = result.expect_err("enabled required failure must reject creation");
                assert!(
                    format!("{error:#}").contains("required MCP server"),
                    "{error:#}"
                );
                assert!(
                    env.runtime
                        .store
                        .list_threads_for_project(&env.project_id)
                        .await?
                        .iter()
                        .all(|thread| thread.visibility != crate::studio::ThreadVisibility::Active)
                );
                assert!(env.runtime.sessions.observed_threads().is_empty());
            }
            env.shutdown().await?;
            server.close().await?;
        }
        Ok::<_, anyhow::Error>(())
    })
    .await?
}

#[tokio::test]
async fn invalid_reconnect_preserves_pending_optional_preparation() -> Result<()> {
    tokio::time::timeout(Duration::from_secs(20), async {
        for failure in ["", "list"] {
            let server = Server::new(failure).await?;
            let env =
                Environment::new(&[("optional", &server, false, "startup_timeout_secs = 60\n")])
                    .await?;
            let response = env.create().await?;
            server.gate.reached.cancelled().await;
            let thread = env.runtime.ensure_thread_owner(&response.thread.id).await?;
            // The actor's initial directory is installed and answers discovery while the
            // optional handshake remains held. A rejected command must not fence that owner.
            thread.reveal_tools(vec!["discover_tools".into()]).await?;
            let before = env.runtime.read_thread_mcp(&response.thread.id).await?;
            assert_eq!(before.servers[0].lifecycle, Lifecycle::Connecting);

            let rejected = tokio::time::timeout(
                Duration::from_secs(2),
                env.runtime
                    .reconnect_thread_mcp(pl_protocol::ReconnectThreadMcpRequest {
                        thread_id: response.thread.id.clone(),
                        server_id: Some("missing".into()),
                    }),
            )
            .await
            .context("invalid reconnect waited for the unrelated optional handshake")?
            .expect_err("a missing reconnect target must be rejected");
            let public = rejected
                .downcast_ref::<pl_protocol::studio::StudioError>()
                .context("invalid reconnect must preserve its public error classification")?;
            assert_eq!(
                public.code,
                pl_protocol::studio::StudioErrorCode::InvalidArgument
            );
            assert!(rejected.to_string().contains("not enabled"), "{rejected:#}");
            assert!(!server.gate.release.is_cancelled());
            assert_eq!(
                env.runtime.read_thread_mcp(&response.thread.id).await?,
                before,
                "rejection must not mutate the existing preparation projection"
            );

            server.gate.release.cancel();
            let expected = if failure.is_empty() {
                Lifecycle::Available
            } else {
                Lifecycle::Unavailable
            };
            wait_state(&env.runtime, &response.thread.id, "optional", expected).await?;
            if failure.is_empty() {
                wait_tool(&env.runtime, &thread, tool_id("optional")).await?;
            }
            assert_eq!(server.gate.handshakes.load(Ordering::SeqCst), 1);
            env.shutdown().await?;
            server.close().await?;
        }
        Ok::<_, anyhow::Error>(())
    })
    .await?
}

#[tokio::test]
async fn pending_preparation_is_joined_on_configuration_reconnect_and_shutdown() -> Result<()> {
    tokio::time::timeout(Duration::from_secs(30), async {
        for action in [
            "configuration",
            "reconnect",
            "changed-failed-reconnect",
            "shutdown",
        ] {
            let server = Server::new("").await?;
            let replacement = if action == "changed-failed-reconnect" {
                let server = Server::new("list").await?;
                server.gate.release.cancel();
                Some(server)
            } else {
                None
            };
            let env =
                Environment::new(&[("optional", &server, false, "startup_timeout_secs = 60\n")])
                    .await?;
            let response = env.create().await?;
            server.gate.reached.cancelled().await;
            if action == "shutdown" {
                env.shutdown().await?;
                assert!(server.gate.disconnected.load(Ordering::SeqCst) > 0);
            } else if action.ends_with("reconnect") {
                if let Some(replacement) = &replacement {
                    let directory = ConfigPaths::from_config_dir(&env.home).mcp_host_dir();
                    tokio::fs::write(
                        directory.join("optional.toml"),
                        document("optional", replacement, false, ""),
                    )
                    .await?;
                    // Freeze the legitimate interval between catalog commit and per-owner
                    // reconciliation. Explicit reconnect must not present the old endpoint's
                    // ready lease as readiness of this newly committed, failing endpoint.
                    env.runtime
                        .config_runtime
                        .reload_mcp_catalog(&McpScope::Host)?;
                }
                let reconnecting =
                    env.runtime
                        .reconnect_thread_mcp(pl_protocol::ReconnectThreadMcpRequest {
                            thread_id: response.thread.id.clone(),
                            server_id: None,
                        });
                tokio::pin!(reconnecting);
                assert!(futures::poll!(&mut reconnecting).is_pending());
                server.gate.release.cancel();
                let result = reconnecting.await;
                if let Some(replacement) = &replacement {
                    assert!(result.is_err());
                    let state = env.runtime.read_thread_mcp(&response.thread.id).await?;
                    assert_eq!(state.servers[0].endpoint_summary, replacement.url);
                    assert_eq!(state.servers[0].lifecycle, Lifecycle::Unavailable);
                } else {
                    assert_eq!(result?.servers[0].lifecycle, Lifecycle::Available);
                    assert_eq!(server.gate.handshakes.load(Ordering::SeqCst), 2);
                }
                env.shutdown().await?;
            } else {
                let directory = ConfigPaths::from_config_dir(&env.home).mcp_host_dir();
                tokio::fs::write(
                    directory.join("optional.toml"),
                    document("optional", &server, false, "enabled = false\n"),
                )
                .await?;
                env.runtime.reload_mcp_catalog(&McpScope::Host).await?;
                server.gate.release.cancel();
                assert_eq!(server.gate.handshakes.load(Ordering::SeqCst), 1);
                let state = env.runtime.read_thread_mcp(&response.thread.id).await?;
                assert!(
                    state
                        .servers
                        .iter()
                        .all(|entry| entry.lifecycle != Lifecycle::Available)
                );
                env.shutdown().await?;
                let closed = env.runtime.read_thread_mcp(&response.thread.id).await?;
                assert!(
                    closed.servers.is_empty(),
                    "no late producer publication after close"
                );
            }
            server.close().await?;
            if let Some(replacement) = replacement {
                replacement.close().await?;
            }
        }
        Ok::<_, anyhow::Error>(())
    })
    .await?
}
