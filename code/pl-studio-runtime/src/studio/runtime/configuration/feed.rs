//! Shared two-unACK window, one latest pending and actual-send reference exposure.
use pl_protocol::products::identity::{ProductFeedCloseReason, ProductResource};
use pl_protocol::studio::StudioErrorCode;
use std::future::Future;
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, watch};
use tokio_util::sync::CancellationToken;

use super::super::models::delivery_window::DeliveryWindow;
use super::super::{StudioRuntime, lifecycle::shutdown::ShutdownLatch};
use super::frames::{self, FrameError, SentConfiguration};
use super::{ConfigurationFrame, ProductFeedIdentity, StudioError};
use crate::config::{ConfigurationCaptureFailure, ConfigurationSnapshot, ConfigurationSource};

struct Window {
    delivery: DeliveryWindow<ConfigurationSnapshot>,
    previous: Option<SentConfiguration>,
    opening_failure: Option<Arc<ConfigurationCaptureFailure>>,
}

/// No worker or second payload cache: the existing supervised transport owns this connection.
pub struct StudioConfigurationFeed {
    identity: ProductFeedIdentity,
    source: Arc<ConfigurationSource>,
    runtime_stop: ShutdownLatch,
    cancel: CancellationToken,
    updates: tokio::sync::Mutex<watch::Receiver<()>>,
    credit: Notify,
    window: Mutex<Window>,
}

impl StudioRuntime {
    pub fn open_configuration(
        &self,
    ) -> impl Future<Output = anyhow::Result<StudioConfigurationFeed>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let source = runtime.configuration_source.clone();
            let (snapshot, updates) = source.observe()?;
            frames::validate(&snapshot)?;
            let origin = source.origin();
            let feed = StudioConfigurationFeed {
                identity: ProductFeedIdentity {
                    feed_id: crate::studio::new_id("product-feed"),
                    owner_epoch: origin.owner_epoch.clone(),
                    incarnation: origin.incarnation,
                    resource: ProductResource::Configuration,
                },
                window: Mutex::new(Window {
                    opening_failure: snapshot.last_failure.clone(),
                    delivery: DeliveryWindow::new(snapshot),
                    previous: None,
                }),
                source,
                runtime_stop: runtime.shutdown_latch.clone(),
                cancel: CancellationToken::new(),
                updates: tokio::sync::Mutex::new(updates),
                credit: Notify::new(),
            };
            feed.ensure_open()?;
            Ok(feed)
        })
    }
}

impl StudioConfigurationFeed {
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
        window.delivery.claim("Configuration")
    }

    /// `send` must be synchronous, bounded and non-reentrant (including inline ACK/read).
    /// Failed build/budget/send keeps the sent prefix and exact pending pin unchanged.
    pub fn send_pending(
        &self,
        send: impl FnOnce(ConfigurationFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window)?;
        window.delivery.require_claimed("Configuration")?;
        let snapshot = self.source.current()?;
        frames::validate(&snapshot)?;
        if let Some(failure) = &snapshot.last_failure
            && !window
                .opening_failure
                .as_ref()
                .is_some_and(|opening| Arc::ptr_eq(opening, failure))
        {
            return Err(failure.diagnostic.clone());
        }
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
            Err(FrameError::Source(error)) => return Err(error),
            Err(FrameError::Resync(reason)) => {
                window.delivery.closing = true;
                let result = window.delivery.send_control(|| {
                    send(ConfigurationFrame::ResyncRequired {
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
        let previous = SentConfiguration::capture(&snapshot)?;
        let sent = self.source.send_exposing(&snapshot, || {
            window
                .delivery
                .deliver(
                    "Configuration",
                    |sequence, _| {
                        Ok(ConfigurationFrame::Data {
                            delivery_sequence: sequence,
                            event: Box::new(event),
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

    /// Only this handle's actual sent prefix can be ACKed. Baseline occupies ordinary Data credit.
    pub fn ack_through(&self, delivery_sequence: u64) -> Result<(), StudioError> {
        {
            let mut window = self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            self.check_open(&window)?;
            window
                .delivery
                .ack_through(delivery_sequence, "Configuration")?;
        }
        self.credit.notify_one();
        Ok(())
    }

    pub async fn changed(&self) -> Result<(), StudioError> {
        tokio::select! { biased;
            () = self.cancelled() => Err(cancelled()),
            () = self.credit.notified() => Ok(()),
            result = async { self.updates.lock().await.changed().await } => result.map_err(|_| StudioError::new(
                StudioErrorCode::Unavailable, "The original Configuration source disappeared", true)),
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
        send: impl FnOnce(ConfigurationFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        let reason = if self.runtime_stop.is_committed() || self.source.current().is_err() {
            ProductFeedCloseReason::RuntimeStopped
        } else {
            ProductFeedCloseReason::Requested
        };
        self.control(
            ConfigurationFrame::Closed {
                identity: self.identity.clone(),
                reason,
            },
            send,
        )
    }
    pub fn send_failure(
        &self,
        error: StudioError,
        send: impl FnOnce(ConfigurationFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        self.control(
            ConfigurationFrame::Failure {
                identity: self.identity.clone(),
                error,
            },
            send,
        )
    }
    fn control(
        &self,
        frame: ConfigurationFrame,
        send: impl FnOnce(ConfigurationFrame) -> Result<(), StudioError>,
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

impl Drop for StudioConfigurationFeed {
    fn drop(&mut self) {
        self.request_close();
    }
}
fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Configuration feed is closing",
        false,
    )
}
