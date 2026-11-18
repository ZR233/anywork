//! Closed SQLite seed for the official conversation cold-read integration_test.
//!
//! Public Runtime APIs write real history, then the fixture and runtime shut
//! down before Flutter opens the same home. This module never edits SQLite or
//! copies a message stream.

use super::*;
use anyhow::{Context, Result, bail, ensure};
use pl_model::config::{AccountConfig, AccountId};
use pl_model::model::{ModelInfo, ModelTransportProfile};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
use pl_studio_runtime::{
    CHAT_BATCH_MAX_BYTES, CurrentFrame, ReadDemand, ThreadNotification, ThreadStatus,
    ThreadWorkspaceMode,
};
use pl_studio_runtime::{
    CreateThreadRequest, NewThreadModelRoute, StudioPromptInput, SubmitPromptRequest,
};
use pl_studio_runtime::{
    CurrentReader, CurrentWatch, StudioHostKind, StudioRuntime, StudioRuntimeOptions,
    config::{ConfigPaths, ConfigStore},
    history::{HISTORY_PROTOCOL_VERSION, HistoryDemand, HistoryRowHead, HistoryTurnState},
    mode::ThreadModeId,
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

pub(super) struct CompletedTurnObservation {
    pub turn_id: String,
    pub route_revision: u64,
    pub snapshot_revision: u64,
}

mod profile;

pub(super) struct ConversationReadWorkScenario<'a> {
    pub workspace: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    pub interrupt: &'a mpsc::Receiver<()>,
    pub profile_read_samples: bool,
    pub profile_read_seed: Option<&'a Path>,
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
    if context.profile_read_samples {
        return profile::run(context);
    }
    let ConversationReadWorkScenario {
        workspace,
        home,
        working,
        output,
        interrupt,
        ..
    } = context;
    let cases_path = output.join("read-cases.json");
    let report_path = output.join("read-report.json");
    let log_path = working.join("conversation-read-work-integration.log");
    let mut runner_exit = None;
    let suite = (|| -> Result<()> {
        let seeded = seed_closed_home(home, working)?;
        fs::write(&cases_path, serde_json::to_vec_pretty(&seeded)?)?;
        let log = File::create(&log_path)?;
        let mut command = desktop_test_command(workspace)?;
        command
            .args(["--suite", "desktop", "--case", "conversation_read_work"])
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
    let seeded = async {
        write_seed_config(home, &fixture.base_url())?;
        let runtime = Box::pin(StudioRuntime::initialize(runtime_options(home))).await?;
        let seeded = async {
            let workspace = runtime.open_project(project).await?;
            let mut thread_ids = Vec::new();
            for index in 0..THREAD_COUNT {
                thread_ids.push(Box::pin(seed_thread(&runtime, &workspace.id, index)).await?);
            }
            Ok::<_, anyhow::Error>(thread_ids)
        }
        .await;
        let stopped = runtime.shutdown_runtime().await.and_then(require_stopped);
        match (seeded, stopped) {
            (Ok(ids), Ok(_)) => Ok(ids),
            (Err(error), Ok(_)) | (Ok(_), Err(error)) => Err(error),
            (Err(error), Err(stop_error)) => {
                Err(error.context(format!("runtime shutdown also failed: {stop_error:#}")))
            }
        }
    }
    .await;
    let fixture_exit = fixture.finish().await;
    match (seeded, fixture_exit) {
        (Ok(ids), Ok(_)) => Ok(ids),
        (Err(error), Ok(_)) => Err(error),
        (Ok(_), Err(error)) => Err(error),
        (Err(error), Err(fixture_error)) => {
            Err(error.context(format!("fixture shutdown also failed: {fixture_error:#}")))
        }
    }
}

async fn seed_thread(runtime: &StudioRuntime, workspace_id: &str, index: usize) -> Result<String> {
    let created = Box::pin(create_seed_thread(runtime, workspace_id, index)).await?;
    let demand = current_demand();
    let current = runtime
        .open_current_reader(
            &created,
            pl_studio_runtime::CURRENT_PROTOCOL_VERSION,
            demand,
        )
        .await?;
    let mut watch = match current.watch(None, demand).await {
        Ok(watch) => watch,
        Err(error) => {
            return match current.close().await {
                Ok(()) => Err(error),
                Err(close_error) => {
                    Err(error.context(format!("Current close also failed: {close_error:#}")))
                }
            };
        }
    };
    let mut saw_baseline = false;
    let outcome: Result<()> = async {
        let first_input = format!("read-input-{index}-00");
        let mut route_revision = Box::pin(wait_initial_turn(
            runtime,
            &current,
            &mut watch,
            &mut saw_baseline,
            &created,
            &first_input,
        ))
        .await?
        .route_revision;
        for turn in 1..TURN_COUNT {
            let input_id = format!("read-input-{index}-{turn:02}");
            runtime
                .submit_prompt_command(
                    created.clone(),
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
            route_revision = Box::pin(wait_notified_turn(
                &current,
                &mut watch,
                &mut saw_baseline,
                &created,
                &input_id,
            ))
            .await?
            .route_revision;
        }
        Ok(())
    }
    .await;
    let closed_watch = watch.close().await;
    let closed_current = current.close().await;
    let mut close_errors = Vec::new();
    if let Err(error) = closed_watch {
        close_errors.push(format!("watch: {error:#}"));
    }
    if let Err(error) = closed_current {
        close_errors.push(format!("reader: {error:#}"));
    }
    match outcome {
        Ok(()) if close_errors.is_empty() => Ok(created),
        Err(error) => {
            let mut message = format!("{error:#}");
            if !close_errors.is_empty() {
                message.push_str(&format!(
                    "; Current close also failed: {}",
                    close_errors.join("; ")
                ));
            }
            Err(anyhow::anyhow!(message))
        }
        Ok(()) => Err(anyhow::anyhow!(
            "Current close failed: {}",
            close_errors.join("; ")
        )),
    }
}

pub(super) async fn wait_initial_turn(
    runtime: &StudioRuntime,
    current: &CurrentReader,
    watch: &mut CurrentWatch,
    saw_baseline: &mut bool,
    thread_id: &str,
    input_id: &str,
) -> Result<CompletedTurnObservation> {
    let deadline = Instant::now() + Duration::from_secs(60);
    let result = async {
        let Some(CurrentFrame::Reset { view }) =
            tokio::time::timeout_at(deadline.into(), watch.next())
                .await
                .context("Current baseline timed out")??
        else {
            bail!("Current watch did not begin with Reset");
        };
        ensure!(
            view.state.thread.id == thread_id,
            "Current Reset belonged to another Thread"
        );
        *saw_baseline = true;
        let history = runtime
            .open_history_reader(thread_id, HISTORY_PROTOCOL_VERSION)
            .await?;
        let observed = match tokio::time::timeout_at(deadline.into(), async {
            let completed = loop {
                let page = history
                    .turns_page(
                        None,
                        None,
                        HistoryDemand {
                            max_rows: 128,
                            max_bytes: 1024 * 1024,
                        },
                    )
                    .await?;
                if let Some(head) = page.entries.iter().find_map(|entry| match &entry.head {
                    HistoryRowHead::Turn(head)
                        if head.input_id.as_deref() == Some(input_id)
                            && head.state == HistoryTurnState::Completed =>
                    {
                        Some(head.clone())
                    }
                    _ => None,
                }) {
                    break head;
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
            };
            let view = current.snapshot(current_demand()).await?;
            Ok::<_, anyhow::Error>((completed, view))
        })
        .await
        {
            Ok(result) => result,
            Err(error) => Err(anyhow::Error::new(error).context("History completion timed out")),
        };
        history.close().await;
        let (completed, view) = observed?;
        ensure!(
            view.state.schema_version == pl_studio_runtime::THREAD_SCHEMA_VERSION
                && view.state.thread.id == thread_id
                && view.state.active_turn.is_none()
                && view.state.thread.status == ThreadStatus::Idle,
            "History completed Turn {} but Current is not idle",
            completed.turn_id
        );
        let route_revision = view
            .state
            .model_route
            .as_ref()
            .map(|route| route.revision)
            .context("completed Turn has no model route")?;
        Ok(CompletedTurnObservation {
            turn_id: completed.turn_id,
            route_revision,
            snapshot_revision: view.state.revision,
        })
    }
    .await;
    result.with_context(|| format!("initial Turn not observed for {input_id}"))
}

pub(super) async fn wait_notified_turn(
    current: &CurrentReader,
    watch: &mut CurrentWatch,
    saw_baseline: &mut bool,
    thread_id: &str,
    input_id: &str,
) -> Result<CompletedTurnObservation> {
    tokio::time::timeout(Duration::from_secs(60), async {
        loop {
            let Some(frame) = watch.next().await? else {
                bail!("Current watch ended before Turn completion");
            };
            match frame {
                CurrentFrame::Reset { .. } => *saw_baseline = true,
                CurrentFrame::Projection { .. } => {}
                CurrentFrame::Notification { notification, .. } => {
                    ensure!(*saw_baseline, "Current notification arrived before Reset");
                    if let ThreadNotification::TurnCompleted { turn } = notification.notification
                        && turn.input_id.as_deref() == Some(input_id)
                    {
                        let view = current.snapshot(current_demand()).await?;
                        ensure!(
                            view.state.schema_version == pl_studio_runtime::THREAD_SCHEMA_VERSION
                                && view.state.thread.id == thread_id
                                && matches!(turn.state, pl_studio_runtime::TurnState::Completed(_))
                                && view.state.active_turn.is_none()
                                && view.state.thread.status == ThreadStatus::Idle,
                            "TurnCompleted and Current State disagree"
                        );
                        let route_revision = view
                            .state
                            .model_route
                            .as_ref()
                            .map(|route| route.revision)
                            .context("completed Turn has no model route")?;
                        return Ok(CompletedTurnObservation {
                            turn_id: turn.id,
                            route_revision,
                            snapshot_revision: view.state.revision,
                        });
                    }
                }
            }
        }
    })
    .await
    .with_context(|| format!("notified Turn not observed for {input_id}"))?
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
                mode: ThreadModeId::simple().label().into(),
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

async fn count_closed_history(home: &Path, thread_ids: &[String]) -> Result<Vec<usize>> {
    let runtime = Box::pin(StudioRuntime::initialize(runtime_options(home))).await?;
    let counted = async {
        let mut totals = Vec::new();
        for thread_id in thread_ids {
            let total = Box::pin(count_main_items(&runtime, thread_id)).await?;
            ensure!(
                total > 40,
                "seeded conversation {thread_id} is too small for a bounded first page: {total}"
            );
            totals.push(total);
        }
        Ok::<_, anyhow::Error>(totals)
    }
    .await;
    let stopped = runtime.shutdown_runtime().await.and_then(require_stopped);
    match (counted, stopped) {
        (Ok(totals), Ok(_)) => Ok(totals),
        (Err(error), Ok(_)) | (Ok(_), Err(error)) => Err(error),
        (Err(error), Err(stop_error)) => {
            Err(error.context(format!("runtime shutdown also failed: {stop_error:#}")))
        }
    }
}

fn runtime_options(home: &Path) -> StudioRuntimeOptions {
    let mut options = StudioRuntimeOptions {
        studio_home: Some(home.to_owned()),
        host: StudioHostKind::Test,
        ..StudioRuntimeOptions::desktop()
    };
    options.skill_search.include_default_user_dir = false;
    options
}

pub(super) fn require_stopped(
    snapshot: pl_studio_runtime::StudioRuntimeSnapshot,
) -> Result<pl_studio_runtime::StudioRuntimeSnapshot> {
    ensure!(
        snapshot.state.is_stopped(),
        "runtime shutdown returned {:?} instead of stopped",
        snapshot.state.kind()
    );
    Ok(snapshot)
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
    let store = ConfigStore::new(ConfigPaths::from_config_dir(home));
    let mut config = store.load_or_default()?;
    let mut model = ModelInfo::compatible(MODEL);
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    let account_id = AccountId::new(ACCOUNT)?;
    config.models.accounts.clear();
    config.models.accounts.insert(
        account_id.clone(),
        AccountConfig::from_explicit_models(
            pl_model::protocol::providers::openai::compatible_endpoint(
                "conversation read fixture",
                base_url,
            ),
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
    store.save(&config)?;
    Ok(())
}

async fn count_main_items(runtime: &StudioRuntime, thread_id: &str) -> Result<usize> {
    let demand = HistoryDemand {
        max_rows: 32,
        max_bytes: CHAT_BATCH_MAX_BYTES.min(64 * 1024),
    };
    let reader = runtime
        .open_history_reader(thread_id, HISTORY_PROTOCOL_VERSION)
        .await?;
    let counted = async {
        let mut cut = None;
        let mut cursor = None;
        let mut total = 0usize;
        loop {
            let page = reader
                .timeline_page(cut.clone(), cursor.clone(), demand)
                .await?;
            for entry in &page.entries {
                match &entry.head {
                    HistoryRowHead::Single(_) | HistoryRowHead::Work(_) => {}
                    _ => bail!("timeline Main contained a non-row head"),
                }
                total = total
                    .checked_add(1)
                    .context("history Main count overflow")?;
            }
            let Some(next) = page.next else {
                break;
            };
            ensure!(
                cursor.as_deref() != Some(next.as_str()),
                "Main continuation did not advance"
            );
            cut = Some(page.cut);
            cursor = Some(next);
        }
        Ok::<_, anyhow::Error>(total)
    }
    .await;
    reader.close().await;
    let total = counted?;
    ensure!(
        total > 40,
        "seeded conversation is too small for a bounded first page: {total}"
    );
    Ok(total)
}

fn current_demand() -> ReadDemand {
    ReadDemand {
        max_items: 128,
        max_bytes: CHAT_BATCH_MAX_BYTES.min(64 * 1024),
    }
}
