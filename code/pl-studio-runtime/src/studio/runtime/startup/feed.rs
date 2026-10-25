use super::{super::models::delivery_window::DeliveryWindow, source::StartupProgressSource};
use pl_protocol::products::read::startup::*;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::{
    future::Future,
    sync::{Arc, Mutex},
};
use tokio::sync::{Notify, watch};
use tokio_util::sync::CancellationToken;

struct Window {
    delivery: DeliveryWindow<StartupStage>,
    index: usize,
}
pub struct StudioStartupProgress {
    source: Arc<StartupProgressSource>,
    feed_id: String,
    window: Mutex<Window>,
    cancel: CancellationToken,
    updates: tokio::sync::Mutex<watch::Receiver<()>>,
    credit: Notify,
}
impl StudioStartupProgress {
    pub(super) fn new(source: Arc<StartupProgressSource>, updates: watch::Receiver<()>) -> Self {
        Self {
            source,
            feed_id: crate::studio::new_id("startup-progress"),
            window: Mutex::new(Window {
                delivery: DeliveryWindow::new(Arc::new(StartupStage::Preparing)),
                index: 0,
            }),
            cancel: CancellationToken::new(),
            updates: tokio::sync::Mutex::new(updates),
            credit: Notify::new(),
        }
    }
    pub fn feed_id(&self) -> String {
        self.feed_id.clone()
    }
    pub fn attempt_id(&self) -> u64 {
        self.source.attempt_id()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        if self.source.stop_token().is_cancelled()
            || self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .delivery
                .closing
        {
            Err(cancelled())
        } else {
            Ok(())
        }
    }
    pub fn claim(&self) -> Result<(), StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if window.delivery.closing || self.source.stop_token().is_cancelled() {
            return Err(cancelled());
        }
        window.delivery.claim("Startup")
    }
    /// Returns true only for an actual Data send. Each callback is bounded/non-reentrant.
    pub fn send_pending(
        &self,
        send: impl FnOnce(StartupProgressFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if window.delivery.closing {
            return Err(cancelled());
        }
        window.delivery.require_claimed("Startup")?;
        self.source.with_next(window.index, |stage, _| {
            let Some(stage) = stage else {
                return Ok(false);
            };
            window.delivery.pending = Some(Arc::new(stage));
            let sent = window
                .delivery
                .deliver(
                    "Startup",
                    |delivery_sequence, stage| {
                        Ok(StartupProgressFrame::Data {
                            delivery_sequence,
                            stage: *stage,
                        })
                    },
                    send,
                )?
                .is_some();
            if sent {
                window.index += 1;
            }
            Ok(sent)
        })
    }
    /// A terminal cannot overtake queued Data. It uses no Data credit and never invents an ACK.
    pub fn send_terminal(
        &self,
        send: impl FnOnce(StartupProgressFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.source.with_next(window.index, |_, terminal| {
            let Some(terminal) = terminal else {
                return Ok(false);
            };
            let frame = match terminal {
                Ok(reason) => StartupProgressFrame::Closed { reason },
                Err(error) => StartupProgressFrame::Failure { error },
            };
            window.delivery.send_control(|| send(frame))?;
            Ok(true)
        })
    }
    pub fn ack_through(&self, sequence: u64) -> Result<(), StudioError> {
        {
            let mut window = self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if window.delivery.closing {
                return Err(cancelled());
            }
            window.delivery.ack_through(sequence, "Startup")?;
        }
        self.credit.notify_one();
        Ok(())
    }
    pub async fn changed(&self) -> Result<(), StudioError> {
        tokio::select! { biased; () = self.cancelled() => Err(cancelled()), () = self.credit.notified() => Ok(()),
        result = async { self.updates.lock().await.changed().await } => result.map_err(|_| cancelled()), }
    }
    pub fn request_close(&self) {
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .closing = true;
        self.cancel.cancel();
    }
    pub fn cancelled(&self) -> impl Future<Output = ()> + Send + 'static + use<> {
        let cancel = self.cancel.clone();
        let stopped = self.source.stop_token();
        async move {
            tokio::select! { biased; () = cancel.cancelled() => {}, () = stopped.cancelled() => {} }
        }
    }
    pub fn is_closing(&self) -> bool {
        self.cancel.is_cancelled() || self.source.stop_token().is_cancelled()
    }
    pub fn send_closed(
        &self,
        send: impl FnOnce(StartupProgressFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        let reason = self.source.close_reason();
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| send(StartupProgressFrame::Closed { reason }))
    }
    pub fn send_failure(
        &self,
        error: StudioError,
        send: impl FnOnce(StartupProgressFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| send(StartupProgressFrame::Failure { error }))
    }
}
impl Drop for StudioStartupProgress {
    fn drop(&mut self) {
        self.request_close();
    }
}
fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Startup progress is closing",
        false,
    )
}
