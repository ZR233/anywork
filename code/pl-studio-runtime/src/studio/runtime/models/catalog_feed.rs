//! The original Catalog publication, a latest pending slot and the shared two-Data ACK window.
use std::future::Future;
use std::sync::{Arc, Mutex};

use pl_protocol::products::identity::{ProductFeedCloseReason, ProductResource};
use pl_protocol::studio::StudioErrorCode;
use tokio::sync::watch;
use tokio_util::sync::CancellationToken;

use super::super::{StudioRuntime, lifecycle::shutdown::ShutdownLatch};
use super::catalog_frames::{self, CatalogEventError, SentCatalog};
use super::delivery_window::DeliveryWindow;
use super::{ModelCatalogFrame, ProductFeedIdentity, StudioError};
use crate::config::{ModelCaptureFailure, ModelCatalogSource, ModelsSnapshot};

struct CatalogWindow {
    delivery: DeliveryWindow<ModelsSnapshot>,
    previous: Option<SentCatalog>,
    opening_failure: Option<Arc<ModelCaptureFailure>>,
}

/// A connection to one original Catalog source. It owns no worker, registry or Configuration
/// mirror: the supervised transport runs delivery and retains this window until actual join.
pub struct StudioModelCatalogFeed {
    identity: ProductFeedIdentity,
    source: Arc<ModelCatalogSource>,
    runtime_stop: ShutdownLatch,
    cancel: CancellationToken,
    updates: tokio::sync::Mutex<watch::Receiver<()>>,
    window: Mutex<CatalogWindow>,
}

impl StudioRuntime {
    /// Register the source receiver and capture the compatible baseline under its original guard.
    /// Opening is supervised by the existing shared read-call owner before the returned await.
    ///
    /// # Errors
    /// Returns original capture/metadata errors, Cancelled after sealing, or shared admission errors.
    pub fn open_model_catalog(
        &self,
    ) -> impl Future<Output = anyhow::Result<StudioModelCatalogFeed>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            if runtime.shutdown_committed() {
                return Err(cancelled().into());
            }
            let source = runtime.models_source.clone();
            let (snapshot, updates) = source.observe()?;
            catalog_frames::validate(&snapshot)?;
            let origin = source.origin();
            let feed = StudioModelCatalogFeed {
                identity: ProductFeedIdentity {
                    feed_id: crate::studio::new_id("product-feed"),
                    owner_epoch: origin.owner_epoch.clone(),
                    incarnation: origin.incarnation,
                    resource: ProductResource::ModelCatalog,
                },
                window: Mutex::new(CatalogWindow {
                    opening_failure: snapshot.last_failure.clone(),
                    delivery: DeliveryWindow::new(snapshot),
                    previous: None,
                }),
                source,
                runtime_stop: runtime.shutdown_latch.clone(),
                cancel: CancellationToken::new(),
                updates: tokio::sync::Mutex::new(updates),
            };
            feed.ensure_open()?;
            Ok(feed)
        })
    }
}

impl StudioModelCatalogFeed {
    pub fn identity(&self) -> ProductFeedIdentity {
        self.identity.clone()
    }

    /// # Errors
    /// Returns Cancelled after this connection, the original source or runtime has been sealed.
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        let window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window)
    }

    /// Only an actual listener calls this; getters do not claim. Closing wins over Conflict.
    ///
    /// # Errors
    /// Returns Cancelled for closing or Conflict for a second actual listener.
    pub fn claim(&self) -> Result<(), StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window)?;
        window.delivery.claim("ModelCatalog")
    }

    /// Coalesce only original publications. Capture failures, including a failure merged away by
    /// watch, are terminal; a newer Ready cannot hide them. Source/member identities are never
    /// rebuilt here. At most one pending snapshot and two successfully sent Data pins are held.
    /// `send` must be bounded, synchronous and non-reentrant, and must not ACK inline.
    ///
    /// # Errors
    /// Returns the original capture/metadata, claim, budget or actual transport error.
    pub fn send_pending(
        &self,
        send: impl FnOnce(ModelCatalogFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window)?;
        window.delivery.require_claimed("ModelCatalog")?;
        let snapshot = self.source.current()?;
        catalog_frames::validate(&snapshot)?;
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
        let event = match catalog_frames::event(&self.identity, &snapshot, window.previous.as_ref())
        {
            Ok(event) => event,
            Err(CatalogEventError::Source(error)) => return Err(error),
            Err(CatalogEventError::Resync(reason)) => {
                // An unrepresentable delta seals only this connection. A control does not wait
                // for Data credit, and a new connection can read the full current index by page.
                window.delivery.closing = true;
                let result = window.delivery.send_control(|| {
                    send(ModelCatalogFrame::ResyncRequired {
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
        let previous = SentCatalog::capture(&snapshot)?;
        let sent = window.delivery.deliver(
            "ModelCatalog",
            |sequence, _| {
                Ok(ModelCatalogFrame::Data {
                    delivery_sequence: sequence,
                    event,
                })
            },
            send,
        )?;
        if sent.is_some() {
            window.previous = Some(previous);
        }
        Ok(sent.is_some())
    }

    /// # Errors
    /// Returns Cancelled for closing or Protocol beyond this handle's actually sent prefix.
    pub fn ack_through(&self, delivery_sequence: u64) -> Result<(), StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window)?;
        window
            .delivery
            .ack_through(delivery_sequence, "ModelCatalog")
    }

    /// Wait for a retained source wake, not a query/polling transport. Exactly one supervised
    /// producer waits on this receiver; the async guard protects only that receiver across await.
    /// Dropping this wait cannot consume a watch change, release a pin or abandon a spawned task.
    ///
    /// # Errors
    /// Returns Cancelled on local/runtime close or Unavailable if the original source disappears.
    pub async fn changed(&self) -> Result<(), StudioError> {
        tokio::select! { biased;
            () = self.cancelled() => Err(cancelled()),
            result = async { self.updates.lock().await.changed().await } => {
                result.map_err(|_| StudioError::new(StudioErrorCode::Unavailable,
                    "The original ModelCatalog source is unavailable", true))
            }
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

    /// Local close and the original runtime fence permanently wake this token-based wait.
    pub fn cancelled(&self) -> impl Future<Output = ()> + Send + 'static + use<> {
        let cancel = self.cancel.clone();
        let runtime_stop = self.runtime_stop.clone();
        async move {
            tokio::select! { biased;
                () = cancel.cancelled() => {},
                () = runtime_stop.committed() => {},
            }
        }
    }

    pub fn is_closing(&self) -> bool {
        let window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window).is_err()
    }

    /// The unique control is ordered after earlier sends, bypasses Data credit, and keeps every
    /// material pin until the supervised transport actually joins and releases this owner.
    ///
    /// # Errors
    /// Returns the original transport error; failed terminal delivery is not Clean.
    pub fn send_closed(
        &self,
        send: impl FnOnce(ModelCatalogFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        let reason = if self.runtime_stop.is_committed() || self.source.current().is_err() {
            ProductFeedCloseReason::RuntimeStopped
        } else {
            ProductFeedCloseReason::Requested
        };
        self.send_control(
            ModelCatalogFrame::Closed {
                identity: self.identity.clone(),
                reason,
            },
            send,
        )
    }

    /// # Errors
    /// Returns the original sink error, without issuing a second control after this Failure.
    pub fn send_failure(
        &self,
        error: StudioError,
        send: impl FnOnce(ModelCatalogFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        self.send_control(
            ModelCatalogFrame::Failure {
                identity: self.identity.clone(),
                error,
            },
            send,
        )
    }

    fn send_control(
        &self,
        frame: ModelCatalogFrame,
        send: impl FnOnce(ModelCatalogFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| send(frame))
    }

    fn check_open(&self, window: &CatalogWindow) -> Result<(), StudioError> {
        if window.delivery.closing || self.cancel.is_cancelled() || self.runtime_stop.is_committed()
        {
            return Err(cancelled());
        }
        self.source.current()?;
        Ok(())
    }
}

impl Drop for StudioModelCatalogFeed {
    fn drop(&mut self) {
        self.request_close();
    }
}

fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "ModelCatalog feed is closing",
        false,
    )
}
