//! Exercise the real supervisor in a separate test process: its exclusive
//! child ownership and signal handler cannot be shared with the test runner.

#![cfg(target_os = "linux")]

use super::{OwnedProcess, finish_manual_gui_session};
use anyhow::{Context, Result, ensure};
use pl_dev_support::process;
use std::fs;
use std::io::Write;
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

const READY: &str = "ANYWORK_ACCEPTANCE_CLEANUP_TEST_READY";
const REPORT: &str = "ANYWORK_ACCEPTANCE_CLEANUP_TEST_REPORT";
const PREPARATION: &str = "ANYWORK_ACCEPTANCE_CLEANUP_TEST_PREPARATION";

/// Invoked only by the test below, with the actual production tree supervisor.
#[test]
fn native_launcher_fixture() -> Result<()> {
    let Some(ready) = std::env::var_os(READY) else {
        return Ok(());
    };
    let report = std::env::var_os(REPORT).context("fixture report path")?;
    if let Ok(mode) = std::env::var(PREPARATION) {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()?;
        return runtime.block_on(async {
            let mut term =
                tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
            let script = if mode == "fail" {
                "printf '%s' \"$$\" > \"$ANYWORK_ACCEPTANCE_CLEANUP_TEST_READY\"; exit 7"
            } else {
                "printf '%s' \"$$\" > \"$ANYWORK_ACCEPTANCE_CLEANUP_TEST_READY\"; exec sleep 60"
            };
            let mut build = tokio::process::Command::new("sh")
                .args(["-c", script])
                .env(READY, &ready)
                .kill_on_drop(true)
                .spawn()?;
            if mode == "fail" {
                let status = build.wait().await?;
                ensure!(status.success(), "preparation worker failed: {status}");
            } else {
                // This fixture publishes its late boundary on cancellation.
                // The group signal also ends the worker: racing those two
                // observations with select would randomly skip publication.
                term.recv().await.context("termination stream ended")?;
                build.wait().await?;
                if mode == "boundary-on-cancel" {
                    print!("{}", super::NATIVE_LAUNCH_BOUNDARY);
                    std::io::stdout().flush()?;
                }
            }
            Ok(())
        });
    }
    print!("{}", super::NATIVE_LAUNCH_BOUNDARY);
    std::io::stdout().flush()?;
    let mut app = Command::new("sh");
    app.args(["-c", "trap '' TERM; printf '%s' \"$$\" > \"$ANYWORK_ACCEPTANCE_CLEANUP_TEST_READY\"; exec sleep 60"]);
    app.env(READY, ready);
    let exit = process::run_resident_reporting(&mut app, "acceptance independent app group")?;
    // Evidence flushing may outlive OwnedProcess::Drop's old 200 ms window.
    // The owner must remain alive until reporting is complete, not be killed
    // as soon as its app has gone.
    thread::sleep(Duration::from_millis(400));
    fs::write(
        report,
        serde_json::to_vec(&serde_json::json!({
            "schema": "anywork-native-exit/1",
            "pid": exit.pid,
            "exitCode": exit.status.code(),
            "signal": exit.status.signal(),
            "cancelled": exit.cancelled,
            "descendantsAtRootExit": exit.descendants_at_root_exit,
            "reclaimedDescendants": exit.reclaimed_descendants,
        }))?,
    )?;
    Ok(())
}

fn launcher_command(ready: &Path, report: &Path, outer_wrapper: bool) -> Result<Command> {
    let executable = std::env::current_exe()?;
    let mut command = if outer_wrapper {
        let mut command = Command::new("sh");
        // Like cargo run, the outer process is not the native supervisor.
        // Its TERM exit must not end the acceptance owner's cleanup wait.
        command
            .args([
                "-c",
                "trap 'exit 143' TERM; \"$@\" & wait",
                "outer-launcher",
            ])
            .arg(&executable);
        command
    } else {
        Command::new(&executable)
    };
    command
        .args([
            "--exact",
            "manual_gui::manual_cleanup_tests::native_launcher_fixture",
            "--nocapture",
        ])
        .env(READY, ready)
        .env(REPORT, report)
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    Ok(command)
}

fn start_launcher(ready: &Path, report: &Path, outer_wrapper: bool) -> Result<OwnedProcess> {
    OwnedProcess::start(&mut launcher_command(ready, report, outer_wrapper)?, false)
}

#[test]
fn preparation_cleanup_uses_the_final_phase_and_joins_build_children() -> Result<()> {
    for mode in ["fail", "hold", "boundary-on-cancel", "native"] {
        let directory = tempfile::tempdir()?;
        let ready = directory.path().join("worker-pid");
        let report = directory.path().join("native-exit.json");
        let log = directory.path().join("gui.log");
        let mut command = launcher_command(&ready, &report, false)?;
        let log_file = fs::File::create(&log)?;
        command.stdout(log_file.try_clone()?).stderr(log_file);
        if mode != "native" {
            command.env(PREPARATION, mode);
        }
        let mut launcher = OwnedProcess::start(&mut command, false)?;
        let (tx, rx) = std::sync::mpsc::channel();
        let worker = if mode == "fail" {
            // This coordinator fixture has no production account/GUI services.
            // Preserve the original failed preparation process status.
            let deadline = Instant::now() + Duration::from_secs(5);
            while launcher.exit_status()?.is_none() {
                ensure!(
                    Instant::now() < deadline,
                    "preparation failure did not exit"
                );
                thread::sleep(Duration::from_millis(20));
            }
            fs::read_to_string(&ready)?.parse::<u32>()?
        } else {
            wait_app(&ready, &mut launcher)?
        };
        let mut account =
            OwnedProcess::start(Command::new("sh").args(["-c", "exec sleep 60"]), true)?;
        tx.send(())?;
        let session = super::wait_for_vm_in_phase(
            &log,
            &mut launcher,
            &mut account,
            &rx,
            super::VmStartupPhase::NativePreparation,
            Duration::from_millis(20),
        );
        assert!(session.is_err());
        let result = finish_manual_gui_session(
            session.map(|_| ()),
            &mut launcher,
            Some(&report),
            if mode == "boundary-on-cancel" {
                Duration::from_millis(250)
            } else {
                Duration::from_secs(10)
            },
            Some(&log),
        );
        let error = format!("{:#}", result.unwrap_err());
        let started = super::native_launch_started(&fs::read_to_string(&log)?);
        println!(
            "phase_case={mode} crossed_boundary={started} stopped={} report_present={}",
            launcher.stopped,
            report.is_file()
        );
        assert!(
            !Path::new(&format!("/proc/{worker}")).exists(),
            "worker was not reaped"
        );
        if mode == "boundary-on-cancel" {
            assert!(started);
            assert!(
                !launcher.stopped,
                "missing post-boundary report must keep fallback armed"
            );
            assert!(error.contains("cleanup timed out"), "{error}");
            assert!(error.contains("manual GUI cancelled"), "{error}");
        } else {
            assert!(launcher.stopped);
            assert!(!error.contains("cleanup also failed"), "{error}");
            assert_eq!(started, mode == "native");
            assert_eq!(report.is_file(), mode == "native");
            assert!(
                error.contains(if mode == "fail" {
                    "GUI exited"
                } else {
                    "manual GUI cancelled"
                }),
                "{error}"
            );
        }
    }
    Ok(())
}

fn wait_app(ready: &Path, launcher: &mut OwnedProcess) -> Result<u32> {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if let Ok(pid) = fs::read_to_string(ready)
            && let Ok(pid) = pid.parse::<u32>()
        {
            return Ok(pid);
        }
        ensure!(
            !launcher.exited()?,
            "fixture launcher exited before app started"
        );
        ensure!(Instant::now() < deadline, "fixture app did not start");
        thread::sleep(Duration::from_millis(20));
    }
}

fn exit_outer_wrapper(launcher: &mut OwnedProcess) -> Result<()> {
    ensure!(
        Command::new("kill")
            .args(["-TERM", &launcher.child.id().to_string()])
            .status()?
            .success(),
        "could not exit only the outer wrapper"
    );
    launcher.child.wait()?;
    ensure!(
        launcher.exit_status()?.is_some(),
        "outer wrapper was not reaped"
    );
    Ok(())
}

/// Safety cleanup runs after recording the tested outcome. Even a regression
/// must not leave this real independent app group running.
fn finish_fixture(launcher: &mut OwnedProcess, report: &Path) -> Result<()> {
    if !report.is_file() {
        launcher.request_stop();
    }
    launcher.wait_exit(Duration::from_secs(10))?;
    let deadline = Instant::now() + Duration::from_secs(10);
    while !report.is_file() {
        ensure!(Instant::now() < deadline, "fixture cleanup report missing");
        thread::sleep(Duration::from_millis(20));
    }
    Ok(())
}

#[test]
fn preexited_wrapper_still_stops_and_joins_the_live_native_owner() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let ready = directory.path().join("app-pid");
    let report = directory.path().join("native-exit.json");
    let mut launcher = start_launcher(&ready, &report, true)?;
    let app_pid = wait_app(&ready, &mut launcher)?;
    exit_outer_wrapper(&mut launcher)?;
    let app_path = format!("/proc/{app_pid}");
    let app_alive_before = Path::new(&app_path).exists();
    let report_before = report.is_file();
    let result = finish_manual_gui_session(
        Err(anyhow::anyhow!("GUI exited before manual review completed")),
        &mut launcher,
        Some(&report),
        Duration::from_secs(10),
        None,
    );
    let error = format!("{:#}", result.unwrap_err());
    let stopped_after = launcher.stopped;
    let app_alive_after = Path::new(&app_path).exists();
    let report_after = report.is_file();
    println!(
        "wrapper_preexited=true app_alive_before={app_alive_before} report_before={report_before} stopped_after={stopped_after} app_alive_after={app_alive_after} report_after={report_after}"
    );
    finish_fixture(&mut launcher, &report)?;
    assert!(app_alive_before && !report_before);
    assert!(
        error.contains("GUI exited before manual review completed"),
        "{error}"
    );
    assert!(!error.contains("cleanup also failed"), "{error}");
    assert!(stopped_after && report_after && !app_alive_after);
    let evidence: serde_json::Value = serde_json::from_slice(&fs::read(&report)?)?;
    assert_eq!(evidence["cancelled"], true);
    assert!(!Path::new(&app_path).exists());
    Ok(())
}

#[test]
fn failed_sessions_wait_for_independent_app_group_and_launcher_report() -> Result<()> {
    for (reason, outer_wrapper) in [
        ("manual GUI input closed before done", false),
        ("manual GUI cancelled", false),
        ("account fixture exited during manual review", false),
        ("manual GUI input closed before done", true),
    ] {
        let directory = tempfile::tempdir()?;
        let ready = directory.path().join("app-pid");
        let report = directory.path().join("native-exit.json");
        let mut launcher = start_launcher(&ready, &report, outer_wrapper)?;
        let app_pid = match wait_app(&ready, &mut launcher) {
            Ok(pid) => pid,
            Err(error) => {
                return finish_manual_gui_session(
                    Err(error),
                    &mut launcher,
                    Some(&report),
                    Duration::from_secs(10),
                    None,
                );
            }
        };
        // ProcessTree::start makes the native app a distinct process-group
        // leader, outside OwnedProcess's launcher group.
        let group_observation = (|| -> Result<u32> {
            let stat = fs::read_to_string(format!("/proc/{app_pid}/stat"))?;
            let (_, fields) = stat.rsplit_once(')').context("app process stat")?;
            Ok(fields
                .split_whitespace()
                .nth(2)
                .context("app process group")?
                .parse()?)
        })();

        let result = finish_manual_gui_session(
            Err(anyhow::anyhow!("{reason}")),
            &mut launcher,
            Some(&report),
            Duration::from_secs(10),
            None,
        );
        let error = format!("{:#}", result.unwrap_err());
        assert_eq!(group_observation?, app_pid);
        assert_ne!(app_pid, launcher.child.id());
        assert!(error.contains(reason), "{error}");
        assert!(!error.contains("cleanup also failed"), "{error}");
        assert!(
            launcher.stopped,
            "launcher must be reaped before owner release"
        );
        let evidence: serde_json::Value = serde_json::from_slice(&fs::read(&report)?)?;
        assert_eq!(evidence["pid"], app_pid);
        assert_eq!(evidence["cancelled"], true);
        assert_eq!(evidence["signal"], 9);
        assert!(
            !Path::new(&format!("/proc/{app_pid}")).exists(),
            "app was not reaped"
        );
        assert!(!directory.path().join("shutdown-stage.txt").exists());
        if outer_wrapper {
            println!(
                "wrapper_exits_on_group_stop=true stopped_after={} report_after={} app_alive_after={}",
                launcher.stopped,
                report.is_file(),
                Path::new(&format!("/proc/{app_pid}")).exists()
            );
        }
    }
    Ok(())
}

#[test]
fn cleanup_timeout_preserves_original_failure_and_does_not_claim_reclamation() -> Result<()> {
    for preexited in [false, true] {
        let directory = tempfile::tempdir()?;
        let ready = directory.path().join("app-pid");
        let report = directory.path().join("native-exit.json");
        let mut launcher = start_launcher(&ready, &report, preexited)?;
        let ready_result = wait_app(&ready, &mut launcher);
        if preexited {
            exit_outer_wrapper(&mut launcher)?;
        }
        let result = finish_manual_gui_session(
            Err(anyhow::anyhow!("original input failure")),
            &mut launcher,
            Some(&report),
            Duration::ZERO,
            None,
        );
        let fallback_armed = !launcher.stopped;
        let app_alive = ready_result
            .as_ref()
            .is_ok_and(|pid| Path::new(&format!("/proc/{pid}")).exists());
        println!(
            "timeout=true wrapper_preexited={preexited} fallback_armed={fallback_armed} report_after={} app_alive_after={app_alive}",
            report.is_file()
        );
        // Record state before safety cleanup, which must not hide premature disarming.
        finish_fixture(&mut launcher, &report)?;
        let app_pid = ready_result?;
        assert!(!Path::new(&format!("/proc/{app_pid}")).exists());
        let error = format!("{:#}", result.unwrap_err());
        assert!(error.contains("original input failure"), "{error}");
        assert!(error.contains("cleanup timed out"), "{error}");
        assert!(
            error.contains("subtree reclamation is unconfirmed"),
            "{error}"
        );
        assert!(report.is_file());
        assert!(
            fallback_armed,
            "outer reap must not disarm whole-owner fallback"
        );
    }
    Ok(())
}
