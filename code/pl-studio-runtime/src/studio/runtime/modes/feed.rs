use super::super::{
    StudioRuntime, lifecycle::shutdown::ShutdownLatch, models::delivery_window::DeliveryWindow,
};
use super::source::{ModesMaterial, ModesSource, cancelled};
use pl_protocol::products::feed::mode_catalog::*;
use pl_protocol::products::identity::{
    ProductFeedCloseReason, ProductFeedIdentity, ProductProjectionStamp, ProductResource,
};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::future::Future;
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, watch};
use tokio_util::sync::CancellationToken;

struct Window {
    delivery: DeliveryWindow<ModesMaterial>,
    previous: Option<Arc<ModesMaterial>>,
}
pub struct StudioModeCatalogFeed {
    identity: ProductFeedIdentity,
    source: Arc<ModesSource>,
    runtime_stop: ShutdownLatch,
    cancel: CancellationToken,
    updates: tokio::sync::Mutex<watch::Receiver<()>>,
    credit: Notify,
    window: Mutex<Window>,
}
impl StudioRuntime {
    pub fn open_mode_catalog(
        &self,
    ) -> impl Future<Output = anyhow::Result<StudioModeCatalogFeed>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            runtime
                .modes_source
                .publish(runtime.read_thread_mode_catalog())?;
            let source = runtime.modes_source.clone();
            let (material, updates) = source.observe()?;
            let origin = source.origin();
            let feed = StudioModeCatalogFeed {
                identity: ProductFeedIdentity {
                    feed_id: crate::studio::new_id("product-feed"),
                    owner_epoch: origin.owner_epoch.clone(),
                    incarnation: origin.incarnation,
                    resource: ProductResource::ModeCatalog,
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
impl StudioModeCatalogFeed {
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
        window.delivery.claim("Modes")
    }
    pub fn send_pending(
        &self,
        send: impl FnOnce(ModeCatalogFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&window)?;
        window.delivery.require_claimed("Modes")?;
        let material = self.source.current()?;
        if window
            .previous
            .as_ref()
            .is_some_and(|old| old.reference == material.reference)
        {
            return Ok(false);
        }
        window.delivery.pending = Some(material.clone());
        if let Some(old) = &window.previous {
            let changes = material
                .entities
                .iter()
                .filter(|entry| !old.entities.contains(entry))
                .count()
                + old
                    .entities
                    .iter()
                    .filter(|old| {
                        !material
                            .entities
                            .iter()
                            .any(|entry| entry.entry == old.entry)
                    })
                    .count();
            if changes > 100 {
                window.delivery.closing = true;
                let result = window.delivery.send_control(|| {
                    send(ModeCatalogFrame::ResyncRequired {
                        identity: self.identity.clone(),
                        reason: pl_protocol::products::identity::ProductResyncReason::SourceLagged,
                    })
                });
                drop(window);
                self.cancel.cancel();
                result?;
                return Ok(true);
            }
        }
        let stamp = ProductProjectionStamp {
            owner_epoch: self.identity.owner_epoch.clone(),
            incarnation: self.identity.incarnation,
            revision: material.reference.revision,
        };
        let header = ModeCatalogHeader {
            revision: material.value.revision,
            reference: material.reference,
        };
        let event = match &window.previous {
            None => ModeCatalogEvent::Baseline {
                identity: self.identity.clone(),
                stamp,
                value: ModeCatalogBaseline {
                    header,
                    collection: Some(material.collection),
                },
            },
            Some(old) => ModeCatalogEvent::Change {
                stamp,
                base_revision: old.reference.revision,
                value: ModeCatalogChange {
                    header,
                    base_collection_revision: Some(old.collection.revision),
                    collection: Some(material.collection),
                    upserted: material
                        .entities
                        .iter()
                        .filter(|entry| !old.entities.contains(entry))
                        .copied()
                        .collect(),
                    removed_entries: old
                        .entities
                        .iter()
                        .filter(|old| !material.entities.iter().any(|item| item.entry == old.entry))
                        .map(|item| item.entry)
                        .collect(),
                },
            },
        };
        let sent = self.source.send_exposing(&material, || {
            window
                .delivery
                .deliver(
                    "Modes",
                    |delivery_sequence, _| {
                        Ok(ModeCatalogFrame::Data {
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
            window.delivery.ack_through(sequence, "Modes")?;
        }
        self.credit.notify_one();
        Ok(())
    }
    pub async fn changed(&self) -> Result<(), StudioError> {
        tokio::select! { biased; () = self.cancelled() => Err(cancelled()), () = self.credit.notified() => Ok(()),
        result = async { self.updates.lock().await.changed().await } => result.map_err(|_| StudioError::new(StudioErrorCode::Unavailable, "Mode source disappeared", true)), }
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
        send: impl FnOnce(ModeCatalogFrame) -> Result<(), StudioError>,
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
                send(ModeCatalogFrame::Closed {
                    identity: self.identity.clone(),
                    reason,
                })
            })
    }
    pub fn send_failure(
        &self,
        error: StudioError,
        send: impl FnOnce(ModeCatalogFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| {
                send(ModeCatalogFrame::Failure {
                    identity: self.identity.clone(),
                    error,
                })
            })
    }
}
impl Drop for StudioModeCatalogFeed {
    fn drop(&mut self) {
        self.request_close();
    }
}
