//! Isolated account/usage/MCP observation through the real native GUI.

use super::context_replay_recovery::wait_driver;
use super::*;
use pl_model::config::builtin_account_catalog;
use pl_studio_runtime::config::{StudioBuiltinMcpServerState, effective_mcp_servers};
use serde_json::{Value, json};

const SLOW_ENV: &str = "ANYWORK_FIXTURE_USAGE_SLOW";
const FAST_ENV: &str = "ANYWORK_FIXTURE_USAGE_FAST";
const PLAN_ENV: &str = "ANYWORK_FIXTURE_USAGE_PLAN";

pub(super) struct Scenario<'a> {
    pub workspace: &'a Path,
    pub app_dir: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    pub fixture_log: &'a Path,
    pub requests_file: &'a Path,
    pub interrupt: &'a mpsc::Receiver<()>,
}

fn prefix() -> String {
    format!("usage-{}", std::process::id())
}

pub(super) fn write_config(home: &Path, ready: &FixtureReady) -> Result<()> {
    let mut config = fixture_config(home, ready, ModelTransportProfile::responses_http())?;
    let catalog = builtin_account_catalog()?;
    for (suffix, preset, env) in [
        ("slow", "deepseek", SLOW_ENV),
        ("fast", "deepseek", FAST_ENV),
        ("denied", "zhipu-coding-plan", PLAN_ENV),
    ] {
        let mut account = catalog
            .templates
            .iter()
            .find(|candidate| candidate.id.as_str() == preset)
            .context("missing usage preset")?
            .account
            .clone();
        account.name = format!("Usage {suffix}");
        account.base_url = ready.base_url.clone();
        account.bearer_token = None;
        account.bearer_token_env = Some(env.to_owned());
        config
            .models
            .accounts
            .insert(AccountId::new(format!("{}-{suffix}", prefix()))?, account);
    }
    // Never connect an official endpoint or invoke npm in this isolated scenario.
    for id in pl_studio_runtime::config::builtin_mcp_server_ids() {
        config.mcp.builtin_servers.insert(
            id.to_owned(),
            StudioBuiltinMcpServerState { enabled: false },
        );
    }
    let host = ready
        .base_url
        .strip_suffix("/v1")
        .context("fixture URL has no /v1")?;
    config.mcp.servers.insert(
        "fixture_usage_mcp".into(),
        StudioMcpServerEntry {
            enabled: true,
            transport: McpServerTransport::StreamableHttp,
            // MCP 路径属于 fixture 的既有契约：直接复用其可见常量，不改外部协议。
            url: Some(format!(
                "{host}{}",
                pl_provider_fixture::PROVIDER_USAGE_MCP_PATH
            )),
            headers: [(
                "Authorization".into(),
                format!("Bearer {}", pl_provider_fixture::PROVIDER_USAGE_MCP_KEY),
            )]
            .into(),
            startup_timeout_secs: Some(180),
            ..StudioMcpServerEntry::default()
        },
    );
    persist_config(home, &config)
}

/// Checks the existing public composition boundary, without constructing a runtime or doing IO.
fn credential_contract() -> Result<Value> {
    let catalog = builtin_account_catalog()?;
    let plan = catalog
        .templates
        .iter()
        .find(|preset| preset.id.as_str() == "zhipu-coding-plan")
        .context("missing Coding Plan preset")?
        .account
        .clone();
    let ordinary = catalog
        .templates
        .iter()
        .find(|preset| preset.id.as_str() == "zhipu")
        .context("missing Zhipu preset")?
        .account
        .clone();
    let mut config = StudioConfig::default_config()?;
    config.models.accounts.clear();
    config.mcp.builtin_servers.clear();
    let assert_key = |config: &StudioConfig, expected: Option<&str>| -> Result<()> {
        ensure!(
            effective_mcp_servers(config).len()
                == pl_studio_runtime::config::builtin_mcp_server_ids().len(),
            "builtin composition is incomplete"
        );
        for server in effective_mcp_servers(config)
            .into_values()
            .filter(|server| pl_studio_runtime::config::is_builtin_mcp_server_id(&server.id))
        {
            ensure!(
                server.bearer_token.as_deref() == expected,
                "builtin MCP credential source differs from the contract"
            );
            ensure!(
                (server.status_kind == pl_studio_runtime::config::McpServerStatusKind::Enabled)
                    == expected.is_some(),
                "empty key enabled a builtin MCP transport"
            );
        }
        Ok(())
    };
    assert_key(&config, None)?;
    let mut ordinary = ordinary;
    ordinary.bearer_token_env = None;
    ordinary.bearer_token = Some("fixture-ordinary-key".into());
    config
        .models
        .accounts
        .insert(AccountId::new("ordinary")?, ordinary);
    assert_key(&config, None)?;
    let mut host_only = plan.clone();
    host_only.template = None;
    host_only.bearer_token_env = None;
    host_only.bearer_token = Some("fixture-host-only-key".into());
    config
        .models
        .accounts
        .insert(AccountId::new("host-only")?, host_only);
    assert_key(&config, None)?;
    let mut first = plan.clone();
    first.bearer_token_env = None;
    first.bearer_token = Some("  ".into());
    let mut second = plan;
    second.bearer_token_env = None;
    second.bearer_token = Some("fixture-plan-b".into());
    config
        .models
        .accounts
        .insert(AccountId::new("plan-a")?, first.clone());
    config
        .models
        .accounts
        .insert(AccountId::new("plan-b")?, second);
    assert_key(&config, Some("fixture-plan-b"))?;
    first.bearer_token = Some("fixture-plan-a".into());
    config
        .models
        .accounts
        .insert(AccountId::new("plan-a")?, first);
    assert_key(&config, Some("fixture-plan-a"))?;
    for id in pl_studio_runtime::config::builtin_mcp_server_ids() {
        config.mcp.builtin_servers.insert(
            id.to_owned(),
            StudioBuiltinMcpServerState { enabled: false },
        );
    }
    ensure!(
        effective_mcp_servers(&config).into_values().all(|server| {
            server.status_kind == pl_studio_runtime::config::McpServerStatusKind::Disabled
        }),
        "explicit builtin disable was lost"
    );
    config.mcp.builtin_servers.clear();
    config.models.accounts.remove(&AccountId::new("plan-a")?);
    assert_key(&config, Some("fixture-plan-b"))?;
    config.models.accounts.remove(&AccountId::new("plan-b")?);
    assert_key(&config, None)?;
    Ok(
        json!({"status":"complete", "codingPlanOnly":true, "noHostFallback":true,
        "blankKeyIgnored":true, "stableSelection":true, "rotationRemoval":true,
        "explicitDisablePreserved":true, "externalConnections":0}),
    )
}

pub(super) fn run(
    context: &Scenario<'_>,
    mut fixture: OwnedProcess,
    ready: &FixtureReady,
) -> Result<()> {
    fs::write(
        context.output.join("mcp-credential-contract.json"),
        serde_json::to_vec_pretty(&credential_contract()?)?,
    )?;
    let project = context.working.join("account-usage-project");
    fs::create_dir(&project)?;
    fs::write(
        project.join("README.md"),
        "Isolated account usage observation.\n",
    )?;
    ensure!(
        Command::new("git")
            .current_dir(&project)
            .args(["init", "-q"])
            .status()?
            .success(),
        "could not initialize isolated project"
    );
    // A short, scenario-owned runtime directory keeps the private keyring daemon's control socket
    // inside the platform's `AF_UNIX` path limit. `ANYWORK_HOME` alone does not namespace OS
    // credentials, so this must stay isolated from the operator's keyring, and it must not inherit
    // the (possibly very deep) workspace path: the daemon cannot bind a truncated socket path.
    // The directory lives until both phases and the fixture have been reaped.
    let keyring_runtime = tempfile::Builder::new()
        .prefix("aw-usage-keyring-")
        .tempdir()
        .context("create isolated keyring runtime directory")?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(keyring_runtime.path(), fs::Permissions::from_mode(0o700))?;
        ensure_keyring_runtime_fits(keyring_runtime.path())?;
    }
    fs::write(keyring_runtime.path().join("fixture-password"), "\n")?;
    let mut gui_errors = 0;
    let journey = (|| -> Result<()> {
        for phase in ["first", "restart"] {
            let gui_log = context
                .working
                .join(format!("account-usage-gui-{phase}.log"));
            let driver_log = context
                .working
                .join(format!("account-usage-driver-{phase}.log"));
            let result = (|| -> Result<()> {
                let log = File::create(&gui_log)?;
                // The UI deliberately creates ordinary preset IDs. ANYWORK_HOME
                // alone does not namespace OS credentials, so never let this probe
                // consult the operator's Secret Service or its keyring files.
                let mut command = if cfg!(target_os = "linux") {
                    let mut command = Command::new("dbus-run-session");
                    command.args(["--", "/bin/bash", "-c", r#"
set -eu
gnome-keyring-daemon --foreground --unlock --components=secrets < "$XDG_RUNTIME_DIR/fixture-password" &
keyring=$!
trap 'kill "$keyring" 2>/dev/null || true; wait "$keyring" 2>/dev/null || true' EXIT
gdbus wait --session --timeout 10 org.freedesktop.secrets
printf 'acceptance_keyring_pid=%s\n' "$keyring"
cargo xtask run-gui --driver
"#]);
                    command
                } else {
                    bail!(
                        "account-usage observation currently requires Linux private D-Bus credential isolation"
                    );
                };
                command
                    .current_dir(context.workspace)
                    .env("ANYWORK_HOME", context.home)
                    .env("XDG_DATA_HOME", context.home.join("xdg-data"))
                    .env("XDG_CONFIG_HOME", context.home.join("xdg-config"))
                    .env("XDG_RUNTIME_DIR", keyring_runtime.path())
                    .env_remove("GNOME_KEYRING_CONTROL")
                    .stdout(Stdio::from(log.try_clone()?))
                    .stderr(Stdio::from(log));
                // Preset drafts must not accidentally inherit a real user credential.
                let catalog = builtin_account_catalog()?;
                for preset in &catalog.templates {
                    if let Some(env) = &preset.account.bearer_token_env {
                        command.env_remove(env);
                    }
                }
                command
                    .env(SLOW_ENV, "fixture-usage-slow")
                    .env(FAST_ENV, "fixture-usage-fast")
                    .env(PLAN_ENV, "fixture-usage-denied");
                let mut gui = OwnedProcess::start(&mut command, false)?;
                let vm_url = wait_for_vm(&gui_log, &mut gui, &mut fixture, context.interrupt)?;
                let log = File::create(&driver_log)?;
                let mut command = process::path_command("dart", &[]);
                let label = |id: &str| -> Result<String> {
                    Ok(catalog
                        .templates
                        .iter()
                        .find(|preset| preset.id.as_str() == id)
                        .context("missing account preset")?
                        .display_name
                        .clone())
                };
                command
                    .current_dir(context.app_dir)
                    .args(["run", "test_driver/account_usage_journey.dart"])
                    .arg(vm_url)
                    .arg(&project)
                    .arg(context.output)
                    .arg(&ready.base_url)
                    .arg(prefix())
                    .arg(label("zhipu-coding-plan")?)
                    .arg(label("zhipu")?)
                    .arg(phase)
                    .stdout(Stdio::from(log.try_clone()?))
                    .stderr(Stdio::from(log));
                let mut driver = OwnedProcess::start(&mut command, false)?;
                let gui_pid = gui.child.id();
                let driver_pid = driver.child.id();
                wait_driver(&mut driver, &mut gui, &mut fixture, context.interrupt)?;
                let summary: Value = serde_json::from_slice(&fs::read(
                    context
                        .output
                        .join(format!("account-usage-summary-{phase}.json")),
                )?)?;
                ensure!(
                    summary["status"] == "complete" && summary["shutdown"] == "completed",
                    "account usage journey did not confirm clean shutdown"
                );
                drop(driver);
                drop(gui);
                fs::write(
                    context.output.join(format!("lifecycle-{phase}.json")),
                    serde_json::to_vec_pretty(&json!({
                        "guiLauncherPid":gui_pid,"driverLauncherPid":driver_pid,
                        "shutdown":"completed","ownersReapedAt":SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs()
                    }))?,
                )?;
                Ok(())
            })();
            for (source, name) in [
                (&gui_log, format!("gui-{phase}.log")),
                (&driver_log, format!("driver-{phase}.log")),
            ] {
                if source.is_file() {
                    write_scenario_log(source, &context.output.join(name), context)?;
                }
            }
            if gui_log.is_file() {
                gui_errors += count_gui_errors(&gui_log)?;
            }
            result?;
            ensure!(gui_errors == 0, "unhandled GUI errors in {phase} phase");
        }
        Ok(())
    })();
    let fixture_status = fixture.stop(context.requests_file);
    drop(fixture);
    write_fixture_log(context.fixture_log, &context.output.join("fixture.log"))?;
    let requests: Vec<pl_provider_fixture::RecordedRequest> = if context.requests_file.is_file() {
        let requests: Vec<pl_provider_fixture::RecordedRequest> =
            serde_json::from_slice(&fs::read(context.requests_file)?)?;
        write_requests(&requests, &context.output.join("requests.json"))?;
        requests
    } else {
        Vec::new()
    };
    let unexpected = requests
        .iter()
        .filter(|request| !request.accepted)
        .filter(|request| {
            !(request.method == "GET"
                && request.path == "/api/monitor/usage/quota/limit"
                && request.body["keyAlias"] == "denied"
                && request.diagnostic.as_ref().is_some_and(|diagnostic| {
                    diagnostic.category == pl_provider_fixture::DENIED_QUOTA_CATEGORY
                }))
        })
        .count();
    fs::write(
        context.output.join("collection.json"),
        serde_json::to_vec_pretty(&json!({
            "scenario":"provider-usage","journey":if journey.is_ok(){"complete"}else{"failed"},
            "error":journey.as_ref().err().map(ToString::to_string),"guiErrors":gui_errors,
            "unexpectedRejections":unexpected,"fixtureExitedSuccessfully":fixture_status.as_ref().is_ok_and(std::process::ExitStatus::success),
            "humanVerdict":"pending","realProviderCompatibility":"not-exercised"
        }))?,
    )?;
    journey?;
    ensure!(
        gui_errors == 0 && unexpected == 0,
        "account usage evidence contains unhandled GUI errors or unexpected fixture rejections"
    );
    ensure!(
        fixture_status?.success(),
        "account fixture did not exit successfully"
    );
    println!(
        "Evidence: {} (human verdict pending)",
        context.output.display()
    );
    Ok(())
}

/// The private keyring daemon binds its control socket *below* `XDG_RUNTIME_DIR`. The kernel
/// silently truncates an over-long `sun_path`, which then surfaces as an unrelated daemon error, so
/// an unusable runtime directory must fail here with the real cause instead of being truncated,
/// shortened or moved onto a fixed insecure path.
#[cfg(unix)]
fn ensure_keyring_runtime_fits(runtime: &Path) -> Result<()> {
    /// `sun_path` is 108 bytes on Linux including the terminating NUL, and the daemon adds its own
    /// `keyring-XXXXXX/control` entry below the runtime directory.
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

fn write_scenario_log(source: &Path, destination: &Path, context: &Scenario<'_>) -> Result<()> {
    // This scenario owns every prompt and credential. Keep failure causes that
    // the generic startup-only projection intentionally omits.
    let redactions = [
        (
            context.working.to_string_lossy().into_owned(),
            "[isolated-root]",
        ),
        (
            context.workspace.to_string_lossy().into_owned(),
            "[workspace]",
        ),
        ("fixture-usage-slow".into(), "[fixture-key]"),
        ("fixture-usage-fast".into(), "[fixture-key]"),
        ("fixture-usage-denied".into(), "[fixture-key]"),
        (
            pl_provider_fixture::PROVIDER_USAGE_MCP_KEY.into(),
            "[fixture-key]",
        ),
    ];
    let text = fs::read_to_string(source)?
        .lines()
        .map(|line| sanitize_driver_line(line, &redactions))
        .collect::<Vec<_>>()
        .join("\n");
    fs::write(destination, text)?;
    Ok(())
}

fn write_requests(
    requests: &[pl_provider_fixture::RecordedRequest],
    destination: &Path,
) -> Result<()> {
    let safe = requests
        .iter()
        .map(|request| {
            json!({
                "method": request.method,
                "path": request.path,
                "accepted": request.accepted,
                "keyAlias": request.body.get("keyAlias"),
                "rpcMethod": request.body.get("method"),
                "diagnostic": request.diagnostic,
            })
        })
        .collect::<Vec<_>>();
    fs::write(destination, serde_json::to_vec_pretty(&safe)?)?;
    Ok(())
}
