//! Physical-owner, cancellation and sibling-isolation proofs for the Studio command.
use super::{binding_host, mcp_stdio, owner};
use crate::session::NativeResources;
use crate::studio::{StudioStore, storage_fault_test_support::close_factory};
use anyhow::Context;
use pl_core::{
    context::{ContextContent, ContextSource},
    model::DynModelSession,
    thread::ThreadHandle,
    tool::opaque::Registration,
};
use pl_protocol::{CreateMcpDocumentRequest, McpScope};
use std::{sync::Arc, time::Duration};
use tokio_util::sync::CancellationToken;

fn gated_initialize(port: u16) -> String {
    mcp_stdio::STDIO_MCP_SCRIPT
        .replace(
            "import json, os, signal, sys, time",
            "import json, os, signal, socket, sys, time",
        )
        .replace(
            "    elif method == \"initialize\":",
            &format!("    elif method == \"initialize\":\n        with socket.create_connection(('127.0.0.1', {port})) as gate:\n            gate.sendall(b'1')\n            gate.recv(1)"),
        )
}

async fn call_registration(
    id: &str,
    tool_id: &str,
    registration: Registration,
    raw: &str,
) -> anyhow::Result<String> {
    let thread = ThreadHandle::start(
        id.into(),
        DynModelSession::new(binding_host::Calls {
            calls: [(tool_id.into(), raw.into())].into(),
            requests: Default::default(),
        }),
    )?;
    let result = async {
        thread.register_tools(vec![registration]).await?;
        thread.reveal_tools(vec![tool_id.into()]).await?;
        thread
            .run_turn(binding_host::turn("reconnect-proof"))
            .await?;
        let snapshot = thread.snapshot();
        Ok(snapshot
            .context
            .records
            .iter()
            .filter(|record| matches!(record.source, ContextSource::ToolResult { .. }))
            .flat_map(|record| &record.content)
            .filter_map(|part| match part {
                ContextContent::Text { text } => Some(text.as_ref()),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join("\n"))
    }
    .await;
    thread.close().await?;
    result
}

#[tokio::test]
async fn reconnect_binding_rejects_wrong_thread_replaced_and_expired_physical_owner()
-> anyhow::Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let fixture = close_factory(&store)?;
    let factory = &fixture.factory;
    let resources = Arc::new(NativeResources::default());
    let old = owner(factory, &resources, "same-id", McpScope::Host, temp.path())?;
    let registration =
        super::super::super::mcp_reconnect_tool::registration(factory.clone(), &old)?;
    let output = call_registration(
        "wrong-id",
        "reconnect_mcp",
        registration,
        r#"{"serverId":"fixture"}"#,
    )
    .await?;
    anyhow::ensure!(output.contains("different Thread"), "{output}");
    let frozen = super::super::super::mcp_reconnect_tool::registration(factory.clone(), &old)?;
    let current = owner(factory, &resources, "same-id", McpScope::Host, temp.path())?;
    let output = call_registration(
        "same-id",
        "reconnect_mcp",
        frozen,
        r#"{"serverId":"fixture"}"#,
    )
    .await?;
    anyhow::ensure!(output.contains("no longer active"), "{output}");
    anyhow::ensure!(current.runtime.snapshots().await.is_empty());
    let expired = super::super::super::mcp_reconnect_tool::registration(factory.clone(), &old)?;
    old.close(&fixture.events).await?;
    drop(old);
    let output = call_registration(
        "same-id",
        "reconnect_mcp",
        expired,
        r#"{"serverId":"fixture"}"#,
    )
    .await?;
    anyhow::ensure!(output.contains("no longer active"), "{output}");
    current.close(&fixture.events).await?;
    Ok(())
}

#[tokio::test]
async fn reconnect_cancellation_and_close_release_the_original_owner_command_boundary()
-> anyhow::Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let fixture = close_factory(&store)?;
    let factory = &fixture.factory;
    let resources = Arc::new(NativeResources::default());
    let current = owner(factory, &resources, "cancel", McpScope::Host, temp.path())?;
    let result = async {
    let command = current.command_lock.lock().await;
    let cancellation = CancellationToken::new();
    let reconnect =
        factory.reconnect_mcp_for_owner(&current, Some("fixture"), cancellation.clone());
    tokio::pin!(reconnect);
    assert!(futures::poll!(&mut reconnect).is_pending());
    cancellation.cancel();
    let error = tokio::time::timeout(Duration::from_secs(2), &mut reconnect)
        .await?
        .unwrap_err();
    anyhow::ensure!(error.to_string().contains("cancelled"));
    drop(command);
    anyhow::ensure!(current.command_lock.try_lock().is_ok());

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    let peer = temp.path().join("slow.py");
    // Signal actual initialize admission, then block; no sleeps infer runtime acceptance.
    std::fs::write(&peer, gated_initialize(listener.local_addr()?.port()))?;
    fixture.config.create_mcp_document(&CreateMcpDocumentRequest {
        scope: McpScope::Host,
        id: "slow".into(),
        raw_toml: format!("schema_version = 1\nid = 'slow'\nkind = 'server'\nenabled = true\ntransport = 'stdio'\ncommand = 'python3'\nargs = {}\nstartup_timeout_secs = 30\n",
            serde_json::to_string(&["-u".to_owned(), peer.display().to_string()])?),
    })?;
    let reconnect =
        factory.reconnect_mcp_for_owner(&current, Some("slow"), CancellationToken::new());
    tokio::pin!(reconnect);
    let accepted = tokio::select! {
        result = &mut reconnect => anyhow::bail!("reconnect ended before initialize: {result:?}"),
        accepted = tokio::time::timeout(Duration::from_secs(5), listener.accept()) =>
            accepted.context("close proof: initialize gate never entered")??,
    };
    let closing = current.close(&fixture.events);
    tokio::pin!(closing);
    assert!(futures::poll!(&mut closing).is_pending());
    let error = tokio::time::timeout(Duration::from_secs(2), &mut reconnect)
        .await.context("close proof: reconnect did not observe owner close")?
        .unwrap_err();
    anyhow::ensure!(error.to_string().contains("closing"));
    tokio::time::timeout(Duration::from_secs(5), closing).await.context("close proof: owner did not join reset")??;
    drop(accepted);
    anyhow::ensure!(current.command_lock.try_lock().is_ok());
    anyhow::ensure!(
        factory
            .reconnect_mcp_for_owner(&current, Some("slow"), CancellationToken::new())
            .await
            .is_err()
    );
    Ok::<_, anyhow::Error>(())
    }.await;
    let closed = current.close(&fixture.events).await;
    result?;
    closed?;
    Ok(())
}

#[tokio::test]
async fn failed_reconnect_preserves_current_lease_during_same_configuration_preparation()
-> anyhow::Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let fixture = close_factory(&store)?;
    let factory = &fixture.factory;
    let peer = temp.path().join("peer.py");
    std::fs::write(&peer, mcp_stdio::STDIO_MCP_SCRIPT)?;
    for id in ["fixture", "unrelated"] {
        fixture
            .config
            .create_mcp_document(&CreateMcpDocumentRequest {
                scope: McpScope::Host,
                id: id.into(),
                raw_toml: format!(
                    "schema_version = 1\nid = '{id}'\nkind = 'server'\nenabled = true\n\
                 transport = 'stdio'\ncommand = 'python3'\nargs = {}\n\
                 startup_timeout_secs = 5\n[env]\nSPECIAL_ENV = '{id}'\nMCP_NO_RESOURCES = '1'\n",
                    serde_json::to_string(&["-u".to_owned(), peer.display().to_string()])?,
                ),
            })?;
    }
    let resources = Arc::new(NativeResources::default());
    let current = owner(
        factory,
        &resources,
        "failed-reset",
        McpScope::Host,
        temp.path(),
    )?;
    let result = async {
        factory
            .refresh_mcp_for_owner(&current, CancellationToken::new())
            .await?;
        let before = current.runtime.acquire_turn_lease().await?;
        let sibling_tools: Vec<_> = before
            .tools()
            .iter()
            .filter(|tool| tool.server_id == "unrelated")
            .cloned()
            .collect();
        anyhow::ensure!(!sibling_tools.is_empty());
        // Only a new process sees this failure; the sibling's established session stays live.
        std::fs::write(&peer, "import sys\nsys.exit(1)\n")?;
        let error = factory
            .reconnect_mcp_for_owner(&current, Some("fixture"), CancellationToken::new())
            .await
            .expect_err("replacement handshake must fail");
        anyhow::ensure!(error.to_string().contains("remains unavailable"));
        let resolved = factory.resolve_mcp_owner_snapshot(&current)?;
        // This is the preparation performed for the next actual model step. Unchanged
        // configuration must reuse the current lease without starting optional peers again.
        let next = current
            .prepare_required(
                resolved.servers,
                Some(resolved.authorization),
                None,
                &fixture.events,
                &CancellationToken::new(),
            )
            .await?;
        anyhow::ensure!(
            next.generation() == before.generation(),
            "same-configuration preparation started a new generation after failed reconnect"
        );
        anyhow::ensure!(
            next.tools() == sibling_tools,
            "failed target was re-exposed or an unrelated session was removed"
        );
        let snapshot = current.read_snapshot();
        anyhow::ensure!(
            snapshot.servers.iter().any(|server| server.id == "fixture"
                && server.lifecycle == pl_protocol::ThreadMcpLifecycleKind::Unavailable),
            "next model preparation changed the failed target state: {snapshot:?}"
        );
        anyhow::ensure!(
            snapshot
                .servers
                .iter()
                .any(|server| server.id == "unrelated"
                    && server.lifecycle == pl_protocol::ThreadMcpLifecycleKind::Available)
        );
        Ok::<_, anyhow::Error>(())
    }
    .await;
    let closed = current.close(&fixture.events).await;
    result?;
    closed?;
    Ok(())
}

#[tokio::test]
async fn cancelled_accepted_reconnect_recovers_projection_and_preserves_sibling_sessions()
-> anyhow::Result<()> {
    use pl_agent_tool::Tool;
    use pl_tool::{
        binding::{ToolCallPolicy, prepare_registration},
        mcp::thread::ThreadMcpTool,
        media::{RetainedToolMedia, ToolMedia, ToolMediaHost},
    };
    #[derive(Debug)]
    struct NoMedia;
    impl ToolMediaHost for NoMedia {
        async fn retain(
            &self,
            _: ToolMedia,
        ) -> Result<RetainedToolMedia, pl_core::tool::opaque::ToolError> {
            unreachable!("the peer only returns text")
        }
    }
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let fixture = close_factory(&store)?;
    let factory = &fixture.factory;
    let peer = temp.path().join("peer.py");
    let log = temp.path().join("requests.jsonl");
    std::fs::write(&peer, mcp_stdio::STDIO_MCP_SCRIPT)?;
    for id in ["fixture", "unrelated"] {
        fixture.config.create_mcp_document(&CreateMcpDocumentRequest {
            scope: McpScope::Host, id: id.into(),
            raw_toml: format!("schema_version = 1\nid = '{id}'\nkind = 'server'\nenabled = true\ntransport = 'stdio'\ncommand = 'python3'\nargs = {}\nstartup_timeout_secs = 5\n[env]\nSPECIAL_ENV = '{id}'\nMCP_SCHEMA_TAG = '{id}'\nMCP_NO_RESOURCES = '1'\nMCP_REQUEST_LOG = {}\n",
                serde_json::to_string(&["-u".to_owned(), peer.display().to_string()])?,
                serde_json::to_string(&log.display().to_string())?),
        })?;
    }
    let a_resources = Arc::new(NativeResources::default());
    let b_resources = Arc::new(NativeResources::default());
    let a = owner(factory, &a_resources, "a", McpScope::Host, temp.path())?;
    let b = owner(factory, &b_resources, "b", McpScope::Host, temp.path())?;
    let result =
        async {
            factory
                .refresh_mcp_for_owner(&a, CancellationToken::new())
                .await?;
            factory
                .refresh_mcp_for_owner(&b, CancellationToken::new())
                .await?;
            let b_before = b.runtime.acquire_turn_lease().await?.generation();
            let b_state = b.read_snapshot();
            let a_before = a.runtime.acquire_turn_lease().await?.generation();
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
            std::fs::write(&peer, gated_initialize(listener.local_addr()?.port()))?;
            a.start_watcher(factory.clone());
            let mut projection = fixture.events.subscribe_topic_signal(
                &crate::StudioProductTopic::ThreadMcp { thread_id: "a".into() });
            let cancellation = CancellationToken::new();
            let reconnect = factory.reconnect_mcp_for_owner(&a, Some("fixture"), cancellation.clone());
            tokio::pin!(reconnect);
            let (mut gate, _) = tokio::select! {
                result = &mut reconnect => anyhow::bail!("reset ended before initialize: {result:?}"),
                accepted = tokio::time::timeout(Duration::from_secs(5), listener.accept()) =>
                    accepted.context("cancel proof: initialize gate never entered")??,
            };
            use tokio::io::{AsyncReadExt, AsyncWriteExt};
            let mut entered = [0];
            gate.read_exact(&mut entered).await?;
            anyhow::ensure!(entered == *b"1", "initialize gate was not entered");
            cancellation.cancel();
            let error = tokio::time::timeout(Duration::from_secs(2), &mut reconnect).await
                .context("cancel proof: caller cancellation did not return")?.unwrap_err();
            anyhow::ensure!(error.to_string().contains("cancelled"), "{error}");
            // Only the existing watcher may finish the reset and restore projection. No
            // explicit refresh, manual resume_projection or replacement reconnect is allowed.
            gate.write_all(b"1").await?;
            drop(gate);
            tokio::time::timeout(Duration::from_secs(5), async {
                loop {
                    let snapshot = a.read_snapshot();
                    if a.projection_ready.load(std::sync::atomic::Ordering::Acquire)
                        && ["fixture", "unrelated"].iter().all(|id| snapshot.servers.iter()
                            .any(|server| server.id == *id
                                && server.lifecycle == pl_protocol::ThreadMcpLifecycleKind::Available))
                        && a.runtime.acquire_turn_lease().await?.generation() > a_before
                    {
                        break;
                    }
                    projection.changed().await?;
                }
                Ok::<_, anyhow::Error>(())
            }).await.with_context(|| format!("cancel proof: original watcher did not restore projection; ready={}, state={:?}, requests={}",
                a.projection_ready.load(std::sync::atomic::Ordering::Acquire), a.read_snapshot(),
                std::fs::read_to_string(&log).unwrap_or_default()))??;
            anyhow::ensure!(a.command_lock.try_lock().is_ok(), "background reconcile retained command lock");
            anyhow::ensure!(b.runtime.acquire_turn_lease().await?.generation() == b_before);
            anyhow::ensure!(b.read_snapshot() == b_state);
            for calling in [&a, &b] {
            let lease = calling.runtime.acquire_turn_lease().await?;
            let descriptor = lease
                .tools()
                .iter()
                .find(|tool| tool.server_id == "fixture")
                .ok_or_else(|| anyhow::anyhow!("sibling lost fixture tool"))?
                .clone();
            let tool = ThreadMcpTool::new(lease, &descriptor.exposed_name, Arc::new(NoMedia))?;
            let prepared = prepare_registration(
                &descriptor.exposed_name,
                tool.definition(),
                ToolCallPolicy::DirectOnly,
            )?;
            let output = call_registration(
                &calling.thread_id,
                &descriptor.exposed_name,
                tool.registration(prepared),
                "{}",
            )
            .await?;
            anyhow::ensure!(output.contains("fixture"), "{output}");
            if Arc::ptr_eq(calling, &a) {
                a.close(&fixture.events).await?;
            }
            }
            let requests = std::fs::read_to_string(&log)?
                .lines()
                .map(serde_json::from_str::<serde_json::Value>)
                .collect::<Result<Vec<_>, _>>()?;
            anyhow::ensure!(
                requests
                    .iter()
                    .filter(
                        |request| request["method"] == "initialize" && request["tag"] == "fixture"
                    )
                    .count()
                    == 3
            );
            anyhow::ensure!(
                requests
                    .iter()
                    .filter(|request| request["method"] == "initialize"
                        && request["tag"] == "unrelated")
                    .count()
                    == 2,
                "targeted reconnect restarted an unrelated server"
            );
            anyhow::ensure!(requests.iter().filter(|request| request["method"] == "tools/call").count() == 2,
                "cancellation replayed a business call");
            Ok::<_, anyhow::Error>(())
        }
        .await;
    let a_close = a.close(&fixture.events).await;
    let b_close = b.close(&fixture.events).await;
    result?;
    a_close?;
    b_close?;
    Ok(())
}
