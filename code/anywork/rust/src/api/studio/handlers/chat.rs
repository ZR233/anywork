use std::sync::{
    Mutex as SyncMutex,
    atomic::{AtomicU64, Ordering},
};

use tokio::sync::{MappedMutexGuard, Mutex, MutexGuard, Notify};
use tokio_util::sync::CancellationToken;

use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::chat_window;
use crate::api::studio::types::{
    BridgeChatDirection, BridgeChatFocus, BridgeChatItem, BridgeChatReceipt, BridgeChatSnapshot,
    BridgeChatUpdate, BridgeError,
};
use pl_studio_runtime::{ChatWindowHandle, ChatWindowStream};

/// 一个独立定位、有界的 FRB 内容窗口。
///
/// 窗口差量、前值索引与基线一致性都由 runtime 的 `ChatWindowStream` 负责（HTTP 与 FRB 共用同一条
/// 映射）；这里只把 typed 结果映射成 FRB DTO。
///
/// `window` 串行化所有接触窗口的操作（`load`/`focus`/取帧），让窗口差量
/// 只有一个写入者；`handle: ChatWindowHandle` 是同一个 `ChatView`（同一个 `Session`）的**锁外**句柄，
/// 按身份读正文走它，不经过窗口锁，因此一个挂起的帧等待不会挡住正文读取。
///
/// 帧等待也走**锁外**：`handle.wait_change(observed_version)` 只看版本与边界水位（不合帧、不构 diff、
/// 不持有窗口锁），随后一个**短临界区**的同步 `take` 只算一次差量并原子推进「已交付」与「已看过」两个
/// 水位。等待期间不持有窗口锁，因此一个挂起的取帧不会挡住 `load`/`focus`/读正文；`close` 靠 select 的
/// cancel 分支立刻结束等待。
///
/// 内容交付只有一个出口 `next`：`load`/`focus`/`extend_latest`/`expand` 只返回操作回执
/// （`BridgeChatReceipt`），不交付窗口——core 在这些操作完成时推进版本并立即唤醒，下一次 `next` 把
/// 窗口移动表达成权威 `Reset`（或大 splice `Patch`），始终以客户端自己的交付基线为 `from`。
pub struct BridgeChatView {
    /// 串行化所有接触窗口的操作；取帧只在短临界区里持锁（见结构体文档）。
    window: Mutex<Option<ChatWindowStream>>,
    /// 同一个 view 的锁外句柄：按身份读条目不经过窗口锁，也不参与窗口差量基线。
    handle: SyncMutex<Option<ChatWindowHandle>>,
    initial: SyncMutex<Option<BridgeChatSnapshot>>,
    /// 控制操作计数器：回执 `operationId` 的来源，客户端据此把 pending 与回执/目标版本关联。
    operations: AtomicU64,
    cancel: CancellationToken,
    /// 注册/退出在途 API 与发布 closing 共用同一个短锁，不跨 await，也不嵌套窗口锁。
    activity: SyncMutex<ChatViewActivity>,
    idle: Notify,
}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
struct ChatViewActivity {
    closing: bool,
    active_calls: usize,
}

/// 每个获准进入的 view API 都持有一份；future 被取消时也会退出登记。
struct ChatViewCall<'a> {
    view: &'a BridgeChatView,
}

pub async fn open_chat_view(
    thread_id: String,
    focus: BridgeChatFocus,
) -> Result<BridgeChatView, BridgeError> {
    let bridge = active_bridge().await?;
    let cancel = bridge.shutdown.child_token();
    let query = chat_window::query(focus);
    let stream = tokio::select! {
        biased;
        () = cancel.cancelled() => return Err(view_closed()),
        stream = bridge.studio.open_chat_window(&thread_id, &query) => stream?,
    };
    let handle = stream.handle();
    let initial = chat_window::snapshot(stream.initial()?)?;
    Ok(BridgeChatView {
        window: Mutex::new(Some(stream)),
        handle: SyncMutex::new(Some(handle)),
        initial: SyncMutex::new(Some(initial)),
        operations: AtomicU64::new(0),
        cancel,
        activity: SyncMutex::new(ChatViewActivity::default()),
        idle: Notify::new(),
    })
}

/// 视图已关闭：明确的生命周期错误，而不是让调用方永久挂起。
fn view_closed() -> BridgeError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Cancelled,
        "chat view is closed",
        false,
    )
    .into()
}

impl BridgeChatView {
    /// The subscription baseline is captured before returning the handle.
    /// A closed view rejects this call rather than returning a stale baseline.
    pub fn initial(&self) -> Result<BridgeChatSnapshot, BridgeError> {
        let _call = self.begin_call()?;
        let initial = self
            .initial
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
            .ok_or_else(view_closed)?;
        Ok(initial)
    }

    /// Waits for one consolidated batch, then returns control to the consumer.
    ///
    /// 「锁外 readiness 等待 + 短临界区同步取帧」：等待期间不持窗口锁（见结构体文档），`close` 立刻
    /// 打断等待。`Ok(None)` 只表示窗口流真的结束（会话不再变化或视图已关闭）。
    pub async fn next(&self) -> Result<Option<BridgeChatUpdate>, BridgeError> {
        let _call = self.begin_call()?;
        let handle = self.view_handle()?;
        loop {
            // 短临界区：只读本消费者「已看过」的唤醒水位，不构 diff、不等待。
            let seen = { self.lock_window().await?.observed_version() };
            // 锁外 readiness 等待：只看版本与边界水位，cancel 可打断，不持有窗口锁。
            let ready = tokio::select! {
                biased;
                () = self.cancel.cancelled() => return Ok(None),
                ready = handle.wait_change(seen) => ready,
            };
            if ready.is_none() {
                return Ok(None);
            }
            // 短临界区：一次同步 take，只算一次差量并原子推进两个水位。
            let update = { self.lock_window().await?.take()? };
            if let Some(update) = update {
                return chat_window::update(update).map(Some);
            }
            // 只推进 observed、本窗口看不到的变化：回到锁外等待。
        }
    }

    fn next_operation_id(&self) -> Result<u64, BridgeError> {
        // 这里只分配唯一编号，不发布其他数据；API 登记与 closing 由 activity 锁同步。
        self.operations
            .try_update(Ordering::Relaxed, Ordering::Relaxed, |previous| {
                previous.checked_add(1)
            })
            .map(|previous| previous + 1)
            .map_err(|_| {
                pl_protocol::studio::StudioError::new(
                    pl_protocol::studio::StudioErrorCode::Overloaded,
                    "chat view operation ids are exhausted",
                    false,
                )
                .into()
            })
    }

    /// 按方向翻页的操作回执：从**当前窗口**继续（core `ChatView::load` 换入一页、换出相反方向的一页）。
    ///
    /// 窗口移动由下一次 `next` 交付；`close` 会取消正在等待 history 的翻页。
    pub async fn load(
        &self,
        direction: BridgeChatDirection,
    ) -> Result<BridgeChatReceipt, BridgeError> {
        let _call = self.begin_call()?;
        let operation_id = self.next_operation_id()?;
        let mut window = self.lock_window().await?;
        tokio::select! {
            biased;
            () = self.cancel.cancelled() => Err(view_closed()),
            result = window.load(chat_window::direction(direction)) => {
                Ok(chat_window::receipt(result?, operation_id))
            }
        }
    }

    /// Fill a short latest viewport without detaching from live content; returns the operation
    /// receipt (`extend_latest` 的 no-op 分支明确返回 NoChange）。Closing cancels the read.
    pub async fn extend_latest(&self) -> Result<BridgeChatReceipt, BridgeError> {
        let _call = self.begin_call()?;
        let operation_id = self.next_operation_id()?;
        let mut window = self.lock_window().await?;
        tokio::select! {
            biased;
            () = self.cancel.cancelled() => Err(view_closed()),
            result = window.extend_latest() => {
                Ok(chat_window::receipt(result?, operation_id))
            }
        }
    }

    /// 换焦点的操作回执：窗口由下一次 `next` 以权威 `Reset` 交付。
    pub async fn focus(&self, focus: BridgeChatFocus) -> Result<BridgeChatReceipt, BridgeError> {
        let _call = self.begin_call()?;
        let operation_id = self.next_operation_id()?;
        let query = chat_window::query(focus);
        let mut window = self.lock_window().await?;
        tokio::select! {
            biased;
            () = self.cancel.cancelled() => Err(view_closed()),
            result = window.focus(&query) => Ok(chat_window::receipt(result?, operation_id)),
        }
    }

    /// 按身份读一条完整条目（内存优先，必要时回落 durable history）。
    ///
    /// 它走的是**同一个 view** 的锁外句柄，读的是与窗口完全相同的共享会话事实：不重新 `open_chat`、
    /// 不按 thread id 另找运行时实例，窗口句柄关闭后也不会读到别的实例的条目。一个挂起的 `next`
    /// 同样不会挡住正文读取。
    pub async fn read_item(&self, item_id: String) -> Result<Option<BridgeChatItem>, BridgeError> {
        let _call = self.begin_call()?;
        let handle = self.view_handle()?;
        let item = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Err(view_closed()),
            item = handle.read_item(&item_id) => item?,
        };
        item.map(chat_window::item).transpose()
    }

    /// 展开被有界窗口省略的条目：一次**同 view 的窗口操作**，返回操作回执。
    ///
    /// 步骤：锁外请求该身份的**完整**正文（同 view/revision，历史条目至多冷读一次并保留到身份离开
    /// 窗口；被取消不会写回）。当这次请求真的升级了仍在本窗口条目的可见正文时，core 推进版本并通知，
    /// 完整正文由下一次 `next` 以 typed 字段更新从唯一出口交付——客户端不在这里收到窗口，也不需要
    /// 自己覆一份 item 或维持另一份 baseline。`retained == false` 表示身份已不在窗口或完整正文此刻
    /// 不可得：调用方保留预览与重试入口，不伪造正文。
    pub async fn expand(&self, item_id: String) -> Result<BridgeChatReceipt, BridgeError> {
        let _call = self.begin_call()?;
        let handle = self.view_handle()?;
        let operation_id = self.next_operation_id()?;
        // 锁外请求完整正文：等待 history 冷读时不阻塞帧交付与其他窗口操作。
        let receipt = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Err(view_closed()),
            result = handle.expand(&item_id) => result?,
        };
        Ok(chat_window::receipt(receipt, operation_id))
    }

    /// 同步拒绝新 view API 并取消在途等待；不关闭共享 Session、Turn 或历史 writer。
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

    /// 幂等关闭：先请求取消，再等待所有获准进入的 view API 退出。
    ///
    /// close 自身不登记为活动调用，也不持窗口锁等待；多个 close 观察同一个 closing 与归零条件。
    /// 归零后释放 view 自有窗口、句柄与首帧，客户端继续持有已关闭的 opaque 也不保留正文资源。
    pub async fn close(&self) {
        self.request_close();
        loop {
            let idle = self.idle.notified();
            tokio::pin!(idle);
            // 先登记通知，再查条件，避免最后一个 API 在检查/等待之间退出造成丢失唤醒。
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
        // 所有 API 的资源借用都在活动 guard 之前释放，归零后没有 API 还能等待/持有窗口锁。
        // 重复 close 对同一批 Option 执行 take，因此取消关闭再重试也能收束剩余释放。
        drop(self.window.lock().await.take());
        drop(
            self.handle
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

    fn begin_call(&self) -> Result<ChatViewCall<'_>, BridgeError> {
        let mut activity = self
            .activity
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if activity.closing || self.cancel.is_cancelled() {
            return Err(view_closed());
        }
        activity.active_calls += 1;
        Ok(ChatViewCall { view: self })
    }

    /// 在途控制操作可以跨 history await 持窗口锁；锁的排队本身也必须被关闭取消。
    async fn lock_window(&self) -> Result<MappedMutexGuard<'_, ChatWindowStream>, BridgeError> {
        let window = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Err(view_closed()),
            window = self.window.lock() => window,
        };
        MutexGuard::try_map(window, Option::as_mut).map_err(|_| view_closed())
    }

    fn view_handle(&self) -> Result<ChatWindowHandle, BridgeError> {
        self.handle
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
            .ok_or_else(view_closed)
    }
}

impl Drop for BridgeChatView {
    fn drop(&mut self) {
        self.request_close();
    }
}

impl Drop for ChatViewCall<'_> {
    fn drop(&mut self) {
        let idle = {
            let mut activity = self
                .view
                .activity
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            activity.active_calls -= 1;
            activity.active_calls == 0
        };
        if idle {
            self.view.idle.notify_waiters();
        }
    }
}
