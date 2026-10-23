//! Timeline 内容 feed 的 registry owner：opening 起强引用，直到真实 join。
//!
//! 复用父模块既有的 owner-published Shared completion；唯一 delivery task 记为
//! producer。page／detail 仍走调用 guard，不另派无人管理的 query 任务。

use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::{Arc, Mutex as SyncMutex};

use flutter_rust_bridge::frb;
use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use tokio::sync::Notify;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use super::{
    OWNED_FAILED, OWNED_NOT_STARTED, OWNED_PENDING, OWNED_SUCCEEDED, SubscriptionCompletion,
    SubscriptionCompletionFacts, SubscriptionOwner, owned_completion,
};
use crate::api::studio::types::{
    BridgeError, BridgeFeedCloseOutcome, BridgeFeedCloseReport, BridgeShutdownIssue,
};
use pl_protocol::TimelineTailBaseline;
use pl_studio_runtime::{TimelineContentReader, TimelineTailStream};

/// 每个 handle 未确认 data 的上限；首 baseline 占额度。
pub(crate) const UNACKED_DATA_LIMIT: u64 = 2;

const OPENING_LIVE: u8 = 0;
const OPENING_PUBLISHED: u8 = 1;
const OPENING_ABORTED: u8 = 2;

/// Timeline feed 的 native owner：registry 持强引用直到 Clean。
#[frb(ignore)]
pub(crate) struct TimelineFeedOwner {
    pub(crate) id: u64,
    thread_id: String,
    cancel: CancellationToken,
    facts: Arc<SubscriptionCompletionFacts>,
    clean: AtomicBool,
    opening: AtomicU8,
    activity: SyncMutex<TimelineActivity>,
    idle: Notify,
    capacity: Notify,
    reader: SyncMutex<Option<Arc<TimelineContentReader>>>,
    tail: SyncMutex<Option<TimelineTailStream>>,
    baseline: SyncMutex<Option<TimelineTailBaseline>>,
    feed_id: SyncMutex<Option<String>>,
    delivery_task: SyncMutex<Option<SubscriptionCompletion>>,
    close_join: SyncMutex<Option<Shared<BoxFuture<'static, BridgeFeedCloseReport>>>>,
    #[cfg(test)]
    capacity_check: Notify,
    #[cfg(test)]
    capacity_resume: Notify,
    #[cfg(test)]
    pause_after_arm: AtomicBool,
}

#[frb(ignore)]
#[derive(Default)]
struct TimelineActivity {
    closing: bool,
    stream_claimed: bool,
    active_calls: usize,
    sent: u64,
    acked: u64,
}

/// 每个获准进入的句柄 API 都持有一份；future 被取消时也会退出登记。
#[frb(ignore)]
pub(crate) struct TimelineCall {
    owner: Arc<TimelineFeedOwner>,
}

/// Opening 期间的 RAII：成功移交 handle 前保持 Opening；失败/取消 drop 为 Aborted。
#[frb(ignore)]
pub(crate) struct TimelineOpening {
    owner: Arc<TimelineFeedOwner>,
}

#[frb(ignore)]
pub(crate) enum TimelineEmit {
    Sent,
    Closed,
}

impl TimelineFeedOwner {
    pub(crate) fn new(id: u64, thread_id: String, cancel: CancellationToken) -> Arc<Self> {
        Arc::new(Self {
            id,
            thread_id,
            cancel,
            facts: Arc::new(SubscriptionCompletionFacts::default()),
            clean: AtomicBool::new(false),
            opening: AtomicU8::new(OPENING_LIVE),
            activity: SyncMutex::new(TimelineActivity::default()),
            idle: Notify::new(),
            capacity: Notify::new(),
            reader: SyncMutex::new(None),
            tail: SyncMutex::new(None),
            baseline: SyncMutex::new(None),
            feed_id: SyncMutex::new(Some(format!("timeline-opening-{id}"))),
            delivery_task: SyncMutex::new(None),
            close_join: SyncMutex::new(None),
            #[cfg(test)]
            capacity_check: Notify::new(),
            #[cfg(test)]
            capacity_resume: Notify::new(),
            #[cfg(test)]
            pause_after_arm: AtomicBool::new(false),
        })
    }

    pub(crate) fn cancel(&self) -> &CancellationToken {
        &self.cancel
    }

    pub(crate) fn feed_id(&self) -> String {
        self.feed_id
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
            .unwrap_or_default()
    }

    /// Registry 只认真实 Clean：delivery 结束但 reader/query 仍在时不得 prune。
    pub(crate) fn is_settled(&self) -> bool {
        self.clean.load(Ordering::Acquire)
    }

    pub(crate) fn is_closing(&self) -> bool {
        let activity = self
            .activity
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        activity.closing || self.cancel.is_cancelled()
    }

    #[cfg(test)]
    pub(crate) fn sent_acked(&self) -> (u64, u64) {
        let activity = self
            .activity
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        (activity.sent, activity.acked)
    }

    pub(crate) fn begin_opening(self: &Arc<Self>) -> TimelineOpening {
        self.opening.store(OPENING_LIVE, Ordering::Release);
        TimelineOpening {
            owner: Arc::clone(self),
        }
    }

    #[cfg(test)]
    pub(crate) fn publish_handle(&self) {
        self.opening.store(OPENING_PUBLISHED, Ordering::Release);
    }

    pub(crate) fn install(
        &self,
        reader: Arc<TimelineContentReader>,
        tail: TimelineTailStream,
        baseline: TimelineTailBaseline,
    ) -> Result<(), BridgeError> {
        let activity = self.activity.lock().unwrap_or_else(|error| error.into_inner());
        if activity.closing || self.cancel.is_cancelled() {
            return Err(timeline_closed());
        }
        *self
            .feed_id
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = Some(baseline.subscription_id.clone());
        *self
            .reader
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = Some(reader);
        *self
            .baseline
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = Some(baseline);
        *self.tail.lock().unwrap_or_else(|error| error.into_inner()) = Some(tail);
        // Publishing and close admission have the same linearization boundary; an open that
        // lost to request_close must not return a newly usable handle.
        self.opening.store(OPENING_PUBLISHED, Ordering::Release);
        Ok(())
    }

    /// 测试与交付循环取出尚未发送的产品基线；只移交一次。
    pub(crate) fn take_baseline(&self) -> Option<TimelineTailBaseline> {
        self.baseline
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take()
    }

    pub(crate) fn content(&self) -> Result<Arc<TimelineContentReader>, BridgeError> {
        self.reader
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
            .ok_or_else(timeline_closed)
    }

    pub(crate) fn take_tail(&self) -> Option<TimelineTailStream> {
        self.tail
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take()
    }

    pub(crate) fn begin_call(self: &Arc<Self>) -> Result<TimelineCall, BridgeError> {
        let mut activity = self
            .activity
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if activity.closing || self.cancel.is_cancelled() {
            return Err(timeline_closed());
        }
        activity.active_calls += 1;
        Ok(TimelineCall {
            owner: Arc::clone(self),
        })
    }

    pub(crate) fn claim_stream(&self) -> Result<(), BridgeError> {
        let mut activity = self
            .activity
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if activity.closing || self.cancel.is_cancelled() {
            return Err(timeline_closed());
        }
        if activity.stream_claimed {
            return Err(timeline_stream_conflict());
        }
        activity.stream_claimed = true;
        Ok(())
    }

    pub(crate) fn request_close(&self) {
        {
            let mut activity = self
                .activity
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            activity.closing = true;
        }
        tracing::trace!(
            subscription_id = self.id,
            thread_id = %self.thread_id,
            "cancelling Studio timeline feed"
        );
        self.cancel.cancel();
        self.capacity.notify_waiters();
        self.idle.notify_waiters();
    }

    /// 同步登记唯一 delivery task：spawn 到登记之间不得 await。
    pub(crate) fn start_delivery(&self, handle: JoinHandle<()>) {
        let mut slot = self.delivery_task.lock().unwrap_or_else(|error| error.into_inner());
        self.facts.producer.store(OWNED_PENDING, Ordering::SeqCst);
        let completion = owned_completion(
            handle,
            self.id,
            Arc::clone(&self.facts),
            SubscriptionOwner::Producer,
        );
        *slot = Some(completion);
    }

    pub(crate) async fn wait_capacity(&self) -> Result<(), BridgeError> {
        loop {
            let notified = self.capacity.notified();
            tokio::pin!(notified);
            notified.as_mut().enable();
            if self.cancel.is_cancelled() {
                return Err(timeline_closed());
            }
            {
                let activity = self
                    .activity
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if activity.closing {
                    return Err(timeline_closed());
                }
                if activity.sent.saturating_sub(activity.acked) < UNACKED_DATA_LIMIT {
                    return Ok(());
                }
            }
            #[cfg(test)]
            self.capacity_test_gate().await;
            tokio::select! {
                biased;
                () = self.cancel.cancelled() => return Err(timeline_closed()),
                () = notified => {}
            }
        }
    }

    /// 在同一把短锁、同一次非 await 步骤里同步 `sink.add` 与 sent 水位。
    pub(crate) fn emit_data<F>(
        &self,
        sink: &F,
        event: crate::api::studio::types::BridgeTimelineEvent,
    ) -> Result<TimelineEmit, BridgeError>
    where
        F: Fn(crate::api::studio::types::BridgeTimelineFrame) -> Result<(), ()>,
    {
        let mut activity = self
            .activity
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if activity.closing || self.cancel.is_cancelled() {
            return Err(timeline_closed());
        }
        let sequence = activity
            .sent
            .checked_add(1)
            .ok_or_else(timeline_sequence_overflow)?;
        let frame = crate::api::studio::types::BridgeTimelineFrame::Data {
            delivery_sequence: sequence,
            event,
        };
        if sink(frame).is_err() {
            drop(activity);
            self.request_close();
            return Err(timeline_closed());
        }
        activity.sent = sequence;
        Ok(TimelineEmit::Sent)
    }

    pub(crate) fn emit_control<F>(
        &self,
        sink: &F,
        frame: crate::api::studio::types::BridgeTimelineFrame,
    ) -> TimelineEmit
    where
        F: Fn(crate::api::studio::types::BridgeTimelineFrame) -> Result<(), ()>,
    {
        let _activity = self
            .activity
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if sink(frame).is_err() {
            drop(_activity);
            self.request_close();
            return TimelineEmit::Closed;
        }
        TimelineEmit::Sent
    }

    pub(crate) fn ack_through(&self, delivery_sequence: u64) -> Result<(), BridgeError> {
        let mut activity = self
            .activity
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if activity.closing || self.cancel.is_cancelled() {
            return Err(timeline_closed());
        }
        if delivery_sequence == 0 || delivery_sequence <= activity.acked {
            return Ok(());
        }
        if delivery_sequence > activity.sent {
            return Err(timeline_ack_beyond_sent());
        }
        activity.acked = delivery_sequence;
        drop(activity);
        self.capacity.notify_waiters();
        Ok(())
    }

    pub(crate) async fn close(self: &Arc<Self>) -> BridgeFeedCloseReport {
        self.request_close();
        let shared = {
            let mut slot = self
                .close_join
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if let Some(existing) = slot.clone() {
                existing
            } else {
                let this = Arc::clone(self);
                let shared = async move { this.join_once().await }.boxed().shared();
                *slot = Some(shared.clone());
                shared
            }
        };
        shared.await
    }

    pub(crate) async fn wait_stopped(self: &Arc<Self>) -> Result<(), Arc<String>> {
        match self.close().await.outcome {
            BridgeFeedCloseOutcome::Clean => Ok(()),
            BridgeFeedCloseOutcome::Unresolved { issues } => {
                let message = issues
                    .first()
                    .map(|issue| issue.diagnostic.message.clone())
                    .unwrap_or_else(|| format!("Studio timeline {} did not stop cleanly", self.id));
                Err(Arc::new(message))
            }
        }
    }

    async fn join_once(self: Arc<Self>) -> BridgeFeedCloseReport {
        self.request_close();
        self.wait_idle().await;
        let delivery = self.wait_delivery().await;
        if !matches!(delivery, DeliveryJoin::Pending) {
        self.release_resources();
        }
        let feed_id = self.feed_id();
        let report = match delivery {
            DeliveryJoin::NeverStarted | DeliveryJoin::Succeeded => {
                if self.resources_held() {
                    unresolved_report(
                        feed_id,
                        "producerTaskFailed",
                        "Studio timeline resources were still held after join",
                    )
                } else {
                    self.clean.store(true, Ordering::Release);
                    BridgeFeedCloseReport {
                        feed_id,
                        outcome: BridgeFeedCloseOutcome::Clean,
                    }
                }
            }
            DeliveryJoin::Pending => unresolved_report(
                feed_id,
                "producerTaskFailed",
                "Studio timeline delivery task did not confirm a clean stop",
            ),
            DeliveryJoin::Failed(error) => {
                unresolved_report(feed_id, "producerTaskFailed", error.as_str())
            }
        };
        if matches!(report.outcome, BridgeFeedCloseOutcome::Unresolved { .. }) {
            self.clean.store(false, Ordering::Release);
        }
        report
    }

    async fn wait_idle(&self) {
        loop {
            let idle = self.idle.notified();
            tokio::pin!(idle);
            idle.as_mut().enable();
            let drained = self
                .activity
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .active_calls
                == 0;
            if drained {
                break;
            }
            idle.await;
        }
    }

    async fn wait_delivery(&self) -> DeliveryJoin {
        let completion = self
            .delivery_task
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone();
        match completion {
            Some(completion) => match completion.await {
                Ok(()) => DeliveryJoin::Succeeded,
                Err(error) => DeliveryJoin::Failed(error),
            },
            None => match self.facts.producer.load(Ordering::SeqCst) {
                OWNED_NOT_STARTED => DeliveryJoin::NeverStarted,
                OWNED_SUCCEEDED => DeliveryJoin::Succeeded,
                OWNED_FAILED => DeliveryJoin::Failed(Arc::new(
                    "Studio timeline delivery task failed without a retained completion"
                        .to_string(),
                )),
                _ => DeliveryJoin::Pending,
            },
        }
    }

    fn release_resources(&self) {
        let mut tail = self
            .tail
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take();
        if let Some(tail) = tail.as_mut() {
            tail.close();
        }
        drop(tail);
        drop(
            self.reader
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .take(),
        );
        drop(
            self.baseline
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .take(),
        );
    }

    fn resources_held(&self) -> bool {
        self.reader
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .is_some()
            || self
                .tail
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .is_some()
            || self
                .baseline
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .is_some()
    }

    fn try_mark_aborted_clean(&self) {
        if self.opening.load(Ordering::Acquire) != OPENING_ABORTED {
            return;
        }
        if self.resources_held() {
            return;
        }
        if self
            .delivery_task
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .is_some()
            || self.facts.producer.load(Ordering::SeqCst) != OWNED_NOT_STARTED
        {
            return;
        }
        let idle = self
            .activity
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .active_calls
            == 0;
        if idle {
            let retained = self
                .close_join
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .take();
            self.clean.store(true, Ordering::Release);
            drop(retained);
        }
    }

    #[cfg(test)]
    async fn capacity_test_gate(&self) {
        if !self.pause_after_arm.load(Ordering::SeqCst) {
            return;
        }
        let resume = self.capacity_resume.notified();
        tokio::pin!(resume);
        resume.as_mut().enable();
        self.pause_after_arm.store(false, Ordering::SeqCst);
        self.capacity_check.notify_waiters();
        resume.await;
    }

    #[cfg(test)]
    pub(crate) fn arm_capacity_park_gate(&self) {
        self.pause_after_arm.store(true, Ordering::SeqCst);
    }

    #[cfg(test)]
    pub(crate) fn capacity_checked(&self) -> tokio::sync::futures::Notified<'_> {
        self.capacity_check.notified()
    }

    #[cfg(test)]
    pub(crate) fn resume_capacity_wait(&self) {
        self.capacity_resume.notify_waiters();
    }

    #[cfg(test)]
    fn hold_baseline_for_test(&self) {
        *self
            .baseline
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = Some(TimelineTailBaseline {
            subscription_id: "held".to_string(),
            version: 1,
            items: Vec::new(),
            before: None,
            has_older: false,
        });
    }
}

enum DeliveryJoin {
    NeverStarted,
    Succeeded,
    Pending,
    Failed(Arc<String>),
}

impl Drop for TimelineCall {
    fn drop(&mut self) {
        let idle = {
            let mut activity = self
                .owner
                .activity
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            activity.active_calls = activity.active_calls.saturating_sub(1);
            activity.active_calls == 0
        };
        if idle {
            self.owner.idle.notify_waiters();
            self.owner.try_mark_aborted_clean();
        }
    }
}

impl Drop for TimelineOpening {
    fn drop(&mut self) {
        if self.owner.opening.load(Ordering::Acquire) == OPENING_LIVE {
            self.owner.opening.store(OPENING_ABORTED, Ordering::Release);
            self.owner.request_close();
            self.owner.try_mark_aborted_clean();
        }
    }
}

pub(crate) fn timeline_closed() -> BridgeError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Cancelled,
        "timeline handle is closed",
        false,
    )
    .into()
}

fn timeline_stream_conflict() -> BridgeError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Conflict,
        "timeline stream can only be opened once",
        false,
    )
    .into()
}

fn timeline_sequence_overflow() -> BridgeError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Protocol,
        "timeline delivery sequence overflowed",
        false,
    )
    .into()
}

fn timeline_ack_beyond_sent() -> BridgeError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Protocol,
        "timeline ack exceeds sent delivery sequence",
        false,
    )
    .into()
}

fn unresolved_report(feed_id: String, code: &str, message: &str) -> BridgeFeedCloseReport {
    BridgeFeedCloseReport {
        feed_id,
        outcome: BridgeFeedCloseOutcome::Unresolved {
            issues: vec![crate::api::studio::types::BridgeFeedCloseIssue {
                diagnostic: BridgeShutdownIssue {
                stage: "subscriptions".to_string(),
                code: code.to_string(),
                message: message.to_string(),
                retryable: false,
                correlation_id: pl_protocol::studio::StudioError::internal().correlation_id,
                },
                // A task panic or a missing completion cannot be repaired by restarting a
                // content producer. Real pending joins remain in the retained close future.
                recovery: crate::api::studio::types::BridgeCleanupRecovery::Terminal,
            }],
        },
    }
}

#[cfg(test)]
mod timeline_feed_owner_tests {
    use super::*;
    use crate::api::studio::subscription::BridgeTaskRegistry;
    use crate::api::studio::types::BridgeErrorCode;
    use std::future::Future;
    use std::pin::Pin;
    use std::task::{Context, Poll};
    use tokio::sync::Notify;

    fn owner(id: u64) -> Arc<TimelineFeedOwner> {
        TimelineFeedOwner::new(id, format!("thread-{id}"), CancellationToken::new())
    }

    fn fill_window(owner: &Arc<TimelineFeedOwner>) {
        let event = crate::api::studio::types::BridgeTimelineEvent::Baseline {
            baseline: crate::api::studio::types::BridgeTimelineBaseline {
                subscription_id: "feed".to_string(),
                version: 1,
                items: Vec::new(),
                before: None,
                has_older: false,
            },
        };
        owner.emit_data(&|_| Ok(()), event.clone()).unwrap();
        owner
            .emit_data(
                &|_| Ok(()),
                crate::api::studio::types::BridgeTimelineEvent::Update {
                    update: crate::api::studio::types::BridgeTimelineUpdate::Patch {
                        subscription_id: "feed".to_string(),
                        from: 1,
                        to: 2,
                        changes: Vec::new(),
                        priority: crate::api::studio::types::BridgeTimelinePriority::Immediate,
                    },
                },
            )
            .unwrap();
        assert_eq!(owner.sent_acked(), (2, 0));
    }

    fn poll_once<F: Future>(fut: &mut Pin<Box<F>>) -> Poll<F::Output> {
        let waker = futures::task::noop_waker();
        let mut cx = Context::from_waker(&waker);
        fut.as_mut().poll(&mut cx)
    }

    async fn registry_contains(registry: &BridgeTaskRegistry, id: u64) -> bool {
        registry.timelines.lock().await.contains_key(&id)
    }

    #[tokio::test]
    async fn timeline_feed_wait_capacity_survives_ack_between_check_and_wait() {
        let owner = owner(1);
        fill_window(&owner);
        owner.arm_capacity_park_gate();
        let checked = owner.capacity_checked();
        tokio::pin!(checked);
        checked.as_mut().enable();
        let mut waiter = {
            let owner = Arc::clone(&owner);
            tokio::spawn(async move { owner.wait_capacity().await })
        };
        checked.await;
        owner.ack_through(2).unwrap();
        owner.resume_capacity_wait();
        let finished =
            tokio::time::timeout(std::time::Duration::from_millis(200), &mut waiter).await;
        match finished {
            Ok(Ok(Ok(()))) => {}
            Ok(Ok(Err(error))) => panic!("capacity wait failed: {error}"),
            Ok(Err(join)) => panic!("capacity waiter join failed: {join}"),
            Err(_) => {
                waiter.abort();
                let _ = waiter.await;
                panic!("capacity waiter hung after ACK between full-window check and park");
            }
        }
    }

    #[tokio::test]
    async fn timeline_feed_close_does_not_clean_before_delivery_joins() {
        let owner = owner(2);
        owner.publish_handle();
        let started = Arc::new(Notify::new());
        let finish = Arc::new(Notify::new());
        let started_wait = started.notified();
        tokio::pin!(started_wait);
        started_wait.as_mut().enable();
        let started_for_task = started.clone();
        let finish_for_task = finish.clone();
        let handle = tokio::spawn(async move {
            started_for_task.notify_waiters();
            finish_for_task.notified().await;
        });
        started_wait.await;
        owner.start_delivery(handle);
        let call = owner.begin_call().unwrap();
        let mut first = Box::pin(owner.close());
        assert!(matches!(poll_once(&mut first), Poll::Pending));
        assert!(!owner.is_settled());
        drop(first);
        let mut second = Box::pin(owner.close());
        assert!(matches!(poll_once(&mut second), Poll::Pending));
        assert!(!owner.is_settled());
        drop(call);
        assert!(matches!(poll_once(&mut second), Poll::Pending));
        assert!(!owner.is_settled());
        finish.notify_waiters();
        let report = second.await;
        assert_eq!(report.outcome, BridgeFeedCloseOutcome::Clean);
        assert!(owner.is_settled());
    }

    #[tokio::test]
    async fn timeline_feed_registry_keeps_owner_until_true_clean() {
        let registry = BridgeTaskRegistry::new();
        let live = owner(3);
        live.publish_handle();
        live.hold_baseline_for_test();
        let started = Arc::new(Notify::new());
        let finish = Arc::new(Notify::new());
        let started_wait = started.notified();
        tokio::pin!(started_wait);
        started_wait.as_mut().enable();
        let started_for_task = started.clone();
        let finish_for_task = finish.clone();
        let handle = tokio::spawn(async move {
            started_for_task.notify_waiters();
            finish_for_task.notified().await;
        });
        started_wait.await;
        live.start_delivery(handle);
        registry.register_timeline(&live).await.unwrap();
        finish.notify_waiters();
        let delivery = live
            .delivery_task
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
            .expect("delivery completion");
        delivery.await.expect("delivery succeeded");
        let other = owner(4);
        registry.register_timeline(&other).await.unwrap();
        assert!(
            registry_contains(&registry, 3).await,
            "finished producer still holding baseline must stay"
        );
        let report = live.close().await;
        assert_eq!(report.outcome, BridgeFeedCloseOutcome::Clean);
        registry.register_timeline(&other).await.unwrap();
        assert!(!registry_contains(&registry, 3).await);
    }

    #[tokio::test]
    async fn timeline_feed_delivery_panic_stays_unresolved_on_reclose() {
        let registry = BridgeTaskRegistry::new();
        let feed = owner(5);
        feed.publish_handle();
        registry.register_timeline(&feed).await.unwrap();
        let handle = tokio::spawn(async {
            panic!("timeline delivery boom");
        });
        feed.start_delivery(handle);
        let first = feed.close().await;
        let second = feed.close().await;
        assert_eq!(first, second);
        match first.outcome {
            BridgeFeedCloseOutcome::Unresolved { issues } => {
                assert_eq!(issues[0].diagnostic.stage, "subscriptions");
                assert_eq!(issues[0].diagnostic.code, "producerTaskFailed");
                assert!(!issues[0].diagnostic.message.contains("boom"));
                assert_eq!(issues[0].recovery, crate::api::studio::types::BridgeCleanupRecovery::Terminal);
            }
            other => panic!("expected unresolved, got {other:?}"),
        }
        assert!(!feed.is_settled());
        registry.unregister_timeline(5).await;
        assert!(registry_contains(&registry, 5).await);
        let extra = owner(50);
        registry.register_timeline(&extra).await.unwrap();
        assert!(registry_contains(&registry, 5).await);
    }

    #[tokio::test]
    async fn timeline_feed_aborted_opening_does_not_accumulate_empty_owners() {
        let registry = BridgeTaskRegistry::new();
        let first = owner(6);
        let opening = first.begin_opening();
        let call = first.begin_call().unwrap();
        registry.register_timeline(&first).await.unwrap();
        let mut close = Box::pin(first.close());
        assert!(matches!(poll_once(&mut close), Poll::Pending));
        drop(close);
        drop(call);
        drop(opening);
        assert!(
            first.is_settled(),
            "empty aborted opening must be proveably Clean"
        );
        let weak = Arc::downgrade(&first);
        let second = owner(7);
        registry.register_timeline(&second).await.unwrap();
        assert!(!registry_contains(&registry, 6).await);
        drop(first);
        assert!(
            weak.upgrade().is_none(),
            "pruned empty opening must not retain a close_join self-cycle"
        );

        let live = owner(8);
        let opening = live.begin_opening();
        let call = live.begin_call().unwrap();
        registry.register_timeline(&live).await.unwrap();
        drop(opening);
        assert!(!live.is_settled(), "active opening call must retain owner");
        let other = owner(9);
        registry.register_timeline(&other).await.unwrap();
        assert!(registry_contains(&registry, 8).await);
        drop(call);
        assert!(live.is_settled());
    }

    #[tokio::test]
    async fn timeline_feed_published_owner_does_not_take_empty_opening_shortcut() {
        let owner = owner(11);
        owner.publish_handle();
        let call = owner.begin_call().unwrap();
        let mut close = Box::pin(owner.close());
        assert!(matches!(poll_once(&mut close), Poll::Pending));
        drop(close);
        drop(call);
        assert!(
            !owner.is_settled(),
            "published handle must join through close, not the aborted-opening shortcut"
        );
        let report = owner.close().await;
        assert_eq!(report.outcome, BridgeFeedCloseOutcome::Clean);
        assert!(owner.is_settled());
    }

    #[tokio::test]
    async fn timeline_feed_wait_capacity_still_rejects_beyond_sent() {
        let owner = owner(10);
        fill_window(&owner);
        let error = owner.ack_through(3).unwrap_err();
        assert_eq!(error.code, BridgeErrorCode::Protocol);
        assert_eq!(owner.sent_acked(), (2, 0));
    }
}
