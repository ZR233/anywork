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

/// Wrap only the actual stored wait. Its real tail result remains in that wait
/// when a caller drops recv(), and closes through the feed's existing token.
fn gate_next_batch(
    feed: &mut ConversationFeed,
) -> (oneshot::Receiver<BufferedBatch>, oneshot::Sender<()>) {
    let wait = feed.content_wait.take().expect("registered real tail wait");
    let cancel = feed.cancel.clone();
    let (entered_tx, entered_rx) = oneshot::channel();
    let (release_tx, release_rx) = oneshot::channel();
    feed.content_wait = Some(Box::pin(async move {
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
    }));
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
                feed.activity_frames.front(),
                Some(ActivityContentFrame::Commit { .. })
            ) && feed.activity_through == target
                && feed.delivered_completion == accepted;
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
        ensure!(feed.delivered_completion == target);
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
