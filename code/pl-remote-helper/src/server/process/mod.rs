//! Physical command owners survive transport replacement and release on terminal acknowledgement.
mod capture;
mod journal;
use super::*;
use crate::budget::{ByteLease, ResourceBudget};
use crate::client::{ChildStdin, ManagedWorker, ProcessCommand, ProcessTermination};
use journal::Journal;
use std::collections::HashMap;
use std::path::PathBuf;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{Notify, watch};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

#[derive(Debug)]
struct Input {
    writer: Option<ChildStdin>,
    offset: u64,
    failure: Option<RemoteError>,
}
#[derive(Debug)]
struct Entry {
    input: Mutex<Input>,
    cancel: CancellationToken,
    exited: CancellationToken,
    startup: watch::Sender<Option<Result<(), RemoteError>>>,
    journal: Journal,
    _lease: ByteLease,
    release_requested: std::sync::atomic::AtomicBool,
}
#[derive(Debug, Clone)]
pub(super) struct ProcessRegistry {
    entries: Arc<Mutex<HashMap<String, Arc<Entry>>>>,
    tasks: TaskTracker,
    closing: CancellationToken,
    budget: ResourceBudget,
}
impl ProcessRegistry {
    pub(super) fn new(budget: ResourceBudget) -> Self {
        Self {
            entries: Default::default(),
            tasks: TaskTracker::new(),
            closing: CancellationToken::new(),
            budget,
        }
    }
    async fn get(&self, id: &str) -> Result<Arc<Entry>, RemoteError> {
        self.entries.lock().await.get(id).cloned().ok_or_else(|| {
            remote_error(RemoteErrorCode::ProcessNotFound, "process handle is closed")
        })
    }
    pub(super) async fn spawn(
        &self,
        request: RemoteSpawnRequest,
        cwd: PathBuf,
        capture: Option<(PathBuf, PathBuf)>,
    ) -> Result<(), RemoteError> {
        if self.closing.is_cancelled() {
            return Err(closed());
        }
        let cost = std::mem::size_of::<Entry>()
            + serde_json::to_vec(&request)
                .map_err(|e| remote_error(RemoteErrorCode::InvalidRequest, e.to_string()))?
                .len();
        let lease = self.budget.try_reserve(cost).ok_or_else(|| {
            remote_error(
                RemoteErrorCode::ResourceExhausted,
                "process handle budget exhausted",
            )
        })?;
        let entry = Arc::new(Entry {
            input: Mutex::new(Input {
                writer: None,
                offset: 0,
                failure: None,
            }),
            cancel: self.closing.child_token(),
            exited: CancellationToken::new(),
            startup: watch::channel(None).0,
            journal: Journal::new(self.budget.clone())?,
            _lease: lease,
            release_requested: std::sync::atomic::AtomicBool::new(false),
        });
        {
            let mut entries = self.entries.lock().await;
            if entries.contains_key(&request.process_id) {
                return Err(remote_error(
                    RemoteErrorCode::InvalidRequest,
                    "process identity is already registered",
                ));
            }
            entries.insert(request.process_id.clone(), entry.clone());
        }
        let mut startup = entry.startup.subscribe();
        let owner = self.clone();
        self.tasks.spawn(async move {
            let result = owner.run(&entry, &request, cwd, capture).await;
            entry.exited.cancel();
            if entry.startup.borrow().is_none() {
                entry
                    .startup
                    .send_replace(Some(Err(result.clone().err().unwrap_or_else(closed))));
            }
            let exit = match result {
                Ok(exit) => exit,
                Err(error) => RemoteProcessExit {
                    process_id: request.process_id.clone(),
                    exit_code: None,
                    signal: None,
                    failure: Some(error),
                    capture: None,
                },
            };
            entry.journal.finish(exit).await;
            let startup_failed = entry.startup.borrow().as_ref().is_some_and(Result::is_err);
            if startup_failed
                || entry
                    .release_requested
                    .load(std::sync::atomic::Ordering::Acquire)
            {
                owner.remove(&request.process_id).await;
            }
        });
        startup
            .wait_for(Option::is_some)
            .await
            .map_err(|_| closed())?
            .as_ref()
            .cloned()
            .ok_or_else(closed)?
    }
    async fn run(
        &self,
        entry: &Entry,
        request: &RemoteSpawnRequest,
        cwd: PathBuf,
        capture_path: Option<(PathBuf, PathBuf)>,
    ) -> Result<RemoteProcessExit, RemoteError> {
        let remaining = request
            .remaining_timeout_ms
            .map(Duration::from_millis)
            .unwrap_or(Duration::from_secs(10));
        let deadline = tokio::time::Instant::now()
            .checked_add(remaining)
            .ok_or_else(|| {
                remote_error(
                    RemoteErrorCode::InvalidRequest,
                    "remaining timeout cannot be represented",
                )
            })?;
        let start = crate::start_control::CommandStartControl::new(
            deadline,
            entry.cancel.clone(),
            self.closing.clone(),
        );
        let mut capture = capture::Capture::prepare(
            &request.capture,
            capture_path
                .as_ref()
                .map(|(out, err)| (out.as_path(), err.as_path())),
        )
        .await?;
        if entry.cancel.is_cancelled() {
            return Err(closed());
        }
        let mut command = ProcessCommand::new(&request.program)
            .args(&request.arguments)
            .current_dir(&cwd);
        for key in &request.remove_environment {
            command = command.env_remove(key);
        }
        for (key, value) in &request.environment {
            command = command.env(key, value);
        }
        let executable =
            std::env::current_exe().map_err(|e| io_error("locate process worker", e))?;
        let mut worker = ManagedWorker::spawn_controlled(&executable, command, &start)
            .await
            .map_err(|e| remote_error(RemoteErrorCode::Io, e.to_string()))?;
        entry.input.lock().await.writer = worker.take_stdin();
        let mut stdout = worker.take_stdout();
        let mut stderr = worker.take_stderr();
        let control = worker.control();
        entry.startup.send_replace(Some(Ok(())));
        let wait = async {
            let result = tokio::select! {
                result = worker.wait() => result,
                _ = entry.cancel.cancelled() => {
                    if control.cancel().await.is_err() { control.close(); }
                    worker.wait().await
                }
            };
            entry.exited.cancel();
            result
        };
        let output = async {
            let mut failure = None;
            while stdout.is_some() || stderr.is_some() {
                let quantum = entry.journal.fragment_bytes();
                let mut out = vec![0; quantum];
                let mut err = vec![0; quantum];
                let (stream, count) = tokio::select! {
                    result = async { stdout.as_mut().unwrap().read(&mut out).await }, if stdout.is_some() => (RemoteOutputStream::Stdout, result),
                    result = async { stderr.as_mut().unwrap().read(&mut err).await }, if stderr.is_some() => (RemoteOutputStream::Stderr, result),
                };
                let count = match count {
                    Ok(count) => count,
                    Err(error) => {
                        failure.get_or_insert_with(|| {
                            remote_error(RemoteErrorCode::OutputRead, error.to_string())
                        });
                        entry.cancel.cancel();
                        0
                    }
                };
                if count == 0 {
                    match stream {
                        RemoteOutputStream::Stdout => stdout = None,
                        RemoteOutputStream::Stderr => stderr = None,
                    }
                    continue;
                }
                let bytes = match stream {
                    RemoteOutputStream::Stdout => &out[..count],
                    RemoteOutputStream::Stderr => &err[..count],
                };
                match capture.append(stream, bytes).await {
                    Ok(capture::Acceptance::Accepted) => {}
                    Ok(capture::Acceptance::Refused) => {
                        entry.cancel.cancel();
                        continue;
                    }
                    Err(error) => {
                        failure.get_or_insert(error);
                        entry.cancel.cancel();
                    }
                }
                if !entry.cancel.is_cancelled()
                    && let Err(error) = entry
                        .journal
                        .push(&request.process_id, stream, bytes, &entry.cancel)
                        .await
                    && !entry.cancel.is_cancelled()
                {
                    failure.get_or_insert(error);
                    entry.cancel.cancel();
                }
            }
            if let Err(error) = capture.flush().await {
                failure.get_or_insert(error);
            }
            (failure, capture.receipt())
        };
        let (result, (failure, receipt)) = tokio::join!(wait, output);
        let (exit_code, signal) =
            match result.map_err(|e| remote_error(RemoteErrorCode::Io, e.to_string()))? {
                ProcessTermination::ExitCode(code) => (Some(code), None),
                ProcessTermination::Signal(signal) => (None, Some(signal)),
            };
        Ok(RemoteProcessExit {
            process_id: request.process_id.clone(),
            exit_code,
            signal,
            failure,
            capture: receipt,
        })
    }
    pub(super) async fn write_stdin(
        &self,
        id: &str,
        offset: u64,
        body: &[u8],
    ) -> Result<u64, RemoteError> {
        let entry = self.get(id).await?;
        let mut input = entry.input.lock().await;
        if let Some(error) = &input.failure {
            return Err(error.clone());
        }
        if offset != input.offset {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "stdin offset differs from confirmed position",
            ));
        }
        let mut remaining = body;
        while !remaining.is_empty() {
            let Some(writer) = input.writer.as_mut() else {
                return Err(remote_error(
                    RemoteErrorCode::ProcessNotFound,
                    "process input is closed",
                ));
            };
            let result = tokio::select! {
                result = writer.write(remaining) => result,
                _ = entry.cancel.cancelled() => Err(io::Error::new(io::ErrorKind::Interrupted, "process input cancelled")),
                _ = entry.exited.cancelled() => Err(io::Error::new(io::ErrorKind::BrokenPipe, "process exited")),
            };
            match result {
                Ok(0) => {
                    return Err(io_error(
                        "stdin write made no progress",
                        io::ErrorKind::WriteZero.into(),
                    ));
                }
                Ok(count) => {
                    input.offset += count as u64;
                    remaining = &remaining[count..];
                }
                Err(error) => {
                    let error = io_error("write process stdin", error);
                    input.failure = Some(error.clone());
                    return Err(error);
                }
            }
        }
        Ok(input.offset)
    }
    pub(super) async fn close_stdin(&self, id: &str) -> Result<(), RemoteError> {
        self.get(id).await?.input.lock().await.writer = None;
        Ok(())
    }
    pub(super) async fn terminate(&self, id: &str) -> Result<(), RemoteError> {
        self.get(id).await?.cancel.cancel();
        Ok(())
    }
    pub(super) async fn acknowledge(&self, id: &str, sequence: u64) -> Result<(), RemoteError> {
        self.get(id).await?.journal.acknowledge(sequence).await
    }
    pub(super) async fn wait(&self, id: &str) -> Result<RemoteProcessExit, RemoteError> {
        Ok(self.get(id).await?.journal.wait().await)
    }
    pub(super) async fn release(&self, id: &str) -> Result<(), RemoteError> {
        let Some(entry) = self.entries.lock().await.get(id).cloned() else {
            return Ok(());
        };
        entry
            .release_requested
            .store(true, std::sync::atomic::Ordering::Release);
        entry.cancel.cancel();
        if entry.journal.is_finished().await {
            self.remove(id).await;
        }
        Ok(())
    }
    pub(super) async fn output(
        &self,
        id: &str,
        after: u64,
        sender: h2::server::SendResponse<crate::transport::Bytes>,
        stop: CancellationToken,
    ) -> io::Result<()> {
        let entry = self
            .get(id)
            .await
            .map_err(|e| io::Error::other(e.message))?;
        entry.journal.stream(after, sender, stop).await
    }
    async fn remove(&self, id: &str) {
        let mut entries = self.entries.lock().await;
        entries.remove(id);
        if entries.len().saturating_mul(4) < entries.capacity() {
            entries.shrink_to_fit();
        }
    }
    pub(super) async fn len(&self) -> usize {
        self.entries.lock().await.len()
    }
    pub(super) async fn terminate_all(&self) -> Result<(), RemoteError> {
        self.closing.cancel();
        self.tasks.close();
        self.tasks.wait().await;
        self.entries.lock().await.clear();
        Ok(())
    }
}
fn closed() -> RemoteError {
    remote_error(
        RemoteErrorCode::RemoteDisconnected,
        "process owner is closing",
    )
}
