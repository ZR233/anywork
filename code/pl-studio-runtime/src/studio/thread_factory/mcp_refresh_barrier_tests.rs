//! Configuration-commit/discovery interleaving with an actual stdio peer and Thread.
use super::{mcp_stdio, owner};
use crate::session::NativeResources;
use crate::studio::{StudioStore, storage_fault_test_support::close_factory};
use pl_agent_tool::Tool;
use pl_core::{
    model::DynModelSession,
    thread::{ThreadError, ThreadHandle},
    tool::opaque::ToolError,
};
use pl_protocol::{
    CreateMcpDocumentRequest, DeleteMcpDocumentRequest, McpScope, UpdateMcpDocumentRequest,
};
use pl_tool::{
    binding::{ToolCallPolicy, prepare_registration},
    mcp::thread::ThreadMcpTool,
    media::{RetainedToolMedia, ToolMedia, ToolMediaHost},
};
use std::{sync::Arc, time::Duration};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_util::sync::CancellationToken;

#[path = "../../../../pl-tool/tests/support/binding_host.rs"]
mod binding_host;

#[derive(Debug)]
struct NoMedia;
impl ToolMediaHost for NoMedia {
    async fn retain(&self, _: ToolMedia) -> Result<RetainedToolMedia, ToolError> {
        Err(ToolError::new(std::io::Error::other(
            "the barrier peer returns text only",
        )))
    }
}

#[tokio::test]
async fn committed_delete_must_not_be_regranted_by_late_refresh() -> anyhow::Result<()> {
    revoked_refresh(false).await
}

#[tokio::test]
async fn committed_disable_must_not_be_regranted_by_late_refresh() -> anyhow::Result<()> {
    revoked_refresh(true).await
}

async fn revoked_refresh(disable: bool) -> anyhow::Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let fixture = close_factory(&store)?;
    let factory = fixture.factory.clone();
    let resources = Arc::new(NativeResources::default());
    let owner = owner(&factory, &resources, "barrier", McpScope::Host, temp.path())?;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    let flag = temp.path().join("block-list");
    let log = temp.path().join("requests.jsonl");
    let peer = temp.path().join("peer.py");
    // Extend the shared peer only with a transport barrier, not with refresh semantics.
    let script = mcp_stdio::STDIO_MCP_SCRIPT
        .replace("import json, os, signal, sys, time", "import json, os, signal, socket, sys, time")
        .replace(
            "    elif method == \"tools/list\":",
            "    elif method == \"tools/list\":\n\
             \x20       late_discovery = os.path.exists(os.environ['MCP_LIST_FLAG'])\n\
             \x20       if late_discovery:\n\
             \x20           with socket.create_connection(('127.0.0.1', int(os.environ['MCP_LIST_PORT']))) as barrier:\n\
             \x20               barrier.sendall(b'1')\n\
             \x20               barrier.recv(1)",
        )
        .replace(
            "        schema = {\"type\": \"object\", \"properties\": {}}",
            "        schema = {\"type\": \"object\", \"properties\": {}}\n\
             \x20       schema['description'] = 'late candidate' if late_discovery else 'initial'",
        );
    std::fs::write(&peer, script)?;
    let raw = format!(
        "schema_version = 1\nid = 'barrier'\nkind = 'server'\nenabled = true\n\
         transport = 'stdio'\ncommand = 'python3'\nargs = {}\n\
         startup_timeout_secs = 10\n[env]\nMCP_NO_RESOURCES = '1'\n\
         MCP_LIST_PORT = '{}'\nMCP_LIST_FLAG = {}\nMCP_REQUEST_LOG = {}\n",
        serde_json::to_string(&["-u".to_owned(), peer.display().to_string()])?,
        listener.local_addr()?.port(),
        serde_json::to_string(&flag.display().to_string())?,
        serde_json::to_string(&log.display().to_string())?,
    );
    let mut running_refresh = None;
    let mut thread: Option<ThreadHandle> = None;
    let result = tokio::time::timeout(Duration::from_secs(30), async {
        let (created, _) = fixture.config.create_mcp_document(&CreateMcpDocumentRequest {
            scope: McpScope::Host, id: "barrier".into(), raw_toml: raw.clone(),
        })?;
        {
            let _command = owner.command_lock.lock().await;
            factory.reconcile_mcp_owner(&owner).await?;
        }
        // Keep a legitimately captured original lease for the delayed-installation proof.
        let initial = owner.runtime.acquire_turn_lease().await?;
        anyhow::ensure!(initial.tools().len() == 1, "actual initial state: {:?}", owner.read_snapshot());
        let original_authorization = initial.authorization();
        anyhow::ensure!(original_authorization.is_active());
        owner.start_watcher(factory.clone());
        std::fs::write(&flag, "block explicit tools/list")?;
        running_refresh = Some({
            let factory = factory.clone();
            let owner = owner.clone();
            tokio::spawn(async move {
                factory.refresh_mcp_for_owner(&owner, CancellationToken::new()).await
            })
        });
        let (mut barrier, _) = listener.accept().await?;
        let mut entered = [0];
        barrier.read_exact(&mut entered).await?;
        anyhow::ensure!(entered == [b'1']);
        let before_discovery = owner.runtime.health_snapshot().await?.generation;

        // Queue directory preparation before the configuration watcher, as in the original
        // counterexample. A revoked runtime must reject this acquisition, not return empty success.
        let preparation = async {
            let command = owner.command_lock.lock().await;
            let lease = owner.runtime.acquire_turn_lease().await;
            (command, lease)
        };
        tokio::pin!(preparation);
        anyhow::ensure!(futures::poll!(&mut preparation).is_pending(),
            "directory preparation did not queue behind the refresh");
        let document = created.document.clone().unwrap();
        let (committed, scopes) = if disable {
            fixture.config.update_mcp_document(&UpdateMcpDocumentRequest {
                document: document.clone(), expected_revision: created.revision,
                raw_toml: raw.replace("enabled = true", "enabled = false"),
            })?
        } else {
            fixture.config.delete_mcp_document(&DeleteMcpDocumentRequest {
                document: document.clone(), expected_revision: created.revision,
            })?
        };
        // Revocation is synchronous with the actual configuration commit, before notification.
        anyhow::ensure!(!original_authorization.is_active(), "commit did not revoke the captured lease");
        factory.reconcile_open_threads_for_scopes(&scopes).await;
        std::fs::remove_file(&flag)?;
        barrier.write_all(b"1").await?;
        drop(barrier);
        let refresh_result = running_refresh.as_mut().unwrap().await?;
        running_refresh.take();
        let (command, late_acquisition) = preparation.await;
        anyhow::ensure!(owner.runtime.health_snapshot().await?.generation == before_discovery,
            "revoked discovery published a new runtime generation");
        anyhow::ensure!(late_acquisition.is_err(), "a revoked current generation was exposed as a fresh lease");
        drop(command);
        let superseded = match refresh_result {
            Ok(receipt) => anyhow::bail!("stale refresh succeeded with catalogRevision={}, current={}",
                receipt.catalog_revision, committed.snapshot.revision),
            Err(error) => error,
        };
        anyhow::ensure!(superseded.to_string().contains("superseded"), "unexpected refresh refusal: {superseded}");

        // Observe corrective publication through runtime events; no sleep or timer-based polling.
        let mut updates = owner.runtime.subscribe();
        loop {
            if let Ok(lease) = owner.runtime.acquire_turn_lease().await
                && lease.authorization().is_active()
                && lease.tools().is_empty()
            {
                break;
            }
            updates.recv().await?;
        }
        let current = factory.refresh_mcp_for_owner(&owner, CancellationToken::new()).await?;
        anyhow::ensure!(current.catalog_revision == committed.snapshot.revision,
            "stable refresh did not report the new configuration revision");
        anyhow::ensure!(
            current.state.servers.iter().all(|server| server.id != "barrier")
                && current.discovery.servers.iter().all(|server| server.server_id != "barrier")
        );

        // Even after current empty publication, the original retained lease cannot be installed.
        // Use the real Thread registration boundary, not a direct equality comparison alone.
        let descriptor = initial.tools().first().unwrap().clone();
        let tool = ThreadMcpTool::new(initial, &descriptor.exposed_name, Arc::new(NoMedia))?;
        let prepared = prepare_registration(&descriptor.exposed_name, tool.definition(), ToolCallPolicy::DirectOnly)?;
        thread = Some(ThreadHandle::start(owner.thread_id.clone(), DynModelSession::new(binding_host::Calls {
            calls: [(descriptor.exposed_name.clone(), "{}".into())].into(), requests: Default::default(),
        }))?);
        let current_thread = thread.as_ref().unwrap();
        let registration = current_thread.register_tools_if_extensions(
            current_thread.snapshot().extension_sequence, vec![tool.registration(prepared)]).await;
        if registration.is_ok() {
            // If registration regresses, actually try the new invocation and retain the
            // peer-call assertion below; an authorization comparison alone is insufficient.
            current_thread.reveal_tools(vec![descriptor.exposed_name]).await?;
            let _outcome = current_thread.run_turn(binding_host::turn("late-call")).await;
        }
        anyhow::ensure!(matches!(registration, Err(ThreadError::ToolPermissionRevoked)),
            "late registration was not rejected for revoked authority: {registration:?}");

        // Re-enabling/deleting-and-recreating issues a valid new authority and remains usable.
        let (restored, scopes) = if disable {
            fixture.config.update_mcp_document(&UpdateMcpDocumentRequest {
                document, expected_revision: committed.revision, raw_toml: raw.clone(),
            })?
        } else {
            fixture.config.create_mcp_document(&CreateMcpDocumentRequest {
                scope: McpScope::Host, id: "barrier".into(), raw_toml: raw.clone(),
            })?
        };
        factory.reconcile_open_threads_for_scopes(&scopes).await;
        let restored_receipt = factory.refresh_mcp_for_owner(&owner, CancellationToken::new()).await?;
        anyhow::ensure!(restored_receipt.catalog_revision == restored.snapshot.revision);
        let recovered = owner.runtime.acquire_turn_lease().await?;
        anyhow::ensure!(recovered.authorization().is_active() && recovered.tools().len() == 1);
        anyhow::ensure!(!original_authorization.is_active(), "restoration revived the old authority");
        eprintln!("barrier evidence: disable={disable}, superseded=true, committedRevision={}, stableReceiptRevision={}, revokedLeaseRejected=true, lateRegistrationRejected=true, restoredRevision={}",
            committed.snapshot.revision, current.catalog_revision, restored_receipt.catalog_revision);
        Ok::<_, anyhow::Error>(())
    }).await.map_err(anyhow::Error::from).and_then(std::convert::identity);

    // Always join the refresh and close the Thread/runtime, including early refusal, timeout,
    // assertion failure and transport errors. Dropping the body also drops its barrier socket.
    owner.cancel_producers();
    let refresh_cleanup = if let Some(refresh) = running_refresh.take() {
        refresh.await.map(|_| ()).map_err(anyhow::Error::from)
    } else {
        Ok(())
    };
    let thread_cleanup = if let Some(thread) = thread {
        thread.close().await.map_err(anyhow::Error::from)
    } else {
        Ok(())
    };
    let owner_cleanup = owner
        .close(&fixture.events)
        .await
        .map_err(anyhow::Error::from);
    let calls = match std::fs::read_to_string(log) {
        Ok(log) => log
            .lines()
            .map(serde_json::from_str::<serde_json::Value>)
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .filter(|request| request["method"] == "tools/call")
            .count(),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => 0,
        Err(error) => return Err(error.into()),
    };
    eprintln!("barrier external evidence: disable={disable}, newPeerCalls={calls}");
    anyhow::ensure!(
        calls == 0,
        "revoked configuration accepted {calls} new external calls"
    );
    if let Err(error) = result {
        return Err(error.context(format!("cleanup: refresh={refresh_cleanup:?}, thread={thread_cleanup:?}, owner={owner_cleanup:?}")));
    }
    refresh_cleanup?;
    thread_cleanup?;
    owner_cleanup?;
    Ok(())
}
