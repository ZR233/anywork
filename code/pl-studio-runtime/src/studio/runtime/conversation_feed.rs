//! Passive, scoped Chat delivery. A handle has exactly one Set and never resets in place.
use super::{
    ConversationReader, StudioRuntime,
    conversation_reader::{JsonBudget, ReadResources, core_demand, messages, query, resync},
    thread_observation::{ConversationCut, ConversationSource, ThreadLiveEvent},
};
use crate::studio::thread_projection::{LiveEvent, TurnEvent};
#[cfg(test)]
mod tests;
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
}

pub struct ConversationFeed {
    reader: ConversationReader,
    initial: Option<ChatBatch>,
    pending: VecDeque<ThreadSubscriptionUpdate>,
    cuts: Option<broadcast::Receiver<Arc<ConversationCut>>>,
    progress: Option<watch::Receiver<Option<Arc<ConversationSource>>>>,
    state: Option<broadcast::Receiver<ThreadLiveEvent>>,
    storage: Option<watch::Receiver<Option<ThreadStorageState>>>,
    last_turn: Option<watch::Receiver<Option<Arc<Turn>>>>,
    slot_changed: watch::Receiver<u64>,
    cut: Option<Arc<ConversationCut>>,
    delivered: u64,
    seen_serial: u64,
    current: Option<CurrentProjection>,
    demand: ReadDemand,
    state_revision: u64,
    state_effect_floor: u64,
    active_turn: Option<String>,
    delivered_terminal: Option<(String, u64)>,
    runtime_floor: (u64, u64),
    state_turn: bool,
    cancel: CancellationToken,
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
    #[tracing::instrument(
        target = "conversation_work", level = "debug", name = "conversation_read",
        skip_all,
        fields(operation = "open", thread_id = thread_id, trace_id, max_items = demand.max_items, max_bytes = demand.max_bytes)
    )]
    pub async fn open_conversation_feed(
        &self,
        thread_id: &str,
        scope: ChatScope,
        demand: ReadDemand,
    ) -> Result<ConversationFeed> {
        let id = crate::studio::ids::new_id("conversation");
        tracing::Span::current().record("trace_id", &id);
        let started = std::time::Instant::now();
        tracing::debug!(target: "conversation_work", "read started");
        core_demand(demand)?;
        let scope_query = query(&scope)?;
        // This is deliberately before every IO, including thread/catalog reads.
        let slot = self.thread_observations.observation_slot(thread_id);
        let (position, mut slot_changed) = slot.capture();
        let registered = position.source.as_ref().map(|source| {
            // State must register before the content/current cut is captured, just like the
            // original State subscription. Capturing first leaves a lost-lifecycle window.
            let state = source.subscribe();
            let last_turn = source.last_turn();
            (source.conversation(), state, source.storage(), last_turn)
        });
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        let history = self.store.history(thread_id).await?;
        let main = matches!(scope, ChatScope::Main);
        let mut cuts = None;
        let mut progress = None;
        let mut state = None;
        let mut storage = None;
        let mut last_turn = None;
        let mut cold_terminal = None;
        let mut model_route = None;
        let mut initial_serial = 0;
        let mut state_effect_floor = 0;
        let mut initial_turn = None;
        let mut interactions = Vec::new();
        let (session, database_id, head, current, items, boundary) = if let Some((
            registration,
            state_rx,
            storage_rx,
            terminal_rx,
        )) = registered
        {
            let (mut source, cut_rx, mut progress_rx) = (
                registration.source,
                registration.cuts,
                registration.progress,
            );
            let mut owner_progress = registration.owner_progress;
            if source.is_none() {
                let mut owner_closed = false;
                loop {
                    if !slot.is_current(position.epoch) {
                        return Err(resync());
                    }
                    let retained = owner_progress.borrow_and_update().clone();
                    if let Some(error) = retained.retained_error() {
                        if !slot.is_current(position.epoch) {
                            return Err(resync());
                        }
                        return Err(crate::error_mapping::shared_runtime_error(error));
                    }
                    source = progress_rx.borrow_and_update().clone();
                    if source.is_some() {
                        break;
                    }
                    if retained.is_finished() || owner_closed {
                        return Err(resync());
                    }
                    #[cfg(test)]
                    if let Some(feed) = position.source.as_ref() {
                        feed.notify_first_open_wait();
                    }
                    tokio::select! { biased;
                        _=slot_changed.changed()=>return Err(resync()),
                        changed=owner_progress.changed()=>owner_closed=changed.is_err(),
                        changed=progress_rx.changed()=>if changed.is_err() { return Err(resync()); }
                    }
                }
            }
            let source = source.ok_or_else(resync)?;
            initial_serial = source.serial;
            state_effect_floor = source.current.projection.source_effect_seq;
            initial_turn = source.current.active_turn.clone();
            interactions = source.current.pending_interactions()?;
            let database_id = history
                .conversation_database_id()
                .await?
                .ok_or_else(resync)?;
            let current = main.then(|| source.current.projection.clone());
            let budget = JsonBudget::new(
                database_id.clone(),
                current.clone(),
                continuation_reserve(&id, &scope, &database_id, source.session.epoch().as_str()),
            );
            let page = source
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
                .await?;
            cuts = Some(cut_rx);
            progress = Some(progress_rx);
            state = Some(state_rx);
            storage = Some(storage_rx);
            last_turn = Some(terminal_rx);
            (
                source.session.clone(),
                Some(database_id),
                source.head,
                current,
                page.items,
                page.before.map(|cursor| cursor.append_seq),
            )
        } else {
            tracing::debug!(
                target: "conversation_work",
                pending_candidates = 0,
                pending_returned = 0,
                "cold source has no pending owner"
            );
            // Current stores pass only the read-only gate. Supported old content is prepared by
            // HistoryStore's original migration barrier, never by activating an execution owner.
            history.prepare_conversation_read().await?;
            let database_id = history.conversation_database_id().await?;
            let session = self.store.chat_session(thread_id).await?;
            let budget = JsonBudget::new(
                database_id.clone().unwrap_or_default(),
                None,
                continuation_reserve(
                    &id,
                    &scope,
                    database_id.as_deref().unwrap_or_default(),
                    session.epoch().as_str(),
                ),
            );
            match history
                .cold_conversation(scope_query, core_demand(demand)?, &budget)
                .await?
            {
                Some(cold) => {
                    ensure!(
                        database_id.as_deref() == Some(cold.database_id.as_str()),
                        resync()
                    );
                    let boundary = (!cold.page.exhausted)
                        .then(|| cold.page.items.first().map(|item| item.header.append_seq))
                        .flatten();
                    let mut current = cold.current;
                    interactions = cold.interactions;
                    model_route = cold.model_route.map(|route| route.snapshot(false));
                    cold_terminal = cold.terminal_turn;
                    state_effect_floor = current.source_effect_seq;
                    current.execution_present = false;
                    current.active = None;
                    current.active_turn = None;
                    current.previews.clear();
                    (
                        session,
                        Some(cold.database_id),
                        cold.head,
                        main.then_some(current),
                        cold.page.items,
                        boundary,
                    )
                }
                None => (
                    session,
                    None,
                    0,
                    main.then(|| CurrentProjection::empty(0, thread.status)),
                    Vec::new(),
                    None,
                ),
            }
        };
        if !slot.is_current(position.epoch) {
            return Err(resync());
        }
        let reader = ConversationReader::new(
            id,
            scope,
            head,
            slot,
            position.epoch,
            ReadResources {
                history,
                session,
                database_id: database_id.clone(),
                source: position.source.clone(),
                thread: thread.clone(),
                recovery: self.recovery.clone(),
            },
        );
        let initial = ChatBatch {
            placement: ChatPlacement::Set,
            messages: messages(items, database_id.as_deref().unwrap_or_default()),
            before: reader.before(boundary).await?,
            current: current.clone(),
        };
        let initial = reader.finish_batch(initial, demand)?;
        tracing::debug!(
            target: "conversation_work",
            returned = initial.messages.len(),
            elapsed_us = started.elapsed().as_micros() as u64,
            "read completed"
        );
        let mut pending = VecDeque::new();
        // Other domains remain State. Current bodies and activity are exclusively Chat.current.
        let runtime_source = position.source.as_ref().and_then(|source| source.runtime());
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
            revision: current
                .as_ref()
                .map_or(0, |current| current.source_effect_seq),
            thread,
            runtime,
            model_route,
            active_turn: initial_turn,
            interactions,
            activity: None,
            storage: storage
                .as_ref()
                .and_then(|storage| storage.borrow().clone()),
        };
        let state_revision = snapshot.revision;
        pending.push_back(ThreadSubscriptionUpdate::Snapshot {
            snapshot: Box::new(snapshot),
        });
        let mut feed = ConversationFeed {
            reader,
            initial: Some(initial),
            pending,
            cuts,
            progress,
            state,
            storage,
            last_turn,
            slot_changed,
            cut: None,
            delivered: head,
            seen_serial: initial_serial,
            current,
            demand,
            state_revision,
            state_effect_floor,
            active_turn,
            delivered_terminal: None,
            runtime_floor,
            state_turn: true,
            cancel: CancellationToken::new(),
        };
        if let Some(turn) = cold_terminal {
            feed.reflect_terminal(turn)?;
        }
        feed.reflect_retained_turn()?;
        Ok(feed)
    }
}
fn continuation_reserve(lease: &str, scope: &ChatScope, database: &str, epoch: &str) -> String {
    serde_json::json!({"lease":lease,"database":database,"scope":scope,"epoch":epoch,"ceiling":u64::MAX,"kind":{"kind":"Before","boundary":u64::MAX}}).to_string()
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
    pub async fn close(&mut self) -> Result<()> {
        self.finish_production();
        Ok(())
    }
    fn finish_production(&mut self) {
        self.cancel.cancel();
        self.cuts = None;
        self.progress = None;
        self.state = None;
        self.storage = None;
        self.last_turn = None;
        self.cut = None;
        self.initial = None;
        self.pending.clear();
        self.current = None;
    }
    fn notification(&mut self, notification: ThreadNotification) -> Result<()> {
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
            ThreadLiveEvent::Activity { .. } => {}
            ThreadLiveEvent::UnframedCommit { sequence } => {
                ensure!(sequence <= self.state_effect_floor, resync());
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
    async fn receive(&mut self) -> Result<Option<ConversationEvent>> {
        loop {
            if self.cancel.is_cancelled() {
                return Err(core::ChatError::Cancelled.into());
            }
            self.reader.ensure()?;
            self.reflect_retained_turn()?;
            if let Some(batch) = self.initial.take() {
                self.state_turn = true;
                return Ok(Some(ConversationEvent::Chat {
                    batch: Box::new(batch),
                }));
            }
            if let Some(update) = self.pending.pop_front() {
                self.state_turn = false;
                return Ok(Some(ConversationEvent::State {
                    update: Box::new(update),
                }));
            }
            if self.state_turn {
                self.state_turn = false;
                if let Some(state) = self.state.as_mut() {
                    match state.try_recv() {
                        Ok(event) => {
                            self.state_event(event)?;
                            if let Some(update) = self.pending.pop_front() {
                                return Ok(Some(ConversationEvent::State {
                                    update: Box::new(update),
                                }));
                            }
                        }
                        Err(broadcast::error::TryRecvError::Empty) => {}
                        Err(_) => return Err(resync()),
                    }
                }
            }
            if let Some(cut) = self.cut.clone() {
                if cut.serial <= self.seen_serial {
                    self.cut = None;
                    continue;
                }
                let main = matches!(self.reader.inner.scope, ChatScope::Main);
                if main && self.delivered >= cut.handoff.main_through {
                    // The owner proves this suffix contains no further Main completion.
                    self.delivered = self.delivered.max(cut.head);
                }
                if cut.head > self.delivered {
                    let budget = if main {
                        // A prefix only removes previews from `before`. Its source stamp is the
                        // reliable effect's stamp, so reserve that envelope and the final one.
                        let mut before = cut.handoff.before.as_ref().clone();
                        before.source_effect_seq = cut.handoff.after.source_effect_seq;
                        let before = self.reader.budget(Some(before)).await?;
                        let after = self
                            .reader
                            .budget(Some(cut.handoff.after.as_ref().clone()))
                            .await?;
                        if core::ChatBudget::fixed_bytes(&before)
                            >= core::ChatBudget::fixed_bytes(&after)
                        {
                            before
                        } else {
                            after
                        }
                    } else {
                        self.reader.budget(None).await?
                    };
                    let batch = cut
                        .session
                        .completed_after(
                            core::ChatCompletionCursor::new(cut.session.epoch(), self.delivered),
                            Some(query(&self.reader.inner.scope)?),
                            Some(cut.head),
                            core_demand(self.demand)?,
                            &budget,
                        )
                        .await?;
                    self.reader.ensure()?;
                    ensure!(batch.through_seq > self.delivered, resync());
                    self.delivered = batch.through_seq;
                    let current = main.then(|| cut.handoff.projection_at(self.delivered));
                    if main && self.delivered >= cut.handoff.main_through {
                        self.delivered = cut.head;
                    }
                    if !batch.items.is_empty() || current.is_some() {
                        let product = ChatBatch {
                            placement: ChatPlacement::Append,
                            messages: messages(batch.items, &budget.database_id),
                            before: None,
                            current: current.clone(),
                        };
                        let product = self.reader.finish_batch(product, self.demand)?;
                        if let Some(current) = current {
                            self.current = Some(current);
                        }
                        if self.delivered == cut.head {
                            self.seen_serial = cut.serial;
                            self.cut = None;
                        }
                        self.state_turn = true;
                        return Ok(Some(ConversationEvent::Chat {
                            batch: Box::new(product),
                        }));
                    }
                } else if main && self.current.as_ref() != Some(cut.handoff.after.as_ref()) {
                    let product = ChatBatch {
                        placement: ChatPlacement::Append,
                        messages: Vec::new(),
                        before: None,
                        current: Some(cut.handoff.after.as_ref().clone()),
                    };
                    let product = self.reader.finish_batch(product, self.demand)?;
                    self.current = product.current.clone();
                    self.seen_serial = cut.serial;
                    self.cut = None;
                    self.state_turn = true;
                    return Ok(Some(ConversationEvent::Chat {
                        batch: Box::new(product),
                    }));
                }
                self.seen_serial = cut.serial;
                self.cut = None;
                continue;
            }
            if let Some(cuts) = self.cuts.as_mut() {
                match cuts.try_recv() {
                    Ok(cut) => {
                        if cut.head >= self.delivered && cut.serial > self.seen_serial {
                            self.cut = Some(cut);
                        }
                        continue;
                    }
                    Err(broadcast::error::TryRecvError::Lagged(_)) => return Err(resync()),
                    Err(broadcast::error::TryRecvError::Closed) => return Err(resync()),
                    Err(broadcast::error::TryRecvError::Empty) => {}
                }
            }
            if let Some(progress) = self.progress.as_mut() {
                let changed = progress.has_changed().map_err(|_| resync())?;
                if changed {
                    let newest = progress.borrow_and_update().clone();
                    if let Some(newest) = newest {
                        // Never let coalesced current cross an undelivered reliable completion cut.
                        if newest.head == self.delivered && newest.serial > self.seen_serial {
                            self.cut = Some(newest.cut());
                            continue;
                        }
                    }
                }
            }
            enum Wake {
                Cut(Result<Arc<ConversationCut>, broadcast::error::RecvError>),
                State(Result<ThreadLiveEvent, broadcast::error::RecvError>),
                Progress,
                Storage(Option<ThreadStorageState>),
                Terminal(bool),
                Slot,
            }
            let wake = tokio::select! {
                biased;
                _=self.cancel.cancelled()=>return Err(core::ChatError::Cancelled.into()),
                _=self.slot_changed.changed()=>Wake::Slot,
                cut=async { match self.cuts.as_mut() { Some(cuts)=>cuts.recv().await,None=>std::future::pending().await } }=>Wake::Cut(cut),
                _=async { match self.progress.as_mut() { Some(progress)=>{ let _=progress.changed().await; },None=>std::future::pending().await } }=>Wake::Progress,
                event=async { match self.state.as_mut() { Some(state)=>state.recv().await,None=>std::future::pending().await } }=>Wake::State(event),
                storage=async { match self.storage.as_mut() { Some(storage)=>{ let _=storage.changed().await;storage.borrow_and_update().clone() },None=>std::future::pending().await } }=>Wake::Storage(storage),
                open=async { match self.last_turn.as_mut() { Some(turn)=>turn.changed().await.is_ok(),None=>std::future::pending().await } }=>Wake::Terminal(open),
            };
            match wake {
                Wake::Slot => return Err(resync()),
                Wake::Cut(Ok(cut)) => self.cut = Some(cut),
                Wake::Cut(Err(_)) => return Err(resync()),
                Wake::State(Ok(event)) => self.state_event(event)?,
                Wake::State(Err(_)) => return Err(resync()),
                Wake::Progress => {
                    if let Some(progress) = self.progress.as_mut() {
                        let newest = progress.borrow_and_update().clone();
                        if let Some(newest) = newest
                            && newest.head == self.delivered
                            && newest.serial > self.seen_serial
                        {
                            self.cut = Some(newest.cut());
                        }
                    }
                }
                Wake::Storage(storage) => {
                    self.notification(ThreadNotification::StorageChanged {
                        storage: storage.map(Box::new),
                    })?
                }
                Wake::Terminal(false) => self.last_turn = None,
                Wake::Terminal(true) => {}
            }
        }
    }
}
