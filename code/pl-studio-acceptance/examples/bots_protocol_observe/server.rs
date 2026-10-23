use anyhow::{Context, Result, bail, ensure};
use pl_dev_support::process;
use serde::Deserialize;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::net::SocketAddr;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, ExitStatus, Stdio};
use std::time::{Duration, Instant};

use super::env::ObservePaths;
use super::http::StudioHttp;
use super::report::{ServerBinarySource, ServerIdentity};

const PYTHON: &str = "python3";
/// Receipts are a separate per-instance file, never the server log: a server that
/// prints a receipt-shaped line to its own output cannot be read as the owner.
const RECEIPTS_EXTENSION: &str = "receipts";
const CONTROL_READY_WINDOW: Duration = Duration::from_secs(15);
const STOP_ANSWER_WINDOW: Duration = Duration::from_secs(15);
/// The owner's own bounded stop (graceful + kill + keyring) must finish inside
/// this window; the group kill below is only the backstop.
const LAUNCHER_STOP_WINDOW: Duration = Duration::from_secs(24);
const REAP_BACKSTOP: Duration = Duration::from_secs(5);
/// The terminal receipt is written just before the owner exits.
const TERMINAL_WINDOW: Duration = Duration::from_secs(3);
const POLL: Duration = Duration::from_millis(50);

pub(crate) struct StudioServer {
    child: Child,
    /// The private typed control face of the process owner (its stdin).
    control: Option<ChildStdin>,
    listen: SocketAddr,
    log: PathBuf,
    /// Owner-only receipt channel of this instance (never the server log).
    receipts: PathBuf,
    /// Nonce that binds every receipt to this launch.
    instance: String,
    server_pid: Option<u32>,
    stop_attempts: u32,
    /// Kernel-confirmed SIGINT deliveries for this instance (0 or 1).
    signals_sent: u32,
    /// The kernel/owner reason a stop could not be delivered, if any.
    stop_failure: Option<String>,
    /// The escalation the owner reported, when its graceful window expired.
    escalation: Option<String>,
    /// The child reached a terminal state, so neither its pid nor its managed
    /// group may be signalled again: the pid is available for reuse.
    reaped: bool,
    /// The outcome of this instance's controlled stop, once it concluded.
    outcome: Option<StopOutcome>,
    exit_status: Option<ExitStatus>,
    /// The owner's trusted terminal receipt, kept as evidence.
    owner_exit: Option<String>,
    identity: ServerIdentity,
}

/// How a stop of this instance actually concluded.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum StopOutcome {
    /// The owner confirmed one kernel-level SIGINT delivery and the launcher
    /// exited zero, so the graceful stop was observed end to end.
    Delivered,
    /// The owner had already observed the server's own exit; nothing was signalled.
    AlreadyExited,
}

/// One typed line of the owner-only receipt channel.
///
/// Only the process owner holds this channel, and `deny_unknown_fields` plus a
/// per-instance nonce mean a line the server itself prints to its log, a stale
/// line from an earlier instance, or an invented field is refused rather than
/// silently ignored.
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum Receipt {
    ControlReady {
        instance: String,
        server_pid: u32,
    },
    ControlError {
        instance: String,
        reason: String,
        detail: Option<String>,
    },
    StopDelivered {
        instance: String,
        op: String,
        signal: String,
        pid: u32,
        count: u32,
    },
    StopAlreadyExited {
        instance: String,
        op: String,
    },
    StopFailed {
        instance: String,
        op: String,
        reason: String,
        errno: Option<i32>,
    },
    StopDuplicate {
        instance: String,
        op: String,
    },
    StopEscalated {
        instance: String,
        op: String,
        signal: String,
        pid: u32,
    },
    ControlRejected {
        instance: String,
        length: usize,
    },
    ControlClosed {
        instance: String,
    },
    OwnerExit {
        instance: String,
        server_exit: Option<i32>,
        keyring_exit: Option<i32>,
        readiness_exit: Option<i32>,
        delivered: u32,
        escalated: bool,
        graceful: bool,
        failure: Option<String>,
        cleanup_complete: bool,
        server_reaped: bool,
        keyring_reaped: bool,
        readiness_reaped: bool,
        cleanup_errors: Vec<String>,
    },
}

/// The owner's own account of how the instance ended.
#[derive(Debug, Clone)]
struct OwnerTerminal {
    server_exit: Option<i32>,
    keyring_exit: Option<i32>,
    readiness_exit: Option<i32>,
    delivered: u32,
    escalated: bool,
    graceful: bool,
    failure: Option<String>,
    cleanup_complete: bool,
    server_reaped: bool,
    keyring_reaped: bool,
    readiness_reaped: bool,
    cleanup_errors: Vec<String>,
}

impl OwnerTerminal {
    /// Everything a graceful stop must prove, checked against the receipt itself
    /// instead of trusting a zero launcher status.
    fn require_graceful(&self, delivered: u32) -> Result<()> {
        ensure!(
            self.cleanup_complete,
            "the owner reported an incomplete cleanup: errors={:?}",
            self.cleanup_errors
        );
        ensure!(
            self.server_reaped && self.keyring_reaped && self.readiness_reaped,
            "the owner did not reap every child: server={} keyring={} readiness={}",
            self.server_reaped,
            self.keyring_reaped,
            self.readiness_reaped
        );
        ensure!(
            self.delivered == 1 && self.delivered == delivered,
            "the owner reported {} deliveries, this stop confirmed {delivered}",
            self.delivered
        );
        ensure!(
            !self.escalated,
            "the stop needed an escalation to SIGKILL; that is not a graceful stop"
        );
        ensure!(
            self.failure.is_none(),
            "the owner recorded a failure: {:?}",
            self.failure
        );
        ensure!(
            self.graceful,
            "the owner did not report the stop as graceful"
        );
        ensure!(
            self.server_exit == Some(0),
            "the server did not exit zero, got {:?}",
            self.server_exit
        );
        ensure!(
            self.readiness_exit == Some(0),
            "the readiness probe did not exit zero, got {:?}",
            self.readiness_exit
        );
        ensure!(
            self.keyring_exit.is_some(),
            "the keyring daemon was not really reaped"
        );
        Ok(())
    }

    /// The natural-exit account: nothing was signalled, and the cleanup still has
    /// to be complete for the instance to be considered reclaimed.
    fn require_already_exited(&self) -> Result<()> {
        ensure!(
            self.delivered == 0,
            "the owner reported {} deliveries although nothing was signalled",
            self.delivered
        );
        ensure!(
            !self.escalated,
            "an already-exited instance must not be escalated"
        );
        ensure!(
            self.cleanup_complete,
            "the owner reported an incomplete cleanup: errors={:?}",
            self.cleanup_errors
        );
        ensure!(
            self.server_reaped && self.keyring_reaped && self.readiness_reaped,
            "the owner did not reap every child: server={} keyring={} readiness={}",
            self.server_reaped,
            self.keyring_reaped,
            self.readiness_reaped
        );
        Ok(())
    }

    fn evidence(&self) -> String {
        format!(
            "owner server_exit={:?} keyring_exit={:?} readiness_exit={:?} delivered={} \
             escalated={} graceful={} cleanup_complete={} failure={:?}",
            self.server_exit,
            self.keyring_exit,
            self.readiness_exit,
            self.delivered,
            self.escalated,
            self.graceful,
            self.cleanup_complete,
            self.failure
        )
    }
}

/// The owner's answer to one stop request.
enum StopAnswer {
    Delivered { count: u32 },
    AlreadyExited,
    Failed { reason: String },
}

/// Facts about one real runtime stop and the same-home relaunch that followed.
///
/// These are measurements of the process boundary, not labels: the single
/// interrupt count and the observed launcher exit code are what make a
/// "graceful stop happened here" claim checkable.
pub(crate) struct ServerRestart {
    pub restart_count: u32,
    pub stopped_server_pid: Option<u32>,
    pub stopped_wrapper_pid: u32,
    pub stopped_sigints: u32,
    pub stopped_exit_code: Option<i32>,
    pub stopped_graceful: bool,
    pub started_server_pid: Option<u32>,
    pub started_wrapper_pid: u32,
    pub listen: SocketAddr,
}

impl std::fmt::Display for ServerRestart {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "restart#{}: stopped serverPid={:?} wrapperPid={} sigints={} exitCode={:?} graceful={}; \
             started serverPid={:?} wrapperPid={} listen={}",
            self.restart_count,
            self.stopped_server_pid,
            self.stopped_wrapper_pid,
            self.stopped_sigints,
            self.stopped_exit_code,
            self.stopped_graceful,
            self.started_server_pid,
            self.started_wrapper_pid,
            self.listen
        )
    }
}

/// Everything needed to launch the same isolated server again. A restart keeps
/// the same home, keyring runtime, manifest, and binary while the listen port
/// and the wrapper PID change; the log is appended so both halves survive.
#[derive(Debug, Clone)]
pub(crate) struct ServerLaunch {
    pub workspace: PathBuf,
    pub home: PathBuf,
    pub keyring_runtime: PathBuf,
    pub log: PathBuf,
    pub manifest: PathBuf,
    pub explicit_binary: Option<PathBuf>,
    pub append_log: bool,
}

impl StudioServer {
    pub fn listen(&self) -> SocketAddr {
        self.listen
    }

    pub fn identity(&self) -> &ServerIdentity {
        &self.identity
    }

    /// `(server_pid, wrapper_group_pid)`; the wrapper group PID is the
    /// dbus-run-session child the stop signal actually targets.
    pub fn pids(&self) -> (Option<u32>, u32) {
        (self.server_pid, self.child.id())
    }

    /// How many managed interrupts this instance actually delivered (never > 1).
    ///
    /// This counts kernel-confirmed deliveries reported by the process owner, not
    /// writes to the control face and not attempted signals.
    pub fn signals_sent(&self) -> u32 {
        self.signals_sent
    }

    /// The observed launcher exit code, or `None` when it died from a signal.
    pub fn exit_code(&self) -> Option<i32> {
        self.exit_status.and_then(|status| status.code())
    }

    /// True only when one delivered interrupt ended in an observed zero exit.
    pub fn stopped_gracefully(&self) -> bool {
        self.outcome == Some(StopOutcome::Delivered)
    }

    /// Process-boundary facts that are safe to record in the report.
    pub fn stop_evidence(&self) -> String {
        let mut evidence = format!(
            "sigints={} reaped={} graceful={} outcome={:?} exitCode={:?}",
            self.signals_sent,
            self.reaped,
            self.stopped_gracefully(),
            self.outcome,
            self.exit_code()
        );
        if let Some(escalation) = &self.escalation {
            evidence.push_str("; escalation=");
            evidence.push_str(escalation);
        }
        if let Some(owner) = &self.owner_exit {
            evidence.push_str("; ");
            evidence.push_str(owner);
        }
        evidence
    }

    pub async fn start(
        paths: &ObservePaths,
        manifest: &Path,
        explicit: Option<&Path>,
    ) -> Result<Self> {
        let launch = ServerLaunch {
            workspace: paths.workspace.clone(),
            home: paths.home.clone(),
            keyring_runtime: paths.keyring_runtime.clone(),
            log: paths.server_log.clone(),
            manifest: manifest.to_path_buf(),
            explicit_binary: explicit.map(Path::to_path_buf),
            append_log: false,
        };
        Self::launch(launch).await
    }

    /// Re-launches the server from a captured [`ServerLaunch`]; used by the
    /// same-home restart cases. The previous server must already be stopped.
    pub async fn relaunch(launch: ServerLaunch) -> Result<Self> {
        Self::launch(launch).await
    }

    async fn launch(launch: ServerLaunch) -> Result<Self> {
        // The process owner signals through a pidfd; without that capability the
        // observation stops here instead of degrading to bare-pid signals.
        super::env::python_pidfd_capability()?;
        let (executable, source) = match launch.explicit_binary.as_deref() {
            Some(path) => (
                super::env::canonicalize_executable(path)?,
                ServerBinarySource::ExplicitPrebuilt,
            ),
            None => (
                build_server(&launch.workspace).await?,
                ServerBinarySource::BuiltCurrent,
            ),
        };
        let identity = ServerIdentity {
            source,
            canonical_path: executable.clone(),
            sha256: super::env::file_sha256(&executable)?,
        };
        let listen =
            std::net::SocketAddr::from(([127, 0, 0, 1], super::env::choose_loopback_port()?));
        Self::spawn(&executable, &launch, listen, identity).await
    }

    async fn spawn(
        executable: &Path,
        launch: &ServerLaunch,
        listen: SocketAddr,
        identity: ServerIdentity,
    ) -> Result<Self> {
        let log = if launch.append_log {
            OpenOptions::new()
                .create(true)
                .append(true)
                .open(&launch.log)
                .with_context(|| format!("failed to append {}", launch.log.display()))?
        } else {
            File::create(&launch.log)
                .with_context(|| format!("failed to create {}", launch.log.display()))?
        };
        // Owner receipts get their own per-instance file. The server log stays a
        // server log, so nothing the server prints can be read as an owner fact.
        let receipts = launch.log.with_extension(RECEIPTS_EXTENSION);
        let receipts_file = File::create(&receipts)
            .with_context(|| format!("failed to create {}", receipts.display()))?;
        // Binds every receipt to this launch and to nothing else.
        let instance = format!("{}-{}", std::process::id(), listen.port());
        let mut command = Command::new("dbus-run-session");
        command
            .arg("--")
            .arg(PYTHON)
            // The reviewed owner source is frozen into this binary; the mutable
            // workspace file is never loaded, so what runs is what was built.
            .arg("-c")
            .arg(super::env::OWNER_SOURCE)
            .arg(executable)
            .arg("--listen")
            .arg(listen.to_string())
            .arg("--studio-home")
            .arg(&launch.home)
            .current_dir(&launch.workspace)
            .env("HOME", &launch.home)
            .env("ANYWORK_HOME", &launch.home)
            .env("XDG_DATA_HOME", launch.home.join("xdg-data"))
            .env("XDG_CONFIG_HOME", launch.home.join("xdg-config"))
            .env("XDG_RUNTIME_DIR", &launch.keyring_runtime)
            .env("ANYWORK_BOTS_FIXTURE_MANIFEST", &launch.manifest)
            .env("ANYWORK_ACCEPTANCE_INSTANCE", &instance)
            .env_remove("GNOME_KEYRING_CONTROL")
            .env_remove("DBUS_SESSION_BUS_ADDRESS")
            .env_remove("GNOME_KEYRING_PID")
            // The owner owns this pipe: it is the typed control face, so the server
            // itself gets /dev/null instead of the caller's stdin.
            .stdin(Stdio::piped())
            // fd 1 = owner receipts, fd 2 = ordinary server log. Python passes only
            // fd 2 to its children.
            .stdout(Stdio::from(receipts_file))
            .stderr(Stdio::from(log));
        // Independent process group so SIGINT/KILL cannot hit the observe worker.
        command.process_group(0);
        process::configure_background_command(&mut command);
        let mut child = command
            .spawn()
            .context("failed to start isolated pl-studio-server")?;
        let control = child.stdin.take();
        let mut server = Self {
            child,
            control,
            listen,
            log: launch.log.clone(),
            receipts,
            instance,
            server_pid: None,
            stop_attempts: 0,
            signals_sent: 0,
            stop_failure: None,
            escalation: None,
            reaped: false,
            outcome: None,
            exit_status: None,
            owner_exit: None,
            identity,
        };
        let http = StudioHttp::new(listen)?;
        match wait_ready(&mut server, &http).await {
            Ok(()) => {
                // The server pid is the one the owner itself reported for this
                // instance; nothing is parsed out of a log line.
                match server.wait_control_ready() {
                    Ok(server_pid) => {
                        server.server_pid = Some(server_pid);
                        Ok(server)
                    }
                    Err(error) => {
                        let stop = server.stop();
                        bail!("{error:#}; server stop={stop:?}");
                    }
                }
            }
            Err(error) => {
                let log = fs::read_to_string(&server.log).unwrap_or_default();
                let stop = server.stop();
                bail!(
                    "{error:#}; server stop={stop:?}; log (redacted): {}",
                    super::env::redact(&truncate(&log, 4000))
                );
            }
        }
    }

    /// Stops this instance through the private typed control face.
    ///
    /// The signal itself is sent by the process owner through the pidfd it opened
    /// before any wait, so a parsed pid is never signalled and the delivery is
    /// kernel-confirmed. A concluded stop is idempotent: repeating it neither
    /// writes another command nor signals again.
    ///
    /// Every path runs the same bounded drain. A refused or missing answer, a
    /// failed signal, and a non-zero launcher exit all end in the owner's own
    /// terminal receipt being read and validated, so a graceful claim can never
    /// come from a launcher status alone.
    pub fn stop(&mut self) -> Result<StopOutcome> {
        if let Some(outcome) = self.outcome {
            return Ok(outcome);
        }
        // A reaped child is no longer ours to signal. Reporting the failure without
        // touching the pid keeps a recycled pid and a repeated stop out of reach.
        if self.reaped {
            bail!(
                "the isolated server was already reaped without a controlled stop ({}); \
                 no signal was sent to the reaped pid",
                self.stop_evidence()
            );
        }
        let server_pid = self.wait_control_ready()?;
        if self.server_pid.is_none() {
            self.server_pid = Some(server_pid);
        }
        let op = format!("stop-{}", self.stop_attempts + 1);
        self.stop_attempts += 1;
        let write = self.write_control(&format!("stop {op}\n"));
        let answer = self.wait_stop_answer(&op)?;
        match &answer {
            Some(StopAnswer::Delivered { count }) => self.signals_sent = *count,
            Some(StopAnswer::Failed { reason }) => self.stop_failure = Some(reason.clone()),
            Some(StopAnswer::AlreadyExited) | None => {}
        }
        // One bounded drain for every path: the owner's own outcome is always
        // observed, so a failure cannot leave an unaccounted live instance behind.
        let status = self.reap_launcher()?;
        if let Some(status) = status {
            // The child is reaped the moment `try_wait` returns it, so this is
            // recorded before any receipt check can fail.
            self.record_reaped(status);
        }
        let terminal = self.read_owner_terminal()?;
        self.owner_exit = terminal.as_ref().map(OwnerTerminal::evidence);
        let write_note = match &write {
            Ok(()) => String::new(),
            Err(error) => format!("; control write failed: {error:#}"),
        };
        let status = match status {
            Some(status) => status,
            None => bail!(
                "the launcher did not exit inside its bounded stop window; its managed group was \
                 killed and this owner proved no cleanup (terminal={}), so the outer resident \
                 supervisor owns the remaining reclamation ({}{write_note})",
                terminal.is_some(),
                self.stop_evidence()
            ),
        };
        let terminal = match terminal {
            Some(terminal) => terminal,
            None => bail!(
                "the process owner reported no trusted terminal receipt, so a graceful stop is not \
                 proven (launcher {status}; {}{write_note})",
                self.stop_evidence()
            ),
        };
        if let Some(reason) = self.stop_failure.take() {
            bail!(
                "the process owner could not deliver the stop signal ({reason}); terminal: {}{write_note}",
                terminal.evidence()
            );
        }
        match answer {
            Some(StopAnswer::Delivered { count }) => {
                terminal.require_graceful(count)?;
                ensure!(
                    status.success(),
                    "the launcher exited with {status} although the owner reported a graceful stop"
                );
                self.outcome = Some(StopOutcome::Delivered);
            }
            Some(StopAnswer::Failed { reason }) => {
                // The failure above already ended this stop; keeping the arm explicit
                // means a future change cannot fall through to a success claim.
                bail!("the process owner reported a delivery failure ({reason})");
            }
            Some(StopAnswer::AlreadyExited) | None => {
                terminal.require_already_exited()?;
                if !status.success() {
                    bail!(
                        "the isolated server launcher exited with {status} before any controlled \
                         stop; terminal: {}{write_note}",
                        terminal.evidence()
                    );
                }
                self.outcome = Some(StopOutcome::AlreadyExited);
            }
        }
        self.outcome
            .context("the stop concluded without an outcome")
    }

    /// Waits, bounded, for this instance's control-ready receipt and returns the
    /// server pid the owner itself reported.
    fn wait_control_ready(&mut self) -> Result<u32> {
        let deadline = Instant::now() + CONTROL_READY_WINDOW;
        loop {
            let receipts = self.read_receipts()?;
            for receipt in &receipts {
                if let Receipt::ControlError {
                    instance,
                    reason,
                    detail,
                } = receipt
                    && instance == &self.instance
                {
                    bail!("the process owner refused to start: reason={reason} detail={detail:?}");
                }
            }
            if let Some(pid) = receipts.iter().find_map(|receipt| match receipt {
                Receipt::ControlReady {
                    instance,
                    server_pid,
                } if instance == &self.instance => Some(*server_pid),
                _ => None,
            }) {
                return Ok(pid);
            }
            if Instant::now() >= deadline {
                bail!(
                    "the process owner announced no control-ready receipt within {}s",
                    CONTROL_READY_WINDOW.as_secs()
                );
            }
            std::thread::sleep(POLL);
        }
    }

    fn write_control(&mut self, command: &str) -> Result<()> {
        let control = self
            .control
            .as_mut()
            .context("the process owner control face is closed")?;
        control
            .write_all(command.as_bytes())
            .context("failed to write the stop command to the process owner")?;
        control
            .flush()
            .context("failed to flush the stop command to the process owner")
    }

    /// Reads the owner's answer for exactly this operation id.
    ///
    /// `None` means no answer arrived inside the bounded window; refusal or a
    /// failed signal is returned as an answer so the caller can still drain, and a
    /// duplicated attempt is a hard error.
    fn wait_stop_answer(&mut self, op: &str) -> Result<Option<StopAnswer>> {
        let deadline = Instant::now() + STOP_ANSWER_WINDOW;
        loop {
            let receipts = self.read_receipts()?;
            let mut delivered: Option<u32> = None;
            let mut already_exited = false;
            let mut failed: Option<String> = None;
            let mut duplicate = false;
            let mut control_closed = false;
            for receipt in &receipts {
                match receipt {
                    Receipt::StopDelivered {
                        instance,
                        op: receipt_op,
                        signal,
                        pid,
                        count,
                    } if instance == &self.instance && receipt_op.as_str() == op => {
                        let pid = *pid;
                        ensure!(
                            signal == "INT",
                            "the process owner reported signal {signal} instead of INT"
                        );
                        ensure!(
                            Some(pid) == self.server_pid,
                            "the delivered signal targeted pid {pid}, not the recorded server pid {:?}",
                            self.server_pid
                        );
                        ensure!(
                            *count == 1,
                            "the process owner reported {count} deliveries; one instance gets exactly one"
                        );
                        if let Some(previous) = delivered {
                            ensure!(
                                previous == *count,
                                "the owner receipt channel holds conflicting delivery counts"
                            );
                        }
                        delivered = Some(*count);
                    }
                    Receipt::StopAlreadyExited {
                        instance,
                        op: receipt_op,
                    } if instance == &self.instance && receipt_op.as_str() == op => {
                        already_exited = true;
                    }
                    Receipt::StopFailed {
                        instance,
                        op: receipt_op,
                        reason,
                        errno,
                    } if instance == &self.instance && receipt_op.as_str() == op => {
                        failed = Some(format!("{reason} (errno={errno:?})"));
                    }
                    Receipt::StopDuplicate {
                        instance,
                        op: receipt_op,
                    } if instance == &self.instance && receipt_op.as_str() == op => {
                        duplicate = true;
                    }
                    Receipt::StopEscalated {
                        instance,
                        op: receipt_op,
                        signal,
                        pid,
                    } if instance == &self.instance => {
                        // An escalation means the graceful window expired, so this
                        // instance's stop is not graceful whatever else it reports.
                        ensure!(
                            signal == "KILL",
                            "the process owner reported an unexpected escalation signal {signal}"
                        );
                        ensure!(
                            Some(*pid) == self.server_pid,
                            "the escalation targeted pid {pid}, not the recorded server pid {:?}",
                            self.server_pid
                        );
                        self.escalation = Some(format!("{signal} pid={pid} for {receipt_op}"));
                    }
                    Receipt::ControlRejected { instance, length } if instance == &self.instance => {
                        // Our command is the only writer, so a rejected command means
                        // something else reached the control face.
                        bail!(
                            "the owner rejected a {length}-byte control command; this instance \
                             wrote only its own stop request"
                        );
                    }
                    Receipt::ControlClosed { instance } if instance == &self.instance => {
                        control_closed = true;
                    }
                    _ => {}
                }
            }
            ensure!(
                !duplicate,
                "the process owner refused a second stop for this instance ({op})"
            );
            if let Some(count) = delivered {
                ensure!(
                    failed.is_none() && !already_exited,
                    "conflicting owner receipts for {op}: delivered={count} failed={failed:?} \
                     already_exited={already_exited}"
                );
                return Ok(Some(StopAnswer::Delivered { count }));
            }
            if let Some(reason) = failed {
                ensure!(
                    !already_exited,
                    "conflicting owner receipts for {op}: failed={reason} already_exited={already_exited}"
                );
                return Ok(Some(StopAnswer::Failed { reason }));
            }
            if already_exited {
                return Ok(Some(StopAnswer::AlreadyExited));
            }
            if control_closed {
                return Ok(Some(StopAnswer::Failed {
                    reason: "the owner control face closed before the stop".to_owned(),
                }));
            }
            if Instant::now() >= deadline {
                return Ok(None);
            }
            std::thread::sleep(POLL);
        }
    }

    /// Bounded wait for the launcher's terminal state.
    ///
    /// There is no unbounded `Child::wait` here: the owner bounds its own stop and
    /// this only backstops it with the managed group of a child we still own.
    /// `None` means the launcher never terminated inside both windows.
    fn reap_launcher(&mut self) -> Result<Option<ExitStatus>> {
        let deadline = Instant::now() + LAUNCHER_STOP_WINDOW;
        loop {
            if let Some(status) = self
                .child
                .try_wait()
                .context("failed to observe the isolated server launcher")?
            {
                return Ok(Some(status));
            }
            if Instant::now() >= deadline {
                break;
            }
            std::thread::sleep(POLL);
        }
        // Still alive and still ours: only the managed group of this child is killed.
        signal_group("KILL", self.child.id());
        let backstop = Instant::now() + REAP_BACKSTOP;
        loop {
            if let Some(status) = self
                .child
                .try_wait()
                .context("failed to observe the isolated server launcher")?
            {
                return Ok(Some(status));
            }
            if Instant::now() >= backstop {
                return Ok(None);
            }
            std::thread::sleep(POLL);
        }
    }

    /// Every typed receipt of this instance's channel.
    ///
    /// A line that is not a typed receipt is an error: only the owner holds this
    /// channel, so an unreadable line is a real integrity failure, not noise.
    fn read_receipts(&self) -> Result<Vec<Receipt>> {
        let text = match fs::read_to_string(&self.receipts) {
            Ok(text) => text,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("failed to read {}", self.receipts.display()));
            }
        };
        text.lines()
            .filter(|line| !line.trim().is_empty())
            .map(|line| {
                serde_json::from_str::<Receipt>(line).with_context(|| {
                    format!("the owner receipt channel holds an untyped line: {line}")
                })
            })
            .collect()
    }

    /// The owner's terminal receipt for this instance, when it is already written.
    fn read_owner_terminal(&self) -> Result<Option<OwnerTerminal>> {
        let deadline = Instant::now() + TERMINAL_WINDOW;
        loop {
            let receipts = self.read_receipts()?;
            let terminals: Vec<&Receipt> = receipts
                .iter()
                .filter(|receipt| {
                    matches!(
                        receipt,
                        Receipt::OwnerExit { instance, .. } if instance == &self.instance
                    )
                })
                .collect();
            ensure!(
                terminals.len() <= 1,
                "the owner receipt channel holds {} terminal receipts for this instance",
                terminals.len()
            );
            if let Some(Receipt::OwnerExit {
                server_exit,
                keyring_exit,
                readiness_exit,
                delivered,
                escalated,
                graceful,
                failure,
                cleanup_complete,
                server_reaped,
                keyring_reaped,
                readiness_reaped,
                cleanup_errors,
                ..
            }) = terminals.first().copied()
            {
                return Ok(Some(OwnerTerminal {
                    server_exit: *server_exit,
                    keyring_exit: *keyring_exit,
                    readiness_exit: *readiness_exit,
                    delivered: *delivered,
                    escalated: *escalated,
                    graceful: *graceful,
                    failure: failure.clone(),
                    cleanup_complete: *cleanup_complete,
                    server_reaped: *server_reaped,
                    keyring_reaped: *keyring_reaped,
                    readiness_reaped: *readiness_reaped,
                    cleanup_errors: cleanup_errors.clone(),
                }));
            }
            if Instant::now() >= deadline {
                return Ok(None);
            }
            std::thread::sleep(POLL);
        }
    }

    fn record_reaped(&mut self, status: ExitStatus) {
        self.reaped = true;
        self.exit_status = Some(status);
    }
}

impl Drop for StudioServer {
    fn drop(&mut self) {
        // Bounded everywhere: a concluded stop is not repeated, and a stop that
        // already failed keeps its real diagnosis instead of looping here.
        if self.outcome.is_none() {
            let _ = self.stop();
        }
    }
}

async fn wait_ready(server: &mut StudioServer, http: &StudioHttp) -> Result<()> {
    let deadline = Instant::now() + super::http::PREDICATE_TIMEOUT;
    loop {
        if let Some(status) = server.child.try_wait()? {
            // Exited before /health: this is a terminal state, not a graceful stop.
            server.record_reaped(status);
            bail!("isolated pl-studio-server exited before /health: {status}");
        }
        match http.wait_health_once().await {
            Ok(()) => return Ok(()),
            Err(error) if Instant::now() >= deadline => {
                bail!("studio server did not become ready on /health: {error:#}");
            }
            Err(_) => tokio::time::sleep(super::http::POLL).await,
        }
    }
}

/// Kills the managed process group of a child we still own.
///
/// This is the only group-wide signal left: the server itself is stopped through
/// the owner's pidfd, never through a parsed pid.
fn signal_group(signal: &str, pid: u32) {
    let group = format!("-{pid}");
    let _ = Command::new("/usr/bin/kill")
        .args(["-s", signal, "--", &group])
        .stderr(Stdio::null())
        .status();
}

async fn build_server(workspace: &Path) -> Result<PathBuf> {
    tokio::task::spawn_blocking({
        let workspace = workspace.to_path_buf();
        move || build_server_blocking(&workspace)
    })
    .await
    .context("server build task join failed")?
}

fn build_server_blocking(workspace: &Path) -> Result<PathBuf> {
    let args = [
        "build",
        "--locked",
        "--offline",
        "-p",
        "pl-studio-server",
        "--bin",
        "pl-studio-server",
    ];
    let status = Command::new("cargo")
        .current_dir(workspace)
        .args(args)
        .status()
        .context("failed to start cargo build -p pl-studio-server")?;
    if !status.success() {
        bail!(
            "debug pl-studio-server failed to compile (locked/offline). This may be an in-flight A crate error; C does not patch those crates. status={status}"
        );
    }
    let discovery = Command::new("cargo")
        .current_dir(workspace)
        .args(args)
        .arg("--message-format=json")
        .output()
        .context("failed to query Cargo for pl-studio-server")?;
    ensure!(
        discovery.status.success(),
        "failed to locate pl-studio-server: {}",
        String::from_utf8_lossy(&discovery.stderr)
    );
    for line in String::from_utf8_lossy(&discovery.stdout).lines() {
        let Ok(record) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        let target = &record["target"];
        if record["reason"] == "compiler-artifact"
            && target["name"] == "pl-studio-server"
            && target["kind"]
                .as_array()
                .is_some_and(|kinds| kinds.iter().any(|kind| kind == "bin"))
            && let Some(executable) = record["executable"].as_str()
        {
            let executable = PathBuf::from(executable);
            ensure!(
                executable.is_file(),
                "server executable missing: {}",
                executable.display()
            );
            return Ok(executable);
        }
    }
    bail!("Cargo reported no pl-studio-server executable")
}

fn truncate(value: &str, max: usize) -> String {
    match value.char_indices().nth(max) {
        None => value.to_owned(),
        Some((index, _)) => format!("{}…", &value[..index]),
    }
}
