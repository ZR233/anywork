//! Observe the native command, never cancel its accepted worker on sink/caller loss.
use crate::api::studio::bridge_runtime::installed_bridge;
use crate::api::studio::subscription::{
    BridgeTaskRegistry,
    typed_feed::{TypedFeedResource, TypedFeedTask},
};
use crate::api::studio::types::{
    BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport, BridgeThreadPreparationProgress,
};
use crate::frb_generated::StreamSink;
use pl_protocol::studio::{FeedCloseOutcome, FeedCloseReport};
use pl_studio_runtime::draft_commands::{
    StudioAttachmentAdmission, StudioThreadCreation, StudioThreadCreationProgress,
};
use std::sync::{Arc, Mutex};
use tokio::sync::Notify;

#[derive(Clone)]
pub(super) enum Native {
    Admission(StudioAttachmentAdmission),
    Creation(StudioThreadCreation),
}
impl Native {
    fn request_close(&self) {
        match self {
            Self::Admission(job) => job.request_close(),
            Self::Creation(job) => job.request_close(),
        }
    }
    async fn close(&self, retry: bool) -> FeedCloseReport {
        match (self, retry) {
            (Self::Admission(job), false) => job.close().await,
            (Self::Admission(job), true) => job.retry_close().await,
            (Self::Creation(job), false) => job.close().await,
            (Self::Creation(job), true) => job.retry_close().await,
        }
    }
}
struct State {
    close_native: bool,
    claimed: bool,
    sink: Option<StreamSink<BridgeThreadPreparationProgress>>,
    progress: Option<StudioThreadCreationProgress>,
}
struct ProgressSink<'a>(&'a Mutex<State>);
impl Drop for ProgressSink<'_> {
    fn drop(&mut self) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sink
            .take();
    }
}
pub(super) struct Owner {
    pub(super) native: Native,
    task: Arc<TypedFeedTask>,
    state: Mutex<State>,
    changed: Notify,
    cleanup: tokio::sync::Mutex<()>,
    registry: &'static BridgeTaskRegistry,
}

impl Owner {
    pub(super) fn new(native: Native) -> Result<Arc<Self>, BridgeError> {
        let bridge = installed_bridge()?;
        let task = TypedFeedTask::new(
            bridge.subscriptions.next_id(),
            bridge.shutdown.child_token(),
        );
        let owner = Arc::new(Self {
            native,
            task: task.clone(),
            state: Mutex::new(State {
                close_native: false,
                claimed: false,
                sink: None,
                progress: None,
            }),
            changed: Notify::new(),
            cleanup: tokio::sync::Mutex::new(()),
            registry: &bridge.subscriptions,
        });
        bridge.subscriptions.register_typed(&task, &owner)?;
        let work = owner.clone();
        if let Err(error) = task.start(async move {
            if matches!(&work.native, Native::Creation(_)) {
                work.progress().await;
            }
            work.release_progress();
            work.task.cancel().cancelled().await;
            let close = work
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .close_native;
            if close {
                work.close_native(false).await;
            }
            // A detached/lost observer leaves the original native job in the bounded registry.
            // result/find or native shutdown can still join it; no accepted worker is aborted.
        }) {
            owner.detach();
            return Err(error);
        }
        Ok(owner)
    }
    pub(super) fn detach(&self) {
        self.task.signal_cancel();
        self.changed.notify_waiters();
    }
    pub(super) fn request_close(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .close_native = true;
        self.native.request_close();
        self.detach();
    }
    async fn close_native(&self, retry: bool) {
        // Serialize only native-report publication, not business result observation. A caller
        // may cancel this wait; native retains the actual cleanup and the next attempt joins it.
        let _cleanup = self.cleanup.lock().await;
        let issues = match self.native.close(retry).await.outcome {
            FeedCloseOutcome::Clean => Vec::new(),
            FeedCloseOutcome::Unresolved { issues } => issues.into_iter().map(Into::into).collect(),
        };
        self.task.replace_cleanup_issues(issues);
    }
    pub(super) async fn close(
        &self,
        operation_id: String,
        retry: bool,
    ) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.request_close();
        let _ = self.task.wait_stopped().await;
        // A joined producer fault still permits closing its actual sink/receiver. Keeping
        // a receiver in State here would make native close wait forever on our own lease.
        self.release_progress();
        self.close_native(retry).await;
        let issues = self.task.close_issues();
        let outcome = if issues.is_empty() {
            self.registry.unregister_typed(self.task.id);
            BridgeFeedCloseOutcome::Clean
        } else {
            BridgeFeedCloseOutcome::Unresolved { issues }
        };
        Ok(BridgeFeedCloseReport {
            feed_id: operation_id,
            outcome,
        })
    }
    pub(super) fn stream(
        &self,
        sink: StreamSink<BridgeThreadPreparationProgress>,
    ) -> Result<(), BridgeError> {
        self.task.admit(|| {
            let Native::Creation(job) = &self.native else {
                return Err(pl_protocol::studio::StudioError::invalid_argument(
                    "This command has no preparation progress",
                )
                .into());
            };
            let progress = job.subscribe_progress()?;
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.claimed {
                return Err(pl_protocol::studio::StudioError::new(
                    pl_protocol::studio::StudioErrorCode::Conflict,
                    "Preparation progress was already claimed",
                    false,
                )
                .into());
            }
            // Keep the same actual native lease from admission until the sink has closed.
            // A check-only temporary receiver would allow native close between these steps.
            state.claimed = true;
            state.sink = Some(sink);
            state.progress = Some(progress);
            Ok(())
        })?;
        self.changed.notify_waiters();
        Ok(())
    }
    async fn progress(&self) {
        let mut progress = loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self.task.cancel().is_cancelled() {
                return;
            }
            if let Some(progress) = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .progress
                .take()
            {
                break progress;
            }
            tokio::select! { biased; () = self.task.cancel().cancelled() => return, () = changed => {} }
        };
        // Drop the sink before the native receiver lease, including on cancellation/sink loss.
        // Thus native close cannot observe a joined progress lease with an unclosed FRB port.
        let _sink = ProgressSink(&self.state);
        if let Some(value) = progress.current()
            && !self.send(value)
        {
            return;
        }
        loop {
            let value = tokio::select! { biased;
                () = self.task.cancel().cancelled() => return,
                value = progress.changed() => value,
            };
            match value {
                Ok(Some(value)) => {
                    if !self.send(value) {
                        return;
                    }
                }
                Ok(None) | Err(_) => return,
            }
        }
    }
    fn send(&self, value: pl_protocol::studio::ThreadPreparationProgress) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sink
            .as_ref()
            .is_some_and(|sink| sink.add(value.into()).is_ok())
    }
    fn release_progress(&self) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.sink.take();
        state.progress.take();
    }
}
#[flutter_rust_bridge::frb(ignore)]
impl TypedFeedResource for Owner {
    fn release_after_join(&self) {
        self.release_progress();
    }
}
