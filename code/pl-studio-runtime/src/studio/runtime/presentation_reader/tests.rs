use super::*;
use crate::studio::runtime::conversation_reader::ReadObservation;
use anyhow::Context as _;
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
        source: Some(ChatSourceId::ForegroundTurn {
            turn_id: "turn".into(),
        }),
        body: DisplayBlockBody::Work {
            summary: Box::default(),
            members: reference(),
        },
        state: pl_protocol::DisplayBlockState::Open,
    }
}

fn member(order: u64) -> DisplayMemberHead {
    let id = format!("member-{order}");
    DisplayMemberHead {
        member_key: id.clone(),
        member_order: order,
        record: pl_protocol::DisplayRecord {
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
            start_fact: None,
            end_fact: None,
            content_source: pl_protocol::DisplayContentSource::FrozenObservation {
                captured_at: None,
                available: true,
            },
        },
    }
}

#[test]
fn live_pages_are_newest_first_selected_but_delivered_in_original_order() -> Result<()> {
    let heads: Vec<_> = (1..=5).map(head).collect();
    let page = live_window(
        10,
        4,
        true,
        None,
        heads.iter().rev(),
        demand(2),
        |boundary| Ok(format!("qualified:{boundary}")),
    )?;
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
        None,
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
    let last = live_window(
        10,
        4,
        true,
        None,
        heads[..1].iter().rev(),
        demand(1),
        |_| anyhow::bail!("a complete last page must not request a cursor"),
    )?;
    assert_eq!(last.blocks[0].block_order, 1);
    assert!(last.older.is_none());
    Ok(())
}

#[test]
fn current_work_cannot_be_omitted_by_a_latest_window_item_or_byte_budget() -> Result<()> {
    let mut heads = [head(1), head(2)];
    heads[0].state = DisplayBlockState::Sealed;
    let latest = live_window(
        3,
        0,
        false,
        Some(heads[1].id.clone()),
        heads.iter().rev(),
        demand(1),
        |at| Ok(format!("before:{at}")),
    )?;
    assert_eq!(latest.current_work_id.as_deref(), Some("block-2"));
    assert_eq!(latest.blocks.len(), 1);
    assert_eq!(latest.blocks[0].id, "block-2");
    let bytes = encoded_size(&latest)? as u32;
    let too_small = ReadDemand {
        max_items: 1,
        max_bytes: bytes - 1,
    };
    assert!(
        live_window(
            3,
            0,
            false,
            Some(heads[1].id.clone()),
            heads.iter().rev(),
            too_small,
            |at| Ok(format!("before:{at}"))
        )
        .is_err()
    );
    assert!(
        live_window(
            3,
            0,
            false,
            Some(heads[0].id.clone()),
            heads.iter().rev(),
            demand(1),
            |at| Ok(format!("before:{at}"))
        )
        .is_err()
    );
    let older = live_window(
        3,
        0,
        false,
        None,
        heads[..1].iter().rev(),
        demand(1),
        |_| anyhow::bail!("complete old page"),
    )?;
    assert!(older.current_work_id.is_none());
    assert_eq!(older.blocks[0].id, "block-1");
    Ok(())
}

#[test]
fn byte_budget_includes_utf8_and_continuation_without_rejecting_complete_small_list() -> Result<()>
{
    let mut heads = [head(1), head(2)];
    heads[1].id = "显示头".repeat(40);
    let complete = live_window(1, 0, true, None, heads.iter().rev(), demand(2), |_| {
        Ok("cursor".repeat(1000))
    })?;
    let exact_bytes = encoded_size(&complete)? as u32;
    let exact = ReadDemand {
        max_items: 2,
        max_bytes: exact_bytes,
    };
    assert_eq!(
        live_window(1, 0, true, None, heads.iter().rev(), exact, |_| {
            Ok("cursor".repeat(1000))
        })?,
        complete
    );
    let undersized = ReadDemand {
        max_bytes: 1,
        ..exact
    };
    assert!(
        live_window(1, 0, true, None, heads.iter().rev(), undersized, |_| Ok(
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
    assert!(
        page.entries
            .iter()
            .all(|m| m.record.atom.completion_item_id.is_none())
    );
    assert!(page.entries.iter().all(|m| m.record.atom.payload.is_none()));
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
async fn v364_member_cut_survives_commit_confirm_cleanup_before_its_sqlite_read() -> Result<()> {
    use crate::{
        runtime_test_support::Environment,
        studio::runtime::conversation_feed::tests::completed_runs::{Harness, finish, start},
    };
    use anyhow::Context as _;
    use tokio::sync::oneshot;

    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        let saved = h
            .effect(
                vec![start("saved-prefix", true)],
                vec![finish("saved-prefix", true, "durable prefix")?],
            )
            .await?;
        let saved_member = saved.display.as_ref().context("saved display")?.members[0]
            .head
            .clone();
        h.save(&saved).await?;
        h.projection.presentation().lock().unwrap().confirm(saved.sequence);
        drop(saved);

        let pending = h
            .effect(
                vec![start("terminal-overlay", true)],
                vec![finish("terminal-overlay", true, "pending terminal body")?],
            )
            .await?;
        let delta = pending.display.as_ref().context("pending display")?;
        let pending_member = delta.members[0].head.clone();
        let terminal_row = Arc::downgrade(&delta.members[0]);
        let original_payload = Arc::downgrade(&pending.completions[0].payload);
        let original_contents = Arc::downgrade(&pending.completions[0].contents);
        let reference = DisplayBlockRef {
            database_id: h.history.conversation_database_id().await?.context("database")?,
            block_id: delta.blocks[0].header.id.clone(),
        };
        let mut feed = env.runtime.open_timeline_feed(&h.thread.id, demand(1)).await?;
        let reader = feed.reader().clone();
        let cut = reader.capture_display(None, 1, None, 0).await?;
        assert_eq!((cut.published, cut.durable), (0, 0));
        assert_eq!(h.session.durable_seq(), 1);
        assert_eq!(cut.current_work_id.as_deref(), Some(reference.block_id.as_str()));
        let captured_revision = cut.open[0].revision;
        let captured_head = Arc::downgrade(&cut.open[0]);
        assert!(matches!(
            &cut.open[0].body,
            DisplayBlockBody::Work { summary, .. } if (summary.total, summary.terminal) == (2, 2)
        ));
        assert_eq!(
            h.projection.presentation().lock().unwrap().resident_member_count(),
            1,
            "saved prefix is sparse; only the unsaved terminal overlay is resident"
        );

        let mut members = reader
            .open_display_members(reference.clone(), DisplayMemberWindow::Latest, demand(2))
            .await?;
        let (entered, captured) = oneshot::channel();
        let (resume, released) = oneshot::channel();
        members.cut_barrier = Some(DisplayMemberReadBarrier { entered, resume: released });
        let old_page = {
            let reading = members.next();
            tokio::pin!(reading);
            tokio::time::timeout(crate::runtime_test_support::integration_test_deadline()?, async {
                tokio::select! {
                    reached = captured => reached.context("member cut was not reached"),
                    result = &mut reading => anyhow::bail!("member read completed before its cut barrier: {result:?}"),
                }
            })
            .await??;

            // The production writer COMMIT completes before either owner confirms or read resumes.
            h.save(&pending).await?;
            assert_eq!(h.session.durable_seq(), 2);
            h.projection.presentation().lock().unwrap().confirm(pending.sequence);
            drop(pending);
            assert_eq!(
                h.projection.presentation().lock().unwrap().resident_member_count(),
                0,
                "confirm releases the open tail's durable terminal row without waiting for the query"
            );
            assert_eq!(terminal_row.strong_count(), 1, "only the in-flight read cut owns this row");
            assert!(original_payload.upgrade().is_none(), "durable original payload is no longer resident");
            assert!(original_contents.upgrade().is_none(), "durable original bodies are no longer resident");

            // Advance the very same tail again. The paused read must not adopt this newer head/row.
            let newer = h
                .effect(
                    vec![start("after-cut", true)],
                    vec![finish("after-cut", true, "newer than the captured cut")?],
                )
                .await?;
            let newer_member = newer.display.as_ref().context("newer display")?.members[0]
                .head
                .clone();
            assert_eq!(newer.display.as_ref().unwrap().blocks[0].header.id, reference.block_id);
            h.save(&newer).await?;
            h.projection.presentation().lock().unwrap().confirm(newer.sequence);
            drop(newer);
            assert_eq!((cut.published, cut.durable), (0, 0));
            assert!(matches!(
                &cut.open[0].body,
                DisplayBlockBody::Work { summary, .. } if (summary.total, summary.terminal) == (2, 2)
            ));
            drop(cut);
            assert_eq!(captured_head.strong_count(), 1, "the actual query retains its captured head");
            resume.send(()).map_err(|_| anyhow::anyhow!("paused read dropped before release"))?;
            let old_page = tokio::time::timeout(
                crate::runtime_test_support::integration_test_deadline()?,
                reading,
            )
            .await??
            .context("captured member page")?;
            (old_page, newer_member)
        };
        let (old_page, newer_member) = old_page;
        assert_eq!(old_page.block, reference);
        assert_eq!(old_page.revision, captured_revision);
        assert!(!old_page.sealed);
        assert_eq!(old_page.entries, [saved_member.clone(), pending_member.clone()]);
        assert!(old_page.before.is_none());
        assert!(terminal_row.upgrade().is_none(), "completed query drops its last overlay reference");
        assert!(captured_head.upgrade().is_none(), "completed query drops its old header reference");
        members.close().await?;
        drop(members);

        let latest_cut = reader.capture_display(None, 1, None, 0).await?;
        assert_eq!(latest_cut.current_work_id.as_deref(), Some(reference.block_id.as_str()));
        assert!(matches!(
            &latest_cut.open[0].body,
            DisplayBlockBody::Work { summary, .. } if (summary.total, summary.terminal) == (3, 3)
        ));
        assert!(!latest_cut.open[0].sealed);
        assert_eq!(
            h.projection.presentation().lock().unwrap().resident_member_count(),
            0
        );
        let mut latest = reader
            .open_display_members(reference.clone(), DisplayMemberWindow::Latest, demand(2))
            .await?;
        let newest = latest.next().await?.context("latest member page")?;
        assert_eq!(newest.revision, latest_cut.open[0].revision);
        assert!(newest.revision > captured_revision);
        assert_eq!(newest.entries, [pending_member, newer_member]);
        let mut older = reader
            .open_display_members(
                reference,
                DisplayMemberWindow::Before { member_order: newest.before.context("older prefix")? },
                demand(2),
            )
            .await?;
        let prefix = older.next().await?.context("saved prefix page")?;
        assert_eq!(prefix.entries, [saved_member]);
        assert!(prefix.before.is_none());
        assert_eq!(
            prefix.entries.iter().chain(&newest.entries)
                .map(|member| member.member_order).collect::<Vec<_>>(),
            [1, 2, 3],
            "the captured overlay's stable key/order is neither lost nor duplicated after cleanup"
        );
        older.close().await?;
        latest.close().await?;
        reader.close().await?;
        feed.close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
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
        assert!(!sealed.is_fixed_snapshot());
        assert!(sealed.next().await?);
        sealed.seal();
        assert!(
            !sealed.is_fixed_snapshot(),
            "closing a hot watch does not make it a cold snapshot"
        );
        assert_eq!(changes.receiver_count(), 0);
        assert!(!sealed.next().await?);

        let (changes, changed) = watch::channel(0);
        let mut interrupted = ReadObservation::new(a1.reader().clone(), Some(changed));
        assert!(interrupted.next().await?);
        drop(changes);
        let lost = interrupted
            .next()
            .await
            .expect_err("a hot watch cannot end as a successful fixed EOF");
        assert_eq!(
            lost.downcast_ref::<pl_protocol::studio::StudioError>()
                .context("typed watch discontinuity")?
                .reason(),
            Some(pl_protocol::studio::StudioErrorReason::ConversationResyncRequired.label())
        );
        assert!(!interrupted.is_fixed_snapshot());

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
