#![cfg(target_os = "linux")]
//! Real Thread catalog publication, beyond the registry/host-binding tests in pl-tool.
#[expect(dead_code, reason = "shared isolated runtime fixtures")]
mod support;

use anyhow::{Context, Result, ensure};
use pl_protocol::{
    ThreadWorkspaceMode, TurnState,
    studio::{StudioPromptInput, SubmitPromptRequest},
};
use pl_provider_fixture::{Protocol, Reply, Step};
use pl_studio_runtime::{
    StudioLspServerState, StudioLspStateSnapshot, StudioProductBaselineState,
    StudioProductEventKind, StudioProductFrame, StudioProductTopic, StudioProductTopicSubscription,
    StudioThreadLspStateSnapshot,
};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};
use support::{Environment, program_reply, prompt_step, receipt, text_reply, tool_reply};

const REPAIR_PATH: &str = ".anywork/lsp/fixture.toml";
const CATALOG_ATTEMPTS: usize = 16;

fn fixture_configuration() -> Result<String> {
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .context("crate parent")?
        .join("pl-tool/tests/support/lsp_fixture.py");
    ensure!(fixture.is_file(), "missing shared LSP peer: {fixture:?}");
    Ok(format!(
        "schema_version = 1\nid = 'fixture'\ncommand = 'python3'\n\
         args = {}\nlanguage_ids = ['fixture']\nextensions = ['fixture']\n\
         operations = ['hover']\n",
        serde_json::to_string(&[
            "-u".to_owned(),
            fixture.display().to_string(),
            "{workspaceRoot}/lsp-requests.jsonl".to_owned(),
        ])?
    ))
}

fn after(steps: &mut Vec<Step>, call: &str, marker: &str, reply: Reply) {
    steps.push(Step::tool_output(
        Protocol::ResponsesHttp,
        call,
        marker,
        steps.len(),
        reply,
    ));
}

fn script(configuration: &str, shell: bool) -> Vec<Step> {
    let mut steps = vec![
        prompt_step(
            "plain",
            0,
            text_reply("ordinary conversation works", "plain"),
        ),
        prompt_step(
            "inspect failure",
            1,
            tool_reply("discover_tools", "failed-discovery", json!({"query":"lsp"})),
        ),
    ];
    after(
        &mut steps,
        "failed-discovery",
        "lsp_status",
        program_reply("lsp_status", "failed-status", json!({})),
    );
    after(
        &mut steps,
        "failed-status",
        "failed",
        program_reply("stat_path", "ordinary-stat", json!({"path":"tracked.txt"})),
    );
    after(
        &mut steps,
        "ordinary-stat",
        "true",
        text_reply("failure is isolated", "inspected"),
    );
    let repair = if shell {
        program_reply(
            "exec_command",
            "repair-file",
            json!({"command":format!(
                "python3 - <<'PY'\nfrom pathlib import Path\nPath({}).write_text({})\nprint({})\nPY",
                serde_json::to_string(REPAIR_PATH).unwrap(),
                serde_json::to_string(configuration).unwrap(),
                serde_json::to_string(REPAIR_PATH).unwrap(),
            )}),
        )
    } else {
        program_reply(
            "write_file",
            "repair-file",
            json!({"path":REPAIR_PATH,"mode":"overwrite","content":configuration}),
        )
    };
    steps.push(prompt_step("repair configuration", steps.len(), repair));
    after(
        &mut steps,
        "repair-file",
        REPAIR_PATH,
        text_reply("configuration repaired", "repaired"),
    );

    // The published LSP Ready event is not a catalog-installation barrier. Observe the
    // actual Thread directory on bounded model round trips, not by guessing a sleep.
    // Unused alternatives can be skipped, but the test must observe a successful probe.
    for attempt in 0..CATALOG_ATTEMPTS {
        let prompt = format!("inspect repaired catalog {attempt}");
        let call = format!("repaired-discovery-{attempt}");
        steps.push(
            prompt_step(
                &prompt,
                steps.len(),
                tool_reply("discover_tools", &call, json!({"query":"lsp"})),
            )
            .optional(),
        );
        steps.push(
            Step::tool_output(
                Protocol::ResponsesHttp,
                &call,
                "lsp_status",
                steps.len(),
                text_reply("catalog observed", &format!("catalog-{attempt}")),
            )
            .optional(),
        );
    }
    steps.push(prompt_step(
        "query repaired server",
        steps.len(),
        program_reply("lsp_status", "mixed-status", json!({})),
    ));
    after(
        &mut steps,
        "mixed-status",
        "ready",
        program_reply("lsp_capabilities", "healthy-capabilities", json!({})),
    );
    after(
        &mut steps,
        "healthy-capabilities",
        "fixture",
        program_reply(
            "lsp_query",
            "real-hover",
            json!({
                "languageId":"fixture","operation":"hover",
                "filePath":"source.fixture","line":2,"character":3
            }),
        ),
    );
    after(
        &mut steps,
        "real-hover",
        "fixture hover",
        text_reply("semantic query works", "queried"),
    );
    steps
}

async fn submit(env: &Environment, thread: &str, prompt: &str) -> Result<()> {
    let revision = env
        .runtime
        .thread_snapshot(thread)
        .await?
        .model_route
        .context("frozen model route")?
        .revision;
    env.runtime
        .submit_prompt_command(
            thread.to_owned(),
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
    completed(env, thread, prompt).await
}

async fn completed(env: &Environment, thread: &str, prompt: &str) -> Result<()> {
    let turn = support::completed_prompt(&env.runtime, thread, prompt).await?;
    ensure!(
        matches!(turn.state, TurnState::Completed(_)),
        "{prompt}: unexpected terminal state {:?}",
        turn.state
    );
    Ok(())
}

fn has_state(snapshot: &StudioLspStateSnapshot, id: &str, ready: bool) -> bool {
    snapshot.state.value().is_some_and(|health| {
        health.lsp_servers.iter().any(|server| {
            server.id == id
                && if ready {
                    matches!(server.state, StudioLspServerState::Available(_))
                } else {
                    matches!(server.state, StudioLspServerState::Unavailable(_))
                }
        })
    })
}

async fn wait_lsp(
    subscription: &mut StudioProductTopicSubscription,
    id: &str,
    ready: bool,
) -> Result<()> {
    // The caller's one watchdog covers every event, including unrelated transitions.
    loop {
        let snapshot = match subscription.recv().await?.context("LSP topic closed")? {
            StudioProductFrame::Baseline(baseline) => match baseline.state {
                StudioProductBaselineState::Lsp(snapshot) => snapshot,
                other => anyhow::bail!("unexpected LSP baseline: {other:?}"),
            },
            StudioProductFrame::Event(event) => match event.kind {
                StudioProductEventKind::LspStateChanged(snapshot) => Box::new(snapshot),
                other => anyhow::bail!("unexpected LSP event: {other:?}"),
            },
            StudioProductFrame::Lagged { dropped, .. } => {
                anyhow::bail!("LSP fixture subscription lost {dropped} events")
            }
        };
        if has_state(&snapshot, id, ready) {
            return Ok(());
        }
    }
}

async fn wait_lsp_revision(
    subscription: &mut StudioProductTopicSubscription,
    id: &str,
    after_revision: u64,
) -> Result<()> {
    loop {
        let snapshot = match subscription.recv().await?.context("LSP topic closed")? {
            StudioProductFrame::Baseline(baseline) => match baseline.state {
                StudioProductBaselineState::Lsp(snapshot) => snapshot,
                other => anyhow::bail!("unexpected LSP baseline: {other:?}"),
            },
            StudioProductFrame::Event(event) => match event.kind {
                StudioProductEventKind::LspStateChanged(snapshot) => Box::new(snapshot),
                other => anyhow::bail!("unexpected LSP event: {other:?}"),
            },
            StudioProductFrame::Lagged { dropped, .. } => {
                anyhow::bail!("LSP fixture subscription lost {dropped} events")
            }
        };
        if snapshot.state.revision() > after_revision && has_state(&snapshot, id, true) {
            return Ok(());
        }
    }
}

async fn wait_thread_lsp(
    subscription: &mut StudioProductTopicSubscription,
    expected_ids: &[&str],
) -> Result<StudioThreadLspStateSnapshot> {
    loop {
        let snapshot = match subscription
            .recv()
            .await?
            .context("Thread LSP topic closed")?
        {
            StudioProductFrame::Baseline(baseline) => match baseline.state {
                StudioProductBaselineState::ThreadLsp(snapshot) => *snapshot,
                other => anyhow::bail!("unexpected Thread LSP baseline: {other:?}"),
            },
            StudioProductFrame::Event(event) => match event.kind {
                StudioProductEventKind::ThreadLspStateChanged(snapshot) => snapshot,
                other => anyhow::bail!("unexpected Thread LSP event: {other:?}"),
            },
            StudioProductFrame::Lagged { dropped, .. } => {
                anyhow::bail!("Thread LSP fixture subscription lost {dropped} events")
            }
        };
        if snapshot.binding_id.is_some() {
            let mut actual = snapshot
                .servers
                .iter()
                .map(|server| server.id.as_str())
                .collect::<Vec<_>>();
            actual.sort_unstable();
            let mut expected = expected_ids.to_vec();
            expected.sort_unstable();
            if actual == expected {
                return Ok(snapshot);
            }
        }
    }
}

fn tool_ids(env: &Environment, call: &str) -> Result<Vec<String>> {
    serde_json::from_value(receipt(&env.root_provider, call)?["toolIds"].clone())
        .context("actual discover_tools result")
}

fn server<'a>(status: &'a Value, id: &str) -> Result<&'a Value> {
    status["servers"]
        .as_array()
        .context("status servers")?
        .iter()
        .find(|server| server["id"] == id)
        .with_context(|| format!("status did not expose {id}: {status}"))
}

#[tokio::test]
async fn failed_lsp_configuration_isolated_and_repaired_in_the_same_real_thread() -> Result<()> {
    configuration_journey(false).await
}

#[tokio::test]
async fn shell_configuration_publishes_servers_and_tools_in_the_same_real_thread() -> Result<()> {
    configuration_journey(true).await
}

async fn configuration_journey(shell: bool) -> Result<()> {
    let deadline = support::integration_test_deadline()?;
    let configuration = fixture_configuration()?;
    let env = Environment::new(script(&configuration, shell), Vec::new()).await?;
    let observed = tokio::time::timeout(deadline, async {
        let directory = env.repo.join(".anywork/lsp");
        std::fs::create_dir_all(&directory)?;
        if !shell {
            std::fs::write(env.repo.join(REPAIR_PATH), "schema_version = [broken TOML")?;
        }
        std::fs::write(
            directory.join("missing.toml"),
            "schema_version = 1\nid = 'missing'\n\
             command = 'anywork-integration-nonexistent-lsp-program'\n\
             language_ids = ['missing']\nextensions = ['missing']\n",
        )?;
        std::fs::write(env.repo.join("source.fixture"), "line one\nline two\n")?;
        let mut events = env
            .runtime
            .subscribe_product_topic(StudioProductTopic::Lsp)
            .await?;
        // Do not configure/probe the registry directly: Thread assembly owns discovery.
        let started = env.start(ThreadWorkspaceMode::Local, "plain").await?;
        let thread = &started.thread.id;
        ensure!(PathBuf::from(&started.thread.workspace_path) == env.repo);
        completed(&env, thread, "plain").await?;
        if !shell {
            wait_lsp(&mut events, "fixture", false).await?;
        }
        // A fresh subscription includes the latest baseline even if both failures coalesced.
        events = env
            .runtime
            .subscribe_product_topic(StudioProductTopic::Lsp)
            .await?;
        wait_lsp(&mut events, "missing", false).await?;
        let mut thread_lsp = env
            .runtime
            .subscribe_product_topic(StudioProductTopic::ThreadLsp {
                thread_id: thread.clone(),
            })
            .await?;
        let failed_ids: &[&str] = if shell {
            &["missing"]
        } else {
            &["fixture", "missing"]
        };
        let association = wait_thread_lsp(&mut thread_lsp, failed_ids).await?;
        ensure!(association.thread_id == *thread);
        ensure!(
            association
                .binding_id
                .as_deref()
                .is_some_and(|id| !id.is_empty())
        );
        ensure!(association.revision > 0);

        submit(&env, thread, "inspect failure").await?;
        ensure!(tool_ids(&env, "failed-discovery")? == ["lsp_status"]);
        let status = receipt(&env.root_provider, "failed-status")?;
        ensure!(
            PathBuf::from(status["workspaceRoot"].as_str().context("status root")?) == env.repo
        );
        for &id in failed_ids {
            let failed = server(&status, id)?;
            ensure!(failed["phase"] == "failed", "{failed}");
            ensure!(
                ["message", "lastError"]
                    .iter()
                    .any(|field| failed[*field].as_str().is_some_and(|text| !text.is_empty())),
                "failure must be actionable: {failed}"
            );
            ensure!(
                failed["configurationPath"]
                    .as_str()
                    .is_some_and(|path| Path::new(path) == directory.join(format!("{id}.toml"))),
                "failure must identify its source: {failed}"
            );
        }
        ensure!(receipt(&env.root_provider, "ordinary-stat")?["exists"] == true);

        // Real file and shell writes must trigger reloading; no test-owned registry refresh,
        // runtime restart, new Thread or explicit GUI reload is allowed here.
        events = env
            .runtime
            .subscribe_product_topic(StudioProductTopic::Lsp)
            .await?;
        submit(&env, thread, "repair configuration").await?;
        ensure!(std::fs::read_to_string(env.repo.join(REPAIR_PATH))? == configuration);
        wait_lsp(&mut events, "fixture", true).await?;
        let published = wait_thread_lsp(&mut thread_lsp, &["fixture", "missing"]).await?;
        ensure!(published.binding_id == association.binding_id);
        let expected = ["lsp_capabilities", "lsp_query", "lsp_status"];
        let mut recovered = false;
        for attempt in 0..CATALOG_ATTEMPTS {
            submit(&env, thread, &format!("inspect repaired catalog {attempt}")).await?;
            let mut actual = tool_ids(&env, &format!("repaired-discovery-{attempt}"))?;
            actual.sort();
            if actual == expected {
                recovered = true;
                break;
            }
            ensure!(
                actual == ["lsp_status"],
                "unexpected LSP catalog: {actual:?}"
            );
        }
        ensure!(
            recovered,
            "healthy server never reached the actual Thread tool catalog"
        );
        submit(&env, thread, "query repaired server").await?;
        let mixed = receipt(&env.root_provider, "mixed-status")?;
        ensure!(server(&mixed, "fixture")?["phase"] == "ready");
        ensure!(server(&mixed, "missing")?["phase"] == "failed");
        let capabilities = receipt(&env.root_provider, "healthy-capabilities")?;
        let healthy = capabilities["servers"]
            .as_array()
            .context("healthy capabilities")?;
        ensure!(healthy.len() == 1 && healthy[0]["id"] == "fixture" && healthy[0]["ready"] == true);
        let hover = receipt(&env.root_provider, "real-hover")?;
        ensure!(
            hover["success"] == true
                && hover["operation"] == "hover"
                && hover["serverId"] == "fixture"
        );
        ensure!(
            hover["result"]
                .as_str()
                .is_some_and(|text| text.contains("fixture hover"))
        );

        let binding = association
            .binding_id
            .clone()
            .context("current Thread LSP binding ID")?;
        let before_reset_revision = env.runtime.read_lsp_state().await.state.revision();
        let mut reset_events = env
            .runtime
            .subscribe_product_topic(StudioProductTopic::Lsp)
            .await?;
        let reset = env
            .runtime
            .reset_thread_lsp_server(pl_protocol::studio::ThreadLspResetRequest {
                thread_id: thread.clone(),
                binding_id: binding.clone(),
                server_id: "fixture".into(),
            })
            .await?;
        ensure!(reset.binding_id.as_deref() == Some(binding.as_str()));
        ensure!(
            reset
                .servers
                .iter()
                .map(|server| server.id.as_str())
                .collect::<std::collections::BTreeSet<_>>()
                == ["fixture", "missing"].into_iter().collect()
        );
        ensure!(
            reset
                .servers
                .iter()
                .find(|server| server.id == "missing")
                .is_some_and(|server| server.phase == "failed"),
            "reset of fixture must not reset the neighboring missing server"
        );
        wait_lsp_revision(&mut reset_events, "fixture", before_reset_revision).await?;
        let after_reset = env.runtime.read_thread_lsp_state(thread).await?;
        ensure!(after_reset.binding_id.as_deref() == Some(binding.as_str()));
        ensure!(
            after_reset
                .servers
                .iter()
                .find(|server| server.id == "missing")
                .is_some_and(|server| server.phase == "failed"),
            "neighboring server state must remain in the Thread projection"
        );

        // Deferred declarations must really have reached the provider, not just a registry view.
        let requests = env.root_provider.recorded();
        ensure!(requests.iter().any(|request| {
            request.body["tools"].as_array().is_some_and(|tools| {
                tools.iter().any(|tool| {
                    tool["name"] == "exec"
                        && tool["description"]
                            .as_str()
                            .is_some_and(|sdk| sdk.contains("tools[\"lsp_query\"]"))
                })
            })
        }));
        let messages = std::fs::read_to_string(env.repo.join("lsp-requests.jsonl"))?
            .lines()
            .map(serde_json::from_str::<Value>)
            .collect::<std::result::Result<Vec<_>, _>>()?;
        ensure!(
            messages
                .iter()
                .any(|message| message["method"] == "initialized")
        );
        ensure!(
            messages
                .iter()
                .any(|message| message["method"] == "textDocument/hover")
        );
        Ok(())
    })
    .await
    .context("real Thread LSP journey exceeded integration watchdog")
    .and_then(|result| result);
    // Cleanup runs after assertions, model failures and timeout alike.
    env.finish(observed).await
}
