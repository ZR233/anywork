//! Passive scoped completion delivery. One Set, monotonic Append prefixes, latest activity.
use super::{
    ConversationReader, StudioRuntime,
    conversation_reader::{
        JsonBudget, ReadResources, annotate_atoms, annotate_sources, core_demand, entries, query,
        resync,
    },
    thread_observation::{ConversationSource, ThreadLiveEvent},
};
use crate::studio::thread_projection::{LiveEvent, TurnEvent};
#[cfg(test)]
pub(super) mod tests;
use anyhow::{Result, ensure};
use pl_core::chat as core;
use pl_protocol::*;
use std::{collections::VecDeque, sync::Arc};
use tokio::sync::{broadcast, watch};
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone)]
pub enum ConversationEvent {
    State {
        update: Box<ThreadSubscriptionUpdate>,
    },
    Chat {
        batch: Box<ChatBatch>,
    },
    Activity {
        snapshot: Arc<ActivitySnapshot>,
    },
    Timeline {
        batch: Box<TimelineBatch>,
    },
}
pub struct ConversationFeed {
    reader: ConversationReader,
    initial: Option<ChatBatch>,
    initial_activity: Option<Arc<ActivitySnapshot>>,
    business_refs: ThreadBusinessRefs,
    pending: VecDeque<ThreadSubscriptionUpdate>,
    progress: Option<watch::Receiver<Option<Arc<ConversationSource>>>>,
    state: Option<super::thread_observation::StateReceiver>,
    storage: Option<watch::Receiver<Option<ThreadStorageState>>>,
    last_turn: Option<watch::Receiver<Option<Arc<Turn>>>>,
    slot_changed: watch::Receiver<u64>,
    target: Option<Arc<CompletionTarget>>,
    delivered: u64,
    seen_serial: u64,
    activity_revision: u64,
    demand: ReadDemand,
    state_revision: u64,
    state_effect_floor: u64,
    active_turn: Option<String>,
    delivered_terminal: Option<(String, u64)>,
    runtime_floor: (u64, u64),
    state_activity: Option<ThreadActivity>,
    state_activity_floor: u64,
    state_turn: bool,
    cancel: CancellationToken,
}
/// A slow reader retains only a bounded observation head, never an obsolete
/// CurrentState's active bodies/collections.
struct CompletionTarget {
    serial: u64,
    session: core::Session,
    head: u64,
    activity: Arc<ActivitySnapshot>,
    sources: Arc<[ChatSourceState]>,
    effect: u64,
}
impl From<&ConversationSource> for CompletionTarget {
    fn from(source: &ConversationSource) -> Self {
        Self {
            serial: source.serial,
            session: source.session.clone(),
            head: source.head,
            activity: source.activity.clone(),
            sources: source.current.source_states().clone(),
            effect: source.current.projection().source_effect_seq,
        }
    }
}
impl std::fmt::Debug for ConversationFeed {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConversationFeed")
            .field("reader", &self.reader)
            .field("delivered", &self.delivered)
            .finish_non_exhaustive()
    }
}
impl StudioRuntime {
    pub async fn open_conversation_feed(
        &self,
        thread_id: &str,
        scope: ChatScope,
        demand: ReadDemand,
    ) -> Result<ConversationFeed> {
        self.open_feed_resources(thread_id, scope, demand, true)
            .await
    }
    pub(super) async fn open_feed_resources(
        &self,
        thread_id: &str,
        scope: ChatScope,
        demand: ReadDemand,
        completed: bool,
    ) -> Result<ConversationFeed> {
        core_demand(demand)?;
        let scope_query = query(&scope)?;
        let id = crate::studio::ids::new_id("conversation");
        let slot = self.thread_observations.observation_slot(thread_id);
        let (position, mut slot_changed) = slot.capture();
        // Register both observations before capturing the serial boundary.
        let registered = position.source.as_ref().map(|source| {
            let state = source.subscribe();
            (
                source.conversation(),
                state,
                source.storage(),
                source.last_turn(),
            )
        });
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        let history = self.store.history(thread_id).await?;
        let mut progress = None;
        let mut state = None;
        let mut storage = None;
        let mut last_turn = None;
        let mut initial_activity = Arc::new(ActivitySnapshot {
            revision: 0,
            completed_through: 0,
            execution_present: false,
            entries: Vec::new(),
        });
        let mut initial_serial = 0;
        let mut initial_turn = None;
        let mut initial_interactions = Vec::new();
        let mut source_states = Vec::new();
        let mut cold_sources = None;
        let mut model_route = None;
        let mut cold_terminal = None;
        let mut business_refs = ThreadBusinessRefs::empty();
        let (session, database_id, head, effect_cut, items, boundary) = if let Some((
            registration,
            state_rx,
            storage_rx,
            terminal_rx,
        )) = registered
        {
            let mut source = registration.source;
            let mut progress_rx = registration.progress;
            let mut owner_progress = registration.owner_progress;
            loop {
                if source.is_some() {
                    break;
                }
                ensure!(slot.is_current(position.epoch), resync());
                let retained = owner_progress.borrow_and_update().clone();
                if let Some(error) = retained.retained_error() {
                    return Err(crate::error_mapping::shared_runtime_error(error));
                }
                source = progress_rx.borrow_and_update().clone();
                if source.is_some() {
                    break;
                }
                ensure!(!retained.is_finished(), resync());
                #[cfg(test)]
                if let Some(feed) = position.source.as_ref() {
                    feed.notify_first_open_wait();
                }
                tokio::select! { biased;
                    _ = slot_changed.changed() => return Err(resync()),
                    changed = owner_progress.changed() => { ensure!(changed.is_ok(), resync()); },
                    changed = progress_rx.changed() => { ensure!(changed.is_ok(), resync()); },
                }
            }
            let source = source.ok_or_else(resync)?;
            let database_id = history
                .conversation_database_id()
                .await?
                .ok_or_else(resync)?;
            let budget = JsonBudget::new(
                database_id.clone(),
                continuation_reserve(&id, &scope, &database_id, source.session.epoch().as_str()),
            )
            .for_scope(&scope);
            validate_run(&scope, &database_id, &source.session, source.head, &budget).await?;
            let page = if completed {
                Some(
                    source
                        .session
                        .page(
                            core::ChatPageRequest {
                                query: scope_query,
                                demand: core_demand(demand)?,
                                before: None,
                                ceiling: Some(source.head),
                            },
                            &budget,
                        )
                        .await?,
                )
            } else {
                None
            };
            initial_serial = source.serial;
            initial_activity = source.activity.clone();
            initial_turn = source.current.active_turn().cloned();
            initial_interactions = source.current.interactions().to_vec();
            business_refs = source.current.business_refs();
            if completed {
                source_states = source.current.source_states().to_vec();
            }
            let effect_cut = source.current.projection().source_effect_seq;
            progress = Some(progress_rx);
            state = Some(state_rx);
            storage = Some(storage_rx);
            last_turn = Some(terminal_rx);
            let (items, boundary) = page.map_or_else(
                || (Vec::new(), None),
                |page| (page.items, page.before.map(|cursor| cursor.append_seq)),
            );
            (
                source.session.clone(),
                Some(database_id),
                source.head,
                effect_cut,
                items,
                boundary,
            )
        } else {
            history.prepare_conversation_read().await?;
            let database_id = history.conversation_database_id().await?;
            let session = self.store.chat_session(thread_id).await?;
            let budget = JsonBudget::new(
                database_id.clone().unwrap_or_default(),
                continuation_reserve(
                    &id,
                    &scope,
                    database_id.as_deref().unwrap_or_default(),
                    session.epoch().as_str(),
                ),
            )
            .for_scope(&scope);
            // The existing cold facade reads actual business state without installing execution.
            let cold = if completed {
                history
                    .cold_conversation(scope_query, core_demand(demand)?, &budget)
                    .await?
            } else {
                history.cold_conversation_state().await?
            };
            match cold {
                Some(cold) => {
                    ensure!(
                        database_id.as_deref() == Some(cold.database_id.as_str()),
                        resync()
                    );
                    // Initialize the original Session's D/H from its read-only publication seed.
                    if completed {
                        session
                            .completed_after(
                                core::ChatCompletionCursor::new(session.epoch(), 0),
                                None,
                                Some(0),
                                core::ReadDemand::new(1, CHAT_BATCH_MAX_BYTES as usize),
                                &budget,
                            )
                            .await?;
                    }
                    validate_run(&scope, &cold.database_id, &session, cold.head, &budget).await?;
                    let boundary = if cold.page.exhausted {
                        None
                    } else {
                        cold.page.items.first().map(|item| {
                            if matches!(scope, ChatScope::Main) {
                                item.header
                                    .run
                                    .map_or(item.header.append_seq, |run| run.start_seq)
                            } else {
                                item.header.append_seq
                            }
                        })
                    };
                    initial_activity = Arc::new(ActivitySnapshot {
                        completed_through: cold.head,
                        revision: 0,
                        execution_present: false,
                        entries: Vec::new(),
                    });
                    initial_interactions = cold.interactions;
                    business_refs =
                        crate::studio::thread_projection::project_business_refs(&cold.current);
                    cold_sources = Some(cold.sources);
                    model_route = cold.model_route.map(|route| route.snapshot(false));
                    cold_terminal = cold.terminal_turn;
                    (
                        session,
                        Some(cold.database_id),
                        cold.head,
                        cold.current.source_effect_seq,
                        cold.page.items,
                        boundary,
                    )
                }
                None => {
                    ensure!(
                        !matches!(scope, ChatScope::Run { .. }),
                        core::ChatError::InvalidArgument("unknown completion run".into())
                    );
                    (session, None, 0, 0, Vec::new(), None)
                }
            }
        };
        ensure!(slot.is_current(position.epoch), resync());
        let mut initial_entries = entries(items, database_id.as_deref().unwrap_or_default())?;
        if !completed {
            // The presentation facade shares State and read resources, never reads/annotates an
            // atomic completion page as an intermediate representation.
        } else if let Some(sources) = cold_sources {
            annotate_atoms(&mut initial_entries, &sources)?;
        } else {
            annotate_sources(&mut initial_entries, &history, &source_states, effect_cut).await?;
        }
        let reader = ConversationReader::new(
            id,
            scope,
            head,
            effect_cut,
            slot,
            position.epoch,
            ReadResources {
                history,
                session,
                database_id,
                source: position.source.clone(),
                thread: thread.clone(),
                recovery: self.recovery.clone(),
            },
        );
        let initial = if completed {
            Some(reader.finish_batch(
                ChatBatch {
                    placement: ChatPlacement::Set,
                    entries: initial_entries,
                    before: reader.before(boundary).await?,
                    from_seq: None,
                    through_seq: head,
                },
                demand,
            )?)
        } else {
            None
        };
        let runtime_source = position.source.as_ref().and_then(|source| source.runtime());
        let state_activity_cut = position
            .source
            .as_ref()
            .and_then(|source| source.state_activity());
        let (state_activity_floor, state_activity) = state_activity_cut
            .map(|cut| (cut.observation_revision, cut.activity.as_deref().cloned()))
            .unwrap_or((0, None));
        let runtime_floor = runtime_source.as_ref().map_or((0, 0), |cut| {
            (cut.observation_revision, cut.catalog_revision)
        });
        let runtime = if let Some(cut) = runtime_source {
            model_route = cut.model_route;
            Some((*cut.runtime).clone())
        } else {
            let (config, _) = self.config_runtime.read_with_catalog()?;
            crate::studio::model_route::annotate_availability(
                model_route.as_mut(),
                &thread,
                &config.config,
            )?;
            None
        };
        let active_turn = initial_turn.as_ref().map(|turn| turn.id.clone());
        let snapshot = pl_protocol::ThreadSnapshot {
            schema_version: THREAD_SCHEMA_VERSION,
            revision: effect_cut,
            thread,
            runtime,
            model_route,
            active_turn: initial_turn,
            interactions: initial_interactions,
            business_refs: business_refs.clone(),
            activity: state_activity.clone(),
            storage: storage
                .as_ref()
                .and_then(|storage| storage.borrow().clone()),
        };
        let mut pending = VecDeque::new();
        pending.push_back(ThreadSubscriptionUpdate::Snapshot {
            completed_history_version: COMPLETED_HISTORY_VERSION,
            snapshot: Box::new(snapshot),
        });
        let mut feed = ConversationFeed {
            reader,
            initial,
            initial_activity: completed.then_some(initial_activity),
            business_refs,
            pending,
            progress,
            state,
            storage,
            last_turn,
            slot_changed,
            target: None,
            delivered: head,
            seen_serial: initial_serial,
            activity_revision: 0,
            demand,
            state_revision: effect_cut,
            state_effect_floor: effect_cut,
            active_turn,
            delivered_terminal: None,
            runtime_floor,
            state_activity,
            state_activity_floor,
            state_turn: true,
            cancel: CancellationToken::new(),
        };
        feed.check_state_budget()?;
        if let Some(turn) = cold_terminal {
            feed.reflect_terminal(turn)?;
        }
        feed.reader.ensure()?;
        Ok(feed)
    }
}
async fn validate_run(
    scope: &ChatScope,
    database_id: &str,
    session: &core::Session,
    head: u64,
    budget: &JsonBudget,
) -> Result<()> {
    let ChatScope::Run { reference } = scope else {
        return Ok(());
    };
    ensure!(
        reference.database_id == database_id,
        core::ChatError::StaleContent
    );
    ensure!(
        reference.index_version == COMPLETED_READ_INDEX_VERSION
            && reference.start_seq > 0
            && reference.start_seq <= head,
        core::ChatError::InvalidArgument("invalid completion run reference".into())
    );
    let headers = JsonBudget::new(budget.database_id.clone(), String::new()).headers_only();
    let page = session
        .page(
            core::ChatPageRequest {
                query: query(scope)?,
                demand: core::ReadDemand::new(1, CHAT_BATCH_MAX_BYTES as usize),
                before: None,
                ceiling: Some(reference.start_seq),
            },
            &headers,
        )
        .await?;
    ensure!(
        page.items.len() == 1
            && page.items[0].header.append_seq == reference.start_seq
            && page.items[0]
                .header
                .run
                .is_some_and(|run| run.start_seq == reference.start_seq && run.ordinal == 1),
        core::ChatError::InvalidArgument("unknown completion run start".into())
    );
    Ok(())
}
fn continuation_reserve(lease: &str, scope: &ChatScope, database: &str, epoch: &str) -> String {
    serde_json::json!({"version":2,
        "index_version":COMPLETED_READ_INDEX_VERSION,"thread_id":lease,"lease":lease,"database":database,
        "scope":scope,"epoch":epoch,"ceiling":u64::MAX,"kind":{"kind":"Before","boundary":u64::MAX}}).to_string()
}
impl ConversationFeed {
    pub fn thread_id(&self) -> &str {
        self.reader.thread_id()
    }
    pub fn subscription_id(&self) -> &str {
        self.reader.subscription_id()
    }
    pub fn reader(&self) -> &ConversationReader {
        &self.reader
    }
    pub fn request_close(&self) {
        self.cancel.cancel();
    }
    pub fn cancellation_token(&self) -> CancellationToken {
        self.cancel.clone()
    }
    pub(super) fn current_progress(&mut self) -> Option<Arc<ConversationSource>> {
        self.progress
            .as_mut()
            .and_then(|progress| progress.borrow_and_update().clone())
    }
    /// Shared State owner for the completed and presentation facades. This never reads Chat.
    pub(super) fn take_state(&mut self) -> Result<Option<ThreadSubscriptionUpdate>> {
        self.reader.ensure()?;
        ensure!(!self.cancel.is_cancelled(), core::ChatError::Cancelled);
        ensure!(
            !self
                .state
                .as_ref()
                .is_some_and(super::thread_observation::StateReceiver::is_closed),
            resync()
        );
        self.reflect_retained_turn()?;
        if let Some(update) = self.pending.pop_front() {
            return Ok(Some(update));
        }
        let queued = self
            .state
            .as_ref()
            .map_or(0, super::thread_observation::StateReceiver::len);
        for _ in 0..queued {
            match self
                .state
                .as_mut()
                .expect("queued State receiver")
                .try_recv()
            {
                Ok(event) => self.state_event(event)?,
                Err(broadcast::error::TryRecvError::Empty) => break,
                Err(_) => return Err(resync()),
            }
        }
        Ok(self.pending.pop_front())
    }
    pub async fn close(&mut self) -> Result<()> {
        self.finish_production();
        Ok(())
    }
    pub(super) fn finish_production(&mut self) {
        self.cancel.cancel();
        self.progress = None;
        self.state = None;
        self.storage = None;
        self.last_turn = None;
        self.target = None;
        self.initial = None;
        self.initial_activity = None;
        self.pending.clear();
    }
    fn notification(&mut self, notification: ThreadNotification) -> Result<()> {
        if let ThreadNotification::ThreadRuntimeUpdated { runtime, .. } = &notification
            && let Some(ThreadSubscriptionUpdate::Notification { notification: last }) =
                self.pending.back_mut()
            && matches!(
                &last.notification,
                ThreadNotification::ThreadRuntimeUpdated { runtime: old, .. }
                    if super::thread_stream::same_live_runtime_identity(runtime, old)
            )
        {
            last.notification = notification;
            last.emitted_at = crate::studio::unix_seconds();
            return self.check_state_budget();
        }
        let next = self.state_revision.checked_add(1).ok_or_else(resync)?;
        self.pending
            .push_back(ThreadSubscriptionUpdate::Notification {
                notification: Box::new(ThreadNotificationEnvelope::new(
                    self.thread_id(),
                    self.reader.inner.epoch,
                    self.state_revision,
                    next,
                    crate::studio::unix_seconds(),
                    notification,
                )),
            });
        self.state_revision = next;
        self.check_state_budget()
    }

    fn check_state_budget(&self) -> Result<()> {
        ensure!(
            self.pending.len() <= 64
                && self
                    .pending
                    .iter()
                    .map(|item| serde_json::to_vec(item).map_or(usize::MAX, |bytes| bytes.len()))
                    .sum::<usize>()
                    <= 1024 * 1024,
            resync()
        );
        Ok(())
    }

    fn terminal_delivered(&self, turn: &Turn) -> bool {
        self.delivered_terminal
            .as_ref()
            .is_some_and(|(id, revision)| id == &turn.id && *revision >= turn.revision)
    }

    fn reflect_retained_turn(&mut self) -> Result<()> {
        let retained = self
            .last_turn
            .as_mut()
            .and_then(|watch| watch.borrow_and_update().clone());
        if let Some(turn) = retained {
            self.reflect_terminal((*turn).clone())?;
        }
        Ok(())
    }

    fn reflect_terminal(&mut self, turn: Turn) -> Result<()> {
        // This is the original State owner's typed terminal fact, published only after its reliable
        // PreparedEffect handoff. It is not inferred from current, progress, content or idle. Replay
        // only a fact covered by this State cut, and never replay an older terminal over an active
        // Turn. Snapshot carries only activeTurn, so omitting this replay loses lastTurn on reopen.
        if turn.revision > self.state_effect_floor
            || self.active_turn.is_some()
            || self.terminal_delivered(&turn)
        {
            return Ok(());
        }
        self.delivered_terminal = Some((turn.id.clone(), turn.revision));
        self.notification(ThreadNotification::TurnCompleted { turn })
    }

    fn state_event(&mut self, event: ThreadLiveEvent) -> Result<()> {
        match event {
            ThreadLiveEvent::BusinessRefs {
                sequence,
                references,
            } => {
                if sequence < self.state_effect_floor || references == self.business_refs {
                    return Ok(());
                }
                self.business_refs = references.clone();
                self.notification(ThreadNotification::BusinessRefsChanged { references })?;
            }
            ThreadLiveEvent::Committed { sequence, changes } => {
                if sequence <= self.state_effect_floor {
                    return Ok(());
                }
                self.state_effect_floor = sequence;
                for change in changes {
                    let notification = match change {
                        LiveEvent::Turn { turn, event } => {
                            if self.terminal_delivered(&turn) {
                                continue;
                            }
                            if matches!(&turn.state, TurnState::Running(_)) {
                                self.active_turn = Some(turn.id.clone());
                            } else if turn.state.is_terminal() {
                                self.delivered_terminal = Some((turn.id.clone(), turn.revision));
                                if self.active_turn.as_deref() == Some(turn.id.as_str()) {
                                    self.active_turn = None;
                                }
                            }
                            match event {
                                TurnEvent::Started => ThreadNotification::TurnStarted { turn },
                                TurnEvent::Updated => ThreadNotification::TurnUpdated { turn },
                                TurnEvent::Completed => ThreadNotification::TurnCompleted { turn },
                            }
                        }
                        LiveEvent::Interaction(interaction) => {
                            ThreadNotification::InteractionChanged { interaction }
                        }
                    };
                    self.notification(notification)?;
                }
            }
            ThreadLiveEvent::Runtime {
                runtime,
                model_route,
                observation_revision,
                catalog_revision,
            } => {
                if observation_revision <= self.runtime_floor.0
                    && catalog_revision <= self.runtime_floor.1
                {
                    return Ok(());
                }
                ensure!(
                    observation_revision >= self.runtime_floor.0
                        && catalog_revision >= self.runtime_floor.1,
                    resync()
                );
                self.runtime_floor = (observation_revision, catalog_revision);
                self.notification(ThreadNotification::ThreadRuntimeUpdated {
                    runtime: Box::new((*runtime).clone()),
                    model_route,
                })?
            }
            ThreadLiveEvent::Activity {
                observation_revision,
                activity,
            } => {
                if observation_revision <= self.state_activity_floor {
                    return Ok(());
                }
                self.state_activity_floor = observation_revision;
                if activity.as_deref() != self.state_activity.as_ref() {
                    self.state_activity = activity.as_deref().cloned();
                    self.notification(ThreadNotification::ActivityChanged {
                        activity: activity.map(|activity| Box::new((*activity).clone())),
                    })?;
                }
            }
            ThreadLiveEvent::UnframedCommit { sequence } => {
                ensure!(
                    sequence <= self.state_effect_floor,
                    resync().context(format!(
                        "conversation UnframedCommit above State floor: sequence={sequence}, state_effect_floor={}",
                        self.state_effect_floor
                    ))
                );
            }
            ThreadLiveEvent::Rebase { .. } => return Err(resync()),
        }
        Ok(())
    }
    pub async fn recv(&mut self) -> Result<Option<ConversationEvent>> {
        let result = self.receive().await;
        if result.as_ref().err().is_some_and(|error| {
            error
                .downcast_ref::<pl_protocol::studio::StudioError>()
                .is_some_and(|error| error.reason() == Some("conversationResyncRequired"))
        }) {
            self.reader.invalidate();
        }
        if result.is_err() {
            self.finish_production();
        }
        result
    }
    fn take_progress(&mut self) -> Result<bool> {
        if self.target.is_some() {
            return Ok(true);
        }
        let Some(progress) = self.progress.as_mut() else {
            return Ok(false);
        };
        let newest = progress.borrow_and_update().clone();
        if let Some(newest) = newest
            && newest.serial > self.seen_serial
        {
            ensure!(newest.head >= self.delivered, resync());
            self.target = Some(Arc::new(CompletionTarget::from(newest.as_ref())));
            return Ok(true);
        }
        Ok(false)
    }
    async fn receive(&mut self) -> Result<Option<ConversationEvent>> {
        loop {
            if self.cancel.is_cancelled() {
                return Err(core::ChatError::Cancelled.into());
            }
            self.reader.ensure()?;
            ensure!(
                !self
                    .state
                    .as_ref()
                    .is_some_and(super::thread_observation::StateReceiver::is_closed),
                resync()
            );
            self.reflect_retained_turn()?;
            if let Some(batch) = self.initial.take() {
                return Ok(Some(ConversationEvent::Chat {
                    batch: Box::new(batch),
                }));
            }
            if let Some(update) = self.pending.pop_front() {
                return Ok(Some(ConversationEvent::State {
                    update: Box::new(update),
                }));
            }
            if let Some(snapshot) = self.initial_activity.take() {
                ensure!(snapshot.completed_through == self.delivered, resync());
                self.activity_revision = snapshot.revision;
                return Ok(Some(ConversationEvent::Activity { snapshot }));
            }
            if self.state_turn {
                self.state_turn = false;
                let queued = self
                    .state
                    .as_ref()
                    .map_or(0, super::thread_observation::StateReceiver::len);
                for _ in 0..queued {
                    match self
                        .state
                        .as_mut()
                        .expect("queued State receiver")
                        .try_recv()
                    {
                        Ok(event) => self.state_event(event)?,
                        Err(broadcast::error::TryRecvError::Empty) => break,
                        Err(broadcast::error::TryRecvError::Lagged(skipped)) => {
                            return Err(resync().context(format!(
                                "conversation state try_recv lagged: skipped={skipped}"
                            )));
                        }
                        Err(broadcast::error::TryRecvError::Closed) => return Err(resync()),
                    }
                }
                if let Some(update) = self.pending.pop_front() {
                    return Ok(Some(ConversationEvent::State {
                        update: Box::new(update),
                    }));
                }
            }
            self.state_turn = true;
            self.take_progress()?;
            if let Some(target) = self.target.clone() {
                if target.head > self.delivered {
                    let mut replay_query = query(&self.reader.inner.scope)?;
                    if matches!(self.reader.inner.scope, ChatScope::Main) {
                        replay_query.selection = core::ChatSelection::Records;
                    }
                    let budget = self
                        .reader
                        .budget()
                        .await?
                        .for_scope(&self.reader.inner.scope);
                    let batch = target
                        .session
                        .completed_after(
                            core::ChatCompletionCursor::new(target.session.epoch(), self.delivered),
                            Some(replay_query),
                            Some(target.head),
                            core_demand(self.demand)?,
                            &budget,
                        )
                        .await?;
                    ensure!(
                        batch.through_seq > self.delivered && batch.through_seq <= target.head,
                        resync()
                    );
                    let mut product = ChatBatch {
                        placement: ChatPlacement::Append,
                        entries: entries(batch.items, &budget.database_id)?,
                        before: None,
                        from_seq: Some(self.delivered),
                        through_seq: batch.through_seq,
                    };
                    if matches!(self.reader.inner.scope, ChatScope::Main) {
                        product
                            .entries
                            .retain(|entry| entry.main_presentation != MainPresentation::Hidden);
                    }
                    self.reader
                        .annotate_source_states(
                            &mut product.entries,
                            &target.sources,
                            target.effect,
                        )
                        .await?;
                    let product = self.reader.finish_batch(product, self.demand)?;
                    self.delivered = product.through_seq;
                    // Empty Appends still accept filtered completion progress and unblock Activity.
                    return Ok(Some(ConversationEvent::Chat {
                        batch: Box::new(product),
                    }));
                }
                self.target = None;
                self.seen_serial = target.serial;
                if target.activity.completed_through < self.delivered
                    || target.activity.revision <= self.activity_revision
                {
                    continue;
                }
                ensure!(
                    target.activity.completed_through == self.delivered,
                    resync()
                );
                self.activity_revision = target.activity.revision;
                return Ok(Some(ConversationEvent::Activity {
                    snapshot: target.activity.clone(),
                }));
            }
            self.wait_change().await?;
        }
    }
    pub(super) async fn wait_change(&mut self) -> Result<()> {
        enum Wake {
            State(Result<ThreadLiveEvent, broadcast::error::RecvError>),
            Progress(bool),
            Storage(Option<ThreadStorageState>),
            Terminal(bool),
            Slot,
        }
        let wake = tokio::select! { biased;
            _ = self.cancel.cancelled() => return Err(core::ChatError::Cancelled.into()),
            _ = self.slot_changed.changed() => Wake::Slot,
            state = async { match self.state.as_mut() { Some(state) => state.recv().await, None => std::future::pending().await } } => Wake::State(state),
            progress = async { match self.progress.as_mut() { Some(progress) => progress.changed().await.is_ok(), None => std::future::pending().await } } => Wake::Progress(progress),
            storage = async { match self.storage.as_mut() { Some(storage) => { if storage.changed().await.is_ok() { storage.borrow_and_update().clone() } else { std::future::pending().await } }, None => std::future::pending().await } } => Wake::Storage(storage),
            terminal = async { match self.last_turn.as_mut() { Some(terminal) => terminal.changed().await.is_ok(), None => std::future::pending().await } } => Wake::Terminal(terminal),
        };
        match wake {
            Wake::Slot => {
                self.reader.ensure()?;
                return Err(resync());
            }
            Wake::State(Ok(event)) => self.state_event(event)?,
            Wake::State(Err(_)) => return Err(resync()),
            Wake::Progress(true) => {}
            Wake::Progress(false) => return Err(resync()),
            Wake::Storage(storage) => self.notification(ThreadNotification::StorageChanged {
                storage: storage.map(Box::new),
            })?,
            Wake::Terminal(false) => self.last_turn = None,
            Wake::Terminal(true) => {}
        }
        Ok(())
    }
}
