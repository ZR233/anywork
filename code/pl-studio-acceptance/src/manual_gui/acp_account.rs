//! Antigravity ACP account acceptance through the real native GUI.
//!
//! One isolated Studio home and one fake ACP Agent state directory are opened by
//! three GUI lifecycles. The first adds the account through "Add account" →
//! Antigravity template → program/args → "Save and connect", proves the
//! connection reports "login required", waits for the fake Agent to announce the
//! real `authenticate` request, sees the release control file finish that wait,
//! and re-checks the verified account. The second reopens the exact same home
//! with the same fake credential to prove the saved config and a fresh check.
//! The third withdraws the fake credential to observe an authentication failure,
//! a cancelled login, a delete/rebuild and a shutdown that cancels an active
//! login.
//!
//! The HTTP provider fixture of the other scenarios is never started here: this
//! phase has no HTTP model step at all, so an unexercised fixture main flow can
//! never be reported as acceptance. Evidence is the product's own saved config,
//! the fake Agent's typed protocol log (ordered, per PID), real PNG screenshot
//! headers with their file times, the Driver captures, and the existing
//! `--native-launch` process-tree record of the real native host.
//!
//! Process ownership is delegated to the existing owner instead of a local
//! `/proc` scanner: `cargo xtask run-gui --driver --native-launch
//! --native-exit-report <file>` launches the native artifact directly, keeps the
//! VM service, and writes the typed `anywork-native-exit/1` record that covers
//! independent process groups and descendants adopted by its subreaper. That
//! record — never the `cargo` wrapper exit code — decides whether the native tree
//! shut down cleanly.
//!
//! The Driver journey (`test_driver/acp_account_journey.dart`) is started with the
//! shared positional contract (`VM_URL OUTPUT_DIR FIXTURE_PROGRAM
//! FIXTURE_STATE_DIR`) and the current lifecycle in `ANYWORK_ACCEPTANCE_ACP_PHASE`.
//! It must write `acp-account-summary-<phase>.json` with `scenario`, `phase`,
//! `verdict`, `status`, `stage`, `shutdown`, an empty `failedChecks` array and one
//! `captures` entry per observed stage (`name`, `file`, `screenshot`), so a
//! journey that stops early fails here instead of producing a partial pass.

use super::*;
use pl_provider_fixture::{
    ACP_AUTH_RELEASE_MARKER, ACP_AUTH_STARTED_MARKER, ACP_AUTHENTICATED_MARKER, ACP_BEHAVIOR_FILE,
    ACP_EVENTS_FILE, AcpFixtureAuthentication, AcpFixtureBehavior, AcpFixtureEvent,
    AcpFixtureProbe,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::io::Read as _;

/// Fake credential store and Agent control directory owned by this scenario.
const STATE_DIR_NAME: &str = "acp-state";
/// Harness→Driver channel for the current lifecycle.
///
/// The journey's four positional arguments are frozen by the shared contract
/// (`VM_URL OUTPUT_DIR FIXTURE_PROGRAM FIXTURE_STATE_DIR`), so the lifecycle is
/// selected additively and never by reordering or appending an argument.
const PHASE_ENV: &str = "ANYWORK_ACCEPTANCE_ACP_PHASE";
/// Frozen provider identity value of the ACP config document.
const PROVIDER: &str = "antigravity";
/// The only schema this harness trusts as the native process-tree record.
const NATIVE_EXIT_SCHEMA: &str = "anywork-native-exit/1";
/// One bounded observation window while a graceful stop is pending.
///
/// A window expiring is a *pending* cleanup diagnosis, never a reason to kill the
/// supervisor or to leave the owner: the caller keeps the handle in the current
/// stack frame, records partial evidence and requests the stop again.
const CLEANUP_WINDOW: Duration = Duration::from_secs(30);
/// Every key the frozen `anywork-native-exit/1` schema must contain. `serde`'s
/// `Option` fields tolerate a missing key, so presence is checked explicitly
/// before the typed decode instead of being inferred from the type.
const NATIVE_EXIT_FIELDS: [&str; 9] = [
    "schema",
    "pid",
    "exitCode",
    "signal",
    "status",
    "elapsedMillis",
    "descendantsAtRootExit",
    "reclaimedDescendants",
    "cancelled",
];
/// Fields a native HTTP account carries. An ACP account must never gain them.
const NATIVE_ONLY_FIELDS: [&str; 6] = [
    "base_url",
    "bearer_token",
    "bearer_token_env",
    "api_key",
    "models",
    "template",
];

pub(super) struct AcpAccountScenario<'a> {
    pub workspace: &'a Path,
    pub app_dir: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    /// Cargo-resolved absolute path of the existing `pl-provider-fixture` binary,
    /// which is this phase's fake ACP Agent peer.
    pub fixture_program: &'a Path,
    pub interrupt: &'a mpsc::Receiver<()>,
}

/// One GUI lifecycle and the facts it must really produce.
struct PhaseSpec {
    phase: &'static str,
    /// `behavior.json` authentication mode the lifecycle starts in.
    authentication: AcpFixtureAuthentication,
    probe: AcpFixtureProbe,
    /// Whether the fake credential persisted by the previous lifecycle survives.
    credential_present: bool,
    /// Captures the Driver summary must contain, each with a real screenshot.
    required_captures: &'static [&'static str],
    /// Normalized ACP requests this lifecycle must really issue.
    required_methods: &'static [&'static str],
    /// Normalized ACP requests this lifecycle must not issue.
    forbidden_methods: &'static [&'static str],
}

const PHASES: [PhaseSpec; 3] = [
    PhaseSpec {
        phase: "first",
        authentication: AcpFixtureAuthentication::Wait,
        probe: AcpFixtureProbe::Normal,
        credential_present: false,
        required_captures: &[
            "accounts-empty",
            "antigravity-template",
            "antigravity-form",
            "required",
            "authenticating",
            "verified",
            "recheck-verified",
        ],
        required_methods: &["initialize", "authenticate", "sessionnew"],
        forbidden_methods: &["prompt"],
    },
    PhaseSpec {
        phase: "restart",
        authentication: AcpFixtureAuthentication::Success,
        probe: AcpFixtureProbe::Normal,
        credential_present: true,
        required_captures: &["persisted-account", "recheck-verified"],
        required_methods: &["initialize", "sessionnew"],
        forbidden_methods: &["authenticate", "prompt"],
    },
    PhaseSpec {
        phase: "faults",
        authentication: AcpFixtureAuthentication::Fail,
        probe: AcpFixtureProbe::Normal,
        credential_present: false,
        required_captures: &["authentication-failed", "cancelled"],
        required_methods: &["initialize", "authenticate"],
        forbidden_methods: &["prompt"],
    },
];

pub(super) fn run(context: &AcpAccountScenario<'_>) -> Result<()> {
    let state = context.working.join(STATE_DIR_NAME);
    fs::create_dir_all(&state)?;
    let program = context.fixture_program.canonicalize().with_context(|| {
        format!(
            "the fake ACP Agent executable is missing: {}",
            context.fixture_program.display()
        )
    })?;
    ensure!(
        program.is_file(),
        "the fake ACP Agent executable is not a regular file: {}",
        program.display()
    );
    let program_text = program
        .to_str()
        .context("the fake ACP Agent path is not valid UTF-8")?
        .to_owned();
    let state_text = state
        .to_str()
        .context("the fake ACP state directory is not valid UTF-8")?
        .to_owned();

    // The UI must prove the add flow itself: nothing may be pre-seeded, neither a
    // saved ACP account nor a fake login in the credential store.
    ensure!(
        !state.join(ACP_AUTHENTICATED_MARKER).exists(),
        "the fake ACP credential store already holds a login; the journey must start logged out"
    );
    let existing = acp_accounts(context.home)?;
    ensure!(
        existing.as_ref().is_none_or(|table| table.is_empty()),
        "the isolated home already contains a saved ACP account before the journey started"
    );

    let redactions = vec![
        (state_text.clone(), "[acp-state]"),
        (program_text.clone(), "[fixture-program]"),
        (
            context.working.to_string_lossy().into_owned(),
            "[isolated-root]",
        ),
        (context.home.to_string_lossy().into_owned(), "[home]"),
        (
            context.workspace.to_string_lossy().into_owned(),
            "[workspace]",
        ),
    ];

    let mut phases: Vec<Value> = Vec::new();
    let mut lifecycles: Vec<Value> = Vec::new();
    let mut cleanups: Vec<Value> = Vec::new();
    let mut screenshots: Vec<Value> = Vec::new();
    let mut events: Vec<AcpFixtureEvent> = Vec::new();

    let journey = (|| -> Result<()> {
        for spec in &PHASES {
            prepare_phase(spec, &state)?;
            let events_before = read_events(&state)?.len();
            let accounts_before = acp_accounts(context.home)?;
            fs::write(
                context
                    .output
                    .join(format!("acp-account-config-{}-before.json", spec.phase)),
                serde_json::to_vec_pretty(&sanitized_acp_config(&accounts_before))?,
            )?;

            let phase_run = run_phase(
                context,
                spec,
                &state,
                &program_text,
                &state_text,
                &mut cleanups,
            )?;

            let current = read_events(&state)?;
            ensure!(
                current.len() >= events_before,
                "the fake ACP Agent rewrote its typed evidence during the {} lifecycle",
                spec.phase
            );
            let delta = &current[events_before..];
            assert_phase_events(spec, delta)?;

            if spec.phase == "first" {
                ensure!(
                    state.join(ACP_AUTHENTICATED_MARKER).is_file(),
                    "the fake Agent did not persist its credential after the login"
                );
            }
            if spec.credential_present {
                ensure!(
                    state.join(ACP_AUTHENTICATED_MARKER).is_file(),
                    "the fake credential persisted by the previous lifecycle was lost across the reopen"
                );
            } else if spec.phase == "faults" {
                ensure!(
                    !state.join(ACP_AUTHENTICATED_MARKER).is_file(),
                    "the failed or cancelled login persisted a fake credential"
                );
            }

            let accounts_after = acp_accounts(context.home)?;
            let saved = accounts_after
                .as_ref()
                .context("no saved ACP account exists after the journey")?;
            ensure!(
                saved.len() == 1,
                "expected exactly one saved ACP account, found {}",
                saved.len()
            );
            let (account_id, account) = saved
                .iter()
                .next()
                .context("saved ACP account is missing")?;
            let account = account
                .as_table()
                .with_context(|| format!("saved ACP account `{account_id}` is not a table"))?;
            assert_acp_account(account, &program_text, &state_text)?;
            // The fault lifecycle deliberately deletes and rebuilds the row, so its
            // identity may change; the reopened lifecycle must not change anything.
            if spec.phase == "restart" {
                ensure!(
                    accounts_before.as_ref() == accounts_after.as_ref(),
                    "reopening the same isolated home changed the saved ACP account"
                );
            }
            let rebuild = json!({
                "idBefore": accounts_before.as_ref().and_then(first_account_identity).map(|(id, _)| id),
                "nameBefore": accounts_before.as_ref().and_then(first_account_identity).map(|(_, name)| name),
                "idAfter": Some(account_id.clone()),
                "nameAfter": account.get("name").and_then(toml::Value::as_str).map(str::to_owned),
                "identityChanged": accounts_before.as_ref().and_then(first_account_identity).map(|(id, _)| id)
                    .is_some_and(|before| before != *account_id),
            });
            fs::write(
                context
                    .output
                    .join(format!("acp-account-config-{}-after.json", spec.phase)),
                serde_json::to_vec_pretty(&sanitized_acp_config(&accounts_after))?,
            )?;

            let (summary, reached, captured) =
                validate_journey_summary(context.output, spec.phase, spec.required_captures)?;
            let wait_window = if spec.phase == "first" {
                Some(assert_capture_within_wait(
                    spec.phase,
                    &captured,
                    &phase_run.observation,
                    context.output,
                )?)
            } else {
                None
            };
            screenshots.extend(captured.iter().cloned());
            let request_counts = method_counts(&normalized_methods(delta));
            let behavior_after = read_behavior(&state)?
                .as_ref()
                .map(serde_json::to_value)
                .transpose()?;
            let authentication = serde_json::to_value(spec.authentication)?;
            let probe = serde_json::to_value(spec.probe)?;

            phases.push(json!({
                "phase": spec.phase,
                "authentication": authentication,
                "probe": probe,
                "credentialPresentAtStart": spec.credential_present,
                "behaviorAfterLifecycle": behavior_after,
                "guiLauncherPid": phase_run.gui_pid,
                "driverLauncherPid": phase_run.driver_pid,
                "guiLauncherExit": phase_run.gui_exit.to_string(),
                "driverExit": phase_run.driver_exit.to_string(),
                "native": &phase_run.native,
                "authenticateObservedAt": phase_run.observation.auth_started.map(epoch_seconds),
                "authReleaseObservedAt": phase_run.observation.auth_release.map(epoch_seconds),
                "requests": normalized_methods(delta),
                "requestCounts": request_counts,
                "waitWindow": wait_window,
                "reachedStage": summary["stage"].clone(),
                "captureNames": reached,
                "captures": captured,
                "savedAccountCount": saved.len(),
                "rebuild": rebuild,
                "config": sanitized_acp_config(&accounts_after),
            }));
            lifecycles.push(json!({
                "phase": spec.phase,
                "guiLauncherPid": phase_run.gui_pid,
                "driverLauncherPid": phase_run.driver_pid,
                "guiLauncherExit": phase_run.gui_exit.to_string(),
                "nativeStatus": phase_run.native["status"].clone(),
                "nativeExitCode": phase_run.native["exitCode"].clone(),
                "nativeReclaimedDescendants": phase_run.native["reclaimedDescendants"].clone(),
                "shutdown": "completed",
                "recordedAt": epoch_seconds(SystemTime::now()),
            }));
        }
        Ok(())
    })();

    // Refresh the fake Agent's accepted evidence after every phase, including a
    // failed journey: an earlier successful phase must never be presented as the
    // whole record, and a read failure is reported instead of being hidden.
    let events_error = match read_events(&state) {
        Ok(refreshed) => {
            events = refreshed;
            None
        }
        Err(error) => Some(error.to_string()),
    };

    // Evidence must survive a failed journey, and the final status may not claim
    // success while any check or evidence write failed.
    let mut gui_errors: Option<usize> = None;
    let evidence = (|| -> Result<()> {
        for spec in &PHASES {
            let gui_log = context
                .working
                .join(format!("acp-account-{}-gui.log", spec.phase));
            let driver_log = context
                .working
                .join(format!("acp-account-{}-driver.log", spec.phase));
            if gui_log.is_file() {
                write_acp_log(
                    &gui_log,
                    &context.output.join(format!("gui-{}.log", spec.phase)),
                    &redactions,
                )?;
            }
            if driver_log.is_file() {
                write_acp_log(
                    &driver_log,
                    &context.output.join(format!("driver-{}.log", spec.phase)),
                    &redactions,
                )?;
            }
            // The raw launcher record is the process-tree authority; keep it
            // unmodified next to the derived summary.
            let report = native_report_path(context.working, spec.phase);
            if report.is_file() {
                fs::copy(
                    &report,
                    context
                        .output
                        .join(format!("native-exit-{}.json", spec.phase)),
                )?;
            }
        }
        let mut errors = 0usize;
        for spec in &PHASES {
            let path = context
                .working
                .join(format!("acp-account-{}-gui.log", spec.phase));
            if path.is_file() {
                errors += count_gui_errors(&path)?;
            }
        }
        gui_errors = Some(errors);
        fs::write(
            context.output.join("gui-health.json"),
            serde_json::to_vec_pretty(&json!({
                "unhandledErrors": errors, "humanVerdict": "pending"
            }))?,
        )?;
        let mut lines = String::new();
        for event in &events {
            lines.push_str(&serde_json::to_string(event)?);
            lines.push('\n');
        }
        fs::write(context.output.join("acp-account-events.jsonl"), lines)?;
        fs::write(
            context.output.join("acp-account-screenshots.json"),
            serde_json::to_vec_pretty(&json!({
                "screenshots": &screenshots,
                "humanVerdict": "pending",
                "visualReview": "the harness only records real PNG sizes and file times; a human must open every image",
            }))?,
        )?;
        fs::write(
            context.output.join("acp-account-shutdown.json"),
            serde_json::to_vec_pretty(&json!({
                "lifecycles": &lifecycles,
                "unverifiedTeardowns": &cleanups,
                "nativeTreeAuthority": "anywork-native-exit/1 written by cargo xtask run-gui --native-launch",
                "humanVerdict": "pending",
            }))?,
        )?;
        Ok(())
    })();
    let evidence_error = evidence.err().map(|error| error.to_string());

    let all_methods = normalized_methods(&events);
    let prompt_requests = all_methods
        .iter()
        .filter(|method| method.contains("prompt"))
        .count();
    let account_state = acp_accounts(context.home);
    let account_ok = account_state
        .as_ref()
        .ok()
        .and_then(|accounts| accounts.as_ref())
        .is_some_and(|table| table.len() == 1);

    let mut failures = Vec::new();
    if evidence_error.is_some() {
        failures.push("evidence files could not be written".to_owned());
    }
    if events_error.is_some() {
        failures.push("the fake Agent evidence could not be refreshed".to_owned());
    }
    if prompt_requests != 0 {
        failures.push("the fake ACP Agent received a prompt request".to_owned());
    }
    if gui_errors != Some(0) {
        failures.push("the GUI did not report a clean run".to_owned());
    }
    if !account_ok {
        failures.push("the ACP account did not survive all lifecycles".to_owned());
    }
    if let Err(error) = &account_state {
        failures.push(format!("the isolated config could not be read: {error}"));
    }
    let status = if journey.is_ok() && failures.is_empty() {
        "complete"
    } else {
        "failed"
    };
    let evidence_ok = evidence_error.is_none();
    let events_ok = events_error.is_none();
    // The collection write is kept separate so it can never replace the journey's
    // own error, and so a failure there cannot leave a "complete" record behind.
    let collection = (|| -> Result<()> {
        let bytes = serde_json::to_vec_pretty(&json!({
            "scenario": "acp-account",
            "status": status,
            "error": journey.as_ref().err().map(ToString::to_string),
            "evidenceError": evidence_error,
            "eventsError": events_error,
            "failures": &failures,
            "checks": {
                "everyLifecycleCertified": journey.is_ok(),
                "nativeEvidenceWritten": evidence_ok,
                "fakeEventsRefreshed": events_ok,
                "noPromptRequests": prompt_requests == 0,
                "guiHealthy": gui_errors == Some(0),
                "singleSavedAcpAccount": account_ok,
            },
            "phases": phases,
            "unverifiedTeardowns": cleanups,
            "eventCount": events.len(),
            "requestCounts": method_counts(&all_methods),
            "promptRequests": prompt_requests,
            "acpAccountSeeded": false,
            "httpFixture": "not-started",
            "httpProviderTraffic": 0,
            "fakeAgent": {
                "program": "[fixture-program]",
                "stateDir": "[acp-state]",
                "events": "every typed request the fake ACP Agent accepted, in order and with its PID",
            },
            "nativeTreeAuthority": {
                "schema": NATIVE_EXIT_SCHEMA,
                "source": "cargo xtask run-gui --driver --native-launch --native-exit-report",
                "requires": "actual exitCode 0, no signal, cancelled=false and an empty reclaimedDescendants",
                "note": "the cargo launcher exit code alone is never a native-shutdown proof",
            },
            "platform": std::env::consts::OS,
            "humanVerdict": "pending",
            "liveOfficialLogin": "not-exercised",
            "notes": [
                "the fake Agent is the official-SDK peer driven by the product; no production fake-login switch exists",
                "screenshots and logs live only in this evidence directory and are never committed",
                "fake login success is not evidence that the official Antigravity program can authenticate",
            ],
        }))?;
        fs::write(context.output.join("acp-account-collection.json"), bytes)?;
        Ok(())
    })();

    println!(
        "Evidence: {} (human verdict pending)",
        context.output.display()
    );
    // The primary failure is reported unchanged; collecting evidence never turns a
    // failed lifecycle into a passing acceptance.
    match (journey, collection) {
        (Err(error), Err(write_error)) => Err(error.context(format!(
            "the acp-account collection record could not be written either: {write_error}"
        ))),
        (Err(error), Ok(())) => Err(error),
        (Ok(()), Err(write_error)) => {
            Err(write_error.context("the acp-account collection record could not be written"))
        }
        (Ok(()), Ok(())) => {
            if !failures.is_empty() {
                bail!("acp-account acceptance failed: {}", failures.join("; "));
            }
            Ok(())
        }
    }
}

/// Resets only this scenario's own control files and writes the next behavior.
fn prepare_phase(spec: &PhaseSpec, state: &Path) -> Result<()> {
    for marker in [ACP_AUTH_STARTED_MARKER, ACP_AUTH_RELEASE_MARKER] {
        remove_if_present(&state.join(marker))?;
    }
    if spec.credential_present {
        ensure!(
            state.join(ACP_AUTHENTICATED_MARKER).is_file(),
            "the {} lifecycle requires the fake credential persisted by the previous lifecycle",
            spec.phase
        );
    } else if spec.phase != "first" {
        // Withdraw only the fake credential so the next check must ask for login
        // again; the saved product config is never touched.
        remove_if_present(&state.join(ACP_AUTHENTICATED_MARKER))?;
    }
    fs::write(
        state.join(ACP_BEHAVIOR_FILE),
        serde_json::to_vec_pretty(&AcpFixtureBehavior {
            authentication: spec.authentication,
            probe: spec.probe,
            disconnect: false,
        })?,
    )?;
    Ok(())
}

fn read_behavior(state: &Path) -> Result<Option<AcpFixtureBehavior>> {
    match fs::read(state.join(ACP_BEHAVIOR_FILE)) {
        Ok(bytes) => Ok(Some(serde_json::from_slice(&bytes)?)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}

fn remove_if_present(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

/// Where `--native-launch` writes the authoritative native tree record.
fn native_report_path(working: &Path, phase: &str) -> PathBuf {
    working.join(format!("acp-account-{phase}-native-exit.json"))
}

/// The launcher's typed `anywork-native-exit/1` record.
///
/// The fields mirror the frozen schema written by `xtask`; `descendantsAtRootExit`
/// is the subtree present the moment the native host was reaped and may be
/// non-empty, while a non-empty `reclaimedDescendants` means the harness had to
/// force-kill leftovers and is therefore not a clean shutdown.
///
/// No field is defaulted: the record is proof, so a truncated document such as
/// `{"schema": …}` must fail to decode instead of silently reading as
/// "no reclaimed descendants, not cancelled". `signal`/`exitCode` stay optional in
/// type because the schema reports them as `null`; their key presence is enforced
/// by [`NATIVE_EXIT_FIELDS`] before the typed decode, because a missing key would
/// otherwise deserialize as `None`.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeExit {
    schema: String,
    pid: u32,
    exit_code: Option<i32>,
    signal: Option<i32>,
    status: String,
    elapsed_millis: u64,
    descendants_at_root_exit: Vec<u32>,
    reclaimed_descendants: Vec<u32>,
    cancelled: bool,
}

impl NativeExit {
    /// Accepts only a natural, successful native exit with nothing left behind.
    fn validate(&self, phase: &str) -> Result<()> {
        ensure!(
            self.schema == NATIVE_EXIT_SCHEMA,
            "acp-account {phase} native exit record has schema `{}`, expected `{NATIVE_EXIT_SCHEMA}`",
            self.schema
        );
        ensure!(
            self.pid > 0,
            "acp-account {phase} native exit record carries no native host pid"
        );
        ensure!(
            self.signal.is_none(),
            "acp-account {phase} native host terminated by signal {:?} (status `{}`)",
            self.signal,
            self.status
        );
        ensure!(
            !self.cancelled,
            "acp-account {phase} native host run was cancelled by the harness"
        );
        ensure!(
            self.exit_code == Some(0),
            "acp-account {phase} native host exited with {:?} (status `{}`)",
            self.exit_code,
            self.status
        );
        ensure!(
            self.reclaimed_descendants.is_empty(),
            "acp-account {phase} native host left processes behind that the harness had to reclaim: {:?}",
            self.reclaimed_descendants
        );
        Ok(())
    }

    fn to_json(&self) -> Value {
        json!({
            "schema": self.schema,
            "pid": self.pid,
            "exitCode": self.exit_code,
            "signal": self.signal,
            "status": self.status,
            "elapsedMillis": self.elapsed_millis,
            "descendantsAtRootExit": self.descendants_at_root_exit,
            "reclaimedDescendants": self.reclaimed_descendants,
            "cancelled": self.cancelled,
            "cleanShutdown": self.exit_code == Some(0)
                && self.signal.is_none()
                && !self.cancelled
                && self.reclaimed_descendants.is_empty(),
        })
    }
}

/// Reads the native record, bounded, and requires it to be complete and typed.
///
/// Presence is validated on the decoded document because a `serde` `Option`
/// field accepts a missing key as `None`; a truncated record must never pass as
/// "no signal". Values still come from the typed [`NativeExit`], never from an
/// ad-hoc reading of the raw JSON.
fn read_native_exit(path: &Path, timeout: Duration) -> Result<NativeExit> {
    let deadline = Instant::now() + timeout;
    loop {
        if let Ok(bytes) = fs::read(path) {
            let document: Value = serde_json::from_slice(&bytes).with_context(|| {
                format!("native exit record is not typed JSON: {}", path.display())
            })?;
            ensure!(
                document.is_object(),
                "native exit record is not a JSON object: {}",
                path.display()
            );
            for field in NATIVE_EXIT_FIELDS {
                ensure!(
                    document.get(field).is_some(),
                    "native exit record is missing the required `{field}` field: {}",
                    path.display()
                );
            }
            return serde_json::from_value(document).with_context(|| {
                format!(
                    "native exit record does not match {NATIVE_EXIT_SCHEMA}: {}",
                    path.display()
                )
            });
        }
        ensure!(
            Instant::now() < deadline,
            "the launcher wrote no native exit record at {}; the native shutdown is unproven",
            path.display()
        );
        thread::sleep(Duration::from_millis(50));
    }
}

/// One lifecycle's ownership result.
struct PhaseRun {
    gui_pid: u32,
    driver_pid: Option<u32>,
    gui_exit: std::process::ExitStatus,
    driver_exit: std::process::ExitStatus,
    observation: PhaseObservation,
    native: Value,
}

/// Runs one GUI lifecycle with both owners alive until the native record is read.
///
/// On any failure the still-owned launcher/driver trees are torn down with a
/// bounded signal and the observed native record (if any) is kept as evidence;
/// the original failure is always returned, so a forced teardown can never look
/// like a clean shutdown.
fn run_phase(
    context: &AcpAccountScenario<'_>,
    spec: &PhaseSpec,
    state: &Path,
    program_text: &str,
    state_text: &str,
    cleanups: &mut Vec<Value>,
) -> Result<PhaseRun> {
    let gui_log = context
        .working
        .join(format!("acp-account-{}-gui.log", spec.phase));
    let report = native_report_path(context.working, spec.phase);
    let mut gui = start_acp_gui(context.workspace, context.home, &gui_log, &report)?;
    let gui_pid = gui.child.id();
    let mut driver: Option<OwnedProcess> = None;
    let mut driver_pid: Option<u32> = None;
    let mut certified = false;
    let outcome = (|| -> Result<(PhaseObservation, std::process::ExitStatus, NativeExit)> {
        let vm_url = wait_for_acp_vm(&gui_log, &mut gui, context.interrupt)?;
        driver = Some(start_acp_driver(
            context,
            spec.phase,
            &vm_url,
            program_text,
            state_text,
        )?);
        let active = driver.as_mut().context("ACP Driver handle is missing")?;
        driver_pid = Some(active.child.id());
        let observation = wait_for_acp_driver(
            spec.phase,
            active,
            &mut gui,
            state,
            context.output,
            context.interrupt,
        )?;
        // The journey ends with a normal application shutdown through the GUI, so
        // the launcher must exit on its own; killing it would hide a hung shutdown.
        let gui_exit = wait_for_gui_exit(spec.phase, &mut gui, context.interrupt)?;
        ensure!(
            gui_exit.success(),
            "the GUI launcher exited with {gui_exit} for the acp-account {} lifecycle",
            spec.phase
        );
        // The launcher writes the record before it exits; it, not the launcher
        // status, is the authority for the real native process tree.
        let native = read_native_exit(&report, Duration::from_secs(20))?;
        native.validate(spec.phase)?;
        certified = true;
        Ok((observation, gui_exit, native))
    })();

    match outcome {
        Ok((observation, gui_exit, native)) => {
            // The native record proved the tree is gone, so Drop must not signal a
            // process group that may already belong to another process.
            gui.mark_reaped();
            if let Some(active) = driver.as_mut() {
                active.mark_reaped();
            }
            let driver_exit = observation.driver;
            drop(driver);
            drop(gui);
            Ok(PhaseRun {
                gui_pid,
                driver_pid,
                gui_exit,
                driver_exit,
                observation,
                native: native.to_json(),
            })
        }
        Err(error) => {
            if !certified {
                cleanups.push(cleanup_owned(
                    spec.phase,
                    &mut gui,
                    driver.as_mut(),
                    &report,
                    context.output,
                    context.interrupt,
                ));
            }
            drop(driver);
            drop(gui);
            Err(error)
        }
    }
}

/// Requests the supervised native owner to stop and waits for it to finish.
///
/// `--native-launch` runs the resident supervisor that owns the native process
/// tree; its SIGTERM handler cancels the children, reclaims them and still writes
/// the `anywork-native-exit/1` record. This path therefore only *asks* the owner
/// to stop: it never kills the supervisor, and every bounded window that expires
/// is recorded as a **pending** cleanup diagnosis while this stack frame keeps the
/// owner and asks again. It returns only after the launcher really exited; if it
/// cannot be collected the run simply stays pending (the operator can observe the
/// process and the partial evidence and decide), which is not a success and never
/// a normal shutdown.
fn cleanup_owned(
    phase: &str,
    gui: &mut OwnedProcess,
    mut driver: Option<&mut OwnedProcess>,
    report: &Path,
    output: &Path,
    interrupt: &mpsc::Receiver<()>,
) -> Value {
    let driver_running = driver
        .as_mut()
        .is_some_and(|active| active.child.try_wait().ok().flatten().is_none());
    // The dart Driver is plain harness tooling in the owner's own process group;
    // its existing short bounded teardown is unchanged.
    if let Some(active) = driver.as_mut() {
        active.terminate();
    }

    let mut launcher_exit = None;
    let mut last_wait_error = None;
    let mut stop_requests = 0_u32;
    let mut pending_windows = 0_u32;
    let mut cancellation_requested = false;
    let mut pending_evidence_error = None;
    let launcher_running = match gui.child.try_wait() {
        Ok(Some(status)) => {
            launcher_exit = Some(status.to_string());
            false
        }
        Ok(None) => true,
        Err(error) => {
            last_wait_error = Some(error.to_string());
            true
        }
    };
    if launcher_running {
        loop {
            // The only signal this path sends. The resident supervisor owns the
            // native tree and performs its own cancellation and reclamation.
            if gui.request_stop() {
                stop_requests += 1;
            }
            match gui.wait_exit(CLEANUP_WINDOW) {
                Ok(Some(status)) => {
                    launcher_exit = Some(status.to_string());
                    break;
                }
                Ok(None) => {}
                Err(error) => last_wait_error = Some(error.to_string()),
            }
            pending_windows += 1;
            if interrupt.try_recv().is_ok() {
                // A cancellation of this task only requests the same graceful
                // stop; the sole supervising owner is never killed from here.
                cancellation_requested = true;
            }
            // Pending cleanup: keep the owner right here, refresh what is known so
            // a long wait is visible instead of a silent hang, and ask again.
            let pending = json!({
                "phase": phase,
                "state": "pending",
                "pendingWindows": pending_windows,
                "stopRequests": stop_requests,
                "lastWaitError": last_wait_error,
                "nativeRecordPresent": report.is_file(),
                "cancellationRequested": cancellation_requested,
                "updatedAt": epoch_seconds(SystemTime::now()),
                "note": "the resident supervisor has not exited; this harness keeps the owner and only requests a stop",
            });
            if let Err(error) = write_json(
                &output.join(format!("acp-account-pending-cleanup-{phase}.json")),
                &pending,
            ) {
                pending_evidence_error = Some(error.to_string());
            }
            println!(
                "acp-account {phase} cleanup pending: window {pending_windows}, stop requests \
                 {stop_requests} (owner retained, no kill)"
            );
        }
    }
    // Reached only after the real exit, so no live owner is dropped here.
    gui.mark_reaped();
    let native = read_native_exit(report, Duration::from_secs(20));
    let (native_record, native_error) = match native {
        Ok(native) => (Some(native.to_json()), None),
        Err(error) => (None, Some(error.to_string())),
    };
    json!({
        "phase": phase,
        "forcedTeardown": true,
        "cleanupState": "collected",
        "stopRequests": stop_requests,
        "pendingWindows": pending_windows,
        "cancellationRequested": cancellation_requested,
        "launcherRunningBeforeTeardown": launcher_running,
        "driverRunningBeforeTeardown": driver_running,
        "launcherExit": launcher_exit,
        "lastWaitError": last_wait_error,
        "pendingEvidence": (pending_windows > 0)
            .then(|| format!("acp-account-pending-cleanup-{phase}.json")),
        "pendingEvidenceError": pending_evidence_error,
        "nativeRecordAfterTeardown": native_record,
        "nativeRecordMissing": native_record.is_none(),
        "nativeRecordError": native_error,
        "cleanShutdown": false,
    })
}

/// Writes one evidence document, keeping the failure (not swallowing it).
fn write_json(path: &Path, value: &Value) -> Result<()> {
    fs::write(path, serde_json::to_vec_pretty(value)?)?;
    Ok(())
}

fn start_acp_gui(
    workspace: &Path,
    home: &Path,
    log_path: &Path,
    report: &Path,
) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    command
        .current_dir(workspace)
        .args([
            "xtask",
            "run-gui",
            "--driver",
            "--native-launch",
            "--native-exit-report",
        ])
        .arg(report)
        .env("ANYWORK_HOME", home)
        // No native account exists in this home, so the product never consults a
        // system secret service; these only keep GTK/dconf caches out of the
        // operator's own directories.
        .env("XDG_DATA_HOME", home.join("xdg-data"))
        .env("XDG_CONFIG_HOME", home.join("xdg-config"))
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    // This scenario configures no native account, so no builtin MCP server may
    // pick up an operator environment key and start network work mid-journey.
    for preset in &pl_model::config::builtin_account_catalog()?.templates {
        for variable in [
            preset.credential_env.as_ref(),
            preset.account.bearer_token_env.as_ref(),
        ]
        .into_iter()
        .flatten()
        {
            command.env_remove(variable);
        }
    }
    OwnedProcess::start(&mut command, false)
}

fn wait_for_acp_vm(
    log: &Path,
    gui: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
) -> Result<String> {
    let deadline = Instant::now() + Duration::from_secs(900);
    loop {
        if let Some(url) = vm_service_url(&fs::read_to_string(log)?) {
            return Ok(url);
        }
        ensure!(
            !gui.exited()?,
            "GUI launcher exited before publishing its VM service"
        );
        ensure!(
            interrupt.try_recv().is_err(),
            "acp-account journey cancelled while starting the GUI"
        );
        ensure!(
            Instant::now() < deadline,
            "GUI VM service startup timed out"
        );
        thread::sleep(Duration::from_millis(300));
    }
}

fn start_acp_driver(
    context: &AcpAccountScenario<'_>,
    phase: &str,
    vm_url: &str,
    program: &str,
    state: &str,
) -> Result<OwnedProcess> {
    let log = File::create(
        context
            .working
            .join(format!("acp-account-{phase}-driver.log")),
    )?;
    let mut command = driver_command(context.app_dir, "test_driver/acp_account_journey.dart");
    command
        .arg(vm_url)
        .arg(context.output)
        .arg(program)
        .arg(state)
        .env("ANYWORK_HOME", context.home)
        .env(PHASE_ENV, phase)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    OwnedProcess::start(&mut command, false)
}

/// First-sighting facts for the login handshake of one lifecycle.
///
/// The markers are latched the first time each of them is observed, so a later
/// sub-scenario that rewrites or removes them cannot move the first waiter's
/// window. The recorded times are the marker files' own modification times,
/// which is when the peer created them.
struct PhaseObservation {
    auth_started: Option<SystemTime>,
    auth_release: Option<SystemTime>,
    driver: std::process::ExitStatus,
}

fn wait_for_acp_driver(
    phase: &str,
    driver: &mut OwnedProcess,
    gui: &mut OwnedProcess,
    state: &Path,
    output: &Path,
    interrupt: &mpsc::Receiver<()>,
) -> Result<PhaseObservation> {
    let deadline = Instant::now() + Duration::from_secs(900);
    let mut auth_started = None;
    let mut auth_release = None;
    loop {
        if auth_started.is_none() {
            auth_started = state_modified(&state.join(ACP_AUTH_STARTED_MARKER));
        }
        if auth_release.is_none() {
            auth_release = state_modified(&state.join(ACP_AUTH_RELEASE_MARKER));
        }
        if let Some(status) = driver.child.try_wait()? {
            ensure!(
                status.success(),
                "acp-account {phase} journey failed with {status} at stage `{}`",
                journey_stage(output, phase)
            );
            return Ok(PhaseObservation {
                auth_started,
                auth_release,
                driver: status,
            });
        }
        ensure!(
            !gui.exited()?,
            "GUI exited before the acp-account {phase} journey completed"
        );
        ensure!(
            interrupt.try_recv().is_err(),
            "acp-account {phase} journey cancelled"
        );
        ensure!(
            Instant::now() < deadline,
            "acp-account {phase} journey timed out at stage `{}`",
            journey_stage(output, phase)
        );
        thread::sleep(Duration::from_millis(100));
    }
}

fn wait_for_gui_exit(
    phase: &str,
    gui: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
) -> Result<std::process::ExitStatus> {
    let deadline = Instant::now() + Duration::from_secs(600);
    loop {
        if let Some(status) = gui.child.try_wait()? {
            // Ownership stays with the caller until the native record is read.
            return Ok(status);
        }
        ensure!(
            interrupt.try_recv().is_err(),
            "acp-account {phase} journey cancelled while the GUI was shutting down"
        );
        ensure!(
            Instant::now() < deadline,
            "the GUI did not shut down after the acp-account {phase} journey"
        );
        thread::sleep(Duration::from_millis(100));
    }
}

fn journey_stage(output: &Path, phase: &str) -> String {
    fs::read(output.join(format!("acp-account-summary-{phase}.json")))
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
        .and_then(|value| value["stage"].as_str().map(str::to_owned))
        .unwrap_or_else(|| "unknown".to_owned())
}

/// Reads the fake Agent's typed, append-only protocol evidence.
///
/// A line the Agent is still writing is skipped instead of failing the run; every
/// complete line must be one typed record, so a silent format change is visible.
fn read_events(state: &Path) -> Result<Vec<AcpFixtureEvent>> {
    let path = state.join(ACP_EVENTS_FILE);
    let text = match fs::read_to_string(&path) {
        Ok(text) => text,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error.into()),
    };
    let complete = match text.rfind('\n') {
        Some(index) => &text[..=index],
        None => "",
    };
    let mut events = Vec::new();
    for (index, line) in complete.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        events.push(
            serde_json::from_str::<AcpFixtureEvent>(line).with_context(|| {
                format!(
                    "fake ACP Agent evidence line {} is not a typed record: {}",
                    index + 1,
                    path.display()
                )
            })?,
        );
    }
    Ok(events)
}

/// The ACP request a typed record proves, in its canonical protocol spelling.
///
/// Response-less records such as a released login or a simulated disconnect are
/// not requests and can never satisfy a required sequence.
fn event_request(event: &AcpFixtureEvent) -> Option<&'static str> {
    match event {
        AcpFixtureEvent::Initialize { .. } => Some("initialize"),
        AcpFixtureEvent::Authenticate { .. } => Some("authenticate"),
        AcpFixtureEvent::SessionNew { .. } => Some("session/new"),
        AcpFixtureEvent::Close { .. } => Some("close"),
        AcpFixtureEvent::NoPrompt { .. } => Some("prompt"),
        AcpFixtureEvent::AuthenticateReleased { .. } | AcpFixtureEvent::Disconnect { .. } => None,
    }
}

fn event_pid(event: &AcpFixtureEvent) -> u32 {
    match event {
        AcpFixtureEvent::Initialize { pid }
        | AcpFixtureEvent::Authenticate { pid }
        | AcpFixtureEvent::SessionNew { pid }
        | AcpFixtureEvent::Close { pid }
        | AcpFixtureEvent::NoPrompt { pid }
        | AcpFixtureEvent::AuthenticateReleased { pid }
        | AcpFixtureEvent::Disconnect { pid, .. } => *pid,
    }
}

/// Lowercases an ACP method so `session/new` and `sessionNew` compare equally.
fn normalize_token(value: &str) -> String {
    value
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .map(|character| character.to_ascii_lowercase())
        .collect()
}

fn normalized_methods(events: &[AcpFixtureEvent]) -> Vec<String> {
    events
        .iter()
        .filter_map(event_request)
        .map(normalize_token)
        .collect()
}

fn method_counts(methods: &[String]) -> BTreeMap<String, usize> {
    let mut counts = BTreeMap::new();
    for method in methods {
        *counts.entry(method.clone()).or_insert(0) += 1;
    }
    counts
}

/// Assertions that bind one lifecycle to the typed protocol it really spoke.
///
/// A method appearing once anywhere is not enough: the successful login is a
/// single connection that must show `authenticate` → released → `session/new`,
/// which rules out "authenticate elsewhere, then claim Verified from an
/// unrelated probe". Ordering uses event positions, and identity uses the peer
/// PID, so neither another connection nor another lifecycle can stand in.
fn assert_phase_events(spec: &PhaseSpec, delta: &[AcpFixtureEvent]) -> Result<()> {
    let methods = normalized_methods(delta);
    for forbidden in spec.forbidden_methods {
        ensure!(
            !methods.iter().any(|method| method.as_str() == *forbidden),
            "the {} lifecycle issued the forbidden ACP `{}` request: {methods:?}",
            spec.phase,
            forbidden
        );
    }
    for required in spec.required_methods {
        ensure!(
            methods.iter().any(|method| method.as_str() == *required),
            "the {} lifecycle never issued the ACP `{}` request; observed {methods:?}",
            spec.phase,
            required
        );
    }
    ensure!(
        !methods.iter().any(|method| method.contains("prompt")),
        "the {} lifecycle issued an ACP prompt request",
        spec.phase
    );
    match spec.phase {
        "first" => assert_first_chain(delta),
        "restart" => assert_restart_chain(delta),
        "faults" => assert_faults_chain(delta),
        _ => Ok(()),
    }
}

/// The events after `start`, up to the next `authenticate`, i.e. one attempt.
fn attempt_window(delta: &[AcpFixtureEvent], start: usize) -> &[AcpFixtureEvent] {
    let end = delta[start + 1..]
        .iter()
        .position(|event| matches!(event, AcpFixtureEvent::Authenticate { .. }))
        .map_or(delta.len(), |offset| start + 1 + offset);
    &delta[start + 1..end]
}

fn assert_first_chain(delta: &[AcpFixtureEvent]) -> Result<()> {
    let login = delta
        .iter()
        .position(|event| matches!(event, AcpFixtureEvent::Authenticate { .. }))
        .context("the first lifecycle never sent an ACP authenticate request")?;
    let pid = event_pid(&delta[login]);
    ensure!(
        delta[..login]
            .iter()
            .any(|event| matches!(event, AcpFixtureEvent::SessionNew { .. })),
        "the first lifecycle authenticated without a preceding connection probe, so login was never actually required"
    );
    ensure!(
        delta[..login].iter().any(
            |event| matches!(event, AcpFixtureEvent::Initialize { pid: init } if *init == pid)
        ),
        "the login connection never completed an initialize handshake"
    );
    let window = attempt_window(delta, login);
    let released = window
        .iter()
        .position(|event| {
            matches!(event, AcpFixtureEvent::AuthenticateReleased { pid: released } if *released == pid)
        })
        .context("the waiting login was never released by the external control file")?;
    ensure!(
        window[released + 1..]
            .iter()
            .any(|event| matches!(event, AcpFixtureEvent::SessionNew { pid: verified } if *verified == pid)),
        "the released login was never verified by session/new on the same connection"
    );
    Ok(())
}

fn assert_restart_chain(delta: &[AcpFixtureEvent]) -> Result<()> {
    let initialized: Vec<u32> = delta
        .iter()
        .filter_map(|event| match event {
            AcpFixtureEvent::Initialize { pid } => Some(*pid),
            _ => None,
        })
        .collect();
    ensure!(
        initialized.iter().any(|pid| delta.iter().any(|event| {
            matches!(event, AcpFixtureEvent::SessionNew { pid: probe } if probe == pid)
        })),
        "the reopened lifecycle never probed a saved account on the connection it handshook"
    );
    Ok(())
}

fn assert_faults_chain(delta: &[AcpFixtureEvent]) -> Result<()> {
    let attempts = delta
        .iter()
        .enumerate()
        .filter(|(_, event)| matches!(event, AcpFixtureEvent::Authenticate { .. }))
        .map(|(index, _)| index)
        .collect::<Vec<_>>();
    ensure!(
        attempts.len() >= 2,
        "the fault lifecycle issued {} authentication attempt(s); a real failure and a real cancellation are required",
        attempts.len()
    );
    let mut failed = None;
    let mut cancelled = None;
    for attempt in attempts {
        let pid = event_pid(&delta[attempt]);
        let window = attempt_window(delta, attempt);
        let released = window
            .iter()
            .any(|event| matches!(event, AcpFixtureEvent::AuthenticateReleased { pid: released } if *released == pid));
        let verified = window
            .iter()
            .any(|event| matches!(event, AcpFixtureEvent::SessionNew { pid: session } if *session == pid));
        if let (false, false) = (released, verified) {
            failed = Some(pid);
        }
        if let (true, false) = (released, verified) {
            cancelled = Some(pid);
        }
    }
    ensure!(
        failed.is_some(),
        "no authentication attempt failed inside its own connection; the fixture failure was not observed"
    );
    ensure!(
        cancelled.is_some(),
        "no cancelled authentication was observed; a closed connection is not a cancellation"
    );
    Ok(())
}

/// Proves the Authenticating screenshot existed between the real authenticate and
/// the release that finished it.
///
/// The comparison is between the PNG's own file time and the marker files' own
/// creation times, both latched at their first sighting, so a journey that takes
/// the screenshot later (or reuses a later marker) cannot satisfy it.
fn assert_capture_within_wait(
    phase: &str,
    captured: &[Value],
    observation: &PhaseObservation,
    output: &Path,
) -> Result<Value> {
    let started = observation
        .auth_started
        .context("the first login was never observed after the fake Agent accepted authenticate")?;
    let released = observation
        .auth_release
        .context("the first login was never observed as released by the external control file")?;
    ensure!(
        started <= released,
        "the login release was written before the authenticate request was accepted"
    );
    let file = captured
        .iter()
        .find(|capture| capture["stage"] == "authenticating")
        .and_then(|capture| capture["file"].as_str())
        .context("the authenticating capture has no file")?;
    let written = fs::metadata(output.join(file))
        .and_then(|metadata| metadata.modified())
        .with_context(|| format!("the authenticating screenshot is missing: {file}"))?;
    ensure!(
        written >= started,
        "the `authenticating` screenshot predates the authenticate request the fake Agent accepted"
    );
    ensure!(
        written <= released,
        "the `authenticating` screenshot was written only after the login had already been released"
    );
    Ok(json!({
        "acceptedAt": epoch_seconds(started),
        "capturedAt": epoch_seconds(written),
        "releasedAt": epoch_seconds(released),
        "capturedWhileWaiting": true,
        "phase": phase,
    }))
}

fn state_modified(path: &Path) -> Option<SystemTime> {
    fs::metadata(path).ok()?.modified().ok()
}

fn epoch_seconds(value: SystemTime) -> u64 {
    value
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or_default()
}

/// The saved ACP accounts table, absent when the document has none.
fn acp_accounts(home: &Path) -> Result<Option<toml::Table>> {
    let file = home.join("config.toml");
    if !file.is_file() {
        return Ok(None);
    }
    let document: toml::Table = toml::from_str(&fs::read_to_string(&file)?)
        .with_context(|| format!("isolated config is not valid TOML: {}", file.display()))?;
    Ok(document
        .get("acp")
        .and_then(toml::Value::as_table)
        .and_then(|acp| acp.get("accounts"))
        .and_then(toml::Value::as_table)
        .cloned())
}

fn first_account_identity(accounts: &toml::Table) -> Option<(String, Option<String>)> {
    accounts.iter().next().map(|(id, value)| {
        (
            id.clone(),
            value
                .as_table()
                .and_then(|table| table.get("name"))
                .and_then(toml::Value::as_str)
                .map(str::to_owned),
        )
    })
}

fn assert_acp_account(account: &toml::Table, program: &str, state: &str) -> Result<()> {
    ensure!(
        account.get("provider").and_then(toml::Value::as_str) == Some(PROVIDER),
        "the saved ACP account does not select the antigravity provider: {:?}",
        account.get("provider")
    );
    ensure!(
        account
            .get("name")
            .and_then(toml::Value::as_str)
            .is_some_and(|name| !name.trim().is_empty()),
        "the saved ACP account has no visible name"
    );
    ensure!(
        account.get("program").and_then(toml::Value::as_str) == Some(program),
        "the saved ACP program is not the executable selected in the UI: {:?}",
        account.get("program")
    );
    let args = account
        .get("args")
        .and_then(toml::Value::as_array)
        .context("the saved ACP account has no args array")?;
    let args = args
        .iter()
        .map(toml::Value::as_str)
        .collect::<Option<Vec<_>>>()
        .context("the saved ACP args contain a non-string entry")?;
    ensure!(
        args == ["--acp-stdio", "--acp-state-dir", state],
        "the saved ACP args are not the typed Agent arguments: {args:?}"
    );
    for field in NATIVE_ONLY_FIELDS {
        ensure!(
            account.get(field).is_none(),
            "the saved ACP account carries the native HTTP field `{field}`"
        );
    }
    Ok(())
}

fn sanitized_acp_config(accounts: &Option<toml::Table>) -> Value {
    let Some(accounts) = accounts else {
        return json!({"present": false, "accounts": []});
    };
    let rows = accounts
        .iter()
        .map(|(account_id, value)| {
            let table = value.as_table();
            let args = table
                .and_then(|table| table.get("args"))
                .and_then(toml::Value::as_array)
                .map(|items| {
                    items
                        .iter()
                        .map(|item| match item.as_str() {
                            Some(flag) if flag.starts_with("--") => flag.to_owned(),
                            Some(_) => "[acp-path]".to_owned(),
                            None => "[non-string]".to_owned(),
                        })
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();
            json!({
                "accountId": account_id,
                "name": table.and_then(|table| table.get("name")).and_then(toml::Value::as_str),
                "provider": table.and_then(|table| table.get("provider")).and_then(toml::Value::as_str),
                "program": table.and_then(|table| table.get("program")).map(|_| "[fixture-program]"),
                "args": args,
                "nativeOnlyFields": NATIVE_ONLY_FIELDS
                    .iter()
                    .filter(|field| table.is_some_and(|table| table.contains_key(**field)))
                    .collect::<Vec<_>>(),
            })
        })
        .collect::<Vec<_>>();
    json!({"present": true, "accounts": rows})
}

/// Validates the Driver's own journey summary and the real screenshot files.
fn validate_journey_summary(
    output: &Path,
    phase: &str,
    required: &[&str],
) -> Result<(Value, Vec<String>, Vec<Value>)> {
    let path = output.join(format!("acp-account-summary-{phase}.json"));
    let bytes = fs::read(&path).with_context(|| {
        format!(
            "Flutter Driver did not write the acp-account {phase} summary: {}",
            path.display()
        )
    })?;
    let summary: Value = serde_json::from_slice(&bytes)?;
    ensure!(
        summary["scenario"] == "acp-account" && summary["phase"] == phase,
        "the acp-account {phase} summary does not belong to this scenario and lifecycle"
    );
    ensure!(
        summary["verdict"] == "pending",
        "the acp-account {phase} summary must keep the human verdict pending"
    );
    ensure!(
        summary["status"] == "complete",
        "the acp-account {phase} journey did not complete: stage={} failedChecks={}",
        summary["stage"],
        summary["failedChecks"]
    );
    // `status` alone is not trusted: the frozen contract requires an explicit,
    // empty `failedChecks` array, and any per-check map the journey publishes must
    // agree with it.
    let failed_checks = summary["failedChecks"]
        .as_array()
        .with_context(|| format!("the acp-account {phase} summary has no failedChecks array"))?;
    ensure!(
        failed_checks.is_empty(),
        "the acp-account {phase} journey reported failed checks: {failed_checks:?}"
    );
    if let Some(checks) = summary["checks"].as_object() {
        let false_checks: Vec<&String> = checks
            .iter()
            .filter(|(_, value)| *value != &Value::Bool(true))
            .map(|(name, _)| name)
            .collect();
        ensure!(
            false_checks.is_empty(),
            "the acp-account {phase} journey published checks that did not pass: {false_checks:?}"
        );
    }
    ensure!(
        summary["shutdown"] == "completed",
        "the acp-account {phase} journey did not confirm a normal application shutdown"
    );
    // The Driver records one capture per observed stage, the same shape the other
    // journeys write; a capture without a real PNG on disk is not evidence.
    let entries = summary["captures"]
        .as_array()
        .with_context(|| format!("the acp-account {phase} summary has no captures array"))?;
    let mut reached = Vec::new();
    let mut captured = Vec::new();
    for capture in entries {
        if let Some(name) = capture["name"].as_str() {
            reached.push(name.to_owned());
        }
    }
    for stage in required {
        let entry = entries
            .iter()
            .find(|entry| entry["name"].as_str() == Some(*stage))
            .with_context(|| {
                format!(
                    "the acp-account {phase} journey recorded no `{stage}` capture; reached {reached:?}"
                )
            })?;
        ensure!(
            entry["screenshot"] == true,
            "the `{stage}` capture did not record a screenshot"
        );
        let file = entry["file"]
            .as_str()
            .with_context(|| format!("the `{stage}` capture has no file"))?;
        ensure!(
            Path::new(file).components().count() == 1,
            "the `{stage}` screenshot must be a file inside the evidence directory: {file}"
        );
        let (width, height) = png_dimensions(&output.join(file))?;
        if let Some(reported) = entry.get("width").and_then(Value::as_u64) {
            ensure!(
                reported == u64::from(width),
                "the `{stage}` screenshot width differs from its real PNG header"
            );
        }
        if let Some(reported) = entry.get("height").and_then(Value::as_u64) {
            ensure!(
                reported == u64::from(height),
                "the `{stage}` screenshot height differs from its real PNG header"
            );
        }
        captured.push(json!({
            "phase": phase, "stage": stage, "file": file, "width": width, "height": height,
            "tree": entry.get("tree").and_then(Value::as_bool),
        }));
    }
    Ok((summary, reached, captured))
}

fn png_dimensions(path: &Path) -> Result<(u32, u32)> {
    let mut file =
        File::open(path).with_context(|| format!("screenshot is missing: {}", path.display()))?;
    let mut header = [0u8; 24];
    file.read_exact(&mut header)
        .with_context(|| format!("screenshot is not a readable PNG: {}", path.display()))?;
    ensure!(
        &header[..8] == b"\x89PNG\r\n\x1a\n" && &header[12..16] == b"IHDR",
        "screenshot is not a PNG: {}",
        path.display()
    );
    Ok((
        u32::from_be_bytes(header[16..20].try_into().expect("four header bytes")),
        u32::from_be_bytes(header[20..24].try_into().expect("four header bytes")),
    ))
}

fn write_acp_log(source: &Path, destination: &Path, redactions: &[(String, &str)]) -> Result<()> {
    let text = fs::read_to_string(source)?;
    let mut output = String::new();
    for line in text.lines() {
        output.push_str(&sanitize_driver_line(line, redactions));
        output.push('\n');
    }
    fs::write(destination, output)?;
    Ok(())
}
