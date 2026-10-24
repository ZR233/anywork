use anyhow::{Context, Result, bail, ensure};
use pl_dev_support::process;
use std::fs::{self, File, OpenOptions};
use std::net::SocketAddr;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use super::env::ObservePaths;
use super::http::StudioHttp;
use super::report::{ServerBinarySource, ServerIdentity};

/// Keep gnome-keyring in the same session as the real server. `exec` would drop
/// the EXIT trap, so the server is started as a child and both paths wait for
/// the keyring process.
const KEYRING_SCRIPT: &str = r#"
set -eu
gnome-keyring-daemon --foreground --unlock --components=secrets < "$XDG_RUNTIME_DIR/fixture-password" &
keyring=$!
trap 'kill "$keyring" 2>/dev/null || true; wait "$keyring" 2>/dev/null || true' EXIT
gdbus wait --session --timeout 10 org.freedesktop.secrets
printf 'acceptance_keyring_pid=%s\n' "$keyring"
"$@" &
server=$!
printf 'acceptance_server_pid=%s\n' "$server"
status=0
wait "$server" || status=$?
kill "$keyring" 2>/dev/null || true
wait "$keyring" 2>/dev/null || true
exit "$status"
"#;

pub(crate) struct StudioServer {
    child: Child,
    listen: SocketAddr,
    log: PathBuf,
    server_pid: Option<u32>,
    stopped: bool,
    identity: ServerIdentity,
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
        let mut command = Command::new("dbus-run-session");
        command
            .arg("--")
            .arg("/bin/bash")
            .arg("-c")
            .arg(KEYRING_SCRIPT)
            .arg("bots-protocol-observe")
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
            .env_remove("GNOME_KEYRING_CONTROL")
            .env_remove("DBUS_SESSION_BUS_ADDRESS")
            .env_remove("GNOME_KEYRING_PID")
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));
        // Independent process group so SIGINT/KILL cannot hit the observe worker.
        command.process_group(0);
        process::configure_background_command(&mut command);
        let child = command
            .spawn()
            .context("failed to start isolated pl-studio-server")?;
        let mut server = Self {
            child,
            listen,
            log: launch.log.clone(),
            server_pid: None,
            stopped: false,
            identity,
        };
        let http = StudioHttp::new(listen)?;
        match wait_ready(&mut server, &http).await {
            Ok(()) => {
                server.server_pid = parse_server_pid(&server.log);
                Ok(server)
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

    pub fn stop(&mut self) -> Result<()> {
        if self.stopped {
            let _ = self.child.try_wait();
            return Ok(());
        }
        if self.server_pid.is_none() {
            self.server_pid = parse_server_pid(&self.log);
        }
        if let Some(pid) = self.server_pid {
            // The shell waits for this actual server and then its keyring.
            // Signalling dbus/the whole group here can reap the wrapper before
            // the runtime releases its home lock during graceful shutdown.
            signal_pid("INT", &pid.to_string());
        } else {
            signal_group("INT", self.child.id());
        }
        let deadline = Instant::now() + Duration::from_secs(8);
        loop {
            if self.child.try_wait()?.is_some() {
                self.stopped = true;
                return Ok(());
            }
            if Instant::now() >= deadline {
                if let Some(pid) = self.server_pid {
                    signal_pid("KILL", &pid.to_string());
                }
                signal_group("KILL", self.child.id());
                match self.child.wait() {
                    Ok(_) => {}
                    Err(error) => {
                        self.stopped = true;
                        bail!("pl-studio-server wait after SIGKILL failed: {error}");
                    }
                }
                self.stopped = true;
                bail!("pl-studio-server did not exit after SIGINT; SIGKILL used");
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }
}

impl Drop for StudioServer {
    fn drop(&mut self) {
        if !self.stopped {
            let _ = self.stop();
        }
    }
}

async fn wait_ready(server: &mut StudioServer, http: &StudioHttp) -> Result<()> {
    let deadline = Instant::now() + super::http::PREDICATE_TIMEOUT;
    loop {
        if let Some(status) = server.child.try_wait()? {
            server.stopped = true;
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

fn signal_pid(signal: &str, pid: &str) {
    let _ = Command::new("/usr/bin/kill")
        .args(["-s", signal, "--", pid])
        .stderr(Stdio::null())
        .status();
}

fn signal_group(signal: &str, pid: u32) {
    let group = format!("-{pid}");
    let _ = Command::new("/usr/bin/kill")
        .args(["-s", signal, "--", &group])
        .stderr(Stdio::null())
        .status();
}

fn parse_server_pid(log: &Path) -> Option<u32> {
    let text = fs::read_to_string(log).ok()?;
    for line in text.lines().rev() {
        if let Some(rest) = line.strip_prefix("acceptance_server_pid=") {
            return rest.trim().parse().ok();
        }
    }
    None
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
