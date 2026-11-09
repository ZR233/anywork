//! Passive scoped completion delivery. One Set, monotonic Append prefixes, latest activity.
use super::{
    ConversationReader, StudioRuntime,
    conversation_reader::{
        JsonBudget, ReadResources, annotate_atoms, annotate_sources, core_demand, entries, query,
        resync,
    },
    thread_observation::ConversationSource,
};
#[cfg(test)]
pub(super) mod tests;
use anyhow::{Result, ensure};
use pl_core::chat as core;
use pl_protocol::*;
use std::sync::Arc;
use tokio::sync::watch;
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone)]
pub enum ConversationEvent {
    Chat { batch: Box<ChatBatch> },
    Activity { snapshot: Arc<ActivitySnapshot> },
}
pub struct ConversationFeed {
    reader: ConversationReader,
    initial: Option<ChatBatch>,
    initial_activity: Option<Arc<ActivitySnapshot>>,
    progress: Option<watch::Receiver<Option<Arc<ConversationSource>>>>,
    slot_changed: watch::Receiver<u64>,
    target: Option<Arc<CompletionTarget>>,
    delivered: u64,
    seen_serial: u64,
    activity_revision: u64,
    demand: ReadDemand,
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
        let registered = position.source.as_ref().map(|source| source.conversation());
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        let history = self.store.history(thread_id).await?;
        let mut progress = None;
        let mut initial_activity = Arc::new(ActivitySnapshot {
            revision: 0,
            completed_through: 0,
            execution_present: false,
            entries: Vec::new(),
        });
        let mut initial_serial = 0;
        let mut source_states = Vec::new();
        let mut cold_sources = None;
        let (session, database_id, head, effect_cut, items, boundary) = if let Some(registration) =
            registered
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
            if completed {
                source_states = source.current.source_states().to_vec();
            }
            let effect_cut = source.current.projection().source_effect_seq;
            progress = Some(progress_rx);
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
                history.cold_presentation_baseline().await?
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
                    cold_sources = Some(cold.sources);
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
            // The presentation facade shares read resources, never reads/annotates an
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
        let feed = ConversationFeed {
            reader,
            initial,
            initial_activity: completed.then_some(initial_activity),
            progress,
            slot_changed,
            target: None,
            delivered: head,
            seen_serial: initial_serial,
            activity_revision: 0,
            demand,
            cancel: CancellationToken::new(),
        };
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
    pub async fn close(&mut self) -> Result<()> {
        self.finish_production();
        Ok(())
    }
    pub(super) fn finish_production(&mut self) {
        self.cancel.cancel();
        self.progress = None;
        self.target = None;
        self.initial = None;
        self.initial_activity = None;
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
            if let Some(batch) = self.initial.take() {
                return Ok(Some(ConversationEvent::Chat {
                    batch: Box::new(batch),
                }));
            }
            if let Some(snapshot) = self.initial_activity.take() {
                ensure!(snapshot.completed_through == self.delivered, resync());
                self.activity_revision = snapshot.revision;
                return Ok(Some(ConversationEvent::Activity { snapshot }));
            }
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
        let progress_open = tokio::select! { biased;
            _ = self.cancel.cancelled() => return Err(core::ChatError::Cancelled.into()),
            _ = self.slot_changed.changed() => return Err(resync()),
            progress = async { match self.progress.as_mut() { Some(progress) => progress.changed().await.is_ok(), None => std::future::pending().await } } => progress,
        };
        ensure!(progress_open, resync());
        Ok(())
    }
}
