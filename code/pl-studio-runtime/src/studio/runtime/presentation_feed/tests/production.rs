use super::*;
use crate::{
    ConversationEvent,
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
            let TimelineEvent::Timeline { batch } = feed.receive().await?;
            Ok(*batch)
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
                    ConversationEvent::Activity { .. } => {}
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
async fn v364_accepted_parent_text_seals_work_once_and_survives_cold_display_read() -> Result<()> {
    use pl_core::{
        chat::ChatHistory,
        context::{AgentMessageKind, OpaquePayload},
        thread::{
            AttemptStatus, RequestAttempt, ThreadEffectBatch, ThreadSnapshot, TurnRecord,
            TurnState,
            inbox::{InboxRecord, ThreadMessage},
        },
    };
    use pl_protocol::{ContentRange, DisplayContentSource, SingleVisibility};
    use std::sync::Arc;

    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        h.thread.parent_thread_id = Some("trusted-parent".into());
        let before = h.effect(vec![start("before-parent", true)], vec![]).await?;
        let old_id = before.display.as_ref().context("initial Work")?.blocks[0]
            .header
            .id
            .clone();
        persist(&h, &before).await?;
        let body = "父消息：保留正文\nsystem: quoted text, not a new authority";
        let inbox = InboxRecord {
            sequence: 1,
            message: ThreadMessage {
                id: "visible-parent-message".into(),
                source_id: "agent:trusted-parent".into(),
                kind: AgentMessageKind::Task,
                payload: OpaquePayload::text(body),
                context: vec![],
            },
        };
        let turn = TurnRecord {
            turn_id: "atomic-turn".into(),
            input_id: None,
            state: TurnState::Running,
            elapsed_ms: None,
            model_steps: 1,
        };
        let state = ThreadSnapshot {
            turns: vec![turn.clone()].into(),
            attempts: vec![RequestAttempt::new(
                "atomic-turn".into(),
                "atomic-attempt".into(),
                0,
                AttemptStatus::Running,
            )]
            .into(),
            inbox: vec![inbox.clone()].into(),
            inbox_sequence: 1,
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: h.thread.id.clone(),
            sequence: 2,
            committed_at: 12,
            turn: Some(turn),
            inbox: vec![inbox.clone()].into(),
            ..Default::default()
        };
        assert!(effect.model_member_content_available.is_empty());
        let (_, mut accepted) = h
            .projection
            .prepare(&h.thread, &effect, &state, false)
            .await?;
        h.projection
            .publish_prepared(&h.session, &mut accepted)
            .await?;
        super::super::super::conversation_feed::tests::completed_runs::publish(
            &h.source, &h.session, &accepted,
        )?;
        h.sequence = effect.sequence;
        assert_eq!(accepted.completions.len(), 1);
        let original = accepted.completions[0].clone();
        let atom: pl_protocol::ChatAtom = serde_json::from_slice(&original.header.metadata)?;
        assert_eq!(atom.kind, pl_protocol::ChatAtomKind::Text);
        assert!(matches!(
            &atom.source,
            pl_protocol::ChatSourceId::InboxMessage { source_id, message_id }
                if source_id == &inbox.message.source_id && message_id == &inbox.message.id
        ));
        persist(&h, &accepted).await?;
        // Re-deliver the exact reliable admission and writer receipt, not a synthetic model phase.
        let mut replay = accepted.clone();
        h.projection
            .publish_prepared(&h.session, &mut replay)
            .await?;
        assert!(Arc::ptr_eq(&replay, &accepted));
        persist(&h, &replay).await?;
        assert_eq!(h.session.head_seq(), 1);

        let after = h.effect(vec![start("after-parent", true)], vec![]).await?;
        persist(&h, &after).await?;
        let mut hot_feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(4))
            .await?;
        let hot = timeline(&mut hot_feed).await?;
        assert_eq!(
            hot.through_pos, 2,
            "a reliably accepted public parent Text seals the prior Work and publishes its Single"
        );
        assert_eq!(hot.blocks.len(), 2);
        assert_eq!(hot.blocks[0].id, old_id);
        let DisplayBlockBody::Work {
            summary,
            members: old_members,
        } = &hot.blocks[0].body
        else {
            panic!("frozen prior Work")
        };
        assert_eq!((summary.total, summary.running), (1, 1));
        let DisplayBlockBody::Single { record, visibility } = &hot.blocks[1].body else {
            panic!("visible accepted parent Single")
        };
        assert_eq!(*visibility, SingleVisibility::Content);
        assert_eq!(record.atom.source, atom.source);
        assert_eq!(record.atom.id, atom.id);
        assert_eq!(
            record.end_fact,
            match atom.lifecycle {
                ChatAtomLifecycle::Terminal { ended, .. } => ended,
                _ => unreachable!(),
            }
        );
        let accepted_at = record
            .end_fact
            .context("reliable parent admission position")?;
        assert_eq!(accepted_at.effect_seq, effect.sequence);
        assert_eq!(
            accepted
                .display
                .as_ref()
                .unwrap()
                .blocks
                .iter()
                .find(|block| block.header.id == old_id)
                .context("frozen old Work")?
                .header
                .boundary,
            Some(accepted_at),
            "the frozen boundary preserves the parent's original effect sequence and suborder"
        );
        let body_ref = record
            .atom
            .contents
            .first()
            .context("parent text body")?
            .reference
            .clone();
        let range = ContentRange {
            offset: 0,
            max_bytes: 4096,
        };
        assert_eq!(
            hot_feed
                .reader()
                .read_content(&body_ref, range.clone())
                .await?
                .bytes,
            body.as_bytes()
        );
        let mut members = hot_feed
            .reader()
            .open_display_members(old_members.clone(), DisplayMemberWindow::Latest, demand(1))
            .await?;
        let frozen = members
            .next()
            .await?
            .context("frozen pre-parent observation")?;
        assert!(frozen.sealed);
        assert_eq!(frozen.entries.len(), 1);
        assert!(matches!(
            frozen.entries[0].record.content_source,
            DisplayContentSource::FrozenObservation { captured_at, available: true }
                if captured_at == Some(effect.committed_at)
        ));
        members.close().await?;
        let live = hot.live.as_ref().context("new live Work")?;
        assert_eq!(live.blocks.len(), 1);
        let new_id = live
            .current_work_id
            .as_ref()
            .context("unique current Work")?;
        assert_ne!(new_id, &old_id);
        assert_eq!(&live.blocks[0].id, new_id);
        assert!(matches!(
            &live.blocks[0].body,
            DisplayBlockBody::Work { summary, .. } if summary.total == 1
        ));
        assert_eq!(
            ChatHistory::item(&h.history, &original.header.item_id)
                .await?
                .context("original")?,
            *original
        );
        hot_feed.reader().close().await?;
        hot_feed.close().await?;
        env.runtime
            .thread_observations
            .observation_slot(&h.thread.id)
            .retire(&h.source);
        let mut cold_feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(4))
            .await?;
        let cold = timeline(&mut cold_feed).await?;
        assert_eq!(cold.blocks, hot.blocks);
        let cold_live = cold.live.context("durable new tail")?;
        assert_eq!(cold_live.current_work_id, live.current_work_id);
        assert_eq!(cold_live.blocks, live.blocks);
        assert_eq!(
            cold_feed
                .reader()
                .read_content(&body_ref, range)
                .await?
                .bytes,
            body.as_bytes()
        );
        cold_feed.reader().close().await?;
        cold_feed.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn v364_empty_text_keeps_the_production_feed_tail_at_max_items_one() -> Result<()> {
    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        let first = h.effect(vec![start("work", true)], vec![]).await?;
        persist(&h, &first).await?;
        let second = h
            .effect(vec![], vec![finish("work", true, "completed work")?])
            .await?;
        persist(&h, &second).await?;
        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let initial = timeline(&mut feed).await?;
        let original = work_reference(&initial.live.context("initial live")?)?;
        feed.reader().close().await?;
        feed.close().await?;
        let third = h.effect(vec![start("empty", false)], vec![]).await?;
        persist(&h, &third).await?;
        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let cut = timeline(&mut feed).await?;
        assert_eq!(cut.through_pos, 0, "empty Started must not publish Work");
        assert!(cut.blocks.is_empty());
        let live = cut.live.context("same live tail")?;
        assert_eq!(live.blocks.len(), 1);
        assert_eq!(work_reference(&live)?, original);
        feed.reader().close().await?;
        feed.close().await?;
        let prepared = h.effect(vec![], vec![finish("empty", false, "")?]).await?;
        persist(&h, &prepared).await?;
        assert_eq!(
            h.session.head_seq(),
            2,
            "the empty original is still a completion"
        );
        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let cut = timeline(&mut feed).await?;
        assert_eq!(cut.through_pos, 0);
        assert_eq!(
            work_reference(&cut.live.context("tail after empty completion")?)?,
            original
        );
        // Empty display content must remain independently readable as an original.
        // This proof belongs to the production reader, not a Flutter protocol loop.
        let completion = prepared.completions.first().context("empty original")?;
        let saved = pl_core::chat::ChatHistory::item(&h.history, &completion.header.item_id)
            .await?
            .context("saved empty original")?;
        assert_eq!(saved, **completion);
        let entry = feed
            .reader()
            .read_completed(&completion.header.item_id, demand(1))
            .await?;
        assert_eq!(entry.atom.content_present, Some(false));
        assert_eq!(
            entry.main_presentation,
            pl_protocol::MainPresentation::Hidden
        );
        let body = entry
            .atom
            .contents
            .iter()
            .find(|content| content.role == pl_protocol::ChatContentRole::Body)
            .context("empty body reference")?;
        let window = feed
            .reader()
            .read_content(
                &body.reference,
                pl_protocol::ContentRange {
                    offset: 0,
                    max_bytes: 1024,
                },
            )
            .await?;
        assert!(window.bytes.is_empty());
        assert_eq!(window.available_through, 0);
        assert!(window.sealed);
        feed.reader().close().await?;
        feed.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn v364_reliable_visible_text_cross_source_late_results_and_final_empty_keep_one_tail()
-> Result<()> {
    use pl_protocol::{DisplayBlockState, SingleVisibility};
    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        let first = h.effect(vec![start("A", true)], vec![]).await?;
        persist(&h, &first).await?;
        let first_id = first.display.as_ref().unwrap().blocks[0].header.id.clone();
        let complete = h
            .effect(vec![], vec![finish("A", true, "reasoning")?])
            .await?;
        persist(&h, &complete).await?;
        let background = h.background_result(101).await?;
        persist(&h, &background).await?;
        assert!(
            background
                .display
                .as_ref()
                .unwrap()
                .blocks
                .iter()
                .all(|block| block.header.id == first_id)
        );
        let text_start = h.effect(vec![start("T", false)], vec![]).await?;
        persist(&h, &text_start).await?;
        assert!(text_start.display.as_ref().unwrap().blocks.is_empty());
        let visible = h.content_available(vec![start("T", false)]).await?;
        persist(&h, &visible).await?;
        let text = visible
            .display
            .as_ref()
            .unwrap()
            .blocks
            .iter()
            .find(|block| matches!(block.header.body, DisplayBlockBody::Single { .. }))
            .unwrap()
            .header
            .clone();
        let DisplayBlockBody::Single { record, .. } = &text.body else {
            unreachable!()
        };
        assert!(record.start_fact < text.first_content_at);
        assert_eq!(visible.display.as_ref().unwrap().published_through, 1);
        let b = h.effect(vec![start("B", true)], vec![]).await?;
        persist(&h, &b).await?;
        let tail_id = b.display.as_ref().unwrap().blocks[0].header.id.clone();
        let finished_b = h
            .effect(vec![], vec![finish("B", true, "finished B")?])
            .await?;
        persist(&h, &finished_b).await?;
        let terminal_text = h.effect(vec![], vec![finish("T", false, "")?]).await?;
        persist(&h, &terminal_text).await?;
        assert!(
            terminal_text
                .display
                .as_ref()
                .unwrap()
                .blocks
                .iter()
                .any(|block| {
                    block.header.id == text.id
                        && matches!(
                            block.header.body,
                            DisplayBlockBody::Single {
                                visibility: SingleVisibility::FinalEmptyAfterContent,
                                ..
                            }
                        )
                })
        );
        let late = h.background_result(102).await?;
        persist(&h, &late).await?;
        assert!(
            late.display
                .as_ref()
                .unwrap()
                .blocks
                .iter()
                .all(|block| block.header.id == tail_id)
        );
        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let initial = timeline(&mut feed).await?;
        assert_eq!(initial.through_pos, 2);
        assert_eq!(initial.blocks.len(), 1);
        let live = initial.live.context("latest canonical live cut")?;
        assert_eq!(live.current_work_id.as_deref(), Some(tail_id.as_str()));
        assert_eq!(live.blocks.len(), 1);
        assert_eq!(live.blocks[0].id, tail_id);
        assert_eq!(live.blocks[0].state, DisplayBlockState::Open);
        let before = initial
            .before
            .context("max_items=1 has the earlier frozen Work")?;
        let older = feed
            .reader()
            .load_timeline_older(&before, demand(1))
            .await?;
        assert_eq!(older.blocks[0].id, first_id);
        assert!(older.live.is_none());
        feed.reader().close().await?;
        feed.close().await?;
        env.runtime
            .thread_observations
            .observation_slot(&h.thread.id)
            .retire(&h.source);
        let mut cold = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let cut = timeline(&mut cold).await?;
        let live = cut.live.context("saved Resting tail")?;
        assert!(!live.execution_present);
        assert_eq!(live.current_work_id.as_deref(), Some(tail_id.as_str()));
        let DisplayBlockBody::Work { summary, .. } = &live.blocks[0].body else {
            panic!("Work")
        };
        assert_eq!(
            (
                summary.total,
                summary.terminal,
                summary.running,
                summary.unavailable
            ),
            (2, 2, 0, 0)
        );
        cold.reader().close().await?;
        cold.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn v364_normal_turn_completion_and_owner_retirement_preserve_the_durable_resting_tail()
-> Result<()> {
    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        let begin = h.effect(vec![start("resting", true)], vec![]).await?;
        persist(&h, &begin).await?;
        let id = begin.display.as_ref().unwrap().blocks[0].header.id.clone();
        let done = h
            .effect(vec![], vec![finish("resting", true, "finished reasoning")?])
            .await?;
        persist(&h, &done).await?;
        let turn = h.finish_successfully().await?;
        assert!(turn.current.source_changes.iter().any(|source| matches!(
            source.lifecycle,
            pl_protocol::ChatSourceLifecycle::Ended {
                outcome: pl_protocol::ChatTerminalOutcome::Completed
            }
        )));
        persist(&h, &turn).await?;
        assert_eq!(turn.display.as_ref().unwrap().published_through, 0);
        assert!(turn.display.as_ref().unwrap().blocks.is_empty());
        env.runtime
            .thread_observations
            .observation_slot(&h.thread.id)
            .retire(&h.source);
        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let batch = timeline(&mut feed).await?;
        assert!(batch.blocks.is_empty());
        let live = batch.live.context("durable Resting tail")?;
        assert_eq!(live.current_work_id.as_deref(), Some(id.as_str()));
        assert!(!live.execution_present);
        let DisplayBlockBody::Work { summary, .. } = &live.blocks[0].body else {
            panic!("Work")
        };
        assert_eq!(
            (
                summary.total,
                summary.terminal,
                summary.running,
                summary.waiting,
                summary.unavailable
            ),
            (1, 1, 0, 0, 0)
        );
        feed.reader().close().await?;
        feed.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn cold_resting_member_snapshot_seals_observation_without_freezing_work() -> Result<()> {
    use pl_core::chat::{ChatError, ChatHistory};
    use pl_protocol::{
        DisplayBlockState,
        studio::{StudioError, StudioErrorReason},
    };

    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        let started = h
            .effect(
                vec![start("resting-one", true), start("resting-two", true)],
                vec![],
            )
            .await?;
        persist(&h, &started).await?;
        let completed = h
            .effect(
                vec![],
                vec![
                    finish("resting-one", true, "saved one")?,
                    finish("resting-two", true, "saved two")?,
                ],
            )
            .await?;
        persist(&h, &completed).await?;
        let expected = completed
            .display
            .as_ref()
            .context("terminal display")?
            .members
            .iter()
            .map(|member| member.head.clone())
            .collect::<Vec<_>>();
        assert_eq!(expected.len(), 2);
        let finished = h.finish_successfully().await?;
        persist(&h, &finished).await?;
        let before = h.history.display_recovery().await?.context("saved tail")?;
        assert_eq!(before.open.len(), 1);
        assert!(!before.open[0].sealed);
        assert_eq!(
            (before.open[0].next_member, before.open[0].unfinished),
            (2, 0)
        );
        env.runtime
            .thread_observations
            .observation_slot(&h.thread.id)
            .retire(&h.source);

        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let live = timeline(&mut feed)
            .await?
            .live
            .context("saved-only live tail")?;
        assert!(!live.execution_present);
        assert_eq!(live.blocks[0].state, DisplayBlockState::Open);
        let reference = work_reference(&live)?;
        let reader = feed.reader().clone();
        let mut latest = reader
            .open_display_members(reference.clone(), DisplayMemberWindow::Latest, demand(1))
            .await?;
        let page = latest.next().await?.context("fixed cold member page")?;
        assert!(
            page.sealed,
            "a saved-only bounded observation must seal before its finite EOF"
        );
        assert_eq!(page.revision, before.open[0].revision);
        assert_eq!(page.entries, [expected[1].clone()]);
        assert_eq!(page.before, Some(2));
        assert!(latest.next().await?.is_none());
        let mut older = reader
            .open_display_members(
                reference.clone(),
                DisplayMemberWindow::Before { member_order: 2 },
                demand(1),
            )
            .await?;
        let prefix = older.next().await?.context("fixed cold prefix")?;
        assert!(prefix.sealed);
        assert_eq!(prefix.entries, [expected[0].clone()]);
        assert!(prefix.before.is_none());
        assert!(older.next().await?.is_none());
        older.close().await?;
        let after = h
            .history
            .display_recovery()
            .await?
            .context("unchanged saved tail")?;
        assert_eq!(
            after.open, before.open,
            "observing a fixed page must not freeze its business block"
        );
        assert_eq!(
            (after.effect, after.published),
            (before.effect, before.published)
        );
        for original in completed.completions.iter() {
            assert_eq!(
                ChatHistory::item(&h.history, &original.header.item_id)
                    .await?
                    .context("saved original")?,
                **original
            );
        }
        assert!(
            env.runtime
                .session_of(&h.thread.id)
                .and_then(|session| session.observed_thread(&h.thread.id))
                .is_none()
        );

        let mut wrong_database = reference.clone();
        wrong_database.database_id.push_str("-stale");
        let stale = reader
            .open_display_members(wrong_database, DisplayMemberWindow::Latest, demand(1))
            .await
            .err()
            .context("wrong database must be rejected")?;
        assert!(matches!(
            stale.downcast_ref::<ChatError>(),
            Some(ChatError::StaleContent)
        ));
        let mut cancelled = reader
            .open_display_members(reference.clone(), DisplayMemberWindow::Latest, demand(1))
            .await?;
        cancelled.request_close();
        assert!(matches!(
            cancelled
                .next()
                .await
                .expect_err("cancelled snapshot must not become EOF")
                .downcast_ref::<ChatError>(),
            Some(ChatError::Cancelled)
        ));
        cancelled.close().await?;
        let mut missing_reference = reference.clone();
        missing_reference.block_id = "missing-snapshot".into();
        let mut missing = reader
            .open_display_members(missing_reference, DisplayMemberWindow::Latest, demand(1))
            .await?;
        assert!(
            missing.next().await.is_err(),
            "a missing first page is not a fixed empty snapshot"
        );
        missing.close().await?;

        let mut captured_cold = reader
            .open_display_members(reference, DisplayMemberWindow::Latest, demand(1))
            .await?;
        env.runtime
            .thread_observations
            .observation_slot(&h.thread.id)
            .install(h.source.clone());
        let changed = captured_cold
            .next()
            .await
            .expect_err("a new source invalidates a cold qualification");
        assert_eq!(
            changed
                .downcast_ref::<StudioError>()
                .context("typed continuity error")?
                .reason(),
            Some(StudioErrorReason::ConversationResyncRequired.label())
        );
        captured_cold.close().await?;
        let changed = latest
            .next()
            .await
            .expect_err("even fixed EOF must recheck the original source epoch");
        assert_eq!(
            changed
                .downcast_ref::<StudioError>()
                .context("typed continuity error after EOF")?
                .reason(),
            Some(StudioErrorReason::ConversationResyncRequired.label())
        );
        latest.close().await?;
        reader.close().await?;
        feed.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn hot_terminal_members_watch_until_business_seal_with_unfinished_observation() -> Result<()>
{
    use pl_protocol::DisplayContentSource;

    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        let done = h
            .effect(
                vec![start("terminal", true)],
                vec![finish("terminal", true, "already finished")?],
            )
            .await?;
        persist(&h, &done).await?;
        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let reference = work_reference(&timeline(&mut feed).await?.live.context("hot tail")?)?;
        let reader = feed.reader().clone();
        let mut members = reader
            .open_display_members(reference.clone(), DisplayMemberWindow::Latest, demand(2))
            .await?;
        let first = members.next().await?.context("terminal open page")?;
        assert!(!first.sealed);
        assert_eq!(first.entries.len(), 1);
        assert!(matches!(
            first.entries[0].record.atom.lifecycle,
            ChatAtomLifecycle::Terminal { .. }
        ));
        {
            let waiting = members.next();
            tokio::pin!(waiting);
            assert!(
                matches!(poll!(&mut waiting), Poll::Pending),
                "all-terminal open Work must keep watching"
            );
            let later = h.effect(vec![start("still-running", true)], vec![]).await?;
            persist(&h, &later).await?;
            let updated = waiting
                .await?
                .context("new member on the same hot observation")?;
            assert_eq!(updated.block, reference);
            assert!(!updated.sealed);
            assert_eq!(updated.entries.len(), 2);
            assert_eq!(updated.entries[0], first.entries[0]);
            assert_eq!(updated.entries[1].member_order, 2);
        }
        let text = h.effect(vec![start("boundary", false)], vec![]).await?;
        persist(&h, &text).await?;
        let visible = h.content_available(vec![start("boundary", false)]).await?;
        persist(&h, &visible).await?;
        let frozen = members
            .next()
            .await?
            .context("business seal publishes a final snapshot")?;
        assert!(frozen.sealed);
        assert!(frozen.revision > first.revision);
        assert_eq!(frozen.entries.len(), 2);
        assert!(matches!(
            frozen.entries[1].record.atom.lifecycle,
            ChatAtomLifecycle::Active { .. }
        ));
        assert!(matches!(
            frozen.entries[1].record.content_source,
            DisplayContentSource::FrozenObservation {
                available: true,
                ..
            }
        ));
        assert!(
            members.next().await?.is_none(),
            "business-sealed snapshot finishes despite an unfinished observation"
        );
        members.close().await?;
        reader.close().await?;
        feed.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn v364_applied_bad_original_reference_is_rejected_on_member_read_without_rebuilding()
-> Result<()> {
    use sea_orm::{ConnectionTrait, Database};
    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        let done = h
            .effect(
                vec![start("original", true)],
                vec![finish("original", true, "preserved original")?],
            )
            .await?;
        persist(&h, &done).await?;
        let delta = done.display.as_ref().unwrap();
        let member = &delta.members[0];
        let original = member
            .head
            .record
            .atom
            .completion_item_id
            .clone()
            .context("original")?;
        let path = env
            .runtime
            .store
            .session_paths(&h.thread.workspace_id, &h.thread.id)?
            .history_database();
        let db = Database::connect(format!("sqlite://{}?mode=rw", path.display())).await?;
        db.execute_raw(sea_orm::Statement::from_sql_and_values(
            sea_orm::DatabaseBackend::Sqlite,
            "UPDATE conversation_display_members SET completion_id='missing',
             metadata=CAST(json_set(metadata,'$.head.record.contentSource.completionId','missing',
                '$.head.record.atom.completionItemId','missing') AS BLOB) WHERE member_key=?",
            vec![member.head.member_key.clone().into()],
        ))
        .await?;
        let database = h
            .history
            .conversation_database_id()
            .await?
            .context("database")?;
        assert!(
            h.history
                .display_member_page(&database, &member.block_id, None, 1)
                .await
                .is_err()
        );
        assert!(
            pl_core::chat::ChatHistory::item(&h.history, &original)
                .await?
                .is_some()
        );
        assert_eq!(
            h.history.display_recovery().await?.unwrap().open[0].id,
            member.block_id
        );
        db.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn reliable_text_visibility_advances_p_without_h_and_member_completion_advances_h_without_p()
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
            active.entries[0].record.atom.lifecycle,
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
        assert!(terminal.entries[0].record.atom.completion_item_id.is_some());
        assert!(terminal.revision > active.revision);
        assert!(
            !terminal.sealed,
            "member completion alone is not a display boundary"
        );

        let before_h = h.session.head_seq();
        h.effect(vec![start("text", false)], vec![]).await?;
        h.content_available(vec![start("text", false)]).await?;
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
                ConversationEvent::Activity { .. } => {}
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
async fn live_source_matches_original_hot_and_cold_headers_without_reading_members() -> Result<()> {
    use sea_orm::{ConnectionTrait, Database};
    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        let prepared = h.effect(vec![start("source-work", true)], vec![]).await?;
        let original = prepared
            .display
            .as_ref()
            .context("prepared display")?
            .blocks[0]
            .header
            .clone();
        persist(&h, &prepared).await?;
        let path = env
            .runtime
            .store
            .session_paths(&h.thread.workspace_id, &h.thread.id)?
            .history_database();
        let db = Database::connect(format!("sqlite://{}?mode=rw", path.display())).await?;
        let mut hot_feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let hot_reader = hot_feed.reader().clone();
        // Both leases validate the real schema first. Removing the table afterwards makes
        // any subsequent member query fail; headers must suffice for source delivery.
        db.execute_unprepared(
            "ALTER TABLE conversation_display_members RENAME TO unavailable_members",
        )
        .await?;
        let hot = hot_reader.initial_timeline(demand(1)).await;
        db.execute_unprepared(
            "ALTER TABLE unavailable_members RENAME TO conversation_display_members",
        )
        .await?;
        let hot = hot?.live.context("hot live window")?;
        assert_eq!(hot.blocks[0].id, original.id);
        assert_eq!(hot.blocks[0].source.as_ref(), Some(&original.source));
        hot_feed.close().await?;
        hot_reader.close().await?;
        env.runtime
            .thread_observations
            .observation_slot(&h.thread.id)
            .retire(&h.source);
        let mut cold_feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let cold_reader = cold_feed.reader().clone();
        db.execute_unprepared(
            "ALTER TABLE conversation_display_members RENAME TO unavailable_members",
        )
        .await?;
        let cold = cold_reader.initial_timeline(demand(1)).await;
        db.execute_unprepared(
            "ALTER TABLE unavailable_members RENAME TO conversation_display_members",
        )
        .await?;
        let cold = cold?.live.context("cold saved open header")?;
        assert!(!cold.execution_present);
        assert_eq!(cold.blocks, hot.blocks);
        assert_eq!(cold.blocks[0].source.as_ref(), Some(&original.source));
        cold_feed.close().await?;
        cold_reader.close().await?;
        db.close().await?;
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
            let prepared = h.content_available(vec![start(&t, false)]).await?;
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
