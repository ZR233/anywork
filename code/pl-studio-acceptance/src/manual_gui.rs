mod account_usage;
mod bots_fixture;
mod context_replay_recovery;
mod conversation_read_work;
mod delegation;
mod mode_editor;
mod model_catalog;
mod question_history;
mod realtime_presentation;
mod shutdown;
mod sidebar_query;
mod skill_activity;
mod timeline_concept;
mod timeline_history_20k;
mod wait_events;
mod web_search;
mod websocket_recovery;

use anyhow::{Context, Result, bail, ensure};
use clap::Parser;
use pl_dev_support::{paths, process};
use pl_model::config::{AccountConfig, AccountId, AgentRoleId};
use pl_model::model::{
    MediaRepresentation, MediaWireFormat, ModelInfo, ModelInputCapability, ModelInputSource,
    ModelMediaInputProfile, ModelModality, ModelTransportProfile,
};
use pl_model::protocol::ProtocolEndpoint;
use pl_protocol::ThreadModeId;
use pl_studio_runtime::config::{
    ConfigPaths, ConfigRuntime, ConfigStore, McpFileV1, McpServerTransport, StudioConfig,
    StudioMcpServerEntry, canonical_mcp_filename,
};
use sea_orm::sqlx::{
    Connection as _, Row,
    sqlite::{SqliteConnectOptions, SqliteConnection},
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::env;
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, IsTerminal, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[derive(Debug, Parser)]
#[command(
    name = "cargo xtask manual-gui",
    bin_name = "cargo xtask manual-gui",
    about = "Prepare an isolated Studio environment. Manual presets stay interactive; desktop and native presets are judged automatically."
)]
pub(crate) struct ManualGuiOptions {
    /// Isolated environment preset. Manual presets keep a human verdict;
    /// `wait-events`, `conversation-read-work`, `question-history`,
    /// `realtime-presentation` and `sidebar-query` are automatic desktop runners;
    /// `shutdown` covers native lifecycle and second-instance behavior.
    /// ACP native acceptance uses the official Flutter integration_test
    /// suites directly; see design/28-acp.md.
    #[arg(long, default_value = "gui", value_parser = parse_manual_gui_scenario)]
    pub(crate) preset: String,
    /// Enable official Flutter MCP/Driver interaction for the manual gui preset.
    #[arg(long)]
    pub(crate) inspect: bool,
    /// Measure native Profile first-content layout with the conversation-read-work preset.
    #[arg(long)]
    pub(crate) profile_read_samples: bool,
    /// Directory for sanitized evidence (defaults to target/manual-gui/<timestamp>-<pid>).
    #[arg(long, value_name = "DIR")]
    pub(crate) output: Option<std::path::PathBuf>,
    /// Retain a successfully closed synthetic environment for release visual review.
    /// Failed timeline-history-20k samples are retained for diagnosis even without this flag.
    #[arg(long)]
    pub(crate) retain_environment: bool,
    /// Run tool-scroll against an explicitly supplied SSH test host (user@host).
    #[arg(long, value_name = "USER@HOST")]
    pub(crate) ssh_target: Option<String>,
    /// Parent directory for synthetic remote fixtures; must already exist.
    #[arg(long, value_name = "PATH", requires = "ssh_target")]
    pub(crate) ssh_workspace_parent: Option<String>,
    /// Damage an isolated startup input, then capture recovery and its backup.
    #[arg(long, value_parser = ["config", "database", "log", "cache"])]
    pub(crate) startup_fault: Option<String>,
    /// Seed the isolated GUI from a closed SQLite-consistent home copy. The source is read-only;
    /// model endpoints become loopback fixtures, external tools and robot connections are disabled.
    #[arg(long, value_name = "DIR", conflicts_with_all = ["startup_fault", "bots_fixture", "model_catalog_url", "model_catalog_control", "model_catalog_inventory"])]
    pub(crate) seed_home_copy: Option<PathBuf>,
    /// Add isolated OpenAI, DeepSeek and MiMo discovery instances against a loopback model-list fixture.
    #[arg(long, value_name = "URL")]
    pub(crate) model_catalog_url: Option<String>,
    /// Named startup inventory written into the model-catalog control file (`a`, `b`, `empty`, `reject-all`, `reject-second`, `real`).
    #[arg(long, value_name = "NAME", conflicts_with = "model_catalog_control")]
    pub(crate) model_catalog_inventory: Option<String>,
    /// Existing control-file path copied into the isolated environment. Mutually exclusive with `--model-catalog-inventory`.
    #[arg(long, value_name = "PATH", conflicts_with = "model_catalog_inventory")]
    pub(crate) model_catalog_control: Option<PathBuf>,
    /// Same-home, same-port catalog restart journey for items 1 and 5. Requires `--preset gui` and a control file.
    #[arg(long)]
    pub(crate) model_catalog_restart: bool,
    /// Exercise the restart coordinator without launching GUI (bind, rewrite inventory, rebind same port).
    #[arg(long)]
    pub(crate) model_catalog_restart_check: bool,
    /// Optional web-search fault so the operator can observe an error path.
    #[arg(
        long,
        value_parser = ["unstructured", "wrong-search-key", "wrong-mcp-key", "missing-search-key"]
    )]
    pub(crate) web_search_fault: Option<String>,
    /// Reusable web-search probe account ids, forwarded to the operator runbook.
    #[arg(long, value_name = "ID,ID,ID")]
    pub(crate) web_search_accounts: Option<String>,
    /// Reusable web-search probe model model_ids, forwarded to the operator runbook.
    #[arg(long, value_name = "MODEL,MODEL,MODEL")]
    pub(crate) web_search_models: Option<String>,
    /// Label the reusable web-search probe as a fixture or real account run.
    #[arg(long, value_parser = ["fixture", "real"])]
    pub(crate) web_search_probe: Option<String>,
    /// Run the native visible-displacement matrix after the `timeline-history`
    /// cold restart: six sizes × 96 fixed ±60 pointer inputs, plus 600 continuous
    /// inputs with direction reversal for each of the three primary sizes
    /// (1800 in total). The GUI runs in profile mode, so the numbers are input
    /// evidence, not an AOT/release performance measurement.
    #[arg(long)]
    pub(crate) timeline_displacement: bool,
    /// Opt-in isolated Feishu platform peer for native bot GUI observation.
    /// Requires `--preset gui` and a Linux debug native environment.
    #[arg(long)]
    pub(crate) bots_fixture: bool,
    /// Optional operator script path recorded in delegation evidence.
    /// The harness owns capture and shutdown; the script is not launched.
    #[arg(long, value_name = "PATH")]
    pub(crate) delegation_driver: Option<PathBuf>,
}

fn parse_manual_gui_scenario(value: &str) -> std::result::Result<String, String> {
    if matches!(value, "realtime-presentation" | "sidebar-query")
        || pl_provider_fixture::GUI_SCENARIOS.contains(&value)
    {
        Ok(value.to_owned())
    } else {
        Err(format!("unknown manual GUI scenario: {value}"))
    }
}

#[derive(Deserialize)]
struct FixtureReady {
    base_url: String,
    ws_url: String,
    scenario: String,
}

#[derive(Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
enum ExplicitRoleRouteCaptureState {
    Initialized,
    SessionOk,
    SessionError,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ExplicitRoleRouteEvidence<'a> {
    schema: u32,
    scenario: &'static str,
    run_id: &'a str,
    phase: &'static str,
    capture_state: ExplicitRoleRouteCaptureState,
    explicit_role_routes: Vec<ExplicitRoleRouteRow>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ExplicitRoleRouteRow {
    key: String,
    account_id: String,
    model_id: String,
    effort: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ExplicitRoleRouteEvidenceMarker<'a> {
    schema: u32,
    run_id: &'a str,
    harness_pid: u32,
    before_file: &'static str,
}

const EXPLICIT_ROLE_ROUTES_BEFORE_FILE: &str = "explicit-role-routes-before.json";
const EXPLICIT_ROLE_ROUTES_AFTER_FILE: &str = "explicit-role-routes-after.json";

#[derive(Deserialize, Serialize, PartialEq, Eq, Debug)]
#[serde(rename_all = "camelCase")]
struct StatisticsDbCounts {
    model_calls: usize,
    committed_calls: usize,
    performance_samples: usize,
}

#[derive(Serialize)]
struct ManualOperation {
    at_unix_ms: u128,
    action: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    outcome: Option<&'static str>,
}

enum InputEvent {
    Line(String),
    Done,
    Eof,
}

struct OwnedProcess {
    child: Child,
    stopped: bool,
}

/// One exclusive external SQLite write transaction held for an acceptance window.
///
/// It opens the real database file (never a copy) and takes `BEGIN IMMEDIATE`,
/// so the runtime writer for that exact library cannot commit while the
/// transaction is held. It gates every accepted scenario the same way and is
/// released from [`Drop`], so a failed or cancelled run can never leave the lock
/// behind.
pub(super) struct SqliteWriteLock {
    release: mpsc::Sender<()>,
    worker: Option<thread::JoinHandle<Result<()>>>,
}

struct StatisticsScenario<'a> {
    workspace: &'a Path,
    app_dir: &'a Path,
    home: &'a Path,
    working: &'a Path,
    output: &'a Path,
    fixture_log: &'a Path,
    requests_file: &'a Path,
    report_file: &'a Path,
    interrupt: &'a mpsc::Receiver<()>,
}

struct RealtimeScenario<'a> {
    workspace: &'a Path,
    app_dir: &'a Path,
    home: &'a Path,
    working: &'a Path,
    output: &'a Path,
    fixture_log: &'a Path,
    requests_file: &'a Path,
    interrupt: &'a mpsc::Receiver<()>,
}

struct ModelCatalogRestart<'a> {
    workspace: &'a Path,
    home: &'a Path,
    output: &'a Path,
    working: &'a Path,
    control_path: &'a Path,
    hits_a_path: &'a Path,
    hits_b_path: &'a Path,
    ready: &'a FixtureReady,
    interrupt: &'a mpsc::Receiver<()>,
}

struct StressBodyScenario<'a> {
    /// `stress-body` or `stress-body-large`; selects the fixture script and the
    /// expected body. Both drive the same journey.
    scenario: &'a str,
    workspace: &'a Path,
    app_dir: &'a Path,
    home: &'a Path,
    working: &'a Path,
    output: &'a Path,
    fixture_log: &'a Path,
    requests_file: &'a Path,
    interrupt: &'a mpsc::Receiver<()>,
}

struct HistoryLockScenario<'a> {
    workspace: &'a Path,
    app_dir: &'a Path,
    home: &'a Path,
    working: &'a Path,
    output: &'a Path,
    fixture_log: &'a Path,
    requests_file: &'a Path,
    interrupt: &'a mpsc::Receiver<()>,
}

/// Persisted long-history scenario: one driver-driven turn, a cold restart on the
/// same isolated home, and (opt-in) the native visible-displacement matrix.
struct TimelineHistoryScenario<'a> {
    workspace: &'a Path,
    app_dir: &'a Path,
    home: &'a Path,
    working: &'a Path,
    output: &'a Path,
    fixture_log: &'a Path,
    requests_file: &'a Path,
    /// 严格脚本的实时计数（同时证明 required 步骤全部消费且无拒绝请求）。
    status_file: &'a Path,
    interrupt: &'a mpsc::Receiver<()>,
    run_displacement: bool,
    capture_presentation: bool,
}

/// live 阶段从真实 snapshot 记录、其余生命周期必须复现的持久化目标身份。
///
/// 项目 id 与会话 id 是 canonical 身份，项目路径是同一数据根上的真实目录；三者
/// 一起排除“同名不同库”或“选到第一个项目/会话”的误通过。
struct PersistedTargetIdentity {
    workspace_id: String,
    project_path: String,
    thread_id: String,
}

struct HistoryFaultScenario<'a> {
    workspace: &'a Path,
    app_dir: &'a Path,
    home: &'a Path,
    working: &'a Path,
    output: &'a Path,
    fixture_log: &'a Path,
    requests_file: &'a Path,
    interrupt: &'a mpsc::Receiver<()>,
}

struct RecoveryScenario<'a> {
    workspace: &'a Path,
    app_dir: &'a Path,
    home: &'a Path,
    working: &'a Path,
    output: &'a Path,
    fixture_log: &'a Path,
    requests_file: &'a Path,
    status_file: &'a Path,
    interrupt: &'a mpsc::Receiver<()>,
}

struct WebSearchScenario<'a> {
    workspace: &'a Path,
    app_dir: &'a Path,
    home: &'a Path,
    working: &'a Path,
    output: &'a Path,
    fixture_log: &'a Path,
    requests_file: &'a Path,
    probe_mode: &'a str,
    interrupt: &'a mpsc::Receiver<()>,
}

impl SqliteWriteLock {
    /// Acquires `BEGIN IMMEDIATE` on [database], naming it [label] in errors.
    ///
    /// [hold_timeout] bounds how long the holder waits for the coordinator to
    /// release it; the worker commits and closes on release, and [`Drop`] is the
    /// backstop, so a failed or cancelled run can never leave the lock behind.
    pub(super) fn acquire(database: &Path, label: &str, hold_timeout: Duration) -> Result<Self> {
        let (acquired_tx, acquired_rx) = mpsc::sync_channel(1);
        let (release, release_rx) = mpsc::channel();
        let path = database.to_owned();
        let label = label.to_owned();
        let worker_label = label.clone();
        let worker = thread::spawn(move || -> Result<()> {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()?;
            runtime.block_on(async move {
                let options = SqliteConnectOptions::new()
                    .filename(path)
                    .create_if_missing(false);
                let mut connection = SqliteConnection::connect_with(&options).await?;
                sea_orm::sqlx::query("BEGIN IMMEDIATE")
                    .execute(&mut connection)
                    .await?;
                acquired_tx.send(()).ok();
                release_rx
                    .recv_timeout(hold_timeout)
                    .with_context(|| format!("{worker_label} SQLite lock release timed out"))?;
                sea_orm::sqlx::query("COMMIT")
                    .execute(&mut connection)
                    .await?;
                Ok(())
            })
        });
        let mut lock = Self {
            release,
            worker: Some(worker),
        };
        if acquired_rx.recv_timeout(Duration::from_secs(8)).is_err() {
            let result = lock.finish();
            result?;
            bail!("{label} BEGIN IMMEDIATE was not acquired");
        }
        Ok(lock)
    }

    pub(super) fn finish(&mut self) -> Result<()> {
        self.release.send(()).ok();
        if let Some(worker) = self.worker.take() {
            worker
                .join()
                .map_err(|_| anyhow::anyhow!("SQLite write lock holder panicked"))??;
        }
        Ok(())
    }
}

impl Drop for SqliteWriteLock {
    fn drop(&mut self) {
        let _ = self.finish();
    }
}

impl OwnedProcess {
    fn start(command: &mut Command, fixture: bool) -> Result<Self> {
        #[cfg(unix)]
        {
            use std::os::unix::process::CommandExt;
            command.process_group(0);
        }
        #[cfg(windows)]
        if fixture {
            use std::os::windows::process::CommandExt;
            use windows_sys::Win32::System::Threading::CREATE_NEW_PROCESS_GROUP;
            command.creation_flags(CREATE_NEW_PROCESS_GROUP);
        } else {
            process::configure_background_command(command);
        }
        #[cfg(not(windows))]
        let _ = fixture;
        #[cfg(not(windows))]
        process::configure_background_command(command);
        Ok(Self {
            child: command.spawn().context("failed to start child process")?,
            stopped: false,
        })
    }

    fn exited(&mut self) -> Result<bool> {
        Ok(self.exit_status()?.is_some())
    }

    /// Reads the real exit status once, if this child already ended.
    ///
    /// A failed startup must report how the child ended instead of the generic
    /// "exited" wording, so the operator sees the peer's own exit status even when
    /// its output was written to a log file.
    fn exit_status(&mut self) -> Result<Option<std::process::ExitStatus>> {
        Ok(self.child.try_wait()?)
    }

    /// Marks this owner as already reaped after the caller independently proved
    /// its whole process tree is gone, so `Drop` does not signal a process group
    /// that may already belong to another process.
    fn mark_reaped(&mut self) {
        self.stopped = true;
    }

    /// Delivers one stop request to this owner's process group without escalating.
    ///
    /// The `--native-launch` launcher runs a supervisor that handles SIGTERM
    /// (`ctrlc` with the `termination` feature): it cancels its own children,
    /// reclaims them and still reports the real native outcome. Killing the group
    /// would take that responsibility away from the supervisor, so this owner
    /// accepts only stop requests; waiting for the real exit belongs to the caller.
    fn request_stop(&self) -> bool {
        #[cfg(unix)]
        {
            Command::new("kill")
                .arg("-TERM")
                .arg("--")
                .arg(format!("-{}", self.child.id()))
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .is_ok_and(|status| status.success())
        }
        #[cfg(windows)]
        {
            // The launcher is not created as its own console process group here, so
            // no portable stop request can be addressed to it. The caller records
            // that the request was unavailable instead of pretending it was sent.
            false
        }
    }

    /// Waits, bounded, for this owner to exit on its own, then reaps it.
    ///
    /// `Ok(None)` means it was still running at the deadline; the caller keeps
    /// ownership and decides the next step instead of dropping a live tree.
    fn wait_exit(&mut self, timeout: Duration) -> Result<Option<std::process::ExitStatus>> {
        let deadline = Instant::now() + timeout;
        loop {
            if let Some(status) = self.child.try_wait()? {
                self.stopped = true;
                return Ok(Some(status));
            }
            if Instant::now() >= deadline {
                return Ok(None);
            }
            thread::sleep(Duration::from_millis(100));
        }
    }

    fn terminate(&mut self) {
        if self.stopped {
            return;
        }
        let signaled = self.kill_tree();
        match self.child.wait() {
            Ok(_) => self.stopped = true,
            Err(error) if signaled => {
                eprintln!(
                    "process {} signaled but wait failed: {error}",
                    self.child.id()
                );
                self.stopped = true;
            }
            Err(error) => {
                eprintln!("failed to terminate process {}: {error}", self.child.id());
            }
        }
    }

    fn kill_tree(&self) -> bool {
        #[cfg(unix)]
        {
            let term = Command::new("kill")
                .arg("-TERM")
                .arg("--")
                .arg(format!("-{}", self.child.id()))
                .stderr(Stdio::null())
                .status();
            thread::sleep(Duration::from_millis(200));
            let kill = Command::new("kill")
                .arg("-KILL")
                .arg("--")
                .arg(format!("-{}", self.child.id()))
                .stderr(Stdio::null())
                .status();
            term.as_ref().is_ok_and(std::process::ExitStatus::success)
                || kill.as_ref().is_ok_and(std::process::ExitStatus::success)
        }
        #[cfg(windows)]
        {
            Command::new("taskkill")
                .args(["/T", "/F", "/PID"])
                .arg(self.child.id().to_string())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .is_ok_and(|status| status.success())
        }
    }

    fn stop(&mut self, report: &Path) -> Result<std::process::ExitStatus> {
        let started = Instant::now();
        #[cfg(unix)]
        {
            let status = Command::new("kill")
                .arg("-TERM")
                .arg("--")
                .arg(format!("-{}", self.child.id()))
                .status()?;
            ensure!(status.success(), "failed to signal process group: {status}");
        }
        #[cfg(windows)]
        {
            use windows_sys::Win32::System::Console::{CTRL_BREAK_EVENT, GenerateConsoleCtrlEvent};
            ensure!(
                unsafe { GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, self.child.id()) } != 0,
                "failed to signal fixture process group: {}",
                std::io::Error::last_os_error()
            );
        }
        let deadline = Instant::now() + Duration::from_secs(10);
        let mut status = None;
        while Instant::now() < deadline {
            if status.is_none() {
                status = self.child.try_wait()?;
            }
            if report.is_file()
                && let Some(status) = status
            {
                self.stopped = true;
                return Ok(status);
            }
            thread::sleep(Duration::from_millis(100));
        }
        status = self.child.try_wait()?;
        let report_visible = report.is_file();
        let elapsed_ms = started.elapsed().as_millis();
        let status_text = status.map(|status| status.to_string());
        let mut stderr = io::stderr().lock();
        let diagnostic_result = writeln!(
            stderr,
            "fixture_stop_deadline elapsed_ms={elapsed_ms} process_status={status_text:?} report_visible={report_visible}"
        )
        .context("failed to write fixture stop deadline diagnostic")
        .and_then(|()| {
        stderr
            .flush()
                .context("failed to flush fixture stop deadline diagnostic")
        });
        let deadline_error = anyhow::anyhow!(
            "fixture stop deadline reached: process exit and requests-file were not both confirmed within the deadline (boundary observation: process_status={status_text:?}, report_visible={report_visible})"
        );
        match diagnostic_result {
            Ok(()) => Err(deadline_error),
            Err(diagnostic_error) => Err(anyhow::anyhow!(
                "{deadline_error:#}; stop deadline diagnostic also failed: {diagnostic_error:#}"
            )),
        }
    }
}

impl Drop for OwnedProcess {
    fn drop(&mut self) {
        if self.stopped {
            return;
        }
        #[cfg(unix)]
        {
            // Terminate descendants even when the group leader has exited.
            let _ = Command::new("kill")
                .arg("-TERM")
                .arg("--")
                .arg(format!("-{}", self.child.id()))
                .stderr(Stdio::null())
                .status();
            thread::sleep(Duration::from_millis(200));
            let _ = Command::new("kill")
                .arg("-KILL")
                .arg("--")
                .arg(format!("-{}", self.child.id()))
                .stderr(Stdio::null())
                .status();
        }
        #[cfg(windows)]
        {
            let _ = Command::new("taskkill")
                .args(["/T", "/F", "/PID"])
                .arg(self.child.id().to_string())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        }
        let _ = self.child.wait();
    }
}

/// Reclaim the optional Feishu peer, model fixture, and start-path evidence
/// without letting a later write replace the primary error.
fn cleanup_bots_gui_start(
    primary: anyhow::Error,
    bots: Option<bots_fixture::BotsFixture>,
    mut fixture: OwnedProcess,
    requests_file: &Path,
    fixture_log: &Path,
    output: &Path,
    gui_log: Option<&Path>,
) -> Result<()> {
    let peer = bots_fixture::finish_optional(bots, output);
    let model = fixture
        .stop(requests_file)
        .map(|_| ())
        .map_err(|error| error.context("model fixture stop failed"));
    drop(fixture);
    let fixture_log_result = write_fixture_log(fixture_log, &output.join("fixture.log"));
    let gui_log_result = gui_log.map_or(Ok(()), |path| {
        write_sanitized_log(path, &output.join("gui.log"))
    });
    let mut result = Err(primary);
    result = bots_fixture::with_cleanup(result, peer);
    result = bots_fixture::with_cleanup(result, model);
    bots_fixture::with_cleanup(
        result,
        bots_fixture::with_cleanup(fixture_log_result, gui_log_result),
    )
}

fn presentation_capture_requested() -> Result<bool> {
    let Some(value) = env::var_os("ANYWORK_CAPTURE_PRESENTATION") else {
        return Ok(false);
    };
    ensure!(
        value == "1",
        "ANYWORK_CAPTURE_PRESENTATION must be unset or `1`, got `{}`",
        value.to_string_lossy()
    );
    ensure!(
        cfg!(any(target_os = "linux", target_os = "windows")),
        "ANYWORK_CAPTURE_PRESENTATION=1 requires Linux or Windows"
    );
    Ok(true)
}

fn configure_presentation_capture(command: &mut Command, output: &Path, requested: bool) {
    command.env_remove("ANYWORK_PRESENTATION_SCREENSHOTS");
    if requested {
        command.env("ANYWORK_PRESENTATION_SCREENSHOTS", output);
    }
}

pub(crate) fn run(options: ManualGuiOptions) -> Result<()> {
    ensure!(
        !options.profile_read_samples || options.preset == "conversation-read-work",
        "--profile-read-samples requires --preset conversation-read-work"
    );
    ensure!(
        !options.inspect || (options.preset == "gui" && !options.bots_fixture),
        "--inspect requires the manual gui preset without --bots-fixture"
    );
    let capture_presentation = presentation_capture_requested()?;
    delegation::validate(&options)?;
    ensure!(
        options.seed_home_copy.is_none() || options.preset == "gui",
        "--seed-home-copy requires --preset gui"
    );
    ensure!(
        !options.retain_environment
            || matches!(
                options.preset.as_str(),
                "gui"
                    | "tool-scroll"
                    | "timeline-history"
                    | "timeline-history-20k"
                    | "question-history"
                    | "realtime-presentation"
                    | "timeline-concept"
                    | "stress-body-large"
                    | "wait-events"
                    | "conversation-read-work"
                    | "sidebar-query"
            )
            || pl_provider_fixture::delegation::Scenario::parse(&options.preset).is_some(),
        "--retain-environment is supported by --preset gui, tool-scroll, \
         timeline-history, timeline-history-20k, question-history, realtime-presentation, \
         timeline-concept, stress-body-large, wait-events, conversation-read-work, \
         sidebar-query and the delegation scenes"
    );
    ensure!(
        !options.timeline_displacement || options.preset == "timeline-history",
        "--timeline-displacement requires --preset timeline-history"
    );
    ensure!(
        options.preset != "timeline-history-20k" || cfg!(target_os = "linux"),
        "--preset timeline-history-20k is supported only on Linux"
    );
    ensure!(
        options.startup_fault.is_none() || options.preset == "gui",
        "--startup-fault requires --preset gui"
    );
    ensure!(
        options.ssh_target.is_none() || options.preset == "tool-scroll",
        "--ssh-target is supported only by --preset tool-scroll"
    );
    ensure!(
        options.web_search_fault.is_none() || options.preset == "web-search",
        "--web-search-fault requires --preset web-search"
    );
    ensure!(
        (options.web_search_accounts.is_none()
            && options.web_search_models.is_none()
            && options.web_search_probe.is_none())
            || options.preset == "web-search",
        "--web-search-accounts/--web-search-models/--web-search-probe require --preset web-search"
    );
    ensure!(
        (options.model_catalog_inventory.is_none() && options.model_catalog_control.is_none())
            || options.preset == "gui",
        "--model-catalog-inventory/--model-catalog-control require --preset gui"
    );
    ensure!(
        options.model_catalog_url.is_none()
            || (options.model_catalog_inventory.is_none()
                && options.model_catalog_control.is_none()),
        "--model-catalog-url cannot be combined with --model-catalog-inventory/--model-catalog-control"
    );
    ensure!(
        !options.model_catalog_restart
            || (options.preset == "gui"
                && (options.model_catalog_inventory.is_some()
                    || options.model_catalog_control.is_some())),
        "--model-catalog-restart requires --preset gui and a catalog control file"
    );
    ensure!(
        !options.model_catalog_restart_check
            || (options.preset == "gui"
                && (options.model_catalog_inventory.is_some()
                    || options.model_catalog_control.is_some())),
        "--model-catalog-restart-check requires --preset gui and a catalog control file"
    );
    // The restart journey withdraws `fixture-model-old` between phases, so it
    // needs a synthesized list; a payload instance replays a capture verbatim.
    // Resolving the selection here reports it before any process or temporary
    // environment exists.
    if options.model_catalog_restart {
        let control = model_catalog::resolve_control(
            options.model_catalog_inventory.as_deref(),
            options.model_catalog_control.as_deref(),
        )?;
        ensure!(
            control.openai.payload.is_none(),
            "--model-catalog-restart requires a `models` inventory; a payload instance returns a captured list with no withdrawable model_id"
        );
    }
    // Automatic desktop/native presets and catalog bind checks own their
    // verdict. Remaining presets are operator runbooks and need a terminal.
    bots_fixture::validate(&options)?;
    if !matches!(
        options.preset.as_str(),
        "statistics"
            | "realtime"
            | "realtime-presentation"
            | "timeline-concept"
            | "stress-body"
            | "stress-body-large"
            | "history-lock"
            | "history-fault"
            | "plan-recovery"
            | "mode-editor"
            | "context-replay-recovery"
            | "websocket-recovery"
            | "call-lifecycle-recovery"
            | "tool-scroll"
            | "web-search"
            | "provider-usage"
            | "shutdown"
            | "timeline-history"
            | "timeline-history-20k"
            | "question-history"
            | "skill-activity"
            | "wait-events"
            | "conversation-read-work"
            | "sidebar-query"
    ) && !options.model_catalog_restart
        && !options.model_catalog_restart_check
        && options.delegation_driver.is_none()
    {
        ensure!(
            io::stdin().is_terminal(),
            "manual-gui requires an interactive terminal"
        );
    }
    let (interrupt_tx, interrupt_rx) = mpsc::channel();
    thread::spawn(move || {
        if let Ok(runtime) = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            let _ = runtime.block_on(tokio::signal::ctrl_c());
            let _ = interrupt_tx.send(());
        }
    });
    let workspace = paths::workspace_root()?;
    let app_dir = paths::studio_app_dir(&workspace);
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let ordinary_gui = options.preset == "gui"
        && !options.retain_environment
        && options.ssh_target.is_none()
        && options.ssh_workspace_parent.is_none()
        && options.startup_fault.is_none()
        && options.seed_home_copy.is_none()
        && options.model_catalog_url.is_none()
        && options.model_catalog_inventory.is_none()
        && options.model_catalog_control.is_none()
        && !options.model_catalog_restart
        && !options.model_catalog_restart_check
        && options.web_search_fault.is_none()
        && options.web_search_accounts.is_none()
        && options.web_search_models.is_none()
        && options.web_search_probe.is_none()
        && !options.timeline_displacement
        && !options.bots_fixture
        && options.delegation_driver.is_none();
    let output = options.output.unwrap_or_else(|| {
        workspace
            .join("target/manual-gui")
            .join(format!("{stamp}-{}", std::process::id()))
    });
    ensure!(
        !output.exists(),
        "evidence directory already exists: {}",
        output.display()
    );
    fs::create_dir_all(&output)?;
    let output = output.canonicalize()?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&output, fs::Permissions::from_mode(0o700))?;
    }
    fs::write(
        output.join("verdict.json"),
        "{\"human_verdict\":\"pending\"}\n",
    )?;
    fs::write(output.join("operations.json"), "[]\n")?;

    if options.preset == "conversation-read-work" {
        let working = tempfile::Builder::new()
            .prefix("environment-")
            .tempdir_in(&output)
            .context("failed to create isolated conversation-read home")?;
        let home = working.path().join("home");
        fs::create_dir(&home)?;
        let result =
            conversation_read_work::run(&conversation_read_work::ConversationReadWorkScenario {
                workspace: &workspace,
                home: &home,
                working: working.path(),
                output: &output,
                interrupt: &interrupt_rx,
                profile_read_samples: options.profile_read_samples,
            });
        if options.retain_environment || result.is_err() {
            let retained = keep_isolated_environment(working, &home, &output, None);
            return match (result, retained) {
                (Ok(()), retained) => retained,
                (Err(error), Ok(())) => Err(error),
                (Err(error), Err(retain_error)) => Err(error.context(format!(
                    "retaining the failed conversation-read environment also failed: {retain_error:#}"
                ))),
            };
        }
        return result;
    }

    if options.preset == "sidebar-query" {
        let working = tempfile::Builder::new()
            .prefix("environment-")
            .tempdir_in(&output)
            .context("failed to create isolated sidebar home")?;
        let home = working.path().join("home");
        fs::create_dir(&home)?;
        let result = sidebar_query::run(&sidebar_query::SidebarQueryScenario {
            workspace: &workspace,
            home: &home,
            working: working.path(),
            output: &output,
            interrupt: &interrupt_rx,
        });
        if options.retain_environment || result.is_err() {
            let retained = keep_isolated_environment(working, &home, &output, None);
            return match (result, retained) {
                (Ok(()), retained) => retained,
                (Err(error), Ok(())) => Err(error),
                (Err(error), Err(retain_error)) => Err(error.context(format!(
                    "retaining the failed sidebar environment also failed: {retain_error:#}"
                ))),
            };
        }
        return result;
    }

    // Cargo may wait on package/build locks. Finish preparation before the
    // fixture's service-readiness deadline starts, then own the native process.
    let fixture_executable = build_fixture_executable(&workspace)?;

    let working = tempfile::Builder::new()
        .prefix("environment-")
        .tempdir_in(&output)
        .context("failed to create isolated GUI home")?;
    let run_id = working
        .path()
        .file_name()
        .and_then(|name| name.to_str())
        .context("isolated GUI environment basename is not valid UTF-8")?;
    let home = working.path().join("home");
    if let Some(source) = &options.seed_home_copy {
        copy_closed_home(source, &home)?;
    } else {
        fs::create_dir(&home)?;
    }

    let ready_file = working.path().join("fixture-ready.json");
    let requests_file = working.path().join("requests.json");
    let stress_report_file = working.path().join("stress-report.json");
    // Live strict-script counters written by the plan-recovery fixture watcher;
    // every other scenario leaves the flag off and never creates the file.
    let status_file = working.path().join("plan-recovery-status.json");
    let fixture_log_path = working.path().join("fixture.log");
    let fixture_log = File::create(&fixture_log_path)?;
    let catalog_control_path = model_catalog::default_control_path(working.path());
    let catalog_control =
        if options.model_catalog_inventory.is_some() || options.model_catalog_control.is_some() {
            Some(model_catalog::materialize_control(
                &catalog_control_path,
                options.model_catalog_inventory.as_deref(),
                options.model_catalog_control.as_deref(),
            )?)
        } else {
            None
        };
    let catalog_hits_path = working.path().join("model-catalog-requests.json");
    let catalog_hits_a_path = working.path().join("model-catalog-requests-a.json");
    let catalog_hits_b_path = working.path().join("model-catalog-requests-b.json");
    let fixture_hits_path = if options.model_catalog_restart {
        catalog_hits_a_path.clone()
    } else {
        catalog_hits_path.clone()
    };
    let fixture_scenario = if options.preset == "realtime-presentation" {
        "realtime"
    } else {
        options.preset.as_str()
    };
    let mut fixture_command = Command::new(&fixture_executable);
    fixture_command
        .current_dir(&workspace)
        .args(["--scenario", fixture_scenario, "--ready-file"])
        .arg(&ready_file)
        .arg("--requests-file")
        .arg(&requests_file)
        .arg("--report-file")
        .arg(&stress_report_file)
        .stdout(Stdio::from(fixture_log.try_clone()?))
        .stderr(Stdio::from(fixture_log));
    if options.ssh_target.is_some() {
        fixture_command.arg("--posix-exec");
    }
    if options.ssh_workspace_parent.is_some() {
        fixture_command.arg("--resource-lifecycle");
    }
    if catalog_control.is_some() {
        fixture_command
            .arg("--model-catalog-control")
            .arg(&catalog_control_path);
        fixture_command
            .arg("--model-catalog-requests")
            .arg(&fixture_hits_path);
    }
    if matches!(
        options.preset.as_str(),
        "plan-recovery"
            | "mode-editor"
            | "context-replay-recovery"
            | "websocket-recovery"
            | "call-lifecycle-recovery"
            | "shutdown"
            | "timeline-history"
            | "timeline-history-20k"
            | "question-history"
            | "skill-activity"
    ) {
        fixture_command.arg("--status-file").arg(&status_file);
    }
    if options.preset == "web-search" && options.web_search_fault.as_deref() == Some("unstructured")
    {
        fixture_command.arg("--fault").arg("unstructured");
    }
    // The shutdown scenario's background-tool turns run the fixture binary in
    // `--tool-peer` mode inside the opened project; the peer writes its business
    // pids to these coordination files (absolute paths so the exec shell never
    // depends on its working directory). Only the shutdown script reads them.
    // The concurrent-stop turn writes its own file so a stale record from the
    // earlier tool-reclamation turn can never be mistaken for the new subtree.
    if options.preset == "shutdown" {
        fixture_command.env(
            "ANYWORK_SHUTDOWN_TOOL_COORD",
            working.path().join("shutdown-tool-coord.json"),
        );
        fixture_command.env(
            "ANYWORK_SHUTDOWN_CONCURRENT_TOOL_COORD",
            working.path().join("shutdown-concurrent-tool-coord.json"),
        );
    }
    #[cfg(windows)]
    process::own_current_process_tree()?;
    let mut fixture = match OwnedProcess::start(&mut fixture_command, true) {
        Ok(fixture) => fixture,
        Err(error) => {
            write_fixture_log(&fixture_log_path, &output.join("fixture.log"))?;
            return Err(error);
        }
    };
    let ready = match wait_for_ready(&ready_file, &mut fixture, &interrupt_rx) {
        Ok(ready) => ready,
        Err(error) => {
            let _ = fixture.stop(&requests_file);
            drop(fixture);
            write_fixture_log(&fixture_log_path, &output.join("fixture.log"))?;
            if requests_file.exists() {
                sanitize_requests(&requests_file, &output.join("requests.json"))?;
            }
            return Err(error);
        }
    };
    ensure!(
        ready.scenario == fixture_scenario,
        "fixture scenario does not match request"
    );
    if let Err(error) = (if options.seed_home_copy.is_some() {
        write_copy_fixture_config(&home, &ready)
    } else {
        write_config(
            &home,
            &ready,
            options.web_search_fault.as_deref(),
            ordinary_gui,
        )
    })
    .and_then(|()| {
        if let Some(control) = catalog_control.as_ref() {
            ensure!(
                options.preset == "gui",
                "--model-catalog-inventory/--model-catalog-control require --preset gui"
            );
            model_catalog::configure(&home, &ready.base_url, Some(control))?;
            model_catalog::write_runbook(
                &output,
                &home,
                &catalog_control_path,
                control,
                &ready.base_url,
            )?;
        } else if let Some(url) = &options.model_catalog_url {
            ensure!(
                options.preset == "gui",
                "--model-catalog-url requires --preset gui"
            );
            model_catalog::configure(&home, url, None)?;
        }
        if ordinary_gui {
            write_explicit_role_route_evidence(
                &home,
                &output,
                run_id,
                ExplicitRoleRouteCaptureState::Initialized,
            )?;
            publish_explicit_role_route_evidence_marker(run_id)?;
        }
        Ok(())
    }) {
        let _ = fixture.stop(&requests_file);
        drop(fixture);
        write_fixture_log(&fixture_log_path, &output.join("fixture.log"))?;
        return Err(error);
    }
    if let Some(fault) = &options.startup_fault {
        seed_startup_fault(&home, fault)?;
    }

    if let Some(scenario) = pl_provider_fixture::delegation::Scenario::parse(&options.preset) {
        let project = working.path().join("delegation-project");
        let result = delegation::run(
            &delegation::ScenarioContext {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                interrupt: &interrupt_rx,
                driver: options.delegation_driver.as_deref(),
                scenario,
            },
            fixture,
            &ready,
        );
        if result.is_ok() && options.retain_environment {
            keep_isolated_environment(working, &home, &output, Some(&project))?;
        }
        return result;
    }

    if options.model_catalog_restart_check {
        let _ = fixture.stop(&requests_file);
        drop(fixture);
        model_catalog::restart_bind_check(
            &build_fixture_executable(&workspace)?,
            &catalog_control_path,
        )?;
        println!("model-catalog-restart-check: same-port rebind succeeded");
        return Ok(());
    }

    if options.preset == "provider-usage" {
        return account_usage::run(
            &account_usage::Scenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                interrupt: &interrupt_rx,
            },
            fixture,
            &ready,
        );
    }

    if options.preset == "web-search" {
        let fault = match options.web_search_fault.as_deref() {
            None => web_search::WebSearchFault::None,
            Some(value) => web_search::WebSearchFault::parse(value)
                .with_context(|| format!("unknown web-search fault: {value}"))?,
        };
        return web_search::run(
            &WebSearchScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                probe_mode: options.web_search_probe.as_deref().unwrap_or("fixture"),
                interrupt: &interrupt_rx,
            },
            fixture,
            &ready,
            fault,
        );
    }

    if matches!(
        options.preset.as_str(),
        "context-replay-recovery" | "websocket-recovery" | "call-lifecycle-recovery"
    ) {
        let run = if matches!(
            options.preset.as_str(),
            "websocket-recovery" | "call-lifecycle-recovery"
        ) {
            websocket_recovery::run
        } else {
            context_replay_recovery::run
        };
        return run(
            &RecoveryScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                status_file: &status_file,
                interrupt: &interrupt_rx,
            },
            fixture,
            &ready,
        );
    }

    if options.preset == "statistics" {
        return run_statistics_scenario(
            &StatisticsScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                report_file: &stress_report_file,
                interrupt: &interrupt_rx,
            },
            fixture,
        );
    }

    if options.preset == "realtime" {
        return run_realtime_scenario(
            &RealtimeScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                interrupt: &interrupt_rx,
            },
            fixture,
        );
    }

    if options.preset == "timeline-concept" {
        let project = working.path().join("timeline-concept-project");
        let result = timeline_concept::run(
            &timeline_concept::TimelineConceptScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                interrupt: &interrupt_rx,
                capture_presentation,
                provider_url: &ready.base_url,
            },
            fixture,
        );
        if options.retain_environment || result.is_err() {
            let retained = keep_isolated_environment(working, &home, &output, Some(&project));
            return match (result, retained) {
                (Ok(()), retained) => retained,
                (Err(error), Ok(())) => Err(error),
                (Err(error), Err(retain_error)) => Err(error.context(format!(
                    "retaining the failed timeline-concept environment also failed: {retain_error:#}"
                ))),
            };
        }
        return result;
    }

    if options.preset == "realtime-presentation" {
        let project = working.path().join("realtime-presentation-project");
        let result = realtime_presentation::run(
            &realtime_presentation::RealtimePresentationScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                interrupt: &interrupt_rx,
                capture_presentation,
            },
            fixture,
        );
        if options.retain_environment || result.is_err() {
            let retained = keep_isolated_environment(working, &home, &output, Some(&project));
            return match (result, retained) {
                (Ok(()), retained) => retained,
                (Err(error), Ok(())) => Err(error),
                (Err(error), Err(retain_error)) => Err(error.context(format!(
                    "retaining the failed realtime-presentation environment also failed: \
                     {retain_error:#}"
                ))),
            };
        }
        return result;
    }

    if options.preset == "wait-events" {
        let project = working.path().join("wait-events-project");
        let result = wait_events::run(
            &wait_events::WaitEventsScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                interrupt: &interrupt_rx,
            },
            fixture,
        );
        if options.retain_environment || result.is_err() {
            let retained = keep_isolated_environment(working, &home, &output, Some(&project));
            return match (result, retained) {
                (Ok(()), retained) => retained,
                (Err(error), Ok(())) => Err(error),
                (Err(error), Err(retain_error)) => Err(error.context(format!(
                    "retaining the failed wait-events environment also failed: {retain_error:#}"
                ))),
            };
        }
        return result;
    }

    if options.preset == "question-history" {
        let project = working.path().join("question-history-project");
        let result = question_history::run(
            &question_history::QuestionHistoryScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                status_file: &status_file,
                interrupt: &interrupt_rx,
                capture_presentation,
            },
            fixture,
        );
        if options.retain_environment || result.is_err() {
            let retained = keep_isolated_environment(working, &home, &output, Some(&project));
            return match (result, retained) {
                (Ok(()), retained) => retained,
                (Err(error), Ok(())) => Err(error),
                (Err(error), Err(retain_error)) => Err(error.context(format!(
                    "retaining the failed question-history environment also failed: \
                     {retain_error:#}"
                ))),
            };
        }
        return result;
    }

    if options.preset == "skill-activity" {
        return skill_activity::run(
            &skill_activity::SkillActivityScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                status_file: &status_file,
                interrupt: &interrupt_rx,
            },
            fixture,
        );
    }

    if matches!(options.preset.as_str(), "stress-body" | "stress-body-large") {
        let project = working.path().join("stress-body-project");
        let result = run_stress_body_scenario(
            &StressBodyScenario {
                scenario: options.preset.as_str(),
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                interrupt: &interrupt_rx,
            },
            fixture,
        );
        // 长正文复查需要整个临时根（含项目与配置绝对路径），不只复制 home。
        if result.is_ok() && options.retain_environment {
            keep_isolated_environment(working, &home, &output, Some(&project))?;
        }
        return result;
    }

    if options.preset == "history-lock" {
        return run_history_lock_scenario(
            &HistoryLockScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                interrupt: &interrupt_rx,
            },
            fixture,
        );
    }

    if options.preset == "plan-recovery" {
        return run_plan_recovery_scenario(
            &RecoveryScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                status_file: &status_file,
                interrupt: &interrupt_rx,
            },
            fixture,
        );
    }

    if options.preset == "mode-editor" {
        return mode_editor::run(
            &RecoveryScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                status_file: &status_file,
                interrupt: &interrupt_rx,
            },
            fixture,
        );
    }

    if options.preset == "history-fault" {
        return run_history_fault_scenario(
            &HistoryFaultScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                interrupt: &interrupt_rx,
            },
            fixture,
        );
    }

    if options.preset == "shutdown" {
        return shutdown::run(
            &shutdown::ShutdownScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                status_file: &status_file,
                fixture_executable: &fixture_executable,
                interrupt: &interrupt_rx,
            },
            fixture,
        );
    }

    if options.preset == "timeline-history" {
        let project = working.path().join("timeline-history-project");
        let result = run_timeline_history_scenario(
            &TimelineHistoryScenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                status_file: &status_file,
                interrupt: &interrupt_rx,
                run_displacement: options.timeline_displacement,
                capture_presentation,
            },
            fixture,
        );
        // 保留整个临时根与配置绝对路径（不只 home），供发布视觉复查复用。
        if result.is_ok() && options.retain_environment {
            keep_isolated_environment(working, &home, &output, Some(&project))?;
        }
        return result;
    }

    if options.preset == "timeline-history-20k" {
        let project = working.path().join("timeline-history-20k-project");
        let result = timeline_history_20k::run(
            &timeline_history_20k::Scenario {
                workspace: &workspace,
                app_dir: &app_dir,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                status_file: &status_file,
                interrupt: &interrupt_rx,
            },
            fixture,
        );
        if options.retain_environment || result.is_err() {
            let retained = keep_isolated_environment(working, &home, &output, Some(&project));
            return match (result, retained) {
                (Ok(()), retained) => retained,
                (Err(error), Ok(())) => Err(error),
                (Err(error), Err(retain_error)) => Err(error.context(format!(
                    "retaining the failed timeline-history-20k environment also failed: {retain_error:#}"
                ))),
            };
        }
        return result;
    }

    let gui_log_path = working.path().join("gui.log");
    let gui_log = File::create(&gui_log_path)?;
    let gui_stdout = match gui_log.try_clone() {
        Ok(stdout) => stdout,
        Err(error) => {
            return cleanup_bots_gui_start(
                error.into(),
                None,
                fixture,
                &requests_file,
                &fixture_log_path,
                &output,
                Some(&gui_log_path),
            );
        }
    };
    let mut bots = if options.bots_fixture {
        match bots_fixture::start(&home, &output) {
            Ok(bots) => Some(bots),
            Err(error) => {
                return cleanup_bots_gui_start(
                    error,
                    None,
                    fixture,
                    &requests_file,
                    &fixture_log_path,
                    &output,
                    None,
                );
            }
        }
    } else {
        None
    };
    let gui_command_result = bots
        .as_ref()
        .map(|fixture| fixture.gui_command(&workspace, &home))
        .transpose();
    let mut gui_command = match gui_command_result {
        Ok(Some(command)) => command,
        Ok(None) => {
            let mut command = Command::new("cargo");
            command
                .current_dir(&workspace)
                .args(["xtask", "run-gui", "--capture"])
                .env("ANYWORK_HOME", &home);
            command
        }
        Err(error) => {
            return cleanup_bots_gui_start(
                error,
                bots.take(),
                fixture,
                &requests_file,
                &fixture_log_path,
                &output,
                Some(&gui_log_path),
            );
        }
    };
    gui_command
        .stdout(Stdio::from(gui_stdout))
        .stderr(Stdio::from(gui_log));
    if bots.is_none() {
        if options.inspect {
            gui_command.arg("--inspect");
        }
        if options.preset == "gui" {
            gui_command.args(["--log-level", "info"]);
        }
        if options.seed_home_copy.is_some() {
            // Observe the real native wait status; Flutter's resident runner reports zero even
            // when the app exits abnormally during migration/restart review.
            gui_command
                .args(["--native-launch", "--native-exit-report"])
                .arg(output.join("native-exit.json"));
        }
        if matches!(options.preset.as_str(), "stress" | "tool-scroll") {
            gui_command.args(["--profile", "--native-launch"]);
        }
    }
    let mut gui = match OwnedProcess::start(&mut gui_command, false) {
        Ok(gui) => gui,
        Err(error) => {
            return cleanup_bots_gui_start(
                error,
                bots.take(),
                fixture,
                &requests_file,
                &fixture_log_path,
                &output,
                Some(&gui_log_path),
            );
        }
    };
    let session = (|| -> Result<()> {
        let vm_url = wait_for_vm(&gui_log_path, &mut gui, &mut fixture, &interrupt_rx)?;
        println!("Native GUI is ready. Evidence: {}", output.display());
        if bots.is_some() {
            println!(
                "Bots fixture runbook: {}",
                output.join("bots-fixture-runbook.md").display()
            );
        }
        if catalog_control.is_some() {
            println!(
                "Model catalog runbook: {}",
                output.join("model-catalog-runbook.md").display()
            );
        }
        if options.model_catalog_restart {
            return run_model_catalog_restart(
                &ModelCatalogRestart {
                    workspace: &workspace,
                    home: &home,
                    output: &output,
                    working: working.path(),
                    control_path: &catalog_control_path,
                    hits_a_path: &catalog_hits_a_path,
                    hits_b_path: &catalog_hits_b_path,
                    ready: &ready,
                    interrupt: &interrupt_rx,
                },
                &mut gui,
                &mut fixture,
            );
        }
        if options.preset == "tool-scroll" {
            fs::write(
                output.join("tool-arguments-fixture.json"),
                serde_json::to_vec_pretty(
                    &pl_provider_fixture::gui_tool_scroll_expected_arguments(
                        cfg!(windows) && options.ssh_target.is_none(),
                    ),
                )?,
            )?;
            println!(
                "Tool-scroll runbook: open the isolated project, send a turn that \
                 expands a tool with image recycling, then type done to capture. \
                 VM service: {vm_url}"
            );
            if let Some(target) = &options.ssh_target {
                println!("SSH target: {target}");
                if let Some(parent) = &options.ssh_workspace_parent {
                    println!("SSH workspace parent: {parent}");
                }
            }
        }
        if options.preset == "stress" {
            let project = working.path().join("stress-project");
            fs::create_dir(&project)?;
            let git = Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?;
            ensure!(
                git.success(),
                "failed to initialize isolated stress project"
            );
            println!(
                "Stress runbook: open {}, send the fixture stress prompt, inspect \
                 paging and frames, then type done to capture. VM service: {vm_url}",
                project.display()
            );
        }
        println!(
            "Record actions one per line: open-project, create-thread, select-model, send-prompt, inspect-response, stop-turn, open-settings, edit-settings, save-settings, other. Type done to capture and shut down; Ctrl-C cancels. Only action codes are saved."
        );
        if bots.is_some() {
            println!(
                "Bots environment commands (this peer only): bots-env registration pending|slow-down|denied|expired|complete|complete-without-user; bots-env message unknown-direct|resend-direct; bots-env conversations prepare-pages. They set fixed synthetic platform inputs and are not GUI or authorization actions."
            );
        }
        let (input_tx, input_rx) = mpsc::channel();
        thread::spawn(move || {
            loop {
                let mut input = String::new();
                match io::stdin().read_line(&mut input) {
                    Ok(0) | Err(_) => {
                        let _ = input_tx.send(InputEvent::Eof);
                        break;
                    }
                    Ok(_) if input.trim() == "done" => {
                        let _ = input_tx.send(InputEvent::Done);
                        break;
                    }
                    Ok(_) => {
                        if input_tx.send(InputEvent::Line(input)).is_err() {
                            break;
                        }
                    }
                }
            }
        });
        let mut operations = Vec::new();
        loop {
            match input_rx.try_recv() {
                Ok(InputEvent::Line(line)) => {
                    let operation = record_session_line(bots.as_ref(), &line)?;
                    operations.push(operation);
                    fs::write(
                        output.join("operations.json"),
                        serde_json::to_vec_pretty(&operations)?,
                    )?;
                    continue;
                }
                Ok(InputEvent::Done) => {
                    capture(&app_dir, &home, &vm_url, &output, &interrupt_rx, true)?;
                    return Ok(());
                }
                Ok(InputEvent::Eof) => bail!("manual GUI input closed before done"),
                Err(mpsc::TryRecvError::Disconnected) => bail!("manual GUI input unavailable"),
                Err(mpsc::TryRecvError::Empty) => {}
            }
            if interrupt_rx.try_recv().is_ok() {
                bail!("manual GUI cancelled; human verdict remains pending");
            }
            ensure!(!gui.exited()?, "GUI exited before manual review completed");
            ensure!(
                !fixture.exited()?,
                "account fixture exited during manual review"
            );
            thread::sleep(Duration::from_millis(200));
        }
    })();
    let session = session.and_then(|()| {
        if options.seed_home_copy.is_some() {
            let status = wait_for_gui_exit(&mut gui, Duration::from_secs(30), "migration review")?;
            ensure!(
                status.success(),
                "migration review GUI exited abnormally: {status}"
            );
            require_native_exit(&output.join("native-exit.json"), None)?;
        }
        Ok(())
    });
    let gui_log_result = write_sanitized_log(&gui_log_path, &output.join("gui.log"));
    drop(gui);
    // This records only the harness session Result, not shutdown acknowledgement
    // or successful reclamation of the complete GUI process tree.
    let role_after_result = if ordinary_gui {
        write_explicit_role_route_evidence(
            &home,
            &output,
            run_id,
            if session.is_ok() {
                ExplicitRoleRouteCaptureState::SessionOk
            } else {
                ExplicitRoleRouteCaptureState::SessionError
            },
        )
    } else {
        Ok(())
    };
    let bots_cleanup = bots_fixture::finish_optional(bots.take(), &output);
    let primary = (|| -> Result<()> {
        let runtime_log = home.join("studio/logs/studio.log");
        if runtime_log.is_file() {
            write_sanitized_log(&runtime_log, &output.join("startup-timing.log"))?;
        }
        if options.startup_fault.is_some() {
            let backups = home.join("startup-backups");
            ensure!(
                backups.is_dir() && fs::read_dir(&backups)?.count() == 1,
                "startup did not produce exactly one recovery backup"
            );
            ensure!(
                !home.join("startup-recovery.toml").exists(),
                "startup recovery did not complete"
            );
            fs::write(
                output.join("startup-recovery.json"),
                serde_json::to_vec_pretty(&serde_json::json!({
                    "fault": options.startup_fault, "backupCount": 1, "completed": true,
                    "preservedOldVersion": fs::read(home.join("sessions/old/retained"))? == b"old session",
                }))?,
            )?;
            copy_startup_evidence(&backups, &output.join("startup-backups"))?;
        }
        if options.model_catalog_restart {
            drop(fixture);
            write_fixture_log(&fixture_log_path, &output.join("fixture.log"))?;
            session?;
            if options.retain_environment {
                keep_isolated_environment(working, &home, &output, None)?;
            }
            return Ok(());
        }
        let fixture_result = fixture.stop(&requests_file);
        drop(fixture);
        write_fixture_log(&fixture_log_path, &output.join("fixture.log"))?;
        model_catalog::copy_hits(
            &catalog_hits_path,
            &output.join("model-catalog-requests.json"),
            catalog_control.is_some(),
        )?;
        if options.preset == "gui" {
            copy_sanitized_config(&home, &output.join("config.toml"))?;
        }
        let stress_report: Option<pl_provider_fixture::StressReport> =
            if stress_report_file.exists() {
                let report = serde_json::from_slice(&fs::read(&stress_report_file)?)?;
                fs::write(
                    output.join("stress-report.json"),
                    serde_json::to_vec_pretty(&report)?,
                )?;
                report
            } else {
                None
            };
        let requests = if requests_file.exists() {
            sanitize_requests(&requests_file, &output.join("requests.json"))?;
            Some(serde_json::from_slice::<Vec<serde_json::Value>>(
                &fs::read(&requests_file)?,
            )?)
        } else {
            None
        };
        let accepted = requests.as_ref().map_or(0, |rows| {
            rows.iter()
                .filter(|row| row.get("accepted").and_then(|value| value.as_bool()) == Some(true))
                .count()
        });
        let rejected = requests.as_ref().map_or(0, |rows| {
            rows.iter()
                .filter(|row| row.get("accepted").and_then(|value| value.as_bool()) == Some(false))
                .count()
        });
        let fixture_complete = fixture_result.as_ref().is_ok_and(|status| status.success());
        let fixture_state = if requests.is_none() {
            "error"
        } else if rejected > 0 {
            "rejected"
        } else if fixture_complete {
            "completed"
        } else if accepted == 0 {
            "pending"
        } else {
            "error"
        };
        fs::write(
            output.join("fixture-status.json"),
            serde_json::to_vec_pretty(&serde_json::json!({
                "scenario": fixture_state, "acceptedRequests": accepted, "rejectedRequests": rejected,
                "emittedEvents": stress_report.as_ref().map(|report| report.emitted_events),
                "elapsedMillis": stress_report.as_ref().map(|report| report.elapsed_millis),
            }))?,
        )?;
        println!("Evidence: {} (human verdict pending)", output.display());
        gui_log_result?;
        if fixture_state == "pending" {
            // A migration review opens saved sessions without sending a model request. Preserve
            // its database evidence even when the GUI exits before review can complete.
            if options.seed_home_copy.is_some() && options.retain_environment {
                keep_isolated_environment(working, &home, &output, None)?;
            }
            session?;
            println!("Fixture main step was not exercised; review remains pending.");
            return Ok(());
        }
        session?;
        ensure!(
            fixture_state == "completed",
            "fixture {fixture_state}; verdict remains pending"
        );
        if options.preset == "tool-scroll" {
            let counts: Vec<_> = requests
                .as_ref()
                .into_iter()
                .flatten()
                .map(|request| count_inline_images(&request["body"]))
                .collect();
            fs::write(
                output.join("image-requests.json"),
                serde_json::to_vec_pretty(&serde_json::json!({
                    "inlineImageCounts": counts,
                    "humanVerdict": "pending",
                }))?,
            )?;
        }
        if options.preset == "stress" {
            let gui_errors = count_gui_errors(&gui_log_path)?;
            let debug_log = output.join("gui-debug.log");
            fs::copy(&gui_log_path, &debug_log)?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                fs::set_permissions(&debug_log, fs::Permissions::from_mode(0o600))?;
            }
            fs::write(
                output.join("gui-health.json"),
                serde_json::to_vec_pretty(&serde_json::json!({
                    "unhandledErrors": gui_errors,
                    "humanVerdict": "pending",
                    "fixtureEvents": stress_report.as_ref().map(|report| report.emitted_events),
                    "fixtureElapsedMillis": stress_report.as_ref().map(|report| report.elapsed_millis),
                }))?,
            )?;
            ensure!(
                gui_errors == 0,
                "GUI reported {gui_errors} unhandled errors during stress"
            );
        }
        if options.retain_environment {
            let project = if options.preset == "tool-scroll" {
                let capture = fs::read_to_string(output.join("capture-stage.txt"))
                    .context("retained environment requires completed shutdown capture")?;
                ensure!(
                    capture.trim() == "shutdown_completed",
                    "runtime shutdown did not complete"
                );
                Some(working.path().join("tool-scroll-project"))
            } else {
                None
            };
            keep_isolated_environment(working, &home, &output, project.as_deref())?;
        }

        Ok(())
    })();
    bots_fixture::with_cleanup(
        bots_fixture::with_cleanup(primary, role_after_result),
        bots_cleanup,
    )
}

/// timeline-history：官方 Flutter 集成测试的真实提交、同 home 重启与可选位移矩阵。
///
/// live/restart 由官方 `integration_test` 持有，应用资源仍经 production
/// `runStudioShutdown`/`AppGraph.close` 收束。可选位移矩阵仍用独立 GUI 进程，
/// 正常关闭由 `ext.anywork.requestExit` 协调，并以真实 OS waitpid 退出码 0 判定。
/// 人工截图复查保持 pending。
fn run_timeline_history_scenario(
    context: &TimelineHistoryScenario<'_>,
    mut fixture: OwnedProcess,
) -> Result<()> {
    let TimelineHistoryScenario {
        workspace,
        app_dir,
        home,
        working,
        output,
        fixture_log,
        requests_file,
        status_file,
        interrupt,
        run_displacement,
        capture_presentation,
    } = context;
    let project = working.join("timeline-history-project");
    let mut phases: Vec<(&str, Option<std::process::ExitStatus>)> = Vec::new();
    let mut persisted_identity: Option<PersistedTargetIdentity> = None;
    let journey = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated timeline-history project"
        );
        for phase in ["live", "restart"] {
            let phase_index = phases.len();
            phases.push((phase, None));
            let integration_log = working.join(format!("timeline-history-{phase}-integration.log"));
            let integration_output = File::create(&integration_log)?;
            let mut command = Command::new("cargo");
            command
                .current_dir(workspace)
                .args([
                    "xtask",
                    "test-project",
                    "--suite",
                    "desktop",
                    "--case",
                    "timeline_presentation",
                ])
                .env("ANYWORK_HOME", home)
                .env("ANYWORK_TIMELINE_PHASE", phase)
                .env("ANYWORK_TIMELINE_PROJECT", &project)
                .env("ANYWORK_TIMELINE_OUTPUT", output)
                .stdout(Stdio::from(integration_output.try_clone()?))
                .stderr(Stdio::from(integration_output));
            configure_presentation_capture(&mut command, output, *capture_presentation);
            let mut runner = OwnedProcess::start(&mut command, false)?;
            let deadline = Instant::now() + Duration::from_secs(3_600);
            let runner_exit = loop {
                if let Some(status) = runner.child.try_wait()? {
                    runner.stopped = true;
                    break status;
                }
                ensure!(
                    !fixture.exited()?,
                    "account fixture exited during timeline-history {phase}"
                );
                ensure!(
                    interrupt.try_recv().is_err(),
                    "timeline-history {phase} cancelled"
                );
                ensure!(
                    Instant::now() < deadline,
                    "timeline-history {phase} integration test timed out"
                );
                thread::sleep(Duration::from_millis(200));
            };
            phases[phase_index].1 = Some(runner_exit);
            ensure!(
                runner_exit.success(),
                "timeline-history {phase} integration test failed: {runner_exit}"
            );
            let report: serde_json::Value = serde_json::from_slice(
                &fs::read(output.join(format!("timeline-history-{phase}.json")))
                    .with_context(|| format!("timeline-history {phase} wrote no report"))?,
            )?;
            ensure!(
                report.get("pass") == Some(&serde_json::Value::Bool(true)),
                "timeline-history {phase} did not pass: {}",
                serde_json::to_string_pretty(&report)?
            );
            ensure!(
                report.get("shutdown") == Some(&serde_json::Value::String("completed".into())),
                "timeline-history {phase} AppGraph shutdown was not clean"
            );
            // 报告键与 Dart 实际产出逐个核对：20k 条必须保持真实 40 页深度、仍有更早
            // 内容、没有重复/错序/停滞游标，冷启动与最新小页符合 tail 基线契约。
            let latest_page = report
                .get("latestPage")
                .and_then(serde_json::Value::as_object)
                .with_context(|| format!("timeline-history {phase} report has no latest page"))?;
            ensure!(
                report.get("latestPageOk") == Some(&serde_json::Value::Bool(true))
                    && latest_page.get("firstContentLaidOut")
                        == Some(&serde_json::Value::Bool(true))
                    && latest_page.get("atLiveEdge") == Some(&serde_json::Value::Bool(true))
                    && latest_page.get("pixelsAtTop") == Some(&serde_json::Value::Bool(true))
                    && latest_page.get("hasOlder") == Some(&serde_json::Value::Bool(true)),
                "timeline-history {phase} latest display has no first content layout: \
                 {latest_page:?}"
            );
            let cold_start = report
                .get("coldStartLatest")
                .and_then(serde_json::Value::as_object)
                .with_context(|| {
                    format!("timeline-history {phase} report has no cold-start observation")
                })?;
            ensure!(
                cold_start.get("live") == Some(&serde_json::Value::Bool(true))
                    && cold_start
                        .get("loadedItems")
                        .and_then(serde_json::Value::as_u64)
                        .is_some_and(|items| items > 0)
                    && cold_start.get("firstContentLaidOut")
                        == Some(&serde_json::Value::Bool(true))
                    && cold_start.get("pixelsAtTop") == Some(&serde_json::Value::Bool(true)),
                "timeline-history {phase} cold start has no first content layout: \
                 {cold_start:?}"
            );
            let paging = report
                .get("paging")
                .and_then(serde_json::Value::as_object)
                .with_context(|| {
                    format!("timeline-history {phase} report has no paging evidence")
                })?;
            let page_count = paging
                .get("pageCount")
                .and_then(serde_json::Value::as_u64)
                .context("timeline-history paging page count missing")?;
            let pages = paging
                .get("pages")
                .and_then(serde_json::Value::as_array)
                .context("timeline-history paging pages missing")?;
            let partial_depth = paging
                .get("partialDepthPages")
                .and_then(serde_json::Value::as_u64)
                .context("timeline-history partial depth missing")?;
            ensure!(
                page_count == 40
                    && partial_depth == 40
                    && pages.len() as u64 == page_count
                    && paging.get("reachedEnd") == Some(&serde_json::Value::Bool(false))
                    && paging.get("hasOlder") == Some(&serde_json::Value::Bool(true))
                    && paging.get("duplicateIdentity") == Some(&serde_json::Value::Bool(false))
                    && paging.get("orderViolation") == Some(&serde_json::Value::Bool(false))
                    && paging.get("cursorStalled") == Some(&serde_json::Value::Bool(false))
                    && paging
                        .get("growthViolations")
                        .and_then(serde_json::Value::as_array)
                        .is_some_and(Vec::is_empty),
                "timeline-history {phase} paging did not prove 40 real partial pages over the \
                 seeded history: {}",
                serde_json::json!({
                    "pageCount": page_count,
                    "partialDepthPages": partial_depth,
                    "pages": pages.len(),
                    "reachedEnd": paging.get("reachedEnd"),
                    "hasOlder": paging.get("hasOlder"),
                })
            );
            if phase == "live" {
                ensure!(
                    report
                        .get("streamingHistory")
                        .and_then(|value| value.get("pass"))
                        == Some(&serde_json::Value::Bool(true)),
                    "timeline-history did not prove live-output growth during independent paging \
                     and completed-atom immutability"
                );
                // 首轮真实 snapshot 是冷启动目标身份的**唯一**来源；baseline 与报告必须
                // 指向同一身份，否则后续冷启动可能打开别的东西却仍然“通过”。
                let identity = report
                    .get("identity")
                    .and_then(serde_json::Value::as_object)
                    .with_context(|| "timeline-history live report has no persisted identity")?;
                ensure!(
                    identity.get("evidenceConsistent") == Some(&serde_json::Value::Bool(true)),
                    "timeline-history live identity is not consistent across \
                     selection/workspace/project/timeline: {identity:?}"
                );
                let workspace_id = identity
                    .get("workspaceId")
                    .and_then(serde_json::Value::as_str)
                    .filter(|id| !id.is_empty())
                    .context("timeline-history live identity has no workspaceId")?
                    .to_owned();
                let thread_id = identity
                    .get("threadId")
                    .and_then(serde_json::Value::as_str)
                    .filter(|id| !id.is_empty())
                    .context("timeline-history live identity has no threadId")?
                    .to_owned();
                let project_path = identity
                    .get("projectPath")
                    .and_then(serde_json::Value::as_str)
                    .filter(|path| !path.is_empty())
                    .context("timeline-history live identity has no projectPath")?
                    .to_owned();
                let baseline: serde_json::Value = serde_json::from_slice(
                    &fs::read(output.join("timeline-history-baseline.json"))
                        .context("timeline-history live wrote no restart baseline")?,
                )?;
                ensure!(
                    baseline
                        .get("workspaceId")
                        .and_then(serde_json::Value::as_str)
                        == Some(workspace_id.as_str())
                        && baseline
                            .get("projectPath")
                            .and_then(serde_json::Value::as_str)
                            == Some(project_path.as_str())
                        && baseline.get("threadId").and_then(serde_json::Value::as_str)
                            == Some(thread_id.as_str()),
                    "timeline-history baseline identity does not match the live report: \
                     {baseline:?}"
                );
                persisted_identity = Some(PersistedTargetIdentity {
                    workspace_id,
                    project_path,
                    thread_id,
                });
            }
            if phase == "restart" {
                let comparison = report
                    .get("restartComparison")
                    .and_then(serde_json::Value::as_object)
                    .with_context(|| "timeline-history restart has no comparison evidence")?;
                ensure!(
                    comparison.get("sameOrder") == Some(&serde_json::Value::Bool(true))
                        && comparison.get("identityMatches")
                            == Some(&serde_json::Value::Bool(true))
                        && comparison.get("latestMatches") == Some(&serde_json::Value::Bool(true))
                        && comparison.get("pageCountMatches")
                            == Some(&serde_json::Value::Bool(true))
                        && comparison.get("oldestMatches") == Some(&serde_json::Value::Bool(true))
                        && comparison.get("loadedItemsMatch")
                            == Some(&serde_json::Value::Bool(true)),
                    "timeline-history cold start did not reproduce the same ordered pages: \
                     {comparison:?}"
                );
                // 冷启动是在**同一持久化身份**上重建的：正常侧栏选择/打开的真实证据
                // 必须与 live 记录的项目、会话一致，且不得把“没点过”写成自动打开。
                let restore = report
                    .get("restore")
                    .and_then(serde_json::Value::as_object)
                    .with_context(
                        || "timeline-history restart has no cold-start restoration evidence",
                    )?;
                let target = persisted_identity
                    .as_ref()
                    .context("timeline-history restart ran without the live identity")?;
                ensure!(
                    restore.get("evidenceConsistent") == Some(&serde_json::Value::Bool(true))
                        && restore.get("workspaceIdMatches")
                            == Some(&serde_json::Value::Bool(true))
                        && restore.get("threadIdMatches") == Some(&serde_json::Value::Bool(true))
                        && restore
                            .get("workspaceId")
                            .and_then(serde_json::Value::as_str)
                            == Some(target.workspace_id.as_str())
                        && restore
                            .get("projectPath")
                            .and_then(serde_json::Value::as_str)
                            == Some(target.project_path.as_str())
                        && restore.get("threadId").and_then(serde_json::Value::as_str)
                            == Some(target.thread_id.as_str()),
                    "timeline-history cold start did not restore the same persisted \
                     project/thread: {restore:?}"
                );
                let auto_opened = restore
                    .get("autoOpened")
                    .and_then(serde_json::Value::as_bool)
                    .context("timeline-history cold start has no auto-opened fact")?;
                let tap_attempts = restore
                    .get("tapAttempts")
                    .and_then(serde_json::Value::as_u64)
                    .context("timeline-history cold start has no tap count")?;
                ensure!(
                    auto_opened == (tap_attempts == 0),
                    "timeline-history cold start mislabels auto-opened vs selected: {restore:?}"
                );
            }
        }
        if *run_displacement {
            let gui_log = working.join("timeline-history-displacement-gui.log");
            let native_exit = output.join("timeline-history-displacement-native-exit.json");
            let mut gui = start_timeline_history_gui(workspace, home, &gui_log, &native_exit)?;
            let vm_url = wait_for_vm(&gui_log, &mut gui, &mut fixture, interrupt)?;
            observe_capture_exit(
                app_dir,
                &vm_url,
                output,
                interrupt,
                &mut gui,
                Some(&mut fixture),
                "timeline-history displacement: restore the same persisted thread, run pointer inputs, then type done.",
            )?;
            let gui_exit = wait_for_gui_exit(&mut gui, Duration::from_secs(120), "displacement")?;
            ensure!(
                gui_exit.success(),
                "displacement GUI did not exit cleanly: {gui_exit}"
            );
            require_native_exit(&native_exit, None)?;
            phases.push(("displacement", Some(gui_exit)));
        }
        Ok(())
    })();

    // Record observed exits before assertions and retain failed-phase evidence.
    // live/restart store the official integration runner log; displacement keeps
    // independent capture/native-exit evidence.
    let redactions = [
        (home.to_string_lossy().into_owned(), "<home>"),
        (working.to_string_lossy().into_owned(), "<coord>"),
        (output.to_string_lossy().into_owned(), "<output>"),
        (app_dir.to_string_lossy().into_owned(), "<app>"),
        (workspace.to_string_lossy().into_owned(), "<workspace>"),
    ];
    for (phase, gui_exit) in &phases {
        let gui_log = working.join(format!("timeline-history-{phase}-gui.log"));
        if gui_log.is_file() {
            write_sanitized_log(
                &gui_log,
                &output.join(format!("timeline-history-{phase}-gui.log")),
            )?;
        }
        if *phase != "displacement" {
            let runner_log = working.join(format!("timeline-history-{phase}-integration.log"));
            write_realtime_driver_evidence(
                &runner_log,
                output,
                &format!("timeline-history-{phase}"),
                *gui_exit,
                journey.as_ref().err(),
                &redactions,
            )?;
            let stem = format!("timeline-history-{phase}");
            let driver_log = output.join(format!("{stem}-driver.log"));
            if driver_log.is_file() {
                fs::rename(driver_log, output.join(format!("{stem}-integration.log")))?;
            }
            fs::rename(
                output.join(format!("{stem}-driver-errors.txt")),
                output.join(format!("{stem}-integration-errors.txt")),
            )?;
        }
        fs::write(
            output.join(format!("timeline-history-{phase}-exit.json")),
            serde_json::to_vec_pretty(&serde_json::json!({
                "phase": phase,
                "guiExit": gui_exit.map(|status| status.code()),
            }))?,
        )?;
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
    let live_status: Option<pl_provider_fixture::FixtureLiveStatus> = if status_file.is_file() {
        Some(serde_json::from_slice(&fs::read(status_file)?)?)
    } else {
        None
    };
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "timeline-history",
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "completed": fixture_result.as_ref().is_ok_and(|status| status.success()),
            "requiredStepsConsumed": live_status.map(|status| status.remaining_optional),
            "humanVerdict": "pending",
        }))?,
    )?;
    require_timeline_history_completion(journey, fixture_result)?;
    ensure!(
        rejected == 0,
        "timeline-history fixture rejected {rejected} account request(s)"
    );
    if *run_displacement {
        fs::write(
            output.join("timeline-displacement-verdict.json"),
            serde_json::to_vec_pretty(&serde_json::json!({
                "humanVerdict": "pending",
                "note": "operator observation; capture never replaces the human screenshot review",
            }))?,
        )?;
    }
    Ok(())
}

fn require_timeline_history_completion(
    journey: Result<()>,
    fixture_result: Result<ExitStatus>,
) -> Result<()> {
    journey?;
    let fixture_status = fixture_result.context("timeline-history provider fixture stop failed")?;
    ensure!(
        fixture_status.success(),
        "timeline-history provider fixture exited with {fixture_status}"
    );
    Ok(())
}

fn start_timeline_history_gui(
    workspace: &Path,
    home: &Path,
    log_path: &Path,
    native_exit: &Path,
) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    command
        .current_dir(workspace)
        // Profile（不是 debug）与其它长历史场景一致；仍不是 AOT/release 性能证据。
        .args([
            "xtask",
            "run-gui",
            "--capture",
            "--profile",
            "--native-launch",
            "--native-exit-report",
        ])
        .arg(native_exit)
        .env("ANYWORK_HOME", home)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    OwnedProcess::start(&mut command, false)
}

fn require_native_exit(path: &Path, pid: Option<u64>) -> Result<()> {
    let report: serde_json::Value = serde_json::from_slice(
        &fs::read(path)
            .with_context(|| format!("missing native exit report {}", path.display()))?,
    )?;
    ensure!(
        report["schema"] == "anywork-native-exit/1"
            && report["pid"]
                .as_u64()
                .is_some_and(|actual| actual > 0 && pid.is_none_or(|expected| actual == expected))
            && report["exitCode"].as_i64() == Some(0)
            && report["signal"].is_null()
            && report["cancelled"].as_bool() == Some(false)
            && report["descendantsAtRootExit"]
                .as_array()
                .is_some_and(Vec::is_empty)
            && report["reclaimedDescendants"]
                .as_array()
                .is_some_and(Vec::is_empty),
        "native host did not exit cleanly: {report}"
    );
    Ok(())
}

/// 等待被 `ext.anywork.requestExit` 协调关闭的 GUI 自然退出，并返回真实退出状态。
fn wait_for_gui_exit(
    gui: &mut OwnedProcess,
    timeout: Duration,
    phase: &str,
) -> Result<std::process::ExitStatus> {
    let deadline = Instant::now() + timeout;
    loop {
        if let Some(status) = gui.child.try_wait()? {
            gui.stopped = true;
            return Ok(status);
        }
        ensure!(
            Instant::now() < deadline,
            "GUI did not exit after the coordinated timeline-history {phase} shutdown"
        );
        thread::sleep(Duration::from_millis(100));
    }
}

fn safe_action(line: &str) -> &'static str {
    match line.split_whitespace().next().unwrap_or("") {
        "open-project" => "open-project",
        "create-thread" => "create-thread",
        "select-model" => "select-model",
        "send-prompt" => "send-prompt",
        "inspect-response" => "inspect-response",
        "stop-turn" => "stop-turn",
        "open-settings" => "open-settings",
        "edit-settings" => "edit-settings",
        "save-settings" => "save-settings",
        _ => "other",
    }
}

fn record_session_line(
    bots: Option<&bots_fixture::BotsFixture>,
    line: &str,
) -> Result<ManualOperation> {
    let at_unix_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |time| time.as_millis());
    let Some(bots) = bots else {
        return Ok(ManualOperation {
            at_unix_ms,
            action: safe_action(line),
            outcome: None,
        });
    };
    match bots_fixture::classify_line(line) {
        bots_fixture::EnvLine::GuiAction => Ok(ManualOperation {
            at_unix_ms,
            action: safe_action(line),
            outcome: None,
        }),
        bots_fixture::EnvLine::UnknownEnv => {
            println!(
                "Unknown bots environment command rejected; platform scripts and synthetic samples are unchanged."
            );
            Ok(ManualOperation {
                at_unix_ms,
                action: "env-command-rejected",
                outcome: Some("rejected"),
            })
        }
        bots_fixture::EnvLine::Registration(command) => {
            bots.apply_registration_env(command)?;
            println!(
                "Queued next mock registration poll ({}); this is not GUI authorization or a product pass.",
                command.action_code()
            );
            Ok(ManualOperation {
                at_unix_ms,
                action: command.action_code(),
                outcome: Some("script-set"),
            })
        }
        bots_fixture::EnvLine::Message(command) => {
            bots.apply_message_env(command)?;
            println!(
                "Queued one fixed synthetic direct message ({}) on the live platform websocket; queued for delivery is not product consumption, approval, execution, or a send pass.",
                command.action_code()
            );
            Ok(ManualOperation {
                at_unix_ms,
                action: command.action_code(),
                outcome: Some("event-queued"),
            })
        }
        bots_fixture::EnvLine::Conversations(command) => {
            bots.apply_conversations_env(command)?;
            println!(
                "Replaced the peer's synthetic conversation and history samples ({}); this is not GUI authorization or a product pass.",
                command.action_code()
            );
            Ok(ManualOperation {
                at_unix_ms,
                action: command.action_code(),
                outcome: Some("environment-set"),
            })
        }
    }
}

fn wait_for_ready(
    path: &Path,
    fixture: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
) -> Result<FixtureReady> {
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        if path.is_file() {
            let ready: FixtureReady = serde_json::from_slice(&fs::read(path)?).context(
                "fixture ready-file must contain base_url, ws_url and scenario JSON fields",
            )?;
            validate_ready(&ready)?;
            return Ok(ready);
        }
        ensure!(
            !fixture.exited()?,
            "fixture exited before writing ready-file"
        );
        ensure!(
            interrupt.try_recv().is_err(),
            "manual GUI cancelled while starting fixture"
        );
        ensure!(Instant::now() < deadline, "fixture ready-file timed out");
        thread::sleep(Duration::from_millis(200));
    }
}

fn validate_ready(ready: &FixtureReady) -> Result<()> {
    let remainder = ready
        .base_url
        .strip_prefix("http://127.0.0.1:")
        .context("fixture base_url must use IPv4 loopback")?;
    let (port, path) = remainder
        .split_once('/')
        .context("fixture base_url must end with /v1")?;
    ensure!(
        port.parse::<u16>().is_ok_and(|port| port != 0) && path == "v1",
        "fixture base_url must be http://127.0.0.1:<port>/v1"
    );
    ensure!(
        pl_provider_fixture::GUI_SCENARIOS.contains(&ready.scenario.as_str()),
        "unsupported fixture scenario"
    );
    ensure!(
        ready.ws_url == ready.base_url.replacen("http://", "ws://", 1),
        "fixture ws_url must use the same loopback endpoint"
    );
    Ok(())
}

/// Accept only closed copies: a live WAL cannot be copied with ordinary filesystem operations.
/// The source remains untouched; every modification happens inside the harness-owned environment.
fn copy_closed_home(source: &Path, target: &Path) -> Result<()> {
    ensure!(
        source.join("config.toml").is_file(),
        "copy config.toml is missing"
    );
    fn validate(path: &Path) -> Result<()> {
        for entry in fs::read_dir(path)? {
            let entry = entry?;
            let kind = entry.file_type()?;
            ensure!(
                !kind.is_symlink(),
                "links are not accepted in a migration copy"
            );
            if kind.is_dir() {
                validate(&entry.path())?;
            } else {
                let name = entry.file_name();
                let name = name.to_string_lossy();
                ensure!(
                    !name.ends_with("-wal") && !name.ends_with("-shm"),
                    "seed home must be a closed, SQLite-consistent copy"
                );
            }
        }
        Ok(())
    }
    validate(source)?;
    copy_startup_evidence(source, target)
}

fn write_copy_fixture_config(home: &Path, ready: &FixtureReady) -> Result<()> {
    // Run the normal protected startup migration on the isolated copy. ConfigStore::new uses an
    // in-memory credential store, so this does not hydrate or rewrite system credentials.
    {
        let runtime =
            ConfigRuntime::initialize(ConfigStore::new(ConfigPaths::from_config_dir(home)))?;
        drop(runtime);
    }
    // Read the migrated desired document strictly; never substitute effective runtime config.
    let mut config: StudioConfig = toml::from_str(&fs::read_to_string(home.join("config.toml"))?)?;
    for account in config.models.accounts.values_mut() {
        let models = account
            .effective_models(None)?
            .into_iter()
            .map(|mut model| {
                model
                    .binding
                    .set_transport(ModelTransportProfile::responses_http());
                model.binding.request.api_model = None;
                model
            })
            .collect();
        *account = AccountConfig::from_explicit_models(
            ProtocolEndpoint::compatible("Local migration fixture", &ready.base_url),
            models,
        );
    }
    let mcp_dir = home.join("mcp");
    if mcp_dir.is_dir() {
        fs::remove_dir_all(&mcp_dir)?;
    }
    config.lsp.servers.clear();
    config.acp = Default::default();
    // Bots have their own canonical documents. Disable them before runtime startup, including
    // each original identity, without deleting their ledger or touching its selected credential.
    let bots = home.join("data/bots");
    if bots.is_dir() {
        for entry in fs::read_dir(bots)? {
            let path = entry?.path().join("config.toml");
            if path.is_file() {
                let mut bot: toml::Table = toml::from_str(&fs::read_to_string(&path)?)?;
                bot.insert("enabled".into(), toml::Value::Boolean(false));
                fs::write(path, toml::to_string_pretty(&bot)?)?;
            }
        }
    }
    persist_config(home, &config)
}

/// This is the single writer every scenario (including the descendant
/// `shutdown` module) uses; the `web_search_fault` selector is only meaningful
/// for the `web-search` scenario, so the other callers pass `None`. Only the
/// ordinary GUI run requests a mixed explicit/inherited role fixture.
fn write_config(
    home: &Path,
    ready: &FixtureReady,
    web_search_fault: Option<&str>,
    ordinary_gui: bool,
) -> Result<()> {
    if pl_provider_fixture::delegation::Scenario::parse(&ready.scenario).is_some() {
        return delegation::write_config(home, ready);
    }
    if ready.scenario == "provider-usage" {
        return account_usage::write_config(home, ready);
    }
    if ready.scenario == "web-search" {
        let fault = match web_search_fault {
            None => web_search::WebSearchFault::None,
            Some(value) => web_search::WebSearchFault::parse(value)
                .with_context(|| format!("unknown web-search fault: {value}"))?,
        };
        return web_search::write_config(home, ready, fault);
    }
    let profile = if ready.scenario == "websocket-recovery" {
        ModelTransportProfile::responses_websocket()
    } else {
        ModelTransportProfile::responses_http()
    };
    write_config_with_profile(home, ready, profile, ordinary_gui)
}

fn write_config_with_profile(
    home: &Path,
    ready: &FixtureReady,
    profile: ModelTransportProfile,
    ordinary_gui: bool,
) -> Result<()> {
    let mut config = fixture_config(ready, profile)?;
    if ordinary_gui {
        let route = config.mode_model_route(&ThreadModeId::simple())?.clone();
        config
            .models
            .routes
            .insert(AgentRoleId::new("explorer")?, route);
    }
    persist_config(home, &config)
}

/// Writes the isolated home's config with one scenario-owned stdio MCP server.
///
/// The shutdown acceptance points this at its own fixture MCP peer so the
/// product starts it through the real supervised worker; the server itself
/// spawns a SIGTERM-ignoring grandchild the product must reclaim.
///
/// Private to `manual_gui`: only the descendant `shutdown` module calls it, and
/// keeping the visibility here means the private [`FixtureReady`] parameter does
/// not leak past its own visibility.
fn write_config_with_mcp_server(
    home: &Path,
    ready: &FixtureReady,
    server_id: &str,
    command: &Path,
    args: &[String],
) -> Result<()> {
    let config = fixture_config(ready, ModelTransportProfile::responses_http())?;
    config.validate()?;
    persist_config(home, &config)?;

    let host_mcp_dir = home.join("mcp/host");
    fs::create_dir_all(&host_mcp_dir)?;
    let doc = McpFileV1::new_server(
        server_id.to_owned(),
        StudioMcpServerEntry {
            enabled: true,
            transport: McpServerTransport::Stdio,
            command: Some(command.to_string_lossy().into_owned()),
            args: args.to_vec(),
            env: BTreeMap::new(),
            cwd: Some(home.to_string_lossy().into_owned()),
            url: None,
            bearer_token_env_var: None,
            headers: BTreeMap::new(),
            startup_timeout_secs: Some(30),
            tool_timeout_secs: None,
            enabled_tools: None,
            disabled_tools: Vec::new(),
        },
    );
    let filename = canonical_mcp_filename(server_id)?;
    fs::write(host_mcp_dir.join(filename), doc.encode()?)?;
    Ok(())
}

/// One scenario-owned `[lsp.servers.<id>]` entry to declare in an isolated home.
///
/// A named spec instead of a long positional argument list: the writer stays a
/// small call site and the fields carry their own meaning at construction.
pub(super) struct LspServerSpec<'a> {
    /// The `[lsp.servers.<id>]` key; must be unique across the catalog.
    pub(super) id: &'a str,
    /// Server program (the fixture binary in `--lsp-stdio` mode).
    pub(super) command: &'a Path,
    /// Program arguments (the mode flag and coordination file path).
    pub(super) args: &'a [String],
    /// The unique language id the server answers. Must not be a builtin id
    /// (the builtin rust-analyzer already owns `rust`) or the merge fails loud.
    pub(super) language_id: &'a str,
    /// Workspace detection rules; empty means "all workspaces".
    pub(super) detection: &'a [String],
    /// File extensions the server claims; empty means none.
    pub(super) extensions: &'a [String],
}

/// Writes the isolated home's config with one scenario-owned `[lsp.servers.<id>]`
/// entry.
///
/// The shutdown acceptance points this at its own fake LSP peer (the fixture
/// binary in `--lsp-stdio` mode) so the product starts it through the real
/// supervised worker when the model issues an `lsp_query`; the server itself
/// spawns a SIGTERM-ignoring grandchild the product must reclaim.
///
/// The entry is injected into the serialized base config instead of naming
/// `pl_lsp::catalog::LspUserServerConfig` directly, so this acceptance tool does
/// not need a new crate dependency edge (and cannot drift a second LSP config
/// fact source: `StudioConfig` remains the single typed owner).
///
/// Private to `manual_gui` (only the descendant `shutdown` module uses it) so
/// the private [`FixtureReady`] parameter stays within its own visibility.
fn write_config_with_lsp_server(
    home: &Path,
    ready: &FixtureReady,
    spec: &LspServerSpec<'_>,
) -> Result<()> {
    let config = fixture_config(ready, ModelTransportProfile::responses_http())?;
    // Round-trip through a `toml::Table` so the injected entry is identical to
    // what `persist_config` / the runtime would read back from `config.toml`.
    let mut table: toml::Table = toml::from_str(&toml::to_string(&config)?)
        .context("failed to round-trip the isolated config for the LSP entry")?;
    let lsp = table
        .entry("lsp".to_owned())
        .or_insert_with(|| toml::Value::Table(toml::Table::new()));
    let lsp = lsp.as_table_mut().context("`lsp` is not a TOML table")?;
    let servers = lsp
        .entry("servers".to_owned())
        .or_insert_with(|| toml::Value::Table(toml::Table::new()));
    let servers = servers
        .as_table_mut()
        .context("`lsp.servers` is not a TOML table")?;
    let mut entry = toml::Table::new();
    entry.insert(
        "command".to_owned(),
        toml::Value::String(spec.command.to_string_lossy().into_owned()),
    );
    entry.insert(
        "args".to_owned(),
        toml::Value::Array(spec.args.iter().cloned().map(toml::Value::String).collect()),
    );
    entry.insert(
        "language_ids".to_owned(),
        toml::Value::Array(vec![toml::Value::String(spec.language_id.to_owned())]),
    );
    entry.insert(
        "detection".to_owned(),
        toml::Value::Array(
            spec.detection
                .iter()
                .cloned()
                .map(toml::Value::String)
                .collect(),
        ),
    );
    entry.insert(
        "extensions".to_owned(),
        toml::Value::Array(
            spec.extensions
                .iter()
                .cloned()
                .map(toml::Value::String)
                .collect(),
        ),
    );
    servers.insert(spec.id.to_owned(), toml::Value::Table(entry));
    let config: StudioConfig = toml::from_str(&toml::to_string(&table)?)
        .context("failed to rebuild the config with the LSP entry")?;
    persist_config(home, &config)
}

/// Builds the standalone fixture with Cargo's release profile before service
/// deadlines; GUI build mode is independent. Cargo owns artifact discovery, so
/// its configured target directory and native executable suffix are not guessed.
fn build_fixture_executable(workspace: &Path) -> Result<PathBuf> {
    const PACKAGE: &str = "pl-provider-fixture";
    let args = [
        "build",
        "--release",
        "--locked",
        "-p",
        PACKAGE,
        "--bin",
        PACKAGE,
    ];
    let mut build = Command::new("cargo");
    build.current_dir(workspace).args(args);
    process::run_checked(
        &mut build,
        "cargo build --release --locked -p pl-provider-fixture --bin pl-provider-fixture",
    )?;

    let discovery = Command::new("cargo")
        .current_dir(workspace)
        .args(args)
        .arg("--message-format=json")
        .output()
        .context("failed to query Cargo for the account fixture executable")?;
    ensure!(
        discovery.status.success(),
        "failed to locate the account fixture executable: {}",
        String::from_utf8_lossy(&discovery.stderr)
    );
    for line in String::from_utf8_lossy(&discovery.stdout).lines() {
        let Ok(record) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        let target = &record["target"];
        if record["reason"] == "compiler-artifact"
            && target["name"] == PACKAGE
            && target["kind"]
                .as_array()
                .is_some_and(|kinds| kinds.iter().any(|kind| kind == "bin"))
            && let Some(executable) = record["executable"].as_str()
        {
            let executable = PathBuf::from(executable);
            ensure!(
                executable.is_file(),
                "Cargo fixture executable is missing: {}",
                executable.display()
            );
            return Ok(executable);
        }
    }
    bail!("Cargo reported no account fixture bin executable")
}

/// Builds the isolated acceptance config without persisting it, so every writer
/// shares one model/account/route fact source.
fn fixture_config(ready: &FixtureReady, profile: ModelTransportProfile) -> Result<StudioConfig> {
    let mut config = StudioConfig::default_config()?;
    let mut model = ModelInfo::compatible("fixture-model");
    model.capabilities.interleaved = Some(pl_model::model::ReasoningInterleaved {
        field: pl_model::model::ReasoningInterleavedField::ReasoningContent,
    });
    model.display_name = "Local GUI fixture".into();
    if matches!(
        ready.scenario.as_str(),
        "timeline-history" | "timeline-history-20k"
    ) {
        model.context_window = Some(1_050_000);
        model.max_context_window = Some(1_050_000);
        model.max_output_tokens = Some(128_000);
    }
    if matches!(
        ready.scenario.as_str(),
        "storage-compaction" | "call-lifecycle-recovery" | "plan-recovery"
    ) {
        model.context_window = Some(1_000_000);
        model.max_context_window = Some(1_000_000);
        model.auto_compact_token_limit = Some(1);
    }
    model.binding.set_transport(profile);
    model.binding.request.api_model = None;
    if matches!(ready.scenario.as_str(), "tool-scroll" | "timeline-concept") {
        model.capabilities.input.push(ModelInputCapability::media(
            ModelModality::Image,
            vec![ModelInputSource::Local],
        ));
        model.binding.request.media.push(ModelMediaInputProfile {
            modality: ModelModality::Image,
            wire: MediaWireFormat::ResponsesInputImage,
            first_send: vec![MediaRepresentation::DataUrl],
            replay: vec![MediaRepresentation::DataUrl],
        });
    }
    let provider_id = AccountId::new(format!("gui-fixture-{}", std::process::id()))?;
    let mut endpoint = ProtocolEndpoint::compatible("Local GUI fixture", &ready.base_url);
    endpoint.service_capabilities.remote_compaction = matches!(
        ready.scenario.as_str(),
        "call-lifecycle-recovery" | "timeline-concept"
    );
    let mut models = vec![model];
    if ready.scenario == "gui" {
        // Distinct metadata in the same isolated account exercises the real
        // settings projection without creating system credential accounts.
        let mut preset = models[0].clone();
        preset.model_id = "fixture-preset".into();
        preset.display_name = "Fixture with a model preset".into();
        preset.context_window = Some(64_000);
        preset.max_context_window = Some(64_000);
        preset.auto_compact_token_limit = Some(24_000);
        preset.capabilities.input.push(ModelInputCapability::media(
            ModelModality::Image,
            vec![ModelInputSource::Local],
        ));
        preset.binding.request.media.push(ModelMediaInputProfile {
            modality: ModelModality::Image,
            wire: MediaWireFormat::ResponsesInputImage,
            first_send: vec![MediaRepresentation::DataUrl],
            replay: vec![MediaRepresentation::DataUrl],
        });
        let mut file_input =
            ModelInputCapability::media(ModelModality::File, vec![ModelInputSource::Local]);
        file_input.limits.media_types = vec!["application/pdf".into()];
        preset.capabilities.input.push(file_input);
        preset.binding.request.media.push(ModelMediaInputProfile {
            modality: ModelModality::File,
            wire: MediaWireFormat::ResponsesInputFile,
            first_send: vec![MediaRepresentation::DataUrl],
            replay: vec![MediaRepresentation::DataUrl],
        });
        let mut unknown = models[0].clone();
        unknown.model_id = "fixture-unknown".into();
        unknown.display_name = "Fixture with unknown context capacity".into();
        unknown.context_window = None;
        unknown.max_context_window = None;
        unknown.auto_compact_token_limit = None;
        models.extend([preset, unknown]);
    }
    let account = AccountConfig::from_explicit_models(endpoint, models);
    config.models.accounts.clear();
    config.models.accounts.insert(provider_id.clone(), account);
    for route in config
        .models
        .routes
        .values_mut()
        .chain(config.mode_model_routes.values_mut())
    {
        route.account_id = provider_id.clone();
        route.model_id = "fixture-model".into();
        route.effort = None;
    }
    Ok(config)
}

/// Validates and persists an isolated config document.
fn persist_config(home: &Path, config: &StudioConfig) -> Result<()> {
    config.validate()?;
    let file = home.join("config.toml");
    fs::write(&file, toml::to_string_pretty(config)?)
        .with_context(|| format!("failed to create isolated config: {}", file.display()))
}

/// Reads the persisted explicit overrides afresh; effective inherited routes
/// belong to the Driver's separate canonical snapshots.
fn write_explicit_role_route_evidence(
    home: &Path,
    output: &Path,
    run_id: &str,
    capture_state: ExplicitRoleRouteCaptureState,
) -> Result<()> {
    let config: StudioConfig = toml::from_str(&fs::read_to_string(home.join("config.toml"))?)?;
    let explicit_role_routes = config
        .models
        .routes
        .iter()
        .map(|(key, route)| ExplicitRoleRouteRow {
            key: key.as_str().to_owned(),
            account_id: route.account_id.as_str().to_owned(),
            model_id: route.model_id.clone(),
            effort: route
                .effort
                .as_ref()
                .map(|effort| effort.as_str().to_owned()),
        })
        .collect();
    let (phase, file) = match capture_state {
        ExplicitRoleRouteCaptureState::Initialized => ("before", EXPLICIT_ROLE_ROUTES_BEFORE_FILE),
        ExplicitRoleRouteCaptureState::SessionOk | ExplicitRoleRouteCaptureState::SessionError => {
            ("after", EXPLICIT_ROLE_ROUTES_AFTER_FILE)
        }
    };
    let evidence = ExplicitRoleRouteEvidence {
        schema: 1,
        scenario: "gui",
        run_id,
        phase,
        capture_state,
        explicit_role_routes,
    };
    fs::write(output.join(file), serde_json::to_vec_pretty(&evidence)?)?;
    Ok(())
}

fn publish_explicit_role_route_evidence_marker(run_id: &str) -> Result<()> {
    let marker = serde_json::to_string(&ExplicitRoleRouteEvidenceMarker {
        schema: 1,
        run_id,
        harness_pid: std::process::id(),
        before_file: EXPLICIT_ROLE_ROUTES_BEFORE_FILE,
    })?;
    let mut stdout = io::stdout().lock();
    writeln!(stdout, "ANYWORK_ACCOUNT_ROLE_EVIDENCE {marker}")?;
    stdout.flush()?;
    Ok(())
}

fn keep_isolated_environment(
    working: tempfile::TempDir,
    home: &Path,
    output: &Path,
    project: Option<&Path>,
) -> Result<()> {
    let root = working.keep();
    let mut evidence = serde_json::json!({"root": root, "home": home});
    if let Some(project) = project {
        evidence["project"] = serde_json::Value::String(project.display().to_string());
    }
    fs::write(
        output.join("retained-environment.json"),
        serde_json::to_vec_pretty(&evidence)?,
    )?;
    Ok(())
}

/// Copies the isolated home config into evidence after stripping credential values.
///
/// Field names stay so reviewers can see which secret slots existed; values that
/// can hold keys, tokens or header/env secrets become `[redacted]`.
fn copy_sanitized_config(home: &Path, destination: &Path) -> Result<()> {
    let source = home.join("config.toml");
    if !source.is_file() {
        eprintln!(
            "isolated config missing after GUI session: {}",
            source.display()
        );
        return Ok(());
    }
    let mut config: toml::Table = toml::from_str(&fs::read_to_string(&source)?)
        .with_context(|| format!("failed to parse isolated config {}", source.display()))?;
    redact_config_secrets(&mut config);
    fs::write(
        destination,
        format!("{}\n", toml::to_string_pretty(&config)?),
    )
    .with_context(|| format!("failed to write sanitized config {}", destination.display()))
}

fn redact_config_secrets(value: &mut toml::Table) {
    const SECRET_KEYS: &[&str] = &["bearer_token", "bearer_token_env", "bearer_token_env_var"];
    for (key, child) in value.iter_mut() {
        if SECRET_KEYS.contains(&key.as_str()) {
            if !matches!(child, toml::Value::String(text) if text == "[redacted]") {
                *child = toml::Value::String("[redacted]".into());
            }
            continue;
        }
        match child {
            toml::Value::Table(table) => {
                if key == "http_headers" || key == "headers" || key == "env" {
                    let nested_keys: Vec<_> = table.keys().cloned().collect();
                    for nested_key in nested_keys {
                        table.insert(nested_key, toml::Value::String("[redacted]".into()));
                    }
                } else {
                    redact_config_secrets(table);
                }
            }
            toml::Value::Array(items) => {
                for item in items {
                    if let toml::Value::Table(table) = item {
                        redact_config_secrets(table);
                    }
                }
            }
            _ => {}
        }
    }
}

fn wait_for_vm(
    path: &Path,
    gui: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
) -> Result<String> {
    let deadline = Instant::now() + Duration::from_secs(600);
    loop {
        let log = fs::read_to_string(path)?;
        if let Some(url) = vm_service_url(&log) {
            return Ok(url);
        }
        ensure!(!gui.exited()?, "GUI exited before publishing VM service");
        ensure!(
            !fixture.exited()?,
            "account fixture exited while GUI started"
        );
        ensure!(
            interrupt.try_recv().is_err(),
            "manual GUI cancelled while starting GUI"
        );
        ensure!(
            Instant::now() < deadline,
            "GUI VM service startup timed out"
        );
        thread::sleep(Duration::from_millis(300));
    }
}

/// Extracts the VM service URL a GUI launcher published in its log.
///
/// The Flutter launch tool names the Dart VM Service; its DevTools URL can use
/// the same host and port but is not a VM endpoint. A directly launched
/// debug/profile artifact prints the engine's own listening announcement.
fn vm_service_url(log: &str) -> Option<String> {
    log.lines()
        .filter_map(|line| {
            line.split("A Dart VM Service on ")
                .nth(1)
                .and_then(|line| line.split(" is available at: http://127.0.0.1:").nth(1))
                .or_else(|| {
                    line.split("The Dart VM service is listening on http://127.0.0.1:")
                        .nth(1)
                })
                .map(|tail| {
                    format!(
                        "http://127.0.0.1:{}",
                        tail.split_whitespace().next().unwrap_or("")
                    )
                })
        })
        .next_back()
}

fn seed_startup_fault(home: &Path, fault: &str) -> Result<()> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(async {
        let studio =
            pl_studio_runtime::StudioRuntime::initialize(pl_studio_runtime::StudioRuntimeOptions {
                studio_home: Some(home.to_owned()),
                host: pl_studio_runtime::StudioHostKind::Test,
                ..pl_studio_runtime::StudioRuntimeOptions::desktop()
            })
            .await?;
        studio.shutdown_runtime().await?;
        Ok::<_, anyhow::Error>(())
    })?;
    fs::create_dir_all(home.join("sessions/old"))?;
    fs::write(home.join("sessions/old/retained"), b"old session")?;
    match fault {
        "config" => fs::write(home.join("config.toml"), b"schema_version = invalid"),
        "database" => fs::write(home.join("data/studio.sqlite"), b"invalid database"),
        "log" => fs::write(home.join("data/calls/logs/calls-0000020000-000001.jsonl"), b"invalid complete record\n"),
        "cache" => fs::write(home.join("data/settings.toml"), b"schemaVersion = 1\nrevision = 2\n[[entries]]\nkey = 'observed:providerUsage:v2'\nvalue = 'invalid JSON'\nupdatedAt = 1\n"),
        _ => bail!("unknown startup fault"),
    }?;
    Ok(())
}

fn copy_startup_evidence(source: &Path, target: &Path) -> Result<()> {
    fs::create_dir(target)?;
    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let kind = entry.file_type()?;
        ensure!(
            !kind.is_symlink(),
            "unexpected link in isolated recovery evidence"
        );
        if kind.is_dir() {
            copy_startup_evidence(&entry.path(), &target.join(entry.file_name()))?;
        } else {
            fs::copy(entry.path(), target.join(entry.file_name()))?;
        }
    }
    Ok(())
}

/// Host-side capture against an already-running GUI VM.
///
/// Reuses the app package mapping so native build hooks are not re-entered.
fn capture_command(app_dir: &Path) -> Command {
    let mut command = process::path_command(
        "dart",
        &["--packages=.dart_tool/package_config.json".into()],
    );
    command.current_dir(app_dir).arg("tool/capture_ui.dart");
    command
}

pub(super) fn capture(
    app_dir: &Path,
    _home: &Path,
    vm_url: &str,
    output: &Path,
    interrupt: &mpsc::Receiver<()>,
    exit_native: bool,
) -> Result<()> {
    let png = output.join("screenshot.png");
    let log_path = output.join("capture.log");
    let log = File::create(&log_path)?;
    let mut command = capture_command(app_dir);
    command
        .args(["--vm-url", vm_url, "--output"])
        .arg(&png)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    if exit_native {
        command.arg("--exit");
    }
    let mut capture = OwnedProcess::start(&mut command, false)?;
    let deadline = Instant::now() + Duration::from_secs(120);
    loop {
        if let Some(status) = capture.child.try_wait()? {
            ensure!(
                status.success(),
                "content capture or shutdown failed ({status}); see {}; human verdict pending",
                log_path.display()
            );
            fs::write(
                output.join("capture-stage.txt"),
                if exit_native {
                    "shutdown_completed\n"
                } else {
                    "screenshot_captured\n"
                },
            )?;
            return Ok(());
        }
        ensure!(
            interrupt.try_recv().is_err(),
            "manual GUI cancelled while capturing evidence"
        );
        ensure!(
            Instant::now() < deadline,
            "content capture or shutdown timed out"
        );
        thread::sleep(Duration::from_millis(200));
    }
}

/// Requests a coordinated native exit without writing a PNG.
pub(super) fn request_app_exit(
    app_dir: &Path,
    vm_url: &str,
    log_path: &Path,
    interrupt: &mpsc::Receiver<()>,
) -> Result<()> {
    let log = File::create(log_path)?;
    let mut command = capture_command(app_dir);
    command
        .args(["--vm-url", vm_url, "--exit"])
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    let mut capture = OwnedProcess::start(&mut command, false)?;
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        if let Some(status) = capture.child.try_wait()? {
            ensure!(
                status.success(),
                "requestExit failed ({status}); see {}",
                log_path.display()
            );
            return Ok(());
        }
        ensure!(interrupt.try_recv().is_err(), "requestExit cancelled");
        ensure!(Instant::now() < deadline, "requestExit timed out");
        thread::sleep(Duration::from_millis(100));
    }
}

/// Waits for the operator to type `done` while the GUI and optional fixture stay up.
fn wait_operator_done(
    prompt: &str,
    gui: &mut OwnedProcess,
    mut fixture: Option<&mut OwnedProcess>,
    interrupt: &mpsc::Receiver<()>,
    timeout: Duration,
) -> Result<()> {
    println!("{prompt}");
    println!("Type done when the observation is complete. Ctrl-C cancels.");
    let (input_tx, input_rx) = mpsc::channel();
    thread::spawn(move || {
        loop {
            let mut input = String::new();
            match io::stdin().read_line(&mut input) {
                Ok(0) | Err(_) => {
                    let _ = input_tx.send(InputEvent::Eof);
                    break;
                }
                Ok(_) if input.trim() == "done" => {
                    let _ = input_tx.send(InputEvent::Done);
                    break;
                }
                Ok(_) => {
                    if input_tx.send(InputEvent::Line(input)).is_err() {
                        break;
                    }
                }
            }
        }
    });
    let deadline = Instant::now() + timeout;
    loop {
        match input_rx.try_recv() {
            Ok(InputEvent::Done) => return Ok(()),
            Ok(InputEvent::Eof) | Err(mpsc::TryRecvError::Disconnected) => {
                bail!("operator input closed before done")
            }
            Ok(InputEvent::Line(_)) => {}
            Err(mpsc::TryRecvError::Empty) => {}
        }
        ensure!(!gui.exited()?, "GUI exited before the operator finished");
        if let Some(fixture) = fixture.as_mut() {
            ensure!(
                !fixture.exited()?,
                "account fixture exited before the operator finished"
            );
        }
        ensure!(
            interrupt.try_recv().is_err(),
            "operator observation cancelled"
        );
        ensure!(Instant::now() < deadline, "operator observation timed out");
        thread::sleep(Duration::from_millis(100));
    }
}

/// Operator runbook, then a coordinated capture and native exit.
fn observe_capture_exit(
    app_dir: &Path,
    vm_url: &str,
    output: &Path,
    interrupt: &mpsc::Receiver<()>,
    gui: &mut OwnedProcess,
    fixture: Option<&mut OwnedProcess>,
    prompt: &str,
) -> Result<()> {
    wait_operator_done(prompt, gui, fixture, interrupt, Duration::from_secs(3_600))?;
    capture(app_dir, Path::new(""), vm_url, output, interrupt, true)?;
    Ok(())
}

fn run_statistics_scenario(
    context: &StatisticsScenario<'_>,
    mut fixture: OwnedProcess,
) -> Result<()> {
    let StatisticsScenario {
        workspace,
        app_dir,
        home,
        working,
        output,
        fixture_log,
        requests_file,
        report_file,
        interrupt,
    } = context;
    let first_log = working.join("statistics-first-gui.log");
    let restart_log = working.join("statistics-restart-gui.log");
    let project = working.join("statistics-project");
    let journey = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated statistics project"
        );
        {
            let mut gui = start_statistics_gui(workspace, home, &first_log)?;
            let vm_url = wait_for_vm(&first_log, &mut gui, &mut fixture, interrupt)?;
            observe_capture_exit(
                app_dir,
                &vm_url,
                output,
                interrupt,
                &mut gui,
                Some(&mut fixture),
                &format!(
                    "statistics first: open {}, send two durable turns, then type done.",
                    project.display()
                ),
            )?;
            let _ = wait_for_gui_exit(&mut gui, Duration::from_secs(120), "first")?;
        }
        let before = statistics_db_counts(home)?;
        ensure!(
            before.committed_calls >= 2 && before.performance_samples >= 1,
            "statistics calls.sqlite did not record both calls: {before:?}"
        );
        fs::write(
            output.join("statistics-db-before-restart.json"),
            serde_json::to_vec_pretty(&before)?,
        )?;
        {
            let mut gui = start_statistics_gui(workspace, home, &restart_log)?;
            let vm_url = wait_for_vm(&restart_log, &mut gui, &mut fixture, interrupt)?;
            observe_capture_exit(
                app_dir,
                &vm_url,
                output,
                interrupt,
                &mut gui,
                Some(&mut fixture),
                "statistics restart: reopen the same home, confirm restored statistics, then type done.",
            )?;
            let _ = wait_for_gui_exit(&mut gui, Duration::from_secs(120), "restart")?;
        }
        let after = statistics_db_counts(home)?;
        fs::write(
            output.join("statistics-db-after-restart.json"),
            serde_json::to_vec_pretty(&after)?,
        )?;
        ensure!(
            before == after,
            "calls.sqlite changed across restart: {before:?} -> {after:?}"
        );
        Ok(())
    })();

    for (source, name) in [
        (&first_log, "statistics-first-gui.log"),
        (&restart_log, "statistics-restart-gui.log"),
    ] {
        if source.exists() {
            write_sanitized_log(source, &output.join(name))?;
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
    let stream: Option<pl_provider_fixture::StressReport> = if report_file.is_file() {
        serde_json::from_slice(&fs::read(report_file)?)?
    } else {
        None
    };
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "statistics", "acceptedRequests": accepted, "rejectedRequests": rejected,
            "emittedEvents": stream.as_ref().map(|row| row.emitted_events),
            "elapsedMillis": stream.as_ref().map(|row| row.elapsed_millis),
            "completed": fixture_result.as_ref().is_ok_and(|status| status.success()),
        }))?,
    )?;
    let errors = [first_log, restart_log]
        .iter()
        .filter(|path| path.is_file())
        .map(|path| count_gui_errors(path))
        .collect::<Result<Vec<_>>>()?
        .into_iter()
        .sum::<usize>();
    fs::write(
        output.join("gui-health.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "unhandledErrors": errors, "humanVerdict": "pending"
        }))?,
    )?;
    println!("Evidence: {} (human verdict pending)", output.display());
    journey?;
    ensure!(
        fixture_result.is_ok_and(|status| status.success())
            && accepted >= 2
            && rejected == 0
            && stream.as_ref().is_some_and(|row| {
                row.emitted_events == pl_provider_fixture::GUI_STATISTICS_PACED_EVENTS
                    && row.elapsed_millis >= 800
            })
            && errors == 0,
        "statistics fixture or GUI health incomplete; human verdict pending"
    );
    Ok(())
}

fn run_model_catalog_restart(
    context: &ModelCatalogRestart<'_>,
    gui: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
) -> Result<()> {
    let ModelCatalogRestart {
        workspace,
        home,
        output,
        working,
        control_path,
        hits_a_path,
        hits_b_path,
        ready,
        interrupt,
    } = context;
    let port = model_catalog::bind_port(&ready.base_url)?;
    let phase_a =
        model_catalog::wait_for_online_cache(home, model_catalog::phase_a_expectation(), None)?;
    fs::write(
        output.join("model-catalog-phase-a.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "checkedAt": phase_a.checked_at,
            "present": model_catalog::phase_a_expectation().present,
            "cachePath": phase_a.cache_path,
        }))?,
    )?;
    gui.terminate();
    let requests = working.join("requests.json");
    fixture
        .stop(&requests)
        .context("phase-A fixture did not write requests-file after graceful signal")?;
    fixture.terminate();
    model_catalog::copy_hits(
        hits_a_path,
        &output.join("model-catalog-requests-a.json"),
        true,
    )?;
    copy_sanitized_config(home, &output.join("config-phase-a.toml"))?;
    model_catalog::rewrite_inventory_b(control_path)?;
    let requests_restart = working.join("requests-restart.json");
    let fixture_restart_log = working.join("fixture-restart.log");
    *fixture = start_catalog_fixture(
        workspace,
        working,
        control_path,
        hits_b_path,
        Some(port),
        interrupt,
    )?;
    let phase_b_log = working.join("catalog-phase-b-gui.log");
    *gui = start_catalog_phase_b_gui(workspace, home, &phase_b_log)?;
    let journey = (|| -> Result<(i64, i64)> {
        wait_for_vm(&phase_b_log, gui, fixture, interrupt)?;
        let phase_b = model_catalog::wait_for_online_cache(
            home,
            model_catalog::phase_b_expectation(),
            Some(phase_a.checked_at),
        )?;
        model_catalog::assert_route_preserved(home)?;
        fs::write(
            output.join("model-catalog-phase-b.json"),
            serde_json::to_vec_pretty(&serde_json::json!({
                "checkedAt": phase_b.checked_at,
                "present": model_catalog::phase_b_expectation().present,
                "absent": model_catalog::phase_b_expectation().absent,
                "samePort": port,
                "cachePath": phase_b.cache_path,
            }))?,
        )?;
        Ok((phase_a.checked_at, phase_b.checked_at))
    })();
    if let Err(error) = fixture.stop(&requests_restart) {
        eprintln!("phase-B fixture stop failed: {error}");
    }
    fixture.terminate();
    model_catalog::copy_hits(
        hits_b_path,
        &output.join("model-catalog-requests-b.json"),
        true,
    )?;
    copy_sanitized_config(home, &output.join("config-phase-b.toml"))?;
    if phase_b_log.is_file() {
        write_sanitized_log(&phase_b_log, &output.join("catalog-phase-b-gui.log"))?;
    }
    if fixture_restart_log.is_file() {
        write_fixture_log(&fixture_restart_log, &output.join("fixture-restart.log"))?;
    }
    if requests_restart.is_file() {
        sanitize_requests(&requests_restart, &output.join("requests-restart.json"))?;
    }
    let (phase_a_checked, phase_b_checked) = journey?;
    println!(
        "Model catalog restart journey passed (port {port}, checkedAt {phase_a_checked} -> {phase_b_checked})"
    );
    Ok(())
}

fn start_catalog_fixture(
    workspace: &Path,
    working: &Path,
    control_path: &Path,
    hits_path: &Path,
    port: Option<u16>,
    interrupt: &mpsc::Receiver<()>,
) -> Result<OwnedProcess> {
    let executable = build_fixture_executable(workspace)?;
    let ready_file = working.join("fixture-ready-restart.json");
    let _ = fs::remove_file(&ready_file);
    let requests_file = working.join("requests-restart.json");
    let log_path = working.join("fixture-restart.log");
    let log = File::create(&log_path)?;
    let mut command = Command::new(executable);
    command
        .current_dir(workspace)
        .args(["--scenario", "gui", "--ready-file"])
        .arg(&ready_file)
        .arg("--requests-file")
        .arg(&requests_file)
        .arg("--model-catalog-control")
        .arg(control_path)
        .arg("--model-catalog-requests")
        .arg(hits_path)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    if let Some(port) = port {
        command.arg("--bind-port").arg(port.to_string());
    }
    let mut fixture = OwnedProcess::start(&mut command, true)?;
    wait_for_ready(&ready_file, &mut fixture, interrupt)?;
    Ok(fixture)
}

fn start_statistics_gui(workspace: &Path, home: &Path, log_path: &Path) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    command
        .current_dir(workspace)
        .args(["xtask", "run-gui", "--capture"])
        .env("ANYWORK_HOME", home)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    OwnedProcess::start(&mut command, false)
}

fn start_catalog_phase_b_gui(
    workspace: &Path,
    home: &Path,
    log_path: &Path,
) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    command
        .current_dir(workspace)
        .args(["xtask", "run-gui", "--capture", "--log-level", "info"])
        .env("ANYWORK_HOME", home)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    OwnedProcess::start(&mut command, false)
}

fn statistics_db_counts(home: &Path) -> Result<StatisticsDbCounts> {
    let database = home.join("data/calls/calls.sqlite");
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(async move {
        let options = SqliteConnectOptions::new()
            .filename(&database)
            .read_only(true);
        let mut connection = SqliteConnection::connect_with(&options).await?;
        let (rows, committed, samples): (i64, i64, i64) = sea_orm::sqlx::query_as(
            "SELECT (SELECT COUNT(*) FROM call_log_index WHERE kind='attempt'),
                    COUNT(*),
                    COALESCE(SUM(CASE WHEN response_millis>0 AND output_tokens IS NOT NULL THEN 1 ELSE 0 END),0)
             FROM performance_samples",
        )
        .fetch_one(&mut connection)
        .await
        .with_context(|| format!("failed to count model calls in {}", database.display()))?;
        Ok(StatisticsDbCounts {
            model_calls: rows.try_into()?,
            committed_calls: committed.try_into()?,
            performance_samples: samples.try_into()?,
        })
    })
}

/// Non-optional steps in the realtime fixture script.
///
/// The fixture only verifies after every one of them is consumed, so a
/// successful run accepts at least this many requests; the count also fails the
/// journey if the script silently stops exercising the realtime states. A tool
/// command is more than one request: the assistant `exec` call, the scripted
/// model's supported `wait` on the task receipt, and the step that observes the
/// delivered result (the two parallel commands add one extra `wait` for the
/// still-running task). The host-cwd command uses the product's fixed full-access policy.
const REALTIME_REQUIRED_STEPS: usize = 15;

/// Fixed plain-fmt fragment of the §24.3 producer credit-wait diagnostic line.
///
/// The GUI's tracing subscriber prints with `with_target(true)`, so every real
/// `producer_credit_wait_pending` event carries this exact target/message/field
/// prefix and the compact `credit_wait` JSON runs to the end of the line; no
/// other part of the line (timestamp, thread id) is relied upon.
const REALTIME_CREDIT_WAIT_MARKER: &str =
    "anywork::conversation_credit: producer_credit_wait_pending credit_wait=";
/// Upper bound for one archived `credit_wait` JSON payload.
const REALTIME_CREDIT_WAIT_MAX_LINE_BYTES: usize = 4096;
/// Whole-record budget — fmt prefix and terminating newline included — for one
/// studio log line read.
const REALTIME_CREDIT_WAIT_MAX_RECORD_BYTES: usize = 8 * 1024;
/// Upper bound for credit-wait observations archived from one run.
const REALTIME_CREDIT_WAIT_MAX_OBSERVATIONS: usize = 2048;
/// Numbered studio log rotations production retains (`writer.rs`
/// `ARCHIVED_LOG_FILES`); the ring shifts by one on every rollover and drops
/// the oldest slot, so a full ring can never prove older files survived.
const REALTIME_CREDIT_WAIT_MAX_ROTATIONS: usize = 7;

/// One §24.3 credit-wait observation: the bounded producer metadata.
///
/// The same private shape decodes and archives the producer metadata without
/// reconstructing its subscription identity or counters.
/// `deny_unknown_fields` keeps the contract at these three fields:
/// missing or unexpected fields are capture errors, never silently reshaped or
/// defaulted into fabricated counters.
#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CreditWaitObservation {
    subscription_id: String,
    sent: u64,
    acknowledged: u64,
}

/// Bounded §24.3 evidence archived as `output/frb-credit-wait.json`.
///
/// Capture problems never abort the harness early: they stay in this record so
/// the realtime cleanup always runs and the strict judgment rejects a recorded,
/// reviewable fact instead of accepting a fabricated empty pass.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CreditWaitEvidence {
    schema: &'static str,
    source: &'static str,
    observations: Vec<CreditWaitObservation>,
    truncated: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    capture_error: Option<String>,
}

/// Scans the isolated home's studio log ring (the live `studio.log` plus its
/// numbered rotations, read live-first then by ascending rotation number for
/// stable evidence) for the fixed §24.3 producer credit-wait lines.
///
/// Only the bounded `credit_wait` metadata is archived; production log lines
/// are never copied out. Missing logs, malformed JSON, impossible counters
/// (sent < acknowledged, difference other than two, empty subscription), an
/// oversized payload or record, a rotation gap, a retention-boundary ring, or
/// more than [`REALTIME_CREDIT_WAIT_MAX_OBSERVATIONS`] observations are
/// preserved as `captureError`/`truncated` for the strict judgment to reject —
/// never silently dropped to look complete.
fn capture_realtime_credit_wait(home: &Path) -> CreditWaitEvidence {
    let mut evidence = CreditWaitEvidence {
        schema: "anywork-frb-credit-wait/1",
        source: "real-frb-producer-poll",
        observations: Vec::new(),
        truncated: false,
        capture_error: None,
    };
    let logs_root = home.join("studio").join("logs");
    let mut live_log: Option<PathBuf> = None;
    let mut rotations: Vec<(u32, PathBuf)> = Vec::new();
    match fs::read_dir(&logs_root) {
        Ok(entries) => {
            for entry in entries {
                let path = match entry {
                    Ok(entry) => entry.path(),
                    Err(error) => {
                        record_credit_wait_error(
                            &mut evidence.capture_error,
                            format!(
                                "cannot read a studio log directory entry in {}: {error}",
                                logs_root.display()
                            ),
                        );
                        continue;
                    }
                };
                // The name check is pure path work; only the current
                // production ring enters the scan, so a metadata problem below
                // is always about a log this capture intended to read.
                let Some(position) = path
                    .file_name()
                    .and_then(|name| name.to_str())
                    .and_then(credit_wait_log_position)
                else {
                    continue;
                };
                match fs::metadata(&path) {
                    Ok(metadata) if metadata.is_file() => {
                        if position == 0 {
                            live_log.get_or_insert(path);
                        } else {
                            rotations.push((position, path));
                        }
                    }
                    Ok(_) => {}
                    Err(error) => {
                        record_credit_wait_error(
                            &mut evidence.capture_error,
                            format!("cannot stat studio log {}: {error}", path.display()),
                        );
                    }
                }
            }
        }
        Err(error) => {
            record_credit_wait_error(
                &mut evidence.capture_error,
                format!(
                    "cannot read studio log directory {}: {error}",
                    logs_root.display()
                ),
            );
            return evidence;
        }
    };
    if live_log.is_none() && rotations.is_empty() {
        record_credit_wait_error(
            &mut evidence.capture_error,
            format!("no studio log files under {}", logs_root.display()),
        );
        return evidence;
    }
    if live_log.is_none() {
        // The live log exists before any §24.3 line can be written, so a ring
        // without it is an unexplained gap, never a clean history.
        record_credit_wait_error(
            &mut evidence.capture_error,
            format!("current studio log missing under {}", logs_root.display()),
        );
    }
    // The appender shifts every rotation up by one and deletes the oldest
    // slot, so a healthy ring is always numbered 1..=K: a hole is a known
    // loss, and a full ring means older generations may already have been
    // evicted — the directory alone can never disprove either.
    rotations.sort_by_key(|(position, _)| *position);
    for (expected, (position, _)) in (1_u32..).zip(rotations.iter()) {
        if *position != expected {
            evidence.truncated = true;
            record_credit_wait_error(
                &mut evidence.capture_error,
                format!(
                    "studio log rotation gap: studio.log.{expected} missing before \
                     studio.log.{position}"
                ),
            );
            break;
        }
    }
    if rotations.len() >= REALTIME_CREDIT_WAIT_MAX_ROTATIONS {
        evidence.truncated = true;
        record_credit_wait_error(
            &mut evidence.capture_error,
            format!(
                "cannot prove older studio log rotations survived (production keeps {})",
                REALTIME_CREDIT_WAIT_MAX_ROTATIONS
            ),
        );
    }
    // Read the live log first (the freshest credit-wait evidence), then the
    // rotations by ascending number (`.1` is the newest); the order is
    // independent of read_dir and stays stable across runs.
    let mut sources: Vec<(u32, PathBuf)> = Vec::new();
    if let Some(live_log) = live_log {
        sources.push((0, live_log));
    }
    sources.extend(rotations);
    for (_, log) in sources {
        let file = match File::open(&log) {
            Ok(file) => file,
            Err(error) => {
                record_credit_wait_error(
                    &mut evidence.capture_error,
                    format!("cannot open {}: {error}", log.display()),
                );
                continue;
            }
        };
        let source = log.display().to_string();
        if !scan_credit_wait_log(&source, &mut BufReader::new(file), &mut evidence) {
            break;
        }
    }
    evidence
}

/// Classifies a current studio log file name into its ring position.
///
/// Production writes the live log as `studio.log` (position 0) and rotates it
/// as `studio.log.N` with N ≥ 1, where `.1` is the newest rotation; the error
/// stream's `error.log.*` and legacy `studio.<date>.log` names belong to other
/// sources and stay out of this capture.
fn credit_wait_log_position(file_name: &str) -> Option<u32> {
    if file_name == "studio.log" {
        return Some(0);
    }
    file_name
        .strip_prefix("studio.log.")
        .and_then(|suffix| suffix.parse::<u32>().ok())
        .filter(|position| *position >= 1)
}

/// Scans one studio log source for the fixed §24.3 credit-wait lines.
///
/// Every record is bounded before allocation: `Read::take` caps how many bytes
/// `BufRead::read_until` can pull from `reader` (once the budget is spent the
/// wrapper reports end of input), so a run without newlines stops at the
/// record budget instead of buffering the whole file. An over-budget record
/// (the budget counts the terminating newline, and a run may reach it before
/// any newline) is marked truncated and ends this source's scan:
/// resynchronizing to the next line boundary would need unbounded reading. A
/// non-empty record without its trailing newline is likewise a
/// truncated write: it is never processed into an observation, not even one
/// whose payload parses. Returns whether further studio log sources may still
/// be scanned.
fn scan_credit_wait_log(
    source: &str,
    reader: &mut impl BufRead,
    evidence: &mut CreditWaitEvidence,
) -> bool {
    let mut number = 0usize;
    loop {
        let mut record = Vec::new();
        let read = reader
            .take(REALTIME_CREDIT_WAIT_MAX_RECORD_BYTES as u64 + 1)
            .read_until(b'\n', &mut record);
        let read = match read {
            Ok(read) => read,
            Err(error) => {
                record_credit_wait_error(
                    &mut evidence.capture_error,
                    format!("cannot read {source} line {}: {error}", number + 1),
                );
                return true;
            }
        };
        if read == 0 {
            return true;
        }
        number += 1;
        let has_newline = record.last() == Some(&b'\n');
        if has_newline {
            record.pop();
        }
        // The budget covers the whole record including its terminating
        // newline, so the raw read length is judged before the pop.
        if read > REALTIME_CREDIT_WAIT_MAX_RECORD_BYTES {
            evidence.truncated = true;
            record_credit_wait_error(
                &mut evidence.capture_error,
                format!(
                    "studio log record at {source} line {number} exceeds {} bytes",
                    REALTIME_CREDIT_WAIT_MAX_RECORD_BYTES
                ),
            );
            return true;
        }
        if !has_newline {
            // The producer flushes whole lines, so a final record without its
            // newline is a truncated write. It never enters UTF-8/marker
            // processing; this source ends here while the collected
            // observations stay for the strict judgment to fail on it.
            evidence.truncated = true;
            record_credit_wait_error(
                &mut evidence.capture_error,
                format!("studio log record at {source} line {number} is not newline-terminated"),
            );
            return true;
        }
        let line = match String::from_utf8(record) {
            Ok(line) => line,
            Err(error) => {
                // The record boundary is still known, so the scan keeps
                // collecting the rest of the file instead of losing it.
                record_credit_wait_error(
                    &mut evidence.capture_error,
                    format!("{source} line {number} is not valid UTF-8: {error}"),
                );
                continue;
            }
        };
        let Some((_, payload)) = line.split_once(REALTIME_CREDIT_WAIT_MARKER) else {
            continue;
        };
        let payload = payload.trim();
        let location = format!("{source} line {number}");
        if payload.len() > REALTIME_CREDIT_WAIT_MAX_LINE_BYTES {
            evidence.truncated = true;
            record_credit_wait_error(
                &mut evidence.capture_error,
                format!(
                    "credit_wait payload at {location} exceeds {} bytes",
                    REALTIME_CREDIT_WAIT_MAX_LINE_BYTES
                ),
            );
            continue;
        }
        let observation = match serde_json::from_str::<CreditWaitObservation>(payload) {
            Ok(observation) => observation,
            Err(error) => {
                record_credit_wait_error(
                    &mut evidence.capture_error,
                    format!(
                        "credit_wait payload at {location} does not match the \
                         credit_wait contract: {error}"
                    ),
                );
                continue;
            }
        };
        if observation.subscription_id.is_empty() {
            record_credit_wait_error(
                &mut evidence.capture_error,
                format!("credit_wait payload at {location} has an empty subscriptionId"),
            );
        } else if observation.sent < observation.acknowledged
            || observation.sent - observation.acknowledged != 2
        {
            record_credit_wait_error(
                &mut evidence.capture_error,
                format!(
                    "credit_wait payload at {location} has impossible counters \
                     (sent={}, acknowledged={})",
                    observation.sent, observation.acknowledged
                ),
            );
        } else if evidence.observations.len() == REALTIME_CREDIT_WAIT_MAX_OBSERVATIONS {
            evidence.truncated = true;
            record_credit_wait_error(
                &mut evidence.capture_error,
                format!(
                    "more than {} credit_wait observations",
                    REALTIME_CREDIT_WAIT_MAX_OBSERVATIONS
                ),
            );
            return false;
        } else {
            evidence.observations.push(observation);
        }
    }
}

/// Keeps the first capture error; later ones never mask the original cause.
fn record_credit_wait_error(slot: &mut Option<String>, message: String) {
    if slot.is_none() {
        *slot = Some(message);
    }
}

fn run_realtime_scenario(context: &RealtimeScenario<'_>, mut fixture: OwnedProcess) -> Result<()> {
    let RealtimeScenario {
        workspace,
        app_dir,
        home,
        working,
        output,
        fixture_log,
        requests_file,
        interrupt,
    } = context;
    let gui_log_path = working.join("realtime-gui.log");
    let project = working.join("realtime-project");
    let journey = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated realtime project"
        );
        {
            let native_exit = output.join("native-exit.json");
            let mut gui = start_realtime_gui(workspace, home, &gui_log_path, true, &native_exit)?;
            let launcher_pid = gui.child.id();
            fs::write(
                output.join("realtime-process-identity.json"),
                serde_json::to_vec_pretty(&serde_json::json!({
                    "launcherPid": launcher_pid,
                    "actualGuiPid": null,
                    "nativeExitReport": "native-exit.json",
                }))?,
            )?;
            let vm_url = wait_for_vm(&gui_log_path, &mut gui, &mut fixture, interrupt)?;
            observe_capture_exit(
                app_dir,
                &vm_url,
                output,
                interrupt,
                &mut gui,
                Some(&mut fixture),
                &format!(
                    "realtime: open {}, send a long-command turn, observe in-flight growth, then type done.",
                    project.display()
                ),
            )?;
            let _ = wait_for_gui_exit(&mut gui, Duration::from_secs(120), "realtime")?;
        }
        Ok(())
    })();

    if gui_log_path.is_file() {
        write_sanitized_log(&gui_log_path, &output.join("realtime-gui.log"))?;
    }

    // The GUI is gone, but the isolated home still exists: pull the bounded
    // §24.3 producer credit-wait metadata out of its rolling studio logs
    // before the home is deleted with the run. Capture problems stay in the
    // evidence and the write result only propagates after the cleanup below,
    // so stop/join/fixture/archiving are never skipped by this probe.
    let credit_wait_evidence = (|| -> Result<CreditWaitEvidence> {
        let evidence = capture_realtime_credit_wait(home);
        let evidence_path = output.join("frb-credit-wait.json");
        fs::write(
            &evidence_path,
            serde_json::to_vec_pretty(&evidence)
                .with_context(|| format!("failed to serialize {}", evidence_path.display()))?,
        )
        .with_context(|| format!("failed to write {}", evidence_path.display()))?;
        Ok(evidence)
    })();

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
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "realtime", "acceptedRequests": accepted, "rejectedRequests": rejected,
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
    let credit_wait = credit_wait_evidence?;
    fs::write(
        output.join("frb-credit-wait-review.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "truncated": credit_wait.truncated,
            "captureError": credit_wait.capture_error,
            "observationCount": credit_wait.observations.len(),
            "humanVerdict": "pending",
        }))?,
    )?;
    ensure!(
        fixture_result.is_ok_and(|status| status.success())
            && accepted >= REALTIME_REQUIRED_STEPS
            && rejected == 0
            && errors == 0,
        "realtime fixture or GUI health incomplete; human verdict pending"
    );
    Ok(())
}

/// Single-item long-body stress journey observed through an operator runbook.
///
/// The fixture appends every increment to one stable item/part with the same
/// event count and nominal rate as the multi-item stress script, so the load is
/// comparable while the evidence is recorded separately. The `stress-body-large`
/// scenario keeps the same event count but pads each increment above the 256KiB
/// native window and slows the paced rate only there, so the generation-time
/// growth above the threshold can be sampled. The synthetic account's byte
/// count is reported as account output bytes only; it is never presented as the
/// volume transferred across the bridge.
fn run_stress_body_scenario(
    context: &StressBodyScenario<'_>,
    mut fixture: OwnedProcess,
) -> Result<()> {
    let StressBodyScenario {
        workspace,
        app_dir,
        home,
        working,
        output,
        fixture_log,
        requests_file,
        interrupt,
        ..
    } = context;
    let gui_log_path = working.join("stress-body-gui.log");
    let project = working.join("stress-body-project");
    let report_file = working.join("stress-report.json");
    let journey = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated stress-body project"
        );
        {
            let mut gui = start_stress_body_gui(workspace, home, &gui_log_path)?;
            let vm_url = wait_for_vm(&gui_log_path, &mut gui, &mut fixture, interrupt)?;
            observe_capture_exit(
                app_dir,
                &vm_url,
                output,
                interrupt,
                &mut gui,
                Some(&mut fixture),
                &format!(
                    "stress-body: open {}, let the long body stream, inspect preview/detail, then type done.",
                    project.display()
                ),
            )?;
            let _ = wait_for_gui_exit(&mut gui, Duration::from_secs(180), "stress-body")?;
        }
        Ok(())
    })();

    if gui_log_path.is_file() {
        write_sanitized_log(&gui_log_path, &output.join("stress-body-gui.log"))?;
    }
    let fixture_result = fixture.stop(requests_file);
    drop(fixture);
    // The fixture only writes its `--report-file` while shutting down, so the
    // stress report is read after the graceful stop, never before it.
    let host_report = if report_file.is_file() {
        let report: Option<pl_provider_fixture::StressReport> =
            serde_json::from_slice(&fs::read(&report_file)?)?;
        report
    } else {
        None
    };
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
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": context.scenario,
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "completed": fixture_result.as_ref().is_ok_and(|status| status.success()),
            "providerEmittedEvents": host_report.as_ref().map(|report| report.emitted_events),
            // Synthetic account text bytes; explicitly not an FRB transfer measurement.
            "providerOutputBytes": host_report.as_ref().map(|report| report.emitted_bytes),
            "providerOutputBytesNote": "synthetic account output text bytes, not FRB transfer volume",
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
    let report = host_report.context("stress-body fixture did not emit a stress report")?;
    ensure!(
        report.emitted_events == pl_provider_fixture::STRESS_EVENT_COUNT,
        "stress-body stream incomplete: {}/{} events",
        report.emitted_events,
        pl_provider_fixture::STRESS_EVENT_COUNT
    );
    ensure!(
        report.emitted_bytes > 0,
        "stress-body stream reported no account output bytes"
    );
    // The large scenario is deliberately paced slower (2,500 token/s) so the
    // window above the 256KiB threshold stays long enough to sample at least two
    // growing frames; the default body keeps its 5,000 token/s, 4s baseline.
    let (min_elapsed, max_elapsed, nominal_rate) = if context.scenario == "stress-body-large" {
        (7_000, 20_000, 2_500)
    } else {
        (3_800, 10_000, 5_000)
    };
    ensure!(
        report.elapsed_millis >= min_elapsed,
        "stress-body stream ran faster than the {nominal_rate} nominal tokens/s"
    );
    ensure!(
        report.elapsed_millis <= max_elapsed,
        "stress-body stream fell behind the {nominal_rate} token/s fixture: {}ms",
        report.elapsed_millis
    );
    ensure!(
        fixture_result.is_ok_and(|status| status.success()) && rejected == 0 && errors == 0,
        "stress-body fixture or GUI health incomplete; human verdict pending"
    );
    Ok(())
}

/// Paused-history-writer acceptance journey observed through an operator runbook.
///
/// The coordinator holds one exclusive external write transaction on the real
/// per-session `history.sqlite` while the fixture streams a reply, so the journey
/// proves the live content still grows and the current activity stays visible
/// while the durable writer cannot commit, and the durable history then catches
/// up with the answer after the lock is released.
///
/// It never fabricates a fault: the pause stays inside the runtime's retryable
/// conflict window, so the run records ordinary SQLite blocking plus the exact
/// live/durable divergence rather than claiming a typed fault. The typed fault,
/// its generation and the explicit retry/resume are exercised by the separate
/// history-fault scenario; the precise scope is written to
/// `history-lock-interface-needs.json` instead of being guessed.
fn run_history_lock_scenario(
    context: &HistoryLockScenario<'_>,
    mut fixture: OwnedProcess,
) -> Result<()> {
    let HistoryLockScenario {
        workspace,
        app_dir,
        home,
        working,
        output,
        fixture_log,
        requests_file,
        interrupt,
    } = context;
    let gui_log_path = working.join("history-lock-gui.log");
    let project = working.join("history-lock-project");
    let acquired_marker = working.join("history-lock-acquired");
    let released_marker = working.join("history-lock-released");
    let mut lock_report: Option<serde_json::Value> = None;
    let mut after: Option<(HistoryLockWatermark, i64)> = None;
    let journey = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated history-lock project"
        );
        // The GUI handle is scoped so the resident process is reaped before the
        // durable history library is read back for the "caught up" assertion.
        {
            let mut gui = start_history_lock_gui(workspace, home, &gui_log_path)?;
            let vm_url = wait_for_vm(&gui_log_path, &mut gui, &mut fixture, interrupt)?;
            wait_operator_done(
                &format!(
                    "history-lock priming: open {}, send one durable turn, wait until it settles, then type done.",
                    project.display()
                ),
                &mut gui,
                Some(&mut fixture),
                interrupt,
                Duration::from_secs(3_600),
            )?;
            let database = history_lock_database(home)?;
            let before = history_lock_watermark(&database)?;
            // Real exclusive write transaction on the actual library. The
            // runtime writer for this exact database cannot commit while held.
            let mut lock =
                SqliteWriteLock::acquire(&database, "history.sqlite", Duration::from_secs(90))?;
            let locked_at = Instant::now();
            fs::write(&acquired_marker, "acquired")?;
            wait_operator_done(
                "history-lock locked: send the locked reply, observe live growth while the writer cannot commit, wait until the turn is terminal, then type done.",
                &mut gui,
                Some(&mut fixture),
                interrupt,
                Duration::from_secs(3_600),
            )?;
            // Read the durable watermarks while the lock is still held: WAL
            // readers are not blocked, and a failure is recorded rather than
            // asserted so a busy read can never be mistaken for a pass.
            let while_locked = history_lock_watermark(&database).ok();
            let while_items =
                history_payload_count(&database, pl_provider_fixture::GUI_HISTORY_LOCK_ANSWER).ok();
            let held_millis = locked_at.elapsed().as_millis();
            let release = lock.finish();
            fs::write(&released_marker, "released")?;
            release?;
            capture(app_dir, Path::new(""), &vm_url, output, interrupt, true)?;
            let _ = wait_for_gui_exit(&mut gui, Duration::from_secs(120), "history-lock")?;
            lock_report = Some(serde_json::json!({
                "database": database.file_name().and_then(|name| name.to_str()),
                "databaseDirectory": database
                    .parent()
                    .and_then(|parent| parent.file_name())
                    .and_then(|name| name.to_str()),
                "heldMillis": held_millis,
                "before": before,
                "whileLocked": while_locked,
                "whileLockedItems": while_items,
            }));
        }
        let database = history_lock_database(home)?;
        after = Some((
            history_lock_watermark(&database)?,
            history_payload_count(&database, pl_provider_fixture::GUI_HISTORY_LOCK_ANSWER)?,
        ));
        Ok(())
    })();

    if gui_log_path.is_file() {
        write_sanitized_log(&gui_log_path, &output.join("history-lock-gui.log"))?;
    }
    if let Some(report) = lock_report.as_ref() {
        fs::write(
            output.join("history-lock-lock.json"),
            serde_json::to_vec_pretty(report)?,
        )?;
    }
    fs::write(
        output.join("history-lock-interface-needs.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "history-lock",
            "coveredNow": [
                "exclusive external BEGIN IMMEDIATE on the real per-session history.sqlite while one reply streams",
                "live content keeps growing and the current activity stays visible while the writer cannot commit",
                "the turn reaches its terminal state while the writer is still locked, and no tool starts on it",
                "after release the durable history catches up with the answer exactly once and exactly",
            ],
            "typedFault": {
                "observed": false,
                "retryableConflictWindowMillis": 30000,
                "reason": "the pause is deliberately kept inside the runtime's retryable-conflict window \
                           (thread_writer.rs RETRYABLE_BUSY_WINDOW, 30s), so the writer absorbed it as ordinary \
                           SQLite blocking and drained after release; the held duration is in \
                           history-lock-lock.json. Ordinary blocking is not a typed fault and is never reported as one",
            },
            "scopeNote": [
                "this scenario deliberately keeps the pause inside the retryable-conflict window, so it never \
                 produces a hard typed fault; ordinary SQLite blocking is never reported as one",
                "the typed writeFailed fault, its stable generation and the explicit retry/resume are exercised \
                 by the separate history-fault scenario, where the operator runbook drives the typed \
                 storageRecovery entry (fault/faultGeneration/acceptedSequence/durableSequence/execution/ \
                 pressurePaused/resumeRequired/canResume/blocksContinuation/lastError)",
            ],
            "notChanged": [
                "no production test hook, no data deletion, no faked state, no shortened tool",
                "existing realtime, stress-body and statistics scenarios are unchanged",
            ],
        }))?,
    )?;
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
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "history-lock",
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
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
    let (before_watermark, after_watermark, after_items) = {
        let report = lock_report
            .as_ref()
            .context("history-lock lock evidence is missing")?;
        let before: HistoryLockWatermark = serde_json::from_value(report["before"].clone())?;
        let (after_watermark, after_items) =
            after.context("history-lock durable watermarks were not read")?;
        (before, after_watermark, after_items)
    };
    // The real library must have committed exactly the locked turn, and its
    // content must be present: the same file the acceptance locked.
    ensure!(
        after_watermark.turns == before_watermark.turns + 1,
        "history writer did not commit exactly the locked turn: {before_watermark:?} -> {after_watermark:?}"
    );
    ensure!(
        after_items >= 1,
        "durable history does not contain the delivered answer: {after_items} matching items"
    );
    // Direct evidence the exclusive lock really paused the writer: the committed
    // turn count must be unchanged while the lock was held. A busy read is not
    // asserted; it simply stays recorded as a gap.
    let while_locked: Option<HistoryLockWatermark> = lock_report
        .as_ref()
        .and_then(|report| serde_json::from_value(report["whileLocked"].clone()).ok());
    if let Some(while_locked) = while_locked {
        ensure!(
            while_locked.turns == before_watermark.turns,
            "history writer committed while the exclusive lock was held: \
             {before_watermark:?} -> {while_locked:?}"
        );
    }
    ensure!(
        fixture_result.is_ok_and(|status| status.success())
            && accepted >= pl_provider_fixture::HISTORY_LOCK_REQUIRED_STEPS
            && rejected == 0
            && errors == 0,
        "history-lock fixture or GUI health incomplete; human verdict pending"
    );
    Ok(())
}

/// Typed history-fault retry/resume acceptance journey observed through an operator runbook.
///
/// The coordinator holds the real per-session `history.sqlite` write lock past the
/// runtime's retryable-conflict window, so the durable writer must surface a typed
/// `writeFailed` fault instead of absorbing ordinary SQLite blocking. While the
/// lock is held the journey proves the live content still grows, the typed fault
/// and its stable generation are observable, and the fault reaches its safe
/// boundary: the safe `exec` the fault turn scheduled is *not* started and no new
/// model request is issued. The lock is then released with no automatic recovery,
/// and the journey drives the explicit controls in order — retry-save until the
/// backend verifies `canResume` while the hard latch `resumeRequired` stays set,
/// then continue — proving the deferred tool and the follow-up answer each
/// complete exactly once.
///
/// The integrated GUI projects a running tool's typed in-flight progress
/// (`output`/`progressBytes`/`itemRevision`), which the realtime journey asserts
/// directly; this fault journey does not depend on it, because the deferred-tool
/// proof is the typed pre-execution status before resume and the committed
/// `result` is the post-resume identity. A baseline build without the typed
/// `storageRecovery` array is reported, never faked as a pass.
fn run_history_fault_scenario(
    context: &HistoryFaultScenario<'_>,
    mut fixture: OwnedProcess,
) -> Result<()> {
    let HistoryFaultScenario {
        workspace,
        app_dir,
        home,
        working,
        output,
        fixture_log,
        requests_file,
        interrupt,
    } = context;
    let gui_log_path = working.join("history-fault-gui.log");
    let project = working.join("history-fault-project");
    let acquired_marker = working.join("history-fault-acquired");
    let released_marker = working.join("history-fault-released");
    let mut lock_report: Option<serde_json::Value> = None;
    let mut after: Option<HistoryFaultAfter> = None;
    let journey = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated history-fault project"
        );
        // The GUI handle is scoped so the resident process is reaped before the
        // durable library is read back for the "caught up" assertion.
        {
            let mut gui = start_history_fault_gui(workspace, home, &gui_log_path)?;
            let vm_url = wait_for_vm(&gui_log_path, &mut gui, &mut fixture, interrupt)?;
            wait_operator_done(
                &format!(
                    "history-fault priming: open {}, send one durable turn, wait until it settles, then type done.",
                    project.display()
                ),
                &mut gui,
                Some(&mut fixture),
                interrupt,
                Duration::from_secs(3_600),
            )?;
            let database = history_lock_database(home)?;
            let before = history_lock_watermark(&database)?;
            // Real exclusive write transaction on the actual library, held past
            // the writer's retryable window so it must surface a fault.
            let mut lock =
                SqliteWriteLock::acquire(&database, "history.sqlite", Duration::from_secs(300))?;
            let locked_at = Instant::now();
            fs::write(&acquired_marker, "acquired")?;
            lock_report = Some(serde_json::json!({
                "database": database.file_name().and_then(|name| name.to_str()),
                "databaseDirectory": database
                    .parent()
                    .and_then(|parent| parent.file_name())
                    .and_then(|name| name.to_str()),
                "heldMillis": 0,
                "before": before,
                "whileLocked": serde_json::Value::Null,
                "whileLockedItems": serde_json::Value::Null,
            }));
            wait_operator_done(
                "history-fault locked: send the fault turn, wait until live growth, the typed writeFailed fault and the safe boundary are visible, then type done.",
                &mut gui,
                Some(&mut fixture),
                interrupt,
                Duration::from_secs(3_600),
            )?;
            let while_locked = history_lock_watermark(&database).ok();
            let while_items =
                history_payload_count(&database, pl_provider_fixture::GUI_HISTORY_FAULT_ANSWER)
                    .ok();
            let held_millis = locked_at.elapsed().as_millis();
            lock_report = Some(serde_json::json!({
                "database": database.file_name().and_then(|name| name.to_str()),
                "databaseDirectory": database
                    .parent()
                    .and_then(|parent| parent.file_name())
                    .and_then(|name| name.to_str()),
                "heldMillis": held_millis,
                "before": before,
                "whileLocked": while_locked,
                "whileLockedItems": while_items,
            }));
            let release = lock.finish();
            fs::write(&released_marker, "released")?;
            release?;
            wait_operator_done(
                "history-fault resume: retry-save until canResume is true, continue, confirm the deferred tool and follow-up answer each complete once, then type done.",
                &mut gui,
                Some(&mut fixture),
                interrupt,
                Duration::from_secs(3_600),
            )?;
            capture(app_dir, Path::new(""), &vm_url, output, interrupt, true)?;
            let _ = wait_for_gui_exit(&mut gui, Duration::from_secs(180), "history-fault")?;
        }
        let database = history_lock_database(home)?;
        after = Some(HistoryFaultAfter {
            watermark: history_lock_watermark(&database)?,
            answer_items: history_payload_count(
                &database,
                pl_provider_fixture::GUI_HISTORY_FAULT_ANSWER,
            )?,
            tool_marker_items: history_payload_count(
                &database,
                pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_MARKER,
            )?,
        });
        Ok(())
    })();

    if gui_log_path.is_file() {
        write_sanitized_log(&gui_log_path, &output.join("history-fault-gui.log"))?;
    }
    if let Some(report) = lock_report.as_ref() {
        fs::write(
            output.join("history-fault-lock.json"),
            serde_json::to_vec_pretty(report)?,
        )?;
    }
    fs::write(
        output.join("history-fault-interface-needs.json"),
        serde_json::to_vec_pretty(&history_fault_interface_needs())?,
    )?;
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
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "history-fault",
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
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
    let (before_watermark, after_state) = {
        let report = lock_report
            .as_ref()
            .context("history-fault lock evidence is missing")?;
        let before: HistoryLockWatermark = serde_json::from_value(report["before"].clone())?;
        (
            before,
            after.context("history-fault durable watermarks were not read")?,
        )
    };
    // The real library must commit exactly the faulted turn once the fault latch
    // was released through the explicit retry/resume path, and its content must be
    // present: the same file the acceptance locked.
    ensure!(
        after_state.watermark.turns == before_watermark.turns + 1,
        "history writer did not commit exactly the faulted turn: {before_watermark:?} -> {:?}",
        after_state.watermark
    );
    ensure!(
        after_state.answer_items >= 1,
        "durable history does not contain the delivered answer: {} matching items",
        after_state.answer_items
    );
    ensure!(
        after_state.tool_marker_items >= 1,
        "durable history does not contain the committed safe-tool result for the faulted turn: \
         {} marker items",
        after_state.tool_marker_items
    );
    // Direct evidence the exclusive lock really paused the writer and the fault
    // held the answer out of durable history: the committed turn count and write
    // watermark must be unchanged while the lock was held, and the answer must be
    // absent. A busy read is not asserted; it simply stays recorded as a gap.
    let while_locked: Option<HistoryLockWatermark> = lock_report
        .as_ref()
        .and_then(|report| serde_json::from_value(report["whileLocked"].clone()).ok());
    if let Some(while_locked) = while_locked {
        ensure!(
            while_locked == before_watermark,
            "history writer committed while the exclusive lock was held: \
             {before_watermark:?} -> {while_locked:?}"
        );
    }
    let while_items: Option<i64> = lock_report
        .as_ref()
        .and_then(|report| serde_json::from_value(report["whileLockedItems"].clone()).ok());
    if let Some(while_items) = while_items {
        ensure!(
            while_items == 0,
            "the answer was already durable while the exclusive lock was held: {while_items} matching items"
        );
    }
    ensure!(
        fixture_result.is_ok_and(|status| status.success())
            && accepted >= pl_provider_fixture::HISTORY_FAULT_REQUIRED_STEPS
            && rejected == 0
            && errors == 0,
        "history-fault fixture or GUI health incomplete; human verdict pending"
    );
    Ok(())
}

/// Plan shutdown/restart recovery acceptance journey driven by the operator runbook.
///
/// Three real GUI lifecycles share one isolated home and one strict fixture
/// script. The first lifecycle submits a real `plan_submit` through the GUI and
/// shuts the GUI down normally while the confirmation is pending; the restart
/// proves the reopened session restores the exact Plan body, interaction and
/// turn identity with no account request before the answer (the coordinator
/// holds the operator on a quiet marker until the fixture counters prove it),
/// approves, and stages the Revise branch before a second normal shutdown; the
/// recheck restores that second pending Plan, answers Revise (which must produce
/// a rewritten Plan confirmation with a fresh interaction identity), approves
/// it, and proves neither answered Plan re-pops. The strict fixture script
/// rejects any extra or duplicated model request, so the run fails closed; the
/// human verdict stays pending either way.
fn run_plan_recovery_scenario(
    context: &RecoveryScenario<'_>,
    mut fixture: OwnedProcess,
) -> Result<()> {
    let RecoveryScenario {
        workspace,
        app_dir,
        home,
        working,
        output,
        fixture_log,
        requests_file,
        status_file,
        interrupt,
    } = context;
    let gui_logs = [
        (
            working.join("plan-recovery-first-gui.log"),
            "plan-recovery-first-gui.log",
        ),
        (
            working.join("plan-recovery-restart-gui.log"),
            "plan-recovery-restart-gui.log",
        ),
        (
            working.join("plan-recovery-recheck-gui.log"),
            "plan-recovery-recheck-gui.log",
        ),
    ];
    let project = working.join("plan-recovery-project");
    let journey = (|| -> Result<()> {
        fs::create_dir(&project)?;
        ensure!(
            Command::new("git")
                .args(["init", "-q"])
                .arg(&project)
                .status()?
                .success(),
            "failed to initialize isolated plan-recovery project"
        );

        // 1. First lifecycle: submit the Approve-branch Plan, then shut the GUI
        // down normally while the confirmation is pending.
        let at_first_card = {
            let mut gui = start_recovery_gui(workspace, home, &gui_logs[0].0)?;
            let vm_url = wait_for_vm(&gui_logs[0].0, &mut gui, &mut fixture, interrupt)?;
            wait_operator_done(
                &format!(
                    "plan-recovery first: open {}, submit the Approve-branch Plan, leave the confirmation pending, then type done.",
                    project.display()
                ),
                &mut gui,
                Some(&mut fixture),
                interrupt,
                Duration::from_secs(3_600),
            )?;
            let at_card = plan_recovery_settled_baseline(status_file)?;
            capture(app_dir, Path::new(""), &vm_url, output, interrupt, true)?;
            let _ = wait_for_gui_exit(&mut gui, Duration::from_secs(180), "first")?;
            at_card
        };
        let after_first = plan_recovery_read_status(status_file)?;
        ensure!(
            after_first.rejected == 0,
            "fixture rejected a request during the first plan-recovery lifecycle: \
             {after_first:?}"
        );
        ensure!(
            after_first.total == at_first_card.total
                && after_first.consumed_steps == at_first_card.consumed_steps,
            "the first normal GUI shutdown issued account requests: \
             {at_first_card:?} -> {after_first:?}"
        );
        fs::write(
            output.join("plan-recovery-requests-first.json"),
            serde_json::to_vec_pretty(&serde_json::json!({
                "note": "baseline settled at the pending card; the normal shutdown itself added no account request",
                "atCard": at_first_card,
                "afterShutdown": after_first,
            }))?,
        )?;

        // 2. Restart lifecycle: restore the pending Plan, prove the reopened
        // window stays quiet, approve, stage the Revise branch, shut down again.
        let at_revise_card = {
            let mut gui = start_recovery_gui(workspace, home, &gui_logs[1].0)?;
            let vm_url = wait_for_vm(&gui_logs[1].0, &mut gui, &mut fixture, interrupt)?;
            wait_operator_done(
                "plan-recovery restart: reopen the pending Plan, confirm the window stays quiet, then type done.",
                &mut gui,
                Some(&mut fixture),
                interrupt,
                Duration::from_secs(3_600),
            )?;
            let mut quiet_evidence = serde_json::Map::new();
            plan_recovery_quiet_window(status_file, after_first, &mut quiet_evidence)?;
            wait_operator_done(
                "plan-recovery restart answer: approve, stage the Revise branch, leave the second confirmation pending, then type done.",
                &mut gui,
                Some(&mut fixture),
                interrupt,
                Duration::from_secs(3_600),
            )?;
            let at_card = plan_recovery_settled_baseline(status_file)?;
            capture(app_dir, Path::new(""), &vm_url, output, interrupt, true)?;
            let _ = wait_for_gui_exit(&mut gui, Duration::from_secs(180), "restart")?;
            fs::write(
                output.join("plan-recovery-requests-restart.json"),
                serde_json::to_vec_pretty(&serde_json::json!({
                    "quietBeforeAnswer": quiet_evidence,
                    "note": "baseline settled at the second pending card; the second normal shutdown added no account request",
                    "atReviseCard": at_card,
                }))?,
            )?;
            at_card
        };
        let after_restart = plan_recovery_read_status(status_file)?;
        ensure!(
            after_restart.rejected == 0,
            "fixture rejected a request during the restart plan-recovery lifecycle: \
             {after_restart:?}"
        );
        ensure!(
            after_restart.total == at_revise_card.total
                && after_restart.consumed_steps == at_revise_card.consumed_steps,
            "the second normal GUI shutdown issued account requests: \
             {at_revise_card:?} -> {after_restart:?}"
        );
        if let Some(value) = serde_json::from_slice::<serde_json::Value>(&fs::read(
            output.join("plan-recovery-requests-restart.json"),
        )?)?
        .as_object_mut()
        {
            value.insert("afterShutdown".into(), serde_json::to_value(after_restart)?);
            fs::write(
                output.join("plan-recovery-requests-restart.json"),
                serde_json::to_vec_pretty(value)?,
            )?;
        }

        // 3. Recheck lifecycle: restore the second pending Plan, answer Revise
        // then Approve, and prove neither answered Plan re-pops.
        {
            let mut gui = start_recovery_gui(workspace, home, &gui_logs[2].0)?;
            let vm_url = wait_for_vm(&gui_logs[2].0, &mut gui, &mut fixture, interrupt)?;
            wait_operator_done(
                "plan-recovery recheck: restore the second pending Plan, confirm the window stays quiet, then type done.",
                &mut gui,
                Some(&mut fixture),
                interrupt,
                Duration::from_secs(3_600),
            )?;
            let mut quiet_evidence = serde_json::Map::new();
            plan_recovery_quiet_window(status_file, after_restart, &mut quiet_evidence)?;
            wait_operator_done(
                "plan-recovery recheck answer: answer Revise then Approve, confirm neither answered Plan re-pops, then type done.",
                &mut gui,
                Some(&mut fixture),
                interrupt,
                Duration::from_secs(3_600),
            )?;
            capture(app_dir, Path::new(""), &vm_url, output, interrupt, true)?;
            let _ = wait_for_gui_exit(&mut gui, Duration::from_secs(180), "recheck")?;
            let final_status = plan_recovery_read_status(status_file)?;
            fs::write(
                output.join("plan-recovery-requests-recheck.json"),
                serde_json::to_vec_pretty(&serde_json::json!({
                    "quietBeforeAnswer": quiet_evidence,
                    "final": final_status,
                }))?,
            )?;
        }
        Ok(())
    })();

    for (source, name) in &gui_logs {
        if source.is_file() {
            write_sanitized_log(source, &output.join(name))?;
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
    let final_status = plan_recovery_read_status(status_file).ok();
    fs::write(
        output.join("fixture-status.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario": "plan-recovery",
            "acceptedRequests": accepted,
            "rejectedRequests": rejected,
            "completed": fixture_result.as_ref().is_ok_and(|status| status.success()),
            "liveStatus": final_status,
        }))?,
    )?;
    let errors = gui_logs
        .iter()
        .filter(|(path, _)| path.is_file())
        .map(|(path, _)| count_gui_errors(path))
        .collect::<Result<Vec<_>>>()?
        .into_iter()
        .sum::<usize>();
    fs::write(
        output.join("gui-health.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "unhandledErrors": errors, "humanVerdict": "pending"
        }))?,
    )?;
    println!("Evidence: {} (human verdict pending)", output.display());
    journey?;
    ensure!(
        fixture_result.is_ok_and(|status| status.success())
            && accepted >= pl_provider_fixture::PLAN_RECOVERY_REQUIRED_STEPS
            && rejected == 0
            && errors == 0,
        "plan-recovery fixture or GUI health incomplete; human verdict pending"
    );
    Ok(())
}

/// Reads the fixture's live strict-script counters.
fn plan_recovery_read_status(status_file: &Path) -> Result<pl_provider_fixture::FixtureLiveStatus> {
    serde_json::from_slice(&fs::read(status_file).with_context(|| {
        format!(
            "fixture live status file is missing: {}",
            status_file.display()
        )
    })?)
    .with_context(|| {
        format!(
            "fixture live status file is corrupt: {}",
            status_file.display()
        )
    })
}

/// Samples the live counters twice and requires them unchanged, so a baseline
/// taken at a stage marker cannot race a still-in-flight request.
fn plan_recovery_settled_baseline(
    status_file: &Path,
) -> Result<pl_provider_fixture::FixtureLiveStatus> {
    let first = plan_recovery_read_status(status_file)?;
    ensure!(
        first.rejected == 0,
        "fixture rejected a request before the plan-recovery baseline: {first:?}"
    );
    thread::sleep(Duration::from_millis(1_500));
    let second = plan_recovery_read_status(status_file)?;
    ensure!(
        second == first,
        "fixture counters still moving while sampling a plan-recovery baseline: \
         {first:?} -> {second:?}"
    );
    Ok(second)
}

/// Proves a reopened-card window recorded no account traffic, then releases
/// the Driver's quiet marker.
///
/// The baseline comes from the previous lifecycle's settled counters, so any
/// model request issued by the restart display itself — an eager continuation
/// or an auto-execution — fails here instead of hiding behind a later answer.
fn plan_recovery_quiet_window(
    status_file: &Path,
    baseline: pl_provider_fixture::FixtureLiveStatus,
    evidence: &mut serde_json::Map<String, serde_json::Value>,
) -> Result<()> {
    let reopened = plan_recovery_read_status(status_file)?;
    ensure!(
        reopened.rejected == 0,
        "fixture rejected a request after the restart display: {reopened:?}"
    );
    ensure!(
        reopened.total == baseline.total && reopened.consumed_steps == baseline.consumed_steps,
        "account traffic appeared between the restart display and the answer: \
         {baseline:?} -> {reopened:?}"
    );
    thread::sleep(Duration::from_millis(2_500));
    let after_window = plan_recovery_read_status(status_file)?;
    ensure!(
        after_window == reopened,
        "account traffic appeared during the quiet window: {reopened:?} -> {after_window:?}"
    );
    evidence.insert("baseline".into(), serde_json::to_value(baseline)?);
    evidence.insert("reopened".into(), serde_json::to_value(reopened)?);
    evidence.insert("quietWindowMillis".into(), serde_json::json!(2_500));
    Ok(())
}

/// Isolate the GUI's user Skills home without changing Cargo or rustup's home.
///
/// Cargo is started before the GUI, so preserving its toolchain locations here
/// keeps the build on the operator's existing installation while the GUI sees
/// only synthetic user configuration and Skills.
fn configure_isolated_gui_home(command: &mut Command, home: &Path) -> Result<()> {
    let cargo_home = preserved_toolchain_home(std::env::var_os("CARGO_HOME"), ".cargo")?;
    let rustup_home = preserved_toolchain_home(std::env::var_os("RUSTUP_HOME"), ".rustup")?;

    command
        .env("ANYWORK_HOME", home)
        .env("HOME", home)
        .env("USERPROFILE", home)
        .env("CARGO_HOME", cargo_home)
        .env("RUSTUP_HOME", rustup_home);
    Ok(())
}

fn real_platform_user_home() -> Result<PathBuf> {
    #[cfg(windows)]
    let real_user_home = std::env::var_os("USERPROFILE");
    #[cfg(not(windows))]
    let real_user_home = std::env::var_os("HOME");

    real_user_home
        .filter(|path| !path.is_empty())
        .map(PathBuf::from)
        .context("could not resolve the real user home before isolating GUI HOME")
}

fn preserved_toolchain_home(
    explicit: Option<std::ffi::OsString>,
    relative: &str,
) -> Result<std::ffi::OsString> {
    match explicit.filter(|path| !path.is_empty()) {
        Some(path) => Ok(path),
        None => Ok(real_platform_user_home()?.join(relative).into_os_string()),
    }
}

fn start_recovery_gui(workspace: &Path, home: &Path, log_path: &Path) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    configure_isolated_gui_home(&mut command, home)?;
    command
        .current_dir(workspace)
        .args(["xtask", "run-gui", "--capture"])
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    OwnedProcess::start(&mut command, false)
}

/// Durable history state read back after the faulted turn committed.
struct HistoryFaultAfter {
    watermark: HistoryLockWatermark,
    answer_items: i64,
    /// Committed items whose payload carries the safe-tool marker.
    tool_marker_items: i64,
}

/// Interface requirements and gaps for the history-fault acceptance.
///
/// The covered facts are the ones the journey really asserts; the gaps name the
/// exact stable field still needed so nothing is inferred from a weaker signal.
fn history_fault_interface_needs() -> serde_json::Value {
    serde_json::json!({
        "scenario": "history-fault",
        "coveredNow": [
            "exclusive external BEGIN IMMEDIATE on the real per-session history.sqlite, held past the writer's retryable-conflict window (thread_writer.rs RETRYABLE_BUSY_WINDOW, 30s)",
            "live content still grows while the durable writer cannot commit",
            "a typed HistoryFault (writeFailed) with a stable faultGeneration is observable from the Driver snapshot's storageRecovery entry for the faulted Thread, together with the pause reason the UI renders from the same typed facts",
            "the fault reaches its canonical safe boundary (continuation deferred: resumeRequired with canResume false): the safe exec the fault turn scheduled stays in an explicit pre-execution state (queued/awaitingApproval, no committed marker), this turn has no final answer, and no follow-up model request is issued",
            "release without automatic recovery, then retry-save until the backend-verified canResume is true while resumeRequired stays set, then continue; the deferred tool and the follow-up answer each complete exactly once",
        ],
        "typedToolProgress": {
            "observed": true,
            "detail": "the integrated GUI projects a running tool's typed in-flight progress: the timeline tool item carries `output` (same source as the committed `result`), `progressBytes` (UTF-8 count) and `itemRevision`, so realtime_journey.dart asserts the realtime long-command output step by step (longCommandInFlightOutputGrows) without reading raw JSON or substituting the final result",
            "historyFaultUse": "this fault journey does not depend on in-flight progress: the deferred-tool proof is the typed pre-execution status (`queued`/`awaitingApproval`) at the latched safe boundary and before/after retry, and the committed `result` carries the post-resume identity",
        },
        "retryResumeContract": {
            "buttons": [
                "history-retry-<threadId>: retry the durable save for the fault generation",
                "history-resume-<threadId>: explicit continue, only enabled when typed canResume is true",
            ],
            "typedState": "storageRecovery[threadId] = {fault, faultGeneration, acceptedSequence, durableSequence, execution, pressurePaused, resumeRequired, canResume, blocksContinuation, lastError}; canResume is derived by the backend from the retry generation/fence, never from lastError text",
            "generation": "a stale generation can never drive a resume; that fence is proved by the runtime's own generation tests, and this journey confirms the button uses the canonical faultGeneration",
        },
        "notChanged": [
            "no production test hook, no data deletion, no faked state, no shortened safe tool",
            "existing realtime, stress-body, statistics and history-lock scenarios are unchanged",
        ],
    })
}

/// Per-session history watermarks read directly from the real `history.sqlite`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub(super) struct HistoryLockWatermark {
    /// Committed `history_turns` rows.
    pub(super) turns: i64,
    /// `history_meta.applied_write_seq`, the durable write watermark.
    pub(super) write_seq: i64,
}

/// Locates the single per-session history library of the isolated home.
///
/// The acceptance deliberately locks the *real* library, never a copy. The home
/// is isolated to this run and holds exactly one Thread, so more than one
/// candidate (or none) is reported instead of guessing which library to lock.
pub(super) fn history_lock_database(home: &Path) -> Result<std::path::PathBuf> {
    let projects = home.join("data/workspaces");
    let mut candidates = Vec::new();
    if projects.is_dir() {
        for project in fs::read_dir(&projects)? {
            let sessions = project?.path().join("sessions");
            if !sessions.is_dir() {
                continue;
            }
            for session in fs::read_dir(&sessions)? {
                let database = session?.path().join("history.sqlite");
                if database.is_file() {
                    candidates.push(database);
                }
            }
        }
    }
    ensure!(
        candidates.len() == 1,
        "expected exactly one per-session history.sqlite under {}, found {}",
        projects.display(),
        candidates.len()
    );
    Ok(candidates.remove(0))
}

/// Reads the single Thread id stored in the isolated home's history library.
pub(super) fn history_owner_thread(home: &Path) -> Result<String> {
    let path = history_lock_database(home)?;
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(async {
        let mut connection = SqliteConnection::connect_with(
            &SqliteConnectOptions::new().filename(&path).read_only(true),
        )
        .await?;
        let owner: String = sea_orm::sqlx::query("SELECT thread_id FROM history_meta WHERE id=1")
            .fetch_one(&mut connection)
            .await?
            .try_get("thread_id")?;
        ensure!(!owner.is_empty(), "history library has an empty Thread id");
        Ok(owner)
    })
}

/// Reads the durable history watermarks through a read-only connection.
pub(super) fn history_lock_watermark(database: &Path) -> Result<HistoryLockWatermark> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    let database = database.to_owned();
    let display = database.clone();
    runtime.block_on(async move {
        let options = SqliteConnectOptions::new()
            .filename(&database)
            .read_only(true);
        let mut connection = SqliteConnection::connect_with(&options).await?;
        let (turns, write_seq): (i64, i64) = sea_orm::sqlx::query_as(
            "SELECT (SELECT COUNT(*) FROM history_turns),
                    COALESCE((SELECT applied_write_seq FROM history_meta WHERE id = 1), 0)",
        )
        .fetch_one(&mut connection)
        .await
        .with_context(|| {
            format!(
                "failed to read history watermarks from {}",
                display.display()
            )
        })?;
        Ok(HistoryLockWatermark { turns, write_seq })
    })
}

/// Runs `PRAGMA quick_check` on [database] through a read-only connection.
///
/// Proves the exact file committed before a forced exit still opens and passes
/// SQLite's own integrity check after a reopen, rather than only that some file
/// exists.
pub(super) fn history_lock_quick_check(database: &Path) -> Result<String> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    let database = database.to_owned();
    let display = database.clone();
    runtime.block_on(async move {
        let options = SqliteConnectOptions::new()
            .filename(&database)
            .read_only(true);
        let mut connection = SqliteConnection::connect_with(&options).await?;
        let (result,): (String,) = sea_orm::sqlx::query_as("PRAGMA quick_check")
            .fetch_one(&mut connection)
            .await
            .with_context(|| format!("failed to run quick_check on {}", display.display()))?;
        Ok(result)
    })
}

/// Counts committed history items whose payload carries [needle].
fn history_payload_count(database: &Path, needle: &str) -> Result<i64> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    let database = database.to_owned();
    let display = database.clone();
    let needle = needle.to_owned();
    runtime.block_on(async move {
        let options = SqliteConnectOptions::new()
            .filename(&database)
            .read_only(true);
        let mut connection = SqliteConnection::connect_with(&options).await?;
        let (count,): (i64,) =
            sea_orm::sqlx::query_as("SELECT COUNT(*) FROM history_items WHERE payload LIKE ?1")
                .bind(format!("%{needle}%"))
                .fetch_one(&mut connection)
                .await
                .with_context(|| {
                    format!(
                        "failed to count committed items matching {needle} from {}",
                        display.display()
                    )
                })?;
        Ok(count)
    })
}

fn start_stress_body_gui(workspace: &Path, home: &Path, log_path: &Path) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    command
        .current_dir(workspace)
        // Profile/AOT keeps the recorded frame timings representative, matching stress.
        .args([
            "xtask",
            "run-gui",
            "--capture",
            "--profile",
            "--native-launch",
        ])
        .env("ANYWORK_HOME", home)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    OwnedProcess::start(&mut command, false)
}

fn start_realtime_gui(
    workspace: &Path,
    home: &Path,
    log_path: &Path,
    credit_wait_diagnostics: bool,
    native_exit_report: &Path,
) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    command
        .current_dir(workspace)
        // Profile/AOT keeps the recorded frame timings representative, matching stress.
        .args([
            "xtask",
            "run-gui",
            "--capture",
            "--profile",
            "--native-launch",
            "--native-exit-report",
        ])
        .arg(native_exit_report)
        .env("ANYWORK_HOME", home);
    // §24.3: only the realtime journey raises the real conversation-credit
    // producer to debug for the Pending diagnostic; the warn floor for
    // everything else keeps that run's production logs small. Other callers
    // keep the inherited RUST_LOG (xtask clears ANYWORK_LOG_LEVEL without an
    // explicit --log-level, so RUST_LOG is the filter the GUI consumes).
    if credit_wait_diagnostics {
        command.env("RUST_LOG", "warn,anywork::conversation_credit=debug");
    }
    command
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    OwnedProcess::start(&mut command, false)
}

fn start_history_lock_gui(workspace: &Path, home: &Path, log_path: &Path) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    command
        .current_dir(workspace)
        // Profile/AOT keeps the observed timings representative, like realtime.
        .args([
            "xtask",
            "run-gui",
            "--capture",
            "--profile",
            "--native-launch",
        ])
        .env("ANYWORK_HOME", home)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    OwnedProcess::start(&mut command, false)
}

fn start_history_fault_gui(workspace: &Path, home: &Path, log_path: &Path) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    command
        .current_dir(workspace)
        // Profile/AOT keeps the observed timings representative, like history-lock.
        .args([
            "xtask",
            "run-gui",
            "--capture",
            "--profile",
            "--native-launch",
        ])
        .env("ANYWORK_HOME", home)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    OwnedProcess::start(&mut command, false)
}

fn write_sanitized_log(source: &Path, destination: &Path) -> Result<()> {
    let log = fs::read_to_string(source)?;
    let mut output = File::create(destination)?;
    for line in log.lines() {
        if let Some((_, timing)) = line.split_once("startup_stage=") {
            let mut fields = timing.split_whitespace();
            let stage = fields.next().unwrap_or_default().trim_matches('"');
            if !stage.is_empty()
                && stage
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
            {
                let elapsed = fields.find_map(|field| {
                    field
                        .strip_prefix("elapsed_ms=")
                        .and_then(|value| value.parse::<u64>().ok())
                });
                if let Some(elapsed) = elapsed {
                    writeln!(output, "startup_stage={stage} elapsed_ms={elapsed}")?;
                } else {
                    writeln!(output, "startup_stage={stage}")?;
                }
            }
        } else if line.contains("available at: http://127.0.0.1:")
            || line.contains("listening on http://127.0.0.1:")
        {
            writeln!(output, "vm_service=ready (address redacted)")?;
        } else if line.contains("resident command exited:") {
            writeln!(output, "gui_process=exited")?;
        } else if let Some(metrics) = line.split("timeline_frame_work ").nth(1)
            && metrics
                .bytes()
                .all(|byte| byte.is_ascii_digit() || matches!(byte, b' ' | b'=' | b'_' | b'\r'))
        {
            writeln!(output, "timeline_frame_work {metrics}")?;
        }
    }
    Ok(())
}

/// Persists the GUI log and an error digest as reviewable evidence.
///
/// The source log lives under the isolated coordination directory that is
/// removed with the run, so both files are written here. The full log is
/// sanitized line by line; the digest always records the exit code and the
/// journey error and never ends up empty when the log has content.
fn write_realtime_driver_evidence(
    driver_log: &Path,
    output: &Path,
    stem: &str,
    exit: Option<std::process::ExitStatus>,
    journey_error: Option<&anyhow::Error>,
    redactions: &[(String, &str)],
) -> Result<()> {
    let sanitized = if driver_log.is_file() {
        let raw = fs::read_to_string(driver_log)?;
        let mut sanitized = String::new();
        for line in raw.lines() {
            sanitized.push_str(&sanitize_driver_line(line, redactions));
            sanitized.push('\n');
        }
        fs::write(output.join(format!("{stem}-driver.log")), &sanitized)?;
        sanitized
    } else {
        String::new()
    };

    let mut digest = String::new();
    match exit {
        Some(status) => digest.push_str(&format!("driver_exit={status}\n")),
        None => digest.push_str("driver_exit=unknown (no exit status observed)\n"),
    }
    if let Some(error) = journey_error {
        digest.push_str(&format!(
            "journey_error={}\n",
            sanitize_driver_line(&error.to_string(), redactions)
        ));
    }
    let mut wrote_diagnostic = false;
    for line in sanitized.lines() {
        if driver_line_is_diagnostic(line) {
            digest.push_str(line);
            digest.push('\n');
            wrote_diagnostic = true;
        }
    }
    if !wrote_diagnostic {
        digest.push_str("driver_log_tail:\n");
        let mut tail: Vec<&str> = sanitized.lines().rev().take(40).collect();
        tail.reverse();
        for line in tail {
            digest.push_str(line);
            digest.push('\n');
        }
    }
    fs::write(output.join(format!("{stem}-driver-errors.txt")), digest)?;
    Ok(())
}

/// Redacts local filesystem paths and loopback ports from one Driver log line.
fn sanitize_driver_line(line: &str, redactions: &[(String, &str)]) -> String {
    let mut sanitized = line.to_owned();
    for (path, replacement) in redactions {
        if !path.is_empty() {
            sanitized = sanitized.replace(path, replacement);
        }
    }
    let sanitized = redact_loopback_urls(&sanitized);
    let sanitized = redact_loopback_ports(&sanitized);
    sanitized.chars().take(480).collect()
}

/// Replaces a whole loopback URL token (scheme, port and ephemeral VM-service
/// auth path) with a marker so the local address is not persisted.
fn redact_loopback_urls(line: &str) -> String {
    let mut output = line.to_owned();
    for scheme in [
        "http://127.0.0.1:",
        "ws://127.0.0.1:",
        "http://localhost:",
        "ws://localhost:",
        "http://0.0.0.0:",
        "ws://0.0.0.0:",
    ] {
        while let Some(index) = output.find(scheme) {
            let end = output[index..]
                .char_indices()
                .find(|&(_, c)| c.is_whitespace() || matches!(c, '"' | '\'' | ')' | ']' | ','))
                .map_or(output.len(), |(offset, _)| index + offset);
            output.replace_range(index..end, "<loopback-url>");
        }
    }
    output
}

/// Replaces a bare `host:<port>` loopback address while keeping `file:line:col`
/// diagnostics intact (only the numeric port after a loopback host is removed).
fn redact_loopback_ports(line: &str) -> String {
    let mut output = line.to_owned();
    for host in ["127.0.0.1:", "localhost:", "0.0.0.0:"] {
        while let Some(index) = output.find(host) {
            let digits = output[index + host.len()..]
                .chars()
                .take_while(char::is_ascii_digit)
                .count();
            if digits == 0 {
                break;
            }
            output.replace_range(index + host.len()..index + host.len() + digits, "<port>");
        }
    }
    output
}

/// Whether a Driver log line carries a failure reason worth keeping.
///
/// Broad on purpose: Dart compile errors, analyzer output, unhandled
/// exceptions and stack frames all end up in the digest.
fn driver_line_is_diagnostic(line: &str) -> bool {
    let trimmed = line.trim_start();
    if trimmed.is_empty() {
        return false;
    }
    if trimmed.starts_with('#') {
        return true;
    }
    [
        "Unhandled exception",
        "Exception",
        "Bad state",
        "StateError",
        "TimeoutException",
        "DriverError",
        "FormatException",
        "SocketException",
        "Error",
        "error",
        "Failed",
        "failed",
        "Compilation",
        "compiler",
        "Connection refused",
        "exit code",
        "Exited",
    ]
    .iter()
    .any(|marker| line.contains(marker))
}

fn count_gui_errors(source: &Path) -> Result<usize> {
    let log = fs::read_to_string(source)?;
    Ok(log
        .lines()
        .filter(|line| {
            line.contains("Unhandled Exception")
                || line.contains("EXCEPTION CAUGHT BY")
                || line.starts_with("E/flutter ")
                || line.contains("] E/flutter ")
                || line.contains("ERROR:flutter/runtime")
        })
        .count())
}

fn count_inline_images(value: &serde_json::Value) -> usize {
    match value {
        serde_json::Value::Object(fields) => {
            usize::from(
                fields.get("type").and_then(serde_json::Value::as_str) == Some("input_image")
                    && fields
                        .get("image_url")
                        .and_then(serde_json::Value::as_str)
                        .is_some_and(|url| {
                            url.starts_with("data:image/") && url.contains(";base64,")
                        }),
            ) + fields.values().map(count_inline_images).sum::<usize>()
        }
        serde_json::Value::Array(values) => values.iter().map(count_inline_images).sum(),
        _ => 0,
    }
}

fn sanitize_requests(source: &Path, destination: &Path) -> Result<()> {
    let requests: Vec<serde_json::Value> = serde_json::from_slice(&fs::read(source)?)?;
    let safe: Vec<_> = requests.iter().map(|request| {
        serde_json::json!({
            "method": request.get("method").and_then(|v| v.as_str()).filter(|m| *m == "POST"),
            "path": request.get("path").and_then(|v| v.as_str()).filter(|p| matches!(*p, "/v1/responses" | "/v1/chat/completions" | "/v1/delegation-a/responses" | "/v1/delegation-b/responses")),
            "accepted": request.get("accepted").and_then(|v| v.as_bool()),
            "body": "[redacted]",
            // Strict-match facts for a rejected step: scenario-owned prompt only,
            // never the caller's actual prompt or tool output.
            "diagnostic": request.get("diagnostic").filter(|value| !value.is_null())
        })
    }).collect();
    fs::write(destination, serde_json::to_vec_pretty(&safe)?)?;
    Ok(())
}

/// Persists the synthetic account log as reviewable evidence.
///
/// The fixture prints one `fixture_*` line per strict-match fact; those lines
/// carry scenario-owned prompts and a match category but never the caller's
/// request body, so they are passed through verbatim. The outermost failure
/// reason is preserved (loopback addresses and local paths still redacted) so a
/// rejected step is never collapsed into an opaque marker. Any other line is
/// dropped because it can contain user content or local paths.
fn write_fixture_log(source: &Path, destination: &Path) -> Result<()> {
    let log = fs::read_to_string(source)?;
    let mut file = File::create(destination)?;
    for line in log.lines() {
        let trimmed = line.trim_end();
        if trimmed.starts_with("fixture_") {
            writeln!(file, "{trimmed}")?;
        } else if let Some(reason) = failure_reason(trimmed) {
            writeln!(file, "fixture_error={reason}")?;
        }
    }
    Ok(())
}

/// Extracts the outermost failure reason from one fixture log line.
///
/// Returns `None` for progress lines that are not failures, keeping the digest
/// focused on why the run stopped rather than every line the fixture wrote.
fn failure_reason(line: &str) -> Option<String> {
    let trimmed = line.trim();
    let reason = trimmed
        .strip_prefix("Error:")
        .or_else(|| trimmed.strip_prefix("error:"))?
        .trim();
    if reason.is_empty() {
        return None;
    }
    let sanitized = redact_loopback_ports(&redact_loopback_urls(reason));
    Some(sanitized.chars().take(480).collect())
}

#[cfg(test)]
mod scenario_cli_tests {
    use super::ManualGuiOptions;
    use clap::Parser;

    #[test]
    fn keeps_presentation_scenarios_without_restoring_removed_acp_journey() {
        for scenario in [
            "gui",
            "timeline-history",
            "question-history",
            "realtime-presentation",
            "timeline-concept",
            "sidebar-query",
        ] {
            let options = ManualGuiOptions::try_parse_from(["acceptance", "--preset", scenario])
                .expect("supported native presentation scenario");
            assert_eq!(options.preset, scenario);
        }
        for scenario in ["acp-auto-install", "unknown-scenario"] {
            assert!(
                ManualGuiOptions::try_parse_from(["acceptance", "--preset", scenario]).is_err()
            );
        }
    }
}

#[cfg(test)]
mod timeline_history_completion_tests {
    use super::require_timeline_history_completion;
    use anyhow::anyhow;
    use std::process::{Command, ExitStatus};

    #[test]
    fn preserves_journey_failure_before_fixture_cleanup_failure() {
        let error = require_timeline_history_completion(
            Err(anyhow!("journey sentinel")),
            Err(anyhow!("fixture sentinel")),
        )
        .expect_err("journey failure must be preserved");
        let message = format!("{error:#}");
        assert!(message.contains("journey sentinel"));
        assert!(!message.contains("fixture sentinel"));
    }

    #[test]
    fn rejects_fixture_stop_error_and_nonzero_exit() {
        let stop_error =
            require_timeline_history_completion(Ok(()), Err(anyhow!("fixture sentinel")))
                .expect_err("fixture stop error must fail the scenario");
        let stop_message = format!("{stop_error:#}");
        assert!(stop_message.contains("timeline-history provider fixture stop failed"));
        assert!(stop_message.contains("fixture sentinel"));

        let status = platform_exit_status(7);
        let exit_error = require_timeline_history_completion(Ok(()), Ok(status))
            .expect_err("nonzero fixture exit must fail the scenario");
        assert!(
            exit_error
                .to_string()
                .contains("timeline-history provider fixture exited with")
        );
    }

    #[test]
    fn accepts_successful_fixture_exit_after_successful_journey() {
        require_timeline_history_completion(Ok(()), Ok(platform_exit_status(0)))
            .expect("successful journey and fixture exit must pass");
    }

    fn platform_exit_status(code: i32) -> ExitStatus {
        #[cfg(unix)]
        let status = Command::new("sh")
            .args(["-c", &format!("exit {code}")])
            .status();
        #[cfg(windows)]
        let status = Command::new("cmd")
            .args(["/C", &format!("exit /B {code}")])
            .status();
        status.expect("platform shell must produce an exit status")
    }
}

#[cfg(test)]
mod vm_service_url_tests {
    use super::vm_service_url;

    #[test]
    fn selects_vm_announcements_not_the_devtools_page() {
        let devtools = "The Flutter DevTools debugger and profiler on Linux is available at: \
            http://127.0.0.1:12345/devtools/?uri=ws://127.0.0.1:12345/ws";
        let launch = format!(
            "[        ] A Dart VM Service on Linux is available at: http://127.0.0.1:12345/\n\
             [        ] {devtools}\n"
        );
        assert_eq!(
            vm_service_url(&launch).as_deref(),
            Some("http://127.0.0.1:12345/")
        );
        assert_eq!(vm_service_url(devtools), None);
        assert_eq!(
            vm_service_url(&format!(
                "{launch}The Dart VM service is listening on http://127.0.0.1:12346/auth-token=/\n"
            ))
            .as_deref(),
            Some("http://127.0.0.1:12346/auth-token=/")
        );
    }
}

#[cfg(test)]
mod credit_wait_capture_tests {
    use super::{
        CreditWaitEvidence, REALTIME_CREDIT_WAIT_MARKER, REALTIME_CREDIT_WAIT_MAX_RECORD_BYTES,
        capture_realtime_credit_wait, scan_credit_wait_log,
    };
    use std::fs;
    use std::io::Cursor;

    /// A real plain-fmt §24.3 line for [subscription]: the fixed target/message
    /// fragment the plain tracing fmt prints, then the compact JSON payload.
    fn credit_line(subscription: &str) -> String {
        format!(
            "2026-02-10T01:02:03.004005Z DEBUG ThreadId(04) {REALTIME_CREDIT_WAIT_MARKER}\
             {{\"subscriptionId\":\"{subscription}\",\"sent\":2,\"acknowledged\":0}}\n"
        )
    }

    /// Creates an isolated `home/studio/logs` ring holding [files].
    fn logs_home(files: &[(String, String)]) -> tempfile::TempDir {
        let home = tempfile::tempdir().expect("temporary studio home");
        let logs = home.path().join("studio").join("logs");
        fs::create_dir_all(&logs).expect("studio log directory");
        for (name, contents) in files {
            fs::write(logs.join(name), contents).expect("studio log file");
        }
        home
    }

    #[test]
    fn reads_live_and_numbered_rotations_and_keeps_rotation_errors() {
        // The live log and the newest rotation each carry a real-format record:
        // both are captured, and the small healthy ring stays complete.
        let home = logs_home(&[
            ("studio.log".to_owned(), credit_line("live")),
            ("studio.log.1".to_owned(), credit_line("rotated")),
        ]);
        let evidence = capture_realtime_credit_wait(home.path());
        assert!(!evidence.truncated);
        assert_eq!(evidence.capture_error, None);
        let subscriptions: Vec<&str> = evidence
            .observations
            .iter()
            .map(|observation| observation.subscription_id.as_str())
            .collect();
        assert_eq!(subscriptions, ["live", "rotated"]);
        drop(home);

        // Bad JSON inside the rotation is a capture error even though the live
        // record is good: the current healthy file never masks the broken one.
        let home = logs_home(&[
            ("studio.log".to_owned(), credit_line("live")),
            (
                "studio.log.1".to_owned(),
                format!("{REALTIME_CREDIT_WAIT_MARKER}{{\"subscriptionId\":\n"),
            ),
        ]);
        let evidence = capture_realtime_credit_wait(home.path());
        assert!(evidence.capture_error.is_some());
        assert_eq!(evidence.observations.len(), 1);
        assert_eq!(evidence.observations[0].subscription_id, "live");
        drop(home);

        // A numbering hole is a known loss, still collecting every readable
        // record while the strict judgment fails on the recorded gap.
        let home = logs_home(&[
            ("studio.log".to_owned(), credit_line("live")),
            ("studio.log.1".to_owned(), credit_line("rotated")),
            ("studio.log.3".to_owned(), credit_line("older")),
        ]);
        let evidence = capture_realtime_credit_wait(home.path());
        assert!(evidence.truncated);
        assert!(evidence.capture_error.is_some());
        assert_eq!(evidence.observations.len(), 3);
        drop(home);

        // A full retention ring cannot prove older generations survived: the
        // failure stays recorded while all eight readable records are kept.
        let home = tempfile::tempdir().expect("temporary studio home");
        let logs = home.path().join("studio").join("logs");
        fs::create_dir_all(&logs).expect("studio log directory");
        fs::write(logs.join("studio.log"), credit_line("live")).expect("studio log file");
        for position in 1..=7 {
            fs::write(
                logs.join(format!("studio.log.{position}")),
                credit_line(&format!("rotation-{position}")),
            )
            .expect("studio log file");
        }
        let evidence = capture_realtime_credit_wait(home.path());
        assert!(evidence.truncated);
        assert!(evidence.capture_error.is_some());
        assert_eq!(evidence.observations.len(), 8);
        drop(home);

        // The live log exists before any §24.3 line can be written, so a ring
        // without it is an unexplained gap, never a clean history.
        let home = logs_home(&[("studio.log.1".to_owned(), credit_line("rotated"))]);
        let evidence = capture_realtime_credit_wait(home.path());
        assert!(evidence.capture_error.is_some());
        assert_eq!(evidence.observations.len(), 1);
    }

    #[test]
    fn log_scan_stops_reading_within_the_record_budget() {
        // One valid record, then a run of input without any newline far beyond
        // the record budget, then a trailing record that must never be read.
        // The scan has to stop consuming at the budget, keep the earlier
        // observation, and record the truncation — draining the whole stream
        // is exactly what the old `BufRead::lines()` scan did.
        let first = credit_line("before-budget");
        let first_len = first.len();
        let mut input = first.into_bytes();
        input.extend(std::iter::repeat_n(
            b'x',
            REALTIME_CREDIT_WAIT_MAX_RECORD_BYTES * 4,
        ));
        input.extend_from_slice(credit_line("after-budget").as_bytes());
        let mut cursor = Cursor::new(input);
        let mut evidence = CreditWaitEvidence {
            schema: "anywork-frb-credit-wait/1",
            source: "real-frb-producer-poll",
            observations: Vec::new(),
            truncated: false,
            capture_error: None,
        };
        assert!(scan_credit_wait_log(
            "budget-test",
            &mut cursor,
            &mut evidence
        ));
        assert!(evidence.truncated);
        assert!(evidence.capture_error.is_some());
        assert_eq!(evidence.observations.len(), 1);
        assert_eq!(evidence.observations[0].subscription_id, "before-budget");
        assert!(
            cursor.position() <= (first_len + REALTIME_CREDIT_WAIT_MAX_RECORD_BYTES + 1) as u64
        );
    }

    #[test]
    fn unterminated_final_record_never_becomes_an_observation() {
        // (a) A complete payload that lost its trailing newline is a truncated
        // write: it must not become an observation, and the strict gate that
        // requires capture_error.is_none() && !truncated cannot pass.
        let mut payload_only = credit_line("unterminated").into_bytes();
        assert_eq!(payload_only.pop(), Some(b'\n'));
        let mut cursor = Cursor::new(payload_only);
        let mut evidence = scan_evidence();
        assert!(scan_credit_wait_log(
            "unterminated-test",
            &mut cursor,
            &mut evidence
        ));
        assert!(evidence.truncated);
        assert!(evidence.capture_error.is_some());
        assert!(evidence.observations.is_empty());

        // (b) A healthy observation followed by a plain tail line without its
        // newline keeps the observation but still fails the strict gate.
        let mut input = credit_line("kept-observation").into_bytes();
        input.extend_from_slice(b"plain tail without newline");
        let mut cursor = Cursor::new(input);
        let mut evidence = scan_evidence();
        assert!(scan_credit_wait_log(
            "tail-test",
            &mut cursor,
            &mut evidence
        ));
        assert!(evidence.truncated);
        assert!(evidence.capture_error.is_some());
        assert_eq!(evidence.observations.len(), 1);
        assert_eq!(evidence.observations[0].subscription_id, "kept-observation");
    }

    #[test]
    fn record_budget_counts_the_terminating_newline() {
        // The whole-record budget includes the fmt prefix and the terminating
        // newline: a filler line of 8191 bytes plus '\n' totals exactly the
        // budget, stays readable, and the later observation is captured.
        let mut input = vec![b'x'; REALTIME_CREDIT_WAIT_MAX_RECORD_BYTES - 1];
        input.push(b'\n');
        input.extend_from_slice(credit_line("after-exact-budget").as_bytes());
        let mut cursor = Cursor::new(input);
        let mut evidence = scan_evidence();
        assert!(scan_credit_wait_log(
            "exact-budget",
            &mut cursor,
            &mut evidence
        ));
        assert!(!evidence.truncated);
        assert_eq!(evidence.capture_error, None);
        assert_eq!(evidence.observations.len(), 1);
        assert_eq!(
            evidence.observations[0].subscription_id,
            "after-exact-budget"
        );

        // One byte over the same total budget is an over-budget record: this
        // source stops there and the trailing observation is never read.
        let mut input = vec![b'x'; REALTIME_CREDIT_WAIT_MAX_RECORD_BYTES];
        input.push(b'\n');
        input.extend_from_slice(credit_line("never-reached").as_bytes());
        let mut cursor = Cursor::new(input);
        let mut evidence = scan_evidence();
        assert!(scan_credit_wait_log(
            "over-budget",
            &mut cursor,
            &mut evidence
        ));
        assert!(evidence.truncated);
        assert!(evidence.capture_error.is_some());
        assert!(evidence.observations.is_empty());
    }

    /// A fresh capture record for driving the single-source scan directly.
    fn scan_evidence() -> CreditWaitEvidence {
        CreditWaitEvidence {
            schema: "anywork-frb-credit-wait/1",
            source: "real-frb-producer-poll",
            observations: Vec::new(),
            truncated: false,
            capture_error: None,
        }
    }
}

#[cfg(test)]
mod toolchain_home_tests {
    use super::preserved_toolchain_home;
    use std::ffi::OsString;

    #[test]
    fn explicit_toolchain_homes_are_preserved_and_defaults_use_real_home() {
        assert_eq!(
            preserved_toolchain_home(Some(OsString::from("/custom/cargo-home")), ".cargo").unwrap(),
            OsString::from("/custom/cargo-home")
        );
        assert_eq!(
            preserved_toolchain_home(Some(OsString::new()), ".rustup").unwrap(),
            super::real_platform_user_home()
                .unwrap()
                .join(".rustup")
                .into_os_string()
        );
    }
}
