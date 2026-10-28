//! One admission deadline and cancellation scope through worker bootstrap.
#[cfg(target_os = "linux")]
use crate::client::WorkerClientError;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
pub use tokio::time::Instant;
pub use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum CommandStartError {
    #[error("command cancelled before business Start")]
    Cancelled,
    #[error("command deadline expired before business Start")]
    Expired,
}

#[derive(Debug, Clone)]
pub struct CommandStartControl {
    deadline: Instant,
    cancellation: CancellationToken,
    shutdown: CancellationToken,
    attempted: Arc<AtomicBool>,
}

impl CommandStartControl {
    pub fn new(
        deadline: Instant,
        cancellation: CancellationToken,
        shutdown: CancellationToken,
    ) -> Self {
        Self {
            deadline,
            cancellation,
            shutdown,
            attempted: Arc::new(AtomicBool::new(false)),
        }
    }
    pub fn deadline(&self) -> Instant {
        self.deadline
    }
    pub fn start_attempted(&self) -> bool {
        self.attempted.load(Ordering::Acquire)
    }
    pub fn confirm_not_started(&self) {
        self.attempted.store(false, Ordering::Release);
    }
    pub fn mark_start_attempted(&self) {
        self.attempted.store(true, Ordering::Release);
    }
    pub fn check(&self) -> Result<(), CommandStartError> {
        if self.cancellation.is_cancelled() || self.shutdown.is_cancelled() {
            return Err(CommandStartError::Cancelled);
        }
        if Instant::now() >= self.deadline {
            return Err(CommandStartError::Expired);
        }
        Ok(())
    }
    pub async fn stopped(&self) {
        tokio::select! {
            _ = self.cancellation.cancelled() => {},
            _ = self.shutdown.cancelled() => {},
            _ = tokio::time::sleep_until(self.deadline) => {},
        }
    }
    #[cfg(target_os = "linux")]
    pub(crate) async fn bootstrap<T>(
        &self,
        future: impl std::future::Future<Output = Result<T, WorkerClientError>>,
    ) -> Result<T, WorkerClientError> {
        self.check()?;
        tokio::select! {
            biased;
            _ = self.stopped() => { self.check()?; Err(WorkerClientError::StartExpired) },
            result = tokio::time::timeout(std::time::Duration::from_secs(10), future) => {
                result.map_err(|_| WorkerClientError::ReadinessTimeout)?
            }
        }
    }
}
