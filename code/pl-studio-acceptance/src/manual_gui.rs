mod account_usage;
mod bots_fixture;
mod context_replay_recovery;
mod conversation_read_work;
mod delegation;

mod message_submission;
mod mode_editor;
mod model_catalog;
mod question_history;
mod realtime_presentation;
mod shutdown;
mod sidebar_query;
mod skill_activity;
mod thread_lsp_status;
mod timeline_concept;
mod timeline_history_20k;
mod wait_events;
mod web_search;
mod websocket_recovery;

use anyhow::{Context, Result, bail, ensure};
use clap::Parser;
#[cfg(windows)]
use pl_dev_support::process::OwnedChild as Child;
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
use std::ffi::OsStr;
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
#[cfg(not(windows))]
use std::process::Child;
use std::process::{Command, ExitStatus, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[derive(Debug, Parser)]
#[command(
    name = "cargo xtask manual-gui",
    bin_name = "cargo xtask manual-gui",
    about = "Prepare an isolated Studio environment. Use official Dart MCP for manual UI interaction and screenshots; send done on stdin to shut down. Desktop and native presets are judged automatically."
)]
pub(crate) struct ManualGuiOptions {
    /// Isolated environment preset. Manual presets keep a human verdict;
    /// `wait-events`, `conversation-read-work`, `question-history`,
    /// `realtime-presentation`, `sidebar-query` and `thread-lsp-status` are automatic desktop runners;
    /// `shutdown` checks normal native exit and remaining child processes.
    /// ACP native acceptance uses the official Flutter integration_test
    /// suites directly; see design/28-acp.md.
    #[arg(long, default_value = "gui", value_parser = parse_manual_gui_scenario)]
    pub(crate) preset: String,
    /// Enable official Flutter MCP/Driver interaction for the manual gui or
    /// plan-recovery or history-fault preset.
    /// The gui preset uses debug native launch with an exit report, not a
    /// resident hot-reload session.
    #[arg(long)]
    pub(crate) inspect: bool,
    /// Run only stop/background evidence; omission keeps the complete realtime journey.
    #[arg(long, value_parser = ["stop-background"])]
    pub(crate) realtime_focus: Option<String>,
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

fn validate_inspect_options(options: &ManualGuiOptions) -> Result<()> {
    ensure!(
        !options.inspect
            || (matches!(
                options.preset.as_str(),
                "gui" | "plan-recovery" | "history-fault"
            ) && !options.bots_fixture),
        "--inspect requires --preset gui, plan-recovery or history-fault without --bots-fixture"
    );
    Ok(())
}

fn validate_realtime_focus(options: &ManualGuiOptions) -> Result<()> {
    ensure!(
        options.realtime_focus.is_none() || options.preset == "realtime-presentation",
        "--realtime-focus requires --preset realtime-presentation"
    );
    Ok(())
}

fn parse_manual_gui_scenario(value: &str) -> std::result::Result<String, String> {
    if matches!(
        value,
        "realtime-presentation" | "sidebar-query" | "thread-lsp-status"
    ) || pl_provider_fixture::GUI_SCENARIOS.contains(&value)
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
    status_file: &'a Path,
    interrupt: &'a mpsc::Receiver<()>,
    inspect: bool,
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
        let flags = if fixture {
            windows_sys::Win32::System::Threading::CREATE_NEW_PROCESS_GROUP
        } else {
            windows_sys::Win32::System::Threading::CREATE_NO_WINDOW
        };
        #[cfg(windows)]
        let child = {
            let placeholder = Command::new(command.get_program());
            Child::spawn(std::mem::replace(command, placeholder), flags)?
        };
        #[cfg(not(windows))]
        let _ = fixture;
        #[cfg(not(windows))]
        process::configure_background_command(command);
        #[cfg(not(windows))]
        let child = command.spawn().context("failed to start child process")?;
        Ok(Self {
            child,
            stopped: false,
        })
    }

    fn tree_exited(&self) -> Result<bool> {
        #[cfg(windows)]
        {
            Ok(self.child.tree_exited()?)
        }
        #[cfg(not(windows))]
        {
            Ok(true)
        }
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
            // Background launchers have no console to receive a targeted event.
            // The caller records
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
            if let Some(status) = self.child.try_wait()?
                && self.tree_exited()?
            {
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
        #[cfg(windows)]
        {
            let result = self
                .child
                .terminate()
                .map_err(anyhow::Error::from)
                .and_then(|()| self.wait_exit(Duration::from_secs(10)))
                .and_then(|status| status.context("Windows Job cleanup timed out"));
            match result {
                Ok(_) => self.stopped = true,
                Err(error) => eprintln!("failed to reclaim Windows Job: {error}"),
            }
        }
        #[cfg(not(windows))]
        {
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
            self.child.terminate().is_ok()
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
                && self.tree_exited()?
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

// Windows relies on OwnedChild::Drop's single termination request. Explicit
// cleanup owns the deadline and is the only proof of Job completion.
#[cfg(unix)]
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

fn desktop_test_command(workspace: &Path) -> Result<Command> {
    let preparation = env::var_os("ANYWORK_DESKTOP_TEST_PREPARATION");
    let xtask = env::var_os("ANYWORK_DESKTOP_TEST_XTASK");
    desktop_test_command_with_handoff(workspace, preparation.as_deref(), xtask.as_deref())
}

fn desktop_test_command_with_handoff(
    workspace: &Path,
    preparation: Option<&OsStr>,
    xtask: Option<&OsStr>,
) -> Result<Command> {
    let mut command = xtask_command_with_handoff(workspace, preparation, xtask)?;
    command.arg("test-project");
    Ok(command)
}

fn xtask_command(workspace: &Path) -> Result<Command> {
    xtask_command_with_handoff(
        workspace,
        env::var_os("ANYWORK_DESKTOP_TEST_PREPARATION").as_deref(),
        env::var_os("ANYWORK_DESKTOP_TEST_XTASK").as_deref(),
    )
}

fn xtask_command_with_handoff(
    workspace: &Path,
    preparation: Option<&OsStr>,
    xtask: Option<&OsStr>,
) -> Result<Command> {
    let mut command = match (preparation, xtask) {
        (None, None) => {
            let mut command = Command::new("cargo");
            command.arg("xtask");
            command
        }
        (Some(preparation), Some(xtask)) if !preparation.is_empty() && !xtask.is_empty() => {
            let mut command = Command::new(xtask);
            command
                .env("ANYWORK_DESKTOP_TEST_PREPARATION", preparation)
                .env("ANYWORK_DESKTOP_TEST_XTASK", xtask);
            command
        }
        _ => bail!(
            "ANYWORK_DESKTOP_TEST_PREPARATION and ANYWORK_DESKTOP_TEST_XTASK must be set together and non-empty"
        ),
    };
    command.current_dir(workspace);
    Ok(command)
}

pub(crate) fn run(options: ManualGuiOptions) -> Result<()> {
    ensure!(
        !options.profile_read_samples || options.preset == "conversation-read-work",
        "--profile-read-samples requires --preset conversation-read-work"
    );
    validate_inspect_options(&options)?;
    validate_realtime_focus(&options)?;
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
                    | "message-submission"
                    | "timeline-concept"
                    | "timeline-boundary"
                    | "media-handoff"
                    | "stress-body-large"
                    | "wait-events"
                    | "conversation-read-work"
                    | "sidebar-query"
                    | "thread-lsp-status"
            )
            || pl_provider_fixture::delegation::Scenario::parse(&options.preset).is_some(),
        "--retain-environment is supported by --preset gui, tool-scroll, \
         timeline-history, timeline-history-20k, question-history, realtime-presentation, \
         timeline-concept, timeline-boundary, media-handoff, message-submission, stress-body-large, wait-events, conversation-read-work, \
         sidebar-query, thread-lsp-status and the delegation scenes"
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
    bots_fixture::validate(&options)?;
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
    let output = options.output.clone().unwrap_or_else(|| {
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

    if options.preset == "thread-lsp-status" {
        ensure!(
            cfg!(target_os = "linux"),
            "Thread LSP integration requires Linux"
        );
        let working = tempfile::Builder::new()
            .prefix("environment-")
            .tempdir_in(&output)?;
        let result = thread_lsp_status::run(&workspace, working.path(), &output, &interrupt_rx);
        if options.retain_environment || result.is_err() {
            let home = working.path().join("sandbox/studio-home");
            let retained = keep_isolated_environment(working, &home, &output, None);
            return match (result, retained) {
                (Ok(()), retained) => retained,
                (Err(error), Ok(())) => Err(error),
                (Err(error), Err(retain_error)) => Err(error.context(format!(
                    "retaining the Thread LSP environment also failed: {retain_error:#}"
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
    let fixture_scenario = options.preset.as_str();
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
    if let Some(focus) = options.realtime_focus.as_deref() {
        fixture_command.args(["--realtime-focus", focus]);
    }
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
            | "history-fault"
            | "mode-editor"
            | "context-replay-recovery"
            | "websocket-recovery"
            | "call-lifecycle-recovery"
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
    if options.preset == "shutdown" {
        fixture_command.env(
            "ANYWORK_SHUTDOWN_TOOL_COMMAND",
            shutdown::tool_command(
                &fixture_executable,
                &working.path().join("shutdown-tool-coord.json"),
            ),
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

    if matches!(
        options.preset.as_str(),
        "timeline-concept" | "timeline-boundary" | "media-handoff"
    ) {
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
                capture_presentation: capture_presentation || options.preset != "timeline-concept",
                provider_url: &ready.base_url,
                mode: match options.preset.as_str() {
                    "timeline-boundary" => timeline_concept::TimelineConceptMode::Boundary,
                    "media-handoff" => timeline_concept::TimelineConceptMode::MediaHandoff,
                    _ => timeline_concept::TimelineConceptMode::Journey,
                },
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

    if options.preset == "message-submission" {
        let project = working.path().join("message-submission-project");
        let result = message_submission::run(
            &message_submission::SubmissionScenario {
                workspace: &workspace,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
                interrupt: &interrupt_rx,
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
                    "retaining the failed message-submission environment also failed: {retain_error:#}"
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
                provider_url: &ready.base_url,
                realtime_focus: options.realtime_focus.as_deref(),
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
            options.inspect,
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
                status_file: &status_file,
                interrupt: &interrupt_rx,
                inspect: options.inspect,
            },
            fixture,
        );
    }

    if options.preset == "shutdown" {
        return shutdown::run(
            &shutdown::ShutdownScenario {
                workspace: &workspace,
                home: &home,
                working: working.path(),
                output: &output,
                fixture_log: &fixture_log_path,
                requests_file: &requests_file,
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
        // Explicit retention also preserves failed runs for state/checkpoint diagnosis.
        if options.retain_environment {
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
    let native_exit_report = configure_manual_gui_launch(&mut gui_command, &options, &output);
    if let Some(report) = &native_exit_report {
        match fs::remove_file(report) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error).context("failed to clear previous native exit report"),
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
        let vm_url = wait_for_vm_in_phase(
            &gui_log_path,
            &mut gui,
            &mut fixture,
            &interrupt_rx,
            if native_exit_report.is_some() {
                VmStartupPhase::NativePreparation
            } else {
                VmStartupPhase::Immediate
            },
            Duration::from_secs(600),
        )?;
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
                 expands a tool with image recycling, then type done to shut down. \
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
                 paging and frames, then type done to shut down. VM service: {vm_url}",
                project.display()
            );
        }
        println!(
            "Use official Dart MCP for UI interaction and screenshots; no action codes are required. Send done on stdin to request normal shutdown and wait for the launcher to exit; EOF or Ctrl-C cancels."
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
            ensure!(
                interrupt_rx.try_recv().is_err(),
                "manual GUI cancelled; human verdict remains pending"
            );
            ensure!(!gui.exited()?, "GUI exited before manual review completed");
            ensure!(
                !fixture.exited()?,
                "account fixture exited during manual review"
            );
            match input_rx.try_recv() {
                Ok(InputEvent::Line(line)) => {
                    if let Some(operation) = record_session_line(bots.as_ref(), &line)? {
                        operations.push(operation);
                        fs::write(
                            output.join("operations.json"),
                            serde_json::to_vec_pretty(&operations)?,
                        )?;
                    }
                    continue;
                }
                Ok(InputEvent::Done) => {
                    request_app_exit(
                        &app_dir,
                        &vm_url,
                        &output.join("request-exit.log"),
                        &interrupt_rx,
                    )?;
                    wait_manual_shutdown(
                        &mut gui,
                        &mut fixture,
                        &interrupt_rx,
                        Duration::from_secs(30),
                        native_exit_report.as_deref(),
                    )?;
                    fs::write(output.join("shutdown-stage.txt"), "shutdown_completed\n")?;
                    return Ok(());
                }
                Ok(InputEvent::Eof) => bail!("manual GUI input closed before done"),
                Err(mpsc::TryRecvError::Disconnected) => bail!("manual GUI input unavailable"),
                Err(mpsc::TryRecvError::Empty) => {}
            }
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
    let session = finish_manual_gui_session(
        session,
        &mut gui,
        native_exit_report.as_deref(),
        Duration::from_secs(10),
        Some(&gui_log_path),
    );
    let gui_log_result = write_sanitized_log(&gui_log_path, &output.join("gui.log"));
    // Native failures first give the launcher its complete cleanup window.
    // Drop is only a last-resort group cleanup if that wait failed; it does
    // not establish reclamation of the independent app group.
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
                require_manual_shutdown(&output)?;
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
            let mut command = desktop_test_command(workspace)?;
            command
                .args(["--suite", "desktop", "--case", "timeline_presentation"])
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
            let mut gui =
                start_timeline_history_gui(workspace, home, &gui_log, &native_exit, false)?;
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
    let continuity_result = (|| -> Result<()> {
        let continuity_source = home.join("studio/logs/studio.log");
        let mut continuity_evidence = File::create(output.join("timeline-history-continuity.log"))?;
        writeln!(
            continuity_evidence,
            "source_scope=current studio.log only; rolling archives not included"
        )?;
        if continuity_source.is_file() {
            for line in fs::read_to_string(&continuity_source)?.lines() {
                if line.split_once(": ").is_some_and(|(header, _)| {
                    header.split_whitespace().last() == Some("conversation_continuity")
                }) {
                    writeln!(
                        continuity_evidence,
                        "{}",
                        sanitize_driver_line(line, &redactions)
                    )?;
                }
            }
        } else {
            writeln!(continuity_evidence, "source_status=missing")?;
        }
        Ok(())
    })();
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
    continuity_result?;
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
    inspect: bool,
) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    command
        .current_dir(workspace)
        // Profile 与发布构建分开取证；只有显式采样调用方装配官方 Driver。
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
    if inspect {
        command.arg("--inspect");
    }
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

/// Configures the existing native launcher and its real exit report, leaving
/// the private bots command isolated and profile presets in profile mode.
fn configure_manual_gui_launch(
    command: &mut Command,
    options: &ManualGuiOptions,
    output: &Path,
) -> Option<PathBuf> {
    if options.bots_fixture {
        return None;
    }
    if options.inspect {
        command.arg("--inspect");
    }
    if options.preset == "gui" {
        command.args(["--log-level", "info"]);
    }
    let profile = matches!(options.preset.as_str(), "stress" | "tool-scroll");
    if profile {
        command.arg("--profile");
    }
    if options.preset == "gui" || options.seed_home_copy.is_some() || profile {
        // The Flutter resident wrapper can mask abnormal native exits. Reuse
        // the direct native launcher (including inspect_main when requested).
        let report = output.join("native-exit.json");
        command
            .args(["--native-launch", "--native-exit-report"])
            .arg(&report);
        Some(report)
    } else {
        None
    }
}

fn require_manual_shutdown(output: &Path) -> Result<()> {
    let stage = fs::read_to_string(output.join("shutdown-stage.txt"))
        .context("retained environment requires verified native shutdown")?;
    ensure!(
        stage.trim() == "shutdown_completed",
        "runtime shutdown did not complete"
    );
    require_native_exit(&output.join("native-exit.json"), None)
}

/// A failed session stays failed even when cancellation reclaims the tree.
/// Give the existing supervisor time to reap independent app groups before the
/// owner can reach its short, group-only Drop fallback.
fn finish_manual_gui_session(
    session: Result<()>,
    gui: &mut OwnedProcess,
    native_exit_report: Option<&Path>,
    cleanup_timeout: Duration,
    startup_log: Option<&Path>,
) -> Result<()> {
    if session.is_ok() || gui.stopped {
        return session;
    }
    let Some(report) = native_exit_report else {
        return session;
    };
    let cleanup = (|| -> Result<()> {
        let deadline = Instant::now() + cleanup_timeout;
        #[cfg(any(target_os = "linux", windows))]
        let mut native_phase = match startup_log {
            Some(log) => native_launch_started(&fs::read_to_string(log)?),
            None => true,
        };
        #[cfg(not(any(target_os = "linux", windows)))]
        let native_phase = {
            // Other hosts lack a verified preparation scope join and
            // retain the native-owner report barrier, including before launch.
            let _ = startup_log;
            true
        };
        // A reaped cargo child can leave the native supervisor alive in the
        // original group. Always request that group's cooperative stop.
        let stop_requested = gui.request_stop();
        #[cfg(windows)]
        let mut stop_requested = if !native_phase {
            gui.child
                .terminate()
                .context("failed to stop GUI preparation Job")?;
            true
        } else {
            stop_requested
        };
        // Do not use wait_exit here: direct-child reap is not subtree cleanup.
        // Keep observing the phase even while the original child is still up:
        // cancellation can race the preparation-to-native transition.
        loop {
            ensure!(
                Instant::now() < deadline,
                "native launcher cleanup timed out (stop_requested={stop_requested}); independent app subtree reclamation is unconfirmed; owner-group termination is not subtree completion"
            );
            #[cfg(any(target_os = "linux", windows))]
            if !native_phase
                && let Some(log) = startup_log
                && native_launch_started(&fs::read_to_string(log)?)
            {
                native_phase = true;
                // The first signal may have preceded the native supervisor's
                // installation. Notify that owner too, without resetting time.
                gui.request_stop();
            }
            #[cfg(windows)]
            if native_phase
                && !stop_requested
                && !gui.tree_exited()?
                && let Some(log) = startup_log
                && let Some(vm_url) = vm_service_url(&fs::read_to_string(log)?)
            {
                // Background Windows launchers have no console signal target.
                // Reuse the existing product exit command, under this cleanup
                // deadline, without consuming the cancelled session's receiver.
                let (_sender, cleanup_interrupt) = mpsc::channel();
                request_app_exit_until(
                    &paths::studio_app_dir(&paths::workspace_root()?),
                    &vm_url,
                    &report.with_file_name("cleanup-request-exit.log"),
                    &cleanup_interrupt,
                    deadline,
                )?;
                stop_requested = true;
            }
            let child_reaped = gui.exit_status()?.is_some();
            #[cfg(any(target_os = "linux", windows))]
            if child_reaped && !native_phase && preparation_group_exited(gui)?
            // No group member can now publish a late boundary. Read again
            // after joining, not from the pre-cancellation phase snapshot.
            {
                let log = startup_log.context("missing native preparation phase log")?;
                if native_launch_started(&fs::read_to_string(log)?) {
                    native_phase = true;
                    gui.request_stop();
                } else {
                    eprintln!("manual GUI preparation stopped; product not started");
                    gui.mark_reaped();
                    return Ok(());
                }
            }
            // Cargo may exit before the internal supervisor finishes its join.
            // A post-boundary run always needs that supervisor's report.
            if child_reaped && native_phase && gui.tree_exited()? {
                match fs::read(report) {
                    Ok(bytes) => match serde_json::from_slice::<serde_json::Value>(&bytes) {
                        Ok(report) => {
                            ensure!(
                                report["schema"] == "anywork-native-exit/1"
                                    && report["pid"].as_u64().is_some_and(|pid| pid > 0)
                                    && report["cancelled"].is_boolean()
                                    && report["descendantsAtRootExit"].is_array()
                                    && report["reclaimedDescendants"].is_array(),
                                "invalid native cleanup report; independent app subtree reclamation is unconfirmed"
                            );
                            break;
                        }
                        // fs::write is not atomic. Wait only for an unfinished JSON
                        // write, never retry a complete malformed report.
                        Err(error) if error.is_eof() => {}
                        Err(error) => return Err(error).context("invalid native cleanup report"),
                    },
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                    Err(error) => {
                        return Err(error).context("failed to read native cleanup report");
                    }
                }
            }
            thread::sleep(Duration::from_millis(50));
        }
        gui.mark_reaped();
        Ok(())
    })();
    bots_fixture::with_cleanup(session, cleanup)
}

#[cfg(windows)]
fn preparation_group_exited(gui: &OwnedProcess) -> Result<bool> {
    gui.tree_exited()
        .context("failed to inspect preparation Job")
}

/// Only absence of the original build group establishes preparation cleanup.
/// Query errors stay unknown; a reaped outer cargo child alone is insufficient.
#[cfg(target_os = "linux")]
fn preparation_group_exited(gui: &OwnedProcess) -> Result<bool> {
    let output = Command::new("ps")
        .args(["-e", "-o", "pgid="])
        .output()
        .context("failed to inspect preparation process group")?;
    ensure!(
        output.status.success(),
        "preparation process group inspection failed: {}",
        output.status
    );
    let groups = std::str::from_utf8(&output.stdout)?;
    for group in groups.split_whitespace() {
        if group.parse::<u32>()? == gui.child.id() {
            return Ok(false);
        }
    }
    Ok(true)
}

/// 等待被 `ext.anywork.requestExit` 协调关闭的 GUI 自然退出，并返回真实退出状态。
fn wait_for_gui_exit(
    gui: &mut OwnedProcess,
    timeout: Duration,
    phase: &str,
) -> Result<std::process::ExitStatus> {
    let deadline = Instant::now() + timeout;
    loop {
        if let Some(status) = gui.child.try_wait()?
            && gui.tree_exited()?
        {
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

/// Waits for the existing launcher's owned process-tree cleanup, not just the
/// requestExit acknowledgement. Failure leaves the owner armed for cleanup.
fn wait_manual_shutdown(
    gui: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
    timeout: Duration,
    native_exit_report: Option<&Path>,
) -> Result<()> {
    let deadline = Instant::now() + timeout;
    loop {
        ensure!(
            interrupt.try_recv().is_err(),
            "manual GUI cancelled during shutdown; human verdict remains pending"
        );
        ensure!(
            !fixture.exited()?,
            "account fixture exited during manual shutdown"
        );
        if let Some(status) = gui.exit_status()?
            && gui.tree_exited()?
        {
            ensure!(status.success(), "manual GUI shutdown failed: {status}");
            if let Some(report) = native_exit_report {
                require_native_exit(report, None)?;
            }
            gui.mark_reaped();
            return Ok(());
        }
        ensure!(
            Instant::now() < deadline,
            "manual GUI launcher did not exit after coordinated shutdown"
        );
        thread::sleep(Duration::from_millis(100));
    }
}

fn record_session_line(
    bots: Option<&bots_fixture::BotsFixture>,
    line: &str,
) -> Result<Option<ManualOperation>> {
    let at_unix_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |time| time.as_millis());
    let Some(bots) = bots else {
        println!("Unrecognized stdin command ignored; use Dart MCP for UI interaction.");
        return Ok(None);
    };
    match bots_fixture::classify_line(line) {
        bots_fixture::EnvLine::NotEnvironment => {
            println!("Unrecognized stdin command ignored; use Dart MCP for UI interaction.");
            Ok(None)
        }
        bots_fixture::EnvLine::UnknownEnv => {
            println!(
                "Unknown bots environment command rejected; platform scripts and synthetic samples are unchanged."
            );
            Ok(Some(ManualOperation {
                at_unix_ms,
                action: "env-command-rejected",
                outcome: Some("rejected"),
            }))
        }
        bots_fixture::EnvLine::Registration(command) => {
            bots.apply_registration_env(command)?;
            println!(
                "Queued next mock registration poll ({}); this is not GUI authorization or a product pass.",
                command.action_code()
            );
            Ok(Some(ManualOperation {
                at_unix_ms,
                action: command.action_code(),
                outcome: Some("script-set"),
            }))
        }
        bots_fixture::EnvLine::Message(command) => {
            bots.apply_message_env(command)?;
            println!(
                "Queued one fixed synthetic direct message ({}) on the live platform websocket; queued for delivery is not product consumption, approval, execution, or a send pass.",
                command.action_code()
            );
            Ok(Some(ManualOperation {
                at_unix_ms,
                action: command.action_code(),
                outcome: Some("event-queued"),
            }))
        }
        bots_fixture::EnvLine::Conversations(command) => {
            bots.apply_conversations_env(command)?;
            println!(
                "Replaced the peer's synthetic conversation and history samples ({}); this is not GUI authorization or a product pass.",
                command.action_code()
            );
            Ok(Some(ManualOperation {
                at_unix_ms,
                action: command.action_code(),
                outcome: Some("environment-set"),
            }))
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
        // Disable copied executable definitions through their owner. Never launch
        // a source account, and keep its isolated document rather than deleting it.
        let mut snapshot = runtime.read()?;
        let definitions = snapshot.acp.definitions.clone();
        for entry in definitions.values() {
            let mut definition = entry.definition.clone();
            definition.enabled = false;
            snapshot = runtime.save_acp_definition(
                snapshot.revision,
                &definition,
                Some(entry.document_revision),
            )?;
        }
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
    let lsp_dir = home.join("lsp");
    if lsp_dir.is_dir() {
        fs::remove_dir_all(&lsp_dir)?;
    }
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
            // This scenario must start the fixture process tree before testing shutdown.
            required: true,
            transport: McpServerTransport::Stdio,
            startup_mode: Default::default(),
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

/// One scenario-owned LSP document to declare in an isolated home.
///
/// A named spec instead of a long positional argument list: the writer stays a
/// small call site and the fields carry their own meaning at construction.
pub(super) struct LspServerSpec<'a> {
    /// The document id; must be unique in this scope.
    pub(super) id: &'a str,
    /// Server program (the fixture binary in `--lsp-stdio` mode).
    pub(super) command: &'a Path,
    /// Program arguments (the mode flag and coordination file path).
    pub(super) args: &'a [String],
    /// The unique language id the server answers.
    pub(super) language_id: &'a str,
    /// Workspace detection rules; empty means "all workspaces".
    pub(super) detection: &'a [String],
    /// File extensions the server claims; empty means none.
    pub(super) extensions: &'a [String],
}

/// Writes the isolated home's config and one independently versioned LSP document.
///
/// The shutdown acceptance points this at its own fake LSP peer (the fixture
/// binary in `--lsp-stdio` mode) so the product starts it through the real
/// supervised worker during asynchronous preparation; the server itself
/// spawns a SIGTERM-ignoring grandchild the product must reclaim.
///
/// Private to `manual_gui` (only the descendant `shutdown` module uses it) so
/// the private [`FixtureReady`] parameter stays within its own visibility.
fn write_config_with_lsp_server(
    home: &Path,
    ready: &FixtureReady,
    spec: &LspServerSpec<'_>,
) -> Result<()> {
    let config = fixture_config(ready, ModelTransportProfile::responses_http())?;
    let mut entry = toml::Table::new();
    entry.insert("schema_version".to_owned(), toml::Value::Integer(1));
    entry.insert("id".to_owned(), toml::Value::String(spec.id.to_owned()));
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
    let directory = home.join("lsp/host");
    fs::create_dir_all(&directory)?;
    fs::write(
        directory.join(format!("{}.toml", spec.id)),
        toml::to_string(&entry)?,
    )?;
    persist_config(home, &config)
}

/// Builds the standalone fixture with Cargo's release profile before service
/// deadlines; GUI build mode is independent. Cargo owns artifact discovery, so
/// its configured target directory and native executable suffix are not guessed.
fn build_fixture_executable(workspace: &Path) -> Result<PathBuf> {
    const PACKAGE: &str = "pl-provider-fixture";
    if let Some(executable) = pl_dev_support::quality_inputs::artifact(workspace, PACKAGE)? {
        return Ok(executable);
    }
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
    if matches!(
        ready.scenario.as_str(),
        "tool-scroll" | "timeline-concept" | "media-handoff"
    ) {
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
    wait_for_vm_in_phase(
        path,
        gui,
        fixture,
        interrupt,
        VmStartupPhase::Immediate,
        Duration::from_secs(600),
    )
}

const NATIVE_LAUNCH_BOUNDARY: &str = "startup_stage=native_launch_ready\n";

fn native_launch_started(log: &str) -> bool {
    log.split_inclusive('\n')
        .any(|line| line == NATIVE_LAUNCH_BOUNDARY)
}

#[derive(Clone, Copy)]
enum VmStartupPhase {
    Immediate,
    NativePreparation,
}

struct VmStartupBudget {
    deadline: Option<Instant>,
    timeout: Duration,
}

impl VmStartupBudget {
    fn new(phase: VmStartupPhase, timeout: Duration, now: Instant) -> Self {
        Self {
            deadline: match phase {
                VmStartupPhase::Immediate => Some(now + timeout),
                VmStartupPhase::NativePreparation => None,
            },
            timeout,
        }
    }

    fn observe(&mut self, log: &str, now: Instant) {
        if self.deadline.is_none() && native_launch_started(log) {
            self.deadline = Some(now + self.timeout);
        }
    }
}

fn wait_for_vm_in_phase(
    path: &Path,
    gui: &mut OwnedProcess,
    fixture: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
    phase: VmStartupPhase,
    timeout: Duration,
) -> Result<String> {
    let mut budget = VmStartupBudget::new(phase, timeout, Instant::now());
    loop {
        let log = fs::read_to_string(path)?;
        budget.observe(&log, Instant::now());
        let mut native_vm_url = None;
        if budget.deadline.is_some()
            && let Some(url) = vm_service_url(&log)
        {
            if matches!(phase, VmStartupPhase::Immediate) {
                return Ok(url);
            }
            native_vm_url = Some(url);
        }
        if let Some(status) = gui.exit_status()? {
            bail!("GUI exited before publishing VM service ({status})");
        }
        ensure!(
            !fixture.exited()?,
            "account fixture exited while GUI started"
        );
        ensure!(
            interrupt.try_recv().is_err(),
            "manual GUI cancelled while starting GUI"
        );
        ensure!(
            budget
                .deadline
                .is_none_or(|deadline| Instant::now() < deadline),
            "GUI VM service startup timed out"
        );
        if let Some(url) = native_vm_url {
            return Ok(url);
        }
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
fn capture_command(app_dir: &Path) -> Result<Command> {
    // Use the SDK selected by Flutter pub, not a PATH batch launcher which
    // re-enters Flutter's SDK maintenance and nested shell/lock machinery.
    let config_path = app_dir.join(".dart_tool/package_config.json");
    let config: serde_json::Value = serde_json::from_slice(
        &fs::read(&config_path)
            .context("read prepared Flutter package config for host Dart tools")?,
    )?;
    let root = config["flutterRoot"]
        .as_str()
        .context("prepared package config has no flutterRoot")?;
    let sdk = reqwest::Url::parse(root)?
        .to_file_path()
        .map_err(|()| {
            anyhow::anyhow!("Flutter package config flutterRoot is not a local file URI")
        })?
        .join("bin/cache/dart-sdk/bin")
        .join(if cfg!(windows) { "dart.exe" } else { "dart" });
    let mut command = Command::new(sdk);
    command
        .current_dir(app_dir)
        .arg("--packages=.dart_tool/package_config.json")
        .arg("tool/capture_ui.dart");
    Ok(command)
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
    let mut command = capture_command(app_dir)?;
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
    request_app_exit_until(
        app_dir,
        vm_url,
        log_path,
        interrupt,
        Instant::now() + Duration::from_secs(30),
    )
}

fn request_app_exit_until(
    app_dir: &Path,
    vm_url: &str,
    log_path: &Path,
    interrupt: &mpsc::Receiver<()>,
    deadline: Instant,
) -> Result<()> {
    let log = File::create(log_path)?;
    let mut command = capture_command(app_dir)?;
    command
        .args(["--vm-url", vm_url, "--exit"])
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    let mut capture = OwnedProcess::start(&mut command, false)?;
    loop {
        if let Some(status) = capture.wait_exit(Duration::ZERO)? {
            ensure!(
                status.success(),
                "requestExit failed ({status}); see {}",
                log_path.display()
            );
            return Ok(());
        }
        ensure!(interrupt.try_recv().is_err(), "requestExit cancelled");
        ensure!(
            Instant::now() < deadline,
            "requestExit timed out (helper root status={:?})",
            capture.exit_status()?
        );
        thread::sleep(Duration::from_millis(100));
    }
}

/// Waits for the operator to type `done` while the GUI and optional fixture stay up.
fn wait_operator_done(
    prompt: &str,
    gui: &mut OwnedProcess,
    fixture: Option<&mut OwnedProcess>,
    interrupt: &mpsc::Receiver<()>,
    timeout: Duration,
) -> Result<()> {
    wait_operator_done_observing(prompt, gui, fixture, interrupt, timeout, || Ok(()))
}

fn wait_operator_done_observing(
    prompt: &str,
    gui: &mut OwnedProcess,
    mut fixture: Option<&mut OwnedProcess>,
    interrupt: &mpsc::Receiver<()>,
    timeout: Duration,
    mut observe: impl FnMut() -> Result<()>,
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
        observe()?;
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
/// operator observes the real failure and retry controls while the lock is held.
/// Persisted watermarks, original records and isolated tool execution evidence
/// are checked independently. The lock is then released with no automatic recovery,
/// and the journey drives the explicit controls in order — retry-save until the
/// backend verifies `canResume` while the hard latch `resumeRequired` stays set,
/// then continue — proving the deferred tool and the follow-up answer each
/// complete exactly once.
///
/// The official inspection Driver exposes widgets, not a `storageRecovery` JSON
/// snapshot. Generation/fence invariants retain their runtime test evidence;
/// manual observations must not be reported as direct typed-state assertions.
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
        status_file,
        interrupt,
        inspect,
    } = context;
    let gui_log_path = working.join("history-fault-gui.log");
    let native_exit_path = output.join("history-fault-native-exit.json");
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
            let mut gui = start_history_fault_gui(
                workspace,
                home,
                &gui_log_path,
                &native_exit_path,
                *inspect,
            )?;
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
            let mut fault_observed_at = None;
            let locked_phase = (|| -> Result<()> {
                let primed_status = plan_recovery_read_status(status_file)?;
                lock_report.as_mut().expect("lock report initialized")["primedFixture"] =
                    serde_json::to_value(primed_status)?;
                ensure!(
                    history_fault_required_consumed(primed_status)? == 1,
                    "unexpected fixture stage at the initial locked observation"
                );
                fs::write(&acquired_marker, "acquired")?;
                wait_operator_done_observing(
                    "history-fault locked: send the fault turn, verify a retry still fails at the safe boundary, then type done before the 300-second lock expires.",
                    &mut gui,
                    Some(&mut fixture),
                    interrupt,
                    Duration::from_secs(300),
                    || {
                        let status = plan_recovery_read_status(status_file)?;
                        let consumed = history_fault_required_consumed(status)?;
                        let report = lock_report.as_mut().expect("lock report initialized");
                        report["whileLockedFixture"] = serde_json::to_value(status)?;
                        ensure!(
                            consumed <= 2,
                            "fault tool continued while SQLite was locked"
                        );
                        if consumed == 2 && fault_observed_at.is_none() {
                            fault_observed_at = Some(Instant::now());
                            report["faultObservedHeldMillis"] =
                                serde_json::json!(locked_at.elapsed().as_millis());
                        }
                        Ok(())
                    },
                )?;
                let observation_elapsed = fault_observed_at
                    .context("no fault request was accepted while SQLite was locked")?
                    .elapsed();
                lock_report.as_mut().expect("lock report initialized")["faultObservationMillis"] =
                    serde_json::json!(observation_elapsed.as_millis());
                ensure!(
                    observation_elapsed >= Duration::from_secs(30),
                    "fault request was not held through the retryable-conflict window"
                );
                let while_locked = history_lock_watermark(&database)?;
                lock_report.as_mut().expect("lock report initialized")["whileLocked"] =
                    serde_json::to_value(while_locked)?;
                let while_originals = history_fault_originals(&database)?;
                let report = lock_report.as_mut().expect("lock report initialized");
                report["whileLockedItems"] = serde_json::json!(while_originals.answers.len());
                report["whileLockedOriginals"] = serde_json::to_value(&while_originals)?;
                let while_executions = history_fault_execution_count(&project)?;
                lock_report.as_mut().expect("lock report initialized")["whileLockedPhysicalExecutions"] =
                    serde_json::json!(while_executions);
                ensure!(
                    while_executions == 0,
                    "fault tool executed before retry/resume"
                );
                Ok(())
            })();
            let release = lock.finish();
            if let Some(report) = lock_report.as_mut() {
                report["heldMillis"] = serde_json::json!(locked_at.elapsed().as_millis());
                report["lockedPhaseSucceeded"] = serde_json::json!(locked_phase.is_ok());
                if let Err(error) = &locked_phase {
                    report["lockedPhaseError"] = serde_json::json!(format!("{error:#}"));
                }
                report["releaseSucceeded"] = serde_json::Value::Bool(release.is_ok());
                if let Err(error) = &release {
                    report["releaseError"] = serde_json::Value::String(format!("{error:#}"));
                }
            }
            if let Err(error) = locked_phase {
                return match release {
                    Ok(()) => Err(error),
                    Err(release_error) => {
                        Err(error.context(format!("lock release also failed: {release_error:#}")))
                    }
                };
            }
            release?;
            fs::write(&released_marker, "released")?;
            wait_operator_done(
                "history-fault resume: retry-save until canResume is true, continue, confirm the deferred tool and follow-up answer each complete once, then type done.",
                &mut gui,
                Some(&mut fixture),
                interrupt,
                Duration::from_secs(3_600),
            )?;
            capture(app_dir, Path::new(""), &vm_url, output, interrupt, true)?;
            let status = wait_for_gui_exit(&mut gui, Duration::from_secs(180), "history-fault")?;
            ensure!(
                status.success(),
                "history-fault GUI did not exit successfully: {status}"
            );
            require_native_exit(&native_exit_path, None)?;
        }
        let database = history_lock_database(home)?;
        after = Some(HistoryFaultAfter {
            watermark: history_lock_watermark(&database)?,
            originals: history_fault_originals(&database)?,
            physical_executions: history_fault_execution_count(&project)?,
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
    fs::write(
        output.join("history-fault-durable.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "originals": after_state.originals,
            "physicalExecutions": after_state.physical_executions,
            "before": before_watermark,
            "after": after_state.watermark,
        }))?,
    )?;
    ensure!(
        after_state.watermark.turns == before_watermark.turns + 1,
        "history writer did not commit exactly the faulted turn: {before_watermark:?} -> {:?}",
        after_state.watermark
    );
    after_state.originals.validate()?;
    ensure!(
        after_state.physical_executions == 1,
        "expected exactly one physical fault-tool execution, found {}",
        after_state.physical_executions
    );
    // Direct evidence the exclusive lock really paused the writer and the fault
    // held the answer out of durable history: the committed turn count and write
    // watermark must be unchanged while the lock was held, and the answer must be
    // absent. A failed read is missing required evidence, never a pass.
    let while_locked: HistoryLockWatermark = lock_report
        .as_ref()
        .context("history-fault lock report is missing")
        .and_then(|report| Ok(serde_json::from_value(report["whileLocked"].clone())?))?;
    ensure!(
        while_locked == before_watermark,
        "history writer committed while the exclusive lock was held: \
         {before_watermark:?} -> {while_locked:?}"
    );
    let while_originals: HistoryFaultOriginals = lock_report
        .as_ref()
        .context("history-fault lock report is missing")
        .and_then(|report| {
            Ok(serde_json::from_value(
                report["whileLockedOriginals"].clone(),
            )?)
        })?;
    ensure!(
        while_originals.answers.is_empty() && while_originals.tools.is_empty(),
        "fault-turn originals were durable while the exclusive lock was held"
    );
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
    inspect: bool,
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
            let mut gui = start_recovery_gui(workspace, home, &gui_logs[0].0, inspect)?;
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
            let status = wait_for_gui_exit(&mut gui, Duration::from_secs(180), "first")?;
            ensure!(
                status.success(),
                "plan-recovery first GUI launcher exited with {status}"
            );
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
            let mut gui = start_recovery_gui(workspace, home, &gui_logs[1].0, inspect)?;
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
            let status = wait_for_gui_exit(&mut gui, Duration::from_secs(180), "restart")?;
            ensure!(
                status.success(),
                "plan-recovery restart GUI launcher exited with {status}"
            );
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
            let mut gui = start_recovery_gui(workspace, home, &gui_logs[2].0, inspect)?;
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
            let status = wait_for_gui_exit(&mut gui, Duration::from_secs(180), "recheck")?;
            ensure!(
                status.success(),
                "plan-recovery recheck GUI launcher exited with {status}"
            );
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
    #[cfg(target_os = "linux")]
    {
        // A synthetic HOME has no desktop user-dirs configuration. Provide the
        // standard Documents entry instead of reading the operator's XDG config
        // or making the product fall back to an invented workspace location.
        let config = home.join(".config");
        fs::create_dir_all(&config)?;
        fs::write(
            config.join("user-dirs.dirs"),
            "XDG_DOCUMENTS_DIR=\"$HOME/Documents\"\n",
        )?;
        command.env("XDG_CONFIG_HOME", config);
    }
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

fn start_recovery_gui(
    workspace: &Path,
    home: &Path,
    log_path: &Path,
    inspect: bool,
) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    configure_isolated_gui_home(&mut command, home)?;
    command
        .current_dir(workspace)
        .args(["xtask", "run-gui", "--capture"])
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    if inspect {
        command.arg("--inspect");
    }
    OwnedProcess::start(&mut command, false)
}

/// Durable history state read back after the faulted turn committed.
struct HistoryFaultAfter {
    watermark: HistoryLockWatermark,
    originals: HistoryFaultOriginals,
    physical_executions: usize,
}

fn history_fault_required_consumed(
    status: pl_provider_fixture::FixtureLiveStatus,
) -> Result<usize> {
    let script = pl_provider_fixture::gui_history_fault_script();
    ensure!(
        status.rejected == 0
            && status.expected_steps == script.len()
            && status.consumed_steps <= script.len(),
        "invalid history-fault fixture stage evidence: {status:?}"
    );
    Ok(script[..status.consumed_steps]
        .iter()
        .filter(|step| !step.optional)
        .count())
}

fn history_fault_execution_count(project: &Path) -> Result<usize> {
    let path = project.join(pl_provider_fixture::GUI_HISTORY_FAULT_EXECUTIONS_FILE);
    let contents = match fs::read_to_string(&path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(0),
        Err(error) => return Err(error).context("read isolated fault-tool execution receipts"),
    };
    ensure!(
        contents
            .lines()
            .all(|line| line == pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_MARKER),
        "unexpected isolated fault-tool execution receipt contents"
    );
    Ok(contents.lines().count())
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct HistoryFaultItemIdentity {
    item_id: String,
    thread_id: String,
    turn_id: String,
    tool_call_id: Option<String>,
}

#[derive(Debug, Default, serde::Serialize, serde::Deserialize)]
struct HistoryFaultOriginals {
    answers: Vec<HistoryFaultItemIdentity>,
    tools: Vec<HistoryFaultItemIdentity>,
}

impl HistoryFaultOriginals {
    fn validate(&self) -> Result<()> {
        ensure!(
            self.answers.len() == 1,
            "expected exactly one durable fault answer: {self:?}"
        );
        ensure!(
            self.tools.len() == 1,
            "expected exactly one durable fault tool result: {self:?}"
        );
        ensure!(
            !self.answers[0].turn_id.is_empty()
                && !self.answers[0].item_id.is_empty()
                && !self.tools[0].item_id.is_empty()
                && self.answers[0].turn_id == self.tools[0].turn_id
                && !self.answers[0].thread_id.is_empty()
                && self.answers[0].thread_id == self.tools[0].thread_id
                && self.tools[0]
                    .tool_call_id
                    .as_ref()
                    .is_some_and(|id| id == pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_CALL_ID),
            "fault answer and tool result must belong to the same real Turn: {self:?}"
        );
        Ok(())
    }
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
            "complete durable watermarks and canonical typed originals are read from the actual locked database; missing reads fail instead of passing",
            "after explicit retry/resume the canonical Final Completed answer and Succeeded tool result belong to the same Thread/Turn, with the exact fixture call id and one physical execution receipt",
            "successful native process exit and its native-exit report are both required",
        ],
        "operatorObservationsRequired": [
            "live content grows before the safe boundary while durable writes are blocked",
            "the real failure banner remains after retry while locked; continue is unavailable",
            "release alone does not resume execution; retry-save enables explicit continue, then the tool and answer complete",
        ],
        "inspectionBoundary": {
            "driver": "official Flutter Driver widget tree, controls and screenshots only",
            "storageRecoverySnapshotAvailable": false,
            "notDirectlyAsserted": "faultGeneration, acceptedSequence, durableSequence and typed pre-execution status are not exported by the inspection Driver; do not restore requestData or claim these were observed",
        },
        "retryResumeContract": {
            "buttons": [
                "history-retry-<threadId>: retry the durable save for the fault generation",
                "history-resume-<threadId>: explicit continue, only enabled when typed canResume is true",
            ],
            "productionState": "controls consume existing Client/AppGraph recovery state; canResume is backend-derived, never inferred from lastError text",
            "generation": "stale-generation fencing is covered by runtime tests, not by a claimed Driver JSON snapshot",
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

/// Bounded inspection of the committed canonical body; invocation text is not execution.
async fn history_content_contains(
    connection: &mut SqliteConnection,
    owner: &str,
    key: &str,
    needle: &str,
) -> Result<bool> {
    let (manifest,): (Vec<u8>,) = sea_orm::sqlx::query_as(
        "SELECT payload FROM conversation_contents WHERE owner_key=?1 AND content_key=?2",
    )
    .bind(owner)
    .bind(key)
    .fetch_one(&mut *connection)
    .await?;
    let manifest: serde_json::Value = serde_json::from_slice(&manifest)?;
    ensure!(
        manifest["sealed"] == true,
        "acceptance original body is not sealed"
    );
    let length = manifest["byteLength"]
        .as_u64()
        .context("body length missing")?;
    let mut offset = 0u64;
    let mut carry = Vec::new();
    let mut found = false;
    while offset < length {
        let (at,data):(i64,Vec<u8>)=sea_orm::sqlx::query_as(
            "SELECT byte_offset,data FROM conversation_content_chunks WHERE owner_key=?1 AND content_key=?2 AND byte_offset>=?3 ORDER BY byte_offset LIMIT 1")
            .bind(owner).bind(key).bind(i64::try_from(offset)?).fetch_one(&mut *connection).await?;
        ensure!(
            u64::try_from(at)? == offset && !data.is_empty(),
            "canonical body has a gap"
        );
        offset += data.len() as u64;
        carry.extend_from_slice(&data);
        found |= carry
            .windows(needle.len())
            .any(|window| window == needle.as_bytes());
        let retained = needle.len().saturating_sub(1).min(carry.len());
        carry.drain(..carry.len() - retained);
    }
    ensure!(offset == length, "canonical body exceeds manifest");
    Ok(found)
}

fn history_fault_originals(database: &Path) -> Result<HistoryFaultOriginals> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(async {
        use pl_protocol::{
            ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatContentRole, ChatTerminalOutcome,
            ContentOwner, ContentTarget, ThreadTextChannel,
        };
        let options = SqliteConnectOptions::new()
            .filename(database)
            .read_only(true)
            .create_if_missing(false);
        let mut connection = SqliteConnection::connect_with(&options).await?;
        let (thread_id,): (String,) =
            sea_orm::sqlx::query_as("SELECT thread_id FROM history_meta WHERE id=1")
                .fetch_one(&mut connection)
                .await?;
        let rows: Vec<(String, Vec<u8>)> =
            sea_orm::sqlx::query_as("SELECT item_id,metadata FROM conversation_items ORDER BY seq")
                .fetch_all(&mut connection)
                .await?;
        let mut originals = HistoryFaultOriginals::default();
        for (record_id, metadata) in rows {
            let atom: ChatAtom =
                serde_json::from_slice(&metadata).context("decode committed canonical header")?;
            if !matches!(
                atom.lifecycle,
                ChatAtomLifecycle::Terminal {
                    outcome: ChatTerminalOutcome::Completed,
                    ..
                }
            ) {
                continue;
            }
            let (needle, role, is_answer) = if atom.kind == ChatAtomKind::Text
                && atom.text_channel == Some(ThreadTextChannel::Final)
            {
                (
                    pl_provider_fixture::GUI_HISTORY_FAULT_ANSWER,
                    ChatContentRole::Body,
                    true,
                )
            } else if atom.tool.as_ref().is_some_and(|tool| {
                tool.call_id == pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_CALL_ID
            }) {
                (
                    pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_MARKER,
                    ChatContentRole::ToolOutput,
                    false,
                )
            } else {
                continue;
            };
            let mut present = false;
            for content in atom.contents.iter().filter(|content| content.role == role) {
                let ContentTarget::Body {
                    owner: ContentOwner::Item { item_id },
                    key,
                } = &content.reference.target
                else {
                    anyhow::bail!("canonical body has wrong owner");
                };
                ensure!(
                    item_id == &record_id,
                    "canonical body points to another original"
                );
                present |= history_content_contains(
                    &mut connection,
                    &format!("4:item{item_id}"),
                    key,
                    needle,
                )
                .await?;
            }
            if present {
                let identity = HistoryFaultItemIdentity {
                    item_id: record_id,
                    thread_id: thread_id.clone(),
                    turn_id: atom
                        .turn_id
                        .context("canonical original has no real Turn")?,
                    tool_call_id: atom.tool.map(|tool| tool.call_id),
                };
                if is_answer {
                    originals.answers.push(identity);
                } else {
                    originals.tools.push(identity);
                }
            }
        }
        connection.close().await?;
        Ok(originals)
    })
}

/// Counts canonical original bodies containing the exact fixture marker.
fn history_payload_count(database: &Path, needle: &str) -> Result<i64> {
    ensure!(!needle.is_empty(), "empty history marker");
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(async {
        let options=SqliteConnectOptions::new().filename(database).read_only(true);
        let mut connection=SqliteConnection::connect_with(&options).await?;
        let rows:Vec<(String,String,String)>=sea_orm::sqlx::query_as(
            "SELECT i.item_id,c.owner_key,c.content_key FROM conversation_items i JOIN conversation_contents c ON c.owner_key='4:item'||i.item_id ORDER BY i.seq,c.content_key")
            .fetch_all(&mut connection).await?;
        let mut found=std::collections::BTreeSet::new();
        for (item,owner,key) in rows {
            if history_content_contains(&mut connection,&owner,&key,needle).await? { found.insert(item); }
        }
        connection.close().await?;
        Ok(i64::try_from(found.len())?)
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

fn start_history_fault_gui(
    workspace: &Path,
    home: &Path,
    log_path: &Path,
    native_exit_path: &Path,
    inspect: bool,
) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new("cargo");
    command
        .current_dir(workspace)
        .args([
            "xtask",
            "run-gui",
            "--capture",
            "--native-launch",
            "--native-exit-report",
        ])
        .arg(native_exit_path)
        .env("ANYWORK_HOME", home)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    // Inspection explicitly selects debug; default observations remain Profile.
    command.arg(if inspect { "--inspect" } else { "--profile" });
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
mod history_fault_tests {
    use super::*;
    use pl_protocol::{
        ChatAtom, ChatAtomContent, ChatAtomKind, ChatAtomLifecycle, ChatContentRole,
        ChatDeliveryKind, ChatSourceId, ChatTerminalOutcome, ChatToolIdentity, ContentOwner,
        ContentRef, ContentTarget, ThreadTextChannel,
    };
    fn answer(id: &str, channel: ThreadTextChannel) -> (String, ChatAtom, String, String) {
        fixture(
            id,
            "fault-turn",
            ChatAtomKind::Text,
            Some(channel),
            None,
            "body",
            pl_provider_fixture::GUI_HISTORY_FAULT_ANSWER,
        )
    }
    fn tool(id: &str, turn: &str, result: &str) -> (String, ChatAtom, String, String) {
        fixture(
            id,
            turn,
            ChatAtomKind::ToolCall,
            None,
            Some(ChatToolIdentity {
                call_id: pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_CALL_ID.into(),
                name: "exec".into(),
            }),
            "tool.result",
            result,
        )
    }
    fn fixture(
        id: &str,
        turn: &str,
        kind: ChatAtomKind,
        channel: Option<ThreadTextChannel>,
        tool: Option<ChatToolIdentity>,
        key: &str,
        body: &str,
    ) -> (String, ChatAtom, String, String) {
        (
            id.into(),
            ChatAtom {
                id: id.into(),
                completion_item_id: Some(id.into()),
                completion_seq: Some(1),
                source: ChatSourceId::ForegroundTurn {
                    turn_id: turn.into(),
                },
                source_state: None,
                source_order: None,
                kind,
                delivery: ChatDeliveryKind::Foreground,
                lifecycle: ChatAtomLifecycle::Terminal {
                    started: None,
                    ended: None,
                    outcome: ChatTerminalOutcome::Completed,
                },
                turn_id: Some(turn.into()),
                attempt_id: None,
                tool,
                wait: None,
                text_channel: channel,
                started_at: None,
                finished_at: None,
                content_present: None,
                contents: vec![ChatAtomContent {
                    role: if key == "body" {
                        ChatContentRole::Body
                    } else {
                        ChatContentRole::ToolOutput
                    },
                    reference: ContentRef {
                        database_id: "fixture".into(),
                        target: ContentTarget::Body {
                            owner: ContentOwner::Item { item_id: id.into() },
                            key: key.into(),
                        },
                    },
                }],
                payload: None,
            },
            key.into(),
            body.into(),
        )
    }
    fn write_items(path: &Path, items: &[(String, ChatAtom, String, String)]) -> Result<()> {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()?;
        runtime.block_on(async {
            let options=SqliteConnectOptions::new().filename(path).create_if_missing(true);
            let mut connection=SqliteConnection::connect_with(&options).await?;
            sea_orm::sqlx::raw_sql("CREATE TABLE IF NOT EXISTS history_meta(id INTEGER,thread_id TEXT); DELETE FROM history_meta; INSERT INTO history_meta VALUES(1,'thread');
                CREATE TABLE IF NOT EXISTS conversation_items(seq INTEGER PRIMARY KEY,item_id TEXT,metadata BLOB);
                CREATE TABLE IF NOT EXISTS conversation_contents(owner_key TEXT,content_key TEXT,payload BLOB);
                CREATE TABLE IF NOT EXISTS conversation_content_chunks(owner_key TEXT,content_key TEXT,byte_offset INTEGER,data BLOB);
                DELETE FROM conversation_items; DELETE FROM conversation_contents; DELETE FROM conversation_content_chunks;").execute(&mut connection).await?;
            for (index,(id,atom,key,body)) in items.iter().enumerate() {
                let owner=format!("4:item{id}");
                sea_orm::sqlx::query("INSERT INTO conversation_items VALUES(?1,?2,?3)")
                    .bind(i64::try_from(index+1)?).bind(id).bind(serde_json::to_vec(atom)?).execute(&mut connection).await?;
                sea_orm::sqlx::query("INSERT INTO conversation_contents VALUES(?1,?2,?3)")
                    .bind(&owner).bind(key).bind(serde_json::to_vec(&serde_json::json!({"sealed":true,"byteLength":body.len()}))?).execute(&mut connection).await?;
                sea_orm::sqlx::query("INSERT INTO conversation_content_chunks VALUES(?1,?2,0,?3)")
                    .bind(&owner).bind(key).bind(body.as_bytes()).execute(&mut connection).await?;
            }
            connection.close().await?; Ok(())
        })
    }

    #[test]
    fn history_fault_counts_real_final_and_tool_output_not_user_or_arguments() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let database = temp.path().join("history.sqlite");
        write_items(
            &database,
            &[
                answer("input", ThreadTextChannel::User),
                answer("commentary", ThreadTextChannel::Commentary),
                answer("answer", ThreadTextChannel::Final),
                tool("argument-only", "fault-turn", "ordinary output"),
                tool(
                    "result",
                    "fault-turn",
                    pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_MARKER,
                ),
            ],
        )?;
        let originals = history_fault_originals(&database)?;
        originals.validate()?;
        assert_eq!(originals.answers[0].item_id, "answer");
        assert_eq!(originals.tools[0].item_id, "result");
        assert_eq!(
            originals.tools[0].tool_call_id.as_deref(),
            Some(pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_CALL_ID)
        );
        Ok(())
    }

    #[test]
    fn history_fault_rejects_duplicate_originals_and_cross_turn_results() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let database = temp.path().join("history.sqlite");
        write_items(
            &database,
            &[
                answer("answer", ThreadTextChannel::Final),
                answer("duplicate", ThreadTextChannel::Final),
                tool(
                    "result",
                    "fault-turn",
                    pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_MARKER,
                ),
            ],
        )?;
        assert!(history_fault_originals(&database)?.validate().is_err());
        write_items(
            &database,
            &[
                answer("answer", ThreadTextChannel::Final),
                tool(
                    "result",
                    "different-turn",
                    pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_MARKER,
                ),
            ],
        )?;
        assert!(history_fault_originals(&database)?.validate().is_err());
        Ok(())
    }

    #[test]
    fn history_fault_execution_receipts_preserve_real_counts_and_reject_garbage() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp
            .path()
            .join(pl_provider_fixture::GUI_HISTORY_FAULT_EXECUTIONS_FILE);
        assert_eq!(history_fault_execution_count(temp.path())?, 0);
        let marker = pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_MARKER;
        fs::write(&path, format!("{marker}\r\n"))?;
        assert_eq!(history_fault_execution_count(temp.path())?, 1);
        fs::write(&path, format!("{marker}\n{marker}\n"))?;
        assert_eq!(history_fault_execution_count(temp.path())?, 2);
        fs::write(&path, "not the tool receipt\n")?;
        assert!(history_fault_execution_count(temp.path()).is_err());
        Ok(())
    }

    #[test]
    fn history_fault_fixture_stage_ignores_optional_titles_and_rejects_missing_evidence()
    -> Result<()> {
        let script = pl_provider_fixture::gui_history_fault_script();
        let mut status = pl_provider_fixture::FixtureLiveStatus {
            accepted: 0,
            rejected: 0,
            total: 0,
            consumed_steps: 0,
            expected_steps: script.len(),
            remaining_optional: false,
        };
        assert_eq!(history_fault_required_consumed(status)?, 0);
        let mut required = 0;
        for step in &script {
            status.consumed_steps += 1;
            status.accepted += 1;
            status.total += 1;
            if !step.optional {
                required += 1;
            }
            assert_eq!(history_fault_required_consumed(status)?, required);
        }
        assert_eq!(required, pl_provider_fixture::HISTORY_FAULT_REQUIRED_STEPS);
        status.rejected = 1;
        assert!(history_fault_required_consumed(status).is_err());
        status.rejected = 0;
        status.consumed_steps += 1;
        assert!(history_fault_required_consumed(status).is_err());
        status.consumed_steps = 0;
        status.expected_steps = 0;
        assert!(history_fault_required_consumed(status).is_err());
        Ok(())
    }
}

#[cfg(target_os = "linux")]
#[cfg(test)]
mod manual_cleanup_tests {
    //! Exercise the real supervisor in a separate test process: its exclusive
    //! child ownership and signal handler cannot be shared with the test runner.

    use super::{OwnedProcess, finish_manual_gui_session};
    use anyhow::{Context, Result, ensure};
    use pl_dev_support::process;
    use std::fs;
    use std::io::Write;
    use std::os::unix::process::ExitStatusExt;
    use std::path::Path;
    use std::process::{Command, Stdio};
    use std::thread;
    use std::time::{Duration, Instant};

    const READY: &str = "ANYWORK_ACCEPTANCE_CLEANUP_TEST_READY";
    const REPORT: &str = "ANYWORK_ACCEPTANCE_CLEANUP_TEST_REPORT";
    const PREPARATION: &str = "ANYWORK_ACCEPTANCE_CLEANUP_TEST_PREPARATION";

    /// Invoked only by the test below, with the actual production tree supervisor.
    #[test]
    fn native_launcher_fixture() -> Result<()> {
        let Some(ready) = std::env::var_os(READY) else {
            return Ok(());
        };
        let report = std::env::var_os(REPORT).context("fixture report path")?;
        if let Ok(mode) = std::env::var(PREPARATION) {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()?;
            return runtime.block_on(async {
                let mut term =
                    tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
                let script = if mode == "fail" {
                    "printf '%s' \"$$\" > \"$ANYWORK_ACCEPTANCE_CLEANUP_TEST_READY\"; exit 7"
                } else {
                    "printf '%s' \"$$\" > \"$ANYWORK_ACCEPTANCE_CLEANUP_TEST_READY\"; exec sleep 60"
                };
                let mut build = tokio::process::Command::new("sh")
                    .args(["-c", script])
                    .env(READY, &ready)
                    .kill_on_drop(true)
                    .spawn()?;
                if mode == "fail" {
                    let status = build.wait().await?;
                    ensure!(status.success(), "preparation worker failed: {status}");
                } else {
                    // This fixture publishes its late boundary on cancellation.
                    // The group signal also ends the worker: racing those two
                    // observations with select would randomly skip publication.
                    term.recv().await.context("termination stream ended")?;
                    build.wait().await?;
                    if mode == "boundary-on-cancel" {
                        print!("{}", super::NATIVE_LAUNCH_BOUNDARY);
                        std::io::stdout().flush()?;
                    }
                }
                Ok(())
            });
        }
        print!("{}", super::NATIVE_LAUNCH_BOUNDARY);
        std::io::stdout().flush()?;
        let mut app = Command::new("sh");
        app.args(["-c", "trap '' TERM; printf '%s' \"$$\" > \"$ANYWORK_ACCEPTANCE_CLEANUP_TEST_READY\"; exec sleep 60"]);
        app.env(READY, ready);
        let exit = process::run_resident_reporting(&mut app, "acceptance independent app group")?;
        // Evidence flushing may outlive OwnedProcess::Drop's old 200 ms window.
        // The owner must remain alive until reporting is complete, not be killed
        // as soon as its app has gone.
        thread::sleep(Duration::from_millis(400));
        fs::write(
            report,
            serde_json::to_vec(&serde_json::json!({
                "schema": "anywork-native-exit/1",
                "pid": exit.pid,
                "exitCode": exit.status.code(),
                "signal": exit.status.signal(),
                "cancelled": exit.cancelled,
                "descendantsAtRootExit": exit.descendants_at_root_exit,
                "reclaimedDescendants": exit.reclaimed_descendants,
            }))?,
        )?;
        Ok(())
    }

    fn launcher_command(ready: &Path, report: &Path, outer_wrapper: bool) -> Result<Command> {
        let executable = std::env::current_exe()?;
        let mut command = if outer_wrapper {
            let mut command = Command::new("sh");
            // Like cargo run, the outer process is not the native supervisor.
            // Its TERM exit must not end the acceptance owner's cleanup wait.
            command
                .args([
                    "-c",
                    "trap 'exit 143' TERM; \"$@\" & wait",
                    "outer-launcher",
                ])
                .arg(&executable);
            command
        } else {
            Command::new(&executable)
        };
        command
            .args([
                "--exact",
                "manual_gui::manual_cleanup_tests::native_launcher_fixture",
                "--nocapture",
            ])
            .env(READY, ready)
            .env(REPORT, report)
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        Ok(command)
    }

    fn start_launcher(ready: &Path, report: &Path, outer_wrapper: bool) -> Result<OwnedProcess> {
        OwnedProcess::start(&mut launcher_command(ready, report, outer_wrapper)?, false)
    }

    #[test]
    fn preparation_cleanup_uses_the_final_phase_and_joins_build_children() -> Result<()> {
        for mode in ["fail", "hold", "boundary-on-cancel", "native"] {
            let directory = tempfile::tempdir()?;
            let ready = directory.path().join("worker-pid");
            let report = directory.path().join("native-exit.json");
            let log = directory.path().join("gui.log");
            let mut command = launcher_command(&ready, &report, false)?;
            let log_file = fs::File::create(&log)?;
            command.stdout(log_file.try_clone()?).stderr(log_file);
            if mode != "native" {
                command.env(PREPARATION, mode);
            }
            let mut launcher = OwnedProcess::start(&mut command, false)?;
            let (tx, rx) = std::sync::mpsc::channel();
            let worker = if mode == "fail" {
                // This coordinator fixture has no production account/GUI services.
                // Preserve the original failed preparation process status.
                let deadline = Instant::now() + Duration::from_secs(5);
                while launcher.exit_status()?.is_none() {
                    ensure!(
                        Instant::now() < deadline,
                        "preparation failure did not exit"
                    );
                    thread::sleep(Duration::from_millis(20));
                }
                fs::read_to_string(&ready)?.parse::<u32>()?
            } else {
                wait_app(&ready, &mut launcher)?
            };
            let mut account =
                OwnedProcess::start(Command::new("sh").args(["-c", "exec sleep 60"]), true)?;
            tx.send(())?;
            let session = super::wait_for_vm_in_phase(
                &log,
                &mut launcher,
                &mut account,
                &rx,
                super::VmStartupPhase::NativePreparation,
                Duration::from_millis(20),
            );
            assert!(session.is_err());
            let result = finish_manual_gui_session(
                session.map(|_| ()),
                &mut launcher,
                Some(&report),
                if mode == "boundary-on-cancel" {
                    Duration::from_millis(250)
                } else {
                    Duration::from_secs(10)
                },
                Some(&log),
            );
            let error = format!("{:#}", result.unwrap_err());
            let started = super::native_launch_started(&fs::read_to_string(&log)?);
            println!(
                "phase_case={mode} crossed_boundary={started} stopped={} report_present={}",
                launcher.stopped,
                report.is_file()
            );
            assert!(
                !Path::new(&format!("/proc/{worker}")).exists(),
                "worker was not reaped"
            );
            if mode == "boundary-on-cancel" {
                assert!(started);
                assert!(
                    !launcher.stopped,
                    "missing post-boundary report must keep fallback armed"
                );
                assert!(error.contains("cleanup timed out"), "{error}");
                assert!(error.contains("manual GUI cancelled"), "{error}");
            } else {
                assert!(launcher.stopped);
                assert!(!error.contains("cleanup also failed"), "{error}");
                assert_eq!(started, mode == "native");
                assert_eq!(report.is_file(), mode == "native");
                assert!(
                    error.contains(if mode == "fail" {
                        "GUI exited"
                    } else {
                        "manual GUI cancelled"
                    }),
                    "{error}"
                );
            }
        }
        Ok(())
    }

    fn wait_app(ready: &Path, launcher: &mut OwnedProcess) -> Result<u32> {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            if let Ok(pid) = fs::read_to_string(ready)
                && let Ok(pid) = pid.parse::<u32>()
            {
                return Ok(pid);
            }
            ensure!(
                !launcher.exited()?,
                "fixture launcher exited before app started"
            );
            ensure!(Instant::now() < deadline, "fixture app did not start");
            thread::sleep(Duration::from_millis(20));
        }
    }

    fn exit_outer_wrapper(launcher: &mut OwnedProcess) -> Result<()> {
        ensure!(
            Command::new("kill")
                .args(["-TERM", &launcher.child.id().to_string()])
                .status()?
                .success(),
            "could not exit only the outer wrapper"
        );
        launcher.child.wait()?;
        ensure!(
            launcher.exit_status()?.is_some(),
            "outer wrapper was not reaped"
        );
        Ok(())
    }

    /// Safety cleanup runs after recording the tested outcome. Even a regression
    /// must not leave this real independent app group running.
    fn finish_fixture(launcher: &mut OwnedProcess, report: &Path) -> Result<()> {
        if !report.is_file() {
            launcher.request_stop();
        }
        launcher.wait_exit(Duration::from_secs(10))?;
        let deadline = Instant::now() + Duration::from_secs(10);
        while !report.is_file() {
            ensure!(Instant::now() < deadline, "fixture cleanup report missing");
            thread::sleep(Duration::from_millis(20));
        }
        Ok(())
    }

    #[test]
    fn preexited_wrapper_still_stops_and_joins_the_live_native_owner() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let ready = directory.path().join("app-pid");
        let report = directory.path().join("native-exit.json");
        let mut launcher = start_launcher(&ready, &report, true)?;
        let app_pid = wait_app(&ready, &mut launcher)?;
        exit_outer_wrapper(&mut launcher)?;
        let app_path = format!("/proc/{app_pid}");
        let app_alive_before = Path::new(&app_path).exists();
        let report_before = report.is_file();
        let result = finish_manual_gui_session(
            Err(anyhow::anyhow!("GUI exited before manual review completed")),
            &mut launcher,
            Some(&report),
            Duration::from_secs(10),
            None,
        );
        let error = format!("{:#}", result.unwrap_err());
        let stopped_after = launcher.stopped;
        let app_alive_after = Path::new(&app_path).exists();
        let report_after = report.is_file();
        println!(
            "wrapper_preexited=true app_alive_before={app_alive_before} report_before={report_before} stopped_after={stopped_after} app_alive_after={app_alive_after} report_after={report_after}"
        );
        finish_fixture(&mut launcher, &report)?;
        assert!(app_alive_before && !report_before);
        assert!(
            error.contains("GUI exited before manual review completed"),
            "{error}"
        );
        assert!(!error.contains("cleanup also failed"), "{error}");
        assert!(stopped_after && report_after && !app_alive_after);
        let evidence: serde_json::Value = serde_json::from_slice(&fs::read(&report)?)?;
        assert_eq!(evidence["cancelled"], true);
        assert!(!Path::new(&app_path).exists());
        Ok(())
    }

    #[test]
    fn failed_sessions_wait_for_independent_app_group_and_launcher_report() -> Result<()> {
        for (reason, outer_wrapper) in [
            ("manual GUI input closed before done", false),
            ("manual GUI cancelled", false),
            ("account fixture exited during manual review", false),
            ("manual GUI input closed before done", true),
        ] {
            let directory = tempfile::tempdir()?;
            let ready = directory.path().join("app-pid");
            let report = directory.path().join("native-exit.json");
            let mut launcher = start_launcher(&ready, &report, outer_wrapper)?;
            let app_pid = match wait_app(&ready, &mut launcher) {
                Ok(pid) => pid,
                Err(error) => {
                    return finish_manual_gui_session(
                        Err(error),
                        &mut launcher,
                        Some(&report),
                        Duration::from_secs(10),
                        None,
                    );
                }
            };
            // ProcessTree::start makes the native app a distinct process-group
            // leader, outside OwnedProcess's launcher group.
            let group_observation = (|| -> Result<u32> {
                let stat = fs::read_to_string(format!("/proc/{app_pid}/stat"))?;
                let (_, fields) = stat.rsplit_once(')').context("app process stat")?;
                Ok(fields
                    .split_whitespace()
                    .nth(2)
                    .context("app process group")?
                    .parse()?)
            })();

            let result = finish_manual_gui_session(
                Err(anyhow::anyhow!("{reason}")),
                &mut launcher,
                Some(&report),
                Duration::from_secs(10),
                None,
            );
            let error = format!("{:#}", result.unwrap_err());
            assert_eq!(group_observation?, app_pid);
            assert_ne!(app_pid, launcher.child.id());
            assert!(error.contains(reason), "{error}");
            assert!(!error.contains("cleanup also failed"), "{error}");
            assert!(
                launcher.stopped,
                "launcher must be reaped before owner release"
            );
            let evidence: serde_json::Value = serde_json::from_slice(&fs::read(&report)?)?;
            assert_eq!(evidence["pid"], app_pid);
            assert_eq!(evidence["cancelled"], true);
            assert_eq!(evidence["signal"], 9);
            assert!(
                !Path::new(&format!("/proc/{app_pid}")).exists(),
                "app was not reaped"
            );
            assert!(!directory.path().join("shutdown-stage.txt").exists());
            if outer_wrapper {
                println!(
                    "wrapper_exits_on_group_stop=true stopped_after={} report_after={} app_alive_after={}",
                    launcher.stopped,
                    report.is_file(),
                    Path::new(&format!("/proc/{app_pid}")).exists()
                );
            }
        }
        Ok(())
    }

    #[test]
    fn cleanup_timeout_preserves_original_failure_and_does_not_claim_reclamation() -> Result<()> {
        for preexited in [false, true] {
            let directory = tempfile::tempdir()?;
            let ready = directory.path().join("app-pid");
            let report = directory.path().join("native-exit.json");
            let mut launcher = start_launcher(&ready, &report, preexited)?;
            let ready_result = wait_app(&ready, &mut launcher);
            if preexited {
                exit_outer_wrapper(&mut launcher)?;
            }
            let result = finish_manual_gui_session(
                Err(anyhow::anyhow!("original input failure")),
                &mut launcher,
                Some(&report),
                Duration::ZERO,
                None,
            );
            let fallback_armed = !launcher.stopped;
            let app_alive = ready_result
                .as_ref()
                .is_ok_and(|pid| Path::new(&format!("/proc/{pid}")).exists());
            println!(
                "timeout=true wrapper_preexited={preexited} fallback_armed={fallback_armed} report_after={} app_alive_after={app_alive}",
                report.is_file()
            );
            // Record state before safety cleanup, which must not hide premature disarming.
            finish_fixture(&mut launcher, &report)?;
            let app_pid = ready_result?;
            assert!(!Path::new(&format!("/proc/{app_pid}")).exists());
            let error = format!("{:#}", result.unwrap_err());
            assert!(error.contains("original input failure"), "{error}");
            assert!(error.contains("cleanup timed out"), "{error}");
            assert!(
                error.contains("subtree reclamation is unconfirmed"),
                "{error}"
            );
            assert!(report.is_file());
            assert!(
                fallback_armed,
                "outer reap must not disarm whole-owner fallback"
            );
        }
        Ok(())
    }
}

#[cfg(test)]
mod manual_startup_tests {
    use super::{NATIVE_LAUNCH_BOUNDARY, VmStartupBudget, VmStartupPhase, native_launch_started};
    use std::time::{Duration, Instant};

    #[test]
    fn preparation_does_not_spend_or_reset_the_vm_budget() {
        let start = Instant::now();
        let timeout = Duration::from_millis(20);
        let prepared = start + Duration::from_secs(6000);
        let mut budget = VmStartupBudget::new(VmStartupPhase::NativePreparation, timeout, start);
        budget.observe("startup_stage=build_bridge elapsed_ms=6000000\n", prepared);
        assert_eq!(budget.deadline, None);
        assert!(!native_launch_started(NATIVE_LAUNCH_BOUNDARY.trim_end()));
        assert!(!native_launch_started(&format!(
            "compiler: {NATIVE_LAUNCH_BOUNDARY}"
        )));
        budget.observe(NATIVE_LAUNCH_BOUNDARY, prepared);
        assert_eq!(budget.deadline, Some(prepared + timeout));
        let expired = prepared + timeout + Duration::from_millis(1);
        budget.observe(NATIVE_LAUNCH_BOUNDARY, expired);
        budget.observe("additional startup output\n", expired);
        assert!(budget.deadline.unwrap() < expired);
        // Existing resident/specialized callers keep their spawn-relative budget.
        let immediate = VmStartupBudget::new(VmStartupPhase::Immediate, timeout, start);
        assert_eq!(immediate.deadline, Some(start + timeout));
    }

    #[cfg(unix)]
    #[test]
    fn waiter_allows_preparation_longer_than_its_short_vm_window() -> anyhow::Result<()> {
        use super::{OwnedProcess, wait_for_vm_in_phase};
        use std::{fs, process::Command, sync::mpsc, thread};

        let directory = tempfile::tempdir()?;
        let path = directory.path().join("gui.log");
        fs::write(&path, "building native inputs\n")?;
        let writer_path = path.clone();
        let writer = thread::spawn(move || -> std::io::Result<()> {
            thread::sleep(Duration::from_millis(650));
            fs::write(
                writer_path,
                format!(
                    "{NATIVE_LAUNCH_BOUNDARY}The Dart VM service is listening on http://127.0.0.1:1234/synthetic/\n"
                ),
            )
        });
        let mut gui = OwnedProcess::start(Command::new("sh").args(["-c", "exec sleep 60"]), false)?;
        let mut fixture =
            OwnedProcess::start(Command::new("sh").args(["-c", "exec sleep 60"]), true)?;
        let (tx, rx) = mpsc::channel();
        let result = wait_for_vm_in_phase(
            &path,
            &mut gui,
            &mut fixture,
            &rx,
            VmStartupPhase::NativePreparation,
            Duration::from_millis(100),
        );
        writer.join().unwrap()?;
        assert_eq!(result?, "http://127.0.0.1:1234/synthetic/");
        fs::write(
            &path,
            format!("{NATIVE_LAUNCH_BOUNDARY}{NATIVE_LAUNCH_BOUNDARY}ordinary startup output\n"),
        )?;
        let error = wait_for_vm_in_phase(
            &path,
            &mut gui,
            &mut fixture,
            &rx,
            VmStartupPhase::NativePreparation,
            Duration::from_millis(20),
        )
        .unwrap_err();
        assert!(
            error.to_string().contains("VM service startup timed out"),
            "{error:#}"
        );
        tx.send(())?;
        let cancelled = wait_for_vm_in_phase(
            &path,
            &mut gui,
            &mut fixture,
            &rx,
            VmStartupPhase::NativePreparation,
            Duration::ZERO,
        )
        .unwrap_err();
        assert!(
            cancelled.to_string().contains("manual GUI cancelled"),
            "{cancelled:#}"
        );
        Ok(())
    }
}

#[cfg(all(test, windows))]
mod windows_cleanup_tests {
    //! Windows kernel scopes with the actual manual-session cleanup coordinator.
    use super::*;

    const FIXTURE: &str = "manual_gui::windows_cleanup_tests::preparation_fixture";

    #[test]
    fn preparation_fixture() -> Result<()> {
        let Some(directory) = env::var_os("PL_PREPARATION_FIXTURE") else {
            return Ok(());
        };
        let directory = PathBuf::from(directory);
        let mode = env::var("PL_PREPARATION_MODE")?;
        if mode == "worker" || mode == "cancel" {
            fs::write(directory.join("ready"), "ready")?;
            let deadline = Instant::now() + Duration::from_secs(20);
            while Instant::now() < deadline {
                thread::sleep(Duration::from_millis(10));
            }
            bail!("fixture was not reclaimed");
        }
        if mode == "orphan" {
            let _child = Command::new(env::current_exe()?)
                .args(["--exact", FIXTURE, "--nocapture"])
                .env("PL_PREPARATION_MODE", "worker")
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()?;
        } else {
            // Model a launcher which crosses the boundary just before exiting.
            fs::write(directory.join("gui.log"), NATIVE_LAUNCH_BOUNDARY)?;
            fs::write(directory.join("ready"), "ready")?;
        }
        Ok(())
    }

    #[test]
    fn preparation_cleanup_retains_first_error_and_native_report_barrier() -> Result<()> {
        for mode in ["orphan", "cancel", "native-missing"] {
            let directory = tempfile::tempdir()?;
            let log = directory.path().join("gui.log");
            let report = directory.path().join("native-exit.json");
            fs::write(&log, "preparing\n")?;
            let mut command = Command::new(env::current_exe()?);
            command
                .args(["--exact", FIXTURE, "--nocapture"])
                .env("PL_PREPARATION_FIXTURE", directory.path())
                .env("PL_PREPARATION_MODE", mode)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null());
            let mut gui = OwnedProcess::start(&mut command, false)?;
            let deadline = Instant::now() + Duration::from_secs(10);
            while !directory.path().join("ready").exists()
                || (mode != "cancel" && gui.exit_status()?.is_none())
            {
                ensure!(
                    Instant::now() < deadline,
                    "fixture readiness timed out: {mode}"
                );
                thread::sleep(Duration::from_millis(10));
            }
            if mode == "orphan" {
                assert!(!gui.tree_exited()?);
            }
            let result = finish_manual_gui_session(
                Err(anyhow::anyhow!("original startup failure")),
                &mut gui,
                Some(&report),
                Duration::from_secs(1),
                Some(&log),
            );
            let error = format!("{:#}", result.unwrap_err());
            assert!(error.contains("original startup failure"), "{error}");
            if mode == "native-missing" {
                assert!(!gui.stopped);
                assert!(error.contains("cleanup timed out"), "{error}");
            } else {
                assert!(gui.stopped, "{mode}: {error}");
                assert!(gui.tree_exited()?);
                assert!(!error.contains("cleanup timed out"), "{error}");
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod desktop_test_command_tests {
    use super::desktop_test_command_with_handoff;
    use std::collections::BTreeMap;
    use std::ffi::OsStr;
    use std::path::Path;

    #[test]
    fn paired_handoff_runs_the_parent_xtask_directly() -> anyhow::Result<()> {
        let workspace = Path::new("workspace with spaces");
        let preparation = OsStr::new("prepared inputs");
        let xtask = OsStr::new("parent executable");
        let mut command =
            desktop_test_command_with_handoff(workspace, Some(preparation), Some(xtask))?;
        command.args(["--suite", "desktop", "--case", "wait_events"]);

        assert_eq!(command.get_program(), xtask);
        assert_eq!(command.get_current_dir(), Some(workspace));
        assert_eq!(
            command.get_args().collect::<Vec<_>>(),
            [
                "test-project",
                "--suite",
                "desktop",
                "--case",
                "wait_events"
            ]
            .map(OsStr::new)
        );
        let environment = command.get_envs().collect::<BTreeMap<_, _>>();
        assert_eq!(
            environment.get(OsStr::new("ANYWORK_DESKTOP_TEST_PREPARATION")),
            Some(&Some(preparation))
        );
        assert_eq!(
            environment.get(OsStr::new("ANYWORK_DESKTOP_TEST_XTASK")),
            Some(&Some(xtask))
        );
        Ok(())
    }

    #[test]
    fn standalone_desktop_test_uses_the_normal_cargo_entrypoint() -> anyhow::Result<()> {
        let workspace = Path::new("workspace");
        let command = desktop_test_command_with_handoff(workspace, None, None)?;
        assert_eq!(command.get_program(), OsStr::new("cargo"));
        assert_eq!(command.get_current_dir(), Some(workspace));
        assert_eq!(
            command.get_args().collect::<Vec<_>>(),
            [OsStr::new("xtask"), OsStr::new("test-project")]
        );
        Ok(())
    }

    #[test]
    fn incomplete_or_empty_handoff_is_rejected_without_falling_back() {
        let preparation = Some(OsStr::new("prepared inputs"));
        let xtask = Some(OsStr::new("parent executable"));
        let empty = Some(OsStr::new(""));
        for (preparation, xtask) in [
            (preparation, None),
            (None, xtask),
            (empty, None),
            (None, empty),
            (preparation, empty),
            (empty, xtask),
            (empty, empty),
        ] {
            assert!(
                desktop_test_command_with_handoff(Path::new("workspace"), preparation, xtask)
                    .is_err(),
                "invalid desktop handoff: preparation={preparation:?}, xtask={xtask:?}"
            );
        }
    }
}

#[cfg(test)]
mod scenario_cli_tests {
    use super::{ManualGuiOptions, validate_inspect_options, validate_realtime_focus};
    use clap::Parser;

    #[test]
    fn keeps_presentation_scenarios_without_restoring_removed_acp_journey() {
        for scenario in [
            "gui",
            "timeline-history",
            "question-history",
            "realtime-presentation",
            "timeline-concept",
            "timeline-boundary",
            "sidebar-query",
            "thread-lsp-status",
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

    #[test]
    fn inspect_uses_explicit_supported_presets_without_bots_fixture() {
        for args in [
            vec!["acceptance", "--preset", "gui", "--inspect"],
            vec!["acceptance", "--preset", "plan-recovery", "--inspect"],
            vec!["acceptance", "--preset", "history-fault", "--inspect"],
        ] {
            let options = ManualGuiOptions::try_parse_from(args).expect("valid inspect args");
            validate_inspect_options(&options).expect("inspect is allowed for this preset");
        }
        for args in [
            vec![
                "acceptance",
                "--preset",
                "gui",
                "--inspect",
                "--bots-fixture",
            ],
            vec![
                "acceptance",
                "--preset",
                "plan-recovery",
                "--inspect",
                "--bots-fixture",
            ],
            vec!["acceptance", "--preset", "timeline-history", "--inspect"],
        ] {
            let options = ManualGuiOptions::try_parse_from(args).expect("syntactically valid args");
            assert!(validate_inspect_options(&options).is_err());
        }
    }

    #[test]
    fn realtime_focus_rejects_unknown_or_unrelated_presets() {
        let focused = ManualGuiOptions::try_parse_from([
            "acceptance",
            "--preset",
            "realtime-presentation",
            "--realtime-focus",
            "stop-background",
        ])
        .expect("supported focus");
        validate_realtime_focus(&focused).expect("focus belongs to realtime-presentation");
        let full =
            ManualGuiOptions::try_parse_from(["acceptance", "--preset", "realtime-presentation"])
                .expect("complete default journey");
        assert!(full.realtime_focus.is_none());
        validate_realtime_focus(&full).expect("default journey");
        for preset in ["gui", "realtime", "history-fault", "timeline-boundary"] {
            let options = ManualGuiOptions::try_parse_from([
                "acceptance",
                "--preset",
                preset,
                "--realtime-focus",
                "stop-background",
            ])
            .expect("syntactically valid");
            assert!(validate_realtime_focus(&options).is_err());
        }
        assert!(
            ManualGuiOptions::try_parse_from([
                "acceptance",
                "--preset",
                "realtime-presentation",
                "--realtime-focus",
                "unknown",
            ])
            .is_err()
        );
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
mod manual_control_tests {
    use super::{
        ManualGuiOptions, bots_fixture, configure_manual_gui_launch, record_session_line,
        require_native_exit,
    };
    use clap::Parser;
    use std::path::Path;
    use std::process::Command;

    #[test]
    fn gui_launch_uses_one_native_report_without_changing_specialized_modes() {
        let output = Path::new("evidence with spaces");
        for arguments in [
            vec!["manual-gui", "--inspect"],
            vec!["manual-gui", "--inspect", "--seed-home-copy", "closed-home"],
            vec!["manual-gui"],
        ] {
            let options = ManualGuiOptions::try_parse_from(arguments).unwrap();
            let mut command = Command::new("cargo");
            let report = configure_manual_gui_launch(&mut command, &options, output);
            let args: Vec<_> = command.get_args().collect();
            assert_eq!(report, Some(output.join("native-exit.json")));
            assert_eq!(
                args.iter().filter(|arg| **arg == "--native-launch").count(),
                1
            );
            assert_eq!(
                args.iter()
                    .filter(|arg| **arg == "--native-exit-report")
                    .count(),
                1
            );
            assert_eq!(args.last().copied(), report.as_deref().map(Path::as_os_str));
            assert_eq!(
                args.contains(&std::ffi::OsStr::new("--inspect")),
                options.inspect
            );
            assert!(!args.contains(&std::ffi::OsStr::new("--profile")));
        }
        for preset in ["stress", "tool-scroll"] {
            let options =
                ManualGuiOptions::try_parse_from(["manual-gui", "--preset", preset]).unwrap();
            let mut command = Command::new("cargo");
            assert_eq!(
                configure_manual_gui_launch(&mut command, &options, output),
                Some(output.join("native-exit.json"))
            );
            assert_eq!(
                command.get_args().collect::<Vec<_>>(),
                [
                    std::ffi::OsStr::new("--profile"),
                    std::ffi::OsStr::new("--native-launch"),
                    std::ffi::OsStr::new("--native-exit-report"),
                    output.join("native-exit.json").as_os_str(),
                ]
            );
        }
        let options = ManualGuiOptions::try_parse_from(["manual-gui", "--bots-fixture"]).unwrap();
        let mut command = Command::new("dbus-run-session");
        command.arg("--private-command");
        assert_eq!(
            configure_manual_gui_launch(&mut command, &options, output),
            None
        );
        assert_eq!(
            command.get_args().collect::<Vec<_>>(),
            ["--private-command"]
        );
        let rejected =
            ManualGuiOptions::try_parse_from(["manual-gui", "--bots-fixture", "--inspect"])
                .unwrap();
        assert!(super::validate_inspect_options(&rejected).is_err());
    }

    fn clean_native_report() -> serde_json::Value {
        serde_json::json!({
            "schema": "anywork-native-exit/1",
            "pid": 42,
            "exitCode": 0,
            "signal": null,
            "cancelled": false,
            "descendantsAtRootExit": [],
            "reclaimedDescendants": [],
        })
    }

    #[test]
    fn native_report_rejects_missing_failed_cancelled_or_unreclaimed_exit() -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("native-exit.json");
        assert!(require_native_exit(&path, None).is_err());
        std::fs::write(&path, b"not-json")?;
        assert!(require_native_exit(&path, None).is_err());
        for (field, value) in [
            ("schema", serde_json::json!("foreign-schema")),
            ("pid", serde_json::json!(0)),
            ("exitCode", serde_json::json!(1)),
            ("signal", serde_json::json!(9)),
            ("cancelled", serde_json::json!(true)),
            ("descendantsAtRootExit", serde_json::json!([43])),
            ("reclaimedDescendants", serde_json::json!([43])),
        ] {
            let mut report = clean_native_report();
            report[field] = value;
            std::fs::write(&path, serde_json::to_vec(&report)?)?;
            assert!(require_native_exit(&path, None).is_err(), "{field}");
        }
        let mut missing_cleanup = clean_native_report();
        missing_cleanup
            .as_object_mut()
            .unwrap()
            .remove("reclaimedDescendants");
        std::fs::write(&path, serde_json::to_vec(&missing_cleanup)?)?;
        assert!(require_native_exit(&path, None).is_err());
        std::fs::write(&path, serde_json::to_vec(&clean_native_report())?)?;
        require_native_exit(&path, Some(42))?;
        assert!(require_native_exit(&path, Some(43)).is_err());
        Ok(())
    }

    #[test]
    fn retained_tool_scroll_requires_new_shutdown_stage_and_real_exit_report() -> anyhow::Result<()>
    {
        let options = ManualGuiOptions::try_parse_from([
            "manual-gui",
            "--preset",
            "tool-scroll",
            "--retain-environment",
        ])?;
        assert!(options.retain_environment);
        let directory = tempfile::tempdir()?;
        let output = directory.path();
        let mut command = Command::new("cargo");
        let report = configure_manual_gui_launch(&mut command, &options, output).unwrap();
        std::fs::write(&report, serde_json::to_vec(&clean_native_report())?)?;
        std::fs::write(output.join("capture-stage.txt"), "shutdown_completed\n")?;
        assert!(super::require_manual_shutdown(output).is_err());
        std::fs::remove_file(output.join("capture-stage.txt"))?;
        std::fs::write(output.join("shutdown-stage.txt"), "shutdown_completed\n")?;
        super::require_manual_shutdown(output)?;
        let mut failed = clean_native_report();
        failed["reclaimedDescendants"] = serde_json::json!([43]);
        std::fs::write(&report, serde_json::to_vec(&failed)?)?;
        assert!(super::require_manual_shutdown(output).is_err());
        std::fs::remove_file(&report)?;
        assert!(super::require_manual_shutdown(output).is_err());
        assert!(!output.join("screenshot.png").exists());
        Ok(())
    }

    #[cfg(unix)]
    #[test]
    fn shutdown_wait_requires_launcher_report_and_preserves_cancellation() -> anyhow::Result<()> {
        use super::{OwnedProcess, wait_manual_shutdown};
        use std::sync::mpsc;
        use std::time::Duration;

        fn process(script: &str) -> anyhow::Result<OwnedProcess> {
            OwnedProcess::start(Command::new("sh").args(["-c", script]), false)
        }

        let directory = tempfile::tempdir()?;
        let path = directory.path().join("native-exit.json");
        let (tx, rx) = mpsc::channel();
        let mut fixture = process("exec sleep 60")?;
        let timeout = Duration::from_secs(2);
        // A successful launcher cannot substitute for a missing/failed native report.
        for report in [
            None,
            Some(clean_native_report()),
            Some({
                let mut failed = clean_native_report();
                failed["exitCode"] = serde_json::json!(1);
                failed
            }),
        ] {
            if let Some(report) = &report {
                std::fs::write(&path, serde_json::to_vec(report)?)?;
            }
            let mut gui = process("exit 0")?;
            let result = wait_manual_shutdown(&mut gui, &mut fixture, &rx, timeout, Some(&path));
            let clean = report
                .as_ref()
                .is_some_and(|report| report["exitCode"] == 0);
            assert_eq!(result.is_ok(), clean, "{result:?}");
        }
        let mut gui = process("exit 7")?;
        assert!(wait_manual_shutdown(&mut gui, &mut fixture, &rx, timeout, None).is_err());
        let mut gui = process("exec sleep 60")?;
        assert!(
            wait_manual_shutdown(&mut gui, &mut fixture, &rx, Duration::ZERO, None)
                .unwrap_err()
                .to_string()
                .contains("did not exit")
        );
        tx.send(())?;
        assert!(
            wait_manual_shutdown(&mut gui, &mut fixture, &rx, timeout, None)
                .unwrap_err()
                .to_string()
                .contains("cancelled")
        );
        let mut exited_fixture = process("exit 0")?;
        exited_fixture.child.wait()?;
        assert!(
            wait_manual_shutdown(&mut gui, &mut exited_fixture, &rx, timeout, None)
                .unwrap_err()
                .to_string()
                .contains("fixture exited")
        );
        Ok(())
    }

    #[test]
    fn ordinary_stdin_never_becomes_a_synthetic_ui_operation() -> anyhow::Result<()> {
        for line in [
            "open-project",
            "send-prompt private text",
            "other",
            "",
            "unrecognized private text",
            "bots-env registration complete",
        ] {
            assert!(record_session_line(None, line)?.is_none());
        }
        Ok(())
    }

    #[test]
    fn bots_control_accepts_only_fixed_environment_commands() {
        use bots_fixture::EnvLine;

        assert!(matches!(
            bots_fixture::classify_line("bots-env registration pending"),
            EnvLine::Registration(_)
        ));
        assert!(matches!(
            bots_fixture::classify_line("bots-env message unknown-direct"),
            EnvLine::Message(_)
        ));
        assert!(matches!(
            bots_fixture::classify_line("bots-env conversations prepare-pages"),
            EnvLine::Conversations(_)
        ));
        for line in [
            "bots-env registration complete supplied-identity",
            "bots-env message unknown-direct supplied-body",
            "bots-env conversations prepare-pages supplied-url",
            "bots-env unknown",
        ] {
            assert!(matches!(
                bots_fixture::classify_line(line),
                EnvLine::UnknownEnv
            ));
        }
        for line in ["send-prompt", "arbitrary private text", ""] {
            assert!(matches!(
                bots_fixture::classify_line(line),
                EnvLine::NotEnvironment
            ));
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
