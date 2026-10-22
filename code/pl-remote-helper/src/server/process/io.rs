//! 进程流的两个方向：stdin 写入与 output 发布。
//!
//! 输出只由这条流自己的背压控制，不维护全连接计数或固定进程数上限。取消后停止向业务消费者
//! 转发，但继续排空两路输出与 capture，直到物理进程结束；stdin 在物理结束后停止等待对端，
//! 避免正常退出被输入循环拖住。

use pl_protocol::remote::{
    RemoteCaptureReceipt, RemoteError, RemoteErrorCode, RemoteEvent, RemoteMessage,
    RemoteOutputStream, RemoteProcessOutput,
};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::sync::watch;

use super::super::path::{io_error, remote_error};
use super::super::records;
use super::capture::{Acceptance, Capture};
use crate::client::{ChildStderr, ChildStdin, ChildStdout};
use crate::remote_transport::{DATA_CHUNK_BYTES, RecordReader, RecordWriter};

/// client→server 的 stdin 方向结果；失败保留原始原因。
pub(super) async fn input<R>(
    mut stdin: Option<ChildStdin>,
    mut reader: RecordReader<R>,
    cancel: &watch::Sender<bool>,
    stopped: &mut watch::Receiver<bool>,
) -> Option<RemoteError>
where
    R: AsyncRead + Unpin,
{
    let mut failure = None;
    let mut stdin_closed = false;
    loop {
        let record = tokio::select! {
            biased;
            // 物理进程已结束：不再等待对端输入，终态记录即将发布。
            _ = stopped.wait_for(|stopped| *stopped) => break,
            record = reader.read() => record,
        };
        let record = match record {
            Ok(Some(record)) => record,
            // 对端在进程仍在运行时关闭这条流：按断流语义终止并保留原因。
            Ok(None) => {
                failure.get_or_insert_with(|| {
                    remote_error(
                        RemoteErrorCode::RemoteDisconnected,
                        "process stream ended before the process exited",
                    )
                });
                cancel.send_replace(true);
                break;
            }
            // 记录损坏或物理通道失败：保留真实传输原因。
            Err(error) => {
                failure.get_or_insert_with(|| {
                    records::stream_failure("process input stream failed", error)
                });
                cancel.send_replace(true);
                break;
            }
        };
        let message = record.message;
        let body = record.body;
        match message {
            RemoteMessage::Stdin => {
                if stdin_closed {
                    failure.get_or_insert_with(|| {
                        remote_error(RemoteErrorCode::InvalidRequest, "process stdin is closed")
                    });
                    cancel.send_replace(true);
                    break;
                }
                let Some(writer) = stdin.as_mut() else {
                    failure.get_or_insert_with(|| {
                        remote_error(
                            RemoteErrorCode::InvalidRequest,
                            "process stdin is not available",
                        )
                    });
                    cancel.send_replace(true);
                    break;
                };
                let written = tokio::select! {
                    biased;
                    _ = stopped.wait_for(|stopped| *stopped) => None,
                    result = writer.write_all(&body) => Some(result),
                };
                match written {
                    // 进程已结束：剩余输入不再有机会送达。
                    None => break,
                    Some(Ok(())) => {}
                    Some(Err(error)) => {
                        failure.get_or_insert_with(|| io_error("write process stdin", error));
                        cancel.send_replace(true);
                        break;
                    }
                }
            }
            RemoteMessage::StdinClosed => {
                if !body.is_empty() {
                    failure.get_or_insert_with(|| {
                        remote_error(
                            RemoteErrorCode::InvalidRecord,
                            "stdinClosed must not carry a body",
                        )
                    });
                    cancel.send_replace(true);
                    break;
                }
                stdin = None;
                stdin_closed = true;
            }
            _ => {
                failure.get_or_insert_with(|| {
                    remote_error(
                        RemoteErrorCode::InvalidRecord,
                        "process streams accept stdin and stdinClosed input only",
                    )
                });
                cancel.send_replace(true);
                break;
            }
        }
    }
    failure
}

pub(super) struct Output<'a, W> {
    pub process_id: &'a str,
    pub stdout: Option<ChildStdout>,
    pub stderr: Option<ChildStderr>,
    pub capture: Capture,
    pub writer: &'a mut RecordWriter<W>,
    pub cancel: &'a watch::Sender<bool>,
    pub cancelled: &'a watch::Receiver<bool>,
}

pub(super) struct OutputOutcome {
    pub failure: Option<RemoteError>,
    pub receipt: Option<RemoteCaptureReceipt>,
}

pub(super) async fn output<W>(mut output: Output<'_, W>) -> OutputOutcome
where
    W: AsyncWrite + Unpin,
{
    let mut stdout_buffer = [0_u8; DATA_CHUNK_BYTES];
    let mut stderr_buffer = [0_u8; DATA_CHUNK_BYTES];
    let mut sequence = 0_u64;
    let mut failure = None;
    let mut capture_open = true;
    let mut wire_open = true;
    while output.stdout.is_some() || output.stderr.is_some() {
        if wire_open && *output.cancelled.borrow() {
            // 取消后只继续排空输出与 capture，不再等待业务消费者。
            wire_open = false;
        }
        let (stream, result) = tokio::select! {
            result = read_stdout(&mut output.stdout, &mut stdout_buffer), if output.stdout.is_some() => (RemoteOutputStream::Stdout, result),
            result = read_stderr(&mut output.stderr, &mut stderr_buffer), if output.stderr.is_some() => (RemoteOutputStream::Stderr, result),
        };
        let count = match result {
            Ok(count) => count,
            Err(error) => {
                failure.get_or_insert_with(|| io_error("read process output", error));
                output.cancel.send_replace(true);
                0
            }
        };
        if count == 0 {
            match stream {
                RemoteOutputStream::Stdout => output.stdout = None,
                RemoteOutputStream::Stderr => output.stderr = None,
            }
            continue;
        }
        let body = match stream {
            RemoteOutputStream::Stdout => &stdout_buffer[..count],
            RemoteOutputStream::Stderr => &stderr_buffer[..count],
        };
        if capture_open {
            match output.capture.append(stream, body).await {
                Ok(Acceptance::Accepted) => {}
                Ok(Acceptance::Refused) => {
                    // capture 预算已用尽：终止进程并停止转发，但仍排空两路输出。
                    output.cancel.send_replace(true);
                    wire_open = false;
                    continue;
                }
                Err(error) => {
                    failure.get_or_insert(error);
                    capture_open = false;
                    output.cancel.send_replace(true);
                }
            }
        }
        if wire_open && *output.cancelled.borrow() {
            wire_open = false;
        }
        if !wire_open {
            continue;
        }
        let Some(next) = sequence.checked_add(1) else {
            failure.get_or_insert_with(|| {
                remote_error(RemoteErrorCode::Io, "process output sequence is exhausted")
            });
            break;
        };
        sequence = next;
        if records::event_body(
            output.writer,
            RemoteEvent::ProcessOutput(RemoteProcessOutput {
                process_id: output.process_id.to_string(),
                sequence,
                stream,
            }),
            body,
        )
        .await
        .is_err()
        {
            // 写半边已不可用：停止转发，继续排空 capture 与物理退出。
            wire_open = false;
            output.cancel.send_replace(true);
        }
    }
    // 关闭捕获句柄（FD 先于进程预算归还）；正文写都已在阻塞任务里 await 完成，无需额外系统调用。
    let receipt = output.capture.finish();
    OutputOutcome { failure, receipt }
}

async fn read_stdout(
    reader: &mut Option<ChildStdout>,
    buffer: &mut [u8],
) -> std::io::Result<usize> {
    match reader {
        Some(reader) => reader.read(buffer).await,
        None => Ok(0),
    }
}

async fn read_stderr(
    reader: &mut Option<ChildStderr>,
    buffer: &mut [u8],
) -> std::io::Result<usize> {
    match reader {
        Some(reader) => reader.read(buffer).await,
        None => Ok(0),
    }
}
