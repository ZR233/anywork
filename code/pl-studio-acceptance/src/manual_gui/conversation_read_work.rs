//! Closed SQLite seed for the official conversation cold-read integration_test.
//!
//! Public Runtime APIs write real history, then the fixture and runtime shut
//! down before Flutter opens the same home. This module never edits SQLite or
//! copies a message stream.

use super::*;
use anyhow::{Context, Result, bail, ensure};
use pl_model::config::{AccountConfig, AccountId};
use pl_model::model::{ModelDefinition, ModelTransportProfile};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
use pl_studio_runtime::{
    CreateThreadRequest, NewThreadModelRoute, StudioPromptInput, SubmitPromptRequest,
};
use pl_studio_runtime::{
    StudioHostKind, StudioRuntime, StudioRuntimeOptions,
    config::{ConfigPaths, ConfigStore},
    history::{HISTORY_PROTOCOL_VERSION, HistoryBusinessRowHead, HistoryDemand, HistoryTurnState},
    mode::ThreadModeId,
};
use pl_studio_runtime::{
    ThreadStatus, ThreadWorkspaceMode,
    timeline::{ConversationEvent, ConversationFeed, TimelinePatch},
};
use serde::Serialize;
use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::{Duration, Instant};

const MODEL: &str = "fixture-model";
const ACCOUNT: &str = "read-fixture";
const TURN_COUNT: usize = 22;
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
    expected_seed_answer: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    switch_thread_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    switch_expected_seed_answer: Option<String>,
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
        runner_exit = Some(wait_desktop_runner(
            &mut runner,
            None,
            interrupt,
            Duration::from_secs(900),
            "conversation read integration tests",
        )?);
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
    let (thread_ids, totals) = Box::pin(write_history(home, &project)).await?;
    Ok(vec![ReadCase {
        name: "bounded-cold-read".into(),
        thread_id: thread_ids[0].clone(),
        main_items: totals[0],
        expected_seed_answer: format!("read-answer-0-{:02}", TURN_COUNT - 1),
        switch_thread_id: Some(thread_ids[1].clone()),
        switch_expected_seed_answer: Some(format!("read-answer-1-{:02}", TURN_COUNT - 1)),
    }])
}

async fn write_history(home: &Path, project: &Path) -> Result<(Vec<String>, Vec<usize>)> {
    let fixture = FixtureServer::start(seed_script()).await?;
    let seeded = async {
        write_seed_config(home, &fixture.base_url())?;
        let runtime = Box::pin(StudioRuntime::initialize(runtime_options(home))).await?;
        let seeded = async {
            let workspace = runtime.open_project(project).await?;
            let mut thread_ids = Vec::new();
            let mut totals = Vec::new();
            for index in 0..THREAD_COUNT {
                let id = Box::pin(seed_thread(&runtime, &workspace.id, index)).await?;
                runtime.synchronize_thread_observation(&id).await?;
                let total = Box::pin(count_main_items(&runtime, &id)).await?;
                totals.push(total);
                thread_ids.push(id);
            }
            Ok::<_, anyhow::Error>((thread_ids, totals))
        }
        .await;
        let stopped = runtime.shutdown_runtime().await.and_then(require_stopped);
        match (seeded, stopped) {
            (Ok(result), Ok(_)) => Ok(result),
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
    let feed = runtime.open_conversation_feed(&created, 64).await?;
    let mut saw_baseline = false;
    let outcome: Result<()> = async {
        let first_input = format!("read-input-{index}-00");
        let mut route_revision = Box::pin(wait_initial_turn(
            runtime,
            &feed,
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
                &feed,
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
    feed.close().await;
    outcome?;
    Ok(created)
}

pub(super) async fn wait_initial_turn(
    runtime: &StudioRuntime,
    feed: &ConversationFeed,
    saw_baseline: &mut bool,
    thread_id: &str,
    input_id: &str,
) -> Result<CompletedTurnObservation> {
    let deadline = Instant::now() + Duration::from_secs(60);
    let result = async {
        let first_event = tokio::time::timeout_at(deadline.into(), feed.next_event())
            .await
            .context("ConversationFeed baseline timed out")?;
        let Some(ConversationEvent::Timeline(TimelinePatch::Reset { .. })) = first_event else {
            bail!("ConversationFeed did not begin with Reset");
        };
        ensure!(
            feed.session_meta_snapshot().thread_id == thread_id,
            "ConversationFeed Reset belonged to another Thread"
        );
        *saw_baseline = true;
        let history = runtime
            .open_history_reader(thread_id, HISTORY_PROTOCOL_VERSION)
            .await?;
        let page = tokio::time::timeout_at(
            deadline.into(),
            history.turns_page(
                None,
                None,
                HistoryDemand {
                    max_rows: 128,
                    max_bytes: 1024 * 1024,
                },
            ),
        )
        .await
        .context("initial History turn check timed out")??;
        history.close().await;
        let already_completed = page.entries.iter().find_map(|entry| match &entry.head {
            HistoryBusinessRowHead::Turn(head)
                if head.input_id.as_deref() == Some(input_id)
                    && head.state == HistoryTurnState::Completed =>
            {
                Some(head.clone())
            }
            _ => None,
        });
        if let Some(completed) = already_completed {
            let meta = feed.session_meta_snapshot();
            ensure!(
                meta.thread_id == thread_id
                    && meta.active_turn.is_none()
                    && meta.status == ThreadStatus::Idle,
                "History completed Turn {} but SessionMeta is not idle",
                completed.turn_id
            );
            let route_revision = meta
                .model_route
                .as_ref()
                .map(|route| route.revision)
                .context("completed Turn has no model route")?;
            return Ok(CompletedTurnObservation {
                turn_id: completed.turn_id,
                route_revision,
                snapshot_revision: meta.revision,
            });
        }
        Box::pin(wait_notified_turn(feed, saw_baseline, thread_id, input_id)).await
    }
    .await;
    result.with_context(|| format!("initial Turn not observed for {input_id}"))
}

pub(super) async fn wait_notified_turn(
    feed: &ConversationFeed,
    saw_baseline: &mut bool,
    thread_id: &str,
    input_id: &str,
) -> Result<CompletedTurnObservation> {
    tokio::time::timeout(Duration::from_secs(60), async {
        loop {
            let meta = feed.session_meta_snapshot();
            if let Some(turn) = meta
                .last_turn
                .as_ref()
                .filter(|turn| turn.input_id.as_deref() == Some(input_id))
                && meta.active_turn.is_none()
                && meta.status == ThreadStatus::Idle
            {
                ensure!(*saw_baseline, "SessionMeta completed before Reset");
                ensure!(
                    meta.thread_id == thread_id
                        && matches!(turn.state, pl_studio_runtime::TurnState::Completed(_)),
                    "TurnCompleted and SessionMeta disagree"
                );
                let route_revision = meta
                    .model_route
                    .as_ref()
                    .map(|route| route.revision)
                    .context("completed Turn has no model route")?;
                return Ok(CompletedTurnObservation {
                    turn_id: turn.id.clone(),
                    route_revision,
                    snapshot_revision: meta.revision,
                });
            }
            let Some(event) = feed.next_event().await else {
                bail!("ConversationFeed ended before Turn completion");
            };
            match event {
                ConversationEvent::Timeline(TimelinePatch::Reset { .. }) => *saw_baseline = true,
                ConversationEvent::SessionMeta(_) => {}
                ConversationEvent::Timeline(_)
                | ConversationEvent::LiveStatus(_)
                | ConversationEvent::InputPresented { .. }
                | ConversationEvent::ResyncRequired { .. } => {}
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
                mode: ThreadModeId::auto().as_str().into(),
                route: NewThreadModelRoute {
                    account_id: ACCOUNT.into(),
                    model_id: MODEL.into(),
                    effort: None,
                },
                service_tier: None,
                delegation_mode: None,
                delegation_preference: None,
                workspace_mode: ThreadWorkspaceMode::Local,
            },
            None,
        )
        .await?;
    Ok(created.thread.id)
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
    let mut model = ModelDefinition::compatible(MODEL);
    model
        .extra
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
        max_bytes: pl_studio_runtime::CHAT_BATCH_MAX_BYTES.min(64 * 1024),
    };
    let reader = runtime
        .open_history_reader(thread_id, HISTORY_PROTOCOL_VERSION)
        .await?;
    let counted = async {
        let mut cut = None;
        let mut cursor = None;
        let mut total = 0usize;
        let mut newer_direct_seq: Option<u64> = None;
        loop {
            let page = reader
                .timeline_page(cut.clone(), cursor.clone(), demand)
                .await?;
            for entry in &page.entries {
                total = total
                    .checked_add(1)
                    .context("history Main count overflow")?;
                if entry.has_folded_after {
                    let _ = (entry.event.seq, newer_direct_seq);
                    total = total
                        .checked_add(1)
                        .context("history Main count overflow")?;
                }
                newer_direct_seq = Some(entry.event.seq);
            }
            if page.next.is_none() && page.has_folded_before_oldest {
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
