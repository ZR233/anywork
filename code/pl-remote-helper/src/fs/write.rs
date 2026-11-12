use super::{FileWriter, WriteDescriptor, WriteMode, WriteResult};
use crate::{ExecutionError, Executor};
use std::io;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    sync::oneshot,
};
use tokio_util::sync::CancellationToken;

pub(super) async fn open(
    executor: Executor,
    descriptor: WriteDescriptor,
) -> Result<FileWriter, ExecutionError> {
    let (mut input, output) = tokio::io::duplex(crate::stream::WINDOW as usize);
    let (ready, prepared) = oneshot::channel();
    let (finish, commit) = oneshot::channel();
    let (result, observed) = oneshot::channel();
    let cancel = CancellationToken::new();
    let stopped = cancel.clone();
    let owner = executor.clone();
    executor.inner.tasks.spawn(async move {
        let closing = owner.inner.closing.clone();
        let prepared = prepare(&descriptor).await;
        let (mut file, temporary) = match prepared {
            Ok(prepared) => prepared,
            Err(error) => {
                let _ = ready.send(Err(error));
                return;
            }
        };
        if ready.send(Ok(())).is_err() {
            return;
        }
        let operation = async {
            let mut length = 0_u64;
            let mut bytes = [0; crate::stream::WINDOW as usize];
            loop {
                let count = input
                    .read(&mut bytes)
                    .await
                    .map_err(|error| ExecutionError::io("file upload source", error))?;
                if count == 0 {
                    break;
                }
                length = length
                    .checked_add(count as u64)
                    .ok_or_else(|| ExecutionError::InvalidInput("file length overflow".into()))?;
                if descriptor
                    .expected_len
                    .is_some_and(|expected| length > expected)
                {
                    return Err(ExecutionError::InvalidInput(
                        "upload exceeds expected length".into(),
                    ));
                }
                file.write_all(&bytes[..count])
                    .await
                    .map_err(|error| ExecutionError::io("write file", error))?;
            }
            commit.await.map_err(|_| ExecutionError::Cancelled)?;
            if descriptor
                .expected_len
                .is_some_and(|expected| length != expected)
            {
                return Err(ExecutionError::InvalidInput(
                    "upload does not match expected length".into(),
                ));
            }
            file.flush()
                .await
                .map_err(|error| ExecutionError::io("flush file", error))?;
            Ok(length)
        };
        let transferred = tokio::select! {
            result = operation => result,
            _ = stopped.cancelled() => Err(ExecutionError::Cancelled),
            _ = closing.cancelled() => Err(ExecutionError::Cancelled),
        };
        // Cancellation of Tokio's async write does not cancel an in-flight OS
        // operation. This registered owner flushes/joins it before releasing the
        // handle and its own temporary file, even when nobody awaits the result.
        let flush = file
            .flush()
            .await
            .map_err(|error| ExecutionError::io("settle file IO", error));
        drop(file);
        let publication = match transferred.and_then(|length| flush.map(|()| length)) {
            Ok(length) if !stopped.is_cancelled() && !closing.is_cancelled() => {
                if let Some(temporary) = temporary {
                    let target = descriptor.path.clone();
                    let mode = descriptor.mode;
                    let published = tokio::task::spawn_blocking(move || {
                        match mode {
                            WriteMode::ReplaceAtomic => temporary.persist(&target),
                            WriteMode::CreateNew => temporary.persist_noclobber(&target),
                            WriteMode::Append => unreachable!("append has no temporary file"),
                        }
                        .map_err(|error| ExecutionError::io("publish file", error.error))
                    })
                    .await
                    .map_err(|error| {
                        ExecutionError::Protocol(format!("publication task failed: {error}"))
                    })
                    .and_then(|result| result);
                    published.map(|()| WriteResult {
                        bytes: length,
                        mode,
                    })
                } else {
                    Ok(WriteResult {
                        bytes: length,
                        mode: descriptor.mode,
                    })
                }
            }
            Ok(_) => Err(ExecutionError::Cancelled),
            Err(error) => Err(error),
        };
        let _ = result.send(publication);
    });
    // This value also guards cancellation while preparation is still pending.
    let writer = FileWriter {
        io: Some(output),
        finish: Some(finish),
        result: Some(observed),
        cancel,
        finishing: false,
        _executor: executor,
        _permit: None,
    };
    prepared
        .await
        .map_err(|_| ExecutionError::Protocol("file preparation owner ended".into()))??;
    Ok(writer)
}

async fn prepare(
    descriptor: &WriteDescriptor,
) -> Result<(tokio::fs::File, Option<tempfile::TempPath>), ExecutionError> {
    if descriptor.mode == WriteMode::Append {
        let file = tokio::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&descriptor.path)
            .await
            .map_err(|error| ExecutionError::io("open append file", error))?;
        return Ok((file, None));
    }
    let target = std::path::Path::new(&descriptor.path);
    let parent = target
        .parent()
        .ok_or_else(|| ExecutionError::InvalidInput("file target has no parent".into()))?
        .to_owned();
    let path = descriptor.path.clone();
    let (file, temporary) = tokio::task::spawn_blocking(move || {
        let temporary = tempfile::Builder::new()
            .prefix(".anywork-write-")
            .tempfile_in(parent)?;
        match std::fs::symlink_metadata(&path) {
            Ok(metadata) if metadata.is_file() => temporary
                .as_file()
                .set_permissions(metadata.permissions())?,
            Ok(_) => (),
            Err(error) if error.kind() == io::ErrorKind::NotFound => (),
            Err(error) => return Err(error),
        }
        Ok::<_, io::Error>(temporary.into_parts())
    })
    .await
    .map_err(|error| ExecutionError::Protocol(format!("file preparation task failed: {error}")))?
    .map_err(|error| ExecutionError::io("prepare atomic file", error))?;
    Ok((tokio::fs::File::from_std(file), Some(temporary)))
}
