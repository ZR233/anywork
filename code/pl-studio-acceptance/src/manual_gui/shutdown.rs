//! 30-second application-shutdown acceptance.
//!
//! The scenario starts a real native GUI and judges the application exit from
//! the OS process itself: `ext.anywork.requestExit` only *requests* the exit,
//! while the coordinator OS-waits the real native pid (from the GUI log
//! `resident command started: pid=`, guarded by a `/proc` start-time) and reads
//! the artifact's genuine wait status from the launcher's structured
//! `--native-launch` report — never the `cargo`/Flutter wrapper exit code, which
//! the platform launch tool always reports as `0`. Every phase shares the real
//! bridge, isolated `ANYWORK_HOME`s and the local provider fixture; nothing is
//! faked with demo mode or an invented snapshot.
//!
//! Phases (each keeps its own non-overwriting evidence):
//!
//! * `normal`   — one durable turn, the typed cleanup acknowledgement, then the
//!   real exit that must return code 0.
//! * `reopen`   — reopen the same home and prove the saved turn is restored.
//! * `busy`     — a duplicate activates the owner and exits before Flutter;
//!   the original instance continues and saves.
//! * `busy-reopen` — reopen the same home and prove that continued turn restored.
//! * `duplicate`— a repeated exit request during the first pending cleanup must
//!   stay inside the single budget measured from the first arm.
//! * `hang`     — the thin native assembly hangs the isolate after arming the
//!   budget; the native host must force exit code 1 at the 30-second deadline.
//! * `runtime-unavailable` — the isolated home's v2 data root cannot be created,
//!   so the runtime fails with a real typed error yet the fatal widget renders
//!   and the app still closes with diagnostics.
//! * `storage-lock` — a durable prime turn plus a writer-lock-blocked turn; the
//!   forced exit must not lose the prime and a reopen must pass `quick_check`.
//! * `service-unresponsive` — a frozen provider fixture must not block exit.
//! * `close-during-init` — a thin-assembly `pending-init` fault keeps the runtime
//!   initializing; the exit must report Degraded + Unknown and force exit 1.
//! * `bridge-unavailable` — a thin-assembly `bridge-load-error` fault leaves no
//!   runtime owner; the close must be a clean NotStarted exit 0.
//! * `subscription-fault` — a thin-assembly faulty shutdown-progress subscription
//!   must surface a typed `progress` diagnostic and a non-zero exit.
//! * `dart-error-fallback` — an unwritable `ANYWORK_HOME/studio/logs` must fall back
//!   to the isolated `TMPDIR` and still record stage/correlation/stack.
//! * `mcp-forced-exit-boundary`, `lsp-forced-exit-boundary`, and
//!   `tool-forced-exit-boundary` prove each owned protocol/tool process and its
//!   SIGTERM-ignoring descendant live before blocking the isolate, then judge
//!   the real forced exit at the single 30-second deadline. Native Executor
//!   ownership cannot run destructors after this abrupt exit. The report keeps
//!   descendants seen at root exit, monitor results and harness intervention;
//!   it does not label forced-exit descendant reclamation as a product guarantee.
//! * `concurrent-stop` — a home that declares the scenario-owned stdio MCP
//!   server runs one background `exec` turn, so a single turn starts two
//!   independent supervised resources. Before taking the exclusive writer lock
//!   the coordinator waits for the strict fixture to accept the turn's required
//!   receipt continuation (its live counters report every remaining step
//!   optional), so the block lands while the turn is still streaming rather than
//!   cancelling it at the receipt. It then holds that lock across the exit
//!   request (the artificially blocked terminal save) and proves both subtrees
//!   are reclaimed on their own while that chain is still waiting. The blocked
//!   save forces a coordinated degraded finish at the 28-second cleanup budget
//!   (the 30-second watchdog is reserved for a
//!   Dart/bridge that never returns), so the phase judges the exit from the real
//!   OS status plus the native diagnostics, never a fabricated ~30-second
//!   target. Each resource is confirmed only when *both* its process and its
//!   SIGTERM-ignoring grandchild were observed to exit, and its completion is
//!   the later of the two, so a grandchild that stops early can never stand in
//!   for a parent that lingers to the native force-out.
//!
//! The duplicate in the `busy` phase exits before Flutter and activates the
//! original native window. No duplicate error window is created or closed.
//! `coverage.json` lists every requirement as executed or not covered; a skipped
//! branch is never written as passed.

use super::{
    FixtureReady, LspServerSpec, OwnedProcess, SqliteWriteLock, count_gui_errors,
    history_lock_database, history_lock_quick_check, history_lock_watermark, request_app_exit,
    sanitize_requests, wait_for_vm, write_config, write_config_with_lsp_server,
    write_config_with_mcp_server, write_fixture_log, write_sanitized_log,
};
use anyhow::{Context, Result, bail, ensure};
use serde::Serialize;
use std::collections::BTreeMap;
use std::fs::{self, File};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

/// The single application-exit budget mandated by design 18 §18.5.3.
const EXIT_BUDGET: Duration = Duration::from_secs(30);

/// How long a phase may keep waiting on the OS process after the budget before
/// the coordinator itself fails: this only guards against a permanently wedged
/// process, it is never treated as a success signal.
const EXIT_GRACE: Duration = Duration::from_secs(45);

/// Upper bound, measured from just before the exit request, within which each
/// independently supervised resource of the `concurrent-stop` phase must have
/// been reclaimed by the product while the artificially blocked save chain is
/// still waiting.
const CONCURRENT_STOP_ACK_BOUND: Duration = Duration::from_secs(15);

/// The Dart cleanup budget the blocked save must exhaust.
const CONCURRENT_CLEANUP_BUDGET: Duration = Duration::from_secs(28);

pub(super) struct ShutdownScenario<'a> {
    pub(super) workspace: &'a Path,
    pub(super) app_dir: &'a Path,
    pub(super) home: &'a Path,
    pub(super) working: &'a Path,
    pub(super) output: &'a Path,
    pub(super) fixture_log: &'a Path,
    pub(super) requests_file: &'a Path,
    pub(super) status_file: &'a Path,
    pub(super) fixture_executable: &'a Path,
    pub(super) interrupt: &'a mpsc::Receiver<()>,
}

/// One phase's machine-checkable lifetime record.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PhaseRecord {
    name: &'static str,
    status: &'static str,
    /// `executed` when the phase ran and produced evidence, `notCovered` when it
    /// was deliberately skipped with a stated reason.
    coverage: &'static str,
    detail: String,
    exit_code: Option<i32>,
    elapsed_millis: Option<u128>,
    native_pid: Option<u32>,
    owned_children: Vec<u32>,
}

/// A requirement that the Linux-only run could not execute, with its reason.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct GapRecord {
    requirement: &'static str,
    reason: &'static str,
    interface_needs: &'static str,
}

pub(super) fn run(context: &ShutdownScenario<'_>, mut fixture: OwnedProcess) -> Result<()> {
    let ShutdownScenario {
        workspace,
        app_dir,
        home,
        working,
        output,
        fixture_log,
        requests_file,
        status_file,
        fixture_executable,
        interrupt,
    } = context;

    let ready: FixtureReady = serde_json::from_slice(
        &fs::read(working.join("fixture-ready.json"))
            .context("shutdown acceptance lost the fixture ready file")?,
    )?;

    // Isolated homes per non-shared phase. Every real closure home carries the
    // same isolated provider config so the runtime installs for real; the
    // unreadable home is the only one deliberately broken.
    let home_duplicate = working.join("shutdown-duplicate-home");
    let home_hang = working.join("shutdown-hang-home");
    let home_storage = working.join("shutdown-storage-home");
    let home_service = working.join("shutdown-service-home");
    let home_unavailable = working.join("shutdown-unavailable-home");
    for extra in [&home_duplicate, &home_hang, &home_storage, &home_service] {
        fs::create_dir_all(extra)?;
        write_config(extra, &ready, None, false)?;
    }
    // The runtime is never allowed to install here: a regular file occupies the
    // path where the current data root must be created, so the runtime fails with a
    // real typed startup error on any host (a read-only directory is ignored
    // when the acceptance runs as root, which proves nothing). The Dart app
    // still starts and stays alive to be asked to exit. (Pointing
    // `ANYWORK_BRIDGE_LIBRARY` at a missing file is not usable here: the Linux
    // CMake configure step refuses a non-existent bridge, so the GUI would never
    // start.)
    fs::create_dir(&home_unavailable)?;
    write_config(&home_unavailable, &ready, None, false)?;
    fs::write(home_unavailable.join("data"), b"not a directory\n")?;

    // Native-fault homes: the two injected startup faults, the
    // subscription fault and the temp-fallback diagnostics home share the
    // normal isolated provider config.
    let home_init_close = working.join("shutdown-init-close-home");
    let home_bridge = working.join("shutdown-bridge-home");
    let home_subscription = working.join("shutdown-subscription-home");
    let home_tmp_fallback = working.join("shutdown-tmp-fallback-home");
    for extra in [&home_init_close, &home_bridge, &home_subscription] {
        fs::create_dir_all(extra)?;
        write_config(extra, &ready, None, false)?;
    }
    // The temp-fallback home cannot create its canonical diagnostic directory:
    // a regular file occupies `<home>/studio/logs`, so `recordDartError`'s canonical
    // write fails on any host (permission bits are ignored when running as
    // root). The fallback log lands in the isolated `TMPDIR` below.
    fs::create_dir(&home_tmp_fallback)?;
    write_config(&home_tmp_fallback, &ready, None, false)?;
    fs::create_dir(home_tmp_fallback.join("studio"))?;
    fs::write(
        home_tmp_fallback.join("studio/logs"),
        b"occupied by the acceptance\n",
    )?;
    let tmp_fallback_tmp = working.join("shutdown-tmp-fallback-tmp");
    fs::create_dir(&tmp_fallback_tmp)?;

    let home_mcp = working.join("shutdown-mcp-home");
    fs::create_dir(&home_mcp)?;
    let mcp_coord = working.join("shutdown-mcp-coord.json");
    write_config_with_mcp_server(
        &home_mcp,
        &ready,
        "shutdown-fixture",
        fixture_executable,
        &[
            "--mcp-stdio".to_owned(),
            "--coord-file".to_owned(),
            mcp_coord.to_string_lossy().into_owned(),
        ],
    )?;

    let home_lsp = working.join("shutdown-lsp-home");
    fs::create_dir(&home_lsp)?;
    let lsp_coord = working.join("shutdown-lsp-coord.json");
    write_config_with_lsp_server(
        &home_lsp,
        &ready,
        &LspServerSpec {
            id: "shutdown-lsp-fixture",
            command: fixture_executable,
            args: &[
                "--lsp-stdio".to_owned(),
                "--coord-file".to_owned(),
                lsp_coord.to_string_lossy().into_owned(),
            ],
            language_id: pl_provider_fixture::GUI_SHUTDOWN_LSP_LANGUAGE_ID,
            detection: &[],
            extensions: &[],
        },
    )?;

    let home_tool = working.join("shutdown-tool-home");
    fs::create_dir(&home_tool)?;
    write_config(&home_tool, &ready, None, false)?;
    let tool_coord = working.join("shutdown-tool-coord.json");

    let home_concurrent = working.join("shutdown-concurrent-home");
    fs::create_dir(&home_concurrent)?;
    let concurrent_mcp_coord = working.join("shutdown-concurrent-mcp-coord.json");
    write_config_with_mcp_server(
        &home_concurrent,
        &ready,
        "shutdown-fixture",
        fixture_executable,
        &[
            "--mcp-stdio".to_owned(),
            "--coord-file".to_owned(),
            concurrent_mcp_coord.to_string_lossy().into_owned(),
            "--inherit-process-group".to_owned(),
        ],
    )?;
    let concurrent_tool_coord = working.join("shutdown-concurrent-tool-coord.json");

    let mut phases: Vec<PhaseRecord> = Vec::new();
    let mut fixture_paused = false;

    let journey = (|| -> Result<()> {
        // ----------------------------------------------------------- normal --
        {
            let log = working.join("shutdown-normal-gui.log");
            let project = prepare_project(working, "shutdown-normal-project")?;
            let mut gui = start_gui_with(
                workspace,
                home,
                &log,
                working,
                "normal",
                NativeLaunch {
                    phase: Some("normal"),
                    project: Some(&project),
                    prompt: Some(pl_provider_fixture::GUI_SHUTDOWN_PROMPTS[0]),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            let vm_url = wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            wait_stage(
                "normal_settled",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(300),
            )?;
            let (native_pid, start_ticks, children, arm) = arm_after_stage(
                app_dir,
                &vm_url,
                &log,
                working,
                "normal",
                "normal_exit_requested",
                &mut gui,
                &mut fixture,
                interrupt,
                true,
            )?;
            let native = wait_native_exit(
                "normal",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            phases.push(PhaseRecord {
                name: "normal",
                status: "executed",
                coverage: "executed",
                detail: format!("requested the real app exit: {}", native.summary()),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(0) && native.signal.is_none(),
                "normal native exit was not code 0: {}",
                native.summary()
            );
            ensure!(
                native.reclaimed_descendants.is_empty(),
                "normal native exit left a child tree for the harness: {:?}",
                native.reclaimed_descendants
            );
            write_sanitized_log(&log, &output.join("shutdown-normal-gui.log"))?;
        }

        // ----------------------------------------------------------- reopen --
        {
            let log = working.join("shutdown-reopen-gui.log");
            let project = working.join("shutdown-normal-project");
            let mut gui = start_gui_with(
                workspace,
                home,
                &log,
                working,
                "reopen",
                NativeLaunch {
                    phase: Some("reopen"),
                    project: Some(&project),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            let vm_url = wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            let (native_pid, start_ticks, children, arm) = arm_after_stage(
                app_dir,
                &vm_url,
                &log,
                working,
                "reopen",
                "reopen_exit_requested",
                &mut gui,
                &mut fixture,
                interrupt,
                true,
            )?;
            let native = wait_native_exit(
                "reopen",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            phases.push(PhaseRecord {
                name: "reopen",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "reopened the same home, matched the saved completed turn and exact content inventory, and requested the real app exit: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(0) && native.signal.is_none(),
                "reopen native exit was not code 0: {}",
                native.summary()
            );
            ensure!(
                native.reclaimed_descendants.is_empty(),
                "reopen native exit left a child tree for the harness: {:?}",
                native.reclaimed_descendants
            );
            write_sanitized_log(&log, &output.join("shutdown-reopen-gui.log"))?;
        }

        // ------------------------------------------------------------- busy --
        {
            let log = working.join("shutdown-busy-first-gui.log");
            let project = working.join("shutdown-normal-project");
            let mut first = start_gui_with(
                workspace,
                home,
                &log,
                working,
                "busy-hold",
                NativeLaunch {
                    phase: Some("busy-hold"),
                    project: Some(&project),
                    prompt: Some(pl_provider_fixture::GUI_SHUTDOWN_PROMPTS[1]),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            let vm_url = wait_for_vm(&log, &mut first, &mut fixture, interrupt)?;
            wait_stage(
                "busy_hold_reopened",
                working,
                &mut first,
                &mut fixture,
                interrupt,
                Duration::from_secs(300),
            )?;
            let second_log = working.join("shutdown-busy-second-gui.log");
            let second = start_gui(workspace, home, &second_log, working, "busy-second")?;
            let busy_evidence =
                capture_second_instance(&second_log, &log, output, working, second, interrupt)?;
            fs::write(
                output.join("shutdown-busy-second.json"),
                serde_json::to_vec_pretty(&busy_evidence)?,
            )?;
            ensure!(
                busy_evidence["redirected"] == true
                    && busy_evidence["ownerActivated"] == true
                    && busy_evidence["secondEngineCreated"] == false,
                "duplicate did not activate the owner before engine creation: {busy_evidence}"
            );
            ensure!(
                busy_evidence["secondNativeReport"]["exitCode"].as_i64() == Some(0)
                    && busy_evidence["secondNativeReport"]["elapsedMillis"]
                        .as_u64()
                        .is_some_and(|elapsed| elapsed < 15_000)
                    && busy_evidence["secondNativeReport"]["signal"].is_null()
                    && busy_evidence["secondNativeReport"]["reclaimedDescendants"]
                        .as_array()
                        .is_some_and(Vec::is_empty),
                "duplicate did not exit cleanly without harness reclamation: {busy_evidence}"
            );
            ensure!(!first.exited()?, "redirect killed the original instance");
            fs::write(
                working.join("shutdown-signal-busy-second-redirected"),
                "redirected",
            )?;
            wait_stage(
                "busy_continued",
                working,
                &mut first,
                &mut fixture,
                interrupt,
                Duration::from_secs(300),
            )?;
            let (native_pid, start_ticks, children, arm) = arm_after_stage(
                app_dir,
                &vm_url,
                &log,
                working,
                "busy-hold",
                "busy_exit_requested",
                &mut first,
                &mut fixture,
                interrupt,
                true,
            )?;
            let native = wait_native_exit(
                "busy-hold",
                working,
                output,
                native_pid,
                start_ticks,
                &mut first,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            phases.push(PhaseRecord {
                name: "busy",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "duplicate redirected and exited before Flutter; the original instance then exited: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(0) && native.signal.is_none(),
                "first instance exit after the second was closed was not code 0: {}",
                native.summary()
            );
            ensure!(
                native.reclaimed_descendants.is_empty(),
                "first instance exit left a child tree for the harness: {:?}",
                native.reclaimed_descendants
            );
            write_sanitized_log(&log, &output.join("shutdown-busy-first-gui.log"))?;
        }

        // ------------------------------------------------------ busy-reopen --
        {
            let log = working.join("shutdown-busy-reopen-gui.log");
            let project = working.join("shutdown-normal-project");
            let mut gui = start_gui_with(
                workspace,
                home,
                &log,
                working,
                "busy-reopen",
                NativeLaunch {
                    phase: Some("busy-reopen"),
                    project: Some(&project),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            let vm_url = wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            let (native_pid, start_ticks, children, arm) = arm_after_stage(
                app_dir,
                &vm_url,
                &log,
                working,
                "busy-reopen",
                "busy-reopen_exit_requested",
                &mut gui,
                &mut fixture,
                interrupt,
                true,
            )?;
            let native = wait_native_exit(
                "busy-reopen",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            phases.push(PhaseRecord {
                name: "busy-reopen",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "reopened the same home after duplicate redirection and matched the continued completed turn and exact content inventory: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(0) && native.signal.is_none(),
                "busy-reopen native exit was not code 0: {}",
                native.summary()
            );
            ensure!(
                native.reclaimed_descendants.is_empty(),
                "busy-reopen native exit left a child tree for the harness: {:?}",
                native.reclaimed_descendants
            );
            write_sanitized_log(&log, &output.join("shutdown-busy-reopen-gui.log"))?;
        }

        // -------------------------------------------------------- duplicate --
        {
            let log = working.join("shutdown-duplicate-gui.log");
            let project = prepare_project(working, "shutdown-duplicate-project")?;
            let mut gui = start_gui_with(
                workspace,
                &home_duplicate,
                &log,
                working,
                "duplicate",
                NativeLaunch {
                    fault: Some("subscription"),
                    phase: Some("duplicate"),
                    project: Some(&project),
                    prompt: Some(pl_provider_fixture::GUI_SHUTDOWN_PROMPTS[2]),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            let vm_url = wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            let (native_pid, start_ticks, children, arm) = arm_after_stage(
                app_dir,
                &vm_url,
                &log,
                working,
                "duplicate",
                "duplicate_exit_requested",
                &mut gui,
                &mut fixture,
                interrupt,
                true,
            )?;
            wait_stage(
                "duplicate_exit_repeated",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                EXIT_GRACE,
            )?;
            let native = wait_native_exit(
                "duplicate",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            phases.push(PhaseRecord {
                name: "duplicate",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "a repeated request reused the pending subscription-fault cleanup and closed through the real exit path: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(1) && native.signal.is_none(),
                "duplicate-exit native exit was not the expected code 1 (Degraded): {}",
                native.summary()
            );
            ensure!(
                native.elapsed <= EXIT_BUDGET + Duration::from_secs(1),
                "duplicated exit request ran past the single budget measured from the first arm: {:?}",
                native.elapsed
            );
            ensure!(
                native.reclaimed_descendants.is_empty(),
                "duplicate-exit native exit left a child tree for the harness: {:?}",
                native.reclaimed_descendants
            );
            let diagnostics = read_native_exit_diagnostics(&home_duplicate)?;
            ensure!(
                diagnostics["coordinatedFinish"] == true,
                "duplicate-exit did not finish through the coordinator: {diagnostics}"
            );
            write_sanitized_log(&log, &output.join("shutdown-duplicate-gui.log"))?;
        }

        // ------------------------------------------------------------- hang --
        {
            let log = working.join("shutdown-hang-gui.log");
            let project = prepare_project(working, "shutdown-hang-project")?;
            let mut gui = start_gui_with(
                workspace,
                &home_hang,
                &log,
                working,
                "hang",
                NativeLaunch {
                    fault: Some("hang"),
                    phase: Some("hang"),
                    project: Some(&project),
                    prompt: Some(pl_provider_fixture::GUI_SHUTDOWN_PROMPTS[3]),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            let vm_url = wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            let (native_pid, start_ticks, children, arm) = arm_after_stage(
                app_dir,
                &vm_url,
                &log,
                working,
                "hang",
                "hang_exit_requested",
                &mut gui,
                &mut fixture,
                interrupt,
                true,
            )?;
            let native = wait_native_exit(
                "hang",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            fs::write(
                output.join("shutdown-hang-trace.json"),
                serde_json::to_vec_pretty(&serde_json::json!({
                    "nativePid": native_pid,
                    "nativeExitCode": native.code,
                    "nativeSignal": native.signal,
                    "elapsedMillis": native.elapsed.as_millis(),
                    "budgetMillis": EXIT_BUDGET.as_millis(),
                    "reclaimedDescendants": native.reclaimed_descendants,
                }))?,
            )?;
            phases.push(PhaseRecord {
                name: "hang",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "the hung native isolate was forced out by the native 30-second deadline: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(1) && native.signal.is_none(),
                "hung shutdown native exit was not code 1: {}",
                native.summary()
            );
            ensure!(
                native.elapsed <= EXIT_BUDGET + Duration::from_secs(1)
                    && native.elapsed + Duration::from_secs(1) >= EXIT_BUDGET,
                "hung shutdown did not exit at the single 30-second deadline (measured from the real arm): {:?}",
                native.elapsed
            );
            write_sanitized_log(&log, &output.join("shutdown-hang-gui.log"))?;
        }

        // ------------------------------------------------------- storage lock --
        {
            let log = working.join("shutdown-storage-prime-gui.log");
            let project = prepare_project(working, "shutdown-storage-project")?;
            let mut gui = start_gui_with(
                workspace,
                &home_storage,
                &log,
                working,
                "storage-lock",
                NativeLaunch {
                    phase: Some("storage-lock"),
                    project: Some(&project),
                    prompt: Some(pl_provider_fixture::GUI_SHUTDOWN_PROMPTS[4]),
                    second_prompt: Some(pl_provider_fixture::GUI_SHUTDOWN_PROMPTS[5]),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            let vm_url = wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            wait_stage(
                "storage_prime_settled",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(300),
            )?;
            let database = history_lock_database(&home_storage)?;
            let before = history_lock_watermark(&database)?;
            let mut lock = SqliteWriteLock::acquire(
                &database,
                "shutdown history.sqlite",
                Duration::from_secs(120),
            )?;
            fs::write(working.join("shutdown-signal-storage-lock-held"), "held")?;
            wait_stage(
                "storage_blocked",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(180),
            )?;
            fs::write(working.join("shutdown-signal-storage-exit"), "exit")?;
            let (native_pid, start_ticks, storage_children, arm) = arm_after_stage(
                app_dir,
                &vm_url,
                &log,
                working,
                "storage-lock",
                "storage_exit_requested",
                &mut gui,
                &mut fixture,
                interrupt,
                true,
            )?;
            let native = wait_native_exit(
                "storage-lock",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            lock.finish()?;
            write_sanitized_log(&log, &output.join("shutdown-storage-prime-gui.log"))?;

            let verify_log = working.join("shutdown-storage-verify-gui.log");
            let mut verify = start_gui_with(
                workspace,
                &home_storage,
                &verify_log,
                working,
                "storage-verify",
                NativeLaunch {
                    phase: Some("storage-verify"),
                    project: Some(&project),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            let verify_vm = wait_for_vm(&verify_log, &mut verify, &mut fixture, interrupt)?;
            wait_stage(
                "storage-verify_restored",
                working,
                &mut verify,
                &mut fixture,
                interrupt,
                Duration::from_secs(300),
            )?;
            let (verify_pid, verify_ticks, verify_children, verify_arm) = arm_after_stage(
                app_dir,
                &verify_vm,
                &verify_log,
                working,
                "storage-verify",
                "storage-verify_exit_requested",
                &mut verify,
                &mut fixture,
                interrupt,
                true,
            )?;
            let verify_native = wait_native_exit(
                "storage-verify",
                working,
                output,
                verify_pid,
                verify_ticks,
                &mut verify,
                interrupt,
                EXIT_GRACE,
                verify_arm,
            )?;
            let database = history_lock_database(&home_storage)?;
            let after = history_lock_watermark(&database)?;
            let quick_check = history_lock_quick_check(&database)?;
            phases.push(PhaseRecord {
                name: "storage-lock",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "writer lock blocked the paced turn; forced native exit {:?}; reopened with writer watermark {before:?} -> {after:?}, quick_check={quick_check}",
                    native.code
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: storage_children,
            });
            fs::write(
                output.join("shutdown-storage-lock.json"),
                serde_json::to_vec_pretty(&serde_json::json!({
                    "blockedExitCode": native.code,
                    "blockedExitSignal": native.signal,
                    "blockedElapsedMillis": native.elapsed.as_millis(),
                    "blockedReclaimedDescendants": native.reclaimed_descendants,
                    "before": before,
                    "after": after,
                    "verifyQuickCheck": quick_check,
                    "verifiedExitCode": verify_native.code,
                    "verifiedExitSignal": verify_native.signal,
                    "verifiedNativePid": verify_native.pid,
                    "verifiedOwnedChildren": verify_children,
                }))?,
            )?;
            ensure!(
                verify_native.code == Some(0) && verify_native.signal.is_none(),
                "storage verify native exit was not code 0: {}",
                verify_native.summary()
            );
            ensure!(
                quick_check == "ok",
                "reopened history database failed PRAGMA quick_check: {quick_check}"
            );
            ensure!(
                matches!(native.code, Some(0) | Some(1)),
                "storage blocked exit recorded no real exit code: {}",
                native.summary()
            );
            ensure!(
                after.turns >= before.turns && after.turns >= 1,
                "the durable prime turn was lost across the forced exit: {before:?} -> {after:?}"
            );
            write_sanitized_log(&verify_log, &output.join("shutdown-storage-verify-gui.log"))?;
        }

        // ------------------------------------------------- runtime-unavailable --
        {
            let log = working.join("shutdown-unavailable-gui.log");
            let mut gui = start_gui(
                workspace,
                &home_unavailable,
                &log,
                working,
                "runtime-unavailable",
            )?;
            let vm_url = wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            let (native_pid, start_ticks, children, arm) = arm_native(
                app_dir,
                &vm_url,
                &log,
                working,
                "runtime-unavailable",
                interrupt,
            )?;
            let native = wait_native_exit(
                "runtime-unavailable",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            phases.push(PhaseRecord {
                name: "runtime-unavailable",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "a real typed startup failure still closed through the real exit path: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(0) && native.signal.is_none(),
                "runtime-unavailable native exit was not code 0: {}",
                native.summary()
            );
            ensure!(
                native.reclaimed_descendants.is_empty(),
                "runtime-unavailable native exit left a child tree for the harness: {:?}",
                native.reclaimed_descendants
            );
            write_sanitized_log(&log, &output.join("shutdown-unavailable-gui.log"))?;
        }

        // ---------------------------------------------- service unresponsive --
        {
            let log = working.join("shutdown-service-gui.log");
            let project = prepare_project(working, "shutdown-service-project")?;
            let mut gui = start_gui_with(
                workspace,
                &home_service,
                &log,
                working,
                "service-unresponsive",
                NativeLaunch {
                    phase: Some("service-unresponsive"),
                    project: Some(&project),
                    prompt: Some(pl_provider_fixture::GUI_SHUTDOWN_PROMPTS[6]),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            let vm_url = wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            wait_stage(
                "service_inflight",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(300),
            )?;
            freeze_fixture(&fixture)?;
            fixture_paused = true;
            fs::write(working.join("shutdown-signal-service-frozen"), "frozen")?;
            let (native_pid, start_ticks, children, arm) = arm_after_stage(
                app_dir,
                &vm_url,
                &log,
                working,
                "service-unresponsive",
                "service_exit_requested",
                &mut gui,
                &mut fixture,
                interrupt,
                true,
            )?;
            let native = wait_native_exit(
                "service-unresponsive",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            resume_fixture(&fixture)?;
            fixture_paused = false;
            phases.push(PhaseRecord {
                name: "service-unresponsive",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "the frozen provider fixture did not block the real app exit: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(0) && native.signal.is_none(),
                "unresponsive-service native exit was not code 0: {}",
                native.summary()
            );
            ensure!(
                native.reclaimed_descendants.is_empty(),
                "unresponsive-service native exit left a child tree for the harness: {:?}",
                native.reclaimed_descendants
            );
            write_sanitized_log(&log, &output.join("shutdown-service-gui.log"))?;
        }

        // ------------------------------------------------- close during init --
        {
            let log = working.join("shutdown-init-close-gui.log");
            let mut gui = start_gui_with(
                workspace,
                &home_init_close,
                &log,
                working,
                "init-close",
                NativeLaunch {
                    fault: Some("pending-init"),
                    ..NativeLaunch::default()
                },
            )?;
            let vm_url = wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            let (native_pid, start_ticks, children, arm) =
                arm_native(app_dir, &vm_url, &log, working, "init-close", interrupt)?;
            let native = wait_native_exit(
                "init-close",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            phases.push(PhaseRecord {
                name: "close-during-init",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "an exit requested while initialization was permanently pending forced exit 1: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(1) && native.signal.is_none(),
                "close-during-init native exit was not code 1: {}",
                native.summary()
            );
            write_sanitized_log(&log, &output.join("shutdown-init-close-gui.log"))?;
        }

        // ------------------------------------------------- bridge-unavailable --
        {
            let log = working.join("shutdown-bridge-gui.log");
            let mut gui = start_gui_with(
                workspace,
                &home_bridge,
                &log,
                working,
                "bridge",
                NativeLaunch {
                    fault: Some("bridge-load-error"),
                    ..NativeLaunch::default()
                },
            )?;
            let vm_url = wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            let (native_pid, start_ticks, children, arm) =
                arm_native(app_dir, &vm_url, &log, working, "bridge", interrupt)?;
            let native = wait_native_exit(
                "bridge",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            phases.push(PhaseRecord {
                name: "bridge-unavailable",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "a native-fault bridge-load failure closed as NotStarted with exit 0: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(0) && native.signal.is_none(),
                "bridge-unavailable native exit was not code 0: {}",
                native.summary()
            );
            write_sanitized_log(&log, &output.join("shutdown-bridge-gui.log"))?;
        }

        // ------------------------------------------------- subscription fault --
        {
            let log = working.join("shutdown-subscription-gui.log");
            let mut gui = start_gui_with(
                workspace,
                &home_subscription,
                &log,
                working,
                "subscription-fault",
                NativeLaunch {
                    fault: Some("subscription"),
                    ..NativeLaunch::default()
                },
            )?;
            let vm_url = wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            let (native_pid, start_ticks, children, arm) = arm_native(
                app_dir,
                &vm_url,
                &log,
                working,
                "subscription-fault",
                interrupt,
            )?;
            let native = wait_native_exit(
                "subscription-fault",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            copy_home_diagnostics(&home_subscription, output, "subscription-fault")?;
            let log_check = validate_dart_error_dir(
                &output.join("diagnostics").join("subscription-fault"),
                "progress",
            )?;
            phases.push(PhaseRecord {
                name: "subscription-fault",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "a faulty shutdown-progress subscription produced a typed progress diagnostic and forced exit 1; log check {log_check}: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(1) && native.signal.is_none(),
                "subscription-fault native exit was not code 1: {}",
                native.summary()
            );
            ensure!(
                log_check["containsStage"] == true
                    && log_check["containsCorrelation"] == true
                    && log_check["containsStack"] == true,
                "subscription-fault diagnostics did not record the typed progress issue: {log_check}"
            );
            write_sanitized_log(&log, &output.join("shutdown-subscription-gui.log"))?;
        }

        // ------------------------------------------------- dart error fallback --
        {
            let log = working.join("shutdown-tmp-fallback-gui.log");
            let mut gui = start_gui_with(
                workspace,
                &home_tmp_fallback,
                &log,
                working,
                "tmp-fallback",
                NativeLaunch {
                    fault: Some("subscription"),
                    tmpdir: Some(&tmp_fallback_tmp),
                    ..NativeLaunch::default()
                },
            )?;
            let vm_url = wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            let (native_pid, start_ticks, children, arm) =
                arm_native(app_dir, &vm_url, &log, working, "tmp-fallback", interrupt)?;
            let native = wait_native_exit(
                "tmp-fallback",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            let fallback_dest = output.join("diagnostics").join("tmp-fallback-temp");
            fs::create_dir_all(&fallback_dest)?;
            if tmp_fallback_tmp.is_dir() {
                for entry in fs::read_dir(&tmp_fallback_tmp)? {
                    let entry = entry?;
                    if entry.file_type()?.is_file() {
                        fs::copy(entry.path(), fallback_dest.join(entry.file_name()))?;
                    }
                }
            }
            let fallback_check = validate_dart_error_dir(&tmp_fallback_tmp, "progress")?;
            phases.push(PhaseRecord {
                name: "dart-error-fallback",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "an unwritable canonical diagnostics path fell back to the isolated TMPDIR (native pid {native_pid}); check {fallback_check}: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(1) && native.signal.is_none(),
                "dart-error-fallback native exit was not code 1: {}",
                native.summary()
            );
            ensure!(
                fallback_check["containsStage"] == true
                    && fallback_check["containsCorrelation"] == true
                    && fallback_check["containsStack"] == true,
                "dart-error-fallback recorded no temp-fallback diagnostic: {fallback_check}"
            );
            write_sanitized_log(&log, &output.join("shutdown-tmp-fallback-gui.log"))?;
        }

        // ------------------------------------------------- native subtree reclamation --
        {
            // The home starts a scenario-owned stdio MCP server that spawns a
            // SIGTERM-ignoring grandchild in its own process group. After the
            // forced exit the product's own supervisor must reclaim that whole
            // subtree BEFORE this harness does: a non-empty reclaimed-descendant
            // set would mean the product leaked and the harness had to cover it.
            let log = working.join("shutdown-mcp-gui.log");
            let project = prepare_project(working, "shutdown-mcp-project")?;
            let mut gui = start_gui_with(
                workspace,
                &home_mcp,
                &log,
                working,
                "mcp-reclamation",
                NativeLaunch {
                    phase: Some("mcp-reclamation"),
                    project: Some(&project),
                    prompt: Some(pl_provider_fixture::GUI_SHUTDOWN_PROMPTS[7]),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            wait_stage(
                "mcp-reclamation_served",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(300),
            )?;
            let (native_pid, start_ticks, children) = snapshot_native(&log)?;
            let coord = read_phase_json(&mcp_coord)?;
            let mcp_pid = coord["mcpPid"].as_u64().unwrap_or_default() as u32;
            let mcp_ticks = coord["mcpStartTicks"].as_u64();
            let grandchild_pid = coord["grandchildPid"].as_u64().unwrap_or_default() as u32;
            let grandchild_ticks = coord["grandchildStartTicks"].as_u64();
            ensure!(
                mcp_pid > 0 && grandchild_pid > 0 && grandchild_pid != mcp_pid,
                "the scenario MCP server recorded no distinct business pids: {coord}"
            );
            #[cfg(target_os = "linux")]
            {
                ensure!(
                    proc_alive(mcp_pid, mcp_ticks) && proc_alive(grandchild_pid, grandchild_ticks),
                    "the MCP business pids were not alive BEFORE the forced exit was requested: mcp={mcp_pid} grandchild={grandchild_pid}"
                );
            }
            let monitor = monitor_business_pids(
                vec![(mcp_pid, mcp_ticks), (grandchild_pid, grandchild_ticks)],
                EXIT_GRACE,
            );
            fs::write(
                working.join("shutdown-signal-mcp-reclamation-armed"),
                "armed",
            )?;
            wait_stage(
                "mcp-reclamation_exit_requested",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(180),
            )?;
            let arm = Instant::now();
            let native = wait_native_exit(
                "mcp-reclamation",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            let reclamation = monitor
                .join()
                .unwrap_or_else(|_| serde_json::json!({"monitor": "panicked"}));
            let forced_kill =
                force_kill_alive([(grandchild_pid, grandchild_ticks), (mcp_pid, mcp_ticks)]);
            fs::write(
                output.join("shutdown-mcp-reclamation.json"),
                serde_json::to_vec_pretty(&serde_json::json!({
                    "coord": coord,
                    "mcpPid": mcp_pid,
                    "grandchildPid": grandchild_pid,
                    "descendantsAtRootExit": native.descendants_at_root_exit,
                    "reclaimedDescendants": native.reclaimed_descendants,
                    "monitor": reclamation,
                    "forcedKill": forced_kill,
                    "descendantCleanupContract": "unconfirmed_after_forced_application_exit",
                }))?,
            )?;
            phases.push(PhaseRecord {
                name: "mcp-forced-exit-boundary",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "after the scenario-owned stdio MCP server and its SIGTERM-ignoring grandchild were proven live, the thin native assembly hung the isolate and the native host forced the process out (exit 1) at the single 30-second deadline with descendants and any harness reclamation recorded separately; abrupt application exit does not confirm Executor descendant cleanup: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(1) && native.signal.is_none(),
                "mcp-reclamation native exit was not code 1 (hung isolate forced out at the fixed 30-second deadline): {}",
                native.summary()
            );
            ensure!(
                native.elapsed <= EXIT_BUDGET + Duration::from_secs(1)
                    && native.elapsed + Duration::from_secs(1) >= EXIT_BUDGET,
                "mcp-reclamation did not exit at the single 30-second deadline (measured from the real arm): {:?}",
                native.elapsed
            );
            // Issue #397 deliberately removes the per-business subreaper worker.
            // The blocked isolate never requests coordinated Executor shutdown;
            // do not turn a harness cleanup into a claim about product ownership.
            write_sanitized_log(&log, &output.join("shutdown-mcp-gui.log"))?;
        }

        // ------------------------------------------------- lsp subtree reclamation --
        {
            let log = working.join("shutdown-lsp-gui.log");
            let project = prepare_project(working, "shutdown-lsp-project")?;
            fs::write(
                project.join(pl_provider_fixture::GUI_SHUTDOWN_LSP_FILE),
                b"language: anywork-shutdown-fixture\n",
            )?;
            let mut gui = start_gui_with(
                workspace,
                &home_lsp,
                &log,
                working,
                "lsp-reclamation",
                NativeLaunch {
                    phase: Some("lsp-reclamation"),
                    project: Some(&project),
                    prompt: Some(pl_provider_fixture::GUI_SHUTDOWN_PROMPTS[8]),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            wait_stage(
                "lsp-reclamation_served",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(300),
            )?;
            let (native_pid, start_ticks, children) = snapshot_native(&log)?;
            let coord = read_phase_json(&lsp_coord)?;
            let lsp_pid = coord["lspPid"].as_u64().unwrap_or_default() as u32;
            let lsp_ticks = coord["lspStartTicks"].as_u64();
            let grandchild_pid = coord["grandchildPid"].as_u64().unwrap_or_default() as u32;
            let grandchild_ticks = coord["grandchildStartTicks"].as_u64();
            ensure!(
                lsp_pid > 0 && grandchild_pid > 0 && grandchild_pid != lsp_pid,
                "the scenario LSP server recorded no distinct business pids: {coord}"
            );
            #[cfg(target_os = "linux")]
            {
                ensure!(
                    proc_alive(lsp_pid, lsp_ticks) && proc_alive(grandchild_pid, grandchild_ticks),
                    "the LSP business pids were not alive BEFORE the forced exit was requested: lsp={lsp_pid} grandchild={grandchild_pid}"
                );
            }
            let monitor = monitor_business_pids(
                vec![(lsp_pid, lsp_ticks), (grandchild_pid, grandchild_ticks)],
                EXIT_GRACE,
            );
            fs::write(
                working.join("shutdown-signal-lsp-reclamation-armed"),
                "armed",
            )?;
            wait_stage(
                "lsp-reclamation_exit_requested",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(180),
            )?;
            let arm = Instant::now();
            let native = wait_native_exit(
                "lsp-reclamation",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            let reclamation = monitor
                .join()
                .unwrap_or_else(|_| serde_json::json!({"monitor": "panicked"}));
            let forced_kill =
                force_kill_alive([(grandchild_pid, grandchild_ticks), (lsp_pid, lsp_ticks)]);
            fs::write(
                output.join("shutdown-lsp-reclamation.json"),
                serde_json::to_vec_pretty(&serde_json::json!({
                    "coord": coord,
                    "lspPid": lsp_pid,
                    "grandchildPid": grandchild_pid,
                    "descendantsAtRootExit": native.descendants_at_root_exit,
                    "reclaimedDescendants": native.reclaimed_descendants,
                    "monitor": reclamation,
                    "forcedKill": forced_kill,
                    "descendantCleanupContract": "unconfirmed_after_forced_application_exit",
                }))?,
            )?;
            phases.push(PhaseRecord {
                name: "lsp-forced-exit-boundary",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "after the scenario-owned fake LSP server (started by the real `lsp_query` tool turn) and its SIGTERM-ignoring grandchild were proven live, the thin native assembly hung the isolate and the native host forced the process out (exit 1) at the single 30-second deadline with descendants and any harness reclamation recorded separately; abrupt application exit does not confirm Executor descendant cleanup: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(1) && native.signal.is_none(),
                "lsp-reclamation native exit was not code 1 (hung isolate forced out at the fixed 30-second deadline): {}",
                native.summary()
            );
            ensure!(
                native.elapsed <= EXIT_BUDGET + Duration::from_secs(1)
                    && native.elapsed + Duration::from_secs(1) >= EXIT_BUDGET,
                "lsp-reclamation did not exit at the single 30-second deadline (measured from the real arm): {:?}",
                native.elapsed
            );
            // Issue #397 deliberately removes the per-business subreaper worker.
            // The blocked isolate never requests coordinated Executor shutdown;
            // do not turn a harness cleanup into a claim about product ownership.
            write_sanitized_log(&log, &output.join("shutdown-lsp-gui.log"))?;
        }

        // ------------------------------------------------ tool subtree reclamation --
        {
            let log = working.join("shutdown-tool-gui.log");
            let project = prepare_project(working, "shutdown-tool-project")?;
            let mut gui = start_gui_with(
                workspace,
                &home_tool,
                &log,
                working,
                "tool-reclamation",
                NativeLaunch {
                    phase: Some("tool-reclamation"),
                    project: Some(&project),
                    prompt: Some(pl_provider_fixture::GUI_SHUTDOWN_PROMPTS[9]),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            wait_stage(
                "tool-reclamation_served",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(300),
            )?;
            let (native_pid, start_ticks, children) = snapshot_native(&log)?;
            let coord = read_phase_json(&tool_coord)?;
            let tool_pid = coord["toolPid"].as_u64().unwrap_or_default() as u32;
            let tool_ticks = coord["toolStartTicks"].as_u64();
            let grandchild_pid = coord["grandchildPid"].as_u64().unwrap_or_default() as u32;
            let grandchild_ticks = coord["grandchildStartTicks"].as_u64();
            ensure!(
                tool_pid > 0 && grandchild_pid > 0 && grandchild_pid != tool_pid,
                "the scenario background tool recorded no distinct business pids: {coord}"
            );
            #[cfg(target_os = "linux")]
            {
                ensure!(
                    proc_alive(tool_pid, tool_ticks)
                        && proc_alive(grandchild_pid, grandchild_ticks),
                    "the tool business pids were not alive BEFORE the forced exit was requested: tool={tool_pid} grandchild={grandchild_pid}"
                );
            }
            let monitor = monitor_business_pids(
                vec![(tool_pid, tool_ticks), (grandchild_pid, grandchild_ticks)],
                EXIT_GRACE,
            );
            fs::write(
                working.join("shutdown-signal-tool-reclamation-armed"),
                "armed",
            )?;
            wait_stage(
                "tool-reclamation_exit_requested",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(180),
            )?;
            let arm = Instant::now();
            let native = wait_native_exit(
                "tool-reclamation",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            let reclamation = monitor
                .join()
                .unwrap_or_else(|_| serde_json::json!({"monitor": "panicked"}));
            let forced_kill =
                force_kill_alive([(grandchild_pid, grandchild_ticks), (tool_pid, tool_ticks)]);
            fs::write(
                output.join("shutdown-tool-reclamation.json"),
                serde_json::to_vec_pretty(&serde_json::json!({
                    "coord": coord,
                    "toolPid": tool_pid,
                    "grandchildPid": grandchild_pid,
                    "descendantsAtRootExit": native.descendants_at_root_exit,
                    "reclaimedDescendants": native.reclaimed_descendants,
                    "monitor": reclamation,
                    "forcedKill": forced_kill,
                    "descendantCleanupContract": "unconfirmed_after_forced_application_exit",
                }))?,
            )?;
            phases.push(PhaseRecord {
                name: "tool-forced-exit-boundary",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "after the scenario-owned background `exec` tool (started by the native Executor) and its SIGTERM-ignoring grandchild were proven live, the thin native assembly hung the isolate and the native host forced the process out (exit 1) at the single 30-second deadline with descendants and any harness reclamation recorded separately; abrupt application exit does not confirm Executor descendant cleanup: {}",
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                native.code == Some(1) && native.signal.is_none(),
                "tool-reclamation native exit was not code 1 (hung isolate forced out at the fixed 30-second deadline): {}",
                native.summary()
            );
            ensure!(
                native.elapsed <= EXIT_BUDGET + Duration::from_secs(1)
                    && native.elapsed + Duration::from_secs(1) >= EXIT_BUDGET,
                "tool-reclamation did not exit at the single 30-second deadline (measured from the real arm): {:?}",
                native.elapsed
            );
            // Issue #397 deliberately removes the per-business subreaper worker.
            // The blocked isolate never requests coordinated Executor shutdown;
            // do not turn a harness cleanup into a claim about product ownership.
            write_sanitized_log(&log, &output.join("shutdown-tool-gui.log"))?;
        }

        // ---------------------------------------------------- concurrent stop --
        {
            let log = working.join("shutdown-concurrent-gui.log");
            let project = prepare_project(working, "shutdown-concurrent-project")?;
            let mut gui = start_gui_with(
                workspace,
                &home_concurrent,
                &log,
                working,
                "concurrent-stop",
                NativeLaunch {
                    phase: Some("concurrent-stop"),
                    project: Some(&project),
                    prompt: Some(pl_provider_fixture::GUI_SHUTDOWN_PROMPTS[10]),
                    output: Some(output),
                    ..NativeLaunch::default()
                },
            )?;
            wait_for_vm(&log, &mut gui, &mut fixture, interrupt)?;
            wait_stage(
                "concurrent-stop_served",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(300),
            )?;
            let continuation = wait_concurrent_continuation(
                status_file,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(120),
            )?;
            let database = history_lock_database(&home_concurrent)?;
            let before = history_lock_watermark(&database)?;
            let mut lock = SqliteWriteLock::acquire(
                &database,
                "shutdown concurrent history.sqlite",
                Duration::from_secs(120),
            )?;
            let (native_pid, start_ticks, children) = snapshot_native(&log)?;
            let mcp = read_phase_json(&concurrent_mcp_coord)?;
            let mcp_pid = mcp["mcpPid"].as_u64().unwrap_or_default() as u32;
            let mcp_ticks = mcp["mcpStartTicks"].as_u64();
            let mcp_gc_pid = mcp["grandchildPid"].as_u64().unwrap_or_default() as u32;
            let mcp_gc_ticks = mcp["grandchildStartTicks"].as_u64();
            let tool = read_phase_json(&concurrent_tool_coord)?;
            let tool_pid = tool["toolPid"].as_u64().unwrap_or_default() as u32;
            let tool_ticks = tool["toolStartTicks"].as_u64();
            let tool_gc_pid = tool["grandchildPid"].as_u64().unwrap_or_default() as u32;
            let tool_gc_ticks = tool["grandchildStartTicks"].as_u64();
            ensure!(
                mcp_pid > 0 && mcp_gc_pid > 0 && mcp_gc_pid != mcp_pid,
                "the concurrent MCP server recorded no distinct business pids: {mcp}"
            );
            ensure!(
                tool_pid > 0 && tool_gc_pid > 0 && tool_gc_pid != tool_pid,
                "the concurrent background tool recorded no distinct business pids: {tool}"
            );
            #[cfg(target_os = "linux")]
            {
                ensure!(
                    proc_alive(mcp_pid, mcp_ticks)
                        && proc_alive(mcp_gc_pid, mcp_gc_ticks)
                        && proc_alive(tool_pid, tool_ticks)
                        && proc_alive(tool_gc_pid, tool_gc_ticks),
                    "a concurrent business pid was not alive BEFORE the exit was requested: \
                     mcp={mcp_pid} mcpGrandchild={mcp_gc_pid} tool={tool_pid} toolGrandchild={tool_gc_pid}"
                );
            }
            let monitor = monitor_concurrent_stop(
                (native_pid, start_ticks),
                vec![
                    (mcp_pid, mcp_ticks),
                    (mcp_gc_pid, mcp_gc_ticks),
                    (tool_pid, tool_ticks),
                    (tool_gc_pid, tool_gc_ticks),
                ],
                EXIT_GRACE,
            );
            fs::write(
                working.join("shutdown-signal-concurrent-stop-armed"),
                "armed",
            )?;
            wait_stage(
                "concurrent-stop_exit_requested",
                working,
                &mut gui,
                &mut fixture,
                interrupt,
                Duration::from_secs(180),
            )?;
            let arm = Instant::now();
            let native = wait_native_exit(
                "concurrent-stop",
                working,
                output,
                native_pid,
                start_ticks,
                &mut gui,
                interrupt,
                EXIT_GRACE,
                arm,
            )?;
            let reclamation = monitor
                .join()
                .unwrap_or_else(|_| serde_json::json!({"monitor": "panicked"}));
            lock.finish()?;
            let forced_kill = force_kill_alive([
                (mcp_gc_pid, mcp_gc_ticks),
                (mcp_pid, mcp_ticks),
                (tool_gc_pid, tool_gc_ticks),
                (tool_pid, tool_ticks),
            ]);
            let stop_millis = |pid: u32| -> Option<u128> {
                reclamation["observed"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .find(|row| row["pid"].as_u64() == Some(u64::from(pid)))
                    .and_then(|row| row["exitedAtMillis"].as_u64())
                    .map(u128::from)
            };
            let mcp_process_stop = stop_millis(mcp_pid);
            let mcp_grandchild_stop = stop_millis(mcp_gc_pid);
            let tool_process_stop = stop_millis(tool_pid);
            let tool_grandchild_stop = stop_millis(tool_gc_pid);
            let resource_stop = |process: Option<u128>, grandchild: Option<u128>| -> Option<u128> {
                match (process, grandchild) {
                    (Some(process), Some(grandchild)) => Some(process.max(grandchild)),
                    _ => None,
                }
            };
            let mcp_stop = resource_stop(mcp_process_stop, mcp_grandchild_stop);
            let tool_stop = resource_stop(tool_process_stop, tool_grandchild_stop);
            let native_exited_at = reclamation["nativeExitedAtMillis"].as_u64().map(u128::from);
            let mcp_before_native_exit =
                matches!((mcp_stop, native_exited_at), (Some(stop), Some(at)) if stop < at);
            let tool_before_native_exit =
                matches!((tool_stop, native_exited_at), (Some(stop), Some(at)) if stop < at);
            let database_after = history_lock_database(&home_concurrent)?;
            let after = history_lock_watermark(&database_after)?;
            let quick_check = history_lock_quick_check(&database_after)?;
            let native_diagnostics = read_native_exit_diagnostics(&home_concurrent)?;
            let diagnostics_code = native_diagnostics["code"].as_str().unwrap_or_default();
            let diagnostics_pending = native_diagnostics["pending"].as_str().unwrap_or_default();
            fs::write(
                output.join("shutdown-concurrent-stop.json"),
                serde_json::to_vec_pretty(&serde_json::json!({
                    "nativePid": native.pid,
                    "nativeExitCode": native.code,
                    "nativeExitSignal": native.signal,
                    "nativeElapsedMillis": native.elapsed.as_millis(),
                    "budgetMillis": EXIT_BUDGET.as_millis(),
                    "cleanupBudgetMillis": CONCURRENT_CLEANUP_BUDGET.as_millis(),
                    "stopAckBoundMillis": CONCURRENT_STOP_ACK_BOUND.as_millis(),
                    "nativeExitedAtMillis": native_exited_at,
                    "writerLockHeldAcrossExit": true,
                    "continuationAccepted": true,
                    "continuationLiveStatus": continuation,
                    "nativeExitDiagnostics": native_diagnostics,
                    "mcp": {
                        "pid": mcp_pid,
                        "grandchildPid": mcp_gc_pid,
                        "processStopMillis": mcp_process_stop,
                        "grandchildStopMillis": mcp_grandchild_stop,
                        "stopMillis": mcp_stop,
                    },
                    "tool": {
                        "pid": tool_pid,
                        "grandchildPid": tool_gc_pid,
                        "processStopMillis": tool_process_stop,
                        "grandchildStopMillis": tool_grandchild_stop,
                        "stopMillis": tool_stop,
                    },
                    "monitor": reclamation,
                    "descendantsAtRootExit": native.descendants_at_root_exit,
                    "reclaimedDescendants": native.reclaimed_descendants,
                    "forcedKill": forced_kill,
                    "before": before,
                    "after": after,
                    "quickCheck": quick_check,
                }))?,
            )?;
            phases.push(PhaseRecord {
                name: "concurrent-stop",
                status: "executed",
                coverage: "executed",
                detail: format!(
                    "the concurrent turn's required receipt continuation was accepted (consumed {}/{} steps, remainingOptional={}) before the exclusive writer lock was taken across the exit (blocked terminal save); the scenario-owned stdio MCP server and the background tool subtree, each with an inherited-group descendant, were proven live and then reclaimed on their own (mcp stop {mcp_stop:?} ms, tool stop {tool_stop:?} ms) while that chain was still waiting; the native exit code 1 was a non-clean degraded shutdown (event={} code={} pending={}, coordinatedFinish={}, deadlineImminent={}): {}",
                    continuation.consumed_steps,
                    continuation.expected_steps,
                    continuation.remaining_optional,
                    native_diagnostics["event"].as_str().unwrap_or_default(),
                    diagnostics_code,
                    diagnostics_pending,
                    native_diagnostics["coordinatedFinish"],
                    native_diagnostics["deadlineImminent"],
                    native.summary()
                ),
                exit_code: native.code,
                elapsed_millis: Some(native.elapsed.as_millis()),
                native_pid: Some(native.pid),
                owned_children: children,
            });
            ensure!(
                reclamation["stillAlive"]
                    .as_array()
                    .is_some_and(Vec::is_empty)
                    && forced_kill.is_empty(),
                "an independent resource was still alive at the observation deadline: {reclamation}"
            );
            ensure!(
                native.reclaimed_descendants.is_empty(),
                "the product leaked a concurrent subtree and the harness had to reclaim it: {:?}",
                native.reclaimed_descendants
            );
            let stop_ack_bound_ms = CONCURRENT_STOP_ACK_BOUND.as_millis();
            ensure!(
                mcp_stop.is_some_and(|ms| ms <= stop_ack_bound_ms),
                "the MCP resource was not confirmed reclaimed within {stop_ack_bound_ms} ms: \
                 mcpProcess={mcp_process_stop:?} mcpGrandchild={mcp_grandchild_stop:?} \
                 (observed {reclamation})"
            );
            ensure!(
                tool_stop.is_some_and(|ms| ms <= stop_ack_bound_ms),
                "the tool resource was not confirmed reclaimed within {stop_ack_bound_ms} ms: \
                 toolProcess={tool_process_stop:?} toolGrandchild={tool_grandchild_stop:?} \
                 (observed {reclamation})"
            );
            ensure!(
                mcp_before_native_exit && tool_before_native_exit,
                "a resource did not stop before the real native exit, so the blocked chain was not \
                 still waiting: mcp={mcp_stop:?} (process {mcp_process_stop:?}, grandchild \
                 {mcp_grandchild_stop:?}) tool={tool_stop:?} (process {tool_process_stop:?}, \
                 grandchild {tool_grandchild_stop:?}) nativeExitedAt={native_exited_at:?} \
                 (observed {reclamation})"
            );
            ensure!(
                native.code == Some(1) && native.signal.is_none(),
                "concurrent-stop native exit was not the degraded code 1: {}",
                native.summary()
            );
            ensure!(
                native.elapsed <= EXIT_BUDGET + Duration::from_secs(1),
                "concurrent-stop ran past the single 30-second hard deadline: {:?}",
                native.elapsed
            );
            ensure!(
                native.elapsed + Duration::from_secs(1) >= CONCURRENT_CLEANUP_BUDGET,
                "concurrent-stop exited before the 28-second cleanup budget, so the writer lock \
                 did not block the save to the budget: {:?}",
                native.elapsed
            );
            ensure!(
                quick_check == "ok",
                "reopened concurrent history database failed PRAGMA quick_check: {quick_check}"
            );
            ensure!(
                diagnostics_code != "cleanExit"
                    && (diagnostics_pending == "unknown"
                        || matches!(
                            diagnostics_pending.parse::<u64>(),
                            Ok(pending) if pending > 0
                        )),
                "the concurrent shutdown was recorded as clean or fully drained, so the writer \
                 lock did not block the save: {native_diagnostics}"
            );
            write_sanitized_log(&log, &output.join("shutdown-concurrent-gui.log"))?;
        }

        Ok(())
    })();

    if fixture_paused {
        let _ = resume_fixture(&fixture);
    }

    // Preserve the launch identity, assembly state and original launcher reports
    // even when a phase fails before arming exit. The outer TempDir is removed.
    // Keep the journey's original error primary if retention itself fails.
    let retained_evidence = retain_native_evidence(working, output);
    if let Err(error) = &retained_evidence {
        eprintln!("shutdown evidence retention failed: {error:#}");
    }

    // Canonical diagnostics live under `ANYWORK_HOME/studio/logs`; copy them so
    // the PID/stage/elapsed/error-code/correlation/persistence facts survive the
    // run's temporary coordination directory, and never rely on stdout alone.
    let mut diagnostics = serde_json::Map::new();
    let diagnostic_homes: [(&str, &Path); 14] = [
        ("normal", *home),
        ("duplicate", home_duplicate.as_path()),
        ("hang", home_hang.as_path()),
        ("storage", home_storage.as_path()),
        ("service", home_service.as_path()),
        ("runtime-unavailable", home_unavailable.as_path()),
        ("init-close", home_init_close.as_path()),
        ("bridge", home_bridge.as_path()),
        ("subscription-fault", home_subscription.as_path()),
        ("tmp-fallback", home_tmp_fallback.as_path()),
        ("mcp-reclamation", home_mcp.as_path()),
        ("lsp-reclamation", home_lsp.as_path()),
        ("tool-reclamation", home_tool.as_path()),
        ("concurrent-stop", home_concurrent.as_path()),
    ];
    for (label, dir) in diagnostic_homes {
        let copied = copy_home_diagnostics(dir, output, label)?;
        diagnostics.insert(
            label.to_owned(),
            serde_json::json!({
                "homeStudioLogs": dir.join("studio/logs").display().to_string(),
                "copiedFiles": copied,
            }),
        );
    }
    fs::write(
        output.join("diagnostics.json"),
        serde_json::to_vec_pretty(&serde_json::Value::Object(diagnostics))?,
    )?;

    // Platform coverage and an intentionally excluded guarantee stay explicit.
    let gaps = vec![
        GapRecord {
            requirement: "non-linux-native-acceptance",
            reason: "this task executes native behavior on Linux; Windows and macOS are compile-only",
            interface_needs: "a native behavior run on the corresponding platform",
        },
        GapRecord {
            requirement: "descendant-reclamation-after-forced-application-exit",
            reason: "the isolate never starts coordinated shutdown; native process-group ownership has no surviving per-process supervisor after abrupt application exit",
            interface_needs: "outside issue #397; actual descendants and harness cleanup remain in each forced-exit report",
        },
    ];

    // Machine checks are `passed` only for the requirements this Linux run
    // actually executed; skipped requirements are `notCovered`, never assumed.
    let machine_checks = serde_json::json!({
        "normalExit": if phases.iter().any(|phase| phase.name == "normal") { "executed" } else { "notCovered" },
        "reopenRestore": if phases.iter().any(|phase| phase.name == "reopen") { "executed" } else { "notCovered" },
        "secondInstanceRedirect": if phases.iter().any(|phase| phase.name == "busy") { "executed" } else { "notCovered" },
        "busyReopenRestore": if phases.iter().any(|phase| phase.name == "busy-reopen") { "executed" } else { "notCovered" },
        "duplicateDeadline": if phases.iter().any(|phase| phase.name == "duplicate") { "executed" } else { "notCovered" },
        "dartHangForced30s": if phases.iter().any(|phase| phase.name == "hang") { "executed" } else { "notCovered" },
        "runtimeUnavailableClose": if phases.iter().any(|phase| phase.name == "runtime-unavailable") { "executed" } else { "notCovered" },
        "storageLockReopen": if phases.iter().any(|phase| phase.name == "storage-lock") { "executed" } else { "notCovered" },
        "serviceUnresponsive": if phases.iter().any(|phase| phase.name == "service-unresponsive") { "executed" } else { "notCovered" },
        "mcpForcedExitBoundary": if phases.iter().any(|phase| phase.name == "mcp-forced-exit-boundary") { "executed" } else { "notCovered" },
        "closeDuringInit": if phases.iter().any(|phase| phase.name == "close-during-init") { "executed" } else { "notCovered" },
        "bridgeUnavailable": if phases.iter().any(|phase| phase.name == "bridge-unavailable") { "executed" } else { "notCovered" },
        "subscriptionCancelFault": if phases.iter().any(|phase| phase.name == "subscription-fault") { "executed" } else { "notCovered" },
        "dartErrorTempFallback": if phases.iter().any(|phase| phase.name == "dart-error-fallback") { "executed" } else { "notCovered" },
        "lspForcedExitBoundary": if phases.iter().any(|phase| phase.name == "lsp-forced-exit-boundary") { "executed" } else { "notCovered" },
        "toolForcedExitBoundary": if phases.iter().any(|phase| phase.name == "tool-forced-exit-boundary") { "executed" } else { "notCovered" },
        "concurrentResourceStop": if phases.iter().any(|phase| phase.name == "concurrent-stop") { "executed" } else { "notCovered" },
        "descendantReclamationAfterForcedExit": "notGuaranteed",
        "windowsNativeAcceptance": "notrun",
        "humanVerdict": "pending",
    });

    // `json!` requires every value to be `Serialize`, and `anyhow::Error` is
    // not, so the fallible live read is flattened to `Option<usize>` here.
    let live_status = read_live_status(status_file).ok();
    let accepted = live_status.as_ref().map(|status| status.accepted);
    let rejected = live_status.as_ref().map(|status| status.rejected);
    fs::write(
        output.join("coverage.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "shutdown",
            "platform": std::env::consts::OS,
            "exitBudgetMillis": EXIT_BUDGET.as_millis(),
            "humanVerdict": "pending",
            "machineChecks": machine_checks,
            "phases": phases,
            "gaps": gaps,
            "liveStatus": live_status,
        }))?,
    )?;
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "shutdown",
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "liveStatus": live_status,
        }))?,
    )?;

    // Only the happy-path phases are gated on a clean GUI log; the fault phases
    // deliberately force exit code 1, a failed runtime install or a frozen
    // provider, so their error lines are recorded as evidence, not treated as an
    // acceptance failure.
    let log_sources: [(&str, bool); 19] = [
        ("shutdown-normal-gui.log", true),
        ("shutdown-reopen-gui.log", true),
        ("shutdown-busy-first-gui.log", true),
        ("shutdown-busy-second-gui.log", false),
        ("shutdown-busy-reopen-gui.log", true),
        // The duplicate phase runs the subscription-fault assembly so the
        // repeated close is genuinely delivered; its log carries that injected
        // fault on purpose and is therefore not a happy-path error source.
        ("shutdown-duplicate-gui.log", false),
        ("shutdown-hang-gui.log", false),
        ("shutdown-unavailable-gui.log", false),
        ("shutdown-storage-prime-gui.log", false),
        ("shutdown-storage-verify-gui.log", true),
        ("shutdown-service-gui.log", false),
        ("shutdown-init-close-gui.log", false),
        ("shutdown-bridge-gui.log", false),
        ("shutdown-subscription-gui.log", false),
        ("shutdown-tmp-fallback-gui.log", false),
        ("shutdown-mcp-gui.log", false),
        ("shutdown-lsp-gui.log", false),
        ("shutdown-tool-gui.log", false),
        ("shutdown-concurrent-gui.log", false),
    ];
    let mut strict_errors = 0usize;
    let mut gui_metrics = serde_json::Map::new();
    for (name, strict) in log_sources {
        let source = working.join(name);
        if !source.is_file() {
            continue;
        }
        write_sanitized_log(&source, &output.join(name))?;
        let count = count_gui_errors(&source)?;
        if strict {
            strict_errors += count;
        }
        gui_metrics.insert(
            name.to_owned(),
            serde_json::json!({ "unhandledErrors": count, "strict": strict }),
        );
    }
    fs::write(
        output.join("gui-health.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "unhandledErrors": strict_errors,
            "phases": gui_metrics,
            "humanVerdict": "pending",
        }))?,
    )?;

    let fixture_result = fixture.stop(requests_file);
    drop(fixture);
    // Re-read the strict counters after the fixture stopped. The fixture's own
    // exit status already encodes `FixtureReport::verify` (a non-zero exit when
    // any required step was left unconsumed), and this snapshot makes the
    // required-step gate explicit instead of trusting an accepted-request count.
    let final_live_status = read_live_status(status_file).ok();
    write_fixture_log(fixture_log, &output.join("fixture.log"))?;
    let requests = if requests_file.is_file() {
        sanitize_requests(requests_file, &output.join("requests.json"))?;
        serde_json::from_slice::<Vec<serde_json::Value>>(&fs::read(requests_file)?)?
    } else {
        Vec::new()
    };
    let rejected_total = requests
        .iter()
        .filter(|row| row["accepted"] == false)
        .count();
    let accepted_total = requests
        .iter()
        .filter(|row| row["accepted"] == true)
        .count();
    println!("Evidence: {} (human verdict pending)", output.display());

    journey?;
    retained_evidence?;

    let fixture_status = fixture_result.as_ref().map(|status| status.to_string());
    ensure!(
        fixture_result.as_ref().is_ok_and(ExitStatus::success)
            && rejected_total == 0
            && strict_errors == 0,
        "shutdown fixture or GUI health incomplete; human verdict pending \
         (accepted={accepted_total}, rejected={rejected_total}, strictErrors={strict_errors}, \
         fixtureStopped={fixture_status:?}, finalLiveStatus={final_live_status:?})"
    );
    Ok(())
}

/// Path of the structured native exit report the launcher writes for [label].
fn native_report_path(working: &Path, label: &str) -> PathBuf {
    working.join(format!("shutdown-native-exit-{label}.json"))
}

/// Optional thin native-test assembly for a shutdown scene.
#[derive(Default)]
struct NativeLaunch<'a> {
    env: &'a [(&'a str, &'a str)],
    fault: Option<&'a str>,
    phase: Option<&'a str>,
    project: Option<&'a Path>,
    prompt: Option<&'a str>,
    second_prompt: Option<&'a str>,
    tmpdir: Option<&'a Path>,
    output: Option<&'a Path>,
}

/// Starts a native GUI for [anywork_home].
///
/// The launcher builds the debug bundle and launches the native artifact
/// directly (`--native-launch`), so the process it starts is the real native
/// host rather than a `cargo`/Flutter tool wrapper whose exit status is always
/// `0`. The launcher records the artifact's genuine wait status (and any child
/// tree it left behind) in the report at [`native_report_path`].
fn start_gui(
    workspace: &Path,
    anywork_home: &Path,
    log_path: &Path,
    working: &Path,
    label: &str,
) -> Result<OwnedProcess> {
    start_gui_with(
        workspace,
        anywork_home,
        log_path,
        working,
        label,
        NativeLaunch::default(),
    )
}

/// Starts a native GUI with extra environment, optional thin fault assembly,
/// and an isolated `TMPDIR`.
///
/// A [NativeLaunch] `fault` or `phase` selects `tool/native_fault_main.dart`.
/// Capture stays off for that assembly. [NativeLaunch::tmpdir] isolates
/// `Directory.systemTemp` so a temp-fallback diagnostic never touches a shared
/// machine temp directory.
fn start_gui_with(
    workspace: &Path,
    anywork_home: &Path,
    log_path: &Path,
    working: &Path,
    label: &str,
    launch: NativeLaunch<'_>,
) -> Result<OwnedProcess> {
    let report = native_report_path(working, label);
    let (log_filename, native_report_filename) = launch_identity_filenames(log_path, &report)?;
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    command
        .current_dir(workspace)
        .args([
            "xtask",
            "run-gui",
            "--native-launch",
            "--native-exit-report",
        ])
        .arg(&report)
        .env("ANYWORK_HOME", anywork_home)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    if launch.fault.is_some() || launch.phase.is_some() {
        command
            .arg("--native-launch-target")
            .arg("tool/native_fault_main.dart")
            .env("ANYWORK_NATIVE_SHUTDOWN_COORD", working);
        if let Some(fault) = launch.fault {
            command.env("ANYWORK_NATIVE_SHUTDOWN_FAULT", fault);
        }
        if let Some(phase) = launch.phase {
            command.env("ANYWORK_NATIVE_SHUTDOWN_PHASE", phase);
        }
        if let Some(project) = launch.project {
            command.env("ANYWORK_NATIVE_SHUTDOWN_PROJECT", project);
        }
        if let Some(prompt) = launch.prompt {
            command.env("ANYWORK_NATIVE_SHUTDOWN_PROMPT", prompt);
        }
        if let Some(prompt) = launch.second_prompt {
            command.env("ANYWORK_NATIVE_SHUTDOWN_SECOND_PROMPT", prompt);
        }
        if let Some(output) = launch.output {
            command.env("ANYWORK_NATIVE_SHUTDOWN_OUTPUT", output);
        }
    } else {
        command.arg("--capture");
    }
    for (key, value) in launch.env {
        command.env(*key, *value);
    }
    // A caller that pins `DISPLAY` wants the instance on a scenario-owned X
    // display. Force the X11 GDK backend and drop any `WAYLAND_DISPLAY`
    // inherited from the ambient session, or GTK could legitimately pick Wayland
    // and then own no window on the very display the delete event targets.
    if launch.env.iter().any(|(key, _)| *key == "DISPLAY") {
        command.env("GDK_BACKEND", "x11");
        command.env_remove("WAYLAND_DISPLAY");
    }
    if let Some(tmpdir) = launch.tmpdir {
        command.env("TMPDIR", tmpdir);
    }
    let gui = OwnedProcess::start(&mut command, false)?;
    write_launch_identity(
        working,
        label,
        gui.child.id(),
        proc_start_ticks(gui.child.id()),
        log_filename,
        native_report_filename,
    )?;
    Ok(gui)
}

fn launch_identity_filenames<'a>(
    log_path: &'a Path,
    report_path: &'a Path,
) -> Result<(&'a str, &'a str)> {
    let log_filename = log_path
        .file_name()
        .context("shutdown launcher log path has no filename")?
        .to_str()
        .context("shutdown launcher log filename is not valid UTF-8")?;
    let native_report_filename = report_path
        .file_name()
        .context("shutdown launcher native report path has no filename")?
        .to_str()
        .context("shutdown launcher native report filename is not valid UTF-8")?;
    Ok((log_filename, native_report_filename))
}

fn write_launch_identity(
    working: &Path,
    label: &str,
    launcher_pid: u32,
    launcher_start_ticks: Option<u64>,
    log_filename: &str,
    native_report_filename: &str,
) -> Result<()> {
    fs::write(
        launch_identity_path(working, launcher_pid),
        serde_json::to_vec_pretty(&serde_json::json!({
            "label": label,
            "launcherPid": launcher_pid,
            "launcherStartTicks": launcher_start_ticks,
            "logFile": log_filename,
            "nativeReportFile": native_report_filename,
        }))?,
    )?;
    Ok(())
}

fn launch_identity_path(working: &Path, launcher_pid: u32) -> PathBuf {
    working.join(format!("shutdown-launch-{launcher_pid}.json"))
}

/// Snapshot only the process tree owned by this launcher, before any close.
/// Start ticks are identity guards, not proof of natural exit.
fn snapshot_launch(
    working: &Path,
    gui: &OwnedProcess,
    known_native: Option<(u32, Option<u64>)>,
) -> Result<()> {
    let path = launch_identity_path(working, gui.child.id());
    let mut identity = read_phase_json(&path)?;
    if identity["nativePid"].is_u64() {
        return Ok(());
    }
    let (pid, ticks) = match known_native {
        Some(known) => known,
        None => {
            let log = identity["logFile"]
                .as_str()
                .context("shutdown launcher identity lost its log filename")?;
            let pid = parse_native_pid(&working.join(log))?;
            (pid, proc_start_ticks(pid))
        }
    };
    identity["nativePid"] = serde_json::json!(pid);
    identity["nativeStartTicks"] = serde_json::json!(ticks);
    identity["descendantsBeforeExit"] = serde_json::json!(
        owned_children(pid)
            .into_iter()
            .map(|pid| serde_json::json!({
                "pid": pid,
                "startTicks": proc_start_ticks(pid),
            }))
            .collect::<Vec<_>>()
    );
    fs::write(path, serde_json::to_vec_pretty(&identity)?)?;
    Ok(())
}

/// Retain existing private evidence, not homes/configs or a second control API.
fn retain_native_evidence(working: &Path, output: &Path) -> Result<()> {
    for entry in fs::read_dir(working)? {
        let entry = entry?;
        if !entry.file_type()?.is_file() {
            continue;
        }
        let name = entry.file_name();
        let Some(name) = name.to_str() else {
            continue;
        };
        if name.starts_with("shutdown-native-exit-")
            || name.starts_with("shutdown-launch-")
            || name.starts_with("shutdown-assembly-")
            || name.starts_with("shutdown-stage")
        {
            fs::copy(entry.path(), output.join(name))?;
        }
    }
    Ok(())
}

/// Creates an isolated git project the operator can open as the session project.
fn prepare_project(working: &Path, name: &str) -> Result<PathBuf> {
    let project = working.join(name);
    fs::create_dir_all(&project)?;
    ensure!(
        Command::new("git")
            .args(["init", "-q"])
            .arg(&project)
            .status()?
            .success(),
        "failed to initialize the isolated shutdown project"
    );
    Ok(project)
}

/// Waits, bounded, for the thin native assembly to publish a stage marker.
fn wait_stage(
    expected: &str,
    working: &Path,
    gui: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
    timeout: Duration,
) -> Result<()> {
    snapshot_launch(working, gui, None)?;
    let marker = working.join(format!("shutdown-stage-{expected}"));
    let deadline = Instant::now() + timeout;
    loop {
        if marker.is_file() {
            return Ok(());
        }
        ensure!(!gui.exited()?, "GUI exited before {expected}");
        ensure!(
            !fixture.exited()?,
            "provider fixture exited before {expected}"
        );
        ensure!(interrupt.try_recv().is_err(), "shutdown journey cancelled");
        ensure!(
            Instant::now() < deadline,
            "shutdown assembly timed out before {expected} (last stage: {})",
            fs::read_to_string(working.join("shutdown-stage")).unwrap_or_else(|_| "connect".into())
        );
        thread::sleep(Duration::from_millis(100));
    }
}

/// Waits until the strict fixture has consumed the concurrent turn's required
/// receipt continuation.
///
/// The assembly marks `concurrent-stop_served` as soon as both independent
/// subtrees record their pids, but the runtime answers the background `exec`
/// call with a task receipt and then re-prompts the model: that continuation is
/// a *required* script step. The fixture's live counters report
/// `remaining_optional` only when every step left at its cursor is optional, so
/// this waits for that flag -- proving the continuation was really accepted --
/// while the paced reply is still streaming.
fn wait_concurrent_continuation(
    status_file: &Path,
    gui: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
    timeout: Duration,
) -> Result<pl_provider_fixture::FixtureLiveStatus> {
    let deadline = Instant::now() + timeout;
    loop {
        if let Some(status) = read_live_status(status_file)
            .ok()
            .filter(|status| status.rejected == 0 && status.remaining_optional)
        {
            return Ok(status);
        }
        ensure!(
            !gui.exited()?,
            "GUI exited before the concurrent receipt continuation was accepted"
        );
        ensure!(
            !fixture.exited()?,
            "provider fixture exited before the concurrent receipt continuation was accepted"
        );
        ensure!(interrupt.try_recv().is_err(), "shutdown journey cancelled");
        ensure!(
            Instant::now() < deadline,
            "the concurrent receipt continuation was not accepted within {timeout:?} \
             (fixture live status: {})",
            read_live_status(status_file)
                .map(|status| format!("{status:?}"))
                .unwrap_or_else(|error| format!("unavailable: {error}"))
        );
        thread::sleep(Duration::from_millis(50));
    }
}

/// A native host's real termination.
///
/// The exit code comes from the launcher's structured report (its direct
/// `waitpid` of the artifact), never from the `cargo`/Flutter wrapper; the
/// disappeared process is independently confirmed by this coordinator's own
/// `/proc` poll with a start-time reuse guard. `elapsed` is measured from the
/// real native arm, not from an earlier save window nor a later Driver wait.
struct NativeExit {
    pid: u32,
    code: Option<i32>,
    signal: Option<i32>,
    elapsed: Duration,
    /// Subtree present when the native host was reaped, before the product's own
    /// supervisor had its natural reclamation window.
    descendants_at_root_exit: Vec<u32>,
    /// Subtree the harness had to force-kill after that window (empty means the
    /// product supervised its own subtree).
    reclaimed_descendants: Vec<u32>,
}

impl NativeExit {
    fn summary(&self) -> String {
        let how = match (self.code, self.signal) {
            (Some(code), _) => format!("exit code {code}"),
            (None, Some(signal)) => format!("signal {signal}"),
            _ => "unknown termination".to_owned(),
        };
        format!(
            "pid {} {how} after {:?} (reclaimed descendants: {})",
            self.pid,
            self.elapsed,
            self.reclaimed_descendants.len()
        )
    }
}

/// Reads the native artifact pid the launcher printed before any close.
///
/// `run_resident_reporting` writes `resident command started: pid=` for the
/// real host, so this coordinator can OS-wait that pid with a start-time reuse
/// guard instead of the `cargo` wrapper pid.
fn parse_native_pid(log: &Path) -> Result<u32> {
    let text =
        fs::read_to_string(log).with_context(|| format!("missing GUI log {}", log.display()))?;
    for line in text.lines().rev() {
        let Some(rest) = line.split("resident command started: pid=").nth(1) else {
            continue;
        };
        let pid = rest
            .split([',', ' '])
            .next()
            .unwrap_or("")
            .parse::<u32>()
            .with_context(|| format!("native pid is not an integer in {}", log.display()))?;
        ensure!(pid > 0, "native pid in {} is zero", log.display());
        return Ok(pid);
    }
    bail!("GUI log {} has no resident command pid", log.display())
}

/// Snapshots the live native host and its descendant PIDs from the launcher log.
///
/// This never waits for an exit request, so subtree phases can resolve the
/// real native process (and prove a business subtree is alive) before any
/// close is issued.
fn snapshot_native(log: &Path) -> Result<(u32, Option<u64>, Vec<u32>)> {
    let pid = parse_native_pid(log)?;
    Ok((pid, proc_start_ticks(pid), owned_children(pid)))
}

/// Requests a coordinated native exit and returns the live identity plus arm time.
fn arm_native(
    app_dir: &Path,
    vm_url: &str,
    log: &Path,
    working: &Path,
    label: &str,
    interrupt: &mpsc::Receiver<()>,
) -> Result<(u32, Option<u64>, Vec<u32>, Instant)> {
    let (pid, ticks, children) = snapshot_native(log)?;
    request_app_exit(
        app_dir,
        vm_url,
        &working.join(format!("shutdown-{label}-request-exit.log")),
        interrupt,
    )?;
    Ok((pid, ticks, children, Instant::now()))
}

/// Waits for the assembly's `{marker}` stage, snapshots the live native host,
/// and optionally issues a second `requestExit` from the host.
///
/// `already_requested` is true when the thin assembly itself called
/// `StudioExitCoordinator.requestExit` or `beginExit` (hang / subtree hang).
/// The host then only snapshots the pid so elapsed is measured from the real
/// arm, never from a later Driver wait.
#[allow(clippy::too_many_arguments)]
fn arm_after_stage(
    app_dir: &Path,
    vm_url: &str,
    log: &Path,
    working: &Path,
    label: &str,
    marker: &str,
    gui: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
    already_requested: bool,
) -> Result<(u32, Option<u64>, Vec<u32>, Instant)> {
    wait_stage(
        marker,
        working,
        gui,
        fixture,
        interrupt,
        Duration::from_secs(180),
    )?;
    let (pid, ticks, children) = snapshot_native(log)?;
    if !already_requested {
        request_app_exit(
            app_dir,
            vm_url,
            &working.join(format!("shutdown-{label}-request-exit.log")),
            interrupt,
        )?;
    }
    Ok((pid, ticks, children, Instant::now()))
}

/// The Linux process start time (jiffies since boot) for [pid], if alive.
///
/// Field 22 of `/proc/<pid>/stat`; the executable name may contain spaces and
/// parentheses, so parsing resumes after the last `)`.
#[cfg(target_os = "linux")]
fn proc_start_ticks(pid: u32) -> Option<u64> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let after_name = &stat[stat.rfind(')')? + 1..];
    let fields: Vec<&str> = after_name.split_whitespace().collect();
    // After the `comm` field the collected slice starts at field 3 (state), so
    // starttime (field 22) is at index 19.
    fields.get(19).and_then(|value| value.parse::<u64>().ok())
}

#[cfg(not(target_os = "linux"))]
fn proc_start_ticks(_pid: u32) -> Option<u64> {
    None
}

/// Whether [pid] is still the same live process that owned [start_ticks].
#[cfg(target_os = "linux")]
fn proc_alive(pid: u32, start_ticks: Option<u64>) -> bool {
    if !Path::new(&format!("/proc/{pid}")).exists() {
        return false;
    }
    match (start_ticks, proc_start_ticks(pid)) {
        (Some(known), Some(current)) => current == known,
        // No start-time baseline available: presence is the only signal.
        (None, _) => true,
        // The pid exists again with a different start time: the original exited.
        (Some(_), None) => false,
    }
}

#[cfg(not(target_os = "linux"))]
fn proc_alive(_pid: u32, _start_ticks: Option<u64>) -> bool {
    false
}

/// A zombie has exited, although its parent still owns the wait/reap duty.
/// Only the root's exit clock uses this distinction; subtree reclamation keeps
/// using proc_alive so an unreaped descendant cannot count as cleaned up.
fn proc_running(pid: u32, start_ticks: Option<u64>) -> bool {
    if !proc_alive(pid, start_ticks) {
        return false;
    }
    #[cfg(target_os = "linux")]
    {
        let Ok(stat) = fs::read_to_string(format!("/proc/{pid}/stat")) else {
            return false;
        };
        let state = stat
            .rfind(')')
            .and_then(|end| stat[end + 1..].split_whitespace().next());
        !matches!(state, Some("Z" | "X"))
    }
    #[cfg(not(target_os = "linux"))]
    false
}

/// Reads the launcher's structured native exit report within [timeout].
fn read_native_report(path: &Path, timeout: Duration) -> Result<serde_json::Value> {
    let deadline = Instant::now() + timeout;
    loop {
        if let Ok(bytes) = fs::read(path) {
            return serde_json::from_slice(&bytes).with_context(|| {
                format!("native exit report is not valid JSON: {}", path.display())
            });
        }
        ensure!(
            Instant::now() < deadline,
            "the launcher wrote no native exit report at {}",
            path.display()
        );
        thread::sleep(Duration::from_millis(50));
    }
}

/// Waits on the real native process and returns its authoritative exit status.
///
/// `arm` is the instant the native host armed its single exit budget, so the
/// reported `elapsed` spans the real shutdown only. [timeout] guards a
/// permanently wedged process and is never a success signal. The launcher's
/// wrapper process is also reaped so no zombie is left, but its exit code is
/// deliberately not used to judge the native host.
#[allow(clippy::too_many_arguments)]
fn wait_native_exit(
    label: &str,
    working: &Path,
    _output: &Path,
    pid: u32,
    start_ticks: Option<u64>,
    gui: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
    timeout: Duration,
    arm: Instant,
) -> Result<NativeExit> {
    snapshot_launch(working, gui, Some((pid, start_ticks)))?;
    let deadline = Instant::now() + timeout;
    loop {
        if !proc_running(pid, start_ticks) {
            break;
        }
        ensure!(interrupt.try_recv().is_err(), "shutdown {label} cancelled");
        ensure!(
            Instant::now() < deadline,
            "shutdown {label} native process {pid} never exited within {timeout:?}"
        );
        thread::sleep(Duration::from_millis(50));
    }
    let elapsed = arm.elapsed();
    // Reap the wrapper so the tree does not leak a zombie; its own status is
    // secondary and never substitutes for the native report.
    let wrapper_deadline = Instant::now() + Duration::from_secs(20);
    loop {
        if gui.child.try_wait()?.is_some() {
            gui.stopped = true;
            break;
        }
        if Instant::now() >= wrapper_deadline {
            break;
        }
        thread::sleep(Duration::from_millis(50));
    }
    let report = read_native_report(&native_report_path(working, label), Duration::from_secs(20))?;
    ensure!(
        report["schema"] == "anywork-native-exit/1"
            && report["cancelled"].as_bool() == Some(false)
            && report["descendantsAtRootExit"].is_array()
            && report["reclaimedDescendants"].is_array(),
        "native exit report is missing lifecycle evidence or was cancelled: {report}"
    );
    ensure!(
        report["pid"].as_u64() == Some(u64::from(pid)),
        "native exit report pid does not match the Driver-reported native pid {pid}: {report}"
    );
    let code = report["exitCode"].as_i64().map(|value| value as i32);
    let signal = report["signal"].as_i64().map(|value| value as i32);
    let descendants_at_root_exit = pid_list(&report["descendantsAtRootExit"]);
    let reclaimed_descendants = pid_list(&report["reclaimedDescendants"]);
    Ok(NativeExit {
        pid,
        code,
        signal,
        elapsed,
        descendants_at_root_exit,
        reclaimed_descendants,
    })
}

/// Parses a JSON array of positive integer pids, ignoring malformed entries.
fn pid_list(value: &serde_json::Value) -> Vec<u32> {
    let mut pids = Vec::new();
    if let Some(values) = value.as_array() {
        for value in values {
            if let Some(pid) = value.as_u64()
                && pid > 0
            {
                pids.push(pid as u32);
            }
        }
    }
    pids
}

/// Waits on the real OS process for [gui]; [timeout] only guards a permanent
/// wedge and is never a success signal.
fn wait_gui_exit(
    label: &str,
    gui: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
    timeout: Duration,
) -> Result<ExitStatus> {
    let deadline = Instant::now() + timeout;
    loop {
        if let Some(status) = gui.child.try_wait()? {
            gui.stopped = true;
            return Ok(status);
        }
        ensure!(interrupt.try_recv().is_err(), "shutdown {label} cancelled");
        ensure!(
            Instant::now() < deadline,
            "shutdown {label} GUI never exited within {timeout:?}"
        );
        thread::sleep(Duration::from_millis(100));
    }
}

/// Waits for the duplicate's own native exit. It must not publish a VM or need
/// a close event. The owner acknowledgement and subsequent turn prove redirection.
fn capture_second_instance(
    second_log: &Path,
    owner_log: &Path,
    output: &Path,
    working: &Path,
    mut second: OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
) -> Result<serde_json::Value> {
    // The native report measures launch time independently of xtask's cached build.
    wait_gui_exit(
        "busy-second",
        &mut second,
        interrupt,
        Duration::from_secs(300),
    )?;
    let native = read_native_report(
        &native_report_path(working, "busy-second"),
        Duration::from_secs(5),
    )?;
    let duplicate = fs::read_to_string(second_log)?;
    let owner = fs::read_to_string(owner_log)?;
    write_sanitized_log(second_log, &output.join("shutdown-busy-second-gui.log"))?;
    Ok(serde_json::json!({
        "redirected": duplicate.contains("event=redirected"),
        "ownerActivated": owner.contains("event=window_activated"),
        "secondEngineCreated": find_vm_url(second_log).is_some(),
        "secondNativeReport": native,
    }))
}

/// Reads the fixture live strict-script counters, when the watcher has written.
fn read_live_status(path: &Path) -> Result<pl_provider_fixture::FixtureLiveStatus> {
    serde_json::from_slice(
        &fs::read(path)
            .with_context(|| format!("fixture live status missing: {}", path.display()))?,
    )
    .context("fixture live status is not a valid counter snapshot")
}

/// Copies the canonical `ANYWORK_HOME/studio/logs` diagnostics into evidence.
///
/// The acceptance must judge the PID/stage/elapsed/error-code/correlation/
/// persistence facts from the product's canonical diagnostics directory, not
/// only from the captured stdout log, so the files are copied beside the rest
/// of the run's evidence. Returns how many files were copied.
fn copy_home_diagnostics(home: &Path, output: &Path, label: &str) -> Result<usize> {
    let source = home.join("studio").join("logs");
    let destination = output.join("diagnostics").join(label);
    let mut copied = 0usize;
    if !source.is_dir() {
        return Ok(copied);
    }
    fs::create_dir_all(&destination)?;
    for entry in fs::read_dir(&source)? {
        let entry = entry?;
        if entry.file_type()?.is_file() {
            fs::copy(entry.path(), destination.join(entry.file_name()))?;
            copied += 1;
        }
    }
    Ok(copied)
}

/// Reads a small JSON evidence file written by a scenario peer.
fn read_phase_json(path: &Path) -> Result<serde_json::Value> {
    serde_json::from_slice(
        &fs::read(path).with_context(|| format!("missing phase evidence {}", path.display()))?,
    )
    .with_context(|| format!("invalid phase evidence {}", path.display()))
}

/// Reads the native host's canonical exit diagnostics for [home].
///
/// The native host writes merged `anywork-exit` lines to
/// `ANYWORK_HOME/studio/logs/anywork-exit-diagnostics.log`. The last line is
/// the authoritative terminal snapshot: a `finish` event is a coordinated
/// `finishExit`, while a `final` snapshot with `exitDeadlineImminent` is the
/// 30-second watchdog. A missing or empty log is a hard error because the
/// concurrent phase must confirm the blocked save never completed.
fn read_native_exit_diagnostics(home: &Path) -> Result<serde_json::Value> {
    let path = home
        .join("studio")
        .join("logs")
        .join("anywork-exit-diagnostics.log");
    let text = fs::read_to_string(&path)
        .with_context(|| format!("missing native exit diagnostics {}", path.display()))?;
    let mut last: BTreeMap<String, String> = BTreeMap::new();
    let mut coordinated_finish = false;
    let mut lines = 0usize;
    for line in text.lines() {
        let Some(rest) = line.strip_prefix("anywork-exit ") else {
            continue;
        };
        let mut fields: BTreeMap<String, String> = BTreeMap::new();
        for token in rest.split_whitespace() {
            if let Some((key, value)) = token.split_once('=') {
                fields.insert(key.to_owned(), value.to_owned());
            }
        }
        if fields.is_empty() {
            continue;
        }
        if fields.get("event").is_some_and(|event| event == "finish") {
            coordinated_finish = true;
        }
        last = fields;
        lines += 1;
    }
    ensure!(
        lines > 0,
        "native exit diagnostics had no anywork-exit line: {}",
        path.display()
    );
    let code = last.get("code").cloned().unwrap_or_default();
    let pending = last.get("pending").cloned().unwrap_or_default();
    Ok(serde_json::json!({
        "log": path.display().to_string(),
        "lines": lines,
        "event": last.get("event").cloned().unwrap_or_default(),
        "stage": last.get("stage").cloned().unwrap_or_default(),
        "code": code,
        "reason": last.get("reason").cloned().unwrap_or_default(),
        "correlation": last.get("correlation").cloned().unwrap_or_default(),
        "pending": pending,
        "pendingUnknown": pending == "unknown",
        "elapsedMillis": last.get("elapsed_ms").and_then(|value| value.parse::<u64>().ok()),
        "coordinatedFinish": coordinated_finish,
        "deadlineImminent": last.get("code").is_some_and(|value| value == "exitDeadlineImminent"),
    }))
}

/// Machine-validates a Dart error log directory (or a single fallback log dir).
///
/// The Dart logger writes entries with `stage=`, `correlation=` and a stack, but
/// no pid field; the caller records the OS pid alongside. Returns the actual
/// per-field findings so the acceptance never claims a copy it did not check.
fn validate_dart_error_dir(dir: &Path, expect_stage: &str) -> Result<serde_json::Value> {
    let mut files = Vec::new();
    let mut contains_stage = false;
    let mut contains_correlation = false;
    let mut contains_stack = false;
    let mut bytes = 0usize;
    if dir.is_dir() {
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            if !entry.file_type()?.is_file() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            if !name.contains("dart-error") {
                continue;
            }
            let text = fs::read_to_string(entry.path()).unwrap_or_default();
            bytes += text.len();
            contains_stage |= text.contains(&format!("stage={expect_stage}"));
            contains_correlation |= text.contains("correlation=corr-");
            contains_stack |=
                text.contains("#0") || text.contains(".dart:") || text.contains(" at ");
            files.push(name);
        }
    }
    Ok(serde_json::json!({
        "directory": dir.display().to_string(),
        "files": files,
        "bytes": bytes,
        "containsStage": contains_stage,
        "containsCorrelation": contains_correlation,
        "containsStack": contains_stack,
    }))
}

/// The VM-service URL the Flutter engine published on [log], if any.
fn find_vm_url(log: &Path) -> Option<String> {
    let text = fs::read_to_string(log).ok()?;
    text.lines()
        .filter_map(|line| {
            line.split("available at: http://127.0.0.1:")
                .nth(1)
                .or_else(|| line.split("listening on http://127.0.0.1:").nth(1))
                .map(|tail| {
                    format!(
                        "http://127.0.0.1:{}",
                        tail.split_whitespace().next().unwrap_or("")
                    )
                })
        })
        .next_back()
}

/// Enumerates the real descendant PIDs of [root] on Linux by walking only
/// `/proc/<pid>/task/*/children`; never a global scan.
#[cfg(target_os = "linux")]
fn owned_children(root: u32) -> Vec<u32> {
    use std::collections::HashSet;

    let mut found = Vec::new();
    let mut stack = vec![root];
    let mut seen: HashSet<u32> = HashSet::new();
    seen.insert(root);
    while let Some(pid) = stack.pop() {
        let task_dir = format!("/proc/{pid}/task");
        let Ok(entries) = fs::read_dir(&task_dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let children = entry.path().join("children");
            let Ok(text) = fs::read_to_string(&children) else {
                continue;
            };
            for token in text.split_whitespace() {
                if let Ok(child) = token.parse::<u32>()
                    && seen.insert(child)
                {
                    found.push(child);
                    stack.push(child);
                }
            }
        }
    }
    found.sort_unstable();
    found
}

#[cfg(not(target_os = "linux"))]
fn owned_children(_root: u32) -> Vec<u32> {
    Vec::new()
}

/// Polls the real business PIDs of a supervised subtree to prove they exited.
fn monitor_business_pids(
    pids: Vec<(u32, Option<u64>)>,
    timeout: Duration,
) -> thread::JoinHandle<serde_json::Value> {
    thread::spawn(move || {
        let started = Instant::now();
        let deadline = started + timeout;
        let mut remaining = pids;
        let mut observed = Vec::new();
        loop {
            remaining.retain(|(pid, ticks)| {
                if proc_alive(*pid, *ticks) {
                    true
                } else {
                    observed.push(serde_json::json!({
                        "pid": pid,
                        "exitedAtMillis": started.elapsed().as_millis(),
                    }));
                    false
                }
            });
            if remaining.is_empty() || Instant::now() >= deadline {
                break;
            }
            thread::sleep(Duration::from_millis(50));
        }
        serde_json::json!({
            "observed": observed,
            "stillAlive": remaining.iter().map(|(pid, _)| *pid).collect::<Vec<u32>>(),
            "elapsedMillis": started.elapsed().as_millis(),
        })
    })
}

/// Monitors the `concurrent-stop` business subtrees and the native host on one
/// shared clock.
fn monitor_concurrent_stop(
    native: (u32, Option<u64>),
    business: Vec<(u32, Option<u64>)>,
    timeout: Duration,
) -> thread::JoinHandle<serde_json::Value> {
    thread::spawn(move || {
        let started = Instant::now();
        let deadline = started + timeout;
        let (native_pid, native_ticks) = native;
        let mut native_exited_at: Option<u128> = None;
        let mut remaining = business;
        let mut observed = Vec::new();
        loop {
            if native_exited_at.is_none() && !proc_alive(native_pid, native_ticks) {
                native_exited_at = Some(started.elapsed().as_millis());
            }
            remaining.retain(|(pid, ticks)| {
                if proc_alive(*pid, *ticks) {
                    true
                } else {
                    observed.push(serde_json::json!({
                        "pid": pid,
                        "exitedAtMillis": started.elapsed().as_millis(),
                    }));
                    false
                }
            });
            if (remaining.is_empty() && native_exited_at.is_some()) || Instant::now() >= deadline {
                break;
            }
            thread::sleep(Duration::from_millis(50));
        }
        serde_json::json!({
            "observed": observed,
            "stillAlive": remaining.iter().map(|(pid, _)| *pid).collect::<Vec<u32>>(),
            "nativeExitedAtMillis": native_exited_at,
            "elapsedMillis": started.elapsed().as_millis(),
        })
    })
}

/// Safety-net kill for leftover business pids. A surviving pid is already a
/// product leak recorded by the independent monitor; this only keeps the run
/// from leaving an orphaned `sleep`.
fn force_kill_alive(pids: impl IntoIterator<Item = (u32, Option<u64>)>) -> Vec<u32> {
    let mut forced_kill = Vec::new();
    for (pid, ticks) in pids {
        if proc_alive(pid, ticks) {
            forced_kill.push(pid);
            let _ = Command::new("kill")
                .arg("-KILL")
                .arg("--")
                .arg(pid.to_string())
                .status();
        }
    }
    forced_kill
}

/// Freezes the owned provider-fixture process group (SIGSTOP) so the service is
/// genuinely unresponsive.
#[cfg(unix)]
fn freeze_fixture(fixture: &OwnedProcess) -> Result<()> {
    signal_fixture(fixture, "STOP")
}

/// Resumes the frozen provider fixture (SIGCONT).
#[cfg(unix)]
fn resume_fixture(fixture: &OwnedProcess) -> Result<()> {
    signal_fixture(fixture, "CONT")
}

#[cfg(not(unix))]
fn freeze_fixture(_fixture: &OwnedProcess) -> Result<()> {
    bail!("service-unresponsive phase requires a POSIX signal host")
}

#[cfg(not(unix))]
fn resume_fixture(_fixture: &OwnedProcess) -> Result<()> {
    Ok(())
}

#[cfg(unix)]
fn signal_fixture(fixture: &OwnedProcess, signal: &str) -> Result<()> {
    signal_group(fixture.child.id(), signal)
}

/// Sends [signal] to the whole process group [pid] owns (never a bare PID), so
/// descendants are covered without a global scan.
#[cfg(unix)]
fn signal_group(pid: u32, signal: &str) -> Result<()> {
    let status = Command::new("kill")
        .arg(format!("-{signal}"))
        .arg("--")
        .arg(format!("-{pid}"))
        .status()?;
    ensure!(
        status.success(),
        "failed to send {signal} to process group {pid}: {status}"
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        launch_identity_filenames, launch_identity_path, read_phase_json, write_launch_identity,
    };
    use anyhow::Result;
    use std::fs;

    #[cfg(target_os = "linux")]
    #[test]
    fn root_exit_is_observed_before_reaping_without_hiding_subtree_obligations() -> Result<()> {
        use std::process::Command;
        use std::time::{Duration, Instant};

        let mut child = Command::new("/bin/sh").args(["-c", "exit 0"]).spawn()?;
        let pid = child.id();
        let ticks = super::proc_start_ticks(pid);
        let deadline = Instant::now() + Duration::from_secs(5);
        while super::proc_running(pid, ticks) && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
        }
        let running = super::proc_running(pid, ticks);
        let unreaped = super::proc_alive(pid, ticks);
        // Always reap before assertions, including a failed observation.
        let status = child.wait()?;
        assert!(status.success());
        assert!(
            !running,
            "an exited root must not wait for its parent's reap"
        );
        assert!(
            unreaped,
            "subtree checks must still see the unreaped process"
        );
        assert!(!super::proc_alive(pid, ticks));
        Ok(())
    }

    #[test]
    fn launch_identity_filenames_round_trip_as_utf8_json_strings() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let log_path = directory.path().join("shutdown normal 测试.log");
        let report_path = directory.path().join("shutdown native 已退出.json");
        fs::write(&log_path, b"synthetic launcher log\n")?;
        fs::write(&report_path, b"{}\n")?;
        let (log_filename, native_report_filename) =
            launch_identity_filenames(&log_path, &report_path)?;
        write_launch_identity(
            directory.path(),
            "normal",
            42,
            Some(123),
            log_filename,
            native_report_filename,
        )?;

        let identity = read_phase_json(&launch_identity_path(directory.path(), 42))?;
        assert!(identity["logFile"].is_string());
        assert!(identity["nativeReportFile"].is_string());
        assert_eq!(
            identity["logFile"].as_str(),
            log_path.file_name().and_then(|name| name.to_str()),
        );
        assert_eq!(
            identity["nativeReportFile"].as_str(),
            report_path.file_name().and_then(|name| name.to_str()),
        );
        assert_eq!(
            identity["logFile"].as_str(),
            Some("shutdown normal 测试.log")
        );
        assert_eq!(
            identity["nativeReportFile"].as_str(),
            Some("shutdown native 已退出.json"),
        );
        Ok(())
    }

    #[cfg(unix)]
    #[test]
    fn launch_identity_filenames_reject_non_utf8_before_launch() {
        use std::ffi::OsStr;
        use std::os::unix::ffi::OsStrExt;
        use std::path::Path;

        let invalid_path = Path::new(OsStr::from_bytes(b"shutdown-\xff.log"));
        let valid_path = Path::new("shutdown valid.json");
        let log_error = launch_identity_filenames(invalid_path, valid_path).unwrap_err();
        assert_eq!(
            log_error.to_string(),
            "shutdown launcher log filename is not valid UTF-8",
        );
        let report_error = launch_identity_filenames(valid_path, invalid_path).unwrap_err();
        assert_eq!(
            report_error.to_string(),
            "shutdown launcher native report filename is not valid UTF-8",
        );
    }
}
