//! 完成批次订阅：一致基线与从交付位置出发的连续补发。
//!
//! 一条订阅只持有三类有界状态：捕获的初始基线、自己**已交付**的完成位置，以及一个唤醒水位。
//! 它不重放旧 token、不保留订阅以来的事件日志、不存 UI 日志，也不随历史增长。内部 watch 只承载
//! 完成上界的唤醒位置；内容帧由订阅者相对自己的交付位置通过会话的统一范围读取计算一次。
//!
//! 补发不能丢完成项，也不能因为落后就跳到当前 head：每一批从上次实际交付的完成序号继续，在条数
//! 与页预算内连续交付；预算截断的批次把 `through_seq` 停在真正交付的最后一条上，下一批从这里继续。
//! 订阅是单消费者类型（`&mut self`），支持取消与关闭；详情和分页读取不挂在订阅生命周期上。

use std::fmt;

use tokio::sync::watch;

use crate::chat::{ChatCompletionCursor, ChatCursor, ChatError, ChatItem, Session, TimelineEpoch};

/// The latest small page captured for one subscription, plus the completion position it reached.
///
/// `epoch` is the run generation the whole subscription belongs to; `completed_cursor` names the
/// newest record actually contained in `items`, so a later batch continues strictly after it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatTailBaseline {
    pub epoch: TimelineEpoch,
    pub items: Vec<ChatItem>,
    /// 请求更旧一页时要原样回传的严格边界；只有 `has_older` 为真时给出。
    pub before: Option<ChatCursor>,
    /// 是否真的还有更旧内容：来自同次一致读取的真实存在性证明，不凭条数猜 EOF。
    pub has_older: bool,
    /// The newest completion this baseline actually carries, if any.
    pub completed_cursor: Option<ChatCompletionCursor>,
}

impl ChatTailBaseline {
    /// Reports whether this baseline carries no content (a closed or empty history).
    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }
}

/// One continuously delivered completion batch.
///
/// `from_seq` is the completion sequence the receiver actually held before this batch (the previous
/// `through_seq`, the baseline cursor, or 0 for an empty history); `through_seq` is the sequence of
/// the last record in `items`, never a position beyond what was delivered. Sequences are assigned
/// consecutively, so a receiver can verify continuity directly: the first item continues right
/// after `from_seq`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatCompletedBatch {
    pub from_seq: u64,
    pub through_seq: u64,
    /// 升序不可变完成记录（有界预览）。
    pub items: Vec<ChatItem>,
}

/// One delivered subscription frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChatTailUpdate {
    /// The completions between the receiver's position and this batch's end.
    Batch(ChatCompletedBatch),
    /// The session no longer publishes completions on this channel; the caller must not treat it
    /// as a normal end of content.
    Closed,
}

/// One bounded tail subscription over a session.
///
/// The type is the single-consumer guarantee: [`ChatTail::next`] takes `&mut self`, so two pending
/// reads on the same subscription are impossible by construction. It holds a strong content
/// reference to the session — not an execution-owner pin — so idle retirement of the owner is
/// unaffected, and closing one subscription stops neither the producer nor the history writer.
pub struct ChatTail {
    subscription: Option<TailSubscription>,
    /// The first frame, until the consumer takes it once.
    initial: Option<ChatTailBaseline>,
    /// The completion sequence this subscription has actually delivered.
    delivered: u64,
    /// The highest completion head this subscription has already examined, whether or not it
    /// produced a frame. It is the level-triggered wake watermark, so a skipped head never re-fires
    /// the wait.
    seen: u64,
}

/// The live subscription resources are acquired and released together. A closed tail can remain
/// allocated without keeping either the session or a notification receiver alive.
struct TailSubscription {
    session: Session,
    watch: watch::Receiver<u64>,
}

impl fmt::Debug for ChatTail {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ChatTail")
            .field("delivered", &self.delivered)
            .field("seen", &self.seen)
            .finish_non_exhaustive()
    }
}

impl ChatTail {
    pub(crate) fn new(
        session: Session,
        watch: watch::Receiver<u64>,
        baseline: ChatTailBaseline,
    ) -> Self {
        let delivered = baseline
            .completed_cursor
            .as_ref()
            .map_or(0, |cursor| cursor.append_seq);
        Self {
            subscription: Some(TailSubscription { session, watch }),
            initial: Some(baseline),
            delivered,
            seen: delivered,
        }
    }

    /// Hands the captured first frame over to the consumer, once.
    ///
    /// The baseline is moved out: this subscription never keeps a second copy of the newest page.
    /// Reading it never queries history and never opens a second subscription.
    ///
    /// # Errors
    /// [`ChatError::Cancelled`] once the subscription is closed, and [`ChatError::Conflict`] when the
    /// first frame was already taken — the frame is a single hand-off, not a repeatable getter.
    pub fn initial(&mut self) -> Result<ChatTailBaseline, ChatError> {
        if self.subscription.is_none() {
            return Err(ChatError::Cancelled);
        }
        self.initial.take().ok_or_else(|| {
            ChatError::Conflict(
                "the captured first frame was already taken by this subscription".to_owned(),
            )
        })
    }

    /// Waits for, and returns, the next deliverable completion batch.
    ///
    /// `Closed` only means the session no longer publishes completions on this channel; an error is
    /// never turned into a normal end of content.
    ///
    /// # Errors
    /// [`ChatError::Cancelled`] once the subscription is closed, [`ChatError::Conflict`] when the
    /// first frame has not been taken yet, [`ChatError::Conflict`] when merged candidates disagree
    /// about one identity or sequence, plus the host's own typed storage and preview failures.
    pub async fn next(&mut self) -> Result<ChatTailUpdate, ChatError> {
        if self.subscription.is_none() {
            return Err(ChatError::Cancelled);
        }
        if self.initial.is_some() {
            return Err(ChatError::Conflict(
                "the captured first frame must be taken before awaiting tail updates".to_owned(),
            ));
        }
        loop {
            let Some(subscription) = &self.subscription else {
                return Err(ChatError::Cancelled);
            };
            let session = subscription.session.clone();
            if !self.wait_ready(&subscription.watch).await {
                return Ok(ChatTailUpdate::Closed);
            }
            let from = self.delivered;
            let (items, through) = session.completed_after(from).await?;
            if through <= from {
                // Nothing new is deliverable yet; advance only the wake watermark so this exact
                // observation of the head does not fire again.
                self.seen = session.head_seq();
                continue;
            }
            self.delivered = through;
            // A budget-truncated batch parks the watermark on what was really delivered, so the
            // remainder wakes immediately instead of being skipped to the head.
            self.seen = through;
            return Ok(ChatTailUpdate::Batch(ChatCompletedBatch {
                from_seq: from,
                through_seq: through,
                items,
            }));
        }
    }

    /// Releases this subscription's notification receiver, baseline and session reference.
    ///
    /// The subscription itself derives no background task, so a caller cancels a pending
    /// [`ChatTail::next`] future before closing or dropping it. Closing one subscription stops
    /// neither other subscriptions nor the producer or the history writer. Repeated calls are
    /// harmless; keeping the closed object alive no longer declares observation demand.
    pub fn close(&mut self) {
        self.subscription = None;
        self.initial = None;
    }

    /// Lock-free readiness wait: only the completion-head watermark is read.
    ///
    /// Returns `false` only when the session no longer publishes completions.
    async fn wait_ready(&self, watch: &watch::Receiver<u64>) -> bool {
        let mut waiter = watch.clone();
        loop {
            let head = *waiter.borrow_and_update();
            if head != self.seen {
                return true;
            }
            if waiter.changed().await.is_err() {
                return false;
            }
        }
    }
}
