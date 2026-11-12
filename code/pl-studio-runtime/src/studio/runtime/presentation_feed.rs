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

#[cfg(test)]
mod tests;

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
