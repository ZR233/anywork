//! Opt-in, real Rust/Dart SSH directory-lease acceptance; not part of the SSH suite.
//! Run only against a task-owned remote directory with prepared official SDKs.
//! Required: PURE_SSH_TEST_SERVER, PURE_SSH_TEST_USERNAME, PURE_SSH_LSP_ROOT,
//! PURE_SSH_LSP_RUST_ANALYZER, PURE_SSH_LSP_RUST_SRC, PURE_SSH_LSP_DART,
//! PURE_SSH_LSP_CARGO_BIN, PURE_SSH_LSP_SCRATCH, PURE_SSH_LSP_ARTIFACTS,
//! and PURE_REMOTE_HELPER_X86_64 (or PURE_REMOTE_HELPER_AARCH64), including its
//! adjacent .sha256. Optional SSH identity/port/known-hosts match ssh_remote.rs.
//! SDK executables must be beneath ROOT/sdk. The entry overwrites project-a/
//! project-b and uses ROOT/home, all of which must belong to this task.
#![cfg(target_os = "linux")]

use anyhow::{Context, ensure};
use pl_agent_tool::Tool;
use pl_core::{context::OpaquePayload, tool::opaque::CallContext};
use pl_lsp::runtime::{LspLifecyclePhase, LspRuntimeRegistry};
use pl_tool::{
    execution::{ExecutionBackend, ExecutionRequest},
    lsp::{LspPathBinding, LspToolKind, ThreadLspTool},
    remote::{RemoteWorkspaceHost, SshConfigFile, SshManager, SshServerProfile},
    workspace::{AgentWorkspace, ToolWorkspace, WorkspaceMutability, WriteMode},
    workspace_file::{WorkspaceFileBackend, WorkspaceFileWriteRequest, WorkspacePolicyBackend},
};
use serde_json::{Value, json};
use std::{
    collections::BTreeSet,
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

fn required(name: &str) -> anyhow::Result<String> {
    std::env::var(name).with_context(|| format!("{name} must be set"))
}

fn context(thread: &str) -> CallContext {
    CallContext {
        thread_id: thread.into(),
        turn_id: "real-ssh-lsp".into(),
        call_id: "semantic-query".into(),
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

async fn write(
    backend: &impl WorkspaceFileBackend,
    path: &str,
    content: impl Into<String>,
) -> anyhow::Result<()> {
    backend
        .write_text(WorkspaceFileWriteRequest {
            mode: WriteMode::Overwrite,
            path: path.into(),
            cwd: None,
            content: content.into(),
        })
        .await?;
    Ok(())
}

async fn run(
    host: &RemoteWorkspaceHost,
    program: &str,
    args: Vec<String>,
) -> anyhow::Result<String> {
    let output = host
        .git
        .run(ExecutionRequest {
            program: program.into(),
            args,
            cwd: ".".into(),
            env: Default::default(),
            timeout: Some(Duration::from_secs(60)),
        })
        .await?;
    ensure!(
        output.status == 0,
        "{program}: exit {}; stdout={}; stderr={}",
        output.status,
        output.stdout,
        output.stderr
    );
    Ok(format!("{}{}", output.stdout, output.stderr))
}

fn source(project: &str, language: &str, revision: &str) -> String {
    let symbol = format!("project_{project}_{language}");
    let marker = format!("{symbol}_{revision}");
    if language == "rust" {
        format!(
            "/// {marker}\npub fn {symbol}() -> u32 {{ 7 }}\npub fn usage() -> u32 {{ {symbol}() }}\n"
        )
    } else {
        format!("/// {marker}\nint {symbol}() => 7;\nint usage() => {symbol}();\n")
    }
}

fn tool(registry: &LspRuntimeRegistry, host: &RemoteWorkspaceHost) -> ThreadLspTool {
    let workspace = ToolWorkspace::new(AgentWorkspace::confined(
        host.files.canonical_path(),
        WorkspaceMutability::ReadWrite,
    ))
    .with_lsp_runtime(Some(registry.clone()));
    ThreadLspTool::new(
        registry.clone(),
        LspPathBinding::Remote {
            workspace,
            files: Arc::new(host.files.clone()),
        },
        LspToolKind::Query,
        LspToolKind::Query.declaration(),
    )
}

async fn hover(
    tool: &ThreadLspTool,
    thread: &str,
    project: &str,
    language: &str,
    revision: &str,
    evidence: &mut Vec<Value>,
) -> anyhow::Result<()> {
    let symbol = format!("project_{project}_{language}");
    let text = source(project, language, revision);
    let line = text.lines().nth(2).context("source usage line")?;
    let input = json!({
        "operation": "hover",
        "languageId": language,
        "filePath": if language == "rust" { "src/lib.rs" } else { "lib/sample.dart" },
        "line": 3,
        "character": line.find(&symbol).context("source usage symbol")? + 2,
    });
    // Initial indexing may yield an empty hover or ContentModified. Only those
    // protocol transients are retried; a nonempty wrong project/revision fails.
    tokio::time::timeout(Duration::from_secs(60), async {
        loop {
            let result = tool
                .execute(
                    OpaquePayload::new("application/json", 1, input.to_string())?,
                    context(thread),
                )
                .await;
            match result {
                Ok(output) => {
                    let value: Value = serde_json::from_str(output.payload().content())?;
                    evidence.push(json!({"thread": thread, "project": project,
                        "language": language, "revision": revision, "query": value}));
                    ensure!(value["success"] == true, "{value}");
                    if value["resultCount"] != 0 {
                        let result = value["result"].as_str().context("hover result text")?;
                        ensure!(
                            result.contains(&format!("{symbol}_{revision}")),
                            "wrong project or stale source for {thread}/{language}: {value}"
                        );
                        println!("hover {thread}/{language}/{revision}: {result}");
                        return Ok::<_, anyhow::Error>(());
                    }
                }
                Err(error)
                    if error.to_string().contains("ContentModified")
                        || error.to_string().contains("-32801") =>
                {
                    evidence.push(json!({"transient": error.to_string(), "thread": thread}));
                }
                Err(error) => return Err(error.into()),
            }
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
    })
    .await
    .context("real language server did not produce a semantic hover")??;
    Ok(())
}

async fn both(
    tool: &ThreadLspTool,
    thread: &str,
    project: &str,
    revision: &str,
    evidence: &mut Vec<Value>,
) -> anyhow::Result<()> {
    for language in ["rust", "dart"] {
        hover(tool, thread, project, language, revision, evidence).await?;
    }
    Ok(())
}

async fn ready(
    registry: &LspRuntimeRegistry,
    root: &Path,
    evidence: &mut Vec<Value>,
) -> anyhow::Result<()> {
    let mut updates = registry.subscribe();
    tokio::time::timeout(Duration::from_secs(120), async {
        loop {
            let snapshots = registry.snapshots_for_workspace(root).await;
            evidence.push(json!({"root": root, "servers": snapshots}));
            ensure!(
                !snapshots
                    .iter()
                    .any(|s| s.phase == LspLifecyclePhase::Failed),
                "real LSP initialization failed: {snapshots:?}"
            );
            if ["rust", "dart"].iter().all(|id| {
                snapshots
                    .iter()
                    .any(|s| s.id == *id && s.phase == LspLifecyclePhase::Ready)
            }) {
                return Ok::<_, anyhow::Error>(());
            }
            updates.recv().await?;
        }
    })
    .await
    .context("Rust and Dart did not both become ready")??;
    Ok(())
}

// Inspect only executables in this task's isolated SDK directory. No global
// process-name matching, killing, or reading unrelated command lines is used.
async fn processes(host: &RemoteWorkspaceHost, sdk: &Path) -> anyhow::Result<Vec<Value>> {
    let script = r#"import json, os, pathlib, sys
prefix = sys.argv[1].rstrip('/') + '/'
found = []
for entry in pathlib.Path('/proc').iterdir():
    if not entry.name.isdigit():
        continue
    try:
        exe = os.readlink(entry / 'exe')
        if exe.startswith(prefix):
            found.append({'pid': int(entry.name), 'exe': exe, 'cwd': os.readlink(entry / 'cwd')})
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        pass
print(json.dumps(found))
"#;
    let text = run(
        host,
        "python3",
        vec!["-c".into(), script.into(), sdk.display().to_string()],
    )
    .await?;
    Ok(serde_json::from_str(&text)?)
}

async fn prepare(
    host: &RemoteWorkspaceHost,
    project: &str,
    remote_root: &Path,
) -> anyhow::Result<()> {
    // Raw files are used only before acquiring any LSP lease/opening documents.
    // Mutations of opened source below must use the production policy backend.
    for directory in ["src", "lib", ".anywork/lsp"] {
        host.files.create_directory(directory.into(), None).await?;
    }
    write(
        &host.files,
        "Cargo.toml",
        format!(
            "[package]\nname = \"lsp_project_{project}\"\nversion = \"0.0.0\"\nedition = \"2021\"\n"
        ),
    )
    .await?;
    write(
        &host.files,
        "pubspec.yaml",
        format!("name: lsp_project_{project}\nenvironment:\n  sdk: '>=3.0.0 <4.0.0'\n"),
    )
    .await?;
    write(&host.files, "src/lib.rs", source(project, "rust", "before")).await?;
    write(
        &host.files,
        "lib/sample.dart",
        source(project, "dart", "before"),
    )
    .await?;
    // JSON strings are also TOML basic strings; every execution-side value is
    // explicit and remains independent of a user's interactive PATH.
    let quoted = |text: &str| serde_json::to_string(text);
    let home = remote_root.join("home").display().to_string();
    let cargo_bin = required("PURE_SSH_LSP_CARGO_BIN")?;
    let env = format!(
        "[env]\nHOME = {}\nPATH = {}\nRUSTC = {}\n",
        quoted(&home)?,
        quoted(&format!("{cargo_bin}:/usr/bin:/bin"))?,
        quoted(&format!("{cargo_bin}/rustc"))?,
    );
    // Both directories deliberately use identical server IDs. Directory identity,
    // not a project-specific server ID, must isolate their production processes.
    write(&host.files, ".anywork/lsp/rust.toml", format!(
        "schema_version = 1\nid = \"rust\"\ncommand = {}\nlanguage_ids = [\"rust\"]\nextensions = [\"rs\"]\ndetection = [\"Cargo.toml\"]\noperations = [\"hover\"]\n{env}[initialization_options]\ncheckOnSave = false\n[initialization_options.cargo]\nsysrootSrc = {}\n[initialization_options.cargo.buildScripts]\nenable = false\n",
        quoted(&required("PURE_SSH_LSP_RUST_ANALYZER")?)?,
        quoted(&required("PURE_SSH_LSP_RUST_SRC")?)?,
    )).await?;
    write(&host.files, ".anywork/lsp/dart.toml", format!(
        "schema_version = 1\nid = \"dart\"\ncommand = {}\nargs = [\"language-server\", \"--cache\", \"{{workspaceRoot}}/.dart-cache\"]\nlanguage_ids = [\"dart\"]\nextensions = [\"dart\"]\ndetection = [\"pubspec.yaml\"]\noperations = [\"hover\"]\n{env}",
        quoted(&required("PURE_SSH_LSP_DART")?)?,
    )).await?;
    Ok(())
}

#[tokio::test]
#[ignore = "external real Rust/Dart SSH; requires explicit task-owned SDK/workspace/helper paths"]
async fn ssh_real_rust_dart_directory_leases() -> anyhow::Result<()> {
    let scratch = PathBuf::from(required("PURE_SSH_LSP_SCRATCH")?);
    let artifacts = PathBuf::from(required("PURE_SSH_LSP_ARTIFACTS")?);
    std::fs::create_dir_all(&scratch)?;
    std::fs::create_dir_all(&artifacts)?;
    let config = tempfile::tempdir_in(scratch)?;
    let known_hosts = std::env::var("PURE_SSH_TEST_KNOWN_HOSTS")
        .unwrap_or(format!("{}/.ssh/known_hosts", required("HOME")?));
    let ssh_config = config.path().join("ssh_config");
    std::fs::write(
        &ssh_config,
        format!("UserKnownHostsFile {known_hosts}\nIdentitiesOnly yes\n"),
    )?;
    let manager = SshManager::new(
        std::env::var_os("PURE_REMOTE_HELPER_AARCH64").map(PathBuf::from),
        std::env::var_os("PURE_REMOTE_HELPER_X86_64").map(PathBuf::from),
    )
    .with_ssh_config(SshConfigFile::at(ssh_config));
    let global = LspRuntimeRegistry::new();
    let registry = global.execution_scope("ssh:real-lsp-acceptance");
    let mut evidence = Vec::new();
    let observed: anyhow::Result<()> = async {
        manager
            .save_server(SshServerProfile {
                alias: "real-lsp-acceptance".into(),
                host_name: required("PURE_SSH_TEST_SERVER")?,
                port: std::env::var("PURE_SSH_TEST_PORT")
                    .ok()
                    .map(|p| p.parse())
                    .transpose()?
                    .unwrap_or(22),
                username: required("PURE_SSH_TEST_USERNAME")?,
                identity_file: std::env::var("PURE_SSH_TEST_IDENTITY").ok(),
            })
            .await?;
        let base = manager
            .open_workspace_host("real-lsp-acceptance", required("PURE_SSH_LSP_ROOT")?)
            .await?;
        let remote_root = PathBuf::from(base.files.canonical_path());
        let sdk = remote_root.join("sdk");
        for (name, program) in [
            ("rust-analyzer", required("PURE_SSH_LSP_RUST_ANALYZER")?),
            ("dart", required("PURE_SSH_LSP_DART")?),
            (
                "cargo",
                format!("{}/cargo", required("PURE_SSH_LSP_CARGO_BIN")?),
            ),
        ] {
            if name != "cargo" {
                ensure!(
                    Path::new(&program).starts_with(&sdk),
                    "{name} must use the task-owned SDK directory for process attribution"
                );
            }
            let version = run(&base, &program, vec!["--version".into()]).await?;
            evidence.push(json!({"program": name, "version": version}));
        }
        for directory in ["project-a", "project-b", "home"] {
            base.files.create_directory(directory.into(), None).await?;
        }
        let a = manager
            .open_workspace_host(
                "real-lsp-acceptance",
                remote_root.join("project-a").display().to_string(),
            )
            .await?;
        let b = manager
            .open_workspace_host(
                "real-lsp-acceptance",
                remote_root.join("project-b").display().to_string(),
            )
            .await?;
        prepare(&a, "a", &remote_root).await?;
        prepare(&b, "b", &remote_root).await?;
        let root_a = PathBuf::from(a.files.canonical_path());
        let root_b = PathBuf::from(b.files.canonical_path());
        // Never replace an existing alias or follow an existing directory as a
        // destination. Any pre-existing path fails without touching user data.
        run(
            &base,
            "ln",
            vec![
                "-sT".into(),
                "--".into(),
                "project-a".into(),
                "project-a-alias".into(),
            ],
        )
        .await?;
        let a_alias = manager
            .open_workspace_host(
                "real-lsp-acceptance",
                remote_root.join("project-a-alias").display().to_string(),
            )
            .await?;
        ensure!(
            Path::new(a_alias.files.canonical_path()) == root_a,
            "alias did not canonicalize to directory A"
        );
        ensure!(
            a_alias.files.workspace_id() != a.files.workspace_id(),
            "alias reused A1's workspace lease instead of opening a distinct handle"
        );
        evidence.push(json!({
            "phase": "distinct-workspace-leases",
            "canonicalRoot": root_a,
            "a1WorkspaceId": a.files.workspace_id(),
            "a2WorkspaceId": a_alias.files.workspace_id(),
        }));
        let a1 = registry
            .acquire_workspace(&root_a, Some(Arc::new(a.clone())), None)
            .await?;
        let b1 = registry
            .acquire_workspace(&root_b, Some(Arc::new(b.clone())), None)
            .await?;
        ready(&registry, &root_a, &mut evidence).await?;
        ready(&registry, &root_b, &mut evidence).await?;
        let first_a = tool(&registry, &a);
        let only_b = tool(&registry, &b);
        both(&first_a, "agent-a1", "a", "before", &mut evidence).await?;
        both(&only_b, "agent-b1", "b", "before", &mut evidence).await?;
        let before_a2 = processes(&base, &sdk).await?;
        evidence.push(json!({"phase": "before-a2-alias-acquire", "processes": before_a2}));
        // A is already serving A1. A2 has a distinct temporary workspace lease
        // in the same logical SSH session; acquiring it must not restart A.
        let a2 = registry
            .acquire_workspace(&root_a, Some(Arc::new(a_alias.clone())), None)
            .await?;
        ready(&registry, &root_a, &mut evidence).await?;
        let second_a = tool(&registry, &a_alias);
        both(&second_a, "agent-a2", "a", "before", &mut evidence).await?;
        let running = processes(&base, &sdk).await?;
        evidence.push(json!({"phase": "both-directories-running", "processes": running}));
        let a_pids = |entries: &[Value]| {
            entries
                .iter()
                .filter(|p| p["cwd"].as_str() == root_a.to_str())
                .filter_map(|p| p["pid"].as_u64())
                .collect::<BTreeSet<_>>()
        };
        ensure!(
            a_pids(&before_a2) == a_pids(&running),
            "a distinct workspace lease in the same session restarted directory A"
        );
        for root in [&root_a, &root_b] {
            ensure!(
                running.iter().any(|p| p["cwd"].as_str() == root.to_str()),
                "no observable SDK process for {}",
                root.display()
            );
        }
        let workspace = ToolWorkspace::new(AgentWorkspace::confined(
            &root_a,
            WorkspaceMutability::ReadWrite,
        ))
        .with_lsp_runtime(Some(registry.clone()));
        // Exercise the production post-write ToolWorkspace notification boundary.
        // Do not use raw a.files or manually notify the registry here: a query's
        // own disk refresh must not substitute for the successful mutation path.
        let policy_files = WorkspacePolicyBackend::new(Arc::new(a.files.clone()), workspace);
        write(&policy_files, "src/lib.rs", source("a", "rust", "after")).await?;
        write(
            &policy_files,
            "lib/sample.dart",
            source("a", "dart", "after"),
        )
        .await?;
        both(&second_a, "agent-a2", "a", "after", &mut evidence).await?;
        a1.close().await?;
        drop(first_a);
        both(&second_a, "agent-a2", "a", "after", &mut evidence).await?;
        a2.close().await?;
        drop(second_a);
        let remaining = processes(&base, &sdk).await?;
        evidence.push(json!({"phase": "a-last-user-released", "processes": remaining}));
        ensure!(
            !remaining
                .iter()
                .any(|p| p["cwd"].as_str() == root_a.to_str()
                    || running
                        .iter()
                        .any(|started| started["cwd"].as_str() == root_a.to_str()
                            && started["pid"] == p["pid"])),
            "directory A LSP process survived final lease close: {remaining:?}"
        );
        ensure!(
            !registry.has_ready_servers(&root_a).await,
            "A still publishes live services"
        );
        both(&only_b, "agent-b1", "b", "before", &mut evidence).await?;
        b1.close().await?;
        drop(only_b);
        let remaining = processes(&base, &sdk).await?;
        evidence.push(json!({"phase": "b-last-user-released", "processes": remaining}));
        ensure!(
            remaining.is_empty(),
            "task-owned LSP processes survived final close: {remaining:?}"
        );
        println!("SSH_REAL_RUST_DART_DIRECTORY_LEASES=PASS");
        Ok(())
    }
    .await;
    // Keep registry and transport cleanup observable even when any assertion,
    // preparation, query, or final lease close failed.
    let shutdown = global.shutdown().await;
    let disconnect = manager.shutdown().await;
    let report = json!({
        "observed": observed.as_ref().map(|_| "passed").map_err(|e| format!("{e:#}")),
        "registryShutdown": shutdown.as_ref().map(|_| "passed").map_err(ToString::to_string),
        "sshShutdown": disconnect.as_ref().map(|_| "passed").map_err(ToString::to_string),
        "evidence": evidence,
    });
    std::fs::write(
        artifacts.join("ssh-lsp-real.json"),
        serde_json::to_vec_pretty(&report)?,
    )?;
    observed?;
    shutdown?;
    disconnect?;
    Ok(())
}
