#![cfg(target_os = "linux")]
//! Production host adapters over a real registry, supervised helper and LSP peer.
use pl_agent_tool::Tool;
use pl_core::{context::OpaquePayload, tool::opaque::CallContext};
use pl_lsp::{catalog::LspUserServerConfig, query::LspQueryOperation, runtime::LspRuntimeRegistry};
use pl_tool::{
    lsp::{LspPathBinding, LspToolKind, ThreadLspTool},
    workspace::{AgentWorkspace, ToolWorkspace},
};
use std::{
    path::{Path, PathBuf},
    sync::Arc,
};

use pl_lsp::host::ExecutorLspHost;
use pl_remote_helper::Executor;

fn context() -> CallContext {
    CallContext {
        thread_id: "lsp-binding".into(),
        turn_id: "turn".into(),
        call_id: "call".into(),
        cancellation: Default::default(),
        extensions: Default::default(),
        catalog: Arc::from([]),
        extension_sequence: 0,
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
    }
}

fn query(path: &Path) -> OpaquePayload {
    OpaquePayload::new(
        "application/json",
        1,
        serde_json::json!({
            "languageId": "fixture", "operation": "hover",
            "filePath": path, "line": 2, "character": 3
        })
        .to_string(),
    )
    .unwrap()
}

#[tokio::test]
async fn hosted_lsp_tools_share_registry_and_preserve_path_authorization() -> anyhow::Result<()> {
    let root = tempfile::tempdir()?;
    let outside = tempfile::tempdir()?;
    tokio::fs::write(root.path().join("fixture.marker"), b"").await?;
    tokio::fs::write(root.path().join("source.fixture"), b"line one\nline two\n").await?;
    let outside_source = outside.path().join("outside.fixture");
    tokio::fs::write(&outside_source, b"private").await?;
    std::os::unix::fs::symlink(&outside_source, root.path().join("escape.fixture"))?;
    let log = root.path().join("requests.jsonl");
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/support/lsp_fixture.py");
    let config = LspUserServerConfig {
        command: "python3".into(),
        args: vec![
            "-u".into(),
            fixture.display().to_string(),
            log.display().to_string(),
        ],
        language_ids: vec!["fixture".into()],
        detection: vec!["fixture.marker".into()],
        extensions: vec!["fixture".into()],
        display_name: Some("Fixture".into()),
        operations: vec![LspQueryOperation::Hover],
        ..Default::default()
    };
    let registry = LspRuntimeRegistry::new();
    let host = local_host(root.path())?;
    registry
        .configure_workspace(root.path(), Some(host), [("fixture".into(), config)].into())
        .await;
    wait_ready(&registry, root.path(), "fixture").await?;
    let paths = LspPathBinding::Local(ToolWorkspace::new(AgentWorkspace::local(root.path())));
    let capabilities = ThreadLspTool::new(
        registry.clone(),
        paths.clone(),
        LspToolKind::Capabilities,
        LspToolKind::Capabilities.declaration(),
    );
    let queries = ThreadLspTool::new(
        registry.clone(),
        paths,
        LspToolKind::Query,
        LspToolKind::Query.declaration(),
    );
    // Always close the registry before propagating assertions or tool failures.
    let observed: anyhow::Result<()> = async {
        let result = capabilities
            .execute(OpaquePayload::new("application/json", 1, "{}")?, context())
            .await?;
        let value: serde_json::Value = serde_json::from_str(result.payload().content())?;
        anyhow::ensure!(value["servers"][0]["ready"] == true, "{value}");
        anyhow::ensure!(value["servers"][0]["languageIds"][0] == "fixture");
        let result = queries
            .execute(query(Path::new("source.fixture")), context())
            .await?;
        let value: serde_json::Value = serde_json::from_str(result.payload().content())?;
        anyhow::ensure!(value["operation"] == "hover");
        anyhow::ensure!(value["serverId"] == "fixture");
        anyhow::ensure!(
            value["result"]
                .as_str()
                .is_some_and(|text| text.contains("fixture hover"))
        );
        let before = tokio::fs::read_to_string(&log).await?;
        for forbidden in [&outside_source, &root.path().join("escape.fixture")] {
            let error = queries
                .execute(query(forbidden), context())
                .await
                .expect_err("path grant must remain host-owned");
            anyhow::ensure!(!error.to_string().contains("fixture hover"));
            anyhow::ensure!(
                tokio::fs::read_to_string(&log).await? == before,
                "denied paths must not reach the server"
            );
        }
        Ok(())
    }
    .await;
    let shutdown = registry.shutdown().await;
    observed?;
    shutdown?;
    let messages: Vec<serde_json::Value> = tokio::fs::read_to_string(&log)
        .await?
        .lines()
        .map(serde_json::from_str)
        .collect::<Result<_, _>>()?;
    let hovers: Vec<_> = messages
        .iter()
        .filter(|entry| entry["method"] == "textDocument/hover")
        .collect();
    anyhow::ensure!(hovers.len() == 1);
    anyhow::ensure!(hovers[0]["params"]["position"]["line"] == 1);
    anyhow::ensure!(hovers[0]["params"]["position"]["character"] == 2);
    anyhow::ensure!(messages.iter().any(|entry| entry["method"] == "shutdown"));
    anyhow::ensure!(messages.iter().any(|entry| entry["method"] == "exit"));
    Ok(())
}

async fn wait_ready(registry: &LspRuntimeRegistry, root: &Path, id: &str) -> anyhow::Result<()> {
    wait_phase(
        registry,
        root,
        id,
        pl_lsp::runtime::LspLifecyclePhase::Ready,
    )
    .await
}

async fn wait_phase(
    registry: &LspRuntimeRegistry,
    root: &Path,
    id: &str,
    phase: pl_lsp::runtime::LspLifecyclePhase,
) -> anyhow::Result<()> {
    let mut updates = registry.subscribe();
    tokio::time::timeout(std::time::Duration::from_secs(15), async {
        loop {
            let snapshots = registry.snapshots_for_workspace(root).await;
            if snapshots
                .iter()
                .any(|server| server.id == id && server.phase == phase)
            {
                return Ok::<_, anyhow::Error>(());
            }
            updates.recv().await?;
        }
    })
    .await??;
    Ok(())
}

fn fixture_config(language: &str, log: &str) -> LspUserServerConfig {
    LspUserServerConfig {
        command: "python3".into(),
        args: vec![
            "-u".into(),
            PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("tests/support/lsp_fixture.py")
                .display()
                .to_string(),
            format!("{{workspaceRoot}}/{log}"),
        ],
        language_ids: vec![language.into()],
        extensions: vec![format!(".{language}")],
        operations: LspQueryOperation::all().to_vec(),
        ..Default::default()
    }
}
async fn write_config(
    root: &Path,
    id: &str,
    config: LspUserServerConfig,
) -> anyhow::Result<PathBuf> {
    let directory = root.join(".anywork/lsp");
    tokio::fs::create_dir_all(&directory).await?;
    let path = directory.join(format!("{id}.toml"));
    // This fixture writes only strings/arrays and its one known nested settings
    // shape; schema behavior is tested independently in pl-lsp's parser tests.
    let mut content = format!(
        "schema_version = 1\nid = {}\ncommand = {}\nargs = {}\nlanguage_ids = {}\nextensions = {}\n",
        serde_json::to_string(id)?,
        serde_json::to_string(&config.command)?,
        serde_json::to_string(&config.args)?,
        serde_json::to_string(&config.language_ids)?,
        serde_json::to_string(&config.extensions)?
    );
    if !config.initialization_options.is_null() {
        content.push_str("[initialization_options]\nnested = [{ root = '{workspaceRoot}/init' }]\n[settings.fixture.nested]\nroot = '{workspaceRoot}/settings'\n");
    }
    if !config.env.is_empty() {
        content.push_str("[env]\n");
        for (key, value) in config.env {
            content.push_str(&format!(
                "{} = {}\n",
                serde_json::to_string(&key)?,
                serde_json::to_string(&value)?
            ));
        }
    }
    tokio::fs::write(&path, content).await?;
    Ok(path)
}
async fn log_messages(path: &Path) -> anyhow::Result<Vec<serde_json::Value>> {
    let text = match tokio::fs::read_to_string(path).await {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error.into()),
    };
    Ok(text
        .lines()
        .filter_map(|line| serde_json::from_str(line).ok())
        .collect())
}
async fn wait_log(
    path: &Path,
    predicate: impl Fn(&[serde_json::Value]) -> bool,
) -> anyhow::Result<Vec<serde_json::Value>> {
    tokio::time::timeout(std::time::Duration::from_secs(15), async {
        loop {
            let messages = log_messages(path).await?;
            if predicate(&messages) {
                return Ok(messages);
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
    })
    .await?
}
fn local_host(root: &Path) -> anyhow::Result<Arc<dyn pl_lsp::host::LspHostBackend>> {
    Ok(Arc::new(ExecutorLspHost::new(
        Executor::local()?,
        root.to_str().unwrap(),
    )?))
}

#[tokio::test]
async fn directory_loading_is_local_failure_isolated_and_initialization_is_parallel()
-> anyhow::Result<()> {
    use pl_lsp::runtime::LspLifecyclePhase as Phase;
    let root = tempfile::tempdir()?;
    let defaults = tempfile::tempdir()?;
    tokio::fs::write(defaults.path().join("fast.toml"), "not valid TOML").await?;
    tokio::fs::write(
        defaults.path().join("broken-default.toml"),
        "not valid TOML",
    )
    .await?;
    let mut fast = fixture_config("fast", "fast.jsonl");
    fast.env.insert(
        "LSP_FIXTURE_VALUE".into(),
        "{workspaceRoot}/environment".into(),
    );
    fast.env
        .insert("LSP_FIXTURE_CONFIGURATION".into(), "1".into());
    fast.initialization_options = serde_json::json!({"nested": [{"root": "{workspaceRoot}/init"}]});
    fast.settings =
        serde_json::json!({"fixture": {"nested": {"root": "{workspaceRoot}/settings"}}});
    write_config(root.path(), "fast", fast).await?;
    let mut slow = fixture_config("slow", "slow.jsonl");
    slow.env.insert("LSP_FIXTURE_DELAY".into(), "60".into());
    write_config(root.path(), "slow", slow).await?;
    let mut failing = fixture_config("failing", "failing.jsonl");
    failing.env.insert("LSP_FIXTURE_FAIL".into(), "1".into());
    write_config(root.path(), "failing", failing).await?;
    tokio::fs::write(root.path().join(".anywork/lsp/broken.toml"), "schema_version=1\nid='broken'\ncommand='private-token'\nlanguage_ids=['broken']\ntypo=true").await?;
    let registry = LspRuntimeRegistry::new();
    tokio::time::timeout(
        std::time::Duration::from_millis(250),
        registry.configure_workspace_from_directory(
            root.path(),
            Some(local_host(root.path())?),
            Some(defaults.path().to_owned()),
        ),
    )
    .await?;
    let observed: anyhow::Result<()> = async {
        let loading = registry.snapshots_for_workspace(root.path()).await;
        anyhow::ensure!(
            loading
                .iter()
                .any(|snapshot| snapshot.phase == Phase::Loading)
        );
        wait_ready(&registry, root.path(), "fast").await?;
        wait_phase(&registry, root.path(), "failing", Phase::Failed).await?;
        let snapshots = registry.snapshots_for_workspace(root.path()).await;
        anyhow::ensure!(
            snapshots
                .iter()
                .any(|snapshot| snapshot.id == "slow" && snapshot.phase == Phase::Initializing)
        );
        for id in ["broken", "broken-default"] {
            anyhow::ensure!(
                snapshots
                    .iter()
                    .any(|snapshot| snapshot.id == id && snapshot.phase == Phase::Failed)
            );
        }
        anyhow::ensure!(!serde_json::to_string(&snapshots)?.contains("private-token"));
        let capabilities = registry.capabilities_for_workspace(root.path()).await;
        anyhow::ensure!(capabilities.servers.len() == 1 && capabilities.servers[0].id == "fast");
        anyhow::ensure!(capabilities.servers[0].operations == ["hover", "diagnostics"]);
        let messages = wait_log(&root.path().join("fast.jsonl"), |messages| {
            messages.iter().any(|message| {
                message["id"] == "configuration-request" && message.get("result").is_some()
            }) && messages
                .iter()
                .any(|message| message["method"] == "workspace/didChangeConfiguration")
        })
        .await?;
        let start = messages
            .iter()
            .find(|message| message["method"] == "fixture/start")
            .unwrap();
        anyhow::ensure!(start["cwd"] == root.path().display().to_string());
        anyhow::ensure!(start["env"] == format!("{}/environment", root.path().display()));
        let initialize = messages
            .iter()
            .find(|message| message["method"] == "initialize")
            .unwrap();
        anyhow::ensure!(
            initialize["params"]["initializationOptions"]["nested"][0]["root"]
                == format!("{}/init", root.path().display())
        );
        let response = messages
            .iter()
            .find(|message| {
                message["id"] == "configuration-request" && message.get("result").is_some()
            })
            .unwrap();
        anyhow::ensure!(
            response["result"][0]["root"] == format!("{}/settings", root.path().display())
        );
        anyhow::ensure!(response["result"][1].is_null());
        Ok(())
    }
    .await;
    let shutdown =
        tokio::time::timeout(std::time::Duration::from_secs(5), registry.shutdown()).await;
    observed?;
    shutdown??;
    anyhow::ensure!(!registry.has_ready_servers(root.path()).await);
    for name in ["fast", "slow", "failing"] {
        for message in log_messages(&root.path().join(format!("{name}.jsonl"))).await? {
            if let Some(pid) = message["pid"].as_u64() {
                anyhow::ensure!(
                    !PathBuf::from(format!("/proc/{pid}")).exists(),
                    "server {pid} must be reaped"
                );
            }
        }
    }
    Ok(())
}

#[tokio::test]
async fn refresh_preserves_unchanged_and_cancels_superseded_generations() -> anyhow::Result<()> {
    use pl_lsp::runtime::LspLifecyclePhase as Phase;
    let root = tempfile::tempdir()?;
    let config = fixture_config("fixture", "requests.jsonl");
    let path = write_config(root.path(), "fixture", config.clone()).await?;
    let registry = LspRuntimeRegistry::new();
    registry
        .configure_workspace(
            root.path(),
            Some(local_host(root.path())?),
            Default::default(),
        )
        .await;
    let observed: anyhow::Result<()> = async {
        wait_ready(&registry, root.path(), "fixture").await?;
        registry.refresh_workspace_configuration(root.path()).await;
        for _ in 0..10 {
            let _ = registry.snapshots_for_workspace(root.path()).await;
            let _ = registry.capabilities_for_workspace(root.path()).await;
        }
        // Force another scan with a bad neighbor, then wait for its published diagnostic:
        // this proves the unchanged member passed a completed merge, not just the old state.
        tokio::fs::write(root.path().join(".anywork/lsp/broken.toml"), "invalid").await?;
        registry.refresh_workspace_configuration(root.path()).await;
        wait_phase(&registry, root.path(), "broken", Phase::Failed).await?;
        let messages = log_messages(&root.path().join("requests.jsonl")).await?;
        anyhow::ensure!(
            messages
                .iter()
                .filter(|message| message["method"] == "fixture/start")
                .count()
                == 1
        );
        let mut slow = config.clone();
        slow.env.insert("LSP_FIXTURE_DELAY".into(), "60".into());
        slow.env
            .insert("LSP_FIXTURE_VALUE".into(), "superseded".into());
        write_config(root.path(), "fixture", slow).await?;
        registry.notify_file_changed(&path).await;
        wait_log(&root.path().join("requests.jsonl"), |messages| {
            messages
                .iter()
                .any(|message| message["env"] == "superseded")
        })
        .await?;
        let mut latest = config;
        latest
            .env
            .insert("LSP_FIXTURE_VALUE".into(), "latest".into());
        write_config(root.path(), "fixture", latest).await?;
        registry.notify_file_changed(&path).await;
        wait_log(&root.path().join("requests.jsonl"), |messages| {
            messages.iter().any(|message| message["env"] == "latest")
        })
        .await?;
        wait_ready(&registry, root.path(), "fixture").await?;
        let snapshots = registry.snapshots_for_workspace(root.path()).await;
        anyhow::ensure!(
            snapshots
                .iter()
                .find(|snapshot| snapshot.id == "fixture")
                .unwrap()
                .phase
                == Phase::Ready
        );
        anyhow::ensure!(
            registry
                .active_server_names_for_workspace(root.path())
                .await
                == ["fixture"]
        );
        // Removal must also stop a healthy process and remove its capabilities.
        tokio::fs::remove_file(&path).await?;
        registry.notify_file_deleted(&path).await;
        let mut updates = registry.subscribe();
        tokio::time::timeout(std::time::Duration::from_secs(5), async {
            while registry.has_ready_servers(root.path()).await {
                updates.recv().await?;
            }
            Ok::<_, anyhow::Error>(())
        })
        .await??;
        Ok(())
    }
    .await;
    let shutdown = registry.shutdown().await;
    observed?;
    shutdown?;
    for message in log_messages(&root.path().join("requests.jsonl")).await? {
        if let Some(pid) = message["pid"].as_u64() {
            anyhow::ensure!(!PathBuf::from(format!("/proc/{pid}")).exists());
        }
    }
    Ok(())
}

#[tokio::test]
async fn exited_servers_are_not_routed_and_status_reads_do_not_restart_them() -> anyhow::Result<()>
{
    let root = tempfile::tempdir()?;
    let mut config = fixture_config("fixture", "exit.jsonl");
    config.env.insert("LSP_FIXTURE_EXIT".into(), "1".into());
    let registry = LspRuntimeRegistry::new();
    registry
        .configure_workspace(
            root.path(),
            Some(local_host(root.path())?),
            [("fixture".into(), config)].into(),
        )
        .await;
    let observed: anyhow::Result<()> = async {
        wait_phase(
            &registry,
            root.path(),
            "fixture",
            pl_lsp::runtime::LspLifecyclePhase::Failed,
        )
        .await?;
        anyhow::ensure!(
            registry
                .capabilities_for_workspace(root.path())
                .await
                .servers
                .is_empty()
        );
        anyhow::ensure!(
            registry
                .active_server_names_for_workspace(root.path())
                .await
                .is_empty()
        );
        for _ in 0..5 {
            let snapshots = registry.snapshots_for_workspace(root.path()).await;
            anyhow::ensure!(snapshots[0].phase == pl_lsp::runtime::LspLifecyclePhase::Failed);
        }
        let error = registry
            .query_in_workspace(
                root.path(),
                pl_lsp::query::LspQuery {
                    operation: LspQueryOperation::Hover,
                    file_path: Some(root.path().join("source.fixture")),
                    line: Some(1),
                    character: Some(1),
                    query: None,
                    max_results: None,
                    language_id: Some("fixture".into()),
                },
            )
            .await
            .expect_err("exited process cannot serve queries");
        anyhow::ensure!(error.to_string().contains("no LSP server"));
        anyhow::ensure!(
            log_messages(&root.path().join("exit.jsonl"))
                .await?
                .iter()
                .filter(|message| message["method"] == "fixture/start")
                .count()
                == 1
        );
        Ok(())
    }
    .await;
    let shutdown = registry.shutdown().await;
    observed?;
    shutdown?;
    Ok(())
}

#[tokio::test]
async fn empty_binding_is_idempotent() -> anyhow::Result<()> {
    let root = tempfile::tempdir()?;
    let registry = LspRuntimeRegistry::new();
    let closed = Executor::local()?;
    let unavailable = Arc::new(ExecutorLspHost::new(closed, root.path().to_str().unwrap())?);
    let mut updates = registry.subscribe();
    registry
        .configure_workspace(root.path(), Some(unavailable.clone()), Default::default())
        .await;
    tokio::time::timeout(std::time::Duration::from_secs(5), async {
        loop {
            if registry
                .snapshots_for_workspace(root.path())
                .await
                .is_empty()
            {
                break;
            }
            updates.recv().await?;
        }
        Ok::<_, anyhow::Error>(())
    })
    .await??;
    while updates.try_recv().is_ok() {}
    for _ in 0..5 {
        registry
            .configure_workspace(root.path(), Some(unavailable.clone()), Default::default())
            .await;
        anyhow::ensure!(
            registry
                .snapshots_for_workspace(root.path())
                .await
                .is_empty()
        );
    }
    anyhow::ensure!(
        updates.try_recv().is_err(),
        "identical empty binding must not publish Loading again"
    );
    registry.refresh_workspace_configuration(root.path()).await;
    anyhow::ensure!(
        tokio::time::timeout(std::time::Duration::from_millis(100), updates.recv())
            .await
            .is_err(),
        "unchanged empty scan must not emit another update"
    );
    registry.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn workspace_catalogs_are_isolated_and_conflicts_never_enter_routing() -> anyhow::Result<()> {
    use pl_lsp::runtime::{LspLifecyclePhase as Phase, LspRoutingError, LspRuntimeError};
    let first = tempfile::tempdir()?;
    let second = tempfile::tempdir()?;
    let mut other = fixture_config("other", "other.jsonl");
    other.extensions = vec![".fixture".into()];
    let registry = LspRuntimeRegistry::new();
    registry
        .configure_workspace(
            first.path(),
            Some(local_host(first.path())?),
            [
                ("first".into(), fixture_config("fixture", "first.jsonl")),
                ("other".into(), other),
            ]
            .into(),
        )
        .await;
    registry
        .configure_workspace(
            second.path(),
            Some(local_host(second.path())?),
            [("first".into(), fixture_config("second", "second.jsonl"))].into(),
        )
        .await;
    let observed: anyhow::Result<()> = async {
        wait_ready(&registry, first.path(), "first").await?;
        wait_ready(&registry, first.path(), "other").await?;
        wait_ready(&registry, second.path(), "first").await?;
        let error = registry
            .query_in_workspace(
                first.path(),
                pl_lsp::query::LspQuery {
                    operation: LspQueryOperation::Hover,
                    file_path: Some(first.path().join("source.fixture")),
                    line: Some(1),
                    character: Some(1),
                    query: None,
                    max_results: None,
                    language_id: None,
                },
            )
            .await
            .expect_err("ambiguous extensions must not select by catalog order");
        anyhow::ensure!(matches!(
            error,
            LspRuntimeError::Routing(LspRoutingError::AmbiguousPath { .. })
        ));
        let path = write_config(
            first.path(),
            "conflict",
            fixture_config("fixture", "conflict.jsonl"),
        )
        .await?;
        registry.notify_file_changed(&path).await;
        wait_phase(&registry, first.path(), "conflict", Phase::Failed).await?;
        wait_phase(&registry, first.path(), "first", Phase::Failed).await?;
        anyhow::ensure!(
            registry
                .active_server_names_for_workspace(first.path())
                .await
                == ["other"]
        );
        anyhow::ensure!(
            registry
                .active_server_names_for_workspace(second.path())
                .await
                == ["first"]
        );
        let second_capabilities = registry.capabilities_for_workspace(second.path()).await;
        anyhow::ensure!(second_capabilities.servers[0].language_ids == ["second"]);
        anyhow::ensure!(!first.path().join("conflict.jsonl").exists());
        anyhow::ensure!(
            log_messages(&second.path().join("second.jsonl"))
                .await?
                .iter()
                .filter(|message| message["method"] == "fixture/start")
                .count()
                == 1
        );
        Ok(())
    }
    .await;
    let shutdown = registry.shutdown().await;
    observed?;
    shutdown?;
    Ok(())
}

#[tokio::test]
async fn local_host_identity_tracks_executor_and_does_not_restart_shared_processes()
-> anyhow::Result<()> {
    use pl_lsp::host::LspHostBackend;
    let root = tempfile::tempdir()?;
    let executor = Executor::local()?;
    let host = Arc::new(ExecutorLspHost::new(
        executor.clone(),
        root.path().to_str().unwrap(),
    )?);
    let identity = host.identity();
    tokio::fs::write(root.path().join("source.fixture"), "fixture source").await?;
    let registry = LspRuntimeRegistry::new();
    let config = fixture_config("fixture", "identity.jsonl");
    registry
        .configure_workspace(
            root.path(),
            Some(host),
            [("fixture".into(), config.clone())].into(),
        )
        .await;
    let observed: anyhow::Result<()> = async {
        wait_ready(&registry, root.path(), "fixture").await?;
        let next = Arc::new(ExecutorLspHost::new(
            executor.clone(),
            root.path().to_str().unwrap(),
        )?);
        anyhow::ensure!(next.identity() == identity);
        let mut updates = registry.subscribe();
        registry
            .configure_workspace(root.path(), Some(next), [("fixture".into(), config)].into())
            .await;
        anyhow::ensure!(
            updates.try_recv().is_err(),
            "same execution binding must not restart LSP"
        );
        let result = registry
            .query_in_workspace(
                root.path(),
                pl_lsp::query::LspQuery {
                    operation: LspQueryOperation::Hover,
                    file_path: Some(root.path().join("source.fixture")),
                    line: Some(1),
                    character: Some(1),
                    query: None,
                    max_results: None,
                    language_id: Some("fixture".into()),
                },
            )
            .await?;
        anyhow::ensure!(result.success && result.result.contains("fixture hover"));
        let replacement = Executor::local()?;
        let replacement_host =
            ExecutorLspHost::new(replacement.clone(), root.path().to_str().unwrap())?;
        anyhow::ensure!(
            replacement_host.identity() != identity,
            "new executor must not revive old handles"
        );
        replacement.close().await?;
        Ok(())
    }
    .await;
    let shutdown = registry.shutdown().await;
    let close = executor.close().await;
    observed?;
    shutdown?;
    close?;
    Ok(())
}

#[tokio::test]
async fn missing_program_failure_does_not_make_registry_shutdown_fail() -> anyhow::Result<()> {
    let root = tempfile::tempdir()?;
    let mut missing = fixture_config("missing", "missing.jsonl");
    missing.command = "anywork-lsp-shutdown-regression-nonexistent-program".into();
    let registry = LspRuntimeRegistry::new();
    registry
        .configure_workspace(
            root.path(),
            Some(local_host(root.path())?),
            [
                ("missing".into(), missing),
                ("fixture".into(), fixture_config("fixture", "healthy.jsonl")),
            ]
            .into(),
        )
        .await;
    let observed: anyhow::Result<()> = async {
        wait_ready(&registry, root.path(), "fixture").await?;
        wait_phase(
            &registry,
            root.path(),
            "missing",
            pl_lsp::runtime::LspLifecyclePhase::Failed,
        )
        .await?;
        let snapshots = registry.snapshots_for_workspace(root.path()).await;
        let failure = snapshots
            .iter()
            .find(|server| server.id == "missing")
            .unwrap();
        anyhow::ensure!(
            failure
                .availability_message
                .as_deref()
                .is_some_and(|error| error.contains("NotStarted") && error.contains("os error 2")),
            "startup cause must remain observable after successful resource cleanup: {failure:?}"
        );
        anyhow::ensure!(
            registry
                .active_server_names_for_workspace(root.path())
                .await
                == ["fixture"]
        );
        Ok(())
    }
    .await;
    let shutdown = registry.shutdown().await;
    observed?;
    shutdown?;
    registry.shutdown().await?;
    let messages = log_messages(&root.path().join("healthy.jsonl")).await?;
    anyhow::ensure!(
        messages
            .iter()
            .any(|message| message["method"] == "shutdown")
    );
    anyhow::ensure!(messages.iter().any(|message| message["method"] == "exit"));
    for message in messages {
        if let Some(pid) = message["pid"].as_u64() {
            anyhow::ensure!(!PathBuf::from(format!("/proc/{pid}")).exists());
        }
    }
    Ok(())
}

fn fixture_query(root: &Path, operation: LspQueryOperation) -> pl_lsp::query::LspQuery {
    pl_lsp::query::LspQuery {
        operation,
        file_path: operation
            .requires_file()
            .then(|| root.join("source.fixture")),
        line: operation.requires_position().then_some(1),
        character: operation.requires_position().then_some(1),
        query: None,
        max_results: None,
        language_id: Some("fixture".into()),
    }
}

#[tokio::test]
async fn endpoint_views_isolate_same_root_and_global_owner_joins_every_partition()
-> anyhow::Result<()> {
    let directory = tempfile::tempdir()?;
    tokio::fs::write(directory.path().join("source.fixture"), "fixture").await?;
    let owner = LspRuntimeRegistry::new();
    let a = owner.execution_scope("ssh:a");
    let b = owner.execution_scope("ssh:b");
    let mut a_config = fixture_config("fixture", "a.jsonl");
    a_config
        .env
        .insert("LSP_FIXTURE_HOVER".into(), "endpoint A".into());
    let mut b_config = fixture_config("fixture", "b.jsonl");
    b_config
        .env
        .insert("LSP_FIXTURE_HOVER".into(), "endpoint B".into());
    let mut global_updates = owner.subscribe();
    a.configure_workspace(
        directory.path(),
        Some(local_host(directory.path())?),
        [("fixture".into(), a_config)].into(),
    )
    .await;
    tokio::time::timeout(std::time::Duration::from_secs(5), global_updates.recv()).await??;
    b.configure_workspace(
        directory.path(),
        Some(local_host(directory.path())?),
        [("fixture".into(), b_config)].into(),
    )
    .await;
    let observed: anyhow::Result<()> = async {
        wait_ready(&a, directory.path(), "fixture").await?;
        wait_ready(&b, directory.path(), "fixture").await?;
        for (view, expected) in [(&a, "endpoint A"), (&b, "endpoint B")] {
            let result = view
                .query_in_workspace(
                    directory.path(),
                    fixture_query(directory.path(), LspQueryOperation::Hover),
                )
                .await?;
            anyhow::ensure!(
                result.result.contains(expected),
                "wrong endpoint response: {}",
                result.result
            );
            anyhow::ensure!(view.snapshots().await.len() == 1);
        }
        anyhow::ensure!(owner.snapshots().await.len() == 2);
        anyhow::ensure!(owner.active_server_names().await == ["fixture"]);
        let same_a = owner.execution_scope("ssh:a");
        anyhow::ensure!(same_a.has_ready_servers(directory.path()).await);
        owner.reset_lsp(pl_lsp::runtime::LspScope::All).await?;
        for (view, log) in [(&a, "a.jsonl"), (&b, "b.jsonl")] {
            wait_log(&directory.path().join(log), |messages| {
                messages
                    .iter()
                    .filter(|message| message["method"] == "fixture/start")
                    .count()
                    == 2
            })
            .await?;
            wait_ready(view, directory.path(), "fixture").await?;
        }
        a.shutdown().await?;
        anyhow::ensure!(!same_a.has_ready_servers(directory.path()).await);
        anyhow::ensure!(
            b.has_ready_servers(directory.path()).await,
            "closing A must not close B"
        );
        anyhow::ensure!(
            b.query_in_workspace(
                directory.path(),
                fixture_query(directory.path(), LspQueryOperation::Hover)
            )
            .await?
            .result
            .contains("endpoint B")
        );
        Ok(())
    }
    .await;
    let shutdown = owner.shutdown().await;
    observed?;
    shutdown?;
    anyhow::ensure!(!b.has_ready_servers(directory.path()).await);
    let late = owner.execution_scope("ssh:late");
    late.configure_workspace(
        directory.path(),
        Some(local_host(directory.path())?),
        [("fixture".into(), fixture_config("fixture", "late.jsonl"))].into(),
    )
    .await;
    anyhow::ensure!(
        late.snapshots().await.is_empty(),
        "global shutdown must reject new partition startup"
    );
    Ok(())
}

#[tokio::test]
async fn explicit_retry_recovers_unchanged_configuration_without_restarting_healthy_neighbors()
-> anyhow::Result<()> {
    use pl_lsp::runtime::LspLifecyclePhase as Phase;
    use std::os::unix::fs::PermissionsExt;
    let directory = tempfile::tempdir()?;
    let mut config = fixture_config("fixture", "retry.jsonl");
    config.command = "{workspaceRoot}/installed-server".into();
    config.args = vec!["{workspaceRoot}/retry.jsonl".into()];
    let path = write_config(directory.path(), "fixture", config).await?;
    let original = tokio::fs::read(&path).await?;
    write_config(
        directory.path(),
        "healthy",
        fixture_config("healthy", "neighbor.jsonl"),
    )
    .await?;
    let registry = LspRuntimeRegistry::new();
    registry
        .configure_workspace(
            directory.path(),
            Some(local_host(directory.path())?),
            Default::default(),
        )
        .await;
    let observed: anyhow::Result<()> = async {
        wait_phase(&registry, directory.path(), "fixture", Phase::Failed).await?;
        wait_ready(&registry, directory.path(), "healthy").await?;
        let executable = directory.path().join("installed-server");
        tokio::fs::write(
            &executable,
            format!(
                "#!/usr/bin/env python3\n{}",
                include_str!("support/lsp_fixture.py")
            ),
        )
        .await?;
        tokio::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o755)).await?;
        tokio::fs::write(
            directory.path().join(".anywork/lsp/scan-marker.toml"),
            "invalid",
        )
        .await?;
        registry
            .refresh_workspace_configuration(directory.path())
            .await;
        wait_phase(&registry, directory.path(), "scan-marker", Phase::Failed).await?;
        anyhow::ensure!(
            registry
                .snapshots_for_workspace(directory.path())
                .await
                .iter()
                .any(|server| server.id == "fixture" && server.phase == Phase::Failed)
        );
        anyhow::ensure!(
            !directory.path().join("retry.jsonl").exists(),
            "passive refresh must not retry unchanged failures"
        );
        registry
            .retry_workspace_configuration(directory.path())
            .await;
        wait_ready(&registry, directory.path(), "fixture").await?;
        anyhow::ensure!(tokio::fs::read(&path).await? == original);
        anyhow::ensure!(
            log_messages(&directory.path().join("neighbor.jsonl"))
                .await?
                .iter()
                .filter(|message| message["method"] == "fixture/start")
                .count()
                == 1
        );
        Ok(())
    }
    .await;
    let shutdown = registry.shutdown().await;
    observed?;
    shutdown?;
    Ok(())
}

#[tokio::test]
async fn diagnostic_maps_are_generation_owned_and_late_old_notifications_are_not_reused()
-> anyhow::Result<()> {
    let directory = tempfile::tempdir()?;
    let mut config = fixture_config("fixture", "diagnostics.jsonl");
    config
        .env
        .insert("LSP_FIXTURE_DIAGNOSTIC".into(), "old-generation".into());
    config.env.insert(
        "LSP_FIXTURE_LATE_DIAGNOSTIC".into(),
        "late-old-generation".into(),
    );
    let path = write_config(directory.path(), "fixture", config.clone()).await?;
    let registry = LspRuntimeRegistry::new();
    registry
        .configure_workspace(
            directory.path(),
            Some(local_host(directory.path())?),
            Default::default(),
        )
        .await;
    let observed: anyhow::Result<()> = async {
        wait_ready(&registry, directory.path(), "fixture").await?;
        let mut updates = registry.subscribe();
        tokio::time::timeout(std::time::Duration::from_secs(5), async {
            loop {
                if registry
                    .snapshots_for_workspace(directory.path())
                    .await
                    .iter()
                    .any(|server| server.id == "fixture" && server.diagnostic_count == 1)
                {
                    break;
                }
                updates.recv().await?;
            }
            Ok::<_, anyhow::Error>(())
        })
        .await??;
        let diagnostics = registry
            .query_in_workspace(
                directory.path(),
                fixture_query(directory.path(), LspQueryOperation::Diagnostics),
            )
            .await?;
        anyhow::ensure!(
            diagnostics.result_count == Some(1) && diagnostics.result.contains("old-generation")
        );
        config.env.clear();
        write_config(directory.path(), "fixture", config).await?;
        registry.notify_file_changed(&path).await;
        wait_log(&directory.path().join("diagnostics.jsonl"), |messages| {
            messages.iter().any(|message| {
                message["method"] == "fixture/publishDiagnostics"
                    && message["message"] == "late-old-generation"
            }) && messages
                .iter()
                .filter(|message| message["method"] == "fixture/start")
                .count()
                == 2
        })
        .await?;
        wait_ready(&registry, directory.path(), "fixture").await?;
        anyhow::ensure!(
            registry.snapshots_for_workspace(directory.path()).await[0].diagnostic_count == 0
        );
        let diagnostics = registry
            .query_in_workspace(
                directory.path(),
                fixture_query(directory.path(), LspQueryOperation::Diagnostics),
            )
            .await?;
        anyhow::ensure!(
            diagnostics.result_count == Some(0) && !diagnostics.result.contains("old-generation")
        );
        Ok(())
    }
    .await;
    let shutdown = registry.shutdown().await;
    observed?;
    shutdown?;
    Ok(())
}
