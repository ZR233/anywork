//! Native GUI wait/sleep/child observation journey.
//!
//! Isolation, fixture, GUI, Driver and process ownership follow the existing
//! realtime harness. The Driver script records screenshots and typed snapshots;
//! this coordinator only propagates internal failures and fixture health. The
//! human verdict stays pending.

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

const REQUIRED_NOTES: &[&str] = &[
    "sleep_first_started",
    "sleep_first_wait",
    "sleep_first_wait_exec",
    "sleep_first_answered",
    "tool_first_started",
    "tool_first_wait",
    "tool_first_cancel_sleep",
    "tool_first_answered",
    "child_parent_sleep_started",
    "spawn_child_requested",
    "spawn_child_wait",
    "child_cancel_parent_sleep",
    "child_work_sleep",
    "child_work_wait",
    "child_work_finish",
    "child_report_once",
    "child_report_still_once",
    "already_ready_wait",
    "already_ready_answered",
    "timeout_sleep_started",
    "timeout_wait",
    "timeout_cancel_sleep",
    "timeout_answered",
    "cancel_sleep_started",
    "cancel_prepare_answered",
    "cancel_wait_hanging",
    "cancel_query_status",
    "cancel_query_cancel",
    "cancel_query_answered",
];

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
    let gui_log_path = working.join("wait-events-gui.log");
    let stage = working.join("wait-events-stage");
    let project = working.join("wait-events-project");
    let mut driver_exit: Option<std::process::ExitStatus> = None;
    let journey = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated wait-events project"
        );
        {
            let mut gui = start_realtime_gui(workspace, home, &gui_log_path)?;
            let vm_url = wait_for_vm(&gui_log_path, &mut gui, &mut fixture, interrupt)?;
            let mut driver = start_wait_events_driver(
                app_dir, home, &vm_url, &project, output, working, &stage,
            )?;
            let status =
                wait_for_realtime_driver(&stage, &mut driver, &mut gui, &mut fixture, interrupt)?;
            driver_exit = Some(status);
            ensure!(
                status.success(),
                "wait-events Driver failed with {status} (last stage: {})",
                fs::read_to_string(&stage).unwrap_or_else(|_| {
                    "driver_not_started (see wait-events-driver-errors.txt)".to_owned()
                })
            );
        }
        Ok(())
    })();

    if gui_log_path.is_file() {
        write_sanitized_log(&gui_log_path, &output.join("wait-events-gui.log"))?;
    }
    write_realtime_driver_evidence(
        &stage.with_extension("driver.log"),
        output,
        "wait-events",
        driver_exit,
        journey.as_ref().err(),
        &[
            (app_dir.to_string_lossy().into_owned(), "<app>"),
            (workspace.to_string_lossy().into_owned(), "<workspace>"),
            (home.to_string_lossy().into_owned(), "<home>"),
            (working.to_string_lossy().into_owned(), "<coord>"),
        ],
    )?;
    if stage.is_file() {
        let value = fs::read_to_string(&stage)?;
        if value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'.' | b'-'))
        {
            fs::write(output.join("wait-events-stage.txt"), value)?;
        }
    }

    let fixture_result = fixture.stop(requests_file);
    drop(fixture);
    write_fixture_log(fixture_log, &output.join("fixture.log"))?;
    let requests = if requests_file.is_file() {
        sanitize_requests(requests_file, &output.join("requests.json"))?;
        serde_json::from_slice::<Vec<serde_json::Value>>(&fs::read(requests_file)?)?
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
    let notes: Vec<String> = requests
        .iter()
        .filter_map(|row| {
            row.pointer("/diagnostic/category")
                .and_then(serde_json::Value::as_str)
                .map(str::to_owned)
        })
        .collect();
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "wait-events",
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "notes": notes,
            "completed": fixture_result.as_ref().is_ok_and(|status| status.success()),
        }))?,
    )?;
    let errors = if gui_log_path.is_file() {
        count_gui_errors(&gui_log_path)?
    } else {
        0
    };
    fs::write(
        output.join("gui-health.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "unhandledErrors": errors, "humanVerdict": "pending"
        }))?,
    )?;
    println!("Evidence: {} (human verdict pending)", output.display());
    journey?;
    // Child-report uniqueness is proven on the fixture model-request boundary
    // (`child_report_once` / `child_report_still_once`), not inferred from Timeline.
    let missing: Vec<&'static str> = REQUIRED_NOTES
        .iter()
        .copied()
        .filter(|note| !notes.iter().any(|observed| observed == note))
        .collect();
    ensure!(
        missing.is_empty(),
        "wait-events fixture missed required notes: {missing:?}"
    );
    let unexpected: Vec<&str> = notes
        .iter()
        .map(String::as_str)
        .filter(|note| {
            matches!(
                *note,
                "child_report_missing"
                    | "child_report_duplicate"
                    | "child_report_dropped"
                    | "child_report_duplicated_later"
                    | "wait_events_unknown_prompt"
                    | "already_ready_task_missing"
                    | "cancel_sleep_task_missing"
                    | "child_marker_on_parent"
            )
        })
        .collect();
    ensure!(
        unexpected.is_empty(),
        "wait-events fixture recorded unexpected notes: {unexpected:?}"
    );
    let summary: serde_json::Value = serde_json::from_slice(
        &fs::read(output.join("wait-events-summary.json"))
            .context("Flutter Driver did not write the wait-events journey summary")?,
    )?;
    ensure!(
        summary["scenario"] == "wait-events" && summary["verdict"] == "pending",
        "wait-events journey summary is missing its scenario or pending verdict"
    );
    let checks = summary["checks"]
        .as_object()
        .context("wait-events journey summary has no checks")?;
    for (name, value) in checks {
        ensure!(
            value == &serde_json::Value::Bool(true),
            "wait-events journey check {name} did not pass"
        );
    }
    ensure!(!checks.is_empty(), "wait-events journey recorded no checks");
    ensure!(
        fixture_result.is_ok_and(|status| status.success()) && rejected == 0 && errors == 0,
        "wait-events fixture or GUI health incomplete; human verdict pending"
    );
    Ok(())
}

fn start_wait_events_driver(
    app_dir: &Path,
    home: &Path,
    vm_url: &str,
    project: &Path,
    output: &Path,
    working: &Path,
    stage: &Path,
) -> Result<OwnedProcess> {
    let log = File::create(stage.with_extension("driver.log"))?;
    let mut command = driver_command(app_dir, "test_driver/wait_events_journey.dart");
    command
        .arg(vm_url)
        .arg(project)
        .arg(output)
        .arg(working)
        .env("ANYWORK_HOME", home)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    OwnedProcess::start(&mut command, false)
}
