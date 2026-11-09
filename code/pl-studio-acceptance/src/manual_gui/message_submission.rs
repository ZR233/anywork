//! Isolated native submission acceptance; assertions remain in integration_test.

use super::*;

pub(super) struct SubmissionScenario<'a> {
    pub workspace: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    pub fixture_log: &'a Path,
    pub requests_file: &'a Path,
    pub interrupt: &'a mpsc::Receiver<()>,
    pub provider_url: &'a str,
}

pub(super) fn run(context: &SubmissionScenario<'_>, mut fixture: OwnedProcess) -> Result<()> {
    let project = context.working.join("message-submission-project");
    let log_path = context.working.join("message-submission-integration.log");
    let mut runner_exit = None;
    let suite = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated submission project"
        );
        let log = File::create(&log_path)?;
        let mut command = desktop_test_command(context.workspace)?;
        command
            .args(["--suite", "desktop", "--case", "message_submission"])
            .env("ANYWORK_HOME", context.home)
            .env_remove("ANYWORK_LOG_LEVEL")
            .env(
                "RUST_LOG",
                "warn,prompt_submission=debug,conversation_work=debug",
            )
            .env("ANYWORK_SUBMISSION_PROJECT", &project)
            .env("ANYWORK_SUBMISSION_OUTPUT", context.output)
            .env("ANYWORK_SUBMISSION_PROVIDER", context.provider_url)
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));
        // This dedicated case requires real PNG evidence; never silently skip it.
        configure_presentation_capture(&mut command, context.output, true);
        let mut runner = OwnedProcess::start(&mut command, false)?;
        let deadline = Instant::now() + Duration::from_secs(1_200);
        loop {
            if let Some(status) = runner.child.try_wait()? {
                runner.stopped = true;
                runner_exit = Some(status);
                ensure!(
                    status.success(),
                    "submission integration test failed: {status}"
                );
                break;
            }
            ensure!(!fixture.exited()?, "submission fixture exited unexpectedly");
            ensure!(
                context.interrupt.try_recv().is_err(),
                "submission case cancelled"
            );
            ensure!(Instant::now() < deadline, "submission case timed out");
            thread::sleep(Duration::from_millis(200));
        }
        let report: serde_json::Value = serde_json::from_slice(
            &fs::read(context.output.join("message-submission.json"))
                .context("submission integration test wrote no report")?,
        )?;
        ensure!(
            report["pass"] == true && report["shutdown"] == "completed",
            "submission report did not pass: {report}"
        );
        for name in [
            "submission-pending.png",
            "submission-received.png",
            "submission-canonical.png",
        ] {
            ensure!(
                context.output.join(name).is_file(),
                "missing submission screenshot {name}"
            );
        }
        Ok(())
    })();
    let fixture_result = fixture.stop(context.requests_file);
    drop(fixture);
    let timing_evidence = write_submission_timing(context.home, context.output);
    let redactions = [
        (
            context.workspace.to_string_lossy().into_owned(),
            "<workspace>",
        ),
        (context.home.to_string_lossy().into_owned(), "<home>"),
        (
            context.working.to_string_lossy().into_owned(),
            "<environment>",
        ),
    ];
    write_realtime_driver_evidence(
        &log_path,
        context.output,
        "message-submission-integration",
        runner_exit,
        suite.as_ref().err(),
        &redactions,
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
    let completed = fixture_result.as_ref().is_ok_and(|status| status.success());
    fs::write(
        context.output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "message-submission",
            "runnerExitCode": runner_exit.and_then(|status| status.code()),
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "completed": completed,
        }))?,
    )?;
    suite?;
    timing_evidence?;
    ensure!(completed, "submission fixture did not exit successfully");
    ensure!(
        accepted >= 2 && rejected == 0,
        "submission fixture incomplete: accepted={accepted} rejected={rejected}"
    );
    Ok(())
}

/// Keep only the named metadata-only runtime events, never prompt bodies.
/// input_id on admission maps to source_effect_seq on projection/publication.
fn write_submission_timing(home: &Path, output: &Path) -> Result<()> {
    let source = File::open(home.join("studio/logs/studio.log"))
        .context("open isolated submission timing log")?;
    let mut destination = File::create(output.join("submission-backend-timing.log"))?;
    writeln!(
        destination,
        "rust_log=warn,prompt_submission=debug,conversation_work=debug\n\
         join=input_id -> prompt accepted.source_effect_seq -> conversation_work.source_effect_seq\n\
         scope=named metadata-only stages from current isolated studio.log; no message bodies"
    )?;
    let events = [
        ("prompt_submission", "prompt lifecycle admission acquired"),
        ("prompt_submission", "prompt thread admission acquired"),
        ("prompt_submission", "prompt resources prepared"),
        ("prompt_submission", "prompt accepted"),
        ("conversation_work", "live owner projection and handoff"),
        ("conversation_work", "completion publication finished"),
        ("conversation_work", "conversation feed published"),
    ];
    let mut count = 0;
    for line in BufReader::new(source).lines() {
        let line = line.context("read isolated submission timing log")?;
        let Some((header, message)) = line.split_once(": ") else {
            continue;
        };
        if events.iter().any(|(target, event)| {
            header.split_whitespace().last() == Some(*target)
                && (message == *event
                    || message
                        .strip_prefix(*event)
                        .is_some_and(|fields| fields.starts_with(' ')))
        }) {
            writeln!(destination, "{line}")?;
            count += 1;
        }
    }
    ensure!(
        count > 0,
        "isolated submission timing log contains no named stages"
    );
    Ok(())
}
