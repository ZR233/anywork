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
    // Old leases retain the original session rather than dispatching through its replacement.
    let result = FrozenMcpLease::call_tool(&old, "peer".into(), "echo".into(), json!({})).await?;
    assert!(
        result.content[0]
            .as_text()
            .unwrap()
            .text
            .contains("session-1")
    );
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
