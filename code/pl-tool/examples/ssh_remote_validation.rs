//! 真实 SSH endpoint 的端到端观察；不进入自动测试门禁。
//!
//! 运行前准备（当前示例端口可用 `PURE_SSH_TEST_PORT` 指定，默认 22）：
//! - `PURE_SSH_TEST_SERVER`：ssh 配置里的 HostName（示例会写入隔离 ssh_config）
//! - `PURE_SSH_TEST_WORKSPACE`：远端 canonical 工作区目录
//! - `PURE_REMOTE_HELPER_AARCH64` / `PURE_REMOTE_HELPER_X86_64`：至少一个 helper 资产
//! - 可选 `PURE_SSH_TEST_PORT`、`PURE_SSH_TEST_USERNAME`、`PURE_SSH_TEST_IDENTITY`、
//!   `PURE_SSH_TEST_KNOWN_HOSTS`、`PURE_SSH_TEST_TOOL`
//! - 流式传输：`PURE_SSH_TEST_TRANSFER_BYTES`（完整验收必须 >= 1 GiB，非法值直接失败）；
//! - 弹性池：`PURE_SSH_TEST_POOL_STREAMS`（完整验收必须 > 511，默认 600）
//!
//! `PURE_SSH_TEST_WORKSPACE` 是**父目录**：示例只通过它的 command/文件接口在此创建本次独占的
//! 子目录（`mkdir` 不带 `-p`，已存在即失败），所有写入、Git/skills/capture/租约/pool 操作都绑定
//! 到该子目录。只有本次 ownership 且全部场景成功后才递归删除该子目录；任何失败都保留现场并
//! 报告路径，绝不删除父目录中的既存内容。
//!
//! 观察内容：文件/命令/Git/Skills/LSP 业务入口、workspace 租约、capture 预算、断线进程回收，
//! 固定内存的 GiB 级流式往返，以及 600 条真实在途上传让真实 ssh 子进程数扩容、并在责任释放后
//! 回落（逻辑操作数不冒充 OS 进程数）。
//!
//! 完整验收为默认模式；`PURE_REMOTE_ACCEPTANCE_SMOKE=1` 用较小数据自查并明确不主张完整验收。
//! 本文件只使用逻辑 `is_same_binding`/真实操作核对代次；physical workspace 的 open/close
//! 生命周期由 `helper_transport_validation` 用低层 `RemoteClient` 直接核对。
use anyhow::Context;
use pl_tool::command::{
    CommandProcessFinalResult, CommandProcessLifecycle, CommandProcessManager, CommandStartRequest,
    CommandWriteRequest,
};
use pl_tool::execution::{ExecutionBackend, ExecutionRequest};
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use pl_tool::skill::SkillsConfig;
use pl_tool::skill::{SkillLoadInvocation, SkillProviderRequest, SkillRegistry};
use pl_tool::workspace_file::{
    WorkspaceFileBackend, WorkspaceFileListRequest, WorkspaceFileListResult,
    WorkspaceFileReadBytesRequest, WorkspaceFileReadRequest, WorkspaceFileRemoveRequest,
    WorkspaceFileStat, WorkspaceFileStatRequest, WorkspaceFileWriteRequest,
};

use pl_tool::remote::{
    RemoteSkillProvider, RemoteWorkspaceHost, SshConnectionState, SshManager, SshServerProfile,
};

use pl_lsp::catalog::{LspCatalogServer, LspCommandSpec, LspServerCatalog, LspServerDefinition};
use pl_lsp::driver::{LspProbeOutcome, LspRepairError, LspResolvedCommand, LspServerDriver};
use pl_lsp::host::LspHostBackend;
use pl_lsp::query::{LspQuery, LspQueryOperation};
use pl_lsp::runtime::{LspMissingComponent, LspRuntimeRegistry};
use tokio_util::sync::CancellationToken;

#[path = "support/outcome.rs"]
mod outcome;
#[path = "support/transfer.rs"]
mod transfer;

use outcome::combine;
use pl_protocol::remote::RemoteWriteMode;
use transfer::{HashingWriter, PatternReader, UploadGate};

/// 安装 tracing 订阅者，让生产已有的结构化生命周期事件出现在 stderr。
///
/// 默认过滤 `pl_tool::remote=info`，可用 `PURE_SSH_TEST_LOG` 覆盖。只消费生产已有字段，
/// 不记录请求/响应正文、目录全集或凭据；安装失败如实返回错误。
///
/// helper 广告的 FD 预算（`resources.operationFds/workspaceFds/costs.*`，只有数值）没有
/// 公共访问器，但生产已在**每次物理连接握手完成时**用 `tracing::debug!` 记录，目标
/// `pl_tool::remote::client`、消息 `connected remote helper`，字段为 `connection`、
/// `helper_version`、`os`、`architecture`、`operation_fds`、`workspace_fds`、
/// `cost_workspace_open`、`cost_workspace_retained`、`cost_metadata`、`cost_directory`、
/// `cost_read_file`、`cost_write_file`、`cost_copy_file`、`cost_spawn`。
/// 默认过滤是 `pl_tool::remote=info`，因此用 `PURE_SSH_TEST_LOG=pl_tool::remote=debug`
/// 运行即可在本示例的 stderr 读到这些数值；本示例不复制 helper 常量，也不新增 getter。
fn init_tracing() -> anyhow::Result<()> {
    let filter = tracing_subscriber::EnvFilter::try_from_env("PURE_SSH_TEST_LOG")
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("pl_tool::remote=info"));
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .try_init()
        .map_err(|error| anyhow::anyhow!("installing the tracing subscriber failed: {error}"))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    init_tracing()?;
    let host = required("PURE_SSH_TEST_SERVER")?;
    let parent_root = required("PURE_SSH_TEST_WORKSPACE")?;
    let aarch64 = std::env::var_os("PURE_REMOTE_HELPER_AARCH64").map(PathBuf::from);
    let x86_64 = std::env::var_os("PURE_REMOTE_HELPER_X86_64").map(PathBuf::from);
    anyhow::ensure!(
        aarch64.is_some() || x86_64.is_some(),
        "provide a remote helper artifact"
    );
    let smoke = smoke_mode();
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
    let port: u16 = std::env::var("PURE_SSH_TEST_PORT")
        .ok()
        .map(|value| value.parse::<u16>())
        .transpose()
        .context("PURE_SSH_TEST_PORT must be a TCP port number")?
        .unwrap_or(22);
    anyhow::ensure!(
        port != 1420,
        "port 1420 is reserved for the user's dev server"
    );
    let profile = SshServerProfile {
        alias: "validation".to_string(),
        host_name: host,
        port,
        username: std::env::var("PURE_SSH_TEST_USERNAME").unwrap_or_else(|_| "root".to_string()),
        identity_file,
    };
    manager.save_server(profile).await?;
    let snapshot = manager.test_connection("validation").await?;
    println!("connection={:?}", snapshot.state);

    // `PURE_SSH_TEST_WORKSPACE` 是父目录：只通过它的 command/文件接口建立本次独占子目录，
    // 之后所有写操作都绑定到该子目录；只有本次 ownership 且全部成功才删除它。
    let parent = manager
        .open_workspace_host("validation", parent_root.clone())
        .await?;
    let child_name = exclusive_child_name();
    // 候选完整路径在 mkdir 之前就已确定：之后任何失败都必须带着它报告。
    let root = format!("{parent_root}/{child_name}");
    let created = create_exclusive_child(&parent, &child_name, &root).await;
    drop(parent);
    if let Err(error) = created {
        // mkdir 结果未知或已成功但验证失败，都不能声明“肯定没创建”：保留候选路径，
        // 并真实断开连接（清理失败合并进主错误，不吞掉）。
        let disconnected = manager
            .disconnect_server("validation")
            .await
            .map_err(anyhow::Error::new);
        return Err(combine_with_candidate(error, disconnected, &root));
    }
    println!("exclusive remote workspace: {root}");

    let outcome = scenarios(&manager, &root, smoke).await;
    // 清理只在本次 ownership 且场景全部成功时执行；失败保留现场并报告路径。
    let disposal = match &outcome {
        Ok(()) => match manager
            .open_workspace_host("validation", parent_root.clone())
            .await
        {
            Ok(parent) => dispose_child(&parent.files, &child_name).await,
            Err(error) => Err(anyhow::Error::new(error).context("reopen parent workspace")),
        },
        Err(error) => {
            println!("kept exclusive workspace {root} after failure: {error:#}");
            Ok(())
        }
    };
    if disposal.is_err() {
        println!("exclusive workspace may remain at {root}");
    }
    let disconnected = manager
        .disconnect_server("validation")
        .await
        .map_err(anyhow::Error::new);
    combine(combine(outcome, disposal), disconnected)
}

/// 场景主体：全部路径都相对于本次独占子目录 `root`。
async fn scenarios(manager: &SshManager, root: &str, smoke: bool) -> anyhow::Result<()> {
    let host = manager
        .open_workspace_host("validation", root.to_string())
        .await?;
    let cached = manager
        .open_workspace_host("validation", root.to_string())
        .await?;
    anyhow::ensure!(host.identity() == cached.identity());
    drop(cached);
    let files = Arc::new(host.files.clone());
    files.create_directory("leases".into(), None).await?;
    for cycle in 0..50 {
        let path = format!("leases/{cycle}");
        files.create_directory(path.clone(), None).await?;
        let path = format!("{root}/{path}");
        let opened = manager
            .open_workspace_host("validation", path.clone())
            .await?;
        let binding = opened.files.clone();
        drop(opened);
        let reopened = manager.open_workspace_host("validation", path).await?;
        // §7：逻辑绑定不永久持有 physical lease；同一代次同一 canonical 路径仍是同一逻辑绑定，
        // 但每次真实操作自己取租约。physical 的 open/close 生命周期由
        // helper_transport_validation 用低层 RemoteClient 直接核对。
        anyhow::ensure!(
            reopened.files.is_same_binding(&binding),
            "reopening one canonical path changed its logical binding"
        );
        reopened
            .files
            .stat_optional(".".into(), None)
            .await?
            .ok_or_else(|| anyhow::anyhow!("reopened workspace handle is not usable"))?;
        drop(reopened);
    }
    files.remove_path("leases".into(), None, true).await?;
    println!("workspace leases: 50 distinct open/drop/reopen cycles PASS");
    files.create_directory("nested".to_string(), None).await?;
    files
        .write_text(WorkspaceFileWriteRequest {
            mode: pl_tool::workspace::WriteMode::Overwrite,
            path: "nested/input.txt".to_string(),
            cwd: None,
            content: "alpha\nbeta\n".to_string(),
        })
        .await?;
    anyhow::ensure!(
        files
            .read_text(WorkspaceFileReadRequest {
                path: "nested/input.txt".to_string(),
                cwd: None,
            })
            .await?
            == "alpha\nbeta\n",
        "nested/input.txt read back mismatch"
    );
    let stat = files
        .stat(WorkspaceFileStatRequest {
            path: "nested/input.txt".to_string(),
            cwd: None,
        })
        .await?;
    anyhow::ensure!(stat.is_file, "nested/input.txt is not a file");
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
        })
        .await?;
    anyhow::ensure!(
        listing.files
            == vec![
                "nested/input.txt".to_string(),
                "nested/moved.txt".to_string()
            ],
        "nested listing mismatch"
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
    anyhow::ensure!(
        matches!(first.state, CommandProcessLifecycle::Running(_)),
        "long running command did not stay Running"
    );
    anyhow::ensure!(
        first.stdout.content == "stdout-one\n",
        "first stdout mismatch"
    );
    anyhow::ensure!(
        first.stderr.content == "stderr-one\n",
        "first stderr mismatch"
    );
    let process_id = first
        .process_id
        .ok_or_else(|| anyhow::anyhow!("the long running command did not report a process id"))?;
    let final_output = processes
        .write_stdin(CommandWriteRequest {
            process_id,
            chars: "hello\n".to_string(),
            yield_time: Duration::from_secs(5),
            max_output_chars: 64 * 1024,
        })
        .await?;
    anyhow::ensure!(
        final_output.state.final_result().is_some(),
        "stdin write did not settle the process"
    );
    anyhow::ensure!(
        final_output.stdout.content == "stdout-one\nstdin:hello\n",
        "final stdout mismatch"
    );
    anyhow::ensure!(
        final_output.stderr.content == "stderr-one\n",
        "final stderr mismatch"
    );
    let capture = files
        .read_text(WorkspaceFileReadRequest {
            path: final_output.capture_file.to_string_lossy().into_owned(),
            cwd: None,
        })
        .await?;
    anyhow::ensure!(capture.contains("stdout-one"), "capture file lost stdout");
    anyhow::ensure!(capture.contains("stderr-one"), "capture file lost stderr");
    anyhow::ensure!(
        capture.contains("stdin:hello"),
        "capture file lost stdin echo"
    );
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
    anyhow::ensure!(
        command_environment.stdout.content == environment.stdout,
        "command PATH differs from remote environment"
    );
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
        .ok_or_else(|| anyhow::anyhow!("remote manager must return typed capacity termination"))?;
    let usage = budget
        .capture_usage
        .ok_or_else(|| anyhow::anyhow!("remote manager must report the final producer receipt"))?;
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
    validate_streaming_transfer(
        files.as_ref(),
        root,
        &host.git,
        smoke,
        if smoke {
            Duration::from_secs(900)
        } else {
            Duration::from_secs(7200)
        },
    )
    .await?;
    validate_elastic_pool(files.as_ref(), root, &host.git, smoke).await?;

    let mut connection_state = manager.subscribe_state("validation").await;
    let tree = processes
        .start(CommandStartRequest {
            command: "sleep 60 & echo $! > tree.pid; wait".to_string(),
            cwd: None,
            allow_workspace_escape: false,
            timeout: Duration::from_secs(90),
            yield_time: Duration::from_millis(300),
            max_output_chars: 64 * 1024,
            session_id: "validation".to_string(),
            tool_id: "disconnect-tree".to_string(),
            call_id: "call-tree".to_string(),
            cancellation_token: None,
            output_observer: None,
        })
        .await?;
    let process_id = tree
        .process_id
        .ok_or_else(|| anyhow::anyhow!("tree process must still be running"))?;
    manager.reconnect_server("validation").await?;
    let interrupted = processes
        .write_stdin(CommandWriteRequest {
            process_id,
            chars: String::new(),
            yield_time: Duration::from_secs(5),
            max_output_chars: 64 * 1024,
        })
        .await?;
    anyhow::ensure!(
        matches!(
            interrupted.state.final_result(),
            Some(CommandProcessFinalResult::Failed { .. })
        ),
        "reconnect did not fail the interrupted process"
    );
    wait_until_ready(&mut connection_state).await?;

    let reconnected = manager
        .open_workspace_host("validation", root.to_string())
        .await?;
    anyhow::ensure!(
        host.identity() != reconnected.identity(),
        "reconnect reused a retired LSP workspace identity"
    );
    anyhow::ensure!(
        !host.files.is_same_binding(&reconnected.files),
        "reconnect kept the retired logical file binding"
    );
    println!(
        "LSP binding generation: PASS (retired binding reused: {})",
        host.files.is_same_binding(&reconnected.files)
    );
    let reconnected_files = Arc::new(reconnected.files);
    let cleanup_check = run_remote(
        &reconnected.git,
        vec![
            "sh".to_string(),
            "-c".to_string(),
            "if kill -0 \"$(cat tree.pid)\" 2>/dev/null; then echo alive; else echo dead; fi"
                .to_string(),
        ],
    )
    .await?;
    anyhow::ensure!(
        cleanup_check.stdout.trim() == "dead",
        "reconnect left the descendant process alive"
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

    Ok(())
}

/// 本次独占子目录的固定前缀：清理时据此拒绝删除任何非本次创建的目标。
const EXCLUSIVE_PREFIX: &str = "anywork-acceptance-";

/// 池进入数据阶段的观测窗口。
const POOL_ENTRY_DEADLINE: Duration = Duration::from_secs(180);
/// 观测窗口内真实的 OS ssh 进程采样间隔（由有 owner 的 interval 驱动）。
const POOL_SAMPLE_INTERVAL: Duration = Duration::from_millis(200);

/// 生成只含 ASCII 字母数字与 `-` 的独占目录名。
fn exclusive_child_name() -> String {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos())
        .unwrap_or_default();
    format!("{EXCLUSIVE_PREFIX}{}-{nanos}", std::process::id())
}

/// 在父目录下原子创建本次独占子目录。
///
/// `mkdir` 不带 `-p`：目标已存在时由远端直接失败，绝不会并入或覆盖父目录中的既有数据。
/// `mkdir` 成功即取得 ownership，后续验证失败只报告而不撤销这一事实；`root` 是调用方在
/// 执行 mkdir 之前就已确定的候选完整路径，任何失败上下文都必须带它。
async fn create_exclusive_child(
    parent: &RemoteWorkspaceHost,
    name: &str,
    root: &str,
) -> anyhow::Result<()> {
    anyhow::ensure!(
        name.starts_with(EXCLUSIVE_PREFIX) && !name.contains('/') && !name.contains(".."),
        "exclusive workspace name must be a single path segment: {name} (candidate {root})"
    );
    let created = run_remote(&parent.git, vec!["mkdir".to_string(), name.to_string()])
        .await
        .with_context(|| format!("create exclusive workspace candidate at {root}"))?;
    anyhow::ensure!(
        created.status == 0,
        "mkdir failed for candidate {root}: {}",
        created.stderr
    );
    let verified = async {
        let stat = parent
            .files
            .stat_optional(name.to_string(), None)
            .await?
            .ok_or_else(|| anyhow::anyhow!("created workspace is not visible"))?;
        anyhow::ensure!(stat.is_dir, "created workspace is not a directory");
        anyhow::Ok(())
    }
    .await;
    verified.with_context(|| {
        format!(
            "exclusive workspace was created at {root} and ownership is kept; verification failed"
        )
    })
}

/// 合并主错误与清理错误；候选路径始终保留在上下文里，绝不因为清理而丢失。
fn combine_with_candidate(
    primary: anyhow::Error,
    cleanup: anyhow::Result<()>,
    root: &str,
) -> anyhow::Error {
    let primary = primary.context(format!(
        "exclusive workspace candidate may exist at {root}; it was kept, not removed"
    ));
    match cleanup {
        Ok(()) => primary,
        Err(error) => primary.context(format!(
            "disconnecting after the failed creation also failed: {error:#}"
        )),
    }
}

/// 只删除本次独占子目录；任何非本次命名的目标都拒绝处理。
async fn dispose_child(
    parent_files: &pl_tool::remote::RemoteWorkspaceFileBackend,
    name: &str,
) -> anyhow::Result<()> {
    anyhow::ensure!(
        name.starts_with(EXCLUSIVE_PREFIX) && !name.contains('/') && !name.contains(".."),
        "refusing to delete a directory this run does not own: {name}"
    );
    match parent_files.stat_optional(name.to_string(), None).await? {
        Some(stat) if stat.is_dir => parent_files
            .remove_path(name.to_string(), None, true)
            .await
            .map_err(anyhow::Error::new),
        Some(_) => anyhow::bail!("owned workspace path {name} is not a directory"),
        None => Ok(()),
    }
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

    // 只清掉本场景自己的 fixture：存在才删除，真实失败必须传播而不是被 `.ok()` 吞掉。
    for path in [".anywork/worktrees/.gitignore", ".anywork/worktrees"] {
        if files.stat_optional(path.to_string(), None).await?.is_some() {
            files
                .remove_path(path.to_string(), None, true)
                .await
                .map_err(anyhow::Error::new)?;
        }
    }
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

    async fn create_directory(&self, path: String, cwd: Option<String>) -> pl_protocol::Result<()> {
        self.inner.create_directory(path, cwd).await
    }
}

async fn validate_git(
    backend: &pl_tool::remote::RemoteExecutionBackend,
    files: &pl_tool::remote::RemoteWorkspaceFileBackend,
) -> anyhow::Result<()> {
    anyhow::ensure!(
        run_remote(
            backend,
            vec!["git".to_string(), "init".to_string(), "-q".to_string()]
        )
        .await?
        .status
            == 0,
        "git init failed in the remote workspace"
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
    anyhow::ensure!(
        catalog.find("remote-validation").is_some(),
        "remote skill catalog is missing the fixture skill"
    );
    let loaded = catalog
        .load(
            "remote-validation",
            SkillLoadInvocation::Model,
            CancellationToken::new(),
        )
        .await?;
    anyhow::ensure!(
        loaded.content.contains("# Remote validation"),
        "loaded skill content mismatch"
    );
    anyhow::ensure!(
        catalog
            .read_resource(
                "remote-validation",
                "references/info.md",
                SkillLoadInvocation::Model,
                CancellationToken::new(),
            )
            .await?
            == "remote reference",
        "skill resource content mismatch"
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
    anyhow::ensure!(
        files
            .read_bytes(WorkspaceFileReadBytesRequest {
                path: "pixel.png".to_string(),
                cwd: None,
                max_bytes: 1024,
            })
            .await?
            == png,
        "image bytes round-trip mismatch"
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
    anyhow::ensure!(result.success, "LSP query failed");
    anyhow::ensure!(
        result.result.contains("remote_symbol"),
        "LSP query lost the remote symbol"
    );
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

const GIB: u64 = 1024 * 1024 * 1024;

/// 本次验收独占的远端目录名：进程身份加纳秒时间，由原子 `mkdir` 决定 ownership。
fn unique_remote_dir(prefix: &str) -> anyhow::Result<String> {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .context("system clock is before the Unix epoch")?
        .as_nanos();
    Ok(format!(
        "anywork-acceptance-{prefix}-{}-{nanos}",
        std::process::id()
    ))
}

/// 用生产命令接口原子创建本次独占目录：`mkdir` 不带 `-p`，退出成功才取得 ownership。
///
/// 目录名由本示例生成，只含 ASCII 字母数字和 `-`，因此作为单个命令参数不需要额外引用；
/// 不靠先 `stat` 消除 TOCTOU，也不在“可能已存在”的目录上做递归删除。
async fn create_owned_directory(
    execution: &pl_tool::remote::RemoteExecutionBackend,
    owned_root: &str,
    directory: &str,
) -> anyhow::Result<()> {
    anyhow::ensure!(
        directory
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || character == '-'),
        "acceptance directory must use only ASCII alphanumerics and '-': {directory}"
    );
    // 候选完整路径在 mkdir 之前就已确定：命令失败（结果未知）也保留候选上下文，
    // 不能因为拿不到结果就当作“肯定没创建”。
    let candidate = format!("{owned_root}/{directory}");
    let output = run_remote(execution, vec!["mkdir".to_string(), directory.to_string()])
        .await
        .with_context(|| {
            format!(
                "remote mkdir result unknown for owned directory '{candidate}'; the candidate may exist and is kept"
            )
        })?;
    anyhow::ensure!(
        output.status == 0,
        "remote mkdir did not create the exclusive directory '{candidate}': {}",
        output.stderr
    );
    Ok(())
}

/// 只删除本次通过原子 `mkdir` 取得 ownership 的目录。
async fn cleanup_owned_directory(
    files: &pl_tool::remote::RemoteWorkspaceFileBackend,
    owned_root: &str,
    directory: &str,
) -> anyhow::Result<()> {
    let owned = format!("{owned_root}/{directory}");
    // 每一路失败都带已知的 owned 路径，调用方才能在报告里指出保留现场的位置。
    files
        .remove_path(directory.to_string(), None, true)
        .await
        .map_err(|error| {
            anyhow::Error::new(error).context(format!(
                "removing owned directory '{owned}' failed; the fixture is kept"
            ))
        })?;
    let remaining = files
        .stat_optional(directory.to_string(), None)
        .await
        .map_err(|error| {
            anyhow::Error::new(error).context(format!(
                "verifying removal of owned directory '{owned}' failed; the fixture may remain"
            ))
        })?;
    anyhow::ensure!(
        remaining.is_none(),
        "owned acceptance directory was not removed: {owned}"
    );
    Ok(())
}

/// 真实 SSH 上的流式上传/下载：公开 backend 入口、长度与内容摘要一致。
///
/// 数据由固定内存的生成器与哈希 sink 产生（`PatternReader` 64 KiB 块、`copy_file_to` 内部
/// 8 KiB 缓冲），不构造整文件缓冲；本入口不测量进程峰值 RSS，固定缓冲之外的内存峰值仍需
/// 由 root 用外部工具采样。
/// 完整验收强制 >= 1 GiB；`PURE_REMOTE_ACCEPTANCE_SMOKE=1` 用较小数据自查并明确不主张完整验收。
/// 成功或操作已返回失败时，远端责任已收束，才删除本次原子创建的独占目录；超时会保留 fixture
/// 并报告路径，避免在在途上传未确认时递归删除。
async fn validate_streaming_transfer(
    files: &pl_tool::remote::RemoteWorkspaceFileBackend,
    owned_root: &str,
    execution: &pl_tool::remote::RemoteExecutionBackend,
    smoke: bool,
    deadline: Duration,
) -> anyhow::Result<()> {
    let bytes = match env_u64("PURE_SSH_TEST_TRANSFER_BYTES")? {
        Some(value) => value,
        None if smoke => 1024 * 1024,
        None => GIB,
    };
    anyhow::ensure!(bytes >= 1024, "transfer size must be at least 1024 bytes");
    if !smoke {
        anyhow::ensure!(
            bytes >= GIB,
            "full acceptance requires PURE_SSH_TEST_TRANSFER_BYTES >= 1 GiB (or use PURE_REMOTE_ACCEPTANCE_SMOKE=1)"
        );
    }
    let directory = unique_remote_dir("transfer")?;
    create_owned_directory(execution, owned_root, &directory)
        .await
        .context("creating the streaming transfer fixture")?;
    let path = format!("{directory}/payload.bin");
    let transfer = async {
        let mut source = PatternReader::new(bytes);
        let written = files
            .copy_file_from(&path, &mut source, bytes, RemoteWriteMode::Create)
            .await?;
        let upload_digest = source.finish();
        anyhow::ensure!(
            written == bytes,
            "streaming upload confirmed {written} of {bytes} bytes"
        );
        let stat = files
            .stat_optional(path.clone(), None)
            .await?
            .ok_or_else(|| anyhow::anyhow!("streamed upload did not create the remote file"))?;
        anyhow::ensure!(
            stat.is_file && stat.len == Some(bytes),
            "remote file length does not match the upload: {stat:?}"
        );
        let mut sink = HashingWriter::new();
        let copied = files.copy_file_to(&path, &mut sink).await?;
        let hashed = sink.bytes();
        let download_digest = sink.finish();
        anyhow::ensure!(
            copied == bytes && hashed == bytes,
            "streaming download returned {copied} of {bytes} bytes (hashed {hashed})"
        );
        anyhow::ensure!(
            download_digest == upload_digest,
            "streaming round-trip digest mismatch: upload={upload_digest} download={download_digest}"
        );
        println!(
            "streaming transfer: bytes={bytes} digest={download_digest} buffers=chunked-64KiB; peak-rss=not-measured-here"
        );
        anyhow::Ok(())
    };
    let outcome = match tokio::time::timeout(deadline, transfer).await {
        Ok(result) => result,
        Err(_) => {
            return Err(anyhow::anyhow!(
                "streaming transfer did not settle within {deadline:?}; owned fixture retained at '{directory}'"
            ));
        }
    };
    // 只有完整成功链（上传确认 + 长度/摘要一致 + 下载确认）才证明远端责任已收束。
    // 任何 Err 都可能是传输/reader 中途失败，不能据此推断终结记录已收到，保留 fixture 并报告。
    match outcome {
        Ok(()) => cleanup_owned_directory(files, owned_root, &directory).await,
        Err(error) => Err(error.context(format!(
            "owned fixture retained at '{directory}' because the transfer did not complete its success chain"
        ))),
    }
}

/// 物理连接扩容：保持超过 511 条真实在途操作，观察真实 ssh 进程数增长，再回落。
///
/// 每次上传声明 1 字节，并由 [`UploadGate`] 在 helper 返回 Ready、reader 首次被 poll 时计数；
/// 只有全部操作都进入数据阶段才检查 OS 事实，然后统一放行、完成上传、删除本次原子创建的
/// 独占目录并等待连接回落。逻辑操作数、子流数与真实 OS 进程数分别记录。
///
/// 清理边界：只有全部本地任务返回（远端 operation 已收束）才删除目录；进入或收束超时会先
/// `abort_all` 并 drain，随后保留 fixture 并报告路径，不把本地 abort 当作远端已清理的证据。
async fn validate_elastic_pool(
    files: &pl_tool::remote::RemoteWorkspaceFileBackend,
    owned_root: &str,
    execution: &pl_tool::remote::RemoteExecutionBackend,
    smoke: bool,
) -> anyhow::Result<()> {
    let streams = match env_u64("PURE_SSH_TEST_POOL_STREAMS")? {
        Some(value) => usize::try_from(value).context("PURE_SSH_TEST_POOL_STREAMS is too large")?,
        None if smoke => 40,
        None => 600,
    };
    anyhow::ensure!(
        streams > 32,
        "concurrent uploads must exceed the old 32-operation limit"
    );
    if !smoke {
        anyhow::ensure!(
            streams > 511,
            "full acceptance requires PURE_SSH_TEST_POOL_STREAMS > 511 (or use PURE_REMOTE_ACCEPTANCE_SMOKE=1)"
        );
    }
    let baseline = ssh_process_count()
        .context("pool acceptance requires Linux /proc ssh process measurement")?;
    let directory = unique_remote_dir("pool")?;
    create_owned_directory(execution, owned_root, &directory)
        .await
        .context("creating the elastic pool fixture")?;
    let files = Arc::new(files.clone());
    let (gate, mut entered) = UploadGate::new(streams);
    let mut tasks = tokio::task::JoinSet::new();
    for index in 0..streams {
        let files = files.clone();
        let gate = gate.clone();
        let path = format!("{directory}/{index}.bin");
        tasks.spawn(async move {
            let mut reader = gate.reader(1);
            files
                .copy_file_from(&path, &mut reader, 1, RemoteWriteMode::Create)
                .await
        });
    }

    // entry 观测：同时观察 gate 信号与真实 task 终态。
    // - 释放前任何 upload 完成（即便 Ok）或失败都立即成为诊断，不再空等 180s 后丢错误；
    // - 峰值用有 owner 的 interval 在窗口内持续采样，记录真实最大值，而不是结束后单点取值。
    let entered_count = Arc::new(AtomicUsize::new(0));
    let peak_seen: Arc<Mutex<Option<usize>>> = Arc::new(Mutex::new(None));
    // 观测 future 只借用 tasks/entered/failures：超时丢弃它之后，
    // 已收集的首因仍留在 failures 里，tasks 也仍可用于 drain。
    let mut entry_failures = FailureLog::default();
    let observation = async {
        {
            let mut sampler = tokio::time::interval(POOL_SAMPLE_INTERVAL);
            sampler.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
            loop {
                tokio::select! {
                    signal = entered.recv() => {
                        anyhow::ensure!(
                            signal.is_some(),
                            "upload gate closed after {} of {streams} entries",
                            entered_count.load(Ordering::SeqCst)
                        );
                        let seen = entered_count.fetch_add(1, Ordering::SeqCst) + 1;
                        if seen == streams {
                            return anyhow::Ok(());
                        }
                    }
                    joined = tasks.join_next(), if !tasks.is_empty() => {
                        match joined {
                            Some(Ok(Ok(bytes))) => entry_failures.push(format!(
                                "an upload completed before release (confirmed {bytes} byte(s))"
                            )),
                            Some(Ok(Err(error))) => {
                                entry_failures.push(format!("upload failed during entry: {error}"));
                            }
                            Some(Err(error)) => {
                                entry_failures.push(format!("upload join failed during entry: {error}"));
                            }
                            None => {}
                        }
                        if !entry_failures.is_empty() {
                            anyhow::bail!(
                                "entry phase failed after {} of {streams} entries: {}",
                                entered_count.load(Ordering::SeqCst),
                                entry_failures.summary()
                            );
                        }
                    }
                    _ = sampler.tick() => {
                        merge_peak(&peak_seen, ssh_process_count());
                    }
                }
            }
        }
    };
    let entered_outcome = match tokio::time::timeout(POOL_ENTRY_DEADLINE, observation).await {
        Ok(result) => result,
        Err(_) => {
            entry_failures.push(format!("entry deadline {POOL_ENTRY_DEADLINE:?} elapsed"));
            Err(anyhow::anyhow!(
                "not every one of {streams} uploads entered its data phase within {POOL_ENTRY_DEADLINE:?}; entered={} observed_peak={:?}; failures={}",
                entered_count.load(Ordering::SeqCst),
                peak_seen
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .to_owned(),
                entry_failures.summary()
            ))
        }
    };
    // 所有 entry 都到齐时 gate 仍关闭（600 个租约都在手里）：此刻立即做最后一次受控采样，
    // 再放行。不能先 release 再取“最后快照”，否则 1 字节上传完成后连接收缩会抹掉峰。
    if entered_outcome.is_ok() {
        merge_peak(&peak_seen, ssh_process_count());
    }
    gate.release();
    let peak = {
        let observed = peak_seen
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .to_owned();
        match (observed, ssh_process_count()) {
            (Some(observed), Some(current)) => Some(observed.max(current)),
            (observed, current) => observed.or(current),
        }
    };

    // 成功/失败/超时都先停止并 join 全部本地任务。
    // 只有“每个 task 都返回 Ok(1 字节确认)”才证明远端 operation 全部收束；任何 Err、取消或
    // 计量不符都说明远端结果未知，不能清理 fixture。超时先 abort_all 并 drain，但本地 join
    // 不是远端完成的证据。
    let (settle_outcome, settled) = if entered_outcome.is_err() {
        tasks.abort_all();
        let mut drained = FailureLog::default();
        while let Some(result) = tasks.join_next().await {
            match result {
                Ok(Ok(bytes)) => drained.push(format!(
                    "upload completed after the entry phase failed (confirmed {bytes} byte(s))"
                )),
                Ok(Err(error)) => drained.push(format!("upload failed: {error}")),
                Err(error) if error.is_cancelled() => {}
                Err(error) => drained.push(format!("upload join failed: {error}")),
            }
        }
        let mut message = "uploads were cancelled after the entry phase failed".to_string();
        if !drained.is_empty() {
            message.push_str(&format!("; observed while draining: {}", drained.summary()));
        }
        (Err(anyhow::anyhow!(message)), false)
    } else {
        // 累计状态放在 future 之外：超时丢弃 future 时，已收集的真实失败仍然保留。
        let mut settle_failures = FailureLog::default();
        let mut settle_completed = 0usize;
        let settle = async {
            while let Some(result) = tasks.join_next().await {
                match result {
                    Ok(Ok(1)) => settle_completed += 1,
                    Ok(Ok(other)) => {
                        settle_failures.push(format!("upload confirmed {other} of 1 byte"));
                    }
                    Ok(Err(error)) => settle_failures.push(format!("upload failed: {error:#}")),
                    Err(error) if error.is_cancelled() => {
                        settle_failures.push("upload task was cancelled");
                    }
                    Err(error) => settle_failures.push(format!("upload task failed: {error}")),
                }
            }
        };
        let settle_deadline = tokio::time::timeout(Duration::from_secs(300), settle).await;
        if settle_deadline.is_err() {
            // deadline 本身就是一条失败；abort 后 drain 非取消的真实 Result，同样并入诊断。
            settle_failures.push("uploads did not settle within 300s after release");
            tasks.abort_all();
            while let Some(result) = tasks.join_next().await {
                match result {
                    Ok(Ok(bytes)) => settle_failures.push(format!(
                        "upload completed after the settle deadline (confirmed {bytes} byte(s))"
                    )),
                    Ok(Err(error)) => settle_failures.push(format!("upload failed: {error:#}")),
                    Err(error) if error.is_cancelled() => {}
                    Err(error) => settle_failures.push(format!("upload task failed: {error}")),
                }
            }
        }
        if settle_completed != streams {
            settle_failures.push(format!("completed {settle_completed} of {streams} uploads"));
        }
        if settle_failures.is_empty() {
            (anyhow::Ok(()), true)
        } else {
            (
                Err(anyhow::anyhow!(
                    "uploads did not settle cleanly ({} issue(s)): {}",
                    settle_failures.total(),
                    settle_failures.summary()
                )),
                false,
            )
        }
    };

    // 先把所有“扩容/在途/回落/责任收束”事实收集完，再决定是否清理：
    // 绝不能先删 fixture 再发现失败，否则诊断现场就没了。
    let mut failures = FailureLog::default();
    if let Err(error) = &entered_outcome {
        failures.push(format!("entry: {error:#}"));
    }
    if let Err(error) = &settle_outcome {
        failures.push(format!("settle: {error:#}"));
    }
    match peak {
        Some(peak) => {
            if !smoke && peak <= baseline {
                failures.push(format!(
                    "pool did not open another physical ssh connection: baseline={baseline} peak={peak}"
                ));
            }
            // 这里只印本示例自己测到的 OS 事实。helper 广告的 FD 预算数值由生产在握手完成
            // 时以 `pl_tool::remote::client` 的 debug 事件给出，用
            // `PURE_SSH_TEST_LOG=pl_tool::remote=debug` 查看（见 `init_tracing` 的说明）；
            // 本示例不复制常量，也不新增 getter。
            println!(
                "elastic pool: logical_operations={streams} ssh_processes={baseline}->{peak} smoke={smoke}"
            );
        }
        None => failures.push("lost OS ssh process measurement"),
    }
    if let Err(error) = wait_for_ssh_ceiling(baseline, Duration::from_secs(120)).await {
        failures.push(format!("shrink: {error:#}"));
    }
    if !settled {
        failures.push(
            "remote operation responsibility was not proven (not every upload confirmed)"
                .to_string(),
        );
    }
    let owned = format!("{owned_root}/{directory}");
    if failures.is_empty() {
        // 只有全部成功条件成立（进入/收束、真实扩容、回落到 baseline、远端责任已收束）才清理。
        cleanup_owned_directory(files.as_ref(), owned_root, &directory).await?;
        Ok(())
    } else {
        anyhow::bail!(
            "elastic pool acceptance failed; owned fixture kept at '{owned}': {}",
            failures.summary()
        )
    }
}

/// scope 内有界失败累计器：最多保留 8 条、每条最多 1024 字符，其余只计数。
///
/// entry / settle / abort-drain 都即时通过它收集，因此超时丢弃 future 也不会丢掉已见首因；
/// 汇总格式固定带 `(+N more)`，deadline 类失败显式写清超时事实。
#[derive(Default)]
struct FailureLog {
    kept: Vec<String>,
    omitted: usize,
}

/// 超长条目截断标记；它的字符数也计入单条上限。
const TRUNCATION_MARKER: &str = "…[truncated]";

impl FailureLog {
    const LIMIT: usize = 8;
    const ENTRY_LIMIT: usize = 1024;

    fn push(&mut self, message: impl Into<String>) {
        if self.kept.len() >= Self::LIMIT {
            self.omitted += 1;
            return;
        }
        let mut text = message.into();
        if text.chars().count() > Self::ENTRY_LIMIT {
            // 标记本身也算预算：截断后的总字符数必须 <= ENTRY_LIMIT。
            let budget = Self::ENTRY_LIMIT - TRUNCATION_MARKER.chars().count();
            let mut truncated: String = text.chars().take(budget).collect();
            truncated.push_str(TRUNCATION_MARKER);
            text = truncated;
        }
        debug_assert!(text.chars().count() <= Self::ENTRY_LIMIT);
        self.kept.push(text);
    }

    fn is_empty(&self) -> bool {
        self.kept.is_empty() && self.omitted == 0
    }

    fn total(&self) -> usize {
        self.kept.len() + self.omitted
    }

    fn summary(&self) -> String {
        let mut text = self.kept.join("; ");
        if self.omitted > 0 {
            text.push_str(&format!("; (+{} more)", self.omitted));
        }
        text
    }
}

/// 把一次真实采样并入观察到的峰值；采样缺失不改变已有结果。
fn merge_peak(peak: &Mutex<Option<usize>>, sample: Option<usize>) {
    let Some(current) = sample else {
        return;
    };
    let mut peak = peak.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    *peak = Some(peak.map_or(current, |seen| seen.max(current)));
}

/// 读取可选的无符号整型环境变量：非法值必须失败，不能静默回退默认值。
fn env_u64(name: &str) -> anyhow::Result<Option<u64>> {
    match std::env::var(name) {
        Ok(value) => {
            Ok(Some(value.parse::<u64>().with_context(|| {
                format!("{name} must be a non-negative integer")
            })?))
        }
        Err(std::env::VarError::NotPresent) => Ok(None),
        Err(error) => Err(anyhow::anyhow!("{name}: {error}")),
    }
}

/// 显式 smoke 选择：小数据自查，结束时不得主张完整验收。
fn smoke_mode() -> bool {
    std::env::var("PURE_REMOTE_ACCEPTANCE_SMOKE").as_deref() == Ok("1")
}

/// 当前进程子树中真实 `ssh` 子进程数量；无法在该宿主测量时返回 `None`。
fn ssh_process_count() -> Option<usize> {
    #[cfg(target_os = "linux")]
    {
        ssh_descendant_processes().ok()
    }
    #[cfg(not(target_os = "linux"))]
    {
        None
    }
}

#[cfg(target_os = "linux")]
fn ssh_descendant_processes() -> anyhow::Result<usize> {
    use std::collections::HashSet;

    let table = process_table()?;
    let mut descendants: HashSet<u32> = HashSet::new();
    descendants.insert(std::process::id());
    loop {
        let before = descendants.len();
        for (pid, parent, _) in &table {
            if descendants.contains(parent) {
                descendants.insert(*pid);
            }
        }
        if descendants.len() == before {
            break;
        }
    }
    Ok(table
        .iter()
        .filter(|(pid, _, command)| descendants.contains(pid) && command == "ssh")
        .count())
}

#[cfg(target_os = "linux")]
fn process_table() -> anyhow::Result<Vec<(u32, u32, String)>> {
    let mut table = Vec::new();
    for entry in std::fs::read_dir("/proc")? {
        let entry = entry?;
        let name = entry.file_name();
        let Some(name) = name.to_str() else {
            continue;
        };
        let Ok(pid) = name.parse::<u32>() else {
            continue;
        };
        let Ok(stat) = std::fs::read_to_string(entry.path().join("stat")) else {
            continue;
        };
        let Some(open) = stat.find('(') else {
            continue;
        };
        let Some(close) = stat.rfind(')') else {
            continue;
        };
        let command = stat[open + 1..close].to_string();
        let mut fields = stat[close + 1..].split_whitespace();
        let Some(_state) = fields.next() else {
            continue;
        };
        let Some(parent) = fields.next().and_then(|value| value.parse::<u32>().ok()) else {
            continue;
        };
        table.push((pid, parent, command));
    }
    Ok(table)
}

async fn wait_for_ssh_ceiling(baseline: usize, deadline: Duration) -> anyhow::Result<()> {
    let deadline = tokio::time::Instant::now() + deadline;
    loop {
        let count = ssh_process_count()
            .ok_or_else(|| anyhow::anyhow!("lost OS process measurement during pool shrink"))?;
        if count <= baseline {
            return Ok(());
        }
        anyhow::ensure!(
            tokio::time::Instant::now() < deadline,
            "expanded ssh connections did not retire: {count} > {baseline}"
        );
        tokio::time::sleep(Duration::from_millis(200)).await;
    }
}
