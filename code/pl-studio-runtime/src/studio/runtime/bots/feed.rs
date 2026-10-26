//! One supervised transport, the existing two-Data window and original Bots topic captures.
use std::future::Future;
use std::sync::{Arc, Mutex};

use pl_protocol::products::identity::{
    ProductFeedCloseReason, ProductProjectionStamp, ProductResource, ProductResyncReason,
};
use pl_protocol::studio::StudioErrorCode;
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

use super::super::models::delivery_window::DeliveryWindow;
use super::super::{
    StudioProductTopicSubscription, StudioRuntime, lifecycle::shutdown::ShutdownLatch,
};
use super::source::{BotsPublication, BotsSource};
use super::{BotsEvent, BotsFrame, ProductFeedIdentity, StudioError};
use crate::{
    StudioProductBaselineState, StudioProductEventKind, StudioProductFrame, StudioProductTopic,
};

struct Window {
    delivery: DeliveryWindow<BotsPublication>,
    previous_revision: Option<u64>,
    resync: Option<ProductResyncReason>,
}

pub struct StudioBotsFeed {
    identity: ProductFeedIdentity,
    source: Arc<BotsSource>,
    runtime_stop: ShutdownLatch,
    cancel: CancellationToken,
    subscription: tokio::sync::Mutex<StudioProductTopicSubscription>,
    credit: Notify,
    window: Mutex<Window>,
}

impl StudioRuntime {
    /// Registers the existing Bots topic before capturing its canonical baseline. No load,
    /// registration, token, credential or connection work is admitted by this opening.
    pub fn open_bots(
        &self,
    ) -> impl Future<Output = anyhow::Result<StudioBotsFeed>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let mut subscription = runtime
                .subscribe_product_topic(StudioProductTopic::Bots)
                .await?;
            let Some(StudioProductFrame::Baseline(baseline)) = subscription.recv().await? else {
                return Err(protocol().into());
            };
            let StudioProductBaselineState::Bots(value) = baseline.state else {
                return Err(protocol().into());
            };
            let source = runtime.bots_source.clone();
            let publication = source.capture(*value)?;
            let origin = source.origin();
            let feed = StudioBotsFeed {
                identity: ProductFeedIdentity {
                    feed_id: crate::studio::new_id("product-feed"),
                    owner_epoch: origin.owner_epoch.clone(),
                    incarnation: origin.incarnation,
                    resource: ProductResource::Bots,
                },
                source,
                runtime_stop: runtime.shutdown_latch.clone(),
                cancel: CancellationToken::new(),
                subscription: tokio::sync::Mutex::new(subscription),
                credit: Notify::new(),
                window: Mutex::new(Window {
                    delivery: DeliveryWindow::new(publication),
                    previous_revision: None,
                    resync: None,
                }),
            };
            feed.ensure_open()?;
            Ok(feed)
        })
    }
}

impl StudioBotsFeed {
    pub fn identity(&self) -> ProductFeedIdentity {
        self.identity.clone()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.check_open(
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
        self.check_open(&window)?;
        window.delivery.claim("Bots")
    }

    /// Synchronous, bounded, non-reentrant transport callback; only an actual successful send
    /// advances the prefix and exposes source status. Baseline uses ordinary Data credit.
    pub fn send_pending(
        &self,
        send: impl FnOnce(BotsFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window)?;
        window.delivery.require_claimed("Bots")?;
        if let Some(reason) = window.resync {
            window.delivery.closing = true;
            let result = window.delivery.send_control(|| {
                send(BotsFrame::ResyncRequired {
                    identity: self.identity.clone(),
                    reason,
                })
            });
            drop(window);
            self.cancel.cancel();
            result?;
            return Ok(true);
        }
        if !window.delivery.has_credit() {
            return Ok(false);
        }
        let Some(publication) = window.delivery.pending.clone() else {
            return Ok(false);
        };
        let revision = publication.value.revision;
        if window
            .previous_revision
            .is_some_and(|previous| revision <= previous)
        {
            window.delivery.pending.take();
            return Ok(false);
        }
        let stamp = ProductProjectionStamp {
            owner_epoch: self.identity.owner_epoch.clone(),
            incarnation: self.identity.incarnation,
            revision,
        };
        let header = publication.header();
        let state = Some((*publication.value).clone());
        let event = match window.previous_revision {
            None => BotsEvent::Baseline {
                identity: self.identity.clone(),
                stamp,
                header,
                state,
            },
            Some(base_revision) => BotsEvent::StateChanged {
                stamp,
                base_revision,
                header,
                state,
            },
        };
        let sent = self.source.send_exposing(&publication, || {
            window
                .delivery
                .deliver(
                    "Bots",
                    |delivery_sequence, _| {
                        Ok(BotsFrame::Data {
                            delivery_sequence,
                            event: Box::new(event),
                        })
                    },
                    send,
                )
                .map(|sent| sent.is_some())
        })?;
        if sent {
            window.previous_revision = Some(revision);
        }
        Ok(sent)
    }

    pub fn ack_through(&self, delivery_sequence: u64) -> Result<(), StudioError> {
        {
            let mut window = self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            self.check_open(&window)?;
            window.delivery.ack_through(delivery_sequence, "Bots")?;
        }
        self.credit.notify_one();
        Ok(())
    }

    pub async fn changed(&self) -> Result<(), StudioError> {
        tokio::select! { biased;
            () = self.cancelled() => Err(cancelled()),
            () = self.credit.notified() => Ok(()),
            frame = async { self.subscription.lock().await.recv().await } => {
                let frame = frame.map_err(|error| crate::error_mapping::studio_error_from_anyhow_ref(&error))?;
                match frame {
                    Some(StudioProductFrame::Event(envelope)) => {
                        let StudioProductEventKind::BotsStateChanged(value) = envelope.kind else { return Err(protocol()); };
                        let publication = self.source.capture(value)?;
                        let mut window = self.window.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
                        self.check_open(&window)?;
                        if !window.previous_revision.is_some_and(|revision| publication.value.revision <= revision) {
                            window.delivery.pending = Some(publication);
                        }
                        Ok(())
                    }
                    Some(StudioProductFrame::Lagged { .. }) => {
                        let mut window = self.window.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
                        self.check_open(&window)?;
                        window.resync = Some(ProductResyncReason::SourceLagged);
                        Ok(())
                    }
                    Some(StudioProductFrame::Baseline(_)) => Err(protocol()),
                    None => Err(StudioError::new(StudioErrorCode::Unavailable, "The original Bots topic closed", true)),
                }
            },
        }
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
        self.ensure_open().is_err()
    }
    pub fn send_closed(
        &self,
        send: impl FnOnce(BotsFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        let reason = if self.runtime_stop.is_committed() || self.source.ensure_open().is_err() {
            ProductFeedCloseReason::RuntimeStopped
        } else {
            ProductFeedCloseReason::Requested
        };
        self.control(
            BotsFrame::Closed {
                identity: self.identity.clone(),
                reason,
            },
            send,
        )
    }
    pub fn send_failure(
        &self,
        error: StudioError,
        send: impl FnOnce(BotsFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        self.control(
            BotsFrame::Failure {
                identity: self.identity.clone(),
                error,
            },
            send,
        )
    }
    fn control(
        &self,
        frame: BotsFrame,
        send: impl FnOnce(BotsFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| send(frame))
    }
    fn check_open(&self, window: &Window) -> Result<(), StudioError> {
        if window.delivery.closing || self.cancel.is_cancelled() || self.runtime_stop.is_committed()
        {
            return Err(cancelled());
        }
        self.source.ensure_open()
    }
}

impl Drop for StudioBotsFeed {
    fn drop(&mut self) {
        self.request_close();
    }
}
fn cancelled() -> StudioError {
    StudioError::new(StudioErrorCode::Cancelled, "Bots feed is closing", false)
}
fn protocol() -> StudioError {
    StudioError::new(
        StudioErrorCode::Protocol,
        "Bots topic returned another publication type",
        false,
    )
}
