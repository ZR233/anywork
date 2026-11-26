//! Unified ConversationFeed and History change observations for one reply target.

use super::content::{FinalError, history_turn_snapshot, read_failure};
use super::projection::{ReplyProjection, gap};
use crate::TurnState;
use crate::studio::runtime::StudioRuntime;
use crate::timeline::{
    ConversationEvent, ConversationFeed, LiveStatusPhase, LiveStatusSnapshot, SessionMetaSnapshot,
};
use std::future::Future;
use tokio_util::sync::CancellationToken;

const BOT_FEED_LIMIT: u32 = 32;

pub(super) struct ReplyWatch {
    feed: ConversationFeed,
    history_reader: crate::history::HistoryReader,
    history_cut: crate::history::HistoryCut,
    meta: SessionMetaSnapshot,
    live_status: LiveStatusSnapshot,
    input_id: Option<String>,
    turn_id: Option<String>,
    projection: Option<ReplyProjection>,
    observed_state: Option<TurnState>,
}

impl ReplyWatch {
    pub(super) async fn open(runtime: &StudioRuntime, thread_id: &str) -> Result<Self, FinalError> {
        let feed = runtime
            .open_conversation_feed(thread_id, BOT_FEED_LIMIT)
            .await
            .map_err(|error| read_failure("bot feed open failed", error))?;
        let history_reader = match runtime
            .open_history_reader(thread_id, crate::history::HISTORY_PROTOCOL_VERSION)
            .await
        {
            Ok(reader) => reader,
            Err(error) => {
                feed.close().await;
                return Err(read_failure("bot history reader open failed", error));
            }
        };
        let history_cut = match history_reader.capture().await {
            Ok(cut) => cut,
            Err(error) => {
                feed.close().await;
                history_reader.close().await;
                return Err(read_failure("bot history capture failed", error));
            }
        };
        let meta = feed.session_meta_snapshot();
        let live_status = feed.live_status_snapshot();
        Ok(Self {
            feed,
            history_reader,
            history_cut,
            meta,
            live_status,
            input_id: None,
            turn_id: None,
            projection: None,
            observed_state: None,
        })
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
        if self.turn_id.as_deref() != Some(turn_id) {
            return None;
        }
        self.observed_state.clone()
    }

    pub(super) async fn select_target(
        &mut self,
        runtime: &StudioRuntime,
        input_id: &str,
        turn_id: Option<&str>,
    ) -> Result<(), FinalError> {
        if self.input_id.as_deref() == Some(input_id) && self.turn_id.as_deref() == turn_id {
            return Ok(());
        }
        self.input_id = Some(input_id.into());
        self.turn_id = turn_id.map(str::to_owned);
        self.projection = None;
        self.observed_state = None;
        self.reconnect(runtime).await
    }

    pub(super) async fn ensure_coverage(&mut self) -> Result<(), FinalError> {
        let Some(turn_id) = self.turn_id.clone() else {
            return Ok(());
        };
        if self.projection.as_ref().is_some_and(|projection| {
            projection.completed().is_ok() && projection.terminal().is_some()
        }) {
            self.refresh_current()?;
            return Ok(());
        }
        let cut = self
            .history_reader
            .capture()
            .await
            .map_err(|error| read_failure("bot history capture failed", error))?;
        let super::content::HistoryTurnSnapshot {
            mut items,
            terminal,
        } = history_turn_snapshot(&self.history_reader, &turn_id, cut.clone()).await?;
        let finished = terminal.is_some();
        if let Some(terminal) = terminal {
            items.push(terminal);
        }
        let mut projection = ReplyProjection::new();
        projection.replace(items)?;
        projection.mark_covered();
        if finished {
            projection.mark_history_terminal();
        }
        self.observed_state = projection.terminal();
        self.projection = Some(projection);
        self.history_cut = cut;
        self.refresh_current()?;
        Ok(())
    }

    pub(super) async fn reconnect(&mut self, runtime: &StudioRuntime) -> Result<(), FinalError> {
        self.feed.close().await;
        self.history_reader.close().await;
        let thread_id = self.meta.thread_id.clone();
        let reopened = Self::open(runtime, &thread_id).await?;
        let input_id = self.input_id.clone();
        let turn_id = self.turn_id.clone();
        *self = reopened;
        self.input_id = input_id;
        self.turn_id = turn_id;
        self.ensure_coverage().await
    }

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
        let event = tokio::select! {
            changed = self.history_reader.wait_changed(self.history_cut.clone()) => {
                self.history_cut = changed
                    .map_err(|error| read_failure("bot history watch failed", error))?;
                return self.ensure_coverage().await;
            }
            event = self.feed.next_event() => event,
        }
        .ok_or_else(|| gap("bot conversation feed ended before reply completed"))?;
        match event {
            ConversationEvent::LiveStatus(live) => {
                self.live_status = live;
            }
            ConversationEvent::SessionMeta(meta) => {
                self.meta = meta;
            }
            ConversationEvent::Timeline(_) | ConversationEvent::InputPresented { .. } => {}
            ConversationEvent::ResyncRequired { reason } => {
                return Err(gap(&format!("bot feed resync required: {reason}")));
            }
        }
        self.refresh_current()?;
        if self.turn_id.is_some() {
            self.ensure_coverage().await?;
        }
        Ok(())
    }

    fn refresh_current(&mut self) -> Result<(), FinalError> {
        let Some(turn_id) = self.turn_id.as_deref() else {
            return Ok(());
        };
        let Some(projection) = &mut self.projection else {
            return Ok(());
        };
        let active = self
            .meta
            .active_turn
            .as_ref()
            .is_some_and(|turn| turn.id == turn_id);
        let previews = match &self.live_status.phase {
            LiveStatusPhase::StreamingText { item_id, text, .. } if active => {
                vec![(item_id.clone(), text.clone())]
            }
            _ => Vec::new(),
        };
        projection.set_activity(active, previews)?;
        projection.validate_budget()?;
        Ok(())
    }

    pub(super) async fn close(&mut self) -> Result<(), FinalError> {
        self.feed.request_close();
        self.history_reader.request_close();
        self.feed.close().await;
        self.history_reader.close().await;
        Ok(())
    }
}
