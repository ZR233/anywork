//! Official integration_test coverage for realtime production presentation.
//! The existing `realtime` preset remains the owner of credit-wait,
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
    pub provider_url: &'a str,
    pub realtime_focus: Option<&'a str>,
}

pub(super) fn run(
    context: &RealtimePresentationScenario<'_>,
    mut fixture: OwnedProcess,
) -> Result<()> {
    let required_steps = match context.realtime_focus {
        None => REALTIME_REQUIRED_STEPS,
        Some("stop-background") => pl_provider_fixture::REALTIME_STOP_BACKGROUND_REQUIRED_STEPS,
        Some(value) => bail!("unknown realtime focus: {value}"),
    };
    let focus = context.realtime_focus.unwrap_or("full");
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
        let mut command = desktop_test_command(context.workspace)?;
        command
            .args(["--suite", "desktop", "--case", "realtime_presentation"])
            .env("ANYWORK_HOME", context.home)
            .env_remove("ANYWORK_LOG_LEVEL")
            .env("RUST_LOG", "warn,conversation_work=debug")
            .env("ANYWORK_REALTIME_PROJECT", &project)
            .env("ANYWORK_REALTIME_OUTPUT", context.output)
            .env("ANYWORK_REALTIME_PROVIDER", context.provider_url)
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));
        if let Some(focus) = context.realtime_focus {
            command.env("ANYWORK_REALTIME_FOCUS", focus);
        } else {
            command.env_remove("ANYWORK_REALTIME_FOCUS");
        }
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
                && report.get("shutdown") == Some(&serde_json::Value::String("completed".into()))
                && report.get("focus").and_then(serde_json::Value::as_str) == Some(focus)
                && report
                    .get("expectedRequiredProviderSteps")
                    .and_then(serde_json::Value::as_u64)
                    == Some(required_steps as u64),
            "realtime-presentation integration report did not pass: {}",
            serde_json::to_string_pretty(&report)?
        );
        Ok(())
    })();

    let fixture_result = fixture.stop(context.requests_file);
    drop(fixture);
    let redactions = [
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
    ];
    let content_range_evidence =
        write_content_range_evidence(context.home, context.output, &redactions);
    write_realtime_driver_evidence(
        &log_path,
        context.output,
        "realtime-presentation-integration",
        runner_exit,
        suite.as_ref().err(),
        &redactions,
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
            "fixtureScenario": "realtime-presentation",
            "runner": "flutter.integration_test",
            "focus": focus,
            "expectedRequiredProviderSteps": required_steps,
            "runnerExitCode": runner_exit.and_then(|status| status.code()),
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "completed": fixture_result.as_ref().is_ok_and(|status| status.success()),
            "requiredStepsConsumed": accepted >= required_steps,
        }))?,
    )?;
    suite?;
    ensure!(
        fixture_result.is_ok_and(|status| status.success()),
        "realtime fixture did not exit successfully"
    );
    ensure!(
        accepted >= required_steps && rejected == 0,
        "realtime-presentation fixture requests were incomplete: \
         accepted={accepted} rejected={rejected}"
    );
    content_range_evidence?;
    println!(
        "Realtime-presentation integration evidence: {}",
        context.output.display()
    );
    Ok(())
}

fn write_content_range_evidence(
    home: &Path,
    output: &Path,
    redactions: &[(String, &str)],
) -> Result<()> {
    let source = home.join("studio/logs/studio.log");
    let destination = output.join("realtime-content-range-driver.log");
    let mut evidence =
        File::create(&destination).context("create realtime content-range driver evidence")?;
    writeln!(
        evidence,
        "rust_log=warn,conversation_work=debug\n\
         filter=target conversation_work: AND message (content range started OR content range completed)\n\
         source_scope=current studio.log only\n\
         rolling_archives=not included\n\
         line_sanitization=existing sanitize_driver_line path/loopback redaction; 480 character limit"
    )?;
    let source = match File::open(source) {
        Ok(source) => source,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            writeln!(evidence, "source_status=missing")?;
            return Ok(());
        }
        Err(error) => return Err(error).context("open isolated current studio.log"),
    };
    let mut reader = BufReader::new(source);
    let mut line = String::new();
    let mut source_bytes = 0;
    let mut saw_event = false;
    loop {
        line.clear();
        let bytes = reader
            .read_line(&mut line)
            .context("read isolated current studio.log as UTF-8")?;
        if bytes == 0 {
            break;
        }
        source_bytes += bytes;
        let line = line.trim_end_matches(['\r', '\n']);
        let matches = line.split_once(": ").is_some_and(|(header, message)| {
            header.split_whitespace().last() == Some("conversation_work")
                && ["content range started", "content range completed"]
                    .into_iter()
                    .any(|event| {
                        message == event
                            || message
                                .strip_prefix(event)
                                .is_some_and(|rest| rest.starts_with(' '))
                    })
        });
        if matches {
            writeln!(
                evidence,
                "{}",
                super::sanitize_driver_line(line, redactions)
            )?;
            saw_event = true;
        }
    }
    writeln!(evidence, "source_status=read\nsource_bytes={source_bytes}")?;
    if !saw_event {
        writeln!(
            evidence,
            "observation=no matching events in current studio.log; this does not establish that no requests occurred"
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn content_range_evidence_preserves_metadata_and_filters_and_redacts() -> Result<()> {
        let home = tempfile::tempdir()?;
        let logs = home.path().join("studio/logs");
        fs::create_dir_all(&logs)?;
        let started = "2026-06-01T12:34:56.123Z DEBUG ThreadId(07) conversation_work: content range started thread_id=\"thread-17\" trace_id=\"trace-29\" content_range_requests=1";
        let completed_prefix = "2026-06-01T12:34:56.456Z DEBUG ThreadId(09) conversation_work: content range completed thread_id=\"thread-17\" trace_id=\"trace-29\" content_bytes=4096";
        let completed = format!(
            "{completed_prefix} path={}/work url=ws://127.0.0.1:41873/secret-token=/ws host=localhost:41873 padding={}",
            home.path().display(),
            "x".repeat(520)
        );
        let raw = format!(
            "{started}\r\n{completed}\n\
             2026-06-01T12:34:56.789Z DEBUG ThreadId(07) other_target: content range started body=other-target-body\n\
             2026-06-01T12:34:56.789Z DEBUG ThreadId(07) other_target: conversation_work: content range completed body=quoted-target-body\n\
             2026-06-01T12:34:56.789Z DEBUG ThreadId(07) other_conversation_work: content range completed body=prefix-target-body\n\
             2026-06-01T12:34:56.789Z DEBUG ThreadId(07) conversation_work_extra: content range completed body=suffix-target-body\n\
             2026-06-01T12:34:56.789Z DEBUG ThreadId(07) conversation_work: read started body=unrelated-body\n\
             2026-06-01T12:34:56.789Z DEBUG ThreadId(07) conversation_work: body=正文 content range started\n\
             2026-06-01T12:34:56.789Z DEBUG ThreadId(07) conversation_work: content range started_later body=other-message-body\n"
        );
        fs::write(logs.join("studio.log"), &raw)?;
        write_content_range_evidence(
            home.path(),
            home.path(),
            &[(home.path().to_string_lossy().into_owned(), "<home>")],
        )?;
        let evidence = fs::read_to_string(home.path().join("realtime-content-range-driver.log"))?;
        let events: Vec<_> = evidence
            .lines()
            .filter(|line| line.starts_with("2026-"))
            .collect();
        assert_eq!(events.len(), 2);
        assert_eq!(events[0], started);
        let expected_completed = format!(
            "{completed_prefix} path=<home>/work url=<loopback-url> host=localhost:<port> padding={}",
            "x".repeat(520)
        );
        assert_eq!(
            events[1],
            expected_completed.chars().take(480).collect::<String>()
        );
        assert!(evidence.contains(&format!("source_status=read\nsource_bytes={}", raw.len())));
        assert!(!evidence.contains(home.path().to_string_lossy().as_ref()));
        assert!(!evidence.contains("secret-token"));
        assert!(!evidence.contains("41873"));
        assert!(!evidence.contains("body="));
        assert!(!evidence.contains("正文"));
        Ok(())
    }

    #[test]
    fn content_range_evidence_distinguishes_missing_empty_and_unmatched_current_file() -> Result<()>
    {
        let home = tempfile::tempdir()?;
        let logs = home.path().join("studio/logs");
        fs::create_dir_all(&logs)?;
        fs::write(
            logs.join("studio.log.1"),
            "2026-06-01T12:34:56Z DEBUG ThreadId(07) conversation_work: content range completed content_bytes=8192\n",
        )?;
        let destination = home.path().join("realtime-content-range-driver.log");
        write_content_range_evidence(home.path(), home.path(), &[])?;
        let missing = fs::read_to_string(&destination)?;
        assert!(missing.contains("source_status=missing"));
        assert!(missing.contains("source_scope=current studio.log only"));
        assert!(missing.contains("rolling_archives=not included"));
        assert!(!missing.contains("source_status=read"));
        assert!(!missing.contains("source_bytes="));
        assert!(!missing.contains("observation="));
        assert!(!missing.contains("content_range_requests="));
        assert!(!missing.contains("content_bytes="));
        fs::write(logs.join("studio.log"), "")?;
        write_content_range_evidence(home.path(), home.path(), &[])?;
        let empty = fs::read_to_string(&destination)?;
        assert!(empty.contains("source_status=read\nsource_bytes=0"));
        assert!(!empty.contains("source_status=missing"));
        assert!(!empty.contains("content_bytes="));
        assert!(empty.contains(
            "observation=no matching events in current studio.log; this does not establish that no requests occurred"
        ));
        let unrelated = "DEBUG other_target: 正文\n";
        fs::write(logs.join("studio.log"), unrelated)?;
        write_content_range_evidence(home.path(), home.path(), &[])?;
        let unmatched = fs::read_to_string(destination)?;
        assert!(unmatched.contains(&format!("source_bytes={}", unrelated.len())));
        assert!(unmatched.contains("observation=no matching events in current studio.log"));
        assert!(!unmatched.contains("正文"));
        assert!(!unmatched.contains("content_bytes="));
        Ok(())
    }

    #[test]
    fn content_range_evidence_propagates_source_io_and_utf8_errors() -> Result<()> {
        let home = tempfile::tempdir()?;
        let source = home.path().join("studio/logs/studio.log");
        fs::create_dir_all(&source)?;
        let error = write_content_range_evidence(home.path(), home.path(), &[])
            .expect_err("a directory is not a readable studio log");
        assert!(error.downcast_ref::<io::Error>().is_some());
        fs::remove_dir(&source)?;
        fs::write(&source, [0xff, b'\n'])?;
        let error = write_content_range_evidence(home.path(), home.path(), &[])
            .expect_err("invalid UTF-8 must not be silently omitted");
        assert_eq!(
            error.downcast_ref::<io::Error>().map(io::Error::kind),
            Some(io::ErrorKind::InvalidData)
        );
        Ok(())
    }
}
