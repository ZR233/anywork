use super::{binding_host, stdio};
use pl_agent_tool::{Tool, ToolHandle};
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
    let runtime = McpRuntime::new(McpConnector::default());
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
                    ("MCP_BINDING_STRUCTURED".into(), "1".into()),
                    ("MCP_SCHEMA_TAG".into(), tag.into()),
                    (
                        "MCP_REQUEST_LOG".into(),
                        root.path()
                            .join("requests.jsonl")
                            .to_string_lossy()
                            .into_owned(),
                    ),
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
    assert_eq!(
        definition.output_schema(),
        descriptor.output_schema.as_ref()
    );
    let output_schema = definition.output_schema().unwrap();
    assert_eq!(
        output_schema["required"],
        serde_json::json!(["count", "empty", "optional"])
    );
    assert_eq!(output_schema["additionalProperties"], false);
    assert_eq!(
        descriptor.effect, None,
        "remote hints must not grant local read authority"
    );
    assert_eq!(descriptor.safety_hints.read_only_hint, Some(true));
    let pl_agent_tool::InputFormat::JsonSchema(schema) = definition.input() else {
        panic!("MCP schema lost")
    };
    assert_eq!(schema, &descriptor.input_schema);
    assert!(schema.get("type").is_none(), "remote schema was normalized");
    assert!(
        schema.get("properties").is_none(),
        "remote schema was simplified"
    );
    assert_eq!(schema["$defs"]["Mode"]["enum"][2], "unarchived");
    let mut tools = Vec::new();
    for mode in [
        "success",
        "error",
        "unarchived",
        "structured_error",
        "missing_structure",
    ] {
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
    assert!(
        lease.authorization() != replacement.authorization(),
        "changing the configured process environment changes the authorization scope"
    );
    assert_eq!(replacement.tools()[0].exposed_name, descriptor.exposed_name);
    for (mode, prepared, tool) in tools {
        assert_eq!(tool.definition(), &definition);
        let checks = match mode {
            "success" => {
                "assert(ok and r.count==3 and #r.empty==0 and r.optional==json.null and r.content==nil and r.isError==nil)"
            }
            "error" => {
                "assert(not ok and r.output==nil and r.message:find('tool execution error', 1, true))"
            }
            "structured_error" => {
                "assert(not ok and r.output.reason=='invalid remote input' and r.output.count==nil and r.message:find('tool execution error', 1, true))"
            }
            "missing_structure" => {
                "assert(not ok and r.output==nil and r.message:find('structuredContent', 1, true))"
            }
            "unarchived" => "assert(not ok and r.output==nil)",
            _ => unreachable!(),
        };
        let code = format!(
            "local ok,r=pcall(tools[{:?}], args); {checks}; return 'checked'",
            definition.name()
        );
        let thread = ThreadHandle::start(
            format!("peer-{mode}"),
            DynModelSession::new(binding_host::Calls {
                calls: [(
                    "exec".into(),
                    serde_json::json!({"code":code, "args":{"mode":mode}}).to_string(),
                )]
                .into(),
                requests: Arc::new(Mutex::new(Vec::new())),
            }),
        )?;
        // This host deliberately exposes the endpoint immediately; no source-specific executor.
        let lua = pl_tool::lua::LuaTool::new("");
        let lua = prepare_registration("exec", lua.definition(), ToolCallPolicy::DirectOnly)?
            .attach(ToolHandle::new(lua))
            .with_nested_calls()
            .foreground();
        thread
            .register_tools(vec![lua, prepared.attach(tool).nested(false)])
            .await?;
        thread.run_turn(binding_host::turn(mode)).await?;
        let effects = thread.effects().await?;
        let parent = effects
            .iter()
            .flat_map(|effect| effect.deliveries.iter())
            .find(|delivery| delivery.tool_id == "exec")
            .unwrap();
        assert!(
            matches!(parent.outcome, ToolOutcome::Succeeded),
            "{mode}: {:?}",
            parent.output.data()
        );
        assert_eq!(parent.output.data().unwrap()["output"], "checked");
        let deliveries = effects
            .iter()
            .flat_map(|effect| effect.deliveries.iter())
            .filter(|delivery| delivery.tool_id == "binding.mcp")
            .collect::<Vec<_>>();
        assert_eq!(deliveries.len(), 1, "the binding must never retry the peer");
        let delivery = deliveries[0];
        if mode == "unarchived" {
            assert!(delivery.output.data().is_none());
            assert_eq!(
                delivery.output.details().unwrap()["content"][0]["resource"]["blob"],
                "Ynl0ZXM="
            );
            let ToolOutcome::Failed(error) = &delivery.outcome else {
                panic!("archive failure was lost")
            };
            assert!(error.source.downcast_ref::<ArchiveFailure>().is_some());
        } else if mode == "success" {
            assert_eq!(
                delivery.output.data(),
                Some(&serde_json::json!({"count": 3, "empty": [], "optional": null}))
            );
            assert_eq!(
                delivery.output.details().unwrap()["content"][0]["text"],
                "old:success"
            );
            assert!(
                delivery
                    .output
                    .details()
                    .unwrap()
                    .get("structuredContent")
                    .is_none()
            );
            assert!(matches!(delivery.outcome, ToolOutcome::Succeeded));
        } else {
            let details = delivery.output.details().unwrap();
            assert_eq!(details["content"][0]["text"], format!("old:{mode}"));
            assert_eq!(details["isError"], mode != "missing_structure");
            if mode == "structured_error" {
                assert_eq!(
                    delivery.output.data(),
                    Some(&serde_json::json!({"reason":"invalid remote input"}))
                );
            } else {
                assert!(delivery.output.data().is_none());
            }
            let ToolOutcome::Failed(error) = &delivery.outcome else {
                panic!("invalid MCP result lost its failure");
            };
            assert_eq!(
                error.kind(),
                pl_core::tool::opaque::ToolFailureKind::Invocation
            );
        }
        thread.close().await?;
    }
    drop(replacement);
    drop(lease);
    runtime.reconcile(servers("untyped")).await?;
    let untyped = published(&runtime, "untyped").await?;
    let descriptor = &untyped.tools()[0];
    let tool = ThreadMcpTool::new(
        untyped.clone(),
        &descriptor.exposed_name,
        Arc::new(FailedArchive),
    )?;
    assert!(tool.definition().output_schema().is_none());
    let declaration =
        prepare_registration("binding.mcp", tool.definition(), ToolCallPolicy::DirectOnly)?;
    let thread = ThreadHandle::start(
        "peer-untyped".into(),
        DynModelSession::new(binding_host::Calls {
            calls: [(
                "binding.mcp".into(),
                r#"{"mode":"missing_structure"}"#.into(),
            )]
            .into(),
            requests: Default::default(),
        }),
    )?;
    thread
        .register_tools(vec![declaration.attach(ToolHandle::new(tool))])
        .await?;
    thread
        .run_turn(binding_host::turn("untyped text-only success"))
        .await?;
    let effects = thread.effects().await?;
    let delivery = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .find(|delivery| delivery.tool_id == "binding.mcp")
        .unwrap();
    assert!(matches!(delivery.outcome, ToolOutcome::Succeeded));
    assert!(delivery.output.data().is_none());
    assert_eq!(
        delivery.output.details().unwrap()["content"][0]["text"],
        "untyped:missing_structure"
    );
    thread.close().await?;
    drop(untyped);
    runtime.shutdown().await?;
    let requests = std::fs::read_to_string(root.path().join("requests.jsonl"))?;
    let calls = requests
        .lines()
        .map(serde_json::from_str::<serde_json::Value>)
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .filter(|entry| entry["method"] == "tools/call")
        .collect::<Vec<_>>();
    assert_eq!(
        calls.len(),
        6,
        "archive errors must not resend a protocol call"
    );
    assert!(calls[..5].iter().all(|entry| entry["tag"] == "old"));
    assert_eq!(calls[5]["tag"], "untyped");
    Ok(())
}

#[tokio::test]
async fn independent_resource_tools_execute_only_on_frozen_resource_assignments()
-> anyhow::Result<()> {
    use pl_agent_tool::{Tool, typed};
    use pl_tool_mcp::support::McpContext;
    let root = tempfile::tempdir()?;
    let script =
        stdio::write_python_mcp_server(root.path(), "resources-peer.py", stdio::STDIO_MCP_SCRIPT);
    let log = root.path().join("requests.jsonl");
    let runtime = McpRuntime::new(McpConnector::default()).handle();
    let servers = |resources: bool| {
        BTreeMap::from([(
            "resources-peer".into(),
            stdio::stdio_effective_config(
                "resources-peer",
                &script,
                Vec::new(),
                BTreeMap::from([
                    ("MCP_BINDING_RESULTS".into(), "1".into()),
                    (
                        "MCP_SCHEMA_TAG".into(),
                        if resources { "resources" } else { "tools-only" }.into(),
                    ),
                    ("MCP_REQUEST_LOG".into(), log.to_string_lossy().into_owned()),
                    (
                        "MCP_NO_RESOURCES".into(),
                        if resources { "0" } else { "1" }.into(),
                    ),
                ]),
                Some(root.path().to_string_lossy().into_owned()),
                pl_tool::mcp::config::McpExecutionContext::Host,
            ),
        )])
    };
    runtime.reconcile(servers(false)).await?;
    let tools_only = published(&runtime, "tools-only").await?;
    assert!(!tools_only.has_resources());
    let listing = typed::prepare_json()?.attach(
        pl_tool_mcp::list_resources::ListMcpResources::new(tools_only.clone()),
    );
    let error = listing
        .execute("{}".into(), McpContext::default())
        .await
        .unwrap_err();
    assert!(error.to_string().contains("resource capability"));
    listing.close().await?;

    runtime.reconcile(servers(true)).await?;
    let lease = published(&runtime, "resources").await?;
    assert!(lease.has_resources());
    let listing = typed::prepare_json()?.attach(
        pl_tool_mcp::list_resources::ListMcpResources::new(lease.clone()),
    );
    let templates = typed::prepare_json()?
        .attach(pl_tool_mcp::list_resource_templates::ListMcpResourceTemplates::new(lease.clone()));
    assert_eq!(
        listing
            .execute("{}".into(), McpContext::default())
            .await?
            .protocol["resources"],
        serde_json::json!([])
    );
    assert_eq!(
        templates
            .execute("{}".into(), McpContext::default())
            .await?
            .protocol["resourceTemplates"],
        serde_json::json!([])
    );
    assert!(
        listing
            .execute(r#"{"server":"missing"}"#.into(), McpContext::default())
            .await
            .is_err()
    );
    assert!(
        templates
            .execute(r#"{"unexpected":true}"#.into(), McpContext::default())
            .await
            .is_err()
    );
    listing.close().await?;
    assert!(
        listing
            .execute("{}".into(), McpContext::default())
            .await
            .is_err()
    );
    // Closing one tool must not close the runtime or another tool's lease.
    assert!(
        templates
            .execute("{}".into(), McpContext::default())
            .await
            .is_ok()
    );

    struct DomainArchive;
    impl pl_tool_media_support::MediaHost for DomainArchive {
        type Reference = String;
        type Projection = ();
        type Error = ArchiveFailure;
        async fn retain(
            &self,
            media: pl_tool_media_support::Media,
        ) -> Result<pl_tool_media_support::Retained<String, ()>, Self::Error> {
            assert_eq!(media.bytes.as_ref(), b"bytes");
            Err(ArchiveFailure)
        }
    }
    let read = typed::prepare_json()?.attach(pl_tool_mcp::read_resource::ReadMcpResource::new(
        lease.clone(),
        Arc::new(DomainArchive),
    ));
    let output = read
        .execute(
            r#"{"server":"resources-peer","uri":"test://doc"}"#.into(),
            McpContext::default(),
        )
        .await?;
    assert_eq!(output.protocol["contents"][0]["text"], "hello");
    let error = read
        .execute(
            r#"{"server":"resources-peer","uri":"test://blob"}"#.into(),
            McpContext::default(),
        )
        .await
        .unwrap_err();
    let typed::InvocationError::Tool(error) = error else {
        panic!("resource did not execute")
    };
    assert!(error.source.downcast_ref::<ArchiveFailure>().is_some());
    assert!(
        matches!(error.observed, Some(pl_tool_mcp::support::Observed::Unarchived { protocol, .. })
        if protocol["contents"][0]["blob"] == "Ynl0ZXM=")
    );
    read.close().await?;
    templates.close().await?;
    drop((lease, tools_only));
    runtime.shutdown().await?;
    let requests = std::fs::read_to_string(log)?
        .lines()
        .map(serde_json::from_str::<serde_json::Value>)
        .collect::<Result<Vec<_>, _>>()?;
    let queries = requests
        .iter()
        .filter(|entry| {
            entry["method"]
                .as_str()
                .is_some_and(|method| method.starts_with("resources/"))
        })
        .collect::<Vec<_>>();
    assert_eq!(queries.len(), 5);
    assert!(queries.iter().all(|entry| entry["tag"] == "resources"));
    assert_eq!(
        queries
            .iter()
            .filter(|entry| entry["method"] == "resources/read")
            .count(),
        2,
        "local archive failure must not re-read the remote resource"
    );
    Ok(())
}
