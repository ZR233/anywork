use std::{
    collections::{BTreeMap, BTreeSet},
    path::Path,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};

use sea_orm::{
    ConnectionTrait, DatabaseConnection, SqliteTransactionMode, TransactionOptions,
    TransactionTrait,
};
use tokio::sync::{Notify, Semaphore, watch};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use super::{
    db::{self, Body, KnownBodyMeta, KnownIndex, Record},
    pending::{Accepted, Pending, Reservation},
    writer_lease::WriterLease,
    *,
};

pub(super) struct State {
    pub pending: Arc<Pending>,
    pub head: u64,
    pub accepting: bool,
    pub closing: bool,
    pub write_error: Option<String>,
    pub usage_revision: u64,
}

/// Serializes strict writers and remembers the cumulative usage state they prepared against.
/// Live admission never acquires the asynchronous writer lock.
pub(crate) struct HistoryAdmissionGuard<'a> {
    _writer: tokio::sync::MutexGuard<'a, ()>,
    usage_revision: AtomicU64,
}

#[cfg(test)]
#[derive(Default)]
pub(crate) struct StrictValidationGate {
    pub(crate) arrived: Notify,
    pub(crate) resume: Notify,
}

#[derive(Debug, thiserror::Error)]
#[error("accounting/cost preparation was superseded by another admission")]
struct UsagePreparationChanged;

impl HistoryError {
    pub(crate) fn is_usage_preparation_changed(&self) -> bool {
        matches!(self, Self::Storage(error) if error.is::<UsagePreparationChanged>())
    }
}

impl HistoryAdmissionGuard<'_> {
    pub(crate) fn usage_revision(&self) -> u64 {
        self.usage_revision.load(Ordering::Relaxed)
    }
}

enum StrictAdmission {
    Read {
        pending: Arc<Pending>,
        indices: Vec<usize>,
    },
    Accepted(Vec<u64>),
}

pub(super) struct Inner {
    pub thread_id: String,
    pub read_only: bool,
    pub database_id: String,
    pub limits: HistoryLimits,
    pub writer: DatabaseConnection,
    pub reader: DatabaseConnection,
    pub state: Mutex<State>,
    pub(super) known: Mutex<KnownIndex>,
    pub read_query_count: AtomicU64,
    durable_head: AtomicU64,
    worker_notify: Arc<Notify>,
    pub event_permits: Arc<Semaphore>,
    pub byte_permits: Arc<Semaphore>,
    pub changed: watch::Sender<u64>,
    pub cancel: CancellationToken,
    pub operations: TaskTracker,
    pub(super) admission: tokio::sync::Mutex<()>,
    flush_lock: tokio::sync::Mutex<()>,
    #[cfg(test)]
    strict_validation_gate: Mutex<Option<Arc<StrictValidationGate>>>,
    lease: Mutex<Option<WriterLease>>,
}

#[derive(Clone)]
pub struct HistoryStore {
    pub(super) inner: Arc<Inner>,
}

impl std::fmt::Debug for HistoryStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HistoryStore")
            .field("thread_id", &self.inner.thread_id)
            .field("database_id", &self.inner.database_id)
            .field("read_only", &self.inner.read_only)
            .finish()
    }
}

#[derive(Clone)]
pub struct HistoryStoreShare(std::sync::Weak<Inner>);

impl std::fmt::Debug for HistoryStoreShare {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HistoryStoreShare").finish_non_exhaustive()
    }
}

fn validate_limits(limits: HistoryLimits) -> Result<()> {
    if limits.pending_events == 0 || limits.pending_bytes == 0 {
        return Err(HistoryError::InvalidDemand(
            "history pending limits must be positive".into(),
        ));
    }
    Ok(())
}

impl HistoryStore {
    pub async fn open_reader(
        path: impl AsRef<Path>,
        thread_id: &str,
        limits: HistoryLimits,
    ) -> Result<HistoryReader> {
        if thread_id.is_empty() {
            return Err(HistoryError::InvalidEvent(
                "Thread identity must not be empty".into(),
            ));
        }
        validate_limits(limits)?;
        let path = path.as_ref();
        if !path.try_exists()? {
            return Err(HistoryError::NotFound(path.display().to_string()));
        }
        let reader = schema::connect(path, true, false).await?;
        let (database_id, head) = schema::identity(&reader, thread_id).await?;
        upgrade::schema26_manifest::require_current(&reader).await?;
        let (changed, _) = watch::channel(head);
        let store = Self {
            inner: Arc::new(Inner {
                thread_id: thread_id.to_owned(),
                read_only: true,
                database_id,
                limits,
                writer: reader.clone(),
                reader,
                state: Mutex::new(State {
                    pending: Arc::new(Pending::new()),
                    head,
                    accepting: false,
                    closing: false,
                    write_error: None,
                    usage_revision: 0,
                }),
                known: Mutex::new(KnownIndex::default()),
                read_query_count: AtomicU64::new(0),
                durable_head: AtomicU64::new(head),
                worker_notify: Arc::new(Notify::new()),
                event_permits: Arc::new(Semaphore::new(limits.pending_events as usize)),
                byte_permits: Arc::new(Semaphore::new(limits.pending_bytes as usize)),
                changed,
                cancel: CancellationToken::new(),
                operations: TaskTracker::new(),
                admission: tokio::sync::Mutex::new(()),
                flush_lock: tokio::sync::Mutex::new(()),
                #[cfg(test)]
                strict_validation_gate: Mutex::new(None),
                lease: Mutex::new(None),
            }),
        };
        Ok(store.reader())
    }

    pub async fn open(
        path: impl AsRef<Path>,
        thread_id: &str,
        limits: HistoryLimits,
    ) -> Result<Self> {
        if thread_id.is_empty() {
            return Err(HistoryError::InvalidEvent(
                "Thread identity must not be empty".into(),
            ));
        }
        validate_limits(limits)?;
        let path = path.as_ref();
        if let Some(parent) = path.parent()
            && !parent.as_os_str().is_empty()
        {
            tokio::fs::create_dir_all(parent).await?;
        }
        let lease = WriterLease::acquire(path)?;
        let existed = path.try_exists()?;
        let writer = schema::connect(path, false, !existed).await?;
        if !existed {
            if let Err(error) = schema::initialize(&writer, thread_id).await {
                let _ = writer.close().await;
                return Err(error);
            }
        } else {
            let empty_db = writer
                .query_one_raw(db::statement(
                    "SELECT 1 FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' LIMIT 1",
                    vec![],
                ))
                .await?
                .is_none();
            if empty_db && let Err(error) = schema::initialize(&writer, thread_id).await {
                let _ = writer.close().await;
                return Err(error);
            }
        }
        let (database_id, head) = match schema::identity(&writer, thread_id).await {
            Ok(identity) => identity,
            Err(error) => {
                let _ = writer.close().await;
                return Err(error);
            }
        };
        if let Err(error) = upgrade::schema26_manifest::require_current(&writer).await {
            let _ = writer.close().await;
            return Err(error);
        }
        let known = if head > 0 {
            match db::load_known_index(&writer).await {
                Ok(known) => known,
                Err(error) => {
                    let _ = writer.close().await;
                    return Err(error);
                }
            }
        } else {
            KnownIndex::default()
        };
        let reader = match schema::connect(path, true, false).await {
            Ok(reader) => reader,
            Err(error) => {
                let _ = writer.close().await;
                return Err(error);
            }
        };
        let (changed, _) = watch::channel(head);
        let store = Self {
            inner: Arc::new(Inner {
                thread_id: thread_id.to_owned(),
                read_only: false,
                database_id,
                limits,
                writer,
                reader,
                state: Mutex::new(State {
                    pending: Arc::new(Pending::new()),
                    head,
                    accepting: true,
                    closing: false,
                    write_error: None,
                    usage_revision: 0,
                }),
                known: Mutex::new(known),
                read_query_count: AtomicU64::new(0),
                durable_head: AtomicU64::new(head),
                worker_notify: Arc::new(Notify::new()),
                event_permits: Arc::new(Semaphore::new(limits.pending_events as usize)),
                byte_permits: Arc::new(Semaphore::new(limits.pending_bytes as usize)),
                changed,
                cancel: CancellationToken::new(),
                operations: TaskTracker::new(),
                admission: tokio::sync::Mutex::new(()),
                flush_lock: tokio::sync::Mutex::new(()),
                #[cfg(test)]
                strict_validation_gate: Mutex::new(None),
                lease: Mutex::new(Some(lease)),
            }),
        };
        spawn_persist_worker(&store);
        Ok(store)
    }

    pub fn read_query_count(&self) -> u64 {
        self.inner.read_query_count.load(Ordering::Relaxed)
    }

    pub fn durable_head(&self) -> u64 {
        self.inner.durable_head.load(Ordering::Relaxed)
    }

    pub fn current_head(&self) -> u64 {
        self.inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .head
    }

    pub async fn accept_in_memory(&self, events: &[HistoryEvent]) -> Result<Vec<u64>> {
        self.accept_batch(events).await
    }

    #[cfg(test)]
    pub(crate) async fn pause_flush(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.inner.flush_lock.lock().await
    }

    #[cfg(test)]
    pub(crate) fn pause_strict_validation(&self) -> Arc<StrictValidationGate> {
        let gate = Arc::new(StrictValidationGate::default());
        *self
            .inner
            .strict_validation_gate
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(gate.clone());
        gate
    }

    pub fn database_id(&self) -> &str {
        &self.inner.database_id
    }

    pub fn thread_id(&self) -> &str {
        &self.inner.thread_id
    }

    pub(crate) fn event_exists_in_memory(&self, event_id: &str) -> bool {
        let state = self
            .inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.pending.event(event_id).is_some() {
            return true;
        }
        self.inner
            .known
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .events
            .contains(event_id)
    }

    pub(crate) fn anchor_exists_in_memory(&self, row: &str) -> bool {
        let state = self
            .inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.pending.anchors.contains_key(row) {
            return true;
        }
        self.inner
            .known
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .anchors
            .contains(row)
    }

    pub fn reader(&self) -> HistoryReader {
        HistoryReader::new(self.inner.clone())
    }

    pub fn shared(&self) -> HistoryStoreShare {
        HistoryStoreShare(Arc::downgrade(&self.inner))
    }

    pub fn from_share(share: &HistoryStoreShare) -> Option<Self> {
        share.0.upgrade().map(|inner| Self { inner })
    }

    pub(crate) async fn anchor_exists(&self, row: &str) -> Result<bool> {
        {
            let state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.closing {
                return Err(HistoryError::Closed);
            }
            if state.pending.anchors.contains_key(row) {
                return Ok(true);
            }
            if !self.inner.read_only
                && self
                    .inner
                    .known
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .anchors
                    .contains(row)
            {
                return Ok(true);
            }
        }
        if !self.inner.read_only {
            return Ok(false);
        }
        self.inner.read_query_count.fetch_add(1, Ordering::Relaxed);
        Ok(db::anchor(&self.inner.reader, row).await?.is_some())
    }

    pub fn status(&self) -> HistoryStatus {
        let state = self
            .inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let pending_events = state.pending.events.len();
        let pending_bytes = state.pending.bytes;
        let max_events = self.inner.limits.pending_events as usize;
        let max_bytes = self.inner.limits.pending_bytes as usize;
        let retained_events =
            max_events.saturating_sub(self.inner.event_permits.available_permits());
        let retained_bytes = max_bytes.saturating_sub(self.inner.byte_permits.available_permits());
        HistoryStatus {
            pending_events,
            pending_bytes,
            retained_events,
            retained_bytes,
            write_error: state.write_error.clone(),
            accepting: state.accepting,
        }
    }

    pub async fn accept_batch(&self, events: &[HistoryEvent]) -> Result<Vec<u64>> {
        let admission = self.admission_guard().await;
        self.accept_locked(&admission, events).await
    }

    pub(crate) async fn admission_guard(&self) -> HistoryAdmissionGuard<'_> {
        let writer = self.inner.admission.lock().await;
        let usage_revision = self.memory_admission_revision();
        HistoryAdmissionGuard {
            _writer: writer,
            usage_revision: AtomicU64::new(usage_revision),
        }
    }

    /// Capture before deriving accounting/cost candidates, not after preparing them.
    pub(crate) fn memory_admission_revision(&self) -> u64 {
        self.inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .usage_revision
    }

    /// Admits only unseen stable identities. Replays are discarded without interpreting their
    /// candidate payload or consulting persistence. Returns exactly the newly accepted records.
    pub(crate) fn accept_new_in_memory(
        &self,
        events: &[HistoryEvent],
        usage_revision: u64,
    ) -> Result<Vec<HistoryEventRecord>> {
        if self.inner.read_only {
            return Err(HistoryError::Closed);
        }
        let mut state = self
            .inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !state.accepting || state.closing {
            return Err(HistoryError::Closed);
        }
        let mut known = self
            .inner
            .known
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut unseen = Vec::new();
        let mut identities = BTreeSet::new();
        for (idx, event) in events.iter().enumerate() {
            if !identities.insert(event.event_id.as_str()) {
                return Err(HistoryError::Conflict(format!(
                    "duplicate event_id {} in batch",
                    event.event_id
                )));
            }
            if !known.events.contains(&event.event_id) {
                unseen.push(idx);
            }
        }
        let retained_sizes = unseen
            .iter()
            .map(|&idx| validate::event(&events[idx]))
            .collect::<Result<Vec<_>>>()?;
        let records = self.commit_new_events(
            &mut state,
            &mut known,
            events,
            &unseen,
            &retained_sizes,
            usage_revision,
        )?;
        drop(known);
        drop(state);
        self.notify_admission(&records);
        Ok(records)
    }

    pub(crate) async fn accept_locked(
        &self,
        admission: &HistoryAdmissionGuard<'_>,
        events: &[HistoryEvent],
    ) -> Result<Vec<u64>> {
        self.accept_locked_at_revision(admission, events, admission.usage_revision())
            .await
    }

    pub(crate) async fn accept_locked_at_revision(
        &self,
        admission: &HistoryAdmissionGuard<'_>,
        events: &[HistoryEvent],
        usage_revision: u64,
    ) -> Result<Vec<u64>> {
        if self.inner.read_only {
            return Err(HistoryError::Closed);
        }
        if events.is_empty() {
            return Ok(Vec::new());
        }
        let mut identities = BTreeSet::new();
        let mut body_ids = BTreeSet::new();
        for event in events {
            validate::event(event)?;
            if !identities.insert(event.event_id.as_str()) {
                return Err(HistoryError::Conflict(format!(
                    "duplicate event_id {} in batch",
                    event.event_id
                )));
            }
            for body in &event.bodies {
                if !body_ids.insert(body.body_id.as_str()) {
                    return Err(HistoryError::Conflict(format!(
                        "duplicate body_id {} in batch",
                        body.body_id
                    )));
                }
            }
        }
        let mut verified = BTreeMap::new();
        loop {
            // Classification and final commit share the same current state/known lock order.
            // All SQLite validation happens after releasing both locks.
            let attempt = {
                let mut state = self
                    .inner
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if !state.accepting || state.closing {
                    return Err(HistoryError::Closed);
                }
                let mut known = self
                    .inner
                    .known
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                let mut assigned = vec![0; events.len()];
                let mut new_indices = Vec::new();
                let mut persisted = Vec::new();
                for (idx, event) in events.iter().enumerate() {
                    if let Some(accepted) = state.pending.event(&event.event_id) {
                        let existing = Record::from_event(&accepted.event);
                        ensure_same_pending_event(&state.pending, &existing, event)?;
                        assigned[idx] = existing.record.seq;
                    } else if known.events.contains(&event.event_id) {
                        if let Some(&seq) = verified.get(&idx) {
                            assigned[idx] = seq;
                        } else {
                            persisted.push(idx);
                        }
                    } else {
                        new_indices.push(idx);
                    }
                }
                if !persisted.is_empty() {
                    StrictAdmission::Read {
                        pending: state.pending.clone(),
                        indices: persisted,
                    }
                } else {
                    let retained_sizes = new_indices
                        .iter()
                        .map(|&idx| validate::event(&events[idx]))
                        .collect::<Result<Vec<_>>>()?;
                    let records = self.commit_new_events(
                        &mut state,
                        &mut known,
                        events,
                        &new_indices,
                        &retained_sizes,
                        usage_revision,
                    )?;
                    for (&idx, record) in new_indices.iter().zip(&records) {
                        assigned[idx] = record.seq;
                    }
                    admission
                        .usage_revision
                        .store(state.usage_revision, Ordering::Relaxed);
                    drop(known);
                    drop(state);
                    self.notify_admission(&records);
                    StrictAdmission::Accepted(assigned)
                }
            };
            match attempt {
                StrictAdmission::Accepted(assigned) => return Ok(assigned),
                StrictAdmission::Read { pending, indices } => {
                    self.inner.read_query_count.fetch_add(1, Ordering::Relaxed);
                    let tx = self.inner.reader.begin().await?;
                    for idx in indices {
                        let event = &events[idx];
                        let existing = db::event(&tx, &event.event_id).await?.ok_or_else(|| {
                            HistoryError::Integrity(format!(
                                "known event {} missing from sqlite",
                                event.event_id
                            ))
                        })?;
                        ensure_same_event(&tx, &pending, &existing, event).await?;
                        verified.insert(idx, existing.record.seq);
                    }
                    tx.commit().await?;
                    #[cfg(test)]
                    {
                        let gate = self
                            .inner
                            .strict_validation_gate
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .take();
                        if let Some(gate) = gate {
                            gate.arrived.notify_one();
                            gate.resume.notified().await;
                        }
                    }
                    // A hot admission may have taken any previously-new ID, anchor or body ID
                    // while SQLite was awaited. Reclassify and validate before assigning seqs.
                }
            }
        }
    }

    fn commit_new_events(
        &self,
        state: &mut State,
        known: &mut KnownIndex,
        events: &[HistoryEvent],
        indices: &[usize],
        retained_sizes: &[usize],
        usage_revision: u64,
    ) -> Result<Vec<HistoryEventRecord>> {
        if indices.is_empty() {
            return Ok(Vec::new());
        }
        let changes_usage = indices.iter().any(|&idx| {
            matches!(
                events[idx].row_scope,
                Some(HistoryBusinessRowScope::Accounting | HistoryBusinessRowScope::Cost)
            )
        });
        if changes_usage && state.usage_revision != usage_revision {
            return Err(HistoryError::Storage(UsagePreparationChanged.into()));
        }
        let next_usage_revision = state
            .usage_revision
            .checked_add(u64::from(changes_usage))
            .ok_or_else(|| HistoryError::Integrity("usage admission revision exhausted".into()))?;
        let new_head = state
            .head
            .checked_add(indices.len() as u64)
            .filter(|seq| *seq <= i64::MAX as u64)
            .ok_or_else(|| HistoryError::InvalidEvent("history sequence exhausted".into()))?;
        let mut anchors = BTreeSet::new();
        let mut new_event_ids = BTreeSet::new();
        let mut new_bodies = BTreeMap::new();
        for &idx in indices {
            let event = &events[idx];
            if event.is_anchor
                && let Some(row_key) = &event.row_key
                && (!anchors.insert(row_key.as_str()) || known.anchors.contains(row_key))
            {
                return Err(HistoryError::Conflict(format!(
                    "duplicate anchor for row_key {row_key}"
                )));
            }
            for body in &event.bodies {
                if known.bodies.contains_key(&body.body_id)
                    || new_bodies
                        .insert(
                            body.body_id.clone(),
                            (
                                event.event_id.as_str(),
                                body.body_key.as_str(),
                                body.bytes.len() as u64,
                            ),
                        )
                        .is_some()
                {
                    return Err(HistoryError::Conflict(format!(
                        "duplicate body_id {}",
                        body.body_id
                    )));
                }
            }
            new_event_ids.insert(event.event_id.as_str());
        }
        for &idx in indices {
            check_references_in_memory(
                known,
                &state.pending,
                &new_event_ids,
                &new_bodies,
                &events[idx],
                &self.inner.database_id,
            )?;
        }
        let mut accepted_events = Vec::with_capacity(indices.len());
        let mut next_pending = (*state.pending).clone();
        for (position, (&idx, &bytes)) in indices.iter().zip(retained_sizes).enumerate() {
            let bytes = u32::try_from(bytes).map_err(|_| HistoryError::Capacity)?;
            let event_permit = self
                .inner
                .event_permits
                .clone()
                .try_acquire_many_owned(1)
                .map_err(|_| HistoryError::Capacity)?;
            let byte_permit = self
                .inner
                .byte_permits
                .clone()
                .try_acquire_many_owned(bytes)
                .map_err(|_| HistoryError::Capacity)?;
            let mut event = events[idx].clone();
            event.seq = state.head + position as u64 + 1;
            let body_headers = (0..event.bodies.len())
                .map(|ordinal| Body::from_event(&event, ordinal))
                .collect();
            let accepted = Arc::new(Accepted {
                event,
                retained_bytes: bytes as usize,
                body_headers,
                _reservation: Arc::new(Reservation {
                    _events: event_permit,
                    _bytes: byte_permit,
                }),
            });
            next_pending.insert(accepted.clone())?;
            accepted_events.push(accepted);
        }
        // No fallible operation below: publish indices and Pending as one memory transition.
        let mut records = Vec::with_capacity(accepted_events.len());
        for accepted in accepted_events {
            let event = &accepted.event;
            known.events.insert(event.event_id.clone());
            if event.is_anchor
                && let Some(row_key) = &event.row_key
            {
                known.anchors.insert(row_key.clone());
            }
            for body in &event.bodies {
                known.bodies.insert(
                    body.body_id.clone(),
                    KnownBodyMeta {
                        owner: event.event_id.clone(),
                        key: body.body_key.clone(),
                        length: body.bytes.len() as u64,
                    },
                );
            }
            if event.payload_schema == "anywork.accounting/1"
                && let Ok(env) = serde_json::from_str::<
                    super::body::BusinessEnvelope<HistoryAccountingHead>,
                >(&event.payload_json)
            {
                known.latest_accounting = Some(env.head);
            } else if event.payload_schema == "anywork.cost/1"
                && let Some(row_key) = &event.row_key
                && let Ok(env) = serde_json::from_str::<
                    super::body::BusinessEnvelope<HistoryCostHead>,
                >(&event.payload_json)
            {
                known.latest_costs.insert(row_key.clone(), env.head);
            }
            records.push(event.to_record());
        }
        state.pending = Arc::new(next_pending);
        state.head = new_head;
        state.usage_revision = next_usage_revision;
        Ok(records)
    }

    fn notify_admission(&self, records: &[HistoryEventRecord]) {
        if let Some(last) = records.last() {
            self.inner
                .changed
                .send_modify(|head| *head = (*head).max(last.seq));
            self.inner.worker_notify.notify_one();
        }
    }

    pub(super) async fn latest_record(&self, row: &str) -> Result<Option<Record>> {
        let pending = {
            let state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Some(accepted) = state.pending.head(row, state.head) {
                return Ok(Some(Record::from_event(&accepted.event)));
            }
            state.head
        };
        self.inner.read_query_count.fetch_add(1, Ordering::Relaxed);
        db::head(&self.inner.reader, row, pending).await
    }

    pub async fn flush(&self) -> Result<()> {
        if self.inner.read_only {
            return Ok(());
        }
        let _flush_guard = self.inner.flush_lock.lock().await;
        let to_flush: Vec<Arc<Accepted>> = {
            let state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.closing {
                return Err(HistoryError::Closed);
            }
            state.pending.events.values().cloned().collect()
        };
        if to_flush.is_empty() {
            let mut state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.write_error = None;
            return Ok(());
        }

        let flush_result: Result<u64> = async {
            let tx = self
                .inner
                .writer
                .begin_with_options(TransactionOptions {
                    sqlite_transaction_mode: Some(SqliteTransactionMode::Immediate),
                    ..Default::default()
                })
                .await?;
            let committed_head = db::event_head(&tx).await?;
            let mut highest = committed_head;
            for accepted in &to_flush {
                if accepted.event.seq <= committed_head {
                    continue;
                }
                db::insert(&tx, &accepted.event).await?;
                highest = highest.max(accepted.event.seq);
            }
            tx.commit().await?;
            Ok(highest)
        }
        .await;

        match flush_result {
            Ok(committed_seq) => {
                let mut state = self
                    .inner
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                state.write_error = None;
                let pending = Arc::make_mut(&mut state.pending);
                pending.remove_through(committed_seq)?;
                self.inner
                    .durable_head
                    .fetch_max(committed_seq, Ordering::Relaxed);
                Ok(())
            }
            Err(error) => {
                let message = error.to_string();
                let mut state = self
                    .inner
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                state.write_error = Some(message);
                Err(error)
            }
        }
    }

    pub async fn close(&self) -> Result<()> {
        if !self.inner.read_only {
            {
                let mut state = self
                    .inner
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                state.accepting = false;
            }
            self.flush().await?;
        }
        {
            let mut state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.accepting = false;
            state.closing = true;
        }
        self.inner.cancel.cancel();
        self.inner.operations.close();
        self.inner.operations.wait().await;
        let _ = self.inner.reader.clone().close().await;
        if !self.inner.read_only {
            let _ = self.inner.writer.clone().close().await;
        }
        let mut lease = self
            .inner
            .lease
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(lease) = lease.as_mut() {
            lease.release()?;
        }
        lease.take();
        Ok(())
    }
}

impl Drop for Inner {
    fn drop(&mut self) {
        self.cancel.cancel();
    }
}

fn spawn_persist_worker(store: &HistoryStore) {
    if store.inner.read_only {
        return;
    }
    let weak = Arc::downgrade(&store.inner);
    let cancel = store.inner.cancel.clone();
    let notify = store.inner.worker_notify.clone();
    store.inner.operations.spawn(async move {
        let mut backoff = Duration::from_millis(25);
        loop {
            tokio::select! {
                () = cancel.cancelled() => return,
                () = notify.notified() => {}
            }
            loop {
                if cancel.is_cancelled() {
                    return;
                }
                let Some(inner) = weak.upgrade() else {
                    return;
                };
                let worker_store = HistoryStore { inner };
                let result = worker_store.flush().await;
                let has_more = {
                    let state = worker_store
                        .inner
                        .state
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    !state.pending.events.is_empty() && !state.closing
                };
                drop(worker_store);
                match result {
                    Ok(()) => {
                        backoff = Duration::from_millis(25);
                        if !has_more {
                            break;
                        }
                    }
                    Err(HistoryError::Closed) => return,
                    Err(_) => {
                        tokio::select! {
                            () = cancel.cancelled() => return,
                            () = tokio::time::sleep(backoff) => {}
                        }
                        backoff = (backoff * 2).min(Duration::from_millis(500));
                    }
                }
            }
        }
    });
}

fn ensure_same_pending_event(
    pending: &Pending,
    existing: &Record,
    candidate: &HistoryEvent,
) -> Result<()> {
    let mut expected = candidate.to_record();
    expected.seq = existing.record.seq;
    expected.recorded_at = existing.record.recorded_at;
    if existing.record != expected || existing.is_anchor != candidate.is_anchor {
        return Err(HistoryError::Conflict(format!(
            "event_id {} conflicts with existing event",
            candidate.event_id
        )));
    }
    let accepted = pending.event(&existing.record.event_id).ok_or_else(|| {
        HistoryError::Integrity(format!(
            "pending event {} vanished during admission",
            existing.record.event_id
        ))
    })?;
    let existing_bodies: Vec<(String, String, u64, Vec<u8>)> = accepted
        .body_headers
        .iter()
        .map(|b| {
            (
                b.key.clone(),
                b.role.as_str().to_owned(),
                b.length,
                b.digest.clone(),
            )
        })
        .collect();
    let candidate_bodies: Vec<(String, String, u64, Vec<u8>)> = candidate
        .bodies
        .iter()
        .map(|b| {
            (
                b.body_key.clone(),
                b.role.as_str().to_owned(),
                b.bytes.len() as u64,
                b.digest(),
            )
        })
        .collect();
    if existing_bodies != candidate_bodies {
        return Err(HistoryError::Conflict(format!(
            "event_id {} body set conflicts with existing event",
            candidate.event_id
        )));
    }
    Ok(())
}

async fn ensure_same_event(
    db: &impl sea_orm::ConnectionTrait,
    pending: &Pending,
    existing: &Record,
    candidate: &HistoryEvent,
) -> Result<()> {
    let mut expected = candidate.to_record();
    expected.seq = existing.record.seq;
    expected.recorded_at = existing.record.recorded_at;
    if existing.record != expected || existing.is_anchor != candidate.is_anchor {
        return Err(HistoryError::Conflict(format!(
            "event_id {} conflicts with existing event",
            candidate.event_id
        )));
    }
    let existing_bodies: Vec<(String, String, u64, Vec<u8>)> =
        if let Some(accepted) = pending.event(&existing.record.event_id) {
            accepted
                .body_headers
                .iter()
                .map(|b| {
                    (
                        b.key.clone(),
                        b.role.as_str().to_owned(),
                        b.length,
                        b.digest.clone(),
                    )
                })
                .collect()
        } else {
            db::bodies(db, &existing.record.event_id, None, i64::MAX as usize)
                .await?
                .into_iter()
                .map(|b| (b.key, b.role.as_str().to_owned(), b.length, b.digest))
                .collect()
        };
    let candidate_bodies: Vec<(String, String, u64, Vec<u8>)> = candidate
        .bodies
        .iter()
        .map(|b| {
            (
                b.body_key.clone(),
                b.role.as_str().to_owned(),
                b.bytes.len() as u64,
                b.digest(),
            )
        })
        .collect();
    if existing_bodies != candidate_bodies {
        return Err(HistoryError::Conflict(format!(
            "event_id {} body set conflicts with existing event",
            candidate.event_id
        )));
    }
    Ok(())
}

fn check_references_in_memory(
    known: &KnownIndex,
    pending: &Pending,
    batch_events: &BTreeSet<&str>,
    batch_bodies: &BTreeMap<String, (&str, &str, u64)>,
    event: &HistoryEvent,
    database_id: &str,
) -> Result<()> {
    let (event_refs, body_refs) = validate::references(event);
    for event_id in event_refs {
        if !batch_events.contains(event_id.as_str())
            && pending.event(&event_id).is_none()
            && !known.events.contains(&event_id)
        {
            return Err(HistoryError::InvalidEvent(format!(
                "event {} references unknown event {event_id}",
                event.event_id
            )));
        }
    }
    for reference in body_refs {
        if reference.database_id != database_id || reference.byte_start != 0 {
            return Err(HistoryError::InvalidEvent(format!(
                "invalid body reference identity in event {}",
                event.event_id
            )));
        }
        if let Some((owner, key, length)) = batch_bodies.get(&reference.body_id) {
            if *owner != reference.owner_event_id
                || *key != reference.body_key
                || reference
                    .byte_start
                    .checked_add(reference.byte_length)
                    .is_none_or(|end| end > *length)
            {
                return Err(HistoryError::InvalidEvent(format!(
                    "body reference {} conflicts with batch body",
                    reference.body_id
                )));
            }
            continue;
        }
        if let Some((_, header, _)) = pending.body(&reference.body_id) {
            if header.owner != reference.owner_event_id
                || header.key != reference.body_key
                || reference
                    .byte_start
                    .checked_add(reference.byte_length)
                    .is_none_or(|end| end > header.length)
            {
                return Err(HistoryError::InvalidEvent(format!(
                    "body reference {} conflicts with pending body",
                    reference.body_id
                )));
            }
            continue;
        }
        let Some(body) = known.bodies.get(&reference.body_id) else {
            return Err(HistoryError::InvalidEvent(format!(
                "event {} references unknown body {}",
                event.event_id, reference.body_id
            )));
        };
        if body.owner != reference.owner_event_id
            || body.key != reference.body_key
            || reference
                .byte_start
                .checked_add(reference.byte_length)
                .is_none_or(|end| end > body.length)
        {
            return Err(HistoryError::InvalidEvent(format!(
                "body reference {} conflicts with stored body",
                reference.body_id
            )));
        }
    }
    Ok(())
}
