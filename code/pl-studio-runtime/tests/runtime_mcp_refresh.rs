//! The real model -> Thread registration -> configuration owner -> MCP peer -> hot catalog path.
#[expect(
    dead_code,
    reason = "reuse the production protocol peer used by pl-tool tests"
)]
#[path = "../../pl-tool/tests/support/mcp_stdio.rs"]
mod mcp_stdio;
#[expect(dead_code, reason = "shared isolated runtime fixtures")]
mod support;

use anyhow::{Context, Result, ensure};
use pl_protocol::{
    CreateMcpDocumentRequest, DeleteMcpDocumentRequest, McpScope, ThreadMcpLifecycleKind,
    ThreadWorkspaceMode, TurnState, UpdateMcpDocumentRequest,
    studio::{StudioPromptInput, SubmitPromptRequest},
};
use pl_provider_fixture::{Protocol, Step};
use pl_studio_runtime::{
    StudioProductBaselineState, StudioProductEventKind, StudioProductFrame, StudioProductTopic,
};
use serde_json::json;
use support::{Environment, prompt_step, receipt, text_reply, tool_output, tool_reply};

const TOOL: &str = "mcp__fixture__inspect_env";
const ATTEMPTS: usize = 16;

fn after(steps: &mut Vec<Step>, call: &str, marker: &str, reply: pl_provider_fixture::Reply) {
    steps.push(Step::tool_output(
        Protocol::ResponsesHttp,
        call,
        marker,
        steps.len(),
        reply,
    ));
}

fn probes(steps: &mut Vec<Step>, phase: &str) {
    // Directory installation is asynchronous. Observe its actual model-facing output,
    // using bounded real Turns (no sleep/poll of internal state and no installation claim).
    for attempt in 0..ATTEMPTS {
        let call = format!("{phase}-{attempt}");
        steps.push(
            prompt_step(
                &call,
                steps.len(),
                tool_reply("discover_tools", &call, json!({"query": TOOL})),
            )
            .optional(),
        );
        steps.push(
            Step::tool_output(
                Protocol::ResponsesHttp,
                &call,
                "toolIds",
                steps.len(),
                text_reply("catalog observed", &call),
            )
            .optional(),
        );
    }
}

fn script() -> Vec<Step> {
    let mut steps = vec![prompt_step(
        "empty",
        0,
        tool_reply(
            "discover_tools",
            "empty-discovery",
            json!({"query":"refresh_mcp"}),
        ),
    )];
    after(
        &mut steps,
        "empty-discovery",
        "refresh_mcp",
        tool_reply("refresh_mcp", "empty-refresh", json!({})),
    );
    after(
        &mut steps,
        "empty-refresh",
        "refreshScheduled",
        text_reply("empty refreshed", "empty"),
    );
    steps.push(prompt_step(
        "invalid",
        steps.len(),
        tool_reply(
            "refresh_mcp",
            "invalid-refresh",
            json!({"threadId":"another-thread"}),
        ),
    ));
    after(
        &mut steps,
        "invalid-refresh",
        "unknown field",
        text_reply("override rejected", "invalid"),
    );
    for phase in ["created", "saved"] {
        probes(&mut steps, phase);
        let call = format!("call-{phase}");
        steps.push(prompt_step(
            &call,
            steps.len(),
            tool_reply(TOOL, &call, json!({"mode":"success"})),
        ));
        after(&mut steps, &call, phase, text_reply("MCP called", &call));
        if phase == "created" {
            steps.push(prompt_step(
                "refresh-live",
                steps.len(),
                tool_reply("refresh_mcp", "live-refresh", json!({})),
            ));
            after(
                &mut steps,
                "live-refresh",
                "refreshScheduled",
                text_reply("live connection refreshed", "refresh-live"),
            );
        }
    }
    steps.push(prompt_step(
        "refresh-disk",
        steps.len(),
        tool_reply("refresh_mcp", "disk-refresh", json!({})),
    ));
    after(
        &mut steps,
        "disk-refresh",
        "refreshScheduled",
        text_reply("disk refreshed", "refresh-disk"),
    );
    probes(&mut steps, "disabled");
    probes(&mut steps, "reloaded");
    steps.push(prompt_step(
        "call-reloaded",
        steps.len(),
        tool_reply(TOOL, "call-reloaded", json!({"mode":"success"})),
    ));
    after(
        &mut steps,
        "call-reloaded",
        "reloaded",
        text_reply("MCP called", "call-reloaded"),
    );
    probes(&mut steps, "deleted");
    steps
}

async fn completed(env: &Environment, id: &str, prompt: &str) -> Result<()> {
    let turn = support::completed_prompt(&env.runtime, id, prompt).await?;
    ensure!(
        matches!(turn.state, TurnState::Completed(_)),
        "{prompt}: unexpected terminal state {:?}",
        turn.state
    );
    Ok(())
}

async fn submit(env: &Environment, id: &str, prompt: &str) -> Result<()> {
    let turn = submit_turn(env, id, prompt).await?;
    ensure!(
        matches!(turn.state, TurnState::Completed(_)),
        "{prompt}: unexpected terminal state {:?}",
        turn.state
    );
    Ok(())
}

async fn submit_turn(env: &Environment, id: &str, prompt: &str) -> Result<pl_protocol::Turn> {
    let revision = env
        .runtime
        .thread_snapshot(id)
        .await?
        .model_route
        .context("frozen model route")?
        .revision;
    env.runtime
        .submit_prompt_command(
            id.to_owned(),
            SubmitPromptRequest {
                input: StudioPromptInput {
                    input_id: format!("input-{prompt}"),
                    text: prompt.to_owned(),
                    attachment_draft_ids: Vec::new(),
                },
                expected_model_route_revision: revision,
            },
        )
        .await?;
    support::completed_prompt(&env.runtime, id, prompt).await
}

async fn catalog(env: &Environment, id: &str, phase: &str, present: bool) -> Result<()> {
    for attempt in 0..ATTEMPTS {
        let call = format!("{phase}-{attempt}");
        let turn = submit_turn(env, id, &call).await?;
        if let TurnState::Failed(failed) = &turn.state {
            // Runtime publication is not an installation barrier. A configuration replacement
            // may revoke a frozen model plan before the hot catalog is installed. Preserve that
            // exact hard refusal; no MCP call is retried and all other failures remain fatal.
            ensure!(
                failed.failure().message
                    == pl_core::thread::ModelOutputViolation::ToolPermissionRevoked.to_string(),
                "{call}: unexpected failed Turn: {failed:?}"
            );
            continue;
        }
        ensure!(
            matches!(turn.state, TurnState::Completed(_)),
            "{call}: unexpected terminal state {:?}",
            turn.state
        );
        let ids: Vec<String> =
            serde_json::from_value(receipt(&env.root_provider, &call)?["toolIds"].clone())?;
        let schema_installed = !present
            || env
                .root_provider
                .recorded()
                .last()
                .and_then(|request| request.body["tools"].as_array())
                .is_some_and(|tools| {
                    tools.iter().any(|tool| {
                        tool["name"] == TOOL && tool["parameters"]["description"] == phase
                    })
                });
        if ids.iter().any(|name| name == TOOL) == present && schema_installed {
            return Ok(());
        }
    }
    anyhow::bail!("{phase}: real Thread catalog never reached presence={present}")
}

async fn state(env: &Environment, id: &str, present: bool, after: u64) -> Result<()> {
    let mut events = env
        .runtime
        .subscribe_product_topic(StudioProductTopic::ThreadMcp {
            thread_id: id.into(),
        })
        .await?;
    loop {
        let snapshot = match events.recv().await?.context("MCP topic ended")? {
            StudioProductFrame::Baseline(baseline) => match baseline.state {
                StudioProductBaselineState::ThreadMcp(snapshot) => *snapshot,
                other => anyhow::bail!("unexpected baseline: {other:?}"),
            },
            StudioProductFrame::Event(event) => match event.kind {
                StudioProductEventKind::ThreadMcpStateChanged(snapshot) => snapshot,
                other => anyhow::bail!("unexpected event: {other:?}"),
            },
            StudioProductFrame::Lagged { dropped, .. } => {
                anyhow::bail!("lost {dropped} MCP events")
            }
        };
        let server = snapshot
            .servers
            .iter()
            .find(|server| server.id == "fixture");
        if snapshot.generation > after
            && if present {
                server.is_some_and(|server| server.lifecycle == ThreadMcpLifecycleKind::Available)
            } else {
                server.is_none()
            }
        {
            return Ok(());
        }
    }
}

fn configuration(env: &Environment, tag: &str, enabled: bool) -> Result<String> {
    Ok(format!(
        "schema_version = 1\nid = 'fixture'\nkind = 'server'\nenabled = {enabled}\n\
         transport = 'stdio'\ncommand = 'python3'\nargs = {}\nstartup_timeout_secs = 5\n\
         tool_timeout_secs = 5\n[env]\nSPECIAL_ENV = '{tag}'\nMCP_NO_RESOURCES = '1'\n\
         MCP_BINDING_RESULTS = '1'\nMCP_SCHEMA_TAG = '{tag}'\n\
         MCP_REQUEST_LOG = {}\n",
        serde_json::to_string(&[
            "-u".to_owned(),
            env.repo.join("peer.py").display().to_string()
        ])?,
        serde_json::to_string(&env.repo.join("mcp-requests.jsonl").display().to_string())?,
    ))
}

#[tokio::test]
async fn real_thread_refresh_and_config_mutations_update_callable_mcp_catalog() -> Result<()> {
    let env = Environment::new(script(), Vec::new()).await?;
    let result = tokio::time::timeout(support::integration_test_deadline()?, async {
        std::fs::write(env.repo.join("peer.py"), mcp_stdio::STDIO_MCP_SCRIPT)?;
        let started = env.start(ThreadWorkspaceMode::Local, "empty").await?;
        let id = &started.thread.id;
        completed(&env, id, "empty").await?;
        let empty = receipt(&env.root_provider, "empty-refresh")?;
        ensure!(empty["scope"]["kind"] == "host" && empty["toolCatalog"] == "refreshScheduled");
        ensure!(
            empty["discovery"]["servers"]
                .as_array()
                .context("discovery servers")?
                .is_empty()
        );
        submit(&env, id, "invalid").await?;
        ensure!(tool_output(&env.root_provider, "invalid-refresh")?.contains("unknown field"));
        ensure!(env.runtime.read_thread_mcp("another-thread").await.is_err());

        let created = env
            .runtime
            .create_mcp_document(&CreateMcpDocumentRequest {
                scope: McpScope::Host,
                id: "fixture".into(),
                raw_toml: configuration(&env, "created", true)?,
            })
            .await?;
        state(&env, id, true, 0).await?;
        catalog(&env, id, "created", true).await?;
        submit(&env, id, "call-created").await?;
        ensure!(tool_output(&env.root_provider, "call-created")?.contains("created"));
        submit(&env, id, "refresh-live").await?;
        let live = receipt(&env.root_provider, "live-refresh")?;
        ensure!(
            live["discovery"]["servers"]
                .as_array()
                .context("live discovery")?
                .iter()
                .any(|server| server["serverId"] == "fixture"
                    && server["status"] == "unchanged"
                    && server["toolCount"] == 1)
        );
        let requests = std::fs::read_to_string(env.repo.join("mcp-requests.jsonl"))?
            .lines()
            .map(serde_json::from_str::<serde_json::Value>)
            .collect::<std::result::Result<Vec<_>, _>>()?;
        ensure!(
            requests
                .iter()
                .filter(|request| request["method"] == "tools/list")
                .count()
                >= 2,
            "refresh must issue a fresh tools/list over the existing connection"
        );
        let pids = requests
            .iter()
            .filter_map(|request| request["pid"].as_u64())
            .collect::<std::collections::BTreeSet<_>>();
        ensure!(
            pids.len() == 1,
            "refresh restarted an unchanged MCP peer: {pids:?}"
        );
        let before_save = env.runtime.read_thread_mcp(id).await?.generation;
        let saved = env
            .runtime
            .update_mcp_document(&UpdateMcpDocumentRequest {
                document: created.document.context("created document")?,
                expected_revision: created.revision,
                raw_toml: configuration(&env, "saved", true)?,
            })
            .await?;
        state(&env, id, true, before_save).await?;
        catalog(&env, id, "saved", true).await?;
        submit(&env, id, "call-saved").await?;
        ensure!(tool_output(&env.root_provider, "call-saved")?.contains("saved"));

        let document = saved.document.context("saved document")?;
        let path = env.home.join(&document.relative_path);
        std::fs::write(&path, configuration(&env, "disabled", false)?)?;
        submit(&env, id, "refresh-disk").await?;
        let refreshed = receipt(&env.root_provider, "disk-refresh")?;
        ensure!(refreshed["catalogRevision"].as_u64() > empty["catalogRevision"].as_u64());
        ensure!(
            refreshed["state"]["servers"]
                .as_array()
                .context("state servers")?
                .iter()
                .all(|server| server["id"] != "fixture")
        );
        catalog(&env, id, "disabled", false).await?;

        std::fs::write(&path, configuration(&env, "reloaded", true)?)?;
        env.runtime.reload_mcp_catalog(&McpScope::Host).await?;
        state(&env, id, true, 0).await?;
        catalog(&env, id, "reloaded", true).await?;
        submit(&env, id, "call-reloaded").await?;
        ensure!(tool_output(&env.root_provider, "call-reloaded")?.contains("reloaded"));
        env.runtime
            .delete_mcp_document(&DeleteMcpDocumentRequest {
                expected_revision: env.runtime.read_mcp_document(&document)?.revision,
                document,
            })
            .await?;
        state(&env, id, false, 0).await?;
        catalog(&env, id, "deleted", false).await?;
        Ok(())
    })
    .await
    .context("MCP integration watchdog")?;
    env.finish(result).await
}
