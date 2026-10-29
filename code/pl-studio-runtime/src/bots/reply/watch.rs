//! One native feed, same-Session queries and one bounded target projection.

use super::content::{FinalError, PrefixRecovery, begin_projection, read_failure, recover_prefix};
use super::projection::{ReplyProjection, gap};
use crate::studio::{ConversationEvent, ConversationFeed, StudioRuntime, TimelineContentReader};
use pl_protocol::{
    ActivityContentFrame, ThreadNotification, ThreadSubscriptionUpdate, TimelineCompletionCursor,
    TimelineTailBaseline, TimelineTailUpdate, TimelineTurnOutcome, Turn, TurnState,
};
use std::future::Future;
use tokio_util::sync::CancellationToken;

pub(super) struct ReplyWatch {
    feed: ConversationFeed,
    input_id: Option<String>,
    turn_id: Option<String>,
    projection: Option<ReplyProjection>,
    recovery: Option<PrefixRecovery>,
    content_cursor: Option<TimelineCompletionCursor>,
    state_revision: Option<u64>,
    state_epoch: Option<u64>,
    observed_turn: Option<Turn>,
}

impl ReplyWatch {
    pub(super) async fn open(runtime: &StudioRuntime, thread_id: &str) -> Result<Self, FinalError> {
        let feed = runtime
            .open_conversation_feed(thread_id, None)
            .await
            .map_err(|error| read_failure("bot conversation feed open failed", error))?;
        let mut watch = Self {
            feed,
            input_id: None,
            turn_id: None,
            projection: None,
            recovery: None,
            content_cursor: None,
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

    pub(super) fn terminal(&self, turn_id: &str) -> Option<TimelineTurnOutcome> {
        (self.turn_id.as_deref() == Some(turn_id))
            .then(|| {
                self.projection
                    .as_ref()?
                    .terminal(self.feed.reader().durable_seq())
            })
            .flatten()
    }

    pub(super) fn observed_state(&self, turn_id: &str) -> Option<TurnState> {
        self.observed_turn
            .as_ref()
            .filter(|turn| {
                turn.id == turn_id
                    && matches!(turn.state, TurnState::Queued(_) | TurnState::Running(_))
            })
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
            .open_conversation_feed(self.feed.thread_id(), None)
            .await
            .map_err(|error| read_failure("bot conversation feed target reopen failed", error))?;
        self.feed = feed;
        self.content_cursor = None;
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

    /// One caller-owned recovery attempt, resuming only the last accepted completion.
    pub(super) async fn reconnect(&mut self, runtime: &StudioRuntime) -> Result<(), FinalError> {
        let cursor = self
            .content_cursor
            .clone()
            .ok_or_else(|| gap("reply resume has no accepted cursor"))?;
        self.close().await?;
        if let Some(projection) = &mut self.projection {
            projection.reset_activity();
        }
        let feed = runtime
            .open_conversation_feed(self.feed.thread_id(), Some(cursor))
            .await
            .map_err(|error| read_failure("bot conversation feed resume failed", error))?;
        self.feed = feed;
        self.state_revision = None;
        self.state_epoch = None;
        self.observed_turn = None;
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
            ConversationEvent::State { update } => self.state(*update),
            ConversationEvent::ContentBaseline { baseline } => {
                if self.content_cursor.is_some() {
                    return Err(gap("duplicate reply content baseline"));
                }
                self.baseline(baseline)
            }
            ConversationEvent::ContentUpdate { update } => self.completed(update),
            ConversationEvent::ActivityContent { frame, completed } => {
                if completed.is_some() && !matches!(frame, ActivityContentFrame::Commit { .. }) {
                    return Err(gap("activity completion outside commit"));
                }
                if matches!(frame, ActivityContentFrame::Commit { .. })
                    && let Some(projection) = &self.projection
                {
                    projection.validate_commit(&frame)?;
                }
                if let Some(update) = completed {
                    self.completed(*update)?;
                }
                if let Some(projection) = &mut self.projection {
                    projection.activity(frame)?;
                }
                Ok(())
            }
        }
    }

    fn completed(&mut self, update: TimelineTailUpdate) -> Result<(), FinalError> {
        match update {
            TimelineTailUpdate::Batch {
                subscription_id,
                timeline_epoch,
                from_seq,
                through_seq,
                items,
            } => {
                let cursor = self
                    .content_cursor
                    .as_ref()
                    .ok_or_else(|| gap("reply completion without baseline"))?;
                if subscription_id != self.feed.subscription_id()
                    || timeline_epoch != cursor.timeline_epoch
                    || from_seq != cursor.append_seq
                    || through_seq <= from_seq
                    || items
                        .last()
                        .is_none_or(|item| item.header.append_seq != through_seq)
                    || items
                        .iter()
                        .scan(from_seq, |previous, item| {
                            let valid = previous.checked_add(1) == Some(item.header.append_seq)
                                && item.header.append_seq <= through_seq;
                            *previous = item.header.append_seq;
                            Some(valid)
                        })
                        .any(|valid| !valid)
                {
                    return Err(gap("reply completion continuity conflict"));
                }
                if let Some(projection) = &mut self.projection {
                    projection.add_page(items)?;
                }
                self.content_cursor = Some(TimelineCompletionCursor {
                    timeline_epoch,
                    append_seq: through_seq,
                });
                Ok(())
            }
            TimelineTailUpdate::Reset { baseline } => {
                if self
                    .content_cursor
                    .as_ref()
                    .is_some_and(|cursor| cursor.timeline_epoch == baseline.timeline_epoch)
                {
                    return Err(gap("reply reset did not change epoch"));
                }
                self.baseline(baseline)
            }
        }
    }

    fn baseline(&mut self, baseline: TimelineTailBaseline) -> Result<(), FinalError> {
        self.projection = None;
        self.recovery = None;
        self.content_cursor = None;
        if baseline.subscription_id != self.feed.subscription_id() {
            return Err(gap("reply content baseline subscription conflict"));
        }
        if baseline.timeline_epoch != baseline.completed_cursor.timeline_epoch {
            return Err(gap("reply baseline epoch conflict"));
        }
        let cursor = baseline.completed_cursor.clone();
        if let Some(turn_id) = &self.turn_id {
            let (projection, recovery) =
                begin_projection(self.feed.thread_id(), turn_id, baseline)?;
            self.projection = Some(projection);
            self.recovery = recovery;
        }
        self.content_cursor = Some(cursor);
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
    use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig};
    use pl_model::model::ModelInfo;
    use pl_model::protocol::ProtocolEndpoint;
    use std::time::Duration;

    #[tokio::test]
    async fn real_feed_resume_and_close_after_cancelled_receive() -> anyhow::Result<()> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let endpoint = std::net::TcpListener::bind("127.0.0.1:0")?;
        let account = AccountId::new("reply-observation")?;
        let route = ModelRouteConfig {
            account_id: account.clone(),
            model_id: "storage-model".into(),
            effort: None,
        };
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        config.models.accounts.insert(
            account,
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible(
                    "Reply fixture",
                    format!("http://{}", endpoint.local_addr()?),
                ),
                vec![ModelInfo::compatible(&route.model_id)],
            ),
        );
        for selected in config
            .models
            .routes
            .values_mut()
            .chain(config.mode_model_routes.values_mut())
        {
            *selected = route.clone();
        }
        ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
        let runtime = StudioRuntime::initialize(crate::StudioRuntimeOptions {
            studio_home: Some(home),
            host: crate::StudioHostKind::Test,
            ..crate::StudioRuntimeOptions::desktop()
        })
        .await?;
        let project = runtime.open_project(&workspace).await?;
        let thread = runtime
            .create_thread(&project.id, "reply observation")
            .await?;
        let mut watch = ReplyWatch::open(&runtime, &thread.id)
            .await
            .map_err(|_| anyhow::anyhow!("open reply watch"))?;
        watch
            .select_target(&runtime, "input", Some("turn"))
            .await
            .map_err(|_| anyhow::anyhow!("select reply target"))?;

        // Drain initial state and activity, then cancel one genuinely pending receive.
        let mut cancelled = false;
        for _ in 0..20 {
            match tokio::time::timeout(Duration::from_millis(100), watch.receive()).await {
                Err(_) => {
                    cancelled = true;
                    break;
                }
                Ok(Ok(())) => {}
                Ok(Err(_)) => anyhow::bail!("initial reply feed failed"),
            }
        }
        anyhow::ensure!(cancelled, "reply receive never became pending");
        let cursor = watch
            .content_cursor
            .clone()
            .ok_or_else(|| anyhow::anyhow!("missing accepted cursor"))?;
        let subscription = watch.feed.subscription_id().to_owned();
        watch
            .reconnect(&runtime)
            .await
            .map_err(|_| anyhow::anyhow!("resume reply watch"))?;
        anyhow::ensure!(
            watch.feed.subscription_id() != subscription,
            "resume reused closed subscription"
        );
        anyhow::ensure!(
            watch.content_cursor == Some(cursor),
            "resume changed accepted cursor"
        );
        for _ in 0..3 {
            tokio::time::timeout(Duration::from_secs(2), watch.receive())
                .await?
                .map_err(|_| anyhow::anyhow!("resumed reply feed failed"))?;
        }
        watch
            .close()
            .await
            .map_err(|_| anyhow::anyhow!("close reply watch"))?;
        anyhow::ensure!(
            watch.receive().await.is_err(),
            "closed reply watch accepted a frame"
        );
        watch
            .close()
            .await
            .map_err(|_| anyhow::anyhow!("repeat reply watch close"))?;
        runtime.shutdown_runtime().await?;
        Ok(())
    }
}
