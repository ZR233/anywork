//! One Templates delivery window, shared by native and HTTP transports; no worker or extra pool.
use std::future::Future;
use std::sync::Mutex;

use pl_protocol::products::feed::account_templates::{
    AccountTemplatesBaseline, AccountTemplatesEvent, AccountTemplatesHeader,
};
use pl_protocol::products::identity::{
    ProductFeedCloseReason, ProductProjectionStamp, ProductResource,
};
use pl_protocol::studio::StudioErrorCode;
use tokio_util::sync::CancellationToken;

use super::super::StudioRuntime;
use super::delivery_window::DeliveryWindow;
use super::templates_source::TemplatesMaterial;
use super::{AccountTemplatesFrame, ProductFeedIdentity, StudioError};

/// Transport-owned feed responsibility, not a single query: it remains open until cancellation.
/// The transport registers its real producer/consumer completion before opening this object, and
/// retains it until those tasks genuinely join. Dropping this value is not a Clean acknowledgement.
pub struct StudioAccountTemplatesFeed {
    identity: ProductFeedIdentity,
    runtime_stop: CancellationToken,
    cancel: CancellationToken,
    window: Mutex<DeliveryWindow<TemplatesMaterial>>,
}

impl StudioRuntime {
    /// Capture this runtime's original builtin material and close notification in one admission.
    /// No templates JSON load, Config read, string-revision hash or new incarnation is performed.
    ///
    /// # Errors
    /// Returns Cancelled after the original runtime fence, or the shared opening-call limit error.
    pub fn open_account_templates(
        &self,
    ) -> impl Future<Output = anyhow::Result<StudioAccountTemplatesFeed>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let (material, runtime_stop) = runtime.templates_source.observe()?;
            let origin = runtime.templates_source.origin();
            let feed = StudioAccountTemplatesFeed {
                identity: ProductFeedIdentity {
                    feed_id: crate::studio::new_id("product-feed"),
                    owner_epoch: origin.owner_epoch.clone(),
                    incarnation: origin.incarnation,
                    resource: ProductResource::AccountTemplates,
                },
                cancel: runtime_stop.child_token(),
                runtime_stop,
                window: Mutex::new(DeliveryWindow::new(material)),
            };
            feed.ensure_open()?;
            Ok(feed)
        })
    }
}

impl StudioAccountTemplatesFeed {
    /// The original fixed-source incarnation and this connection's distinct feed ID.
    pub fn identity(&self) -> ProductFeedIdentity {
        self.identity.clone()
    }

    /// # Errors
    /// Returns Cancelled once this feed or its original runtime has been sealed.
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        let window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window)
    }

    /// Called only by the actual first listen, not an events getter. Closing wins over Conflict.
    ///
    /// # Errors
    /// Returns Cancelled for closing, or Conflict if an actual listener already claimed it.
    pub fn claim(&self) -> Result<(), StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window)?;
        window.claim("AccountTemplates")
    }

    /// The original material is retained in the two-Data window only on an actual successful
    /// transport send. `send` must be bounded, synchronous and non-reentrant (FRB port add or HTTP
    /// try_send), as in the existing Metrics delivery boundary. It must never await or ACK inline.
    ///
    /// # Errors
    /// Returns the typed closing/claim/budget error or the actual transport send failure.
    pub fn send_pending(
        &self,
        send: impl FnOnce(AccountTemplatesFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window)?;
        window
            .deliver(
                "AccountTemplates",
                |sequence, material| {
                    let event = AccountTemplatesEvent::Baseline {
                        identity: self.identity.clone(),
                        stamp: ProductProjectionStamp {
                            owner_epoch: self.identity.owner_epoch.clone(),
                            incarnation: self.identity.incarnation,
                            revision: 1,
                        },
                        value: AccountTemplatesBaseline {
                            header: AccountTemplatesHeader {
                                schema_version: material.value.schema_version,
                                reference: material.reference,
                            },
                            collection: Some(material.collection),
                        },
                    };
                    Ok(AccountTemplatesFrame::Data {
                        delivery_sequence: sequence,
                        event,
                    })
                },
                send,
            )
            .map(|material| material.is_some())
    }

    /// ACK is valid only for this handle's actually sent continuous prefix, including baseline.
    ///
    /// # Errors
    /// Returns Cancelled for closing, or Protocol if ACK exceeds this connection's sent prefix.
    pub fn ack_through(&self, delivery_sequence: u64) -> Result<(), StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window)?;
        window.ack_through(delivery_sequence, "AccountTemplates")
    }

    /// Synchronously seal and notify; the registered transport still has to join its real tasks.
    pub fn request_close(&self) {
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .closing = true;
        self.cancel.cancel();
    }

    /// Both the original runtime fence and a local request permanently wake this retained token.
    pub fn cancelled(&self) -> impl Future<Output = ()> + Send + 'static + use<> {
        let cancel = self.cancel.clone();
        async move { cancel.cancelled().await }
    }

    pub fn is_closing(&self) -> bool {
        let window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        window.closing || self.cancel.is_cancelled()
    }

    /// Terminal controls use no Data credit and are attempted at most once, even with a full
    /// unACK window. Material is not released here; the transport must still join its real tasks.
    ///
    /// # Errors
    /// Returns the original sink error without turning a failed terminal send into Clean.
    pub fn send_closed(
        &self,
        send: impl FnOnce(AccountTemplatesFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        let reason = if self.runtime_stop.is_cancelled() {
            ProductFeedCloseReason::RuntimeStopped
        } else {
            ProductFeedCloseReason::Requested
        };
        self.send_control(
            AccountTemplatesFrame::Closed {
                identity: self.identity.clone(),
                reason,
            },
            send,
        )
    }

    /// Seal with one typed Failure, preserving the same material and join responsibility.
    ///
    /// # Errors
    /// Returns the original sink error; no additional Closed is sent after this control terminal.
    pub fn send_failure(
        &self,
        error: StudioError,
        send: impl FnOnce(AccountTemplatesFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        self.send_control(
            AccountTemplatesFrame::Failure {
                identity: self.identity.clone(),
                error,
            },
            send,
        )
    }

    fn send_control(
        &self,
        frame: AccountTemplatesFrame,
        send: impl FnOnce(AccountTemplatesFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        window.send_control(|| send(frame))
    }

    fn check_open(&self, window: &DeliveryWindow<TemplatesMaterial>) -> Result<(), StudioError> {
        if window.closing || self.cancel.is_cancelled() {
            Err(StudioError::new(
                StudioErrorCode::Cancelled,
                "AccountTemplates feed is closing",
                false,
            ))
        } else {
            Ok(())
        }
    }
}
