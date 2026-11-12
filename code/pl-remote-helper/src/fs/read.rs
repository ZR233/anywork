//! Registered native read owners retain each OS future until it actually finishes.
use super::*;
use bytes::Bytes;
use tokio::sync::mpsc;
use tokio_util::io::StreamReader;

pub(super) async fn open(executor: &Executor, path: String) -> Result<FileReader, ExecutionError> {
    let cancel = executor.inner.closing.child_token();
    let guard = cancel.clone().drop_guard();
    let stop = cancel.clone();
    let (ready, prepared) = oneshot::channel();
    let (send, receive) = mpsc::channel(1);
    executor.inner.tasks.spawn(async move {
        if stop.is_cancelled() {
            let _ = ready.send(Err(ExecutionError::Cancelled));
            return;
        }
        // Never cancel an OS operation by dropping this future. Cancellation is
        // observed between operations and at bounded channel admission.
        let mut file = match tokio::fs::File::open(path).await {
            Ok(file) => file,
            Err(error) => {
                let _ = ready.send(Err(ExecutionError::io("open file", error)));
                return;
            }
        };
        if stop.is_cancelled() {
            let _ = ready.send(Err(ExecutionError::Cancelled));
            return;
        }
        if ready.send(Ok(())).is_err() {
            return;
        }
        let mut bytes = vec![0; crate::stream::WINDOW as usize];
        loop {
            let permit = tokio::select! {
                _=stop.cancelled()=>return,
                permit=send.reserve()=>match permit {Ok(permit)=>permit,Err(_)=>return},
            };
            let result = file.read(&mut bytes).await;
            if stop.is_cancelled() {
                return;
            }
            match result {
                Ok(0) => return,
                Ok(count) => permit.send(Ok(Bytes::copy_from_slice(&bytes[..count]))),
                Err(error) => {
                    permit.send(Err(error));
                    return;
                }
            }
        }
    });
    tokio::select! {
        _=executor.inner.closing.cancelled()=>return Err(ExecutionError::Disconnected("file reader is closed".into())),
        result=prepared=>result.map_err(|_|ExecutionError::Protocol("native read owner ended during open".into()))??,
    }
    guard.disarm();
    let stream = futures::stream::unfold(receive, |mut receive| async move {
        receive.recv().await.map(|item| (item, receive))
    });
    Ok(FileReader {
        io: Box::pin(StreamReader::new(Box::pin(stream))),
        _executor: executor.clone(),
        cancel: Some(cancel),
        finished: false,
    })
}

type DirectoryResult = Result<Option<DirectoryEntry>, ExecutionError>;
pub(super) struct Directory {
    requests: mpsc::Sender<oneshot::Sender<DirectoryResult>>,
    pending: Option<oneshot::Receiver<DirectoryResult>>,
    cancel: CancellationToken,
}
impl Drop for Directory {
    fn drop(&mut self) {
        self.cancel.cancel();
    }
}
impl Directory {
    pub async fn next(&mut self) -> DirectoryResult {
        if self.pending.is_none() {
            let (send, receive) = oneshot::channel();
            self.requests.try_send(send).map_err(|_| {
                ExecutionError::Disconnected("native directory owner is closed".into())
            })?;
            // Store the observation before awaiting: cancelling next() must not
            // lose an entry already being read by the OS owner.
            self.pending = Some(receive);
        }
        let result = self
            .pending
            .as_mut()
            .expect("directory observation")
            .await
            .map_err(|_| ExecutionError::Disconnected("native directory owner ended".into()));
        self.pending = None;
        result?
    }
}

pub(super) async fn directory(
    executor: &Executor,
    path: String,
) -> Result<Directory, ExecutionError> {
    let cancel = executor.inner.closing.child_token();
    let guard = cancel.clone().drop_guard();
    let stop = cancel.clone();
    let (ready, prepared) = oneshot::channel();
    let (requests, mut receive) = mpsc::channel::<oneshot::Sender<DirectoryResult>>(1);
    executor.inner.tasks.spawn(async move {
        if stop.is_cancelled() {
            let _ = ready.send(Err(ExecutionError::Cancelled));
            return;
        }
        let mut entries = match tokio::fs::read_dir(path).await {
            Ok(entries) => entries,
            Err(error) => {
                let _ = ready.send(Err(ExecutionError::io("open directory", error)));
                return;
            }
        };
        if stop.is_cancelled() {
            let _ = ready.send(Err(ExecutionError::Cancelled));
            return;
        }
        if ready.send(Ok(())).is_err() {
            return;
        }
        loop {
            let request = tokio::select! {
                _=stop.cancelled()=>return,
                request=receive.recv()=>match request {Some(request)=>request,None=>return},
            };
            let entry = next_entry(&mut entries).await;
            if stop.is_cancelled() {
                return;
            }
            let ended = matches!(entry, Ok(None));
            let _ = request.send(entry);
            if ended {
                return;
            }
        }
    });
    tokio::select! {
        _=executor.inner.closing.cancelled()=>return Err(ExecutionError::Disconnected("directory reader is closed".into())),
        result=prepared=>result.map_err(|_|ExecutionError::Protocol("native directory owner ended during open".into()))??,
    }
    guard.disarm();
    Ok(Directory {
        requests,
        pending: None,
        cancel,
    })
}

async fn next_entry(entries: &mut tokio::fs::ReadDir) -> DirectoryResult {
    let Some(entry) = entries
        .next_entry()
        .await
        .map_err(|error| ExecutionError::io("read directory", error))?
    else {
        return Ok(None);
    };
    let name = entry
        .file_name()
        .into_string()
        .map_err(|_| ExecutionError::InvalidInput("directory name is not UTF-8".into()))?;
    let path = entry
        .path()
        .into_os_string()
        .into_string()
        .map_err(|_| ExecutionError::InvalidInput("directory path is not UTF-8".into()))?;
    let kind = entry
        .file_type()
        .await
        .map_err(|error| ExecutionError::io("directory entry type", error))?;
    Ok(Some(DirectoryEntry {
        name,
        path,
        is_file: kind.is_file(),
        is_dir: kind.is_dir(),
        is_symlink: kind.is_symlink(),
    }))
}
