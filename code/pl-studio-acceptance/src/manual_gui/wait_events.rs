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
        let project = projects.join("sleep-first");
        fs::create_dir_all(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated sleep-first project"
        );
        let log = File::create(&log_path)?;
        let mut command = desktop_test_command(workspace)?;
        command
            .args(["--suite", "desktop", "--case", "wait_events"])
            .env("ANYWORK_HOME", home)
            .env("ANYWORK_WAIT_PROJECTS", &projects)
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));
        let mut runner = OwnedProcess::start(&mut command, false)?;
        runner_exit = Some(wait_desktop_runner(
            &mut runner,
            Some(&mut fixture),
            interrupt,
            Duration::from_secs(900),
            "Waiting integration test",
        )?);
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
    // Boundary evidence only, not a replacement for Flutter assertions. This
    // validates that the retained test consumed the real sleep-first provider
    // context rather than merely rendering fixture text.
    ensure!(
        notes.contains(&"sleep_first_answered"),
        "missing provider boundary: sleep_first_answered"
    );
    println!("Waiting integration evidence: {}", output.display());
    Ok(())
}
