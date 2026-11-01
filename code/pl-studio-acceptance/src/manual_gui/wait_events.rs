//! Official Flutter integration_test runner over the isolated real Studio stack.
//! The fixture and subprocess remain owned here; assertions and test discovery
//! belong to Flutter, not to a second host-side observation state machine.

use super::*;

pub(super) struct WaitEventsScenario<'a> {
    pub workspace: &'a Path,
    pub app_dir: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    pub fixture_log: &'a Path,
    pub requests_file: &'a Path,
    pub interrupt: &'a mpsc::Receiver<()>,
}

pub(super) fn run(context: &WaitEventsScenario<'_>, mut fixture: OwnedProcess) -> Result<()> {
    let WaitEventsScenario {
        workspace,
        app_dir,
        home,
        working,
        output,
        fixture_log,
        requests_file,
        interrupt,
    } = context;
    let log_path = working.join("wait-events-integration.log");
    let projects = working.join("wait-events-project");
    let mut runner_exit = None;
    let suite = (|| -> Result<()> {
        for name in ["sleep-first", "tool-first", "timeout", "child", "cancel"] {
            let project = projects.join(name);
            fs::create_dir_all(&project)?;
            ensure!(
                Command::new("git")
                    .args(["init", "-q"])
                    .arg(&project)
                    .status()?
                    .success(),
                "failed to initialize isolated {name} project"
            );
        }
        let log = File::create(&log_path)?;
        let mut command = Command::new("cargo");
        command
            .current_dir(workspace)
            .args([
                "xtask",
                "run-gui",
                "--integration-test",
                "integration_test/wait_events_test.dart",
            ])
            .env("ANYWORK_HOME", home)
            .env("ANYWORK_WAIT_PROJECTS", &projects)
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
                    "Waiting integration tests failed: {status}"
                );
                break;
            }
            ensure!(
                !fixture.exited()?,
                "fixture exited during Waiting integration tests"
            );
            ensure!(
                interrupt.try_recv().is_err(),
                "Waiting integration tests cancelled"
            );
            ensure!(
                Instant::now() < deadline,
                "Waiting integration tests timed out"
            );
            thread::sleep(Duration::from_millis(200));
        }
        Ok(())
    })();

    // Archive even on assertion/startup failure; do not lose evidence when the
    // enclosing harness retains or releases its isolated environment.
    let fixture_result = fixture.stop(requests_file);
    drop(fixture);
    write_realtime_driver_evidence(
        &log_path,
        output,
        "wait-events-integration",
        runner_exit,
        suite.as_ref().err(),
        &[
            (app_dir.to_string_lossy().into_owned(), "<app>"),
            (workspace.to_string_lossy().into_owned(), "<workspace>"),
            (home.to_string_lossy().into_owned(), "<home>"),
            (working.to_string_lossy().into_owned(), "<environment>"),
        ],
    )?;
    write_fixture_log(fixture_log, &output.join("fixture.log"))?;
    let requests = if requests_file.is_file() {
        sanitize_requests(requests_file, &output.join("requests.json"))?;
        serde_json::from_slice::<Vec<serde_json::Value>>(&fs::read(requests_file)?)?
    } else {
        Vec::new()
    };
    let rejected = requests
        .iter()
        .filter(|row| row["accepted"] == false)
        .count();
    let notes: Vec<&str> = requests
        .iter()
        .filter_map(|row| row.pointer("/diagnostic/category")?.as_str())
        .collect();
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "wait-events",
            "runner": "flutter.integration_test",
            "runnerExitCode": runner_exit.and_then(|status| status.code()),
            "rejectedRequests": rejected,
            "notes": notes,
            "completed": fixture_result.as_ref().is_ok_and(|status| status.success()),
        }))?,
    )?;
    suite?;
    ensure!(
        fixture_result.is_ok_and(|status| status.success()) && rejected == 0,
        "Waiting fixture failed or rejected requests"
    );
    // Boundary evidence only, not a replacement for Flutter assertions. In
    // particular these two notes validate the real provider context, not UI text.
    for required in [
        "sleep_first_answered",
        "tool_first_answered",
        "already_ready_answered",
        "timeout_answered",
        "child_report_once",
        "child_report_still_once",
        "cancel_query_answered",
    ] {
        ensure!(
            notes.contains(&required),
            "missing provider boundary: {required}"
        );
    }
    println!("Waiting integration evidence: {}", output.display());
    Ok(())
}
