//! Narrow owner/lifecycle proofs complement the real model/Thread integration test.
use super::*;
use crate::session::NativeResources;
use crate::studio::{StudioStore, storage_fault_test_support::close_factory};
use std::time::Duration;
#[path = "mcp_refresh_barrier_tests.rs"]
mod barrier_tests;
#[path = "../../../../pl-tool/tests/support/binding_host.rs"]
mod binding_host;
#[expect(dead_code, reason = "shared real stdio protocol fixture")]
#[path = "../../../../pl-tool/tests/support/mcp_stdio.rs"]
mod mcp_stdio;
#[path = "mcp_reconnect_tests.rs"]
mod reconnect_tests;

fn owner(
    factory: &StudioThreadFactory,
    resources: &Arc<NativeResources>,
    id: &str,
    scope: McpScope,
    root: &std::path::Path,
) -> Result<Arc<ThreadMcpOwner>> {
    factory.bind_resource_scope(id, resources)?;
    let connector = factory.services.mcp_connector.clone();
    let runtime = McpRuntime::new(connector);
    let owner = ThreadMcpOwner::new(
        id.into(),
        Arc::new(ThreadToolLifetime {
            gate: Arc::new(tokio::sync::Mutex::new(())),
            cancellation: CancellationToken::new(),
        }),
        scope,
        root.into(),
        None,
        runtime.handle(),
        BTreeMap::new(),
    );
    *resources.mcp.lock().unwrap() = Some(owner.clone());
    Ok(owner)
}

#[tokio::test]
async fn refresh_rejects_replaced_owner_and_cancellation_releases_command_lock() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let fixture = close_factory(&store)?;
    let factory = &fixture.factory;
    let resources = Arc::new(NativeResources::default());
    let old = owner(factory, &resources, "same-id", McpScope::Host, temp.path())?;
    let current = owner(factory, &resources, "same-id", McpScope::Host, temp.path())?;
    assert!(
        factory
            .refresh_mcp_for_owner(&old, CancellationToken::new())
            .await
            .is_err()
    );
    assert!(current.runtime.snapshots().await.is_empty());

    let command = current.command_lock.lock().await;
    tokio::time::timeout(
        Duration::from_secs(2),
        factory.reconcile_open_threads_for_scopes(&[McpScope::Host]),
    )
    .await?;
    let cancellation = CancellationToken::new();
    let refresh = factory.refresh_mcp_for_owner(&current, cancellation.clone());
    tokio::pin!(refresh);
    assert!(futures::poll!(&mut refresh).is_pending());
    cancellation.cancel();
    assert!(
        tokio::time::timeout(Duration::from_secs(2), &mut refresh)
            .await?
            .is_err()
    );
    drop(command);

    fixture.config.create_mcp_document(&pl_protocol::CreateMcpDocumentRequest {
        scope: McpScope::Host,
        id: "slow".into(),
        raw_toml: "schema_version = 1\nid = 'slow'\nkind = 'server'\nenabled = true\ntransport = 'stdio'\ncommand = 'python3'\nargs = ['-c', 'import time; time.sleep(60)']\nstartup_timeout_secs = 30\n".into(),
    })?;
    // Refresh now owns the lock while its accepted runtime command is pending.
    // Closing must cancel it before trying to acquire that same lock.
    let refresh = factory.refresh_mcp_for_owner(&current, CancellationToken::new());
    tokio::pin!(refresh);
    assert!(futures::poll!(&mut refresh).is_pending());
    assert!(current.command_lock.try_lock().is_err());
    let closing = current.close(&fixture.events);
    tokio::pin!(closing);
    assert!(futures::poll!(&mut closing).is_pending());
    assert!(
        tokio::time::timeout(Duration::from_secs(2), &mut refresh)
            .await?
            .is_err()
    );
    tokio::time::timeout(Duration::from_secs(2), closing).await??;
    assert!(
        factory
            .refresh_mcp_for_owner(&current, CancellationToken::new())
            .await
            .is_err()
    );
    old.close(&fixture.events).await?;
    Ok(())
}

#[tokio::test]
async fn ssh_refresh_reloads_host_inheritance_without_commanding_unrelated_owners() -> Result<()> {
    use crate::config::ConfigPaths;
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let fixture = close_factory(&store)?;
    let factory = &fixture.factory;
    let ssh_scope = McpScope::Ssh {
        ssh_alias: "selected".into(),
    };
    let other_scope = McpScope::Ssh {
        ssh_alias: "other".into(),
    };
    let ssh_resources = Arc::new(NativeResources::default());
    let host_resources = Arc::new(NativeResources::default());
    let other_resources = Arc::new(NativeResources::default());
    let ssh = owner(
        factory,
        &ssh_resources,
        "ssh",
        ssh_scope.clone(),
        temp.path(),
    )?;
    let host = owner(
        factory,
        &host_resources,
        "host",
        McpScope::Host,
        temp.path(),
    )?;
    let other = owner(
        factory,
        &other_resources,
        "other",
        other_scope.clone(),
        temp.path(),
    )?;
    let before = fixture.config.mcp_catalog_snapshot(&ssh_scope)?;
    let other_before = fixture.config.mcp_catalog_snapshot(&other_scope)?;
    let host_state = host.read_snapshot();
    let other_state = other.read_snapshot();
    let paths = ConfigPaths::from_config_dir(store.paths().home().join("isolated-test-config"));
    std::fs::create_dir_all(paths.mcp_host_dir())?;
    let peer = temp.path().join("peer.py");
    std::fs::write(&peer, mcp_stdio::STDIO_MCP_SCRIPT)?;
    // Host-inherited servers execute on Host even for SSH owners. No invented SSH
    // transport is necessary to prove actual connection/discovery and scope isolation.
    std::fs::write(
        paths.mcp_host_dir().join("shared.toml"),
        format!(
            "schema_version = 1\nid = 'shared'\nkind = 'server'\nenabled = true\ntransport = 'stdio'\ncommand = 'python3'\nargs = {}\nstartup_timeout_secs = 5\n[env]\nMCP_NO_RESOURCES = '1'\n",
            serde_json::to_string(&["-u".to_owned(), peer.display().to_string()])?
        ),
    )?;
    let receipt = factory
        .refresh_mcp_for_owner(&ssh, CancellationToken::new())
        .await?;
    assert!(receipt.catalog_revision > before.revision);
    assert!(
        receipt
            .state
            .servers
            .iter()
            .any(|server| server.id == "shared"
                && server.lifecycle == ThreadMcpLifecycleKind::Available
                && server.tool_count == Some(1)),
        "actual state: {:?}",
        receipt.state
    );
    assert!(
        receipt
            .discovery
            .servers
            .iter()
            .any(|server| server.server_id == "shared"
                && server.status == pl_tool::mcp::McpToolRefreshStatus::Unchanged)
    );
    let selected = fixture.config.mcp_catalog_snapshot(&ssh_scope)?;
    assert!(
        selected
            .entries
            .iter()
            .any(|entry| entry.id == "shared" && entry.inherited_from_host)
    );
    assert!(
        fixture
            .config
            .mcp_catalog_snapshot(&McpScope::Host)?
            .entries
            .iter()
            .any(|entry| entry.id == "shared")
    );
    // No all-scope reload, no Host runtime notification, no activation of another owner.
    assert_eq!(
        fixture.config.mcp_catalog_snapshot(&other_scope)?,
        other_before
    );
    assert_eq!(host.read_snapshot(), host_state);
    assert_eq!(other.read_snapshot(), other_state);

    let reconnected = factory.reconnect_thread_mcp("ssh", Some("shared")).await?;
    assert!(reconnected.servers.iter().any(
        |server| server.id == "shared" && server.lifecycle == ThreadMcpLifecycleKind::Available
    ));

    // Settings publications (including account/credential edits) are a different source:
    // unlike the scope-only tool refresh above, they must still schedule reconciliation.
    let settings = fixture.config.read()?;
    host.mark_settings_revision(settings.revision);
    let mut updates = host.runtime.subscribe();
    host.start_watcher(factory.clone());
    let settings = fixture
        .config
        .replace(settings.revision, settings.canonical_config().clone())?;
    host.request_settings_reconcile(settings.revision);
    tokio::time::timeout(Duration::from_secs(5), async {
        updates.recv().await?;
        let _command = host.command_lock.lock().await;
        anyhow::ensure!(
            host.read_snapshot()
                .servers
                .iter()
                .any(|server| server.id == "shared"
                    && server.lifecycle == ThreadMcpLifecycleKind::Available)
        );
        Ok::<_, anyhow::Error>(())
    })
    .await??;
    ssh.close(&fixture.events).await?;
    host.close(&fixture.events).await?;
    other.close(&fixture.events).await?;
    Ok(())
}
