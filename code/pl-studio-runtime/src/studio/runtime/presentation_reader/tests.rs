use super::*;
use crate::studio::runtime::conversation_reader::ReadObservation;
use futures::poll;
use pl_protocol::{
    ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind, ChatScope, ChatSourceId,
    ChatTerminalOutcome, DisplayBlockBody,
};
use std::task::Poll;
use tokio::sync::watch;

fn demand(max_items: u32) -> ReadDemand {
    ReadDemand {
        max_items,
        max_bytes: 16 * 1024,
    }
}

fn reference() -> DisplayBlockRef {
    DisplayBlockRef {
        database_id: "database".into(),
        block_id: "work".into(),
    }
}

fn head(order: u64) -> LiveDisplayBlock {
    LiveDisplayBlock {
        id: format!("block-{order}"),
        block_order: order,
        body: DisplayBlockBody::Work {
            summary: Box::default(),
            members: reference(),
        },
        closing: false,
    }
}

fn member(order: u64) -> DisplayMemberHead {
    let id = format!("member-{order}");
    DisplayMemberHead {
        member_key: id.clone(),
        member_order: order,
        atom: ChatAtom {
            id,
            completion_item_id: None,
            completion_seq: None,
            source: ChatSourceId::ForegroundTurn {
                turn_id: "turn".into(),
            },
            source_state: None,
            source_order: Some(order),
            kind: ChatAtomKind::ToolCall,
            delivery: ChatDeliveryKind::Foreground,
            lifecycle: ChatAtomLifecycle::Terminal {
                started: None,
                ended: None,
                outcome: ChatTerminalOutcome::Cancelled,
            },
            turn_id: Some("turn".into()),
            attempt_id: None,
            tool: None,
            wait: None,
            text_channel: None,
            started_at: None,
            finished_at: None,
            content_present: None,
            contents: Vec::new(),
            payload: None,
        },
        // A genuine interrupted member has no fabricated ChatItem.
        completion_id: None,
    }
}

#[test]
fn live_pages_are_newest_first_selected_but_delivered_in_original_order() -> Result<()> {
    let heads: Vec<_> = (1..=5).map(head).collect();
    let page = live_window(10, 4, true, heads.iter().rev(), demand(2), |boundary| {
        Ok(format!("qualified:{boundary}"))
    })?;
    assert_eq!(
        page.blocks
            .iter()
            .map(|b| b.block_order)
            .collect::<Vec<_>>(),
        [4, 5]
    );
    assert_eq!(page.older.as_deref(), Some("qualified:4"));
    let next = live_window(
        10,
        4,
        true,
        heads.iter().rev().filter(|head| head.block_order < 4),
        demand(2),
        |boundary| Ok(format!("qualified:{boundary}")),
    )?;
    assert_eq!(
        next.blocks
            .iter()
            .map(|b| b.block_order)
            .collect::<Vec<_>>(),
        [2, 3]
    );
    assert_eq!(next.older.as_deref(), Some("qualified:2"));
    let last = live_window(10, 4, true, heads[..1].iter().rev(), demand(1), |_| {
        anyhow::bail!("a complete last page must not request a cursor")
    })?;
    assert_eq!(last.blocks[0].block_order, 1);
    assert!(last.older.is_none());
    Ok(())
}

#[test]
fn byte_budget_includes_utf8_and_continuation_without_rejecting_complete_small_list() -> Result<()>
{
    let mut heads = [head(1), head(2)];
    heads[1].id = "显示头".repeat(40);
    let complete = live_window(1, 0, true, heads.iter().rev(), demand(2), |_| {
        Ok("cursor".repeat(1000))
    })?;
    let exact_bytes = encoded_size(&complete)? as u32;
    let exact = ReadDemand {
        max_items: 2,
        max_bytes: exact_bytes,
    };
    assert_eq!(
        live_window(1, 0, true, heads.iter().rev(), exact, |_| {
            Ok("cursor".repeat(1000))
        })?,
        complete
    );
    let undersized = ReadDemand {
        max_bytes: 1,
        ..exact
    };
    assert!(
        live_window(1, 0, true, heads.iter().rev(), undersized, |_| Ok(
            "c".into()
        ))
        .is_err()
    );
    // The JSON byte counter uses the same encoding as the transport, not character count.
    assert_eq!(
        encoded_size(&complete)?,
        serde_json::to_vec(&complete)?.len()
    );
    Ok(())
}

#[test]
fn member_windows_preserve_stable_orders_and_real_terminal_without_body() -> Result<()> {
    let members: Vec<_> = (1..=5).map(member).collect();
    let page = member_page(
        reference(),
        8,
        false,
        DisplayMemberWindow::Latest,
        members.iter().rev(),
        demand(2),
    )?;
    assert_eq!(
        page.entries
            .iter()
            .map(|m| m.member_order)
            .collect::<Vec<_>>(),
        [4, 5]
    );
    assert_eq!(page.before, Some(4));
    assert!(!page.sealed);
    assert!(page.entries.iter().all(|m| m.completion_id.is_none()));
    assert!(page.entries.iter().all(|m| m.atom.payload.is_none()));
    let frozen = member_page(
        reference(),
        9,
        true,
        DisplayMemberWindow::Before { member_order: 4 },
        members[..3].iter().rev(),
        demand(2),
    )?;
    assert_eq!(
        frozen
            .entries
            .iter()
            .map(|m| m.member_order)
            .collect::<Vec<_>>(),
        [2, 3]
    );
    assert_eq!(frozen.before, Some(2));
    assert!(frozen.sealed);
    assert_eq!(frozen.block, page.block);
    assert!(
        member_page(
            reference(),
            9,
            true,
            DisplayMemberWindow::Before { member_order: 4 },
            members.iter().rev(),
            demand(2),
        )
        .is_err()
    );
    Ok(())
}

#[tokio::test]
async fn display_cursors_and_observation_reuse_real_reader_qualification() -> Result<()> {
    use crate::runtime_test_support::Environment;
    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread_a = env
            .runtime
            .create_thread(&env.project.id, "presentation A")
            .await?;
        let thread_b = env
            .runtime
            .create_thread(&env.project.id, "presentation B")
            .await?;
        let mut a1 = env
            .runtime
            .open_conversation_feed(&thread_a.id, ChatScope::Main, demand(1))
            .await?;
        let mut b = env
            .runtime
            .open_conversation_feed(&thread_b.id, ChatScope::Main, demand(1))
            .await?;
        a1.reader().bind_presentation_ceiling(12)?;
        b.reader().bind_presentation_ceiling(12)?;
        let tokens = a1.reader().presentation_tokens().await?;
        let history = tokens.before(12, 8)?;
        let live = tokens.live_before(3, 5)?;
        assert_eq!(a1.reader().display_boundary(&history).await?, (12, 8));
        assert_eq!(a1.reader().live_display_boundary(&live, 3).await?, 5);
        let stale = a1
            .reader()
            .live_display_boundary(&live, 4)
            .await
            .expect_err("structural revision must invalidate only live continuation");
        assert!(matches!(
            stale.downcast_ref::<ChatError>(),
            Some(ChatError::StaleContent)
        ));
        assert_eq!(a1.reader().display_boundary(&history).await?, (12, 8));
        assert!(b.reader().display_boundary(&history).await.is_err());
        assert!(a1.reader().display_boundary(&live).await.is_err());

        // Shared pull lifecycle: close wakes an already parked next without a receive/credit lock.
        let (changes, changed) = watch::channel(0);
        let mut observation = ReadObservation::new(a1.reader().clone(), Some(changed));
        assert!(observation.next().await?);
        let cancellation = observation.cancellation_token();
        {
            let waiting = observation.next();
            tokio::pin!(waiting);
            assert!(matches!(poll!(&mut waiting), Poll::Pending));
            cancellation.cancel();
            assert!(matches!(
                waiting
                    .await
                    .expect_err("close must wake next")
                    .downcast_ref::<ChatError>(),
                Some(ChatError::Cancelled)
            ));
        }
        // Closing this view does not retire the borrowed reader or its other windows.
        a1.reader().ensure()?;
        drop(observation);
        assert_eq!(changes.receiver_count(), 0);

        let (changes, changed) = watch::channel(0);
        let mut sealed = ReadObservation::new(a1.reader().clone(), Some(changed));
        assert!(sealed.next().await?);
        sealed.seal();
        assert_eq!(changes.receiver_count(), 0);
        assert!(!sealed.next().await?);

        a1.reader().close().await?;
        let mut a2 = env
            .runtime
            .open_conversation_feed(&thread_a.id, ChatScope::Main, demand(1))
            .await?;
        a2.reader().bind_presentation_ceiling(12)?;
        assert!(a1.reader().display_boundary(&history).await.is_err());
        assert!(a2.reader().display_boundary(&history).await.is_err());
        let current = a2.reader().presentation_tokens().await?.before(12, 8)?;
        assert_eq!(a2.reader().display_boundary(&current).await?, (12, 8));
        a1.close().await?;
        b.close().await?;
        a2.reader().close().await?;
        a2.close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}
