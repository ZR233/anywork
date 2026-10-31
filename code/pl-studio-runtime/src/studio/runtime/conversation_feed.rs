//! 同一会话的完成交付与当前态观察；查询独立持有同一注册 Session。

use anyhow::{Result, ensure};
use futures::{
    StreamExt,
    future::BoxFuture,
    stream::{Select, select},
};
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

mod sources;
#[cfg(test)]
mod tests;

use sources::{
    ActivitySource, ContentSlot, ContentSource, SourceEvent, StateSource, wait_activity,
};

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
    // Persistent round-robin at two levels gives continuously ready, ungated
    // sources a 2 * 2 arbitration bound (watch acceptance counts as one item).
    // Both cursors survive recv cancellation and rearming of the original waits.
    sources: Select<StateSource, Select<ContentSource, ActivitySource>>,
    cancel: CancellationToken,
}

impl std::fmt::Debug for ConversationFeed {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConversationFeed")
            .field("thread_id", &self.thread_id())
            .field("subscription_id", &self.subscription_id)
            .field(
                "delivered_completion",
                &self.activity().delivered_completion,
            )
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
        let had_activity_source = activity_source.is_some();
        Ok(ConversationFeed {
            reader,
            subscription_id,
            initial,
            sources: select(
                StateSource {
                    wait: Some(wait_state(state, cancel.clone())),
                },
                select(
                    ContentSource {
                        slot: Some(ContentSlot::Waiting(wait_content(content, cancel.clone()))),
                        allowed_through: delivered_completion,
                    },
                    ActivitySource {
                        wait: activity_source.map(|source| wait_activity(source, cancel.clone())),
                        delivery: activity_delivery,
                        frames: activity_frames,
                        through: activity_through,
                        delivered_completion,
                        permitted_completion: delivered_completion,
                        bootstrap: bootstrap_activity,
                        had_source: had_activity_source,
                    },
                ),
            ),
            cancel,
        })
    }
}

impl ConversationFeed {
    fn activity(&self) -> &ActivitySource {
        self.sources.get_ref().1.get_ref().1
    }

    fn activity_mut(&mut self) -> &mut ActivitySource {
        self.sources.get_mut().1.get_mut().1
    }

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
            let (state, rest) = self.sources.get_mut();
            let (content, activity) = rest.get_mut();
            if state.wait.is_none()
                && content.slot.is_none()
                && activity.wait.is_none()
                && activity.frames.is_empty()
            {
                return Ok(None);
            }
            ensure!(
                !activity.commit_waits() || content.slot.is_some(),
                "activity commit lost its completion source"
            );
            if activity.had_source
                && activity.wait.is_none()
                && let Some(ContentSlot::Ready(ready)) = &content.slot
                && let Ok(Some(TimelineTailUpdate::Batch { through_seq, .. })) = &ready.1
            {
                activity.ensure_completion_has_activity(*through_seq)?;
            }
            content.allowed_through = activity.completion_limit();
            let event = tokio::select! {
                biased;
                () = self.cancel.cancelled() => return Err(cancelled()),
                event = self.sources.next() => event.expect("domain sources never terminate"),
            };
            match event {
                SourceEvent::ActivityFrame(frame) => {
                    self.reader.ensure_read_access()?;
                    if matches!(frame, ActivityContentFrame::Commit { .. }) {
                        self.activity_mut().commit_delivered();
                    }
                    return Ok(Some(ConversationEvent::ActivityContent {
                        frame,
                        completed: None,
                    }));
                }
                SourceEvent::ActivityChanged(mut source, changed) => {
                    if changed {
                        let snapshot = source.borrow_and_update().clone();
                        let cancel = self.cancel.clone();
                        let activity = self.activity_mut();
                        activity.through = snapshot.completed_through;
                        activity.frames = activity
                            .delivery
                            .encode(snapshot, ACTIVITY_CONTENT_BUDGET_BYTES)?
                            .into();
                        activity.wait = Some(wait_activity(source, cancel));
                    }
                    // A new completed_through can block its newly encoded Commit.
                    // Recheck all publication/lost-source gates before arbitration.
                }
                SourceEvent::State(state, result) => match result {
                    Ok(Some(update)) => {
                        self.reader.ensure_read_access()?;
                        self.sources.get_mut().0.wait =
                            Some(wait_state(*state, self.cancel.clone()));
                        return Ok(Some(ConversationEvent::State {
                            update: Box::new(update),
                        }));
                    }
                    Ok(None) => drop(state),
                    Err(error) => {
                        self.request_close();
                        return Err(error);
                    }
                },
                SourceEvent::Content => {
                    let source = self.sources.get_ref().1.get_ref().0;
                    let Some(ContentSlot::Ready(ready)) = &source.slot else {
                        unreachable!("content arbitration retains its original result");
                    };
                    if let Ok(Some(update)) = &ready.1 {
                        let TimelineTailUpdate::Batch {
                            from_seq,
                            through_seq,
                            ..
                        } = update
                        else {
                            anyhow::bail!("a registered completion tail changed its epoch");
                        };
                        ensure!(
                            *from_seq == self.activity().delivered_completion,
                            "completion tail skipped a delivered position"
                        );
                        self.activity()
                            .ensure_completion_has_activity(*through_seq)?;
                        if *from_seq >= self.activity().completion_limit() {
                            continue;
                        }
                    }
                    let Some(ContentSlot::Ready(ready)) =
                        self.sources.get_mut().1.get_mut().0.slot.take()
                    else {
                        unreachable!("checked content result");
                    };
                    let (mut content, result) = *ready;
                    match result {
                        Ok(Some(update)) => {
                            self.reader.ensure_read_access()?;
                            let (update, suffix) =
                                completion_prefix(update, self.activity().completion_limit())?;
                            let TimelineTailUpdate::Batch { through_seq, .. } = &update else {
                                unreachable!("validated completion batch");
                            };
                            let activity = self.activity_mut();
                            let commit_waits = activity.commit_waits();
                            activity.delivered_completion = *through_seq;
                            self.sources.get_mut().1.get_mut().0.slot = Some(match suffix {
                                Some(suffix) => {
                                    ContentSlot::Ready(Box::new((content, Ok(Some(suffix)))))
                                }
                                None => {
                                    ContentSlot::Waiting(wait_content(content, self.cancel.clone()))
                                }
                            });
                            let activity = self.activity_mut();
                            if commit_waits && activity.delivered_completion >= activity.through {
                                let frame = activity.frames.pop_front().expect("pending commit");
                                activity.commit_delivered();
                                return Ok(Some(ConversationEvent::ActivityContent {
                                    frame,
                                    completed: Some(Box::new(update)),
                                }));
                            }
                            return Ok(Some(ConversationEvent::ContentUpdate { update }));
                        }
                        Ok(None) => content.close(),
                        Err(error) => {
                            content.close();
                            self.request_close();
                            return Err(error);
                        }
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
        let (state, rest) = self.sources.get_mut();
        let (content, activity) = rest.get_mut();
        activity.frames.clear();
        if let Some(wait) = state.wait.as_mut() {
            let (handle, _) = wait.await;
            state.wait = None;
            drop(handle);
        }
        if let Some(ContentSlot::Waiting(wait)) = content.slot.as_mut() {
            let result = wait.await;
            content.slot = Some(ContentSlot::Ready(Box::new(result)));
        }
        if let Some(ContentSlot::Ready(ready)) = content.slot.take() {
            let (mut handle, _) = *ready;
            handle.close();
        }
        if let Some(wait) = activity.wait.as_mut() {
            let (source, _) = wait.await;
            activity.wait = None;
            drop(source);
        }
        Ok(())
    }
}

impl Drop for ConversationFeed {
    fn drop(&mut self) {
        self.request_close();
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

/// Move a contiguous prefix out of the sole in-flight batch, never read ahead.
fn completion_prefix(
    update: TimelineTailUpdate,
    allowed_through: u64,
) -> Result<(TimelineTailUpdate, Option<TimelineTailUpdate>)> {
    let TimelineTailUpdate::Batch {
        subscription_id,
        timeline_epoch,
        from_seq,
        through_seq,
        mut items,
    } = update
    else {
        anyhow::bail!("a registered completion tail changed its epoch");
    };
    let prefix_through = through_seq.min(allowed_through);
    ensure!(
        prefix_through > from_seq,
        "completion publication has no permitted prefix"
    );
    let suffix = if prefix_through < through_seq {
        let split = items.partition_point(|item| item.header.append_seq <= prefix_through);
        ensure!(
            split > 0 && items[split - 1].header.append_seq == prefix_through,
            "completion batch skipped its publication boundary"
        );
        let suffix = items.split_off(split);
        Some(TimelineTailUpdate::Batch {
            subscription_id: subscription_id.clone(),
            timeline_epoch: timeline_epoch.clone(),
            from_seq: prefix_through,
            through_seq,
            items: suffix,
        })
    } else {
        None
    };
    Ok((
        TimelineTailUpdate::Batch {
            subscription_id,
            timeline_epoch,
            from_seq,
            through_seq: prefix_through,
            items,
        },
        suffix,
    ))
}

fn cancelled() -> anyhow::Error {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "The conversation observation is closed",
        false,
    )
    .into()
}
