use std::{
    collections::{BTreeMap, BTreeSet},
    fs::File,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

use sea_orm::{
    ConnectionTrait, DatabaseConnection, SqliteTransactionMode, TransactionOptions,
    TransactionTrait,
};
use tokio::sync::{OwnedSemaphorePermit, Semaphore, watch};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use super::{
    db::{self, Body, Record},
    pending::{Accepted, Pending, Reservation},
    *,
};

pub(super) struct State {
    pub pending: Arc<Pending>,
    pub head: u64,
    pub accepting: bool,
    pub closing: bool,
    pub write_error: Option<String>,
}

pub(super) struct Inner {
    pub thread_id: String,
    pub read_only: bool,
    pub database_id: String,
    pub limits: HistoryLimits,
    pub writer: DatabaseConnection,
    pub reader: DatabaseConnection,
    pub state: Mutex<State>,
    pub event_permits: Arc<Semaphore>,
    pub byte_permits: Arc<Semaphore>,
    pub changed: watch::Sender<u64>,
    pub cancel: CancellationToken,
    pub operations: TaskTracker,
    pub(super) admission: tokio::sync::Mutex<()>,
    flush_lock: tokio::sync::Mutex<()>,
    lease: Mutex<Option<File>>,
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

fn writer_lock_path(history_path: &Path) -> PathBuf {
    let mut lock_path = history_path.as_os_str().to_os_string();
    lock_path.push(".writer.lock");
    PathBuf::from(lock_path)
}

fn acquire_writer_lease(history_path: &Path) -> Result<File> {
    let lock_path = writer_lock_path(history_path);
    if let Some(parent) = lock_path.parent()
        && !parent.as_os_str().is_empty()
    {
        std::fs::create_dir_all(parent)?;
    }
    let file = File::options()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(&lock_path)?;
    file.try_lock()
        .map_err(|error| HistoryError::Conflict(format!("history writer lease: {error}")))?;
    Ok(file)
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
                }),
                event_permits: Arc::new(Semaphore::new(limits.pending_events as usize)),
                byte_permits: Arc::new(Semaphore::new(limits.pending_bytes as usize)),
                changed,
                cancel: CancellationToken::new(),
                operations: TaskTracker::new(),
                admission: tokio::sync::Mutex::new(()),
                flush_lock: tokio::sync::Mutex::new(()),
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
        let lease = acquire_writer_lease(path)?;
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
        let reader = match schema::connect(path, true, false).await {
            Ok(reader) => reader,
            Err(error) => {
                let _ = writer.close().await;
                return Err(error);
            }
        };
        let (changed, _) = watch::channel(head);
        Ok(Self {
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
                }),
                event_permits: Arc::new(Semaphore::new(limits.pending_events as usize)),
                byte_permits: Arc::new(Semaphore::new(limits.pending_bytes as usize)),
                changed,
                cancel: CancellationToken::new(),
                operations: TaskTracker::new(),
                admission: tokio::sync::Mutex::new(()),
                flush_lock: tokio::sync::Mutex::new(()),
                lease: Mutex::new(Some(lease)),
            }),
        })
    }

    pub fn database_id(&self) -> &str {
        &self.inner.database_id
    }

    pub fn thread_id(&self) -> &str {
        &self.inner.thread_id
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
        }
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
        let retained_events = max_events.saturating_sub(self.inner.event_permits.available_permits());
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

    pub(crate) async fn admission_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.inner.admission.lock().await
    }

    pub(crate) async fn accept_locked(
        &self,
        _admission: &tokio::sync::MutexGuard<'_, ()>,
        events: &[HistoryEvent],
    ) -> Result<Vec<u64>> {
        if self.inner.read_only {
            return Err(HistoryError::Closed);
        }
        if events.is_empty() {
            return Ok(Vec::new());
        }
        let pending_snapshot = {
            let state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if !state.accepting || state.closing {
                return Err(HistoryError::Closed);
            }
            state.pending.clone()
        };

        let mut seen_event_ids = BTreeSet::new();
        let mut seen_body_ids = BTreeSet::new();
        let mut retained_sizes = Vec::with_capacity(events.len());
        for event in events {
            let bytes = validate::event(event)?;
            if !seen_event_ids.insert(event.event_id.as_str()) {
                return Err(HistoryError::Conflict(format!(
                    "duplicate event_id {} in batch",
                    event.event_id
                )));
            }
            for body in &event.bodies {
                if !seen_body_ids.insert(body.body_id.as_str()) {
                    return Err(HistoryError::Conflict(format!(
                        "duplicate body_id {} in batch",
                        body.body_id
                    )));
                }
            }
            retained_sizes.push(bytes);
        }

        let tx = self.inner.reader.begin().await?;
        let mut assigned = vec![0u64; events.len()];
        let mut new_indices = Vec::new();
        let mut new_event_ids = BTreeSet::new();
        let mut new_bodies: BTreeMap<String, (&str, &str, u64)> = BTreeMap::new();
        let mut batch_anchors = BTreeSet::new();

        for (idx, event) in events.iter().enumerate() {
            let existing = if let Some(accepted) = pending_snapshot.event(&event.event_id) {
                Some(Record::from_event(&accepted.event))
            } else {
                db::event(&tx, &event.event_id).await?
            };

            if let Some(existing) = existing {
                ensure_same_event(&tx, &pending_snapshot, &existing, event).await?;
                assigned[idx] = existing.record.seq;
                continue;
            }

            if event.is_anchor
                && let Some(row_key) = &event.row_key
                && (!batch_anchors.insert(row_key.as_str())
                    || pending_snapshot.anchors.contains_key(row_key)
                    || db::anchor(&tx, row_key).await?.is_some())
            {
                return Err(HistoryError::Conflict(format!(
                    "duplicate anchor for row_key {row_key}"
                )));
            }

            for body in &event.bodies {
                if pending_snapshot.bodies.contains_key(&body.body_id)
                    || db::body(&tx, &body.body_id).await?.is_some()
                {
                    return Err(HistoryError::Conflict(format!(
                        "body_id {} already exists",
                        body.body_id
                    )));
                }
                new_bodies.insert(
                    body.body_id.clone(),
                    (
                        event.event_id.as_str(),
                        body.body_key.as_str(),
                        body.bytes.len() as u64,
                    ),
                );
            }
            new_event_ids.insert(event.event_id.as_str());
            new_indices.push(idx);
        }

        for &idx in &new_indices {
            check_references(
                &tx,
                &pending_snapshot,
                &new_event_ids,
                &new_bodies,
                &events[idx],
                &self.inner.database_id,
            )
            .await?;
        }
        tx.commit().await?;

        if new_indices.is_empty() {
            return Ok(assigned);
        }

        let mut reservations = Vec::with_capacity(new_indices.len());
        for &idx in &new_indices {
            let bytes = u32::try_from(retained_sizes[idx]).map_err(|_| HistoryError::Capacity)?;
            let ev_permit: OwnedSemaphorePermit = self
                .inner
                .event_permits
                .clone()
                .try_acquire_many_owned(1)
                .map_err(|_| HistoryError::Capacity)?;
            let byte_permit: OwnedSemaphorePermit = self
                .inner
                .byte_permits
                .clone()
                .try_acquire_many_owned(bytes)
                .map_err(|_| HistoryError::Capacity)?;
            reservations.push(Arc::new(Reservation {
                _events: ev_permit,
                _bytes: byte_permit,
            }));
        }

        let new_head = {
            let mut state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if !state.accepting || state.closing {
                return Err(HistoryError::Closed);
            }
            let mut next_seq = state.head;
            let mut next_pending = (*state.pending).clone();
            for (idx, reservation) in new_indices.into_iter().zip(reservations) {
                next_seq = next_seq
                    .checked_add(1)
                    .filter(|seq| *seq <= i64::MAX as u64)
                    .ok_or_else(|| {
                        HistoryError::InvalidEvent("history sequence exhausted".into())
                    })?;
                let mut accepted_event = events[idx].clone();
                accepted_event.seq = next_seq;
                let body_headers = (0..accepted_event.bodies.len())
                    .map(|ordinal| Body::from_event(&accepted_event, ordinal))
                    .collect();
                next_pending.insert(Arc::new(Accepted {
                    event: accepted_event,
                    retained_bytes: retained_sizes[idx],
                    body_headers,
                    _reservation: reservation,
                }))?;
                assigned[idx] = next_seq;
            }
            state.pending = Arc::new(next_pending);
            state.head = next_seq;
            state.head
        };
        let _ = self.inner.changed.send(new_head);
        Ok(assigned)
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
        let lease = self
            .inner
            .lease
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        drop(lease);
        Ok(())
    }
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
                .map(|b| (b.key.clone(), b.role.as_str().to_owned(), b.length, b.digest.clone()))
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

async fn check_references(
    tx: &impl sea_orm::ConnectionTrait,
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
            && db::event(tx, &event_id).await?.is_none()
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
        let Some(body) = db::body(tx, &reference.body_id).await? else {
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
