use super::{
    OwnedProcess, driver_command, history_lock_database, require_native_exit, sanitize_driver_line,
    sanitize_requests, start_timeline_history_gui, wait_for_gui_exit, wait_for_vm,
    write_fixture_log, write_realtime_driver_evidence, write_sanitized_log,
};
use anyhow::{Context, Result, ensure};
use pl_provider_fixture::FixtureLiveStatus;
use sea_orm::sqlx::{
    Connection as _,
    sqlite::{SqliteConnectOptions, SqliteConnection},
};
use serde::Serialize;
use serde_json::{Value, json};
use std::fmt;
use std::fs::{self, File};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

const TIMELINE_HISTORY_20K_SEED_RECORD_GLOB: &str = concat!(
    "model:*:presentation:item:*:",
    "timeline-history-20k-seed-[0-9][0-9]-item-[0-9][0-9][0-9][0-9]:text:0"
);
const TIMELINE_HISTORY_20K_GROWTH_RECORD_GLOB: &str = concat!(
    "model:*:presentation:item:*:",
    "timeline-history-20k-growth-[0-9][0-9]-item-[0-9][0-9][0-9][0-9]:text:0"
);

pub(super) struct Scenario<'a> {
    pub(super) workspace: &'a Path,
    pub(super) app_dir: &'a Path,
    pub(super) home: &'a Path,
    pub(super) working: &'a Path,
    pub(super) output: &'a Path,
    pub(super) fixture_log: &'a Path,
    pub(super) requests_file: &'a Path,
    pub(super) status_file: &'a Path,
    pub(super) interrupt: &'a mpsc::Receiver<()>,
}

#[derive(Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct HistoryAudit {
    thread_id: String,
    canonical_atoms: i64,
    distinct_canonical_ids: i64,
    seed_text_items: i64,
    distinct_seed_text_ids: i64,
    growth_text_items: i64,
    distinct_growth_text_ids: i64,
    history_items: i64,
    history_turns: i64,
    applied_write_seq: i64,
    database_bytes: u64,
    wal_bytes: Option<u64>,
    #[serde(skip)]
    timeline_records: Vec<String>,
    #[serde(skip)]
    history_item_records: Vec<String>,
    #[serde(skip)]
    history_turn_records: Vec<String>,
}

impl fmt::Debug for HistoryAudit {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HistoryAudit")
            .field("thread_id", &self.thread_id)
            .field("canonical_atoms", &self.canonical_atoms)
            .field("distinct_canonical_ids", &self.distinct_canonical_ids)
            .field("seed_text_items", &self.seed_text_items)
            .field("distinct_seed_text_ids", &self.distinct_seed_text_ids)
            .field("growth_text_items", &self.growth_text_items)
            .field("distinct_growth_text_ids", &self.distinct_growth_text_ids)
            .field("history_items", &self.history_items)
            .field("history_turns", &self.history_turns)
            .field("applied_write_seq", &self.applied_write_seq)
            .field("database_bytes", &self.database_bytes)
            .field("wal_bytes", &self.wal_bytes)
            .field("timeline_record_rows", &self.timeline_records.len())
            .field("history_item_rows", &self.history_item_records.len())
            .field("history_turn_rows", &self.history_turn_records.len())
            .finish()
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PhaseSummary {
    phase: String,
    launcher_pid: u32,
    gui_pid: u64,
    launcher_command_to_vm_millis: u128,
    process_start_to_driver_observable_millis: u128,
    driver_exit: Option<i32>,
    gui_exit: Option<i32>,
}

struct PhaseOutcome {
    summary: PhaseSummary,
    cold_observation: Option<ColdPhaseObservation>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ColdPhaseObservation {
    thread_id: String,
    final_queue: QueueWatermark,
    before_scroll: QueueWatermark,
    after_scroll: QueueWatermark,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct QueueWatermark {
    history_admitted: u64,
    history_durable: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct ColdLifecycleCheck {
    phase: String,
    previous_closed: u64,
    open: u64,
    after_close: u64,
    exact_inventory_unchanged: bool,
}

pub(super) fn run(context: &Scenario<'_>, mut fixture: OwnedProcess) -> Result<()> {
    let project = context.working.join("timeline-history-20k-project");
    let mut phases = Vec::new();
    let mut seed_audit = None;
    let mut cold_audits = Vec::new();
    let mut cold_lifecycle_checks = Vec::new();
    let mut growth_before = None;
    let mut growth_after = None;
    let journey = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated timeline-history-20k project"
        );

        let mut database: Option<PathBuf> = None;
        for phase in ["seed", "cold-1", "cold-2", "cold-3", "growth"] {
            if phase == "growth" {
                growth_before = Some(history_audit(
                    database
                        .as_deref()
                        .context("growth has no seeded history database")?,
                )?);
            }
            let outcome = run_phase(context, &project, phase, database.as_deref(), &mut fixture)?;
            phases.push(outcome.summary);

            let current_database = match database {
                Some(ref path) => path.clone(),
                None => history_lock_database(context.home)?,
            };
            database = Some(current_database.clone());
            let audit = history_audit(&current_database)?;
            match phase {
                "seed" => {
                    ensure!(
                        audit.seed_text_items == 20_000
                            && audit.distinct_seed_text_ids == 20_000
                            && audit.growth_text_items == 0
                            && audit.canonical_atoms > 20_000,
                        "seed did not persist exactly 20,000 unique text items plus normal user facts: {audit:?}"
                    );
                    seed_audit = Some(audit);
                }
                "cold-1" | "cold-2" | "cold-3" => {
                    let seed = seed_audit
                        .as_ref()
                        .context("cold phase has no seed audit")?;
                    let previous_closed = cold_audits.last().unwrap_or(seed);
                    let observation = outcome
                        .cold_observation
                        .as_ref()
                        .context("cold phase has no strict watermark observation")?;
                    cold_lifecycle_checks.push(verify_cold_lifecycle(
                        phase,
                        seed,
                        previous_closed,
                        &audit,
                        observation,
                    )?);
                    cold_audits.push(audit);
                }
                "growth" => {
                    ensure!(
                        audit.seed_text_items == 20_000
                            && audit.distinct_seed_text_ids == 20_000
                            && audit.growth_text_items == 2_000
                            && audit.distinct_growth_text_ids == 2_000
                            && audit.canonical_atoms > 22_000,
                        "growth did not persist exactly 2,000 additional unique text items: {audit:?}"
                    );
                    growth_after = Some(audit);
                }
                _ => unreachable!(),
            }
        }
        Ok(())
    })();

    let fixture_result = fixture.stop(context.requests_file);
    drop(fixture);
    let fixture_log_failure =
        write_fixture_log(context.fixture_log, &context.output.join("fixture.log"))
            .err()
            .map(|error| error.to_string());
    let requests_result = read_requests(context.requests_file, context.output);
    let requests_failure = requests_result
        .as_ref()
        .err()
        .map(|error| error.to_string());
    let requests = requests_result.unwrap_or_default();
    let accepted = requests
        .iter()
        .filter(|request| request["accepted"] == true)
        .count();
    let rejected = requests
        .iter()
        .filter(|request| request["accepted"] == false)
        .count();
    let live_status_result = read_required_live_status(context.status_file);
    let live_status_failure = live_status_result
        .as_ref()
        .err()
        .map(|error| error.to_string());
    let live_status = live_status_result.ok();
    let journey_failure = journey.as_ref().err().map(|error| error.to_string());
    let fixture_stop_failure = fixture_result.as_ref().err().map(|error| error.to_string());
    let stopped_cleanly = fixture_result.as_ref().is_ok_and(|status| status.success());
    let final_result = final_verdict(&FinalGate {
        journey_failure: journey_failure.as_deref(),
        fixture_stop_failure: fixture_stop_failure.as_deref(),
        fixture_stopped_cleanly: stopped_cleanly,
        fixture_log_failure: fixture_log_failure.as_deref(),
        requests_failure: requests_failure.as_deref(),
        accepted,
        rejected,
        status_failure: live_status_failure.as_deref(),
        status: live_status.as_ref(),
    });
    let verdict = verdict_json(&final_result);
    let aggregate = json!({
        "scenario": "timeline-history-20k",
        "platform": "linux",
        "processCold": true,
        "osPageCacheControlled": false,
        "osPageCacheNote": "GUI processes are cold; host Linux page cache is not cleared or controlled",
        "profile": "Flutter profile; release-profile Rust bridge",
        "shape": {
            "seedBatches": 10,
            "seedTextItemsPerBatch": 2_000,
            "seedTextItems": 20_000,
            "growthBatches": 20,
            "growthTextItemsPerBatch": 100,
            "growthTextItems": 2_000,
            "textBodyBytesPerItem": 32,
            "metadataHeavyShortText": true,
            "largeBodyOrComplexMarkdownClaimed": false,
        },
        "tokenMeasurement": {
            "status": "notMeasured",
            "fixtureUsageIsTokenizerMeasurement": false,
        },
        "storageInterpretation": {
            "queueBytes": "writer queue occupancy, not database write bytes",
            "databaseAndWalBytes": "logical file occupancy, not physical IO",
            "procIo": "whole GUI process including embedded Runtime",
            "sequenceNumbersAreTransactions": false,
            "transactionCount": null,
        },
        "phases": phases,
        "seedAudit": seed_audit,
        "coldAudits": cold_audits,
        "coldLifecycleChecks": cold_lifecycle_checks,
        "growthBefore": growth_before,
        "growthAfter": growth_after,
        "fixture": {
            "requestBodyLimitBytes": pl_provider_fixture::GUI_TIMELINE_HISTORY_20K_REQUEST_BODY_BYTES.get(),
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "status": live_status.as_ref(),
            "statusError": live_status_failure,
            "requestEvidenceError": requests_failure,
            "fixtureLogError": fixture_log_failure,
            "stopError": fixture_stop_failure,
            "stoppedCleanly": stopped_cleanly,
        },
        "pass": verdict["pass"],
        "failure": verdict["failure"],
    });
    fs::write(
        context.output.join("timeline-history-20k.json"),
        serde_json::to_vec_pretty(&aggregate)?,
    )?;
    fs::write(
        context.output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&aggregate["fixture"])?,
    )?;

    final_result
}

struct FinalGate<'a> {
    journey_failure: Option<&'a str>,
    fixture_stop_failure: Option<&'a str>,
    fixture_stopped_cleanly: bool,
    fixture_log_failure: Option<&'a str>,
    requests_failure: Option<&'a str>,
    accepted: usize,
    rejected: usize,
    status_failure: Option<&'a str>,
    status: Option<&'a FixtureLiveStatus>,
}

fn final_verdict(gate: &FinalGate<'_>) -> Result<()> {
    ensure!(
        gate.journey_failure.is_none(),
        "timeline-history-20k journey failed: {}",
        gate.journey_failure.unwrap_or("unknown journey failure")
    );
    ensure!(
        gate.fixture_stop_failure.is_none(),
        "timeline-history-20k fixture stop failed: {}",
        gate.fixture_stop_failure
            .unwrap_or("unknown fixture stop failure")
    );
    ensure!(
        gate.fixture_stopped_cleanly,
        "timeline-history-20k fixture did not exit cleanly"
    );
    ensure!(
        gate.fixture_log_failure.is_none(),
        "timeline-history-20k fixture log evidence failed: {}",
        gate.fixture_log_failure
            .unwrap_or("unknown fixture log failure")
    );
    ensure!(
        gate.requests_failure.is_none(),
        "timeline-history-20k request evidence failed: {}",
        gate.requests_failure
            .unwrap_or("unknown request evidence failure")
    );
    ensure!(
        gate.rejected == 0 && gate.accepted >= 30,
        "timeline-history-20k fixture requests were incomplete: accepted={} rejected={}",
        gate.accepted,
        gate.rejected
    );
    ensure!(
        gate.status_failure.is_none(),
        "timeline-history-20k fixture status failed: {}",
        gate.status_failure
            .unwrap_or("unknown fixture status failure")
    );
    let status = gate
        .status
        .context("timeline-history-20k fixture status is required")?;
    ensure!(
        status.accepted == gate.accepted
            && status.rejected == gate.rejected
            && status.rejected == 0
            && status.remaining_optional,
        "timeline-history-20k strict script did not consume every required step or status disagreed with requests: {status:?}"
    );
    Ok(())
}

fn verdict_json(result: &Result<()>) -> Value {
    json!({
        "pass": result.is_ok(),
        "failure": result.as_ref().err().map(|error| error.to_string()),
    })
}

fn read_requests(path: &Path, output: &Path) -> Result<Vec<Value>> {
    ensure!(
        path.is_file(),
        "timeline-history-20k fixture request evidence is missing"
    );
    sanitize_requests(path, &output.join("requests.json"))?;
    serde_json::from_slice(&fs::read(path)?).context("fixture request evidence is malformed")
}

fn read_required_live_status(path: &Path) -> Result<FixtureLiveStatus> {
    ensure!(
        path.is_file(),
        "timeline-history-20k fixture status is missing"
    );
    serde_json::from_slice(&fs::read(path)?).context("fixture status is malformed")
}

fn run_phase(
    context: &Scenario<'_>,
    project: &Path,
    phase: &str,
    database: Option<&Path>,
    fixture: &mut OwnedProcess,
) -> Result<PhaseOutcome> {
    let gui_log = context
        .working
        .join(format!("timeline-history-20k-{phase}-gui.log"));
    let driver_log = context
        .working
        .join(format!("timeline-history-20k-{phase}-driver.log"));
    let stage = context
        .working
        .join(format!("timeline-history-20k-{phase}-stage"));
    let pid_file = context
        .working
        .join(format!("timeline-history-20k-{phase}-pid"));
    let native_exit = context
        .output
        .join(format!("timeline-history-20k-{phase}-native-exit.json"));
    let started = Instant::now();
    let mut gui = None;
    let mut driver = None;
    let mut driver_exit = None;
    let mut gui_exit = None;
    let phase_result = (|| -> Result<PhaseOutcome> {
        gui = Some(start_timeline_history_gui(
            context.workspace,
            context.home,
            &gui_log,
            &native_exit,
        )?);
        let active_gui = gui
            .as_mut()
            .context("timeline-history-20k GUI handle is missing")?;
        let launcher_pid = active_gui.child.id();
        let vm_url = wait_for_vm(&gui_log, active_gui, fixture, context.interrupt)?;
        let process_start_to_vm_millis = started.elapsed().as_millis();
        driver = Some(start_driver(
            context,
            project,
            phase,
            &vm_url,
            &driver_log,
            database,
        )?);
        let active_driver = driver
            .as_mut()
            .context("timeline-history-20k Driver handle is missing")?;
        let gui_pid = wait_for_driver_pid(
            &pid_file,
            &stage,
            active_driver,
            active_gui,
            fixture,
            context.interrupt,
            phase,
        )?;
        let process_start_to_driver_observable_millis = linux_process_age_millis(gui_pid)?;
        let status = wait_for_driver(&stage, active_driver, fixture, context.interrupt, phase)?;
        driver_exit = Some(status);
        ensure!(
            status.success(),
            "timeline-history-20k {phase} Driver failed: {status}"
        );
        let status = wait_for_gui_exit(active_gui, Duration::from_secs(180), phase)?;
        gui_exit = Some(status);
        ensure!(
            status.success(),
            "timeline-history-20k {phase} GUI failed: {status}"
        );

        let report_path = context
            .output
            .join(format!("timeline-history-20k-{phase}.json"));
        let mut report: Value = serde_json::from_slice(
            &fs::read(&report_path)
                .with_context(|| format!("{phase} Driver wrote no phase report"))?,
        )?;
        ensure!(
            report["pass"] == true && report["shutdown"] == "completed",
            "timeline-history-20k {phase} did not pass: {report}"
        );
        ensure!(
            report["pid"].as_u64() == Some(gui_pid),
            "{phase} Driver/native PID mismatch"
        );
        let cold_observation = phase
            .starts_with("cold-")
            .then(|| cold_phase_observation(&report, phase))
            .transpose()?;
        report["harnessTiming"] = json!({
            "launcherPid": launcher_pid,
            "actualGuiPid": gui_pid,
            "launcherCommandToVmMillis": process_start_to_vm_millis,
            "processStartToDriverObservableMillis": process_start_to_driver_observable_millis,
            "processStartSource": "/proc/<actual-gui-pid>/stat starttime against /proc/uptime",
            "buildTimeIncludedInProcessStartToDriver": false,
            "launcherCommandToVmMayIncludeBuild": true,
        });
        fs::write(&report_path, serde_json::to_vec_pretty(&report)?)?;
        require_native_exit(&native_exit, Some(gui_pid))?;
        Ok(PhaseOutcome {
            summary: PhaseSummary {
                phase: phase.to_owned(),
                launcher_pid,
                gui_pid,
                launcher_command_to_vm_millis: process_start_to_vm_millis,
                process_start_to_driver_observable_millis,
                driver_exit: status_code(driver_exit),
                gui_exit: status_code(gui_exit),
            },
            cold_observation,
        })
    })();

    let cleanup_result = if phase_result.is_err() {
        settle_failed_phase(
            driver.as_mut(),
            gui.as_mut(),
            &mut driver_exit,
            &mut gui_exit,
        )
    } else {
        Ok(())
    };
    let redactions = [
        (context.home.to_string_lossy().into_owned(), "<home>"),
        (context.working.to_string_lossy().into_owned(), "<coord>"),
        (context.output.to_string_lossy().into_owned(), "<output>"),
        (context.app_dir.to_string_lossy().into_owned(), "<app>"),
        (
            context.workspace.to_string_lossy().into_owned(),
            "<workspace>",
        ),
    ];
    let evidence_result = write_phase_evidence(
        context,
        phase,
        &gui_log,
        &driver_log,
        driver_exit,
        gui_exit,
        phase_result.as_ref().err(),
        &redactions,
    );
    finish_phase_result(phase_result, cleanup_result, evidence_result)
}

fn status_code(status: Option<std::process::ExitStatus>) -> Option<i32> {
    status.and_then(|status| status.code())
}

fn settle_failed_phase(
    driver: Option<&mut OwnedProcess>,
    gui: Option<&mut OwnedProcess>,
    driver_exit: &mut Option<std::process::ExitStatus>,
    gui_exit: &mut Option<std::process::ExitStatus>,
) -> Result<()> {
    let driver_result = settle_failed_process(driver, driver_exit, "Driver");
    let gui_result = settle_failed_process(gui, gui_exit, "GUI");
    driver_result?;
    gui_result
}

fn settle_failed_process(
    process: Option<&mut OwnedProcess>,
    exit: &mut Option<std::process::ExitStatus>,
    label: &str,
) -> Result<()> {
    let Some(process) = process else {
        return Ok(());
    };
    if exit.is_some() {
        return Ok(());
    }
    match process.exit_status() {
        Ok(Some(status)) => {
            process.mark_reaped();
            *exit = Some(status);
            return Ok(());
        }
        Ok(None) => {}
        Err(error) => {
            process.terminate();
            return Err(error).with_context(|| format!("failed to observe {label} before cleanup"));
        }
    }
    let _ = process.request_stop();
    match process.wait_exit(Duration::from_secs(30)) {
        Ok(Some(status)) => {
            *exit = Some(status);
            Ok(())
        }
        Ok(None) => {
            process.terminate();
            *exit = process.exit_status()?;
            ensure!(exit.is_some(), "{label} remained live after cleanup");
            Ok(())
        }
        Err(error) => {
            process.terminate();
            Err(error).with_context(|| format!("failed to reap {label} during cleanup"))
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn write_phase_evidence(
    context: &Scenario<'_>,
    phase: &str,
    gui_log: &Path,
    driver_log: &Path,
    driver_exit: Option<std::process::ExitStatus>,
    gui_exit: Option<std::process::ExitStatus>,
    phase_error: Option<&anyhow::Error>,
    redactions: &[(String, &str)],
) -> Result<()> {
    let gui_result = if gui_log.is_file() {
        write_sanitized_log(
            gui_log,
            &context
                .output
                .join(format!("timeline-history-20k-{phase}-gui.log")),
        )
    } else {
        Ok(())
    };
    let driver_result = write_realtime_driver_evidence(
        driver_log,
        context.output,
        &format!("timeline-history-20k-{phase}"),
        driver_exit,
        phase_error,
        redactions,
    );
    let failure = phase_error.map(|error| sanitize_driver_line(&error.to_string(), redactions));
    let exit_result = fs::write(
        context
            .output
            .join(format!("timeline-history-20k-{phase}-exit.json")),
        serde_json::to_vec_pretty(&json!({
            "phase": phase,
            "driverExit": status_code(driver_exit),
            "guiExit": status_code(gui_exit),
            "failure": failure,
        }))?,
    )
    .context("failed to write timeline-history-20k phase exit evidence");
    gui_result?;
    driver_result?;
    exit_result
}

fn finish_phase_result<T>(
    phase_result: Result<T>,
    cleanup_result: Result<()>,
    evidence_result: Result<()>,
) -> Result<T> {
    match phase_result {
        Ok(value) => {
            cleanup_result?;
            evidence_result?;
            Ok(value)
        }
        Err(primary) => {
            let mut message = format!("{primary:#}");
            if let Err(error) = cleanup_result {
                message.push_str(&format!("; process cleanup also failed: {error:#}"));
            }
            if let Err(error) = evidence_result {
                message.push_str(&format!("; evidence collection also failed: {error:#}"));
            }
            Err(anyhow::anyhow!(message))
        }
    }
}

fn start_driver(
    context: &Scenario<'_>,
    project: &Path,
    phase: &str,
    vm_url: &str,
    log_path: &Path,
    database: Option<&Path>,
) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = driver_command(
        context.app_dir,
        "test_driver/timeline_history_20k_journey.dart",
    );
    command
        .arg(phase)
        .arg(vm_url)
        .arg(project)
        .arg(context.output)
        .arg(context.working)
        .env("ANYWORK_HOME", context.home)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    if let Some(database) = database {
        command.env("ANYWORK_TIMELINE_HISTORY_DB", database);
    }
    OwnedProcess::start(&mut command, false)
}

fn wait_for_driver_pid(
    pid_file: &Path,
    stage: &Path,
    driver: &mut OwnedProcess,
    gui: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
    phase: &str,
) -> Result<u64> {
    let deadline = Instant::now() + Duration::from_secs(120);
    loop {
        if pid_file.is_file() {
            let pid = fs::read_to_string(pid_file)?
                .trim()
                .parse::<u64>()
                .context("Driver PID evidence is not an integer")?;
            ensure!(pid > 0, "Driver reported an invalid GUI PID");
            return Ok(pid);
        }
        ensure!(
            !driver.exited()?,
            "{phase} Driver exited before publishing the actual GUI PID"
        );
        ensure!(
            !gui.exited()?,
            "{phase} GUI exited before Driver observation"
        );
        ensure!(
            !fixture.exited()?,
            "fixture exited during timeline-history-20k {phase}"
        );
        ensure!(
            interrupt.try_recv().is_err(),
            "timeline-history-20k {phase} cancelled"
        );
        ensure!(
            Instant::now() < deadline,
            "timeline-history-20k {phase} Driver observation timed out (stage: {})",
            fs::read_to_string(stage).unwrap_or_else(|_| "connect".into())
        );
        thread::sleep(Duration::from_millis(100));
    }
}

fn wait_for_driver(
    stage: &Path,
    driver: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
    phase: &str,
) -> Result<std::process::ExitStatus> {
    let deadline = Instant::now() + Duration::from_secs(7_200);
    loop {
        if let Some(status) = driver.child.try_wait()? {
            driver.mark_reaped();
            return Ok(status);
        }
        ensure!(
            !fixture.exited()?,
            "timeline-history-20k {phase} fixture exited before Driver completion"
        );
        ensure!(
            interrupt.try_recv().is_err(),
            "timeline-history-20k {phase} cancelled"
        );
        ensure!(
            Instant::now() < deadline,
            "timeline-history-20k {phase} timed out (stage: {})",
            fs::read_to_string(stage).unwrap_or_else(|_| "connect".into())
        );
        thread::sleep(Duration::from_millis(200));
    }
}

fn history_audit(database: &Path) -> Result<HistoryAudit> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    let database = database.to_owned();
    let display = database.clone();
    let query_database = database.clone();
    let mut audit = runtime.block_on(async move {
        let options = SqliteConnectOptions::new()
            .filename(&query_database)
            .read_only(true);
        let mut connection = SqliteConnection::connect_with(&options).await?;
        let row: (String, i64, i64, i64, i64, i64, i64, i64, i64, i64) = sea_orm::sqlx::query_as(
            "SELECT
                    (SELECT thread_id FROM history_meta WHERE id=1),
                    (SELECT COUNT(*) FROM timeline_records),
                    (SELECT COUNT(DISTINCT record_id) FROM timeline_records),
                    (SELECT COUNT(*) FROM timeline_records
                       WHERE record_id GLOB ?),
                    (SELECT COUNT(DISTINCT record_id) FROM timeline_records
                       WHERE record_id GLOB ?),
                    (SELECT COUNT(*) FROM timeline_records
                       WHERE record_id GLOB ?),
                    (SELECT COUNT(DISTINCT record_id) FROM timeline_records
                       WHERE record_id GLOB ?),
                    (SELECT COUNT(*) FROM history_items),
                    (SELECT COUNT(*) FROM history_turns),
                    (SELECT applied_write_seq FROM history_meta WHERE id=1)",
        )
        .bind(TIMELINE_HISTORY_20K_SEED_RECORD_GLOB)
        .bind(TIMELINE_HISTORY_20K_SEED_RECORD_GLOB)
        .bind(TIMELINE_HISTORY_20K_GROWTH_RECORD_GLOB)
        .bind(TIMELINE_HISTORY_20K_GROWTH_RECORD_GLOB)
        .fetch_one(&mut connection)
        .await
        .with_context(|| format!("failed to audit {}", display.display()))?;
        let timeline_records = sea_orm::sqlx::query_scalar::<_, String>(
            "SELECT json_array(append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload)
             FROM timeline_records ORDER BY append_seq",
        )
        .fetch_all(&mut connection)
        .await
        .with_context(|| format!("failed to read exact timeline inventory from {}", display.display()))?;
        let history_item_records = sea_orm::sqlx::query_scalar::<_, String>(
            "SELECT json_array(ordinal,item_id,turn_id,kind,revision,lifecycle,created_at,updated_at,payload,last_write_seq)
             FROM history_items ORDER BY ordinal",
        )
        .fetch_all(&mut connection)
        .await
        .with_context(|| format!("failed to read exact item inventory from {}", display.display()))?;
        let history_turn_records = sea_orm::sqlx::query_scalar::<_, String>(
            "SELECT json_array(turn_id,first_ordinal,last_ordinal,revision,payload,last_write_seq)
             FROM history_turns ORDER BY turn_id",
        )
        .fetch_all(&mut connection)
        .await
        .with_context(|| format!("failed to read exact Turn inventory from {}", display.display()))?;
        Ok::<_, anyhow::Error>(HistoryAudit {
            thread_id: row.0,
            canonical_atoms: row.1,
            distinct_canonical_ids: row.2,
            seed_text_items: row.3,
            distinct_seed_text_ids: row.4,
            growth_text_items: row.5,
            distinct_growth_text_ids: row.6,
            history_items: row.7,
            history_turns: row.8,
            applied_write_seq: row.9,
            database_bytes: 0,
            wal_bytes: None,
            timeline_records,
            history_item_records,
            history_turn_records,
        })
    })?;
    audit.database_bytes = fs::metadata(&database)?.len();
    let wal = PathBuf::from(format!("{}-wal", database.display()));
    audit.wal_bytes = wal
        .is_file()
        .then(|| fs::metadata(wal).map(|value| value.len()))
        .transpose()?;
    Ok(audit)
}

fn same_persisted_inventory(seed: &HistoryAudit, cold: &HistoryAudit) -> bool {
    seed.thread_id == cold.thread_id
        && seed.canonical_atoms == cold.canonical_atoms
        && seed.distinct_canonical_ids == cold.distinct_canonical_ids
        && seed.seed_text_items == cold.seed_text_items
        && seed.distinct_seed_text_ids == cold.distinct_seed_text_ids
        && seed.growth_text_items == cold.growth_text_items
        && seed.distinct_growth_text_ids == cold.distinct_growth_text_ids
        && seed.history_items == cold.history_items
        && seed.history_turns == cold.history_turns
        && seed.timeline_records == cold.timeline_records
        && seed.history_item_records == cold.history_item_records
        && seed.history_turn_records == cold.history_turn_records
}

fn cold_phase_observation(report: &Value, phase: &str) -> Result<ColdPhaseObservation> {
    let (thread_id, final_queue) =
        final_persistence_watermark(&report["persistence"], &format!("{phase}.persistence"))?;
    let watermarks = report["coldWatermarks"]
        .as_object()
        .with_context(|| format!("{phase}.coldWatermarks must be an object"))?;
    let before_scroll = queue_watermark(
        watermarks
            .get("beforeScroll")
            .with_context(|| format!("{phase}.coldWatermarks.beforeScroll is missing"))?,
        &format!("{phase}.coldWatermarks.beforeScroll"),
        false,
    )?;
    let after_scroll = queue_watermark(
        watermarks
            .get("afterScroll")
            .with_context(|| format!("{phase}.coldWatermarks.afterScroll is missing"))?,
        &format!("{phase}.coldWatermarks.afterScroll"),
        false,
    )?;
    Ok(ColdPhaseObservation {
        thread_id,
        final_queue,
        before_scroll,
        after_scroll,
    })
}

fn final_persistence_watermark(value: &Value, context: &str) -> Result<(String, QueueWatermark)> {
    let object = value
        .as_object()
        .with_context(|| format!("{context} must be an object"))?;
    for field in ["pendingOperations", "pendingBytes", "inFlightBytes"] {
        ensure!(
            required_u64(object.get(field), &format!("{context}.{field}"))? == 0,
            "{context}.{field} must be zero after durability drain"
        );
    }
    let threads = object
        .get("threads")
        .and_then(Value::as_array)
        .with_context(|| format!("{context}.threads must be an array"))?;
    ensure!(
        threads.len() == 1,
        "{context}.threads must contain exactly one thread"
    );
    let thread = threads[0]
        .as_object()
        .with_context(|| format!("{context}.threads[0] must be an object"))?;
    let thread_id = thread
        .get("threadId")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .with_context(|| format!("{context}.threads[0].threadId must be a non-empty string"))?
        .to_owned();
    for field in ["pending", "pendingBytes", "inFlightBytes"] {
        ensure!(
            required_u64(thread.get(field), &format!("{context}.threads[0].{field}"))? == 0,
            "{context}.threads[0].{field} must be zero after durability drain"
        );
    }
    let watermark = QueueWatermark {
        history_admitted: required_u64(
            thread.get("historyAdmitted"),
            &format!("{context}.threads[0].historyAdmitted"),
        )?,
        history_durable: required_u64(
            thread.get("historyDurable"),
            &format!("{context}.threads[0].historyDurable"),
        )?,
    };
    ensure!(
        watermark.history_durable == watermark.history_admitted,
        "{context} is not durably drained: {watermark:?}"
    );
    Ok((thread_id, watermark))
}

fn queue_watermark(value: &Value, context: &str, require_drained: bool) -> Result<QueueWatermark> {
    let object = value
        .as_object()
        .with_context(|| format!("{context} must be an object"))?;
    for field in ["pendingOperations", "pendingBytes", "inFlightBytes"] {
        let value = required_u64(object.get(field), &format!("{context}.{field}"))?;
        if require_drained {
            ensure!(value == 0, "{context}.{field} must be zero");
        }
    }
    let watermark = QueueWatermark {
        history_admitted: required_u64(
            object.get("historyAdmitted"),
            &format!("{context}.historyAdmitted"),
        )?,
        history_durable: required_u64(
            object.get("historyDurable"),
            &format!("{context}.historyDurable"),
        )?,
    };
    ensure!(
        watermark.history_durable <= watermark.history_admitted,
        "{context}.historyDurable exceeds historyAdmitted"
    );
    Ok(watermark)
}

fn required_u64(value: Option<&Value>, field: &str) -> Result<u64> {
    value
        .and_then(Value::as_u64)
        .with_context(|| format!("{field} must be a non-negative integer"))
}

fn verify_cold_lifecycle(
    phase: &str,
    seed: &HistoryAudit,
    previous: &HistoryAudit,
    current: &HistoryAudit,
    observation: &ColdPhaseObservation,
) -> Result<ColdLifecycleCheck> {
    ensure!(
        same_persisted_inventory(seed, current),
        "{phase} changed the immutable seed inventory: seed={seed:?} cold={current:?}"
    );
    ensure!(
        observation.thread_id == seed.thread_id,
        "{phase} persistence belongs to another thread: expected={} actual={}",
        seed.thread_id,
        observation.thread_id
    );
    let previous_closed = u64::try_from(previous.applied_write_seq)
        .with_context(|| format!("{phase} previous closed watermark is negative"))?;
    let open = previous_closed
        .checked_add(1)
        .with_context(|| format!("{phase} open lifecycle watermark overflowed"))?;
    let after_close = open
        .checked_add(2)
        .with_context(|| format!("{phase} close lifecycle watermark overflowed"))?;
    let actual_after_close = u64::try_from(current.applied_write_seq)
        .with_context(|| format!("{phase} after-close watermark is negative"))?;
    ensure!(
        observation.final_queue.history_admitted == open
            && observation.final_queue.history_durable == open,
        "{phase} open lifecycle watermark mismatch: expected={open} actual={:?}",
        observation.final_queue
    );
    ensure!(
        observation.before_scroll.history_admitted == open
            && observation.after_scroll.history_admitted == open,
        "{phase} real scroll changed history admission: open={open} before={:?} after={:?}",
        observation.before_scroll,
        observation.after_scroll
    );
    ensure!(
        observation.before_scroll.history_durable <= open
            && observation.after_scroll.history_durable
                >= observation.before_scroll.history_durable
            && observation.after_scroll.history_durable <= open,
        "{phase} real scroll durability did not monotonically approach admission: before={:?} after={:?}",
        observation.before_scroll,
        observation.after_scroll
    );
    ensure!(
        actual_after_close == after_close,
        "{phase} close lifecycle watermark mismatch: previousClosed={previous_closed} open={open} expectedAfterClose={after_close} actualAfterClose={actual_after_close}"
    );
    Ok(ColdLifecycleCheck {
        phase: phase.to_owned(),
        previous_closed,
        open,
        after_close,
        exact_inventory_unchanged: true,
    })
}

fn linux_process_age_millis(pid: u64) -> Result<u128> {
    let uptime = fs::read_to_string("/proc/uptime")?
        .split_whitespace()
        .next()
        .context("/proc/uptime has no uptime field")?
        .parse::<f64>()
        .context("/proc/uptime field is not numeric")?;
    let stat = fs::read_to_string(format!("/proc/{pid}/stat"))?;
    let fields = stat
        .rsplit_once(')')
        .context("/proc PID stat has no command terminator")?
        .1
        .split_whitespace()
        .collect::<Vec<_>>();
    // The suffix begins at field 3 (`state`); starttime is Linux proc field 22.
    let start_ticks = fields
        .get(19)
        .context("/proc PID stat has no starttime field")?
        .parse::<f64>()
        .context("/proc PID starttime is not numeric")?;
    let output = Command::new("getconf").arg("CLK_TCK").output()?;
    ensure!(
        output.status.success(),
        "getconf CLK_TCK failed: {}",
        output.status
    );
    let ticks_per_second = String::from_utf8(output.stdout)?
        .trim()
        .parse::<f64>()
        .context("getconf CLK_TCK is not numeric")?;
    ensure!(
        ticks_per_second.is_finite() && ticks_per_second > 0.0,
        "getconf CLK_TCK returned an invalid value"
    );
    let age_seconds = uptime - start_ticks / ticks_per_second;
    ensure!(
        age_seconds.is_finite() && age_seconds >= 0.0,
        "actual GUI process starttime is later than /proc uptime"
    );
    Ok(Duration::from_secs_f64(age_seconds).as_millis())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn complete_status() -> FixtureLiveStatus {
        FixtureLiveStatus {
            accepted: 30,
            rejected: 0,
            total: 30,
            consumed_steps: 30,
            expected_steps: 30,
            remaining_optional: true,
        }
    }

    fn passing_gate<'a>(status: Option<&'a FixtureLiveStatus>) -> FinalGate<'a> {
        FinalGate {
            journey_failure: None,
            fixture_stop_failure: None,
            fixture_stopped_cleanly: true,
            fixture_log_failure: None,
            requests_failure: None,
            accepted: 30,
            rejected: 0,
            status_failure: None,
            status,
        }
    }

    async fn sqlite_glob_matches(
        connection: &mut SqliteConnection,
        record_id: &str,
        pattern: &str,
    ) -> bool {
        sea_orm::sqlx::query_as::<_, (i64,)>("SELECT ? GLOB ?")
            .bind(record_id)
            .bind(pattern)
            .fetch_one(connection)
            .await
            .unwrap()
            .0
            == 1
    }

    fn audit(applied_write_seq: i64) -> HistoryAudit {
        HistoryAudit {
            thread_id: "thread-1".into(),
            canonical_atoms: 2,
            distinct_canonical_ids: 2,
            seed_text_items: 1,
            distinct_seed_text_ids: 1,
            growth_text_items: 0,
            distinct_growth_text_ids: 0,
            history_items: 2,
            history_turns: 1,
            applied_write_seq,
            database_bytes: 100,
            wal_bytes: Some(0),
            timeline_records: vec![
                r#"[1,"item-1",null,1,null,"text",{"value":"a"}]"#.into(),
                r#"[2,"turn-1","turn-1",1,10,"turn",{"state":"completed"}]"#.into(),
            ],
            history_item_records: vec![
                r#"[1,"item-1","turn-1","text",0,"terminal",1,1,{"value":"a"},1]"#.into(),
                r#"[2,"turn-1","turn-1","turn",0,"terminal",1,1,{"state":"completed"},1]"#.into(),
            ],
            history_turn_records: vec![r#"["turn-1",1,2,0,{"state":"completed"},1]"#.into()],
        }
    }

    fn cold_report(open: u64) -> Value {
        json!({
            "persistence": {
                "pendingOperations": 0,
                "pendingBytes": 0,
                "inFlightBytes": 0,
                "threads": [{
                    "threadId": "thread-1",
                    "historyAdmitted": open,
                    "historyDurable": open,
                    "pending": 0,
                    "pendingBytes": 0,
                    "inFlightBytes": 0
                }]
            },
            "coldWatermarks": {
                "beforeScroll": {
                    "pendingOperations": 1,
                    "pendingBytes": 16,
                    "inFlightBytes": 8,
                    "historyAdmitted": open,
                    "historyDurable": open - 1
                },
                "afterScroll": {
                    "pendingOperations": 0,
                    "pendingBytes": 0,
                    "inFlightBytes": 0,
                    "historyAdmitted": open,
                    "historyDurable": open
                }
            }
        })
    }

    #[test]
    fn missing_status_cannot_serialize_a_passing_verdict() {
        let result = final_verdict(&passing_gate(None));
        let verdict = verdict_json(&result);
        assert_eq!(verdict["pass"], false);
        assert!(verdict["failure"].as_str().unwrap().contains("required"));
    }

    #[test]
    fn failed_fixture_exit_cannot_serialize_a_passing_verdict() {
        let status = complete_status();
        let mut gate = passing_gate(Some(&status));
        gate.fixture_stopped_cleanly = false;
        let result = final_verdict(&gate);
        let verdict = verdict_json(&result);
        assert_eq!(verdict["pass"], false);
        assert!(
            verdict["failure"]
                .as_str()
                .unwrap()
                .contains("did not exit cleanly")
        );
    }

    #[test]
    fn malformed_status_is_an_explicit_failure() {
        let directory = tempfile::tempdir().unwrap();
        let status = directory.path().join("fixture-status.json");
        fs::write(&status, b"{").unwrap();
        let error = read_required_live_status(&status).unwrap_err();
        assert!(error.to_string().contains("malformed"));
    }

    #[test]
    fn phase_failure_remains_primary_when_cleanup_and_evidence_also_fail() {
        let error = finish_phase_result::<()>(
            Err(anyhow::anyhow!("original Driver failure")),
            Err(anyhow::anyhow!("cleanup failure")),
            Err(anyhow::anyhow!("evidence failure")),
        )
        .unwrap_err()
        .to_string();
        assert!(error.starts_with("original Driver failure"));
        assert!(error.contains("process cleanup also failed: cleanup failure"));
        assert!(error.contains("evidence collection also failed: evidence failure"));
    }

    #[test]
    fn successful_phase_does_not_swallow_evidence_failure() {
        let error = finish_phase_result(Ok(()), Ok(()), Err(anyhow::anyhow!("evidence failure")))
            .unwrap_err();
        assert_eq!(error.to_string(), "evidence failure");
    }

    #[test]
    fn exact_inventory_rejects_equal_counts_with_changed_payload_identity_or_order() {
        let seed = audit(10);

        let mut changed_payload = seed.clone();
        changed_payload.timeline_records[0] =
            r#"[1,"item-1",null,1,null,"text",{"value":"changed"}]"#.into();
        assert!(!same_persisted_inventory(&seed, &changed_payload));

        let mut changed_identity = seed.clone();
        changed_identity.history_item_records[0] =
            r#"[1,"other-item","turn-1","text",0,"terminal",1,1,{"value":"a"},1]"#.into();
        assert!(!same_persisted_inventory(&seed, &changed_identity));

        let mut changed_order = seed.clone();
        changed_order.timeline_records.reverse();
        assert!(!same_persisted_inventory(&seed, &changed_order));
    }

    #[test]
    fn exact_inventory_and_open_close_watermarks_pass_strict_cold_contract() {
        let seed = audit(10);
        let cold = audit(13);
        let observation = cold_phase_observation(&cold_report(11), "cold-1").unwrap();

        let check = verify_cold_lifecycle("cold-1", &seed, &seed, &cold, &observation).unwrap();
        assert_eq!(
            check,
            ColdLifecycleCheck {
                phase: "cold-1".into(),
                previous_closed: 10,
                open: 11,
                after_close: 13,
                exact_inventory_unchanged: true,
            }
        );
    }

    #[test]
    fn missing_fractional_or_incorrect_watermarks_are_rejected() {
        let seed = audit(10);
        let cold = audit(13);

        let mut missing = cold_report(11);
        missing["persistence"]["threads"][0]
            .as_object_mut()
            .unwrap()
            .remove("historyAdmitted");
        assert!(cold_phase_observation(&missing, "cold-1").is_err());

        let mut fractional = cold_report(11);
        fractional["coldWatermarks"]["afterScroll"]["historyAdmitted"] = json!(11.0);
        assert!(cold_phase_observation(&fractional, "cold-1").is_err());

        let observation = cold_phase_observation(&cold_report(12), "cold-1").unwrap();
        assert!(verify_cold_lifecycle("cold-1", &seed, &seed, &cold, &observation).is_err());
    }

    #[test]
    fn canonical_timeline_record_globs_match_only_the_expected_fixture_items() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        runtime.block_on(async {
            let mut connection = SqliteConnection::connect_with(
                &SqliteConnectOptions::new().in_memory(true),
            )
            .await
            .unwrap();

            let seed =
                "model:26:input:app-359979975:1:3:0:presentation:item:38:timeline-history-20k-seed-01-item-0000:text:0";
            let growth =
                "model:207:input:app-42:9:11:0:presentation:item:7:timeline-history-20k-growth-20-item-0099:text:0";
            assert!(
                sqlite_glob_matches(
                    &mut connection,
                    seed,
                    TIMELINE_HISTORY_20K_SEED_RECORD_GLOB
                )
                .await,
                "the observed canonical seed ID must match the production audit pattern"
            );
            assert!(
                !sqlite_glob_matches(
                    &mut connection,
                    seed,
                    TIMELINE_HISTORY_20K_GROWTH_RECORD_GLOB
                )
                .await,
                "a seed ID must not be counted as growth"
            );
            assert!(
                sqlite_glob_matches(
                    &mut connection,
                    growth,
                    TIMELINE_HISTORY_20K_GROWTH_RECORD_GLOB
                )
                .await,
                "a canonical growth ID must match the production audit pattern"
            );
            assert!(
                !sqlite_glob_matches(
                    &mut connection,
                    growth,
                    TIMELINE_HISTORY_20K_SEED_RECORD_GLOB
                )
                .await,
                "a growth ID must not be counted as seed"
            );

            for invalid in [
                "user:app-359979975:timeline-history-20k-seed-01-item-0000:text:0",
                "turn:3:timeline-history-20k-seed-01-item-0000:text:0",
                "inference:3:timeline-history-20k-seed-01-item-0000:text:0",
                "model:26:input:app:1:3:0:presentation:item:38:ordinary-user:text:0",
                "model:26:input:app:1:3:0:presentation:item:38:timeline-history-20k-seed-1-item-0000:text:0",
                "model:26:input:app:1:3:0:presentation:item:38:timeline-history-20k-seed-aa-item-0000:text:0",
                "model:26:input:app:1:3:0:presentation:item:38:timeline-history-20k-seed-01-item-000:text:0",
                "model:26:input:app:1:3:0:presentation:item:38:timeline-history-20k-seed-01-item-00000:text:0",
                "model:26:input:app:1:3:0:presentation:item:38:timeline-history-20k-seed-01-item-00a0:text:0",
                "model:26:input:app:1:3:0:presentation:item:38:timeline-history-20k-seed-01-item-0000:text:1",
            ] {
                assert!(
                    !sqlite_glob_matches(
                        &mut connection,
                        invalid,
                        TIMELINE_HISTORY_20K_SEED_RECORD_GLOB
                    )
                    .await,
                    "invalid record unexpectedly matched seed GLOB: {invalid}"
                );
                assert!(
                    !sqlite_glob_matches(
                        &mut connection,
                        invalid,
                        TIMELINE_HISTORY_20K_GROWTH_RECORD_GLOB
                    )
                    .await,
                    "invalid record unexpectedly matched growth GLOB: {invalid}"
                );
            }
        });
    }
}
