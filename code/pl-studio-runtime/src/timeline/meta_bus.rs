//! Single-point CoreEvent translator and per-thread MetaEventBus.
//!
//! Receives `CoreEvent` via `CoreEventSink` (non-blocking mpsc -> serial per-thread actor),
//! translates `CoreCommitEvent` into `HistoryEvent` ONCE in pure RAM, admits into
//! `HistoryStore::accept_new_in_memory` with ZERO SQLite reads, and broadcasts `ThreadMetaEvent`
//! to `TimelineDataLayer`, `LiveStatusDataLayer`, and `SessionMetaLayer`.

use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    fmt,
    sync::{Arc, Mutex, RwLock, Weak},
};

use anyhow::Result;
use pl_core::thread::{CoreCommitEvent, CoreEvent, CoreEventSink, HistoryExport};
use pl_core::usage::UsageOutcome;
use tokio::sync::{broadcast, mpsc, watch};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use crate::history::{
    HistoryEvent, HistoryEventKind, HistoryEventRecord, HistoryOriginalInfo, HistoryStore,
    HistoryTimelineRole, HistoryUsageFact, milliseconds_from_seconds,
};
use crate::studio::runtime::chat_item::{
    accepted_inbox_draft, accepted_input_draft, atom, build_active_tool_event,
    build_connection_event, build_event_from_draft, completion_draft, static_state,
};
use crate::studio::storage::thread_writer::batch::{
    BatchWriteContext, delivery_event, run_event, source_event, turn_event,
};
use crate::studio::thread_projection::{
    PreparedAccounting,
    live::{
        completion_ready,
        prepared::{prepared_turns, retained_resources, review_delivery_facts},
    },
    order, project_effect_items,
};
use crate::{
    ChatActiveStatus, ChatAtom, ChatAtomLifecycle, ChatDeliveryKind, ChatSourceId,
    ChatTerminalOutcome, ExecutionItem, ExecutionShape, Thread, ThreadToolState,
};

use super::live_status_layer::{LiveStatusDataLayer, STREAMING_TEXT_COALESCE_INTERVAL};
use super::models::{LiveStatusSnapshot, SessionMetaSnapshot};

const BROADCAST_CAPACITY: usize = 2048;

#[derive(Debug, Clone)]
pub enum ThreadMetaEvent {
    History {
        record: Arc<HistoryEventRecord>,
        input_id: Option<String>,
        turn_id: Option<String>,
    },
    LiveStatus(Arc<LiveStatusSnapshot>),
    SessionMeta(Arc<SessionMetaSnapshot>),
    Closed,
}

#[derive(Clone)]
struct TranslatorState {
    run: pl_core::thread::current::RuntimeEpoch,
    run_started_emitted: bool,
    next_ordinal: u64,
    emitted_tool_stages: BTreeMap<String, &'static str>,
    completed_drafts: BTreeSet<String>,
    translated_commit_seqs: BTreeSet<u64>,
}

impl TranslatorState {
    fn new(run: pl_core::thread::current::RuntimeEpoch) -> Self {
        Self {
            run,
            run_started_emitted: false,
            next_ordinal: 0,
            emitted_tool_stages: BTreeMap::new(),
            completed_drafts: BTreeSet::new(),
            translated_commit_seqs: BTreeSet::new(),
        }
    }

    fn reserve_ordinal(&mut self) -> u64 {
        self.next_ordinal = self.next_ordinal.saturating_add(1).max(1);
        self.next_ordinal
    }
}

struct Inner {
    runtime_epoch: pl_core::thread::current::RuntimeEpoch,
    thread: Mutex<Thread>,
    history: HistoryStore,
    tx: mpsc::UnboundedSender<CoreEvent>,
    broadcast: broadcast::Sender<ThreadMetaEvent>,
    recent_history: Mutex<VecDeque<Arc<HistoryEventRecord>>>,
    live_status: Arc<LiveStatusDataLayer>,
    latest_meta: RwLock<Option<Arc<SessionMetaSnapshot>>>,
    translator: tokio::sync::Mutex<TranslatorState>,
    processed_commits: Mutex<BTreeMap<u64, std::result::Result<(), Arc<anyhow::Error>>>>,
    processed_notify: watch::Sender<u64>,
    cancel: CancellationToken,
    tasks: TaskTracker,
}

#[derive(Debug)]
struct CommitAdmissionError {
    sequence: u64,
    error: Arc<anyhow::Error>,
}

impl fmt::Display for CommitAdmissionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "history commit {} was not admitted: {:#}",
            self.sequence, self.error
        )
    }
}

impl std::error::Error for CommitAdmissionError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(self.error.as_ref().as_ref())
    }
}

fn admission_failure_through(inner: &Inner, sequence: u64) -> Option<CommitAdmissionError> {
    inner
        .processed_commits
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .range(..=sequence)
        .find_map(|(&sequence, result)| {
            result.as_ref().err().map(|error| CommitAdmissionError {
                sequence,
                error: Arc::clone(error),
            })
        })
}

impl Drop for Inner {
    fn drop(&mut self) {
        self.cancel.cancel();
        let _ = self.broadcast.send(ThreadMetaEvent::Closed);
    }
}

/// Per-thread single event exit & broadcast bus.
#[derive(Clone)]
pub struct MetaEventBus {
    inner: Arc<Inner>,
}

impl fmt::Debug for MetaEventBus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("MetaEventBus")
            .field("thread_id", &self.inner.history.thread_id())
            .finish_non_exhaustive()
    }
}

/// Non-owning sink handle given to `pl-core::ThreadHandle::attach_event_sink` so `ThreadHandle`
/// does not create an `Arc` cycle or outlive explicit close.
#[derive(Clone)]
pub struct BusEventSink(Weak<Inner>);

impl fmt::Debug for BusEventSink {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("BusEventSink").finish_non_exhaustive()
    }
}

impl CoreEventSink for BusEventSink {
    fn emit(&self, event: CoreEvent) {
        if let Some(inner) = self.0.upgrade() {
            let _ = inner.tx.send(event);
        }
    }
}

impl CoreEventSink for MetaEventBus {
    fn emit(&self, event: CoreEvent) {
        let _ = self.inner.tx.send(event);
    }
}

impl MetaEventBus {
    /// Opens a `MetaEventBus` bound to a thread's `HistoryStore` (zero SQLite reads during live turns).
    #[must_use]
    pub fn open(
        thread: Thread,
        history: HistoryStore,
        runtime_epoch: pl_core::thread::current::RuntimeEpoch,
    ) -> Self {
        let (tx, rx) = mpsc::unbounded_channel();
        let (broadcast, _) = broadcast::channel(BROADCAST_CAPACITY);
        let live_status = Arc::new(LiveStatusDataLayer::new());
        let (processed_notify, _) = watch::channel(0);
        let cancel = CancellationToken::new();
        let tasks = TaskTracker::new();

        let inner = Arc::new(Inner {
            runtime_epoch,
            thread: Mutex::new(thread),
            history,
            tx,
            broadcast,
            recent_history: Mutex::new(VecDeque::new()),
            live_status,
            latest_meta: RwLock::new(None),
            translator: tokio::sync::Mutex::new(TranslatorState::new(runtime_epoch)),
            processed_commits: Mutex::new(BTreeMap::new()),
            processed_notify,
            cancel: cancel.clone(),
            tasks: tasks.clone(),
        });

        let weak = Arc::downgrade(&inner);
        tasks.spawn(run_serial_actor(weak, rx, cancel));

        Self { inner }
    }

    #[must_use]
    pub fn runtime_epoch(&self) -> pl_core::thread::current::RuntimeEpoch {
        self.inner.runtime_epoch
    }

    #[must_use]
    pub fn ptr_eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }

    #[must_use]
    pub fn sink(&self) -> BusEventSink {
        BusEventSink(Arc::downgrade(&self.inner))
    }

    pub fn emit_core_event(&self, event: CoreEvent) {
        let _ = self.inner.tx.send(event);
    }

    #[must_use]
    pub fn history(&self) -> &HistoryStore {
        &self.inner.history
    }

    #[must_use]
    pub fn live_status(&self) -> &Arc<LiveStatusDataLayer> {
        &self.inner.live_status
    }

    #[must_use]
    pub fn subscribe(&self) -> broadcast::Receiver<ThreadMetaEvent> {
        self.inner.broadcast.subscribe()
    }

    /// Call after subscribing. The receiver may also contain these records, which are deduped
    /// by sequence at the feed. A missed range requires an explicit cold re-open.
    pub(super) fn replay_history_after(&self, after: u64) -> Option<Vec<Arc<HistoryEventRecord>>> {
        let recent = self
            .inner
            .recent_history
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let head = self.inner.history.current_head();
        let records: Vec<_> = recent
            .iter()
            .filter(|record| record.seq > after)
            .cloned()
            .collect();
        (head.saturating_sub(after) == records.len() as u64).then_some(records)
    }

    #[must_use]
    pub fn latest_meta(&self) -> Option<Arc<SessionMetaSnapshot>> {
        self.inner
            .latest_meta
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub fn update_session_meta(&self, meta: SessionMetaSnapshot) {
        let arc = Arc::new(meta);
        *self
            .inner
            .latest_meta
            .write()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(arc.clone());
        let _ = self.inner.broadcast.send(ThreadMetaEvent::SessionMeta(arc));
    }

    pub fn update_thread(&self, thread: Thread) {
        *self
            .inner
            .thread
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = thread;
    }

    /// Publishes only newly admitted stable identities; replay candidates are not broadcast.
    /// Cumulative usage is prepared exclusively by the durable translator with its memory revision.
    pub async fn admit_and_broadcast(&self, events: Vec<HistoryEvent>) -> Result<Vec<u64>> {
        let _serial = self.inner.translator.lock().await;
        anyhow::ensure!(
            !events.iter().any(|event| matches!(
                event.row_scope,
                Some(
                    crate::history::HistoryBusinessRowScope::Accounting
                        | crate::history::HistoryBusinessRowScope::Cost
                )
            )),
            "cumulative usage must be prepared and admitted through the durable commit translator"
        );
        let revision = self.inner.history.memory_admission_revision();
        admit_and_broadcast_inner(&self.inner, &events, revision)
    }

    /// Waits for successful in-memory acceptance. Earlier failed commits cannot be hidden by a
    /// later success. Cancellation and a closed actor are failures, not acknowledgements.
    pub async fn wait_admitted_commit(&self, commit_seq: u64) -> Result<()> {
        if commit_seq == 0 {
            return Ok(());
        }
        let mut rx = self.inner.processed_notify.subscribe();
        loop {
            let done = {
                let outcomes = self
                    .inner
                    .processed_commits
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if let Some(error) =
                    outcomes
                        .range(..=commit_seq)
                        .find_map(|(&sequence, result)| {
                            result.as_ref().err().map(|error| CommitAdmissionError {
                                sequence,
                                error: Arc::clone(error),
                            })
                        })
                {
                    return Err(error.into());
                }
                outcomes
                    .get(&commit_seq)
                    .is_some_and(std::result::Result::is_ok)
            };
            if done {
                return Ok(());
            }
            tokio::select! {
                () = self.inner.cancel.cancelled() => anyhow::bail!("MetaEventBus closed before commit {commit_seq} was admitted"),
                changed = rx.changed() => {
                    if changed.is_err() {
                        anyhow::bail!("MetaEventBus actor closed before commit {commit_seq} was admitted");
                    }
                }
            }
        }
    }

    /// Waits until `MetaEventBus` has translated & admitted `commit_seq` and `HistoryStore`
    /// has flushed it to SQLite.
    pub async fn flush_through_commit(&self, commit_seq: u64) -> Result<()> {
        self.wait_admitted_commit(commit_seq).await?;
        self.inner.history.flush().await?;
        Ok(())
    }

    pub async fn close(&self) {
        self.inner.cancel.cancel();
        let _ = self.inner.broadcast.send(ThreadMetaEvent::Closed);
        self.inner.tasks.close();
        self.inner.tasks.wait().await;
    }
}

async fn run_serial_actor(
    weak: Weak<Inner>,
    mut rx: mpsc::UnboundedReceiver<CoreEvent>,
    cancel: CancellationToken,
) {
    let _actor_closed = cancel.clone().drop_guard();
    let mut ticker = tokio::time::interval(STREAMING_TEXT_COALESCE_INTERVAL);
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        tokio::select! {
            biased;
            () = cancel.cancelled() => break,
            _ = ticker.tick() => {
                if let Some(inner) = weak.upgrade()
                    && let Some(snapshot) = inner.live_status.flush_coalesced()
                {
                    let _ = inner.broadcast.send(ThreadMetaEvent::LiveStatus(Arc::new(snapshot)));
                }
            }
            maybe = rx.recv() => {
                let Some(event) = maybe else {
                    break;
                };
                let Some(inner) = weak.upgrade() else {
                    break;
                };
                match event {
                    CoreEvent::Live(live) => {
                        if let Some(snapshot) = inner.live_status.on_live_event(&live) {
                            let _ = inner.broadcast.send(ThreadMetaEvent::LiveStatus(Arc::new(snapshot)));
                        }
                    }
                    CoreEvent::Durable(commit) => {
                        let commit_seq = commit.export.effect.sequence;
                        let result = if let Some(error) = admission_failure_through(&inner, commit_seq.saturating_sub(1)) {
                            Err(error.into())
                        } else {
                            handle_durable_commit(&inner, commit).await
                        };
                        if let Err(error) = &result {
                            tracing::error!(thread_id = %inner.history.thread_id(), error = %error,
                                "MetaEventBus durable commit admission failed");
                        }
                        inner.processed_commits.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
                            .insert(commit_seq, result.map_err(Arc::new));
                        inner
                            .processed_notify
                            .send_modify(|n| *n = n.wrapping_add(1));
                    }
                }
            }
        }
    }
}

async fn handle_durable_commit(inner: &Arc<Inner>, commit: Arc<CoreCommitEvent>) -> Result<()> {
    let thread = inner
        .thread
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .clone();
    let database_id = inner.history.database_id().to_owned();
    let commit_seq = commit.export.effect.sequence;
    let mut translator = inner.translator.lock().await;
    if translator.translated_commit_seqs.contains(&commit_seq) {
        return Ok(());
    }
    let mut candidate = translator.clone();
    let revision = inner.history.memory_admission_revision();
    let events = translate_commit(
        &mut candidate,
        &inner.history,
        &thread,
        &database_id,
        &commit.export,
    )?;
    admit_and_broadcast_inner(inner, &events, revision)?;
    candidate.translated_commit_seqs.insert(commit_seq);
    *translator = candidate;
    Ok(())
}

fn admit_and_broadcast_inner(
    inner: &Arc<Inner>,
    events: &[HistoryEvent],
    usage_revision: u64,
) -> Result<Vec<u64>> {
    let records = {
        let mut recent = inner
            .recent_history
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let records = inner
            .history
            .accept_new_in_memory(events, usage_revision)?
            .into_iter()
            .map(Arc::new)
            .collect::<Vec<_>>();
        for record in &records {
            if recent.len() == BROADCAST_CAPACITY {
                recent.pop_front();
            }
            recent.push_back(Arc::clone(record));
        }
        records
    };
    let mut seqs = Vec::with_capacity(records.len());
    for record in records {
        seqs.push(record.seq);
        let input_id = match &record.source {
            Some(ChatSourceId::Input { input_id }) => Some(input_id.clone()),
            _ => None,
        };
        let turn_id = record.turn_id.clone();
        if let Some(snapshot) = inner.live_status.on_history_record(&record) {
            let _ = inner
                .broadcast
                .send(ThreadMetaEvent::LiveStatus(Arc::new(snapshot)));
        }
        let _ = inner.broadcast.send(ThreadMetaEvent::History {
            record,
            input_id,
            turn_id,
        });
    }
    Ok(seqs)
}

/// Translates one `CoreCommitEvent::export` into Schema 27 `HistoryEvent` rows strictly in RAM.
/// Guarantees `CompactionCompleted` uses `HistoryTimelineRole::Boundary` (`2`) and emits full
/// turn/source/resource/accounting/cost/delivery business rows without SQLite read queries.
fn translate_commit(
    state: &mut TranslatorState,
    history: &HistoryStore,
    thread: &Thread,
    database_id: &str,
    export: &HistoryExport,
) -> Result<Vec<HistoryEvent>> {
    let effect = &export.effect;
    let snapshot = &export.state;
    let run = state.run;
    let run_str = run.to_string();
    let recorded_at = milliseconds_from_seconds(effect.committed_at)?;
    let mut events = Vec::new();
    let mut local_anchors = BTreeSet::new();

    if !state.run_started_emitted {
        let run_ev = run_event(&run_str, recorded_at)?;
        if !history.event_exists_in_memory(&run_ev.event_id) {
            events.push(run_ev);
        }
        state.run_started_emitted = true;
    }

    let projected = project_effect_items(
        thread,
        snapshot,
        effect,
        &BTreeMap::new(),
        &BTreeMap::new(),
        &BTreeSet::new(),
    )?;

    let mut reserved_ordinals = BTreeMap::new();
    for item in &projected.items {
        reserved_ordinals.insert(item.id.clone(), state.reserve_ordinal());
    }
    let projected = if reserved_ordinals.is_empty() {
        projected
    } else {
        project_effect_items(
            thread,
            snapshot,
            effect,
            &BTreeMap::new(),
            &reserved_ordinals,
            &BTreeSet::new(),
        )?
    };

    // 1. Accepted user inputs.
    for change in effect.inputs.iter() {
        if let pl_core::thread::input::InputChange::Accepted(record) = change {
            let at = crate::ChatFactPosition {
                effect_seq: effect.sequence,
                suborder: 1,
            };
            if let Some(draft) =
                accepted_input_draft(thread, record, at, effect.committed_at, database_id)?
            {
                if !state.completed_drafts.insert(draft.item_id.clone())
                    || history.event_exists_in_memory(&draft.item_id)
                {
                    continue;
                }
                let mut atom_val = serde_json::from_slice::<ChatAtom>(&draft.metadata)?;
                atom_val.source = ChatSourceId::Input {
                    input_id: record.input.id.clone(),
                };
                atom_val.kind = crate::ChatAtomKind::Input;
                let ev = emit_draft_event(
                    &atom_val,
                    &draft,
                    HistoryEventKind::InputAccepted,
                    HistoryTimelineRole::Boundary,
                    run,
                    recorded_at,
                    database_id,
                )?;
                events.push(ev);
            }
        }
    }

    // 2. Accepted parent inbox messages (skipping forwarded final task results already sealed by tools).
    for record in effect.inbox.iter() {
        if snapshot
            .tasks
            .values()
            .chain(effect.tasks.iter())
            .any(|task| task.id == record.message.source_id)
        {
            continue;
        }
        let at = crate::ChatFactPosition {
            effect_seq: effect.sequence,
            suborder: 2,
        };
        if let Some(draft) =
            accepted_inbox_draft(thread, record, at, effect.committed_at, database_id)?
        {
            if !state.completed_drafts.insert(draft.item_id.clone())
                || history.event_exists_in_memory(&draft.item_id)
            {
                continue;
            }
            let mut atom_val = serde_json::from_slice::<ChatAtom>(&draft.metadata)?;
            atom_val.source = ChatSourceId::InboxMessage {
                source_id: record.message.source_id.clone(),
                message_id: record.message.id.clone(),
            };
            let ev = emit_draft_event(
                &atom_val,
                &draft,
                HistoryEventKind::InboxMessageReceived,
                HistoryTimelineRole::Boundary,
                run,
                recorded_at,
                database_id,
            )?;
            events.push(ev);
        }
    }

    // 3. Model connection events (Boundary = 2).
    for (index, conn) in effect.model_connection_events.iter().enumerate() {
        let kind = match conn.kind {
            pl_core::model::ModelConnectionEventKind::Disconnected => {
                HistoryEventKind::ConnectionDisconnected
            }
            pl_core::model::ModelConnectionEventKind::Reconnected => {
                HistoryEventKind::ConnectionReconnected
            }
        };
        let mut history_event = HistoryEvent::new(
            format!(
                "conn:model:{run}:{}:{}:{}",
                effect.sequence,
                index,
                conn.kind.as_str()
            ),
            kind,
            HistoryTimelineRole::Boundary,
            recorded_at,
        );
        history_event.occurred_at = Some(recorded_at);
        history_event.run_id = Some(run_str.clone());
        history_event.turn_id = Some(conn.turn_id.clone());
        history_event.attempt_id = Some(conn.attempt_id.clone());
        let mut data = serde_json::Map::new();
        data.insert(
            "state".into(),
            serde_json::Value::String(conn.kind.as_str().to_owned()),
        );
        data.insert("scope".into(), serde_json::Value::String("model".into()));
        data.insert(
            "transport".into(),
            serde_json::Value::String(conn.transport.clone()),
        );
        if let Some(fallback) = &conn.fallback_transport {
            data.insert(
                "fallbackTransport".into(),
                serde_json::Value::String(fallback.clone()),
            );
        }
        data.insert(
            "attempt".into(),
            serde_json::Value::Number(serde_json::Number::from(conn.retry)),
        );
        data.insert(
            "maxAttempts".into(),
            serde_json::Value::Number(serde_json::Number::from(conn.max_retries)),
        );
        data.insert(
            "recoverable".into(),
            serde_json::Value::Bool(conn.recoverable),
        );
        if let Some(reason) = &conn.reason {
            data.insert("reason".into(), serde_json::Value::String(reason.clone()));
        }
        if let Some(duration_ms) = conn.duration_ms {
            data.insert(
                "durationMs".into(),
                serde_json::Value::Number(serde_json::Number::from(duration_ms)),
            );
        }
        build_connection_event(&mut history_event, serde_json::Value::Object(data))?;
        events.push(history_event);
    }

    // 4. Retained resources, review deliveries, continuation sources, and immutable Turn business rows.
    for fact in retained_resources(effect)? {
        events.push(crate::studio::history_resources::observed_event(
            &fact.reference,
            &run_str,
            &fact.call_id,
            fact.turn_id.as_deref(),
            effect.sequence,
            recorded_at,
            database_id,
        )?);
    }
    for fact in review_delivery_facts(&thread.id, effect)? {
        events.push(delivery_event(
            &thread.id,
            "review_delivery",
            &fact.message.id,
            serde_json::to_string(&fact)?,
            run,
            BatchWriteContext {
                recorded_at,
                anchor: false,
                database_id,
            },
        )?);
    }
    for operation in effect.continuations.iter() {
        let ended = !matches!(
            operation.disposition,
            pl_core::thread::ContinuationDisposition::Scheduled
        );
        let source_head = crate::history::HistorySourceHead {
            source: crate::HistorySource::Operation {
                operation_id: operation.request.operation_id.clone(),
            },
            lifecycle: match operation.disposition {
                pl_core::thread::ContinuationDisposition::Scheduled => {
                    crate::ChatSourceLifecycle::Active
                }
                pl_core::thread::ContinuationDisposition::Effective => {
                    crate::ChatSourceLifecycle::Ended {
                        outcome: ChatTerminalOutcome::Completed,
                    }
                }
                pl_core::thread::ContinuationDisposition::NotExecuted(_) => {
                    crate::ChatSourceLifecycle::Ended {
                        outcome: ChatTerminalOutcome::Cancelled,
                    }
                }
            },
            started_at: Some(recorded_at),
            ended_at: ended.then_some(recorded_at),
            observed_at: Some(recorded_at),
            detail_event_id: None,
        };
        let identity = serde_json::to_string(&source_head.source)?;
        let row = format!("source:{identity}");
        let anchor = local_anchors.insert(row.clone()) && !history.anchor_exists_in_memory(&row);
        let payload = pl_core::context::OpaquePayload::new(
            "pl.core.resume-operation",
            1,
            serde_json::to_string(operation)?,
        )?;
        events.push(source_event(
            &source_head,
            Some(serde_json::to_vec(&payload)?),
            Some(&operation.request.operation_id),
            Some(operation.acceptance_epoch.to_string()),
            Some(operation.turn_id.clone()),
            BatchWriteContext {
                recorded_at,
                anchor,
                database_id,
            },
        )?);
    }
    let (history_turns, history_turn_details) =
        prepared_turns(&projected.items, run, effect.sequence)?;
    for turn in &history_turns {
        let row = format!("turn:{}", turn.turn_id);
        let anchor = local_anchors.insert(row.clone()) && !history.anchor_exists_in_memory(&row);
        let ev = turn_event(
            format!("turn:{}:{}:{}", run_str, turn.turn_id, effect.sequence),
            turn,
            history_turn_details.get(&turn.turn_id),
            recorded_at,
            anchor,
            database_id,
        )?;
        events.push(ev);
    }

    // 5. Pure-RAM usage & cost business rows (`anywork.accounting/1`, `anywork.cost/1`).
    let accounting = PreparedAccounting::shared(effect)?;
    if !accounting.facts.is_empty() {
        let mut usage_facts = Vec::with_capacity(accounting.facts.len());
        for fact in accounting.facts.iter() {
            let outcome = match fact.status {
                crate::studio::storage::calls::CallStatus::Committed => UsageOutcome::Succeeded,
                crate::studio::storage::calls::CallStatus::Rejected => UsageOutcome::Rejected,
                crate::studio::storage::calls::CallStatus::Cancelled => UsageOutcome::Cancelled,
                crate::studio::storage::calls::CallStatus::Interrupted => UsageOutcome::Interrupted,
                crate::studio::storage::calls::CallStatus::Failed => UsageOutcome::Failed,
                crate::studio::storage::calls::CallStatus::Running => {
                    anyhow::bail!("running accounting fact cannot enter history")
                }
            };
            usage_facts.push(HistoryUsageFact {
                event_id: format!("usage:settlement:{}", fact.record.inference_id),
                runtime_epoch: run,
                turn_id: fact.turn_id.clone(),
                outcome,
                record: fact.record.clone(),
                settlement: Some(fact.settlement.clone()),
            });
        }
        events.extend(history.prepare_usage_in_memory(&usage_facts)?);
    }

    // 6. Active non-terminal tool stages + terminal execution items.
    for item in &projected.items {
        if !completion_ready(item) {
            if let ExecutionShape::Tool(tool) = item.state() {
                let call_id = tool.invocation().tool_call_id();
                let waiting = matches!(tool.state(), ThreadToolState::AwaitingApproval(_))
                    || tool.user_input().is_some_and(|i| {
                        matches!(i.state(), crate::ThreadToolUserInputState::Pending)
                    });
                let task = effect
                    .tasks
                    .iter()
                    .find(|t| t.call_id == call_id)
                    .or_else(|| snapshot.tasks.values().find(|t| t.call_id == call_id));
                let cancel_requested = task.is_some_and(|t| t.cancel_requested);
                let stage_key = if cancel_requested {
                    "cancel_requested"
                } else if waiting {
                    "waiting_approval"
                } else {
                    "called"
                };
                if state.emitted_tool_stages.get(call_id).copied() != Some(stage_key) {
                    state
                        .emitted_tool_stages
                        .insert(call_id.to_owned(), stage_key);
                    let kind = match stage_key {
                        "waiting_approval" => HistoryEventKind::ToolWaitingApproval,
                        "cancel_requested" => HistoryEventKind::ToolCancelRequested,
                        _ => HistoryEventKind::ToolCalled,
                    };
                    let mut atom_val = atom(&ExecutionItem::new(
                        item.id.clone(),
                        crate::studio::thread_projection::ItemStamp {
                            thread_id: std::borrow::Cow::Borrowed(&item.thread_id),
                            turn_id: std::borrow::Cow::Borrowed(&item.turn_id),
                            ordinal: item.ordinal,
                            revision: item.revision,
                            created_at: item.created_at,
                            updated_at: item.updated_at,
                        },
                        static_state(item.state()),
                    ));
                    if waiting {
                        atom_val.lifecycle = ChatAtomLifecycle::Active {
                            started: None,
                            status: ChatActiveStatus::Waiting,
                        };
                        atom_val.finished_at = None;
                    }
                    let role = if crate::studio::thread_projection::work(&atom_val) {
                        HistoryTimelineRole::Work
                    } else {
                        HistoryTimelineRole::Hidden
                    };
                    let mut history_event = HistoryEvent::new(
                        format!(
                            "tool-stage:{run}:{}:{}:{}",
                            effect.sequence,
                            call_id,
                            kind.as_str()
                        ),
                        kind,
                        role,
                        recorded_at,
                    );
                    history_event.occurred_at = Some(recorded_at);
                    history_event.run_id = Some(run_str.clone());
                    history_event.turn_id =
                        (!item.turn_id.is_empty()).then(|| item.turn_id.clone());
                    history_event.call_id = Some(call_id.to_owned());
                    history_event.entity_id = Some(item.id.clone());
                    history_event.tool_name = Some(tool.invocation().name().to_owned());
                    build_active_tool_event(
                        &mut history_event,
                        &atom_val,
                        item,
                        cancel_requested,
                        database_id,
                    )?;
                    events.push(history_event);
                }
            }
            continue;
        }

        if matches!(item.state(), ExecutionShape::Turn(_)) {
            continue;
        }

        // Terminal item -> freeze draft & emit canonical HistoryEvent once per item_id.
        if !state.completed_drafts.insert(item.id.clone())
            || history.event_exists_in_memory(&item.id)
        {
            continue;
        }
        let original_body =
            crate::studio::thread_projection::live::prepared::original_tool_result_body(
                item, snapshot,
            );
        let draft = completion_draft(item, effect.sequence, database_id, original_body)?;
        let mut atom_val = serde_json::from_slice::<ChatAtom>(&draft.metadata)?;
        atom_val.source_order = Some(item.ordinal);
        if let Some(tool) = &atom_val.tool {
            state.emitted_tool_stages.remove(&tool.call_id);
        }
        let kind = match atom_val.kind {
            crate::ChatAtomKind::Input => HistoryEventKind::InputAccepted,
            crate::ChatAtomKind::Text => HistoryEventKind::TextCompleted,
            crate::ChatAtomKind::Reasoning => HistoryEventKind::ReasoningCompleted,
            crate::ChatAtomKind::Plan => HistoryEventKind::PlanResolved,
            crate::ChatAtomKind::Compaction => HistoryEventKind::CompactionCompleted,
            crate::ChatAtomKind::Agent => HistoryEventKind::AgentCompleted,
            crate::ChatAtomKind::TurnReceipt => HistoryEventKind::TurnReceiptRecorded,
            crate::ChatAtomKind::ToolCall | crate::ChatAtomKind::Interaction => {
                if atom_val.delivery == ChatDeliveryKind::BackgroundHandoff {
                    HistoryEventKind::ToolBackgrounded
                } else {
                    HistoryEventKind::ToolCompleted
                }
            }
            _ => HistoryEventKind::ItemRecorded,
        };
        let role = if matches!(kind, HistoryEventKind::CompactionCompleted) {
            HistoryTimelineRole::Boundary
        } else if crate::studio::thread_projection::hidden(&atom_val) {
            HistoryTimelineRole::Hidden
        } else if crate::studio::thread_projection::work(&atom_val) {
            HistoryTimelineRole::Work
        } else if atom_val.kind == crate::ChatAtomKind::Text
            && atom_val.content_present == Some(false)
        {
            HistoryTimelineRole::Hidden
        } else {
            HistoryTimelineRole::Boundary
        };
        let mut ev =
            emit_draft_event(&atom_val, &draft, kind, role, run, recorded_at, database_id)?;
        if ev.turn_id.is_none() && !item.turn_id.is_empty() {
            ev.turn_id = Some(item.turn_id.clone());
        }
        events.push(ev);
    }

    // 7. Terminal turn receipt when turn failed / cancelled / interrupted / budget-limited
    // (or synthetic hidden TurnEnded if `projected.items` had no Turn entity).
    if let Some(turn) = &effect.turn {
        let is_terminal = turn.state != pl_core::thread::TurnState::Running;
        let has_projected_turn = history_turns.iter().any(|t| t.turn_id == turn.turn_id);
        if !has_projected_turn {
            let kind = if is_terminal {
                HistoryEventKind::TurnEnded
            } else {
                HistoryEventKind::TurnStarted
            };
            let mut ev = HistoryEvent::new(
                format!("turn:{}:{}:{}", run_str, effect.sequence, kind.as_str()),
                kind,
                HistoryTimelineRole::Hidden,
                recorded_at,
            );
            ev.occurred_at = Some(recorded_at);
            ev.run_id = Some(run_str.clone());
            ev.turn_id = Some(turn.turn_id.clone());
            ev.payload_schema = "anywork.business/1".into();
            ev.payload_json = serde_json::json!({
                "factType": ev.kind.as_str(),
                "turnId": turn.turn_id,
                "inputId": turn.input_id,
            })
            .to_string();
            events.push(ev);
        }

        if is_terminal {
            let outcome = match &turn.state {
                pl_core::thread::TurnState::Failed { description, .. } => {
                    Some(("failed", Some(description.clone())))
                }
                pl_core::thread::TurnState::Cancelled => Some(("cancelled", None)),
                pl_core::thread::TurnState::Interrupted => Some(("interrupted", None)),
                pl_core::thread::TurnState::Finished(pl_core::thread::TurnOutcome::StepLimit) => {
                    Some(("budgetLimited", None))
                }
                _ => None,
            };
            if let Some((outcome_kind, reason)) = outcome {
                let mut receipt = HistoryEvent::new(
                    order::turn_id(&turn.turn_id),
                    HistoryEventKind::TurnReceiptRecorded,
                    HistoryTimelineRole::Boundary,
                    recorded_at,
                );
                receipt.occurred_at = Some(recorded_at);
                receipt.run_id = Some(run_str);
                receipt.turn_id = Some(turn.turn_id.clone());
                receipt.entity_id = Some(order::turn_id(&turn.turn_id));
                let projected_failure =
                    history_turn_details
                        .get(&turn.turn_id)
                        .and_then(|t| match &t.state {
                            crate::TurnState::Failed(failed) => {
                                serde_json::to_value(failed.failure()).ok()
                            }
                            _ => None,
                        });
                let data = serde_json::json!({
                    "inputId": turn.input_id,
                    "outcome": {
                        "kind": outcome_kind,
                        "data": {
                            "reason": reason,
                            "failure": projected_failure,
                        },
                    }
                });
                let envelope = crate::history::EventPayloadEnvelope {
                    contract: "anywork.event/1".into(),
                    item_type: "turn".into(),
                    meta: crate::history::HistoryEventMeta {
                        entity_id: order::turn_id(&turn.turn_id),
                        entity_kind: crate::ChatAtomKind::TurnReceipt,
                        delivery: ChatDeliveryKind::Independent,
                        state: crate::history::HistoryEntityState::KnownTerminal {
                            outcome: match outcome_kind {
                                "failed" => ChatTerminalOutcome::Failed,
                                "cancelled" => ChatTerminalOutcome::Cancelled,
                                _ => ChatTerminalOutcome::Completed,
                            },
                        },
                        started_at: Some(recorded_at),
                        finished_at: Some(recorded_at),
                        text_channel: None,
                        model_recovery: None,
                        single_visibility: None,
                        presentation_contract: None,
                        source_order: None,
                        content_present: Some(false),
                        wait: None,
                        tool: None,
                    },
                    data,
                    bodies: Vec::new(),
                    source_order: None,
                    turn_id: Some(turn.turn_id.clone()),
                    captured_at: Some(recorded_at),
                };
                receipt.payload_schema = "anywork.event/1".into();
                receipt.payload_json = serde_json::to_string(&envelope)?;
                events.push(receipt);
            }
        }
    }

    Ok(events)
}

fn emit_draft_event(
    atom_val: &ChatAtom,
    draft: &pl_core::chat::ChatDraft,
    kind: HistoryEventKind,
    role: HistoryTimelineRole,
    run: pl_core::thread::current::RuntimeEpoch,
    recorded_at: i64,
    database_id: &str,
) -> Result<HistoryEvent> {
    let mut event = HistoryEvent::new(draft.item_id.clone(), kind, role, recorded_at);
    event.occurred_at = atom_val
        .finished_at
        .or(atom_val.started_at)
        .map(milliseconds_from_seconds)
        .transpose()?;
    event.run_id = Some(run.to_string());
    event.turn_id = atom_val.turn_id.clone();
    event.attempt_id = atom_val.attempt_id.clone();
    event.entity_id = Some(atom_val.id.clone());
    event.source = Some(atom_val.source.clone());
    event.message_id = match &atom_val.source {
        ChatSourceId::InboxMessage { message_id, .. }
        | ChatSourceId::BackgroundResult { message_id } => Some(message_id.clone()),
        _ => None,
    };
    event.original = Some(HistoryOriginalInfo {
        query_class: draft.query_class.clone(),
        parent_id: draft
            .parent_id
            .as_ref()
            .map(|parent| parent.as_str().to_owned()),
        original_kind: atom_val.kind,
        tool_name: atom_val.tool.as_ref().map(|tool| tool.name.clone()),
    });
    if let Some(tool) = &atom_val.tool {
        event.call_id = Some(tool.call_id.clone());
        event.tool_name = Some(tool.name.clone());
    }
    build_event_from_draft(&mut event, atom_val, draft, database_id, Vec::new())?;
    Ok(event)
}
