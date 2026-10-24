//! Retained physical cleanup. A cancelled observer never owns the last stage or task handle.
use super::*;

#[derive(Debug, Clone)]
pub(super) enum StagingCleanup {
    Create(CreateOwner),
    ReplaceStage(Arc<LegacyStage>),
    Replace(PathBuf),
}

#[derive(Debug)]
pub(super) struct LegacyStage {
    path: PathBuf,
    temporary: std::sync::Mutex<Option<tempfile::TempPath>>,
}

impl StagingCleanup {
    pub(super) fn replace_stage(temporary: tempfile::TempPath) -> Self {
        Self::ReplaceStage(Arc::new(LegacyStage {
            path: temporary.to_path_buf(),
            temporary: std::sync::Mutex::new(Some(temporary)),
        }))
    }
}

impl LegacyStage {
    fn finish(&self) -> Result<(), RemoteError> {
        let temporary = self
            .temporary
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        if let Some(temporary) = temporary {
            // Discharge tempfile's RAII finalizer inside the retained blocking worker, not
            // later on an async thread when the last state/Arc is released. The fallback
            // path remains owned for retry even when this consuming finalizer fails.
            match temporary.close() {
                Ok(()) => Ok(()),
                Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
                Err(error) => Err(io_error("remove transfer staging", error)),
            }
        } else {
            remove(&self.path)
        }
    }
}

#[derive(Debug)]
pub(super) struct ClosingFile {
    pub(super) publication: Option<(u64, String)>,
    finalizer: Mutex<CleanupState>,
}

#[derive(Debug)]
struct CleanupState {
    cleanup: Option<StagingCleanup>,
    task: Option<tokio::task::JoinHandle<Result<(), RemoteError>>>,
}

impl ClosingFile {
    pub(super) fn new(cleanup: Option<StagingCleanup>, publication: Option<(u64, String)>) -> Self {
        Self {
            publication,
            finalizer: Mutex::new(CleanupState {
                cleanup,
                task: None,
            }),
        }
    }

    pub(super) async fn finish(&self) -> Result<(), RemoteError> {
        let mut finalizer = self.finalizer.lock().await;
        finalizer.finish().await
    }
}

impl CleanupState {
    async fn finish(&mut self) -> Result<(), RemoteError> {
        if self.task.is_none() {
            if let Some(cleanup) = &self.cleanup {
                self.task = Some(start(cleanup.clone()));
            } else {
                return Ok(());
            }
        }
        // Both the original owner and this unique JoinHandle stay in the state-owned ClosingFile.
        // Cancellation only releases its finalizer lock; the next observer borrows this slot.
        let joined = self
            .task
            .as_mut()
            .expect("cleanup task installed before waiting")
            .await;
        self.task.take();
        joined.map_err(|error| {
            remote_error(
                RemoteErrorCode::OutcomeUnknown,
                format!("transfer cleanup worker did not return: {error}"),
            )
        })??;
        // Only a joined, successful physical finalizer releases the last cleanup obligation.
        self.cleanup.take();
        Ok(())
    }
}

pub(super) async fn cleanup_stage(cleanup: &StagingCleanup) -> Result<(), RemoteError> {
    // Commit runs under the helper's retained ordinary-operation owner; close instead retains
    // this same worker in ClosingFile because its control observer is cancellable.
    start(cleanup.clone())
        .await
        .map_err(|error| io_error("transfer cleanup task", io::Error::other(error)))?
}

fn start(cleanup: StagingCleanup) -> tokio::task::JoinHandle<Result<(), RemoteError>> {
    tokio::task::spawn_blocking(move || match cleanup {
        StagingCleanup::Create(owner) => owner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .cleanup()
            .map_err(|error| io_error("clean Create staging/directory barrier", error)),
        StagingCleanup::Replace(path) => remove(&path),
        StagingCleanup::ReplaceStage(stage) => stage.finish(),
    })
}

fn remove(path: &std::path::Path) -> Result<(), RemoteError> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(io_error("remove transfer staging", error)),
    }
}
