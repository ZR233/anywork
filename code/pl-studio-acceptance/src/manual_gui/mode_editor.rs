//! Mode-editor GUI journey with root Mode/workflow snapshot assertions.

use super::*;
use sea_orm::sqlx::{
    Connection as _, Row,
    sqlite::{SqliteConnectOptions, SqliteConnection},
};

const MODE_EDITOR_ID: &str = "mode.editor-evidence";
const MODE_EDITOR_FILE: &str = "mode.editor-evidence.json";
const MODE_EDITOR_PHASES: [&str; 3] = ["first", "restart", "recheck"];
const MODE_EDITOR_REQUIRED_REQUESTS: usize = 10;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct RunObservation {
    run_id: String,
    lineage_id: String,
    graph_hash: String,
    graph_revision: u64,
    mode_id: String,
    current_state_id: String,
    lifecycle: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ModeObservation {
    thread_id: String,
    mode_extension_revision: u64,
    mode_version: u64,
    definition: serde_json::Value,
    graph_revision: u64,
    frozen_turn_id: String,
    compiled_graph_hash: String,
    instruction_prompt: String,
    workflow_extension_revision: u64,
    workflow: serde_json::Value,
    run: RunObservation,
    history_records: usize,
    #[serde(skip_serializing)]
    history: serde_json::Value,
}

#[derive(Default)]
struct JourneyEvidence {
    thread_id: Option<String>,
    graph_updated: Option<ModeObservation>,
    prompt_updated: Option<ModeObservation>,
    first_final_history: Option<serde_json::Value>,
    restart_final_history: Option<serde_json::Value>,
}

/// Run three fresh native GUIs against one isolated home, project and fixture.
pub(super) fn run(context: &RecoveryScenario<'_>, mut fixture: OwnedProcess) -> Result<()> {
    let project = context.working.join("mode-editor-project");
    let coord = context.working.join("mode-editor-coord");
    let mut evidence = JourneyEvidence::default();
    let mut lifecycles = Vec::new();
    let mut phase_reports = Vec::new();
    let mut driver_exits = BTreeMap::new();
    fs::write(
        context.output.join("verdict.json"),
        "{\"human_verdict\":\"pending\"}\n",
    )?;
    fs::write(context.output.join("lifecycle.json"), "[]\n")?;

    let journey = (|| -> Result<()> {
        fs::create_dir(&project)?;
        fs::create_dir(&coord)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated mode-editor project"
        );
        for phase in MODE_EDITOR_PHASES {
            run_phase(
                context,
                &mut fixture,
                &project,
                &coord,
                phase,
                &mut evidence,
                &mut lifecycles,
                &mut phase_reports,
                &mut driver_exits,
            )?;
        }
        Ok(())
    })();

    let fixture_result = fixture.stop(context.requests_file);
    drop(fixture);
    let requests = if context.requests_file.is_file() {
        sanitize_requests(context.requests_file, &context.output.join("requests.json"))?;
        serde_json::from_slice::<Vec<serde_json::Value>>(&fs::read(context.requests_file)?)?
    } else {
        Vec::new()
    };
    write_fixture_log(context.fixture_log, &context.output.join("fixture.log"))?;

    let redactions = [
        (context.app_dir.to_string_lossy().into_owned(), "<app>"),
        (
            context.workspace.to_string_lossy().into_owned(),
            "<workspace>",
        ),
        (context.home.to_string_lossy().into_owned(), "<home>"),
        (context.working.to_string_lossy().into_owned(), "<coord>"),
    ];
    for phase in MODE_EDITOR_PHASES {
        let gui_log = context.working.join(format!("mode-editor-{phase}-gui.log"));
        if gui_log.is_file() {
            write_sanitized_log(
                &gui_log,
                &context.output.join(format!("mode-editor-{phase}-gui.log")),
            )?;
            let log = fs::read_to_string(&gui_log)?;
            let lines: Vec<_> = log.lines().collect();
            let mut errors = String::new();
            for (index, line) in lines.iter().enumerate() {
                if line.contains("EXCEPTION CAUGHT BY") || line.contains("Unhandled Exception") {
                    for detail in lines.iter().skip(index).take(28) {
                        errors.push_str(&sanitize_driver_line(detail, &redactions));
                        errors.push('\n');
                    }
                }
            }
            fs::write(
                context
                    .output
                    .join(format!("mode-editor-{phase}-gui-errors.txt")),
                errors,
            )?;
        }
        let driver_log = context
            .working
            .join(format!("mode-editor-{phase}-driver.log"));
        write_process_evidence(
            &driver_log,
            context.output,
            &format!("mode-editor-{phase}"),
            "driver",
            driver_exits.get(phase).cloned().flatten(),
            journey.as_ref().err(),
            &redactions,
        )?;
    }
    write_lifecycle(context.output, &lifecycles)?;
    let accepted = requests
        .iter()
        .filter(|request| request["accepted"] == true)
        .count();
    let rejected = requests
        .iter()
        .filter(|request| request["accepted"] == false)
        .count();
    let fixture_complete = fixture_result.as_ref().is_ok_and(|status| status.success());
    fs::write(
        context.output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "mode-editor",
            "completed": fixture_complete,
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "requiredAcceptedRequests": MODE_EDITOR_REQUIRED_REQUESTS,
            "error": fixture_result
                .as_ref()
                .err()
                .map(|error| sanitize_driver_line(&error.to_string(), &redactions)),
        }))?,
    )?;

    let gui_errors = MODE_EDITOR_PHASES
        .iter()
        .map(|phase| {
            let path = context.working.join(format!("mode-editor-{phase}-gui.log"));
            if path.is_file() {
                count_gui_errors(&path)
            } else {
                Ok(0)
            }
        })
        .collect::<Result<Vec<_>>>()?
        .into_iter()
        .sum::<usize>();
    let dart_errors = MODE_EDITOR_PHASES
        .iter()
        .map(|phase| {
            let path = context
                .working
                .join(format!("mode-editor-{phase}-driver.log"));
            if path.is_file() {
                count_dart_errors(&path)
            } else {
                Ok(0)
            }
        })
        .collect::<Result<Vec<_>>>()?
        .into_iter()
        .sum::<usize>();
    fs::write(
        context.output.join("gui-health.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "unhandledGuiErrors": gui_errors,
            "dartErrors": dart_errors,
            "humanVerdict": "pending",
        }))?,
    )?;
    let journey_error = journey
        .as_ref()
        .err()
        .map(|error| sanitize_driver_line(&error.to_string(), &redactions));
    let complete = journey.is_ok()
        && fixture_complete
        && accepted >= MODE_EDITOR_REQUIRED_REQUESTS
        && rejected == 0
        && gui_errors == 0
        && dart_errors == 0;
    fs::write(
        context.output.join("mode-editor-result.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "mode-editor",
            "status": if complete {"complete"} else {"failed"},
            "humanVerdict": "pending",
            "phases": phase_reports,
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "requiredAcceptedRequests": MODE_EDITOR_REQUIRED_REQUESTS,
            "guiErrors": gui_errors,
            "dartErrors": dart_errors,
            "fixtureCompleted": fixture_complete,
            "error": journey_error,
        }))?,
    )?;
    println!(
        "Evidence: {} (human verdict pending)",
        context.output.display()
    );

    journey?;
    ensure!(
        fixture_complete
            && accepted >= MODE_EDITOR_REQUIRED_REQUESTS
            && rejected == 0
            && gui_errors == 0
            && dart_errors == 0,
        "mode-editor fixture or GUI health incomplete; human verdict pending"
    );
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn run_phase(
    context: &RecoveryScenario<'_>,
    fixture: &mut OwnedProcess,
    project: &Path,
    coord: &Path,
    phase: &'static str,
    evidence: &mut JourneyEvidence,
    lifecycles: &mut Vec<serde_json::Value>,
    phase_reports: &mut Vec<serde_json::Value>,
    driver_exits: &mut BTreeMap<&'static str, Option<std::process::ExitStatus>>,
) -> Result<()> {
    let gui_log = context.working.join(format!("mode-editor-{phase}-gui.log"));
    let driver_log = context
        .working
        .join(format!("mode-editor-{phase}-driver.log"));
    let mut gui = start_recovery_gui(context.workspace, context.home, &gui_log)?;
    let gui_pid = gui.child.id();
    let mut driver = None;
    let mut driver_pid = None;
    let mut driver_exit = None;
    let outcome = (|| -> Result<()> {
        let vm_url = wait_for_vm(&gui_log, &mut gui, fixture, context.interrupt)?;
        let log = File::create(&driver_log)?;
        let mut command = driver_command(context.app_dir, "test_driver/mode_editor_journey.dart");
        command
            .args([phase, &vm_url])
            .arg(project)
            .arg(context.output)
            .arg(coord)
            .arg(context.home)
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));
        let process = OwnedProcess::start(&mut command, false)?;
        driver_pid = Some(process.child.id());
        driver = Some(process);
        let driver = driver.as_mut().expect("Mode editor Driver was installed");

        match phase {
            "first" => {
                let original = await_mode_stage(
                    "first-updated-during-turn",
                    context,
                    coord,
                    driver,
                    &mut gui,
                    fixture,
                    evidence,
                )?;
                ensure!(
                    definition_prompt(&original).contains("mode-editor-original"),
                    "first Turn did not freeze the original Mode prompt"
                );
                assert_valid_snapshot(&original)?;
                let original_run = original.run.clone();
                mark_stage_verified(coord, "first-updated-during-turn")?;

                let graph = await_mode_stage(
                    "graph-updated",
                    context,
                    coord,
                    driver,
                    &mut gui,
                    fixture,
                    evidence,
                )?;
                ensure!(
                    definition_prompt(&graph).contains("mode-editor-graph-updated"),
                    "graph-updated Turn did not freeze the updated graph prompt"
                );
                assert_valid_snapshot(&graph)?;
                assert_graph_update(&graph, &original_run)?;
                mark_stage_verified(coord, "graph-updated")?;
                evidence.graph_updated = Some(graph);

                let prompt = await_mode_stage(
                    "prompt-updated",
                    context,
                    coord,
                    driver,
                    &mut gui,
                    fixture,
                    evidence,
                )?;
                ensure!(
                    definition_prompt(&prompt).contains("mode-editor-prompt-only"),
                    "prompt-updated Turn did not freeze the prompt-only update"
                );
                assert_prompt_only_update(
                    &prompt,
                    evidence
                        .graph_updated
                        .as_ref()
                        .context("graph-updated snapshot is missing")?,
                )?;
                mark_stage_verified(coord, "prompt-updated")?;
                evidence.prompt_updated = Some(prompt);

                let deleted = await_mode_stage(
                    "deleted-running",
                    context,
                    coord,
                    driver,
                    &mut gui,
                    fixture,
                    evidence,
                )?;
                ensure!(
                    !mode_file(context.home).is_file(),
                    "deleted-running stage still has the Mode file"
                );
                assert_same_snapshot(
                    &deleted,
                    evidence
                        .prompt_updated
                        .as_ref()
                        .context("prompt-updated snapshot is missing")?,
                    "deleting the Mode changed the saved Turn snapshot",
                )?;
                mark_stage_verified(coord, "deleted-running")?;
            }
            "restart" => {
                let reopened = await_mode_stage(
                    "restart-opened",
                    context,
                    coord,
                    driver,
                    &mut gui,
                    fixture,
                    evidence,
                )?;
                ensure!(
                    !mode_file(context.home).is_file(),
                    "restart opened with the deleted Mode file present"
                );
                assert_same_snapshot(
                    &reopened,
                    evidence
                        .prompt_updated
                        .as_ref()
                        .context("prompt-updated snapshot is missing")?,
                    "restart changed the deleted Mode snapshot",
                )?;
                ensure!(
                    Some(&reopened.history) == evidence.first_final_history.as_ref(),
                    "restart history differs from the first lifecycle's final history"
                );
                let quiet = quiet_window(context.status_file)?;
                fs::write(
                    context.output.join("restart-quiet.json"),
                    serde_json::to_vec_pretty(&quiet)?,
                )?;
                mark_stage_verified(coord, "restart-opened")?;
            }
            "recheck" => {
                let reopened = await_mode_stage(
                    "recheck-opened",
                    context,
                    coord,
                    driver,
                    &mut gui,
                    fixture,
                    evidence,
                )?;
                ensure!(
                    !mode_file(context.home).is_file(),
                    "recheck opened with the deleted Mode file present"
                );
                assert_same_snapshot(
                    &reopened,
                    evidence
                        .prompt_updated
                        .as_ref()
                        .context("prompt-updated snapshot is missing")?,
                    "recheck changed the deleted Mode snapshot",
                )?;
                ensure!(
                    Some(&reopened.history) == evidence.restart_final_history.as_ref(),
                    "recheck history differs from the restart lifecycle's final history"
                );
                let quiet = quiet_window(context.status_file)?;
                fs::write(
                    context.output.join("recheck-quiet.json"),
                    serde_json::to_vec_pretty(&quiet)?,
                )?;
                mark_stage_verified(coord, "recheck-opened")?;
            }
            other => bail!("unknown mode-editor phase: {other}"),
        }

        super::context_replay_recovery::wait_driver(driver, &mut gui, fixture, context.interrupt)
            .with_context(|| format!("mode-editor {phase} Driver did not finish"))?;
        let status = driver
            .child
            .try_wait()?
            .context("completed Driver has no exit status")?;
        driver_exit = Some(status);
        ensure!(
            status.success(),
            "mode-editor {phase} Driver failed with {status}"
        );
        ensure!(
            count_dart_errors(&driver_log)? == 0,
            "mode-editor {phase} Driver log contains an error"
        );
        let (_summary, summary_thread) = read_phase_summary(context.output, phase)?;
        let observed_thread = read_observed_thread(coord)?;
        ensure!(
            summary_thread == observed_thread,
            "mode-editor {phase} summary and observed Thread differ"
        );
        remember_thread(evidence, &summary_thread)?;
        match phase {
            "first" => {
                let final_observation = read_mode_observation(context.home, &summary_thread)?;
                ensure!(
                    final_observation.history_records > 0,
                    "first lifecycle final history is empty"
                );
                evidence.first_final_history = Some(final_observation.history);
            }
            "restart" => {
                let final_observation = read_mode_observation(context.home, &summary_thread)?;
                ensure!(
                    final_observation.history_records > 0,
                    "restart lifecycle final history is empty"
                );
                evidence.restart_final_history = Some(final_observation.history);
            }
            _ => {}
        }
        phase_reports.push(serde_json::json!({
            "phase": phase,
            "status": "complete",
            "threadId": summary_thread,
        }));
        Ok(())
    })();

    if let Some(process) = driver.as_mut() {
        process.terminate();
    }
    gui.terminate();
    lifecycles.push(serde_json::json!({
        "scenario": "mode-editor",
        "phase": phase,
        "guiLauncherPid": gui_pid,
        "driverLauncherPid": driver_pid,
        "driverExit": driver_exit.as_ref().map(ToString::to_string),
        "shutdown": if outcome.is_ok() { "completed" } else { "failed" },
        "ownersReapedAt": SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
    }));
    driver_exits.insert(phase, driver_exit);
    let lifecycle_write = write_lifecycle(context.output, lifecycles);
    if outcome.is_ok() {
        lifecycle_write?;
    } else if let Err(error) = lifecycle_write {
        eprintln!("failed to persist mode-editor lifecycle after phase failure: {error}");
    }
    if outcome.is_err() {
        phase_reports.push(serde_json::json!({
            "phase": phase,
            "status": "failed",
        }));
    }
    outcome
}

fn await_mode_stage(
    stage: &'static str,
    context: &RecoveryScenario<'_>,
    coord: &Path,
    driver: &mut OwnedProcess,
    gui: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
    evidence: &mut JourneyEvidence,
) -> Result<ModeObservation> {
    super::context_replay_recovery::wait_stage(
        &coord.join(stage),
        driver,
        gui,
        fixture,
        context.interrupt,
    )
    .with_context(|| format!("mode-editor Driver did not reach {stage}"))?;
    let thread_id = read_observed_thread(coord)?;
    remember_thread(evidence, &thread_id)?;
    let observation = read_mode_observation(context.home, &thread_id)
        .with_context(|| format!("failed to read the checkpoint at {stage}"))?;
    persist_stage(context.output, stage, &observation)?;
    Ok(observation)
}

fn remember_thread(evidence: &mut JourneyEvidence, thread_id: &str) -> Result<()> {
    if let Some(previous) = &evidence.thread_id {
        ensure!(
            previous == thread_id,
            "mode-editor phases reopened different Threads"
        );
    } else {
        evidence.thread_id = Some(thread_id.to_owned());
    }
    Ok(())
}

fn read_phase_summary(output: &Path, phase: &str) -> Result<(serde_json::Value, String)> {
    let path = output.join(format!("{phase}-summary.json"));
    let summary: serde_json::Value = serde_json::from_slice(
        &fs::read(&path)
            .with_context(|| format!("Mode editor Driver did not write {phase}-summary.json"))?,
    )?;
    ensure!(
        summary["status"] == "complete" && summary["shutdown"] == "completed",
        "mode-editor {phase} summary did not complete a normal shutdown"
    );
    let thread_id = summary["threadId"]
        .as_str()
        .context("mode-editor summary Thread id is missing")?
        .to_owned();
    ensure!(
        !thread_id.is_empty(),
        "mode-editor summary Thread id is empty"
    );
    Ok((summary, thread_id))
}

fn read_observed_thread(coord: &Path) -> Result<String> {
    let observed: serde_json::Value =
        serde_json::from_slice(&fs::read(coord.join("observed.json"))?)?;
    let thread_id = observed["threadId"]
        .as_str()
        .context("mode-editor observed Thread id is missing")?
        .to_owned();
    ensure!(
        !thread_id.is_empty(),
        "mode-editor observed Thread id is empty"
    );
    Ok(thread_id)
}

fn mark_stage_verified(coord: &Path, stage: &str) -> Result<()> {
    fs::write(coord.join(format!("{stage}-verified")), "verified")?;
    Ok(())
}

fn persist_stage(output: &Path, stage: &str, observation: &ModeObservation) -> Result<()> {
    fs::write(
        output.join(format!("mode-editor-{stage}.json")),
        serde_json::to_vec_pretty(observation)?,
    )?;
    Ok(())
}

fn write_lifecycle(output: &Path, lifecycles: &[serde_json::Value]) -> Result<()> {
    fs::write(
        output.join("lifecycle.json"),
        serde_json::to_vec_pretty(lifecycles)?,
    )?;
    Ok(())
}

fn mode_file(home: &Path) -> PathBuf {
    home.join("modes").join(MODE_EDITOR_FILE)
}

fn definition_prompt(observation: &ModeObservation) -> &str {
    observation.definition["prompt"]
        .as_str()
        .unwrap_or_default()
}

fn assert_valid_snapshot(observation: &ModeObservation) -> Result<()> {
    ensure!(
        observation.mode_version == 2,
        "saved Mode payload version is {}, expected 2",
        observation.mode_version
    );
    ensure!(
        observation.mode_extension_revision > 0
            && observation.workflow_extension_revision > 0
            && !observation.frozen_turn_id.is_empty(),
        "saved Mode extension is missing its revision or frozen Turn"
    );
    ensure!(
        observation.definition["id"] == MODE_EDITOR_ID,
        "saved Mode definition has the wrong id"
    );
    ensure!(
        observation.run.mode_id == MODE_EDITOR_ID,
        "workflow run belongs to another Mode"
    );
    ensure!(
        observation.run.graph_revision == observation.graph_revision,
        "Mode and workflow run graph revisions differ"
    );
    ensure!(
        observation.instruction_prompt == definition_prompt(observation),
        "saved Mode and model instruction Prompt differ"
    );
    ensure!(
        observation.run.graph_hash == observation.compiled_graph_hash,
        "saved Mode workflow does not compile to the run graph hash"
    );
    Ok(())
}

fn assert_graph_update(observation: &ModeObservation, original: &RunObservation) -> Result<()> {
    assert_valid_snapshot(observation)?;
    ensure!(
        observation.compiled_graph_hash != original.graph_hash,
        "graph-updated Turn retained the original graph hash"
    );
    ensure!(
        observation.run.run_id != original.run_id,
        "graph-updated Turn retained the original run id"
    );
    ensure!(
        observation.run.lineage_id == original.lineage_id,
        "graph-updated Turn changed the workflow lineage"
    );
    let archives = observation.workflow["archivedRuns"]
        .as_array()
        .context("workflow archivedRuns is missing")?;
    ensure!(
        archives.iter().any(|archive| {
            archive["outcome"] == "modeUpdated"
                && archive["runId"].as_str() == Some(original.run_id.as_str())
                && archive["lineageId"].as_str() == Some(original.lineage_id.as_str())
                && archive["graphHash"].as_str() == Some(original.graph_hash.as_str())
        }),
        "graph update did not archive the original run as modeUpdated"
    );
    Ok(())
}

fn assert_prompt_only_update(
    observation: &ModeObservation,
    expected: &ModeObservation,
) -> Result<()> {
    assert_valid_snapshot(observation)?;
    ensure!(
        definition_prompt(observation) != definition_prompt(expected),
        "prompt-only update did not change the saved Mode prompt"
    );
    ensure!(
        observation.compiled_graph_hash == expected.compiled_graph_hash
            && observation.graph_revision == expected.graph_revision,
        "prompt-only update changed the graph identity"
    );
    ensure!(
        observation.run == expected.run,
        "prompt-only update changed the run or lineage"
    );
    Ok(())
}

fn assert_same_snapshot(
    observation: &ModeObservation,
    expected: &ModeObservation,
    message: &str,
) -> Result<()> {
    assert_valid_snapshot(observation)?;
    ensure!(observation.definition == expected.definition, "{message}");
    ensure!(
        definition_prompt(observation) == definition_prompt(expected),
        "{message}"
    );
    ensure!(
        observation.compiled_graph_hash == expected.compiled_graph_hash
            && observation.graph_revision == expected.graph_revision,
        "{message}"
    );
    ensure!(observation.run == expected.run, "{message}");
    Ok(())
}

fn quiet_window(status_file: &Path) -> Result<serde_json::Value> {
    let before = plan_recovery_read_status(status_file)?;
    ensure!(
        before.rejected == 0,
        "fixture rejected a request before the mode-editor quiet window"
    );
    thread::sleep(Duration::from_secs(2));
    let after = plan_recovery_read_status(status_file)?;
    ensure!(
        before == after,
        "provider traffic appeared during the mode-editor quiet window: \
         {before:?} -> {after:?}"
    );
    Ok(serde_json::json!({
        "before": before,
        "after": after,
        "quietWindowMillis": 2_000,
    }))
}

fn count_dart_errors(source: &Path) -> Result<usize> {
    let log = fs::read_to_string(source)?;
    Ok(log
        .lines()
        .filter(|line| {
            line.contains("Unhandled exception")
                || line.contains("Bad state:")
                || line.contains("DriverError")
                || line.contains("FormatException")
                || line.contains("Compilation failed")
                || line.contains("E/flutter")
                || line.contains("] E/flutter")
        })
        .count())
}

fn read_mode_observation(home: &Path, thread_id: &str) -> Result<ModeObservation> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(read_mode_observation_async(home, thread_id))
}

async fn read_mode_observation_async(home: &Path, thread_id: &str) -> Result<ModeObservation> {
    let sessions = home.join("v2/sessions");
    let mut matching = Vec::new();
    if sessions.is_dir() {
        for entry in fs::read_dir(&sessions)? {
            let path = entry?.path().join("history.sqlite");
            if !path.is_file() {
                continue;
            }
            let mut connection = SqliteConnection::connect_with(
                &SqliteConnectOptions::new().filename(&path).read_only(true),
            )
            .await?;
            let owner = sea_orm::sqlx::query("SELECT thread_id FROM history_meta WHERE id=1")
                .fetch_optional(&mut connection)
                .await?
                .map(|row| row.try_get::<String, _>("thread_id"))
                .transpose()?;
            connection.close().await?;
            if owner.as_deref() == Some(thread_id) {
                matching.push(path);
            }
        }
    }
    ensure!(
        matching.len() == 1,
        "expected one history.sqlite for mode-editor Thread, found {}",
        matching.len()
    );
    let path = matching.remove(0);
    let mut connection = SqliteConnection::connect_with(
        &SqliteConnectOptions::new().filename(&path).read_only(true),
    )
    .await?;
    let checkpoint_payload: String =
        sea_orm::sqlx::query("SELECT payload FROM session_checkpoint WHERE id=1")
            .fetch_one(&mut connection)
            .await?
            .try_get("payload")?;
    let checkpoint: serde_json::Value = serde_json::from_str(&checkpoint_payload)?;
    ensure!(
        checkpoint["threadId"] == thread_id,
        "checkpoint belongs to another Thread"
    );
    let extensions = &checkpoint["state"]["extensions"];
    let mode_record = &extensions["studio.mode"];
    let mode_payload = &mode_record["payload"];
    ensure!(
        mode_payload["format"] == "pl.studio.mode",
        "checkpoint has no Mode extension"
    );
    let mode_version = mode_payload["version"]
        .as_u64()
        .context("Mode payload version is missing")?;
    let mode_content = parse_embedded_json(&mode_payload["content"], "Mode payload content")?;
    let definition = mode_content["definition"].clone();
    ensure!(
        definition.is_object(),
        "Mode payload content has no definition"
    );
    let graph_revision = mode_content["graphRevision"]
        .as_u64()
        .context("Mode payload graphRevision is missing")?;
    let frozen_turn_id = mode_content["frozenTurnId"]
        .as_str()
        .context("Mode payload frozenTurnId is missing")?
        .to_owned();
    let compiled_graph_hash = compile_workflow_hash(definition["workflow"].clone())?;

    let instructions = parse_embedded_json(
        &extensions["studio.instructions"]["payload"]["content"],
        "instruction snapshot",
    )?;
    let instruction_prompt = instructions["developer"]
        .as_array()
        .context("instruction blocks missing")?
        .iter()
        .find(|block| block["source"]["kind"] == "executionProfile")
        .and_then(|block| block["content"].as_str())
        .context("saved Mode instruction block missing")?
        .to_owned();

    let workflow_record = &extensions["studio.workflow"];
    let workflow_payload = &workflow_record["payload"];
    ensure!(
        workflow_payload["format"] == "pl.studio.workflow",
        "checkpoint has no workflow extension"
    );
    let workflow = parse_embedded_json(&workflow_payload["content"], "workflow payload content")?;
    let current_run = workflow["currentRun"]
        .as_object()
        .context("workflow currentRun is missing")?;
    let run = RunObservation {
        run_id: required_string(current_run, "runId")?,
        lineage_id: required_string(current_run, "lineageId")?,
        graph_hash: required_string(current_run, "graphHash")?,
        graph_revision: current_run["graphRevision"]
            .as_u64()
            .context("workflow graphRevision is missing")?,
        mode_id: required_string(current_run, "modeId")?,
        current_state_id: required_string(current_run, "currentStateId")?,
        lifecycle: required_string(current_run, "lifecycle")?,
    };
    let context_rows = sea_orm::sqlx::query("SELECT payload FROM current_context ORDER BY ordinal")
        .fetch_all(&mut connection)
        .await?;
    let history = context_rows
        .into_iter()
        .map(|row| {
            let payload: String = row.try_get("payload")?;
            Ok(serde_json::from_str::<serde_json::Value>(&payload)?)
        })
        .collect::<Result<Vec<_>>>()?;
    connection.close().await?;
    Ok(ModeObservation {
        thread_id: thread_id.to_owned(),
        mode_extension_revision: mode_record["revision"]
            .as_u64()
            .context("Mode extension revision is missing")?,
        mode_version,
        definition,
        graph_revision,
        frozen_turn_id,
        compiled_graph_hash,
        instruction_prompt,
        workflow_extension_revision: workflow_record["revision"]
            .as_u64()
            .context("workflow extension revision is missing")?,
        workflow,
        run,
        history_records: history.len(),
        history: serde_json::json!(history),
    })
}

fn parse_embedded_json(value: &serde_json::Value, label: &str) -> Result<serde_json::Value> {
    let content = value
        .as_str()
        .with_context(|| format!("{label} is not a JSON string"))?;
    serde_json::from_str(content).with_context(|| format!("{label} is invalid JSON"))
}

fn compile_workflow_hash(workflow: serde_json::Value) -> Result<String> {
    let definition = serde_json::from_value(workflow)
        .context("saved Mode workflow does not match the workflow protocol")?;
    let compiled = pl_studio_runtime::mode::compile_workflow_definition(definition)
        .map_err(|error| anyhow::anyhow!("saved Mode workflow is invalid: {error}"))?;
    Ok(compiled.graph_hash().to_owned())
}

fn required_string(
    object: &serde_json::Map<String, serde_json::Value>,
    field: &str,
) -> Result<String> {
    object
        .get(field)
        .and_then(serde_json::Value::as_str)
        .map(str::to_owned)
        .with_context(|| format!("workflow {field} is missing"))
}
