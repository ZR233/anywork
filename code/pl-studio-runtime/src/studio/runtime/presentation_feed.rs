//! Display-prefix framing, independent of atomic H and transport credit.
//!
//! This is a per-reader delivery position, not a producer, registry, or reliable event queue.
//! The original owner supplies a fixed P/live cut and its pending/SQLite heads.

use super::{
    ConversationFeed, ConversationReader, StudioRuntime, conversation_reader::resync,
    presentation_reader::encoded_size,
};
use anyhow::{Result, ensure};
use pl_core::chat::ChatError;
use pl_protocol::{
    ChatPlacement, DisplayBlock, LiveDisplayWindow, PRESENTATION_VERSION, ReadDemand, TimelineBatch,
};

#[derive(Debug, Clone)]
pub enum TimelineEvent {
    Timeline { batch: Box<TimelineBatch> },
}

/// Presentation-only facade over the original read/close owner. State has a separate feed.
pub struct TimelineFeed {
    shared: ConversationFeed,
    initial: Option<TimelineBatch>,
    delivery: TimelineDelivery,
    demand: ReadDemand,
    seen_serial: u64,
    last_live: Option<LiveDisplayWindow>,
}

impl StudioRuntime {
    pub async fn open_timeline_feed(
        &self,
        thread_id: &str,
        demand: ReadDemand,
    ) -> Result<TimelineFeed> {
        let shared = self
            .open_feed_resources(thread_id, pl_protocol::ChatScope::Main, demand, false)
            .await?;
        // Progress registration already exists before this original read lease captures P0.
        let initial = shared.reader().initial_timeline(demand).await?;
        let through = initial.through_pos;
        let last_live = initial.live.clone();
        Ok(TimelineFeed {
            shared,
            initial: Some(initial),
            delivery: TimelineDelivery::new(through),
            demand,
            seen_serial: 0,
            last_live,
        })
    }
}

impl TimelineFeed {
    pub fn thread_id(&self) -> &str {
        self.shared.thread_id()
    }
    pub fn subscription_id(&self) -> &str {
        self.shared.subscription_id()
    }
    pub fn reader(&self) -> &ConversationReader {
        self.shared.reader()
    }
    pub fn cancellation_token(&self) -> tokio_util::sync::CancellationToken {
        self.shared.cancellation_token()
    }
    pub fn request_close(&self) {
        self.shared.request_close();
    }
    pub async fn close(&mut self) -> Result<()> {
        self.request_close();
        self.initial = None;
        self.last_live = None;
        self.delivery.target = None;
        self.shared.close().await
    }
    pub async fn load_older(&self, before: &str, demand: ReadDemand) -> Result<TimelineBatch> {
        self.reader().load_timeline_older(before, demand).await
    }
    pub async fn load_live_older(
        &self,
        before: &str,
        demand: ReadDemand,
    ) -> Result<LiveDisplayWindow> {
        self.reader().load_live_older(before, demand).await
    }
    pub async fn receive(&mut self) -> Result<TimelineEvent> {
        let result = self.receive_inner().await;
        if let Err(error) = &result {
            if error
                .downcast_ref::<pl_protocol::studio::StudioError>()
                .is_some_and(|error| error.reason() == Some("conversationResyncRequired"))
            {
                self.reader().invalidate();
            }
            self.initial = None;
            self.last_live = None;
            self.delivery.target = None;
            self.shared.finish_production();
        }
        result
    }
    async fn receive_inner(&mut self) -> Result<TimelineEvent> {
        loop {
            self.reader().ensure()?;
            ensure!(
                !self.shared.cancellation_token().is_cancelled(),
                ChatError::Cancelled
            );
            if let Some(batch) = self.initial.take() {
                return Ok(TimelineEvent::Timeline {
                    batch: Box::new(batch),
                });
            }
            if self.delivery.target_through().is_none()
                && let Some(source) = self.shared.current_progress()
                && source.serial > self.seen_serial
            {
                self.seen_serial = source.serial;
                // Do not retain obsolete CurrentState/body references while waiting on transport.
                drop(source);
                let cut = self
                    .reader()
                    .capture_display(None, self.demand.max_items as usize + 1, Some(u64::MAX), 0)
                    .await?;
                let tokens = self.reader().presentation_tokens().await?;
                // A split handoff can finish with a pure-live frame at Pt. Reserve its widest
                // from_pos now, including decimal-width growth since the last delivered position.
                let reserve = TimelineBatch {
                    presentation_version: PRESENTATION_VERSION,
                    placement: ChatPlacement::Append,
                    blocks: Vec::new(),
                    before: None,
                    from_pos: Some(cut.published),
                    through_pos: cut.published,
                    live: None,
                };
                let bytes = (self.demand.max_bytes as usize)
                    .checked_sub(encoded_size(&reserve)?.saturating_sub(4))
                    .ok_or_else(invalid_page)?;
                let live = self.reader().cut_live(
                    &cut,
                    ReadDemand {
                        max_bytes: bytes as u32,
                        ..self.demand
                    },
                    &tokens,
                )?;
                if cut.published > self.delivery.delivered()
                    || self.last_live.as_ref() != Some(&live)
                {
                    self.delivery.capture(live)?;
                }
            }
            if let Some(through) = self.delivery.target_through() {
                let mut heads = if through > self.delivery.delivered() {
                    self.reader()
                        .timeline_append_heads(self.delivery.delivered(), through, self.demand)
                        .await?
                } else {
                    Vec::new()
                };
                let mut bytes = 0;
                let mut count = 0;
                for head in &heads {
                    let envelope = TimelineBatch {
                        presentation_version: PRESENTATION_VERSION,
                        placement: ChatPlacement::Append,
                        blocks: Vec::new(),
                        before: None,
                        from_pos: Some(self.delivery.delivered()),
                        through_pos: head.history_pos,
                        live: None,
                    };
                    let next = bytes + encoded_size(head)? + usize::from(count > 0);
                    if encoded_size(&envelope)? + next > self.demand.max_bytes as usize {
                        break;
                    }
                    bytes = next;
                    count += 1;
                }
                ensure!(heads.is_empty() || count > 0, invalid_page());
                heads.truncate(count);
                let batch = self.delivery.append(heads, self.demand)?;
                if let Some(live) = &batch.live {
                    self.last_live = Some(live.clone());
                }
                self.reader().ensure()?;
                ensure!(
                    !self.shared.cancellation_token().is_cancelled(),
                    ChatError::Cancelled
                );
                return Ok(TimelineEvent::Timeline {
                    batch: Box::new(batch),
                });
            }
            // Only publication/current changes wake this facade. State has its own observation.
            self.shared.wait_change().await?;
        }
    }
}

/// A slow consumer retains one bounded target window until that fixed prefix is delivered.
pub(super) struct TimelineDelivery {
    delivered: u64,
    target: Option<LiveDisplayWindow>,
}

impl TimelineDelivery {
    pub(super) fn new(delivered: u64) -> Self {
        Self {
            delivered,
            target: None,
        }
    }

    pub(super) fn delivered(&self) -> u64 {
        self.delivered
    }

    pub(super) fn target_through(&self) -> Option<u64> {
        self.target.as_ref().map(|live| live.history_through)
    }

    /// Called only after the previous target is completely consumed. New watch values cannot
    /// replace a partly delivered target and strand its live blocks.
    pub(super) fn capture(&mut self, live: LiveDisplayWindow) -> Result<()> {
        ensure!(self.target.is_none(), resync());
        ensure!(live.history_through >= self.delivered, resync());
        self.target = Some(live);
        Ok(())
    }

    /// Accept one contiguous frozen prefix selected by the original presentation reader.
    /// State advances only after every invariant and the actual encoded budget have passed.
    pub(super) fn append(
        &mut self,
        blocks: Vec<DisplayBlock>,
        demand: ReadDemand,
    ) -> Result<TimelineBatch> {
        demand.validate(1)?;
        let target = self.target.as_ref().ok_or_else(resync)?;
        ensure!(blocks.len() <= demand.max_items as usize, invalid_page());
        let mut through = self.delivered;
        for block in &blocks {
            let expected = through.checked_add(1).ok_or_else(resync)?;
            ensure!(
                block.history_pos == expected && block.history_pos <= target.history_through,
                resync()
            );
            through = block.history_pos;
        }
        ensure!(
            through > self.delivered || through == target.history_through,
            resync()
        );
        let complete = through == target.history_through;
        let mut batch = TimelineBatch {
            presentation_version: PRESENTATION_VERSION,
            placement: ChatPlacement::Append,
            blocks,
            before: None,
            from_pos: Some(self.delivered),
            through_pos: through,
            live: complete.then(|| target.clone()),
        };
        // A head and the target window may each fit while their combination does not. Deliver the
        // head without replacing remaining live, then deliver a pure-live frame at the same P.
        let mut attached = complete;
        if encoded_size(&batch)? > demand.max_bytes as usize && !batch.blocks.is_empty() && complete
        {
            batch.live = None;
            attached = false;
        }
        ensure!(
            encoded_size(&batch)? <= demand.max_bytes as usize,
            invalid_page()
        );
        self.delivered = through;
        if attached {
            self.target = None;
        }
        Ok(batch)
    }
}

fn invalid_page() -> anyhow::Error {
    ChatError::InvalidDemand("timeline page exceeds its item or encoded byte budget".into()).into()
}

/// Set captures history and live at the same P. Prepend never carries live and never advances
/// TimelineDelivery. The caller creates the continuation using the original read qualification.
pub(super) fn history_batch(
    placement: ChatPlacement,
    blocks: Vec<DisplayBlock>,
    before: Option<String>,
    through: u64,
    live: Option<LiveDisplayWindow>,
    demand: ReadDemand,
) -> Result<TimelineBatch> {
    demand.validate(1)?;
    ensure!(
        matches!(placement, ChatPlacement::Set | ChatPlacement::Prepend),
        resync()
    );
    ensure!(
        live.as_ref().is_none_or(|live| {
            matches!(placement, ChatPlacement::Set) && live.history_through == through
        }),
        resync()
    );
    ensure!(
        !matches!(placement, ChatPlacement::Set) || live.is_some(),
        resync()
    );
    let mut previous = 0;
    for block in &blocks {
        ensure!(
            block.history_pos > previous
                && block.history_pos <= through
                && (previous == 0 || previous.checked_add(1) == Some(block.history_pos)),
            resync()
        );
        previous = block.history_pos;
    }
    ensure!(
        !matches!(placement, ChatPlacement::Set) || previous == through,
        resync()
    );
    let batch = TimelineBatch {
        presentation_version: PRESENTATION_VERSION,
        placement,
        blocks,
        before,
        from_pos: None,
        through_pos: through,
        live,
    };
    ensure!(
        batch.blocks.len() <= demand.max_items as usize
            && encoded_size(&batch)? <= demand.max_bytes as usize,
        invalid_page()
    );
    Ok(batch)
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::{DisplayBlockBody, DisplayBlockRef, LiveDisplayBlock};

    fn demand(max_items: u32) -> ReadDemand {
        ReadDemand {
            max_items,
            max_bytes: 16 * 1024,
        }
    }

    fn body(id: &str) -> DisplayBlockBody {
        DisplayBlockBody::Work {
            timing: Default::default(),
            members: DisplayBlockRef {
                database_id: "database".into(),
                block_id: id.into(),
            },
        }
    }

    fn block(pos: u64) -> DisplayBlock {
        let id = format!("block-{pos}");
        DisplayBlock {
            body: body(&id),
            id,
            history_pos: pos,
        }
    }

    fn live(through: u64, ids: &[u64]) -> LiveDisplayWindow {
        LiveDisplayWindow {
            revision: 7,
            history_through: through,
            execution_present: true,
            current_work_id: ids.last().map(|order| format!("block-{order}")),
            blocks: ids
                .iter()
                .map(|order| {
                    let id = format!("block-{order}");
                    LiveDisplayBlock {
                        has_unfinished_members: false,
                        thinking_summary: None,
                        body: body(&id),
                        id,
                        block_order: *order,
                        source: None,
                        state: if ids.last() == Some(order) {
                            pl_protocol::DisplayBlockState::Open
                        } else {
                            pl_protocol::DisplayBlockState::Sealed
                        },
                    }
                })
                .collect(),
            older: None,
        }
    }

    #[test]
    fn split_handoff_keeps_fixed_target_and_unpublished_live_until_last_frame() -> Result<()> {
        let mut delivery = TimelineDelivery::new(0);
        let target = live(2, &[3]);
        delivery.capture(target.clone())?;
        let first = delivery.append(vec![block(1)], demand(1))?;
        assert_eq!(first.from_pos, Some(0));
        assert_eq!(first.through_pos, 1);
        assert!(first.live.is_none());
        // A newer watch value is not allowed to overtake an already captured target.
        assert!(delivery.capture(live(5, &[6])).is_err());
        assert_eq!(delivery.target_through(), Some(2));
        let second = delivery.append(vec![block(2)], demand(1))?;
        assert_eq!(second.from_pos, Some(1));
        assert_eq!(second.through_pos, 2);
        assert_eq!(second.live, Some(target));
        assert_eq!(delivery.delivered(), 2);
        assert_eq!(delivery.target_through(), None);
        // Coalesced watch notifications do not define the frozen prefix: the next read fills 3..5.
        delivery.capture(live(5, &[6]))?;
        for pos in 3..=5 {
            let batch = delivery.append(vec![block(pos)], demand(1))?;
            assert_eq!(batch.blocks[0].history_pos, pos);
            assert_eq!(batch.live.is_some(), pos == 5);
        }
        Ok(())
    }

    #[test]
    fn unchanged_p_delivers_live_without_history_and_without_requiring_atomic_h() -> Result<()> {
        let mut delivery = TimelineDelivery::new(4);
        let mut changed = live(4, &[5]);
        changed.blocks[0].thinking_summary = Some("new bounded thought".into());
        changed.blocks[0].has_unfinished_members = true;
        delivery.capture(changed.clone())?;
        let frame = delivery.append(Vec::new(), demand(1))?;
        assert!(frame.blocks.is_empty());
        assert_eq!(frame.from_pos, Some(4));
        assert_eq!(frame.through_pos, 4);
        assert_eq!(frame.live, Some(changed));
        // Removing a reliably empty text segment also needs no fabricated history position.
        delivery.capture(live(4, &[]))?;
        assert_eq!(
            delivery.append(Vec::new(), demand(1))?.live,
            Some(live(4, &[]))
        );
        Ok(())
    }

    #[test]
    fn rejected_prefix_and_byte_budget_do_not_advance_delivery() -> Result<()> {
        let mut delivery = TimelineDelivery::new(0);
        delivery.capture(live(2, &[3]))?;
        assert!(delivery.append(vec![], demand(1)).is_err());
        assert!(delivery.append(vec![block(2)], demand(1)).is_err());
        assert!(
            delivery
                .append(vec![block(1), block(2)], demand(1))
                .is_err()
        );
        let tiny = ReadDemand {
            max_items: 1,
            max_bytes: 1,
        };
        assert!(delivery.append(vec![block(1)], tiny).is_err());
        assert_eq!(delivery.delivered(), 0);
        assert_eq!(delivery.target_through(), Some(2));
        delivery.append(vec![block(1)], demand(1))?;
        assert!(delivery.append(vec![block(2)], tiny).is_err());
        assert_eq!(delivery.delivered(), 1);
        assert_eq!(delivery.target_through(), Some(2));
        let final_frame = delivery.append(vec![block(2)], demand(1))?;
        assert!(final_frame.live.is_some());
        Ok(())
    }

    #[test]
    fn set_is_same_cut_and_prepend_cannot_replace_live_or_change_stream_position() -> Result<()> {
        let delivery = TimelineDelivery::new(9);
        let set = history_batch(
            ChatPlacement::Set,
            vec![block(9)],
            Some("older".into()),
            9,
            Some(live(9, &[10])),
            demand(1),
        )?;
        assert_eq!(set.through_pos, 9);
        assert!(set.from_pos.is_none());
        assert!(
            history_batch(
                ChatPlacement::Set,
                vec![block(9)],
                None,
                9,
                Some(live(10, &[11])),
                demand(1),
            )
            .is_err()
        );
        assert!(
            history_batch(
                ChatPlacement::Prepend,
                vec![block(1)],
                None,
                9,
                Some(live(9, &[10])),
                demand(1),
            )
            .is_err()
        );
        let prepend = history_batch(
            ChatPlacement::Prepend,
            vec![block(1)],
            None,
            9,
            None,
            demand(1),
        )?;
        assert!(prepend.live.is_none());
        assert_eq!(delivery.delivered(), 9);
        Ok(())
    }

    #[test]
    fn final_head_and_live_can_use_separate_bounded_frames_at_the_same_p() -> Result<()> {
        let target = live(1, &[2, 3, 4]);
        let shell = TimelineBatch {
            presentation_version: PRESENTATION_VERSION,
            placement: ChatPlacement::Append,
            blocks: vec![],
            before: None,
            from_pos: Some(1),
            through_pos: 1,
            live: Some(target.clone()),
        };
        let demand = ReadDemand {
            max_items: 1,
            max_bytes: encoded_size(&shell)? as u32,
        };
        let mut delivery = TimelineDelivery::new(0);
        delivery.capture(target.clone())?;
        let first = delivery.append(vec![block(1)], demand)?;
        assert_eq!(first.through_pos, 1);
        assert!(first.live.is_none());
        assert_eq!(delivery.target_through(), Some(1));
        let last = delivery.append(vec![], demand)?;
        assert_eq!(last.from_pos, Some(1));
        assert_eq!(last.through_pos, 1);
        assert_eq!(last.live, Some(target));
        assert!(delivery.target_through().is_none());
        Ok(())
    }

    #[tokio::test]
    async fn empty_production_feed_shares_query_qualification_and_close_wakes_receive() -> Result<()>
    {
        use crate::runtime_test_support::Environment;
        use futures::poll;
        use std::task::Poll;
        let env = Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = env
                .runtime
                .create_thread(&env.project.id, "empty display feed")
                .await?;
            let mut feed = env
                .runtime
                .open_timeline_feed(&thread.id, demand(1))
                .await?;
            let TimelineEvent::Timeline { batch } = feed.receive().await?;
            assert_eq!(batch.placement, ChatPlacement::Set);
            assert!(batch.blocks.is_empty());
            assert_eq!(batch.through_pos, 0);
            let initial_live = batch.live.expect("Set must carry live at its P");
            assert!(initial_live.blocks.is_empty());
            assert!(
                initial_live.execution_present,
                "create_thread installs the real resident owner, even before its first work block"
            );
            let mut state = env.runtime.open_conversation_state_feed(&thread.id).await?;
            assert!(matches!(
                state.recv().await?,
                Some(pl_protocol::ThreadSubscriptionUpdate::Snapshot { .. })
            ));
            state.close().await?;
            let reader = feed.reader().clone();
            let cancellation = feed.cancellation_token();
            {
                let receiving = feed.receive();
                tokio::pin!(receiving);
                assert!(matches!(poll!(&mut receiving), Poll::Pending));
                // Query admission is not the receive lock, and no stream ACK is necessary.
                reader.read_business_refs().await?;
                cancellation.cancel();
                assert!(matches!(
                    receiving
                        .await
                        .expect_err("close must wake receive")
                        .downcast_ref::<ChatError>(),
                    Some(ChatError::Cancelled)
                ));
            }
            feed.close().await?;
            reader.read_business_refs().await?;
            reader.close().await?;
            assert!(reader.read_business_refs().await.is_err());
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    mod lifecycle {
        use super::{production::timeline, production::work_reference, *};
        use crate::{
            runtime_test_support::Environment,
            studio::runtime::conversation_feed::tests::completed_runs::{Harness, start},
        };
        use anyhow::Context;
        use futures::poll;
        use pl_protocol::DisplayMemberWindow;
        use std::task::Poll;

        #[tokio::test]
        async fn parked_feed_and_member_receives_do_not_block_queries_and_close_only_their_observation()
        -> Result<()> {
            let env = Environment::new(vec![], vec![]).await?;
            let result = async {
                let mut h = Harness::new(&env).await?;
                h.effect(vec![start("reasoning", true)], vec![]).await?;
                let mut feed = env
                    .runtime
                    .open_timeline_feed(&h.thread.id, demand(1))
                    .await?;
                let initial = timeline(&mut feed).await?;
                let reference = work_reference(&initial.live.context("live Work")?)?;
                let mut state = env
                    .runtime
                    .open_conversation_state_feed(&h.thread.id)
                    .await?;
                assert!(matches!(
                    state.recv().await?,
                    Some(pl_protocol::ThreadSubscriptionUpdate::Snapshot { .. })
                ));
                state.close().await?;
                let reader = feed.reader().clone();
                let feed_cancel = feed.cancellation_token();
                {
                    let receiving = feed.receive();
                    tokio::pin!(receiving);
                    assert!(matches!(poll!(&mut receiving), Poll::Pending));
                    reader.read_business_refs().await?;
                    let mut members = reader
                        .open_display_members(
                            reference.clone(),
                            DisplayMemberWindow::Latest,
                            demand(1),
                        )
                        .await?;
                    let first = members
                        .next()
                        .await?
                        .context("member query while feed waits")?;
                    assert_eq!(first.entries.len(), 1);
                    let cancel = members.cancellation_token();
                    {
                        let next = members.next();
                        tokio::pin!(next);
                        assert!(matches!(poll!(&mut next), Poll::Pending));
                        reader.read_business_refs().await?;
                        cancel.cancel();
                        assert!(matches!(
                            next.await
                                .expect_err("local member close")
                                .downcast_ref::<ChatError>(),
                            Some(ChatError::Cancelled)
                        ));
                    }
                    members.close().await?;
                    reader.read_business_refs().await?;
                    feed_cancel.cancel();
                    assert!(matches!(
                        receiving
                            .await
                            .expect_err("local feed close")
                            .downcast_ref::<ChatError>(),
                        Some(ChatError::Cancelled)
                    ));
                }
                feed.request_close();
                feed.close().await?;
                reader.read_business_refs().await?;
                let mut independent = reader
                    .open_display_members(reference, DisplayMemberWindow::Latest, demand(1))
                    .await?;
                assert_eq!(
                    independent
                        .next()
                        .await?
                        .context("reader survives producer close")?
                        .entries
                        .len(),
                    1
                );
                // Only the outer full owner closes this independent qualification.
                reader.request_close();
                reader.close().await?;
                assert!(independent.next().await.is_err());
                independent.close().await?;
                assert!(reader.read_business_refs().await.is_err());
                Ok(())
            }
            .await;
            env.finish(result).await
        }
    }

    mod live_cursor {
        use super::production::{timeline, work_reference};
        use super::*;
        use crate::{
            runtime_test_support::Environment,
            studio::runtime::conversation_feed::tests::completed_runs::{Harness, finish, start},
        };
        use anyhow::Context;
        use pl_protocol::DisplayMemberWindow;

        #[tokio::test]
        async fn live_cursor_survives_member_status_change_and_only_structure_makes_it_stale()
        -> Result<()> {
            let env = Environment::new(vec![], vec![]).await?;
            let result = async {
                let mut h = Harness::new(&env).await?;
                h.effect(vec![start("earlier-body", false)], vec![]).await?;
                h.content_available(vec![start("earlier-body", false)])
                    .await?;
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
                h.content_available(vec![start("body", false)]).await?;
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
    }

    mod position_width {
        use super::{production::timeline, *};
        use crate::{
            runtime_test_support::Environment,
            studio::runtime::conversation_feed::tests::completed_runs::{Harness, finish, start},
        };
        use anyhow::Context;
        use std::collections::BTreeSet;

        async fn handoff_at_decimal_boundary(delivered: u64) -> Result<()> {
            let env = Environment::new(vec![], vec![]).await?;
            let result = async {
                let mut h = Harness::new(&env).await?;
                // One initial visible Single, followed by Work/Single pairs, produces the odd prefix.
                // Every separator has actual nonempty content and its own reliable content phase.
                assert_eq!(delivered % 2, 1);
                h.effect(vec![start("seed-initial", false)], vec![]).await?;
                h.content_available(vec![start("seed-initial", false)])
                    .await?;
                h.effect(vec![], vec![finish("seed-initial", false, "initial")?])
                    .await?;
                for i in 0..(delivered - 1) / 2 {
                    let work = format!("seed-work-{i}");
                    let text = format!("seed-text-{i}");
                    h.effect(vec![start(&work, true)], vec![]).await?;
                    h.effect(vec![], vec![finish(&work, true, "finished")?])
                        .await?;
                    h.effect(vec![start(&text, false)], vec![]).await?;
                    h.content_available(vec![start(&text, false)]).await?;
                    h.effect(vec![], vec![finish(&text, false, "separator")?])
                        .await?;
                }
                h.effect(vec![start("handoff-work", true)], vec![]).await?;
                h.effect(vec![], vec![finish("handoff-work", true, "finished")?])
                    .await?;
                let generous = ReadDemand {
                    max_items: 8,
                    max_bytes: pl_protocol::CHAT_BATCH_MAX_BYTES,
                };
                let mut feed = env
                    .runtime
                    .open_timeline_feed(&h.thread.id, generous)
                    .await?;
                let initial = timeline(&mut feed).await?;
                assert_eq!(initial.through_pos, delivered);
                let retiring_id = initial
                    .live
                    .as_ref()
                    .context("initial live Work")?
                    .blocks
                    .last()
                    .context("Work waiting for a reliable boundary")?
                    .id
                    .clone();

                // The first text begins the handoff, and the unfinished text prefix holds all eight
                // subsequent live heads. Long but bounded provider identities make that window larger
                // than the initial history page, without loading or padding any content body.
                let starts: Vec<_> = (0..8)
                    .map(|i| start(&format!("pending-text-{i}-{}", "p".repeat(512)), false))
                    .collect();
                h.effect(starts.clone(), vec![]).await?;
                h.content_available(starts).await?;
                let cut = feed
                    .reader()
                    .capture_display(None, 9, Some(u64::MAX), 0)
                    .await?;
                let target = delivered + 1;
                assert_eq!(cut.published, target);
                let tokens = feed.reader().presentation_tokens().await?;
                let full_live = feed.reader().cut_live(&cut, generous, &tokens)?;
                assert_eq!(full_live.blocks.len(), 8);
                assert!(full_live.older.is_none());

                let old_reserve = TimelineBatch {
                    presentation_version: PRESENTATION_VERSION,
                    placement: ChatPlacement::Append,
                    blocks: Vec::new(),
                    before: None,
                    from_pos: Some(delivered),
                    through_pos: target,
                    live: Some(full_live.clone()),
                };
                let tight_bytes = encoded_size(&old_reserve)? as u32;
                let final_full = TimelineBatch {
                    from_pos: Some(target),
                    ..old_reserve
                };
                assert_eq!(encoded_size(&final_full)?, tight_bytes as usize + 1);
                assert!(
                    encoded_size(&initial)? <= tight_bytes as usize,
                    "initial={} tight={tight_bytes}",
                    encoded_size(&initial)?
                );
                assert!(tight_bytes <= generous.max_bytes);
                // Tighten only this private fixture's demand after the exact wire size is known. The
                // already delivered Set also fits the same ceiling; source, reader, cut and receive path
                // are real. No owner, timeline target, or delivery position is synthesized.
                feed.demand = ReadDemand {
                    max_bytes: tight_bytes,
                    ..generous
                };

                let mut accepted_ids = Vec::new();
                let mut final_live = None;
                let mut previous = delivered;
                for _ in 0..3 {
                    let batch = timeline(&mut feed).await?;
                    assert!(encoded_size(&batch)? <= tight_bytes as usize);
                    assert_eq!(batch.from_pos, Some(previous));
                    assert!(batch.through_pos >= previous && batch.through_pos <= target);
                    previous = batch.through_pos;
                    accepted_ids.extend(batch.blocks.iter().map(|block| block.id.clone()));
                    if let Some(live) = batch.live {
                        assert_eq!(batch.through_pos, target);
                        final_live = Some(live);
                        break;
                    }
                    assert_eq!(feed.delivery.target_through(), Some(target));
                }
                let live = final_live
                    .context("the captured target must finish, not terminate on demand")?;
                assert_eq!(accepted_ids, [retiring_id]);
                assert_eq!(live.history_through, target);
                assert_eq!(live.revision, cut.revision);
                assert!(
                    live.blocks.len() < full_live.blocks.len(),
                    "reserve must reduce the page, not widen the budget"
                );
                assert!(
                    live.older.is_some(),
                    "unselected live heads must remain queryable"
                );
                assert_eq!(feed.delivery.delivered(), target);
                assert!(feed.delivery.target_through().is_none());

                let mut ids = live
                    .blocks
                    .iter()
                    .map(|head| head.id.clone())
                    .collect::<BTreeSet<_>>();
                let mut before = live.older;
                while let Some(cursor) = before {
                    let older = feed.reader().load_live_older(&cursor, feed.demand).await?;
                    assert!(encoded_size(&older)? <= tight_bytes as usize);
                    assert_eq!(
                        (older.history_through, older.revision),
                        (target, cut.revision)
                    );
                    ids.extend(older.blocks.into_iter().map(|head| head.id));
                    before = older.older;
                }
                assert_eq!(
                    ids,
                    full_live.blocks.into_iter().map(|head| head.id).collect()
                );
                feed.close().await?;
                feed.reader().close().await?;
                Ok(())
            }
            .await;
            env.finish(result).await
        }

        #[tokio::test]
        async fn handoff_budget_remains_bounded_across_9_to_10_with_multiple_live_heads()
        -> Result<()> {
            handoff_at_decimal_boundary(9).await
        }

        #[tokio::test]
        async fn handoff_budget_remains_bounded_across_99_to_100_with_multiple_live_heads()
        -> Result<()> {
            handoff_at_decimal_boundary(99).await
        }
    }

    mod production {
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
        async fn v364_accepted_parent_text_seals_work_once_and_survives_cold_display_read()
        -> Result<()> {
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
            timing,
            members: old_members,
        } = &hot.blocks[0].body
        else {
            panic!("frozen prior Work")
        };
        assert!(timing.finished_at.is_some());
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
            DisplayBlockBody::Work { timing: summary, .. } if summary.finished_at.is_none()
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
                let saved =
                    pl_core::chat::ChatHistory::item(&h.history, &completion.header.item_id)
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
                h.conversation.retire_test_execution();
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
                let DisplayBlockBody::Work {
                    timing: summary, ..
                } = &live.blocks[0].body
                else {
                    panic!("Work")
                };
                assert!(summary.finished_at.is_none());
                assert!(!live.blocks[0].has_unfinished_members);
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
                h.conversation.retire_test_execution();
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
                let DisplayBlockBody::Work {
                    timing: summary, ..
                } = &live.blocks[0].body
                else {
                    panic!("Work")
                };
                assert!(summary.finished_at.is_none());
                assert!(!live.blocks[0].has_unfinished_members);
                feed.reader().close().await?;
                feed.close().await?;
                Ok(())
            }
            .await;
            env.finish(result).await
        }

        #[tokio::test]
        async fn resting_member_observation_survives_execution_replacement_without_freezing_work()
        -> Result<()> {
            use pl_core::chat::{ChatError, ChatHistory};
            use pl_protocol::DisplayBlockState;

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
                h.conversation.retire_test_execution();
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
                    !page.sealed,
                    "execution retirement must not seal a mutable business block"
                );
                assert_eq!(page.revision, before.open[0].revision);
                assert_eq!(page.entries, [expected[1].clone()]);
                assert_eq!(page.before, Some(2));
                assert!(futures::poll!(Box::pin(latest.next()).as_mut()).is_pending());
                let mut older = reader
                    .open_display_members(
                        reference.clone(),
                        DisplayMemberWindow::Before { member_order: 2 },
                        demand(1),
                    )
                    .await?;
                let prefix = older.next().await?.context("fixed cold prefix")?;
                assert!(!prefix.sealed);
                assert_eq!(prefix.entries, [expected[0].clone()]);
                assert!(prefix.before.is_none());
                assert!(futures::poll!(Box::pin(older.next()).as_mut()).is_pending());
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
                let unchanged = captured_cold
                    .next()
                    .await?
                    .context("same Store after execution replacement")?;
                assert_eq!(unchanged.entries, [expected[1].clone()]);
                assert!(!unchanged.sealed);
                captured_cold.close().await?;
                assert!(futures::poll!(Box::pin(latest.next()).as_mut()).is_pending());
                latest.close().await?;
                reader.close().await?;
                feed.close().await?;
                Ok(())
            }
            .await;
            env.finish(result).await
        }

        #[tokio::test]
        async fn hot_terminal_members_watch_until_business_seal_with_unfinished_observation()
        -> Result<()> {
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
                let reference =
                    work_reference(&timeline(&mut feed).await?.live.context("hot tail")?)?;
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
                let DisplayBlockBody::Work {
                    timing: summary, ..
                } = &updated_live.blocks[0].body
                else {
                    anyhow::bail!("expected Work");
                };
                assert!(summary.finished_at.is_none());
                assert!(!updated_live.blocks[0].has_unfinished_members);
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
                        event => {
                            anyhow::bail!("text start manufactured atomic completion: {event:?}")
                        }
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
        async fn live_source_matches_original_hot_and_cold_headers_without_reading_members()
        -> Result<()> {
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
                h.conversation.retire_test_execution();
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
                        .open_display_members(
                            reference.clone(),
                            DisplayMemberWindow::Latest,
                            demand(1),
                        )
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
                h.conversation.retire_test_execution();
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
    }
}
