//! Low-cost non-GUI acceptance matrix for ACP server auto-install.
//!
//! This observer drives the product's public HTTP operations
//! (`/api/v1/runtime/acp-install` read/start/cancel) against a real
//! `pl-studio-server` in an isolated home, with the fixture peer providing the
//! official registry/distribution environment through the standard HTTPS proxy
//! contract plus an isolated CA file. It never re-implements install logic and
//! never inspects private runtime state: every conclusion comes from the public
//! snapshot JSON, the real `<home>/studio/acp-servers` tree and the peer request
//! log.
//!
//! Cases:
//! - `source-rejected`: metadata points outside the official Google host;
//! - `missing-executable`: the package does not contain the declared entry;
//! - `zip64`, `zip64-data-descriptor`: valid samples must install completely;
//! - `zip-too-many-members`, `zip-duplicate`, `zip-case-collision`, `zip-crc`,
//!   `zip-size-mismatch`: hostile samples must fail with the exact typed code;
//! - `cache-corrupt`: an existing published copy is corrupted, then reused;
//! - `lock-wait`: another process holds the asset lock; waiting is cancellable
//!   and the holder is never disturbed;
//! - `shutdown-download`: the server is asked to exit during a real download and
//!   must stop the transfer, release the lock and leave no descendant.
//!
//! Each case starts its own isolated server subprocess with that case's proxy and
//! CA environment, so no process reads a global proxy variable. Wire identities
//! are `sha256:<64hex>`; filesystem keys are the 64 lowercase hex.

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("acp_install_observe requires the Linux native host");
    std::process::exit(2);
}

#[cfg(target_os = "linux")]
fn main() -> anyhow::Result<()> {
    linux::run()
}

#[cfg(target_os = "linux")]
mod linux {
    use std::cell::RefCell;
    use std::collections::BTreeMap;
    use std::fs::{self, File};
    use std::os::unix::process::CommandExt as _;
    use std::path::{Path, PathBuf};
    use std::process::{Child, Command, Stdio};
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

    use anyhow::{Context, Result, bail, ensure};
    use clap::Parser;
    use pl_protocol::studio::{
        AcpInstallSnapshot, AcpInstallState, AcpProvider, CancelAcpInstallRequest,
        StartAcpInstallRequest,
    };
    use pl_provider_fixture::acp_install::{
        AcpInstallControl, ArchiveControl, ArchiveStep, ArchiveVariant, RedirectTarget,
        file_sha256, fixed, host_target,
    };
    use reqwest::blocking::Client;
    use serde_json::{Value, json};

    const READY_FILE: &str = "ready.json";
    const REPORT_FILE: &str = "report.json";
    const CONTROL_FILE: &str = "control.json";
    const PROVIDER: &str = "antigravity";
    const PROGRAM_MEMBER: &str = "agy_acp_server.par";
    const AUXILIARY: &str = "localharness_external";
    const WIRE_ID_PREFIX: &str = "sha256:";
    const REQUESTS_FILE: &str = "requests.jsonl";
    /// 固定分发 host，即 `fixed::ARCHIVE_BASE_URL` 的 authority。
    const FIXED_ARCHIVE_HOST: &str = "dl.google.com";
    /// 已退役的 registry 来源：出现即失败，不能降格成“无关请求”。
    const RETIRED_REGISTRY_HOST: &str = "cdn.agentclientprotocol.com";
    const RETIRED_REGISTRY_PATH_PREFIX: &str = "/registry/";

    #[derive(Parser, Debug)]
    #[command(
        name = "acp_install_observe",
        about = "Drive production ACP install operations against the controlled official peer"
    )]
    struct Options {
        /// Evidence directory (defaults to target/acp-install-observe/<stamp>-<pid>).
        #[arg(long, value_name = "DIR")]
        output: Option<PathBuf>,
        /// Already-built pl-studio-server (defaults to building the workspace).
        #[arg(long = "server-binary", value_name = "PATH")]
        server_binary: Option<PathBuf>,
        /// Keep the isolated home after a successful run.
        #[arg(long)]
        retain_environment: bool,
        /// Run only these cases (repeatable).
        #[arg(long = "case", value_name = "NAME")]
        cases: Vec<String>,
    }

    pub(super) fn run() -> Result<()> {
        let options = Options::parse();
        let command: Vec<String> = std::env::args().collect();
        let paths = Paths::prepare(options.output.as_deref())?;
        let client = Client::builder()
            .no_proxy()
            .timeout(Duration::from_secs(30))
            .build()?;
        let selected: Vec<String> = if options.cases.is_empty() {
            [
                "source-rejected",
                "missing-executable",
                "zip64",
                "zip64-data-descriptor",
                "zip-too-many-members",
                "zip-duplicate",
                "zip-case-collision",
                "zip-crc",
                "zip-size-mismatch",
                "zip-descriptor-zero",
                "zip-descriptor-local",
                "zip-unknown-flags",
                "zip-implicit-dirs",
                "zip-empty-member",
                "program-not-executable",
                "cache-corrupt",
                "lock-wait",
                "shutdown-download",
                "existing-wide-permissions",
                "sidecar-reset-retry",
                "auth-preparation-required",
                "auth-installation-invalid",
                "auth-legacy-fields",
                "auth-server-version",
            ]
            .into_iter()
            .map(str::to_owned)
            .collect()
        } else {
            options.cases.clone()
        };

        let started_at = SystemTime::now();
        let mut results: Vec<Value> = Vec::new();
        let mut failure: Option<anyhow::Error> = None;
        for case in &selected {
            match run_case(case, &paths, &client, options.server_binary.as_deref()) {
                Ok(value) => results.push(value),
                Err(error) => {
                    failure = Some(error.context(format!("acp_install_observe case `{case}`")));
                    break;
                }
            }
        }
        let status = if failure.is_some() {
            "failed"
        } else {
            "completed"
        };
        let mut evidence = json!({
            "scenario": "acp-install-observe",
            "status": status,
            "platform": std::env::consts::OS,
            "architecture": std::env::consts::ARCH,
            "source": "fixture",
            "humanVerdict": "pending",
            "command": command,
            "startedAt": epoch_seconds(started_at),
            "finishedAt": epoch_seconds(SystemTime::now()),
            "server": paths.server_identity(options.server_binary.as_deref())?,
            // 实际被启动的 fixture peer：`ANYWORK_ACP_INSTALL_PEER` 替代时也必须如实记录，
            // 避免只凭 server 身份推断 peer 版本。
            "peer": paths.peer_identity()?,
            "cases": results,
        });
        redact_value(&mut evidence, &paths.redactions());
        // Everything that decides the process exit is collected *before* the
        // artifact is written, so the recorded `exitCode` is the real one and a
        // partial evidence copy can never look like a clean run.
        let mut problems = paths.copy_peer_evidence()?;
        if failure.is_none() && options.retain_environment {
            match paths.scrub_private_material() {
                Ok(()) => {
                    let retained_home = paths.home();
                    if let Err(error) = fs::write(
                        paths.output.join("retained-environment.json"),
                        serde_json::to_vec_pretty(&json!({
                            "root": paths.working.keep(),
                            "home": retained_home,
                        }))?,
                    ) {
                        problems.push(format!(
                            "failed to record the retained environment: {error}"
                        ));
                    }
                }
                Err(error) => {
                    problems.push(format!("failed to remove private key material: {error:#}"))
                }
            }
        }
        let exit_code = i64::from(failure.is_some() || !problems.is_empty());
        evidence["exitCode"] = json!(exit_code);
        let report = paths.output.join("acp-install-observe.json");
        fs::write(&report, serde_json::to_vec_pretty(&evidence)?)?;
        match (failure, problems.is_empty()) {
            (Some(error), _) => Err(error),
            (None, true) => Ok(()),
            (None, false) => Err(anyhow::anyhow!(problems.join("; "))),
        }
    }

    struct Paths {
        workspace: PathBuf,
        output: PathBuf,
        working: tempfile::TempDir,
        /// 当前 case 的隔离 home；每个 case 开始时轮换到全新目录。
        home: RefCell<PathBuf>,
        case_seq: AtomicU32,
        peer: PathBuf,
        agent: PathBuf,
        auxiliary: PathBuf,
        program: PathBuf,
        large_program: PathBuf,
        target: String,
    }

    impl Paths {
        fn prepare(requested: Option<&Path>) -> Result<Self> {
            let workspace = pl_dev_support::paths::workspace_root()?;
            let output = match requested {
                Some(path) => {
                    fs::create_dir_all(path)?;
                    fs::canonicalize(path)?
                }
                None => {
                    let stamp = epoch_seconds(SystemTime::now());
                    let path = workspace
                        .join("target/acp-install-observe")
                        .join(format!("{stamp}-{}", std::process::id()));
                    fs::create_dir_all(&path)?;
                    fs::canonicalize(path)?
                }
            };
            let working = tempfile::Builder::new()
                .prefix("environment-")
                .tempdir_in(&output)?;
            let home = working.path().join("home");
            fs::create_dir(&home)?;
            let peer = working.path().join("peer");
            fs::create_dir(&peer)?;
            let agent = working.path().join("agent");
            fs::create_dir(&agent)?;
            let auxiliary = working.path().join(AUXILIARY);
            fs::write(&auxiliary, b"acp install observe auxiliary member\n")?;
            let program = PathBuf::from("/usr/bin/true");
            ensure!(
                program.is_file(),
                "the install-only program fixture is missing: {}",
                program.display()
            );
            // A multi-megabyte real binary keeps the shutdown download inside a
            // real transfer window long enough for an explicit synchronization
            // point instead of a race with a tiny package.
            let large_program = ["/usr/bin/python3.12", "/usr/bin/git", "/usr/bin/openssl"]
                .into_iter()
                .map(PathBuf::from)
                .find(|path| {
                    fs::metadata(path)
                        .map(|meta| meta.is_file() && meta.len() >= 4 * 1024 * 1024)
                        .unwrap_or(false)
                })
                .context("no sufficiently large real executable for the shutdown case")?;
            Ok(Self {
                workspace,
                output,
                working,
                home: RefCell::new(home),
                case_seq: AtomicU32::new(0),
                peer,
                agent,
                auxiliary,
                program,
                large_program,
                target: host_target()?,
            })
        }

        fn home(&self) -> PathBuf {
            self.home.borrow().clone()
        }

        /// 每个 case 一个全新 home。
        ///
        /// 固定 descriptor 后所有 case 的 installationId 相同：共享 home 会让一个
        /// 成功安装后面的故障 case 直接 `reused`，故障根本不会发生。轮换目录而不是
        /// 清空共享目录，旧 case 的产物仍可事后核对。
        fn rotate_home(&self) -> Result<()> {
            let next_index = self.case_seq.fetch_add(1, Ordering::SeqCst) + 1;
            let next = self.working.path().join(format!("home-{next_index}"));
            fs::create_dir(&next)?;
            *self.home.borrow_mut() = next;
            Ok(())
        }

        fn installed_dir(&self, key: &str) -> PathBuf {
            self.home()
                .join("studio/acp-servers/installed")
                .join(PROVIDER)
                .join(&self.target)
                .join(key)
        }

        fn downloads_dir(&self) -> PathBuf {
            self.home()
                .join("studio/acp-servers/downloads")
                .join(PROVIDER)
                .join(&self.target)
        }

        fn lock_path(&self) -> PathBuf {
            self.home()
                .join("studio/acp-servers/locks")
                .join(PROVIDER)
                .join(format!("{}.lock", self.target))
        }

        fn installed_ids(&self) -> Result<Vec<String>> {
            let directory = self
                .home()
                .join("studio/acp-servers/installed")
                .join(PROVIDER)
                .join(&self.target);
            let mut ids = Vec::new();
            if directory.is_dir() {
                for entry in fs::read_dir(directory)? {
                    let entry = entry?;
                    if entry.file_type()?.is_dir() {
                        ids.push(entry.file_name().to_string_lossy().into_owned());
                    }
                }
            }
            ids.sort();
            Ok(ids)
        }

        /// 固定的可执行身份事实：路径、字节数与摘要（不含任何秘密）。
        fn binary_identity(&self, path: &Path) -> Result<Value> {
            let (bytes, sha256) = if path.is_file() {
                (
                    fs::metadata(path).map(|meta| meta.len()).unwrap_or(0),
                    file_sha256(path)?,
                )
            } else {
                (0, String::new())
            };
            Ok(json!({
                "path": path.to_string_lossy(),
                "bytes": bytes,
                "sha256": sha256,
            }))
        }

        /// 本 run 实际会被启动的 fixture peer（`ANYWORK_ACP_INSTALL_PEER` 可替代）。
        fn peer_binary(&self) -> PathBuf {
            std::env::var_os("ANYWORK_ACP_INSTALL_PEER")
                .map(PathBuf::from)
                .filter(|path| path.is_file())
                .unwrap_or_else(|| self.workspace.join("target/debug/pl-provider-fixture"))
        }

        fn peer_identity(&self) -> Result<Value> {
            let path = self.peer_binary();
            let mut identity = self.binary_identity(&path)?;
            identity["source"] = Value::String(
                if std::env::var_os("ANYWORK_ACP_INSTALL_PEER")
                    .is_some_and(|value| Path::new(&value).is_file())
                {
                    "env-override".to_owned()
                } else {
                    "workspace-build".to_owned()
                },
            );
            Ok(identity)
        }

        fn server_identity(&self, explicit: Option<&Path>) -> Result<Value> {
            let path = explicit
                .map(Path::to_path_buf)
                .unwrap_or_else(|| self.workspace.join("target/debug/pl-studio-server"));
            let mut identity = self.binary_identity(&path)?;
            identity["source"] = Value::String(if explicit.is_some() {
                "explicit".to_owned()
            } else {
                "workspace-build".to_owned()
            });
            Ok(json!({
                "path": identity["path"].clone(),
                "source": identity["source"].clone(),
                // Every crate in this workspace inherits `[workspace.package]
                // version`, so the acceptance build names the server's version.
                "version": env!("CARGO_PKG_VERSION"),
                "bytes": identity["bytes"].clone(),
                "sha256": identity["sha256"].clone(),
            }))
        }

        fn redactions(&self) -> Vec<(String, String)> {
            let mut redactions = vec![
                (
                    self.working.path().to_string_lossy().into_owned(),
                    "[isolated-root]".to_owned(),
                ),
                (
                    self.home().to_string_lossy().into_owned(),
                    "[home]".to_owned(),
                ),
                (
                    self.workspace.to_string_lossy().into_owned(),
                    "[workspace]".to_owned(),
                ),
                (
                    self.output.to_string_lossy().into_owned(),
                    "[evidence]".to_owned(),
                ),
                (
                    self.peer.to_string_lossy().into_owned(),
                    "[peer]".to_owned(),
                ),
                (
                    self.agent.to_string_lossy().into_owned(),
                    "[agent]".to_owned(),
                ),
                (
                    self.program.to_string_lossy().into_owned(),
                    "[program]".to_owned(),
                ),
                (
                    self.large_program.to_string_lossy().into_owned(),
                    "[large-program]".to_owned(),
                ),
                (
                    self.auxiliary.to_string_lossy().into_owned(),
                    "[auxiliary]".to_owned(),
                ),
            ];
            if let Ok(relative) = self.output.strip_prefix(&self.workspace) {
                redactions.push((
                    relative.to_string_lossy().into_owned(),
                    "[evidence]".to_owned(),
                ));
            }
            redactions.retain(|(from, _)| !from.is_empty());
            redactions
        }

        fn copy_peer_evidence(&self) -> Result<Vec<String>> {
            let mut problems = Vec::new();
            let redactions = self.redactions();
            if let Ok(text) = fs::read_to_string(self.peer.join("requests.jsonl")) {
                let mut redacted = text;
                for (from, to) in &redactions {
                    redacted = redacted.replace(from, to);
                }
                if let Err(error) = fs::write(self.output.join("peer-requests.jsonl"), redacted) {
                    problems.push(format!("failed to copy the peer request log: {error}"));
                }
            }
            if let Ok(text) = fs::read_to_string(self.peer.join("peer.log")) {
                let mut redacted = text;
                for (from, to) in &redactions {
                    redacted = redacted.replace(from, to);
                }
                if let Err(error) = fs::write(self.output.join("peer.log"), redacted) {
                    problems.push(format!("failed to copy the peer log: {error}"));
                }
            }
            Ok(problems)
        }

        /// Removes one-off private key material from a retained environment.
        fn scrub_private_material(&self) -> Result<()> {
            for name in [
                "tls/ca.key",
                "tls/leaf.key",
                "tls/leaf.key.der",
                "tls/leaf.csr",
                "tls/.srl",
            ] {
                let path = self.peer.join(name);
                match fs::remove_file(&path) {
                    Ok(()) => {}
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                    Err(error) => {
                        return Err(error).with_context(|| {
                            format!("failed to remove private material: {}", path.display())
                        });
                    }
                }
            }
            Ok(())
        }
    }

    fn epoch_seconds(value: SystemTime) -> u64 {
        value
            .duration_since(UNIX_EPOCH)
            .map_or(0, |elapsed| elapsed.as_secs())
    }

    fn redact_value(value: &mut Value, redactions: &[(String, String)]) {
        match value {
            Value::String(text) => {
                for (from, to) in redactions {
                    if !from.is_empty() {
                        *text = text.replace(from, to);
                    }
                }
            }
            Value::Array(items) => items
                .iter_mut()
                .for_each(|item| redact_value(item, redactions)),
            Value::Object(map) => map
                .values_mut()
                .for_each(|item| redact_value(item, redactions)),
            _ => {}
        }
    }

    struct ServerProcess {
        child: Child,
        listen: std::net::SocketAddr,
        log: PathBuf,
        group: u32,
    }

    impl ServerProcess {
        fn base(&self) -> String {
            format!("http://{}", self.listen)
        }

        /// Asks the isolated server to stop and waits for the real exit.
        ///
        /// SIGINT is the product's ordered shutdown path; a stronger signal is
        /// only sent when that window expires. A non-zero/signal exit is a real
        /// failure and is returned as such.
        fn stop(&mut self) -> Result<std::process::ExitStatus> {
            if let Some(status) = self.child.try_wait()? {
                ensure!(
                    status.success(),
                    "the isolated server exited with {status}; log tail: {}",
                    tail(&fs::read_to_string(&self.log).unwrap_or_default())
                );
                return Ok(status);
            }
            signal_group("INT", self.group);
            let deadline = Instant::now() + Duration::from_secs(10);
            loop {
                if let Some(status) = self.child.try_wait()? {
                    ensure!(
                        status.success(),
                        "the isolated server exited with {status} during shutdown; log tail: {}",
                        tail(&fs::read_to_string(&self.log).unwrap_or_default())
                    );
                    return Ok(status);
                }
                if Instant::now() >= deadline {
                    break;
                }
                std::thread::sleep(Duration::from_millis(100));
            }
            signal_group("TERM", self.group);
            let deadline = Instant::now() + Duration::from_secs(20);
            loop {
                if let Some(status) = self.child.try_wait()? {
                    ensure!(
                        status.success(),
                        "the isolated server had to be terminated with {status}; log tail: {}",
                        tail(&fs::read_to_string(&self.log).unwrap_or_default())
                    );
                    return Ok(status);
                }
                ensure!(
                    Instant::now() < deadline,
                    "the isolated server did not stop within the shutdown budget; log tail: {}",
                    tail(&fs::read_to_string(&self.log).unwrap_or_default())
                );
                std::thread::sleep(Duration::from_millis(100));
            }
        }

        fn discard(&mut self) {
            signal_group("KILL", self.group);
            let _ = self.child.wait();
        }
    }

    impl Drop for ServerProcess {
        fn drop(&mut self) {
            if self.child.try_wait().ok().flatten().is_none() {
                self.discard();
            }
        }
    }

    fn start_server(
        paths: &Paths,
        client: &Client,
        explicit: Option<&Path>,
        proxy: &str,
        ca: &str,
        home: &Path,
    ) -> Result<ServerProcess> {
        let binary = match explicit {
            Some(path) => path.to_path_buf(),
            None => {
                let status = Command::new("cargo")
                    .current_dir(&paths.workspace)
                    .args(["build", "-p", "pl-studio-server", "--locked"])
                    .status()
                    .context("failed to build pl-studio-server")?;
                ensure!(
                    status.success(),
                    "building pl-studio-server failed: {status}"
                );
                paths.workspace.join("target/debug/pl-studio-server")
            }
        };
        ensure!(
            binary.is_file(),
            "the Studio server binary is missing: {}",
            binary.display()
        );
        let listen = std::net::SocketAddr::from(([127, 0, 0, 1], choose_port()?));
        let log = paths
            .working
            .path()
            .join(format!("server-{}.log", listen.port()));
        let file = File::create(&log)?;
        let mut command = Command::new(&binary);
        // One intent, one source: the explicit home drives the CLI flag **and**
        // every HOME/XDG variable. `--studio-home` wins over the environment, so
        // leaving it at `paths.home` would silently run the server on the shared
        // home and make an isolated case prove nothing.
        command
            .arg("--listen")
            .arg(listen.to_string())
            .arg("--studio-home")
            .arg(home)
            .current_dir(&paths.workspace)
            .env("HOME", home)
            .env("ANYWORK_HOME", home)
            .env("XDG_DATA_HOME", home.join("xdg-data"))
            .env("XDG_CONFIG_HOME", home.join("xdg-config"))
            .env("HTTPS_PROXY", format!("http://{proxy}"))
            .env("HTTP_PROXY", format!("http://{proxy}"))
            .env("NO_PROXY", "127.0.0.1,localhost")
            .env("no_proxy", "127.0.0.1,localhost")
            .env("SSL_CERT_FILE", ca)
            .env_remove("ALL_PROXY")
            .env_remove("all_proxy")
            .stdout(Stdio::from(file.try_clone()?))
            .stderr(Stdio::from(file));
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
        command.process_group(0);
        pl_dev_support::process::configure_background_command(&mut command);
        let child = command
            .spawn()
            .context("failed to start the isolated server")?;
        let group = child.id();
        let mut server = ServerProcess {
            child,
            listen,
            log,
            group,
        };
        let deadline = Instant::now() + Duration::from_secs(180);
        loop {
            if let Some(status) = server.child.try_wait()? {
                let log = fs::read_to_string(&server.log).unwrap_or_default();
                signal_group("KILL", server.group);
                bail!("the isolated server exited with {status}: {}", tail(&log));
            }
            let ready = client
                .get(format!("{}/api/v1/runtime/acp-install", server.base()))
                .timeout(Duration::from_secs(5))
                .send()
                .is_ok_and(|response| response.status().is_success());
            if ready {
                return Ok(server);
            }
            if Instant::now() >= deadline {
                let log = fs::read_to_string(&server.log).unwrap_or_default();
                server.discard();
                bail!(
                    "the isolated server did not answer the install endpoint in time: {}",
                    tail(&log)
                );
            }
            std::thread::sleep(Duration::from_millis(200));
        }
    }

    fn choose_port() -> Result<u16> {
        let listener = std::net::TcpListener::bind(("127.0.0.1", 0))?;
        let port = listener.local_addr()?.port();
        ensure!(
            port != 1420 && port != 1421,
            "reserved development port chosen"
        );
        Ok(port)
    }

    fn signal_group(signal: &str, group: u32) {
        let _ = Command::new("kill")
            .args([&format!("-{signal}"), "--", &format!("-{group}")])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }

    fn tail(log: &str) -> String {
        let lines: Vec<&str> = log.lines().rev().take(20).collect();
        lines.into_iter().rev().collect::<Vec<_>>().join("\n")
    }

    struct Peer {
        child: Child,
        ready: Value,
        group: u32,
    }

    impl Peer {
        fn proxy(&self) -> Result<String> {
            Ok(self.ready["proxyAddress"]
                .as_str()
                .context("peer ready document has no proxy address")?
                .to_owned())
        }

        fn ca(&self) -> Result<String> {
            Ok(self.ready["caPem"]
                .as_str()
                .context("peer ready document has no CA path")?
                .to_owned())
        }

        fn archive_bytes(&self) -> Result<u64> {
            self.ready["archiveBytes"]
                .as_u64()
                .context("peer ready document has no archive size")
        }

        fn stop(mut self, peer: &Path) -> Result<Value> {
            // A peer that already exited is not a clean stop: the real status is
            // required on both paths, and a report on disk proves nothing about
            // how the process ended.
            let status = match self.child.try_wait()? {
                Some(status) => status,
                None => {
                    signal_group("TERM", self.group);
                    let deadline = Instant::now() + Duration::from_secs(30);
                    loop {
                        if let Some(status) = self.child.try_wait()? {
                            break status;
                        }
                        ensure!(
                            Instant::now() < deadline,
                            "the install peer did not stop within the cleanup budget"
                        );
                        std::thread::sleep(Duration::from_millis(100));
                    }
                }
            };
            ensure!(
                status.success(),
                "the install peer exited with {status} instead of a clean stop"
            );
            let report = read_json(&peer.join(REPORT_FILE))?;
            // The peer writes its report only after closing admission and joining
            // every connection/tunnel handler; anything else is a live task.
            ensure!(
                report["closed"].as_bool() == Some(true),
                "the install peer report does not prove that every handler stopped"
            );
            Ok(report)
        }

        fn discard(&mut self) {
            signal_group("KILL", self.group);
            let _ = self.child.wait();
        }
    }

    impl Drop for Peer {
        fn drop(&mut self) {
            if self.child.try_wait().ok().flatten().is_none() {
                self.discard();
            }
        }
    }

    fn start_peer(paths: &Paths, control: &AcpInstallControl) -> Result<Peer> {
        for name in [READY_FILE, REPORT_FILE] {
            let _ = fs::remove_file(paths.peer.join(name));
        }
        fs::write(
            paths.peer.join(CONTROL_FILE),
            serde_json::to_vec_pretty(control)?,
        )?;
        let log = paths.peer.join("peer.log");
        let file = File::create(&log)?;
        let binary = paths.peer_binary();
        ensure!(
            binary.is_file(),
            "the fixture peer binary is missing: {} (build -p pl-provider-fixture first)",
            binary.display()
        );
        let mut command = Command::new(&binary);
        command
            .arg("--acp-install-fixture")
            .arg("--acp-install-dir")
            .arg(&paths.peer)
            .stdout(Stdio::from(file.try_clone()?))
            .stderr(Stdio::from(file));
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
        command.process_group(0);
        pl_dev_support::process::configure_background_command(&mut command);
        let child = command
            .spawn()
            .context("failed to start the install peer")?;
        let group = child.id();
        let mut peer = Peer {
            child,
            ready: Value::Null,
            group,
        };
        let deadline = Instant::now() + Duration::from_secs(120);
        loop {
            if let Ok(bytes) = fs::read(paths.peer.join(READY_FILE)) {
                peer.ready = serde_json::from_slice(&bytes)?;
                return Ok(peer);
            }
            if peer.child.try_wait()?.is_some() {
                let log = fs::read_to_string(&log).unwrap_or_default();
                peer.discard();
                bail!(
                    "the install peer exited before becoming ready: {}",
                    tail(&log)
                );
            }
            if Instant::now() >= deadline {
                let log = fs::read_to_string(&log).unwrap_or_default();
                peer.discard();
                bail!(
                    "the install peer did not become ready in time; log: {}",
                    tail(&log)
                );
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }

    /// Holds the product's asset lock through the standard `flock` tool.
    struct LockHolder {
        child: Child,
        group: u32,
    }

    impl LockHolder {
        fn acquire(path: &Path) -> Result<Self> {
            use std::os::unix::fs::{DirBuilderExt as _, PermissionsExt as _};
            // 受管目录必须是 0700：用默认 umask 创建会让产品在 waitForLock 阶段
            // 直接以 ACL 不合格失败，这个 case 就变成了在测自己的权限。
            if let Some(parent) = path.parent() {
                fs::DirBuilder::new()
                    .recursive(true)
                    .mode(0o700)
                    .create(parent)?;
            }
            if !path.exists() {
                fs::OpenOptions::new()
                    .create_new(true)
                    .write(true)
                    .open(path)?;
                fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
            }
            let mut command = Command::new("flock");
            command
                .arg("--exclusive")
                .arg(path)
                .arg("sleep")
                .arg("600")
                .stdout(Stdio::null())
                .stderr(Stdio::null());
            // The lock lives in the file description shared with the `sleep`
            // child, so the holder is its own process group and releasing kills
            // the group instead of leaving an orphan that keeps the lock.
            command.process_group(0);
            let child = command
                .spawn()
                .context("the standard `flock` tool is required to hold the asset lock")?;
            let group = child.id();
            Ok(Self { child, group })
        }

        fn running(&mut self) -> bool {
            self.child.try_wait().ok().flatten().is_none()
        }

        fn release(mut self) -> Result<()> {
            // SIGKILL is the intended release: the holder holds the lock through a
            // long-lived `sleep`, so a clean exit is not expected here.
            signal_group("KILL", self.group);
            let _ = self.child.wait()?;
            Ok(())
        }
    }

    impl Drop for LockHolder {
        fn drop(&mut self) {
            if self.child.try_wait().ok().flatten().is_none() {
                signal_group("KILL", self.group);
                let _ = self.child.wait();
            }
        }
    }

    fn lock_is_free(path: &Path) -> Result<bool> {
        let status = Command::new("flock")
            .arg("--nonblock")
            .arg(path)
            .arg("true")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()?;
        Ok(status.success())
    }

    #[derive(Clone, Copy)]
    enum ZipExpectation {
        Ready,
        Failed(&'static str),
    }

    fn run_case(
        case: &str,
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
    ) -> Result<Value> {
        // 固定 descriptor 下所有 case 的安装身份相同：一个 case 一个全新 home，
        // 否则先跑的成功 case 会让后面的故障 case 直接复用 Ready。
        paths.rotate_home()?;
        let mut value = match case {
            "source-rejected" => source_rejected(paths, client, server_binary),
            "auth-preparation-required" => auth_preparation_required(paths, client, server_binary),
            "auth-installation-invalid" => auth_installation_invalid(paths, client, server_binary),
            "auth-legacy-fields" => auth_legacy_fields(paths, client, server_binary),
            "auth-server-version" => auth_server_version(paths, client, server_binary),
            "missing-executable" => missing_executable(paths, client, server_binary),
            "zip64" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::Zip64,
                ZipExpectation::Ready,
            ),
            "zip64-data-descriptor" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::Zip64DataDescriptor,
                ZipExpectation::Ready,
            ),
            "zip-too-many-members" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::TooManyMembers,
                ZipExpectation::Failed("tooLarge"),
            ),
            "zip-duplicate" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::Duplicate,
                ZipExpectation::Failed("invalidArchive"),
            ),
            "zip-case-collision" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::CaseCollision,
                ZipExpectation::Failed("invalidArchive"),
            ),
            "zip-crc" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::CorruptCrc,
                ZipExpectation::Failed("invalidArchive"),
            ),
            "zip-size-mismatch" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::SizeMismatch,
                ZipExpectation::Failed("invalidArchive"),
            ),
            // Counter-examples for the header/descriptor contract: a lying data
            // descriptor, a non-zero bit-3 local placeholder, and a flag outside the
            // supported allowlist must all be rejected by the product.
            //
            // `zip-descriptor-zero` is the opposite: under the user's confirmed
            // policy only the duplicated tail fields are not re-compared, while the
            // payload, central directory, receipt and full tree still are, so this
            // package must install completely.
            "zip-descriptor-zero" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::DataDescriptorZero,
                ZipExpectation::Ready,
            ),
            "zip-descriptor-local" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::DataDescriptorLocalNonZero,
                ZipExpectation::Failed("invalidArchive"),
            ),
            "zip-unknown-flags" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::UnknownFlags,
                ZipExpectation::Failed("invalidArchive"),
            ),
            // Implicit parent directories count against the package budget even
            // when the member count stays inside it.
            "zip-implicit-dirs" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::ImplicitDirectories,
                ZipExpectation::Failed("tooLarge"),
            ),
            // A genuinely empty member keeps real zeros in local header, data
            // descriptor and central directory, so it must install completely.
            "zip-empty-member" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::EmptyMember,
                ZipExpectation::Ready,
            ),
            // A program member without the executable bit is not a usable entry.
            "program-not-executable" => zip_case(
                paths,
                client,
                server_binary,
                ArchiveVariant::ProgramNotExecutable,
                ZipExpectation::Failed("missingExecutable"),
            ),
            "existing-wide-permissions" => existing_wide_permissions(paths, client, server_binary),
            // A real validator change must reset the resume state and rebuild the
            // sidecar; a later operation on the same descriptor then resumes.
            "sidecar-reset-retry" => sidecar_reset_retry(paths, client, server_binary),
            "cache-corrupt" => cache_corrupt(paths, client, server_binary),
            "lock-wait" => lock_wait(paths, client, server_binary),
            "shutdown-download" => shutdown_download(paths, client, server_binary),
            other => bail!("unknown case `{other}`"),
        }?;
        // Keep the requested matrix name next to the version-based evidence label
        // so one ZIP variant can never be mistaken for another.
        value["requestedCase"] = json!(case);
        Ok(value)
    }

    struct CaseEnv {
        peer: Peer,
        server: ServerProcess,
        archive_sha: String,
        archive_bytes: u64,
    }

    impl CaseEnv {
        fn open(
            paths: &Paths,
            client: &Client,
            server_binary: Option<&Path>,
            control: &AcpInstallControl,
        ) -> Result<Self> {
            Self::open_with_home(paths, &paths.home(), client, server_binary, control)
        }

        /// Opens one isolated server against an explicit home.
        ///
        /// Counter-examples that must create dangerous pre-existing state use their
        /// own home, so they can neither observe nor damage another case's
        /// successful installation or broken cache.
        fn open_with_home(
            paths: &Paths,
            home: &Path,
            client: &Client,
            server_binary: Option<&Path>,
            control: &AcpInstallControl,
        ) -> Result<Self> {
            let peer = start_peer(paths, control)?;
            let proxy = peer.proxy()?;
            let ca = peer.ca()?;
            let archive_sha = peer
                .ready
                .get("archiveSha256")
                .and_then(Value::as_str)
                .context("peer ready document has no archive digest")?
                .to_owned();
            let archive_bytes = peer.archive_bytes()?;
            let server = match start_server(paths, client, server_binary, &proxy, &ca, home) {
                Ok(server) => server,
                Err(error) => {
                    let mut peer = peer;
                    peer.discard();
                    return Err(error);
                }
            };
            Ok(Self {
                peer,
                server,
                archive_sha,
                archive_bytes,
            })
        }

        fn base(&self) -> String {
            self.server.base()
        }
    }

    fn finish(case: &str, peer_dir: &Path, env: CaseEnv, outcome: Result<Value>) -> Result<Value> {
        let CaseEnv {
            peer,
            mut server,
            archive_sha,
            archive_bytes,
        } = env;
        let stop = server.stop();
        let report = peer.stop(peer_dir);
        // Cleanup failures are collected before the case outcome so a real
        // shutdown/closure defect can never be hidden by a green case body.
        let exit = stop?;
        let report = report?;
        // 每个生命周期都要核对证据完整：日志行全部合法、报告证明记录完整、计数与
        // 日志相核。缺一即失败，不能降格成“零请求”。
        let request_records = validate_peer_evidence(peer_dir, &report)?;
        // 计数成立还不够：来源分类也必须成立。退役 registry、固定 host 上的非固定
        // path 或非 GET/HEAD 请求都在这里失败；其它 host 的隧道只作诊断。
        let source_audit = audit_peer_sources(&request_records)?;
        let value = outcome?;
        let mut value = value;
        if let Some(object) = value.as_object_mut() {
            object.insert("case".to_owned(), Value::String(case.to_owned()));
            object.insert("serverExit".to_owned(), Value::String(exit.to_string()));
            object.insert("archiveSha256".to_owned(), Value::String(archive_sha));
            object.insert(
                "archiveBytes".to_owned(),
                Value::Number(archive_bytes.into()),
            );
            object.insert("peer".to_owned(), report);
            object.insert(
                "peerRequestRecords".to_owned(),
                Value::Number((request_records.len() as u64).into()),
            );
            object.insert("sourceAudit".to_owned(), source_audit);
        }
        Ok(value)
    }

    /// 归档地址来源政策：固定 URL 被重定向到别的 host 时必须拒绝。
    ///
    /// registry 文档删除后，这条安全边界仍由产品逐跳校验，所以样本挪到归档响应上。
    fn source_rejected(
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
    ) -> Result<Value> {
        let mut control = control(paths, ArchiveVariant::Normal, 65_536, None, 0);
        control.archive.redirects = 1;
        control.archive.redirect_target = Some(RedirectTarget::ForeignHost);
        let env = CaseEnv::open(paths, client, server_binary, &control)?;
        let before = paths.installed_ids()?;
        let outcome = (|| -> Result<Value> {
            start(client, &env.base(), "observe-source-rejected")?;
            let state = wait_terminal(client, &env.base(), Duration::from_secs(120))?;
            // 跨 host 的重定向必须在**下载阶段**被判为来源拒绝、且不可重试；
            // 这一点由产品的 typed 结果证明，不能只看“没有 2xx”。
            let failure = expect_failed(&state, "sourceRejected")?;
            ensure!(
                failure["stage"].as_str() == Some("download"),
                "the rejected source failed at `{:?}` instead of the download stage",
                failure["stage"]
            );
            ensure!(
                failure["retryable"].as_bool() == Some(false),
                "a rejected source must not be retryable"
            );
            ensure!(
                paths.installed_ids()? == before,
                "the rejected source still published an installation"
            );
            let (redirects, bodies) = peer_archive_statuses(&paths.peer)?;
            ensure!(
                redirects >= 1,
                "the fixture never issued the forbidden redirect"
            );
            ensure!(
                bodies == 0,
                "the rejected hop still received an archive body ({bodies} responses)"
            );
            // 更关键的事实：product 根本不得尝试连接被拒的 host。proxy 会拒绝非官方
            // CONNECT，所以只看“官方端点没有 2xx”会被这个 403 掩盖。
            let attempted = peer_attempted_hosts(&paths.peer)?;
            ensure!(
                !attempted
                    .iter()
                    .any(|host| host.contains("example.invalid")),
                "the product actually attempted the rejected redirect target: {attempted:?}"
            );
            // server 自身还有与安装无关的出网行为（例如目录同步），它们也会被 peer
            // 以 403 拒掉；这里只声明“被拒的重定向目标从未被连接”，并把全部实际
            // 尝试原样记录，避免把无关流量误当成通过条件。
            let unrelated_rejected: Vec<&String> = attempted
                .iter()
                .filter(|host| !host.starts_with("dl.google.com"))
                .collect();
            let attempts = peer_archive_requests(&paths.peer)?;
            ensure!(
                attempts == 1,
                "the rejected source was retried automatically: {attempts} archive requests"
            );
            Ok(json!({
                "failure": failure,
                "rejectedRedirect": true,
                "redirectResponses": redirects,
                "servedBodies": bodies,
                "attemptedHosts": attempted,
                "unrelatedRejectedTunnels": unrelated_rejected,
                "archiveRequests": attempts,
                "connectedToRejectedHost": false,
            }))
        })();
        finish("source-rejected", &paths.peer, env, outcome)
    }

    fn missing_executable(
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
    ) -> Result<Value> {
        let control = control(paths, ArchiveVariant::MissingExecutable, 65_536, None, 0);
        let env = CaseEnv::open(paths, client, server_binary, &control)?;
        let before = paths.installed_ids()?;
        let outcome = (|| -> Result<Value> {
            start(client, &env.base(), "observe-missing-executable")?;
            let state = wait_terminal(client, &env.base(), Duration::from_secs(120))?;
            let failure = expect_failed(&state, "missingExecutable")?;
            ensure!(
                paths.installed_ids()? == before,
                "a package without the declared entry still published an installation"
            );
            Ok(json!({ "failure": failure }))
        })();
        finish("missing-executable", &paths.peer, env, outcome)
    }

    fn zip_case(
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
        variant: ArchiveVariant,
        expectation: ZipExpectation,
    ) -> Result<Value> {
        let control = control(paths, variant, 262_144, None, 0);
        let env = CaseEnv::open(paths, client, server_binary, &control)?;
        let before = paths.installed_ids()?;
        let archive_sha = env.archive_sha.clone();
        // The served package is the expectation for the published tree.
        let expected_members: Vec<Value> = env
            .peer
            .ready
            .get("members")
            .and_then(Value::as_array)
            .cloned()
            .context("the peer ready document has no member list")?;
        let outcome = (|| -> Result<Value> {
            start(client, &env.base(), "observe-zip")?;
            let state = wait_terminal(client, &env.base(), Duration::from_secs(300))?;
            match expectation {
                ZipExpectation::Ready => {
                    let observed = expect_ready(&state)?;
                    let key = storage_key(&observed.wire_id)?;
                    verify_publication(
                        paths,
                        &key,
                        &observed,
                        &archive_sha,
                        &expected_members,
                        &paths.program,
                    )?;
                    Ok(json!({ "expectation": "ready", "observed": observed.json }))
                }
                ZipExpectation::Failed(code) => {
                    let failure = expect_failed(&state, code)?;
                    ensure!(
                        paths.installed_ids()? == before,
                        "the rejected package still published an installation"
                    );
                    Ok(json!({ "expectation": "failed", "failure": failure }))
                }
            }
        })();
        finish(&format!("zip-{variant:?}"), &paths.peer, env, outcome)
    }

    /// A pre-existing managed directory with world-writable permissions must be
    /// refused, not silently tightened, and nothing may be published.
    #[cfg_attr(not(unix), allow(unused_variables))]
    fn existing_wide_permissions(
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
    ) -> Result<Value> {
        #[cfg(not(unix))]
        {
            bail!("the wide-permission counter-example requires the Unix native host");
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;

            let control = control_with(
                paths,
                &paths.program,
                ArchiveVariant::Normal,
                262_144,
                None,
                0,
            );
            // This case owns a whole home of its own: it creates a dangerous
            // pre-existing directory and must not observe, chmod or delete another
            // case's successful installation or broken cache.
            let home = paths.working.path().join("wide-permissions-home");
            create_private_ancestor(&home)?;
            // The product refuses any managed directory that is not exactly 0700,
            // so the ancestors of the deliberately wide target have to look like a
            // safe product tree. `create_dir_all` would create them as 0777 & ~umask
            // (0775 here) and the product would reject an ancestor long before the
            // target is reached — a failure that proves nothing about the target.
            let mut managed = home.clone();
            let mut ancestor_facts: Vec<(String, String)> = Vec::new();
            for component in ["studio", "acp-servers", "installed", PROVIDER] {
                managed = managed.join(component);
                let mode = create_private_ancestor(&managed)?;
                ancestor_facts.push((
                    managed
                        .strip_prefix(&home)
                        .unwrap_or(&managed)
                        .to_string_lossy()
                        .into_owned(),
                    format!("{mode:04o}"),
                ));
            }
            // Only the provider/target level itself is deliberately wide open: this
            // is the directory `installed_dir()` ensures at the publish stage.
            let target_dir = managed.join(&paths.target);
            create_wide_target(&target_dir)?;
            managed = target_dir;
            ancestor_facts.push((
                managed
                    .strip_prefix(&home)
                    .unwrap_or(&managed)
                    .to_string_lossy()
                    .into_owned(),
                "0777".to_owned(),
            ));
            let before = installed_ids_in(&home, &paths.target)?;
            // Whatever earlier cases published in the shared home must stay
            // byte-identical: this case may only touch its own home.
            let shared_before = installed_fingerprint(&paths.home(), &paths.target)?;
            let env = CaseEnv::open_with_home(paths, &home, client, server_binary, &control)?;
            let outcome = (|| -> Result<Value> {
                start(client, &env.base(), "observe-wide-permissions")?;
                let failed = wait_terminal(client, &env.base(), Duration::from_secs(120))?;
                ensure!(
                    matches!(failed, AcpInstallState::Failed { .. }),
                    "the wide-permission install did not fail: {}",
                    observe(&failed)
                );
                let observed = expect_failed(&failed, "io")?;
                // The rejection must come from the target directory ensure at the
                // publish stage, not from an earlier ancestor: any other stage would
                // mean this case never exercised the directory it created.
                ensure!(
                    observed["stage"].as_str() == Some("publish"),
                    "the wide-permission rejection happened at stage `{:?}` instead of `publish`",
                    observed["stage"].as_str()
                );
                // Refusing to trust the directory also means refusing to "fix" it
                // quietly: the observed mode must still be the wide one.
                let mode = fs::metadata(&managed)?.permissions().mode() & 0o7777;
                ensure!(
                    mode == 0o777,
                    "the product silently rewrote the rejected directory mode to {mode:04o}"
                );
                ensure!(
                    installed_ids_in(&home, &paths.target)? == before,
                    "the wide-permission install published an installation anyway"
                );
                let shared_after = installed_fingerprint(&paths.home(), &paths.target)?;
                ensure!(
                    shared_before == shared_after,
                    "the wide-permission case changed an installation in the shared home"
                );
                Ok(json!({
                    "failed": observed,
                    "directoryMode": format!("{mode:04o}"),
                    "directoryKept": true,
                    "expectedStage": "publish",
                    "actualStage": observed["stage"].clone(),
                    "managedAncestors": ancestor_facts,
                    "isolatedHome": home.to_string_lossy(),
                    "sharedInstalls": shared_before.keys().cloned().collect::<Vec<_>>(),
                    "sharedInstallsUnchanged": true,
                }))
            })();
            let finished = finish("existing-wide-permissions", &paths.peer, env, outcome);
            // Only this case's own home is removed; nothing outside it can be
            // affected, whatever order the matrix runs in.
            remove_tree(&home)?;
            finished
        }
    }

    /// Real `FileChanged` → `reset()` → rebuilt private sidecar → resume retry.
    ///
    /// The peer deliberately answers a conditional range with a validator the
    /// client does not hold (a real hazard), so the downloader must notice the
    /// changed representation, discard its resume state and start over. After the
    /// retry budget is exhausted the transfer has to keep a non-zero `.part` plus a
    /// freshly rebuilt `0600` sidecar carrying the new validator. A second
    /// operation on the same frozen descriptor must then resume instead of
    /// downloading from zero.
    fn sidecar_reset_retry(
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
    ) -> Result<Value> {
        let version = "1.12.0";
        let url = fixed_archive_url()?;
        let etag_a = format!("\"sidecar-a-{version}\"");
        let etag_b = format!("\"sidecar-b-{version}\"");
        let drop_step = |etag: &str| ArchiveStep {
            etag: Some(etag.to_owned()),
            drop_after_bytes: Some(262_144),
        };
        let mut broken = control_with(
            paths,
            &paths.large_program,
            ArchiveVariant::Normal,
            65_536,
            None,
            // A short real delay keeps the dropped body observable: with no delay the
            // abort can reach the client before it consumed any frame, so no resume
            // state would exist and the case would test nothing.
            20,
        );
        broken.archive.etag = Some(etag_a.clone());
        // 1: full body with A, aborted. 2: the conditional range is answered with B
        // (changed representation) and aborted. 3..: the client restarts from zero
        // and keeps getting aborted until its retry budget is spent.
        broken.archive.script = vec![
            drop_step(&etag_a),
            drop_step(&etag_b),
            drop_step(&etag_b),
            drop_step(&etag_b),
            drop_step(&etag_b),
            drop_step(&etag_b),
        ];
        let before = paths.installed_ids()?;
        // Other cases legitimately keep their own partials in the shared home (the
        // shutdown lifecycle does), so this case records them first and only claims
        // the entries it creates itself.
        // sentinel 必须在基线快照**之前**落盘：它属于“未知产物”，后续只允许不变。
        let sentinel = seed_unknown_sentinel(&paths.home(), &paths.target)?;
        let sentinel_for_report = sentinel.clone();
        let downloads_before = download_entries(paths)?;
        let env = CaseEnv::open(paths, client, server_binary, &broken)?;
        let CaseEnv {
            peer,
            mut server,
            archive_sha,
            ..
        } = env;
        // 固定发行只有一条路径：不能用本 case 自己的标签拼出“另一个版本”的 URL。
        let suffix = fixed_archive_path()?;
        let first = (|| -> Result<Value> {
            start(client, &server.base(), "observe-sidecar-reset")?;
            let failed = wait_terminal(client, &server.base(), Duration::from_secs(180))?;
            let observed = expect_failed(&failed, "network")?;
            ensure!(
                paths.installed_ids()? == before,
                "the failed retry operation published an installation"
            );
            ensure!(
                !account_saved(&paths.home())?,
                "an ACP account was saved before the installation completed"
            );
            let requests = peer_requests(&paths.peer)?;
            let archive: Vec<&Value> = requests
                .iter()
                .filter(|record| {
                    record["path"]
                        .as_str()
                        .is_some_and(|path| path.ends_with(suffix.as_str()))
                })
                .collect();
            let drops = requests
                .iter()
                .filter(|record| record["kind"].as_str() == Some("archiveDrop"))
                .count();
            // The product allows three automatic retries, so this scripted lifecycle
            // must issue exactly four archive requests and drop four bodies; a
            // different count means the retry contract or the scripted peer changed.
            ensure!(
                archive.len() == 4 && drops == 4,
                "expected 4 archive requests and 4 dropped bodies, observed {} and {}",
                archive.len(),
                drops
            );
            // Order matters: full body with A, then the conditional range answered
            // with B (the representation change), then a restart from zero with B,
            // and every later attempt resumes on B.
            ensure!(
                archive[0]["range"].is_null()
                    && archive[0]["status"].as_u64() == Some(200)
                    && archive[0]["etag"].as_str() == Some(etag_a.as_str()),
                "request 1 was not a full body carrying the original validator"
            );
            ensure!(
                archive[1]["status"].as_u64() == Some(206)
                    && archive[1]["ifRange"].as_str() == Some(etag_a.as_str())
                    && archive[1]["etag"].as_str() == Some(etag_b.as_str())
                    && archive[1]["range"]
                        .as_str()
                        .and_then(range_start)
                        .is_some_and(|start| start > 0),
                "request 2 was not the conditional range answered with the changed validator"
            );
            ensure!(
                archive[2]["range"].is_null()
                    && archive[2]["status"].as_u64() == Some(200)
                    && archive[2]["etag"].as_str() == Some(etag_b.as_str()),
                "request 3 was not the restart from zero with the new validator"
            );
            ensure!(
                archive[3]["status"].as_u64() == Some(206)
                    && archive[3]["ifRange"].as_str() == Some(etag_b.as_str())
                    && archive[3]["etag"].as_str() == Some(etag_b.as_str())
                    && archive[3]["range"]
                        .as_str()
                        .and_then(range_start)
                        .is_some_and(|start| start > 0),
                "request 4 was not the final conditional retry on the new validator"
            );
            let downloads_after = download_entries(paths)?;
            // The shared home may already hold other cases' partials (the shutdown
            // lifecycle does): they have to stay byte-identical, and only this
            // lifecycle's descriptor key may appear.
            for (name, facts) in &downloads_before {
                ensure!(
                    downloads_after.get(name) == Some(facts),
                    "the earlier partial download `{name}` changed during this lifecycle"
                );
            }
            let fresh: Vec<&String> = downloads_after
                .keys()
                .filter(|name| !downloads_before.contains_key(*name))
                .collect();
            ensure!(
                fresh.len() == 2,
                "expected one new partial download and its sidecar, found {}",
                fresh.len()
            );
            let mut part: Option<(String, u64, u32, String)> = None;
            let mut sidecar: Option<(String, u64, u32, String)> = None;
            for name in &fresh {
                let (bytes, mode, digest) = &downloads_after[*name];
                if let Some(key) = name.strip_suffix(".zip.part") {
                    part = Some((key.to_owned(), *bytes, *mode, digest.clone()));
                } else if let Some(key) = name.strip_suffix(".zip.downloadinfo") {
                    sidecar = Some((key.to_owned(), *bytes, *mode, digest.clone()));
                }
            }
            let (part_key, part_bytes, part_mode, part_digest) =
                part.context("the interrupted lifecycle kept no partial download")?;
            let (sidecar_key, sidecar_bytes, sidecar_mode, sidecar_digest) =
                sidecar.context("the interrupted lifecycle kept no resume sidecar")?;
            ensure!(
                part_key == sidecar_key,
                "the partial `{part_key}` and its sidecar `{sidecar_key}` name different keys"
            );
            let sidecar_text = fs::read_to_string(
                paths
                    .downloads_dir()
                    .join(format!("{sidecar_key}.zip.downloadinfo")),
            )?;
            ensure!(
                sidecar_text.contains(etag_b.as_str()),
                "the rebuilt resume sidecar does not carry the new validator"
            );
            // Deterministic for this scripted peer: 64 KiB chunks with 20 ms pacing,
            // drops at 256 KiB and the three-retry budget always leave six consumed
            // chunks and the same serialized sidecar.
            ensure!(
                part_bytes == 393_216,
                "the interrupted transfer kept {part_bytes} bytes instead of the deterministic 393216"
            );
            ensure!(
                sidecar_bytes == 46,
                "the rebuilt sidecar is {sidecar_bytes} bytes instead of the deterministic 46"
            );
            #[cfg(unix)]
            {
                ensure!(
                    part_mode == 0o600,
                    "the partial download is {part_mode:04o} instead of 0600"
                );
                ensure!(
                    sidecar_mode == 0o600,
                    "the rebuilt sidecar is {sidecar_mode:04o} instead of 0600"
                );
            }
            Ok(json!({
                "failed": observed,
                "archiveRequests": archive.len(),
                "drops": drops,
                "sequence": archive.iter().map(|record| json!({
                    "range": record["range"].clone(),
                    "ifRange": record["ifRange"].clone(),
                    "status": record["status"].clone(),
                    "etag": record["etag"].clone(),
                })).collect::<Vec<_>>(),
                "part": {
                    "key": part_key,
                    "bytes": part_bytes,
                    "mode": format!("{part_mode:04o}"),
                    "sha256": part_digest,
                },
                "sidecar": {
                    "bytes": sidecar_bytes,
                    "mode": format!("{sidecar_mode:04o}"),
                    "sha256": sidecar_digest,
                    "carriesNewValidator": true,
                },
                "otherPartialsUnchanged": downloads_before.len(),
                // 未知产物（固定内容/0600）逐个逐字节核对未变：内容、长度与模式都在
                // `downloads_before`/`downloads_after` 的比较范围内。
                "sentinel": sentinel_for_report,
                "accountSaved": false,
            }))
        })();
        let stop = server.stop();
        let peer_facts = peer.stop(&paths.peer);
        let first = first?;
        stop?;
        peer_facts?;
        let part_key = first["part"]["key"]
            .as_str()
            .context("the failed operation kept no partial download")?
            .to_owned();
        let part_bytes = first["part"]["bytes"]
            .as_u64()
            .context("the failed operation reported no partial length")?;
        // Same frozen descriptor, now answered completely with the new validator.
        let mut healthy = control_with(
            paths,
            &paths.large_program,
            ArchiveVariant::Normal,
            262_144,
            None,
            0,
        );
        healthy.archive.etag = Some(etag_b.clone());
        // 固定 1.4.1 没有发行方摘要，也没有可发布 argv：产品 ready 只能报固定版本。
        let env = CaseEnv::open(paths, client, server_binary, &healthy)?;
        let expected: Vec<Value> = env
            .peer
            .ready
            .get("members")
            .and_then(Value::as_array)
            .cloned()
            .context("the peer ready document has no member list")?;
        let archive_bytes = env.peer.archive_bytes()?;
        let second = (|| -> Result<Value> {
            start(client, &env.base(), "observe-sidecar-retry")?;
            let ready = wait_terminal(client, &env.base(), Duration::from_secs(300))?;
            let observed = expect_ready(&ready)?;
            let key = storage_key(&observed.wire_id)?;
            let release = &observed.json["release"];
            ensure!(
                release["version"].as_str() == Some(fixed::SERVER_VERSION),
                "the ready release names another version than the fixed 1.4.1"
            );
            ensure!(
                release["target"].as_str() == Some(paths.target.as_str()),
                "the ready release names another platform target"
            );
            ensure!(
                release["archiveUrl"].as_str() == Some(url.as_str()),
                "the ready release names another archive URL"
            );
            ensure!(
                release["sha256"].is_null(),
                "the ready release carries a publisher digest the fixed release never publishes"
            );
            let expected_program = paths
                .installed_dir(&key)
                .join(PROGRAM_MEMBER)
                .to_string_lossy()
                .into_owned();
            ensure!(
                observed.json["program"].as_str() == Some(expected_program.as_str()),
                "the ready command is not the published program entry"
            );
            ensure!(
                observed.json.get("args").is_none(),
                "the ready entry still exposes a launch argv; the DTO only carries the read-only program"
            );
            ensure!(
                observed.json["reused"].as_bool() == Some(false),
                "the retry publication reports reuse instead of a fresh install"
            );
            verify_publication(
                paths,
                &key,
                &observed,
                &archive_sha,
                &expected,
                &paths.large_program,
            )?;
            let requests = peer_requests(&paths.peer)?;
            let archive: Vec<&Value> = requests
                .iter()
                .filter(|record| {
                    record["path"]
                        .as_str()
                        .is_some_and(|path| path.ends_with(suffix.as_str()))
                })
                .collect();
            ensure!(
                archive.len() == 1,
                "the retry operation issued {} archive requests instead of one resume",
                archive.len()
            );
            let resumed = archive[0];
            ensure!(
                resumed["status"].as_u64() == Some(206),
                "the retry operation was not answered with a partial content response"
            );
            ensure!(
                resumed["range"].as_str().and_then(range_start) == Some(part_bytes),
                "the retry did not resume exactly at the interrupted partial length ({part_bytes})"
            );
            ensure!(
                resumed["ifRange"].as_str() == Some(etag_b.as_str()),
                "the retry did not send the rebuilt validator"
            );
            ensure!(
                resumed["etag"].as_str() == Some(etag_b.as_str()),
                "the resumed response carries another validator"
            );
            let expected_range =
                format!("bytes {part_bytes}-{}/{archive_bytes}", archive_bytes - 1);
            ensure!(
                resumed["contentRange"].as_str() == Some(expected_range.as_str()),
                "the resumed response content range does not match the interrupted length"
            );
            ensure!(
                !account_saved(&paths.home())?,
                "an ACP account was saved by a preparation-only operation"
            );
            Ok(json!({ "ready": observed.json, "key": key }))
        })();
        let mut value = finish("sidecar-reset-retry", &paths.peer, env, second)?;
        ensure!(
            value["key"].as_str() == Some(part_key.as_str()),
            "the retry operation published another descriptor than the interrupted transfer"
        );
        let first_operation = first["failed"]["operationId"].as_str();
        let second_operation = value["ready"]["operationId"].as_str();
        ensure!(
            first_operation.is_some()
                && second_operation.is_some()
                && first_operation != second_operation,
            "both operations reported the same identity"
        );
        ensure!(
            value["ready"]["release"]["version"].as_str() == Some(fixed::SERVER_VERSION)
                && value["ready"]["release"]["archiveUrl"].as_str() == Some(url.as_str()),
            "the retry operation resolved another release"
        );
        if let Some(object) = value.as_object_mut() {
            object.insert("interrupted".to_owned(), first);
        }
        Ok(value)
    }

    /// 预置一个**未知**的下载残留：独立的 64 位十六进制 key，part 与 sidecar 都是
    /// 固定内容、0600 权限。
    ///
    /// 它只用于证明“产品不会动别人的未知产物”，**不**声称这是另一个可安装版本：
    /// 固定发行只有 1.4.1，测试没有权限制造第二种 descriptor。
    fn seed_unknown_sentinel(home: &Path, target: &str) -> Result<Value> {
        use std::os::unix::fs::{DirBuilderExt as _, PermissionsExt as _};
        let key = "5e17e1e15e17e1e15e17e1e15e17e1e15e17e1e15e17e1e15e17e1e15e17e1e1";
        let downloads = home
            .join("studio/acp-servers/downloads")
            .join(PROVIDER)
            .join(target);
        // 受管目录必须是 0700：用默认 umask 创建会让产品在 waitForLock 阶段以
        // ACL 不合格失败，sentinel 就变成了在测自己的权限。
        fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(&downloads)?;
        let part = downloads.join(format!("{key}.zip.part"));
        let sidecar = downloads.join(format!("{key}.zip.downloadinfo"));
        let part_bytes = b"synthetic unknown partial that no descriptor owns\n";
        let sidecar_bytes = b"synthetic unknown resume sidecar\n";
        fs::write(&part, part_bytes)?;
        fs::write(&sidecar, sidecar_bytes)?;
        fs::set_permissions(&part, fs::Permissions::from_mode(0o600))?;
        fs::set_permissions(&sidecar, fs::Permissions::from_mode(0o600))?;
        Ok(json!({
            "syntheticSentinel": true,
            "key": key,
            "part": {
                "bytes": part_bytes.len(),
                "mode": "0600",
                "sha256": file_sha256(&part)?,
            },
            "sidecar": {
                "bytes": sidecar_bytes.len(),
                "mode": "0600",
                "sha256": file_sha256(&sidecar)?,
            },
        }))
    }

    /// Every partial download and resume sidecar currently present, with the full
    /// content identity (length, real mode and the existing file digest).
    ///
    /// Keyed by file name so a case can prove which entries it created while the
    /// earlier cases' own partials in the shared home stay untouched.
    fn download_entries(paths: &Paths) -> Result<BTreeMap<String, (u64, u32, String)>> {
        let downloads = paths.downloads_dir();
        let mut entries = BTreeMap::new();
        if downloads.is_dir() {
            for entry in fs::read_dir(&downloads)? {
                let entry = entry?;
                let name = entry.file_name().to_string_lossy().into_owned();
                if name.ends_with(".zip.part") || name.ends_with(".zip.downloadinfo") {
                    let metadata = entry.metadata()?;
                    let digest = file_sha256(&entry.path())?;
                    entries.insert(name, (metadata.len(), mode_of(&metadata), digest));
                }
            }
        }
        Ok(entries)
    }

    /// Whether any ACP account was saved in this isolated home.
    fn account_saved(home: &Path) -> Result<bool> {
        let path = home.join("config.toml");
        if !path.is_file() {
            return Ok(false);
        }
        Ok(fs::read_to_string(&path)?.contains("acpAccounts"))
    }

    /// 该 peer 生命周期里的全部证据记录（严格解析；空白行/未知种类/结构错误失败）。
    fn peer_requests(peer: &Path) -> Result<Vec<Value>> {
        peer_log_records(peer)
    }

    fn cache_corrupt(
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
    ) -> Result<Value> {
        let control = control(paths, ArchiveVariant::Normal, 262_144, None, 0);
        let env = CaseEnv::open(paths, client, server_binary, &control)?;
        let archive_sha = env.archive_sha.clone();
        let expected_members: Vec<Value> = env
            .peer
            .ready
            .get("members")
            .and_then(Value::as_array)
            .cloned()
            .context("the peer ready document has no member list")?;
        let outcome = (|| -> Result<Value> {
            start(client, &env.base(), "observe-cache-first")?;
            let ready = wait_terminal(client, &env.base(), Duration::from_secs(300))?;
            let observed = expect_ready(&ready)?;
            let key = storage_key(&observed.wire_id)?;
            verify_publication(
                paths,
                &key,
                &observed,
                &archive_sha,
                &expected_members,
                &paths.program,
            )?;
            let directory = paths.installed_dir(&key);
            let receipt_path = directory.join("receipt.json");
            let original = read_json(&receipt_path)?;
            let before = member_hashes(&directory, &["receipt.json"])?;
            // Corrupt the published receipt; its members stay byte-identical so a
            // silent repair-by-overwrite would be visible.
            let mut corrupted = original.clone();
            corrupted["installationId"] = Value::String("corrupted".to_owned());
            fs::write(&receipt_path, serde_json::to_vec_pretty(&corrupted)?)?;
            start(client, &env.base(), "observe-cache-reuse")?;
            let state = wait_terminal(client, &env.base(), Duration::from_secs(120))?;
            let failure = expect_failed(&state, "cacheCorrupt")?;
            ensure!(
                receipt_path.is_file()
                    && read_json(&receipt_path)?["installationId"].as_str() == Some("corrupted"),
                "the corrupted installation was repaired or removed instead of preserved"
            );
            ensure!(
                member_hashes(&directory, &["receipt.json"])? == before,
                "the corrupted installation members were silently rewritten"
            );
            Ok(json!({
                "installationKey": key,
                "wireId": observed.wire_id,
                "failure": failure,
                "preservedMembers": before.len(),
            }))
        })();
        finish("cache-corrupt", &paths.peer, env, outcome)
    }

    fn lock_wait(paths: &Paths, client: &Client, server_binary: Option<&Path>) -> Result<Value> {
        let control = control(paths, ArchiveVariant::Normal, 65_536, None, 0);
        let env = CaseEnv::open(paths, client, server_binary, &control)?;
        let lock_path = paths.lock_path();
        let mut holder = LockHolder::acquire(&lock_path)?;
        let held_by = Instant::now() + Duration::from_secs(10);
        while lock_is_free(&lock_path)? {
            ensure!(
                holder.running() && Instant::now() < held_by,
                "the asset lock holder never acquired the lock"
            );
            std::thread::sleep(Duration::from_millis(50));
        }
        let before = downloads(paths)?;
        let outcome = (|| -> Result<Value> {
            start(client, &env.base(), "observe-lock-wait")?;
            let waiting = poll_until(client, &env.base(), Duration::from_secs(60), |state| {
                matches!(state, AcpInstallState::Waiting { .. })
            })?;
            ensure!(
                downloads(paths)? == before,
                "the waiting operation started downloading before the lock was available"
            );
            cancel(
                client,
                &env.base(),
                "observe-lock-cancel",
                "observe-lock-wait",
            )?;
            let cancelled = wait_terminal(client, &env.base(), Duration::from_secs(60))?;
            ensure!(
                matches!(cancelled, AcpInstallState::Cancelled { .. }),
                "the waiting operation did not end in Cancelled"
            );
            ensure!(
                holder.running() && !lock_is_free(&lock_path)?,
                "the waiting cancellation stole the holder's lock"
            );
            ensure!(
                downloads(paths)? == before,
                "the cancelled waiting operation wrote a partial download"
            );
            Ok(json!({
                "waiting": observe(&waiting),
                "cancelled": observe(&cancelled),
                "holderKeptLock": true,
            }))
        })();
        holder.release()?;
        let released_by = Instant::now() + Duration::from_secs(10);
        while !lock_is_free(&lock_path)? {
            ensure!(
                Instant::now() < released_by,
                "the asset lock stayed held after the observer released it"
            );
            std::thread::sleep(Duration::from_millis(50));
        }
        finish("lock-wait", &paths.peer, env, outcome)
    }

    /// Shutdown during a real download, bound to this descriptor's storage key.
    ///
    /// The key is derived by the product from the frozen registry descriptor
    /// (version/target/URL/digest/argv), so acceptance learns it from a *completed*
    /// install of the identical descriptor with fast chunks, removes that
    /// publication and its archive, and only then performs the slow download that
    /// is interrupted. The in-flight `.part` must carry that same key, which binds
    /// the stopped transfer to the descriptor instead of "some new file".
    fn shutdown_download(
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
    ) -> Result<Value> {
        let url = fixed_archive_url()?;
        let warm = warm_storage_key(paths, client, server_binary, &url)?;
        let key = warm["key"]
            .as_str()
            .context("the warm pass reported no storage key")?
            .to_owned();
        // Drop the warm publication and its archive sidecars, so the interrupted
        // pass is a fresh download of the same descriptor.
        remove_tree(&paths.installed_dir(&key))?;
        for suffix in [".zip", ".zip.part", ".zip.downloadinfo"] {
            remove_file_if_present(&paths.downloads_dir().join(format!("{key}{suffix}")))?;
        }
        let control = control_with(
            paths,
            &paths.large_program,
            ArchiveVariant::Normal,
            32_768,
            None,
            15,
        );
        let env = CaseEnv::open(paths, client, server_binary, &control)?;
        let CaseEnv {
            peer,
            mut server,
            archive_sha,
            archive_bytes,
        } = env;
        let before = downloads(paths)?;
        let group = server.group;
        let mut stopped = false;
        let outcome = (|| -> Result<(Value, String, u64, u64)> {
            start(client, &server.base(), "observe-shutdown")?;
            let downloading =
                poll_until(client, &server.base(), Duration::from_secs(120), |state| {
                    matches!(
                        state,
                        AcpInstallState::Downloading { operation_id, release, progress, .. }
                            if operation_id == "observe-shutdown"
                                && release.version == fixed::SERVER_VERSION
                                && release.target == paths.target
                                && release.archive_url == url
                                && release.sha256.is_none()
                                && progress.completed_bytes > 0
                                && progress
                                    .total_bytes
                                    .is_some_and(|total| progress.completed_bytes < total)
                    )
                })?;
            let (partial_key, partial) = current_partial(paths, &before)?;
            ensure!(
                partial_key == key,
                "the in-flight partial `{partial_key}` does not belong to this descriptor's key `{key}`"
            );
            ensure!(
                partial > 0 && partial < archive_bytes,
                "the download was not really in flight at shutdown ({partial}/{archive_bytes})"
            );
            let exit = server.stop()?;
            stopped = true;
            ensure!(
                exit.success(),
                "the server did not exit cleanly during the download: {exit}"
            );
            // Two measurements *after* the real exit prove the transfer stopped;
            // the bytes written while the ordered shutdown was still running are
            // expected and must not be confused with post-exit writes.
            let stopped_at = fs::metadata(paths.downloads_dir().join(format!("{key}.zip.part")))
                .map(|meta| meta.len())
                .unwrap_or(0);
            std::thread::sleep(Duration::from_millis(500));
            let after = fs::metadata(paths.downloads_dir().join(format!("{key}.zip.part")))
                .map(|meta| meta.len())
                .unwrap_or(0);
            ensure!(
                after == stopped_at,
                "the partial download kept writing after the server exited ({stopped_at} -> {after})"
            );
            ensure!(
                after < archive_bytes,
                "the interrupted download completed instead of stopping ({after}/{archive_bytes})"
            );
            ensure!(
                !paths.downloads_dir().join(format!("{key}.zip")).exists(),
                "the interrupted download was reported as a completed archive"
            );
            let deadline = Instant::now() + Duration::from_secs(30);
            while !lock_is_free(&paths.lock_path())? {
                ensure!(
                    Instant::now() < deadline,
                    "the asset lock was not released by the shutdown"
                );
                std::thread::sleep(Duration::from_millis(50));
            }
            let leftovers = residents_in_group(group);
            ensure!(
                leftovers.is_empty(),
                "the isolated server left descendants in its process group: {leftovers:?}"
            );
            Ok((observe(&downloading), partial_key, partial, after))
        })();
        // Always reclaim both owners: the peer is stopped exactly once, and the
        // server is only stopped here when the case failed before its own stop.
        let report = peer.stop(&paths.peer);
        let cleanup = if stopped || server.child.try_wait().ok().flatten().is_some() {
            Ok(None)
        } else {
            server.stop().map(Some)
        };
        let (observed, partial_key, partial, after) = outcome?;
        let report = report?;
        if let Err(error) = cleanup {
            bail!("the shutdown case could not reclaim the server: {error:#}");
        }
        Ok(json!({
            "case": "shutdown-download",
            "downloading": observed,
            "storageKey": partial_key,
            "warm": warm,
            "partialBytesBefore": partial,
            "partialBytesAfter": after,
            "lockReleased": true,
            "serverGroupEmpty": residents_in_group(group).is_empty(),
            "serverExit": "clean",
            "archiveSha256": archive_sha,
            "archiveBytes": archive_bytes,
            "peer": report,
        }))
    }

    /// Learns the product's storage key for one frozen descriptor.
    ///
    /// A completed install of the identical descriptor with fast chunks reports the
    /// wire `installationId`; its 64-hex part is the storage key the product also
    /// uses for downloads, locks and receipts. This pass is fully reclaimed and its
    /// caller removes the publication before the interrupted pass runs.
    fn warm_storage_key(
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
        url: &str,
    ) -> Result<Value> {
        let control = control_with(
            paths,
            &paths.large_program,
            ArchiveVariant::Normal,
            1 << 20,
            None,
            0,
        );
        let env = CaseEnv::open(paths, client, server_binary, &control)?;
        let CaseEnv {
            peer,
            mut server,
            archive_bytes,
            ..
        } = env;
        let outcome = (|| -> Result<Value> {
            start(client, &server.base(), "observe-shutdown-warm")?;
            let ready = wait_terminal(client, &server.base(), Duration::from_secs(300))?;
            let AcpInstallState::Ready { server, .. } = ready else {
                bail!("the warm install never became ready: {}", observe(&ready));
            };
            let hex = server
                .installation_id
                .strip_prefix("sha256:")
                .context("the warm installation identity is not a wire value")?;
            ensure!(
                hex.len() == 64
                    && hex
                        .bytes()
                        .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte)),
                "the warm installation identity is not a storage key"
            );
            ensure!(
                server.release.version == fixed::SERVER_VERSION
                    && server.release.archive_url == url
                    && server.release.sha256.is_none(),
                "the warm install froze another descriptor"
            );
            Ok(json!({
                "key": hex,
                "installationId": server.installation_id,
                "release": release_json(&server.release),
                "archiveBytes": archive_bytes,
            }))
        })();
        let stop = server.stop();
        let peer_facts = peer.stop(&paths.peer);
        let value = outcome?;
        stop?;
        peer_facts?;
        Ok(value)
    }

    /// Creates one product-managed ancestor with the exact private mode the product
    /// requires, independent of the host umask, and returns the observed mode.
    #[cfg(unix)]
    fn create_private_ancestor(path: &Path) -> Result<u32> {
        use std::os::unix::fs::{DirBuilderExt, PermissionsExt};

        let mut builder = fs::DirBuilder::new();
        builder.mode(0o700);
        builder
            .create(path)
            .with_context(|| format!("failed to create the directory {}", path.display()))?;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
        let mode = mode_of(&fs::metadata(path)?);
        ensure!(
            mode == 0o700,
            "the acceptance created the managed ancestor {} with {mode:04o} instead of 0700",
            path.display()
        );
        Ok(mode)
    }

    /// Creates the deliberately wide target directory and returns its observed mode.
    #[cfg(unix)]
    fn create_wide_target(path: &Path) -> Result<u32> {
        use std::os::unix::fs::{DirBuilderExt, PermissionsExt};

        let mut builder = fs::DirBuilder::new();
        builder.mode(0o777);
        builder
            .create(path)
            .with_context(|| format!("failed to create the directory {}", path.display()))?;
        fs::set_permissions(path, fs::Permissions::from_mode(0o777))?;
        let mode = mode_of(&fs::metadata(path)?);
        ensure!(
            mode == 0o777,
            "the deliberate wide target {} is {mode:04o} instead of 0777",
            path.display()
        );
        Ok(mode)
    }

    /// File facts of every published installation under one explicit home.
    fn installed_fingerprint(
        home: &Path,
        target: &str,
    ) -> Result<BTreeMap<String, BTreeMap<String, String>>> {
        let mut fingerprint = BTreeMap::new();
        for key in installed_ids_in(home, target)? {
            let directory = home
                .join("studio/acp-servers/installed")
                .join(PROVIDER)
                .join(target)
                .join(&key);
            fingerprint.insert(key, member_hashes(&directory, &[])?);
        }
        Ok(fingerprint)
    }

    /// Published installation keys under one explicit home.
    fn installed_ids_in(home: &Path, target: &str) -> Result<Vec<String>> {
        let directory = home
            .join("studio/acp-servers/installed")
            .join(PROVIDER)
            .join(target);
        let mut ids = Vec::new();
        if directory.is_dir() {
            for entry in fs::read_dir(directory)? {
                let entry = entry?;
                if entry.file_type()?.is_dir() {
                    ids.push(entry.file_name().to_string_lossy().into_owned());
                }
            }
        }
        ids.sort();
        Ok(ids)
    }

    fn remove_tree(path: &Path) -> Result<()> {
        match fs::remove_dir_all(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error).with_context(|| format!("failed to clear {}", path.display())),
        }
    }

    fn remove_file_if_present(path: &Path) -> Result<()> {
        match fs::remove_file(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error).with_context(|| format!("failed to clear {}", path.display())),
        }
    }

    fn current_partial(paths: &Paths, before: &BTreeMap<String, u64>) -> Result<(String, u64)> {
        let after = downloads(paths)?;
        let new: Vec<(&String, &u64)> = after
            .iter()
            .filter(|(key, _)| !before.contains_key(*key))
            .collect();
        ensure!(
            new.len() == 1,
            "expected exactly one partial download for the active operation, found {}",
            new.len()
        );
        Ok((new[0].0.clone(), *new[0].1))
    }

    fn downloads(paths: &Paths) -> Result<BTreeMap<String, u64>> {
        let mut parts = BTreeMap::new();
        let directory = paths.downloads_dir();
        if !directory.is_dir() {
            return Ok(parts);
        }
        for entry in fs::read_dir(directory)? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().into_owned();
            if let Some(key) = name.strip_suffix(".zip.part") {
                parts.insert(
                    key.to_owned(),
                    entry.metadata().map(|meta| meta.len()).unwrap_or(0),
                );
            }
        }
        Ok(parts)
    }

    fn residents_in_group(group: u32) -> Vec<u32> {
        let mut residents = Vec::new();
        let Ok(entries) = fs::read_dir("/proc") else {
            return residents;
        };
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let Ok(pid) = name.parse::<u32>() else {
                continue;
            };
            let Ok(stat) = fs::read_to_string(entry.path().join("stat")) else {
                continue;
            };
            let Some(close) = stat.rfind(')') else {
                continue;
            };
            let fields: Vec<&str> = stat[close + 1..].split_whitespace().collect();
            if fields.get(2).and_then(|value| value.parse::<u32>().ok()) == Some(group) {
                residents.push(pid);
            }
        }
        residents
    }

    struct Observed {
        wire_id: String,
        json: Value,
    }

    fn expect_ready(state: &AcpInstallState) -> Result<Observed> {
        let AcpInstallState::Ready {
            operation_id,
            server,
        } = state
        else {
            bail!("the operation did not end in Ready: {}", observe(state));
        };
        ensure!(
            server.program.ends_with(PROGRAM_MEMBER),
            "the published program is not the declared entry: {}",
            server.program
        );
        Ok(Observed {
            wire_id: server.installation_id.clone(),
            json: json!({
                "phase": "ready",
                "operationId": operation_id,
                "installationId": server.installation_id,
                "program": server.program,
                "reused": server.reused,
                "release": release_json(&server.release),
            }),
        })
    }

    fn release_json(release: &pl_protocol::studio::AcpInstallRelease) -> Value {
        json!({
            "version": release.version,
            "target": release.target,
            "archiveUrl": release.archive_url,
            "sha256": release.sha256,
        })
    }

    fn expect_failed(state: &AcpInstallState, expected: &str) -> Result<Value> {
        let AcpInstallState::Failed {
            operation_id,
            failure,
        } = state
        else {
            bail!("the operation did not end in Failed: {}", observe(state));
        };
        ensure!(
            failure.code.label() == expected,
            "the operation failed with `{}` at stage `{}` instead of `{expected}`",
            failure.code.label(),
            failure.stage.label()
        );
        Ok(json!({
            "phase": "failed",
            "operationId": operation_id,
            "code": failure.code.label(),
            "stage": failure.stage.label(),
            "retryable": failure.retryable,
        }))
    }

    /// Typed observation without Debug strings.
    fn observe(state: &AcpInstallState) -> Value {
        match state {
            AcpInstallState::Idle => json!({ "phase": "idle" }),
            AcpInstallState::Ready {
                operation_id,
                server,
            } => json!({
                "phase": "ready",
                "operationId": operation_id,
                "installationId": server.installation_id,
                "program": server.program,
                "reused": server.reused,
            }),
            AcpInstallState::Failed {
                operation_id,
                failure,
            } => json!({
                "phase": "failed",
                "operationId": operation_id,
                "code": failure.code.label(),
                "stage": failure.stage.label(),
                "retryable": failure.retryable,
            }),
            AcpInstallState::Cancelled { operation_id } => {
                json!({ "phase": "cancelled", "operationId": operation_id })
            }
            AcpInstallState::Cancelling { operation_id } => {
                json!({ "phase": "cancelling", "operationId": operation_id })
            }
            AcpInstallState::Waiting {
                operation_id,
                release,
            } => json!({
                "phase": "waiting",
                "operationId": operation_id,
                "release": release_json(release),
            }),
            AcpInstallState::Downloading {
                operation_id,
                release,
                progress,
                retry_count,
            } => json!({
                "phase": "downloading",
                "operationId": operation_id,
                "release": release_json(release),
                "completedBytes": progress.completed_bytes,
                "totalBytes": progress.total_bytes,
                "retryCount": retry_count,
            }),
            AcpInstallState::Verifying { operation_id, .. } => {
                json!({ "phase": "verifying", "operationId": operation_id })
            }
            AcpInstallState::Extracting { operation_id, .. } => {
                json!({ "phase": "extracting", "operationId": operation_id })
            }
            AcpInstallState::Publishing { operation_id, .. } => {
                json!({ "phase": "publishing", "operationId": operation_id })
            }
            AcpInstallState::Closing { operation_id, .. } => {
                json!({ "phase": "closing", "operationId": operation_id })
            }
            AcpInstallState::Resolving { operation_id } => {
                json!({ "phase": "resolving", "operationId": operation_id })
            }
        }
    }

    // ---------------------------------------------------------------- auth ----
    //
    // 非 GUI 的认证判定：直接走 server 的真实 HTTP 命令与真实 ACP 子进程，
    // 不经过 GUI/Driver。四种边界都属于产品契约本身：缺安装、安装损坏、
    // 旧配置字段、以及 server 版本不符；最后一个还必须证明**没有**向不合格的
    // server 发送 authenticate / session/new。

    /// 认证类 case 的包内程序：`pl-provider-fixture` 自身。
    ///
    /// 只有它会以官方 basename + 固定 argv 进入 packaged 模式；`/usr/bin/true`
    /// 这类替身只能证明安装形状，用来跑认证会得到 transport 而不是协议判定。
    fn fixture_agent_program(paths: &Paths) -> Result<PathBuf> {
        let binary = paths.workspace.join("target/debug/pl-provider-fixture");
        if !binary.is_file() {
            let status = Command::new("cargo")
                .current_dir(&paths.workspace)
                .args([
                    "build",
                    "-p",
                    "pl-provider-fixture",
                    "--bin",
                    "pl-provider-fixture",
                ])
                .status()
                .context("failed to build the fixture agent")?;
            ensure!(
                status.success(),
                "building pl-provider-fixture failed: {status}"
            );
        }
        ensure!(
            binary.is_file(),
            "the fixture agent binary is missing: {}",
            binary.display()
        );
        Ok(binary)
    }

    fn get_json(client: &Client, url: &str) -> Result<Value> {
        let response = client
            .get(url)
            .send()
            .with_context(|| format!("GET {url} failed"))?;
        ensure!(
            response.status().is_success(),
            "GET {url} answered {}",
            response.status()
        );
        Ok(response.json()?)
    }

    fn settings_revision(client: &Client, base: &str) -> Result<u64> {
        Ok(
            get_json(client, &format!("{base}/api/v1/settings"))?["config"]["revision"]
                .as_u64()
                .unwrap_or(0),
        )
    }

    /// 保存一条只含 name/provider 的 ACP 账号（现役结构没有 program/args）。
    fn save_account(
        client: &Client,
        base: &str,
        operation: &str,
        account: &str,
        name: &str,
    ) -> Result<()> {
        let body = json!({
            "operationId": operation,
            "expectedRevision": settings_revision(client, base)?,
            "account": { "accountId": account, "name": name, "provider": PROVIDER },
        });
        let response = client
            .put(format!("{base}/api/v1/settings/acp-account"))
            .json(&body)
            .send()
            .context("save account request failed")?;
        ensure!(
            response.status().is_success(),
            "save account answered {}: {}",
            response.status(),
            response.text().unwrap_or_default()
        );
        Ok(())
    }

    /// 一次只读认证检查：命令返回受理回执，终态通过 ACP 认证快照观察。
    fn start_auth_check(client: &Client, base: &str, operation: &str, account: &str) -> Result<()> {
        let snapshot = get_json(client, &format!("{base}/api/v1/runtime/acp-auth"))?;
        let revision = snapshot["accounts"]
            .as_array()
            .and_then(|accounts| {
                accounts
                    .iter()
                    .find(|entry| entry["accountId"].as_str() == Some(account))
            })
            .and_then(|entry| entry["connectionRevision"].as_u64())
            .unwrap_or(0);
        let body = json!({
            "operationId": operation,
            "accountId": account,
            "expectedConnectionRevision": revision,
            // `AcpAuthAction` 自带 `action` 标签，因此字段值本身也带同一标签。
            "action": { "action": "check" },
        });
        let response = client
            .post(format!("{base}/api/v1/runtime/acp-auth/start"))
            .json(&body)
            .send()
            .context("auth start request failed")?;
        ensure!(
            response.status().is_success(),
            "auth start answered {}: {}",
            response.status(),
            response.text().unwrap_or_default()
        );
        Ok(())
    }

    /// 等到该账号的认证观察进入终态（required / verified / failed / cancelled）。
    fn wait_auth_terminal(
        client: &Client,
        base: &str,
        account: &str,
        timeout: Duration,
    ) -> Result<Value> {
        let deadline = Instant::now() + timeout;
        loop {
            let snapshot = get_json(client, &format!("{base}/api/v1/runtime/acp-auth"))?;
            if let Some(entry) = snapshot["accounts"].as_array().and_then(|accounts| {
                accounts
                    .iter()
                    .find(|entry| entry["accountId"].as_str() == Some(account))
            }) {
                let kind = entry["state"]["kind"].as_str().unwrap_or_default();
                if matches!(kind, "required" | "verified" | "failed" | "cancelled") {
                    return Ok(entry["state"].clone());
                }
            }
            ensure!(
                Instant::now() < deadline,
                "the ACP auth observation for `{account}` did not reach a terminal state"
            );
            std::thread::sleep(Duration::from_millis(100));
        }
    }

    /// 读合成 agent 的协议事件：`(事件名, 进程号)`。
    ///
    /// 完整契约（fixture writer 的每条记录都满足，缺一不可）：
    /// - I/O：只有 `NotFound` 等价于“还没有任何事件”；权限、目录冲突等其它失败传播。
    /// - 结构：空白行不是“跳过”而是证据损坏，带行号拒绝——writer 从不写空行，
    ///   因此空行只能来自截断、拼接或覆写。
    /// - 语法：每行必须是 typed JSON；解析失败带行号传播。
    /// - 结构：`event` 必须是非空字符串，`pid` 必须是大于 0 的整数——fixture 的
    ///   每条记录都写 pid，因此缺字段/错类型/无效值都视为证据损坏，而不是空事件。
    fn agent_events(state: &Path) -> Result<Vec<(String, u64)>> {
        let path = state.join("events.jsonl");
        let text = match fs::read_to_string(&path) {
            Ok(text) => text,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(Vec::new());
            }
            Err(error) => {
                return Err(error).with_context(|| {
                    format!(
                        "failed to read the synthetic agent evidence: {}",
                        path.display()
                    )
                });
            }
        };
        let mut events = Vec::new();
        for (index, raw) in text.lines().enumerate() {
            let number = index + 1;
            let line = raw.trim();
            ensure!(
                !line.is_empty(),
                "the synthetic agent event on line {number} is blank"
            );
            let value: Value = serde_json::from_str(line).with_context(|| {
                format!("the synthetic agent event on line {number} is not typed JSON: {line}")
            })?;
            let event = value
                .get("event")
                .and_then(Value::as_str)
                .filter(|name| !name.trim().is_empty())
                .with_context(|| {
                    format!("the synthetic agent event on line {number} carries no event name")
                })?;
            let pid = value
                .get("pid")
                .and_then(Value::as_u64)
                .filter(|pid| *pid > 0)
                .with_context(|| {
                    format!("the synthetic agent event on line {number} carries no valid agent pid")
                })?;
            events.push((event.to_owned(), pid));
        }
        Ok(events)
    }

    /// 该 pid 是否仍然存在（Linux `/proc` 是这次失败收束的真实证据）。
    fn pid_running(pid: u64) -> bool {
        pid != 0 && Path::new(&format!("/proc/{pid}")).exists()
    }

    /// 一条 peer 证据记录的种类与必需字段（与 fixture writer 一一对应）。
    fn validate_peer_record(record: &Value, number: usize) -> Result<()> {
        let kind = record["kind"]
            .as_str()
            .filter(|kind| !kind.trim().is_empty())
            .with_context(|| format!("peer log line {number} carries no record kind"))?;
        let string_field = |field: &str| -> Result<()> {
            ensure!(
                record[field].as_str().is_some(),
                "peer log line {number} (`{kind}`) requires the string field `{field}`"
            );
            Ok(())
        };
        let number_field = |field: &str| -> Result<()> {
            ensure!(
                record[field].as_u64().is_some(),
                "peer log line {number} (`{kind}`) requires the integer field `{field}`"
            );
            Ok(())
        };
        match kind {
            "connectionError" => {
                string_field("peer")?;
                string_field("message")?;
            }
            "tunnelError" => {
                string_field("host")?;
                string_field("message")?;
            }
            "rejectedPlainRequest" => {
                number_field("seq")?;
                string_field("method")?;
                string_field("uri")?;
                number_field("status")?;
            }
            "rejectedTunnel" => {
                number_field("seq")?;
                string_field("authority")?;
                number_field("status")?;
            }
            "connect" => {
                number_field("seq")?;
                string_field("host")?;
                number_field("status")?;
                number_field("atMs")?;
            }
            "handlerError" => {
                number_field("seq")?;
                string_field("host")?;
                string_field("path")?;
                string_field("message")?;
            }
            "request" => {
                number_field("seq")?;
                string_field("host")?;
                string_field("method")?;
                string_field("path")?;
                number_field("status")?;
                number_field("atMs")?;
            }
            "archiveDrop" => {
                number_field("served")?;
                number_field("offset")?;
                string_field("etag")?;
            }
            other => {
                anyhow::bail!("peer log line {number} carries the unknown record kind `{other}`")
            }
        }
        Ok(())
    }

    /// 读完整 peer 记录日志：文件缺失、空白行、坏 JSON、未知种类或结构错误都失败。
    fn peer_log_records(peer: &Path) -> Result<Vec<Value>> {
        let text = fs::read_to_string(peer.join(REQUESTS_FILE)).with_context(|| {
            format!(
                "the peer request log is missing: {}",
                peer.join(REQUESTS_FILE).display()
            )
        })?;
        let mut records = Vec::new();
        for (index, raw) in text.lines().enumerate() {
            let number = index + 1;
            ensure!(!raw.trim().is_empty(), "peer log line {number} is blank");
            let value: Value = serde_json::from_str(raw)
                .with_context(|| format!("peer log line {number} is not typed JSON: {raw}"))?;
            validate_peer_record(&value, number)?;
            records.push(value);
        }
        Ok(records)
    }

    /// 报告与日志必须互相证明：记录完整、行数等于成功数、计数器与日志相核。
    ///
    /// `archiveRequests` 计所有打到固定 archive path 的 HTTP 请求（GET/HEAD 及 3xx/503
    /// 都算），因此这里用同口径比对；`connects` 只计被接受的 CONNECT。
    fn validate_peer_evidence(peer: &Path, report: &Value) -> Result<Vec<Value>> {
        let records = peer_log_records(peer)?;
        let log = report
            .get("requestLog")
            .context("the peer report carries no requestLog facts")?;
        ensure!(
            log["failed"].as_bool() == Some(false),
            "the peer lost request records: {:?}",
            log["firstError"]
        );
        let attempted = log["attempted"]
            .as_u64()
            .context("the peer requestLog carries no attempt count")?;
        let succeeded = log["succeeded"]
            .as_u64()
            .context("the peer requestLog carries no success count")?;
        ensure!(
            attempted == succeeded,
            "the peer attempted {attempted} request records but only {succeeded} were written"
        );
        ensure!(
            succeeded as usize == records.len(),
            "the peer report claims {succeeded} records but the log holds {}",
            records.len()
        );
        let fixed = fixed_archive_path()?;
        let logged_archive = records
            .iter()
            .filter(|record| {
                record["kind"].as_str() == Some("request")
                    && record["path"].as_str() == Some(fixed.as_str())
            })
            .count() as u64;
        ensure!(
            report["archiveRequests"].as_u64() == Some(logged_archive),
            "the peer counter ({:?}) differs from the logged archive requests ({logged_archive})",
            report["archiveRequests"]
        );
        let logged_connects = records
            .iter()
            .filter(|record| record["kind"].as_str() == Some("connect"))
            .count() as u64;
        ensure!(
            report["connects"].as_u64() == Some(logged_connects),
            "the peer counter ({:?}) differs from the logged accepts ({logged_connects})",
            report["connects"]
        );
        Ok(records)
    }

    /// 一条 peer 记录的主机名：`host`、`authority` 或 `uri` 三选一，去掉端口。
    fn record_hostname(record: &Value) -> String {
        let hostname = |raw: &str| {
            raw.rsplit_once(':')
                .map_or(raw, |(name, _)| name)
                .to_owned()
        };
        if let Some(host) = record["host"].as_str() {
            return hostname(host);
        }
        if let Some(authority) = record["authority"].as_str() {
            return hostname(authority);
        }
        let uri = record["uri"].as_str().unwrap_or_default();
        let without_scheme = uri.split_once("://").map_or(uri, |(_, rest)| rest);
        hostname(without_scheme.split('/').next().unwrap_or_default())
    }

    /// 从**同一次严格读取**的记录建立固定来源证据（不重新解析日志，也不读 report
    /// 里不存在的字段）。
    ///
    /// 规则与 manual-GUI 的来源审计一致，而不是“拒绝一切隧道”：
    /// - 退役 registry（确切 host 或 `/registry/` 前缀）出现即失败，没有豁免；
    /// - 固定分发 host 上的 `request` 只接受本机固定完整 archive path，method 只接受
    ///   GET/HEAD；任何其它 host 或非固定 path 的 `request` 同样是来源违规；
    /// - 其它 host 的 CONNECT／被拒隧道只作 `unrelatedRequests` 诊断：产品自身还有与
    ///   安装无关的出网（例如目录同步），既不算违规也不算安装通过证据。
    fn audit_peer_sources(records: &[Value]) -> Result<Value> {
        let fixed = fixed_archive_path()?;
        let mut archive_requests = 0_u64;
        let mut accepted_connects = 0_u64;
        let mut legacy: Vec<String> = Vec::new();
        let mut violations: Vec<String> = Vec::new();
        let mut unrelated: Vec<String> = Vec::new();
        for record in records {
            let kind = record["kind"].as_str().unwrap_or_default();
            let hostname = record_hostname(record);
            let path = record["path"].as_str().unwrap_or_default();
            let method = record["method"].as_str().unwrap_or_default();
            let legacy_path = path.starts_with(RETIRED_REGISTRY_PATH_PREFIX)
                || record["uri"]
                    .as_str()
                    .is_some_and(|uri| uri.contains(RETIRED_REGISTRY_PATH_PREFIX));
            if hostname == RETIRED_REGISTRY_HOST || legacy_path {
                legacy.push(format!("{kind}:{hostname}{path}"));
                continue;
            }
            match kind {
                "request" => {
                    if hostname != FIXED_ARCHIVE_HOST {
                        violations.push(format!("install request to {hostname}{path}"));
                    } else if path != fixed {
                        violations.push(format!(
                            "install request to a non-fixed archive path: {path}"
                        ));
                    } else if !matches!(method, "GET" | "HEAD") {
                        violations.push(format!("install archive request used method `{method}`"));
                    } else {
                        archive_requests += 1;
                    }
                }
                "connect" if hostname == FIXED_ARCHIVE_HOST => accepted_connects += 1,
                "connect" | "rejectedTunnel" | "rejectedPlainRequest" => {
                    unrelated.push(format!("{kind}:{hostname}"));
                }
                _ => {}
            }
        }
        ensure!(
            legacy.is_empty(),
            "the product still requested the retired registry source: {legacy:?}"
        );
        ensure!(
            violations.is_empty(),
            "the peer observed install traffic outside the fixed source: {violations:?}"
        );
        Ok(json!({
            "archiveRequests": archive_requests,
            "acceptedConnects": accepted_connects,
            "legacyRegistryAttempts": legacy,
            "sourceViolations": violations,
            "unrelatedRequests": unrelated,
            "fixedArchivePath": fixed,
            "requestRecords": records.len(),
        }))
    }

    /// peer 日志里所有被尝试过的主机名（CONNECT 与被拒隧道都算）。
    fn peer_attempted_hosts(peer: &Path) -> Result<Vec<String>> {
        let mut hosts = Vec::new();
        for record in peer_log_records(peer)? {
            match record["kind"].as_str().unwrap_or_default() {
                "connect" => hosts.push(record["host"].as_str().unwrap_or_default().to_owned()),
                "rejectedTunnel" => {
                    hosts.push(record["authority"].as_str().unwrap_or_default().to_owned())
                }
                "rejectedPlainRequest" => {
                    hosts.push(record["uri"].as_str().unwrap_or_default().to_owned())
                }
                _ => {}
            }
        }
        Ok(hosts)
    }

    /// 该 peer 生命周期里固定归档路径的响应分布：(3xx 重定向数, 2xx 正文数)。
    fn peer_archive_statuses(peer: &Path) -> Result<(u64, u64)> {
        let fixed = fixed_archive_path()?;
        let (mut redirects, mut bodies) = (0, 0);
        for record in peer_log_records(peer)? {
            if record["kind"].as_str() != Some("request")
                || record["path"].as_str() != Some(fixed.as_str())
            {
                continue;
            }
            match record["status"].as_u64() {
                Some(status) if (300..400).contains(&status) => redirects += 1,
                Some(status) if (200..300).contains(&status) => bodies += 1,
                _ => {}
            }
        }
        Ok((redirects, bodies))
    }

    /// 该 peer 生命周期里真正发出的固定归档请求数（来自完整请求日志）。
    fn peer_archive_requests(peer: &Path) -> Result<u64> {
        let fixed = fixed_archive_path()?;
        Ok(peer_log_records(peer)?
            .iter()
            .filter(|record| {
                record["kind"].as_str() == Some("request")
                    && record["path"].as_str() == Some(fixed.as_str())
            })
            .count() as u64)
    }

    /// 账号必须在某个类型化阶段失败，且终态不是 required/verified。
    fn expect_auth_failure(state: &Value, code: &str, stage: &str) -> Result<Value> {
        ensure!(
            state["kind"].as_str() == Some("failed"),
            "the auth observation ended as {:?} instead of a typed failure",
            state["kind"]
        );
        ensure!(
            state["failure"]["code"].as_str() == Some(code),
            "the auth failure is `{:?}` instead of `{code}`",
            state["failure"]["code"]
        );
        ensure!(
            state["failure"]["stage"].as_str() == Some(stage),
            "the auth failure stage is `{:?}` instead of `{stage}`",
            state["failure"]["stage"]
        );
        ensure!(
            state["failure"]["retryable"].as_bool().is_some(),
            "the auth failure carries no retryable flag"
        );
        Ok(json!({
            "code": code,
            "stage": stage,
            "message": state["failure"]["message"].clone(),
        }))
    }

    /// 缺安装：命令不得隐式下载或修复，只能报 preparationRequired@prepare。
    fn auth_preparation_required(
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
    ) -> Result<Value> {
        let control = control(paths, ArchiveVariant::Normal, 65_536, None, 0);
        let env = CaseEnv::open(paths, client, server_binary, &control)?;
        let outcome = (|| -> Result<Value> {
            save_account(
                client,
                &env.base(),
                "observe-auth-prepare",
                "acct-prepare",
                "prepare",
            )?;
            start_auth_check(
                client,
                &env.base(),
                "observe-auth-prepare-check",
                "acct-prepare",
            )?;
            let state = wait_auth_terminal(
                client,
                &env.base(),
                "acct-prepare",
                Duration::from_secs(120),
            )?;
            let failure = expect_auth_failure(&state, "preparationRequired", "prepare")?;
            ensure!(
                installed_ids_in(&paths.home(), &paths.target)?.is_empty(),
                "the read-only check installed a package although preparation is required"
            );
            ensure!(
                peer_archive_requests(&paths.peer)? == 0,
                "the read-only check downloaded the archive"
            );
            Ok(json!({ "failure": failure, "archiveRequests": 0 }))
        })();
        finish("auth-preparation-required", &paths.peer, env, outcome)
    }

    /// 安装存在但被破坏（成员缺失 → 回执/整树不一致）：installationInvalid@prepare。
    fn auth_installation_invalid(
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
    ) -> Result<Value> {
        let agent_program = fixture_agent_program(paths)?;
        let control = control_with(
            paths,
            &agent_program,
            ArchiveVariant::Normal,
            262_144,
            None,
            0,
        );
        let env = CaseEnv::open(paths, client, server_binary, &control)?;
        let outcome = (|| -> Result<Value> {
            save_account(
                client,
                &env.base(),
                "observe-auth-invalid",
                "acct-invalid",
                "invalid",
            )?;
            start(client, &env.base(), "observe-auth-invalid-install")?;
            let ready = wait_terminal(client, &env.base(), Duration::from_secs(300))?;
            let observed = expect_ready(&ready)?;
            let key = storage_key(&observed.wire_id)?;
            // 只改一个**独立辅助成员**的内容：agent 控制与主程序都保持原样可运行，
            // 因此下面的结论只限于“没有观察到任何 ACP 协议请求/事件”，不能、也不
            // 用来归因于“删除了控制文件”。回执仍记原摘要，整树因此不符。
            let auxiliary = paths.installed_dir(&key).join(AUXILIARY);
            let mut content = fs::read(&auxiliary).with_context(|| {
                format!(
                    "the published auxiliary member is missing: {}",
                    auxiliary.display()
                )
            })?;
            content.extend_from_slice(b"tampered-after-publication\n");
            fs::write(&auxiliary, &content)?;
            let events_before = agent_events(&paths.agent)?;
            start_auth_check(
                client,
                &env.base(),
                "observe-auth-invalid-check",
                "acct-invalid",
            )?;
            let state = wait_auth_terminal(
                client,
                &env.base(),
                "acct-invalid",
                Duration::from_secs(120),
            )?;
            let failure = expect_auth_failure(&state, "installationInvalid", "prepare")?;
            // 证据信号：agent 的协议事件水位完全没变。fixture 只有在**收到请求**时
            // 才写事件，因此这里能声明的只是“该次检查没有向合成 agent 发出任何 ACP
            // 协议请求”；不声称操作系统层面没有 spawn 进程。
            let events_after = agent_events(&paths.agent)?;
            ensure!(
                events_after.len() == events_before.len()
                    && events_after.iter().eq(events_before.iter()),
                "an ACP protocol request reached the synthetic agent although the installation was invalid"
            );
            ensure!(
                !events_after.iter().any(|(name, _)| name == "initialize"),
                "an invalid installation still produced an ACP initialize"
            );
            Ok(json!({
                "failure": failure,
                "tamperedMember": AUXILIARY,
                "tamper": "appended-bytes-after-publication",
                "eventsBefore": events_before.len(),
                "eventsAfter": events_after.len(),
                "newProtocolEvents": 0,
                "acpProtocolRequestsObserved": 0,
                "evidenceSignal": "no ACP protocol event was written during the whole check (the fixture writes one per received request)",
            }))
        })();
        finish("auth-installation-invalid", &paths.peer, env, outcome)
    }

    /// 旧配置字段（program/args）在现役 API 必须被拒绝，且不写入任何账号。
    fn auth_legacy_fields(
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
    ) -> Result<Value> {
        let control = control(paths, ArchiveVariant::Normal, 65_536, None, 0);
        let env = CaseEnv::open(paths, client, server_binary, &control)?;
        let outcome = (|| -> Result<Value> {
            let body = json!({
                "operationId": "observe-auth-legacy",
                "expectedRevision": settings_revision(client, &env.base())?,
                "account": {
                    "accountId": "acct-legacy",
                    "name": "legacy",
                    "provider": PROVIDER,
                    // 已删除的执行字段：现役结构必须拒绝，而不是悄悄接受。
                    "program": "/usr/bin/true",
                    "args": ["--acp-stdio"],
                },
            });
            let response = client
                .put(format!("{}/api/v1/settings/acp-account", env.base()))
                .json(&body)
                .send()
                .context("legacy save request failed")?;
            let status = response.status();
            ensure!(
                status.is_client_error(),
                "the legacy program/args payload was accepted with {status}"
            );
            ensure!(
                !account_saved(&paths.home())?,
                "the rejected legacy payload still persisted an ACP account"
            );
            Ok(json!({ "status": status.as_u16(), "accountPersisted": false }))
        })();
        finish("auth-legacy-fields", &paths.peer, env, outcome)
    }

    /// 固定版本握手：wrong / missing / 带空白的 1.4.1 都必须 serverVersionMismatch，
    /// 且不得向不合格的 server 发送 authenticate 或 session/new。
    fn auth_server_version(
        paths: &Paths,
        client: &Client,
        server_binary: Option<&Path>,
    ) -> Result<Value> {
        let agent_program = fixture_agent_program(paths)?;
        let control = control_with(
            paths,
            &agent_program,
            ArchiveVariant::Normal,
            262_144,
            None,
            0,
        );
        let env = CaseEnv::open(paths, client, server_binary, &control)?;
        let behavior_path = paths.agent.join("behavior.json");
        let outcome = (|| -> Result<Value> {
            save_account(
                client,
                &env.base(),
                "observe-auth-version",
                "acct-version",
                "version",
            )?;
            start(client, &env.base(), "observe-auth-version-install")?;
            let ready = wait_terminal(client, &env.base(), Duration::from_secs(300))?;
            let _ = expect_ready(&ready)?;
            let mut runs = Vec::new();
            for (index, server_info) in [
                json!({"version": "1.4.0"}),
                json!({"version": null}),
                json!({"version": " 1.4.1 "}),
            ]
            .into_iter()
            .enumerate()
            {
                fs::write(
                    &behavior_path,
                    serde_json::to_vec_pretty(&json!({ "serverInfo": server_info }))?,
                )?;
                let before = agent_events(&paths.agent)?;
                let operation = format!("observe-auth-version-check-{index}");
                start_auth_check(client, &env.base(), &operation, "acct-version")?;
                let state = wait_auth_terminal(
                    client,
                    &env.base(),
                    "acct-version",
                    Duration::from_secs(120),
                )?;
                let failure = expect_auth_failure(&state, "serverVersionMismatch", "initialize")?;
                let after = agent_events(&paths.agent)?;
                ensure!(
                    after.len() >= before.len() && after[..before.len()].iter().eq(before.iter()),
                    "the synthetic agent rewrote its earlier protocol evidence during the version check"
                );
                let delta = &after[before.len()..];
                // 精确事实：不合格 server 只允许看到**一条** initialize，不允许出现
                // authenticate/sessionNew/close 等后续方法，也不允许重连式重复 initialize。
                let names: Vec<&str> = delta.iter().map(|(name, _)| name.as_str()).collect();
                ensure!(
                    names == ["initialize"],
                    "an unqualified server saw {:?} instead of exactly one initialize",
                    names
                );
                let pid = delta[0].1;
                ensure!(
                    pid != 0,
                    "the single initialize record carries no agent process identity"
                );
                ensure!(
                    !pid_running(pid),
                    "the rejected agent process {pid} is still alive after the version check"
                );
                runs.push(json!({
                    "serverInfo": server_info,
                    "failure": failure,
                    "operationId": operation,
                    "events": names,
                    "agentPid": pid,
                    "agentExited": true,
                    "sentAuthenticate": false,
                    "sentSessionNew": false,
                }));
            }
            Ok(json!({ "runs": runs }))
        })();
        finish("auth-server-version", &paths.peer, env, outcome)
    }

    fn control(
        paths: &Paths,
        variant: ArchiveVariant,
        chunk_bytes: usize,
        drop_after_bytes: Option<u64>,
        chunk_delay_ms: u64,
    ) -> AcpInstallControl {
        control_with(
            paths,
            &paths.program,
            variant,
            chunk_bytes,
            drop_after_bytes,
            chunk_delay_ms,
        )
    }

    #[allow(clippy::too_many_arguments)]
    /// 固定 1.4.1 的生命周期控制：不再有 registry 文档、版本、摘要、URL 或 argv
    /// 选择项，只有外部响应形状（redirect / 传输控制）与合成 agent state 目录。
    fn control_with(
        paths: &Paths,
        program: &Path,
        variant: ArchiveVariant,
        chunk_bytes: usize,
        drop_after_bytes: Option<u64>,
        chunk_delay_ms: u64,
    ) -> AcpInstallControl {
        AcpInstallControl {
            archive: ArchiveControl {
                variant,
                program: program.to_path_buf(),
                auxiliary: paths.auxiliary.clone(),
                agent_state_dir: paths.agent.clone(),
                chunk_bytes: Some(chunk_bytes.max(1)),
                chunk_delay_ms,
                unknown_length: false,
                drop_after_bytes,
                drop_requests: 0,
                fail_requests: 0,
                redirects: 0,
                redirect_target: None,
                etag: None,
                script: Vec::new(),
            },
            stop_file: None,
        }
    }

    /// 当前宿主固定的官方归档 URL（产品唯一允许的发行）。
    fn fixed_archive_url() -> Result<String> {
        fixed::archive_url(&host_target()?).context("the host has no fixed Antigravity release")
    }

    /// 当前宿主固定的归档请求路径（含前导 `/`）。
    fn fixed_archive_path() -> Result<String> {
        fixed::archive_path(&host_target()?).context("the host has no fixed Antigravity release")
    }

    fn start(client: &Client, base: &str, operation: &str) -> Result<()> {
        let body = StartAcpInstallRequest {
            operation_id: operation.to_owned(),
            provider: AcpProvider::Antigravity,
        };
        let response = client
            .post(format!("{base}/api/v1/runtime/acp-install/start"))
            .json(&body)
            .send()
            .context("start request failed")?;
        ensure!(
            response.status().is_success(),
            "start request answered {}",
            response.status()
        );
        let reply: Value = response.json()?;
        ensure!(
            reply["snapshot"]["installations"].is_array() && reply["receipt"].is_object(),
            "the start reply carries no canonical snapshot or receipt"
        );
        assert_wire_casing(&reply["snapshot"], "start reply")?;
        Ok(())
    }

    fn cancel(client: &Client, base: &str, operation: &str, target: &str) -> Result<()> {
        let body = CancelAcpInstallRequest {
            operation_id: operation.to_owned(),
            provider: AcpProvider::Antigravity,
            target_operation_id: target.to_owned(),
        };
        let response = client
            .post(format!("{base}/api/v1/runtime/acp-install/cancel"))
            .json(&body)
            .send()
            .context("cancel request failed")?;
        ensure!(
            response.status().is_success(),
            "cancel request answered {}",
            response.status()
        );
        Ok(())
    }

    fn read(client: &Client, base: &str) -> Result<(Value, AcpInstallSnapshot)> {
        let response = client
            .get(format!("{base}/api/v1/runtime/acp-install"))
            .send()
            .context("read request failed")?;
        ensure!(
            response.status().is_success(),
            "read request answered {}",
            response.status()
        );
        let raw: Value = response.json()?;
        assert_wire_casing(&raw, "read reply")?;
        let snapshot: AcpInstallSnapshot =
            serde_json::from_value(raw.clone()).context("read reply is not the typed snapshot")?;
        Ok((raw, snapshot))
    }

    /// The wire JSON must carry the documented camelCase field names; a same-Rust
    /// DTO round-trip cannot prove what HTTP actually emitted.
    fn assert_wire_casing(snapshot: &Value, context: &str) -> Result<()> {
        let Some(installations) = snapshot["installations"].as_array() else {
            bail!("{context} carries no installations array");
        };
        for entry in installations {
            let state = entry.get("state").unwrap_or(entry);
            let kind = state["kind"].as_str().unwrap_or_default();
            if !matches!(kind, "idle") {
                ensure!(
                    state.get("operationId").is_some(),
                    "{context} state `{kind}` does not use the camelCase operationId field"
                );
                ensure!(
                    state.get("operation_id").is_none(),
                    "{context} state `{kind}` still uses the snake_case operation_id field"
                );
            }
            if kind == "downloading" {
                ensure!(
                    state.get("retryCount").is_some(),
                    "{context} downloading state does not use the camelCase retryCount field"
                );
                ensure!(
                    state.get("retry_count").is_none(),
                    "{context} downloading state still uses the snake_case retry_count field"
                );
            }
        }
        Ok(())
    }

    fn state(client: &Client, base: &str) -> Result<AcpInstallState> {
        let (_raw, snapshot) = read(client, base)?;
        Ok(snapshot.state_of(AcpProvider::Antigravity))
    }

    fn poll_until(
        client: &Client,
        base: &str,
        budget: Duration,
        predicate: impl Fn(&AcpInstallState) -> bool,
    ) -> Result<AcpInstallState> {
        let deadline = Instant::now() + budget;
        loop {
            let current = state(client, base)?;
            if predicate(&current) {
                return Ok(current);
            }
            ensure!(
                Instant::now() < deadline,
                "the expected install state was not reached in time: {}",
                observe(&current)
            );
            std::thread::sleep(Duration::from_millis(100));
        }
    }

    fn wait_terminal(client: &Client, base: &str, budget: Duration) -> Result<AcpInstallState> {
        poll_until(client, base, budget, AcpInstallState::is_terminal)
    }

    /// First byte of a single `bytes=start-...` request range.
    fn range_start(value: &str) -> Option<u64> {
        let spec = value.strip_prefix("bytes=")?;
        let start = spec.split('-').next()?;
        if start.is_empty() {
            return None;
        }
        start.parse().ok()
    }

    fn storage_key(wire: &str) -> Result<String> {
        let hex = wire
            .strip_prefix(WIRE_ID_PREFIX)
            .with_context(|| format!("unexpected wire installation id `{wire}`"))?;
        ensure!(
            hex.len() == 64
                && hex
                    .bytes()
                    .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte)),
            "wire installation id `{wire}` is not sha256:<64 lowercase hex>"
        );
        Ok(hex.to_owned())
    }

    fn verify_publication(
        paths: &Paths,
        key: &str,
        observed: &Observed,
        archive_sha: &str,
        expected: &[Value],
        packaged_program: &Path,
    ) -> Result<()> {
        let directory = paths.installed_dir(key);
        // `is_dir()`/`metadata()` follow links, so a symlinked root could
        // impersonate a publication. The root itself must be a real directory;
        // link facts stay visible instead of being resolved away.
        let root = fs::symlink_metadata(&directory).with_context(|| {
            format!(
                "the published installation root is missing: {}",
                directory.display()
            )
        })?;
        ensure!(
            root.file_type().is_dir(),
            "the published installation root is not a real directory (symlink or special entry)"
        );
        // The installation root is the product's own directory: exact 0700.
        #[cfg(unix)]
        ensure!(
            mode_of(&root) == 0o700,
            "the installation root does not have mode 0700"
        );
        let receipt_path = directory.join("receipt.json");
        let receipt_file = fs::symlink_metadata(&receipt_path).with_context(|| {
            format!(
                "the installation receipt is missing: {}",
                receipt_path.display()
            )
        })?;
        ensure!(
            receipt_file.file_type().is_file(),
            "the installation receipt is not a real regular file"
        );
        let receipt = read_json(&receipt_path)?;
        ensure!(
            receipt["installationId"].as_str() == Some(observed.wire_id.as_str()),
            "the receipt wire identity does not match the ready installation"
        );
        ensure!(
            receipt["command"].as_str() == Some(PROGRAM_MEMBER),
            "the receipt names another program entry"
        );
        ensure!(
            receipt["archiveSha256"].as_str() == Some(archive_sha),
            "the receipt records another local archive digest"
        );
        // The **served package** is the expectation, never the receipt itself: a
        // publication that silently drops a member (an empty one included) still
        // looks self-consistent in its own receipt, so the peer's member list is
        // the independent fact compared against receipt and the real tree.
        let mut expected_members: BTreeMap<String, (u64, String, Option<u32>)> = BTreeMap::new();
        for member in expected {
            let path = member["path"]
                .as_str()
                .context("a peer member has no path")?
                .to_owned();
            let entry = (
                member["size"]
                    .as_u64()
                    .context("a peer member has no size")?,
                member["sha256"]
                    .as_str()
                    .context("a peer member has no digest")?
                    .to_owned(),
                mode_field(&member["mode"], "peer member")?,
            );
            ensure!(
                expected_members.insert(path.clone(), entry).is_none(),
                "the peer declared the member `{path}` twice"
            );
        }
        ensure!(
            !expected_members.is_empty(),
            "the peer ready document declares no members"
        );
        let members = receipt["members"]
            .as_array()
            .context("the receipt has no member list")?;
        let mut receipt_members: BTreeMap<&str, &Value> = BTreeMap::new();
        for member in members {
            let path = member["path"]
                .as_str()
                .context("a receipt member has no path")?;
            ensure!(
                receipt_members.insert(path, member).is_none(),
                "the receipt declares the member `{path}` twice"
            );
        }
        ensure!(
            receipt_members.keys().eq(expected_members.keys()),
            "the receipt member set differs from the served package"
        );
        for (relative, (size, sha, mode)) in &expected_members {
            let member = receipt_members
                .get(relative.as_str())
                .with_context(|| format!("the receipt omits the member `{relative}`"))?;
            ensure!(
                member["size"].as_u64() == Some(*size),
                "the receipt member `{relative}` has another size"
            );
            ensure!(
                member["sha256"].as_str() == Some(sha.as_str()),
                "the receipt member `{relative}` has another digest"
            );
            ensure!(
                mode_field(&member["mode"], "receipt member")? == *mode,
                "the receipt member `{relative}` has another mode"
            );
            let path = directory.join(relative);
            ensure!(
                path.is_file(),
                "the published member is missing: {relative}"
            );
            ensure!(
                fs::metadata(&path)?.len() == *size,
                "the published member `{relative}` has another size"
            );
            ensure!(
                file_sha256(&path)? == *sha,
                "the published member `{relative}` has another digest"
            );
            let actual = mode_of(&fs::metadata(&path)?);
            #[cfg(unix)]
            {
                ensure!(
                    Some(actual) == *mode,
                    "the published member `{relative}` has the wrong mode"
                );
                ensure!(
                    actual & 0o7000 == 0,
                    "the published member `{relative}` carries setuid/setgid/sticky bits"
                );
                // The executable bit is part of each member's own mode contract
                // (compared above), not a blanket rule: an auxiliary program the
                // package legitimately marks executable must not be rejected.
                // Only the declared entry must really be executable.
                if relative == PROGRAM_MEMBER {
                    ensure!(
                        actual & 0o111 != 0,
                        "the published program carries no executable bit"
                    );
                }
            }
            #[cfg(not(unix))]
            let _ = actual;
        }
        // Package directories carry their own normalized mode in the receipt.
        let mut declared_dirs: BTreeMap<String, Option<u32>> = BTreeMap::new();
        for entry in receipt["directories"]
            .as_array()
            .context("the receipt has no directory list")?
        {
            let path = entry["path"]
                .as_str()
                .context("a receipt directory has no path")?;
            ensure!(
                declared_dirs
                    .insert(
                        path.to_owned(),
                        mode_field(&entry["mode"], "receipt directory")?
                    )
                    .is_none(),
                "the receipt declares the directory `{path}` twice"
            );
        }
        // Full-tree closure: exactly the receipt plus the served members, inside
        // declared directories only, with the declared permission facts.
        for (relative, is_file, mode) in tree_paths(&directory)? {
            if is_file {
                ensure!(
                    relative == "receipt.json" || expected_members.contains_key(&relative),
                    "the published installation contains an undeclared file: {relative}"
                );
                continue;
            }
            let declared = declared_dirs.get(&relative).with_context(|| {
                format!("the published installation contains an undeclared directory: {relative}")
            })?;
            #[cfg(unix)]
            {
                let actual = mode.context("a published directory carries no permission facts")?;
                ensure!(
                    Some(actual) == *declared,
                    "the published directory `{relative}` has the wrong mode"
                );
                ensure!(
                    actual & 0o022 == 0 && actual & 0o7000 == 0,
                    "the published directory `{relative}` carries dangerous permission bits"
                );
            }
            #[cfg(not(unix))]
            let _ = (&declared, mode);
        }
        for relative in declared_dirs.keys() {
            ensure!(
                directory.join(relative).is_dir(),
                "the published installation is missing the declared directory `{relative}`"
            );
        }
        // Binary identity: the published program must be the very file the peer
        // packaged, not a same-name substitute.
        let published_program = directory.join(PROGRAM_MEMBER);
        ensure!(
            fs::metadata(&published_program)?.len() == fs::metadata(packaged_program)?.len()
                && file_sha256(&published_program)? == file_sha256(packaged_program)?,
            "the published program is not the fixture binary"
        );
        let archive = paths.downloads_dir().join(format!("{key}.zip"));
        ensure!(
            archive.is_file() && file_sha256(&archive)? == archive_sha,
            "the local archive is missing or has another digest"
        );
        Ok(())
    }

    #[cfg(unix)]
    fn mode_of(metadata: &std::fs::Metadata) -> u32 {
        use std::os::unix::fs::MetadataExt;
        // Real permission bits: masking setuid/setgid/sticky away would make the
        // "no special bits" assertions vacuous and hide a 0755 installation root.
        metadata.mode() & 0o7777
    }

    /// One Unix mode field from JSON, checked instead of truncated.
    ///
    /// Permission facts never exceed `0o7777`; a larger number is malformed, so it
    /// must fail instead of silently wrapping when narrowed to `u32`.
    fn mode_field(value: &Value, what: &str) -> Result<Option<u32>> {
        match value.as_u64() {
            None => Ok(None),
            Some(raw) => u32::try_from(raw)
                .map(Some)
                .with_context(|| format!("the {what} mode {raw} is not a permission field")),
        }
    }

    /// Every path below one published installation as
    /// `(relative, is_file, mode)`.
    ///
    /// Symlinks and special entries fail immediately: a publication is only ever
    /// regular files inside plain directories.
    fn tree_paths(root: &Path) -> Result<Vec<(String, bool, Option<u32>)>> {
        fn visit(
            root: &Path,
            directory: &Path,
            out: &mut Vec<(String, bool, Option<u32>)>,
        ) -> Result<()> {
            for entry in fs::read_dir(directory)? {
                let entry = entry?;
                let path = entry.path();
                let relative = path
                    .strip_prefix(root)
                    .unwrap_or(&path)
                    .to_string_lossy()
                    .replace('\\', "/");
                let file_type = entry.file_type()?;
                ensure!(
                    !file_type.is_symlink(),
                    "the published installation contains a symlink: {relative}"
                );
                if file_type.is_dir() {
                    out.push((relative, false, Some(mode_of(&entry.metadata()?))));
                    visit(root, &path, out)?;
                } else {
                    ensure!(
                        file_type.is_file(),
                        "the published installation contains a special entry: {relative}"
                    );
                    out.push((relative, true, Some(mode_of(&entry.metadata()?))));
                }
            }
            Ok(())
        }
        let mut out = Vec::new();
        visit(root, root, &mut out)?;
        Ok(out)
    }

    fn member_hashes(directory: &Path, excluded: &[&str]) -> Result<BTreeMap<String, String>> {
        let mut hashes = BTreeMap::new();
        collect(directory, directory, excluded, &mut hashes)?;
        Ok(hashes)
    }

    fn collect(
        root: &Path,
        directory: &Path,
        excluded: &[&str],
        hashes: &mut BTreeMap<String, String>,
    ) -> Result<()> {
        for entry in fs::read_dir(directory)? {
            let entry = entry?;
            let path = entry.path();
            if entry.file_type()?.is_dir() {
                collect(root, &path, excluded, hashes)?;
                continue;
            }
            let relative = path
                .strip_prefix(root)
                .unwrap_or(&path)
                .to_string_lossy()
                .replace('\\', "/");
            if excluded.contains(&relative.as_str()) {
                continue;
            }
            hashes.insert(relative, file_sha256(&path)?);
        }
        Ok(())
    }

    fn read_json(path: &Path) -> Result<Value> {
        let bytes = fs::read(path)
            .with_context(|| format!("failed to read expected evidence: {}", path.display()))?;
        serde_json::from_slice(&bytes)
            .with_context(|| format!("evidence is not typed JSON: {}", path.display()))
    }
}
