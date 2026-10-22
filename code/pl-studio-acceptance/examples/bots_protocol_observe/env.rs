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

pub(crate) fn observer_identity(workspace: &Path) -> Result<crate::report::ObserverIdentity> {
    const FILES: &[&str] = &[
        "code/pl-studio-acceptance/examples/bots_protocol_observe/main.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/cases.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/cases/registration/mod.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/cases/registration/lifecycle.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/cases/registration/no_user.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/cases/registration/observe.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/cases/replies/mod.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/cases/replies/interaction_restart.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/cases/replies/send_outcomes.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/env.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/http.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/report.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/server.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/sqlite.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/topic.rs",
        "code/pl-studio-acceptance/examples/bots_protocol_observe/thread_watch.rs",
    ];
    let mut example_files = Vec::new();
    for relative in FILES {
        let path = workspace.join(relative);
        example_files.push(crate::report::FileDigest {
            path: relative.to_string(),
            sha256: file_sha256(&path)?,
        });
    }
    Ok(crate::report::ObserverIdentity {
        workspace_head: git_head(workspace),
        example_files,
    })
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
