//! ProjectDirectory has one original native pending/ACK window; the existing bridge owns its task.
use futures::FutureExt;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_studio_runtime::workspace::{ProjectDirectoryFrame, StudioProjectDirectoryFeed};
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, oneshot};

use super::super::identity::BridgeProductFeedIdentity;
use super::project_directory::BridgeProjectDirectoryFrame;
use crate::api::studio::bridge_runtime::installed_bridge;
use crate::api::studio::subscription::BridgeTaskRegistry;
use crate::api::studio::subscription::typed_feed::{TypedFeedResource, TypedFeedTask, closed};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport};
use crate::frb_generated::StreamSink;

struct ProjectDirectoryOwner {
    task: Arc<TypedFeedTask>,
    feed: Mutex<Option<Arc<StudioProjectDirectoryFeed>>>,
    sink: Mutex<Option<StreamSink<BridgeProjectDirectoryFrame>>>,
    changed: Notify,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeProjectDirectoryFeed {
    owner: Arc<ProjectDirectoryOwner>,
    registry: &'static BridgeTaskRegistry,
    identity: BridgeProductFeedIdentity,
}
struct Opening(Option<Arc<ProjectDirectoryOwner>>);
impl Drop for Opening {
    fn drop(&mut self) {
        if let Some(owner) = &self.0 {
            owner.request_close();
        }
    }
}

pub async fn open_project_directory() -> Result<BridgeProjectDirectoryFeed, BridgeError> {
    let bridge = installed_bridge()?;
    let task = TypedFeedTask::new(
        bridge.subscriptions.next_id(),
        bridge.shutdown.child_token(),
    );
    let owner = Arc::new(ProjectDirectoryOwner {
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
        let feed = match bridge.studio.open_project_directory().await {
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
            close_native(&producer, &feed).await;
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
            close_native(&producer, &feed).await;
            std::panic::resume_unwind(panic);
        }
        close_native(&producer, &feed).await;
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
    let handle = BridgeProjectDirectoryFeed {
        owner,
        registry: &bridge.subscriptions,
        identity: identity.into(),
    };
    opening.0.take();
    Ok(handle)
}

impl BridgeProjectDirectoryFeed {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductFeedIdentity {
        self.identity.clone()
    }
    pub async fn stream(
        &self,
        sink: StreamSink<BridgeProjectDirectoryFrame>,
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
            feed_id: self.identity.feed_id.clone(),
            outcome,
        })
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.request_close();
        let _ = self.owner.task.wait_stopped().await;
        let feed = self
            .owner
            .feed
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(feed) = feed {
            let issues = match feed.retry_close().await.outcome {
                pl_protocol::studio::FeedCloseOutcome::Clean => Vec::new(),
                pl_protocol::studio::FeedCloseOutcome::Unresolved { issues } => {
                    issues.into_iter().map(Into::into).collect()
                }
            };
            self.owner.task.replace_cleanup_issues(issues);
        }
        self.close().await
    }
}
impl Drop for BridgeProjectDirectoryFeed {
    fn drop(&mut self) {
        self.request_close();
    }
}

impl ProjectDirectoryOwner {
    fn feed(&self) -> Result<Arc<StudioProjectDirectoryFeed>, BridgeError> {
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
    async fn wait_sink(&self, feed: &StudioProjectDirectoryFeed) -> bool {
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
    fn send(&self, frame: ProjectDirectoryFrame) -> Result<(), StudioError> {
        self.sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .ok_or_else(transport_failed)
            .and_then(|sink| sink.add(frame.into()).map_err(|_| transport_failed()))
    }
}
#[flutter_rust_bridge::frb(ignore)]
impl TypedFeedResource for ProjectDirectoryOwner {
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
async fn run(owner: &ProjectDirectoryOwner, feed: &StudioProjectDirectoryFeed) {
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
        if let Err(error) = feed.refresh().await {
            finish(
                owner,
                feed,
                pl_studio_runtime::studio_error_from_anyhow(error),
            );
            return;
        }
        let mut send_failure = None;
        let result = owner.task.admit_studio(|| {
            feed.send_pending(|frame| {
                let result = owner.send(frame);
                if let Err(error) = &result {
                    send_failure = Some(error.clone());
                }
                result
            })
        });
        if let Some(error) = send_failure {
            owner.task.record_failure(error.into());
        }
        if let Err(error) = result {
            finish(owner, feed, error);
            return;
        }
        tokio::select! { biased;
            () = owner.task.cancel().cancelled() => {}, () = feed.cancelled() => {},
            result = feed.changed() => if let Err(error) = result { finish(owner, feed, error); return; },
            () = changed => {},
        }
    }
}
fn finish(owner: &ProjectDirectoryOwner, feed: &StudioProjectDirectoryFeed, error: StudioError) {
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
        "ProjectDirectory stream sink is unavailable",
        false,
    )
}
async fn close_native(owner: &ProjectDirectoryOwner, feed: &StudioProjectDirectoryFeed) {
    if let pl_protocol::studio::FeedCloseOutcome::Unresolved { issues } = feed.close().await.outcome
    {
        for issue in issues {
            owner.task.record_cleanup_issue(issue.into());
        }
    }
}
