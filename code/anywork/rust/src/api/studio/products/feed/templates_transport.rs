//! Templates' real native stream. The runtime owns its only ACK/material window.
use std::sync::{Arc, Mutex};

use futures::FutureExt;
use pl_studio_runtime::models::{AccountTemplatesFrame, StudioAccountTemplatesFeed};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use tokio::sync::{Notify, oneshot};

use crate::api::studio::bridge_runtime::installed_bridge;
use crate::api::studio::subscription::BridgeTaskRegistry;
use crate::api::studio::subscription::typed_feed::{TypedFeedResource, TypedFeedTask, closed};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport};
use crate::frb_generated::StreamSink;
use super::account_templates::BridgeAccountTemplatesFrame;
use super::super::identity::BridgeProductFeedIdentity;

struct TemplatesOwner {
    task: Arc<TypedFeedTask>,
    feed: Mutex<Option<Arc<StudioAccountTemplatesFeed>>>,
    sink: Mutex<Option<StreamSink<BridgeAccountTemplatesFrame>>>,
    changed: Notify,
}

/// Owns the actual producer, sink and original runtime material until confirmed join.
pub struct BridgeAccountTemplatesFeed {
    owner: Arc<TemplatesOwner>,
    registry: &'static BridgeTaskRegistry,
    identity: BridgeProductFeedIdentity,
}

// A queued open result is not yet an adopted opaque. Cancel even if oneshot.send succeeded.
struct Opening(Option<Arc<TemplatesOwner>>);

impl Drop for Opening {
    fn drop(&mut self) {
        if let Some(owner) = &self.0 { owner.request_close(); }
    }
}

/// Open Templates without reloading JSON or inventing sourceStatus. The original runtime opening
/// is supervised before its first await, including cancellation and a lost/late open reply.
///
/// # Errors
/// Returns the original typed runtime/closing/admission error; it never returns a healthy stub.
pub async fn open_account_templates() -> Result<BridgeAccountTemplatesFeed, BridgeError> {
    let bridge = installed_bridge()?;
    let task = TypedFeedTask::new(bridge.subscriptions.next_id(), bridge.shutdown.child_token());
    let owner = Arc::new(TemplatesOwner { task: task.clone(), feed: Mutex::new(None),
        sink: Mutex::new(None), changed: Notify::new() });
    bridge.subscriptions.register_typed(&task, &owner)?;
    let mut opening = Opening(Some(owner.clone()));
    let (opened, ready) = oneshot::channel();
    let producer = owner.clone();
    if let Err(error) = task.start(async move {
        let feed = match bridge.studio.open_account_templates().await {
            Ok(feed) => Arc::new(feed),
            Err(error) => {
                producer.request_close();
                let _ = opened.send(Err(BridgeError::from(error)));
                return;
            }
        };
        *producer.feed.lock().unwrap_or_else(std::sync::PoisonError::into_inner) = Some(feed.clone());
        let installed = producer.task.admit(|| {
            feed.ensure_open()?;
            Ok(feed.identity())
        });
        match installed {
            Ok(identity) => {
                if opened.send(Ok(identity)).is_err() { producer.request_close(); }
            }
            Err(error) => {
                producer.request_close();
                let _ = opened.send(Err(error));
            }
        }
        if !producer.wait_sink(&feed).await { feed.request_close(); return; }
        let result = std::panic::AssertUnwindSafe(run_delivery(&producer, &feed)).catch_unwind().await;
        if let Err(panic) = result {
            if let Err(error) = feed.send_failure(StudioError::internal(), |frame| producer.send(frame)) {
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
    let handle = BridgeAccountTemplatesFeed { owner, registry: &bridge.subscriptions, identity: identity.into() };
    opening.0.take();
    Ok(handle)
}

impl BridgeAccountTemplatesFeed {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductFeedIdentity { self.identity.clone() }

    /// Only this actual listen claims the runtime stream. An events getter does not exist.
    pub async fn stream(&self, sink: StreamSink<BridgeAccountTemplatesFrame>) -> Result<(), BridgeError> {
        self.owner.task.admit(|| {
            self.owner.feed()?.claim()?;
            *self.owner.sink.lock().unwrap_or_else(std::sync::PoisonError::into_inner) = Some(sink);
            Ok(())
        })?;
        self.owner.changed.notify_waiters();
        Ok(())
    }

    pub async fn ack_through(&self, delivery_sequence: u64) -> Result<(), BridgeError> {
        self.owner.task.admit(|| Ok(self.owner.feed()?.ack_through(delivery_sequence)?))?;
        self.owner.changed.notify_waiters();
        Ok(())
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) { self.owner.request_close(); }

    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.request_close();
        let outcome = if self.owner.task.wait_stopped().await.is_ok() {
            self.registry.unregister_typed(self.owner.task.id);
            BridgeFeedCloseOutcome::Clean
        } else {
            BridgeFeedCloseOutcome::Unresolved { issues: self.owner.task.close_issues() }
        };
        Ok(BridgeFeedCloseReport { feed_id: self.identity.feed_id.clone(), outcome })
    }

    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> { self.close().await }
}

impl Drop for BridgeAccountTemplatesFeed {
    fn drop(&mut self) { self.request_close(); }
}

impl TemplatesOwner {
    fn feed(&self) -> Result<Arc<StudioAccountTemplatesFeed>, BridgeError> {
        self.feed.lock().unwrap_or_else(std::sync::PoisonError::into_inner).clone().ok_or_else(closed)
    }

    fn request_close(&self) {
        self.task.signal_cancel();
        let feed = self.feed.lock().unwrap_or_else(std::sync::PoisonError::into_inner).clone();
        if let Some(feed) = feed { feed.request_close(); }
    }

    async fn wait_sink(&self, feed: &StudioAccountTemplatesFeed) -> bool {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self.task.cancel().is_cancelled() || feed.is_closing() { return self.finish_wait_sink(); }
            if self.sink.lock().unwrap_or_else(std::sync::PoisonError::into_inner).is_some() { return true; }
            tokio::select! { biased;
                () = self.task.cancel().cancelled() => return self.finish_wait_sink(),
                () = feed.cancelled() => return self.finish_wait_sink(),
                () = changed => {}
            }
        }
    }

    fn finish_wait_sink(&self) -> bool {
        // Close the same admission gate as stream() before deciding there is no listener.
        // A prior successful registration must enter run_delivery's typed close path; once
        // this gate wins, a later stream cannot install a sink after we return false.
        self.task.signal_cancel();
        self.sink.lock().unwrap_or_else(std::sync::PoisonError::into_inner).is_some()
    }

    fn send(&self, frame: AccountTemplatesFrame) -> Result<(), StudioError> {
        let sink = self.sink.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        sink.as_ref().ok_or_else(transport_failed)?.add(frame.into()).map_err(|_| transport_failed())
    }
}

impl TypedFeedResource for TemplatesOwner {
    fn release_after_join(&self) {
        self.sink.lock().unwrap_or_else(std::sync::PoisonError::into_inner).take();
        self.feed.lock().unwrap_or_else(std::sync::PoisonError::into_inner).take();
    }
}

async fn run_delivery(owner: &TemplatesOwner, feed: &StudioAccountTemplatesFeed) {
    loop {
        let changed = owner.changed.notified();
        tokio::pin!(changed);
        changed.as_mut().enable();
        if owner.task.cancel().is_cancelled() || feed.is_closing() {
            if let Err(error) = feed.send_closed(|frame| owner.send(frame)) { owner.task.record_failure(error.into()); }
            return;
        }
        match owner.task.admit_studio(|| feed.send_pending(|frame| owner.send(frame))) {
            Ok(_) => {}
            Err(error) if error.code == StudioErrorCode::Cancelled => {
                if let Err(error) = feed.send_closed(|frame| owner.send(frame)) {
                    owner.task.record_failure(error.into());
                }
                return;
            }
            Err(error) => {
                owner.task.record_failure(error.clone().into());
                if let Err(error) = feed.send_failure(error, |frame| owner.send(frame)) {
                    owner.task.record_failure(error.into());
                }
                return;
            }
        }
        // The builtin snapshot is immutable for this source incarnation. After its baseline the
        // connection stays open for ACK/close, rather than treating a static source as query EOF.
        tokio::select! { biased;
            () = owner.task.cancel().cancelled() => {}
            () = feed.cancelled() => {}
            () = changed => {}
        }
    }
}

fn transport_failed() -> StudioError {
    StudioError::new(StudioErrorCode::Unavailable, "AccountTemplates stream sink is unavailable", false)
}
