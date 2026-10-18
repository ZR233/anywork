//! Timeline 内容源的 FRB 句柄：一页读取、按身份详情与一条有界尾部连接。
//!
//! 句柄只捕获同一个共享 `Session`（经 `TimelineTailStream`）与自己的取消令牌。三条路径互不阻塞：
//! `page` 与 `read_detail` 不经过取帧的锁，因此一个挂起的 `next` 不会挡住翻页或读正文；同一句柄同时
//! 发起第二个 `next` 直接返回 `Busy`，不排队两个消费者。
//!
//! 关闭顺序固定：先拒绝新调用并取消在途等待，再等待所有登记调用退出，最后释放首帧、尾部基线与
//! `Session` 引用。重复 `close` 对同一批资源执行同样的收束，不会提前确认。`Drop` 只发取消请求，不假装
//! 完成 join。

use std::sync::{
    Arc, Mutex as SyncMutex,
    atomic::{AtomicBool, Ordering},
};

use tokio::sync::{Mutex, Notify};
use tokio_util::sync::CancellationToken;

use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::timeline_content;
use crate::api::studio::types::{
    BridgeError, BridgeTimelineBaseline, BridgeTimelineDetailChunk, BridgeTimelineDetailQuery,
    BridgeTimelinePage, BridgeTimelineUpdate,
};
use pl_studio_runtime::{TimelineContentReader, TimelineTailStream};

/// 一个独立的 Timeline 内容句柄。
pub struct BridgeTimeline {
    /// 打开时捕获的内容读取句柄：同一共享 `Session` 与 Thread 身份，`page`/`read_detail` 都走它。
    ///
    /// 关闭后它被真正释放，因此已关闭的句柄不可能按 thread id 读到另一个运行时实例。
    reader: SyncMutex<Option<Arc<TimelineContentReader>>>,
    /// 串行化取帧；`page`/`read_detail` 不经过它。
    tail: Mutex<Option<TimelineTailStream>>,
    initial: SyncMutex<Option<BridgeTimelineBaseline>>,
    /// 同时只允许一个在途 `next`；第二个直接 `Busy`。
    next_in_flight: AtomicBool,
    cancel: CancellationToken,
    /// 注册/退出在途调用与发布 closing 共用同一个短锁，不跨 await，也不嵌套尾部锁。
    activity: SyncMutex<TimelineActivity>,
    idle: Notify,
}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
struct TimelineActivity {
    closing: bool,
    active_calls: usize,
}

/// 每个获准进入的句柄 API 都持有一份；future 被取消时也会退出登记。
struct TimelineCall<'a> {
    timeline: &'a BridgeTimeline,
}

/// 一次在途取帧；析构时释放独占标记，取消或提前返回都不会把它留成永久 Busy。
struct NextGuard<'a> {
    timeline: &'a BridgeTimeline,
}

pub async fn open_timeline(thread_id: String) -> Result<BridgeTimeline, BridgeError> {
    let bridge = active_bridge().await?;
    let cancel = bridge.shutdown.child_token();
    // One captured reader and one tail observation share the same session, so a later page or detail
    // can never resolve a different instance than the frames this handle delivers.
    let reader = tokio::select! {
        biased;
        () = cancel.cancelled() => return Err(timeline_closed()),
        reader = bridge.studio.timeline_reader(&thread_id) => Arc::new(reader?),
    };
    let mut stream = tokio::select! {
        biased;
        () = cancel.cancelled() => return Err(timeline_closed()),
        stream = reader.open_tail() => stream?,
    };
    let initial = timeline_content::baseline(stream.initial()?)?;
    Ok(BridgeTimeline {
        reader: SyncMutex::new(Some(reader)),
        tail: Mutex::new(Some(stream)),
        initial: SyncMutex::new(Some(initial)),
        next_in_flight: AtomicBool::new(false),
        cancel,
        activity: SyncMutex::new(TimelineActivity::default()),
        idle: Notify::new(),
    })
}

/// 句柄已关闭：明确的生命周期错误，而不是让调用方永久挂起。
fn timeline_closed() -> BridgeError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Cancelled,
        "timeline handle is closed",
        false,
    )
    .into()
}

/// 首帧已经交付过：它是单次移交，不是可重复读取的 getter。
fn baseline_taken() -> BridgeError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Conflict,
        "the timeline first frame was already delivered by this handle",
        false,
    )
    .into()
}

/// 首帧尚未交付：Dart 必须先取第一帧，不能直接开始等帧。
///
/// 这是 transport 边界上的 gate，与 core 观察自身的单次移交纪律一致：即使句柄在打开时已经从 core
/// 取走首帧并缓存，外部消费者没消费它之前也不允许 `next`。
fn initial_required() -> BridgeError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Conflict,
        "the timeline first frame must be taken before awaiting tail frames",
        false,
    )
    .into()
}

/// 同一句柄已经有一个在途取帧：不排队第二个消费者。
fn next_busy() -> BridgeError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Busy,
        "timeline handle already awaits one tail frame",
        true,
    )
    .into()
}

impl BridgeTimeline {
    /// Hands the captured first frame over, once.
    ///
    /// The baseline is moved out and the handle keeps no second copy, so a long-lived connection costs
    /// one bounded continuity baseline instead of "first page + continuity copy". A closed handle and
    /// an already-delivered first frame are distinct typed errors.
    pub fn initial(&self) -> Result<BridgeTimelineBaseline, BridgeError> {
        let _call = self.begin_call()?;
        self.initial
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take()
            .ok_or_else(baseline_taken)
    }

    /// Reads one stateless page: newest, or strictly older than the opaque `before` token.
    ///
    /// It never waits for a pending `next`.
    pub async fn page(
        &self,
        before: Option<String>,
        limit: Option<u32>,
    ) -> Result<BridgeTimelinePage, BridgeError> {
        let _call = self.begin_call()?;
        let reader = self.content()?;
        let query = timeline_content::page_query(before, limit);
        let page = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Err(timeline_closed()),
            page = reader.page(&query) => page?,
        };
        timeline_content::page(page)
    }

    /// Waits for, and returns, the next frame of this connection.
    ///
    /// `Ok(None)` only means the session no longer publishes progress; an error is never turned into a
    /// normal end of content.
    ///
    /// The first frame must already be handed over by [`BridgeTimeline::initial`], otherwise this
    /// returns a typed `Conflict` without touching the tail lock: a Dart pump that calls `next` first
    /// cannot bypass the single hand-off. `page`/`read_detail` do not require it. A second concurrent
    /// call returns `Busy`, and a closed handle always returns `Cancelled` before any of these checks.
    pub async fn next(&self) -> Result<Option<BridgeTimelineUpdate>, BridgeError> {
        let _call = self.begin_call()?;
        // 关闭优先由 `begin_call` 判定；随后才是「首帧必须先交付」这条外部纪律。
        self.ensure_first_frame_delivered()?;
        let _exclusive = self.begin_next()?;
        let mut tail = self.lock_tail().await?;
        let Some(stream) = tail.as_mut() else {
            return Err(timeline_closed());
        };
        let update = tokio::select! {
            biased;
            // 关闭／取消不是内容的正常结束：返回类型化 Cancelled，由上层收束，而不是假 EOF。
            () = self.cancel.cancelled() => return Err(timeline_closed()),
            update = stream.next() => update?,
        };
        update.map(timeline_content::update).transpose()
    }

    /// Reads one bounded block of a field's complete body.
    ///
    /// It never waits for a pending `next`.
    pub async fn read_detail(
        &self,
        item_id: String,
        query: BridgeTimelineDetailQuery,
    ) -> Result<BridgeTimelineDetailChunk, BridgeError> {
        let _call = self.begin_call()?;
        let reader = self.content()?;
        let query = timeline_content::detail_query(query);
        let chunk = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Err(timeline_closed()),
            chunk = reader.read_detail(&item_id, &query) => chunk?,
        };
        timeline_content::detail_chunk(chunk)
    }

    /// Synchronously rejects new calls and cancels in-flight waits.
    ///
    /// The shared `Session`, its Turn and the history writer keep running.
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        {
            let mut activity = self
                .activity
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            activity.closing = true;
        }
        self.cancel.cancel();
    }

    /// Idempotent close: reject new calls, wait for every registered call, then release the baseline,
    /// the tail observation and the session reference.
    ///
    /// A second close observes the same `closing` flag and the same drain condition, so it can never
    /// confirm earlier than the first.
    pub async fn close(&self) {
        self.request_close();
        loop {
            let idle = self.idle.notified();
            tokio::pin!(idle);
            // Register the notification before checking the condition so the last call cannot exit
            // between the check and the wait.
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
        // Every API released its borrows before its guard dropped, so no call can still be waiting for
        // the tail lock. Repeating close re-takes the same options, so a cancelled close still finishes
        // releasing what is left.
        let mut tail = self.tail.lock().await.take();
        if let Some(tail) = tail.as_mut() {
            tail.close();
        }
        drop(tail);
        // The captured reader is the handle's whole Session reference; releasing it here is what makes
        // a closed handle unable to read anything again.
        drop(
            self.reader
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .take(),
        );
        drop(
            self.initial
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .take(),
        );
    }

    fn begin_call(&self) -> Result<TimelineCall<'_>, BridgeError> {
        let mut activity = self
            .activity
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if activity.closing || self.cancel.is_cancelled() {
            return Err(timeline_closed());
        }
        activity.active_calls += 1;
        Ok(TimelineCall { timeline: self })
    }

    /// 捕获的内容读取句柄；句柄关闭后明确拒绝。
    fn content(&self) -> Result<Arc<TimelineContentReader>, BridgeError> {
        self.reader
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
            .ok_or_else(timeline_closed)
    }

    /// Whether the cached first frame has been handed to the consumer.
    ///
    /// The check takes the short synchronous lock only; it never waits for a frame and never takes the
    /// tail lock, so it cannot queue a second consumer.
    fn ensure_first_frame_delivered(&self) -> Result<(), BridgeError> {
        let delivered = self
            .initial
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .is_none();
        if delivered {
            Ok(())
        } else {
            Err(initial_required())
        }
    }

    fn begin_next(&self) -> Result<NextGuard<'_>, BridgeError> {
        self.next_in_flight
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| next_busy())?;
        Ok(NextGuard { timeline: self })
    }

    async fn lock_tail(
        &self,
    ) -> Result<tokio::sync::MutexGuard<'_, Option<TimelineTailStream>>, BridgeError> {
        let tail = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Err(timeline_closed()),
            tail = self.tail.lock() => tail,
        };
        Ok(tail)
    }
}

impl Drop for BridgeTimeline {
    fn drop(&mut self) {
        self.request_close();
    }
}

impl Drop for TimelineCall<'_> {
    fn drop(&mut self) {
        let idle = {
            let mut activity = self
                .timeline
                .activity
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            activity.active_calls -= 1;
            activity.active_calls == 0
        };
        if idle {
            self.timeline.idle.notify_waiters();
        }
    }
}

impl Drop for NextGuard<'_> {
    fn drop(&mut self) {
        self.timeline.next_in_flight.store(false, Ordering::Release);
    }
}
