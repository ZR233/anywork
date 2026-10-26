//! Pre-active Startup progress uses native reliable stages and the same real bridge task owner.
use futures::FutureExt;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_studio_runtime::startup::StudioStartupProgress;
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, oneshot};

use crate::api::studio::subscription::BridgeTaskRegistry;
use crate::api::studio::subscription::typed_feed::{TypedFeedResource, TypedFeedTask, closed};
use crate::api::studio::types::BridgeStartupStage;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport};
use crate::frb_generated::StreamSink;
use pl_protocol::products::read::startup::{
    StartupCloseReason, StartupProgressFrame, StartupStage,
};
use std::sync::LazyLock;
use tokio_util::sync::CancellationToken;

static STARTUP_TASKS: LazyLock<BridgeTaskRegistry> = LazyLock::new(BridgeTaskRegistry::new);

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeStartupCloseReason {
    Requested,
    AttemptReplaced,
    Completed,
    RuntimeStopped,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeStartupProgressFrame {
    Data {
        delivery_sequence: u64,
        stage: BridgeStartupStage,
    },
    Failure {
        error: BridgeError,
    },
    Closed {
        reason: BridgeStartupCloseReason,
    },
}
impl From<StartupProgressFrame> for BridgeStartupProgressFrame {
    fn from(value: StartupProgressFrame) -> Self {
        match value {
            StartupProgressFrame::Data {
                delivery_sequence,
                stage,
            } => Self::Data {
                delivery_sequence,
                stage: stage.into(),
            },
            StartupProgressFrame::Failure { error } => Self::Failure {
                error: error.into(),
            },
            StartupProgressFrame::Closed { reason } => Self::Closed {
                reason: match reason {
                    StartupCloseReason::Requested => BridgeStartupCloseReason::Requested,
                    StartupCloseReason::AttemptReplaced => {
                        BridgeStartupCloseReason::AttemptReplaced
                    }
                    StartupCloseReason::Completed => BridgeStartupCloseReason::Completed,
                    StartupCloseReason::RuntimeStopped => BridgeStartupCloseReason::RuntimeStopped,
                },
            },
        }
    }
}
impl From<StartupStage> for BridgeStartupStage {
    fn from(value: StartupStage) -> Self {
        match value {
            StartupStage::Preparing => Self::Preparing,
            StartupStage::WaitingForSteps => Self::WaitingForSteps,
            StartupStage::ClosingResources => Self::ClosingResources,
            StartupStage::BackingUp => Self::BackingUp,
            StartupStage::Resetting => Self::Resetting,
            StartupStage::StartingServices => Self::StartingServices,
            StartupStage::OpeningStorage => Self::OpeningStorage,
            StartupStage::LoadingConfiguration => Self::LoadingConfiguration,
            StartupStage::ReadingProjects => Self::ReadingProjects,
            StartupStage::PreparingResources => Self::PreparingResources,
            StartupStage::Ready => Self::Ready,
            StartupStage::Failed => Self::Failed,
        }
    }
}

pub async fn initialize_library() -> Result<(), BridgeError> {
    crate::api::studio::handlers::lifecycle::init_app();
    Ok(())
}
pub async fn prepare_startup_attempt() -> Result<u64, BridgeError> {
    crate::api::studio::handlers::lifecycle::prepare_startup_attempt().await
}
pub async fn start_studio_runtime(
    attempt_id: u64,
) -> Result<super::super::read::startup::BridgeRuntimeReady, BridgeError> {
    crate::api::studio::handlers::lifecycle::start_studio_runtime(attempt_id).await
}
/// The existing exit coordinator joins this pre-active registry under its original deadline.
pub(crate) async fn close_for_exit(
    deadline: std::time::Instant,
) -> Vec<crate::api::studio::types::BridgeShutdownIssue> {
    let pending = STARTUP_TASKS.broadcast_cancel(deadline).await;
    STARTUP_TASKS.join_cancelled(pending, deadline).await
}

struct StartupOwner {
    task: Arc<TypedFeedTask>,
    feed: Mutex<Option<Arc<StudioStartupProgress>>>,
    sink: Mutex<Option<StreamSink<BridgeStartupProgressFrame>>>,
    changed: Notify,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeStartupFeed {
    owner: Arc<StartupOwner>,
    registry: &'static BridgeTaskRegistry,
    identity: String,
}
struct Opening(Option<Arc<StartupOwner>>);
impl Drop for Opening {
    fn drop(&mut self) {
        if let Some(owner) = &self.0 {
            owner.request_close();
        }
    }
}

pub async fn open_startup_progress(attempt_id: u64) -> Result<BridgeStartupFeed, BridgeError> {
    let source = crate::api::studio::handlers::lifecycle::startup_progress_source(attempt_id)?;
    let task = TypedFeedTask::new(STARTUP_TASKS.next_id(), CancellationToken::new());
    let owner = Arc::new(StartupOwner {
        task: task.clone(),
        feed: Mutex::new(None),
        sink: Mutex::new(None),
        changed: Notify::new(),
    });
    STARTUP_TASKS.register_typed(&task, &owner)?;
    let mut opening = Opening(Some(owner.clone()));
    let (opened, ready) = oneshot::channel();
    let producer = owner.clone();
    if let Err(error) = task.start(async move {
        let feed = match source.open_startup_progress(attempt_id) {
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
            Ok(feed.feed_id())
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
        let outcome = std::panic::AssertUnwindSafe(run(&producer, &feed))
            .catch_unwind()
            .await;
        if let Err(panic) = outcome {
            if let Err(error) =
                feed.send_failure(StudioError::internal(), |frame| producer.send(frame))
            {
                producer.task.record_failure(error.into());
            }
            producer
                .sink
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .take();
            std::panic::resume_unwind(panic);
        }
        // Terminal delivery ends this stream, but the unACKed pins remain with the original feed
        // until the explicit close joins. EOF alone does not release them or report Clean.
        producer
            .sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
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
    let handle = BridgeStartupFeed {
        owner,
        registry: &STARTUP_TASKS,
        identity,
    };
    opening.0.take();
    Ok(handle)
}

impl BridgeStartupFeed {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> String {
        self.identity.clone()
    }
    pub async fn stream(
        &self,
        sink: StreamSink<BridgeStartupProgressFrame>,
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
            feed_id: self.identity.clone(),
            outcome,
        })
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.close().await
    }
}
impl Drop for BridgeStartupFeed {
    fn drop(&mut self) {
        self.request_close();
    }
}

impl StartupOwner {
    fn feed(&self) -> Result<Arc<StudioStartupProgress>, BridgeError> {
        self.feed
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
            .ok_or_else(closed)
    }
    fn request_close(&self) {
        self.task.signal_cancel();
        if let Some(feed) = self
            .feed
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
        {
            feed.request_close();
        }
    }
    async fn wait_sink(&self, feed: &StudioStartupProgress) -> bool {
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
                result = feed.changed() => if let Err(error) = result {
                    if error.code != StudioErrorCode::Cancelled { self.task.record_failure(error.into()); }
                    feed.request_close(); return self.finish_wait_sink();
                },
                () = changed => {},
            }
        }
    }
    fn finish_wait_sink(&self) -> bool {
        self.task.signal_cancel();
        self.sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .is_some()
    }
    fn send(&self, frame: StartupProgressFrame) -> Result<(), StudioError> {
        self.sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .ok_or_else(transport_failed)
            .and_then(|sink| sink.add(frame.into()).map_err(|_| transport_failed()))
    }
}
#[flutter_rust_bridge::frb(ignore)]
impl TypedFeedResource for StartupOwner {
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
async fn run(owner: &StartupOwner, feed: &StudioStartupProgress) {
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
        loop {
            let mut failed_send = None;
            let result = owner.task.admit_studio(|| {
                feed.send_pending(|frame| {
                    let result = owner.send(frame);
                    if let Err(error) = &result {
                        failed_send = Some(error.clone());
                    }
                    result
                })
            });
            if let Some(error) = failed_send {
                owner.task.record_failure(error.into());
            }
            match result {
                Ok(true) => continue,
                Ok(false) => break,
                Err(error) => {
                    finish(owner, feed, error);
                    return;
                }
            }
        }
        let mut failed_send = None;
        let terminal = owner.task.admit_studio(|| {
            feed.send_terminal(|frame| {
                let result = owner.send(frame);
                if let Err(error) = &result {
                    failed_send = Some(error.clone());
                }
                result
            })
        });
        if let Some(error) = failed_send {
            owner.task.record_failure(error.into());
        }
        match terminal {
            Ok(true) => return,
            Ok(false) => {}
            Err(error) => {
                finish(owner, feed, error);
                return;
            }
        }
        tokio::select! { biased;
            () = owner.task.cancel().cancelled() => {}, () = feed.cancelled() => {},
            result = feed.changed() => if let Err(error) = result { finish(owner, feed, error); return; },
            () = changed => {},
        }
    }
}
fn finish(owner: &StartupOwner, feed: &StudioStartupProgress, error: StudioError) {
    let result = if error.code == StudioErrorCode::Cancelled {
        feed.send_closed(|frame| owner.send(frame))
    } else {
        feed.send_failure(error, |frame| owner.send(frame))
    };
    if let Err(error) = result {
        owner.task.record_failure(error.into());
    }
}
fn transport_failed() -> StudioError {
    StudioError::new(
        StudioErrorCode::Unavailable,
        "Startup stream sink is unavailable",
        false,
    )
}
