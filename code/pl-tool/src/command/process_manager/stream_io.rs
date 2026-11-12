use super::{
    CommandCaptureFailure, CommandOutputStream, CommandProcessEntry, CommandProcessTransition,
    StreamKind, lifecycle::apply_transition,
};
use crate::command::CommandReader;
use std::sync::Arc;
use tokio::io::AsyncReadExt;
pub(super) async fn read_stdout(entry: Arc<CommandProcessEntry>, reader: CommandReader) {
    read_stream(entry, reader, StreamKind::Stdout).await;
}
pub(super) async fn read_stderr(entry: Arc<CommandProcessEntry>, reader: CommandReader) {
    read_stream(entry, reader, StreamKind::Stderr).await;
}
async fn read_stream(
    entry: Arc<CommandProcessEntry>,
    mut reader: CommandReader,
    stream: StreamKind,
) {
    let mut buffer = [0u8; 8192];
    loop {
        let read = tokio::select! { result=reader.read(&mut buffer)=>result,_=entry.drain_stopped.cancelled()=>break };
        match read {
            Ok(0) => break,
            Ok(length) => {
                let chunk = &buffer[..length];
                let revision = entry.state.lock().await.record_output(stream, chunk);
                if let Some(observer) = &entry.output_observer {
                    observer.output_chunk(stream.into(), chunk, revision);
                }
                entry.notify.notify_waiters();
            }
            Err(error) => {
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
    // Reader Drop settles an abandoned capture before declaring this preview closed.
    drop(reader);
    if let Some(observer) = &entry.output_observer {
        observer.output_closed(stream.into());
    }
    apply_transition(&entry, CommandProcessTransition::StreamClosed(stream)).await;
}
/// Records a hard capture failure and terminates the operation's process tree.
///
/// The reason is recorded and its terminating transition applied under one state lock, so a process
/// that exits on its own at the same moment still reports the typed output failure instead of a
/// healthy exit, and the bytes already written stay readable.
pub(super) async fn fail_capture(entry: &CommandProcessEntry, failure: CommandCaptureFailure) {
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
