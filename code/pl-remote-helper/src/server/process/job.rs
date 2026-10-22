//! 一个进程流的完整生命周期：启动裁决、全双工输入输出与唯一退出记录。
//!
//! `processSpawned` 之后这条流同时承载 client→server 的 stdin 与 server→client 的输出。
//! 物理退出、两路输出排空与 capture 计量全部收束后才发布唯一的 `processExit`；启动失败、
//! 输入错误或对端断流都保留原始失败并终止进程，不把错误吞进正常退出。
//!
//! 流阶段整体捕获 panic：IO 侧崩溃不能让 worker 脱离回收责任，本任务据此决定是否还要再等
//! 一次真实退出，并把异常记录为 helper 层面失败。

use std::panic::AssertUnwindSafe;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use futures::FutureExt;
use pl_protocol::remote::{
    RemoteErrorCode, RemoteEvent, RemoteProcessExit, RemoteResponse, RemoteShellDescriptor,
    RemoteSpawnRequest,
};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::watch;

use super::super::path::{Target, remote_error};
use super::super::records;
use super::super::resources::ResourceLease;
use super::super::tasks::BlockingTasks;
use super::{CwdCapability, ProcessRegistry, Reservation, io, resource};
use crate::client::ProcessTermination;
use crate::remote_transport::{RecordReader, RecordWriter};

pub(super) struct Job<R, W> {
    pub registry: ProcessRegistry,
    pub reservation: Reservation,
    pub shell: RemoteShellDescriptor,
    pub request: RemoteSpawnRequest,
    pub cwd: CwdCapability,
    pub capture: Option<Target>,
    pub reader: RecordReader<R>,
    pub writer: RecordWriter<W>,
    /// 连接 owner：capture 文件与所有终止阶段的阻塞调用都经它真实 join。
    pub tasks: BlockingTasks,
    /// 本进程操作的整份 FD 预算：从准入一直持有到 worker/pipes/capture/cwd 真实回收。
    pub lease: ResourceLease,
}

pub(super) async fn run<R, W>(job: Job<R, W>)
where
    R: AsyncRead + Unpin + Send,
    W: AsyncWrite + Unpin + Send,
{
    let Job {
        registry,
        reservation,
        shell,
        request,
        cwd,
        capture: capture_target,
        reader,
        mut writer,
        tasks,
        lease,
    } = job;
    // 预算与 cwd/worker/capture 句柄随 Job 存活：`ProcessSpawned` 不是终结。两路输出与物理
    // 回收结束后先显式回收这些资源（见下方终结顺序），之后才发布唯一的 `ProcessExit`。
    let process_id = reservation.process_id().to_string();
    let cancel = reservation.cancel();
    let mut cancelled = reservation.cancelled();
    // 输出侧只读观察取消；与 wait 侧共享同一份每进程信号。
    let output_cancelled = reservation.cancelled();
    // 启动准备只借用 capture 目标能力；不论成败，结束后立刻真正关闭它的 parent FD 与预算，
    // 不让这个中间能力活到进程退出记录之后。
    let started = resource::start(
        &request,
        &cwd,
        capture_target.as_ref(),
        &shell,
        &reservation,
        &tasks,
    )
    .await;
    drop(capture_target);
    let (mut worker, capture) = match started {
        Ok(prepared) => prepared,
        Err(error) => {
            // 进程从未提交：只回执启动失败，登记随 reservation 释放。
            records::fail(&mut writer, error).await;
            return;
        }
    };
    if records::respond(
        &mut writer,
        RemoteResponse::ProcessSpawned {
            process_id: process_id.clone(),
        },
    )
    .await
    .is_err()
    {
        // 对端收不到启动结果就不能拥有这个进程：立即终止并照常回收。
        cancel.send_replace(true);
    }
    let control = worker.control();
    let stdin = worker.take_stdin();
    let stdout = worker.take_stdout();
    let stderr = worker.take_stderr();
    // 物理结束信号让输入侧停止等待对端数据，正常退出不被输入循环拖住。
    let (stopped, mut finished) = watch::channel(false);
    // 物理回收是否真正完成；panic 后据此决定是否还需要再等一次退出。
    let reaped = Arc::new(AtomicBool::new(false));
    let reaped_by_wait = Arc::clone(&reaped);
    let stage = AssertUnwindSafe(async {
        let wait = async {
            // 取消意图与物理退出竞争：一次只让一个 future 借用 worker。
            let first = tokio::select! {
                biased;
                _ = cancelled.wait_for(|cancelled| *cancelled) => None,
                result = worker.wait() => Some(result),
            };
            let result = match first {
                Some(result) => result,
                None => {
                    // 取消到达：先发出终止请求，再等真实退出；`wait` 可跨取消继续观察。
                    if control.cancel().await.is_err() {
                        control.close();
                    }
                    worker.wait().await
                }
            };
            stopped.send_replace(true);
            reaped_by_wait.store(true, Ordering::Release);
            result
        };
        tokio::join!(
            wait,
            io::output(io::Output {
                process_id: &process_id,
                stdout,
                stderr,
                capture,
                writer: &mut writer,
                cancel: &cancel,
                cancelled: &output_cancelled,
            }),
            io::input(stdin, reader, &cancel, &mut finished),
        )
    });
    let outcome = stage.catch_unwind().await;
    match outcome {
        Ok((termination, output, input)) => {
            let mut failure = input.or(output.failure);
            let (exit_code, signal) = match termination {
                Ok(ProcessTermination::ExitCode(code)) => (Some(code), None),
                Ok(ProcessTermination::Signal(signal)) => (None, Some(signal)),
                Err(error) => {
                    // 物理回收没完成是 helper 层面的失败，退出前必须可见。
                    registry.record_failure(remote_error(
                        RemoteErrorCode::Io,
                        format!("process '{process_id}' cleanup failed: {error}"),
                    ));
                    failure.get_or_insert_with(|| {
                        remote_error(
                            RemoteErrorCode::Io,
                            format!("process cleanup failed: {error}"),
                        )
                    });
                    (None, None)
                }
            };
            // 终结顺序：stdio/capture 已随输出任务结束关闭，这里再显式回收进程句柄、cwd 能力与
            // 本操作的整份 FD 预算，之后才发布唯一终态。因此 client 收到 `ProcessExit` 时，本
            // 进程占用的 FD 已经真正归还，紧随其后的请求不会被刚结束的进程误拒。
            drop(control);
            drop(worker);
            drop(cwd);
            drop(lease);
            // 唯一终态记录：两路输出、capture 与物理退出都已结束。
            let _ = records::event(
                &mut writer,
                RemoteEvent::ProcessExit(RemoteProcessExit {
                    process_id,
                    exit_code,
                    signal,
                    failure,
                    capture: output.receipt,
                }),
            )
            .await;
            let _ = records::finish(&mut writer).await;
        }
        Err(_panic) => {
            // 流内容已不可信，不再发布终态记录；丢弃写半边让对端看到明确的失败。
            registry.record_failure(remote_error(
                RemoteErrorCode::Io,
                format!("process '{process_id}' stream stage panicked"),
            ));
            cancel.send_replace(true);
            if !reaped.load(Ordering::Acquire) {
                if control.cancel().await.is_err() {
                    control.close();
                }
                if let Err(error) = worker.wait().await {
                    registry.record_failure(remote_error(
                        RemoteErrorCode::Io,
                        format!("process '{process_id}' cleanup failed: {error}"),
                    ));
                }
            }
        }
    }
}
