//! Isolated provider/usage/MCP observation through the real native GUI.

use super::context_replay_recovery::wait_driver;
use super::*;
use pl_model::config::builtin_provider_catalog;
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
    let catalog = builtin_provider_catalog()?;
    for (suffix, preset, env) in [
        ("slow", "deepseek", SLOW_ENV),
        ("fast", "deepseek", FAST_ENV),
        ("denied", "zhipu-coding-plan", PLAN_ENV),
    ] {
        let mut provider = catalog
            .presets
            .iter()
            .find(|candidate| candidate.id.as_str() == preset)
            .context("missing usage preset")?
            .provider
            .clone();
        provider.name = format!("Usage {suffix}");
        provider.base_url = ready.base_url.clone();
        provider.bearer_token = None;
        provider.bearer_token_env = Some(env.to_owned());
        config
            .models
            .providers
            .insert(ProviderId::new(format!("{}-{suffix}", prefix()))?, provider);
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
            url: Some(format!("{host}/provider-usage/mcp")),
            headers: [("Authorization".into(), "Bearer fixture-usage-mcp".into())].into(),
            startup_timeout_secs: Some(180),
            ..StudioMcpServerEntry::default()
        },
    );
    persist_config(home, &config)
}

/// Checks the existing public composition boundary, without constructing a runtime or doing IO.
fn credential_contract() -> Result<Value> {
    let catalog = builtin_provider_catalog()?;
    let plan = catalog
        .presets
        .iter()
        .find(|preset| preset.id.as_str() == "zhipu-coding-plan")
        .context("missing Coding Plan preset")?
        .provider
        .clone();
    let ordinary = catalog
        .presets
        .iter()
        .find(|preset| preset.id.as_str() == "zhipu")
        .context("missing Zhipu preset")?
        .provider
        .clone();
    let mut config = StudioConfig::default_config()?;
    config.models.providers.clear();
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
        .providers
        .insert(ProviderId::new("ordinary")?, ordinary);
    assert_key(&config, None)?;
    let mut host_only = plan.clone();
    host_only.preset = None;
    host_only.bearer_token_env = None;
    host_only.bearer_token = Some("fixture-host-only-key".into());
    config
        .models
        .providers
        .insert(ProviderId::new("host-only")?, host_only);
    assert_key(&config, None)?;
    let mut first = plan.clone();
    first.bearer_token_env = None;
    first.bearer_token = Some("  ".into());
    let mut second = plan;
    second.bearer_token_env = None;
    second.bearer_token = Some("fixture-plan-b".into());
    config
        .models
        .providers
        .insert(ProviderId::new("plan-a")?, first.clone());
    config
        .models
        .providers
        .insert(ProviderId::new("plan-b")?, second);
    assert_key(&config, Some("fixture-plan-b"))?;
    first.bearer_token = Some("fixture-plan-a".into());
    config
        .models
        .providers
        .insert(ProviderId::new("plan-a")?, first);
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
    config.models.providers.remove(&ProviderId::new("plan-a")?);
    assert_key(&config, Some("fixture-plan-b"))?;
    config.models.providers.remove(&ProviderId::new("plan-b")?);
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
    let project = context.working.join("provider-usage-project");
    fs::create_dir(&project)?;
    fs::write(
        project.join("README.md"),
        "Isolated provider usage observation.\n",
    )?;
    ensure!(
        Command::new("git")
            .current_dir(&project)
            .args(["init", "-q"])
            .status()?
            .success(),
        "could not initialize isolated project"
    );
    let keyring_runtime = context.home.join("keyring-runtime");
    fs::create_dir(&keyring_runtime)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&keyring_runtime, fs::Permissions::from_mode(0o700))?;
    }
    fs::write(keyring_runtime.join("fixture-password"), "\n")?;
    let mut gui_errors = 0;
    let journey = (|| -> Result<()> {
        for phase in ["first", "restart"] {
            let gui_log = context
                .working
                .join(format!("provider-usage-gui-{phase}.log"));
            let driver_log = context
                .working
                .join(format!("provider-usage-driver-{phase}.log"));
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
                        "provider-usage observation currently requires Linux private D-Bus credential isolation"
                    );
                };
                command
                    .current_dir(context.workspace)
                    .env("ANYWORK_HOME", context.home)
                    .env("XDG_DATA_HOME", context.home.join("xdg-data"))
                    .env("XDG_CONFIG_HOME", context.home.join("xdg-config"))
                    .env("XDG_RUNTIME_DIR", &keyring_runtime)
                    .env_remove("GNOME_KEYRING_CONTROL")
                    .stdout(Stdio::from(log.try_clone()?))
                    .stderr(Stdio::from(log));
                // Preset drafts must not accidentally inherit a real user credential.
                let catalog = builtin_provider_catalog()?;
                for preset in &catalog.presets {
                    if let Some(env) = &preset.provider.bearer_token_env {
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
                        .presets
                        .iter()
                        .find(|preset| preset.id.as_str() == id)
                        .context("missing provider preset")?
                        .display_name
                        .clone())
                };
                command
                    .current_dir(context.app_dir)
                    .args(["run", "test_driver/provider_usage_journey.dart"])
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
                        .join(format!("provider-usage-summary-{phase}.json")),
                )?)?;
                ensure!(
                    summary["status"] == "complete" && summary["shutdown"] == "completed",
                    "provider usage journey did not confirm clean shutdown"
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
        "provider usage evidence contains unhandled GUI errors or unexpected fixture rejections"
    );
    ensure!(
        fixture_status?.success(),
        "provider fixture did not exit successfully"
    );
    println!(
        "Evidence: {} (human verdict pending)",
        context.output.display()
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
        ("fixture-usage-mcp".into(), "[fixture-key]"),
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
