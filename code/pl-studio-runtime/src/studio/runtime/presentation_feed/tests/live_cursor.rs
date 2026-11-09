use super::production::{timeline, work_reference};
use super::*;
use crate::{
    runtime_test_support::Environment,
    studio::runtime::conversation_feed::tests::completed_runs::{Harness, finish, start},
};
use anyhow::Context;
use pl_protocol::DisplayMemberWindow;

#[tokio::test]
async fn live_cursor_survives_member_status_change_and_only_structure_makes_it_stale() -> Result<()>
{
    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        h.effect(vec![start("first", true), start("second", true)], vec![])
            .await?;
        h.effect(vec![start("body", false)], vec![]).await?;
        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let initial = timeline(&mut feed).await?;
        assert_eq!(initial.through_pos, 0);
        let live = initial
            .live
            .context("initial closing Work and active Text")?;
        assert_eq!(live.blocks.len(), 1);
        let before = live.older.context("earlier closing Work")?;
        let older = feed.reader().load_live_older(&before, demand(1)).await?;
        let reference = work_reference(&older)?;
        let mut members = feed
            .reader()
            .open_display_members(
                reference,
                DisplayMemberWindow::Before { member_order: 2 },
                demand(1),
            )
            .await?;
        let active = members.next().await?.context("first member")?;
        assert_eq!(active.entries[0].member_order, 1);
        h.effect(vec![], vec![finish("first", true, "first terminal")?])
            .await?;
        assert_eq!(h.session.head_seq(), 1);
        let updated = feed.reader().load_live_older(&before, demand(1)).await?;
        assert_eq!(updated.history_through, 0);
        assert_eq!(
            updated.revision, older.revision,
            "status changes must not stale a structural cursor"
        );
        let DisplayBlockBody::Work { summary, .. } = &updated.blocks[0].body else {
            anyhow::bail!("expected closing Work");
        };
        assert_eq!(
            (summary.total, summary.terminal, summary.running),
            (2, 1, 1)
        );
        let terminal = members.next().await?.context("changed first member")?;
        assert_eq!(terminal.entries[0].member_key, active.entries[0].member_key);
        assert!(terminal.entries[0].completion_id.is_some());
        h.effect(vec![], vec![finish("second", true, "second terminal")?])
            .await?;
        let frozen = timeline(&mut feed).await?;
        assert_eq!(frozen.through_pos, 1);
        let stale = feed
            .reader()
            .load_live_older(&before, demand(1))
            .await
            .expect_err("handoff changes the live structure");
        assert!(matches!(
            stale.downcast_ref::<ChatError>(),
            Some(ChatError::StaleContent)
        ));
        feed.reader().read_business_refs().await?;
        assert!(members.next().await?.context("sealed group")?.sealed);
        assert!(members.next().await?.is_none());
        members.close().await?;
        feed.reader().close().await?;
        feed.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}
