use super::super::{
    StudioRuntime, lifecycle::shutdown::ShutdownLatch, models::delivery_window::DeliveryWindow,
};
use super::source::{UpdatesMaterial, UpdatesSource, cancelled};
use pl_protocol::products::feed::updates::*;
use pl_protocol::products::identity::{
    ProductFeedCloseReason, ProductFeedIdentity, ProductProjectionStamp, ProductResource,
};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::future::Future;
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, watch};
use tokio_util::sync::CancellationToken;

struct Window {
    delivery: DeliveryWindow<UpdatesMaterial>,
    previous: Option<Arc<UpdatesMaterial>>,
}
pub struct StudioUpdatesFeed {
    identity: ProductFeedIdentity,
    source: Arc<UpdatesSource>,
    runtime_stop: ShutdownLatch,
    cancel: CancellationToken,
    updates: tokio::sync::Mutex<watch::Receiver<()>>,
    credit: Notify,
    window: Mutex<Window>,
}
impl StudioRuntime {
    pub fn open_updates(
        &self,
    ) -> impl Future<Output = anyhow::Result<StudioUpdatesFeed>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let source = runtime.updates_source.clone();
            let (material, updates) = source.observe()?;
            let origin = source.origin();
            let feed = StudioUpdatesFeed {
                identity: ProductFeedIdentity {
                    feed_id: crate::studio::new_id("product-feed"),
                    owner_epoch: origin.owner_epoch.clone(),
                    incarnation: origin.incarnation,
                    resource: ProductResource::Updates,
                },
                source,
                runtime_stop: runtime.shutdown_latch.clone(),
                cancel: CancellationToken::new(),
                updates: tokio::sync::Mutex::new(updates),
                credit: Notify::new(),
                window: Mutex::new(Window {
                    delivery: DeliveryWindow::new(material),
                    previous: None,
                }),
            };
            feed.ensure_open()?;
            Ok(feed)
        })
    }
}
impl StudioUpdatesFeed {
    pub fn identity(&self) -> ProductFeedIdentity {
        self.identity.clone()
    }
    fn check(&self, window: &Window) -> Result<(), StudioError> {
        if window.delivery.closing || self.cancel.is_cancelled() || self.runtime_stop.is_committed()
        {
            return Err(cancelled());
        }
        self.source.ensure_open()
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
        window.delivery.claim("Updates")
    }
    pub fn send_pending(
        &self,
        send: impl FnOnce(UpdatesFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&window)?;
        window.delivery.require_claimed("Updates")?;
        let material = match self.source.next_after(
            window
                .previous
                .as_ref()
                .map(|value| value.reference.revision),
        ) {
            Ok(Some(material)) => material,
            Ok(None) => return Ok(false),
            Err(error) if error.code == StudioErrorCode::Superseded => {
                window.delivery.closing = true;
                let result = window.delivery.send_control(|| {
                    send(UpdatesFrame::ResyncRequired {
                        identity: self.identity.clone(),
                        reason:
                            pl_protocol::products::identity::ProductResyncReason::ReliableQueueFull,
                    })
                });
                drop(window);
                self.cancel.cancel();
                result?;
                return Ok(true);
            }
            Err(error) => return Err(error),
        };
        window.delivery.pending = Some(material.clone());
        let stamp = ProductProjectionStamp {
            owner_epoch: self.identity.owner_epoch.clone(),
            incarnation: self.identity.incarnation,
            revision: material.reference.revision,
        };
        let header = super::material::feed_header(&material);
        let event = match &window.previous {
            None => UpdatesEvent::Baseline {
                identity: self.identity.clone(),
                stamp,
                value: header,
            },
            Some(old) => UpdatesEvent::Replace {
                stamp,
                base_revision: old.reference.revision,
                value: header,
            },
        };
        let sent = self.source.send_exposing(&material, || {
            window
                .delivery
                .deliver(
                    "Updates",
                    |delivery_sequence, _| {
                        Ok(UpdatesFrame::Data {
                            delivery_sequence,
                            event,
                        })
                    },
                    send,
                )
                .map(|sent| sent.is_some())
        })?;
        if sent {
            window.previous = Some(material);
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
            window.delivery.ack_through(sequence, "Updates")?;
        }
        self.credit.notify_one();
        Ok(())
    }
    pub async fn changed(&self) -> Result<(), StudioError> {
        tokio::select! { biased; () = self.cancelled() => Err(cancelled()), () = self.credit.notified() => Ok(()),
        result = async { self.updates.lock().await.changed().await } => result.map_err(|_| StudioError::new(StudioErrorCode::Unavailable, "Update source disappeared", true)), }
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
        self.ensure_open()
            .is_err_and(|error| error.code == StudioErrorCode::Cancelled)
    }
    pub fn send_closed(
        &self,
        send: impl FnOnce(UpdatesFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        let reason = if self.runtime_stop.is_committed() || self.source.ensure_open().is_err() {
            ProductFeedCloseReason::RuntimeStopped
        } else {
            ProductFeedCloseReason::Requested
        };
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| {
                send(UpdatesFrame::Closed {
                    identity: self.identity.clone(),
                    reason,
                })
            })
    }
    pub fn send_failure(
        &self,
        error: StudioError,
        send: impl FnOnce(UpdatesFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| {
                send(UpdatesFrame::Failure {
                    identity: self.identity.clone(),
                    error,
                })
            })
    }
}
impl Drop for StudioUpdatesFeed {
    fn drop(&mut self) {
        self.request_close();
    }
}
