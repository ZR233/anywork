//! 真实 helper（Linux 本地 stdio）的传输层观察；不进入自动测试门禁。
//!
//! 运行：`cargo run -p pl-tool --example helper_transport_validation`
//!
//! 需要 PATH 上有 `pl-remote-helper`（`cargo install --path code/pl-remote-helper --locked`），
//! 或用 `PURE_HELPER_BIN=<path>` 指定。临时工作区位于 `TMPDIR`，可用
//! `PURE_REMOTE_ACCEPTANCE_DIR=<dir>` 指定父目录，不写入源码树或用户 home。
//!
//! 完整验收（默认）：大文件往返 >= 1 GiB，且必须完成 >4 GiB 偏移的 range 读取。
//! 显式 smoke：`PURE_REMOTE_ACCEPTANCE_SMOKE=1` 用小数据快速自查，结束时明确打印未主张完整验收。
//! `PURE_HELPER_TEST_LARGE_BYTES` 可覆盖大文件字节数（非法值直接失败，不静默回退）。
//!
//! 覆盖：
//! 1. 旧协议版本 hello 被明确拒绝并结束连接（用生产传输扮演客户端，不手写帧）。
//! 2. 目录流条目总量远超旧 64 KiB 头预算、逐条完整、可提前停止，应用错误后心跳/stat/exec 正常。
//! 3. FIFO 等特殊文件在 read/write/create/append/copy 上都被拒绝且不阻塞，也不产生副作用。
//! 4. 50 轮 workspace open/close 后 helper 的 fd 与线程回落（physical 生命周期）；RSS 只记录
//!    前后值作为趋势，峰值由 root 外部采样，本入口不作峰值承诺。
//! 5. 上传短读、取消与计量不一致都不发布半文件；正常 overwrite 才原子发布。
//! 6. 固定内存的大文件上传/下载哈希一致；完整验收强制 >4 GiB 偏移 range。
//! 7. 正常 shutdown、EOF 与租约过期都不遗留远端物理进程，且退出状态按场景裁决。
//!
//! 每个场景拥有独立 helper，所有路径（成功、失败、超时、取消）都执行同一收尾：
//! 退出裁决 → stderr 排空 → 后代回收。
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use anyhow::{Context, ensure};
use pl_protocol::remote::{
    REMOTE_PROTOCOL_VERSION, RemoteCapture, RemoteCopyRequest, RemoteErrorCode, RemoteFileStat,
    RemoteMessage, RemotePathRequest, RemoteReadRequest, RemoteRequest, RemoteResponse,
    RemoteSpawnRequest, RemoteWorkspaceOpened, RemoteWriteMode, RemoteWriteRequest,
};
use pl_remote_helper::remote_transport::{
    ConnectionOwner, RecordReader, RecordWriter, RemoteRecord, RemoteStream, Role, TransportError,
};
use pl_tool::command::CommandExit;
use pl_tool::remote::{RemoteClient, RemoteClientError};
use tokio::io::{AsyncRead, AsyncReadExt};

#[path = "support/helper.rs"]
mod helper_process;
#[path = "support/outcome.rs"]
mod outcome;
#[path = "support/transfer.rs"]
mod transfer;

use helper_process::{
    ExitExpectation, Helper, finish_scenario, process_alive, request_graceful_shutdown,
};
use outcome::{TaskOwner, combine, run_with_deadline};
use transfer::{HashingWriter, PatternReader};

const GIB: u64 = 1024 * 1024 * 1024;
const SMOKE_LARGE_BYTES: u64 = 8 * 1024 * 1024;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    if !cfg!(target_os = "linux") {
        anyhow::bail!(
            "helper transport acceptance observes /proc resources and FIFO files; run it on Linux"
        );
    }
    let smoke = smoke_mode();
    // 先校验完整 stage 列表：非法选择必须在启动任何 helper 之前就失败。
    let selected = selected_stages()?;
    // 默认跑完整场景；`PURE_HELPER_TEST_STAGE=a,b` 只用于手工验收单点复跑，
    // 这种选择性运行不主张 full acceptance。
    let plan: Vec<(&'static str, StageFuture)> = vec![
        ("protocol_version", Box::pin(protocol_version_rejected())),
        ("directory_stream", Box::pin(directory_stream())),
        ("special_files", Box::pin(special_files_refused())),
        ("oversized_record", Box::pin(oversized_record_is_local())),
        ("workspace_leases", Box::pin(workspace_lease_cycles())),
        ("upload_atomicity", Box::pin(upload_atomicity())),
        (
            "output_terminate",
            Box::pin(output_backpressure_terminate()),
        ),
        ("large_transfer", Box::pin(large_transfer(smoke))),
        ("connection_endings", Box::pin(connection_endings())),
    ];
    let mut stages = 0;
    for (name, future) in plan {
        let wanted = selected
            .as_ref()
            .is_none_or(|selected| selected.iter().any(|wanted| wanted == name));
        if !wanted {
            continue;
        }
        stage(name, future, &mut stages).await?;
    }
    if let Some(selected) = &selected {
        println!(
            "stages={stages} selected stages only ({selected:?}); full acceptance not claimed"
        );
    } else if smoke {
        println!(
            "stages={stages} smoke observations completed; full acceptance (>=1 GiB + >4 GiB range) not claimed"
        );
    } else {
        println!("stages={stages} helper transport acceptance completed (full)");
    }
    Ok(())
}

async fn stage<F>(name: &str, future: F, stages: &mut usize) -> anyhow::Result<()>
where
    F: std::future::Future<Output = anyhow::Result<()>>,
{
    let started = Instant::now();
    // 每个场景自己给主体设 deadline，并在返回前执行 helper 收尾；这里不再丢弃 future。
    future
        .await
        .with_context(|| format!("stage {name} failed"))?;
    *stages += 1;
    println!("stage={name} elapsed_ms={}", started.elapsed().as_millis());
    Ok(())
}

/// 手工验收用的 stage 计划条目：一个名字加一个 boxed future。
type StageFuture = std::pin::Pin<Box<dyn std::future::Future<Output = anyhow::Result<()>>>>;

/// 全部可选择的 stage 名称；显式选择只能来自这个集合。
const ACCEPTANCE_STAGES: [&str; 9] = [
    "protocol_version",
    "directory_stream",
    "special_files",
    "oversized_record",
    "workspace_leases",
    "upload_atomicity",
    "output_terminate",
    "large_transfer",
    "connection_endings",
];

/// 解析手工验收用的显式 stage 选择。
///
/// 未设置环境变量才是默认“跑完整场景”。显式设置必须是逗号分隔的已知名称：
/// 空值、纯空白、空逗号段、未知名称、重复名称都返回错误，绝不退化成 full 或 stages=0 成功。
fn selected_stages() -> anyhow::Result<Option<Vec<String>>> {
    let Some(value) = std::env::var_os("PURE_HELPER_TEST_STAGE") else {
        return Ok(None);
    };
    let raw = value.to_string_lossy().into_owned();
    let mut selected: Vec<String> = Vec::new();
    for part in raw.split(',') {
        let name = part.trim();
        ensure!(
            !name.is_empty(),
            "PURE_HELPER_TEST_STAGE has an empty stage name in {raw:?}; known stages: {ACCEPTANCE_STAGES:?}"
        );
        ensure!(
            ACCEPTANCE_STAGES.contains(&name),
            "PURE_HELPER_TEST_STAGE has an unknown stage {name:?}; known stages: {ACCEPTANCE_STAGES:?}"
        );
        ensure!(
            !selected.iter().any(|seen| seen == name),
            "PURE_HELPER_TEST_STAGE repeats stage {name:?}; duplicates are rejected to keep the selection unambiguous"
        );
        selected.push(name.to_string());
    }
    ensure!(
        !selected.is_empty(),
        "PURE_HELPER_TEST_STAGE must select at least one stage, got {raw:?}"
    );
    Ok(Some(selected))
}

fn smoke_mode() -> bool {
    std::env::var("PURE_REMOTE_ACCEPTANCE_SMOKE").as_deref() == Ok("1")
}

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

/// 旧协议版本在握手阶段被明确拒绝，且连接随后结束。
async fn protocol_version_rejected() -> anyhow::Result<()> {
    let fixture: Option<tempfile::TempDir> = None;
    let mut helper = Helper::start().await?;
    let mut tasks = TaskOwner::new();
    // 交接本身也在收尾路径内：take_pipes 的 Err 仍会走 finish_scenario，
    // helper 一定被显式 wait + stderr join，不会因为提前 `?` 逃逸丢掉清理责任。
    let handoff = helper.take_pipes();
    let outcome = match handoff {
        Err(error) => Err(error.context("protocol rejection requires both helper pipes")),
        Ok((stdout, stdin)) => {
            let (owner, handle, incoming) = ConnectionOwner::start(stdout, stdin, Role::Client);
            let body = run_with_deadline(Duration::from_secs(60), async move {
                drop(incoming);
                let stream = handle.open_control().await?;
                let mut control = StreamPeer::new(stream);
                control
                    .send(
                        RemoteMessage::Request(RemoteRequest::Hello {
                            protocol_version: REMOTE_PROTOCOL_VERSION - 1,
                        }),
                        &[],
                    )
                    .await?;
                let record = control.read().await?;
                let RemoteMessage::Response(RemoteResponse::Error(error)) = &record.message else {
                    anyhow::bail!(
                        "old protocol version was not rejected: {:?}",
                        record.message
                    );
                };
                ensure!(
                    error.code == RemoteErrorCode::ProtocolMismatch,
                    "unexpected rejection code: {:?}",
                    error.code
                );
                // helper 收束后控制流以 EOF/Closed 结束；其他读错误是真实失败。
                match control.reader.read().await {
                    Ok(None) | Err(TransportError::Closed | TransportError::Cancelled) => {}
                    Err(error) => {
                        anyhow::bail!("control stream read failed after rejection: {error}");
                    }
                    Ok(Some(record)) => anyhow::bail!(
                        "helper kept the connection after a protocol mismatch: {:?}",
                        record.message
                    ),
                }
                drop(control);
                drop(handle);
                println!("protocol version: rejected_with={:?}", error.code);
                anyhow::Ok(())
            })
            .await;
            let settled = settle_owner(&owner).await;
            combine(body, settled)
        }
    };
    // helper 对旧协议版本的握手明确以非零状态退出：这里必须期望失败，
    // 且不放过任何其他 cleanup 错误（combine 已把 body 与 owner 收束合并）。
    finish_scenario(
        outcome,
        &mut tasks,
        helper,
        fixture,
        ExitExpectation::Failure,
        Duration::from_secs(20),
        ensure_protocol_mismatch_diagnosis,
    )
    .await
}
async fn directory_stream() -> anyhow::Result<()> {
    let fixture = Some(acceptance_root("helper-directory")?);
    let mut helper = Helper::start().await?;
    let mut tasks = TaskOwner::new();
    let outcome = run_with_deadline(Duration::from_secs(180), async {
        let fixture = fixture
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("scenario requires an owned fixture"))?;
        let client = helper.connect().await?;
        let names: Vec<String> = (0..700)
            .map(|index| format!("item-{index:04}-{}", "n".repeat(100)))
            .collect();
        for name in &names {
            std::fs::write(fixture.path().join(name), b"x")?;
        }
        let name_bytes: usize = names.iter().map(String::len).sum();
        ensure!(
            name_bytes > 64 * 1024,
            "directory fixture must exceed the old 64 KiB budget: {name_bytes}"
        );
        let workspace = open_workspace(&client, fixture.path()).await?;
        let workspace_id = workspace.workspace_id;

        let mut stream = client
            .directory(RemoteRequest::ListDirectory(RemotePathRequest {
                workspace_id: workspace_id.clone(),
                path: ".".into(),
            }))
            .await?;
        ensure!(!stream.metadata().path.is_empty());
        let mut seen = Vec::new();
        while let Some(entry) = stream.next_entry().await? {
            ensure!(!entry.is_directory, "unexpected directory entry: {entry:?}");
            seen.push(entry.name);
        }
        seen.sort();
        let mut expected = names.clone();
        expected.sort();
        ensure!(
            seen == expected,
            "directory stream entries differ: {} of {}",
            seen.len(),
            expected.len()
        );

        // 只取三条就丢弃迭代器，随后心跳与新操作照常。
        let mut early = client
            .directory(RemoteRequest::ListDirectory(RemotePathRequest {
                workspace_id: workspace_id.clone(),
                path: ".".into(),
            }))
            .await?;
        for index in 0..3 {
            early
                .next_entry()
                .await?
                .with_context(|| format!("early-stop listing ended before entry {index}"))?;
        }
        drop(early);
        client.heartbeat().await?;

        // 应用错误只结束该操作。
        let missing = client
            .directory(RemoteRequest::ListDirectory(RemotePathRequest {
                workspace_id: workspace_id.clone(),
                path: "missing-directory".into(),
            }))
            .await;
        let missing_error = match missing {
            Ok(mut stream) => loop {
                match stream.next_entry().await {
                    Ok(Some(_)) => continue,
                    Ok(None) => {
                        anyhow::bail!("missing directory produced a complete listing")
                    }
                    Err(error) => break error,
                }
            },
            Err(error) => error,
        };
        ensure!(
            matches!(
                missing_error,
                RemoteClientError::Remote {
                    code: RemoteErrorCode::PathNotFound | RemoteErrorCode::Io,
                    ..
                }
            ),
            "unexpected missing-directory error: {missing_error}"
        );
        client.heartbeat().await?;
        let stat = stat_path(&client, &workspace_id, ".").await?;
        ensure!(stat.is_directory);
        let (exit, _, _) = exec(&client, &workspace_id, "dir-exec", "printf ok").await?;
        ensure!(
            exit.exit_code == Some(0),
            "exec failed after directory error: {exit:?}"
        );

        println!(
            "directory: entries={} name_bytes={name_bytes} early_stop=3 error=isolated health=ok",
            seen.len()
        );
        request_graceful_shutdown(&client).await?;
        anyhow::Ok(())
    })
    .await;
    finish_scenario(
        outcome,
        &mut tasks,
        helper,
        fixture,
        ExitExpectation::Success,
        Duration::from_secs(30),
        |_, _| Ok(()),
    )
    .await
}

/// FIFO 等特殊文件在所有文件原语上都被拒绝，且不阻塞、不产生副作用。
async fn special_files_refused() -> anyhow::Result<()> {
    let fixture = Some(acceptance_root("helper-special")?);
    let mut helper = Helper::start().await?;
    let mut tasks = TaskOwner::new();
    let outcome = run_with_deadline(Duration::from_secs(180), async {
        let fixture = fixture
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("scenario requires an owned fixture"))?;
        let client = helper.connect().await?;
        std::fs::write(fixture.path().join("regular.txt"), b"synthetic")?;
        let fifo = fixture.path().join("special.pipe");
        let status = std::process::Command::new("mkfifo")
            .arg(&fifo)
            .status()
            .context("mkfifo must be available for the special-file observation")?;
        ensure!(status.success(), "mkfifo failed: {status:?}");
        let workspace = open_workspace(&client, fixture.path()).await?;
        let workspace_id = workspace.workspace_id;

        // read_file 打开特殊文件必须失败而不是挂起。
        let read = tokio::time::timeout(
            Duration::from_secs(10),
            client.read_file(RemoteReadRequest {
                workspace_id: workspace_id.clone(),
                path: "special.pipe".into(),
                offset: 0,
                max_bytes: Some(64),
            }),
        )
        .await
        .context("read_file on a FIFO did not settle")?;
        ensure!(read.is_err(), "read_file accepted a FIFO");
        client.heartbeat().await?;

        // append/create 到 FIFO 必须失败，且不得启动任何命令。
        for mode in [RemoteWriteMode::Append, RemoteWriteMode::Create] {
            let mut source: &[u8] = b"x";
            let write = tokio::time::timeout(
                Duration::from_secs(10),
                client.write_file(
                    RemoteWriteRequest {
                        target: RemotePathRequest {
                            workspace_id: workspace_id.clone(),
                            path: "special.pipe".into(),
                        },
                        mode,
                        total_len: 1,
                    },
                    &mut source,
                ),
            )
            .await
            .context("write_file on a FIFO did not settle")?;
            ensure!(write.is_err(), "write_file {mode:?} accepted a FIFO");
        }
        // capture 目标为 FIFO：必须在启动命令前被拒绝，且不产生任何副作用。
        let capture = client
            .spawn_process(RemoteSpawnRequest {
                process_id: "fifo-capture".into(),
                workspace_id: workspace_id.clone(),
                command: "printf started > must-not-start".into(),
                cwd: ".".into(),
                environment: Default::default(),
                capture: RemoteCapture::File {
                    path: "special.pipe".into(),
                    limit_bytes: 64 * 1024,
                },
            })
            .await;
        ensure!(capture.is_err(), "capture onto a FIFO was accepted");
        ensure!(
            !fixture.path().join("must-not-start").exists(),
            "refused special-file preparation started a command"
        );

        // copy 的源或目标为特殊文件都必须失败。
        for (source, target) in [
            ("special.pipe", "copy-source.txt"),
            ("regular.txt", "special.pipe"),
        ] {
            let copy = tokio::time::timeout(
                Duration::from_secs(10),
                client.request(RemoteRequest::CopyPath(RemoteCopyRequest {
                    workspace_id: workspace_id.clone(),
                    source: source.into(),
                    target: target.into(),
                    recursive: false,
                })),
            )
            .await
            .context("copyPath on a FIFO did not settle")?;
            ensure!(
                copy.is_err(),
                "copyPath accepted a FIFO: {source} -> {target}"
            );
        }
        ensure!(
            !fixture.path().join("copy-source.txt").exists(),
            "copy from a FIFO published a partial target"
        );
        ensure!(
            std::fs::read(fixture.path().join("regular.txt"))? == b"synthetic",
            "copy onto a FIFO modified the regular source"
        );
        client.heartbeat().await?;
        println!("special files: read=refused write=refused copy=refused side_effects=none");
        request_graceful_shutdown(&client).await?;
        anyhow::Ok(())
    })
    .await;
    finish_scenario(
        outcome,
        &mut tasks,
        helper,
        fixture,
        ExitExpectation::Success,
        Duration::from_secs(30),
        |_, _| Ok(()),
    )
    .await
}

/// 超限 record 在本地编码阶段被拒绝，同一连接随后仍可心跳、stat 与 exec。
async fn oversized_record_is_local() -> anyhow::Result<()> {
    let fixture = Some(acceptance_root("helper-oversized")?);
    let mut helper = Helper::start().await?;
    let mut tasks = TaskOwner::new();
    let outcome = run_with_deadline(Duration::from_secs(120), async {
        let fixture = fixture
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("scenario requires an owned fixture"))?;
        let client = helper.connect().await?;
        let workspace = open_workspace(&client, fixture.path()).await?;
        let workspace_id = workspace.workspace_id;
        let oversized = "p".repeat(70 * 1024);
        let error = client
            .request(RemoteRequest::Stat(RemotePathRequest {
                workspace_id: workspace_id.clone(),
                path: oversized,
            }))
            .await
            .expect_err("oversized request record was accepted");
        let text = error.to_string().to_ascii_lowercase();
        ensure!(
            text.contains("record") || text.contains("65536"),
            "oversized request did not fail as a local record limit: {error}"
        );
        // 本地编码失败不能污染共享 writer：控制面与普通请求必须继续工作。
        client.heartbeat().await?;
        let stat = stat_path(&client, &workspace_id, ".").await?;
        ensure!(stat.is_directory);
        let (exit, stdout, _) =
            exec(&client, &workspace_id, "after-oversized", "printf ok").await?;
        ensure!(
            exit.exit_code == Some(0) && stdout.as_slice() == b"ok",
            "exec failed after an oversized record"
        );
        println!("oversized record: locally rejected, connection healthy");
        request_graceful_shutdown(&client).await?;
        anyhow::Ok(())
    })
    .await;
    finish_scenario(
        outcome,
        &mut tasks,
        helper,
        fixture,
        ExitExpectation::Success,
        Duration::from_secs(30),
        |_, _| Ok(()),
    )
    .await
}

/// 50 轮 workspace open/close 后 fd 与线程回落到基线附近（physical 生命周期）。
/// RSS 只记录前后值作为趋势；峰值测量不属于本入口的断言。
async fn workspace_lease_cycles() -> anyhow::Result<()> {
    let fixture = Some(acceptance_root("helper-cycles")?);
    let mut helper = Helper::start().await?;
    let mut tasks = TaskOwner::new();
    let outcome = run_with_deadline(Duration::from_secs(180), async {
        let fixture = fixture
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("scenario requires an owned fixture"))?;
        let client = helper.connect().await?;
        for index in 0..50 {
            std::fs::create_dir(fixture.path().join(format!("lease-{index}")))?;
        }
        // 先打开一个 workspace 作为基线，避免把首次分配算作泄漏。
        let warm = open_workspace(&client, fixture.path()).await?;
        client
            .request(RemoteRequest::CloseWorkspace {
                workspace_id: warm.workspace_id,
            })
            .await?;
        let baseline = helper_resources(helper.id())?;

        for index in 0..50 {
            let directory = fixture.path().join(format!("lease-{index}"));
            let opened = open_workspace(&client, &directory).await?;
            let closed = client
                .request(RemoteRequest::CloseWorkspace {
                    workspace_id: opened.workspace_id.clone(),
                })
                .await?;
            ensure!(
                matches!(closed, RemoteResponse::Ack),
                "closeWorkspace was not acknowledged"
            );
            let stat = client
                .request(RemoteRequest::Stat(RemotePathRequest {
                    workspace_id: opened.workspace_id,
                    path: ".".into(),
                }))
                .await;
            ensure!(
                matches!(
                    stat,
                    Err(RemoteClientError::Remote {
                        code: RemoteErrorCode::WorkspaceNotFound,
                        ..
                    })
                ),
                "closed workspace handle stayed usable: {stat:?}"
            );
        }
        let final_resources = helper_resources(helper.id())?;
        ensure!(
            final_resources.files <= baseline.files + 2,
            "workspace cycles leaked helper file descriptors: {baseline:?} -> {final_resources:?}"
        );
        ensure!(
            final_resources.threads <= baseline.threads + 4,
            "workspace cycles leaked helper threads: {baseline:?} -> {final_resources:?}"
        );
        println!("workspace cycles: 50 baseline={baseline:?} final={final_resources:?}");
        request_graceful_shutdown(&client).await?;
        anyhow::Ok(())
    })
    .await;
    finish_scenario(
        outcome,
        &mut tasks,
        helper,
        fixture,
        ExitExpectation::Success,
        Duration::from_secs(30),
        |_, _| Ok(()),
    )
    .await
}

#[derive(Debug)]
struct HelperResources {
    files: usize,
    threads: usize,
    rss_kib: u64,
}

fn helper_resources(pid: u32) -> anyhow::Result<HelperResources> {
    let process = PathBuf::from(format!("/proc/{pid}"));
    let files = std::fs::read_dir(process.join("fd"))?.count();
    let threads = std::fs::read_dir(process.join("task"))?.count();
    let status = std::fs::read_to_string(process.join("status"))?;
    let rss_kib = status
        .lines()
        .find_map(|line| {
            line.strip_prefix("VmRSS:")
                .and_then(|value| value.split_whitespace().next())
                .and_then(|value| value.parse::<u64>().ok())
        })
        .context("helper status has no VmRSS")?;
    Ok(HelperResources {
        files,
        threads,
        rss_kib,
    })
}

/// 短读、取消与计量不一致都不发布半文件；正常 overwrite 才原子发布。
async fn upload_atomicity() -> anyhow::Result<()> {
    let fixture = Some(acceptance_root("helper-upload")?);
    let mut helper = Helper::start().await?;
    let mut tasks = TaskOwner::new();
    let outcome = run_with_deadline(Duration::from_secs(300), async {
        let fixture = fixture
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("scenario requires an owned fixture"))?;
        let client = helper.connect().await?;
        std::fs::write(fixture.path().join("existing.txt"), b"original")?;
        let workspace = open_workspace(&client, fixture.path()).await?;
        let workspace_id = workspace.workspace_id;

        // 1. 短读 create 失败，目标不得出现。
        let mut short: &[u8] = &[b's'; 100];
        let result = client
            .write_file(
                write_request(&workspace_id, "short.txt", RemoteWriteMode::Create, 4096),
                &mut short,
            )
            .await;
        ensure!(
            result.is_err(),
            "short upload published a partial create: {result:?}"
        );
        ensure!(
            !fixture.path().join("short.txt").exists(),
            "short upload created the target"
        );

        // 2. 短读 overwrite 失败，原内容保持不变。
        let mut short: &[u8] = &[b's'; 100];
        let result = client
            .write_file(
                write_request(
                    &workspace_id,
                    "existing.txt",
                    RemoteWriteMode::Overwrite,
                    4096,
                ),
                &mut short,
            )
            .await;
        ensure!(
            result.is_err(),
            "short upload published a partial overwrite: {result:?}"
        );
        ensure!(
            std::fs::read(fixture.path().join("existing.txt"))? == b"original",
            "short overwrite changed the existing file"
        );

        // 3. 上传中取消：进入数据阶段后取消，create 不出现目标，overwrite 不改变内容。
        for (path, mode) in [
            ("cancelled.txt", RemoteWriteMode::Create),
            ("existing.txt", RemoteWriteMode::Overwrite),
        ] {
            // 声明长度 128 KiB 大于实际提供的 64 KiB：客户端必须已经写出部分 Data 并继续
            // 索取更多字节；源停在未就绪上是“确实处于数据阶段”的确定性通知，而不是时间窗口。
            let declared = 128 * 1024;
            let (stalled_tx, stalled_rx) = tokio::sync::oneshot::channel();
            let mut source = StalledReader::new(64 * 1024, stalled_tx);
            let mut upload = Box::pin(client.write_file(
                write_request(&workspace_id, path, mode, declared),
                &mut source,
            ));
            let entered = tokio::time::timeout(Duration::from_secs(10), async {
                tokio::select! {
                    stalled = stalled_rx => stalled.context("stalled upload source was dropped"),
                    finished = &mut upload => {
                        anyhow::bail!("upload finished before the data phase stalled: {finished:?}")
                    }
                }
            })
            .await
            .context("upload never reached the data phase")?;
            entered?;
            // 数据阶段已确认：取消调用方，由 helper 收束暂存责任。
            drop(upload);
            drop(source);
            // 取消没有远端确认：这里只做健康期的有界观察（连接仍可用、目标未被发布），
            // 终结证明由 helper 真实退出后的 fixture 后置检查给出。
            let deadline = Instant::now() + Duration::from_secs(10);
            for check in 0..4 {
                ensure!(
                    Instant::now() < deadline,
                    "cancelled upload target did not settle: {path}"
                );
                let settled = if path == "existing.txt" {
                    std::fs::read(fixture.path().join(path))? == b"original"
                } else {
                    !fixture.path().join(path).exists()
                };
                ensure!(
                    settled,
                    "cancelled upload published or replaced {path} at check {check}"
                );
                client.heartbeat().await?;
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        }

        // 4. 正常 overwrite 原子发布，且工作区没有残留暂存文件。
        let mut source: &[u8] = b"published";
        let written = client
            .write_file(
                write_request(
                    &workspace_id,
                    "existing.txt",
                    RemoteWriteMode::Overwrite,
                    9,
                ),
                &mut source,
            )
            .await?;
        ensure!(written == 9, "published byte count mismatch: {written}");
        ensure!(
            std::fs::read(fixture.path().join("existing.txt"))? == b"published",
            "overwrite did not publish atomically"
        );
        let mut listing = client
            .directory(RemoteRequest::ListDirectory(RemotePathRequest {
                workspace_id: workspace_id.clone(),
                path: ".".into(),
            }))
            .await?;
        let mut names = Vec::new();
        while let Some(entry) = listing.next_entry().await? {
            names.push(entry.name);
        }
        names.sort();
        ensure!(
            names == vec!["existing.txt".to_string()],
            "workspace retains unexpected files after uploads: {names:?}"
        );
        println!(
            "upload atomicity: short=refused overwrite=refused cancel=unpublished publish=atomic leftovers=none"
        );
        request_graceful_shutdown(&client).await?;
        anyhow::Ok(())
    })
    .await;
    finish_scenario(
        outcome,
        &mut tasks,
        helper,
        fixture,
        ExitExpectation::Success,
        Duration::from_secs(30),
        |_, fixture| {
            let Some(fixture) = fixture else {
                anyhow::bail!("upload atomicity requires an owned fixture");
            };
            // helper 已真实退出、后代已回收：此刻才核对拥有目录的终态，
            // 否则 TempDir 自动删除会掩盖取消上传留下的半成品或暂存目录。
            let mut entries: Vec<String> = std::fs::read_dir(fixture)?
                .map(|entry| entry.map(|entry| entry.file_name().to_string_lossy().into_owned()))
                .collect::<std::io::Result<Vec<_>>>()?;
            entries.sort();
            ensure!(
                entries == vec!["existing.txt".to_string()],
                "workspace retained entries after helper exit: {entries:?}"
            );
            ensure!(
                !fixture.join("cancelled.txt").exists(),
                "cancelled upload published its target"
            );
            ensure!(
                std::fs::read(fixture.join("existing.txt"))? == b"published",
                "published target content mismatch after helper exit"
            );
            Ok(())
        },
    )
    .await
}

/// 输出消费者停读时的 Terminate：控制面必须被确认，命令与后代都真实回收。
///
/// 背压证据由本次 TempDir 内的 python3 stdlib 生产脚本自己给出（不进入生产 wire）：
/// stdout 设为 nonblocking，按小块累计写入；遇 EAGAIN 用 `select.poll(POLLOUT)` 观察**同一个**
/// 待写阶段 200ms，恢复可写就继续填充；只有“已写 > 旧 64 KiB 且持续无 POLLOUT 达窗口”才
/// 原子写 `blocked.json`（含 producer/child pid 与计量）并保持未消费的阻塞状态。
/// 64 MiB 总填充上界仍未阻塞即明确失败，不放大窗口。关键阶段全程保持 stdin 句柄存活。
const PRODUCER_SCRIPT: &str = r#"
import json, os, select, subprocess, sys

CHUNK = 8192
LIMIT = 64 * 1024 * 1024
WINDOW_MS = 200

child = subprocess.Popen(["sleep", "300"])
with open("child.pid", "w", encoding="utf-8") as handle:
    handle.write(str(child.pid))

fd = sys.stdout.fileno()
os.set_blocking(fd, False)
poll = select.poll()
poll.register(fd, select.POLLOUT)

written = 0
chunk = b"x" * CHUNK
while written < LIMIT:
    try:
        written += os.write(fd, chunk)
        continue
    except BlockingIOError:
        events = poll.poll(WINDOW_MS)
        if events:
            continue
        if written <= 64 * 1024:
            payload = {
                "reason": "backpressure observed before the 64 KiB budget",
                "producer_pid": os.getpid(),
                "child_pid": child.pid,
                "written": written,
            }
            with open("failed.json.tmp", "w", encoding="utf-8") as handle:
                json.dump(payload, handle)
            os.replace("failed.json.tmp", "failed.json")
            sys.exit(2)
        payload = {"producer_pid": os.getpid(), "child_pid": child.pid, "written": written}
        with open("blocked.json.tmp", "w", encoding="utf-8") as handle:
            json.dump(payload, handle)
        os.replace("blocked.json.tmp", "blocked.json")
        # 保持“等待可写”的阻塞状态，不消费、不退出。
        while True:
            poll.poll(None)

payload = {
    "producer_pid": os.getpid(),
    "child_pid": child.pid,
    "written": written,
    "blocked": False,
}
with open("failed.json.tmp", "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
os.replace("failed.json.tmp", "failed.json")
sys.exit(2)
"#;

async fn output_backpressure_terminate() -> anyhow::Result<()> {
    let fixture = Some(acceptance_root("helper-terminate")?);
    let mut helper = Helper::start().await?;
    let mut tasks = TaskOwner::new();
    let outcome = run_with_deadline(Duration::from_secs(180), async {
        let fixture_path = fixture
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("terminate scenario requires an owned fixture"))?
            .path()
            .to_path_buf();
        // 一次性脚本只落在本次独占 TempDir，不进入项目目录或生产代码。
        std::fs::write(fixture_path.join("producer.py"), PRODUCER_SCRIPT)?;
        let client = helper.connect().await?;
        let workspace = open_workspace(&client, &fixture_path).await?;
        let workspace_id = workspace.workspace_id;
        let mut command = client
            .spawn_process(RemoteSpawnRequest {
                process_id: "stopped-reader".into(),
                workspace_id: workspace_id.clone(),
                command: "python3 producer.py".into(),
                cwd: ".".into(),
                environment: Default::default(),
                capture: RemoteCapture::None,
            })
            .await?;
        // 关键阶段保持 stdin 存活：不制造独立的 stdinClosed 交错。
        let stdin = command.take_stdin().context("process must expose stdin")?;
        // 取出 stdout 但先不消费：helper 的输出写端会被真实背压挡住。
        let mut stdout = command.take_stdout().context("process must expose stdout")?;

        let blocked_path = fixture_path.join("blocked.json");
        let failed_path = fixture_path.join("failed.json");
        let deadline = Instant::now() + Duration::from_secs(120);
        while !blocked_path.exists() {
            ensure!(
                !failed_path.exists(),
                "producer filled its upper bound without sustained backpressure: {}",
                std::fs::read_to_string(&failed_path).unwrap_or_default()
            );
            ensure!(
                Instant::now() < deadline,
                "producer never reported sustained backpressure"
            );
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        let blocked: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(
            &blocked_path,
        )?)?;
        let producer_pid = blocked["producer_pid"]
            .as_u64()
            .context("producer pid is missing")? as u32;
        let child_pid = blocked["child_pid"]
            .as_u64()
            .context("child pid is missing")? as u32;
        let written = blocked["written"]
            .as_u64()
            .context("written byte count is missing")?;
        ensure!(
            written > 64 * 1024,
            "producer reported backpressure after only {written} bytes"
        );
        ensure!(process_alive(producer_pid), "producer must still be running");
        ensure!(process_alive(child_pid), "descendant must still be running");
        helper.register_descendant(child_pid);

        // 直接 typed Terminate（控制事务必须收到 Ack）；此刻 stdout 仍未消费、stdin 仍存活。
        let response = client
            .request(RemoteRequest::Terminate {
                process_id: "stopped-reader".into(),
            })
            .await?;
        ensure!(
            matches!(response, RemoteResponse::Ack),
            "terminate was not acknowledged: {response:?}"
        );
        // 控制面仍健康。
        client.heartbeat().await?;
        let stat = stat_path(&client, &workspace_id, ".").await?;
        ensure!(stat.is_directory, "workspace stat failed after terminate");

        // 现在才开始有界 buffer 排空 stdout，并等命令终态。
        let mut drained = 0u64;
        let mut buffer = vec![0u8; 64 * 1024];
        loop {
            let count = stdout.read(&mut buffer).await?;
            if count == 0 {
                break;
            }
            drained += count as u64;
        }
        let exit = command.wait().await.map_err(anyhow::Error::msg)?;
        ensure!(
            exit.exit_code != Some(0),
            "terminated command reported a clean exit: {exit:?}"
        );
        println!(
            "terminate: producer={producer_pid} descendant={child_pid} written={written} drained={drained} exit={exit:?}"
        );
        drop(stdin);
        request_graceful_shutdown(&client).await?;
        anyhow::Ok(())
    })
    .await;
    finish_scenario(
        outcome,
        &mut tasks,
        helper,
        fixture,
        ExitExpectation::Success,
        Duration::from_secs(45),
        |stderr, _| {
            ensure!(
                !stderr.contains("pl-remote-helper failed"),
                "terminate scenario reported a helper failure: {stderr}"
            );
            Ok(())
        },
    )
    .await
}

/// 固定内存的大文件上传/下载哈希一致；完整验收强制 >4 GiB 偏移 range。
async fn large_transfer(smoke: bool) -> anyhow::Result<()> {
    let configured = env_u64("PURE_HELPER_TEST_LARGE_BYTES")?;
    let total = match configured {
        Some(value) => value,
        None if smoke => SMOKE_LARGE_BYTES,
        None => GIB,
    };
    ensure!(total >= 1024, "large transfer size must be at least 1024");
    if !smoke {
        ensure!(
            total >= GIB,
            "full acceptance requires PURE_HELPER_TEST_LARGE_BYTES >= 1 GiB (or use PURE_REMOTE_ACCEPTANCE_SMOKE=1)"
        );
    }
    let sparse_enabled =
        !smoke || std::env::var("PURE_HELPER_TEST_OVER_4GIB").as_deref() == Ok("1");

    let fixture = Some(acceptance_root("helper-large")?);
    let mut helper = Helper::start().await?;
    let mut tasks = TaskOwner::new();
    let body_deadline = if smoke {
        Duration::from_secs(600)
    } else {
        Duration::from_secs(7200)
    };
    let outcome = run_with_deadline(body_deadline, async {
        let client = helper.connect().await?;
        let fixture_path = fixture
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("large transfer requires an owned fixture"))?
            .path()
            .to_path_buf();
        let workspace = open_workspace(&client, &fixture_path).await?;
        let workspace_id = workspace.workspace_id;
        let baseline = helper_resources(helper.id())?;

        let (upload_tx, upload_rx) = tokio::sync::oneshot::channel();
        {
            let upload_client = client.clone();
            let upload_workspace = workspace_id.clone();
            tasks.spawn(async move {
                let mut pattern = PatternReader::new(total);
                let written = upload_client
                    .write_file(
                        write_request(
                            &upload_workspace,
                            "large.bin",
                            RemoteWriteMode::Create,
                            total,
                        ),
                        &mut pattern,
                    )
                    .await?;
                let _ = upload_tx.send((written, pattern.finish()));
                anyhow::Ok(())
            });
        }

        // 大文件进行中：心跳、stat 与小命令仍然完成。
        client.heartbeat().await?;
        let stat = stat_path(&client, &workspace_id, ".").await?;
        ensure!(stat.is_directory);
        let (exit, small_stdout, _) =
            exec(&client, &workspace_id, "during-upload", "printf during").await?;
        ensure!(
            exit.exit_code == Some(0) && small_stdout.as_slice() == b"during",
            "small command did not complete during upload"
        );

        let (written, upload_digest) = upload_rx
            .await
            .context("upload task exited before reporting its receipt")?;
        ensure!(written == total, "upload receipt mismatch: {written}");
        let uploaded_len = std::fs::metadata(fixture_path.join("large.bin"))?.len();
        ensure!(
            uploaded_len == total,
            "remote file length mismatch: {uploaded_len}"
        );

        let (download_tx, download_rx) = tokio::sync::oneshot::channel();
        {
            let download_client = client.clone();
            let download_workspace = workspace_id.clone();
            tasks.spawn(async move {
                let mut reader = download_client
                    .read_file(RemoteReadRequest {
                        workspace_id: download_workspace,
                        path: "large.bin".into(),
                        offset: 0,
                        max_bytes: None,
                    })
                    .await?;
                let total_len = reader.metadata().total_len;
                let mut sink = HashingWriter::new();
                let copied = tokio::io::copy(&mut reader, &mut sink).await?;
                let _ = download_tx.send((copied, total_len, sink.bytes(), sink.finish()));
                anyhow::Ok(())
            });
        }
        client.heartbeat().await?;
        let (copied, total_len, counted, download_digest) = download_rx
            .await
            .context("download task exited before reporting its receipt")?;
        ensure!(
            total_len == total && copied == total && counted == total,
            "download length mismatch: total={total_len} copied={copied} hashed={counted}"
        );
        ensure!(
            download_digest == upload_digest,
            "round-trip digest mismatch: upload={upload_digest} download={download_digest}"
        );

        let after = helper_resources(helper.id())?;
        println!(
            "large transfer: bytes={total} digest={download_digest} rss_kib_before_after={}->{} files={}->{} peak_rss=not-measured-here",
            baseline.rss_kib, after.rss_kib, baseline.files, after.files
        );

        if sparse_enabled {
            let sparse = fixture_path.join("sparse.bin");
            let file = std::fs::OpenOptions::new()
                .create(true)
                .truncate(true)
                .write(true)
                .open(&sparse)?;
            let size = 5 * GIB;
            file.set_len(size)?;
            drop(file);
            let offset = 4 * GIB + 12_345;
            let length = 64 * 1024;
            let mut reader = client
                .read_file(RemoteReadRequest {
                    workspace_id: workspace_id.clone(),
                    path: "sparse.bin".into(),
                    offset,
                    max_bytes: Some(length),
                })
                .await?;
            ensure!(reader.metadata().offset == offset, "range offset mismatch");
            ensure!(
                reader.metadata().total_len == size,
                "range total length mismatch"
            );
            ensure!(
                reader.metadata().transfer_len == length,
                "range transfer length mismatch"
            );
            let mut buffer = vec![0u8; 16 * 1024];
            let mut read = 0u64;
            loop {
                let count = reader.read(&mut buffer).await?;
                if count == 0 {
                    break;
                }
                ensure!(
                    buffer[..count].iter().all(|byte| *byte == 0),
                    "sparse range returned non-zero bytes"
                );
                read += count as u64;
            }
            ensure!(read == length, "sparse range read {read} of {length}");
            println!(
                "sparse range: size={size} offset={offset} transfer_len={length} read={read}"
            );
        } else {
            println!("sparse range: skipped (smoke mode)");
        }

        request_graceful_shutdown(&client).await?;
        anyhow::Ok(())
    })
    .await;
    finish_scenario(
        outcome,
        &mut tasks,
        helper,
        fixture,
        ExitExpectation::Success,
        Duration::from_secs(60),
        |_, _| Ok(()),
    )
    .await
}

/// 正常 shutdown、EOF 与租约过期都不遗留远端物理进程，退出状态与诊断按场景裁决。
///
/// 每个场景的 TempDir、Helper 与本地 task 集合都在 deadline body 之外创建并持有；body 只借用
/// 它们。body 成功、失败或超时后都先 cancel+join 本地 task，再裁决 helper 退出/排空 stderr/
/// 回收后代；只有全部成功才允许删除拥有目录，否则保留 fixture 并报告路径。
async fn connection_endings() -> anyhow::Result<()> {
    // 单向 shutdown：helper 必须正常退出。
    {
        let fixture = Some(acceptance_root("helper-end-shutdown")?);
        let mut helper = Helper::start().await?;
        let mut tasks = TaskOwner::new();
        let outcome = run_with_deadline(Duration::from_secs(120), async {
            let client = helper.connect().await?;
            let fixture_path = fixture
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("shutdown scenario requires an owned fixture"))?
                .path()
                .to_path_buf();
            let (_command, descendant) =
                start_process_tree(&mut helper, &client, &fixture_path).await?;
            ensure!(process_alive(descendant));
            client.request_shutdown().await?;
            println!("ending=shutdown requested with descendant={descendant}");
            anyhow::Ok(())
        })
        .await;
        finish_scenario(
            outcome,
            &mut tasks,
            helper,
            fixture,
            ExitExpectation::Success,
            Duration::from_secs(45),
            ensure_shutdown_diagnosis,
        )
        .await?;
    }

    // 未发送 shutdown 的 control EOF：必须是非零且可识别的连接失败。
    {
        let fixture = Some(acceptance_root("helper-end-eof")?);
        let mut helper = Helper::start().await?;
        let mut tasks = TaskOwner::new();
        let outcome = run_with_deadline(Duration::from_secs(120), async {
            let client = helper.connect().await?;
            let fixture_path = fixture
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("eof scenario requires an owned fixture"))?
                .path()
                .to_path_buf();
            let (_command, descendant) =
                start_process_tree(&mut helper, &client, &fixture_path).await?;
            ensure!(process_alive(descendant));
            client.close().await?;
            println!("ending=eof requested with descendant={descendant}");
            anyhow::Ok(())
        })
        .await;
        finish_scenario(
            outcome,
            &mut tasks,
            helper,
            fixture,
            ExitExpectation::Failure,
            Duration::from_secs(45),
            ensure_unexpected_eof_diagnosis,
        )
        .await?;
    }

    // 租约过期：保留打开的连接、不再发送任何流量；约 30s 后 helper 以失败退出。
    {
        let fixture = Some(acceptance_root("helper-end-lease")?);
        let mut helper = Helper::start().await?;
        let mut tasks = TaskOwner::new();
        let outcome = run_with_deadline(Duration::from_secs(90), async {
            let client = helper.connect().await?;
            let fixture_path = fixture
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("lease scenario requires an owned fixture"))?
                .path()
                .to_path_buf();
            let (_command, descendant) =
                start_process_tree(&mut helper, &client, &fixture_path).await?;
            ensure!(process_alive(descendant));
            let quiet_since = Instant::now();
            let status = helper
                .wait_exit(ExitExpectation::Failure, Duration::from_secs(60))
                .await?;
            let elapsed = quiet_since.elapsed();
            ensure!(
                (Duration::from_secs(25)..=Duration::from_secs(45)).contains(&elapsed),
                "lease expiry happened after {elapsed:?}, outside the 30s lease window"
            );
            drop(client);
            println!(
                "ending=lease helper_exit={status} elapsed_ms={} descendant={descendant}",
                elapsed.as_millis()
            );
            anyhow::Ok(())
        })
        .await;
        finish_scenario(
            outcome,
            &mut tasks,
            helper,
            fixture,
            ExitExpectation::Failure,
            Duration::from_secs(5),
            ensure_lease_diagnosis,
        )
        .await?;
    }
    Ok(())
}

/// 显式收束扮演对端的连接 owner：请求关闭并等待驱动任务真实结束。
///
/// 连接已因协议违约被 helper 收束，因此传输层终态错误是本场景的预期结果；
/// 但驱动任务异常结束（panic/abort）说明没有真正 join，必须报告。
async fn settle_owner(owner: &ConnectionOwner) -> anyhow::Result<()> {
    // 这里的连接本来就由 helper 收束：Ok（本端先关）与 Closed（对端已关）都是预期终态，
    // 其他错误（I/O、Multiplex、DriverTask）都是真实失败，不能为通过而宽泛忽略。
    let close = match owner.close().await {
        Ok(()) | Err(TransportError::Closed) => Ok(()),
        Err(error) => Err(anyhow::anyhow!("owner close failed: {error}")),
    };
    let waited = match owner.wait_closed().await {
        Ok(()) | Err(TransportError::Closed) => Ok(()),
        Err(error) => Err(anyhow::anyhow!("owner wait_closed failed: {error}")),
    };
    combine(close, waited)
}

/// 协议版本拒绝：helper 必须以非零状态退出，并给出可识别的协议不匹配诊断。
fn ensure_protocol_mismatch_diagnosis(stderr: &str, _fixture: Option<&Path>) -> anyhow::Result<()> {
    ensure!(
        stderr.contains("pl-remote-helper failed"),
        "protocol rejection did not report a helper failure: {stderr}"
    );
    ensure!(
        stderr.to_lowercase().contains("protocol")
            || stderr.to_lowercase().contains("version mismatch"),
        "protocol rejection diagnosis is not recognizable: {stderr}"
    );
    Ok(())
}

/// 正常 shutdown：helper 干净退出，不得留下失败诊断。
fn ensure_shutdown_diagnosis(stderr: &str, _fixture: Option<&Path>) -> anyhow::Result<()> {
    ensure!(
        !stderr.contains("pl-remote-helper failed"),
        "clean shutdown reported a helper failure: {stderr}"
    );
    Ok(())
}

/// 未发送 shutdown 的控制 EOF：必须以可识别的 UnexpectedEof 诊断失败退出。
fn ensure_unexpected_eof_diagnosis(stderr: &str, _fixture: Option<&Path>) -> anyhow::Result<()> {
    ensure!(
        stderr.contains("pl-remote-helper failed"),
        "unexpected control EOF did not report a helper failure: {stderr}"
    );
    ensure!(
        stderr.contains("the connection ended unexpectedly")
            || stderr.contains("before the control stream")
            // canonical helper 的无 Shutdown EOF 语义；只接受这一条明确诊断。
            || stderr.contains("the remote control stream ended without a shutdown request"),
        "unexpected control EOF diagnosis is not recognizable: {stderr}"
    );
    Ok(())
}

/// 租约过期：诊断必须指明 heartbeat 租约，而不是其他失败。
fn ensure_lease_diagnosis(stderr: &str, _fixture: Option<&Path>) -> anyhow::Result<()> {
    ensure!(
        stderr.contains("remote helper heartbeat lease expired"),
        "lease expiry diagnosis is not recognizable: {stderr}"
    );
    Ok(())
}

/// 启动一个带长命后代的命令，并把该后代登记到 helper 的收尾清单。
async fn start_process_tree(
    helper: &mut Helper,
    client: &RemoteClient,
    root: &Path,
) -> anyhow::Result<(pl_tool::command::ManagedCommand, u32)> {
    let workspace = open_workspace(client, root).await?;
    let workspace_id = workspace.workspace_id;
    let command = client
        .spawn_process(RemoteSpawnRequest {
            process_id: "tree".into(),
            workspace_id: workspace_id.clone(),
            command: "sleep 120 & echo $! > child.pid; wait".into(),
            cwd: ".".into(),
            environment: Default::default(),
            capture: RemoteCapture::None,
        })
        .await?;
    let pid_path = root.join("child.pid");
    let deadline = Instant::now() + Duration::from_secs(10);
    while !pid_path.exists() {
        ensure!(
            Instant::now() < deadline,
            "descendant pid was never written"
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let descendant: u32 = std::fs::read_to_string(&pid_path)?.trim().parse()?;
    helper.register_descendant(descendant);
    Ok((command, descendant))
}

async fn open_workspace(
    client: &RemoteClient,
    path: &Path,
) -> anyhow::Result<RemoteWorkspaceOpened> {
    let response = client
        .request(RemoteRequest::OpenWorkspace {
            path: path.to_string_lossy().to_string(),
        })
        .await?;
    match response {
        RemoteResponse::WorkspaceOpened(opened) => Ok(opened),
        other => anyhow::bail!("unexpected openWorkspace response: {other:?}"),
    }
}

async fn stat_path(
    client: &RemoteClient,
    workspace_id: &str,
    path: &str,
) -> anyhow::Result<RemoteFileStat> {
    let response = client
        .request(RemoteRequest::Stat(RemotePathRequest {
            workspace_id: workspace_id.into(),
            path: path.into(),
        }))
        .await?;
    match response {
        RemoteResponse::Stat(stat) => Ok(stat),
        other => anyhow::bail!("unexpected stat response: {other:?}"),
    }
}

/// 运行一条不写 capture 的命令，并同时排空 stdout/stderr。
async fn exec(
    client: &RemoteClient,
    workspace_id: &str,
    process_id: &str,
    command: &str,
) -> anyhow::Result<(CommandExit, Vec<u8>, Vec<u8>)> {
    let mut handle = client
        .spawn_process(RemoteSpawnRequest {
            process_id: process_id.into(),
            workspace_id: workspace_id.into(),
            command: command.into(),
            cwd: ".".into(),
            environment: Default::default(),
            capture: RemoteCapture::None,
        })
        .await?;
    drop(handle.take_stdin());
    let mut stdout = handle.take_stdout().context("process must expose stdout")?;
    let mut stderr = handle.take_stderr().context("process must expose stderr")?;
    let (stdout, stderr) = tokio::join!(
        async {
            let mut collected = Vec::new();
            stdout.read_to_end(&mut collected).await?;
            anyhow::Ok(collected)
        },
        async {
            let mut collected = Vec::new();
            stderr.read_to_end(&mut collected).await?;
            anyhow::Ok(collected)
        }
    );
    let exit = handle.wait().await.map_err(anyhow::Error::msg)?;
    Ok((exit, stdout?, stderr?))
}

fn write_request(
    workspace_id: &str,
    path: &str,
    mode: RemoteWriteMode,
    total_len: u64,
) -> RemoteWriteRequest {
    RemoteWriteRequest {
        target: RemotePathRequest {
            workspace_id: workspace_id.into(),
            path: path.into(),
        },
        mode,
        total_len,
    }
}

fn acceptance_root(prefix: &str) -> anyhow::Result<tempfile::TempDir> {
    // prefix 由 Builder 借用，因此字符串必须先成为具名绑定。
    let prefix = format!("{prefix}-");
    let mut builder = tempfile::Builder::new();
    let builder = builder.prefix(&prefix);
    match std::env::var_os("PURE_REMOTE_ACCEPTANCE_DIR") {
        Some(directory) => {
            let directory = PathBuf::from(directory);
            std::fs::create_dir_all(&directory).with_context(|| {
                format!(
                    "failed to create explicit acceptance directory {}",
                    directory.display()
                )
            })?;
            Ok(builder.tempdir_in(directory)?)
        }
        None => Ok(builder.tempdir()?),
    }
}

/// 只提供声明长度一部分后停在未就绪的上传源。
///
/// 声明长度必须大于实际提供量：这样客户端在数据阶段仍然需要更多字节，
/// 因而停在源上而不是“已送出全部字节、只等终结记录”。
/// 源在真正进入“提供完毕且未就绪”时通知观察者，作为数据阶段的确定性证据。
struct StalledReader {
    remaining: usize,
    stalled: Option<tokio::sync::oneshot::Sender<()>>,
}

impl StalledReader {
    fn new(provide: usize, stalled: tokio::sync::oneshot::Sender<()>) -> Self {
        Self {
            remaining: provide,
            stalled: Some(stalled),
        }
    }
}

impl AsyncRead for StalledReader {
    fn poll_read(
        mut self: std::pin::Pin<&mut Self>,
        _context: &mut std::task::Context<'_>,
        buffer: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        if self.remaining == 0 {
            // 已提供完全部字节但声明长度更大：保持未就绪，直到调用方取消上传。
            if let Some(stalled) = self.stalled.take() {
                let _ = stalled.send(());
            }
            return std::task::Poll::Pending;
        }
        let start = buffer.filled().len();
        let count = buffer.remaining().min(self.remaining).min(8 * 1024);
        {
            let target = buffer.initialize_unfilled_to(start + count);
            target.fill(b'c');
        }
        buffer.advance(count);
        self.remaining -= count;
        std::task::Poll::Ready(Ok(()))
    }
}

/// 受控客户端侧的单条流：用生产记录分帧读写。
struct StreamPeer {
    reader: RecordReader<tokio::io::ReadHalf<RemoteStream>>,
    writer: RecordWriter<tokio::io::WriteHalf<RemoteStream>>,
}

impl StreamPeer {
    fn new(stream: RemoteStream) -> Self {
        let (read, write) = tokio::io::split(stream);
        Self {
            reader: RecordReader::new(read),
            writer: RecordWriter::new(write),
        }
    }

    async fn read(&mut self) -> anyhow::Result<RemoteRecord> {
        self.reader
            .read()
            .await?
            .context("control stream ended without a record")
    }

    async fn send(&mut self, message: RemoteMessage, body: &[u8]) -> anyhow::Result<()> {
        self.writer.send(&message, body).await?;
        Ok(())
    }
}
