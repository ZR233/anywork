use anyhow::{Context, Result, bail, ensure};
use pl_protocol::{ThreadContentField, ThreadWorkspaceMode, TimelinePageQuery};
use pl_provider_fixture::ReplyStage;
use tokio::sync::oneshot;

use super::*;

#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
#[path = "../../../../tests/support/mod.rs"]
mod support;

#[derive(Debug)]
struct BufferedBatch {
    epoch: String,
    from: u64,
    through: u64,
    items: Vec<(String, u64)>,
}

fn take_content_wait(feed: &mut ConversationFeed) -> ContentWait {
    match feed.sources.get_mut().1.get_mut().0.slot.take() {
        Some(ContentSlot::Waiting(wait)) => wait,
        _ => panic!("expected the original waiting tail read"),
    }
}

fn install_content_wait(feed: &mut ConversationFeed, wait: ContentWait) {
    let slot = &mut feed.sources.get_mut().1.get_mut().0.slot;
    assert!(slot.is_none(), "one in-flight content responsibility");
    *slot = Some(ContentSlot::Waiting(wait));
}

/// Wrap only the actual stored wait. Its real tail result remains in that wait
/// when a caller drops recv(), and closes through the feed's existing token.
fn gate_next_batch(
    feed: &mut ConversationFeed,
) -> (oneshot::Receiver<BufferedBatch>, oneshot::Sender<()>) {
    let wait = take_content_wait(feed);
    let cancel = feed.cancel.clone();
    let (entered_tx, entered_rx) = oneshot::channel();
    let (release_tx, release_rx) = oneshot::channel();
    install_content_wait(
        feed,
        Box::pin(async move {
            let (mut content, result) = wait.await;
            if let Ok(Some(TimelineTailUpdate::Batch {
                timeline_epoch,
                from_seq,
                through_seq,
                items,
                ..
            })) = &result
            {
                let _ = entered_tx.send(BufferedBatch {
                    epoch: timeline_epoch.clone(),
                    from: *from_seq,
                    through: *through_seq,
                    items: items
                        .iter()
                        .map(|item| (item.header.id.clone(), item.header.append_seq))
                        .collect(),
                });
                tokio::select! {
                    biased;
                    () = cancel.cancelled() => {
                        content.close();
                        return (content, Err(cancelled()));
                    }
                    _ = release_rx => {}
                }
            }
            (content, result)
        }),
    );
    (entered_rx, release_tx)
}

async fn next(feed: &mut ConversationFeed) -> Result<ConversationEvent> {
    feed.recv()
        .await?
        .context("real feed ended before its facts")
}

async fn final_commit_with_buffered_batch(cancel_receive: bool) -> Result<()> {
    let stage = ReplyStage::new();
    let env = support::Environment::new(
        vec![support::prompt_step(
            "atomic-feed-commit",
            0,
            support::held_reply(&stage, "atomic-feed-response"),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Worktree, "atomic-feed-commit")
            .await?;
        let id = &thread.thread.id;
        support::reached(&stage).await?;
        env.runtime.synchronize_thread_observation(id).await?;
        let mut feed = env.runtime.open_conversation_feed(id, None).await?;
        let ConversationEvent::ContentBaseline { baseline } = next(&mut feed).await? else {
            bail!("first observation did not carry its baseline");
        };
        ensure!(!baseline.items.is_empty());
        let accepted = baseline.completed_cursor.append_seq;
        ensure!(accepted > 0);
        loop {
            match next(&mut feed).await? {
                ConversationEvent::State { .. } => {}
                ConversationEvent::ActivityContent {
                    frame: ActivityContentFrame::Commit { .. },
                    completed: None,
                } => break,
                ConversationEvent::ActivityContent {
                    completed: None, ..
                } => {}
                event => bail!("unexpected fact while the provider is held: {event:?}"),
            }
        }
        let reader = feed.reader.clone();
        let (mut entered, release) = gate_next_batch(&mut feed);
        stage.release();
        support::completed_prompt(&env.runtime, id, "atomic-feed-commit").await?;
        env.runtime.synchronize_thread_observation(id).await?;
        let target = reader.head_seq();
        ensure!(target > accepted);

        let mut buffered = None;
        loop {
            let commit_waits = matches!(
                feed.activity().frames.front(),
                Some(ActivityContentFrame::Commit { .. })
            ) && feed.activity().through == target
                && feed.activity().delivered_completion == accepted;
            if buffered.is_some() && commit_waits {
                break;
            }
            tokio::select! {
                batch = &mut entered, if buffered.is_none() => {
                    buffered = Some(batch.context("real tail did not produce its batch")?);
                }
                event = feed.recv() => {
                    match event?.context("real feed ended at the publication boundary")? {
                        ConversationEvent::State { .. } => {}
                        ConversationEvent::ActivityContent {
                            frame: ActivityContentFrame::Commit { .. }, ..
                        } => bail!("activity cleared before its completion batch was released"),
                        ConversationEvent::ActivityContent { completed: None, .. } => {}
                        event => bail!("gated completion escaped its stored wait: {event:?}"),
                    }
                }
            }
        }
        let buffered = buffered.context("actual buffered batch")?;
        ensure!(buffered.epoch == baseline.timeline_epoch);
        ensure!(buffered.from == accepted && buffered.through == target);
        ensure!(!buffered.items.is_empty());
        ensure!(
            buffered
                .items
                .iter()
                .enumerate()
                .all(|(index, (_, seq))| *seq == accepted + index as u64 + 1)
        );

        // Both facts now exist at their actual boundaries. Drain only real state
        // notifications; Pending proves this receive awaits the gated tail result.
        let event = loop {
            let mut receive = Box::pin(feed.recv());
            match futures::poll!(receive.as_mut()) {
                std::task::Poll::Ready(Ok(Some(ConversationEvent::State { .. }))) => continue,
                std::task::Poll::Ready(other) => {
                    bail!("commit bypassed its buffered completion: {other:?}");
                }
                std::task::Poll::Pending => {}
            }
            let page = reader
                .page(&TimelinePageQuery {
                    before: None,
                    limit: Some(100),
                })
                .await?;
            ensure!(page.timeline_epoch == buffered.epoch);
            ensure!(page.items.last().map(|item| item.header.append_seq) == Some(target));
            ensure!(buffered.items.iter().all(|(id, seq)| {
                page.items
                    .iter()
                    .any(|item| &item.header.id == id && item.header.append_seq == *seq)
            }));
            ensure!(
                page.items
                    .iter()
                    .any(|item| item.fields.iter().any(|field| {
                        field.field == ThreadContentField::Text && field.text == "released"
                    }))
            );
            if cancel_receive {
                drop(receive);
                release
                    .send(())
                    .map_err(|_| anyhow::anyhow!("cancelled recv dropped its stored tail wait"))?;
                break next(&mut feed).await?;
            }
            release
                .send(())
                .map_err(|_| anyhow::anyhow!("stored tail wait was lost before release"))?;
            break receive.await?.context("feed ended after tail release")?;
        };
        let mut event = event;
        let update = loop {
            match event {
                ConversationEvent::State { .. } => event = next(&mut feed).await?,
                ConversationEvent::ActivityContent {
                    frame: ActivityContentFrame::Commit { .. },
                    completed: Some(update),
                } => break *update,
                event => bail!("final commit did not share its completion delivery: {event:?}"),
            }
        };
        let TimelineTailUpdate::Batch {
            timeline_epoch,
            from_seq,
            through_seq,
            items,
            ..
        } = update
        else {
            bail!("registered tail changed epoch");
        };
        ensure!(timeline_epoch == buffered.epoch);
        ensure!(from_seq == buffered.from && through_seq == buffered.through);
        ensure!(
            items
                .iter()
                .map(|item| (item.header.id.clone(), item.header.append_seq))
                .collect::<Vec<_>>()
                == buffered.items
        );
        ensure!(feed.activity().delivered_completion == target);
        feed.close().await?;
        drop(feed);
        drop(reader);
        Ok(())
    }
    .await;
    stage.release();
    env.finish(result).await
}

#[tokio::test]
async fn final_batch_and_activity_commit_share_a_real_delivery() -> Result<()> {
    final_commit_with_buffered_batch(false).await
}

#[tokio::test]
async fn cancelled_receive_keeps_the_real_batch_for_its_activity_commit() -> Result<()> {
    final_commit_with_buffered_batch(true).await
}

async fn held_environment(task: &str, stage: &ReplyStage) -> Result<support::Environment> {
    support::Environment::new(
        vec![support::prompt_step(
            task,
            0,
            support::held_reply(stage, task),
        )],
        vec![],
    )
    .await
}

async fn initial_activity_commit(feed: &mut ConversationFeed) -> Result<()> {
    loop {
        match next(feed).await? {
            ConversationEvent::State { .. } => {}
            ConversationEvent::ActivityContent {
                frame: ActivityContentFrame::Commit { .. },
                completed: None,
            } => return Ok(()),
            ConversationEvent::ActivityContent {
                completed: None, ..
            } => {}
            other => bail!("unexpected initial activity: {other:?}"),
        }
    }
}

async fn drain_ready(feed: &mut ConversationFeed) -> Result<()> {
    loop {
        let mut receive = Box::pin(feed.recv());
        match futures::poll!(receive.as_mut()) {
            std::task::Poll::Pending => return Ok(()),
            std::task::Poll::Ready(Ok(Some(ConversationEvent::State { .. }))) => {}
            other => bail!("unexpected fact while draining state: {other:?}"),
        }
    }
}

#[tokio::test]
async fn hot_state_and_large_activity_give_each_ready_source_four_arbitrations() -> Result<()> {
    let stage = ReplyStage::new();
    let task = "feed-finite-fairness";
    let env = held_environment(task, &stage).await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Worktree, task).await?;
        let id = &thread.thread.id;
        support::reached(&stage).await?;
        env.runtime.synchronize_thread_observation(id).await?;
        let mut feed = env.runtime.open_conversation_feed(id, None).await?;
        let ConversationEvent::ContentBaseline { baseline } = next(&mut feed).await? else {
            bail!("missing real baseline");
        };
        let cursor = baseline.completed_cursor;
        feed.close().await?;
        stage.release();
        support::completed_prompt(&env.runtime, id, task).await?;
        env.runtime.synchronize_thread_observation(id).await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(id, Some(cursor.clone()))
            .await?;
        // The actual same-epoch bootstrap must publish activity before granting
        // catch-up permission, without advancing the delivered completion cursor.
        initial_activity_commit(&mut feed).await?;
        ensure!(feed.activity().delivered_completion == cursor.append_seq);
        let target = feed.reader.head_seq();
        ensure!(feed.activity().permitted_completion == target);
        let ready = feed.sources.get_mut().1.get_mut().0.slot.take().unwrap();
        let (content, result) = match ready {
            ContentSlot::Waiting(wait) => wait.await,
            ContentSlot::Ready(ready) => *ready,
        };
        let batch = result?.context("real completion batch")?;
        ensure!(target > feed.activity().delivered_completion);
        install_content_wait(
            &mut feed,
            Box::pin(std::future::ready((content, Ok(Some(batch))))),
        );

        // A real encoder supplies more frames than this entire measured prefix
        // can drain. Its pending watch cannot add hidden arbitrations in the test.
        let mut snapshot = ActivitySnapshot {
            completed_through: target,
            ..Default::default()
        };
        snapshot.text.insert(
            pl_protocol::ActivityTextRegion::Response {
                item_id: "large-ready-activity".into(),
            },
            pl_core::model::ContentBlock::from_text(
                &"x".repeat(pl_protocol::ACTIVITY_TEXT_FRAME_BYTES * 32),
            ),
        );
        let activity = feed.activity_mut();
        activity.through = snapshot.completed_through;
        activity.frames = activity
            .delivery
            .encode(Arc::new(snapshot), ACTIVITY_CONTENT_BUDGET_BYTES)?
            .into();
        ensure!(activity.frames.len() > 24);

        let mut parked = Vec::new();
        let mut reheat_state = true;
        let mut last_state = 0;
        let mut last_activity = 0;
        let mut completion_at = None;
        for arbitration in 1..=24 {
            if reheat_state {
                // Real subscription handles/results, with only readiness controlled.
                // Retain the replaced original wait and join it after feed cancellation.
                let mut state = env
                    .runtime
                    .subscribe_thread(ThreadSubscriptionRequest {
                        thread_id: id.clone(),
                    })
                    .await?;
                let update = state.recv().await?.context("real state snapshot")?;
                parked.push(
                    feed.sources
                        .get_mut()
                        .0
                        .wait
                        .replace(Box::pin(std::future::ready((state, Ok(Some(update))))))
                        .unwrap(),
                );
            }
            let event = {
                let mut receive = Box::pin(feed.recv());
                match futures::poll!(receive.as_mut()) {
                    std::task::Poll::Ready(event) => event?.context("ready feed ended")?,
                    std::task::Poll::Pending => bail!("all-ready competition became pending"),
                }
            };
            reheat_state = matches!(event, ConversationEvent::State { .. });
            match event {
                ConversationEvent::State { .. } => last_state = arbitration,
                ConversationEvent::ActivityContent {
                    completed: None, ..
                } => last_activity = arbitration,
                ConversationEvent::ContentUpdate {
                    update: TimelineTailUpdate::Batch { through_seq, .. },
                } => {
                    ensure!(through_seq == target);
                    ensure!(completion_at.replace(arbitration).is_none());
                    ensure!(arbitration <= 4, "ready completion starved");
                }
                other => bail!("unexpected fairness delivery: {other:?}"),
            }
            ensure!(arbitration - last_state < 4, "ready state starved");
            ensure!(arbitration - last_activity < 4, "ready activity starved");
        }
        ensure!(completion_at.is_some(), "ready completion never delivered");
        ensure!(feed.activity().delivered_completion == target);
        ensure!(!feed.activity().frames.is_empty());
        feed.close().await?;
        for wait in parked {
            let (state, _) = wait.await;
            drop(state);
        }
        Ok(())
    }
    .await;
    stage.release();
    env.finish(result).await
}

#[tokio::test]
async fn cancelled_receive_retains_activity_notification_and_close_joins_all_waits() -> Result<()> {
    let stage = ReplyStage::new();
    let task = "feed-activity-wait";
    let env = held_environment(task, &stage).await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Worktree, task).await?;
        let id = &thread.thread.id;
        support::reached(&stage).await?;
        env.runtime.synchronize_thread_observation(id).await?;
        let mut feed = env.runtime.open_conversation_feed(id, None).await?;
        ensure!(matches!(
            next(&mut feed).await?,
            ConversationEvent::ContentBaseline { .. }
        ));
        initial_activity_commit(&mut feed).await?;
        drain_ready(&mut feed).await?;

        let wait = feed.activity_mut().wait.take().context("real watch wait")?;
        let (entered_tx, mut entered_rx) = oneshot::channel();
        let (notified_tx, mut notified_rx) = oneshot::channel();
        feed.activity_mut().wait = Some(Box::pin(async move {
            let _ = entered_tx.send(());
            let result = wait.await;
            let _ = notified_tx.send(());
            result
        }));
        drain_ready(&mut feed).await?;
        entered_rx
            .try_recv()
            .context("activity wait was not polled")?;
        ensure!(
            matches!(
                notified_rx.try_recv(),
                Err(oneshot::error::TryRecvError::Empty)
            ),
            "cancelled recv dropped or completed its original watch wait"
        );
        // drain_ready cancelled a genuinely Pending recv after the owned changed()
        // registered. A subsequent real publication must survive that cancellation.
        stage.release();
        support::completed_prompt(&env.runtime, id, task).await?;
        env.runtime.synchronize_thread_observation(id).await?;
        let target = feed.reader.head_seq();
        let mut committed = false;
        for _ in 0..16 {
            let event = next(&mut feed).await?;
            if matches!(
                event,
                ConversationEvent::ActivityContent {
                    frame: ActivityContentFrame::Commit { .. },
                    ..
                }
            ) && feed.activity().through == target
            {
                committed = true;
                break;
            }
        }
        ensure!(
            committed,
            "cancelled recv lost the real activity publication"
        );
        notified_rx
            .try_recv()
            .context("original watch wait did not receive the publication")?;
        ensure!(feed.activity().delivered_completion == target);

        let state = &mut feed.sources.get_mut().0.wait;
        let wait = state.take().context("captured state wait")?;
        let (state_tx, mut state_rx) = oneshot::channel();
        *state = Some(Box::pin(async move {
            let result = wait.await;
            let _ = state_tx.send(());
            result
        }));
        let wait = take_content_wait(&mut feed);
        let (content_tx, mut content_rx) = oneshot::channel();
        install_content_wait(
            &mut feed,
            Box::pin(async move {
                let result = wait.await;
                let _ = content_tx.send(());
                result
            }),
        );
        let wait = feed
            .activity_mut()
            .wait
            .take()
            .context("captured activity wait")?;
        let (closing_tx, mut closing_rx) = oneshot::channel();
        let (release_tx, release_rx) = oneshot::channel();
        let (activity_tx, mut activity_rx) = oneshot::channel();
        feed.activity_mut().wait = Some(Box::pin(async move {
            let result = wait.await;
            let _ = closing_tx.send(());
            let _ = release_rx.await;
            let _ = activity_tx.send(());
            result
        }));
        let reader = feed.reader.clone();
        {
            let mut closing = Box::pin(feed.close());
            ensure!(futures::poll!(closing.as_mut()).is_pending());
        }
        closing_rx
            .try_recv()
            .context("close did not await the real activity wait")?;
        state_rx
            .try_recv()
            .context("close dropped its state wait")?;
        content_rx
            .try_recv()
            .context("close dropped its completion wait")?;
        ensure!(matches!(
            activity_rx.try_recv(),
            Err(oneshot::error::TryRecvError::Empty)
        ));
        ensure!(
            feed.recv().await.is_err(),
            "cancel must precede publication"
        );
        release_tx
            .send(())
            .map_err(|_| anyhow::anyhow!("close dropped its activity join"))?;
        feed.close().await?;
        activity_rx
            .try_recv()
            .context("activity wait was not joined")?;
        feed.close().await?;
        ensure!(
            reader
                .page(&TimelinePageQuery {
                    before: None,
                    limit: Some(100)
                })
                .await?
                .items
                .last()
                .map(|item| item.header.append_seq)
                == Some(target)
        );
        Ok(())
    }
    .await;
    stage.release();
    env.finish(result).await
}

#[tokio::test]
async fn snapshot_after_completion_source_ends_cannot_publish_its_blocked_commit() -> Result<()> {
    let stage = ReplyStage::new();
    let task = "feed-ended-completion";
    let env = held_environment(task, &stage).await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Worktree, task).await?;
        let id = &thread.thread.id;
        support::reached(&stage).await?;
        env.runtime.synchronize_thread_observation(id).await?;
        let mut feed = env.runtime.open_conversation_feed(id, None).await?;
        ensure!(matches!(
            next(&mut feed).await?,
            ConversationEvent::ContentBaseline { .. }
        ));
        initial_activity_commit(&mut feed).await?;
        drain_ready(&mut feed).await?;
        let original_activity = feed
            .activity_mut()
            .wait
            .take()
            .context("original activity wait")?;
        let original_content = take_content_wait(&mut feed);
        let (sender, receiver) = watch::channel(Arc::new(ActivitySnapshot::default()));
        feed.activity_mut().wait = Some(wait_activity(receiver, feed.cancel.clone()));
        let tail = feed.reader.open_tail().await?;
        // Control the normal-end result, not close()'s distinct cancellation error.
        // The feed must consume this result and close the original real handle.
        install_content_wait(&mut feed, Box::pin(std::future::ready((tail, Ok(None)))));
        drain_ready(&mut feed).await?;
        ensure!(feed.sources.get_ref().1.get_ref().0.slot.is_none());
        let through = feed.activity().delivered_completion + 1;
        sender.send(Arc::new(ActivitySnapshot {
            completed_through: through,
            ..Default::default()
        }))?;
        loop {
            match next(&mut feed).await? {
                ConversationEvent::State { .. } => {}
                ConversationEvent::ActivityContent {
                    frame: ActivityContentFrame::Begin { .. },
                    completed: None,
                } => break,
                other => bail!("unexpected fact after the new snapshot: {other:?}"),
            }
        }
        let error = feed
            .recv()
            .await
            .expect_err("blocked Commit escaped or waited forever");
        ensure!(
            error
                .to_string()
                .contains("activity commit lost its completion source")
        );
        ensure!(feed.activity().through == through);
        ensure!(feed.activity().commit_waits());
        feed.close().await?;
        let (source, _) = original_activity.await;
        drop(source);
        let (mut content, _) = original_content.await;
        content.close();
        Ok(())
    }
    .await;
    stage.release();
    env.finish(result).await
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum PublicationCase {
    Early,
    Split,
    ActivityLost,
}

fn streaming_held_reply(stage: &ReplyStage, id: &str) -> pl_provider_fixture::Reply {
    let mut events = pl_provider_fixture::responses_text("released", id, support::MODEL);
    let terminal = events
        .iter()
        .position(|event| event["type"] == "response.output_item.done")
        .expect("fixture has a terminal boundary");
    let after = events.split_off(terminal);
    stage.gated(events, after)
}

fn current_activity(runtime: &StudioRuntime, id: &str) -> Result<Arc<ActivitySnapshot>> {
    let mut receiver = runtime
        .thread_observations
        .live_feed(id)
        .context("real activity publisher")?
        .activity_content();
    Ok(receiver.borrow_and_update().clone())
}

async fn wait_for_activity_text(runtime: &StudioRuntime, id: &str) -> Result<()> {
    let mut receiver = runtime
        .thread_observations
        .live_feed(id)
        .context("real streaming publisher")?
        .activity_content();
    tokio::time::timeout(std::time::Duration::from_secs(20), async {
        loop {
            if receiver
                .borrow_and_update()
                .text
                .values()
                .any(|block| !block.is_empty())
            {
                return Ok(());
            }
            receiver
                .changed()
                .await
                .context("activity ended before its real text")?;
        }
    })
    .await
    .context("real activity text was not published")?
}

fn retained_batch(feed: &ConversationFeed) -> Result<&TimelineTailUpdate> {
    let Some(ContentSlot::Ready(ready)) = &feed.sources.get_ref().1.get_ref().0.slot else {
        bail!("original batch/handle no longer occupies the unique ready slot");
    };
    match &ready.1 {
        Ok(Some(batch @ TimelineTailUpdate::Batch { .. })) => Ok(batch),
        other => bail!("unexpected retained original result: {other:?}"),
    }
}

async fn observe_original_batch(
    feed: &mut ConversationFeed,
    batch: &mut oneshot::Receiver<TimelineTailUpdate>,
) -> Result<TimelineTailUpdate> {
    loop {
        tokio::select! {
            result = &mut *batch => return result.context("real original tail batch"),
            event = feed.recv() => match event? {
                Some(ConversationEvent::State { .. }) => {}
                other => bail!("unlicensed completion escaped before activity publication: {other:?}"),
            },
        }
    }
}

async fn begin_without_completion(feed: &mut ConversationFeed, delivered: u64) -> Result<()> {
    loop {
        match next(feed).await? {
            ConversationEvent::State { .. } => {}
            ConversationEvent::ActivityContent {
                frame: ActivityContentFrame::Begin { .. },
                completed: None,
            } => {
                ensure!(feed.activity().delivered_completion == delivered);
                return Ok(());
            }
            other => bail!("completion escaped before Begin: {other:?}"),
        }
    }
}

async fn joined_commit(
    feed: &mut ConversationFeed,
    from: u64,
    through: u64,
    require_text: bool,
) -> Result<TimelineTailUpdate> {
    let mut text_frames = 0;
    loop {
        match next(feed).await? {
            ConversationEvent::State { .. } => {}
            ConversationEvent::ActivityContent {
                frame: ActivityContentFrame::Text { .. },
                completed: None,
            } => {
                text_frames += 1;
                ensure!(
                    feed.activity().delivered_completion == from,
                    "completion advanced during a non-Commit activity frame"
                );
            }
            ConversationEvent::ActivityContent {
                frame: ActivityContentFrame::Commit { .. },
                completed: Some(batch),
            } => {
                let TimelineTailUpdate::Batch {
                    from_seq,
                    through_seq,
                    ..
                } = &*batch
                else {
                    bail!("completion reset at an established activity transaction");
                };
                ensure!(*from_seq == from && *through_seq == through);
                ensure!(feed.activity().delivered_completion == through);
                ensure!(feed.activity().permitted_completion == through);
                ensure!(
                    !require_text || text_frames > 0,
                    "real exit did not have its Remove frame"
                );
                return Ok(*batch);
            }
            other => bail!("completion was not handed off with its exact Commit: {other:?}"),
        }
    }
}

async fn real_batch_publication(case: PublicationCase) -> Result<()> {
    let first = ReplyStage::new();
    let second = ReplyStage::new();
    let task = "permission-first";
    let next_task = "permission-second";
    let mut steps = vec![support::prompt_step(
        task,
        0,
        streaming_held_reply(&first, task),
    )];
    if case == PublicationCase::Split {
        steps.push(support::prompt_step(
            next_task,
            1,
            streaming_held_reply(&second, next_task),
        ));
    }
    let env = support::Environment::new(steps, vec![]).await?;
    let result = async {
        let thread = env.start(ThreadWorkspaceMode::Worktree, task).await?;
        let id = &thread.thread.id;
        support::reached(&first).await?;
        wait_for_activity_text(&env.runtime, id).await?;
        env.runtime.synchronize_thread_observation(id).await?;
        let held = current_activity(&env.runtime, id)?;
        let mut feed = env.runtime.open_conversation_feed(id, None).await?;
        let ConversationEvent::ContentBaseline { baseline } = next(&mut feed).await? else {
            bail!("missing real first baseline");
        };
        let accepted = baseline.completed_cursor.append_seq;
        initial_activity_commit(&mut feed).await?;

        // This watch delays only the activity source's publication. Every value
        // sent below is an unmodified snapshot captured from the real publisher.
        let original_activity = feed
            .activity_mut()
            .wait
            .take()
            .context("real owned activity wait")?;
        let (publisher, receiver) = watch::channel(held);
        feed.activity_mut().wait = Some(wait_activity(receiver, feed.cancel.clone()));
        let wait = take_content_wait(&mut feed);
        let cancel = feed.cancel.clone();
        let (read_tx, read_rx) = oneshot::channel();
        let (batch_tx, mut batch_rx) = oneshot::channel();
        install_content_wait(
            &mut feed,
            Box::pin(async move {
                // Do not resume the original tail wait until this gate opens.
                // Cancellation still awaits it, waking its token and recovering its handle.
                tokio::select! { biased; () = cancel.cancelled() => {}, _ = read_rx => {} }
                let result = wait.await;
                if let Ok(Some(batch)) = &result.1 {
                    let _ = batch_tx.send(batch.clone());
                }
                result
            }),
        );
        first.release();
        support::completed_prompt(&env.runtime, id, task).await?;
        env.runtime.synchronize_thread_observation(id).await?;
        let exit_one = current_activity(&env.runtime, id)?;
        let through_one = exit_one.completed_through;
        ensure!(through_one > accepted && exit_one.text.is_empty());

        let exit_two = if case == PublicationCase::Split {
            publisher.send(exit_one.clone())?;
            // Begin is now on the wire, but the original tail read is still held.
            begin_without_completion(&mut feed, accepted).await?;
            ensure!(matches!(
                feed.activity().frames.front(),
                Some(ActivityContentFrame::Text { .. })
            ));
            env.runtime
                .submit_prompt(super::super::StudioSubmitPromptRequest {
                    thread_id: id.clone(),
                    input: pl_protocol::studio::StudioPromptInput {
                        input_id: format!("input-{next_task}"),
                        text: next_task.into(),
                        attachment_draft_ids: vec![],
                    },
                    options: Default::default(),
                })
                .await?;
            support::reached(&second).await?;
            wait_for_activity_text(&env.runtime, id).await?;
            second.release();
            support::completed_prompt(&env.runtime, id, next_task).await?;
            env.runtime.synchronize_thread_observation(id).await?;
            let snapshot = current_activity(&env.runtime, id)?;
            ensure!(snapshot.completed_through > through_one && snapshot.text.is_empty());
            Some(snapshot)
        } else {
            None
        };
        read_tx
            .send(())
            .map_err(|_| anyhow::anyhow!("original read gate disappeared"))?;

        if case != PublicationCase::Split {
            // Tail is genuinely ready while the controlled activity publisher has
            // not published its exit at all. No completion position may advance.
            let original = observe_original_batch(&mut feed, &mut batch_rx).await?;
            drain_ready(&mut feed).await?;
            ensure!(feed.activity().delivered_completion == accepted);
            ensure!(feed.activity().permitted_completion == accepted);
            ensure!(retained_batch(&feed)? == &original);
            if case == PublicationCase::ActivityLost {
                drop(publisher);
                let error = loop {
                    match feed.recv().await {
                        Ok(Some(ConversationEvent::State { .. })) => {}
                        Err(error) => break error,
                        other => bail!("lost activity hung or released unlicensed data: {other:?}"),
                    }
                };
                ensure!(
                    error
                        .to_string()
                        .contains("completion batch lost its activity source")
                );
                ensure!(feed.activity().delivered_completion == accepted);
                ensure!(retained_batch(&feed)? == &original);
                feed.close().await?;
                ensure!(feed.sources.get_ref().1.get_ref().0.slot.is_none());
                feed.close().await?;
                let (receiver, _) = original_activity.await;
                drop(receiver);
                return Ok(());
            }
            publisher.send(exit_one)?;
            begin_without_completion(&mut feed, accepted).await?;
            let joined = joined_commit(&mut feed, accepted, through_one, true).await?;
            ensure!(
                joined == original,
                "original single batch changed during its handoff"
            );
        } else {
            let prefix = joined_commit(&mut feed, accepted, through_one, true).await?;
            let original = batch_rx
                .try_recv()
                .context("original cross-snapshot tail batch")?;
            let remaining = retained_batch(&feed)?.clone();
            let TimelineTailUpdate::Batch {
                from_seq,
                through_seq,
                items,
                ..
            } = &remaining
            else {
                bail!("missing retained suffix");
            };
            let exit_two = exit_two.context("second real exit")?;
            ensure!(*from_seq == through_one && *through_seq == exit_two.completed_through);
            ensure!(!items.is_empty());
            // The only original handle is in Ready, not in another tail wait.
            // A truly Pending receive is cancelled without losing that suffix.
            drain_ready(&mut feed).await?;
            ensure!(retained_batch(&feed)? == &remaining);
            ensure!(feed.activity().delivered_completion == through_one);
            publisher.send(exit_two.clone())?;
            begin_without_completion(&mut feed, through_one).await?;
            let suffix =
                joined_commit(&mut feed, through_one, exit_two.completed_through, false).await?;
            ensure!(suffix == remaining);
            let TimelineTailUpdate::Batch {
                items: mut delivered,
                subscription_id,
                timeline_epoch,
                from_seq,
                ..
            } = prefix
            else {
                bail!("missing prefix");
            };
            let TimelineTailUpdate::Batch {
                items, through_seq, ..
            } = suffix
            else {
                bail!("missing suffix");
            };
            delivered.extend(items);
            ensure!(
                original
                    == TimelineTailUpdate::Batch {
                        subscription_id,
                        timeline_epoch,
                        from_seq,
                        through_seq,
                        items: delivered,
                    },
                "partition changed original identities, payloads, order or ranges"
            );
            ensure!(matches!(
                feed.sources.get_ref().1.get_ref().0.slot,
                Some(ContentSlot::Waiting(_))
            ));
        }
        let reader = feed.reader.clone();
        feed.close().await?;
        ensure!(
            publisher.is_closed(),
            "close retained the activity receiver"
        );
        let (receiver, _) = original_activity.await;
        drop(receiver);
        ensure!(
            !reader
                .page(&TimelinePageQuery {
                    before: None,
                    limit: Some(100)
                })
                .await?
                .items
                .is_empty()
        );
        Ok(())
    }
    .await;
    first.release();
    second.release();
    env.finish(result).await
}

#[tokio::test]
async fn early_real_batch_waits_for_publication_and_all_exit_frames() -> Result<()> {
    real_batch_publication(PublicationCase::Early).await
}

#[tokio::test]
async fn one_real_batch_crosses_two_real_exits_without_read_ahead_or_cancellation_loss()
-> Result<()> {
    real_batch_publication(PublicationCase::Split).await
}

#[tokio::test]
async fn unlicensed_real_batch_fails_when_its_activity_publisher_ends() -> Result<()> {
    real_batch_publication(PublicationCase::ActivityLost).await
}
