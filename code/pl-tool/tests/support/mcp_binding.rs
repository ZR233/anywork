use super::{binding_host, helper, stdio};
use pl_agent_tool::ToolHandle;
use pl_core::{
    model::DynModelSession,
    thread::{ThreadHandle, ToolOutcome},
    tool::opaque::ToolError,
};
use pl_tool::{
    binding::{ToolCallPolicy, prepare_registration},
    mcp::{McpConnector, McpRuntime, McpRuntimeHandle, McpTurnLease, thread::ThreadMcpTool},
    media::{RetainedToolMedia, ToolMedia, ToolMediaHost},
};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
    time::Duration,
};

#[derive(Debug)]
struct FailedArchive;

#[derive(Debug, thiserror::Error)]
#[error("archive rejected the exact received bytes")]
struct ArchiveFailure;

impl ToolMediaHost for FailedArchive {
    async fn retain(&self, media: ToolMedia) -> Result<RetainedToolMedia, ToolError> {
        assert_eq!(media.bytes.as_ref(), b"bytes");
        Err(ToolError::new(ArchiveFailure))
    }
}

async fn published(handle: &McpRuntimeHandle, tag: &str) -> anyhow::Result<McpTurnLease> {
    let mut changes = handle.subscribe();
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let lease = handle.acquire_turn_lease().await?;
            if lease
                .tools()
                .first()
                .is_some_and(|tool| tool.input_schema["description"] == tag)
            {
                return Ok(lease);
            }
            changes.recv().await?;
        }
    })
    .await?
}

#[tokio::test]
async fn frozen_peer_descriptor_and_results_survive_the_new_handle() -> anyhow::Result<()> {
    let root = tempfile::tempdir()?;
    let script =
        stdio::write_python_mcp_server(root.path(), "binding-peer.py", stdio::STDIO_MCP_SCRIPT);
    let runtime = McpRuntime::new(
        McpConnector::default().with_stdio_worker(helper::remote_helper_executable().to_path_buf()),
    );
    let runtime = runtime.handle();
    let servers = |tag: &str| {
        BTreeMap::from([(
            "binding-peer".to_owned(),
            stdio::stdio_effective_config(
                "binding-peer",
                &script,
                Vec::new(),
                BTreeMap::from([
                    ("MCP_BINDING_RESULTS".into(), "1".into()),
                    ("MCP_SCHEMA_TAG".into(), tag.into()),
                ]),
                Some(root.path().to_string_lossy().into_owned()),
                pl_tool::mcp::config::McpExecutionContext::Host,
            ),
        )])
    };
    runtime.reconcile(servers("old")).await?;
    let lease = published(&runtime, "old").await?;
    assert!(lease.has_resources());
    let descriptor = &lease.tools()[0];
    let definition = descriptor.definition()?;
    assert!(definition.output_schema().is_some());
    let mut tools = Vec::new();
    for mode in ["success", "error", "unarchived"] {
        let prepared =
            prepare_registration("binding.mcp", &definition, ToolCallPolicy::DirectOnly)?;
        let tool = ThreadMcpTool::new(
            lease.clone(),
            &descriptor.exposed_name,
            Arc::new(FailedArchive),
        )?;
        tools.push((mode, prepared, ToolHandle::new(tool)));
    }
    runtime.reconcile(servers("new")).await?;
    let replacement = published(&runtime, "new").await?;
    assert_ne!(lease.generation(), replacement.generation());
    assert_eq!(replacement.tools()[0].exposed_name, descriptor.exposed_name);
    for (mode, prepared, tool) in tools {
        assert_eq!(tool.definition(), &definition);
        let thread = ThreadHandle::start(
            format!("peer-{mode}"),
            DynModelSession::new(binding_host::Calls {
                calls: [("binding.mcp".into(), format!(r#"{{"mode":"{mode}"}}"#))].into(),
                requests: Arc::new(Mutex::new(Vec::new())),
            }),
        )?;
        // This host deliberately exposes the endpoint immediately; no source-specific executor.
        thread.register_tools(vec![prepared.attach(tool)]).await?;
        thread.run_turn(binding_host::turn(mode)).await?;
        let effects = thread.effects().await?;
        let deliveries = effects
            .iter()
            .flat_map(|effect| effect.deliveries.iter())
            .filter(|delivery| delivery.tool_id == "binding.mcp")
            .collect::<Vec<_>>();
        assert_eq!(deliveries.len(), 1, "the binding must never retry the peer");
        let delivery = deliveries[0];
        let payload = delivery.output.payload();
        if mode == "unarchived" {
            assert_eq!(payload.format(), "pl.tool.mcp-unarchived");
            assert!(payload.content().contains("Ynl0ZXM="));
            let ToolOutcome::Failed(error) = &delivery.outcome else {
                panic!("archive failure was lost")
            };
            assert!(error.source.downcast_ref::<ArchiveFailure>().is_some());
        } else {
            let json: serde_json::Value = serde_json::from_str(payload.content())?;
            assert_eq!(json["content"][0]["text"], format!("old:{mode}"));
            assert_eq!(
                matches!(delivery.outcome, ToolOutcome::Failed(_)),
                mode == "error"
            );
        }
        thread.close().await?;
    }
    drop(replacement);
    drop(lease);
    runtime.shutdown().await?;
    Ok(())
}
