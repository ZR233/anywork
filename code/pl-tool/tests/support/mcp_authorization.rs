//! Real Thread admission against real local peers, not direct token comparison alone.
use super::{binding_host, helper, stdio};
use pl_agent_tool::ToolHandle;
use pl_core::{
    context::OpaquePayload,
    model::{
        DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput, ModelToolCall,
        PreparedModelCall,
    },
    thread::{ThreadError, ThreadHandle, ToolOutcome},
    tool::opaque::{Registration, ToolError},
};
use pl_tool::{
    binding::{ToolCallPolicy, prepare_registration},
    mcp::{
        McpConnector, McpResetScope, McpRuntime, McpRuntimeHandle, McpTurnLease,
        config::{EffectiveMcpServerConfig, McpExecutionContext, McpServerStatusKind},
        resources::{McpResourceToolKind, ThreadMcpResourceTool},
        thread::ThreadMcpTool,
    },
    media::{RetainedToolMedia, ToolMedia, ToolMediaHost},
};
use std::{collections::BTreeMap, path::Path, sync::Arc, time::Duration};
use tokio::sync::Notify;

#[tokio::test]
async fn target_effect_and_resource_assignment_changes_deny_old_calls_but_allow_new_calls()
-> anyhow::Result<()> {
    enum Change {
        Target,
        Effect,
        Resources,
    }
    for change in [Change::Target, Change::Effect, Change::Resources] {
        let root = tempfile::tempdir()?;
        let script =
            stdio::write_python_mcp_server(root.path(), "scope-peer.py", stdio::STDIO_MCP_SCRIPT);
        let runtime = runtime();
        let mut config = servers(root.path(), &script, true);
        runtime.reconcile(config.clone()).await?;
        let original = ready(&runtime, &["a", "b"]).await?;
        let started = Arc::new(Notify::new());
        let release = Arc::new(Notify::new());
        let thread = ThreadHandle::start(
            "scope-change".into(),
            DynModelSession::new(FrozenResponse {
                call: Some((
                    "read_mcp_resource".into(),
                    r#"{"server":"a","uri":"test://doc"}"#.into(),
                )),
                started: started.clone(),
                release: release.clone(),
            }),
        )?;
        thread.register_tools(resources(&original)?).await?;
        let running = {
            let thread = thread.clone();
            tokio::spawn(async move { thread.run_turn(binding_host::turn("scope")).await })
        };
        tokio::time::timeout(Duration::from_secs(10), started.notified()).await?;
        let current_server = match change {
            Change::Target => {
                config
                    .get_mut("a")
                    .unwrap()
                    .config
                    .args
                    .push("new-target".into());
                runtime.reconcile(config).await?;
                "a"
            }
            Change::Effect => {
                config.get_mut("a").unwrap().tool_effect =
                    Some(pl_tool::approval::ToolEffect::WorkspaceWrite);
                runtime.reconcile(config).await?;
                "a"
            }
            Change::Resources => {
                // Identical target and credentials; only negotiated resource assignment
                // changes. B keeps every facade name installed.
                std::fs::write(root.path().join("a.resources-enabled"), "0")?;
                runtime.reset(McpResetScope::All, config).await?;
                "b"
            }
        };
        let replacement = ready(&runtime, &["a", "b"]).await?;
        thread.register_tools(resources(&replacement)?).await?;
        release.notify_one();
        let outcome = running.await?;
        let effects = thread.effects().await?;
        thread.close().await?;
        let fresh = ThreadHandle::start(
            "fresh-scope".into(),
            DynModelSession::new(binding_host::Calls {
                calls: [(
                    "read_mcp_resource".into(),
                    format!(r#"{{"server":"{current_server}","uri":"test://doc"}}"#),
                )]
                .into(),
                requests: Default::default(),
            }),
        )?;
        fresh.register_tools(resources(&replacement)?).await?;
        let fresh_outcome = fresh.run_turn(binding_host::turn("current")).await;
        let fresh_effects = fresh.effects().await?;
        fresh.close().await?;
        drop((original, replacement));
        runtime.shutdown().await?;
        assert_eq!(outcome?.model_steps, 2);
        assert!(effects.iter().flat_map(|effect| effect.deliveries.iter()).any(|delivery|
            matches!(&delivery.outcome, ToolOutcome::Failed(error)
                if matches!(error.source.downcast_ref::<ThreadError>(), Some(ThreadError::ToolPermissionRevoked)))));
        fresh_outcome?;
        let delivery = fresh_effects
            .iter()
            .flat_map(|effect| effect.deliveries.iter())
            .find(|delivery| delivery.tool_id == "read_mcp_resource")
            .expect("the new authorized call must deliver the received resource");
        let received: serde_json::Value =
            serde_json::from_str(delivery.output.payload().content())?;
        assert_eq!(received["contents"][0]["text"], "hello");
        for id in ["a", "b"] {
            let count = requests(root.path(), id)?
                .iter()
                .filter(|request| request["method"] == "resources/read")
                .count();
            assert_eq!(
                count,
                usize::from(id == current_server),
                "only the fresh authorized plan may reach its peer"
            );
        }
    }
    Ok(())
}

#[derive(Debug)]
struct NoMedia;
impl ToolMediaHost for NoMedia {
    async fn retain(&self, _: ToolMedia) -> Result<RetainedToolMedia, ToolError> {
        panic!("these peers return only text and resource listings")
    }
}

struct FrozenResponse {
    call: Option<(String, String)>,
    started: Arc<Notify>,
    release: Arc<Notify>,
}

impl ModelSession for FrozenResponse {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let call = self.call.take();
        let started = self.started.clone();
        let release = self.release.clone();
        Ok(PreparedModelCall::new(async move {
            let calls = if let Some((tool_id, input)) = call {
                started.notify_one();
                release.notified().await;
                vec![ModelToolCall {
                    call_id: request.attempt_id.clone(),
                    tool_id,
                    arguments: OpaquePayload::new("application/json", 1, input).unwrap(),
                    rejection: None,
                    presentation_contract: None,
                }]
            } else {
                Vec::new()
            };
            Ok(ModelStepOutput {
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                tool_calls: calls,
                content: Vec::new(),
                private_context: None,
                turn_action: Default::default(),
                usage: Default::default(),
            })
        }))
    }
    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

fn runtime() -> McpRuntimeHandle {
    McpRuntime::new(
        McpConnector::default().with_stdio_worker(helper::remote_helper_executable().to_path_buf()),
    )
    .handle()
}

fn servers(
    root: &Path,
    script: &Path,
    resources_only: bool,
) -> BTreeMap<String, EffectiveMcpServerConfig> {
    ["a", "b"]
        .into_iter()
        .map(|id| {
            (
                id.into(),
                stdio::stdio_effective_config(
                    id,
                    script,
                    Vec::new(),
                    BTreeMap::from([
                        (
                            "MCP_REQUEST_LOG".into(),
                            root.join(format!("{id}.jsonl"))
                                .to_string_lossy()
                                .into_owned(),
                        ),
                        ("MCP_SCHEMA_TAG".into(), id.into()),
                        (
                            "MCP_RESOURCES_FLAG".into(),
                            root.join(format!("{id}.resources-enabled"))
                                .to_string_lossy()
                                .into_owned(),
                        ),
                        ("MCP_BINDING_RESULTS".into(), "1".into()),
                        (
                            "MCP_RESOURCES_ONLY".into(),
                            if resources_only { "1" } else { "0" }.into(),
                        ),
                    ]),
                    Some(root.to_string_lossy().into_owned()),
                    McpExecutionContext::Host,
                ),
            )
        })
        .collect()
}

async fn ready(runtime: &McpRuntimeHandle, expected: &[&str]) -> anyhow::Result<McpTurnLease> {
    let mut updates = runtime.subscribe();
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let lease = runtime.acquire_turn_lease().await?;
            if lease
                .server_ids()
                .iter()
                .map(String::as_str)
                .eq(expected.iter().copied())
            {
                return Ok(lease);
            }
            updates.recv().await?;
        }
    })
    .await?
}

fn resources(lease: &McpTurnLease) -> anyhow::Result<Vec<Registration>> {
    McpResourceToolKind::all()
        .iter()
        .map(|kind| {
            let definition = kind.definition();
            let prepared = prepare_registration(
                kind.name(),
                &definition,
                ToolCallPolicy::DirectAndProgrammatic,
            )?;
            let tool =
                ThreadMcpResourceTool::new(lease.clone(), *kind, Arc::new(NoMedia), definition);
            // Expose these host endpoints immediately so the fixture tests admission, not discovery.
            Ok(prepared
                .attach(ToolHandle::new(tool))
                .with_authorization(lease.authorization()))
        })
        .collect()
}

fn requests(root: &Path, id: &str) -> anyhow::Result<Vec<serde_json::Value>> {
    std::fs::read_to_string(root.join(format!("{id}.jsonl")))?
        .lines()
        .map(|line| serde_json::from_str(line).map_err(Into::into))
        .collect()
}

#[tokio::test]
async fn removed_or_disabled_resource_server_revokes_frozen_read_and_aggregate_list()
-> anyhow::Result<()> {
    for disable in [false, true] {
        let root = tempfile::tempdir()?;
        let script = stdio::write_python_mcp_server(
            root.path(),
            "authorization-peer.py",
            stdio::STDIO_MCP_SCRIPT,
        );
        let runtime = runtime();
        let mut config = servers(root.path(), &script, true);
        runtime.reconcile(config.clone()).await?;
        let original = ready(&runtime, &["a", "b"]).await?;
        assert!(
            original.tools().is_empty(),
            "resource-only peers must expose no dynamic tools"
        );
        let mut frozen = Vec::new();
        for (name, input) in [
            ("read_mcp_resource", r#"{"server":"a","uri":"test://doc"}"#),
            ("list_mcp_resources", "{}"),
        ] {
            let started = Arc::new(Notify::new());
            let release = Arc::new(Notify::new());
            let thread = ThreadHandle::start(
                format!("{name}-{disable}"),
                DynModelSession::new(FrozenResponse {
                    call: Some((name.into(), input.into())),
                    started: started.clone(),
                    release: release.clone(),
                }),
            )?;
            thread.register_tools(resources(&original)?).await?;
            let running = {
                let thread = thread.clone();
                tokio::spawn(async move { thread.run_turn(binding_host::turn("frozen")).await })
            };
            tokio::time::timeout(Duration::from_secs(10), started.notified()).await?;
            frozen.push((thread, release, running));
        }
        if disable {
            let server = config.get_mut("a").unwrap();
            server.status_kind = McpServerStatusKind::Disabled;
            server.config.enabled = false;
        } else {
            config.remove("a");
        }
        runtime.reconcile(config).await?;
        let replacement = ready(&runtime, &["b"]).await?;
        assert!(
            replacement.has_resources(),
            "B keeps every resource facade name installed"
        );
        let mut outcomes = Vec::new();
        for (thread, release, running) in frozen {
            thread.register_tools(resources(&replacement)?).await?;
            release.notify_one();
            outcomes.push((running.await?, thread.effects().await?));
            thread.close().await?;
        }
        drop((original, replacement));
        runtime.shutdown().await?;
        for (outcome, effects) in outcomes {
            assert_eq!(outcome?.model_steps, 2);
            assert!(effects.iter().flat_map(|effect| effect.deliveries.iter()).any(|delivery|
                matches!(&delivery.outcome, ToolOutcome::Failed(error)
                    if matches!(error.source.downcast_ref::<ThreadError>(), Some(ThreadError::ToolPermissionRevoked)))));
        }
        for id in ["a", "b"] {
            assert!(
                requests(root.path(), id)?
                    .iter()
                    .all(|request| !request["method"]
                        .as_str()
                        .unwrap_or("")
                        .starts_with("resources/")),
                "a revoked plan must not dispatch either an explicit read or aggregate query"
            );
        }
    }
    Ok(())
}

#[tokio::test]
async fn identical_transport_reset_keeps_frozen_thread_call_on_original_peer() -> anyhow::Result<()>
{
    let root = tempfile::tempdir()?;
    let script =
        stdio::write_python_mcp_server(root.path(), "transport-peer.py", stdio::STDIO_MCP_SCRIPT);
    let runtime = runtime();
    let mut config = servers(root.path(), &script, false);
    config.remove("b");
    runtime.reconcile(config.clone()).await?;
    let original = ready(&runtime, &["a"]).await?;
    let descriptor = &original.tools()[0];
    let name = descriptor.exposed_name.clone();
    let original_pid = requests(root.path(), "a")?
        .into_iter()
        .find(|request| request["method"] == "tools/list")
        .unwrap()["pid"]
        .clone();
    let started = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let thread = ThreadHandle::start(
        "unchanged-authorization".into(),
        DynModelSession::new(FrozenResponse {
            call: Some((name.clone(), r#"{"mode":"success"}"#.into())),
            started: started.clone(),
            release: release.clone(),
        }),
    )?;
    let registration = |lease: &McpTurnLease| -> anyhow::Result<Registration> {
        let definition = lease.tools()[0].definition()?;
        let prepared = prepare_registration(&name, &definition, ToolCallPolicy::DirectOnly)?;
        let tool = ThreadMcpTool::new(lease.clone(), &name, Arc::new(NoMedia))?;
        Ok(prepared
            .attach(ToolHandle::new(tool))
            .with_authorization(lease.authorization()))
    };
    thread
        .register_tools(vec![registration(&original)?])
        .await?;
    let running = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(binding_host::turn("transport")).await })
    };
    tokio::time::timeout(Duration::from_secs(10), started.notified()).await?;
    runtime.reset(McpResetScope::All, config).await?;
    let replacement = ready(&runtime, &["a"]).await?;
    assert_ne!(original.generation(), replacement.generation());
    assert!(original.authorization() == replacement.authorization());
    thread
        .register_tools(vec![registration(&replacement)?])
        .await?;
    release.notify_one();
    let outcome = running.await?;
    thread.close().await?;
    drop((original, replacement));
    runtime.shutdown().await?;
    outcome?;
    let requests = requests(root.path(), "a")?;
    let discovery_pids = requests
        .iter()
        .filter(|request| request["method"] == "tools/list")
        .map(|request| &request["pid"])
        .collect::<Vec<_>>();
    assert_eq!(discovery_pids.len(), 2);
    assert_ne!(
        discovery_pids[0], discovery_pids[1],
        "reset must create a real replacement transport"
    );
    let calls = requests
        .iter()
        .filter(|request| request["method"] == "tools/call")
        .collect::<Vec<_>>();
    assert_eq!(calls.len(), 1);
    assert_eq!(
        calls[0]["pid"], original_pid,
        "the admitted frozen plan must still use its original lease"
    );
    Ok(())
}
