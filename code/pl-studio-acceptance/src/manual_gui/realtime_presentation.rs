//! Official integration_test coverage for realtime production presentation.
//! The existing `realtime` Driver journey remains the owner of credit-wait,
//! host-cwd, geometry and diagnostic evidence.

use super::*;

pub(super) struct RealtimePresentationScenario<'a> {
    pub workspace: &'a Path,
    pub app_dir: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    pub fixture_log: &'a Path,
    pub requests_file: &'a Path,
    pub interrupt: &'a mpsc::Receiver<()>,
    pub capture_presentation: bool,
}

pub(super) fn run(
    context: &RealtimePresentationScenario<'_>,
    mut fixture: OwnedProcess,
) -> Result<()> {
    let project = context.working.join("realtime-presentation-project");
    let log_path = context
        .working
        .join("realtime-presentation-integration.log");
    let mut runner_exit = None;
    let suite = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated realtime-presentation project"
        );
        let log = File::create(&log_path)?;
        let mut command = Command::new("cargo");
        command
            .current_dir(context.workspace)
            .args([
                "xtask",
                "run-gui",
                "--integration-test",
                "integration_test/realtime_presentation_test.dart",
            ])
            .env("ANYWORK_HOME", context.home)
            .env("ANYWORK_REALTIME_PROJECT", &project)
            .env("ANYWORK_REALTIME_OUTPUT", context.output)
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));
        configure_presentation_capture(&mut command, context.output, context.capture_presentation);
        let mut runner = OwnedProcess::start(&mut command, false)?;
        let deadline = Instant::now() + Duration::from_secs(1_200);
        loop {
            if let Some(status) = runner.child.try_wait()? {
                runner.stopped = true;
                runner_exit = Some(status);
                ensure!(
                    status.success(),
                    "realtime-presentation integration test failed: {status}"
                );
                break;
            }
            ensure!(
                !fixture.exited()?,
                "fixture exited during realtime-presentation integration test"
            );
            ensure!(
                context.interrupt.try_recv().is_err(),
                "realtime-presentation integration test cancelled"
            );
            ensure!(
                Instant::now() < deadline,
                "realtime-presentation integration test timed out"
            );
            thread::sleep(Duration::from_millis(200));
        }
        let report: serde_json::Value = serde_json::from_slice(
            &fs::read(context.output.join("realtime-presentation.json"))
                .context("realtime-presentation integration test wrote no report")?,
        )?;
        ensure!(
            report.get("pass") == Some(&serde_json::Value::Bool(true))
                && report.get("shutdown") == Some(&serde_json::Value::String("completed".into())),
            "realtime-presentation integration report did not pass: {}",
            serde_json::to_string_pretty(&report)?
        );
        Ok(())
    })();

    let fixture_result = fixture.stop(context.requests_file);
    drop(fixture);
    write_realtime_driver_evidence(
        &log_path,
        context.output,
        "realtime-presentation-integration",
        runner_exit,
        suite.as_ref().err(),
        &[
            (context.app_dir.to_string_lossy().into_owned(), "<app>"),
            (
                context.workspace.to_string_lossy().into_owned(),
                "<workspace>",
            ),
            (context.home.to_string_lossy().into_owned(), "<home>"),
            (
                context.working.to_string_lossy().into_owned(),
                "<environment>",
            ),
        ],
    )?;
    let archived_log = context
        .output
        .join("realtime-presentation-integration-driver.log");
    if archived_log.is_file() {
        fs::rename(
            archived_log,
            context.output.join("realtime-presentation-integration.log"),
        )?;
    }
    fs::rename(
        context
            .output
            .join("realtime-presentation-integration-driver-errors.txt"),
        context
            .output
            .join("realtime-presentation-integration-errors.txt"),
    )?;
    write_fixture_log(context.fixture_log, &context.output.join("fixture.log"))?;
    let requests = if context.requests_file.is_file() {
        sanitize_requests(context.requests_file, &context.output.join("requests.json"))?;
        serde_json::from_slice::<Vec<serde_json::Value>>(&fs::read(context.requests_file)?)?
    } else {
        Vec::new()
    };
    let accepted = requests
        .iter()
        .filter(|row| row["accepted"] == true)
        .count();
    let rejected = requests
        .iter()
        .filter(|row| row["accepted"] == false)
        .count();
    fs::write(
        context.output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "realtime-presentation",
            "fixtureScenario": "realtime",
            "runner": "flutter.integration_test",
            "runnerExitCode": runner_exit.and_then(|status| status.code()),
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "completed": fixture_result.as_ref().is_ok_and(|status| status.success()),
            "requiredStepsConsumed": accepted >= REALTIME_REQUIRED_STEPS,
        }))?,
    )?;
    suite?;
    ensure!(
        fixture_result.is_ok_and(|status| status.success()),
        "realtime fixture did not exit successfully"
    );
    ensure!(
        accepted >= REALTIME_REQUIRED_STEPS && rejected == 0,
        "realtime-presentation fixture requests were incomplete: \
         accepted={accepted} rejected={rejected}"
    );
    println!(
        "Realtime-presentation integration evidence: {}",
        context.output.display()
    );
    Ok(())
}
