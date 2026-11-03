//! Independent concept journey; never consumes the realtime Driver script.

mod media_fault;

use super::*;

pub(super) struct TimelineConceptScenario<'a> {
    pub workspace: &'a Path,
    pub app_dir: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    pub fixture_log: &'a Path,
    pub requests_file: &'a Path,
    pub interrupt: &'a mpsc::Receiver<()>,
    pub capture_presentation: bool,
    pub provider_url: &'a str,
}

pub(super) fn run(context: &TimelineConceptScenario<'_>, mut fixture: OwnedProcess) -> Result<()> {
    let project = context.working.join("timeline-concept-project");
    let log_path = context.working.join("timeline-concept-integration.log");
    let mut runner_exit = None;
    let suite = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated timeline-concept project"
        );
        fs::write(
            project.join("concept-boundary.txt"),
            "concept-boundary-source\n",
        )?;
        for name in ["a", "b", "c"] {
            fs::copy(
                context
                    .app_dir
                    .join("integration_test/fixtures/tool-image.png"),
                project.join(format!("concept-image-{name}.png")),
            )?;
        }
        // These are user attachments, not the three independent view_image
        // sources above. Keep their resource hashes separate for media faults.
        for (source, target) in [
            (
                "assets/branding/anywork-startup-cat.png",
                "concept-input-a.png",
            ),
            (
                "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png",
                "concept-input-b.png",
            ),
            (
                "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png",
                "concept-input-c.png",
            ),
        ] {
            fs::copy(context.app_dir.join(source), project.join(target))?;
        }
        let empty_thread = seed_empty_thread(context.home, &project)?;
        File::create(&log_path)?;
        for phase in ["journey", "reopen", "media-missing"] {
            let reopen = phase != "journey";
            if phase == "media-missing" {
                media_fault::inject(context.working, context.home, &project, context.output)?;
            }
            let mut log = fs::OpenOptions::new().append(true).open(&log_path)?;
            writeln!(log, "timeline-concept native process: phase={phase}")?;
            let mut command = Command::new("cargo");
            command
                .current_dir(context.workspace)
                .args([
                    "xtask",
                    "run-gui",
                    "--integration-test",
                    "integration_test/timeline_concept_test.dart",
                ])
                .env("ANYWORK_HOME", context.home)
                .env("ANYWORK_TIMELINE_CONCEPT_PROJECT", &project)
                .env("ANYWORK_TIMELINE_CONCEPT_OUTPUT", context.output)
                .env("ANYWORK_TIMELINE_CONCEPT_PROVIDER", context.provider_url)
                .env("ANYWORK_TIMELINE_CONCEPT_EMPTY_THREAD", &empty_thread)
                .env(
                    "ANYWORK_TIMELINE_CONCEPT_REOPEN",
                    if reopen { "1" } else { "0" },
                )
                .env(
                    "ANYWORK_TIMELINE_CONCEPT_MEDIA_FAULT",
                    if phase == "media-missing" { "1" } else { "0" },
                )
                .stdout(Stdio::from(log.try_clone()?))
                .stderr(Stdio::from(log));
            configure_presentation_capture(
                &mut command,
                context.output,
                context.capture_presentation,
            );
            let mut runner = OwnedProcess::start(&mut command, false)?;
            let deadline = Instant::now() + Duration::from_secs(1_200);
            loop {
                if let Some(status) = runner.child.try_wait()? {
                    runner.stopped = true;
                    runner_exit = Some(status);
                    ensure!(
                        status.success(),
                        "timeline-concept integration test failed: {status}"
                    );
                    break;
                }
                ensure!(
                    !fixture.exited()?,
                    "fixture exited during timeline-concept integration test"
                );
                ensure!(
                    context.interrupt.try_recv().is_err(),
                    "timeline-concept integration test cancelled"
                );
                ensure!(
                    Instant::now() < deadline,
                    "timeline-concept integration test timed out"
                );
                thread::sleep(Duration::from_millis(200));
            }
            let name = match phase {
                "journey" => "timeline-concept.json",
                "reopen" => "timeline-concept-reopen.json",
                _ => "timeline-concept-media-missing.json",
            };
            let report: serde_json::Value = serde_json::from_slice(
                &fs::read(context.output.join(name))
                    .context("timeline-concept integration test wrote no report")?,
            )?;
            ensure!(
                report.get("pass") == Some(&serde_json::Value::Bool(true))
                    && report.get("shutdown")
                        == Some(&serde_json::Value::String("completed".into())),
                "timeline-concept integration report did not pass: {}",
                serde_json::to_string_pretty(&report)?
            );
            if phase == "media-missing" {
                ensure!(
                    report["mediaResourceFailureObserved"] == true,
                    "missing-media phase must observe the real production image load failure"
                );
            }
        }
        Ok(())
    })();

    let fixture_result = fixture.stop(context.requests_file);
    drop(fixture);
    write_realtime_driver_evidence(
        &log_path,
        context.output,
        "timeline-concept-integration",
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
        .join("timeline-concept-integration-driver.log");
    if archived_log.is_file() {
        fs::rename(
            archived_log,
            context.output.join("timeline-concept-integration.log"),
        )?;
    }
    fs::rename(
        context
            .output
            .join("timeline-concept-integration-driver-errors.txt"),
        context
            .output
            .join("timeline-concept-integration-errors.txt"),
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
    // The fixture exits successfully only after FixtureReport::verify confirms
    // all required script steps. Accepted requests also include completion waits
    // that do not advance the script, so their count alone is not completion.
    let completed = fixture_result.as_ref().is_ok_and(|status| status.success());
    let required_steps_consumed = completed
        && accepted >= pl_provider_fixture::timeline_concept::REQUIRED_STEPS
        && rejected == 0;
    fs::write(
        context.output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "timeline-concept",
            "fixtureScenario": "timeline-concept",
            "runner": "flutter.integration_test",
            "runnerExitCode": runner_exit.and_then(|status| status.code()),
            "acceptedRequests": accepted,
            "acceptedRequestsMeaning": "raw provider requests, including completion waits; not script steps",
            "rejectedRequests": rejected,
            "completed": completed,
            "requiredStepsConsumed": required_steps_consumed,
        }))?,
    )?;
    suite?;
    ensure!(
        completed,
        "timeline-concept fixture did not exit successfully"
    );
    ensure!(
        required_steps_consumed,
        "timeline-concept fixture requests were incomplete: \
         accepted={accepted} rejected={rejected}"
    );
    println!(
        "Timeline-concept integration evidence: {}",
        context.output.display()
    );
    Ok(())
}

/// Create the initial empty conversation through the real product owner, not
/// by synthesizing history rows. The GUI subsequently opens its SQLite history.
fn seed_empty_thread(home: &Path, project: &Path) -> Result<String> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(async {
        let studio = Box::pin(pl_studio_runtime::StudioRuntime::initialize(
            pl_studio_runtime::StudioRuntimeOptions {
                studio_home: Some(home.to_owned()),
                host: pl_studio_runtime::StudioHostKind::Test,
                ..pl_studio_runtime::StudioRuntimeOptions::desktop()
            },
        ))
        .await?;
        let prepared = async {
            let workspace = Box::pin(studio.open_project(project)).await?;
            let thread = Box::pin(studio.create_thread(&workspace.id, "概念工况空会话")).await?;
            Ok::<_, anyhow::Error>(thread.id)
        }
        .await;
        Box::pin(studio.shutdown_runtime()).await?;
        prepared
    })
}
