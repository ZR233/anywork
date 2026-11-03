use super::{
    OwnedProcess, history_lock_database, history_owner_thread, observe_capture_exit,
    require_native_exit, sanitize_driver_line, sanitize_requests, start_timeline_history_gui,
    wait_for_gui_exit, wait_for_vm, write_fixture_log, write_sanitized_log,
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
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::mpsc;
use std::time::{Duration, Instant};

const TIMELINE_HISTORY_20K_SEED_RECORD_GLOB: &str = concat!(
    "model:*:presentation:item:*:",
    "timeline-history-20k-seed-[0-9][0-9]-item-[0-9][0-9][0-9][0-9]:text:0"
);
const TIMELINE_HISTORY_20K_GROWTH_RECORD_GLOB: &str = concat!(
    "model:*:presentation:item:*:",
    "timeline-history-20k-growth-[0-9][0-9]-item-[0-9][0-9][0-9][0-9]:text:0"
);
const OPEN_SAMPLES: usize = 20;

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
    conversation_records: Vec<String>,
    #[serde(skip)]
    content_manifests: Vec<String>,
    #[serde(skip)]
    content_chunks: Vec<String>,
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
            .field("conversation_record_rows", &self.conversation_records.len())
            .field("content_manifest_rows", &self.content_manifests.len())
            .field("content_chunk_rows", &self.content_chunks.len())
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
    gui_exit: Option<i32>,
}

struct PhaseOutcome {
    summary: PhaseSummary,
    cold_observation: Option<ColdPhaseObservation>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ColdPhaseObservation {
    thread_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct ColdLifecycleCheck {
    phase: String,
    previous_closed: u64,
    after_close: u64,
    writer_absent_at_samples: bool,
    exact_inventory_unchanged: bool,
}

pub(super) fn run(context: &Scenario<'_>, mut fixture: OwnedProcess) -> Result<()> {
    let project = context.working.join("timeline-history-20k-project");
    let mut phases = Vec::new();
    let mut seed_audit = None;
    let mut cold_audits = Vec::new();
    let mut cold_lifecycle_checks = Vec::new();
    let mut switch_audit = None;
    let mut opening_performance = None;
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
        let phase_names = std::iter::once("seed".to_owned())
            .chain((1..=OPEN_SAMPLES).map(|sample| format!("cold-{sample}")))
            .chain(["switch".to_owned(), "growth".to_owned()]);
        for phase in phase_names {
            let phase = phase.as_str();
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
                phase if phase.starts_with("cold-") => {
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
                "switch" => {
                    ensure!(
                        same_persisted_inventory(
                            seed_audit
                                .as_ref()
                                .context("switch phase has no seed audit")?,
                            &audit,
                        ),
                        "ordinary switching changed the original 20,000-item inventory"
                    );
                    switch_audit = Some(audit);
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
        opening_performance = Some(json!({
            "measurement": "operator-runbook",
            "status": "notMeasured",
            "note": "Driver viewport p95 is no longer collected; unique inventory proofs remain",
        }));
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
        "coldOpenProcess": "a fresh GUI process for each cold-N phase",
        "ordinarySwitchProcess": "one warm GUI process with real reference-session switches",
        "osPageCacheControlled": false,
        "osPageCacheNote": "GUI processes are cold; host Linux page cache is not cleared or controlled",
        "profile": "Flutter profile; release-profile Rust bridge",
        "shape": {
            "seedBatches": 10,
            "seedTextItemsPerBatch": 2_000,
            "seedTextItems": 20_000,
            "coldOpenSamples": OPEN_SAMPLES,
            "ordinarySwitchSamples": OPEN_SAMPLES,
            "referenceSessionTextItems": 1,
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
        "switchAudit": switch_audit,
        "openingPerformance": opening_performance,
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
        gate.rejected == 0 && gate.accepted >= 31,
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
    let native_exit = context
        .output
        .join(format!("timeline-history-20k-{phase}-native-exit.json"));
    let started = Instant::now();
    let mut gui = None;
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
        let _ = database;
        observe_capture_exit(
            context.app_dir,
            &vm_url,
            context.output,
            context.interrupt,
            active_gui,
            Some(fixture),
            &format!(
                "timeline-history-20k {phase}: open {}, complete the {phase} observation, then type done.",
                project.display()
            ),
        )?;
        let status = wait_for_gui_exit(active_gui, Duration::from_secs(180), phase)?;
        gui_exit = Some(status);
        ensure!(
            status.success(),
            "timeline-history-20k {phase} GUI failed: {status}"
        );
        let native: Value =
            serde_json::from_slice(&fs::read(&native_exit).with_context(|| {
                format!("missing native exit report {}", native_exit.display())
            })?)?;
        let gui_pid = native["pid"]
            .as_u64()
            .context("timeline-history-20k native exit report has no pid")?;
        require_native_exit(&native_exit, Some(gui_pid))?;
        let cold_observation = if phase.starts_with("cold-") {
            Some(ColdPhaseObservation {
                thread_id: history_owner_thread(context.home)?,
            })
        } else {
            None
        };
        fs::write(
            context
                .output
                .join(format!("timeline-history-20k-{phase}.json")),
            serde_json::to_vec_pretty(&json!({
                "phase": phase,
                "shutdown": "completed",
                "pid": gui_pid,
                "harnessTiming": {
                    "launcherPid": launcher_pid,
                    "actualGuiPid": gui_pid,
                    "launcherCommandToVmMillis": process_start_to_vm_millis,
                },
            }))?,
        )?;
        Ok(PhaseOutcome {
            summary: PhaseSummary {
                phase: phase.to_owned(),
                launcher_pid,
                gui_pid,
                launcher_command_to_vm_millis: process_start_to_vm_millis,
                gui_exit: status_code(gui_exit),
            },
            cold_observation,
        })
    })();

    let cleanup_result = if phase_result.is_err() {
        settle_failed_phase(gui.as_mut(), &mut gui_exit)
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
    gui: Option<&mut OwnedProcess>,
    gui_exit: &mut Option<std::process::ExitStatus>,
) -> Result<()> {
    settle_failed_process(gui, gui_exit, "GUI")
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
    let failure = phase_error.map(|error| sanitize_driver_line(&error.to_string(), redactions));
    let exit_result = fs::write(
        context
            .output
            .join(format!("timeline-history-20k-{phase}-exit.json")),
        serde_json::to_vec_pretty(&json!({
            "phase": phase,
            "guiExit": status_code(gui_exit),
            "failure": failure,
        }))?,
    )
    .context("failed to write timeline-history-20k phase exit evidence");
    gui_result?;
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
                    (SELECT COUNT(*) FROM conversation_items),
                    (SELECT COUNT(DISTINCT item_id) FROM conversation_items),
                    (SELECT COUNT(*) FROM conversation_items
                       WHERE item_id GLOB ?),
                    (SELECT COUNT(DISTINCT item_id) FROM conversation_items
                       WHERE item_id GLOB ?),
                    (SELECT COUNT(*) FROM conversation_items
                       WHERE item_id GLOB ?),
                    (SELECT COUNT(DISTINCT item_id) FROM conversation_items
                       WHERE item_id GLOB ?),
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
        let conversation_records = sea_orm::sqlx::query_scalar::<_, String>(
            "SELECT json_array(seq,item_id,query_class,parent_id,hex(payload))
             FROM conversation_items ORDER BY seq",
        )
        .fetch_all(&mut connection)
        .await
        .with_context(|| format!("failed to read exact timeline inventory from {}", display.display()))?;
        // A completed envelope can reference external bodies. Compare their
        // exact persisted manifests/chunks too; equal item counts or previews
        // cannot prove preservation. `4:item` is the canonical ChatKey("item", id)
        // storage prefix; mutable Current bodies are intentionally excluded.
        let content_manifests = sea_orm::sqlx::query_scalar::<_, String>(
            "SELECT json_array(c.owner_key,c.content_key,hex(c.payload))
             FROM conversation_contents c JOIN conversation_items i ON c.owner_key='4:item'||i.item_id
             ORDER BY c.owner_key,c.content_key",
        ).fetch_all(&mut connection).await
            .context("failed to audit completed content manifests")?;
        let content_chunks = sea_orm::sqlx::query_scalar::<_, String>(
            "SELECT json_array(c.owner_key,c.content_key,c.byte_offset,hex(c.data))
             FROM conversation_content_chunks c JOIN conversation_items i ON c.owner_key='4:item'||i.item_id
             ORDER BY c.owner_key,c.content_key,c.byte_offset",
        ).fetch_all(&mut connection).await
            .context("failed to audit completed content chunks")?;
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
            conversation_records,
            content_manifests,
            content_chunks,
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
        && seed.conversation_records == cold.conversation_records
        && seed.content_manifests == cold.content_manifests
        && seed.content_chunks == cold.content_chunks
        && seed.history_item_records == cold.history_item_records
        && seed.history_turn_records == cold.history_turn_records
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
    let seed_closed = u64::try_from(seed.applied_write_seq)
        .with_context(|| format!("{phase} seed closed watermark is negative"))?;
    let actual_after_close = u64::try_from(current.applied_write_seq)
        .with_context(|| format!("{phase} after-close watermark is negative"))?;
    ensure!(
        previous_closed == seed_closed && actual_after_close == previous_closed,
        "{phase} passive reading saved an effect: seedClosed={seed_closed} previousClosed={previous_closed} actualAfterClose={actual_after_close}"
    );
    Ok(ColdLifecycleCheck {
        phase: phase.to_owned(),
        previous_closed,
        after_close: actual_after_close,
        writer_absent_at_samples: true,
        exact_inventory_unchanged: true,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn complete_status() -> FixtureLiveStatus {
        FixtureLiveStatus {
            accepted: 31,
            rejected: 0,
            total: 31,
            consumed_steps: 31,
            expected_steps: 31,
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
            accepted: 31,
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
            conversation_records: vec![
                r#"[1,"item-1",null,1,null,"text",{"value":"a"}]"#.into(),
                r#"[2,"turn-1","turn-1",1,10,"turn",{"state":"completed"}]"#.into(),
            ],
            content_manifests: vec![r#"["4:itemitem-1","body","manifest"]"#.into()],
            content_chunks: vec![r#"["4:itemitem-1","body",0,"61"]"#.into()],
            history_item_records: vec![
                r#"[1,"item-1","turn-1","text",0,"terminal",1,1,{"value":"a"},1]"#.into(),
                r#"[2,"turn-1","turn-1","turn",0,"terminal",1,1,{"state":"completed"},1]"#.into(),
            ],
            history_turn_records: vec![r#"["turn-1",1,2,0,{"state":"completed"},1]"#.into()],
        }
    }

    fn cold_observation(thread_id: &str) -> ColdPhaseObservation {
        ColdPhaseObservation {
            thread_id: thread_id.into(),
        }
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
        changed_payload.conversation_records[0] =
            r#"[1,"item-1",null,1,null,"text",{"value":"changed"}]"#.into();
        assert!(!same_persisted_inventory(&seed, &changed_payload));

        let mut changed_identity = seed.clone();
        changed_identity.history_item_records[0] =
            r#"[1,"other-item","turn-1","text",0,"terminal",1,1,{"value":"a"},1]"#.into();
        assert!(!same_persisted_inventory(&seed, &changed_identity));

        let mut changed_order = seed.clone();
        changed_order.conversation_records.reverse();
        assert!(!same_persisted_inventory(&seed, &changed_order));

        let mut changed_body = seed.clone();
        changed_body.content_chunks[0] = r#"["4:itemitem-1","body",0,"62"]"#.into();
        assert!(!same_persisted_inventory(&seed, &changed_body));

        let mut changed_manifest = seed.clone();
        changed_manifest.content_manifests.clear();
        assert!(!same_persisted_inventory(&seed, &changed_manifest));
    }

    #[test]
    fn exact_inventory_and_unchanged_watermark_pass_passive_cold_contract() {
        let seed = audit(10);
        let cold = audit(10);
        let check =
            verify_cold_lifecycle("cold-1", &seed, &seed, &cold, &cold_observation("thread-1"))
                .unwrap();
        assert_eq!(
            check,
            ColdLifecycleCheck {
                phase: "cold-1".into(),
                previous_closed: 10,
                after_close: 10,
                writer_absent_at_samples: true,
                exact_inventory_unchanged: true,
            }
        );
    }

    #[test]
    fn saved_effects_or_another_thread_cannot_pass_passive_cold_contract() {
        let seed = audit(10);
        let same_thread = cold_observation("thread-1");
        // A changed write watermark is a saved effect even without Driver queue evidence.
        for changed_sequence in [9, 11, 13] {
            let cold = audit(changed_sequence);
            assert!(verify_cold_lifecycle("cold-1", &seed, &seed, &cold, &same_thread).is_err());
        }
        assert!(
            verify_cold_lifecycle(
                "cold-1",
                &seed,
                &seed,
                &seed,
                &cold_observation("another-thread"),
            )
            .is_err()
        );
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
