use std::sync::Arc;

use tokio::io::AsyncReadExt;

use super::lifecycle::apply_transition;
use super::state::CaptureAcceptance;
use super::{
    CommandCaptureFailure, CommandOutputStream, CommandProcessEntry, CommandProcessTransition,
    StreamKind,
};
use crate::command::{CommandBackend, CommandCaptureStream, CommandReader};

pub(super) async fn read_stdout<B>(
    entry: Arc<CommandProcessEntry>,
    backend: Arc<B>,
    stdout: CommandReader,
) where
    B: CommandBackend,
{
    read_stream(entry, backend, stdout, StreamKind::Stdout).await;
}

pub(super) async fn read_stderr<B>(
    entry: Arc<CommandProcessEntry>,
    backend: Arc<B>,
    stderr: CommandReader,
) where
    B: CommandBackend,
{
    read_stream(entry, backend, stderr, StreamKind::Stderr).await;
}

/// Reads one command stream, accepting every chunk into the shared bounded plan.
///
/// The reader never touches the capture file: it only accepts a chunk into the operation's one plan
/// and wakes the writer task. A slow disk therefore cannot stall this stream, the other stream, or the
/// live preview; both readers keep accepting up to the shared budget while the single writer appends
/// at its own pace.
///
/// `backend` 只在接纳前估算落盘存储成本：额度按 backend 真实要落的字节计费，因此"一份输出被写进
/// 两个文件"的后端不会被低估。
async fn read_stream<R, B>(
    entry: Arc<CommandProcessEntry>,
    backend: Arc<B>,
    mut reader: R,
    stream: StreamKind,
) where
    R: tokio::io::AsyncRead + Unpin,
    B: CommandBackend,
{
    let mut buffer = [0_u8; 8192];
    loop {
        match reader.read(&mut buffer).await {
            Ok(0) => break,
            Ok(n) => {
                let chunk = &buffer[..n];
                let capture_stream = match stream {
                    StreamKind::Stdout => CommandCaptureStream::Stdout,
                    StreamKind::Stderr => CommandCaptureStream::Stderr,
                };
                // 使用启动时固定的所有权；同步计价无 I/O，接纳与发布沿用同一个共享计划。
                let acceptance = {
                    let mut state = entry.state.lock().await;
                    let storage_cost = match state.capture_ownership {
                        crate::command::CommandCaptureOwnership::Manager => backend
                            .capture_storage_cost(&entry.output_target, capture_stream, chunk),
                        crate::command::CommandCaptureOwnership::Producer => 0,
                    };
                    state.accept_capture(capture_stream, chunk, storage_cost)
                };
                match acceptance {
                    CaptureAcceptance::Accepted => {}
                    CaptureAcceptance::OutputLimitExceeded {
                        limit_bytes,
                        charged_bytes,
                        refused_bytes,
                    } => {
                        fail_capture(
                            &entry,
                            CommandCaptureFailure::OutputLimitExceeded {
                                limit_bytes,
                                charged_bytes,
                                refused_bytes,
                            },
                        )
                        .await;
                        break;
                    }
                    CaptureAcceptance::Faulted => break,
                }
                // Publish the accepted chunk to the live observer: the bounded in-memory view reflects
                // the byte immediately and never waits on the capture writer's disk.
                let revision = {
                    let mut state = entry.state.lock().await;
                    state.record_output(stream, chunk)
                };
                if let Some(observer) = &entry.output_observer {
                    observer.output_chunk(stream.into(), chunk, revision);
                }
                entry.notify.notify_waiters();
                // The accepted chunk is queued; only the single writer appends it.
                entry.capture_wake.notify_one();
            }
            Err(error) => {
                // A read failure is not a healthy end of output: the capture is truncated here, so
                // stop the process tree with the bytes already accepted and report the exact typed
                // capture failure instead of only a health note on a normal exit.
                fail_capture(
                    &entry,
                    CommandCaptureFailure::Read {
                        message: error.to_string(),
                    },
                )
                .await;
                break;
            }
        }
    }
    apply_transition(&entry, CommandProcessTransition::StreamClosed(stream)).await;
}

/// The operation's single capture writer task: appends every accepted chunk in acceptance order.
///
/// It owns the shared capture fragment for the whole operation, so stdout and stderr never append
/// concurrently and the offset the backend confirms stays consistent. A chunk accepted first is
/// written first, and once an append fails the writer stops: the failing chunk and every chunk
/// accepted before the fault stay in the plan as one repair, instead of appending past the fault or
/// overwriting the first reason. The writer only stops when it has settled the plan (drained, or
/// faulted with the plan retained) and no stream can accept more, so the operation's terminal result
/// is never published before the accepted bytes are written or owed.
pub(super) async fn run_capture_writer<B>(entry: Arc<CommandProcessEntry>, backend: Arc<B>)
where
    B: CommandBackend,
{
    loop {
        // Register interest *before* draining so a chunk accepted while the writer is appending is
        // never lost: `notify_one` also keeps a permit if the wake-up races this registration.
        let notified = entry.capture_wake.notified();
        tokio::pin!(notified);
        notified.as_mut().enable();

        drain_plan(&entry, backend.as_ref()).await;

        let settled = {
            let mut state = entry.state.lock().await;
            // A failed append keeps every accepted chunk as the one repair plan; the writer stops
            // appending but still settles, so the retained plan is never orphaned and the operation
            // can become final with its obligation intact.
            let ready = state.capture_write_faulted()
                || (state.capture_pending_is_empty() && state.output_streams_closed());
            if ready {
                state.mark_capture_drained();
                state.promote_drained_final();
            }
            ready
        };
        if settled {
            entry.notify.notify_waiters();
            return;
        }
        notified.await;
    }
}

/// Writes every accepted chunk from the front of the plan to the backend, stopping at the first fault.
async fn drain_plan<B>(entry: &CommandProcessEntry, backend: &B)
where
    B: CommandBackend,
{
    loop {
        // A write that already failed must not keep appending to the bad fragment: the accepted chunks
        // it did not store stay queued as one repair plan instead of overwriting the first failure.
        let front = {
            let state = entry.state.lock().await;
            if state.capture_write_faulted() {
                return;
            }
            state.front_capture()
        };
        let Some(front) = front else {
            return;
        };
        match backend
            .append_output_chunk(&entry.output_target, front.stream, &front.pending)
            .await
        {
            Ok(committed_len) => {
                {
                    let mut state = entry.state.lock().await;
                    state.confirm_front_capture(committed_len);
                }
                entry.notify.notify_waiters();
            }
            Err(error) => {
                entry.state.lock().await.fault_capture_write();
                fail_capture(
                    entry,
                    CommandCaptureFailure::Write {
                        message: error.to_string(),
                    },
                )
                .await;
                return;
            }
        }
    }
}

/// Records a hard capture failure and terminates the operation's process tree.
///
/// The reason is recorded and its terminating transition applied under one state lock, so a process
/// that exits on its own at the same moment still reports the typed output failure instead of a
/// healthy exit, and the bytes already written stay readable.
async fn fail_capture(entry: &CommandProcessEntry, failure: CommandCaptureFailure) {
    {
        let mut state = entry.state.lock().await;
        state.record_capture_failure(failure.clone());
        state.apply_transition(CommandProcessTransition::OutputFailed {
            failure: failure.clone(),
        });
    }
    // Notify the running call's own observer before the process tree finishes terminating and
    // draining, so the typed fault reaches the storage boundary while the call is still in flight
    // instead of only when `execute` unwinds. The observer only forwards it; the same fault is
    // reported again on the return path, so a dropped notification is never the only report.
    if let Some(observer) = &entry.output_observer {
        observer.output_failed(&failure);
    }
    entry.notify.notify_waiters();
    entry.output_failure.cancel();
}

impl From<StreamKind> for CommandOutputStream {
    fn from(value: StreamKind) -> Self {
        match value {
            StreamKind::Stdout => Self::Stdout,
            StreamKind::Stderr => Self::Stderr,
        }
    }
}
