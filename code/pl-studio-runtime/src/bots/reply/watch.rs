//! One native feed, the same read lease, and one bounded target projection.

use super::content::{Coverage, FinalError, ReplyItem, decode_entry, demand, read_failure};
use super::projection::{ReplyProjection, gap};
use crate::studio::{ConversationEvent, ConversationFeed, ConversationReader, StudioRuntime};
use pl_protocol::{
    ChatBatch, ChatPlacement, ChatScope, ThreadNotification, ThreadSubscriptionUpdate, Turn,
    TurnState,
};
use std::future::Future;
use tokio_util::sync::CancellationToken;

/// A taken Chat frame remains owned here across cancellation of asynchronous body
/// reads. Only a completely decoded batch can publish its completions/current.
struct PendingChat {
    batch: ChatBatch,
    next: usize,
    items: Vec<ReplyItem>,
}

pub(super) struct ReplyWatch {
    feed: ConversationFeed,
    input_id: Option<String>,
    turn_id: Option<String>,
    projection: Option<ReplyProjection>,
    pending: Option<PendingChat>,
    before: Option<String>,
    chat_ready: bool,
    coverage: Coverage,
    state_revision: Option<u64>,
    state_epoch: Option<u64>,
    observed_turn: Option<Turn>,
}

impl ReplyWatch {
    pub(super) async fn open(runtime: &StudioRuntime, thread_id: &str) -> Result<Self, FinalError> {
        let feed = runtime
            .open_conversation_feed(thread_id, ChatScope::Main, demand())
            .await
            .map_err(|error| read_failure("bot conversation feed open failed", error))?;
        // No await after acquisition: the caller immediately owns both close duties.
        Ok(Self {
            feed,
            input_id: None,
            turn_id: None,
            projection: None,
            pending: None,
            before: None,
            chat_ready: false,
            coverage: Coverage::default(),
            state_revision: None,
            state_epoch: None,
            observed_turn: None,
        })
    }

    pub(super) fn reader(&self) -> ConversationReader {
        self.feed.reader().clone()
    }
    pub(super) fn preview(&self) -> Option<String> {
        self.projection.as_ref().and_then(ReplyProjection::preview)
    }
    pub(super) fn projection(&self) -> Option<ReplyProjection> {
        self.projection.clone()
    }
    pub(super) fn terminal(&self, turn_id: &str) -> Option<TurnState> {
        if self.turn_id.as_deref() != Some(turn_id) {
            return None;
        }
        self.projection.as_ref()?.terminal()
    }
    pub(super) fn observed_state(&self, turn_id: &str) -> Option<TurnState> {
        self.observed_turn
            .as_ref()
            .filter(|turn| turn.id == turn_id)
            .map(|turn| turn.state.clone())
    }

    /// Only canonical consumed-input routing selects a target, never current/last active.
    pub(super) async fn select_target(
        &mut self,
        runtime: &StudioRuntime,
        input_id: &str,
        turn_id: Option<&str>,
    ) -> Result<(), FinalError> {
        if self.input_id.as_deref() == Some(input_id) && self.turn_id.as_deref() == turn_id {
            return Ok(());
        }
        self.projection = None;
        self.input_id = Some(input_id.into());
        self.turn_id = turn_id.map(str::to_owned);
        self.reconnect(runtime).await?;
        self.ensure_coverage().await
    }

    pub(super) async fn ensure_coverage(&mut self) -> Result<(), FinalError> {
        if self.turn_id.is_none() {
            return Ok(());
        }
        while !self.chat_ready {
            self.receive().await?;
        }
        self.finish_pending().await?;
        while let Some(before) = self.before.clone() {
            let page = self
                .feed
                .reader()
                .load_older(&before, demand())
                .await
                .map_err(|error| read_failure("reply prefix recovery page failed", error))?;
            if page.placement != ChatPlacement::Prepend {
                return Err(gap("reply older page is not Prepend"));
            }
            self.stage(page)?;
            self.finish_pending().await?;
        }
        if let Some(projection) = &mut self.projection {
            projection.mark_covered();
        }
        self.qualify_terminal_cut().await?;
        Ok(())
    }

    /// Reconnection creates a new feed/Set and reconstructs only the reliable target.
    /// No public Core position, parsed cursor or old projection proves continuity.
    pub(super) async fn reconnect(&mut self, runtime: &StudioRuntime) -> Result<(), FinalError> {
        self.close().await?;
        let feed = runtime
            .open_conversation_feed(self.feed.thread_id(), ChatScope::Main, demand())
            .await
            .map_err(|error| read_failure("bot conversation feed reopen failed", error))?;
        self.feed = feed;
        self.projection = None;
        self.pending = None;
        self.before = None;
        self.chat_ready = false;
        self.coverage = Coverage::default();
        self.state_revision = None;
        self.state_epoch = None;
        self.observed_turn = None;
        Ok(())
    }

    /// Both futures remain task-owned; observation failure cancels new platform
    /// admission but drains an already admitted action to its real result.
    pub(super) async fn during<T>(
        &mut self,
        future: impl Future<Output = T>,
        action_cancel: Option<&CancellationToken>,
    ) -> (T, Option<FinalError>) {
        tokio::pin!(future);
        let mut failure = None;
        loop {
            let event = tokio::select! {
                result = &mut future => return (result, failure),
                event = self.receive(), if failure.is_none() => event,
            };
            if let Err(error) = event {
                self.feed.request_close();
                if let Some(cancel) = action_cancel {
                    cancel.cancel();
                }
                failure = Some(error);
            }
        }
    }

    pub(super) async fn receive(&mut self) -> Result<(), FinalError> {
        if self.pending.is_some() {
            self.finish_pending().await?;
            return self.qualify_terminal_cut().await;
        }
        let event = self
            .feed
            .recv()
            .await
            .map_err(|error| read_failure("bot conversation feed failed; new Set required", error))?
            .ok_or_else(|| gap("bot conversation feed ended before reply completed"))?;
        match event {
            ConversationEvent::State { update } => self.state(*update),
            ConversationEvent::Chat { batch } => {
                if (!self.chat_ready && batch.placement != ChatPlacement::Set)
                    || (self.chat_ready
                        && !matches!(
                            batch.placement,
                            ChatPlacement::Append | ChatPlacement::Update
                        ))
                {
                    return Err(gap("reply feed expected first Set then Append or Update"));
                }
                self.stage(*batch)?;
                self.finish_pending().await
            }
        }?;
        self.qualify_terminal_cut().await
    }

    async fn qualify_terminal_cut(&mut self) -> Result<(), FinalError> {
        let Some(cut) = self
            .projection
            .as_ref()
            .and_then(ReplyProjection::terminal_cut_to_qualify)
        else {
            return Ok(());
        };
        let source = pl_protocol::ChatSourceId::ForegroundTurn {
            turn_id: self
                .turn_id
                .clone()
                .ok_or_else(|| gap("terminal has no target"))?,
        };
        if self
            .reader()
            .source_ended_at(&source, cut)
            .await
            .map_err(|error| read_failure("terminal source cut qualification failed", error))?
            && let Some(projection) = &mut self.projection
        {
            projection.qualify_terminal_cut();
        }
        Ok(())
    }

    fn stage(&mut self, batch: ChatBatch) -> Result<(), FinalError> {
        if self.pending.is_some() {
            return Err(gap("reply pending batch overwritten"));
        }
        if batch.entries.len() > demand().max_items as usize {
            return Err(gap("reply batch exceeded its entry budget"));
        }
        if self.turn_id.is_some() {
            if batch.placement == ChatPlacement::Append {
                self.coverage.admit(&batch.entries)?;
            } else if batch.placement != ChatPlacement::Update {
                self.coverage.page(&batch.entries)?;
            }
        }
        self.pending = Some(PendingChat {
            batch,
            next: 0,
            items: Vec::new(),
        });
        Ok(())
    }

    async fn finish_pending(&mut self) -> Result<(), FinalError> {
        while let Some(pending) = &self.pending {
            if pending.next == pending.batch.entries.len() {
                break;
            }
            // Cancellation before this await returns leaves the original message
            // and its index intact. Retrying an immutable bounded read is idempotent.
            let item = if let Some(turn_id) = &self.turn_id {
                decode_entry(
                    self.feed.reader(),
                    &pending.batch.entries[pending.next],
                    turn_id,
                )
                .await?
            } else {
                None
            };
            let pending = self.pending.as_mut().expect("owned pending batch");
            if let Some(item) = item {
                let bytes = pending
                    .items
                    .iter()
                    .chain(std::iter::once(&item))
                    .try_fold(0usize, |size, item| size.checked_add(item.preview_bytes()));
                if bytes.is_none_or(|size| size > super::content::MAX_TURN_BODY_BYTES) {
                    return Err(FinalError::Attention(
                        "pending reply batch exceeded its body budget".into(),
                    ));
                }
                pending.items.push(item);
            }
            pending.next += 1;
        }
        let Some(pending) = self.pending.take() else {
            return Ok(());
        };
        let ChatBatch {
            placement,
            before,
            current,
            ..
        } = pending.batch;
        if matches!(placement, ChatPlacement::Set | ChatPlacement::Prepend) {
            if let Some(token) = &before {
                self.coverage.cursor(token)?;
            }
            self.before = before;
        }
        if placement == ChatPlacement::Set {
            self.chat_ready = true;
            self.projection = self.turn_id.as_deref().map(ReplyProjection::new);
        }
        if let Some(projection) = &mut self.projection {
            // Accept all completed members before retiring their current previews.
            projection.apply(placement, pending.items)?;
            if let Some(current) = current {
                projection.set_current(current)?;
            }
            projection.validate_budget()?;
            if self.before.is_none() {
                projection.mark_covered();
            }
            if let Some(turn) = &self.observed_turn {
                projection.observe_terminal(&turn.state);
            }
        }
        Ok(())
    }

    fn state(&mut self, update: ThreadSubscriptionUpdate) -> Result<(), FinalError> {
        match update {
            ThreadSubscriptionUpdate::Snapshot { snapshot } => {
                if snapshot.thread.id != self.feed.thread_id() || self.state_revision.is_some() {
                    return Err(gap("reply state baseline identity or continuity conflict"));
                }
                self.state_revision = Some(snapshot.revision);
                if let Some(turn) = snapshot.active_turn {
                    self.observe_turn(turn)?;
                }
            }
            ThreadSubscriptionUpdate::Notification { notification } => {
                if notification.thread_id != self.feed.thread_id()
                    || self.state_revision != Some(notification.base_revision)
                    || notification.revision <= notification.base_revision
                    || self
                        .state_epoch
                        .is_some_and(|epoch| epoch != notification.epoch)
                {
                    return Err(gap("reply state stream continuity lost"));
                }
                match notification.notification {
                    ThreadNotification::Lagged { .. } => {
                        return Err(gap("reply state stream lagged; new baseline required"));
                    }
                    ThreadNotification::TurnStarted { turn }
                    | ThreadNotification::TurnUpdated { turn }
                    | ThreadNotification::TurnCompleted { turn } => self.observe_turn(turn)?,
                    ThreadNotification::InteractionChanged { .. }
                    | ThreadNotification::ThreadRuntimeUpdated { .. }
                    | ThreadNotification::ActivityChanged { .. }
                    | ThreadNotification::StorageChanged { .. } => {}
                }
                self.state_epoch = Some(notification.epoch);
                self.state_revision = Some(notification.revision);
            }
        }
        Ok(())
    }

    fn observe_turn(&mut self, turn: Turn) -> Result<(), FinalError> {
        if turn.thread_id != self.feed.thread_id() {
            return Err(gap("reply observed Turn belongs to another Thread"));
        }
        if self.turn_id.as_deref() != Some(&turn.id) {
            return Ok(());
        }
        if let Some(previous) = &self.observed_turn
            && (turn.revision < previous.revision
                || turn.revision == previous.revision && turn != *previous)
        {
            return Err(gap("reply observed Turn revision conflict"));
        }
        if let Some(projection) = &mut self.projection {
            projection.observe_terminal(&turn.state);
        }
        self.observed_turn = Some(turn);
        Ok(())
    }

    pub(super) async fn close(&mut self) -> Result<(), FinalError> {
        let reader = self.reader();
        self.feed.request_close();
        let feed = self
            .feed
            .close()
            .await
            .map_err(|error| read_failure("bot conversation feed close failed", error));
        let reader = reader
            .close()
            .await
            .map_err(|error| read_failure("bot conversation reader close failed", error));
        match (feed, reader) {
            (Ok(()), result) | (result, Ok(())) => result,
            (Err(first), Err(second)) => Err(FinalError::Attention(format!(
                "reply close failed on both owners: {first:?}; {second:?}"
            ))),
        }
    }
}

#[cfg(test)]
#[path = "tests.rs"]
mod tests;
