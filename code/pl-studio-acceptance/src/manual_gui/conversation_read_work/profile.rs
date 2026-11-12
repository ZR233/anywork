//! Opt-in native Profile samples; the ordinary integration lane never enters here.
//!
//! Seed/audit/build/VM discovery are preparation, not timers. Only the product
//! owner's selection -> first nonempty content layout span is admitted.

use super::*;
use serde_json::{Value, json};

mod identity;
mod report;
mod seed;

use report::{Group, SAMPLES};

#[derive(Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct ToolEvidence {
    command: Vec<String>,
    exit_status: Option<String>,
    forced_recovery: bool,
    errors: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AppEvidence {
    name: String,
    mode: String,
    launcher_pid: Option<u32>,
    launcher_exit_status: Option<String>,
    native_pid: Option<u64>,
    probe: Option<Value>,
    artifacts: Option<Value>,
    native_exit: Option<Value>,
    exit_request: Option<ToolEvidence>,
    probe_process: Option<ToolEvidence>,
    forced_recovery: bool,
    errors: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ProfileEvidence {
    finalized: bool,
    source_before: Option<Value>,
    source_after: Option<Value>,
    environment: Option<Value>,
    seeds: Vec<seed::Inventory>,
    applications: Vec<AppEvidence>,
    cold: Group,
    switches: Group,
    errors: Vec<String>,
}

impl ProfileEvidence {
    fn save(&self, output: &Path) -> Result<()> {
        let cold = self.cold.summary();
        let switches = self.switches.summary();
        let target_met =
            self.finalized && self.errors.is_empty() && cold.meets_target && switches.meets_target;
        write_json(
            &output.join("profile-read-report.json"),
            &json!({
                "schemaVersion": 1,
                "scenario": "conversation-read-work",
                "runner": "native-profile-owner-layout",
                "platform": {"os": env::consts::OS, "arch": env::consts::ARCH},
                "flutterBuildMode": "profile",
                "seedRequirements": {"threads": 2, "minimumMainItemsPerThread": 20_000},
                "freshApplicationLaunchesRequested": 21,
                "artifactPolicy": "all started applications must have the same actual native and packaged bridge Git blob identities",
                "timing": "same owner monotonic selectionStartedMicros -> layoutCompletedMicros",
                "statistics": {
                    "units": "microseconds",
                    "p50": "median",
                    "p95": "nearest rank ceil(0.95*n)",
                    "target": "both groups require 20 successes and p95 <= 500000",
                    "switchSample": "A return span; B span retained in viaOtherThread, never summed",
                },
                "excludedFromTiming": ["seed", "read-model preparation", "inventory audit", "build", "VM readiness", "RPC polling", "shutdown"],
                "pageCache": "uncontrolled; fresh App processes do not imply physical cold cache",
                "failurePolicy": "fail fast after recording the failed application; remaining slots stay notExecuted",
                "otherMetrics": {
                    "viewportFillAndEof": "notMeasured",
                    "physicalDiskIo": "notMeasured",
                    "buildRaster": "notMeasured"
                },
                "sourceBefore": self.source_before,
                "sourceAfter": self.source_after,
                "environment": self.environment,
                "seed": self.seeds,
                "applications": self.applications,
                "cold": {"summary": cold, "samples": self.cold.samples},
                "switch": {"summary": switches, "samples": self.switches.samples},
                "errors": self.errors,
                "completed": target_met,
                "targetMet": target_met,
            }),
        )
    }
}

pub(super) fn run(context: &ConversationReadWorkScenario<'_>) -> Result<()> {
    let mut evidence = ProfileEvidence {
        finalized: false,
        source_before: None,
        source_after: None,
        environment: None,
        seeds: Vec::new(),
        applications: Vec::new(),
        cold: Group::new("cold"),
        switches: Group::new("switch"),
        errors: Vec::new(),
    };
    // A seed/startup failure must still leave the full requested sample denominator.
    evidence.save(context.output)?;
    let primary = (|| -> Result<()> {
        evidence.source_before = Some(identity::source(context, "before")?);
        evidence.environment = Some(identity::environment(context)?);
        seed::run(context, &mut evidence.seeds)?;
        evidence.save(context.output)?;
        let a = evidence.seeds[0]
            .thread_id
            .clone()
            .context("missing seed A")?;
        let b = evidence.seeds[1]
            .thread_id
            .clone()
            .context("missing seed B")?;
        ensure!(a != b, "profile seeds reused the same Thread");
        let project = evidence.seeds[0]
            .project_id
            .clone()
            .context("missing seed project")?;
        ensure!(
            evidence.seeds[1].project_id.as_deref() == Some(project.as_str()),
            "profile seeds must belong to the same project"
        );
        for index in 0..SAMPLES {
            let mut app = run_app(
                context,
                &format!("cold-{:02}", index + 1),
                "cold",
                &a,
                &b,
                &project,
                1,
            );
            let fixed = require_fixed_artifacts(&evidence.applications, &app);
            record(&mut app.errors, "fixed application artifacts", fixed);
            admit_samples(&mut evidence.cold, index, 1, &mut app, &a);
            let failed = !app.errors.is_empty();
            evidence.errors.extend(app.errors.iter().cloned());
            evidence.applications.push(app);
            evidence.save(context.output)?;
            ensure!(!failed, "cold sample {} failed", index + 1);
        }
        let mut app = run_app(context, "switch", "switch", &a, &b, &project, SAMPLES);
        let fixed = require_fixed_artifacts(&evidence.applications, &app);
        record(&mut app.errors, "fixed application artifacts", fixed);
        admit_samples(&mut evidence.switches, 0, SAMPLES, &mut app, &a);
        let failed = !app.errors.is_empty();
        evidence.errors.extend(app.errors.iter().cloned());
        evidence.applications.push(app);
        evidence.save(context.output)?;
        ensure!(!failed, "switch samples failed");
        ensure!(
            evidence.cold.summary().meets_target && evidence.switches.summary().meets_target,
            "complete cold/switch sample distributions did not meet p95 <= 500 ms"
        );
        Ok(())
    })();
    record(&mut evidence.errors, "profile sampling", primary);

    // Even a failed seed or sample gets a final source check and a partial report.
    evidence.source_after = record(
        &mut evidence.errors,
        "final source identity",
        identity::source(context, "after"),
    );
    if let (Some(before), Some(after)) = (&evidence.source_before, &evidence.source_after)
        && before != after
    {
        evidence
            .errors
            .push("source changed during profile sampling".into());
    }
    evidence.finalized = true;
    let saved = evidence.save(context.output);
    record(&mut evidence.errors, "save final profile report", saved);
    println!("native Profile evidence: {}", context.output.display());
    require_no_errors(&evidence.errors)
}

fn admit_samples(
    group: &mut Group,
    offset: usize,
    requested: usize,
    app: &mut AppEvidence,
    thread: &str,
) {
    if let Some(raw) = &app.probe {
        record(
            &mut app.errors,
            "validate probe owner spans",
            group.ingest(raw, offset, requested, thread),
        );
    }
    if !app.errors.is_empty() {
        // Retain validated observations, and never turn missing/invalid samples
        // into zero-duration observations.
        group.fail_unexecuted(offset, thread, app.errors.join("\n"));
    }
}

fn require_fixed_artifacts(previous: &[AppEvidence], current: &AppEvidence) -> Result<()> {
    if current.launcher_pid.is_none() {
        return Ok(());
    }
    let actual = current
        .artifacts
        .as_ref()
        .context("started application has no artifact identity")?;
    identity::require_same_artifacts(actual, actual)?;
    for earlier in previous.iter().filter(|app| app.launcher_pid.is_some()) {
        let expected = earlier
            .artifacts
            .as_ref()
            .context("earlier application has no artifact identity")?;
        identity::require_same_artifacts(expected, actual).with_context(|| {
            format!(
                "artifacts differ between {} and {}",
                earlier.name, current.name
            )
        })?;
    }
    Ok(())
}

fn run_app(
    context: &ConversationReadWorkScenario<'_>,
    name: &str,
    mode: &str,
    a: &str,
    b: &str,
    project: &str,
    requested: usize,
) -> AppEvidence {
    let directory = context.output.join(format!("profile-{name}"));
    let raw_directory = context.working.join(format!("profile-{name}"));
    let mut evidence = AppEvidence {
        name: name.into(),
        mode: mode.into(),
        launcher_pid: None,
        launcher_exit_status: None,
        native_pid: None,
        probe: None,
        artifacts: None,
        native_exit: None,
        exit_request: None,
        probe_process: None,
        forced_recovery: false,
        errors: Vec::new(),
    };
    if record(
        &mut evidence.errors,
        "create application evidence directory",
        fs::create_dir_all(&directory).with_context(|| {
            format!(
                "create application evidence directory {}",
                directory.display()
            )
        }),
    )
    .is_none()
    {
        return evidence;
    }
    if record(
        &mut evidence.errors,
        "create raw application log directory",
        fs::create_dir_all(&raw_directory).with_context(|| {
            format!(
                "create raw application log directory {}",
                raw_directory.display()
            )
        }),
    )
    .is_none()
    {
        return evidence;
    }
    let gui_log = raw_directory.join("gui.log");
    let native_exit = directory.join("native-exit.json");
    let Some(mut gui) = record(
        &mut evidence.errors,
        "start fresh native Profile application",
        start_timeline_history_gui(
            context.workspace,
            context.home,
            &gui_log,
            &native_exit,
            true,
        ),
    ) else {
        return evidence;
    };
    evidence.launcher_pid = Some(gui.child.id());
    let vm = record(
        &mut evidence.errors,
        "wait for native VM",
        wait_for_profile_vm(&gui_log, &mut gui, context.interrupt),
    );
    if let Some(vm) = &vm {
        evidence.artifacts = record(
            &mut evidence.errors,
            "built native/bridge identity",
            identity::artifacts(context, &directory),
        );
        let output = raw_directory.join("probe.json");
        let mut command = Command::new("cargo");
        command
            .current_dir(context.workspace)
            .args([
                "dart",
                "--packages=.dart_tool/package_config.json",
                "tool/profile_timeline_probe.dart",
                "--vm-url",
            ])
            .arg(websocket_url(vm))
            .args([
                "--project-id",
                project,
                "--thread-id",
                a,
                "--mode",
                mode,
                "--samples",
            ])
            .arg(requested.to_string())
            .arg("--output")
            .arg(&output);
        if mode == "switch" {
            command.args(["--other-thread-id", b]);
        }
        let tool = run_tool(
            &mut command,
            &directory,
            "probe",
            context.interrupt,
            // The CLI bounds every connection/span at 30 s. This outer process
            // deadline also covers cleanup and a failed-to-exit probe.
            Duration::from_secs(if mode == "switch" { 1_500 } else { 180 }),
            Some(&mut gui),
            Some(&raw_directory),
        );
        evidence.errors.extend(
            tool.errors
                .iter()
                .map(|error| format!("{name} probe: {error}")),
        );
        evidence.probe_process = Some(tool);
        let probe = record(
            &mut evidence.errors,
            "read probe JSON (partial evidence required on CLI failure)",
            read_json(&output),
        );
        if let Some(probe) = probe {
            if probe["completed"] != true {
                evidence
                    .errors
                    .push(redact_loopback_urls(&format!("probe incomplete: {probe}")));
            }
            let mut sanitized = probe;
            sanitize_probe_strings(&mut sanitized);
            record(
                &mut evidence.errors,
                "save sanitized probe JSON",
                write_json(&directory.join("probe.json"), &sanitized),
            );
            evidence.probe = Some(sanitized);
        }

        // Normal product close first. Driver/VM disconnection is not application exit.
        if let Some(mut close) = record(
            &mut evidence.errors,
            "prepare product exit command",
            capture_command(&context.workspace.join("code/anywork")),
        ) {
            close.args(["--vm-url", vm, "--exit"]);
            let tool = run_tool(
                &mut close,
                &directory,
                "request-exit",
                context.interrupt,
                Duration::from_secs(45),
                None,
                Some(&raw_directory),
            );
            evidence.errors.extend(
                tool.errors
                    .iter()
                    .map(|error| format!("{name} requestExit: {error}")),
            );
            evidence.exit_request = Some(tool);
        }
        if let Some(status) = record(
            &mut evidence.errors,
            "wait for actual GUI OS exit",
            wait_for_gui_exit(&mut gui, Duration::from_secs(30), name),
        ) {
            evidence.launcher_exit_status = Some(status.to_string());
            if !status.success() {
                evidence
                    .errors
                    .push(format!("native launcher exited unsuccessfully: {status}"));
            }
        }
    }

    if !gui.stopped {
        evidence.forced_recovery = true;
        evidence
            .errors
            .push("GUI required fallback process recovery; not a clean product exit".into());
        if let Some(status) = record(
            &mut evidence.errors,
            "GUI fallback stop/join",
            gui.stop(&native_exit),
        ) {
            evidence.launcher_exit_status = Some(status.to_string());
        }
        if !gui.stopped {
            force_reap(&mut gui, &mut evidence.errors);
        }
    }
    record(
        &mut evidence.errors,
        "native exit/descendant validation",
        require_native_exit(&native_exit, None),
    );
    evidence.native_exit = record(
        &mut evidence.errors,
        "read native exit evidence",
        read_json(&native_exit),
    );
    evidence.native_pid = evidence
        .native_exit
        .as_ref()
        .and_then(|report| report["pid"].as_u64());
    record(
        &mut evidence.errors,
        "save sanitized GUI log",
        write_driver_log(&gui_log, &directory.join("gui.log")),
    );
    evidence
}

fn wait_for_profile_vm(
    log: &Path,
    gui: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
) -> Result<String> {
    let deadline = Instant::now() + Duration::from_secs(900);
    loop {
        if let Some(status) = gui.exit_status()? {
            bail!("native Profile launcher exited before VM discovery: {status}");
        }
        ensure!(
            interrupt.try_recv().is_err(),
            "native Profile startup cancelled"
        );
        if let Some(url) = vm_service_url(&fs::read_to_string(log)?) {
            return Ok(url);
        }
        ensure!(
            Instant::now() < deadline,
            "native Profile VM startup timed out"
        );
        thread::sleep(Duration::from_millis(100));
    }
}

fn websocket_url(http: &str) -> String {
    format!(
        "ws://{}/ws",
        http.trim_start_matches("http://").trim_end_matches('/')
    )
}

/// Bounded tool ownership, with every forced stop retained as a failure. GUI
/// monitoring is for probes only, not for the tool that requests product exit.
fn run_tool(
    command: &mut Command,
    directory: &Path,
    label: &str,
    interrupt: &mpsc::Receiver<()>,
    timeout: Duration,
    mut gui: Option<&mut OwnedProcess>,
    raw_directory: Option<&Path>,
) -> ToolEvidence {
    let mut evidence = ToolEvidence {
        command: safe_command(command),
        ..ToolEvidence::default()
    };
    let setup = (|| -> Result<OwnedProcess> {
        fs::create_dir_all(directory)?;
        let logs = raw_directory.unwrap_or(directory);
        fs::create_dir_all(logs)?;
        command.stdout(Stdio::from(File::create(
            logs.join(format!("{label}.stdout.log")),
        )?));
        command.stderr(Stdio::from(File::create(
            logs.join(format!("{label}.stderr.log")),
        )?));
        OwnedProcess::start(command, false)
    })();
    if let Some(mut tool) = record(&mut evidence.errors, "spawn tool", setup) {
        let result = (|| -> Result<ExitStatus> {
            let deadline = Instant::now() + timeout;
            loop {
                if let Some(status) = tool.child.try_wait()? {
                    tool.mark_reaped();
                    return Ok(status);
                }
                if let Some(gui) = gui.as_deref_mut() {
                    ensure!(!gui.exited()?, "GUI exited while probe was active");
                }
                ensure!(interrupt.try_recv().is_err(), "tool cancelled");
                ensure!(
                    Instant::now() < deadline,
                    "tool timed out after {timeout:?}"
                );
                thread::sleep(Duration::from_millis(100));
            }
        })();
        if let Some(status) = record(&mut evidence.errors, "tool wait/join", result) {
            evidence.exit_status = Some(status.to_string());
            if !status.success() {
                evidence.errors.push(format!("tool returned {status}"));
            }
        }
        if !tool.stopped {
            evidence.forced_recovery = true;
            evidence
                .errors
                .push("tool required forced process recovery".into());
            force_reap(&mut tool, &mut evidence.errors);
        }
    }
    if let Some(raw_directory) = raw_directory {
        for stream in ["stdout", "stderr"] {
            let file = format!("{label}.{stream}.log");
            let source = raw_directory.join(&file);
            if source.is_file() {
                record(
                    &mut evidence.errors,
                    "save sanitized tool log",
                    write_driver_log(&source, &directory.join(file)),
                );
            }
        }
    }
    let saved = write_json(&directory.join(format!("{label}.process.json")), &evidence);
    record(&mut evidence.errors, "save tool process evidence", saved);
    evidence
}

fn force_reap(process: &mut OwnedProcess, errors: &mut Vec<String>) {
    if !process.request_stop() {
        errors.push("process stop request unavailable or failed".into());
    }
    if record(
        errors,
        "process stop wait",
        process.wait_exit(Duration::from_secs(10)),
    )
    .flatten()
    .is_some()
    {
        return;
    }
    if !process.kill_tree() {
        errors.push("forced process tree signal failed".into());
    }
    if record(
        errors,
        "forced process tree wait",
        process.wait_exit(Duration::from_secs(10)),
    )
    .flatten()
    .is_none()
    {
        errors.push(
            "process exit still unconfirmed after forced recovery; owner Drop will retry".into(),
        );
    }
}

fn record<T>(errors: &mut Vec<String>, phase: &str, result: Result<T>) -> Option<T> {
    match result {
        Ok(value) => Some(value),
        Err(error) => {
            errors.push(redact_loopback_urls(&format!("{phase}: {error:#}")));
            None
        }
    }
}

/// Keep program and non-sensitive arguments, but never Command's environment or
/// a VM endpoint. This is evidence metadata only; the actual command is untouched.
fn safe_command(command: &Command) -> Vec<String> {
    let mut description = vec![command.get_program().to_string_lossy().into_owned()];
    let mut vm_value = false;
    for argument in command.get_args() {
        let argument = argument.to_string_lossy();
        if vm_value {
            description.push("<vm-uri>".into());
            vm_value = false;
        } else if argument == "--vm-url" {
            description.push(argument.into_owned());
            vm_value = true;
        } else if argument.starts_with("--vm-url=") {
            description.push("--vm-url=<vm-uri>".into());
        } else {
            description.push(redact_loopback_urls(&argument));
        }
    }
    description
}

fn write_driver_log(source: &Path, destination: &Path) -> Result<()> {
    let raw =
        fs::read_to_string(source).with_context(|| format!("read raw log {}", source.display()))?;
    let mut sanitized = String::new();
    for line in raw.lines() {
        sanitized.push_str(&sanitize_driver_line(line, &[]));
        sanitized.push('\n');
    }
    fs::write(destination, sanitized)
        .with_context(|| format!("write sanitized log {}", destination.display()))
}

fn sanitize_probe_strings(value: &mut Value) {
    match value {
        Value::String(text) => *text = redact_loopback_urls(text),
        Value::Array(values) => values.iter_mut().for_each(sanitize_probe_strings),
        Value::Object(values) => values.values_mut().for_each(sanitize_probe_strings),
        _ => {}
    }
}

fn require_no_errors(errors: &[String]) -> Result<()> {
    ensure!(errors.is_empty(), "{}", errors.join("\n"));
    Ok(())
}

fn write_json(path: &Path, value: &impl Serialize) -> Result<()> {
    fs::write(path, serde_json::to_vec_pretty(value)?)
        .with_context(|| format!("write {}", path.display()))
}

fn read_json(path: &Path) -> Result<Value> {
    serde_json::from_slice(&fs::read(path).with_context(|| format!("read {}", path.display()))?)
        .with_context(|| format!("decode {}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_and_driver_evidence_do_not_publish_vm_auth_uri() {
        let token = "profile-secret-token";
        let uri = format!("ws://127.0.0.1:41873/{token}=/ws");
        let mut command = Command::new("cargo");
        command.args([
            "dart",
            "tool/profile_timeline_probe.dart",
            "--vm-url",
            &uri,
            "--mode",
            "cold",
        ]);
        let description = safe_command(&command);
        assert_eq!(description[3..], ["--vm-url", "<vm-uri>", "--mode", "cold"]);
        assert!(!description.join(" ").contains(token));
        let raw = format!("Driver connected to {uri}; sample failed");
        let sanitized = sanitize_driver_line(&raw, &[]);
        assert!(sanitized.contains("sample failed"));
        assert!(!sanitized.contains(token));
        let mut report = json!({"failure": raw, "elapsedMicros": 500_001, "completed": false});
        sanitize_probe_strings(&mut report);
        assert!(!report.to_string().contains(token));
        assert_eq!(report["elapsedMicros"], 500_001);
        assert_eq!(report["completed"], false);
    }
}
