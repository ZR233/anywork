use std::future::Future;
use std::sync::atomic::{AtomicBool, Ordering};

use pl_lifecycle::ManagedResource;
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

use crate::api::studio::types::BridgeError;

/// Source capability required by [`ManagedPullObservation`].
pub(crate) trait PullObservationSource: Send + Sync + 'static {
    type Frame;
    fn next(&self) -> impl Future<Output = Result<Option<Self::Frame>, BridgeError>> + Send;
    fn request_close(&self);
    fn close(&self) -> impl Future<Output = Result<(), BridgeError>> + Send;
}

/// Shared single-flight pull gate and close lifecycle for FRB pull observations.
pub(crate) struct ManagedPullObservation<S> {
    source: S,
    shutdown: CancellationToken,
    closing: AtomicBool,
    next_gate: Mutex<()>,
    busy_message: &'static str,
}

impl<S: PullObservationSource> ManagedPullObservation<S> {
    pub(crate) fn new(source: S, shutdown: CancellationToken, busy_message: &'static str) -> Self {
        Self {
            source,
            shutdown,
            closing: AtomicBool::new(false),
            next_gate: Mutex::new(()),
            busy_message,
        }
    }

    pub(crate) async fn next(&self) -> Result<Option<S::Frame>, BridgeError> {
        if self.closing.load(Ordering::Acquire) {
            return Ok(None);
        }
        let _next = self.next_gate.try_lock().map_err(|_| {
            BridgeError::from(pl_studio_runtime::StudioError::new(
                pl_studio_runtime::StudioErrorCode::Busy,
                self.busy_message,
                true,
            ))
        })?;
        if self.closing.load(Ordering::Acquire) {
            return Ok(None);
        }
        tokio::select! {
            biased;
            _ = self.shutdown.cancelled() => {
                self.request_close();
                Ok(None)
            }
            next = self.source.next() => next,
        }
    }
}

impl<S: PullObservationSource> ManagedResource for ManagedPullObservation<S> {
    type Error = BridgeError;

    fn request_close(&self) {
        self.closing.store(true, Ordering::Release);
        self.source.request_close();
    }

    async fn close(&self) -> Result<(), BridgeError> {
        self.request_close();
        self.source.close().await?;
        let _next = self.next_gate.lock().await;
        Ok(())
    }
}
