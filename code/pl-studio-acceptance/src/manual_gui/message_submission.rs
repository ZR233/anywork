//! Isolated native submission acceptance; assertions remain in integration_test.

use super::*;
use futures::FutureExt as _;
use pl_provider_fixture::{
    FixtureOptions, FixtureServer, Protocol, ReplyStage, Step, responses_text,
};

const LIFECYCLE_PROMPT: &str = "请保持这次执行，等待我停止后再显式继续。";

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
    let runtime = tokio::runtime::Runtime::new()?;
    let gates = [ReplyStage::new(), ReplyStage::new()];
    let mut lifecycle_fixture = None;
    let mut fixture_result = None;
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
            if fixture_result.is_none() {
                ensure!(!fixture.exited()?, "submission fixture exited unexpectedly");
                if context
                    .output
                    .join("submission-lifecycle-requested")
                    .is_file()
                {
                    // The original two-turn story has completed. Reuse the
                    // same strict provider implementation and address for its
                    // continuation, without changing any product configuration.
                    fixture_result = Some(fixture.stop(context.requests_file));
                    ensure!(
                        fixture_result.as_ref().is_some_and(|result| result
                            .as_ref()
                            .is_ok_and(|status| status.success())),
                        "submission provider did not complete before lifecycle handoff"
                    );
                    let port = reqwest::Url::parse(context.provider_url)?
                        .port()
                        .context("submission provider has no explicit loopback port")?;
                    let server = runtime.block_on(FixtureServer::start_with_options(
                        lifecycle_script(&gates),
                        FixtureOptions {
                            bind_port: Some(port),
                            ..FixtureOptions::default()
                        },
                    ))?;
                    ensure!(
                        server.base_url() == context.provider_url,
                        "lifecycle fixture changed the configured provider address"
                    );
                    lifecycle_fixture = Some(server);
                    fs::write(
                        context.output.join("submission-lifecycle-ready"),
                        b"ready\n",
                    )?;
                }
            }
            for (name, gate) in ["stop", "resume"].into_iter().zip(&gates) {
                let reached = context.output.join(format!("submission-{name}-reached"));
                if !reached.is_file() && gate.wait_reached().now_or_never().is_some() {
                    fs::write(reached, b"prefix written\n")?;
                }
                if context
                    .output
                    .join(format!("submission-{name}-release"))
                    .is_file()
                {
                    gate.release();
                }
            }
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
            report["pass"] == true
                && report["shutdown"] == "completed"
                && report["lifecycle"]["completed"] == true,
            "submission report did not pass: {report}"
        );
        for name in [
            "submission-pending.png",
            "submission-received.png",
            "submission-canonical.png",
            "submission-editing.png",
            "submission-next-draft.png",
            "submission-stopping.png",
            "submission-stopped.png",
            "submission-resumed-narrow.png",
        ] {
            ensure!(
                context.output.join(name).is_file(),
                "missing submission screenshot {name}"
            );
        }
        Ok(())
    })();
    let fixture_result = fixture_result.unwrap_or_else(|| fixture.stop(context.requests_file));
    drop(fixture);
    // Release and join the in-process provider on success AND failure. Its
    // recorded requests remain available even if a GUI assertion failed.
    for gate in &gates {
        gate.release();
    }
    let lifecycle_result = (|| -> Result<()> {
        let server = lifecycle_fixture.context("lifecycle provider was not exercised")?;
        let report = runtime.block_on(server.shutdown())?;
        let raw_requests = context.working.join("submission-lifecycle-requests.json");
        fs::write(&raw_requests, serde_json::to_vec_pretty(&report.requests)?)?;
        sanitize_requests(
            &raw_requests,
            &context.output.join("submission-lifecycle-requests.json"),
        )?;
        fs::write(
            context.output.join("submission-lifecycle-fixture.json"),
            serde_json::to_vec_pretty(&serde_json::json!({
                "listenerJoined": true,
                "consumedSteps": report.consumed_steps,
                "expectedSteps": report.expected_steps,
                "acceptedRequests": report.requests.iter().filter(|request| request.accepted).count(),
                "rejectedRequests": report.requests.iter().filter(|request| !request.accepted).count(),
            }))?,
        )?;
        report.verify()
    })();
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
    lifecycle_result?;
    ensure!(completed, "submission fixture did not exit successfully");
    ensure!(
        accepted >= 2 && rejected == 0,
        "submission fixture incomplete: accepted={accepted} rejected={rejected}"
    );
    Ok(())
}

/// Extend the existing journey after its original provider script is exhausted.
/// Gates delay only SSE completion, never synthesize receipt/canonical state.
fn lifecycle_script(gates: &[ReplyStage; 2]) -> Vec<Step> {
    ["正在处理这次可停止的执行。", "已显式继续，恢复执行完成。"]
        .into_iter()
        .enumerate()
        .map(|(index, text)| {
            let events = responses_text(
                text,
                &format!("submission-lifecycle-{index}"),
                "fixture-model",
            );
            let last = events.len() - 1;
            Step::prompt(
                Protocol::ResponsesHttp,
                LIFECYCLE_PROMPT,
                index,
                gates[index].gated(events[..last].to_vec(), events[last..].to_vec()),
            )
        })
        .collect()
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
