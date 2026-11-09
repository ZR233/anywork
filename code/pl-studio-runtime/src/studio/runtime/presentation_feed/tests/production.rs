use super::*;
use crate::{
    runtime_test_support::Environment,
    studio::runtime::conversation_feed::tests::completed_runs::{Harness, finish, start},
};
use anyhow::Context;
use futures::poll;
use pl_protocol::{ChatActiveStatus, ChatAtomLifecycle, ChatScope, DisplayMemberWindow};
use std::task::Poll;

pub(super) async fn timeline(feed: &mut TimelineFeed) -> Result<TimelineBatch> {
    tokio::time::timeout(
        crate::runtime_test_support::integration_test_deadline()?,
        async {
            loop {
                match feed.receive().await? {
                    ConversationEvent::Timeline { batch } => return Ok(*batch),
                    ConversationEvent::State { .. } => {}
                    event => anyhow::bail!("presentation feed emitted atomic event: {event:?}"),
                }
            }
        },
    )
    .await?
}

async fn atomic(feed: &mut ConversationFeed) -> Result<pl_protocol::ChatBatch> {
    tokio::time::timeout(
        crate::runtime_test_support::integration_test_deadline()?,
        async {
            loop {
                match feed.recv().await?.context("completion feed ended")? {
                    ConversationEvent::Chat { batch } => return Ok(*batch),
                    ConversationEvent::State { .. } | ConversationEvent::Activity { .. } => {}
                    ConversationEvent::Timeline { .. } => {
                        anyhow::bail!("completion feed emitted Timeline")
                    }
                }
            }
        },
    )
    .await?
}

pub(super) fn work_reference(live: &LiveDisplayWindow) -> Result<DisplayBlockRef> {
    live.blocks
        .iter()
        .find_map(|block| match &block.body {
            DisplayBlockBody::Work { members, .. } => Some(members.clone()),
            _ => None,
        })
        .context("live Work block")
}

async fn persist(
    h: &Harness,
    prepared: &crate::studio::thread_projection::PreparedEffect,
) -> Result<()> {
    h.save(prepared).await.with_context(|| {
        format!(
            "saving real fixture effect {}, completions={}, published={}",
            prepared.sequence,
            prepared.completions.len(),
            prepared
                .display
                .as_ref()
                .map_or(0, |delta| delta.published_through),
        )
    })?;
    h.projection
        .presentation()
        .lock()
        .unwrap()
        .confirm(prepared.sequence);
    Ok(())
}

#[tokio::test]
async fn reliable_text_start_advances_p_without_h_and_member_completion_advances_h_without_p()
-> Result<()> {
    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        h.effect(vec![start("reasoning", true)], vec![]).await?;
        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let mut completed = env
            .runtime
            .open_conversation_feed(&h.thread.id, ChatScope::Main, demand(1))
            .await?;
        assert_eq!(atomic(&mut completed).await?.through_seq, 0);
        let initial = timeline(&mut feed).await?;
        assert_eq!(initial.placement, ChatPlacement::Set);
        assert!(initial.blocks.is_empty());
        let first_live = initial.live.context("initial live")?;
        assert_eq!(first_live.history_through, 0);
        let reference = work_reference(&first_live)?;
        let reader = feed.reader().clone();
        let mut members = reader
            .open_display_members(reference.clone(), DisplayMemberWindow::Latest, demand(1))
            .await?;
        let active = members.next().await?.context("active member page")?;
        assert!(!active.sealed);
        assert_eq!(active.entries.len(), 1);
        assert!(matches!(
            active.entries[0].atom.lifecycle,
            ChatAtomLifecycle::Active {
                status: ChatActiveStatus::Running,
                ..
            }
        ));

        h.effect(vec![], vec![finish("reasoning", true, "real reasoning")?])
            .await?;
        assert_eq!(h.session.head_seq(), 1);
        let completion = atomic(&mut completed).await?;
        assert_eq!(completion.from_seq, Some(0));
        assert_eq!(completion.through_seq, 1);
        assert_eq!(
            completion.entries.len(),
            1,
            "atomic consumer must not wait for display boundary"
        );
        let updated = timeline(&mut feed).await?;
        assert_eq!(updated.from_pos, Some(0));
        assert_eq!(updated.through_pos, 0);
        assert!(
            updated.blocks.is_empty(),
            "terminal member must remain inside live Work"
        );
        let updated_live = updated.live.context("updated live")?;
        assert_eq!(work_reference(&updated_live)?, reference);
        let DisplayBlockBody::Work { summary, .. } = &updated_live.blocks[0].body else {
            anyhow::bail!("expected Work");
        };
        assert_eq!(
            (summary.total, summary.terminal, summary.running),
            (1, 1, 0)
        );
        let terminal = members.next().await?.context("terminal member page")?;
        assert_eq!(terminal.entries[0].member_key, active.entries[0].member_key);
        assert!(terminal.entries[0].completion_id.is_some());
        assert!(terminal.revision > active.revision);
        assert!(
            !terminal.sealed,
            "member completion alone is not a display boundary"
        );

        let before_h = h.session.head_seq();
        h.effect(vec![start("text", false)], vec![]).await?;
        assert_eq!(h.session.head_seq(), before_h);
        let handoff = timeline(&mut feed).await?;
        assert_eq!(handoff.from_pos, Some(0));
        assert_eq!(handoff.through_pos, 1);
        assert_eq!(handoff.blocks.len(), 1);
        assert_eq!(handoff.blocks[0].id, reference.block_id);
        let live = handoff.live.context("handoff live")?;
        assert!(
            live.blocks
                .iter()
                .all(|block| block.id != reference.block_id)
        );
        assert_eq!(
            live.blocks.len(),
            1,
            "new streaming text is already live at the same cut"
        );
        let sealed = members
            .next()
            .await?
            .context("same member ref after handoff")?;
        assert_eq!(sealed.block, reference);
        assert!(sealed.sealed);
        assert!(members.next().await?.is_none());
        // The completed feed reflects activity at H=1, never a synthetic completion for P=1.
        loop {
            match completed.recv().await?.context("completion feed ended")? {
                ConversationEvent::Activity { snapshot }
                    if snapshot.completed_through == before_h =>
                {
                    break;
                }
                ConversationEvent::State { .. } | ConversationEvent::Activity { .. } => {}
                event => anyhow::bail!("text start manufactured atomic completion: {event:?}"),
            }
        }

        members.close().await?;
        feed.close().await?;
        reader.read_business_refs().await?;
        reader.close().await?;
        completed.reader().close().await?;
        completed.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn slow_feed_replays_frozen_sqlite_prefix_and_cold_members_keep_the_same_reference()
-> Result<()> {
    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        assert_eq!(timeline(&mut feed).await?.through_pos, 0);
        let reader = feed.reader().clone();
        let mut reference = None;
        for i in 0..2 {
            let r = format!("reasoning-{i}");
            let t = format!("text-{i}");
            let prepared = h.effect(vec![start(&r, true)], vec![]).await?;
            persist(&h, &prepared).await?;
            let prepared = h
                .effect(vec![], vec![finish(&r, true, "saved reasoning")?])
                .await?;
            persist(&h, &prepared).await?;
            if i == 0 {
                let cut = reader.capture_display(None, 2, None, 0).await?;
                let tokens = reader.presentation_tokens().await?;
                reference = Some(work_reference(&reader.cut_live(
                    &cut,
                    demand(2),
                    &tokens,
                )?)?);
            }
            let prepared = h.effect(vec![start(&t, false)], vec![]).await?;
            persist(&h, &prepared).await?;
            let prepared = h
                .effect(vec![], vec![finish(&t, false, "saved text")?])
                .await?;
            persist(&h, &prepared).await?;
        }
        let reference = reference.context("first Work reference")?;
        assert_eq!(h.session.head_seq(), 4);
        let mut delivered = Vec::new();
        for pos in 1..=4 {
            let batch = timeline(&mut feed).await?;
            assert_eq!(batch.from_pos, Some(pos - 1));
            assert_eq!(batch.through_pos, pos);
            assert_eq!(batch.blocks.len(), 1);
            assert_eq!(batch.live.is_some(), pos == 4);
            delivered.extend(batch.blocks);
        }
        assert_eq!(delivered[0].id, reference.block_id);
        let mut hot_members = reader
            .open_display_members(reference.clone(), DisplayMemberWindow::Latest, demand(1))
            .await?;
        let hot = hot_members
            .next()
            .await?
            .context("saved historical members")?;
        assert!(hot.sealed);
        assert!(hot_members.next().await?.is_none());

        // A parked event receiver has no query/credit ownership. Query a sealed window while it waits.
        let cancel = feed.cancellation_token();
        {
            let receiving = feed.receive();
            tokio::pin!(receiving);
            assert!(matches!(poll!(&mut receiving), Poll::Pending));
            let mut independent = reader
                .open_display_members(reference.clone(), DisplayMemberWindow::Latest, demand(1))
                .await?;
            assert_eq!(
                independent
                    .next()
                    .await?
                    .context("independent query")?
                    .entries,
                hot.entries
            );
            independent.close().await?;
            cancel.cancel();
            assert!(receiving.await.is_err());
        }
        feed.close().await?;
        reader.read_business_refs().await?;
        reader.close().await?;
        hot_members.close().await?;
        env.runtime
            .thread_observations
            .observation_slot(&h.thread.id)
            .retire(&h.source);
        let mut cold_feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let cold_set = timeline(&mut cold_feed).await?;
        assert_eq!(cold_set.through_pos, 4);
        assert_eq!(cold_set.blocks[0], delivered[3]);
        assert!(
            !cold_set
                .live
                .as_ref()
                .context("cold live")?
                .execution_present
        );
        let mut before = cold_set.before.context("older frozen heads")?;
        for expected in delivered[..3].iter().rev() {
            let older = cold_feed
                .reader()
                .load_timeline_older(&before, demand(1))
                .await?;
            assert_eq!(older.placement, ChatPlacement::Prepend);
            assert!(older.live.is_none());
            assert_eq!(&older.blocks[0], expected);
            if expected.history_pos > 1 {
                before = older.before.context("continuation")?;
            } else {
                assert!(older.before.is_none());
            }
        }
        let mut cold_members = cold_feed
            .reader()
            .open_display_members(reference, DisplayMemberWindow::Latest, demand(1))
            .await?;
        let cold = cold_members.next().await?.context("cold members")?;
        assert_eq!(cold, hot);
        assert!(cold_members.next().await?.is_none());
        cold_members.close().await?;
        cold_feed.reader().close().await?;
        cold_feed.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}
