//! The native Thread Configuration FIFO is posted directly to FRB; there is no second pending queue.
use super::configuration::BridgeThreadConfigurationFrame;
use super::identity::{BridgeThreadFeedIdentity, BridgeThreadObservationMode};
use crate::api::studio::bridge_runtime::installed_bridge;
use crate::api::studio::subscription::BridgeTaskRegistry;
use crate::api::studio::subscription::typed_feed::{TypedFeedResource, TypedFeedTask, closed};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport};
use crate::frb_generated::StreamSink;
use pl_protocol::studio::{FeedCloseOutcome, StudioError, StudioErrorCode};
use pl_studio_runtime::thread_configuration::{
    DeliveryStep, StudioThreadConfiguration, ThreadObservationMode,
};
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, oneshot};

struct Owner {
    task: Arc<TypedFeedTask>,
    source: Mutex<Option<Arc<StudioThreadConfiguration>>>,
    sink: Mutex<Option<StreamSink<BridgeThreadConfigurationFrame>>>,
    changed: Notify,
    cleanup: tokio::sync::Mutex<()>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeThreadConfiguration {
    owner: Arc<Owner>,
    registry: &'static BridgeTaskRegistry,
    identity: BridgeThreadFeedIdentity,
}
struct Opening(Option<Arc<Owner>>);
impl Drop for Opening {
    fn drop(&mut self) {
        if let Some(owner) = &self.0 {
            owner.request_close();
        }
    }
}

pub async fn open_thread_configuration(
    thread_id: String,
    mode: BridgeThreadObservationMode,
) -> Result<BridgeThreadConfiguration, BridgeError> {
    let bridge = installed_bridge()?;
    let mode = match mode {
        BridgeThreadObservationMode::Live => ThreadObservationMode::Live,
        BridgeThreadObservationMode::Cold => ThreadObservationMode::Cold,
    };
    let task = TypedFeedTask::new(
        bridge.subscriptions.next_id(),
        bridge.shutdown.child_token(),
    );
    let owner = Arc::new(Owner {
        task: task.clone(),
        source: Mutex::new(None),
        sink: Mutex::new(None),
        changed: Notify::new(),
        cleanup: tokio::sync::Mutex::new(()),
    });
    bridge.subscriptions.register_typed(&task, &owner)?;
    let mut opening = Opening(Some(owner.clone()));
    let (opened, ready) = oneshot::channel();
    let work = owner.clone();
    if let Err(error) = task.start(async move {
        let source = match bridge
            .studio
            .open_thread_configuration(thread_id, mode)
            .await
        {
            Ok(source) => Arc::new(source),
            Err(error) => {
                work.request_close();
                let _ = opened.send(Err(BridgeError::from(error)));
                return;
            }
        };
        *work
            .source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(source.clone());
        let result = work.task.admit(|| Ok(source.identity()));
        if result.is_err() {
            work.request_close();
        }
        if opened.send(result).is_err() {
            work.request_close();
        }
        if work.wait_sink().await {
            work.deliver(&source).await;
        }
        work.sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        // Natural EOF/control delivery is not an ACK or a resource close. Keep all original
        // unacknowledged material until explicit close or the original bridge shutdown.
        work.task.cancel().cancelled().await;
        work.close_source().await;
    }) {
        owner.request_close();
        return Err(error);
    }
    let identity = ready
        .await
        .map_err(|_| BridgeError::from(StudioError::internal()))??;
    let feed = BridgeThreadConfiguration {
        owner,
        registry: &bridge.subscriptions,
        identity: identity.into(),
    };
    opening.0.take();
    Ok(feed)
}
impl BridgeThreadConfiguration {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeThreadFeedIdentity {
        self.identity.clone()
    }
    pub async fn stream(
        &self,
        sink: StreamSink<BridgeThreadConfigurationFrame>,
    ) -> Result<(), BridgeError> {
        self.owner.task.admit(|| {
            let source = self.owner.source()?;
            source.claim()?;
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
    pub async fn ack_through(&self, delivery_sequence: u64) -> Result<(), BridgeError> {
        self.owner
            .task
            .admit(|| Ok(self.owner.source()?.ack_through(delivery_sequence)?))
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.owner.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.request_close();
        let _ = self.owner.task.wait_stopped().await;
        self.owner
            .sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        self.owner.close_source().await;
        let issues = self.owner.task.close_issues();
        let outcome = if issues.is_empty() {
            self.registry.unregister_typed(self.owner.task.id);
            BridgeFeedCloseOutcome::Clean
        } else {
            BridgeFeedCloseOutcome::Unresolved { issues }
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
impl Drop for BridgeThreadConfiguration {
    fn drop(&mut self) {
        self.request_close();
    }
}
impl Owner {
    fn source(&self) -> Result<Arc<StudioThreadConfiguration>, BridgeError> {
        self.source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
            .ok_or_else(closed)
    }
    fn request_close(&self) {
        self.task.signal_cancel();
        if let Ok(source) = self.source() {
            source.request_close();
        }
        self.changed.notify_waiters();
    }
    async fn close_source(&self) {
        let _cleanup = self.cleanup.lock().await;
        let source = self
            .source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        let Some(source) = source else {
            return;
        };
        let issues = match source.retry_close().await.outcome {
            FeedCloseOutcome::Clean => {
                self.source
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .take();
                Vec::new()
            }
            FeedCloseOutcome::Unresolved { issues } => issues.into_iter().map(Into::into).collect(),
        };
        self.task.replace_cleanup_issues(issues);
    }
    async fn wait_sink(&self) -> bool {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self.task.cancel().is_cancelled() {
                return false;
            }
            if self
                .sink
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .is_some()
            {
                return true;
            }
            tokio::select! { biased; () = self.task.cancel().cancelled() => return false, () = changed => {} }
        }
    }
    fn send(
        &self,
        frame: pl_protocol::thread_facets::configuration::ConfigurationFrame,
    ) -> Result<(), StudioError> {
        self.sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .ok_or_else(|| {
                StudioError::new(
                    StudioErrorCode::Cancelled,
                    "Thread Configuration stream is not attached",
                    false,
                )
            })?
            .add(frame.into())
            .map_err(|_| {
                StudioError::new(
                    StudioErrorCode::Unavailable,
                    "Thread Configuration stream sink is unavailable",
                    false,
                )
            })
    }
    async fn deliver(&self, source: &StudioThreadConfiguration) {
        loop {
            if self.task.cancel().is_cancelled() {
                source.request_close();
                let _ = source.send_next(|frame| self.send(frame));
                return;
            }
            match self
                .task
                .admit_studio(|| source.send_next(|frame| self.send(frame)))
            {
                Ok(DeliveryStep::Data) => continue,
                Ok(DeliveryStep::Terminal) => return,
                Ok(DeliveryStep::Waiting) => {}
                Err(error)
                    if error.code == StudioErrorCode::Cancelled
                        && self.task.cancel().is_cancelled() =>
                {
                    continue;
                }
                Err(error) => {
                    self.task.record_failure(error.into());
                    self.request_close();
                    return;
                }
            }
            tokio::select! { biased;
                () = self.task.cancel().cancelled() => {},
                () = source.ready() => {},
            }
        }
    }
}
impl TypedFeedResource for Owner {
    fn release_after_join(&self) {
        self.sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        self.source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
    }
}
