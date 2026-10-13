use std::sync::atomic::{AtomicU64, Ordering};

use tokio::sync::Mutex;
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
/// `window: Mutex<ChatWindowStream>` 串行化所有接触窗口的操作（`load`/`focus`/取帧），让窗口差量
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
    window: Mutex<ChatWindowStream>,
    /// 同一个 view 的锁外句柄：按身份读条目不经过窗口锁，也不参与窗口差量基线。
    handle: ChatWindowHandle,
    initial: BridgeChatSnapshot,
    /// 控制操作计数器：回执 `operationId` 的来源，客户端据此把 pending 与回执/目标版本关联。
    operations: AtomicU64,
    cancel: CancellationToken,
}

pub async fn open_chat_view(
    thread_id: String,
    focus: BridgeChatFocus,
) -> Result<BridgeChatView, BridgeError> {
    let bridge = active_bridge().await?;
    let stream = bridge
        .studio
        .open_chat_window(&thread_id, &chat_window::query(focus))
        .await?;
    let handle = stream.handle();
    let initial = chat_window::snapshot(stream.initial()?)?;
    let cancel = bridge.shutdown.child_token();
    Ok(BridgeChatView {
        window: Mutex::new(stream),
        handle,
        initial,
        operations: AtomicU64::new(0),
        cancel,
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
    pub fn initial(&self) -> BridgeChatSnapshot {
        self.initial.clone()
    }

    /// Waits for one consolidated batch, then returns control to the consumer.
    ///
    /// 「锁外 readiness 等待 + 短临界区同步取帧」：等待期间不持窗口锁（见结构体文档），`close` 立刻
    /// 打断等待。`Ok(None)` 只表示窗口流真的结束（会话不再变化或视图已关闭）。
    pub async fn next(&self) -> Result<Option<BridgeChatUpdate>, BridgeError> {
        loop {
            // 短临界区：只读本消费者「已看过」的唤醒水位，不构 diff、不等待。
            let seen = { self.window.lock().await.observed_version() };
            // 锁外 readiness 等待：只看版本与边界水位，cancel 可打断，不持有窗口锁。
            let ready = tokio::select! {
                biased;
                () = self.cancel.cancelled() => return Ok(None),
                ready = self.handle.wait_change(seen) => ready,
            };
            if ready.is_none() {
                return Ok(None);
            }
            // 短临界区：一次同步 take，只算一次差量并原子推进两个水位。
            let update = { self.window.lock().await.take()? };
            if let Some(update) = update {
                return chat_window::update(update).map(Some);
            }
            // 只推进 observed、本窗口看不到的变化，或已被控制操作交付：回到锁外等待。
        }
    }

    fn next_operation_id(&self) -> u64 {
        self.operations.fetch_add(1, Ordering::Relaxed) + 1
    }

    /// 按方向翻页的操作回执：从**当前窗口**继续（core `ChatView::load` 换入一页、换出相反方向的一页）。
    ///
    /// 窗口移动由下一次 `next` 交付；`close` 会取消正在等待 history 的翻页。
    pub async fn load(
        &self,
        direction: BridgeChatDirection,
    ) -> Result<BridgeChatReceipt, BridgeError> {
        if self.cancel.is_cancelled() {
            return Err(view_closed());
        }
        let operation_id = self.next_operation_id();
        let mut window = self.window.lock().await;
        tokio::select! {
            biased;
            () = self.cancel.cancelled() => Err(view_closed()),
            result = window.load(chat_window::direction(direction)) => {
                Ok(chat_window::receipt(result?, operation_id))
            }
        }
    }

    /// Fill a short latest viewport without detaching from live content; returns the operation
    /// receipt (`extend_latest` 的 no-op 分支不推进版本、无帧）。Closing cancels the read.
    pub async fn extend_latest(&self) -> Result<BridgeChatReceipt, BridgeError> {
        if self.cancel.is_cancelled() {
            return Err(view_closed());
        }
        let operation_id = self.next_operation_id();
        let mut window = self.window.lock().await;
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
        if self.cancel.is_cancelled() {
            return Err(view_closed());
        }
        let operation_id = self.next_operation_id();
        let query = chat_window::query(focus);
        let mut window = self.window.lock().await;
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
        self.handle
            .read_item(&item_id)
            .await?
            .map(chat_window::item)
            .transpose()
    }

    /// 展开被有界窗口省略的条目：一次**同 view 的窗口操作**，返回操作回执。
    ///
    /// 步骤：锁外请求该身份的**完整**正文（同 view/revision，历史条目至多冷读一次并保留到身份离开
    /// 窗口；被取消不会写回）。当这次请求真的升级了仍在本窗口条目的可见正文时，core 推进版本并通知，
    /// 完整正文由下一次 `next` 以 typed 字段更新从唯一出口交付——客户端不在这里收到窗口，也不需要
    /// 自己覆一份 item 或维持另一份 baseline。`retained == false` 表示身份已不在窗口或完整正文此刻
    /// 不可得：调用方保留预览与重试入口，不伪造正文。
    pub async fn expand(&self, item_id: String) -> Result<BridgeChatReceipt, BridgeError> {
        if self.cancel.is_cancelled() {
            return Err(view_closed());
        }
        let operation_id = self.next_operation_id();
        // 锁外请求完整正文：等待 history 冷读时不阻塞帧交付与其他窗口操作。
        let retained = tokio::select! {
            biased;
            () = self.cancel.cancelled() => return Err(view_closed()),
            result = self.handle.request_complete(&item_id) => result?.is_some(),
        };
        let window = self.window.lock().await;
        Ok(chat_window::receipt(window.receipt(retained), operation_id))
    }

    /// 结束这个窗口：取消锁内的帧等待、打断正在 await history 的翻页/换焦点。
    pub fn close(&self) {
        self.cancel.cancel();
    }
}

impl Drop for BridgeChatView {
    fn drop(&mut self) {
        self.cancel.cancel();
    }
}
