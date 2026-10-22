//! Isolated Feishu platform peer and private Secret Service for `--bots-fixture`.
//!
//! Opt-in native GUI wiring only. Does not drive product UI, authorize a real
//! tenant, or change default model scenarios.

mod bots_env_samples;

use super::ManualGuiOptions;
use anyhow::{Context, Result, bail, ensure};
use pl_model::config::builtin_account_catalog;
use pl_provider_fixture::feishu::{
    FeishuPeer, FeishuReport, GroupChat, HistoryMessage, RegistrationBeginOptions,
    RegistrationPollScript, RegistrationTenantBrand, SyntheticEvent,
};
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const RESERVED_DEV_PORT: u16 = 1420;
const RESERVED_DEFAULT_SERVER_PORT: u16 = 1421;
const MANIFEST_MAX_BYTES: usize = 8 * 1024;
const BIND_ATTEMPTS: u32 = 8;

/// Keep gnome-keyring in the same session as the GUI. `exec` would drop the
/// EXIT trap, so cargo stays a child and both paths wait for the daemon.
const KEYRING_SCRIPT: &str = r#"
set -eu
gnome-keyring-daemon --foreground --unlock --components=secrets < "$XDG_RUNTIME_DIR/fixture-password" &
keyring=$!
trap 'kill "$keyring" 2>/dev/null || true; wait "$keyring" 2>/dev/null || true' EXIT
gdbus wait --session --timeout 10 org.freedesktop.secrets
printf 'acceptance_keyring_pid=%s\n' "$keyring"
status=0
"$@" || status=$?
kill "$keyring" 2>/dev/null || true
wait "$keyring" 2>/dev/null || true
exit "$status"
"#;

const RUNBOOK: &str = r#"# Bots fixture runbook

This `manual-gui --scenario gui --bots-fixture` run is a **local loopback**
Feishu platform environment plus the existing scripted model fixture.

- Real Feishu authorization, QR login, and tenant compatibility are **not**
  exercised.
- `verdict.json` stays `human_verdict=pending`. A successful environment start
  or process exit 0 is not a first-setup, model, or send pass.
- The peer starts with a synthetic registration poll script (`pending`). Local
  stdin environment commands may replace the **next** poll script. They do
  not click the GUI, complete authorization, or judge product results.
- Screenshots and raw Driver captures are not automatically redacted; do not
  treat them as PR-ready evidence.
- Do not copy App Secret, device code, verification URL, QR payload, or tokens
  into logs or reports.

## Local registration environment commands

Only this `--bots-fixture` session accepts the following stdin lines. Each one
calls the existing Feishu control setter on **this** peer. They are not GUI
clicks, tenant authorization, bot save, or a first-setup pass.

| stdin line | next poll script |
| --- | --- |
| `bots-env registration pending` | `Pending` |
| `bots-env registration slow-down` | `SlowDown` |
| `bots-env registration denied` | `Denied` |
| `bots-env registration expired` | `Expired` |
| `bots-env registration complete` | `Completed` with synthetic first-user identity |
| `bots-env registration complete-without-user` | `Completed` without a user identity |

The script applies to **future** registration polls. An in-flight poll keeps the
script captured when that handler entered. After the script is consumed, the
peer returns `Pending` again. Begin options stay interval 5s / expires 600s;
tenant brand stays Feishu.

`complete` uses the peer's already-approved synthetic credentials. It does not
accept App ID, secret, device code, URL, or user id from the operator.
`complete-without-user` does not mint a first trusted user; pair in the real GUI
with product permissions. Local expire is not a GUI cancel; cancel still requires
the product button.

Setting a script only means the mock reply was queued. `human_verdict` stays
pending. Unknown `bots-env` lines are rejected without changing the script and
without echoing the original input. Screenshots are not PR-ready unless taken
after Expired/Cancelled or redacted.

## Local message and conversation environment commands

Only this `--bots-fixture` session accepts the additional fixed stdin lines.
They take no parameters: no URL, secret, device code, open id, chat id, or
message body can be supplied, and unknown `bots-env` lines stay rejected
without echoing the original input.

| stdin line | fixed effect |
| --- | --- |
| `bots-env message unknown-direct` | delivers one fixed synthetic DM event from the additional pairing-only synthetic user `ou_anywork_fixture_unknown` in chat `oc_anywork_fixture_env_direct`, platform message id `om_anywork_fixture_env_unknown_direct`, body is the existing GUI model prompt |
| `bots-env message resend-direct` | delivers one fixed synthetic DM event from the same user and chat with a different platform message id `om_anywork_fixture_env_resend-direct` |
| `bots-env conversations prepare-pages` | replaces this peer's synthetic group directory and history with the bounded paging sample |

Message semantics:

- Both messages are plain inbound `im.message.receive_v1` events pushed through
  the peer control websocket path. Before the GUI approves the user, the
  product is expected to raise pairing only, with no model run; after approval,
  `resend-direct` is a new platform input because its message id differs.
- Re-invoking the same message action re-delivers the exact same fixed
  synthetic identity and body. The product observes a duplicate delivery, not a
  new platform input, and no new model run is implied.
- The action requires a live product websocket on this peer. Without one, the
  action fails with the peer's real websocket error and nothing is queued.
  Success only means the frame entered the live socket; it is not proof that
  the product consumed, approved, executed, or replied to the message.
- The model main flow may run at most once, at the resend stage, from these
  environment inputs. Registration ticket screenshots stay PR-safe only after
  Expired/Cancelled; raw Driver captures are never PR-ready evidence.

Paging sample semantics:

- 25 synthetic groups (the peer default group first, the second entry returns
  the real history permission-failure business code) and 25 synthetic history
  messages for the default group. Both exceed the real product default page
  limit of 20, so the GUI has a genuine next page; product paging defaults are
  not modified for the environment.
- The sample replaces only this peer's synthetic catalog. It is not GUI
  authorization, not a send, and not a product pass; `human_verdict` stays
  pending.
"#;

pub(super) struct BotsFixture {
    peer: Option<FeishuPeer>,
    runtime: Option<tokio::runtime::Runtime>,
    keyring: Option<tempfile::TempDir>,
    manifest: PathBuf,
}

/// Fixed local environment command for this peer's next registration poll.
#[derive(Clone, Copy)]
pub(super) enum RegistrationEnvCommand {
    Pending,
    SlowDown,
    Denied,
    Expired,
    Complete,
    CompleteWithoutUser,
}

pub(super) enum EnvLine {
    GuiAction,
    Registration(RegistrationEnvCommand),
    Message(MessageEnvCommand),
    Conversations(ConversationsEnvCommand),
    UnknownEnv,
}

/// Fixed synthetic inbound message delivery for this peer.
#[derive(Clone, Copy)]
pub(super) enum MessageEnvCommand {
    UnknownDirect,
    ResendDirect,
}

/// Fixed synthetic conversation catalog sample for this peer.
#[derive(Clone, Copy)]
pub(super) enum ConversationsEnvCommand {
    PreparePages,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FixtureManifest {
    schema_version: u32,
    studio_home: String,
    base_url: String,
}

struct PlatformShutdown {
    started: bool,
    listener_joined: bool,
    sockets_joined: bool,
    join_error: Option<String>,
    accepted: usize,
    rejected: usize,
    diagnostic_lines: Vec<String>,
}

impl PlatformShutdown {
    fn idle() -> Self {
        Self {
            started: false,
            listener_joined: true,
            sockets_joined: true,
            join_error: None,
            accepted: 0,
            rejected: 0,
            diagnostic_lines: Vec::new(),
        }
    }

    fn from_report(report: &FeishuReport) -> Self {
        Self {
            started: true,
            listener_joined: report.listener_joined,
            sockets_joined: report.sockets_joined,
            join_error: report.join_error.clone(),
            accepted: report.calls.iter().filter(|call| call.accepted).count(),
            rejected: report.calls.iter().filter(|call| !call.accepted).count(),
            diagnostic_lines: report.diagnostic_lines(),
        }
    }

    fn failed(join_error: String) -> Self {
        Self {
            started: true,
            listener_joined: false,
            sockets_joined: false,
            join_error: Some(join_error),
            accepted: 0,
            rejected: 0,
            diagnostic_lines: Vec::new(),
        }
    }

    fn resources_ok(&self) -> bool {
        self.listener_joined && self.sockets_joined && self.join_error.is_none()
    }
}

pub(super) fn validate(options: &ManualGuiOptions) -> Result<()> {
    if !options.bots_fixture {
        return Ok(());
    }
    ensure!(
        options.scenario == "gui",
        "--bots-fixture requires --scenario gui"
    );
    ensure!(
        cfg!(debug_assertions),
        "--bots-fixture requires a debug native acceptance build; profile/release paths are rejected"
    );
    ensure!(
        cfg!(target_os = "linux"),
        "--bots-fixture requires Linux private D-Bus/Secret Service isolation and does not fall back to the operator keyring or the real Feishu platform"
    );
    ensure!(
        options.startup_fault.is_none(),
        "--bots-fixture cannot be combined with --startup-fault"
    );
    ensure!(
        options.model_catalog_url.is_none()
            && options.model_catalog_inventory.is_none()
            && options.model_catalog_control.is_none()
            && !options.model_catalog_restart
            && !options.model_catalog_restart_check,
        "--bots-fixture cannot be combined with model-catalog flags"
    );
    ensure!(
        options.ssh_target.is_none() && options.ssh_workspace_parent.is_none(),
        "--bots-fixture cannot be combined with --ssh-target"
    );
    ensure!(
        options.web_search_fault.is_none()
            && options.web_search_accounts.is_none()
            && options.web_search_models.is_none()
            && options.web_search_probe.is_none(),
        "--bots-fixture cannot be combined with web-search flags"
    );
    ensure!(
        !options.timeline_displacement,
        "--bots-fixture cannot be combined with --timeline-displacement"
    );
    require_linux_tools()
}

pub(super) fn classify_line(line: &str) -> EnvLine {
    let trimmed = line.trim();
    if trimmed == "done" {
        return EnvLine::GuiAction;
    }
    let tokens: Vec<&str> = trimmed.split_whitespace().collect();
    if tokens.first().copied() != Some("bots-env") {
        return EnvLine::GuiAction;
    }
    env_command(&tokens).unwrap_or(EnvLine::UnknownEnv)
}

fn env_command(tokens: &[&str]) -> Option<EnvLine> {
    RegistrationEnvCommand::parse(tokens)
        .map(EnvLine::Registration)
        .or_else(|| MessageEnvCommand::parse(tokens).map(EnvLine::Message))
        .or_else(|| ConversationsEnvCommand::parse(tokens).map(EnvLine::Conversations))
}

impl RegistrationEnvCommand {
    fn parse(tokens: &[&str]) -> Option<Self> {
        match tokens {
            ["bots-env", "registration", "pending"] => Some(Self::Pending),
            ["bots-env", "registration", "slow-down"] => Some(Self::SlowDown),
            ["bots-env", "registration", "denied"] => Some(Self::Denied),
            ["bots-env", "registration", "expired"] => Some(Self::Expired),
            ["bots-env", "registration", "complete"] => Some(Self::Complete),
            ["bots-env", "registration", "complete-without-user"] => {
                Some(Self::CompleteWithoutUser)
            }
            _ => None,
        }
    }

    pub(super) fn action_code(self) -> &'static str {
        match self {
            Self::Pending => "env-registration-pending",
            Self::SlowDown => "env-registration-slow-down",
            Self::Denied => "env-registration-denied",
            Self::Expired => "env-registration-expired",
            Self::Complete => "env-registration-complete",
            Self::CompleteWithoutUser => "env-registration-complete-without-user",
        }
    }

    fn script(self) -> Vec<RegistrationPollScript> {
        vec![match self {
            Self::Pending => RegistrationPollScript::Pending,
            Self::SlowDown => RegistrationPollScript::SlowDown,
            Self::Denied => RegistrationPollScript::Denied,
            Self::Expired => RegistrationPollScript::Expired,
            Self::Complete => RegistrationPollScript::Completed {
                include_open_id: true,
            },
            Self::CompleteWithoutUser => RegistrationPollScript::Completed {
                include_open_id: false,
            },
        }]
    }
}

impl MessageEnvCommand {
    fn parse(tokens: &[&str]) -> Option<Self> {
        match tokens {
            ["bots-env", "message", "unknown-direct"] => Some(Self::UnknownDirect),
            ["bots-env", "message", "resend-direct"] => Some(Self::ResendDirect),
            _ => None,
        }
    }

    pub(super) fn action_code(self) -> &'static str {
        match self {
            Self::UnknownDirect => "env-message-unknown-direct",
            Self::ResendDirect => "env-message-resend-direct",
        }
    }

    fn event(self) -> SyntheticEvent {
        match self {
            Self::UnknownDirect => bots_env_samples::unknown_direct_event(),
            Self::ResendDirect => bots_env_samples::resend_direct_event(),
        }
    }
}

impl ConversationsEnvCommand {
    fn parse(tokens: &[&str]) -> Option<Self> {
        match tokens {
            ["bots-env", "conversations", "prepare-pages"] => Some(Self::PreparePages),
            _ => None,
        }
    }

    pub(super) fn action_code(self) -> &'static str {
        match self {
            Self::PreparePages => "env-conversations-prepare-pages",
        }
    }

    fn samples(self) -> (Vec<GroupChat>, Vec<HistoryMessage>) {
        match self {
            Self::PreparePages => (
                bots_env_samples::paged_groups(),
                bots_env_samples::paged_history(),
            ),
        }
    }
}

pub(super) fn with_cleanup(primary: Result<()>, cleanup: Result<()>) -> Result<()> {
    match (primary, cleanup) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) => Err(error),
        (Ok(()), Err(cleanup)) => Err(cleanup),
        (Err(error), Err(cleanup)) => {
            Err(error.context(format!("cleanup also failed: {cleanup:#}")))
        }
    }
}

pub(super) fn finish_optional(bots: Option<BotsFixture>, output: &Path) -> Result<()> {
    match bots {
        Some(bots) => bots.finish(output),
        None => Ok(()),
    }
}

pub(super) fn start(home: &Path, output: &Path) -> Result<BotsFixture> {
    fs::create_dir_all(home.join("xdg-data"))?;
    fs::create_dir_all(home.join("xdg-config"))?;
    let keyring = create_keyring_runtime()?;
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .context("failed to build the Feishu peer Tokio runtime")?;
    let mut fixture = BotsFixture {
        peer: None,
        runtime: Some(runtime),
        keyring: Some(keyring),
        manifest: PathBuf::new(),
    };
    if let Err(error) = fixture.start_inner(home, output) {
        let cleanup = fixture.finish(output);
        return match with_cleanup(Err(error), cleanup) {
            Ok(()) => Err(anyhow::anyhow!(
                "partial bots fixture start failed without an error"
            )),
            Err(error) => Err(error),
        };
    }
    Ok(fixture)
}

impl BotsFixture {
    fn start_inner(&mut self, home: &Path, output: &Path) -> Result<()> {
        let peer = {
            let runtime = self
                .runtime
                .as_ref()
                .context("missing Feishu peer Tokio runtime")?;
            start_peer(runtime)?
        };
        self.peer = Some(peer);
        let origin = {
            let runtime = self
                .runtime
                .as_ref()
                .context("missing Feishu peer Tokio runtime")?;
            let peer = self
                .peer
                .as_ref()
                .context("Feishu peer missing after start")?;
            configure_platform(runtime, peer);
            peer.origin().to_owned()
        };
        self.manifest = write_fixture_manifest(home, &origin)?;
        write_runbook(output)?;
        Ok(())
    }

    pub(super) fn gui_command(&self, workspace: &Path, home: &Path) -> Result<Command> {
        let keyring = self
            .keyring
            .as_ref()
            .context("missing private keyring runtime directory")?;
        ensure!(
            !self.manifest.as_os_str().is_empty(),
            "bots fixture manifest is not prepared"
        );
        let mut command = Command::new("dbus-run-session");
        command
            .current_dir(workspace)
            .arg("--")
            .arg("/bin/bash")
            .arg("-c")
            .arg(KEYRING_SCRIPT)
            .arg("bots-fixture-gui")
            .arg("cargo")
            .arg("xtask")
            .arg("run-gui")
            .arg("--driver")
            .arg("--log-level")
            .arg("info");
        apply_isolation_env(&mut command, home, keyring.path(), &self.manifest)?;
        Ok(command)
    }

    pub(super) fn apply_registration_env(&self, command: RegistrationEnvCommand) -> Result<()> {
        let runtime = self
            .runtime
            .as_ref()
            .context("missing Feishu peer Tokio runtime")?;
        let peer = self.peer.as_ref().context("Feishu peer is not started")?;
        let script = command.script();
        runtime.block_on(peer.control().set_registration_script(script));
        Ok(())
    }

    /// Push one fixed synthetic event through the peer's real websocket
    /// control path. Fails with the peer's own error when no product socket is
    /// live; success only means the frame entered the socket.
    pub(super) fn apply_message_env(&self, command: MessageEnvCommand) -> Result<()> {
        let runtime = self
            .runtime
            .as_ref()
            .context("missing Feishu peer Tokio runtime")?;
        let peer = self.peer.as_ref().context("Feishu peer is not started")?;
        runtime.block_on(peer.control().send_event(command.event()))?;
        Ok(())
    }

    /// Replace this peer's synthetic group directory and history sample.
    pub(super) fn apply_conversations_env(&self, command: ConversationsEnvCommand) -> Result<()> {
        let runtime = self
            .runtime
            .as_ref()
            .context("missing Feishu peer Tokio runtime")?;
        let peer = self.peer.as_ref().context("Feishu peer is not started")?;
        let (groups, history) = command.samples();
        runtime.block_on(async {
            let control = peer.control();
            control.set_groups(groups).await;
            control.set_history(history).await;
        });
        Ok(())
    }

    pub(super) fn finish(self, output: &Path) -> Result<()> {
        let facts = self.shutdown_inner();
        if !facts.started {
            return Ok(());
        }
        let write = write_platform_evidence(output, &facts);
        let resources = if facts.resources_ok() {
            Ok(())
        } else {
            Err(anyhow::anyhow!(
                "feishu peer resources did not join cleanly: listenerJoined={} socketsJoined={} joinError={}",
                facts.listener_joined,
                facts.sockets_joined,
                facts.join_error.as_deref().unwrap_or("none")
            ))
        };
        with_cleanup(resources, write)
    }

    fn shutdown_inner(mut self) -> PlatformShutdown {
        let facts = match (self.peer.take(), self.runtime.as_ref()) {
            (Some(mut peer), Some(runtime)) => match runtime.block_on(peer.shutdown()) {
                Ok(report) => PlatformShutdown::from_report(&report),
                Err(error) => PlatformShutdown::failed(error.to_string()),
            },
            (None, _) => PlatformShutdown::idle(),
            (Some(peer), None) => {
                drop(peer);
                PlatformShutdown::failed("missing Tokio runtime for feishu peer shutdown".into())
            }
        };
        drop(self.runtime.take());
        drop(self.keyring.take());
        facts
    }
}

impl Drop for BotsFixture {
    fn drop(&mut self) {
        // Last-resort abort only. Callers must `finish` so shutdown is awaited
        // on the owner thread; Drop must not `block_on` this runtime.
        if self.peer.is_some() {
            eprintln!(
                "bots fixture dropped without shutdown; aborting the Feishu peer instead of joining it"
            );
        }
        self.peer.take();
        self.runtime.take();
        self.keyring.take();
    }
}

fn start_peer(runtime: &tokio::runtime::Runtime) -> Result<FeishuPeer> {
    let mut last_error = None;
    for _ in 0..BIND_ATTEMPTS {
        let mut peer = runtime
            .block_on(FeishuPeer::start())
            .context("failed to start the isolated Feishu peer")?;
        let port = peer.address().port();
        if port != 0 && port != RESERVED_DEV_PORT && port != RESERVED_DEFAULT_SERVER_PORT {
            return Ok(peer);
        }
        last_error = Some(match runtime.block_on(peer.shutdown()) {
            Ok(report) => match report.join_error {
                Some(join) => format!("ephemeral port {port} is reserved; join {join}"),
                None => format!("ephemeral port {port} is reserved"),
            },
            Err(error) => {
                format!("ephemeral port {port} is reserved; shutdown failed: {error:#}")
            }
        });
    }
    bail!(
        "{}",
        last_error.unwrap_or_else(|| "could not bind the Feishu peer outside 1420/1421".into())
    )
}

fn configure_platform(runtime: &tokio::runtime::Runtime, peer: &FeishuPeer) {
    runtime.block_on(async {
        let control = peer.control();
        control
            .set_registration_script(vec![RegistrationPollScript::Pending])
            .await;
        control
            .set_registration_begin_options(RegistrationBeginOptions::default())
            .await;
        control
            .set_registration_tenant_brand(Some(RegistrationTenantBrand::Feishu))
            .await;
    });
}

fn write_fixture_manifest(home: &Path, feishu_origin: &str) -> Result<PathBuf> {
    let canonical_home = fs::canonicalize(home).context("studio home cannot be canonicalized")?;
    let origin = feishu_origin.trim_end_matches('/');
    let port = parse_loopback_port(origin)?;
    ensure!(
        port != RESERVED_DEV_PORT && port != RESERVED_DEFAULT_SERVER_PORT && port != 0,
        "fixture origin must be http://127.0.0.1:<ephemeral-port>"
    );
    let manifest = FixtureManifest {
        schema_version: 1,
        studio_home: canonical_home.to_string_lossy().into_owned(),
        base_url: format!("{origin}/"),
    };
    let bytes = serde_json::to_vec(&manifest)?;
    ensure!(
        bytes.len() <= MANIFEST_MAX_BYTES,
        "bots fixture manifest exceeds 8KiB"
    );
    let path = canonical_home.join("bots-fixture-manifest.json");
    let tmp = canonical_home.join(".bots-fixture-manifest.json.tmp");
    fs::write(&tmp, &bytes).context("failed to write bots fixture manifest")?;
    fs::rename(&tmp, &path).context("failed to publish bots fixture manifest")?;
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
    rest.parse().context("fixture origin port is not a u16")
}

fn write_runbook(output: &Path) -> Result<()> {
    fs::write(output.join("bots-fixture-runbook.md"), RUNBOOK)
        .context("failed to write bots fixture runbook")
}

fn write_platform_evidence(output: &Path, facts: &PlatformShutdown) -> Result<()> {
    let evidence = serde_json::json!({
        "humanVerdict": "pending",
        "realFeishuCompatibility": "not-exercised",
        "localMock": true,
        "listenerJoined": facts.listener_joined,
        "socketsJoined": facts.sockets_joined,
        "joinError": facts.join_error,
        "acceptedCalls": facts.accepted,
        "rejectedCalls": facts.rejected,
        "resources": if facts.resources_ok() { "success" } else { "incomplete" },
        "diagnostics": facts.diagnostic_lines,
        "registrationScript": "pending",
        "note": "Environment resource facts only. This is not a first-setup or send verdict.",
    });
    fs::write(
        output.join("feishu-platform.json"),
        serde_json::to_vec_pretty(&evidence)?,
    )
    .context("failed to write feishu platform evidence")
}

fn apply_isolation_env(
    command: &mut Command,
    home: &Path,
    keyring_runtime: &Path,
    manifest: &Path,
) -> Result<()> {
    command
        .env("HOME", home)
        .env("ANYWORK_HOME", home)
        .env("XDG_DATA_HOME", home.join("xdg-data"))
        .env("XDG_CONFIG_HOME", home.join("xdg-config"))
        .env("XDG_RUNTIME_DIR", keyring_runtime)
        .env("ANYWORK_BOTS_FIXTURE_MANIFEST", manifest)
        .env_remove("GNOME_KEYRING_CONTROL")
        .env_remove("DBUS_SESSION_BUS_ADDRESS")
        .env_remove("GNOME_KEYRING_PID");
    preserve_toolchain_caches(command);
    clear_template_bearer_env(command)?;
    Ok(())
}

fn preserve_toolchain_caches(command: &mut Command) {
    const EXPLICIT: &[&str] = &[
        "RUSTUP_HOME",
        "CARGO_HOME",
        "CARGO_TARGET_DIR",
        "PUB_CACHE",
        "RUSTUP_TOOLCHAIN",
        "RUSTC",
        "CARGO",
        "FLUTTER_ROOT",
    ];
    for key in EXPLICIT {
        if let Some(value) = std::env::var_os(key).filter(|value| !value.is_empty()) {
            command.env(key, value);
        }
    }
    keep_operator_tool_dir(command, "RUSTUP_HOME", ".rustup");
    keep_operator_tool_dir(command, "CARGO_HOME", ".cargo");
    keep_operator_tool_dir(command, "PUB_CACHE", ".pub-cache");
}

fn keep_operator_tool_dir(command: &mut Command, key: &str, relative: &str) {
    if std::env::var_os(key).is_some_and(|value| !value.is_empty()) {
        return;
    }
    let Some(home) = std::env::var_os("HOME") else {
        return;
    };
    let path = PathBuf::from(home).join(relative);
    if path.exists() {
        command.env(key, path);
    }
}

fn clear_template_bearer_env(command: &mut Command) -> Result<()> {
    let catalog = builtin_account_catalog().context("missing account catalog")?;
    for preset in &catalog.templates {
        if let Some(env) = &preset.account.bearer_token_env {
            command.env_remove(env);
        }
    }
    Ok(())
}

fn create_keyring_runtime() -> Result<tempfile::TempDir> {
    let keyring = tempfile::Builder::new()
        .prefix("aw-bots-kr-")
        .tempdir()
        .context("create isolated keyring runtime directory")?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(keyring.path(), fs::Permissions::from_mode(0o700))?;
        ensure_keyring_runtime_fits(keyring.path())?;
    }
    fs::write(keyring.path().join("fixture-password"), "\n")?;
    Ok(keyring)
}

/// The private keyring daemon binds its control socket below `XDG_RUNTIME_DIR`.
#[cfg(unix)]
fn ensure_keyring_runtime_fits(runtime: &Path) -> Result<()> {
    const SUN_PATH_BYTES: usize = 108;
    const DAEMON_SUFFIX_BYTES: usize = 32;
    let bytes = std::os::unix::ffi::OsStrExt::as_bytes(runtime.as_os_str()).len();
    ensure!(
        bytes + DAEMON_SUFFIX_BYTES < SUN_PATH_BYTES,
        "isolated keyring runtime path {} is {bytes} bytes; it must stay under {} bytes so the \
         private daemon control socket fits AF_UNIX limits",
        runtime.display(),
        SUN_PATH_BYTES - DAEMON_SUFFIX_BYTES
    );
    Ok(())
}

fn require_linux_tools() -> Result<()> {
    for tool in ["dbus-run-session", "gnome-keyring-daemon", "gdbus"] {
        if Command::new(tool)
            .arg("--help")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .is_err()
        {
            bail!("{tool} is required for private Secret Service isolation");
        }
    }
    Ok(())
}
