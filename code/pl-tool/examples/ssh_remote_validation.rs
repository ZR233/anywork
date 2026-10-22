#[path = "support/remote_manager.rs"]
mod remote_manager;
#[path = "support/remote_stream.rs"]
mod remote_stream;
use pl_tool::command::{
    CommandProcessLifecycle, CommandProcessManager, CommandStartRequest, CommandWriteRequest,
};
use pl_tool::execution::{ExecutionBackend, ExecutionRequest};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use pl_tool::skill::SkillsConfig;
use pl_tool::skill::{SkillLoadInvocation, SkillProviderRequest, SkillRegistry};
use pl_tool::workspace_file::{
    WorkspaceFileBackend, WorkspaceFileListRequest, WorkspaceFileListResult,
    WorkspaceFileReadBytesRequest, WorkspaceFileReadRequest, WorkspaceFileRemoveRequest,
    WorkspaceFileStat, WorkspaceFileStatRequest, WorkspaceFileWriteRequest,
};

use pl_tool::remote::{RemoteSkillProvider, SshConnectionState, SshManager, SshServerProfile};

use pl_lsp::catalog::{LspCatalogServer, LspCommandSpec, LspServerCatalog, LspServerDefinition};
use pl_lsp::driver::{LspProbeOutcome, LspRepairError, LspResolvedCommand, LspServerDriver};
use pl_lsp::host::LspHostBackend;
use pl_lsp::query::{LspQuery, LspQueryOperation};
use pl_lsp::runtime::{LspMissingComponent, LspRuntimeRegistry};
use tokio_util::sync::CancellationToken;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let host = required("PURE_SSH_TEST_SERVER")?;
    let workspace = required("PURE_SSH_TEST_WORKSPACE")?;
    let aarch64 = std::env::var_os("PURE_REMOTE_HELPER_AARCH64").map(PathBuf::from);
    let x86_64 = std::env::var_os("PURE_REMOTE_HELPER_X86_64").map(PathBuf::from);
    anyhow::ensure!(
        aarch64.is_some() || x86_64.is_some(),
        "provide a remote helper artifact"
    );
    let isolated_config = tempfile::tempdir()?;
    let ssh_config_path = isolated_config.path().join("ssh_config");
    let known_hosts = std::env::var("PURE_SSH_TEST_KNOWN_HOSTS").unwrap_or_else(|_| {
        format!(
            "{}/.ssh/known_hosts",
            std::env::var("HOME").unwrap_or_default()
        )
    });
    std::fs::write(
        &ssh_config_path,
        format!("UserKnownHostsFile {known_hosts}\nIdentitiesOnly yes\n"),
    )?;
    let manager = SshManager::new(aarch64, x86_64)
        .with_ssh_config(pl_tool::remote::SshConfigFile::at(ssh_config_path));
    let identity_file = std::env::var("PURE_SSH_TEST_IDENTITY").ok();
    let profile = SshServerProfile {
        alias: "validation".to_string(),
        host_name: host,
        port: std::env::var("PURE_SSH_TEST_PORT")
            .ok()
            .map(|port| port.parse())
            .transpose()?
            .unwrap_or(22),
        username: std::env::var("PURE_SSH_TEST_USERNAME").unwrap_or_else(|_| "root".to_string()),
        identity_file,
    };
    remote_manager::cancellation_joins_connect(profile.clone(), std::path::Path::new(&known_hosts))
        .await?;
    manager.save_server(profile).await?;
    let snapshot = manager.test_connection("validation").await?;
    println!("connection={:?}", snapshot.state);

    let host = manager
        .open_workspace_host("validation", workspace.clone())
        .await?;
    let cached = manager
        .open_workspace_host("validation", workspace.clone())
        .await?;
    anyhow::ensure!(host.identity() == cached.identity());
    drop(cached);
    let files = Arc::new(host.files.clone());
    files.create_directory("leases".into(), None).await?;
    for cycle in 0..50 {
        let path = format!("leases/{cycle}");
        files.create_directory(path.clone(), None).await?;
        let path = format!("{workspace}/{path}");
        let opened = manager
            .open_workspace_host("validation", path.clone())
            .await?;
        let identity = opened.files.workspace_id().to_owned();
        drop(opened);
        let reopened = manager.open_workspace_host("validation", path).await?;
        anyhow::ensure!(
            reopened.files.workspace_id() != identity,
            "workspace cache permanently retained its last user"
        );
        drop(reopened);
    }
    files.remove_path("leases".into(), None, true).await?;
    println!("workspace leases: 50 distinct open/drop/reopen cycles PASS");
    remote_manager::verify_single_business_channel("multiple-workspaces")?;
    files.create_directory("nested".to_string(), None).await?;
    files
        .write_text(WorkspaceFileWriteRequest {
            mode: pl_tool::workspace::WriteMode::Overwrite,
            path: "nested/input.txt".to_string(),
            cwd: None,
            content: "alpha\nbeta\n".to_string(),
        })
        .await?;
    assert_eq!(
        files
            .read_text(WorkspaceFileReadRequest {
                path: "nested/input.txt".to_string(),
                cwd: None,
            })
            .await?,
        "alpha\nbeta\n"
    );
    let stat = files
        .stat(WorkspaceFileStatRequest {
            path: "nested/input.txt".to_string(),
            cwd: None,
        })
        .await?;
    assert!(stat.is_file);
    files
        .copy_path(
            "nested/input.txt".to_string(),
            "nested/copied.txt".to_string(),
            None,
            false,
        )
        .await?;
    files
        .rename_path(
            "nested/copied.txt".to_string(),
            "nested/moved.txt".to_string(),
            None,
        )
        .await?;
    let listing = files
        .list(WorkspaceFileListRequest {
            path: ".".to_string(),
            cwd: None,
            glob: "**/*.txt".to_string(),
            max_files: 20,
            include_dirs: true,
            cursor: None,
            implicit_recovery: false,
        })
        .await?;
    assert_eq!(
        listing.files,
        vec![
            "nested/input.txt".to_string(),
            "nested/moved.txt".to_string()
        ]
    );

    let processes = CommandProcessManager::new(Arc::new(host.commands.clone()));
    let first = processes
        .start(CommandStartRequest {
            command: "printf 'stdout-one\\n'; printf 'stderr-one\\n' >&2; read line; printf 'stdin:%s\\n' \"$line\"".to_string(),
            cwd: None,
            allow_workspace_escape: false,
            timeout: Duration::from_secs(20),
            yield_time: Duration::from_millis(500),
            max_output_chars: 64 * 1024,
            session_id: "validation".to_string(),
            tool_id: "observable-exec".to_string(),
            call_id: "call-1".to_string(),
            cancellation_token: None,
            output_observer: None,
        })
        .await?;
    assert!(matches!(first.state, CommandProcessLifecycle::Running(_)));
    assert_eq!(first.stdout.content, "stdout-one\n");
    assert_eq!(first.stderr.content, "stderr-one\n");
    let process_id = first.process_id.expect("running process id");
    let final_output = processes
        .write_stdin(CommandWriteRequest {
            process_id,
            chars: "hello\n".to_string(),
            yield_time: Duration::from_secs(5),
            max_output_chars: 64 * 1024,
        })
        .await?;
    assert!(final_output.state.final_result().is_some());
    assert_eq!(final_output.stdout.content, "stdout-one\nstdin:hello\n");
    assert_eq!(final_output.stderr.content, "stderr-one\n");
    let capture = files
        .read_text(WorkspaceFileReadRequest {
            path: final_output.capture_file.to_string_lossy().into_owned(),
            cwd: None,
        })
        .await?;
    assert!(capture.contains("stdout-one"));
    assert!(capture.contains("stderr-one"));
    assert!(capture.contains("stdin:hello"));
    validate_session_capture_layout(files.as_ref(), &final_output.capture_file).await?;

    let environment = run_remote(
        &host.git,
        vec!["sh".into(), "-c".into(), "printf '%s' \"$PATH\"".into()],
    )
    .await?;
    anyhow::ensure!(environment.status == 0, "read remote execution PATH");
    let command_environment = processes
        .start(CommandStartRequest {
            command: "printf '%s' \"$PATH\"".to_string(),
            cwd: None,
            allow_workspace_escape: false,
            timeout: Duration::from_secs(10),
            yield_time: Duration::from_secs(5),
            max_output_chars: 64 * 1024,
            session_id: "validation".into(),
            tool_id: "environment".into(),
            call_id: "environment".into(),
            cancellation_token: None,
            output_observer: None,
        })
        .await?;
    assert_eq!(command_environment.stdout.content, environment.stdout);
    files
        .write_text(WorkspaceFileWriteRequest {
            mode: pl_tool::workspace::WriteMode::Overwrite,
            path: "expected-path.json".into(),
            cwd: None,
            content: serde_json::to_string(&environment.stdout)?,
        })
        .await?;
    if let Ok(tool) = std::env::var("PURE_SSH_TEST_TOOL") {
        let output = run_remote(&host.git, vec![tool, "--version".into()]).await?;
        anyhow::ensure!(
            output.status == 0,
            "configured remote tool must be discoverable"
        );
    }
    let budget = processes
        .run_task(
            "task-remote-budget",
            CommandStartRequest {
                command: "head -c 20000000 /dev/zero".into(),
                cwd: None,
                allow_workspace_escape: false,
                timeout: Duration::from_secs(30),
                yield_time: Duration::ZERO,
                max_output_chars: 256,
                session_id: "budget".into(),
                tool_id: "exec".into(),
                call_id: "remote-budget".into(),
                cancellation_token: None,
                output_observer: None,
            },
        )
        .await?;
    let limit = budget
        .output_limit_exceeded()
        .expect("remote manager must return typed capacity termination");
    let usage = budget.capture_usage.expect("final producer receipt");
    let disk = files
        .stat(WorkspaceFileStatRequest {
            path: budget.capture_file.to_string_lossy().into_owned(),
            cwd: None,
        })
        .await?;
    anyhow::ensure!(
        limit.charged_bytes == usage.charged_bytes && Some(usage.charged_bytes) == disk.len
    );
    anyhow::ensure!(usage.charged_bytes <= usage.limit_bytes && usage.refused_bytes > 0);
    anyhow::ensure!(budget.capture_repair().is_none());
    println!("remote capacity termination={limit:?}, disk={:?}", disk.len);

    // Git/worktree 没有归档读者，直传结果不应继承 exec 的磁盘额度。
    let large = run_remote(
        &host.git,
        vec![
            "sh".into(),
            "-c".into(),
            "head -c 20000000 /dev/zero".into(),
        ],
    )
    .await?;
    anyhow::ensure!(large.status == 0 && large.stdout.len() == 20_000_000);
    validate_git(&host.git, files.as_ref()).await?;
    validate_skills(files.clone()).await?;
    validate_image_bytes(files.as_ref()).await?;
    validate_lsp_backend(host.clone(), files.as_ref()).await?;

    let mut connection_state = manager.subscribe_state("validation").await;
    use pl_tool::command::{CommandBackend, CommandOutputTarget, CommandSpawnRequest};
    use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
    let mut tree = host.commands.spawn(CommandSpawnRequest {
        process_id: "reconnect-tree".into(),
        command: "sleep 60 & child=$!; echo $child > tree.pid; printf 'ready\\n'; read line; printf 'continued:%s\\n' \"$line\"; kill $child; wait $child 2>/dev/null; exit 0".into(),
        cwd: ".".into(), output_target: CommandOutputTarget::new("reconnect.log", "reconnect.log"),
        capture_limit_bytes: 1024 * 1024,
    }).await?;
    let mut stdout = BufReader::new(tree.take_stdout().expect("command stdout"));
    let mut stderr = tree.take_stderr().expect("command stderr");
    let mut stdin = tree.take_stdin().expect("command stdin");
    let mut line = String::new();
    stdout.read_line(&mut line).await?;
    anyhow::ensure!(
        line == "ready\n",
        "command must be running before disconnect"
    );
    manager.reconnect_server("validation").await?;
    wait_until_ready(&mut connection_state).await?;
    let reconnected = manager.open_workspace_host("validation", workspace).await?;
    anyhow::ensure!(
        host.identity() == reconnected.identity(),
        "attachment replacement changed physical workspace identity"
    );
    stdin.write_all(b"once\n").await?;
    drop(stdin);
    let (output, errors, exit) = tokio::join!(
        async {
            let mut text = String::new();
            stdout.read_to_string(&mut text).await?;
            anyhow::Ok(text)
        },
        async {
            let mut bytes = Vec::new();
            stderr.read_to_end(&mut bytes).await?;
            anyhow::Ok(bytes)
        },
        tree.wait()
    );
    anyhow::ensure!(output? == "continued:once\n" && errors?.is_empty());
    anyhow::ensure!(exit.map_err(anyhow::Error::msg)?.exit_code == Some(0));
    println!(
        "same-instance reconnect: original process, stdin, output and workspace identity PASS"
    );
    let reconnected_files = Arc::new(reconnected.files);
    let cleanup_check = run_remote(
        &reconnected.git,
        vec![
            "sh".into(),
            "-c".into(),
            "if kill -0 \"$(cat tree.pid)\" 2>/dev/null; then echo alive; else echo dead; fi"
                .into(),
        ],
    )
    .await?;
    anyhow::ensure!(cleanup_check.stdout.trim() == "dead");

    let transfer_bytes = std::env::var("PURE_SSH_TEST_TRANSFER_BYTES")
        .ok()
        .map(|value| value.parse::<u64>())
        .transpose()?
        .unwrap_or(1024 * 1024 * 1024);
    anyhow::ensure!(transfer_bytes >= 2);
    let (reached, at_gate) = tokio::sync::oneshot::channel();
    let (resume, continued) = tokio::sync::oneshot::channel();
    let uploader = reconnected_files.clone();
    let upload_started = std::time::Instant::now();
    let mut upload = tokio::spawn(async move {
        let mut source = remote_stream::GatedPattern::new(transfer_bytes, reached, continued);
        uploader
            .copy_file_from(
                "streamed.bin",
                pl_tool::workspace::WriteMode::Overwrite,
                transfer_bytes,
                &mut source,
            )
            .await
    });
    tokio::select! {
        reached = at_gate => reached?,
        result = &mut upload => { anyhow::bail!("upload completed before the reconnect gate: {result:?}"); }
    }
    remote_manager::verify_single_business_channel("file-transfer-active")?;
    let restoring = std::time::Instant::now();
    manager.reconnect_server("validation").await?;
    let recovery_seconds = restoring.elapsed().as_secs_f64();
    remote_manager::verify_single_business_channel("replacement-attached")?;
    resume
        .send(())
        .map_err(|_| anyhow::anyhow!("upload source retired early"))?;
    anyhow::ensure!(upload.await?? == transfer_bytes);
    let upload_seconds = upload_started.elapsed().as_secs_f64();
    let download_started = std::time::Instant::now();
    anyhow::ensure!(
        reconnected_files
            .copy_file_to("streamed.bin", &mut tokio::io::sink())
            .await?
            == transfer_bytes
    );
    println!(
        "{}",
        serde_json::json!({"scenario":"ssh-streaming-transfer", "bytes":transfer_bytes,
        "uploadSeconds":upload_seconds, "downloadSeconds":download_started.elapsed().as_secs_f64(),
        "recoverySeconds":recovery_seconds, "wholeFileResident":false, "sha256Match":true})
    );

    for path in [
        "nested",
        ".agents/skills",
        ".git",
        ".anywork",
        "target",
        "pixel.png",
        "fixture.py",
        "lsp_fixture.py",
        "expected-path.json",
        "tracked.txt",
        "tree.pid",
        "reconnect.log",
        "streamed.bin",
    ] {
        if reconnected_files
            .stat_optional(path.to_string(), None)
            .await?
            .is_some()
        {
            reconnected_files
                .remove_path(path.to_string(), None, true)
                .await?;
        }
    }

    manager.disconnect_server("validation").await?;
    println!("remote SSH validation passed");
    Ok(())
}

async fn validate_session_capture_layout(
    files: &pl_tool::remote::RemoteWorkspaceFileBackend,
    capture: &std::path::Path,
) -> anyhow::Result<()> {
    use pl_tool::workspace::{
        AgentWorkspace, POOL_GITIGNORE, SessionFiles, prepare_session_files, prepare_worktree_pool,
    };
    let capture = capture.to_string_lossy().replace('\\', "/");
    anyhow::ensure!(
        capture.starts_with(".anywork/sessions/") && capture.ends_with("/output.log"),
        "remote capture must use session commands layout: {capture}"
    );
    anyhow::ensure!(!capture.contains("target/pure"));
    let alpha = SessionFiles::new("validation");
    anyhow::ensure!(capture.contains(alpha.thread_key()));
    if files
        .stat_optional(".anywork/sessions/.gitignore".into(), None)
        .await?
        .is_none()
    {
        files
            .write_text(WorkspaceFileWriteRequest {
                mode: pl_tool::workspace::WriteMode::Create,
                path: ".anywork/sessions/.gitignore".into(),
                cwd: None,
                content: "keep-remote\n".into(),
            })
            .await?;
    }
    let existing = files
        .read_text(WorkspaceFileReadRequest {
            path: ".anywork/sessions/.gitignore".into(),
            cwd: None,
        })
        .await?;
    prepare_session_files(files, &alpha).await?;
    prepare_worktree_pool(files).await?;
    let after = files
        .read_text(WorkspaceFileReadRequest {
            path: ".anywork/sessions/.gitignore".into(),
            cwd: None,
        })
        .await?;
    anyhow::ensure!(
        after == existing,
        "existing sessions ignore must be preserved"
    );
    let worktree_ignore = files
        .read_text(WorkspaceFileReadRequest {
            path: ".anywork/worktrees/.gitignore".into(),
            cwd: None,
        })
        .await?;
    anyhow::ensure!(worktree_ignore == POOL_GITIGNORE);
    files.create_directory("nested".into(), None).await?;
    let relative = files
        .write_text(WorkspaceFileWriteRequest {
            mode: pl_tool::workspace::WriteMode::Overwrite,
            path: "from-cwd.txt".into(),
            cwd: Some("nested".into()),
            content: "cwd-ok\n".into(),
        })
        .await;
    anyhow::ensure!(relative.is_ok());
    anyhow::ensure!(
        files
            .create_directory("../escape".into(), None)
            .await
            .is_err()
    );
    let workspace = AgentWorkspace::directory("/remote", Some(vec!["/remote/src".into()]))
        .with_session_id("validation");
    anyhow::ensure!(
        workspace
            .ensure_relative_path_writable(None, &alpha.scratch().to_string_lossy())
            .is_ok()
    );
    anyhow::ensure!(
        workspace
            .ensure_relative_path_writable(None, &alpha.commands().join("x").to_string_lossy())
            .is_err()
    );
    let empty =
        AgentWorkspace::directory("/remote", Some(Vec::new())).with_session_id("validation");
    anyhow::ensure!(
        empty
            .ensure_relative_path_writable(None, &alpha.scratch().to_string_lossy())
            .is_ok()
    );
    anyhow::ensure!(
        empty
            .ensure_relative_path_writable(None, &alpha.artifacts().to_string_lossy())
            .is_ok()
    );
    anyhow::ensure!(
        empty
            .ensure_relative_path_writable(None, "src/lib.rs")
            .is_err()
    );
    anyhow::ensure!(
        empty
            .ensure_relative_path_writable(None, &alpha.commands().join("x").to_string_lossy())
            .is_err()
    );
    concurrent_remote_pool_ignore(files).await?;
    println!("OK  remote SessionFiles capture, ignore, relative cwd");
    Ok(())
}

async fn concurrent_remote_pool_ignore(
    files: &pl_tool::remote::RemoteWorkspaceFileBackend,
) -> anyhow::Result<()> {
    use pl_tool::workspace::{POOL_GITIGNORE, prepare_worktree_pool};
    use tokio::sync::Barrier;

    files
        .remove_path(".anywork/worktrees/.gitignore".into(), None, false)
        .await
        .ok();
    files
        .remove_path(".anywork/worktrees".into(), None, true)
        .await
        .ok();
    let barrier = Arc::new(Barrier::new(2));
    let left = RacingRemoteIgnore {
        inner: files.clone(),
        barrier: barrier.clone(),
        ignore_path: ".anywork/worktrees/.gitignore".into(),
    };
    let right = RacingRemoteIgnore {
        inner: files.clone(),
        barrier,
        ignore_path: ".anywork/worktrees/.gitignore".into(),
    };
    let (left_result, right_result) =
        tokio::join!(prepare_worktree_pool(&left), prepare_worktree_pool(&right));
    left_result?;
    right_result?;
    let ignore = files
        .read_text(WorkspaceFileReadRequest {
            path: ".anywork/worktrees/.gitignore".into(),
            cwd: None,
        })
        .await?;
    anyhow::ensure!(ignore == POOL_GITIGNORE);
    println!("OK  remote concurrent worktree ignore create");
    Ok(())
}

#[derive(Debug, Clone)]
struct RacingRemoteIgnore {
    inner: pl_tool::remote::RemoteWorkspaceFileBackend,
    barrier: Arc<tokio::sync::Barrier>,
    ignore_path: String,
}

impl WorkspaceFileBackend for RacingRemoteIgnore {
    async fn default_cwd(&self) -> pl_protocol::Result<String> {
        self.inner.default_cwd().await
    }

    async fn stat_optional(
        &self,
        request: WorkspaceFileStatRequest,
    ) -> pl_protocol::Result<Option<WorkspaceFileStat>> {
        let racing = request.path == self.ignore_path;
        let result = WorkspaceFileBackend::stat_optional(&self.inner, request).await?;
        if racing && result.is_none() {
            self.barrier.wait().await;
        }
        Ok(result)
    }

    async fn read_text(&self, request: WorkspaceFileReadRequest) -> pl_protocol::Result<String> {
        self.inner.read_text(request).await
    }

    async fn read_bytes(
        &self,
        request: WorkspaceFileReadBytesRequest,
    ) -> pl_protocol::Result<Vec<u8>> {
        self.inner.read_bytes(request).await
    }

    async fn write_text(&self, request: WorkspaceFileWriteRequest) -> pl_protocol::Result<()> {
        self.inner.write_text(request).await
    }

    async fn remove_file(&self, request: WorkspaceFileRemoveRequest) -> pl_protocol::Result<()> {
        self.inner.remove_file(request).await
    }

    async fn list(
        &self,
        request: WorkspaceFileListRequest,
    ) -> pl_protocol::Result<WorkspaceFileListResult> {
        self.inner.list(request).await
    }

    async fn close_listing(&self, cursor: String) -> pl_protocol::Result<()> {
        self.inner.close_listing(cursor).await
    }

    async fn create_directory(&self, path: String, cwd: Option<String>) -> pl_protocol::Result<()> {
        self.inner.create_directory(path, cwd).await
    }
}

async fn validate_git(
    backend: &pl_tool::remote::RemoteExecutionBackend,
    files: &pl_tool::remote::RemoteWorkspaceFileBackend,
) -> anyhow::Result<()> {
    assert_eq!(
        run_remote(
            backend,
            vec!["git".to_string(), "init".to_string(), "-q".to_string()]
        )
        .await?
        .status,
        0
    );
    files
        .write_text(WorkspaceFileWriteRequest {
            mode: pl_tool::workspace::WriteMode::Overwrite,
            path: "tracked.txt".to_string(),
            cwd: None,
            content: "remote git\n".to_string(),
        })
        .await?;
    for args in [
        vec!["git", "config", "user.email", "remote@example.invalid"],
        vec!["git", "config", "user.name", "Remote Validation"],
        vec!["git", "add", "tracked.txt"],
        vec!["git", "commit", "-q", "-m", "validation"],
        vec![
            "git",
            "worktree",
            "add",
            "-q",
            "-b",
            "validation/worktree",
            ".anywork/worktree",
        ],
        vec!["git", "worktree", "remove", "-f", ".anywork/worktree"],
    ] {
        let output = run_remote(backend, args.into_iter().map(str::to_string).collect()).await?;
        anyhow::ensure!(output.status == 0, "git failed: {}", output.stderr);
    }
    Ok(())
}

async fn validate_skills(
    files: Arc<pl_tool::remote::RemoteWorkspaceFileBackend>,
) -> anyhow::Result<()> {
    files
        .create_directory(".agents/skills/remote".to_string(), None)
        .await?;
    files
        .write_text(WorkspaceFileWriteRequest {
            mode: pl_tool::workspace::WriteMode::Overwrite,
            path: ".agents/skills/remote/SKILL.md".to_string(),
            cwd: None,
            content: "---\nname: remote-validation\ndescription: Validate remote Skills.\n---\n\n# Remote validation\n"
                .to_string(),
        })
        .await?;
    files
        .create_directory(".agents/skills/remote/references".to_string(), None)
        .await?;
    files
        .write_text(WorkspaceFileWriteRequest {
            mode: pl_tool::workspace::WriteMode::Overwrite,
            path: ".agents/skills/remote/references/info.md".to_string(),
            cwd: None,
            content: "remote reference".to_string(),
        })
        .await?;
    let registry = SkillRegistry::new();
    let _registration = registry.register(Arc::new(RemoteSkillProvider::new(files)?))?;
    let catalog = registry
        .discover(SkillProviderRequest {
            workspace_root: PathBuf::from("remote-validation"),
            config: SkillsConfig::default(),
            system_dir: None,
            cancellation: CancellationToken::new(),
        })
        .await?;
    assert!(catalog.find("remote-validation").is_some());
    let loaded = catalog
        .load(
            "remote-validation",
            SkillLoadInvocation::Model,
            CancellationToken::new(),
        )
        .await?;
    assert!(loaded.content.contains("# Remote validation"));
    assert_eq!(
        catalog
            .read_resource(
                "remote-validation",
                "references/info.md",
                SkillLoadInvocation::Model,
                CancellationToken::new(),
            )
            .await?,
        "remote reference"
    );
    Ok(())
}

async fn validate_image_bytes(
    files: &pl_tool::remote::RemoteWorkspaceFileBackend,
) -> anyhow::Result<()> {
    let png = base64::Engine::decode(
        &base64::engine::general_purpose::STANDARD,
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
    )?;
    files
        .write_bytes_atomic("pixel.png".to_string(), None, &png)
        .await?;
    assert_eq!(
        files
            .read_bytes(WorkspaceFileReadBytesRequest {
                path: "pixel.png".to_string(),
                cwd: None,
                max_bytes: 1024,
            })
            .await?,
        png
    );
    Ok(())
}

async fn validate_lsp_backend(
    host: pl_tool::remote::RemoteWorkspaceHost,
    files: &pl_tool::remote::RemoteWorkspaceFileBackend,
) -> anyhow::Result<()> {
    let server = r#"import json
import os
import sys

with open("expected-path.json") as expected:
    assert os.environ["PATH"] == json.load(expected), "LSP must inherit the execution environment"

def read_message():
    length = None
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line == b"\r\n":
            break
        name, value = line.decode().split(":", 1)
        if name.lower() == "content-length":
            length = int(value.strip())
    return json.loads(sys.stdin.buffer.read(length))

def send(value):
    body = json.dumps(value, separators=(",", ":")).encode()
    sys.stdout.buffer.write(b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)
    sys.stdout.buffer.flush()

while True:
    message = read_message()
    if message is None:
        break
    method = message.get("method")
    if method == "exit":
        break
    if "id" not in message:
        continue
    if method == "initialize":
        result = {"capabilities": {"documentSymbolProvider": True}}
    elif method == "textDocument/documentSymbol":
        result = [{"name": "remote_symbol", "kind": 12, "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 5}}, "selectionRange": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 5}}}]
    elif method == "shutdown":
        result = None
    else:
        result = None
    send({"jsonrpc": "2.0", "id": message["id"], "result": result})
"#;
    files
        .write_text(WorkspaceFileWriteRequest {
            mode: pl_tool::workspace::WriteMode::Overwrite,
            path: "lsp_fixture.py".to_string(),
            cwd: None,
            content: server.to_string(),
        })
        .await?;
    files
        .write_text(WorkspaceFileWriteRequest {
            mode: pl_tool::workspace::WriteMode::Overwrite,
            path: "fixture.py".to_string(),
            cwd: None,
            content: "def remote_symbol():\n    pass\n".to_string(),
        })
        .await?;

    let mut catalog = LspServerCatalog::empty();
    catalog.insert(LspCatalogServer {
        definition: LspServerDefinition {
            id: "remote-python-fixture".to_string(),
            display_name: "Remote Python fixture".to_string(),
            language_ids: vec!["python".to_string()],
            extensions: vec![".py".to_string()],
            detection: vec!["fixture.py".to_string()],
            command: LspCommandSpec {
                program: "python3".to_string(),
                args: vec!["-u".to_string(), "lsp_fixture.py".to_string()],
            },
            operations: vec![LspQueryOperation::DocumentSymbol],
        },
        driver: Arc::new(ValidationLspDriver),
    })?;
    let registry = LspRuntimeRegistry::with_catalog(catalog);
    let workspace_root = PathBuf::from(files.canonical_path());
    let host: Arc<dyn LspHostBackend> = Arc::new(host);
    registry
        .reconcile_workspace_membership_with_host(&workspace_root, host)
        .await;
    registry.probe_lsp_server(&workspace_root).await;
    let result = registry
        .query_in_workspace(
            &workspace_root,
            LspQuery {
                operation: LspQueryOperation::DocumentSymbol,
                file_path: Some(workspace_root.join("fixture.py")),
                line: None,
                character: None,
                query: None,
                max_results: None,
                language_id: Some("python".to_string()),
            },
        )
        .await?;
    assert!(result.success);
    assert!(result.result.contains("remote_symbol"));
    registry.shutdown().await?;
    Ok(())
}

struct ValidationLspDriver;

impl LspServerDriver for ValidationLspDriver {
    fn probe<'a>(
        &'a self,
        _command: &'a LspResolvedCommand,
        _host: Option<&'a dyn LspHostBackend>,
    ) -> futures::future::BoxFuture<'a, LspProbeOutcome> {
        Box::pin(std::future::ready(LspProbeOutcome::Ready {
            version: "fixture".to_string(),
        }))
    }

    fn repair<'a>(
        &'a self,
        _component: &'a LspMissingComponent,
        _host: Option<&'a dyn LspHostBackend>,
    ) -> futures::future::BoxFuture<'a, Result<(), LspRepairError>> {
        Box::pin(std::future::ready(Err(LspRepairError::NotSupported)))
    }
}

async fn run_remote(
    backend: &pl_tool::remote::RemoteExecutionBackend,
    command: Vec<String>,
) -> anyhow::Result<pl_tool::execution::ExecutionOutput> {
    let (program, args) = command
        .split_first()
        .ok_or_else(|| anyhow::anyhow!("remote command must not be empty"))?;
    backend
        .run(ExecutionRequest {
            program: PathBuf::from(program),
            args: args.to_vec(),
            cwd: PathBuf::from("."),
            env: Default::default(),
            timeout: Some(Duration::from_secs(30)),
        })
        .await
        .map_err(anyhow::Error::msg)
}

async fn wait_until_ready(
    state: &mut tokio::sync::watch::Receiver<SshConnectionState>,
) -> anyhow::Result<()> {
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            state
                .changed()
                .await
                .map_err(|_| anyhow::anyhow!("SSH state stream closed"))?;
            if matches!(&*state.borrow(), SshConnectionState::Ready { .. }) {
                return Ok::<_, anyhow::Error>(());
            }
        }
    })
    .await
    .map_err(|_| anyhow::anyhow!("SSH reconnect did not become ready"))??;
    Ok(())
}

fn required(name: &str) -> anyhow::Result<String> {
    std::env::var(name).map_err(|_| anyhow::anyhow!("{name} must be set"))
}
