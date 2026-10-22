//! 远端进程流：启动裁决、全双工输入、逐进程输出序列与最终退出/捕获结算。
//!
//! 进程流是一条独占的双向子流：客户端发送 `stdin` / `stdinClosed`，helper 发送
//! `processOutput`（每进程从 1 单调）与唯一的 `processExit`。终止请求走 control，实际退出与
//! capture 仍从本流结算；取消只停止等待业务消费者并继续排空到真实退出。

use std::io;

use pl_protocol::remote::{
    RemoteCapture, RemoteEvent, RemoteMessage, RemoteOutputStream, RemoteProcessExit,
    RemoteRequest, RemoteResponse, RemoteSpawnRequest,
};
use pl_remote_helper::remote_transport::{
    DATA_CHUNK_BYTES, RecordReader, RemoteRecord, RemoteStream,
};
use tokio::io::{AsyncReadExt, AsyncWriteExt, DuplexStream, ReadHalf};
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

use crate::command::{
    CommandCancellation, CommandCaptureReceipt, CommandExit, CommandIo, ManagedCommand,
};

use super::super::error::RemoteClientError;
use super::RemoteClient;
use super::session::OperationStream;
use super::session::{
    StreamLease, StreamOwnership, message_kind, read_record, response_kind, response_record,
    send_record,
};

/// One local read of stdin data handed to the remote process.
const INPUT_CHUNK_BYTES: usize = 8 * 1024;
/// Bound of each local pipe between the command lease and this supervisor.
const PIPE_BYTES: usize = 64 * 1024;

struct ProcessJob {
    lease: StreamLease,
    request: RemoteSpawnRequest,
    stdin: DuplexStream,
    stdout: DuplexStream,
    stderr: DuplexStream,
    started: oneshot::Sender<Result<(), RemoteClientError>>,
}

/// Spawns one remote process and transfers supervision into a command lease.
pub(super) async fn spawn(
    lease: StreamLease,
    request: RemoteSpawnRequest,
) -> Result<ManagedCommand, RemoteClientError> {
    let (stdin, input) = tokio::io::duplex(PIPE_BYTES);
    let (stdout, output) = tokio::io::duplex(PIPE_BYTES);
    let (stderr, errors) = tokio::io::duplex(PIPE_BYTES);
    let (started, startup) = oneshot::channel();
    let client = lease.client().clone();
    if client.inner.tasks.is_closed() {
        // The connection already stopped admitting supervised work; never detach a task that no
        // owner would drain.
        return Err(RemoteClientError::Disconnected);
    }
    let job = ProcessJob {
        lease,
        request,
        stdin: input,
        stdout: output,
        stderr: errors,
        started,
    };
    let command = ManagedCommand::new(
        None,
        CommandIo {
            stdin: Some(Box::pin(stdin)),
            stdout: Some(Box::pin(stdout)),
            stderr: Some(Box::pin(stderr)),
        },
        move |cancellation| {
            // The tracked supervisor is registered synchronously while the command lease is
            // constructed; the returned future only awaits that owner. Startup therefore never
            // waits on a task that would only be spawned once the wait future is polled.
            let tasks = job.lease.client().inner.tasks.clone();
            let supervisor = tokio::spawn(tasks.track_future(supervise(job, cancellation)));
            async move {
                match supervisor.await {
                    Ok(result) => result,
                    Err(error) => Err(format!("remote process supervisor failed: {error}")),
                }
            }
        },
    );
    startup
        .await
        .unwrap_or(Err(RemoteClientError::Disconnected))?;
    Ok(command)
}

async fn supervise(
    job: ProcessJob,
    cancellation: CommandCancellation,
) -> Result<CommandExit, String> {
    let ProcessJob {
        lease,
        request,
        stdin,
        stdout,
        stderr,
        started,
    } = job;
    let process_id = request.process_id.clone();
    let expects_capture = matches!(&request.capture, RemoteCapture::File { .. });
    let client = lease.client().clone();

    let stream = match begin(lease, request).await {
        Ok(stream) => stream,
        Err(error) => {
            let reason = error.to_string();
            drop(stdin);
            drop(stdout);
            drop(stderr);
            let _ = started.send(Err(error));
            return Err(reason);
        }
    };
    let _ = started.send(Ok(()));

    let parts = stream.into_parts();
    let (exit_sender, mut exit) = oneshot::channel();
    let discard = CancellationToken::new();
    let pump = tokio::spawn(pump_output(OutputPump {
        reader: parts.reader,
        stdout,
        stderr,
        discard: discard.clone(),
        process_id: process_id.clone(),
        client: client.clone(),
        ownership: parts.ownership,
        exit: exit_sender,
    }));

    let mut writer = parts.writer;
    let mut input = stdin;
    let mut buffer = vec![0_u8; INPUT_CHUNK_BYTES];
    let mut input_open = true;
    let mut terminated = false;
    let mut failure: Option<String> = None;

    let exit_result = loop {
        tokio::select! {
            biased;
            result = &mut exit => {
                break result.unwrap_or_else(|_| {
                    Err(RemoteClientError::protocol(
                        "remote process stream ended without an exit record",
                    ))
                });
            }
            () = cancellation.cancelled(), if !terminated => {
                terminated = true;
                // Stop waiting for a business consumer but keep the stream owned until the real
                // exit and capture settlement arrive from the helper.
                discard.cancel();
                input_open = false;
                if let Err(error) = terminate(&client, &process_id).await {
                    failure.get_or_insert(error);
                }
            }
            () = client.wait_disconnected() => {
                // The helper reclaims the process when the stream is lost; there is no further
                // exit or capture to settle on this connection.
                discard.cancel();
                failure.get_or_insert_with(|| {
                    "remote connection closed while the process was running".to_string()
                });
                break Err(RemoteClientError::Disconnected);
            }
            read = input.read(&mut buffer), if input_open => {
                match read {
                    Ok(0) => {
                        input_open = false;
                        if let Err(error) = send_record(
                            &mut writer,
                            &client,
                            &RemoteMessage::StdinClosed,
                            &[],
                            "process stdin",
                        )
                        .await
                        {
                            failure.get_or_insert_with(|| error.to_string());
                            // A failed close-input record is as fatal as a failed stdin chunk:
                            // terminate through control and keep draining to the real exit or the
                            // connection's terminal state instead of waiting for an exit that may
                            // never arrive.
                            if !terminated {
                                terminated = true;
                                discard.cancel();
                                if let Err(error) = terminate(&client, &process_id).await {
                                    failure.get_or_insert(error);
                                }
                            }
                        }
                    }
                    Ok(count) => {
                        if let Err(error) = send_record(
                            &mut writer,
                            &client,
                            &RemoteMessage::Stdin,
                            &buffer[..count],
                            "process stdin",
                        )
                        .await
                        {
                            failure.get_or_insert_with(|| error.to_string());
                            input_open = false;
                            if !terminated {
                                terminated = true;
                                discard.cancel();
                                if let Err(error) = terminate(&client, &process_id).await {
                                    failure.get_or_insert(error);
                                }
                            }
                        }
                    }
                    Err(error) => {
                        failure.get_or_insert_with(|| format!("read local process stdin: {error}"));
                        input_open = false;
                        if !terminated {
                            terminated = true;
                            discard.cancel();
                            if let Err(error) = terminate(&client, &process_id).await {
                                failure.get_or_insert(error);
                            }
                        }
                    }
                }
            }
        }
    };

    drop(input);
    drop(writer);
    if let Err(error) = pump.await {
        return Err(format!("remote process output task failed: {error}"));
    }

    if let Some(error) = failure {
        return Err(error);
    }
    let exit = exit_result.map_err(|error| error.to_string())?;
    if exit.process_id != process_id {
        return Err(format!(
            "remote exit was reported for process '{}' instead of '{process_id}'",
            exit.process_id
        ));
    }
    if let Some(error) = &exit.failure {
        return Err(format!(
            "remote process failed ({:?}): {}",
            error.code, error.message
        ));
    }
    if exit.capture.is_some() != expects_capture {
        return Err("capture receipt does not match the spawn policy".to_string());
    }
    Ok(CommandExit {
        exit_code: exit.exit_code,
        capture: exit.capture.map(|receipt| CommandCaptureReceipt {
            limit_bytes: receipt.limit_bytes,
            committed_len: receipt.charged_bytes,
            charged_bytes: receipt.charged_bytes,
            refused_bytes: receipt.refused_bytes,
        }),
    })
}

async fn begin(
    lease: StreamLease,
    request: RemoteSpawnRequest,
) -> Result<OperationStream, RemoteClientError> {
    let process_id = request.process_id.clone();
    let mut stream = lease.open_stream().await?;
    stream.send_request(RemoteRequest::Spawn(request)).await?;
    match response_record(stream.read().await?, "spawn")? {
        RemoteResponse::ProcessSpawned {
            process_id: spawned,
        } if spawned == process_id => Ok(stream),
        RemoteResponse::ProcessSpawned {
            process_id: spawned,
        } => Err(RemoteClientError::protocol(format!(
            "helper started process '{spawned}' instead of '{process_id}'"
        ))),
        response => Err(RemoteClientError::protocol(format!(
            "expected a process start receipt, received {}",
            response_kind(&response)
        ))),
    }
}

async fn terminate(client: &RemoteClient, process_id: &str) -> Result<(), String> {
    // A terminate receipt only confirms the request was accepted; the exit and capture settle on
    // the process stream. The request must never be replayed transparently.
    client
        .request(RemoteRequest::Terminate {
            process_id: process_id.to_string(),
        })
        .await
        .map(|_| ())
        .map_err(|error| format!("remote terminate failed: {error}"))
}

/// Everything one process output pump owns: the receive half, both local sinks, cancellation and
/// the operation's connection/workspace/permit responsibility.
struct OutputPump {
    reader: RecordReader<ReadHalf<RemoteStream>>,
    stdout: DuplexStream,
    stderr: DuplexStream,
    discard: CancellationToken,
    process_id: String,
    client: RemoteClient,
    ownership: StreamOwnership,
    exit: oneshot::Sender<Result<RemoteProcessExit, RemoteClientError>>,
}

async fn pump_output(pump: OutputPump) {
    let OutputPump {
        mut reader,
        mut stdout,
        mut stderr,
        discard,
        process_id,
        client,
        // The operation keeps its connection, workspace lease and permit until the stream ends.
        ownership: _ownership,
        exit,
    } = pump;
    let mut sequence = 0_u64;
    let mut stdout_open = true;
    let mut stderr_open = true;
    loop {
        let record = match read_record(&mut reader, &client, "process stream").await {
            Ok(Some(record)) => record,
            Ok(None) => {
                let _ = exit.send(Err(RemoteClientError::protocol(
                    "process stream ended before the process exit",
                )));
                return;
            }
            Err(error) => {
                let _ = exit.send(Err(error));
                return;
            }
        };
        let RemoteRecord { message, body } = record;
        match message {
            RemoteMessage::Event(RemoteEvent::ProcessOutput(output)) => {
                if output.process_id != process_id {
                    let _ = exit.send(Err(RemoteClientError::protocol(format!(
                        "output for process '{}' arrived on the stream of '{process_id}'",
                        output.process_id
                    ))));
                    return;
                }
                if output.sequence <= sequence {
                    let _ = exit.send(Err(RemoteClientError::protocol(format!(
                        "process output sequence {} is not after {sequence}",
                        output.sequence
                    ))));
                    return;
                }
                sequence = output.sequence;
                if body.len() > DATA_CHUNK_BYTES {
                    let _ = exit.send(Err(RemoteClientError::protocol(format!(
                        "process output chunk of {} bytes exceeds the chunk budget",
                        body.len()
                    ))));
                    return;
                }
                if discard.is_cancelled() {
                    continue;
                }
                let written = match output.stream {
                    RemoteOutputStream::Stdout if stdout_open => {
                        // A canceled command stops waiting for its business consumer; a blocked
                        // local write must not stop the stream from reaching the real exit.
                        let result = tokio::select! {
                            biased;
                            () = discard.cancelled() => Ok(()),
                            result = stdout.write_all(&body) => result,
                        };
                        if result.is_err() {
                            stdout_open = false;
                        }
                        result
                    }
                    RemoteOutputStream::Stderr if stderr_open => {
                        let result = tokio::select! {
                            biased;
                            () = discard.cancelled() => Ok(()),
                            result = stderr.write_all(&body) => result,
                        };
                        if result.is_err() {
                            stderr_open = false;
                        }
                        result
                    }
                    // A closed local consumer only loses its own late output; the stream keeps
                    // draining so the remote process never blocks on us.
                    _ => Ok(()),
                };
                if let Err(error) = written
                    && error.kind() != io::ErrorKind::BrokenPipe
                {
                    tracing::debug!(
                        connection = client.instance(),
                        process = %process_id,
                        %error,
                        "remote process output consumer stopped"
                    );
                }
            }
            RemoteMessage::Event(RemoteEvent::ProcessExit(remote_exit)) => {
                if remote_exit.process_id != process_id {
                    let _ = exit.send(Err(RemoteClientError::protocol(format!(
                        "exit for process '{}' arrived on the stream of '{process_id}'",
                        remote_exit.process_id
                    ))));
                    return;
                }
                let _ = exit.send(Ok(remote_exit));
                return;
            }
            RemoteMessage::Response(RemoteResponse::Error(error)) => {
                let _ = exit.send(Err(RemoteClientError::remote(&error)));
                return;
            }
            other => {
                let _ = exit.send(Err(RemoteClientError::protocol(format!(
                    "unexpected {} in a process stream",
                    message_kind(&other)
                ))));
                return;
            }
        }
    }
}
