//! Official integration_test journey for the real question interaction and its
//! persisted, redacted timeline receipt.

use super::*;

pub(super) struct QuestionHistoryScenario<'a> {
    pub workspace: &'a Path,
    pub app_dir: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    pub fixture_log: &'a Path,
    pub requests_file: &'a Path,
    pub status_file: &'a Path,
    pub interrupt: &'a mpsc::Receiver<()>,
    pub capture_presentation: bool,
}

pub(super) fn run(context: &QuestionHistoryScenario<'_>, mut fixture: OwnedProcess) -> Result<()> {
    let project = context.working.join("question-history-project");
    let log_path = context.working.join("question-history-integration.log");
    let mut runner_exit = None;
    let suite = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated question-history project"
        );
        let log = File::create(&log_path)?;
        let ready: pl_provider_fixture::ReadyFile =
            serde_json::from_slice(&fs::read(context.working.join("fixture-ready.json"))?)?;
        let mut command = Command::new("cargo");
        command
            .current_dir(context.workspace)
            .args([
                "xtask",
                "run-gui",
                "--integration-test",
                "integration_test/question_history_test.dart",
            ])
            .env("ANYWORK_HOME", context.home)
            .env("ANYWORK_QUESTION_HISTORY_PROJECT", &project)
            .env("ANYWORK_QUESTION_HISTORY_OUTPUT", context.output)
            .env("ANYWORK_QUESTION_HISTORY_PROVIDER", ready.base_url)
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));
        configure_presentation_capture(&mut command, context.output, context.capture_presentation);
        let mut runner = OwnedProcess::start(&mut command, false)?;
        let deadline = Instant::now() + Duration::from_secs(900);
        loop {
            if let Some(status) = runner.child.try_wait()? {
                runner.stopped = true;
                runner_exit = Some(status);
                ensure!(
                    status.success(),
                    "question-history integration test failed: {status}"
                );
                break;
            }
            ensure!(
                !fixture.exited()?,
                "fixture exited during question-history integration test"
            );
            ensure!(
                context.interrupt.try_recv().is_err(),
                "question-history integration test cancelled"
            );
            ensure!(
                Instant::now() < deadline,
                "question-history integration test timed out"
            );
            thread::sleep(Duration::from_millis(200));
        }
        let report: serde_json::Value = serde_json::from_slice(
            &fs::read(context.output.join("question-history.json"))
                .context("question-history integration test wrote no report")?,
        )?;
        ensure!(
            report.get("pass") == Some(&serde_json::Value::Bool(true))
                && report.get("shutdown") == Some(&serde_json::Value::String("completed".into())),
            "question-history integration report did not pass: {}",
            serde_json::to_string_pretty(&report)?
        );
        Ok(())
    })();

    let fixture_result = fixture.stop(context.requests_file);
    drop(fixture);
    write_realtime_driver_evidence(
        &log_path,
        context.output,
        "question-history-integration",
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
        .join("question-history-integration-driver.log");
    if archived_log.is_file() {
        fs::rename(
            archived_log,
            context.output.join("question-history-integration.log"),
        )?;
    }
    fs::rename(
        context
            .output
            .join("question-history-integration-driver-errors.txt"),
        context
            .output
            .join("question-history-integration-errors.txt"),
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
    let live_status: Option<pl_provider_fixture::FixtureLiveStatus> =
        if context.status_file.is_file() {
            Some(serde_json::from_slice(&fs::read(context.status_file)?)?)
        } else {
            None
        };
    fs::write(
        context.output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "question-history",
            "runner": "flutter.integration_test",
            "runnerExitCode": runner_exit.and_then(|status| status.code()),
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "completed": fixture_result.as_ref().is_ok_and(|status| status.success()),
            "requiredStepsConsumed": live_status.map(|status| status.remaining_optional),
        }))?,
    )?;
    suite?;
    ensure!(
        fixture_result.is_ok_and(|status| status.success()),
        "question-history fixture did not exit successfully"
    );
    ensure!(
        accepted >= 2 && rejected == 0,
        "question-history fixture requests were incomplete: accepted={accepted} rejected={rejected}"
    );
    if let Some(status) = live_status {
        ensure!(
            status.rejected == 0 && status.remaining_optional,
            "question-history strict script did not consume every required step: {status:?}"
        );
    }
    println!(
        "Question-history integration evidence: {}",
        context.output.display()
    );
    Ok(())
}
