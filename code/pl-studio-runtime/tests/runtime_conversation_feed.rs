#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};
use pl_protocol::{
    ActivityContentFrame, ThreadWorkspaceMode, TimelineCompletionCursor, TimelineTailUpdate,
};
use pl_studio_runtime::{ConversationEvent, ConversationFeed};
use std::{collections::HashSet, time::Duration};
use support::{Environment, completed_prompt, prompt_step, text_reply};

async fn next(feed: &mut ConversationFeed) -> Result<ConversationEvent> {
    let event = tokio::time::timeout(Duration::from_secs(10), feed.recv())
        .await
        .context("conversation feed did not deliver its pending facts")??;
    event.context("conversation feed ended before its pending facts")
}

#[tokio::test]
async fn nonempty_feed_resumes_contiguous_completions_after_latest_activity() -> Result<()> {
    let env = Environment::new(
        vec![prompt_step(
            "feed-resume",
            0,
            text_reply("a real completed response", "feed-resume"),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Worktree, "feed-resume")
            .await?;
        completed_prompt(&env.runtime, &thread.thread.id, "feed-resume").await?;
        // Keep the registered Session alive across transport retirement, as an
        // independent presentation query scope does in production.
        let reader = env.runtime.timeline_reader(&thread.thread.id).await?;
        let mut initial = env
            .runtime
            .open_conversation_feed(&thread.thread.id, None)
            .await?;
        let ConversationEvent::ContentBaseline { baseline } = next(&mut initial).await? else {
            anyhow::bail!("initial feed did not deliver a baseline");
        };
        ensure!(
            !baseline.items.is_empty(),
            "fixture history must be nonempty"
        );
        ensure!(baseline.completed_cursor.append_seq > 0);
        ensure!(baseline.timeline_epoch == reader.epoch());
        let target = baseline.completed_cursor.append_seq;
        initial.close().await?;
        drop(initial);

        let mut resumed = env
            .runtime
            .open_conversation_feed(
                &thread.thread.id,
                Some(TimelineCompletionCursor {
                    timeline_epoch: baseline.timeline_epoch.clone(),
                    append_seq: 0,
                }),
            )
            .await?;
        let mut through = 0;
        let mut activity_committed = false;
        let mut identities = HashSet::new();
        while through < target {
            let update = match next(&mut resumed).await? {
                ConversationEvent::State { .. } => continue,
                ConversationEvent::ContentBaseline { .. } => {
                    anyhow::bail!("same-epoch resume replaced the presentation baseline")
                }
                ConversationEvent::ActivityContent { frame, completed } => {
                    if matches!(frame, ActivityContentFrame::Commit { .. }) {
                        activity_committed = true;
                    } else {
                        ensure!(completed.is_none(), "non-commit carried completions");
                    }
                    let Some(completed) = completed else {
                        continue;
                    };
                    *completed
                }
                ConversationEvent::ContentUpdate { update } => update,
            };
            ensure!(
                activity_committed,
                "resume must deliver the current activity before history catch-up"
            );
            let TimelineTailUpdate::Batch {
                timeline_epoch,
                from_seq,
                through_seq,
                items,
                ..
            } = update
            else {
                anyhow::bail!("same-epoch resume unexpectedly reset its completion window");
            };
            ensure!(timeline_epoch == baseline.timeline_epoch);
            ensure!(from_seq == through && !items.is_empty());
            for item in items {
                through += 1;
                ensure!(item.header.append_seq == through);
                ensure!(item.header.thread_id == thread.thread.id);
                ensure!(identities.insert(item.header.id), "completion was repeated");
            }
            ensure!(through == through_seq);
        }
        resumed.close().await?;
        drop(resumed);
        drop(reader);
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn saved_nonempty_feed_resets_only_the_completion_epoch_after_restart() -> Result<()> {
    let mut env = Environment::new(
        vec![prompt_step(
            "feed-reset",
            0,
            text_reply("a persisted completed response", "feed-reset"),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Worktree, "feed-reset")
            .await?;
        completed_prompt(&env.runtime, &thread.thread.id, "feed-reset").await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(&thread.thread.id, None)
            .await?;
        let ConversationEvent::ContentBaseline { baseline: old } = next(&mut feed).await? else {
            anyhow::bail!("initial feed did not deliver a baseline");
        };
        ensure!(!old.items.is_empty());
        feed.close().await?;
        drop(feed);
        // Establish the observation watermark explicitly; a terminal Turn
        // notification alone is not proof that its projection has completed.
        // Shutdown must still join any reliable effects created by closing.
        env.runtime
            .synchronize_thread_observation(&thread.thread.id)
            .await
            .with_context(|| {
                format!(
                    "projection did not settle before restart: {:?}",
                    env.runtime.persistence_queue_snapshot()
                )
            })?;
        env.restart().await.with_context(|| {
            format!(
                "runtime restart failed after projection synchronization: {:?}",
                env.runtime.persistence_queue_snapshot()
            )
        })?;
        let mut restored = env
            .runtime
            .open_conversation_feed(&thread.thread.id, Some(old.completed_cursor.clone()))
            .await?;
        let ConversationEvent::ContentUpdate {
            update: TimelineTailUpdate::Reset { baseline },
        } = next(&mut restored).await?
        else {
            anyhow::bail!("a new Session epoch did not reset the completion window");
        };
        ensure!(baseline.timeline_epoch != old.timeline_epoch);
        ensure!(baseline.completed_cursor.append_seq >= old.completed_cursor.append_seq);
        for original in old.items {
            ensure!(
                baseline.items.iter().any(|item| {
                    item.header.id == original.header.id
                        && item.header.append_seq == original.header.append_seq
                }),
                "restart lost an already published completed fact"
            );
        }
        restored.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}
