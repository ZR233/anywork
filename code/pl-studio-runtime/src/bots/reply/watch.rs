//! One native feed, same-Session queries and one bounded target projection.

use super::content::{FinalError, PrefixRecovery, begin_projection, read_failure, recover_prefix};
use super::projection::{ReplyProjection, gap};
use crate::studio::{ConversationEvent, ConversationFeed, StudioRuntime, TimelineContentReader};
use pl_protocol::{
    ThreadNotification, ThreadSubscriptionUpdate, TimelineTailBaseline, TimelineTailUpdate, Turn,
    TurnState,
};
use std::future::Future;
use tokio_util::sync::CancellationToken;

pub(super) struct ReplyWatch {
    feed: ConversationFeed,
    input_id: Option<String>,
    turn_id: Option<String>,
    projection: Option<ReplyProjection>,
    recovery: Option<PrefixRecovery>,
    content_version: Option<u64>,
    state_revision: Option<u64>,
    state_epoch: Option<u64>,
    observed_turn: Option<Turn>,
}

impl ReplyWatch {
    pub(super) async fn open(runtime: &StudioRuntime, thread_id: &str) -> Result<Self, FinalError> {
        let feed = runtime
            .open_conversation_feed(thread_id)
            .await
            .map_err(|error| read_failure("bot conversation feed open failed", error))?;
        let mut watch = Self {
            feed,
            input_id: None,
            turn_id: None,
            projection: None,
            recovery: None,
            content_version: None,
            state_revision: None,
            state_epoch: None,
            observed_turn: None,
        };
        // Consume the real stream baseline; never call initial/next independently.
        watch.receive().await?;
        Ok(watch)
    }

    pub(super) fn reader(&self) -> TimelineContentReader {
        self.feed.reader().clone()
    }

    pub(super) fn preview(&self) -> Option<String> {
        self.projection.as_ref().and_then(ReplyProjection::preview)
    }

    pub(super) fn observed_state(&self, turn_id: &str) -> Option<TurnState> {
        self.observed_turn
            .as_ref()
            .filter(|turn| turn.id == turn_id)
            .map(|turn| turn.state.clone())
    }

    /// Canonical receipt association is the only way to select a reply target.
    /// A continuation changes the generation even if the old card is still present.
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
        self.recovery = None;
        self.input_id = Some(input_id.to_string());
        self.turn_id = turn_id.map(str::to_string);
        // Close the old observation before a new baseline/target can be published.
        self.close().await?;
        let feed = runtime
            .open_conversation_feed(self.feed.thread_id())
            .await
            .map_err(|error| read_failure("bot conversation feed target reopen failed", error))?;
        self.feed = feed;
        self.content_version = None;
        self.state_revision = None;
        self.state_epoch = None;
        self.observed_turn = None;
        self.receive().await?;
        self.ensure_coverage().await
    }

    pub(super) async fn ensure_coverage(&mut self) -> Result<(), FinalError> {
        if let (Some(projection), Some(recovery)) = (&mut self.projection, &mut self.recovery) {
            recover_prefix(self.feed.reader(), projection, recovery).await?;
            self.recovery = None;
        }
        Ok(())
    }

    /// Keep consuming and reducing while an admission/read/platform action waits.
    /// Both futures belong to this task; no detached pump or token queue exists.
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
                // Observation failure is not permission to abandon an already
                // durable platform intent. Drain the owned action to its real
                // result, without accepting another frame.
                self.feed.request_close();
                if let Some(cancel) = action_cancel {
                    // Stop at the next admission boundary, without dropping an
                    // HTTP request already in flight.
                    cancel.cancel();
                }
                failure = Some(error);
            }
        }
    }

    pub(super) async fn receive(&mut self) -> Result<(), FinalError> {
        let event = match self.feed.recv().await {
            Ok(Some(event)) => event,
            result => {
                self.projection = None;
                self.recovery = None;
                return Err(match result {
                    Err(error) => {
                        read_failure("bot conversation feed failed; continuity lost", error)
                    }
                    Ok(_) => gap("bot conversation feed ended before reply completed"),
                });
            }
        };
        // Everything after recv is synchronous. Selecting the platform future
        // cannot cancel half of a baseline recovery or lose an already-taken frame.
        match event {
            ConversationEvent::State { update } => {
                let result = self.state(*update);
                if result.is_err() {
                    self.projection = None;
                    self.recovery = None;
                }
                result
            }
            ConversationEvent::ContentBaseline { baseline } => {
                if self.content_version.is_some() {
                    return Err(gap("duplicate reply content baseline"));
                }
                self.baseline(baseline)
            }
            ConversationEvent::ContentUpdate { update } => match update {
                TimelineTailUpdate::Patch {
                    subscription_id,
                    from,
                    to,
                    changes,
                    ..
                } => {
                    if subscription_id != self.feed.subscription_id()
                        || self.content_version != Some(from)
                        || to <= from
                    {
                        self.projection = None;
                        return Err(gap("reply content subscription or version gap"));
                    }
                    if let Some(projection) = &mut self.projection
                        && let Err(error) = projection.apply(changes)
                    {
                        self.projection = None;
                        return Err(error);
                    }
                    self.content_version = Some(to);
                    Ok(())
                }
                TimelineTailUpdate::Resync {
                    subscription_id,
                    baseline,
                    ..
                } => {
                    self.projection = None;
                    if subscription_id != self.feed.subscription_id() {
                        return Err(gap("reply content Resync identity conflict"));
                    }
                    self.baseline(baseline)
                }
            },
        }
    }

    fn baseline(&mut self, baseline: TimelineTailBaseline) -> Result<(), FinalError> {
        self.projection = None;
        self.recovery = None;
        self.content_version = None;
        if baseline.subscription_id != self.feed.subscription_id() {
            return Err(gap("reply content baseline subscription conflict"));
        }
        let version = baseline.version;
        if let Some(turn_id) = &self.turn_id {
            let (projection, recovery) =
                begin_projection(self.feed.thread_id(), turn_id, baseline)?;
            self.projection = Some(projection);
            self.recovery = recovery;
        }
        self.content_version = Some(version);
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
                    self.projection = None;
                    return Err(gap("reply state stream continuity lost"));
                }
                match notification.notification {
                    ThreadNotification::Lagged { .. } => {
                        self.projection = None;
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
        self.observed_turn = Some(turn);
        Ok(())
    }

    pub(super) async fn close(&mut self) -> Result<(), FinalError> {
        self.feed.request_close();
        self.feed
            .close()
            .await
            .map_err(|error| read_failure("bot conversation feed close failed", error))
    }
}
