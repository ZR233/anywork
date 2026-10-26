//! Timeline 内容源的 FRB 句柄：一页读取、按身份详情与一条有界推送 feed。
//!
//! 句柄只捕获同一个共享 `Session`（经 `TimelineTailStream`）与自己的取消令牌。三条路径互不阻塞：
//! `page` 与 `read_detail` 不经过取帧的锁，因此一个挂起的 delivery 不会挡住翻页或读正文。
//!
//! 关闭顺序固定：先拒绝新调用并取消在途等待，再等待所有登记调用与唯一 delivery task 退出，最后释放
//! 首帧、尾部基线与 `Session` 引用。重复 `close` 读取同一份 retained 结果。`Drop` 只发取消请求，不假装
//! 完成 join。

use std::sync::Arc;

use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::timeline_content;
use crate::api::studio::subscription::timeline::{TimelineFeedOwner, timeline_closed};
use crate::api::studio::types::{
    BridgeError, BridgeFeedCloseReport, BridgeTimelineDetailChunk, BridgeTimelineDetailQuery,
    BridgeTimelineEvent, BridgeTimelineFrame, BridgeTimelinePage,
};
use crate::frb_generated::StreamSink;

/// 产品 Timeline 载荷准入上限；计数不含 FRB 封套。
const DATA_PAYLOAD_CAP_BYTES: u64 = 8 * 1024 * 1024;

/// 一个独立的 Timeline 内容句柄。
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeTimeline {
    owner: Arc<TimelineFeedOwner>,
}

pub async fn open_timeline(thread_id: String) -> Result<BridgeTimeline, BridgeError> {
    let bridge = active_bridge().await?;
    let cancel = bridge.shutdown.child_token();
    let owner = TimelineFeedOwner::new(bridge.subscriptions.next_id(), thread_id.clone(), cancel);
    let opening = owner.begin_opening();
    let _call = owner.begin_call()?;
    bridge.subscriptions.register_timeline(&owner).await?;
    if owner.is_closing() {
        return Err(timeline_closed());
    }
    let reader = tokio::select! {
        biased;
        () = owner.cancel().cancelled() => return Err(timeline_closed()),
        reader = bridge.studio.timeline_reader(&thread_id) => Arc::new(reader?),
    };
    let mut stream = tokio::select! {
        biased;
        () = owner.cancel().cancelled() => return Err(timeline_closed()),
        stream = reader.open_tail() => stream?,
    };
    let baseline = stream.initial()?;
    if owner.is_closing() {
        drop(stream);
        drop(reader);
        return Err(timeline_closed());
    }
    owner.install(reader, stream, baseline)?;
    drop(opening);
    Ok(BridgeTimeline { owner })
}

impl BridgeTimeline {
    /// 打开本句柄唯一的 typed 推送流；登记 delivery task 后立即返回。
    pub async fn stream(&self, sink: StreamSink<BridgeTimelineFrame>) -> Result<(), BridgeError> {
        let _call = self.owner.begin_call()?;
        self.owner.claim_stream()?;
        let owner = Arc::clone(&self.owner);
        let handle = tokio::spawn(async move {
            run_delivery(owner, move |frame| sink.add(frame).map_err(|_| ())).await;
        });
        self.owner.start_delivery(handle);
        Ok(())
    }

    pub async fn ack_through(&self, delivery_sequence: u64) -> Result<(), BridgeError> {
        let _call = self.owner.begin_call()?;
        self.owner.ack_through(delivery_sequence)
    }

    /// Reads one stateless page: newest, or strictly older than the opaque `before` token.
    ///
    /// It never waits for a pending delivery frame.
    pub async fn page(
        &self,
        before: Option<String>,
        limit: Option<u32>,
    ) -> Result<BridgeTimelinePage, BridgeError> {
        let _call = self.owner.begin_call()?;
        let reader = self.owner.content()?;
        let query = timeline_content::page_query(before, limit);
        let page = tokio::select! {
            biased;
            () = self.owner.cancel().cancelled() => return Err(timeline_closed()),
            page = reader.page(&query) => page?,
        };
        timeline_content::page(page)
    }

    /// Reads one bounded block of a field's complete body.
    ///
    /// It never waits for a pending delivery frame.
    pub async fn read_detail(
        &self,
        item_id: String,
        query: BridgeTimelineDetailQuery,
    ) -> Result<BridgeTimelineDetailChunk, BridgeError> {
        let _call = self.owner.begin_call()?;
        let reader = self.owner.content()?;
        let query = timeline_content::detail_query(query);
        let chunk = tokio::select! {
            biased;
            () = self.owner.cancel().cancelled() => return Err(timeline_closed()),
            chunk = reader.read_detail(&item_id, &query) => chunk?,
        };
        timeline_content::detail_chunk(chunk)
    }

    /// Synchronously rejects new calls and cancels in-flight waits.
    ///
    /// The shared `Session`, its Turn and the history writer keep running.
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.owner.request_close();
    }

    /// Idempotent close: reject new calls, wait for every registered call and the delivery task,
    /// then release the baseline, the tail observation and the session reference.
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        let report = self.owner.close().await;
        if matches!(
            report.outcome,
            crate::api::studio::types::BridgeFeedCloseOutcome::Clean
        ) && let Some(bridge) = crate::api::studio::bridge_runtime::current_bridge()
        {
            bridge
                .subscriptions
                .unregister_timeline(self.owner.id)
                .await;
        }
        Ok(report)
    }

    /// Continues the original retained cleanup; never restarts the content producer.
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.close().await
    }
}

impl Drop for BridgeTimeline {
    fn drop(&mut self) {
        self.request_close();
    }
}

async fn run_delivery<F>(owner: Arc<TimelineFeedOwner>, sink: F)
where
    F: Fn(BridgeTimelineFrame) -> Result<(), ()> + Send + Sync,
{
    let mut failure: Option<BridgeError> = None;
    match deliver_feed(&owner, &sink).await {
        Ok(()) => {}
        Err(error) if error.code == crate::api::studio::types::BridgeErrorCode::Cancelled => {}
        Err(error) => failure = Some(error),
    }
    if let Some(error) = failure {
        let _ = owner.emit_control(&sink, BridgeTimelineFrame::Failure { error });
        return;
    }
    let _ = owner.emit_control(&sink, BridgeTimelineFrame::Closed);
}

async fn deliver_feed<F>(owner: &Arc<TimelineFeedOwner>, sink: &F) -> Result<(), BridgeError>
where
    F: Fn(BridgeTimelineFrame) -> Result<(), ()> + Send + Sync,
{
    let Some(baseline) = owner.take_baseline() else {
        return Err(timeline_closed());
    };
    emit_payload(
        owner,
        sink,
        &baseline,
        BridgeTimelineEvent::Baseline {
            baseline: timeline_content::baseline(baseline.clone())?,
        },
    )
    .await?;
    let Some(mut tail) = owner.take_tail() else {
        return Err(timeline_closed());
    };
    loop {
        if owner.is_closing() {
            return Err(timeline_closed());
        }
        let update = tokio::select! {
            biased;
            () = owner.cancel().cancelled() => return Err(timeline_closed()),
            update = tail.next() => update?,
        };
        let Some(update) = update else {
            return Ok(());
        };
        emit_payload(
            owner,
            sink,
            &update,
            BridgeTimelineEvent::Update {
                update: timeline_content::update(update.clone())?,
            },
        )
        .await?;
    }
}

async fn emit_payload<F>(
    owner: &Arc<TimelineFeedOwner>,
    sink: &F,
    payload: &impl serde::Serialize,
    event: BridgeTimelineEvent,
) -> Result<(), BridgeError>
where
    F: Fn(BridgeTimelineFrame) -> Result<(), ()> + Send + Sync,
{
    let bytes = timeline_content::encoded_payload_bytes(payload)?;
    if bytes > DATA_PAYLOAD_CAP_BYTES {
        return Err(timeline_overloaded());
    }
    owner.wait_capacity().await?;
    match owner.emit_data(sink, event)? {
        crate::api::studio::subscription::timeline::TimelineEmit::Sent => Ok(()),
        crate::api::studio::subscription::timeline::TimelineEmit::Closed => Err(timeline_closed()),
    }
}

fn timeline_overloaded() -> BridgeError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Overloaded,
        "timeline data payload exceeds 8 MiB",
        true,
    )
    .into()
}

#[cfg(test)]
mod timeline_feed_tests {
    use super::*;
    use crate::api::studio::subscription::timeline::TimelineEmit;
    use crate::api::studio::types::{
        BridgeErrorCode, BridgeFeedCloseOutcome, BridgeTimelineBaseline,
    };
    use pl_protocol::{TimelineTailBaseline, TimelineTailUpdate};
    use std::sync::Mutex as StdMutex;
    use tokio_util::sync::CancellationToken;

    struct CollectingSink {
        frames: StdMutex<Vec<BridgeTimelineFrame>>,
        fail_after: StdMutex<Option<usize>>,
    }

    impl CollectingSink {
        fn new() -> Self {
            Self {
                frames: StdMutex::new(Vec::new()),
                fail_after: StdMutex::new(None),
            }
        }

        fn fail_next(&self) {
            let count = self.frames.lock().expect("frames").len();
            *self.fail_after.lock().expect("fail") = Some(count);
        }

        fn frames(&self) -> Vec<BridgeTimelineFrame> {
            self.frames.lock().expect("frames").clone()
        }

        fn add(&self, frame: BridgeTimelineFrame) -> Result<(), ()> {
            let mut frames = self.frames.lock().expect("frames");
            if self
                .fail_after
                .lock()
                .expect("fail")
                .is_some_and(|limit| frames.len() >= limit)
            {
                return Err(());
            }
            frames.push(frame);
            Ok(())
        }
    }

    fn empty_baseline(subscription_id: &str) -> TimelineTailBaseline {
        TimelineTailBaseline {
            subscription_id: subscription_id.to_string(),
            version: 1,
            items: Vec::new(),
            before: None,
            has_older: false,
        }
    }

    fn owner() -> Arc<TimelineFeedOwner> {
        TimelineFeedOwner::new(1, "thread-1".to_string(), CancellationToken::new())
    }

    fn patch_update(from: u64, to: u64) -> TimelineTailUpdate {
        TimelineTailUpdate::Patch {
            subscription_id: "feed-1".to_string(),
            from,
            to,
            changes: Vec::new(),
            priority: pl_protocol::TimelinePriority::Immediate,
        }
    }

    #[tokio::test]
    async fn timeline_feed_window_holds_third_data_until_ack() {
        let owner = owner();
        let sink = CollectingSink::new();
        let baseline = empty_baseline("feed-1");
        emit_payload(
            &owner,
            &|frame| sink.add(frame),
            &baseline,
            BridgeTimelineEvent::Baseline {
                baseline: timeline_content::baseline(baseline.clone()).unwrap(),
            },
        )
        .await
        .unwrap();
        emit_payload(
            &owner,
            &|frame| sink.add(frame),
            &patch_update(1, 2),
            BridgeTimelineEvent::Update {
                update: timeline_content::update(patch_update(1, 2)).unwrap(),
            },
        )
        .await
        .unwrap();
        let (sent, acked) = owner.sent_acked();
        assert_eq!((sent, acked), (2, 0));
        assert_eq!(sink.frames().len(), 2);

        let waiter = {
            let owner = Arc::clone(&owner);
            tokio::spawn(async move { owner.wait_capacity().await })
        };
        tokio::task::yield_now().await;
        assert!(!waiter.is_finished());
        owner.ack_through(1).unwrap();
        waiter.await.unwrap().unwrap();
        emit_payload(
            &owner,
            &|frame| sink.add(frame),
            &patch_update(2, 3),
            BridgeTimelineEvent::Update {
                update: timeline_content::update(patch_update(2, 3)).unwrap(),
            },
        )
        .await
        .unwrap();
        assert_eq!(sink.frames().len(), 3);
        match &sink.frames()[2] {
            BridgeTimelineFrame::Data {
                delivery_sequence, ..
            } => assert_eq!(*delivery_sequence, 3),
            other => panic!("expected third data, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn timeline_feed_ack_is_idempotent_and_rejects_beyond_sent() {
        let owner = owner();
        let sink = CollectingSink::new();
        let baseline = empty_baseline("feed-1");
        emit_payload(
            &owner,
            &|frame| sink.add(frame),
            &baseline,
            BridgeTimelineEvent::Baseline {
                baseline: timeline_content::baseline(baseline.clone()).unwrap(),
            },
        )
        .await
        .unwrap();
        owner.ack_through(0).unwrap();
        owner.ack_through(0).unwrap();
        owner.ack_through(1).unwrap();
        owner.ack_through(1).unwrap();
        let error = owner.ack_through(2).unwrap_err();
        assert_eq!(error.code, BridgeErrorCode::Protocol);
        assert!(!error.retryable);
        let (sent, acked) = owner.sent_acked();
        assert_eq!((sent, acked), (1, 1));
        let other = TimelineFeedOwner::new(2, "thread-2".to_string(), CancellationToken::new());
        other.ack_through(0).unwrap();
        assert_eq!(other.sent_acked(), (0, 0));
    }

    fn terminal_saved_update() -> TimelineTailUpdate {
        TimelineTailUpdate::Patch {
            subscription_id: "feed-1".to_string(),
            from: 2,
            to: 3,
            changes: vec![pl_protocol::TimelineChange::UpdateItem {
                item_id: "item".to_string(),
                expected_revision: 1,
                revision: 1,
                omitted_bytes: 0,
                saved: true,
                lifecycle: pl_protocol::TimelineLifecycle::Terminal,
                item_shell: None,
                fields: vec![pl_protocol::TimelineFieldUpdate {
                    field: pl_protocol::ThreadContentField::Text,
                    change: pl_protocol::TimelineFieldChange::Replace {
                        text: "done".to_string(),
                    },
                    total_bytes: 4,
                    preview_bytes: 4,
                }],
            }],
            priority: pl_protocol::TimelinePriority::Immediate,
        }
    }

    #[tokio::test]
    async fn timeline_feed_terminal_update_still_waits_for_window() {
        let owner = owner();
        let sink = Arc::new(CollectingSink::new());
        let baseline = empty_baseline("feed-1");
        emit_payload(
            &owner,
            &|frame| sink.add(frame),
            &baseline,
            BridgeTimelineEvent::Baseline {
                baseline: timeline_content::baseline(baseline.clone()).unwrap(),
            },
        )
        .await
        .unwrap();
        emit_payload(
            &owner,
            &|frame| sink.add(frame),
            &patch_update(1, 2),
            BridgeTimelineEvent::Update {
                update: timeline_content::update(patch_update(1, 2)).unwrap(),
            },
        )
        .await
        .unwrap();
        assert_eq!(sink.frames().len(), 2);
        owner.arm_capacity_park_gate();
        let checked = owner.capacity_checked();
        tokio::pin!(checked);
        checked.as_mut().enable();
        let terminal = terminal_saved_update();
        let mut sender = {
            let owner = Arc::clone(&owner);
            let sink = Arc::clone(&sink);
            tokio::spawn(async move {
                emit_payload(
                    &owner,
                    &|frame| sink.add(frame),
                    &terminal,
                    BridgeTimelineEvent::Update {
                        update: timeline_content::update(terminal.clone()).unwrap(),
                    },
                )
                .await
            })
        };
        tokio::select! {
            biased;
            () = &mut checked => {}
            early = tokio::time::timeout(std::time::Duration::from_millis(50), &mut sender) => {
                sender.abort();
                let _ = sender.await;
                panic!("terminal emit finished before capacity park: {early:?}");
            }
        }
        assert!(!sender.is_finished());
        assert_eq!(sink.frames().len(), 2);
        owner.ack_through(1).unwrap();
        owner.resume_capacity_wait();
        sender.await.unwrap().unwrap();
        assert_eq!(sink.frames().len(), 3);
        match &sink.frames()[2] {
            BridgeTimelineFrame::Data {
                delivery_sequence,
                event: BridgeTimelineEvent::Update { update },
            } => {
                assert_eq!(*delivery_sequence, 3);
                match update {
                    crate::api::studio::types::BridgeTimelineUpdate::Patch { changes, .. } => {
                        match &changes[0] {
                            crate::api::studio::types::BridgeTimelineChange::UpdateItem {
                                saved,
                                lifecycle,
                                ..
                            } => {
                                assert!(*saved);
                                assert_eq!(
                                    *lifecycle,
                                    crate::api::studio::types::BridgeTimelineLifecycle::Terminal
                                );
                            }
                            other => panic!("expected UpdateItem, got {other:?}"),
                        }
                    }
                    other => panic!("expected Patch, got {other:?}"),
                }
            }
            other => panic!("expected third data, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn timeline_feed_close_joins_without_stream_and_repeats_result() {
        let owner = owner();
        // 未挂流时 owner 仍持有构造期发出的真实原始 feed id；close 必须报告同一份身份，
        // 既不能清空它，也不能在第二次 close 时换成另一份身份。
        let opening_feed_id = owner.feed_id();
        assert!(
            !opening_feed_id.is_empty(),
            "a timeline opening owner must expose its real feed id before close"
        );
        let first = owner.close().await;
        let second = owner.close().await;
        assert_eq!(first, second);
        assert_eq!(first.feed_id, opening_feed_id);
        assert_eq!(second.feed_id, opening_feed_id);
        assert_eq!(first.outcome, BridgeFeedCloseOutcome::Clean);
        assert_eq!(second.outcome, BridgeFeedCloseOutcome::Clean);
    }

    #[tokio::test]
    async fn timeline_feed_sink_failure_cancels_and_join_stays_readable() {
        let owner = owner();
        let sink = CollectingSink::new();
        sink.fail_next();
        let baseline = empty_baseline("feed-1");
        let error = emit_payload(
            &owner,
            &|frame| sink.add(frame),
            &baseline,
            BridgeTimelineEvent::Baseline {
                baseline: timeline_content::baseline(baseline.clone()).unwrap(),
            },
        )
        .await
        .unwrap_err();
        assert_eq!(error.code, BridgeErrorCode::Cancelled);
        let report = owner.close().await;
        assert_eq!(report.outcome, BridgeFeedCloseOutcome::Clean);
        assert!(sink.frames().is_empty());
    }

    #[tokio::test]
    async fn timeline_feed_payload_cap_is_overloaded_without_truncation() {
        let owner = owner();
        let sink = CollectingSink::new();
        let oversized = TimelineTailUpdate::Patch {
            subscription_id: "feed-1".to_string(),
            from: 1,
            to: 2,
            changes: vec![pl_protocol::TimelineChange::UpdateItem {
                item_id: "item".to_string(),
                expected_revision: 0,
                revision: 1,
                omitted_bytes: 0,
                saved: true,
                lifecycle: pl_protocol::TimelineLifecycle::Terminal,
                item_shell: None,
                fields: vec![pl_protocol::TimelineFieldUpdate {
                    field: pl_protocol::ThreadContentField::Text,
                    change: pl_protocol::TimelineFieldChange::Replace {
                        text: "x".repeat((DATA_PAYLOAD_CAP_BYTES as usize) + 8),
                    },
                    total_bytes: DATA_PAYLOAD_CAP_BYTES + 8,
                    preview_bytes: DATA_PAYLOAD_CAP_BYTES + 8,
                }],
            }],
            priority: pl_protocol::TimelinePriority::Immediate,
        };
        let bytes = timeline_content::encoded_payload_bytes(&oversized).unwrap();
        assert!(bytes > DATA_PAYLOAD_CAP_BYTES);
        let error = emit_payload(
            &owner,
            &|frame| sink.add(frame),
            &oversized,
            BridgeTimelineEvent::Update {
                update: crate::api::studio::types::BridgeTimelineUpdate::Patch {
                    subscription_id: "feed-1".to_string(),
                    from: 1,
                    to: 2,
                    changes: Vec::new(),
                    priority: crate::api::studio::types::BridgeTimelinePriority::Immediate,
                },
            },
        )
        .await
        .unwrap_err();
        assert_eq!(error.code, BridgeErrorCode::Overloaded);
        assert!(error.retryable);
        assert!(sink.frames().is_empty());
    }

    #[tokio::test]
    async fn timeline_feed_second_stream_is_conflict() {
        let owner = owner();
        owner.claim_stream().unwrap();
        let error = owner.claim_stream().unwrap_err();
        assert_eq!(error.code, BridgeErrorCode::Conflict);
        assert!(!error.retryable);
    }

    #[tokio::test]
    async fn timeline_feed_resync_is_ordinary_data() {
        let owner = owner();
        let sink = CollectingSink::new();
        let baseline = empty_baseline("feed-1");
        emit_payload(
            &owner,
            &|frame| sink.add(frame),
            &baseline,
            BridgeTimelineEvent::Baseline {
                baseline: timeline_content::baseline(baseline.clone()).unwrap(),
            },
        )
        .await
        .unwrap();
        let resync = TimelineTailUpdate::Resync {
            subscription_id: "feed-1".to_string(),
            reason: pl_protocol::TimelineResyncReason::Lagging,
            baseline: empty_baseline("feed-1"),
        };
        emit_payload(
            &owner,
            &|frame| sink.add(frame),
            &resync,
            BridgeTimelineEvent::Update {
                update: timeline_content::update(resync.clone()).unwrap(),
            },
        )
        .await
        .unwrap();
        match &sink.frames()[1] {
            BridgeTimelineFrame::Data {
                delivery_sequence,
                event: BridgeTimelineEvent::Update { update },
            } => {
                assert_eq!(*delivery_sequence, 2);
                assert!(matches!(
                    update,
                    crate::api::studio::types::BridgeTimelineUpdate::Resync { .. }
                ));
            }
            other => panic!("expected resync data, got {other:?}"),
        }
    }

    #[test]
    fn timeline_feed_emit_does_not_publish_unsent_sequence() {
        let owner = owner();
        let sink = CollectingSink::new();
        sink.fail_next();
        let event = BridgeTimelineEvent::Baseline {
            baseline: BridgeTimelineBaseline {
                subscription_id: "feed-1".to_string(),
                version: 1,
                items: Vec::new(),
                before: None,
                has_older: false,
            },
        };
        let error = match owner.emit_data(&&|frame| sink.add(frame), event) {
            Err(error) => error,
            Ok(TimelineEmit::Sent) => panic!("sent unexpectedly"),
            Ok(TimelineEmit::Closed) => panic!("closed without error"),
        };
        assert_eq!(error.code, BridgeErrorCode::Cancelled);
        assert_eq!(owner.sent_acked(), (0, 0));
        assert!(owner.ack_through(1).is_err());
    }
}
