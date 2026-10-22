//! 受控 peer 驱动的单连接语义观察；不进入自动测试门禁。
//!
//! 运行：`cargo run -p pl-tool --example remote_resource_validation`
//!
//! peer 只负责外部时序：它用生产共用传输（Yamux + 记录分帧）实现服务端角色，
//! 不复制旧帧协议，也不自测自己的实现。被观察对象是 `pl_tool::remote::RemoteClient`。
//!
//! 覆盖：
//! 1. 目录流条目远超旧 64 KiB 头预算时逐条完整、可提前停止，且停止后连接仍健康。
//! 2. 目录错误、读偏移/终结/计量错误、上传错误都只结束对应操作，随后心跳、stat、exec 正常。
//! 3. 三个慢消费者（目录、下载、进程输出）都不读取时，其他操作与控制面继续进展。
//! 4. 单连接 511 条普通子流全部在途，第 512 个调用可取消地等待而不是失败，控制面不受阻。
//! 5. 进程：启动取消不越过启动裁决；stdin 拒绝后立即 exit 仍保留原始错误；
//!    未消费输出显式取消后仍完成回收。
//! 6. 上传流：连续 offset、UploadFinished 校验、错误响应与计量不一致都失败。
//! 7. hello 版本协商失败（helper 拒绝与 helper 版本不符）与单向 shutdown。
//!
//! 每个场景的连接、受控 peer 与本地任务都由 `Scene` 持有：deadline 只约束场景 body，
//! body 内的派生任务一律登记到 owner；超时或失败后仍按“取消并 join 本地任务 →
//! 关闭并等待连接 → join 控制任务”的顺序收尾，失败经 `Err` 报告而不是只打印结论。
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Context, ensure};
use pl_protocol::remote::{
    REMOTE_PROTOCOL_VERSION, RemoteCapability, RemoteCapture, RemoteDirectoryEntry,
    RemoteDirectoryMetadata, RemoteError, RemoteErrorCode, RemoteEvent, RemoteFileMetadata,
    RemoteFileStat, RemoteHello, RemoteMessage, RemoteOutputStream, RemotePathRequest,
    RemoteProcessExit, RemoteProcessOutput, RemoteReadRequest, RemoteRequest, RemoteResourceCosts,
    RemoteResourceLimits, RemoteResponse, RemoteShellDescriptor, RemoteShellDialect,
    RemoteSpawnRequest, RemoteWorkspaceOpened, RemoteWriteMode, RemoteWriteRequest,
};
use pl_remote_helper::remote_transport::{
    ConnectionHandle, ConnectionOwner, DATA_CHUNK_BYTES, IncomingStreams, OPERATION_STREAMS,
    RecordReader, RecordWriter, RemoteRecord, RemoteStream, Role, TransportError,
};
use pl_tool::command::CommandExit;
use pl_tool::remote::{RemoteClient, RemoteClientError};
use tokio::io::{AsyncReadExt, AsyncWriteExt, ReadHalf, WriteHalf};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

#[path = "support/outcome.rs"]
mod outcome;

use outcome::{TaskOwner, combine, run_with_deadline};

const CONTROL_REQUEST_BUFFER: usize = 64;
const SLOW_DOWNLOAD_LEN: u64 = 64 * 1024 * 1024;
const SLOW_FILL_LIMIT: u64 = 64 * 1024 * 1024;
/// 同一个未完成 send 持续 Pending 达到该窗口，才判定接收窗口确实耗尽。
const BACKPRESSURE_WINDOW: Duration = Duration::from_millis(200);
/// 放行后慢目录继续发出的入口总数（远大于接收窗口，足以核对完整消费）。
const SLOW_DIRECTORY_TOTAL: u64 = 8192;
/// 放行后慢进程继续发出的输出记录总数。
const SLOW_OUTPUT_TOTAL: u64 = 512;
const STAGE_TIMEOUT: Duration = Duration::from_secs(300);
const TRANSPORT_BUFFER: usize = 256 * 1024;
/// 受控 peer 声明的 helper build：必须与客户端编译版本一致，否则正向握手会被拒绝。
const CONTROLLED_HELPER: &str = env!("CARGO_PKG_VERSION");
const WORKSPACE: &str = "acceptance";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut stages = 0;
    stage("directory_large", directory_large(), &mut stages).await?;
    stage("directory_early_stop", directory_early_stop(), &mut stages).await?;
    stage("error_isolation", error_isolation(), &mut stages).await?;
    stage(
        "resource_budget_handshake",
        handshake_resource_budget_rejected(),
        &mut stages,
    )
    .await?;
    stage("fd_budget_admission", fd_budget_admission(), &mut stages).await?;
    stage(
        "workspace_budget_recovery",
        workspace_budget_recovery(),
        &mut stages,
    )
    .await?;
    stage("slow_consumers", slow_consumers(), &mut stages).await?;
    stage(
        "ordinary_stream_limit",
        ordinary_stream_limit(),
        &mut stages,
    )
    .await?;
    stage(
        "process_startup_cancel",
        process_startup_cancel(),
        &mut stages,
    )
    .await?;
    stage(
        "process_input_rejected",
        process_input_rejected(),
        &mut stages,
    )
    .await?;
    stage(
        "process_cancel_after_output",
        process_cancel_after_output(),
        &mut stages,
    )
    .await?;
    stage("read_protocol_errors", read_protocol_errors(), &mut stages).await?;
    stage(
        "upload_stream_semantics",
        upload_stream_semantics(),
        &mut stages,
    )
    .await?;
    stage(
        "handshake_and_shutdown",
        handshake_and_shutdown(),
        &mut stages,
    )
    .await?;
    println!("stages={stages} controlled-peer observations completed");
    Ok(())
}

/// 每个场景自己拥有连接与本地任务，deadline 只约束场景 body；这里只统计完成的阶段。
async fn stage<F>(name: &str, future: F, stages: &mut usize) -> anyhow::Result<()>
where
    F: std::future::Future<Output = anyhow::Result<()>>,
{
    future
        .await
        .with_context(|| format!("stage {name} failed"))?;
    *stages += 1;
    println!("stage={name} completed");
    Ok(())
}

/// 目录条目总量超过旧 64 KiB 元数据预算，逐条内容与数量完整核对。
async fn directory_large() -> anyhow::Result<()> {
    let mut scene = Scene::open().await?;
    let outcome = {
        let SceneParts {
            client,
            peer,
            tasks,
        } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            ensure!(client.hello().helper_version == CONTROLLED_HELPER);
            ensure!(client.hello().protocol_version == REMOTE_PROTOCOL_VERSION);

            let names = directory_names(600);
            let name_bytes: usize = names.iter().map(String::len).sum();
            ensure!(
                name_bytes > 64 * 1024,
                "directory fixture must exceed the old 64 KiB metadata budget: {name_bytes}"
            );

            let directory_client = client.clone();
            let opening = spawn_owned(tasks, async move {
                directory_client
                    .directory(RemoteRequest::ListDirectory(RemotePathRequest {
                        workspace_id: WORKSPACE.into(),
                        path: "large".into(),
                    }))
                    .await
            });
            let mut operation = peer.accept_operation().await?;
            expect_request(&mut operation, "listDirectory", |request| {
                matches!(request, RemoteRequest::ListDirectory(_))
            })
            .await?;
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::Directory(RemoteDirectoryMetadata {
                        path: "/remote/large".into(),
                        parent: Some("/remote".into()),
                    })),
                    &[],
                )
                .await?;
            let mut stream = opening.await??;
            ensure!(stream.metadata().path == "/remote/large");
            ensure!(stream.metadata().parent.as_deref() == Some("/remote"));
            // peer 与消费者并发推进：整份目录远大于单条记录，也大于一条流的接收窗口。
            let peer_names = names.clone();
            let sending = spawn_owned(tasks, async move {
                let mut operation = operation;
                for name in &peer_names {
                    operation
                        .send(
                            RemoteMessage::DirectoryEntry(RemoteDirectoryEntry {
                                name: name.clone(),
                                path: format!("/remote/large/{name}"),
                                is_directory: false,
                                is_symlink: false,
                            }),
                            &[],
                        )
                        .await?;
                }
                operation
                    .send(RemoteMessage::Response(RemoteResponse::Complete), &[])
                    .await?;
                anyhow::Ok(())
            });
            let mut seen = Vec::new();
            while let Some(entry) = stream.next_entry().await? {
                seen.push(entry);
            }
            sending.await??;
            ensure!(
                seen.len() == names.len(),
                "directory stream lost entries: {} of {}",
                seen.len(),
                names.len()
            );
            for (index, (entry, name)) in seen.iter().zip(&names).enumerate() {
                ensure!(entry.name == *name, "entry {index} renamed: {}", entry.name);
                ensure!(entry.path == format!("/remote/large/{name}"));
                ensure!(!entry.is_directory && !entry.is_symlink);
            }
            client.heartbeat().await?;
            peer.expect_heartbeat().await?;
            println!(
                "directory: entries={} name_bytes={name_bytes} complete=true heartbeat=true",
                seen.len()
            );
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await
}

/// 客户端只取前三条就丢弃迭代器；连接与其他操作不受影响。
async fn directory_early_stop() -> anyhow::Result<()> {
    let mut scene = Scene::open().await?;
    let outcome = {
        let SceneParts {
            client,
            peer,
            tasks,
        } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            let names = directory_names(2000);
            let directory_client = client.clone();
            let opening = spawn_owned(tasks, async move {
                directory_client
                    .directory(RemoteRequest::ListDirectory(RemotePathRequest {
                        workspace_id: WORKSPACE.into(),
                        path: "early".into(),
                    }))
                    .await
            });
            let mut operation = peer.accept_operation().await?;
            expect_request(&mut operation, "listDirectory", |request| {
                matches!(request, RemoteRequest::ListDirectory(_))
            })
            .await?;
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::Directory(RemoteDirectoryMetadata {
                        path: "/remote/early".into(),
                        parent: None,
                    })),
                    &[],
                )
                .await?;
            let mut stream = opening.await??;
            ensure!(stream.metadata().path == "/remote/early");
            let peer_names = names.clone();
            let sending = spawn_owned(tasks, async move {
                let mut operation = operation;
                let mut offered = 0usize;
                let mut write_closed = false;
                for name in &peer_names {
                    let entry = RemoteDirectoryEntry {
                        name: name.clone(),
                        path: format!("/remote/early/{name}"),
                        is_directory: false,
                        is_symlink: false,
                    };
                    if operation
                        .send(RemoteMessage::DirectoryEntry(entry), &[])
                        .await
                        .is_err()
                    {
                        write_closed = true;
                        break;
                    }
                    offered += 1;
                }
                anyhow::Ok((offered, write_closed))
            });
            for (index, expected) in names.iter().enumerate().take(3) {
                let entry = stream
                    .next_entry()
                    .await?
                    .with_context(|| format!("early-stop fixture ended before entry {index}"))?;
                ensure!(entry.name == *expected, "entry {index} mismatch");
            }
            drop(stream);
            // 整份目录远大于一条流的接收窗口：提前停止必须由 peer 观察到流被重置。
            let (offered, peer_write_closed) = tokio::time::timeout(Duration::from_secs(30), sending)
                .await
                .context("peer did not observe the early stop")???;
            ensure!(
                peer_write_closed,
                "peer did not observe the early-stopped stream (offered={offered})"
            );

            // 丢弃迭代器只收束该操作：控制面与新操作继续可用。
            client.heartbeat().await?;
            peer.expect_heartbeat().await?;
            let response = stat_once(client.clone(), peer, tasks).await?;
            ensure!(
                matches!(response, RemoteResponse::Stat(_)),
                "stat failed after early stop"
            );
            println!(
                "early stop: consumed=3 offered={offered} peer_write_closed={peer_write_closed} heartbeat=true stat=true"
            );
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await
}

/// 应用错误只结束对应操作，随后心跳、stat 与 exec 照常工作。
async fn error_isolation() -> anyhow::Result<()> {
    let mut scene = Scene::open().await?;
    let outcome = {
        let SceneParts {
            client,
            peer,
            tasks,
        } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            let directory_client = client.clone();
            let opening = spawn_owned(tasks, async move {
                directory_client
                    .directory(RemoteRequest::ListDirectory(RemotePathRequest {
                        workspace_id: WORKSPACE.into(),
                        path: "denied".into(),
                    }))
                    .await
            });
            let mut operation = peer.accept_operation().await?;
            expect_request(&mut operation, "listDirectory", |request| {
                matches!(request, RemoteRequest::ListDirectory(_))
            })
            .await?;
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::Directory(RemoteDirectoryMetadata {
                        path: "/remote/denied".into(),
                        parent: None,
                    })),
                    &[],
                )
                .await?;
            let mut stream = opening.await??;
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::Error(RemoteError {
                        code: RemoteErrorCode::Io,
                        message: "synthetic directory failure".into(),
                    })),
                    &[],
                )
                .await?;
            drop(operation);
            let error = loop {
                match stream.next_entry().await {
                    Ok(Some(_)) => continue,
                    Ok(None) => anyhow::bail!("directory ended without an error record"),
                    Err(error) => break error,
                }
            };
            ensure!(
                matches!(
                    error,
                    RemoteClientError::Remote {
                        code: RemoteErrorCode::Io,
                        ..
                    }
                ),
                "unexpected directory error: {error}"
            );
            drop(stream);

            // 第二个操作：准入阶段就被服务端 FD 预算拒绝。peer 读到 ListDirectory 后
            // 不回目录头，而是把 ResourceExhausted 作为该流的首个响应；因此
            // `directory` 自身必须直接以 typed `RemoteClientError::Remote` 失败，
            // 而不是先给出流、再在读取条目时报错。
            let directory_client = client.clone();
            let refused = spawn_owned(tasks, async move {
                directory_client
                    .directory(RemoteRequest::ListDirectory(RemotePathRequest {
                        workspace_id: WORKSPACE.into(),
                        path: "exhausted".into(),
                    }))
                    .await
            });
            let mut operation = peer.accept_operation().await?;
            expect_request(&mut operation, "listDirectory", |request| {
                matches!(request, RemoteRequest::ListDirectory(_))
            })
            .await?;
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::Error(RemoteError {
                        code: RemoteErrorCode::ResourceExhausted,
                        message: "synthetic helper resource exhaustion".into(),
                    })),
                    &[],
                )
                .await?;
            drop(operation);
            let error = match refused
                .await
                .context("resource-exhausted directory task was dropped")?
            {
                Ok(stream) => {
            drop(stream);
                    anyhow::bail!("resource exhaustion was answered with a directory stream")
                }
                Err(error) => error,
            };
            ensure!(
                matches!(
                    error,
                    RemoteClientError::Remote {
                        code: RemoteErrorCode::ResourceExhausted,
                        ..
                    }
                ),
                "unexpected resource-exhausted error: {error}"
            );

            client.heartbeat().await?;
            peer.expect_heartbeat().await?;
            // 健康连接继续工作；若 client 重放了被拒绝的目录请求，stat_once 的
            // 首个 accept 会拿到 ListDirectory 而不是 Stat，从而直接失败。
            let response = stat_once(client.clone(), peer, tasks).await?;
            ensure!(
                matches!(response, RemoteResponse::Stat(_)),
                "stat failed after directory error"
            );
            let exit = exec_once(client.clone(), peer, "healthy", b"ok", 0, tasks).await?;
            ensure!(
                exit.exit_code == Some(0),
                "exec failed after directory error: {exit:?}"
            );
            println!(
                "isolation: directory_error=io resource_exhausted=admission_rejected replay=none heartbeat=ok stat=ok exec_exit={:?}",
                exit.exit_code
            );
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await
}

/// 三个慢消费者都不读取时，控制面与新的普通操作仍有进展。
///
/// 每个 producer 都必须先真正进入背压（写未完成、流未终结、已发送量明显超过暂存窗口），
/// 只有三个背压点都被确认后才执行 heartbeat/stat/exec，最后统一放行并核对字节与终态。
async fn slow_consumers() -> anyhow::Result<()> {
    let mut scene = Scene::open().await?;
    let outcome = {
        let SceneParts {
            client,
            peer,
            tasks,
        } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            let (release, release_rx) = tokio::sync::watch::channel(false);

            // 目录：先建立迭代器，再由 producer 填满接收窗口。
            let directory_client = client.clone();
            let opening = spawn_owned(tasks, async move {
                directory_client
                    .directory(RemoteRequest::ListDirectory(RemotePathRequest {
                        workspace_id: WORKSPACE.into(),
                        path: "slow".into(),
                    }))
                    .await
            });
            let mut directory_operation = peer.accept_operation().await?;
            expect_request(&mut directory_operation, "listDirectory", |request| {
                matches!(request, RemoteRequest::ListDirectory(_))
            })
            .await?;
            directory_operation
                .send(
                    RemoteMessage::Response(RemoteResponse::Directory(RemoteDirectoryMetadata {
                        path: "/remote/slow".into(),
                        parent: None,
                    })),
                    &[],
                )
                .await?;
            let mut directory_stream = opening.await??;
            let (directory_blocked, directory_blocked_rx) = tokio::sync::oneshot::channel();
            let directory_producer = spawn_owned(tasks, produce_blocked_directory(
                directory_operation,
                release_rx.clone(),
                directory_blocked,
            ));

            // 下载：先取得 reader，再由 producer 填满接收窗口。
            let read_client = client.clone();
            let opening = spawn_owned(tasks, async move {
                read_client
                    .read_file(RemoteReadRequest {
                        workspace_id: WORKSPACE.into(),
                        path: "slow.bin".into(),
                        offset: 0,
                        max_bytes: None,
                    })
                    .await
            });
            let mut read_operation = peer.accept_operation().await?;
            expect_request(&mut read_operation, "readFile", |request| {
                matches!(request, RemoteRequest::ReadFile(_))
            })
            .await?;
            read_operation
                .send(
                    RemoteMessage::Response(RemoteResponse::File(RemoteFileMetadata {
                        offset: 0,
                        total_len: SLOW_DOWNLOAD_LEN,
                        transfer_len: SLOW_DOWNLOAD_LEN,
                    })),
                    &[],
                )
                .await?;
            let mut download = opening.await??;
            ensure!(
                download.metadata().offset == 0 && download.metadata().transfer_len == SLOW_DOWNLOAD_LEN,
                "unexpected download metadata"
            );
            let (read_blocked, read_blocked_rx) = tokio::sync::oneshot::channel();
            let read_producer = spawn_owned(tasks, produce_blocked_download(
                read_operation,
                release_rx.clone(),
                read_blocked,
                SLOW_DOWNLOAD_LEN,
            ));

            // 进程输出：先取得命令，再由 producer 填满接收窗口；客户端不消费。
            let process_client = client.clone();
            let request = spawn_request("slow");
            let opening = spawn_owned(tasks, async move { process_client.spawn_process(request).await });
            let mut process_operation = peer.accept_operation().await?;
            expect_request(&mut process_operation, "spawn", |request| {
                matches!(request, RemoteRequest::Spawn(_))
            })
            .await?;
            process_operation
                .send(
                    RemoteMessage::Response(RemoteResponse::ProcessSpawned {
                        process_id: "slow".into(),
                    }),
                    &[],
                )
                .await?;
            let mut stalled = opening.await??;
            let mut stalled_stdout = stalled
                .take_stdout()
                .context("stalled process must expose stdout")?;
            let (process_blocked, process_blocked_rx) = tokio::sync::oneshot::channel();
            let process_producer = spawn_owned(tasks, produce_blocked_output(
                process_operation,
                release_rx,
                process_blocked,
            ));

            // 三个背压点都必须已确认：写未完成、流未终结、已发送量超过暂存窗口。
            let directory_backpressure = wait_for_backpressure(directory_blocked_rx, "directory").await?;
            let read_backpressure = wait_for_backpressure(read_blocked_rx, "download").await?;
            let process_backpressure = wait_for_backpressure(process_blocked_rx, "process").await?;
            println!(
                "backpressure: directory_bytes={} download_bytes={} process_bytes={}",
                directory_backpressure, read_backpressure, process_backpressure
            );

            // 背压仍在时，控制面与新操作必须完成。
            client.heartbeat().await?;
            peer.expect_heartbeat().await?;
            let response = stat_once(client.clone(), peer, tasks).await?;
            ensure!(
                matches!(response, RemoteResponse::Stat(_)),
                "stat stalled behind slow consumers"
            );
            let quick = exec_once(client.clone(), peer, "quick", b"q", 0, tasks).await?;
            ensure!(
                quick.exit_code == Some(0),
                "exec stalled behind slow consumers: {quick:?}"
            );

            // 放开消费，核对完整字节与终态。
            release.send(true)?;
            let mut entries = 0usize;
            while let Some(entry) = directory_stream.next_entry().await? {
                ensure!(
                    entry.name.starts_with("entry-"),
                    "slow directory entry {entries} mismatch: {}",
                    entry.name
                );
                entries += 1;
            }
            let mut buffer = vec![0u8; DATA_CHUNK_BYTES];
            let mut downloaded = 0u64;
            loop {
                let read = download.read(&mut buffer).await?;
                if read == 0 {
                    break;
                }
                ensure!(buffer[..read].iter().all(|byte| *byte == b'r'));
                downloaded += read as u64;
            }
            let mut consumed = 0u64;
            loop {
                let read = stalled_stdout.read(&mut buffer).await?;
                if read == 0 {
                    break;
                }
                consumed += read as u64;
            }

            let directory_total = directory_producer.await??;
            let download_total = read_producer.await??;
            let process_total = process_producer.await??;
            ensure!(
                entries as u64 == directory_total,
                "directory entry count {entries} != {directory_total}"
            );
            ensure!(
                downloaded == download_total,
                "download bytes {downloaded} != {download_total}"
            );
            ensure!(
                consumed == process_total,
                "process bytes {consumed} != {process_total}"
            );
            let stalled_exit = stalled.wait().await.map_err(anyhow::Error::msg)?;
            ensure!(
                stalled_exit.exit_code == Some(0),
                "slow process exit mismatch: {stalled_exit:?}"
            );
            println!(
                "slow consumers: directory_entries={entries} download_bytes={downloaded} process_bytes={consumed} control_progress=true stat=true exec=true"
            );
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await
}

/// 目录 producer：填满接收窗口后停在未完成写入上，等到放行再发终结记录。
async fn produce_blocked_directory(
    mut operation: StreamPeer,
    mut release: tokio::sync::watch::Receiver<bool>,
    blocked: tokio::sync::oneshot::Sender<u64>,
) -> anyhow::Result<u64> {
    let mut sent = 0u64;
    let mut bytes = 0u64;
    let mut blocked = Some(blocked);
    loop {
        ensure!(
            sent < SLOW_DIRECTORY_TOTAL,
            "directory fixture ended without observing backpressure"
        );
        ensure!(
            bytes < SLOW_FILL_LIMIT,
            "directory stream window did not fill within {SLOW_FILL_LIMIT} bytes"
        );
        let entry = RemoteDirectoryEntry {
            name: format!("entry-{sent:05}-{}", "d".repeat(120)),
            path: format!("/remote/slow/{sent}"),
            is_directory: false,
            is_symlink: false,
        };
        let mut send = Box::pin(operation.send(RemoteMessage::DirectoryEntry(entry), &[]));
        // 只看“同一个未完成 send 是否持续 Pending 到观察窗口”：窗口内完成属正常调度，
        // 照常累计该条并继续填充下一条；绝不丢弃未完成 future 再重发（T1 会 poison）。
        match tokio::time::timeout(BACKPRESSURE_WINDOW, &mut send).await {
            Ok(result) => {
                result?;
                sent += 1;
                bytes += 160;
            }
            Err(_) => {
                ensure_backpressure(bytes, "directory")?;
                if let Some(blocked) = blocked.take() {
                    let _ = blocked.send(bytes);
                }
                release.wait_for(|released| *released).await?;
                // `.await` 消费同一个 future，借用随之结束，不需要也不能再 drop。
                send.await?;
                sent += 1;
                while sent < SLOW_DIRECTORY_TOTAL {
                    let entry = RemoteDirectoryEntry {
                        name: format!("entry-{sent:05}-{}", "d".repeat(120)),
                        path: format!("/remote/slow/{sent}"),
                        is_directory: false,
                        is_symlink: false,
                    };
                    operation
                        .send(RemoteMessage::DirectoryEntry(entry), &[])
                        .await?;
                    sent += 1;
                }
                operation
                    .send(RemoteMessage::Response(RemoteResponse::Complete), &[])
                    .await?;
                return Ok(sent);
            }
        }
    }
}

/// 下载 producer：发出正文直到写未完成，放行后发终结记录。
async fn produce_blocked_download(
    mut operation: StreamPeer,
    mut release: tokio::sync::watch::Receiver<bool>,
    blocked: tokio::sync::oneshot::Sender<u64>,
    total_len: u64,
) -> anyhow::Result<u64> {
    let body = vec![b'r'; DATA_CHUNK_BYTES];
    let mut offset = 0u64;
    let mut blocked = Some(blocked);
    loop {
        ensure!(
            offset < total_len,
            "download fixture ended without observing backpressure"
        );
        ensure!(
            offset < SLOW_FILL_LIMIT,
            "download stream window did not fill within {SLOW_FILL_LIMIT} bytes"
        );
        let mut send = Box::pin(operation.send(RemoteMessage::Data { offset }, &body));
        // 同一个 send 持续 Pending 到观察窗口才算窗口耗尽；窗口内完成只累计一次。
        match tokio::time::timeout(BACKPRESSURE_WINDOW, &mut send).await {
            Ok(result) => {
                result?;
                offset += DATA_CHUNK_BYTES as u64;
            }
            Err(_) => {
                ensure_backpressure(offset, "download")?;
                if let Some(blocked) = blocked.take() {
                    let _ = blocked.send(offset);
                }
                release.wait_for(|released| *released).await?;
                // `.await` 消费同一个 future，借用随之结束，不需要也不能再 drop。
                send.await?;
                offset += DATA_CHUNK_BYTES as u64;
                while offset < total_len {
                    operation
                        .send(RemoteMessage::Data { offset }, &body)
                        .await?;
                    offset += DATA_CHUNK_BYTES as u64;
                }
                operation
                    .send(
                        RemoteMessage::Response(RemoteResponse::Transferred { bytes: offset }),
                        &[],
                    )
                    .await?;
                return Ok(offset);
            }
        }
    }
}

/// 进程输出 producer：发出输出直到写未完成，放行后补发唯一退出记录。
async fn produce_blocked_output(
    mut operation: StreamPeer,
    mut release: tokio::sync::watch::Receiver<bool>,
    blocked: tokio::sync::oneshot::Sender<u64>,
) -> anyhow::Result<u64> {
    let body = vec![b'o'; DATA_CHUNK_BYTES];
    let mut sequence = 0u64;
    let mut bytes = 0u64;
    let mut blocked = Some(blocked);
    loop {
        ensure!(
            sequence < SLOW_OUTPUT_TOTAL,
            "process fixture ended without observing backpressure"
        );
        ensure!(
            bytes < SLOW_FILL_LIMIT,
            "process stream window did not fill within {SLOW_FILL_LIMIT} bytes"
        );
        sequence += 1;
        let mut send = Box::pin(operation.send(
            RemoteMessage::Event(RemoteEvent::ProcessOutput(RemoteProcessOutput {
                process_id: "slow".into(),
                sequence,
                stream: RemoteOutputStream::Stdout,
            })),
            &body,
        ));
        // 同一个 send 持续 Pending 到观察窗口才算窗口耗尽；窗口内完成只累计一次。
        match tokio::time::timeout(BACKPRESSURE_WINDOW, &mut send).await {
            Ok(result) => {
                result?;
                bytes += DATA_CHUNK_BYTES as u64;
            }
            Err(_) => {
                ensure_backpressure(bytes, "process")?;
                if let Some(blocked) = blocked.take() {
                    let _ = blocked.send(bytes);
                }
                release.wait_for(|released| *released).await?;
                // `.await` 消费同一个 future，借用随之结束，不需要也不能再 drop。
                send.await?;
                bytes += DATA_CHUNK_BYTES as u64;
                while sequence < SLOW_OUTPUT_TOTAL {
                    sequence += 1;
                    operation
                        .send(
                            RemoteMessage::Event(RemoteEvent::ProcessOutput(RemoteProcessOutput {
                                process_id: "slow".into(),
                                sequence,
                                stream: RemoteOutputStream::Stdout,
                            })),
                            &body,
                        )
                        .await?;
                    bytes += DATA_CHUNK_BYTES as u64;
                }
                operation
                    .send(
                        RemoteMessage::Event(RemoteEvent::ProcessExit(RemoteProcessExit {
                            process_id: "slow".into(),
                            exit_code: Some(0),
                            signal: None,
                            failure: None,
                            capture: None,
                        })),
                        &[],
                    )
                    .await?;
                return Ok(bytes);
            }
        }
    }
}

/// 背压前提：已发送量必须明显超过客户端未消费时的暂存窗口。
fn ensure_backpressure(sent_bytes: u64, stage: &str) -> anyhow::Result<()> {
    ensure!(
        sent_bytes > 64 * 1024,
        "{stage} producer reported backpressure after only {sent_bytes} bytes"
    );
    Ok(())
}

async fn wait_for_backpressure(
    receiver: tokio::sync::oneshot::Receiver<u64>,
    stage: &str,
) -> anyhow::Result<u64> {
    let sent = tokio::time::timeout(Duration::from_secs(30), receiver)
        .await
        .with_context(|| format!("{stage} producer never reached backpressure"))?
        .context("producer exited before reporting backpressure")?;
    Ok(sent)
}

/// 511 条普通子流全部在途：第 512 个调用等待可取消准入，控制面不被占用。
///
/// 本场景使用默认受控 Hello 广告的充足预算（operation_fds=4096 / workspace_fds=512），
/// 因此 511 条在途测的是**流容量**而不是 FD 准入；低 FD 准入由 `fd_budget_admission` 单独观察。
///
/// 占用额度的是**已经拿到启动应答、并且仍然打开的目录流**：受控 peer 先回 `Directory` 元数据
/// 头（这条真实发送让 Yamux 完成该子流的 ACK），随后不发送任何条目、也不结束，客户端因此
/// 一直持有该子流的读端。不能用短 unary `Stat` 填槽：Yamux 的 ACK 只能搭在真实外发帧或
/// WindowUpdate 上，短响应在 256 条未 ACK 时可能永远等不到释放，fixture 会自锁（不是生产的
/// 511 预算问题）。这里不改任何生产预算，也不伪造传输状态。
async fn ordinary_stream_limit() -> anyhow::Result<()> {
    let mut scene = Scene::open().await?;
    let outcome = {
        let SceneParts {
            client,
            peer,
            tasks,
        } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            let (opened_tx, mut opened_rx) = mpsc::channel::<()>(OPERATION_STREAMS);
            let mut results = Vec::with_capacity(OPERATION_STREAMS);
            // 每条在途流有自己的放行信号：这样才能“只释放一个 slot”并证明后续准入。
            let mut releases: Vec<Option<tokio::sync::oneshot::Sender<()>>> =
                Vec::with_capacity(OPERATION_STREAMS);
            for index in 0..OPERATION_STREAMS {
                let directory_client = client.clone();
                let opened = opened_tx.clone();
                let (release, released) = tokio::sync::oneshot::channel::<()>();
                releases.push(Some(release));
                results.push(spawn_owned(tasks, async move {
                    // 请求 path 携带本次 task 的 id：接受顺序与 spawn 顺序无关，
                    // peer 侧据此把每条在途流与它自己的放行信号配对。
                    let mut stream = directory_client
                        .directory(RemoteRequest::ListDirectory(RemotePathRequest {
                            workspace_id: WORKSPACE.into(),
                            path: format!("held/{index}"),
                        }))
                        .await?;
                    // 头部已被应答：该子流是真实建立并在途的，保持打开直到本条被放行。
                    let _ = opened.send(()).await;
                    released
                        .await
                        .context("the release signal for a held stream was dropped")?;
                    while stream.next_entry().await?.is_some() {}
                    anyhow::Ok(())
                }));
            }
            drop(opened_tx);
            println!("held streams: spawned={OPERATION_STREAMS}");
            // 逐条接受 + 应答 + 确认放行：客户端每条目录流都要等到这条真实发送（也顺带完成
            // Yamux 的 ACK），因此必须与接受循环交错推进，不能先等齐 511 个信号。
            let mut held: Vec<(usize, StreamPeer)> = Vec::with_capacity(OPERATION_STREAMS);
            for accepted in 0..OPERATION_STREAMS {
                let mut operation = peer.accept_operation().await?;
                let record = operation.read().await?;
                let RemoteMessage::Request(RemoteRequest::ListDirectory(request)) =
                    &record.message
                else {
                    anyhow::bail!(
                        "held stream did not start with listDirectory: {:?}",
                        record.message
                    );
                };
                let task = request
                    .path
                    .strip_prefix("held/")
                    .and_then(|index| index.parse::<usize>().ok())
                    .with_context(|| format!("held stream path is not identified: {}", request.path))?;
                anyhow::ensure!(
                    task < OPERATION_STREAMS,
                    "held stream id {task} is out of range"
                );
                operation
                    .send(
                        RemoteMessage::Response(RemoteResponse::Directory(RemoteDirectoryMetadata {
                            path: "/remote/held".into(),
                            parent: None,
                        })),
                        &[],
                    )
                    .await?;
                opened_rx.recv().await.with_context(|| {
                    format!("directory stream {accepted} opened without signalling")
                })?;
                held.push((task, operation));
                if accepted % 64 == 0 {
                    println!("held streams: accepted={accepted}");
                }
            }
            println!("held streams: admitted={}", held.len());
            ensure!(
                held.len() == OPERATION_STREAMS,
                "expected {OPERATION_STREAMS} reserved ordinary streams, held {}",
                held.len()
            );

            // 511 条仍在途时：带唯一 path 的等待请求必须真的进入准入等待（不是“已发出在等响应”），
            // 然后被真实取消；随后只释放一个 slot 再发不同 path 的新请求，peer 读到的必须只有新请求。
            // 这条 check 能击败“超额发出旧请求”的错误实现：旧请求若已写出，peer 会先读到它。
            let waiting_client = client.clone();
            let mut waiting = Box::pin(waiting_client.directory(RemoteRequest::ListDirectory(
                RemotePathRequest {
                    workspace_id: WORKSPACE.into(),
                    path: "cancelled-wait".into(),
                },
            )));
            ensure!(
                futures::poll!(&mut waiting).is_pending(),
                "request {OPERATION_STREAMS} was rejected instead of waiting for stream capacity"
            );
            tokio::task::yield_now().await;
            ensure!(
                futures::poll!(&mut waiting).is_pending(),
                "the waiting request left admission without a free slot"
            );
            // 真实取消：丢弃已进入准入等待的 future，不做“保留但不再 poll”的假取消。
            drop(waiting);
            println!("held streams: waiting request cancelled");

            // 控制面不占用普通额度。
            client.heartbeat().await?;
            peer.expect_heartbeat().await?;
            println!("held streams: control heartbeat ok with {OPERATION_STREAMS} held");

            // 只释放一个 slot：先通知该 task 开始排空，再结束它那条流；
            // slot 在流真正 drop 后归还，因此后续请求必须等这次释放完成才可能被准入。
            let (released_task, mut released) =
                held.pop().context("no held stream to release")?;
            releases[released_task]
                .take()
                .context("no release signal for the held stream")?
                .send(())
                .map_err(|()| anyhow::anyhow!("held stream task dropped its release signal"))?;
            released
                .send(RemoteMessage::Response(RemoteResponse::Complete), &[])
                .await?;
            drop(released);
            println!("held streams: released one slot (task={released_task})");

            // 新请求带不同 path，且必须在释放后才被准入。
            let admitted_client = client.clone();
            let admitted = Box::pin(admitted_client.directory(RemoteRequest::ListDirectory(
                RemotePathRequest {
                    workspace_id: WORKSPACE.into(),
                    path: "admitted-after-cancel".into(),
                },
            )));
            let (accepted, admitted_stream) = tokio::join!(
                async {
                    println!("held streams: waiting for the replacement request");
                    let mut operation = peer.accept_operation().await?;
                    println!("held streams: replacement request accepted");
                    let record = operation.read().await?;
                    let RemoteMessage::Request(RemoteRequest::ListDirectory(request)) =
                        &record.message
                    else {
                        anyhow::bail!(
                            "admitted stream did not start with listDirectory: {:?}",
                            record.message
                        );
                    };
                    ensure!(
                        request.path == "admitted-after-cancel",
                        "the cancelled waiting request reached the helper: {}",
                        request.path
                    );
                    operation
                        .send(
                            RemoteMessage::Response(RemoteResponse::Directory(
                                RemoteDirectoryMetadata {
                                    path: "/remote/admitted".into(),
                                    parent: None,
                                },
                            )),
                            &[],
                        )
                        .await?;
                    Ok::<StreamPeer, anyhow::Error>(operation)
                },
                async {
                    let stream = admitted.await;
                    println!("held streams: replacement request completed");
                    stream.context("admitted directory stream was dropped")
                }
            );
            let mut admitted_operation = accepted?;
            let mut admitted_stream = admitted_stream?;
            admitted_operation
                .send(RemoteMessage::Response(RemoteResponse::Complete), &[])
                .await?;
            ensure!(
                admitted_stream.next_entry().await?.is_none(),
                "admitted stream did not end with the completion record"
            );
            drop(admitted_operation);
            println!("held streams: admitted-after-cancel completed");

            // 放行剩余在途流并等待它们真实结束。
            for (task, mut operation) in held {
                if let Some(release) = releases[task].take() {
                    let _ = release.send(());
                }
                operation
                    .send(RemoteMessage::Response(RemoteResponse::Complete), &[])
                    .await?;
            }
            let mut completed = 0usize;
            for result in results {
                result
                    .await
                    .context("a held directory stream task was dropped")??;
                completed += 1;
            }
            ensure!(
                completed == OPERATION_STREAMS,
                "completed {completed} of {OPERATION_STREAMS} admitted streams"
            );
            println!(
                "streams: reserved={OPERATION_STREAMS} completed={completed} waiting_admission=1 control=independent"
            );
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await
}

/// 启动已提交后取消调用方，Terminate 不得越过未确认的启动裁决。
///
/// 判定不依赖时间窗口：受控 peer 的控制处理器在裁决发布前收到 Terminate 立即失败；
/// body 在发布裁决之前用 Heartbeat 屏障确认控制面已按序处理完此前的全部消息。
async fn process_startup_cancel() -> anyhow::Result<()> {
    let mut scene = Scene::open().await?;
    let outcome = {
        let SceneParts {
            client,
            peer,
            tasks,
        } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            let gate = peer.startup_gate();
            // 只有本场景开启启动裁决判定；其他场景的 Terminate 语义保持原样。
            gate.set(StartupPhase::AwaitingDecision);
            let cancel = CancellationToken::new();
            let spawn_client = client.clone();
            let request = spawn_request("controlled");
            let opening = {
                let cancel = cancel.clone();
                spawn_owned(tasks, async move {
                    tokio::select! {
                        result = spawn_client.spawn_process(request) => {
                            Ok::<_, anyhow::Error>(Some(result))
                    }
                        _ = cancel.cancelled() => Ok(None),
                    }
                })
            };
            let mut operation = peer.accept_operation().await?;
            expect_request(&mut operation, "spawn", |request| {
                matches!(request, RemoteRequest::Spawn(_))
            })
            .await?;

            // 启动裁决之前取消调用方；该任务由场景 owner join，不 detached。
            cancel.cancel();
            let cancelled = opening
                .await
                .context("cancelled startup caller task was dropped")??;
            ensure!(
                cancelled.is_none(),
                "cancelled spawn caller returned a result before the startup decision"
            );

            // Heartbeat 屏障：裁决未发布时控制面必须仍可按时序推进。
            // 若控制处理器已因越序 Terminate 主动失败，这里会立即收到通道关闭错误。
            client.heartbeat().await?;
            peer.expect_heartbeat().await?;
            ensure!(
                gate.phase() == StartupPhase::AwaitingDecision,
                "startup decision changed before it was published"
            );

            // 现在才发布启动裁决；此后的 Terminate 属于预期收束。
            gate.set(StartupPhase::Decided);
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::ProcessSpawned {
                        process_id: "controlled".into(),
                    }),
                    &[],
                )
                .await?;
            peer.expect_terminate("controlled").await?;
            operation
                .send(
                    RemoteMessage::Event(RemoteEvent::ProcessExit(RemoteProcessExit {
                        process_id: "controlled".into(),
                        exit_code: None,
                        signal: Some(15),
                        failure: None,
                        capture: None,
                    })),
                    &[],
                )
                .await?;
            drop(operation);

            // 第二次 Heartbeat 屏障：恰好一次 Terminate，且其后不得有迟到控制消息。
            client.heartbeat().await?;
            peer.expect_heartbeat().await?;
            ensure!(
                peer.try_next_control_request().is_none(),
                "unexpected late control message after the terminate"
            );
            println!(
                "startup cancel: caller cancelled and joined before the startup result; exactly one terminate observed after it"
            );
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await
}

/// stdin 被拒绝且进程立刻退出时，原始输入错误不得被正常退出吞掉。
async fn process_input_rejected() -> anyhow::Result<()> {
    let mut scene = Scene::open().await?;
    let outcome = {
        let SceneParts {
            client,
            peer,
            tasks,
        } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            let spawn_client = client.clone();
            let request = spawn_request("controlled");
            let task = spawn_owned(
                tasks,
                async move { spawn_client.spawn_process(request).await },
            );
            let mut operation = peer.accept_operation().await?;
            expect_request(&mut operation, "spawn", |request| {
                matches!(request, RemoteRequest::Spawn(_))
            })
            .await?;
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::ProcessSpawned {
                        process_id: "controlled".into(),
                    }),
                    &[],
                )
                .await?;
            let mut command = task.await??;
            let mut stdin = command.take_stdin().context("process must expose stdin")?;
            stdin.write_all(b"input").await?;
            let record = operation.read().await?;
            ensure!(
                matches!(record.message, RemoteMessage::Stdin),
                "expected stdin record, got {:?}",
                record.message
            );
            ensure!(&record.body[..] == b"input", "stdin body mismatch");
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::Error(RemoteError {
                        code: RemoteErrorCode::Io,
                        message: "synthetic input rejected".into(),
                    })),
                    &[],
                )
                .await?;
            operation
                .send(
                    RemoteMessage::Event(RemoteEvent::ProcessExit(RemoteProcessExit {
                        process_id: "controlled".into(),
                        exit_code: Some(0),
                        signal: None,
                        failure: None,
                        capture: None,
                    })),
                    &[],
                )
                .await?;
            drop(operation);
            let error = command
                .wait()
                .await
                .expect_err("stdin rejection was swallowed by the normal exit");
            ensure!(
                error.contains("synthetic input rejected"),
                "original stdin failure lost: {error}"
            );
            println!("input rejection: original error preserved through immediate exit");
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await
}

/// 输出无人消费时显式取消：停止等待消费者，仍完成输出丢弃与物理回收。
async fn process_cancel_after_output() -> anyhow::Result<()> {
    let mut scene = Scene::open().await?;
    let outcome = {
        let SceneParts {
            client,
            peer,
            tasks,
        } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            let spawn_client = client.clone();
            let request = spawn_request("controlled");
            let task = spawn_owned(
                tasks,
                async move { spawn_client.spawn_process(request).await },
            );
            let mut operation = peer.accept_operation().await?;
            expect_request(&mut operation, "spawn", |request| {
                matches!(request, RemoteRequest::Spawn(_))
            })
            .await?;
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::ProcessSpawned {
                        process_id: "controlled".into(),
                    }),
                    &[],
                )
                .await?;
            let mut command = task.await??;
            let unread = command
                .take_stdout()
                .context("process must expose stdout")?;
            let body = vec![b'x'; 8 * 1024];
            for sequence in 1..=16u64 {
                operation
                    .send(
                        RemoteMessage::Event(RemoteEvent::ProcessOutput(RemoteProcessOutput {
                            process_id: "controlled".into(),
                            sequence,
                            stream: RemoteOutputStream::Stdout,
                        })),
                        &body,
                    )
                    .await?;
            }
            operation
                .send(
                    RemoteMessage::Event(RemoteEvent::ProcessExit(RemoteProcessExit {
                        process_id: "controlled".into(),
                        exit_code: Some(0),
                        signal: None,
                        failure: None,
                        capture: None,
                    })),
                    &[],
                )
                .await?;
            drop(operation);
            command.cancellation().cancel();
            let exit = command.wait().await.map_err(anyhow::Error::msg)?;
            ensure!(
                exit.exit_code == Some(0),
                "cancelled process exit mismatch: {exit:?}"
            );
            ensure!(
                exit.capture.is_none(),
                "capture receipt without a capture policy"
            );
            drop(unread);
            drop(command);
            client.heartbeat().await?;
            peer.expect_heartbeat_with(&["controlled"]).await?;
            println!(
                "cancel after output: unread_bytes={} exit={:?}",
                body.len() * 16,
                exit.exit_code
            );
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await
}

/// 读流：错误 offset、缺失终结与计量不一致都失败，且不破坏连接。
async fn read_protocol_errors() -> anyhow::Result<()> {
    let mut scene = Scene::open().await?;
    let outcome = {
        let SceneParts {
            client,
            peer,
            tasks,
        } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            let mut buffer = [0u8; 32];

            // 1. 偏移不连续。
            let read_client = client.clone();
            let opening = spawn_owned(tasks, async move {
                read_client
                    .read_file(RemoteReadRequest {
                        workspace_id: WORKSPACE.into(),
                        path: "offset.bin".into(),
                        offset: 0,
                        max_bytes: None,
                    })
                    .await
            });
            let mut operation = peer.accept_operation().await?;
            expect_request(&mut operation, "readFile", |request| {
                matches!(request, RemoteRequest::ReadFile(_))
            })
            .await?;
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::File(RemoteFileMetadata {
                        offset: 0,
                        total_len: 64,
                        transfer_len: 64,
                    })),
                    &[],
                )
                .await?;
            let mut reader = opening.await??;
            ensure!(reader.metadata().transfer_len == 64);
            operation
                .send(RemoteMessage::Data { offset: 32 }, &[b'a'; 16])
                .await?;
            drop(operation);
            let mut error: Option<std::io::Error> = None;
            for _ in 0..4 {
                match reader.read(&mut buffer).await {
                    Ok(0) => break,
                    Ok(_) => continue,
                    Err(failure) => {
                        error = Some(failure);
                        break;
                    }
                }
            }
            ensure!(
                error.is_some(),
                "discontinuous read offset was accepted as success"
            );
            drop(reader);

            // 2. 没有 Transferred 终结的裸 EOF。
            let read_client = client.clone();
            let opening = spawn_owned(tasks, async move {
                read_client
                    .read_file(RemoteReadRequest {
                        workspace_id: WORKSPACE.into(),
                        path: "eof.bin".into(),
                        offset: 0,
                        max_bytes: None,
                    })
                    .await
            });
            let mut operation = peer.accept_operation().await?;
            expect_request(&mut operation, "readFile", |request| {
                matches!(request, RemoteRequest::ReadFile(_))
            })
            .await?;
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::File(RemoteFileMetadata {
                        offset: 0,
                        total_len: 16,
                        transfer_len: 16,
                    })),
                    &[],
                )
                .await?;
            let mut reader = opening.await??;
            operation
                .send(RemoteMessage::Data { offset: 0 }, &[b'b'; 16])
                .await?;
            drop(operation);
            let mut read_total = 0usize;
            let mut error: Option<std::io::Error> = None;
            loop {
                match reader.read(&mut buffer).await {
                    Ok(0) => break,
                    Ok(count) => read_total += count,
                    Err(failure) => {
                        error = Some(failure);
                        break;
                    }
                }
            }
            ensure!(
                error.is_some(),
                "bare EOF after {read_total} bytes was reported as a clean success"
            );
            drop(reader);

            // 3. Transferred 计量与声明的传输长度不一致。
            let read_client = client.clone();
            let opening = spawn_owned(tasks, async move {
                read_client
                    .read_file(RemoteReadRequest {
                        workspace_id: WORKSPACE.into(),
                        path: "short.bin".into(),
                        offset: 0,
                        max_bytes: None,
                    })
                    .await
            });
            let mut operation = peer.accept_operation().await?;
            expect_request(&mut operation, "readFile", |request| {
                matches!(request, RemoteRequest::ReadFile(_))
            })
            .await?;
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::File(RemoteFileMetadata {
                        offset: 0,
                        total_len: 32,
                        transfer_len: 32,
                    })),
                    &[],
                )
                .await?;
            let mut reader = opening.await??;
            operation
                .send(RemoteMessage::Data { offset: 0 }, &[b'c'; 32])
                .await?;
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::Transferred { bytes: 31 }),
                    &[],
                )
                .await?;
            drop(operation);
            let mut error: Option<std::io::Error> = None;
            loop {
                match reader.read(&mut buffer).await {
                    Ok(0) => break,
                    Ok(_) => continue,
                    Err(failure) => {
                        error = Some(failure);
                        break;
                    }
                }
            }
            ensure!(error.is_some(), "transfer accounting mismatch was accepted");
            drop(reader);

            client.heartbeat().await?;
            peer.expect_heartbeat().await?;
            let response = stat_once(client.clone(), peer, tasks).await?;
            ensure!(matches!(response, RemoteResponse::Stat(_)));
            println!(
                "read errors: offset=rejected bare_eof=rejected accounting=rejected connection=healthy"
            );
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await
}

/// 上传：连续 offset、UploadFinished 校验、错误响应与计量不一致。
async fn upload_stream_semantics() -> anyhow::Result<()> {
    let mut scene = Scene::open().await?;
    let outcome = {
        let SceneParts {
            client,
            peer,
            tasks,
        } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            let total_len = (DATA_CHUNK_BYTES * 3) as u64;

            // 1. 正常上传：逐条核对连续 offset 与 UploadFinished。
            let upload_client = client.clone();
            let request = write_request(total_len);
            let data = upload_payload();
            let task = spawn_owned(tasks, async move {
                let mut source: &[u8] = &data;
                upload_client.write_file(request, &mut source).await
            });
            let mut operation = peer.accept_operation().await?;
            let record = operation.read().await?;
            let RemoteMessage::Request(RemoteRequest::WriteFile(write)) = record.message else {
                anyhow::bail!("expected writeFile request");
            };
            ensure!(
                write.mode == RemoteWriteMode::Create && write.total_len == total_len,
                "unexpected write request: {write:?}"
            );
            operation
                .send(RemoteMessage::Response(RemoteResponse::Ready), &[])
                .await?;
            let mut received = 0u64;
            let mut records = 0usize;
            loop {
                let record = operation.read().await?;
                match record.message {
                    RemoteMessage::Data { offset } => {
                        ensure!(offset == received, "upload offset {offset} != {received}");
                        ensure!(!record.body.is_empty(), "empty upload chunk");
                        received += record.body.len() as u64;
                        records += 1;
                    }
                    RemoteMessage::UploadFinished { total_len } => {
                        ensure!(
                            total_len == received,
                            "upload finished {total_len} != {received}"
                        );
                        break;
                    }
                    other => anyhow::bail!("unexpected upload record: {other:?}"),
                }
            }
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::Transferred { bytes: received }),
                    &[],
                )
                .await?;
            drop(operation);
            let written = task.await??;
            ensure!(written == total_len, "write receipt mismatch: {written}");
            ensure!(
                received == total_len,
                "peer received {received} of {total_len}"
            );
            ensure!(records >= 3, "upload was not chunked: {records}");

            // 2. 上传中途的服务端错误。
            let upload_client = client.clone();
            let request = write_request(total_len);
            let data = upload_payload();
            let task = spawn_owned(tasks, async move {
                let mut source: &[u8] = &data;
                upload_client.write_file(request, &mut source).await
            });
            let mut operation = peer.accept_operation().await?;
            let record = operation.read().await?;
            ensure!(
                matches!(
                    record.message,
                    RemoteMessage::Request(RemoteRequest::WriteFile(_))
                ),
                "expected writeFile request"
            );
            operation
                .send(RemoteMessage::Response(RemoteResponse::Ready), &[])
                .await?;
            let mut received = 0u64;
            while received < DATA_CHUNK_BYTES as u64 {
                let record = operation.read().await?;
                let RemoteMessage::Data { offset } = record.message else {
                    anyhow::bail!("expected upload data before the error");
                };
                ensure!(offset == received, "upload offset {offset} != {received}");
                received += record.body.len() as u64;
            }
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::Error(RemoteError {
                        code: RemoteErrorCode::Io,
                        message: "synthetic upload failure".into(),
                    })),
                    &[],
                )
                .await?;
            drop(operation);
            let error = task
                .await?
                .expect_err("server upload error was reported as success");
            ensure!(
                matches!(
                    error,
                    RemoteClientError::Remote {
                        code: RemoteErrorCode::Io,
                        ..
                    }
                ),
                "unexpected upload error: {error}"
            );

            // 3. 计量不一致的确认。
            let upload_client = client.clone();
            let request = write_request(total_len);
            let data = upload_payload();
            let task = spawn_owned(tasks, async move {
                let mut source: &[u8] = &data;
                upload_client.write_file(request, &mut source).await
            });
            let mut operation = peer.accept_operation().await?;
            operation.read().await?;
            operation
                .send(RemoteMessage::Response(RemoteResponse::Ready), &[])
                .await?;
            loop {
                let record = operation.read().await?;
                if matches!(record.message, RemoteMessage::UploadFinished { .. }) {
                    break;
                }
            }
            operation
                .send(
                    RemoteMessage::Response(RemoteResponse::Transferred { bytes: 1 }),
                    &[],
                )
                .await?;
            drop(operation);
            let result = task.await?;
            ensure!(
                result.is_err(),
                "transfer accounting mismatch was accepted: {result:?}"
            );

            client.heartbeat().await?;
            peer.expect_heartbeat().await?;
            println!(
                "uploads: chunks={records} bytes={received} mid_stream_error=rejected accounting=rejected"
            );
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await
}

/// Hello 预算非法时必须让 `connect` 失败并回收 owner（不是仅构造 DTO 回读）。
///
/// 代表性组合：零池、零成本、retained>open、普通成本>operation 池。每个失败都必须被
/// client 的 Hello 校验判为协议失败，且受控 peer 的 owner/handle 在此之后被显式 close+join。
async fn handshake_resource_budget_rejected() -> anyhow::Result<()> {
    for (label, limits) in invalid_resource_limits() {
        let error = rejected_handshake(hello_with(REMOTE_PROTOCOL_VERSION, limits), label).await?;
        ensure!(
            is_protocol_error(&error),
            "{label}: invalid resource budget was not rejected as a protocol failure: {error}"
        );
        println!("resource budget rejected: {label}");
    }
    Ok(())
}

/// 代表性非法预算组合。
fn invalid_resource_limits() -> Vec<(&'static str, RemoteResourceLimits)> {
    let base = controlled_limits();
    let costs = base.costs;
    vec![
        (
            "zero operation pool",
            RemoteResourceLimits {
                operation_fds: 0,
                ..base
            },
        ),
        (
            "zero workspace pool",
            RemoteResourceLimits {
                workspace_fds: 0,
                ..base
            },
        ),
        (
            "zero metadata cost",
            RemoteResourceLimits {
                costs: RemoteResourceCosts {
                    metadata: 0,
                    ..costs
                },
                ..base
            },
        ),
        (
            "retained above open",
            RemoteResourceLimits {
                costs: RemoteResourceCosts {
                    workspace_retained: costs.workspace_open + 1,
                    ..costs
                },
                ..base
            },
        ),
        (
            "operation cost above pool",
            RemoteResourceLimits {
                operation_fds: costs.spawn - 1,
                ..base
            },
        ),
    ]
}

/// 用一个声明了给定 Hello 的受控 peer 完成握手，返回 client 的真实失败。
///
/// owner/handle 在 body 之外创建，body 只返回结果；收尾无条件显式 close + wait_closed，
/// 因此“拒绝后 owner 被回收”与“client 失败类型”都被证明。
async fn rejected_handshake(hello: RemoteHello, label: &str) -> anyhow::Result<RemoteClientError> {
    let (server, client_io) = tokio::io::duplex(TRANSPORT_BUFFER);
    let (server_read, server_write) = tokio::io::split(server);
    let (client_read, client_write) = tokio::io::split(client_io);
    let (owner, handle, mut incoming) =
        ConnectionOwner::start(server_read, server_write, Role::Server);
    let outcome = {
        let body = async move {
            let handshake = async move {
                let stream = incoming
                    .accept()
                    .await?
                    .context("peer never opened the control stream")?;
                let mut control = StreamPeer::new(stream);
                control.read().await?;
                control
                    .send(RemoteMessage::Response(RemoteResponse::Hello(hello)), &[])
                    .await?;
                anyhow::Ok(())
            };
            let (connect, served) =
                tokio::join!(RemoteClient::connect(client_read, client_write), handshake);
            served.context("controlled peer did not answer the hello")?;
            match connect {
                Ok(_) => anyhow::bail!("{label}: an invalid resource budget was accepted"),
                Err(error) => anyhow::Ok(error),
            }
        };
        // `run_with_deadline` 固定返回 `anyhow::Result<()>`；这里要带回 client 的真实失败类型，
        // 因此直接用 timeout 包裹 body。
        match tokio::time::timeout(STAGE_TIMEOUT, body).await {
            Ok(result) => result,
            Err(_) => Err(anyhow::anyhow!(
                "handshake rejection did not settle within {STAGE_TIMEOUT:?}"
            )),
        }
    };
    let settled = settle_manual_connection(&owner, handle).await;
    match (outcome, settled) {
        (Ok(error), Ok(())) => Ok(error),
        (Ok(_), Err(cleanup)) => Err(cleanup),
        (Err(error), Ok(())) => Err(error),
        (Err(error), Err(cleanup)) => Err(error.context(format!(
            "handshake rejection cleanup also failed: {cleanup:#}"
        ))),
    }
}

/// 低 operation FD 预算（Yamux 仍有空位）时的准入行为。
///
/// 第一条目录流吃满 FD 预算后：第二个真实请求必须停在准入等待（不发送业务请求），
/// 控制面心跳仍进展；取消等待不泄 permit；释放第一条后新请求的首个 accept 身份必须是它。
async fn fd_budget_admission() -> anyhow::Result<()> {
    let mut scene = Scene::open_with(hello_with(
        REMOTE_PROTOCOL_VERSION,
        RemoteResourceLimits {
            // 目录成本 3：池只能容纳一条在途目录操作；流预算仍是 511。
            operation_fds: 3,
            workspace_fds: 8,
            costs: RemoteResourceCosts {
                workspace_open: 3,
                workspace_retained: 1,
                metadata: 3,
                directory: 3,
                read_file: 3,
                write_file: 3,
                copy_file: 3,
                spawn: 3,
            },
        },
    ))
    .await?;
    let outcome = {
        let SceneParts { client, peer, .. } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            // 第一条：占用整份 operation 预算并保持打开。
            let first_client = client.clone();
            let (first_operation, first_stream) = tokio::join!(
                async {
                    let mut operation = peer.accept_operation().await?;
                    expect_request(&mut operation, "first", |request| {
                        matches!(request, RemoteRequest::ListDirectory(_))
                    })
                    .await?;
                    operation
                        .send(
                            RemoteMessage::Response(RemoteResponse::Directory(
                                RemoteDirectoryMetadata {
                                    path: "/remote/fd-first".into(),
                                    parent: None,
                                },
                            )),
                            &[],
                        )
                        .await?;
                    Ok::<StreamPeer, anyhow::Error>(operation)
                },
                async {
                    first_client
                        .directory(RemoteRequest::ListDirectory(RemotePathRequest {
                            workspace_id: WORKSPACE.into(),
                            path: "fd-first".into(),
                        }))
                        .await
                        .context("first directory stream was dropped")
                }
            );
            let mut first_operation = first_operation?;
            let mut first_stream = first_stream?;

            // 第二条：FD 满而流有空位 → 真实 client 必须停在准入等待，不发请求。
            let waiting_client = client.clone();
            let mut waiting = Box::pin(waiting_client.directory(RemoteRequest::ListDirectory(
                RemotePathRequest {
                    workspace_id: WORKSPACE.into(),
                    path: "fd-cancelled".into(),
                },
            )));
            ensure!(
                futures::poll!(&mut waiting).is_pending(),
                "second request was not held by the FD budget"
            );
            tokio::task::yield_now().await;
            ensure!(
                futures::poll!(&mut waiting).is_pending(),
                "second request left admission without a free FD slot"
            );

            // 控制面不取业务预算：心跳仍能完成。
            client.heartbeat().await?;
            peer.expect_heartbeat().await?;

            // 取消等待：丢弃已进入准入等待的 future，不发送任何业务请求。
            drop(waiting);

            // 释放第一条（结束其流 → 归还 FD permit）。
            first_operation
                .send(RemoteMessage::Response(RemoteResponse::Complete), &[])
                .await?;
            drop(first_operation);
            while first_stream.next_entry().await?.is_some() {}

            // 新请求：首个 accept 必须正是它（被取消的旧请求从未上线）。
            let admitted_client = client.clone();
            let admitted = Box::pin(admitted_client.directory(RemoteRequest::ListDirectory(
                RemotePathRequest {
                    workspace_id: WORKSPACE.into(),
                    path: "fd-admitted".into(),
                },
            )));
            let (accepted, admitted_stream) = tokio::join!(
                async {
                    let mut operation = peer.accept_operation().await?;
                    let record = operation.read().await?;
                    let RemoteMessage::Request(RemoteRequest::ListDirectory(request)) =
                        &record.message
                    else {
                        anyhow::bail!(
                            "admitted stream did not start with listDirectory: {:?}",
                            record.message
                        );
                    };
                    ensure!(
                        request.path == "fd-admitted",
                        "the cancelled request reached the helper: {}",
                        request.path
                    );
                    operation
                        .send(
                            RemoteMessage::Response(RemoteResponse::Directory(
                                RemoteDirectoryMetadata {
                                    path: "/remote/fd-admitted".into(),
                                    parent: None,
                                },
                            )),
                            &[],
                        )
                        .await?;
                    Ok::<StreamPeer, anyhow::Error>(operation)
                },
                async { admitted.await.context("admitted directory stream was dropped") }
            );
            let mut admitted_operation = accepted?;
            let mut admitted_stream = admitted_stream?;
            admitted_operation
                .send(RemoteMessage::Response(RemoteResponse::Complete), &[])
                .await?;
            ensure!(
                admitted_stream.next_entry().await?.is_none(),
                "admitted stream did not end with the completion record"
            );
            drop(admitted_operation);
            println!(
                "fd admission: second_waiting=1 control_ok=true cancelled=1 replay=none admitted=fd-admitted"
            );
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await
}

/// 低 workspace FD 预算下取消公开 `request(OpenWorkspace)` 的未知 handle 责任。
///
/// 调用方在请求已上线后取消等待；client 的跟踪 owner 必须继续读取成功结果并显式
/// CloseWorkspace（控制事务 Ack 后池恢复），因此后续 open 才能再次成功。
async fn workspace_budget_recovery() -> anyhow::Result<()> {
    let mut scene = Scene::open_with(hello_with(
        REMOTE_PROTOCOL_VERSION,
        RemoteResourceLimits {
            // open 成本 3、retained 1：池只有 3 时同一时刻只容得下一次 open。
            operation_fds: 64,
            workspace_fds: 3,
            costs: RemoteResourceCosts {
                workspace_open: 3,
                workspace_retained: 1,
                metadata: 4,
                directory: 3,
                read_file: 3,
                write_file: 4,
                copy_file: 5,
                spawn: 15,
            },
        },
    ))
    .await?;
    let outcome = {
        let SceneParts { client, peer, .. } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            // 0) 等待助手不得吞掉真实失败：本地立刻给出的 typed Err 必须作为 source
            // 保留在返回错误链上（只追加“未等到操作流”的上下文）。这里用同一助手的
            // 即时 future 触发，不发送任何请求、不依赖 peer 时序。
            let mut settled = Box::pin(std::future::ready(Err::<RemoteResponse, _>(
                RemoteClientError::Cancelled,
            )));
            let error = match drive_until_accepted(peer, &mut settled).await {
                Ok(_) => anyhow::bail!("a settled request yielded an operation stream"),
                Err(error) => error,
            };
            ensure!(
                matches!(
                    error.downcast_ref::<RemoteClientError>(),
                    Some(RemoteClientError::Cancelled)
                ),
                "the request failure was flattened instead of kept as the error source: {error:#}"
            );
            println!("workspace budget: settled request kept its typed source before any stream");

            // 1) 发出 OpenWorkspace 后取消调用方等待（请求已在线上）。
            let first_client = client.clone();
            let mut abandoned = Box::pin(first_client.request(RemoteRequest::OpenWorkspace {
                path: "/remote/fd-workspace".into(),
            }));
            let mut first_operation = drive_until_accepted(peer, &mut abandoned).await?;
            expect_request(&mut first_operation, "openWorkspace", |request| {
                matches!(request, RemoteRequest::OpenWorkspace { .. })
            })
            .await?;
            drop(abandoned);
            first_operation
                .send(
                    RemoteMessage::Response(RemoteResponse::WorkspaceOpened(
                        RemoteWorkspaceOpened {
                            workspace_id: "fd-ws-1".into(),
                            canonical_path: "/remote/fd-workspace".into(),
                        },
                    )),
                    &[],
                )
                .await?;
            drop(first_operation);

            // 2) owner 仍读走成功结果，并因无人认领而显式 CloseWorkspace。
            peer.expect_close_workspace("fd-ws-1").await?;

            // 3) Ack 后池恢复：下一次 open 必须成功。
            let second_client = client.clone();
            let second = Box::pin(second_client.request(RemoteRequest::OpenWorkspace {
                path: "/remote/fd-workspace-2".into(),
            }));
            let (accepted, response) = tokio::join!(
                async {
                    let mut operation = peer.accept_operation().await?;
                    expect_request(&mut operation, "openWorkspace", |request| {
                        matches!(request, RemoteRequest::OpenWorkspace { .. })
                    })
                    .await?;
                    operation
                        .send(
                            RemoteMessage::Response(RemoteResponse::WorkspaceOpened(
                                RemoteWorkspaceOpened {
                                    workspace_id: "fd-ws-2".into(),
                                    canonical_path: "/remote/fd-workspace-2".into(),
                                },
                            )),
                            &[],
                        )
                        .await?;
                    Ok::<StreamPeer, anyhow::Error>(operation)
                },
                async { second.await.context("second openWorkspace was dropped") }
            );
            let second_operation = accepted?;
            let response = response?;
            ensure!(
                matches!(
                    &response,
                    RemoteResponse::WorkspaceOpened(opened) if opened.workspace_id == "fd-ws-2"
                ),
                "second openWorkspace returned {response:?}"
            );
            drop(second_operation);

            // 4) 显式 CloseWorkspace 必须被 Ack，并再次让出预算。
            let close_client = client.clone();
            let close = Box::pin(close_client.request(RemoteRequest::CloseWorkspace {
                workspace_id: "fd-ws-2".into(),
            }));
            let (observed, acknowledged) = tokio::join!(
                async {
                    peer.expect_close_workspace("fd-ws-2").await?;
                    Ok::<(), anyhow::Error>(())
                },
                async {
                    let response = close
                        .await
                        .context("explicit closeWorkspace was dropped")?;
                    ensure!(
                        matches!(response, RemoteResponse::Ack),
                        "explicit closeWorkspace was not acknowledged: {response:?}"
                    );
                    Ok::<(), anyhow::Error>(())
                }
            );
            observed?;
            acknowledged?;

            // 5) 关闭后仍能再 open：证明显式关闭同样归还了预算。
            let third_client = client.clone();
            let third = Box::pin(third_client.request(RemoteRequest::OpenWorkspace {
                path: "/remote/fd-workspace-3".into(),
            }));
            let (accepted, response) = tokio::join!(
                async {
                    let mut operation = peer.accept_operation().await?;
                    expect_request(&mut operation, "openWorkspace", |request| {
                        matches!(request, RemoteRequest::OpenWorkspace { .. })
                    })
                    .await?;
                    operation
                        .send(
                            RemoteMessage::Response(RemoteResponse::WorkspaceOpened(
                                RemoteWorkspaceOpened {
                                    workspace_id: "fd-ws-3".into(),
                                    canonical_path: "/remote/fd-workspace-3".into(),
                                },
                            )),
                            &[],
                        )
                        .await?;
                    Ok::<StreamPeer, anyhow::Error>(operation)
                },
                async { third.await.context("third openWorkspace was dropped") }
            );
            let third_operation = accepted?;
            let response = response?;
            ensure!(
                matches!(
                    &response,
                    RemoteResponse::WorkspaceOpened(opened) if opened.workspace_id == "fd-ws-3"
                ),
                "third openWorkspace returned {response:?}"
            );
            drop(third_operation);
            let close_client = client.clone();
            let close = Box::pin(close_client.request(RemoteRequest::CloseWorkspace {
                workspace_id: "fd-ws-3".into(),
            }));
            let (observed, acknowledged) = tokio::join!(
                async {
                    peer.expect_close_workspace("fd-ws-3").await?;
                    Ok::<(), anyhow::Error>(())
                },
                async {
                    let response = close
                        .await
                        .context("third closeWorkspace was dropped")?;
                    ensure!(
                        matches!(response, RemoteResponse::Ack),
                        "third closeWorkspace was not acknowledged: {response:?}"
                    );
                    Ok::<(), anyhow::Error>(())
                }
            );
            observed?;
            acknowledged?;
            println!(
                "workspace budget: abandoned=closed_by_owner reopened=fd-ws-2 explicit_close=acked reopened_again=fd-ws-3"
            );
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await
}

/// hello 版本协商：helper 拒绝与 helper 版本不符都必须失败；关闭是单向 shutdown。
///
/// 两个手工对端的 owner 都创建在 deadline body 之外：body 只返回结果，收尾一律
/// `settle_manual_connection` 后与 body 结果 `combine`，失败不会跳过真实 close/wait。
async fn handshake_and_shutdown() -> anyhow::Result<()> {
    // helper 拒绝当前客户端的版本。
    {
        let (server, client_io) = tokio::io::duplex(TRANSPORT_BUFFER);
        let (server_read, server_write) = tokio::io::split(server);
        let (client_read, client_write) = tokio::io::split(client_io);
        let (owner, handle, mut incoming) =
            ConnectionOwner::start(server_read, server_write, Role::Server);
        let outcome = {
            let body = async move {
                let handshake = async move {
                    let stream = incoming
                        .accept()
                        .await?
                        .context("peer never opened the control stream")?;
                    let mut control = StreamPeer::new(stream);
                    let record = control.read().await?;
                    let RemoteMessage::Request(RemoteRequest::Hello { protocol_version }) =
                        record.message
                    else {
                        anyhow::bail!("first control record must be Hello");
                    };
                    ensure!(
                        protocol_version == REMOTE_PROTOCOL_VERSION,
                        "client announced {protocol_version}"
                    );
                    control
                        .send(
                            RemoteMessage::Response(RemoteResponse::Error(RemoteError {
                                code: RemoteErrorCode::ProtocolMismatch,
                                message: "protocol version rejected by helper".into(),
                            })),
                            &[],
                        )
                        .await?;
                    anyhow::Ok(())
                };
                let (connect, served) =
                    tokio::join!(RemoteClient::connect(client_read, client_write), handshake);
                served.context("controlled peer did not reject the hello")?;
                let error = match connect {
                    Ok(_) => anyhow::bail!("helper rejection was ignored"),
                    Err(error) => error,
                };
                ensure!(
                    is_protocol_error(&error),
                    "unexpected helper-rejection error: {error}"
                );
                anyhow::Ok(())
            };
            run_with_deadline(STAGE_TIMEOUT, body).await
        };
        let settled = settle_manual_connection(&owner, handle).await;
        combine(outcome, settled)?;
    }

    // helper 返回未知协议版本。
    {
        let (server, client_io) = tokio::io::duplex(TRANSPORT_BUFFER);
        let (server_read, server_write) = tokio::io::split(server);
        let (client_read, client_write) = tokio::io::split(client_io);
        let (owner, handle, mut incoming) =
            ConnectionOwner::start(server_read, server_write, Role::Server);
        let outcome = {
            let body = async move {
                let handshake = async move {
                    let stream = incoming
                        .accept()
                        .await?
                        .context("peer never opened the control stream")?;
                    let mut control = StreamPeer::new(stream);
                    control.read().await?;
                    control
                        .send(
                            RemoteMessage::Response(RemoteResponse::Hello(hello(
                                REMOTE_PROTOCOL_VERSION - 1,
                            ))),
                            &[],
                        )
                        .await?;
                    anyhow::Ok(())
                };
                let (connect, served) =
                    tokio::join!(RemoteClient::connect(client_read, client_write), handshake);
                served.context("controlled peer did not answer the hello")?;
                let error = match connect {
                    Ok(_) => anyhow::bail!("mismatched helper version was accepted"),
                    Err(error) => error,
                };
                ensure!(
                    is_protocol_error(&error),
                    "unexpected helper-version error: {error}"
                );
                anyhow::Ok(())
            };
            run_with_deadline(STAGE_TIMEOUT, body).await
        };
        let settled = settle_manual_connection(&owner, handle).await;
        combine(outcome, settled)?;
    }

    // 正常协商后单向 shutdown，不等待远端确认；关闭与断连由场景 owner 统一收尾。
    let mut scene = Scene::open().await?;
    let outcome = {
        let SceneParts { client, peer, .. } = scene.parts();
        run_with_deadline(STAGE_TIMEOUT, async move {
            client.request_shutdown().await?;
            let request = peer
                .wait_for_control_request(Duration::from_secs(5))
                .await?;
            ensure!(
                matches!(request, RemoteRequest::Shutdown),
                "expected shutdown"
            );
            Ok(())
        })
        .await
    };
    scene.finish(outcome).await?;
    println!(
        "handshake: helper_rejection=rejected helper_version_mismatch=rejected shutdown=accepted close=disconnected"
    );
    Ok(())
}

fn is_protocol_error(error: &RemoteClientError) -> bool {
    match error {
        RemoteClientError::Remote {
            code: RemoteErrorCode::ProtocolMismatch,
            ..
        } => true,
        // 协议失败由 typed 变体本身表达；不去匹配生产错误文案（文案属于生产实现细节，
        // 会随 Hello 校验项变化），否则验收会在合法改文案时误判。
        RemoteClientError::Protocol(_) => true,
        // 传输层上下文保留第一因：协议拒绝被包在 Context 里时仍然是协议拒绝。
        RemoteClientError::Context { source, .. } => is_protocol_error(source),
        RemoteClientError::ManagerClosing
        | RemoteClientError::Disconnected
        | RemoteClientError::Cancelled
        | RemoteClientError::AuthenticationFailed(_)
        | RemoteClientError::Remote { .. }
        | RemoteClientError::Io { .. }
        | RemoteClientError::Task { .. } => false,
    }
}

/// 受控 peer 广告的 FD 预算：足够 511 条目录流单独吃满流容量，不会先撞 FD。
fn controlled_limits() -> RemoteResourceLimits {
    RemoteResourceLimits {
        operation_fds: 4096,
        workspace_fds: 512,
        costs: controlled_costs(),
    }
}

/// 与真实 helper 一致的 FD 成本集合（消费者只读 peer 广告，不复制判定逻辑）。
fn controlled_costs() -> RemoteResourceCosts {
    RemoteResourceCosts {
        workspace_open: 3,
        workspace_retained: 1,
        metadata: 4,
        directory: 3,
        read_file: 3,
        write_file: 4,
        copy_file: 5,
        spawn: 15,
    }
}

fn hello(protocol_version: u32) -> RemoteHello {
    hello_with(protocol_version, controlled_limits())
}

fn hello_with(protocol_version: u32, resources: RemoteResourceLimits) -> RemoteHello {
    RemoteHello {
        protocol_version,
        helper_version: CONTROLLED_HELPER.into(),
        os: "linux".into(),
        architecture: "x86_64".into(),
        capabilities: vec![
            RemoteCapability::DirectoryBrowse,
            RemoteCapability::WorkspaceFiles,
            RemoteCapability::ObservableExec,
        ],
        shell: RemoteShellDescriptor {
            dialect: RemoteShellDialect::Bash,
            path: "/bin/bash".into(),
        },
        resources,
    }
}

fn directory_names(count: usize) -> Vec<String> {
    (0..count)
        .map(|index| format!("entry-{index:04}-{}", "x".repeat(120)))
        .collect()
}

fn stat_request() -> RemotePathRequest {
    RemotePathRequest {
        workspace_id: WORKSPACE.into(),
        path: ".".into(),
    }
}

fn dot_stat() -> RemoteFileStat {
    RemoteFileStat {
        path: ".".into(),
        is_file: false,
        is_directory: true,
        len: None,
        readonly: true,
        modified_at: Some(1),
    }
}

fn spawn_request(process_id: &str) -> RemoteSpawnRequest {
    RemoteSpawnRequest {
        process_id: process_id.into(),
        workspace_id: WORKSPACE.into(),
        command: "synthetic".into(),
        cwd: ".".into(),
        environment: Default::default(),
        capture: RemoteCapture::None,
    }
}

fn write_request(total_len: u64) -> RemoteWriteRequest {
    RemoteWriteRequest {
        target: RemotePathRequest {
            workspace_id: WORKSPACE.into(),
            path: "upload.bin".into(),
        },
        mode: RemoteWriteMode::Create,
        total_len,
    }
}

fn upload_payload() -> Vec<u8> {
    (0..(DATA_CHUNK_BYTES * 3))
        .map(|index| index as u8)
        .collect()
}

/// 在同一个等待里推进请求 future 与 peer 的接入，直到操作流真的到达。
///
/// 请求 future 只有被 poll 才会租约、开流并写出请求，因此把它和 `accept_operation`
/// 放进同一个 `select!`：先就绪的一侧直接决定结果，不靠固定次数 poll、协作让出或
/// 零超时探测来“凑”出顺序。操作流到达说明请求已在线上，调用方此后可以安全取消。
///
/// 请求先结束时区分两种结论：`Err(error)` 是真实失败原因，作为 `anyhow` 的 source
/// 原样上抛并只追加“未等到操作流”的上下文；只有意外的 `Ok(_)` 才是时序错误，
/// 此时不格式化返回值（`T` 不一定可 `Debug`），也不伪造原因。
async fn drive_until_accepted<F, T, E>(
    peer: &mut Peer,
    future: &mut std::pin::Pin<Box<F>>,
) -> anyhow::Result<StreamPeer>
where
    F: std::future::Future<Output = std::result::Result<T, E>>,
    E: std::error::Error + Send + Sync + 'static,
{
    tokio::time::timeout(STAGE_TIMEOUT, async {
        tokio::select! {
            accepted = peer.accept_operation() => accepted,
            // 请求先结束：真实 Err 作为 source 原样上抛，只追加“未等到操作流”的上下文；
            // 只有意外的 Ok 才是时序错误，且不格式化返回值（`T` 不一定可 `Debug`）。
            settled = future.as_mut() => match settled {
                Err(error) => Err(anyhow::Error::new(error).context(
                    "the request failed before its operation stream reached the peer",
                )),
                Ok(_) => Err(anyhow::anyhow!(
                    "the request completed before its operation stream reached the peer"
                )),
            },
        }
    })
    .await
    .context("no operation stream reached the peer before the stage deadline")?
}

/// 一次 unary stat：peer 服务与客户端请求必须并发推进。
async fn stat_once(
    client: RemoteClient,
    peer: &mut Peer,
    tasks: &mut TaskOwner,
) -> anyhow::Result<RemoteResponse> {
    let task = spawn_owned(tasks, async move {
        client.request(RemoteRequest::Stat(stat_request())).await
    });
    let mut operation = peer.accept_operation().await?;
    expect_request(&mut operation, "stat", |request| {
        matches!(request, RemoteRequest::Stat(_))
    })
    .await?;
    operation
        .send(
            RemoteMessage::Response(RemoteResponse::Stat(dot_stat())),
            &[],
        )
        .await?;
    drop(operation);
    Ok(task.await.context("stat task was dropped")??)
}

/// 一次完整 exec：启动、stdin 关闭、输出与退出各阶段都核对。
async fn exec_once(
    client: RemoteClient,
    peer: &mut Peer,
    process_id: &str,
    stdout: &[u8],
    exit_code: i32,
    tasks: &mut TaskOwner,
) -> anyhow::Result<CommandExit> {
    let request = spawn_request(process_id);
    let task = spawn_owned(tasks, async move { client.spawn_process(request).await });
    let mut operation = peer.accept_operation().await?;
    expect_request(&mut operation, "spawn", |request| {
        matches!(request, RemoteRequest::Spawn(_))
    })
    .await?;
    operation
        .send(
            RemoteMessage::Response(RemoteResponse::ProcessSpawned {
                process_id: process_id.into(),
            }),
            &[],
        )
        .await?;
    let mut command = task.await.context("spawn task was dropped")??;
    drop(command.take_stdin());
    let record = operation.read().await?;
    ensure!(
        matches!(record.message, RemoteMessage::StdinClosed),
        "client must close stdin before exit, got {:?}",
        record.message
    );
    let mut out = command
        .take_stdout()
        .context("process must expose stdout")?;
    if !stdout.is_empty() {
        operation
            .send(
                RemoteMessage::Event(RemoteEvent::ProcessOutput(RemoteProcessOutput {
                    process_id: process_id.into(),
                    sequence: 1,
                    stream: RemoteOutputStream::Stdout,
                })),
                stdout,
            )
            .await?;
    }
    operation
        .send(
            RemoteMessage::Event(RemoteEvent::ProcessExit(RemoteProcessExit {
                process_id: process_id.into(),
                exit_code: Some(exit_code),
                signal: None,
                failure: None,
                capture: None,
            })),
            &[],
        )
        .await?;
    drop(operation);
    let mut received = Vec::new();
    out.read_to_end(&mut received).await?;
    ensure!(
        received == stdout,
        "process output mismatch: {} bytes",
        received.len()
    );
    command.wait().await.map_err(anyhow::Error::msg)
}

/// 场景 owner：连接、受控 peer 与本地任务集合都在 deadline body 之外创建并持有。
///
/// body 只借用它们；超时只丢弃 body future，随后统一执行：取消并 join 本地任务 → 关闭并等待
/// 物理连接 owner → join 控制任务终态。绝不依赖 Drop 触发取消来宣称完成。
struct Scene {
    client: RemoteClient,
    peer: Peer,
    tasks: TaskOwner,
}

impl Scene {
    async fn open() -> anyhow::Result<Self> {
        Self::open_with(hello(REMOTE_PROTOCOL_VERSION)).await
    }

    /// 用指定 Hello（含 FD 预算）建立受控 peer；预算场景用它声明受限能力。
    async fn open_with(hello: RemoteHello) -> anyhow::Result<Self> {
        let (client, peer) = connect_pair(hello).await?;
        Ok(Self {
            client,
            peer,
            tasks: TaskOwner::new(),
        })
    }

    /// 同时借用连接、受控 peer 与本地任务集合。
    ///
    /// body 只能通过这些借用访问场景资源，因此超时丢弃 body 之后 owner 仍完整可用。
    fn parts(&mut self) -> SceneParts<'_> {
        SceneParts {
            client: &self.client,
            peer: &mut self.peer,
            tasks: &mut self.tasks,
        }
    }

    async fn finish(self, outcome: anyhow::Result<()>) -> anyhow::Result<()> {
        let Self {
            mut tasks,
            client,
            peer,
        } = self;
        let tasks_cleanup = tasks.shutdown().await;
        let close = async {
            client.close().await?;
            anyhow::ensure!(
                client.is_disconnected(),
                "closed client still reports connected"
            );
            tokio::time::timeout(Duration::from_secs(5), client.wait_disconnected())
                .await
                .context("client close did not settle")?;
            anyhow::Ok(())
        }
        .await;
        let peer_cleanup = peer.shutdown(Duration::from_secs(10)).await;
        let mut failures: Vec<String> = Vec::new();
        if let Err(error) = &tasks_cleanup {
            failures.push(format!("tasks: {error:#}"));
        }
        if let Err(error) = &close {
            failures.push(format!("client: {error:#}"));
        }
        if let Err(error) = &peer_cleanup {
            failures.push(format!("peer: {error:#}"));
        }
        match (outcome, failures.is_empty()) {
            (Ok(()), true) => Ok(()),
            (Err(error), true) => Err(error),
            (Ok(()), false) => anyhow::bail!("scene cleanup failed: {}", failures.join("; ")),
            (Err(error), false) => Err(error.context(format!(
                "scene cleanup also failed: {}",
                failures.join("; ")
            ))),
        }
    }
}

/// 场景资源的临时借用集合：由 `Scene::parts` 产生，body 结束时借用随之释放。
struct SceneParts<'a> {
    client: &'a RemoteClient,
    peer: &'a mut Peer,
    tasks: &'a mut TaskOwner,
}

/// 交给场景 owner 的派生任务：结果经 oneshot 交给 body，任务本身由 owner 取消并 join。
///
/// body 取消或超时后结果无处可去：此时任务把未来的**真实失败**交回 owner，
/// 使清理阶段仍报告该错误，而不是把“无人接收”当成任务成功。
fn spawn_owned<T, E, F>(
    tasks: &mut TaskOwner,
    future: F,
) -> tokio::sync::oneshot::Receiver<std::result::Result<T, E>>
where
    T: Send + 'static,
    E: Into<anyhow::Error> + Send + 'static,
    F: std::future::Future<Output = std::result::Result<T, E>> + Send + 'static,
{
    let (sender, receiver) = tokio::sync::oneshot::channel();
    tasks.spawn(async move {
        let output = future.await;
        match sender.send(output) {
            // body 已消费结果：成功与失败都由 body 报告。
            Ok(()) => anyhow::Ok(()),
            // body 已取消：成功结果无需再报告，真实失败必须归档到 owner。
            Err(Ok(_)) => anyhow::Ok(()),
            Err(Err(error)) => Err(error.into()),
        }
    });
    receiver
}

/// 启动裁决阶段：受控 peer 的控制处理器据此判定 Terminate 是否越过未发布的裁决。
#[derive(Clone, Copy, Default, PartialEq, Eq, Debug)]
enum StartupPhase {
    /// 未开启判定：该连接上的 Terminate 按普通控制消息处理。
    #[default]
    Unenforced,
    /// 启动已提交、裁决尚未发布：此刻出现 Terminate 必须立即失败。
    AwaitingDecision,
    /// 启动裁决已发布：此后出现的 Terminate 属于预期收束。
    Decided,
}

/// 与受控 peer 的控制处理器共享的启动裁决门。
#[derive(Clone, Default)]
struct StartupGate {
    phase: Arc<Mutex<StartupPhase>>,
}

impl StartupGate {
    /// 只读快照；持有者 panic 也只影响锁的毒性标记，阶段值本身仍然可读。
    fn phase(&self) -> StartupPhase {
        match self.phase.lock() {
            Ok(guard) => *guard,
            Err(poisoned) => *poisoned.into_inner(),
        }
    }

    fn set(&self, phase: StartupPhase) {
        match self.phase.lock() {
            Ok(mut guard) => *guard = phase,
            Err(poisoned) => *poisoned.into_inner() = phase,
        }
    }
}

/// 受控 peer 的单条操作流：用生产记录分帧读写。
struct StreamPeer {
    reader: RecordReader<ReadHalf<RemoteStream>>,
    writer: RecordWriter<WriteHalf<RemoteStream>>,
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
            .context("operation stream ended without a record")
    }

    async fn send(&mut self, message: RemoteMessage, body: &[u8]) -> anyhow::Result<()> {
        self.writer.send(&message, body).await?;
        Ok(())
    }
}

struct Peer {
    _owner: ConnectionOwner,
    _handle: ConnectionHandle,
    control_task: Option<JoinHandle<anyhow::Result<()>>>,
    incoming: IncomingStreams,
    control_requests: mpsc::Receiver<RemoteRequest>,
    startup: StartupGate,
}

impl Peer {
    /// 与受控 peer 控制处理器共享的启动裁决门。
    fn startup_gate(&self) -> StartupGate {
        self.startup.clone()
    }

    async fn accept_operation(&mut self) -> anyhow::Result<StreamPeer> {
        let stream = self
            .incoming
            .accept()
            .await?
            .context("connection ended before the operation stream")?;
        Ok(StreamPeer::new(stream))
    }

    async fn next_control_request(&mut self) -> Option<RemoteRequest> {
        self.control_requests.recv().await
    }

    /// 只查看此刻已送达的控制消息，用于确定时序检查点（不是时间窗口）。
    fn try_next_control_request(&mut self) -> Option<RemoteRequest> {
        self.control_requests.try_recv().ok()
    }

    /// 收尾：关闭并等待连接 owner、再 join 控制任务终态；任何失败都传播。
    async fn shutdown(mut self, deadline: Duration) -> anyhow::Result<()> {
        let mut failures: Vec<String> = Vec::new();
        match self._owner.close().await {
            Ok(()) | Err(TransportError::Closed) => {}
            Err(error) => failures.push(format!("owner close: {error}")),
        }
        match self._owner.wait_closed().await {
            Ok(()) | Err(TransportError::Closed) => {}
            Err(error) => failures.push(format!("owner wait_closed: {error}")),
        }
        if let Some(mut task) = self.control_task.take() {
            match tokio::time::timeout(deadline, &mut task).await {
                Ok(joined) => match joined {
                    Ok(Ok(())) => {}
                    Ok(Err(error)) => failures.push(format!("control: {error:#}")),
                    Err(error) => failures.push(format!("control join: {error}")),
                },
                Err(_) => {
                    task.abort();
                    let _ = task.await;
                    failures.push("control task did not end before the deadline".to_string());
                }
            }
        }
        if failures.is_empty() {
            Ok(())
        } else {
            anyhow::bail!("peer cleanup failed: {}", failures.join("; "))
        }
    }

    async fn wait_for_control_request(
        &mut self,
        deadline: Duration,
    ) -> anyhow::Result<RemoteRequest> {
        tokio::time::timeout(deadline, self.next_control_request())
            .await
            .context("expected control request did not arrive")?
            .context("control stream ended before the expected request")
    }

    /// 心跳应答成功必须伴随对端真的收到 Heartbeat，而不是任意控制消息。
    ///
    /// `allowed_terminate` 只放行本场景已声明的进程终止请求，其他方法一律失败。
    async fn expect_heartbeat_with(&mut self, allowed_terminate: &[&str]) -> anyhow::Result<()> {
        loop {
            let request = self
                .wait_for_control_request(Duration::from_secs(5))
                .await?;
            match request {
                RemoteRequest::Heartbeat => return Ok(()),
                RemoteRequest::Terminate { ref process_id }
                    if allowed_terminate.contains(&process_id.as_str()) =>
                {
                    continue;
                }
                other => anyhow::bail!("expected heartbeat on the control stream, got {other:?}"),
            }
        }
    }

    async fn expect_heartbeat(&mut self) -> anyhow::Result<()> {
        self.expect_heartbeat_with(&[]).await
    }

    /// 等待指定 workspace 的 CloseWorkspace；期间允许心跳，其他控制消息都视为失败。
    async fn expect_close_workspace(&mut self, expected: &str) -> anyhow::Result<()> {
        loop {
            let request = self
                .wait_for_control_request(Duration::from_secs(5))
                .await?;
            match request {
                RemoteRequest::Heartbeat => continue,
                RemoteRequest::CloseWorkspace { workspace_id } => {
                    ensure!(
                        workspace_id == expected,
                        "closeWorkspace for {workspace_id} (expected {expected})"
                    );
                    return Ok(());
                }
                other => anyhow::bail!(
                    "unexpected control request while waiting for closeWorkspace: {other:?}"
                ),
            }
        }
    }

    /// 等待属于该进程的 Terminate；期间允许心跳，其他控制消息都视为失败。
    async fn expect_terminate(&mut self, process_id: &str) -> anyhow::Result<()> {
        loop {
            let request = self
                .wait_for_control_request(Duration::from_secs(5))
                .await?;
            match request {
                RemoteRequest::Heartbeat => continue,
                RemoteRequest::Terminate { process_id: ref id } if id.as_str() == process_id => {
                    return Ok(());
                }
                other => anyhow::bail!(
                    "expected terminate for {process_id} on the control stream, got {other:?}"
                ),
            }
        }
    }
}

async fn serve_control(
    mut control: StreamPeer,
    requests: mpsc::Sender<RemoteRequest>,
    startup: StartupGate,
) -> anyhow::Result<()> {
    loop {
        let record = match control.reader.read().await {
            Ok(Some(record)) => record,
            // 干净 EOF 是控制流正常收束。
            Ok(None) => return Ok(()),
            // 对端关闭连接后控制流以 Closed/Cancelled 结束是预期的收束；其他读错误是真实失败。
            Err(TransportError::Closed | TransportError::Cancelled) => return Ok(()),
            Err(error) => anyhow::bail!("control stream read failed: {error}"),
        };
        let RemoteMessage::Request(request) = record.message else {
            anyhow::bail!("control stream received a non-request record");
        };
        let shutdown = matches!(request, RemoteRequest::Shutdown);
        // 启动裁决门：裁决发布前出现 Terminate 说明它越过了未确认的启动结果，必须立即失败，
        // 而不是留给调用方在某个时间点“没看到消息”来推断。
        match &request {
            RemoteRequest::Terminate { process_id }
                if startup.phase() == StartupPhase::AwaitingDecision =>
            {
                anyhow::bail!(
                    "terminate for {process_id} overtook the unacknowledged startup decision"
                );
            }
            _ => {}
        }
        match &request {
            RemoteRequest::Shutdown => {}
            RemoteRequest::Heartbeat
            | RemoteRequest::Terminate { .. }
            | RemoteRequest::CloseWorkspace { .. } => {
                control
                    .send(RemoteMessage::Response(RemoteResponse::Ack), &[])
                    .await?;
            }
            other => anyhow::bail!("unexpected controlled-peer control request: {other:?}"),
        }
        // 观察者必须收到每条控制事务；通道关闭是明确的验收失败。
        if requests.send(request).await.is_err() {
            anyhow::bail!("control observer closed before receiving the request");
        }
        if shutdown {
            return Ok(());
        }
    }
}

/// 未发布的受控 peer：握手失败时把连接 owner 交回调用方，避免用 Drop 取消代替显式收尾。
struct PeerStartupFailure {
    error: anyhow::Error,
    owner: ConnectionOwner,
    handle: ConnectionHandle,
    incoming: IncomingStreams,
}

/// 完成控制流握手：accept 控制流、校验版本、发送 hello。
async fn prepare_peer(
    incoming: &mut IncomingStreams,
    hello: RemoteHello,
) -> anyhow::Result<StreamPeer> {
    let stream = incoming
        .accept()
        .await?
        .context("peer never opened the control stream")?;
    let mut control = StreamPeer::new(stream);
    let record = control.read().await?;
    let RemoteMessage::Request(RemoteRequest::Hello { protocol_version }) = record.message else {
        anyhow::bail!("first control record must be Hello");
    };
    ensure!(
        protocol_version == REMOTE_PROTOCOL_VERSION,
        "client announced protocol {protocol_version}"
    );
    control
        .send(RemoteMessage::Response(RemoteResponse::Hello(hello)), &[])
        .await?;
    Ok(control)
}

/// 受控 peer 的握手：成功时把 owner/handle/incoming 装进 `Peer`，失败时原样交回调用方。
async fn peer_handshake(
    owner: ConnectionOwner,
    handle: ConnectionHandle,
    mut incoming: IncomingStreams,
    hello: RemoteHello,
    startup: StartupGate,
) -> std::result::Result<Peer, PeerStartupFailure> {
    let control = match prepare_peer(&mut incoming, hello).await {
        Ok(control) => control,
        Err(error) => {
            return Err(PeerStartupFailure {
                error,
                owner,
                handle,
                incoming,
            });
        }
    };
    let (requests, control_requests) = mpsc::channel(CONTROL_REQUEST_BUFFER);
    let control_task = tokio::spawn(serve_control(control, requests, startup.clone()));
    Ok(Peer {
        _owner: owner,
        _handle: handle,
        control_task: Some(control_task),
        incoming,
        control_requests,
        startup,
    })
}

/// 显式收束未发布的受控 peer：先放弃入站流，再关闭 owner 并等待驱动任务真实结束。
async fn settle_peer_startup(
    owner: ConnectionOwner,
    handle: ConnectionHandle,
    incoming: IncomingStreams,
) -> anyhow::Result<()> {
    drop(incoming);
    drop(handle);
    settle_owner(&owner).await
}

/// 关闭连接 owner 并等待驱动任务结束；`Closed` 表示连接已经收束。
async fn settle_owner(owner: &ConnectionOwner) -> anyhow::Result<()> {
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

/// 手工构造对端的统一收束：显式关闭并等待真实 join，失败合并报告。
async fn settle_manual_connection(
    owner: &ConnectionOwner,
    handle: ConnectionHandle,
) -> anyhow::Result<()> {
    drop(handle);
    settle_owner(owner).await
}

/// 显式关闭客户端并等待断连；已断连本身是正常收束。
async fn close_client(client: RemoteClient) -> anyhow::Result<()> {
    let close = match client.close().await {
        Ok(()) | Err(RemoteClientError::ManagerClosing | RemoteClientError::Disconnected) => Ok(()),
        Err(error) => Err(anyhow::anyhow!("client close failed: {error}")),
    };
    let settled =
        match tokio::time::timeout(Duration::from_secs(5), client.wait_disconnected()).await {
            Ok(()) => Ok(()),
            Err(_) => Err(anyhow::anyhow!("client close did not settle")),
        };
    combine(close, settled)
}

/// 把清理失败合并进主错误：清理失败永远不覆盖原始失败。
fn merge_context(
    primary: anyhow::Error,
    label: &str,
    cleanup: anyhow::Result<()>,
) -> anyhow::Error {
    match cleanup {
        Ok(()) => primary,
        Err(error) => primary.context(format!("{label} also failed: {error:#}")),
    }
}

async fn connect_pair(hello: RemoteHello) -> anyhow::Result<(RemoteClient, Peer)> {
    let (server, client_io) = tokio::io::duplex(TRANSPORT_BUFFER);
    let (server_read, server_write) = tokio::io::split(server);
    let (client_read, client_write) = tokio::io::split(client_io);
    let (owner, handle, incoming) = ConnectionOwner::start(server_read, server_write, Role::Server);
    let startup = StartupGate::default();
    let handshake = peer_handshake(owner, handle, incoming, hello, startup);
    let (client, peer) = tokio::join!(RemoteClient::connect(client_read, client_write), handshake);
    // 四种组合都显式收束已建立的一半：绝不用 Drop 取消冒充完成。
    match (client, peer) {
        (Ok(client), Ok(peer)) => Ok((client, peer)),
        (Ok(client), Err(failure)) => {
            let PeerStartupFailure {
                error,
                owner,
                handle,
                incoming,
            } = failure;
            let primary = error.context("controlled peer handshake failed");
            let peer_settled = settle_peer_startup(owner, handle, incoming).await;
            let client_settled = close_client(client).await;
            Err(merge_context(
                merge_context(primary, "controlled peer startup cleanup", peer_settled),
                "client close",
                client_settled,
            ))
        }
        (Err(client_error), Ok(peer)) => {
            let primary = anyhow::Error::new(client_error).context("client connect failed");
            let settled = peer.shutdown(Duration::from_secs(10)).await;
            Err(merge_context(primary, "controlled peer shutdown", settled))
        }
        (Err(client_error), Err(failure)) => {
            let PeerStartupFailure {
                error,
                owner,
                handle,
                incoming,
            } = failure;
            let primary = anyhow::Error::new(client_error)
                .context(format!("controlled peer handshake also failed: {error:#}"));
            let settled = settle_peer_startup(owner, handle, incoming).await;
            Err(merge_context(
                primary,
                "controlled peer startup cleanup",
                settled,
            ))
        }
    }
}

async fn expect_request<F>(
    operation: &mut StreamPeer,
    name: &str,
    matches_request: F,
) -> anyhow::Result<()>
where
    F: FnOnce(&RemoteRequest) -> bool,
{
    let record = operation.read().await?;
    let RemoteMessage::Request(request) = &record.message else {
        anyhow::bail!(
            "{name}: operation did not start with a request: {:?}",
            record.message
        );
    };
    ensure!(
        matches_request(request),
        "{name}: unexpected request {request:?}"
    );
    Ok(())
}
