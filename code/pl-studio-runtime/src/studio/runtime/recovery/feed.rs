use super::super::{
    StudioRuntime, lifecycle::shutdown::ShutdownLatch, models::delivery_window::DeliveryWindow,
};
use super::{
    frames::{self, SentRecovery},
    source::{RecoverySnapshot, RecoverySource},
};
use pl_protocol::products::feed::recovery::RecoveryFrame;
use pl_protocol::products::identity::*;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::{
    future::Future,
    sync::{Arc, Mutex},
};
use tokio::sync::{Notify, watch};
use tokio_util::sync::CancellationToken;

struct Window {
    delivery: DeliveryWindow<RecoverySnapshot>,
    previous: Option<SentRecovery>,
}
pub struct StudioRecoveryFeed {
    identity: ProductFeedIdentity,
    source: Arc<RecoverySource>,
    runtime_stop: ShutdownLatch,
    cancel: CancellationToken,
    updates: tokio::sync::Mutex<watch::Receiver<()>>,
    credit: Notify,
    window: Mutex<Window>,
}
impl StudioRuntime {
    pub fn open_recovery(
        &self,
    ) -> impl Future<Output = anyhow::Result<StudioRecoveryFeed>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let source = runtime.recovery_source.clone();
            let (snapshot, updates) = source.observe()?;
            let origin = source.origin();
            let feed = StudioRecoveryFeed {
                identity: ProductFeedIdentity {
                    feed_id: crate::studio::new_id("recovery-feed"),
                    owner_epoch: origin.owner_epoch.clone(),
                    incarnation: origin.incarnation,
                    resource: ProductResource::Recovery,
                },
                source,
                runtime_stop: runtime.shutdown_latch.clone(),
                cancel: CancellationToken::new(),
                updates: tokio::sync::Mutex::new(updates),
                credit: Notify::new(),
                window: Mutex::new(Window {
                    delivery: DeliveryWindow::new(snapshot),
                    previous: None,
                }),
            };
            feed.ensure_open()?;
            Ok(feed)
        })
    }
}
impl StudioRecoveryFeed {
    pub fn identity(&self) -> ProductFeedIdentity {
        self.identity.clone()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.check(
            &self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        )
    }
    pub fn claim(&self) -> Result<(), StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&window)?;
        window.delivery.claim("Recovery")
    }
    /// Synchronous, bounded and non-reentrant send; exposure commits only after success.
    pub fn send_pending(
        &self,
        send: impl FnOnce(RecoveryFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&window)?;
        window.delivery.require_claimed("Recovery")?;
        let snapshot = self.source.current()?;
        if window
            .previous
            .as_ref()
            .is_some_and(|previous| previous.revision == snapshot.revision)
        {
            return Ok(false);
        }
        window.delivery.pending = Some(snapshot.clone());
        let event = match frames::event(&self.identity, &snapshot, window.previous.as_ref()) {
            Ok(event) => event,
            Err(reason) => {
                window.delivery.closing = true;
                let result = window.delivery.send_control(|| {
                    send(RecoveryFrame::ResyncRequired {
                        identity: self.identity.clone(),
                        reason,
                    })
                });
                drop(window);
                self.cancel.cancel();
                result?;
                return Ok(true);
            }
        };
        if !window.delivery.has_credit() {
            return Ok(false);
        }
        let previous = SentRecovery::capture(&snapshot);
        let sent = self.source.send_exposing(&snapshot, || {
            window
                .delivery
                .deliver(
                    "Recovery",
                    |delivery_sequence, _| {
                        Ok(RecoveryFrame::Data {
                            delivery_sequence,
                            event,
                        })
                    },
                    send,
                )
                .map(|sent| sent.is_some())
        })?;
        if sent {
            window.previous = Some(previous);
        }
        Ok(sent)
    }
    pub fn ack_through(&self, sequence: u64) -> Result<(), StudioError> {
        {
            let mut window = self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            self.check(&window)?;
            window.delivery.ack_through(sequence, "Recovery")?;
        }
        self.credit.notify_one();
        Ok(())
    }
    pub async fn changed(&self) -> Result<(), StudioError> {
        self.ensure_open()?;
        tokio::select! { biased; () = self.cancelled() => Err(cancelled()), () = self.credit.notified() => Ok(()),
        result = async { self.updates.lock().await.changed().await } => result.map_err(|_| StudioError::new(StudioErrorCode::Unavailable, "Recovery source disappeared", true)), }
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
        let runtime = self.runtime_stop.clone();
        async move {
            tokio::select! { biased; () = cancel.cancelled() => {}, () = runtime.committed() => {} }
        }
    }
    pub fn is_closing(&self) -> bool {
        self.cancel.is_cancelled()
            || self.runtime_stop.is_committed()
            || self.source.is_sealed()
            || self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .delivery
                .closing
    }
    pub fn send_closed(
        &self,
        send: impl FnOnce(RecoveryFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        let reason = if self.runtime_stop.is_committed() || self.source.is_sealed() {
            ProductFeedCloseReason::RuntimeStopped
        } else {
            ProductFeedCloseReason::Requested
        };
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| {
                send(RecoveryFrame::Closed {
                    identity: self.identity.clone(),
                    reason,
                })
            })
    }
    pub fn send_failure(
        &self,
        error: StudioError,
        send: impl FnOnce(RecoveryFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| {
                send(RecoveryFrame::Failure {
                    identity: self.identity.clone(),
                    error,
                })
            })
    }
    fn check(&self, window: &Window) -> Result<(), StudioError> {
        if window.delivery.closing || self.cancel.is_cancelled() || self.runtime_stop.is_committed()
        {
            return Err(cancelled());
        }
        self.source.ensure_open()
    }
}
impl Drop for StudioRecoveryFeed {
    fn drop(&mut self) {
        self.request_close();
    }
}
fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Recovery feed is closing",
        false,
    )
}
