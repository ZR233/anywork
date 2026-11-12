//! Real Streamable HTTP peers exercising the serial runtime discovery path.
use super::*;
use pl_tool::mcp::{McpResetScope, McpRuntimeHandle, McpToolRefreshStatus};
use pl_tool_mcp::support::FrozenMcpLease;
use serde_json::{Value, json};

struct RefreshPeer {
    state: MockMcpHttpState,
    config: EffectiveMcpServerConfig,
    notifications: tokio::sync::broadcast::Sender<()>,
    task: tokio::task::JoinHandle<()>,
}

impl RefreshPeer {
    async fn start() -> anyhow::Result<Self> {
        let state = MockMcpHttpState::default();
        let (notifications, _) = tokio::sync::broadcast::channel::<()>(16);
        let sender = notifications.clone();
        let app = Router::new()
            .route(
                "/mcp",
                post(handle_mcp_post)
                    .get(move || {
                        let receiver = sender.subscribe();
                        async move {
                            let stream = futures::stream::unfold(receiver, |mut receiver| async {
                                receiver.recv().await.ok()?;
                                Some((
                                    Ok::<_, std::convert::Infallible>(Bytes::from_static(
                                        b"data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/tools/list_changed\"}\n\n",
                                    )),
                                    receiver,
                                ))
                            });
                            (
                                [(axum::http::header::CONTENT_TYPE, "text/event-stream")],
                                Body::from_stream(stream),
                            )
                        }
                    })
                    .delete(handle_mcp_delete),
            )
            .with_state(state.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let addr = listener.local_addr()?;
        let task = tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        let config = EffectiveMcpServerConfig {
            id: "peer".into(),
            source_kind: McpServerSourceKind::User,
            source_label: "user".into(),
            source_detail: None,
            status_kind: McpServerStatusKind::Enabled,
            status_message: None,
            mutation_policy: McpServerMutationPolicy::UserEditable,
            bearer_token: Some("refresh-secret-token".into()),
            tool_effect: None,
            execution_context: McpExecutionContext::Host,
            config: McpServerConfig {
                transport: McpServerTransport::StreamableHttp,
                startup_mode: Default::default(),
                command: None,
                args: Vec::new(),
                env: BTreeMap::new(),
                cwd: None,
                url: Some(format!("http://{addr}/mcp")),
                bearer_token_env_var: None,
                headers: BTreeMap::new(),
                enabled: true,
                required: false,
                startup_timeout_secs: Some(5),
                tool_timeout_secs: Some(5),
                enabled_tools: None,
                disabled_tools: vec!["hidden".into()],
            },
        };
        Ok(Self {
            state,
            config,
            notifications,
            task,
        })
    }

    fn tools(&self, tools: Value) {
        // RMCP 3.9's ListToolsResult uses SEP-2549 camelCase fields. A fresh
        // minute-long cache must never satisfy an explicit runtime refresh.
        *self.state.list_reply.lock().unwrap() = Some(json!({
            "result": {
                "resultType": "complete",
                "tools": tools,
                "ttlMs": 60_000,
                "cacheScope": "private"
            }
        }));
    }

    fn servers(&self) -> BTreeMap<String, EffectiveMcpServerConfig> {
        BTreeMap::from([("peer".into(), self.config.clone())])
    }

    fn gate(&self) -> Arc<tokio::sync::Semaphore> {
        let gate = Arc::new(tokio::sync::Semaphore::new(0));
        *self.state.list_gate.lock().unwrap() = Some(gate.clone());
        gate
    }

    async fn entered(&self) -> anyhow::Result<()> {
        tokio::time::timeout(Duration::from_secs(5), self.state.list_entered.notified()).await?;
        Ok(())
    }
}

impl Drop for RefreshPeer {
    fn drop(&mut self) {
        self.task.abort();
    }
}

fn tool(name: &str) -> Value {
    json!({"name": name, "description": "original", "inputSchema": {"type": "object", "properties": {}}})
}

async fn refresh(handle: &McpRuntimeHandle) -> anyhow::Result<pl_tool::mcp::McpToolRefreshReport> {
    Ok(tokio::time::timeout(Duration::from_secs(10), handle.refresh_tools()).await??)
}

#[tokio::test]
async fn request_errors_and_sdk_timeout_preserve_the_session_without_replay() -> anyhow::Result<()>
{
    let mut peer = RefreshPeer::start().await?;
    peer.config.config.tool_timeout_secs = Some(1);
    let runtime = McpRuntime::new(McpConnector::default());
    let handle = runtime.handle();
    handle.reconcile(peer.servers()).await?;
    let lease = handle.acquire_turn_lease().await?;
    let call = || FrozenMcpLease::call_tool(&lease, "peer".into(), "echo".into(), json!({}));

    *peer.state.call_reply.lock().unwrap() = Some(json!({
        "error": {"code": -32602, "message": "invalid refresh-secret-token"}
    }));
    let error = call().await.unwrap_err().to_string();
    assert!(!error.contains("refresh-secret-token"));
    assert!(error.contains("invalid"));
    *peer.state.call_reply.lock().unwrap() = None;
    call().await?;

    *peer.state.call_reply.lock().unwrap() = Some(json!({
        "result": {"content": [{"type": "text", "text": "business error"}], "isError": true}
    }));
    assert_eq!(call().await?.is_error, Some(true));
    *peer.state.call_reply.lock().unwrap() = None;
    call().await?;

    let gate = Arc::new(tokio::sync::Semaphore::new(0));
    *peer.state.call_gate.lock().unwrap() = Some(gate.clone());
    let error = call().await.unwrap_err().to_string();
    assert!(error.contains("timeout"), "{error}");
    gate.add_permits(1);
    *peer.state.call_gate.lock().unwrap() = None;
    tokio::time::timeout(Duration::from_secs(5), peer.state.cancelled.notified()).await?;
    call().await?;

    assert_eq!(peer.state.call_requests.load(Ordering::SeqCst), 6);
    assert_eq!(peer.state.cancel_requests.load(Ordering::SeqCst), 1);
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 1);
    assert_eq!(
        handle.acquire_turn_lease().await?.generation(),
        lease.generation()
    );
    assert_eq!(handle.available_server_names().await, vec!["peer"]);
    handle.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn retiring_one_session_does_not_stall_sibling_deadlines_or_admission() -> anyhow::Result<()>
{
    let mut first = RefreshPeer::start().await?;
    first.config.id = "a".into();
    let mut sibling = RefreshPeer::start().await?;
    sibling.config.id = "b".into();
    sibling.config.config.tool_timeout_secs = Some(1);
    let servers = BTreeMap::from([
        ("a".into(), first.config.clone()),
        ("b".into(), sibling.config.clone()),
    ]);
    let handle = McpRuntime::new(McpConnector::default()).handle();
    handle.reconcile(servers.clone()).await?;
    let old = handle.acquire_turn_lease().await?;
    handle
        .reset(
            McpResetScope::Server {
                server_id: "a".into(),
            },
            servers,
        )
        .await?;
    let current = handle.acquire_turn_lease().await?;
    let close_gate = Arc::new(tokio::sync::Semaphore::new(0));
    *first.state.delete_gate.lock().unwrap() = Some(close_gate.clone());
    let call_gate = Arc::new(tokio::sync::Semaphore::new(0));
    *sibling.state.call_gate.lock().unwrap() = Some(call_gate.clone());
    let mut call = Box::pin(FrozenMcpLease::call_tool(
        &current,
        "b".into(),
        "echo".into(),
        json!({}),
    ));
    let started = Instant::now();
    assert!(futures::poll!(call.as_mut()).is_pending());
    tokio::time::timeout(
        Duration::from_secs(3),
        sibling.state.call_entered.notified(),
    )
    .await?;
    *sibling.state.call_gate.lock().unwrap() = None;
    drop(old);
    tokio::time::timeout(
        Duration::from_secs(3),
        first.state.delete_entered.notified(),
    )
    .await?;
    let timed_out = tokio::time::timeout(Duration::from_millis(1500), call).await;
    let elapsed = started.elapsed();
    // Admission and the next response must also progress while A's close is still pending.
    let next = tokio::time::timeout(
        Duration::from_millis(500),
        FrozenMcpLease::call_tool(&current, "b".into(), "echo".into(), json!({})),
    )
    .await;
    let completed_while_blocked = first.state.delete_completed.load(Ordering::SeqCst);
    *first.state.delete_gate.lock().unwrap() = None;
    close_gate.add_permits(1);
    call_gate.add_permits(1);
    handle.shutdown().await?;

    let error = timed_out
        .expect("retirement must continue polling sibling requests")
        .expect_err("the original B request must time out")
        .to_string();
    assert!(error.contains("timeout"), "{error}");
    assert!(elapsed < Duration::from_millis(1500), "{elapsed:?}");
    next.expect("retirement must not block sibling admission")?;
    assert_eq!(completed_while_blocked, 0);
    assert_eq!(first.state.delete_completed.load(Ordering::SeqCst), 2);
    assert_eq!(sibling.state.call_requests.load(Ordering::SeqCst), 2);
    assert_eq!(sibling.state.session_generation.load(Ordering::SeqCst), 1);
    Ok(())
}

#[tokio::test]
async fn blocked_cancel_confirmation_cannot_extend_request_deadline_or_kill_the_session()
-> anyhow::Result<()> {
    let mut peer = RefreshPeer::start().await?;
    peer.config.config.tool_timeout_secs = Some(1);
    let mut servers = peer.servers();
    let mut sibling = peer.config.clone();
    sibling.id = "sibling".into();
    servers.insert("sibling".into(), sibling);
    let handle = McpRuntime::new(McpConnector::default()).handle();
    handle.reconcile(servers).await?;
    let lease = handle.acquire_turn_lease().await?;
    let call_gate = Arc::new(tokio::sync::Semaphore::new(0));
    let cancel_gate = Arc::new(tokio::sync::Semaphore::new(0));
    *peer.state.call_gate.lock().unwrap() = Some(call_gate.clone());
    *peer.state.cancel_gate.lock().unwrap() = Some(cancel_gate.clone());
    let started = Instant::now();
    let mut call = Box::pin(FrozenMcpLease::call_tool(
        &lease,
        "peer".into(),
        "echo".into(),
        json!({}),
    ));
    assert!(futures::poll!(call.as_mut()).is_pending());
    tokio::time::timeout(Duration::from_secs(5), peer.state.call_entered.notified()).await?;
    // Only the already accepted original call keeps this gate.
    *peer.state.call_gate.lock().unwrap() = None;
    let result = tokio::time::timeout(Duration::from_secs(2), call).await;
    let elapsed = started.elapsed();
    let cancellation =
        tokio::time::timeout(Duration::from_secs(2), peer.state.cancelled.notified()).await;
    let completed_while_blocked = peer.state.cancel_completed.load(Ordering::SeqCst);
    let available = handle.available_server_names().await;
    let sibling_result =
        FrozenMcpLease::call_tool(&lease, "sibling".into(), "echo".into(), json!({})).await;

    // Release both SDK-owned exchanges even when the assertions below expose a regression.
    *peer.state.cancel_gate.lock().unwrap() = None;
    call_gate.add_permits(1);
    cancel_gate.add_permits(1);
    let next_result =
        FrozenMcpLease::call_tool(&lease, "peer".into(), "echo".into(), json!({})).await;
    handle.shutdown().await?;

    let error = result
        .expect("SDK cancellation confirmation must not extend the request deadline")
        .expect_err("the blocked original request must time out")
        .to_string();
    assert!(error.contains("timeout"), "{error}");
    assert!(elapsed < Duration::from_millis(1500), "{elapsed:?}");
    cancellation?;
    assert_eq!(
        completed_while_blocked, 0,
        "cancellation was attempted, not acknowledged"
    );
    assert_eq!(available, vec!["peer", "sibling"]);
    sibling_result?;
    next_result?;
    assert_eq!(peer.state.call_requests.load(Ordering::SeqCst), 3);
    assert_eq!(peer.state.cancel_requests.load(Ordering::SeqCst), 1);
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 2);
    Ok(())
}

#[tokio::test]
async fn discovery_transport_failure_withdraws_tools_until_explicit_reset() -> anyhow::Result<()> {
    let peer = RefreshPeer::start().await?;
    let handle = McpRuntime::new(McpConnector::default()).handle();
    handle.reconcile(peer.servers()).await?;
    let old = handle.acquire_turn_lease().await?;
    peer.state.expire_next_list.store(true, Ordering::SeqCst);
    assert_eq!(
        refresh(&handle).await?.servers[0].status,
        McpToolRefreshStatus::Failed
    );
    assert!(handle.available_server_names().await.is_empty());
    assert!(
        FrozenMcpLease::call_tool(&old, "peer".into(), "echo".into(), json!({}))
            .await
            .is_err()
    );
    handle.reconcile(peer.servers()).await?;
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 1);
    handle.reset(McpResetScope::All, peer.servers()).await?;
    let next = handle.acquire_turn_lease().await?;
    FrozenMcpLease::call_tool(&next, "peer".into(), "echo".into(), json!({})).await?;
    assert_eq!(peer.state.call_requests.load(Ordering::SeqCst), 1);
    assert_eq!(peer.state.list_requests.load(Ordering::SeqCst), 3);
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 2);
    handle.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn failed_reset_seals_old_target_leases_but_preserves_accepted_calls_and_siblings()
-> anyhow::Result<()> {
    let peer = RefreshPeer::start().await?;
    let mut servers = peer.servers();
    let mut sibling = peer.config.clone();
    sibling.id = "sibling".into();
    servers.insert("sibling".into(), sibling);
    let handle = McpRuntime::new(McpConnector::default()).handle();
    handle.reconcile(servers.clone()).await?;
    let old = handle.acquire_turn_lease().await?;
    let gate = Arc::new(tokio::sync::Semaphore::new(0));
    *peer.state.call_gate.lock().unwrap() = Some(gate.clone());
    let mut accepted = Box::pin(FrozenMcpLease::call_tool(
        &old,
        "peer".into(),
        "echo".into(),
        json!({}),
    ));
    assert!(futures::poll!(accepted.as_mut()).is_pending());
    tokio::time::timeout(Duration::from_secs(5), peer.state.call_entered.notified()).await?;
    *peer.state.call_gate.lock().unwrap() = None;
    *peer.state.list_reply.lock().unwrap() = Some(json!({
        "error": {"code": -32603, "message": "reset discovery failed"}
    }));
    assert!(
        handle
            .reset(
                McpResetScope::Server {
                    server_id: "peer".into()
                },
                servers
            )
            .await
            .is_err()
    );
    let next = handle.acquire_turn_lease().await?;
    assert_eq!(handle.available_server_names().await, vec!["sibling"]);
    for lease in [&old, &next] {
        assert!(
            FrozenMcpLease::call_tool(lease, "peer".into(), "echo".into(), json!({}))
                .await
                .is_err()
        );
        FrozenMcpLease::call_tool(lease, "sibling".into(), "echo".into(), json!({})).await?;
    }
    gate.add_permits(1);
    let result = accepted.await?;
    assert!(
        result.content[0]
            .as_text()
            .unwrap()
            .text
            .contains("session-")
    );
    assert_eq!(
        peer.state.call_requests.load(Ordering::SeqCst),
        3,
        "the accepted call runs once; rejected old-target calls never reach the server"
    );
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 3);
    handle.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn idle_stdio_exit_is_published_and_explicit_reset_recovers() -> anyhow::Result<()> {
    let temp = tempfile::tempdir()?;
    let script = write_python_mcp_server(temp.path(), "server.py", STDIO_MCP_SCRIPT);
    let pid_file = temp.path().join("server.pid");
    let config = stdio_effective_config(
        "stdio",
        &script,
        Vec::new(),
        BTreeMap::from([(
            "MCP_PID_FILE".into(),
            pid_file.to_string_lossy().into_owned(),
        )]),
        Some(temp.path().to_string_lossy().into_owned()),
        McpExecutionContext::Host,
    );
    let runtime = McpRuntime::new(
        McpConnector::default().with_stdio_worker(helper::remote_helper_executable().to_path_buf()),
    );
    let handle = runtime.handle();
    let servers = BTreeMap::from([("stdio".into(), config)]);
    handle.reconcile(servers.clone()).await?;
    let old = handle.acquire_turn_lease().await?;
    let pid: i32 = std::fs::read_to_string(&pid_file)?.parse()?;
    let mut updates = handle.subscribe();
    // This test owns the process and terminates it while no request is active.
    // SAFETY: kill takes only integer arguments; pid is the positive PID written by
    // this test's still-owned child, and SIGTERM is a valid signal.
    assert!(pid > 0);
    assert_eq!(unsafe { libc::kill(pid, libc::SIGTERM) }, 0);
    tokio::time::timeout(Duration::from_secs(5), updates.recv()).await??;
    assert!(handle.available_server_names().await.is_empty());
    assert!(handle.acquire_turn_lease().await?.tools().is_empty());
    assert!(
        FrozenMcpLease::call_tool(&old, "stdio".into(), "inspect_env".into(), json!({}))
            .await
            .is_err()
    );
    // An unchanged configuration is not an implicit retry path.
    handle.reconcile(servers.clone()).await?;
    assert!(handle.available_server_names().await.is_empty());
    handle
        .reset(
            McpResetScope::Server {
                server_id: "stdio".into(),
            },
            servers,
        )
        .await?;
    let next = handle.acquire_turn_lease().await?;
    assert_ne!(std::fs::read_to_string(&pid_file)?.parse::<i32>()?, pid);
    FrozenMcpLease::call_tool(&next, "stdio".into(), "inspect_env".into(), json!({})).await?;
    handle.shutdown().await?;
    handle.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn old_stdio_notifications_and_failure_cannot_invalidate_a_reset_session()
-> anyhow::Result<()> {
    let temp = tempfile::tempdir()?;
    let script = write_python_mcp_server(temp.path(), "server.py", STDIO_MCP_SCRIPT);
    let release = temp.path().join("release");
    let log = temp.path().join("requests.jsonl");
    let config = stdio_effective_config(
        "stdio",
        &script,
        Vec::new(),
        BTreeMap::from([
            ("MCP_REQUEST_LOG".into(), log.to_string_lossy().into_owned()),
            (
                "MCP_LATE_DISCONNECT_RELEASE".into(),
                release.to_string_lossy().into_owned(),
            ),
        ]),
        Some(temp.path().to_string_lossy().into_owned()),
        McpExecutionContext::Host,
    );
    let runtime = McpRuntime::new(
        McpConnector::default().with_stdio_worker(helper::remote_helper_executable().to_path_buf()),
    );
    let handle = runtime.handle();
    let servers = BTreeMap::from([("stdio".into(), config)]);
    handle.reconcile(servers.clone()).await?;
    let old = handle.acquire_turn_lease().await?;
    // Admit the old request before reset, then keep its result pending across replacement.
    let mut accepted = Box::pin(FrozenMcpLease::call_tool(
        &old,
        "stdio".into(),
        "inspect_env".into(),
        json!({"mode": "late_disconnect"}),
    ));
    assert!(futures::poll!(accepted.as_mut()).is_pending());
    assert_eq!(handle.available_server_names().await, vec!["stdio"]);
    handle.reset(McpResetScope::All, servers).await?;
    let next = handle.acquire_turn_lease().await?;
    assert_ne!(old.generation(), next.generation());
    std::fs::write(&release, b"ready")?;
    assert!(accepted.await.is_err());
    FrozenMcpLease::call_tool(&next, "stdio".into(), "inspect_env".into(), json!({})).await?;
    // An explicit discovery is a serial barrier after the old failure; the late notification
    // must not add a redundant tools/list on the newly installed session.
    refresh(&handle).await?;
    let records = std::fs::read_to_string(&log)?
        .lines()
        .map(serde_json::from_str::<Value>)
        .collect::<std::result::Result<Vec<_>, _>>()?;
    assert_eq!(
        records
            .iter()
            .filter(|r| r["method"] == "tools/call")
            .count(),
        2
    );
    assert_eq!(
        records
            .iter()
            .filter(|r| r["method"] == "tools/list")
            .count(),
        3
    );
    assert_eq!(handle.available_server_names().await, vec!["stdio"]);
    assert_eq!(
        handle.acquire_turn_lease().await?.generation(),
        next.generation()
    );
    handle.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn dropped_call_keeps_its_generation_and_shutdown_joins_the_original_request()
-> anyhow::Result<()> {
    let peer = RefreshPeer::start().await?;
    let runtime = McpRuntime::new(McpConnector::default());
    let handle = runtime.handle();
    handle.reconcile(peer.servers()).await?;
    let lease = handle.acquire_turn_lease().await?;
    let gate = Arc::new(tokio::sync::Semaphore::new(0));
    *peer.state.call_gate.lock().unwrap() = Some(gate.clone());
    let caller = tokio::spawn(async move {
        FrozenMcpLease::call_tool(&lease, "peer".into(), "echo".into(), json!({})).await
    });
    tokio::time::timeout(Duration::from_secs(5), peer.state.call_entered.notified()).await?;
    caller.abort();
    assert!(caller.await.unwrap_err().is_cancelled());
    handle.reset(McpResetScope::All, peer.servers()).await?;
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 2);
    assert!(
        peer.state.deleted_sessions.lock().unwrap().is_empty(),
        "the original request, not its dropped caller, must retain the old generation"
    );

    let mut shutdown = Box::pin(handle.shutdown());
    assert!(
        tokio::time::timeout(Duration::from_millis(50), shutdown.as_mut())
            .await
            .is_err(),
        "shutdown must wait for the accepted request"
    );
    // Shutdown was admitted and must reject new calls rather than replaying the old one.
    gate.add_permits(1);
    tokio::time::timeout(Duration::from_secs(5), shutdown).await??;
    handle.shutdown().await?;
    assert_eq!(peer.state.call_requests.load(Ordering::SeqCst), 1);
    assert_eq!(peer.state.deleted_sessions.lock().unwrap().len(), 2);
    Ok(())
}

#[tokio::test]
async fn reconcile_keeps_equal_but_independently_revocable_config_guard() -> anyhow::Result<()> {
    replace_equal_config_guard(false).await
}

#[tokio::test]
async fn reset_keeps_equal_but_independently_revocable_config_guard() -> anyhow::Result<()> {
    replace_equal_config_guard(true).await
}

async fn replace_equal_config_guard(reset: bool) -> anyhow::Result<()> {
    use pl_core::tool::opaque::ToolAuthorization;
    use pl_tool_mcp::support::ResourceOperation;

    let peer = RefreshPeer::start().await?;
    peer.tools(json!([tool("echo")]));
    let handle = McpRuntime::new(McpConnector::default()).handle();
    let parent = ToolAuthorization::unique();
    let first_guard = parent.scoped(7);
    let replacement_guard = parent.scoped(7);
    assert_eq!(first_guard, replacement_guard);
    assert!(!first_guard.same_instance(&replacement_guard));
    handle
        .reconcile_authorized(peer.servers(), first_guard.clone())
        .await?;
    let first_lease = handle.acquire_turn_lease().await?;

    if reset {
        handle
            .reset_authorized(
                McpResetScope::All,
                peer.servers(),
                replacement_guard.clone(),
            )
            .await?;
    } else {
        handle
            .reconcile_authorized(peer.servers(), replacement_guard.clone())
            .await?;
    }
    let replacement_lease = handle.acquire_turn_lease().await?;
    assert!(
        !replacement_lease
            .authorization()
            .same_instance(&first_lease.authorization()),
        "independent revocation must not reuse an earlier guard's execution authority"
    );
    FrozenMcpLease::call_tool(&replacement_lease, "peer".into(), "echo".into(), json!({})).await?;
    FrozenMcpLease::resource_query(
        &replacement_lease,
        None,
        ResourceOperation::ListResources { cursor: None },
    )
    .await?;

    replacement_guard.revoke();
    assert!(first_guard.is_active());
    assert!(first_lease.authorization().is_active());
    assert!(
        !replacement_lease.authorization().is_active(),
        "the successful authorized update discarded its independently revocable guard"
    );
    assert!(
        handle
            .acquire_turn_lease()
            .await
            .unwrap_err()
            .to_string()
            .contains("authorization was revoked")
    );
    let call_error =
        FrozenMcpLease::call_tool(&replacement_lease, "peer".into(), "echo".into(), json!({}))
            .await
            .unwrap_err();
    assert!(call_error.to_string().contains("authorization was revoked"));
    let resource_error = FrozenMcpLease::resource_query(
        &replacement_lease,
        None,
        ResourceOperation::ListResources { cursor: None },
    )
    .await
    .unwrap_err();
    assert!(
        resource_error
            .to_string()
            .contains("authorization was revoked")
    );
    drop(replacement_lease);
    drop(first_lease);
    handle.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn revoked_config_blocks_discovery_publication_leases_and_new_requests() -> anyhow::Result<()>
{
    use pl_core::tool::opaque::ToolAuthorization;
    let peer = RefreshPeer::start().await?;
    peer.tools(json!([tool("echo")]));
    let handle = McpRuntime::new(McpConnector::default()).handle();
    let authority = ToolAuthorization::unique();
    handle
        .reconcile_authorized(peer.servers(), authority.clone())
        .await?;
    let initial_authorization = handle.acquire_turn_lease().await?.authorization();
    let mut schema_only = tool("echo");
    schema_only["description"] = json!("new presentation, unchanged dispatch scope");
    peer.tools(json!([schema_only]));
    assert_eq!(
        refresh(&handle).await?.servers[0].status,
        McpToolRefreshStatus::Updated
    );
    let old = handle.acquire_turn_lease().await?;
    assert_eq!(
        old.authorization(),
        initial_authorization,
        "a guarded authority must survive a presentation-only generation change"
    );
    handle
        .reconcile_authorized(peer.servers(), authority.clone())
        .await?;
    assert_eq!(refresh(&handle).await?.generation, old.generation().0);
    assert_eq!(
        handle.acquire_turn_lease().await?.authorization(),
        old.authorization()
    );
    FrozenMcpLease::resource_query(
        &old,
        None,
        pl_tool_mcp::support::ResourceOperation::ListResources { cursor: None },
    )
    .await?;

    let call_gate = Arc::new(tokio::sync::Semaphore::new(0));
    *peer.state.call_gate.lock().unwrap() = Some(call_gate.clone());
    let accepted = {
        let old = old.clone();
        tokio::spawn(async move {
            FrozenMcpLease::call_tool(&old, "peer".into(), "echo".into(), json!({})).await
        })
    };
    tokio::time::timeout(Duration::from_secs(5), peer.state.call_entered.notified()).await?;

    let gate = peer.gate();
    let refreshing = {
        let handle = handle.clone();
        tokio::spawn(async move { handle.refresh_tools().await })
    };
    peer.entered().await?;
    peer.tools(json!([tool("echo"), tool("late")]));
    authority.revoke();
    *peer.state.list_gate.lock().unwrap() = None;
    gate.add_permits(1);
    let report = refreshing.await??;
    assert_eq!(report.generation, old.generation().0);
    assert_eq!(report.servers[0].status, McpToolRefreshStatus::Failed);
    assert!(!old.authorization().is_active());
    assert!(handle.acquire_turn_lease().await.is_err());
    assert!(
        FrozenMcpLease::call_tool(&old, "peer".into(), "echo".into(), json!({}))
            .await
            .is_err()
    );
    let resource_error = FrozenMcpLease::resource_query(
        &old,
        None,
        pl_tool_mcp::support::ResourceOperation::ListResources { cursor: None },
    )
    .await
    .unwrap_err();
    assert!(
        resource_error
            .to_string()
            .contains("authorization was revoked")
    );
    assert!(handle.reconcile(peer.servers()).await.is_err());
    assert!(
        handle
            .reset(McpResetScope::All, peer.servers())
            .await
            .is_err()
    );
    assert!(
        handle
            .reconcile_authorized(peer.servers(), authority)
            .await
            .is_err()
    );
    assert!(
        peer.state.deleted_sessions.lock().unwrap().is_empty(),
        "revoking admission must not close a shared session"
    );
    *peer.state.call_gate.lock().unwrap() = None;
    call_gate.add_permits(1);
    let accepted_result = accepted.await??;
    assert!(
        !accepted_result.content.is_empty(),
        "accepted response was discarded after revocation"
    );

    let empty_authority = ToolAuthorization::unique();
    handle
        .reconcile_authorized(BTreeMap::new(), empty_authority.clone())
        .await?;
    assert!(handle.acquire_turn_lease().await?.tools().is_empty());
    empty_authority.revoke();
    assert!(handle.acquire_turn_lease().await.is_err());
    let restored_authority = ToolAuthorization::unique();
    handle
        .reconcile_authorized(peer.servers(), restored_authority)
        .await?;
    let restored = handle.acquire_turn_lease().await?;
    assert!(restored.authorization().is_active());
    assert_ne!(restored.authorization(), old.authorization());
    assert_eq!(restored.tools().len(), 2);
    drop(restored);
    drop(old);
    handle.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn revoked_preparation_is_rejected_and_new_configuration_can_reconcile() -> anyhow::Result<()>
{
    use pl_core::tool::opaque::ToolAuthorization;
    let peer = RefreshPeer::start().await?;
    peer.tools(json!([tool("echo")]));
    let handle = McpRuntime::new(McpConnector::default()).handle();
    let authority = ToolAuthorization::unique();
    handle
        .reconcile_authorized(BTreeMap::new(), authority.clone())
        .await?;
    let before = handle.acquire_turn_lease().await?.generation();
    let gate = peer.gate();
    let preparing = {
        let handle = handle.clone();
        let servers = peer.servers();
        let authority = authority.clone();
        tokio::spawn(async move { handle.reconcile_authorized(servers, authority).await })
    };
    peer.entered().await?;
    authority.revoke();
    *peer.state.list_gate.lock().unwrap() = None;
    gate.add_permits(1);
    assert!(preparing.await?.is_err());
    assert_eq!(handle.health_snapshot().await?.generation, before.0);
    assert!(handle.acquire_turn_lease().await.is_err());
    assert_eq!(
        peer.state.deleted_sessions.lock().unwrap().as_slice(),
        ["session-1"]
    );
    handle
        .reconcile_authorized(peer.servers(), ToolAuthorization::unique())
        .await?;
    let lease = handle.acquire_turn_lease().await?;
    assert_eq!(lease.tools().len(), 1);
    assert!(lease.authorization().is_active());
    drop(lease);
    handle.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn refresh_tools_updates_complete_definitions_and_reuses_connection() -> anyhow::Result<()> {
    let peer = RefreshPeer::start().await?;
    peer.tools(json!([tool("echo"), tool("removed"), tool("hidden")]));
    let handle = McpRuntime::new(McpConnector::default()).handle();
    handle.reconcile(peer.servers()).await?;
    let old = handle.acquire_turn_lease().await?;
    assert_eq!(
        old.tools().len(),
        2,
        "{:?}",
        handle.health_snapshot().await?
    );
    assert_eq!(peer.state.list_requests.load(Ordering::SeqCst), 1);
    let mut updates = handle.subscribe();

    let unchanged = refresh(&handle).await?;
    assert_eq!(unchanged.servers[0].status, McpToolRefreshStatus::Unchanged);
    assert_eq!(unchanged.generation, old.generation().0);
    assert_eq!(
        peer.state.list_requests.load(Ordering::SeqCst),
        2,
        "even a no-op refresh must contact the peer before ttlMs expires"
    );
    assert!(matches!(
        updates.try_recv(),
        Err(tokio::sync::broadcast::error::TryRecvError::Empty)
    ));
    // Server enumeration order is not a definition change or a reason to invalidate
    // the model's stable tool prefix/cache. Filtering and publication use name order.
    peer.tools(json!([tool("removed"), tool("hidden"), tool("echo")]));
    let reordered = refresh(&handle).await?;
    assert_eq!(reordered.servers[0].status, McpToolRefreshStatus::Unchanged);
    assert_eq!(reordered.generation, old.generation().0);
    assert_eq!(
        handle
            .acquire_turn_lease()
            .await?
            .tools()
            .iter()
            .map(|tool| tool.raw_name.as_str())
            .collect::<Vec<_>>(),
        vec!["echo", "removed"],
    );
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 1);
    assert!(matches!(
        updates.try_recv(),
        Err(tokio::sync::broadcast::error::TryRecvError::Empty)
    ));
    // Changes excluded by configuration are not model-visible changes.
    peer.tools(json!([tool("echo"), tool("removed")]));
    assert_eq!(refresh(&handle).await?.generation, old.generation().0);

    let mut changed = tool("echo");
    changed["inputSchema"] =
        json!({"type": "object", "properties": {"limit": {"type": "integer"}}});
    changed["outputSchema"] = json!({"type": "object", "properties": {"ok": {"type": "boolean"}}});
    changed["annotations"] = json!({"readOnlyHint": true});
    changed["icons"] = json!([{"src": "https://example.test/icon.png"}]);
    changed["_meta"] = json!({"revision": 2});
    peer.tools(json!([changed.clone(), tool("added")]));
    let report = refresh(&handle).await?;
    assert_eq!(report.servers[0].status, McpToolRefreshStatus::Updated);
    assert_eq!(report.servers[0].tool_count, Some(2));
    assert_ne!(report.generation, old.generation().0);
    updates.try_recv()?;
    let new = handle.acquire_turn_lease().await?;
    let descriptor = new.tools().iter().find(|t| t.raw_name == "echo").unwrap();
    assert_eq!(descriptor.input_schema, changed["inputSchema"]);
    assert_eq!(
        descriptor.output_schema.as_ref(),
        Some(&changed["outputSchema"])
    );
    assert_eq!(
        descriptor.annotations.as_ref(),
        Some(&changed["annotations"])
    );
    assert_eq!(descriptor.icons.as_ref(), Some(&changed["icons"]));
    assert_eq!(descriptor.metadata.as_ref(), Some(&changed["_meta"]));
    assert!(new.tools().iter().any(|t| t.raw_name == "added"));
    assert!(!new.tools().iter().any(|t| t.raw_name == "removed"));
    assert!(old.tools().iter().any(|t| t.raw_name == "removed"));
    assert_ne!(old.tools()[0].input_schema, descriptor.input_schema);
    let result =
        FrozenMcpLease::call_tool(&old, "peer".into(), "removed".into(), json!({})).await?;
    let payload: Value = serde_json::from_str(result.content[0].as_text().unwrap().text.as_str())?;
    assert_eq!(payload["session"], "session-1");
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 1);
    assert!(peer.state.deleted_sessions.lock().unwrap().is_empty());

    // Input schema changes alone, and then non-schema metadata alone, must each publish.
    changed["inputSchema"]["properties"]["limit"]["type"] = json!("string");
    peer.tools(json!([changed.clone(), tool("added")]));
    assert_eq!(
        refresh(&handle).await?.servers[0].status,
        McpToolRefreshStatus::Updated
    );
    changed["_meta"] = json!({"revision": 3});
    peer.tools(json!([changed, tool("added")]));
    assert_eq!(
        refresh(&handle).await?.servers[0].status,
        McpToolRefreshStatus::Updated
    );
    let no_op = refresh(&handle).await?;
    assert_eq!(no_op.servers[0].status, McpToolRefreshStatus::Unchanged);

    *peer.state.list_reply.lock().unwrap() = Some(json!({
        "error": {"code": -32603, "message": "failed refresh-secret-token"}
    }));
    let requests_before_failure = peer.state.list_requests.load(Ordering::SeqCst);
    let failed = refresh(&handle).await?;
    assert_eq!(
        peer.state.list_requests.load(Ordering::SeqCst),
        requests_before_failure + 1
    );
    assert_eq!(failed.servers[0].status, McpToolRefreshStatus::Failed);
    assert_eq!(failed.servers[0].tool_count, Some(2));
    let message = failed.servers[0].message.as_deref().unwrap();
    assert!(message.contains("[redacted]"), "{message}");
    assert!(!message.contains("refresh-secret-token"));
    assert_eq!(failed.generation, no_op.generation);
    assert_eq!(handle.acquire_turn_lease().await?.tools().len(), 2);
    peer.tools(json!([]));
    let recovered = refresh(&handle).await?;
    assert_eq!(
        peer.state.list_requests.load(Ordering::SeqCst),
        requests_before_failure + 2
    );
    assert_eq!(recovered.servers[0].status, McpToolRefreshStatus::Updated);
    assert_eq!(recovered.servers[0].tool_count, Some(0));
    assert!(handle.acquire_turn_lease().await?.tools().is_empty());
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 1);
    handle.shutdown().await?;
    assert_eq!(
        peer.state.deleted_sessions.lock().unwrap().as_slice(),
        &["session-1"]
    );
    Ok(())
}

#[tokio::test]
async fn refresh_tools_serializes_reset_and_does_not_block_calls_or_leases() -> anyhow::Result<()> {
    let peer = RefreshPeer::start().await?;
    peer.tools(json!([tool("echo")]));
    let handle = McpRuntime::new(McpConnector::default()).handle();
    handle.reconcile(peer.servers()).await?;
    let old = handle.acquire_turn_lease().await?;
    let gate = peer.gate();
    let refresh_handle = handle.clone();
    let request = tokio::spawn(async move { refresh_handle.refresh_tools().await });
    peer.entered().await?;
    let lease = tokio::time::timeout(Duration::from_secs(1), handle.acquire_turn_lease()).await??;
    assert_eq!(lease.generation(), old.generation());
    tokio::time::timeout(
        Duration::from_secs(1),
        FrozenMcpLease::call_tool(&old, "peer".into(), "echo".into(), json!({})),
    )
    .await??;
    let servers = peer.servers();
    let mut reset = Box::pin(handle.reset(McpResetScope::All, servers));
    assert!(futures::poll!(reset.as_mut()).is_pending());
    // Let the serial refresh finish; reset's handshake then gets its own discovery.
    *peer.state.list_gate.lock().unwrap() = None;
    gate.add_permits(1);
    assert_eq!(
        request.await??.servers[0].status,
        McpToolRefreshStatus::Unchanged
    );
    tokio::time::timeout(Duration::from_secs(10), reset).await??;
    let replacement = handle.acquire_turn_lease().await?;
    assert_ne!(replacement.generation(), old.generation());
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 2);
    // Reset stops admission through the old lease; it must not silently use the replacement.
    assert!(
        FrozenMcpLease::call_tool(&old, "peer".into(), "echo".into(), json!({}))
            .await
            .is_err()
    );
    FrozenMcpLease::call_tool(&replacement, "peer".into(), "echo".into(), json!({})).await?;
    assert_eq!(
        refresh(&handle).await?.generation,
        replacement.generation().0
    );
    handle.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn refresh_tools_shutdown_completes_active_and_queued_requests() -> anyhow::Result<()> {
    let peer = RefreshPeer::start().await?;
    peer.tools(json!([tool("echo")]));
    let handle = McpRuntime::new(McpConnector::default()).handle();
    handle.reconcile(peer.servers()).await?;
    let _gate = peer.gate();
    let active_handle = handle.clone();
    let active = tokio::spawn(async move { active_handle.refresh_tools().await });
    peer.entered().await?;
    let mut queued = Box::pin(handle.refresh_tools());
    assert!(futures::poll!(queued.as_mut()).is_pending());
    tokio::time::timeout(Duration::from_secs(2), handle.shutdown()).await??;
    assert!(
        tokio::time::timeout(Duration::from_secs(1), active)
            .await??
            .is_err()
    );
    assert!(
        tokio::time::timeout(Duration::from_secs(1), queued)
            .await?
            .is_err()
    );
    assert!(handle.refresh_tools().await.is_err());
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 1);
    assert_eq!(
        peer.state.deleted_sessions.lock().unwrap().as_slice(),
        &["session-1"]
    );
    Ok(())
}

#[tokio::test]
async fn refresh_tools_cancellation_is_owned_and_notifications_share_no_op_detection()
-> anyhow::Result<()> {
    let peer = RefreshPeer::start().await?;
    peer.tools(json!([tool("echo")]));
    let handle = McpRuntime::new(McpConnector::default()).handle();
    handle.reconcile(peer.servers()).await?;
    let old = handle.acquire_turn_lease().await?;
    let gate = peer.gate();
    let cancelled_handle = handle.clone();
    let cancelled = tokio::spawn(async move { cancelled_handle.refresh_tools().await });
    peer.entered().await?;
    cancelled.abort();
    assert!(cancelled.await.unwrap_err().is_cancelled());
    peer.tools(json!([tool("echo"), tool("added")]));
    *peer.state.list_gate.lock().unwrap() = None;
    gate.add_permits(1);
    // A queued explicit request observes the cancelled caller's completed publication.
    let report = refresh(&handle).await?;
    assert_eq!(report.servers[0].status, McpToolRefreshStatus::Unchanged);
    assert_ne!(report.generation, old.generation().0);
    let generation = report.generation;
    let gate = peer.gate();
    peer.notifications.send(())?;
    peer.entered().await?;
    *peer.state.list_gate.lock().unwrap() = None;
    gate.add_permits(1);
    assert_eq!(refresh(&handle).await?.generation, generation);
    peer.tools(json!([tool("echo")]));
    let mut updates = handle.subscribe();
    peer.notifications.send(())?;
    tokio::time::timeout(Duration::from_secs(5), updates.recv()).await??;
    assert_eq!(handle.acquire_turn_lease().await?.tools().len(), 1);
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 1);
    handle.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn refresh_tools_empty_and_unavailable_servers_do_not_connect() -> anyhow::Result<()> {
    let handle = McpRuntime::new(McpConnector::default()).handle();
    let empty = refresh(&handle).await?;
    assert!(empty.servers.is_empty());
    assert_eq!(empty.generation, 0);
    let peer = RefreshPeer::start().await?;
    let mut disabled = peer.config.clone();
    disabled.id = "disabled".into();
    disabled.status_kind = McpServerStatusKind::Disabled;
    let mut missing = peer.config.clone();
    missing.id = "missing".into();
    missing.status_kind = McpServerStatusKind::MissingCredential;
    missing.status_message = Some("do not leak refresh-secret-token".into());
    let mut unavailable = peer.config.clone();
    unavailable.id = "unavailable".into();
    unavailable.config.url = Some("http://127.0.0.1:0/mcp".into());
    handle
        .reconcile(BTreeMap::from([
            (disabled.id.clone(), disabled),
            (missing.id.clone(), missing),
            (unavailable.id.clone(), unavailable),
        ]))
        .await?;
    let before = handle.acquire_turn_lease().await?.generation();
    let report = refresh(&handle).await?;
    assert_eq!(report.generation, before.0);
    assert_eq!(report.servers.len(), 3);
    for server in report.servers {
        assert_eq!(server.status, McpToolRefreshStatus::Skipped);
        assert_eq!(server.tool_count, None);
        let message = server.message.unwrap();
        assert!(!message.contains("refresh-secret-token"));
        assert!(message.contains(match server.server_id.as_str() {
            "disabled" => "disabled",
            "missing" => "missing credentials",
            "unavailable" => "unavailable",
            other => panic!("unexpected server {other}"),
        }));
    }
    assert_eq!(peer.state.session_generation.load(Ordering::SeqCst), 0);
    handle.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn refresh_tools_continues_after_one_server_fails() -> anyhow::Result<()> {
    let first = RefreshPeer::start().await?;
    let second = RefreshPeer::start().await?;
    first.tools(json!([tool("first")]));
    second.tools(json!([tool("second")]));
    let mut config = second.config.clone();
    config.id = "second".into();
    let mut servers = first.servers();
    servers.insert(config.id.clone(), config);
    let handle = McpRuntime::new(McpConnector::default()).handle();
    handle.reconcile(servers).await?;
    let old = handle.acquire_turn_lease().await?;
    *first.state.list_reply.lock().unwrap() = Some(json!({
        "error": {"code": -32603, "message": "temporary discovery failure"}
    }));
    second.tools(json!([tool("replacement")]));
    let report = refresh(&handle).await?;
    assert_eq!(report.servers.len(), 2);
    assert_eq!(report.servers[0].server_id, "peer");
    assert_eq!(report.servers[0].status, McpToolRefreshStatus::Failed);
    assert_eq!(report.servers[1].server_id, "second");
    assert_eq!(report.servers[1].status, McpToolRefreshStatus::Updated);
    let new = handle.acquire_turn_lease().await?;
    assert_eq!(report.generation, new.generation().0);
    assert_ne!(new.generation(), old.generation());
    assert!(new.tools().iter().any(|tool| tool.raw_name == "first"));
    assert!(
        new.tools()
            .iter()
            .any(|tool| tool.raw_name == "replacement")
    );
    assert!(!new.tools().iter().any(|tool| tool.raw_name == "second"));
    assert_eq!(first.state.session_generation.load(Ordering::SeqCst), 1);
    assert_eq!(second.state.session_generation.load(Ordering::SeqCst), 1);
    handle.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn refresh_tools_orders_configuration_changes_before_later_discovery() -> anyhow::Result<()> {
    let original = RefreshPeer::start().await?;
    let other = RefreshPeer::start().await?;
    original.tools(json!([tool("original")]));
    other.tools(json!([tool("other")]));
    let handle = McpRuntime::new(McpConnector::default()).handle();
    handle.reconcile(original.servers()).await?;
    let old = handle.acquire_turn_lease().await?;
    let gate = original.gate();
    let active_handle = handle.clone();
    let active = tokio::spawn(async move { active_handle.refresh_tools().await });
    original.entered().await?;

    // Queue A -> B -> A while A's discovery is blocked. Comparing A against the
    // generation at enqueue time would incorrectly discard the second reconcile.
    let mut to_other = Box::pin(handle.reconcile(other.servers()));
    assert!(futures::poll!(to_other.as_mut()).is_pending());
    let mut back_to_original = Box::pin(handle.reconcile(original.servers()));
    assert!(futures::poll!(back_to_original.as_mut()).is_pending());
    let mut later_refresh = Box::pin(handle.refresh_tools());
    assert!(futures::poll!(later_refresh.as_mut()).is_pending());
    original.tools(json!([tool("new-original")]));
    *original.state.list_gate.lock().unwrap() = None;
    gate.add_permits(1);

    let report = tokio::time::timeout(Duration::from_secs(10), async {
        assert_eq!(
            active.await??.servers[0].status,
            McpToolRefreshStatus::Updated
        );
        to_other.await?;
        back_to_original.await?;
        Ok::<_, anyhow::Error>(later_refresh.await?)
    })
    .await??;
    assert_eq!(report.servers[0].status, McpToolRefreshStatus::Unchanged);
    let new = handle.acquire_turn_lease().await?;
    assert_eq!(report.generation, new.generation().0);
    assert_eq!(new.tools()[0].raw_name, "new-original");
    assert_eq!(old.tools()[0].raw_name, "original");
    assert_eq!(original.state.session_generation.load(Ordering::SeqCst), 2);
    assert_eq!(other.state.session_generation.load(Ordering::SeqCst), 1);
    assert_eq!(
        other.state.deleted_sessions.lock().unwrap().as_slice(),
        &["session-1"]
    );
    handle.shutdown().await?;
    Ok(())
}
