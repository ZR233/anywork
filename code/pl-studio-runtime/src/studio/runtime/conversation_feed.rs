//! 同一会话的完成交付与当前态观察；查询独立持有同一注册 Session。

use anyhow::{Result, ensure};
use futures::future::BoxFuture;
use pl_protocol::{
    ActivityContentFrame, ThreadSubscriptionRequest, ThreadSubscriptionUpdate,
    TimelineCompletionCursor, TimelineTailUpdate,
    studio::{StudioError, StudioErrorCode},
};
use std::{collections::VecDeque, sync::Arc};
use tokio::sync::watch;
use tokio_util::sync::CancellationToken;

use super::activity_delivery::{ACTIVITY_CONTENT_BUDGET_BYTES, ActivityDelivery};
use super::{StudioRuntime, StudioThreadSubscription, TimelineContentReader, TimelineTailStream};
use crate::studio::thread_projection::ActivitySnapshot;

#[cfg(test)]
mod tests;

#[derive(Debug, Clone)]
pub enum ConversationEvent {
    State {
        update: Box<ThreadSubscriptionUpdate>,
    },
    ContentBaseline {
        baseline: pl_protocol::TimelineTailBaseline,
    },
    ContentUpdate {
        update: TimelineTailUpdate,
    },
    /// 仅 Commit 可以附带使活动退出的完成批次；先接纳完成项，再公开活动当前态。
    ActivityContent {
        frame: ActivityContentFrame,
        completed: Option<Box<TimelineTailUpdate>>,
    },
}

type StateWait = BoxFuture<
    'static,
    (
        StudioThreadSubscription,
        Result<Option<ThreadSubscriptionUpdate>>,
    ),
>;
type ContentWait = BoxFuture<'static, (TimelineTailStream, Result<Option<TimelineTailUpdate>>)>;

/// 唯一接收者只拥有有界在途帧、各源等待和取消；不复制历史窗口或执行资源。
pub struct ConversationFeed {
    reader: TimelineContentReader,
    subscription_id: String,
    initial: Option<ConversationEvent>,
    state_wait: Option<StateWait>,
    content_wait: Option<ContentWait>,
    activity_source: Option<watch::Receiver<Arc<ActivitySnapshot>>>,
    activity_delivery: ActivityDelivery,
    activity_frames: VecDeque<ActivityContentFrame>,
    activity_through: u64,
    delivered_completion: u64,
    bootstrap_activity: bool,
    cancel: CancellationToken,
}

impl std::fmt::Debug for ConversationFeed {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConversationFeed")
            .field("thread_id", &self.thread_id())
            .field("subscription_id", &self.subscription_id)
            .field("delivered_completion", &self.delivered_completion)
            .field("closed", &self.cancel.is_cancelled())
            .finish_non_exhaustive()
    }
}

impl StudioRuntime {
    /// 首订阅直接捕获基线；同代重连先交最新活动，再从实际接纳位置连续补发。
    /// epoch 变化只 reset 完成窗口；未公开的局部资源在失败或取消时直接释放。
    pub async fn open_conversation_feed(
        &self,
        thread_id: &str,
        resume_after: Option<TimelineCompletionCursor>,
    ) -> Result<ConversationFeed> {
        let reader = self.timeline_reader(thread_id).await?;
        let same_epoch = resume_after
            .as_ref()
            .filter(|cursor| cursor.timeline_epoch == reader.epoch());
        let bootstrap_activity = same_epoch.is_some();
        let (content, initial, delivered_completion) = if let Some(cursor) = same_epoch {
            (
                reader.open_tail_after(cursor).await?,
                None,
                cursor.append_seq,
            )
        } else {
            let mut content = reader.open_tail().await?;
            let baseline = content.initial().await?;
            let through = baseline.completed_cursor.append_seq;
            let initial = if resume_after.is_some() {
                ConversationEvent::ContentUpdate {
                    update: TimelineTailUpdate::Reset { baseline },
                }
            } else {
                ConversationEvent::ContentBaseline { baseline }
            };
            (content, Some(initial), through)
        };
        let subscription_id = content.subscription_id().to_owned();
        let state = self
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: thread_id.to_owned(),
            })
            .await?;
        let mut activity_source = self
            .thread_observations
            .live_feed(thread_id)
            .map(|feed| feed.activity_content());
        let snapshot = activity_source
            .as_mut()
            .map(|source| source.borrow_and_update().clone())
            .unwrap_or_default();
        let activity_through = snapshot.completed_through;
        let mut activity_delivery = ActivityDelivery::default();
        let activity_frames = activity_delivery
            .encode(snapshot, ACTIVITY_CONTENT_BUDGET_BYTES)?
            .into();
        let cancel = CancellationToken::new();
        Ok(ConversationFeed {
            reader,
            subscription_id,
            initial,
            state_wait: Some(wait_state(state, cancel.clone())),
            content_wait: Some(wait_content(content, cancel.clone())),
            activity_source,
            activity_delivery,
            activity_frames,
            activity_through,
            delivered_completion,
            bootstrap_activity,
            cancel,
        })
    }
}

impl ConversationFeed {
    pub fn thread_id(&self) -> &str {
        self.reader.thread_id()
    }
    pub fn subscription_id(&self) -> &str {
        &self.subscription_id
    }
    pub fn reader(&self) -> &TimelineContentReader {
        &self.reader
    }

    pub async fn recv(&mut self) -> Result<Option<ConversationEvent>> {
        loop {
            if self.cancel.is_cancelled() {
                return Err(cancelled());
            }
            if let Some(initial) = self.initial.take() {
                self.reader.ensure_read_access()?;
                return Ok(Some(initial));
            }
            if self.state_wait.is_none()
                && self.content_wait.is_none()
                && self.activity_source.is_none()
                && self.activity_frames.is_empty()
            {
                return Ok(None);
            }
            let commit_waits = matches!(
                self.activity_frames.front(),
                Some(ActivityContentFrame::Commit { .. })
            ) && !self.bootstrap_activity
                && self.delivered_completion < self.activity_through;
            ensure!(
                !commit_waits || self.content_wait.is_some(),
                "activity commit lost its completion source"
            );
            let activity_ready = !self.activity_frames.is_empty() && !commit_waits;
            let watch_activity = self.activity_source.is_some() && self.activity_frames.is_empty();
            tokio::select! {
                () = self.cancel.cancelled() => return Err(cancelled()),
                frame = async { self.activity_frames.pop_front().expect("guarded activity frame") }, if activity_ready => {
                    self.reader.ensure_read_access()?;
                    if matches!(frame, ActivityContentFrame::Commit { .. }) { self.bootstrap_activity = false; }
                    return Ok(Some(ConversationEvent::ActivityContent { frame, completed: None }));
                }
                changed = activity_changed(&mut self.activity_source), if watch_activity => {
                    if changed.is_err() { self.activity_source = None; }
                    else if let Some(source) = self.activity_source.as_mut() {
                        let snapshot = source.borrow_and_update().clone();
                        self.activity_through = snapshot.completed_through;
                        self.activity_frames = self.activity_delivery.encode(snapshot, ACTIVITY_CONTENT_BUDGET_BYTES)?.into();
                    }
                }
                (state, result) = receive_slot(&mut self.state_wait) => {
                    self.state_wait = None;
                    match result {
                        Ok(Some(update)) => {
                            self.reader.ensure_read_access()?;
                            self.state_wait = Some(wait_state(state, self.cancel.clone()));
                            return Ok(Some(ConversationEvent::State { update: Box::new(update) }));
                        }
                        Ok(None) => drop(state),
                        Err(error) => { self.request_close(); return Err(error); }
                    }
                }
                (mut content, result) = receive_slot(&mut self.content_wait), if !self.bootstrap_activity => {
                    self.content_wait = None;
                    match result {
                        Ok(Some(update)) => {
                            self.reader.ensure_read_access()?;
                            let TimelineTailUpdate::Batch { from_seq, through_seq, .. } = &update else {
                                anyhow::bail!("a registered completion tail changed its epoch");
                            };
                            ensure!(*from_seq == self.delivered_completion, "completion tail skipped a delivered position");
                            self.delivered_completion = *through_seq;
                            self.content_wait = Some(wait_content(content, self.cancel.clone()));
                            if commit_waits && self.delivered_completion >= self.activity_through {
                                let frame = self.activity_frames.pop_front().expect("pending commit");
                                return Ok(Some(ConversationEvent::ActivityContent { frame, completed: Some(Box::new(update)) }));
                            }
                            return Ok(Some(ConversationEvent::ContentUpdate { update }));
                        }
                        Ok(None) => content.close(),
                        Err(error) => { content.close(); self.request_close(); return Err(error); }
                    }
                }
            }
        }
    }

    pub fn request_close(&self) {
        self.cancel.cancel();
    }

    /// 取消当前观察并 join 已捕获的各源等待；不取消业务执行或可靠 writer。
    pub async fn close(&mut self) -> Result<()> {
        self.request_close();
        self.initial = None;
        self.activity_frames.clear();
        self.activity_source = None;
        if let Some(wait) = self.state_wait.as_mut() {
            let (state, _) = wait.await;
            self.state_wait = None;
            drop(state);
        }
        if let Some(wait) = self.content_wait.as_mut() {
            let (mut content, _) = wait.await;
            self.content_wait = None;
            content.close();
        }
        Ok(())
    }
}

impl Drop for ConversationFeed {
    fn drop(&mut self) {
        self.request_close();
    }
}

async fn activity_changed(
    source: &mut Option<watch::Receiver<Arc<ActivitySnapshot>>>,
) -> std::result::Result<(), watch::error::RecvError> {
    match source {
        Some(source) => source.changed().await,
        None => std::future::pending().await,
    }
}

fn wait_state(mut state: StudioThreadSubscription, cancel: CancellationToken) -> StateWait {
    Box::pin(async move {
        let result = tokio::select! { biased; () = cancel.cancelled() => Err(cancelled()), result = state.recv() => result };
        (state, result)
    })
}

fn wait_content(mut content: TimelineTailStream, cancel: CancellationToken) -> ContentWait {
    Box::pin(async move {
        let result = tokio::select! { biased; () = cancel.cancelled() => Err(cancelled()), result = content.next() => result };
        (content, result)
    })
}

async fn receive_slot<T>(slot: &mut Option<BoxFuture<'static, T>>) -> T {
    match slot {
        Some(wait) => wait.await,
        None => std::future::pending().await,
    }
}

fn cancelled() -> anyhow::Error {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "The conversation observation is closed",
        false,
    )
    .into()
}
