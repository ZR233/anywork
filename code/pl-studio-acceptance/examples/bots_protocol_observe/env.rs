use anyhow::{Context, Result, bail, ensure};
use pl_model::config::{AccountConfig, AccountId};
use pl_model::model::{ModelInfo, ModelTransportProfile};
use pl_model::protocol::ProtocolEndpoint;
use pl_studio_runtime::config::StudioConfig;
use serde::Serialize;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const RESERVED_DEV_PORT: u16 = 1420;
const RESERVED_DEFAULT_SERVER_PORT: u16 = 1421;
const MANIFEST_MAX_BYTES: usize = 8 * 1024;
const PORT_ATTEMPTS: u32 = 8;

#[derive(Debug)]
pub(crate) struct ObservePaths {
    pub workspace: PathBuf,
    pub output: PathBuf,
    working: Option<tempfile::TempDir>,
    keyring_working: Option<tempfile::TempDir>,
    pub home: PathBuf,
    pub project: PathBuf,
    pub keyring_runtime: PathBuf,
    pub server_log: PathBuf,
}

impl ObservePaths {
    pub fn retain(&mut self) -> Result<()> {
        let Some(working) = self.working.take() else {
            return Ok(());
        };
        let root = working.keep();
        let keyring_root = self.keyring_working.take().map(|working| working.keep());
        let evidence = serde_json::json!({
            "root": root,
            "home": self.home,
            "project": self.project,
            "keyringRuntime": self.keyring_runtime,
            "keyringRoot": keyring_root,
        });
        fs::write(
            self.output.join("retained-environment.json"),
            serde_json::to_vec_pretty(&evidence)?,
        )?;
        Ok(())
    }
}

pub(crate) fn prepare_output(output: Option<&Path>) -> Result<PathBuf> {
    let workspace = pl_dev_support::paths::workspace_root()?;
    match output {
        Some(path) => {
            fs::create_dir_all(path)?;
            Ok(fs::canonicalize(path)?)
        }
        None => {
            let stamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|duration| duration.as_millis())
                .unwrap_or(0);
            let dir = workspace
                .join("target")
                .join("bots-protocol-observe")
                .join(format!("{stamp}-{}", std::process::id()));
            fs::create_dir_all(&dir)?;
            Ok(fs::canonicalize(&dir)?)
        }
    }
}

pub(crate) fn prepare(output: Option<&Path>) -> Result<ObservePaths> {
    let workspace = pl_dev_support::paths::workspace_root()?;
    let output = prepare_output(output)?;
    let target = workspace.join("target");
    fs::create_dir_all(&target)?;
    let working = tempfile::Builder::new()
        .prefix("bots-protocol-observe-")
        .tempdir_in(&target)
        .context("failed to create isolated observe working directory")?;
    let home = working.path().join("studio-home");
    let project = working.path().join("project");
    let keyring_working = tempfile::Builder::new()
        .prefix("bots-kr-")
        .tempdir()
        .context("failed to create short XDG_RUNTIME_DIR for Secret Service")?;
    let keyring_runtime = keyring_working.path().to_path_buf();
    let server_log = working.path().join("studio-server.log");
    fs::create_dir_all(&home)?;
    fs::create_dir_all(&project)?;
    fs::set_permissions(&keyring_runtime, fs::Permissions::from_mode(0o700))?;
    fs::write(keyring_runtime.join("fixture-password"), "\n")?;
    fs::write(
        project.join("README.md"),
        "Isolated bots protocol observation.\n",
    )?;
    ensure!(
        std::process::Command::new("git")
            .current_dir(&project)
            .args(["init", "-q"])
            .status()?
            .success(),
        "could not initialize isolated project"
    );
    Ok(ObservePaths {
        workspace,
        output,
        working: Some(working),
        keyring_working: Some(keyring_working),
        home,
        project,
        keyring_runtime,
        server_log,
    })
}

pub(crate) fn write_model_config(home: &Path, model_base_url: &str) -> Result<()> {
    let mut config = StudioConfig::default_config()?;
    let mut model = ModelInfo::compatible("fixture-model");
    model.display_name = "Bots protocol fixture".into();
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    model.binding.request.api_model = None;
    let account_id = AccountId::new(format!("bots-observe-{}", std::process::id()))?;
    let endpoint = ProtocolEndpoint::compatible("Bots protocol fixture", model_base_url);
    let account = AccountConfig::from_explicit_models(endpoint, vec![model]);
    config.models.accounts.clear();
    config.models.accounts.insert(account_id.clone(), account);
    for route in config
        .models
        .routes
        .values_mut()
        .chain(config.mode_model_routes.values_mut())
    {
        route.account_id = account_id.clone();
        route.model_id = "fixture-model".into();
        route.effort = None;
    }
    config.skills.user_dir = home.join("skills").to_string_lossy().into_owned();
    config.validate()?;
    fs::write(home.join("config.toml"), toml::to_string_pretty(&config)?)
        .with_context(|| format!("failed to write isolated config under {}", home.display()))
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FixtureManifest {
    schema_version: u32,
    studio_home: String,
    base_url: String,
}

pub(crate) fn write_fixture_manifest(home: &Path, feishu_origin: &str) -> Result<PathBuf> {
    let canonical_home = fs::canonicalize(home).context("studio home cannot be canonicalized")?;
    let origin = feishu_origin.trim_end_matches('/');
    let port = parse_loopback_port(origin)?;
    ensure!(
        port != RESERVED_DEV_PORT && port != 0,
        "fixture origin must be http://127.0.0.1:<ephemeral-port>"
    );
    let base_url = format!("{origin}/");
    let manifest = FixtureManifest {
        schema_version: 1,
        studio_home: canonical_home.to_string_lossy().into_owned(),
        base_url,
    };
    let bytes = serde_json::to_vec(&manifest)?;
    ensure!(
        bytes.len() <= MANIFEST_MAX_BYTES,
        "bots fixture manifest exceeds 8KiB"
    );
    let path = home.join("bots-fixture-manifest.json");
    fs::write(&path, bytes)?;
    let canonical = fs::canonicalize(&path)?;
    ensure!(
        canonical.starts_with(&canonical_home),
        "bots fixture manifest escaped the isolated studio home"
    );
    Ok(canonical)
}

fn parse_loopback_port(origin: &str) -> Result<u16> {
    let rest = origin
        .strip_prefix("http://127.0.0.1:")
        .context("fixture origin must use IPv4 loopback")?;
    let hostport = rest.split('/').next().unwrap_or(rest);
    hostport.parse().context("fixture origin port is not a u16")
}

pub(crate) fn choose_loopback_port() -> Result<u16> {
    for _ in 0..PORT_ATTEMPTS {
        let listener = std::net::TcpListener::bind("127.0.0.1:0")?;
        let port = listener.local_addr()?.port();
        drop(listener);
        if port != 0 && port != RESERVED_DEV_PORT && port != RESERVED_DEFAULT_SERVER_PORT {
            return Ok(port);
        }
    }
    bail!("could not reserve a loopback port outside 1420/1421")
}

pub(crate) fn redact(value: &str) -> String {
    let mut redacted = value.to_owned();
    for secret in [
        pl_provider_fixture::feishu::DEFAULT_APP_SECRET,
        pl_provider_fixture::feishu::REGISTERED_APP_SECRET,
        pl_provider_fixture::feishu::TENANT_ACCESS_TOKEN,
    ] {
        redacted = redacted.replace(secret, "[redacted]");
    }
    redacted
}

pub(crate) fn canonicalize_executable(path: &Path) -> Result<PathBuf> {
    let canonical = fs::canonicalize(path)
        .with_context(|| format!("server binary cannot be canonicalized: {}", path.display()))?;
    ensure!(
        canonical.is_file(),
        "server binary is not a file: {}",
        canonical.display()
    );
    let mode = fs::metadata(&canonical)?.permissions().mode();
    ensure!(
        mode & 0o111 != 0,
        "server binary is not executable: {}",
        canonical.display()
    );
    Ok(canonical)
}

pub(crate) fn file_sha256(path: &Path) -> Result<String> {
    let output = std::process::Command::new("sha256sum")
        .arg("--")
        .arg(path)
        .output()
        .context("failed to run sha256sum")?;
    ensure!(
        output.status.success(),
        "sha256sum failed for {}: {}",
        path.display(),
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    let hash = stdout
        .split_whitespace()
        .next()
        .context("sha256sum produced no hash")?;
    ensure!(
        hash.len() == 64 && hash.chars().all(|ch| ch.is_ascii_hexdigit()),
        "sha256sum did not return a 64-character hex digest"
    );
    Ok(hash.to_ascii_lowercase())
}

/// Fails explicitly when the launcher's Python cannot signal through a pidfd.
/// Source path label of the owner program, as it appears in the identity record.
pub(crate) const OWNER_SOURCE_PATH: &str =
    "code/pl-studio-acceptance/examples/bots_protocol_observe/server_control.py";

/// The exact bytes executed as the process owner.
///
/// They are frozen into the observer binary at build time and run through
/// `python3 -c`, so the mutable workspace file is never loaded at run time and the
/// recorded digest describes what actually ran.
pub(crate) const OWNER_SOURCE: &str = include_str!("server_control.py");

/// Digest of one byte slice, using the same `sha256sum` entry the rest of the
/// observation uses (on stdin, so no temporary file is created).
pub(crate) fn bytes_sha256(bytes: &[u8]) -> Result<String> {
    use std::io::Write;
    use std::process::{Command, Stdio};
    let mut child = Command::new("sha256sum")
        .arg("-")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("failed to run sha256sum for a byte digest")?;
    child
        .stdin
        .take()
        .context("sha256sum stdin is unavailable")?
        .write_all(bytes)
        .context("failed to write the owner source to sha256sum")?;
    let output = child
        .wait_with_output()
        .context("sha256sum did not finish for a byte digest")?;
    ensure!(
        output.status.success(),
        "sha256sum failed for the owner source: {}",
        String::from_utf8_lossy(&output.stderr).trim()
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    let hash = stdout
        .split_whitespace()
        .next()
        .context("sha256sum produced no hash for the owner source")?;
    ensure!(
        hash.len() == 64 && hash.chars().all(|ch| ch.is_ascii_hexdigit()),
        "sha256sum did not return a 64-character hex digest for the owner source"
    );
    Ok(hash.to_ascii_lowercase())
}

/// Digest of the owner bytes that this binary actually executes.
pub(crate) fn owner_source_sha256() -> Result<String> {
    bytes_sha256(OWNER_SOURCE.as_bytes())
}

/// Fails explicitly when the launcher's Python cannot signal through a pidfd.
///
/// The isolated server stop is defined as a kernel-confirmed delivery to a pidfd
/// the owner opened before any wait. Without `os.pidfd_open` /
/// `signal.pidfd_send_signal` the run has no truthful way to make that claim, so
/// it reports an environment failure instead of falling back to bare-pid signals.
pub(crate) fn python_pidfd_capability() -> Result<()> {
    const PYTHON: &str = "python3";
    const PROBE: &str = "import os, signal, sys\n\
        sys.exit(0 if hasattr(os, 'pidfd_open') and hasattr(signal, 'pidfd_send_signal') else 1)\n";
    let output = std::process::Command::new(PYTHON)
        .arg("-c")
        .arg(PROBE)
        .output()
        .with_context(|| format!("failed to run {PYTHON} for the pidfd capability preflight"))?;
    ensure!(
        output.status.success(),
        "{PYTHON} lacks os.pidfd_open/signal.pidfd_send_signal (status {}); this observation \
         needs pidfd-based signalling and will not fall back to bare-pid signals. stderr: {}",
        output.status,
        String::from_utf8_lossy(&output.stderr).trim()
    );
    Ok(())
}

pub(crate) fn observer_identity(workspace: &Path) -> Result<crate::report::ObserverIdentity> {
    /// Every source root the observation really depends on: the observer example
    /// itself and the independent provider peer, whose staged SSE and CardKit
    /// behaviour the scenarios encode. Binding only the example would let the
    /// peer change without the run recording it.
    const ROOTS: [&str; 2] = [
        "code/pl-studio-acceptance/examples/bots_protocol_observe",
        "code/pl-provider-fixture/src",
    ];
    /// Bound on the whole source set, so a runaway or generated tree cannot turn
    /// the identity record into an unbounded hash walk.
    const MAX_FILES: usize = 256;
    const MAX_DEPTH: usize = 8;
    let mut relatives = Vec::new();
    for root in ROOTS {
        let path = workspace.join(root);
        let before = relatives.len();
        collect_observer_sources(&path, root, 0, MAX_DEPTH, &mut relatives)?;
        ensure!(
            relatives.len() > before,
            "observer source enumeration found no source file under {root}"
        );
    }
    ensure!(
        relatives.len() <= MAX_FILES,
        "observer source enumeration found {} source files, above the {MAX_FILES} bound",
        relatives.len()
    );
    let mut example_files = Vec::new();
    for relative in relatives {
        let path = workspace.join(&relative);
        example_files.push(crate::report::FileDigest {
            sha256: file_sha256(&path)?,
            path: relative,
        });
    }
    // The owner program runs from bytes frozen into this binary, so the executed
    // digest is recorded next to the workspace file: a reviewed file that was not
    // what ran, or the reverse, is then visible in the summary.
    example_files.push(crate::report::FileDigest {
        sha256: owner_source_sha256()?,
        path: format!("{OWNER_SOURCE_PATH} (executed bytes)"),
    });
    Ok(crate::report::ObserverIdentity {
        workspace_head: git_head(workspace),
        example_files,
    })
}

/// Recursively enumerates every `*.rs` and `*.py` file of one observer source root.
///
/// The identity record must cover the whole executable example, including files
/// added later, so a static list can silently stop describing what actually ran.
/// Traversal stays bounded in depth and count, skips dot entries, and refuses
/// symlinks instead of following a link out of the source root.
fn collect_observer_sources(
    dir: &Path,
    relative: &str,
    depth: usize,
    max_depth: usize,
    found: &mut Vec<String>,
) -> Result<()> {
    ensure!(
        depth <= max_depth,
        "observer source enumeration exceeded {max_depth} levels at {relative}"
    );
    let mut entries = Vec::new();
    for entry in fs::read_dir(dir)
        .with_context(|| format!("failed to read observer source directory {}", dir.display()))?
    {
        entries.push(entry?.path());
    }
    entries.sort();
    for path in entries {
        let name = path
            .file_name()
            .map_or_else(String::new, |name| name.to_string_lossy().into_owned());
        if name.is_empty() || name.starts_with('.') {
            continue;
        }
        let metadata = fs::symlink_metadata(&path)?;
        ensure!(
            !metadata.file_type().is_symlink(),
            "observer source enumeration refuses symlink {}",
            path.display()
        );
        let child = format!("{relative}/{name}");
        if metadata.is_dir() {
            collect_observer_sources(&path, &child, depth + 1, max_depth, found)?;
        } else if metadata.is_file() && (name.ends_with(".rs") || name.ends_with(".py")) {
            found.push(child);
        }
    }
    Ok(())
}

fn git_head(workspace: &Path) -> Option<String> {
    let output = std::process::Command::new("git")
        .arg("-C")
        .arg(workspace)
        .args(["rev-parse", "HEAD"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let head = String::from_utf8(output.stdout).ok()?;
    let head = head.trim();
    if head.is_empty() {
        None
    } else {
        Some(head.to_owned())
    }
}

pub(crate) fn require_linux_tools() -> Result<()> {
    for tool in [
        "dbus-run-session",
        "gnome-keyring-daemon",
        "gdbus",
        "sha256sum",
    ] {
        let status = std::process::Command::new(tool)
            .arg("--help")
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();
        if status.is_err() {
            bail!("{tool} is required for private Secret Service isolation");
        }
    }
    Ok(())
}
