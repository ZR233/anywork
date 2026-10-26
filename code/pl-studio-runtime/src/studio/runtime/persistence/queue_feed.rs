use super::super::{
    StudioRuntime, lifecycle::shutdown::ShutdownLatch, models::delivery_window::DeliveryWindow,
};
use super::{
    frames::{self, SentPersistenceQueue},
    source::{PersistenceQueueSnapshot, PersistenceQueueSource},
};
use pl_protocol::products::feed::persistence_queue::PersistenceQueueFrame;
use pl_protocol::products::identity::*;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::{
    future::Future,
    sync::{Arc, Mutex},
};
use tokio::sync::{Notify, watch};
use tokio_util::sync::CancellationToken;

struct Window {
    delivery: DeliveryWindow<PersistenceQueueSnapshot>,
    previous: Option<SentPersistenceQueue>,
}
pub struct StudioPersistenceQueueFeed {
    identity: ProductFeedIdentity,
    source: Arc<PersistenceQueueSource>,
    runtime_stop: ShutdownLatch,
    cancel: CancellationToken,
    updates: tokio::sync::Mutex<watch::Receiver<()>>,
    credit: Notify,
    window: Mutex<Window>,
}
impl StudioRuntime {
    pub fn open_persistence_queue(
        &self,
    ) -> impl Future<Output = anyhow::Result<StudioPersistenceQueueFeed>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let source = runtime.persistence_queue_source.clone();
            let (snapshot, updates) = source.observe()?;
            let origin = source.origin();
            let feed = StudioPersistenceQueueFeed {
                identity: ProductFeedIdentity {
                    feed_id: crate::studio::new_id("persistence_queue-feed"),
                    owner_epoch: origin.owner_epoch.clone(),
                    incarnation: origin.incarnation,
                    resource: ProductResource::PersistenceQueue,
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
impl StudioPersistenceQueueFeed {
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
        window.delivery.claim("PersistenceQueue")
    }
    /// Synchronous, bounded and non-reentrant send; exposure commits only after success.
    pub fn send_pending(
        &self,
        send: impl FnOnce(PersistenceQueueFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&window)?;
        window.delivery.require_claimed("PersistenceQueue")?;
        let snapshot = self.source.current()?;
        if window
            .previous
            .as_ref()
            .is_some_and(|previous| previous.revision == snapshot.revision)
        {
            return Ok(false);
        }
        window.delivery.pending = Some(snapshot.clone());
        let event = match frames::queue_event(&self.identity, &snapshot, window.previous.as_ref()) {
            Ok(event) => event,
            Err(reason) => {
                window.delivery.closing = true;
                let result = window.delivery.send_control(|| {
                    send(PersistenceQueueFrame::ResyncRequired {
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
        let previous = SentPersistenceQueue::capture(&snapshot);
        let sent = self.source.send_exposing(&snapshot, || {
            window
                .delivery
                .deliver(
                    "PersistenceQueue",
                    |delivery_sequence, _| {
                        Ok(PersistenceQueueFrame::Data {
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
            window.delivery.ack_through(sequence, "PersistenceQueue")?;
        }
        self.credit.notify_one();
        Ok(())
    }
    pub async fn changed(&self) -> Result<(), StudioError> {
        self.ensure_open()?;
        tokio::select! { biased; () = self.cancelled() => Err(cancelled()), () = self.credit.notified() => Ok(()),
        result = async { self.updates.lock().await.changed().await } => result.map_err(|_| StudioError::new(StudioErrorCode::Unavailable, "PersistenceQueue source disappeared", true)), }
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
        send: impl FnOnce(PersistenceQueueFrame) -> Result<(), StudioError>,
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
                send(PersistenceQueueFrame::Closed {
                    identity: self.identity.clone(),
                    reason,
                })
            })
    }
    pub fn send_failure(
        &self,
        error: StudioError,
        send: impl FnOnce(PersistenceQueueFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| {
                send(PersistenceQueueFrame::Failure {
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
impl Drop for StudioPersistenceQueueFeed {
    fn drop(&mut self) {
        self.request_close();
    }
}
fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "PersistenceQueue feed is closing",
        false,
    )
}
