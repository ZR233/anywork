//! Closed SQLite seed for the official conversation cold-read integration_test.
//!
//! Public Runtime APIs write real history, then the fixture and runtime shut
//! down before Flutter opens the same home. This module never edits SQLite or
//! copies a message stream.

use super::*;
use anyhow::{Context, Result, bail, ensure};
use pl_model::config::{AccountConfig, AccountId};
use pl_model::model::{ModelInfo, ModelTransportProfile};
use pl_model::protocol::ProtocolEndpoint;
use pl_protocol::studio::{
    CreateThreadRequest, NewThreadModelRoute, StudioPromptInput, SubmitPromptRequest,
};
use pl_protocol::{
    CHAT_BATCH_MAX_BYTES, CHAT_READ_MAX_ITEMS, ChatPlacement, ChatScope, ReadDemand,
    ThreadNotification, ThreadSubscriptionRequest, ThreadSubscriptionUpdate, ThreadWorkspaceMode,
};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
use pl_studio_runtime::{
    ConversationEvent, StudioHostKind, StudioRuntime, StudioRuntimeOptions,
    StudioThreadSubscription,
    config::{ConfigPaths, ConfigStore, StudioConfig},
};
use serde::Serialize;
use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::{Duration, Instant};

const MODEL: &str = "fixture-model";
const ACCOUNT: &str = "read-fixture";
const TURN_COUNT: usize = 24;
const THREAD_COUNT: usize = 2;

pub(super) struct ConversationReadWorkScenario<'a> {
    pub workspace: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    pub interrupt: &'a mpsc::Receiver<()>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ReadCase {
    name: String,
    thread_id: String,
    main_items: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    switch_thread_id: Option<String>,
}

pub(super) fn run(context: &ConversationReadWorkScenario<'_>) -> Result<()> {
    let ConversationReadWorkScenario {
        workspace,
        home,
        working,
        output,
        interrupt,
    } = context;
    let cases_path = output.join("read-cases.json");
    let report_path = output.join("read-report.json");
    let log_path = working.join("conversation-read-work-integration.log");
    let mut runner_exit = None;
    let suite = (|| -> Result<()> {
        let seeded = seed_closed_home(home, working)?;
        fs::write(&cases_path, serde_json::to_vec_pretty(&seeded)?)?;
        let log = File::create(&log_path)?;
        let mut command = Command::new("cargo");
        command
            .current_dir(workspace)
            .args([
                "xtask",
                "test-project",
                "--suite",
                "desktop",
                "--case",
                "conversation_read_work",
            ])
            .env("ANYWORK_HOME", home)
            .env("ANYWORK_READ_CASES", &cases_path)
            .env("ANYWORK_READ_REPORT", &report_path)
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));
        let mut runner = OwnedProcess::start(&mut command, false)?;
        let deadline = Instant::now() + Duration::from_secs(900);
        loop {
            if let Some(status) = runner.child.try_wait()? {
                runner.stopped = true;
                runner_exit = Some(status);
                ensure!(
                    status.success(),
                    "conversation read integration tests failed: {status}"
                );
                break;
            }
            ensure!(
                interrupt.try_recv().is_err(),
                "conversation read integration tests cancelled"
            );
            ensure!(
                Instant::now() < deadline,
                "conversation read integration tests timed out"
            );
            thread::sleep(Duration::from_millis(200));
        }
        Ok(())
    })();
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "conversation-read-work",
            "runner": "flutter.integration_test",
            "runnerExitCode": runner_exit.and_then(|status| status.code()),
            "completed": suite.is_ok(),
        }))?,
    )?;
    if log_path.is_file() {
        let _ = fs::copy(
            &log_path,
            output.join("conversation-read-work-integration.log"),
        );
    }
    suite?;
    println!(
        "conversation read integration evidence: {}",
        output.display()
    );
    Ok(())
}

fn seed_closed_home(home: &Path, working: &Path) -> Result<Vec<ReadCase>> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(Box::pin(seed_closed_home_async(home, working)))
}

async fn seed_closed_home_async(home: &Path, working: &Path) -> Result<Vec<ReadCase>> {
    let project = working.join("conversation-read-project");
    init_git_project(&project)?;
    let thread_ids = Box::pin(write_history(home, &project)).await?;
    let totals = Box::pin(count_closed_history(home, &thread_ids)).await?;
    Ok(vec![
        ReadCase {
            name: "bounded-cold-read".into(),
            thread_id: thread_ids[0].clone(),
            main_items: totals[0],
            switch_thread_id: Some(thread_ids[1].clone()),
        },
        ReadCase {
            name: "independent-page".into(),
            thread_id: thread_ids[1].clone(),
            main_items: totals[1],
            switch_thread_id: None,
        },
    ])
}

async fn write_history(home: &Path, project: &Path) -> Result<Vec<String>> {
    let fixture = FixtureServer::start(seed_script()).await?;
    write_seed_config(home, &fixture.base_url())?;
    let runtime = Box::pin(StudioRuntime::initialize(runtime_options(home))).await?;
    let workspace = runtime.open_project(project).await?;
    let mut thread_ids = Vec::new();
    for index in 0..THREAD_COUNT {
        thread_ids.push(Box::pin(seed_thread(&runtime, &workspace.id, index)).await?);
    }
    runtime.shutdown_runtime().await?;
    fixture.finish().await?;
    Ok(thread_ids)
}

async fn seed_thread(runtime: &StudioRuntime, workspace_id: &str, index: usize) -> Result<String> {
    let created = Box::pin(create_seed_thread(runtime, workspace_id, index)).await?;
    let mut subscription = runtime
        .subscribe_thread(ThreadSubscriptionRequest {
            thread_id: created.clone(),
        })
        .await?;
    let mut route_revision = Box::pin(wait_completed(
        runtime,
        &mut subscription,
        &created,
        &format!("read-input-{index}-00"),
    ))
    .await?;
    for turn in 1..TURN_COUNT {
        route_revision = Box::pin(seed_followup(
            runtime,
            &mut subscription,
            &created,
            index,
            turn,
            route_revision,
        ))
        .await?;
    }
    Ok(created)
}

async fn create_seed_thread(
    runtime: &StudioRuntime,
    workspace_id: &str,
    index: usize,
) -> Result<String> {
    let created = runtime
        .create_thread_command(
            workspace_id.to_owned(),
            CreateThreadRequest {
                title: Some(format!("conversation-read-{index}")),
                input: StudioPromptInput {
                    input_id: format!("read-input-{index}-00"),
                    text: format!("read-seed-{index}-00"),
                    attachment_draft_ids: Vec::new(),
                },
                mode: pl_protocol::ThreadModeId::simple().label().into(),
                route: NewThreadModelRoute {
                    account_id: ACCOUNT.into(),
                    model_id: MODEL.into(),
                    effort: None,
                },
                delegation_mode: None,
                delegation_preference: None,
                workspace_mode: ThreadWorkspaceMode::Local,
            },
            None,
        )
        .await?;
    Ok(created.thread.id)
}

async fn seed_followup(
    runtime: &StudioRuntime,
    subscription: &mut StudioThreadSubscription,
    thread_id: &str,
    index: usize,
    turn: usize,
    route_revision: u64,
) -> Result<u64> {
    let input_id = format!("read-input-{index}-{turn:02}");
    runtime
        .submit_prompt_command(
            thread_id.to_owned(),
            SubmitPromptRequest {
                input: StudioPromptInput {
                    input_id: input_id.clone(),
                    text: format!("read-seed-{index}-{turn:02}"),
                    attachment_draft_ids: Vec::new(),
                },
                expected_model_route_revision: route_revision,
            },
        )
        .await?;
    wait_completed(runtime, subscription, thread_id, &input_id).await
}

async fn count_closed_history(home: &Path, thread_ids: &[String]) -> Result<Vec<usize>> {
    let runtime = Box::pin(StudioRuntime::initialize(runtime_options(home))).await?;
    let mut totals = Vec::new();
    for thread_id in thread_ids {
        let total = Box::pin(count_main_items(&runtime, thread_id)).await?;
        ensure!(
            total > 40,
            "seeded conversation {thread_id} is too small for a bounded first page: {total}"
        );
        totals.push(total);
    }
    runtime.shutdown_runtime().await?;
    Ok(totals)
}

fn runtime_options(home: &Path) -> StudioRuntimeOptions {
    StudioRuntimeOptions {
        studio_home: Some(home.to_owned()),
        host: StudioHostKind::Test,
        ..StudioRuntimeOptions::desktop()
    }
}

fn init_git_project(project: &Path) -> Result<()> {
    fs::create_dir_all(project)?;
    let git = |args: &[&str]| -> Result<()> {
        let output = Command::new("git")
            .arg("-C")
            .arg(project)
            .args(args)
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .output()?;
        ensure!(
            output.status.success(),
            "git {args:?}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        Ok(())
    };
    git(&["init", "-q", "-b", "main"])?;
    git(&["config", "--local", "core.autocrlf", "false"])?;
    git(&["config", "--local", "core.eol", "lf"])?;
    git(&["config", "user.name", "Conversation Read Seed"])?;
    git(&["config", "user.email", "conversation-read@example.invalid"])?;
    fs::write(project.join("README.md"), "conversation read seed\n")?;
    git(&["add", "."])?;
    git(&["commit", "-q", "-m", "seed"])?;
    Ok(())
}

fn seed_script() -> Vec<Step> {
    let mut steps = Vec::new();
    for thread in 0..THREAD_COUNT {
        for turn in 0..TURN_COUNT {
            let text = format!("read-seed-{thread}-{turn:02}");
            steps.push(Step::prompt(
                Protocol::ResponsesHttp,
                text,
                steps.len(),
                Reply::Sse(responses_text(
                    &format!("read-answer-{thread}-{turn:02}"),
                    &format!("read-{thread}-{turn:02}"),
                    MODEL,
                )),
            ));
        }
    }
    steps
}

fn write_seed_config(home: &Path, base_url: &str) -> Result<()> {
    let mut config = StudioConfig::default_config()?;
    let mut model = ModelInfo::compatible(MODEL);
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    let account_id = AccountId::new(ACCOUNT)?;
    config.models.accounts.clear();
    config.models.accounts.insert(
        account_id.clone(),
        AccountConfig::from_explicit_models(
            ProtocolEndpoint::compatible("conversation read fixture", base_url),
            vec![model],
        ),
    );
    for route in config
        .models
        .routes
        .values_mut()
        .chain(config.mode_model_routes.values_mut())
    {
        route.account_id = account_id.clone();
        route.model_id = MODEL.into();
        route.effort = None;
    }
    ConfigStore::new(ConfigPaths::from_config_dir(home)).save(&config)?;
    Ok(())
}

async fn wait_completed(
    runtime: &StudioRuntime,
    subscription: &mut StudioThreadSubscription,
    thread_id: &str,
    input_id: &str,
) -> Result<u64> {
    tokio::time::timeout(Duration::from_secs(60), async {
        while let Some(update) = subscription.recv().await? {
            if let ThreadSubscriptionUpdate::Notification { notification } = update
                && let ThreadNotification::TurnCompleted { turn } = notification.notification
                && turn.input_id.as_deref() == Some(input_id)
            {
                let snapshot = runtime.thread_snapshot(thread_id).await?;
                return snapshot
                    .model_route
                    .as_ref()
                    .map(|route| route.revision)
                    .context("completed Turn has no model route");
            }
        }
        anyhow::bail!("thread stream ended without a terminal Turn for {input_id}")
    })
    .await
    .with_context(|| format!("terminal Turn not observed for {input_id}"))?
}

async fn count_main_items(runtime: &StudioRuntime, thread_id: &str) -> Result<usize> {
    let demand = ReadDemand {
        max_items: 32,
        max_bytes: CHAT_BATCH_MAX_BYTES.min(64 * 1024),
    };
    let mut feed = runtime
        .open_conversation_feed(thread_id, ChatScope::Main, demand)
        .await?;
    let mut batch = loop {
        match feed.recv().await? {
            Some(ConversationEvent::Chat { batch }) if batch.placement == ChatPlacement::Set => {
                break *batch;
            }
            Some(_) => {}
            None => bail!("conversation feed ended before the cold Set"),
        }
    };
    let reader = feed.reader().clone();
    let count_items = |batch: &pl_protocol::ChatBatch| -> Result<usize> {
        batch.validate_for(&ChatScope::Main)?;
        Ok(batch.entries.len())
    };
    let mut total = count_items(&batch)?;
    while let Some(before) = batch.before {
        batch = reader.load_older(&before, demand).await?;
        ensure!(
            batch.before.as_deref() != Some(before.as_str()),
            "Main item continuation did not advance"
        );
        total += count_items(&batch)?;
    }
    feed.close().await?;
    ensure!(
        total < CHAT_READ_MAX_ITEMS as usize,
        "seeded conversation exceeded the public read item ceiling"
    );
    Ok(total)
}
