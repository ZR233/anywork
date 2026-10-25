//! One native execution FIFO/window, posted directly to FRB without another pending queue.
use super::execution::BridgeExecutionFrame;
use super::identity::{BridgeThreadFeedIdentity, BridgeThreadObservationMode};
use crate::api::studio::bridge_runtime::installed_bridge;
use crate::api::studio::subscription::BridgeTaskRegistry;
use crate::api::studio::subscription::typed_feed::{TypedFeedResource, TypedFeedTask, closed};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport};
use crate::frb_generated::StreamSink;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_studio_runtime::thread_execution::{
    DeliveryStep, StudioThreadExecution, ThreadObservationMode,
};
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, oneshot};

struct Owner {
    task: Arc<TypedFeedTask>,
    source: Mutex<Option<Arc<StudioThreadExecution>>>,
    sink: Mutex<Option<StreamSink<BridgeExecutionFrame>>>,
    changed: Notify,
}

#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeThreadExecution {
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

pub async fn open_thread_execution(
    thread_id: String,
    mode: BridgeThreadObservationMode,
) -> Result<BridgeThreadExecution, BridgeError> {
    open_original_execution(move || {
        let mode = match mode {
            BridgeThreadObservationMode::Live => ThreadObservationMode::Live,
            BridgeThreadObservationMode::Cold => ThreadObservationMode::Cold,
        };
        async move {
            installed_bridge()?
                .studio
                .open_thread_execution(thread_id, mode)
                .await
        }
    })
    .await
}

#[flutter_rust_bridge::frb(ignore)]
pub(crate) async fn open_original_execution<F>(
    open: impl FnOnce() -> F + Send + 'static,
) -> Result<BridgeThreadExecution, BridgeError>
where
    F: std::future::Future<Output = anyhow::Result<StudioThreadExecution>> + Send + 'static,
{
    let bridge = installed_bridge()?;
    let task = TypedFeedTask::new(
        bridge.subscriptions.next_id(),
        bridge.shutdown.child_token(),
    );
    let owner = Arc::new(Owner {
        task: task.clone(),
        source: Mutex::new(None),
        sink: Mutex::new(None),
        changed: Notify::new(),
    });
    bridge.subscriptions.register_typed(&task, &owner)?;
    let mut opening = Opening(Some(owner.clone()));
    let (opened, ready) = oneshot::channel();
    let work = owner.clone();
    if let Err(error) = task.start(async move {
        let source = match open().await {
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
        // A natural control terminal does not release unacknowledged material before explicit
        // close. The original registry retains this same completion through actual native close.
        work.task.cancel().cancelled().await;
        source.request_close();
        let _ = source.close().await;
        work.source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
    }) {
        owner.request_close();
        return Err(error);
    }
    let identity = ready
        .await
        .map_err(|_| BridgeError::from(StudioError::internal()))??;
    let feed = BridgeThreadExecution {
        owner,
        registry: &bridge.subscriptions,
        identity: identity.into(),
    };
    opening.0.take();
    Ok(feed)
}

impl BridgeThreadExecution {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeThreadFeedIdentity {
        self.identity.clone()
    }

    pub async fn stream(&self, sink: StreamSink<BridgeExecutionFrame>) -> Result<(), BridgeError> {
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
        let source = self
            .owner
            .source
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(source) = source {
            let _ = source.close().await;
        }
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
impl Drop for BridgeThreadExecution {
    fn drop(&mut self) {
        self.request_close();
    }
}

impl Owner {
    fn source(&self) -> Result<Arc<StudioThreadExecution>, BridgeError> {
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
        frame: pl_protocol::thread_facets::execution::ExecutionFrame,
    ) -> Result<(), StudioError> {
        self.sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .ok_or_else(|| {
                StudioError::new(
                    StudioErrorCode::Cancelled,
                    "Execution stream is not attached",
                    false,
                )
            })?
            .add(frame.into())
            .map_err(|_| {
                StudioError::new(
                    StudioErrorCode::Unavailable,
                    "Execution stream sink is unavailable",
                    false,
                )
            })
    }
    async fn deliver(&self, source: &StudioThreadExecution) {
        loop {
            if self.task.cancel().is_cancelled() {
                source.request_close();
                // RequestClose already sealed native Data admission. This can only post its one
                // queued control terminal, never bypass the native data window after closing.
                let _ = source.send_next(|frame| self.send(frame));
                return;
            }
            let step = self
                .task
                .admit_studio(|| source.send_next(|frame| self.send(frame)));
            match step {
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
#[flutter_rust_bridge::frb(ignore)]
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
