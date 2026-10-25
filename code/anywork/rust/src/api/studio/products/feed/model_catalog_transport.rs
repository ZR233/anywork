//! Catalog's real native stream. The runtime owns its only pending/ACK/material window.
use std::sync::{Arc, Mutex};

use futures::FutureExt;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_studio_runtime::models::{ModelCatalogFrame, StudioModelCatalogFeed};
use tokio::sync::{Notify, oneshot};

use super::super::identity::BridgeProductFeedIdentity;
use super::model_catalog::BridgeModelCatalogFrame;
use crate::api::studio::bridge_runtime::installed_bridge;
use crate::api::studio::subscription::BridgeTaskRegistry;
use crate::api::studio::subscription::typed_feed::{TypedFeedResource, TypedFeedTask, closed};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport};
use crate::frb_generated::StreamSink;

struct CatalogOwner {
    task: Arc<TypedFeedTask>,
    feed: Mutex<Option<Arc<StudioModelCatalogFeed>>>,
    sink: Mutex<Option<StreamSink<BridgeModelCatalogFrame>>>,
    changed: Notify,
}

/// Owns the producer, sink and original Catalog/source-status pins until confirmed join.
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeModelCatalogFeed {
    owner: Arc<CatalogOwner>,
    registry: &'static BridgeTaskRegistry,
    identity: BridgeProductFeedIdentity,
}

// Successful oneshot delivery is not opaque adoption. Lost/late replies still owe real close.
struct Opening(Option<Arc<CatalogOwner>>);

impl Drop for Opening {
    fn drop(&mut self) {
        if let Some(owner) = &self.0 {
            owner.request_close();
        }
    }
}

/// Open the actual original Catalog source, not Settings, polling or a fresh Ready wrapper.
/// Registration precedes the first runtime await, so late opens remain owned during shutdown.
///
/// # Errors
/// Returns the original typed runtime, metadata, capture or closing/admission error.
pub async fn open_model_catalog() -> Result<BridgeModelCatalogFeed, BridgeError> {
    let bridge = installed_bridge()?;
    let task = TypedFeedTask::new(
        bridge.subscriptions.next_id(),
        bridge.shutdown.child_token(),
    );
    let owner = Arc::new(CatalogOwner {
        task: task.clone(),
        feed: Mutex::new(None),
        sink: Mutex::new(None),
        changed: Notify::new(),
    });
    bridge.subscriptions.register_typed(&task, &owner)?;
    let mut opening = Opening(Some(owner.clone()));
    let (opened, ready) = oneshot::channel();
    let producer = owner.clone();
    if let Err(error) = task.start(async move {
        let feed = match bridge.studio.open_model_catalog().await {
            Ok(feed) => Arc::new(feed),
            Err(error) => {
                producer.request_close();
                let _ = opened.send(Err(BridgeError::from(error)));
                return;
            }
        };
        *producer
            .feed
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(feed.clone());
        let installed = producer.task.admit(|| {
            feed.ensure_open()?;
            Ok(feed.identity())
        });
        match installed {
            Ok(identity) => {
                if opened.send(Ok(identity)).is_err() {
                    producer.request_close();
                }
            }
            Err(error) => {
                producer.request_close();
                let _ = opened.send(Err(error));
            }
        }
        if !producer.wait_sink(&feed).await {
            feed.request_close();
            return;
        }
        let result = std::panic::AssertUnwindSafe(run_delivery(&producer, &feed))
            .catch_unwind()
            .await;
        if let Err(panic) = result {
            if let Err(error) =
                feed.send_failure(StudioError::internal(), |frame| producer.send(frame))
            {
                producer.task.record_failure(error.into());
            }
            std::panic::resume_unwind(panic);
        }
    }) {
        owner.request_close();
        return Err(error);
    }
    let identity = match ready.await {
        Ok(result) => result?,
        Err(_) => {
            owner.request_close();
            return Err(StudioError::internal().into());
        }
    };
    let handle = BridgeModelCatalogFeed {
        owner,
        registry: &bridge.subscriptions,
        identity: identity.into(),
    };
    opening.0.take();
    Ok(handle)
}

impl BridgeModelCatalogFeed {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductFeedIdentity {
        self.identity.clone()
    }

    /// This actual listen claims the stream; a second listen cannot replace the first sink.
    ///
    /// # Errors
    /// Returns Cancelled for closing before considering a second-listener Conflict.
    pub async fn stream(
        &self,
        sink: StreamSink<BridgeModelCatalogFrame>,
    ) -> Result<(), BridgeError> {
        self.owner.task.admit(|| {
            self.owner.feed()?.claim()?;
            *self
                .owner
                .sink
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(sink);
            Ok(())
        })?;
        self.owner.changed.notify_waiters();
        Ok(())
    }

    /// # Errors
    /// Returns the original handle's typed closing or out-of-prefix ACK error.
    pub async fn ack_through(&self, delivery_sequence: u64) -> Result<(), BridgeError> {
        self.owner
            .task
            .admit(|| Ok(self.owner.feed()?.ack_through(delivery_sequence)?))?;
        self.owner.changed.notify_waiters();
        Ok(())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.owner.request_close();
    }

    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.request_close();
        let outcome = if self.owner.task.wait_stopped().await.is_ok() {
            self.registry.unregister_typed(self.owner.task.id);
            BridgeFeedCloseOutcome::Clean
        } else {
            BridgeFeedCloseOutcome::Unresolved {
                issues: self.owner.task.close_issues(),
            }
        };
        Ok(BridgeFeedCloseReport {
            feed_id: self.identity.feed_id.clone(),
            outcome,
        })
    }

    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.close().await
    }
}

impl Drop for BridgeModelCatalogFeed {
    fn drop(&mut self) {
        self.request_close();
    }
}

impl CatalogOwner {
    fn feed(&self) -> Result<Arc<StudioModelCatalogFeed>, BridgeError> {
        self.feed
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
            .ok_or_else(closed)
    }

    fn request_close(&self) {
        self.task.signal_cancel();
        let feed = self
            .feed
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(feed) = feed {
            feed.request_close();
        }
    }

    async fn wait_sink(&self, feed: &StudioModelCatalogFeed) -> bool {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self.task.cancel().is_cancelled() || feed.is_closing() {
                return self.finish_wait_sink();
            }
            if self
                .sink
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .is_some()
            {
                return true;
            }
            tokio::select! { biased;
                () = self.task.cancel().cancelled() => return self.finish_wait_sink(),
                () = feed.cancelled() => return self.finish_wait_sink(),
                result = feed.changed() => {
                    if let Err(error) = result {
                        if error.code != StudioErrorCode::Cancelled { self.task.record_failure(error.into()); }
                        feed.request_close();
                        return self.finish_wait_sink();
                    }
                },
                () = changed => {}
            }
        }
    }

    fn finish_wait_sink(&self) -> bool {
        // Seal the same gate as stream before concluding there is no installed listener. A
        // registration that already won must enter run_delivery's unique typed control path.
        self.task.signal_cancel();
        self.sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .is_some()
    }

    fn send(&self, frame: ModelCatalogFrame) -> Result<(), StudioError> {
        let sink = self
            .sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        sink.as_ref()
            .ok_or_else(transport_failed)?
            .add(frame.into())
            .map_err(|_| transport_failed())
    }
}

#[flutter_rust_bridge::frb(ignore)]
impl TypedFeedResource for CatalogOwner {
    fn release_after_join(&self) {
        self.sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        self.feed
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
    }
}

async fn run_delivery(owner: &CatalogOwner, feed: &StudioModelCatalogFeed) {
    loop {
        let changed = owner.changed.notified();
        tokio::pin!(changed);
        changed.as_mut().enable();
        if owner.task.cancel().is_cancelled() || feed.is_closing() {
            if let Err(error) = feed.send_closed(|frame| owner.send(frame)) {
                owner.task.record_failure(error.into());
            }
            return;
        }
        match owner
            .task
            .admit_studio(|| feed.send_pending(|frame| owner.send(frame)))
        {
            Ok(_) => {}
            Err(error) => {
                finish_delivery(owner, feed, error);
                return;
            }
        }
        tokio::select! { biased;
            () = owner.task.cancel().cancelled() => {}
            () = feed.cancelled() => {}
            result = feed.changed() => {
                if let Err(error) = result { finish_delivery(owner, feed, error); return; }
            },
            () = changed => {}
        }
    }
}

fn finish_delivery(owner: &CatalogOwner, feed: &StudioModelCatalogFeed, error: StudioError) {
    let result = if error.code == StudioErrorCode::Cancelled {
        feed.send_closed(|frame| owner.send(frame))
    } else {
        owner.task.record_failure(error.clone().into());
        feed.send_failure(error, |frame| owner.send(frame))
    };
    if let Err(error) = result {
        owner.task.record_failure(error.into());
    }
}

fn transport_failed() -> StudioError {
    StudioError::new(
        StudioErrorCode::Unavailable,
        "ModelCatalog stream sink is unavailable",
        false,
    )
}
