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
        h.effect(vec![start("earlier-body", false)], vec![]).await?;
        h.effect(vec![start("first", true), start("second", true)], vec![])
            .await?;
        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let initial = timeline(&mut feed).await?;
        assert_eq!(initial.through_pos, 0);
        let live = initial
            .live
            .context("initial open Work and earlier active Text")?;
        assert_eq!(live.blocks.len(), 1);
        let reference = work_reference(&live)?;
        let before = live.older.context("earlier active Text")?;
        let older = feed.reader().load_live_older(&before, demand(1)).await?;
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
        let terminal = members.next().await?.context("changed first member")?;
        assert_eq!(terminal.entries[0].member_key, active.entries[0].member_key);
        assert!(terminal.entries[0].record.atom.completion_item_id.is_some());
        h.effect(vec![start("body", false)], vec![]).await?;
        let stale = feed
            .reader()
            .load_live_older(&before, demand(1))
            .await
            .expect_err("a new reliable segment changes the live structure");
        assert!(matches!(
            stale.downcast_ref::<ChatError>(),
            Some(ChatError::StaleContent)
        ));
        feed.reader().read_business_refs().await?;
        let sealed = members.next().await?.context("sealed group")?;
        assert!(
            sealed.sealed,
            "earlier unfinished Text delays publication, not freezing"
        );
        assert_eq!(sealed.entries[0].member_key, active.entries[0].member_key);
        assert!(members.next().await?.is_none());
        h.effect(
            vec![],
            vec![finish("second", true, "late second terminal")?],
        )
        .await?;
        assert!(
            members.next().await?.is_none(),
            "late terminal never reopens the sealed observation"
        );
        members.close().await?;
        feed.reader().close().await?;
        feed.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}
